import Foundation
import UIKit
import Display
import AppBundle
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ContextUI
import ChatListUI
import WGCore
import WGHooks
import WGFeaturesShared

/// The profile's «…» menu (`WGPeerInfoHooks.menuItems`): «Удалённые сообщения», «Изменённые
/// сообщения», «Закладки», and excluding this chat from anti-delete. The counts come from the
/// account's summaries in memory, the namespace from the index (secret chats included).
enum WGAntiDeletePeerMenu {
    private static func icon(_ name: String) -> (PresentationTheme) -> UIImage? {
        return { theme in
            return generateTintedImage(image: UIImage(bundleImageName: name), color: theme.contextMenu.primaryColor)
        }
    }

    static func items(_ peerInfo: WGPeerInfoContext) -> [ContextMenuItem] {
        if peerInfo.isSettings {
            return []
        }
        let context = peerInfo.context
        let chatPeerId = (peerInfo.chatPeer ?? peerInfo.peer).id
        let accountId = context.account.id
        var result: [ContextMenuItem] = []

        let push: (ViewController) -> Void = { [weak controller = peerInfo.controller] screen in
            if let navigationController = controller?.navigationController as? NavigationController {
                navigationController.pushViewController(screen)
            } else {
                WGAntiDeleteMessageMenu.rootNavigationController(context)?.pushViewController(screen)
            }
        }

        let deletedCount = WGAntiDeleteAccounts.shared.count(account: accountId, kind: .deleted, peerId: chatPeerId)
        if deletedCount > 0 {
            result.append(.action(ContextMenuActionItem(text: WGStrings.AntiDelete.PeerMenu.deleted(count: deletedCount), icon: WGAntiDeletePeerMenu.icon("Chat/Context Menu/Delete"), action: { _, f in
                f(.dismissWithoutContent)
                push(wgMakeAntiDeleteChatHistoryController(context: context, kind: .deleted, peerId: chatPeerId))
            })))
        }
        let editedCount = WGAntiDeleteAccounts.shared.count(account: accountId, kind: .edited, peerId: chatPeerId)
        if editedCount > 0 {
            result.append(.action(ContextMenuActionItem(text: WGStrings.AntiDelete.PeerMenu.edited(count: editedCount), icon: WGAntiDeletePeerMenu.icon("Chat/Context Menu/Edit"), action: { _, f in
                f(.dismissWithoutContent)
                push(wgMakeAntiDeleteChatHistoryController(context: context, kind: .edited, peerId: chatPeerId))
            })))
        }
        if WGBookmarkSettings.enabled.value && WGAntiDeleteAccounts.shared.hasBookmarks(account: accountId, peerId: chatPeerId) {
            result.append(.action(ContextMenuActionItem(text: WGStrings.Bookmarks.PeerMenu.title, icon: WGAntiDeletePeerMenu.icon("Chat/Context Menu/ReadingList"), action: { _, f in
                f(.dismissWithoutContent)
                push(wgMakeBookmarksController(context: context, peerId: chatPeerId))
            })))
        }

        let capturing = WGAntiDeleteSettings.enabled.value || WGAntiDeleteSettings.keepOwn.value || WGAntiDeleteSettings.keepSelfDestructing.value || WGAntiDeleteSettings.editHistory.value
        if capturing && chatPeerId != context.account.peerId {
            let key = chatPeerId.wgKey
            let excluded = WGAntiDeleteSettings.excludedPeers.value(for: accountId.wg).contains(key)
            result.append(.action(ContextMenuActionItem(text: excluded ? WGStrings.AntiDelete.PeerMenu.include : WGStrings.AntiDelete.PeerMenu.exclude, icon: WGAntiDeletePeerMenu.icon("Chat/Context Menu/Ban"), action: { _, f in
                f(.dismissWithoutContent)
                var peers = WGAntiDeleteSettings.excludedPeers.value(for: accountId.wg)
                if peers.contains(key) {
                    peers.remove(key)
                } else {
                    peers.insert(key)
                }
                WGAntiDeleteSettings.excludedPeers.set(peers, for: accountId.wg)
            })))
        }
        return result
    }
}

/// `WGChatListHooks.previewText`: the row shows the local edit of the last message, like the bubble.
enum WGAntiDeleteChatList {
    static func previewText(_ row: WGChatListRowContext) -> NSAttributedString? {
        guard let message = row.messages.first?._asMessage() else {
            return nil
        }
        var localEdit: WGLocalEditMessageAttribute?
        for attribute in message.attributes {
            if let attribute = attribute as? WGLocalEditMessageAttribute, attribute.isActive {
                localEdit = attribute
            }
        }
        guard let localEdit else {
            return nil
        }
        let presentationData = row.context.sharedContext.currentPresentationData.with { $0 }
        let font = Font.regular(floor(presentationData.listsFontSize.itemListBaseFontSize * 15.0 / 17.0))
        return NSAttributedString(string: localEdit.text.replacingOccurrences(of: "\n", with: " "), font: font, textColor: row.theme.chatList.messageTextColor)
    }
}
