import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import AccountContext
import ContextUI
import AppBundle
import ChatInterfaceState
import PeerInfoUI
import WGCore
import WGHooks
import WGFeaturesShared

/// Items WGExtras adds to the «…» menu of a group's or channel's profile (WGPeerInfoHooks.menuItems):
/// «Недавние действия» for admins, «Администраторы» for every member of a group, «Показать закреп».
enum WGExtrasProfileMenu {
    static func register() {
        WGPeerInfoHooks.menuItems.register({ info in
            return WGExtrasProfileMenu.items(info)
        })
    }

    private static func items(_ info: WGPeerInfoContext) -> [ContextMenuItem] {
        if info.isSettings {
            return []
        }
        let chatPeer = info.chatPeer ?? info.peer
        var items: [ContextMenuItem] = []
        if case let .channel(channel) = chatPeer {
            let isAdmin = channel.adminRights != nil || channel.flags.contains(.isCreator)
            if WGExtrasSettings.recentActionsShortcut.value && isAdmin {
                items.append(WGExtrasProfileMenu.recentActionsItem(info, peer: chatPeer))
            }
            if WGExtrasSettings.administratorsMenuItem.value, case .group = channel.info {
                items.append(WGExtrasProfileMenu.administratorsItem(info, peerId: chatPeer.id))
            }
        }
        if WGExtrasSettings.hiddenPinnedMenuItem.value && chatPeer.id != info.context.account.peerId {
            items.append(WGExtrasProfileMenu.hiddenPinnedItem(info, peer: chatPeer))
        }
        return items
    }

    private static func recentActionsItem(_ info: WGPeerInfoContext, peer: EnginePeer) -> ContextMenuItem {
        let context = info.context
        let controller = info.controller
        return .action(ContextMenuActionItem(text: WGStrings.Extras.Profile.recentActions, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Calendar"), color: theme.contextMenu.primaryColor)
        }, action: { [weak controller] _, f in
            f(.dismissWithoutContent)
            controller?.push(context.sharedContext.makeChatRecentActionsController(context: context, peer: peer, adminPeerId: nil, starsState: nil))
        }))
    }

    private static func administratorsItem(_ info: WGPeerInfoContext, peerId: EnginePeer.Id) -> ContextMenuItem {
        let context = info.context
        let controller = info.controller
        return .action(ContextMenuActionItem(text: WGStrings.Extras.Profile.administrators, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Groups"), color: theme.contextMenu.primaryColor)
        }, action: { [weak controller] _, f in
            f(.dismissWithoutContent)
            controller?.push(channelAdminsController(context: context, peerId: peerId))
        }))
    }

    /// Clears the chat's «closed pinned message» (stored state, and the open chat when it appears)
    /// and goes to the chat, where the pinned bar is back.
    private static func hiddenPinnedItem(_ info: WGPeerInfoContext, peer: EnginePeer) -> ContextMenuItem {
        let context = info.context
        let controller = info.controller
        return .action(ContextMenuActionItem(text: WGStrings.Extras.Profile.showPinned, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/PinnedList"), color: theme.contextMenu.primaryColor)
        }, action: { [weak controller] _, f in
            f(.dismissWithoutContent)
            WGExtrasPinnedRequests.request(peerId: peer.id)
            let navigationController = controller?.navigationController as? NavigationController
            let _ = (ChatInterfaceState.update(engine: context.engine, peerId: peer.id, threadId: nil, { state in
                return state.withUpdatedMessageActionsState({ value in
                    var value = value
                    value.closedPinnedMessageId = nil
                    return value
                })
            })
            |> deliverOnMainQueue).start(completed: {
                guard let navigationController else {
                    return
                }
                context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer)))
            })
        }))
    }
}
