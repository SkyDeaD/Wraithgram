import Foundation
import UIKit
import Display
import TelegramCore
import TelegramPresentationData
import AccountContext
import UndoUI
import WGCore
import WGHooks

/// «Дата регистрации» in the info section of every user's and bot's profile, the own profile too
/// (that is where the ID row is; the Settings tab has no info rows). The value follows `precision` and
/// `source`, the account's age is on the right, a long press copies it; a tap does nothing, like the
/// ID row (owner, build 201: the explanation alert went). Off (`regDate.show`): no row, no work, no request.
enum WGRegDateProfileRow {
    static func register() {
        // After the ID / data center / dates of WGProfileDecor (order 100).
        WGPeerInfoHooks.infoRows.register({ info in
            return WGRegDateProfileRow.rows(info)
        }, order: 110)
    }

    /// Asked on every layout of the profile: memory and snapshots only (WGRegDate).
    private static func rows(_ info: WGPeerInfoContext) -> [WGPeerInfoRow] {
        if !WGRegDateSettings.show.value {
            return []
        }
        // A secret chat's profile describes the user too.
        guard case let .user(user) = info.peer else {
            return []
        }
        let context = info.context
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        guard let row = WGRegDate.shared.row(context: context, peerId: user.id, cachedData: info.cachedData, sourceMessageId: info.sourceMessageId, sourceChatPeerId: info.sourceChatPeerId, controller: info.controller, strings: presentationData.strings) else {
            return []
        }
        let copyText = row.texts.copy
        return [WGPeerInfoRow(id: "regDate.profile", label: WGStrings.RegDate.Profile.label, text: row.texts.value, rightLabel: row.texts.age, longTapAction: { [weak controller = info.controller] in
            WGRegDateProfileRow.copy(copyText, context: context, controller: controller)
        })]
    }

    private static func copy(_ text: String, context: AccountContext, controller: ViewController?) {
        UIPasteboard.general.string = text
        guard let controller else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller.present(UndoOverlayController(presentationData: presentationData, content: .copy(text: WGStrings.RegDate.Profile.copied), elevatedLayout: false, animateInAsReplacement: false, action: { _ in
            return false
        }), in: .current)
    }
}
