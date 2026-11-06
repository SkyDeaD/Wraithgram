import Foundation
import UIKit
import SwiftSignalKit
import Postbox
import Display
import TelegramCore
import TelegramPresentationData
import AccountContext
import ContextUI
import AppBundle
import ChatListUI
import WGCore
import WGHooks
import WGFeaturesShared

/// Where «Пароль на чаты» (and the chats of a locked secret folder) reach into Telegram — through the
/// points, not through eleven edits of the chat screen:
/// - opening a chat (`openChat`) asks first; a peek or a chat screen reached any other way is covered
///   (`lifecycle`) and asks when it appears; reading stops while the cover is up;
/// - the chat list row shows «Чат защищён» instead of the text, no thumbnails, no author line;
/// - the search leaves the chat's messages out (every tab);
/// - pushes, banners, the widget and Siri — `WGChatProtection` in WGFeaturesShared;
/// - the profile's «…» menu protects / unprotects one chat (unprotecting asks first).
enum WGChatLockHandlers {
    static func register() {
        let lock = WGChatLock.shared

        WGChatScreenHooks.openChat.register({ params, proceed in
            return lock.interceptOpen(params, proceed: proceed)
        }, order: -100)
        WGChatScreenHooks.lifecycle.register({ event, screen in
            lock.screenEvent(event, screen: screen)
        })

        // Lists: first, so that no other preview handler shows the text of a protected chat.
        WGChatListHooks.previewText.register({ row in
            guard WGChatLockHandlers.hidesRow(row) else {
                return nil
            }
            let fontSize = row.context.sharedContext.currentPresentationData.with { $0 }.listsFontSize.itemListBaseFontSize
            return NSAttributedString(string: WGStrings.Security.ChatLock.previewText, font: Font.regular(floor(fontSize * 15.0 / 17.0)), textColor: row.theme.chatList.messageTextColor)
        }, order: -1000)
        WGChatListHooks.hidesMediaPreview.register({ row in
            return WGChatLockHandlers.hidesRow(row)
        })
        WGChatListHooks.hidesLastMessageAuthor.register({ row in
            return WGChatLockHandlers.hidesRow(row)
        })
        WGChatListHooks.hidesSearchMessages.register({ context, message in
            return lock.hidesContentInLists(account: context.account.id.wg, peerId: message.id.peerId)
        })
        // Rows of chats whose protection or folder lock changed are laid out again (the set changes
        // rarely: a chat added to / removed from the list, the folder opened / locked).
        WGChatListHooks.accessoryPeers.register({ context in
            return WGChatLockHandlers.relayoutPeers(context: context)
        })

        WGPeerInfoHooks.menuItems.register({ info in
            return WGChatLockHandlers.profileMenuItems(info)
        })
        // A profile opened outside the chat: its shared media stay covered until the check.
        WGProfileMediaLock.register()
    }

    private static func hidesRow(_ row: WGChatListRowContext) -> Bool {
        guard let peer = row.peer else {
            return false
        }
        let lock = WGChatLock.shared
        lock.notePeer(peer)
        return lock.hidesContentInLists(account: row.context.account.id.wg, peerId: peer.id)
    }

    private static func relayoutPeers(context: AccountContext) -> Signal<Set<EnginePeer.Id>, NoError> {
        let account = context.account.id.wg
        return combineLatest(
            WGSecuritySharedSettings.chatLockEnabled.signal,
            WGSecuritySharedSettings.chatLockPeers.signal(for: account),
            WGSecuritySharedSettings.secretFolderPeers.signal(for: account),
            WGSecretFolder.shared.unlockedSignal(account: account)
        )
        |> map { enabled, peers, folderPeers, folderUnlocked -> Set<EnginePeer.Id> in
            var result = Set<EnginePeer.Id>()
            if enabled {
                for key in peers {
                    result.insert(PeerId(wgKey: key))
                }
            }
            if !folderUnlocked {
                for key in folderPeers {
                    result.insert(PeerId(wgKey: key))
                }
            }
            return result
        }
        |> distinctUntilChanged
    }

    // MARK: Profile menu

    private static func profileMenuItems(_ info: WGPeerInfoContext) -> [ContextMenuItem] {
        guard !info.isSettings, WGSecuritySharedSettings.chatLockEnabled.value, !WGSecuritySharedSettings.chatLockAllChats.value else {
            return []
        }
        let peerId = info.chatPeer?.id ?? info.peer.id
        if peerId == info.context.account.peerId || !WGChatProtection.isLockable(peerId) {
            return []
        }
        let context = info.context
        let account = context.account.id.wg
        let key = peerId.wgKey
        let isProtected = WGSecuritySharedSettings.chatLockPeers.value(for: account).contains(key)
        let title = isProtected ? WGStrings.Security.ChatLock.unprotectChat : WGStrings.Security.ChatLock.protectChat
        return [.action(ContextMenuActionItem(text: title, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Lock"), color: theme.contextMenu.primaryColor)
        }, action: { _, f in
            f(.default)
            let apply: () -> Void = {
                var peers = WGSecuritySharedSettings.chatLockPeers.value(for: account)
                if isProtected {
                    peers.remove(key)
                } else {
                    peers.insert(key)
                }
                WGSecuritySharedSettings.chatLockPeers.set(peers, for: account)
            }
            if isProtected {
                // Taking a chat out of the protection is what an intruder would do: ask first.
                WGLocalAuthGate.shared.authenticate(context: context, reason: WGStrings.Security.Auth.reasonSettings, completion: { granted in
                    if granted {
                        apply()
                    }
                })
            } else {
                apply()
            }
        }))]
    }
}
