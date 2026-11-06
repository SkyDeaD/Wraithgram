import Foundation
import UIKit
import ObjectiveC
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import AccountContext
import UndoUI
import WGCore
import WGHooks
import WGAppearanceSettings

/// Profile appearance (profile_ui_toggles, SG-C1/C2/C4):
/// - ID, data center, dates of creation / joining and «mutual contact» as info rows — all from the
///   peer record on the device, no network, texts from Wraithgram's own strings;
/// - the own animated header background (gif_wallpapers);
/// - no star-rating («level») badge (`WGPeerInfoHooks.hidesItem(.starRating)`, WGAppearancePendingPoints:
///   the header then keeps no room for it).
enum WGProfileDecor {
    static func register() {
        WGPeerInfoHooks.infoRows.register({ context in
            return WGProfileDecor.rows(context)
        }, order: 100)

        WGPeerInfoHooks.headerDidLayout.register({ header in
            WGProfileHeaderDecor.update(header)
        }, order: 100)
    }

    // MARK: Info rows

    private static func rows(_ info: WGPeerInfoContext) -> [WGPeerInfoRow] {
        let showId = WGAppearanceSettings.profileShowId.value
        let showDataCenter = WGAppearanceSettings.profileShowDataCenter.value
        let showDates = WGAppearanceSettings.profileShowDates.value
        if !showId && !showDataCenter && !showDates {
            return []
        }
        let context = info.context
        let peer = info.peer
        let strings = context.sharedContext.currentPresentationData.with { $0 }.strings
        var result: [WGPeerInfoRow] = []

        if showId {
            let idText = WGProfileDecor.idText(peer)
            result.append(WGPeerInfoRow(id: "appearance.profile.id", label: WGStrings.Appearance.Profile.idLabel, text: idText, longTapAction: { [weak controller = info.controller] in
                WGProfileDecor.copy(idText, context: context, controller: controller)
            }))
        }

        if showDataCenter, let resource = peer.smallProfileImage?.resource as? CloudPeerPhotoSizeMediaResource {
            let text = WGStrings.Appearance.Profile.dataCenterValue(number: "\(resource.datacenterId)")
            result.append(WGPeerInfoRow(id: "appearance.profile.dataCenter", label: WGStrings.Appearance.Profile.dataCenterLabel, text: text, longTapAction: { [weak controller = info.controller] in
                WGProfileDecor.copy(text, context: context, controller: controller)
            }))
        }

        if showDates {
            switch peer {
            case let .channel(channel):
                // `date` of a channel is the day the account joined it, or its creation date for
                // somebody who is not a member (Telegram API).
                let label: String
                if case .member = channel.participationStatus {
                    label = WGStrings.Appearance.Profile.joinedLabel
                } else if case .broadcast = channel.info {
                    label = WGStrings.Appearance.Profile.channelCreatedLabel
                } else {
                    label = WGStrings.Appearance.Profile.groupCreatedLabel
                }
                if channel.creationDate > 0 {
                    let text = stringForDate(timestamp: channel.creationDate, strings: strings)
                    result.append(WGPeerInfoRow(id: "appearance.profile.date", label: label, text: text, longTapAction: { [weak controller = info.controller] in
                        WGProfileDecor.copy(text, context: context, controller: controller)
                    }))
                }
            case let .legacyGroup(group):
                if group.creationDate > 0 {
                    let text = stringForDate(timestamp: group.creationDate, strings: strings)
                    result.append(WGPeerInfoRow(id: "appearance.profile.date", label: WGStrings.Appearance.Profile.groupCreatedLabel, text: text, longTapAction: { [weak controller = info.controller] in
                        WGProfileDecor.copy(text, context: context, controller: controller)
                    }))
                }
            case let .user(user):
                if user.flags.contains(.mutualContact) && user.id != context.account.peerId {
                    result.append(WGPeerInfoRow(id: "appearance.profile.mutual", label: WGStrings.Appearance.Profile.mutualContactLabel, text: WGStrings.Appearance.Profile.mutualContactValue))
                }
                // A member's profile opened from a group: when they joined it.
                if let groupId = info.sourceChatPeerId, let joined = WGMemberJoinDates.shared.joinDate(context: context, groupId: groupId, memberId: user.id, controller: info.controller) {
                    let text = stringForDate(timestamp: joined.date, strings: strings)
                    result.append(WGPeerInfoRow(id: "appearance.profile.joinedGroup", label: WGStrings.Appearance.Profile.memberJoinedLabel(chat: joined.groupTitle), text: text, longTapAction: { [weak controller = info.controller] in
                        WGProfileDecor.copy(text, context: context, controller: controller)
                    }))
                }
            case .secretChat, .community:
                break
            }
        }
        return result
    }

    /// The ID as bots and the Bot API see it: users as is, groups negative, channels with -100.
    private static func idText(_ peer: EnginePeer) -> String {
        let id = peer.id.id._internalGetInt64Value()
        switch peer {
        case .user, .secretChat:
            return "\(id)"
        case .legacyGroup:
            return "-\(id)"
        case .channel:
            return "-100\(id)"
        case .community:
            return "\(id)"
        }
    }

    private static func copy(_ text: String, context: AccountContext, controller: ViewController?) {
        UIPasteboard.general.string = text
        guard let controller else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(presentationData: presentationData, content: .copy(text: WGStrings.Appearance.Profile.copied), elevatedLayout: false, animateInAsReplacement: false, action: { _ in
            return false
        }), in: .current)
    }
}

/// When a member joined a group (SG-C4, «Дата вступления»), for the profile opened from that group.
/// Only from data on the device, as the row's description promises: a basic group's cached
/// participant list carries the date. A supergroup keeps no participant list on the device, and
/// asking the server (`channels.getParticipant`) would tell it whose profile was opened from which
/// group — so a supergroup member gets no row. The rows are built synchronously from what is known;
/// an unknown date is read once, then the profile is laid out again (`requestLayout`) and reads the
/// answer here. Main thread; answers live for the session.
final class WGMemberJoinDates {
    struct Joined {
        let date: Int32
        let groupTitle: String
    }

    private enum State {
        case loading
        case known(Joined?)
    }

    static let shared = WGMemberJoinDates()

    private var states: [String: State] = [:]

    private init() {
    }

    func joinDate(context: AccountContext, groupId: EnginePeer.Id, memberId: EnginePeer.Id, controller: ViewController?) -> Joined? {
        assert(Thread.isMainThread)
        // Basic groups only: see the type's comment (no network).
        guard groupId.namespace == Namespaces.Peer.CloudGroup else {
            return nil
        }
        let key = "\(context.account.id.wg.rawValue):\(groupId.wgKey.stringValue):\(memberId.wgKey.stringValue)"
        if let state = self.states[key] {
            switch state {
            case let .known(joined):
                return joined
            case .loading:
                return nil
            }
        }
        self.states[key] = .loading

        let title: Signal<String, NoError> = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: groupId))
        |> map { peer -> String in
            guard let peer else {
                return ""
            }
            switch peer {
            case let .channel(channel):
                return channel.title
            case let .legacyGroup(group):
                return group.title
            default:
                return ""
            }
        }
        // The group's cached participants (Postbox), never the network.
        let date: Signal<Int32?, NoError> = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.LegacyGroupParticipants(id: groupId))
        |> map { participants -> Int32? in
            guard case let .known(list) = participants else {
                return nil
            }
            for participant in list where participant.peerId == memberId {
                switch participant {
                case let .member(_, _, invitedAt, _), let .admin(_, _, invitedAt, _):
                    return invitedAt
                case .creator:
                    return nil
                }
            }
            return nil
        }
        let _ = (combineLatest(date |> take(1), title)
        |> deliverOnMainQueue).start(next: { [weak controller] date, title in
            var joined: Joined?
            if let date, date > 0 {
                joined = Joined(date: date, groupTitle: title)
            }
            self.states[key] = .known(joined)
            if joined != nil {
                controller?.requestLayout(transition: .immediate)
            }
        })
        return nil
    }
}

/// The own profile header: the animated background behind the avatar. Attached once per header node;
/// the per-layout work is a frame update.
///
/// The background banner comes with the header layout (`WGPeerInfoHeader.backgroundContainerView`);
/// the first subview of the header is only the fallback. It is kept weakly.
private final class WGProfileHeaderDecor {
    private static var key: UInt8 = 0

    private weak var node: ASDisplayNode?
    private var videoView: WGLoopingVideoView?
    private weak var bannerView: UIView?
    private var disposable: Disposable?
    private var lastWidth: CGFloat = 0.0

    private init(node: ASDisplayNode) {
        self.node = node
        self.disposable = (WGProfileBackgroundSettings.signal
        |> deliverOnMainQueue).start(next: { [weak self] _ in
            self?.applyBackground()
        })
    }

    deinit {
        self.disposable?.dispose()
    }

    static func update(_ header: WGPeerInfoHeader) {
        let isOwn = header.isSettings || header.peer?.id == header.context.account.peerId
        if !isOwn {
            return
        }
        let decor: WGProfileHeaderDecor
        if let current = objc_getAssociatedObject(header.node, &WGProfileHeaderDecor.key) as? WGProfileHeaderDecor {
            decor = current
        } else {
            decor = WGProfileHeaderDecor(node: header.node)
            objc_setAssociatedObject(header.node, &WGProfileHeaderDecor.key, decor, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        decor.lastWidth = header.width
        if let bannerView = header.backgroundContainerView {
            decor.bannerView = bannerView
        }
        decor.applyBackground()
    }

    private func applyBackground() {
        guard let node = self.node else {
            return
        }
        let settings = WGProfileBackgroundSettings.current()
        guard settings.enabled, let url = WGAnimatedBackgrounds.fileURL(.profile) else {
            if let videoView = self.videoView {
                self.videoView = nil
                videoView.setVideo(url: nil, version: 0)
                videoView.removeFromSuperview()
            }
            return
        }
        // The header's background banner (cover, emoji pattern); the video goes right above it,
        // under the avatar, the name and the buttons.
        guard let banner = self.bannerView ?? node.view.subviews.first(where: { !($0 is WGLoopingVideoView) }) else {
            return
        }
        let videoView: WGLoopingVideoView
        if let current = self.videoView {
            videoView = current
        } else {
            videoView = WGLoopingVideoView(frame: CGRect())
            self.videoView = videoView
        }
        if videoView.superview !== node.view {
            node.view.insertSubview(videoView, aboveSubview: banner)
        }
        let bannerBottom = banner.frame.maxY
        videoView.frame = CGRect(x: 0.0, y: 0.0, width: max(self.lastWidth, banner.frame.width), height: max(0.0, bannerBottom))
        videoView.alpha = CGFloat(settings.opacity)
        videoView.setVideo(url: url, version: settings.version)
    }
}

struct WGProfileBackgroundSettings: Equatable {
    var enabled: Bool
    var opacity: Double
    var version: Int

    static func current() -> WGProfileBackgroundSettings {
        return WGProfileBackgroundSettings(enabled: WGAppearanceSettings.profileBackground.value, opacity: wgClampPercent(WGAppearanceSettings.profileBackgroundOpacity.value), version: WGAppearanceSettings.profileBackgroundVersion.value)
    }

    static var signal: Signal<WGProfileBackgroundSettings, NoError> {
        return WGSettingsStore.shared.revision
        |> map { _ -> WGProfileBackgroundSettings in
            return WGProfileBackgroundSettings.current()
        }
        |> distinctUntilChanged
    }
}
