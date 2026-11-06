import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import LocalizedPeerData
import AccountContext
import ContextUI
import AppBundle
import UndoUI
import WGCore
import WGHooks
import WGFeaturesShared

/// Toast at the bottom of the current screen.
func wgGhostToast(context: AccountContext, text: String) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    context.sharedContext.mainWindow?.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in
        return false
    }), on: .root)
}

private func wgGhostMenuIcon(_ name: String) -> (PresentationTheme) -> UIImage? {
    return { theme in
        return generateTintedImage(image: UIImage(bundleImageName: name), color: theme.contextMenu.primaryColor)
    }
}

/// «Прочитать» in the menus of messages, stories and media, and the ghost-mode items of a profile's
/// «…» menu («Исключения», «Подглядеть онлайн»).
enum WGGhostMenuItems {
    static func register() {
        WGMessageMenuHooks.items.register({ menuContext in
            return WGGhostMenuItems.messageItems(menuContext)
        }, order: 100)
        WGStoryHooks.menuItems.register({ menuContext in
            return WGGhostMenuItems.storyItems(menuContext)
        }, order: 100)
        WGGalleryHooks.menuItems.register({ menuContext in
            return WGGhostMenuItems.galleryItems(menuContext)
        }, order: 100)
        WGPeerInfoHooks.menuItems.register({ peerInfoContext in
            return WGGhostMenuItems.profileItems(peerInfoContext)
        }, order: 100)
    }

    // MARK: Message

    private static func messageItems(_ menuContext: WGMessageMenuContext) -> [WGMessageMenuEntry] {
        let context = menuContext.context
        let account = context.account.id.wg
        guard let message = menuContext.messages.max(by: { $0.id.id < $1.id.id }), message.flags.contains(.Incoming) else {
            return []
        }
        let peerId = message.id.peerId
        if peerId.namespace == Namespaces.Peer.SecretChat {
            if message.id.namespace != Namespaces.Message.SecretIncoming {
                return []
            }
        } else if message.id.namespace != Namespaces.Message.Cloud {
            return []
        }
        if !WGGhostPolicy.hides(.readReceipts, peerId: peerId, account: account) {
            return []
        }
        let threadId = menuContext.chatLocation.threadId
        let key = peerId.wgGhostReadKey(threadId: threadId)
        // Known to be read on the server already: nothing to send (no flag threaded through the menu's data).
        if peerId.namespace != Namespaces.Peer.SecretChat, let serverMax = WGGhostReadLedger.shared.serverReadMaxId(account: account, key: key), message.id.id <= serverMax {
            return []
        }
        let item = ContextMenuItem.action(ContextMenuActionItem(text: WGStrings.GhostMode.Action.read, icon: wgGhostMenuIcon("Chat/Context Menu/Read"), action: { _, f in
            f(.default)
            let _ = (WGGhostMenuItems.read(context: context, message: message, threadId: threadId)
            |> deliverOnMainQueue).start(next: { success in
                wgGhostToast(context: context, text: success ? WGStrings.GhostMode.Action.readDone : WGStrings.GhostMode.Action.failed)
            })
        }))
        return [WGMessageMenuEntry(position: .top, item: item)]
    }

    /// Reads the chat on the server up to the message (and the message's "listened" mark), then on the
    /// device. The push the local read schedules finds the server ahead and sends nothing.
    static func read(context: AccountContext, message: Message, threadId: Int64?) -> Signal<Bool, NoError> {
        let account = context.account
        let peerId = message.id.peerId
        var contents: Signal<Bool, NoError> = .single(true)
        if message.attributes.contains(where: { $0 is ConsumableContentMessageAttribute }) {
            contents = WGGhostExplicitReads.readContents(account: account, peerId: peerId, messageIds: [message.id.id])
        }
        return WGGhostExplicitReads.readHistory(account: account, peerId: peerId, threadId: threadId, maxId: message.id.id, maxTimestamp: message.timestamp)
        |> mapToSignal { success -> Signal<Bool, NoError> in
            if !success {
                return .single(false)
            }
            let local: Signal<Never, NoError>
            if threadId == nil {
                local = context.engine.messages.applyMaxReadIndexInteractively(index: message.index) |> ignoreValues
            } else {
                local = .complete()
            }
            return local
            |> mapToSignal { _ -> Signal<Bool, NoError> in
            }
            |> then(contents)
        }
    }

    // MARK: Story

    private static func storyItems(_ menuContext: WGStoryMenuContext) -> [ContextMenuItem] {
        let context = menuContext.context
        let account = context.account.id.wg
        let peerId = menuContext.peer.id
        if peerId == context.account.peerId || !WGGhostPolicy.hides(.storyViews, peerId: peerId, account: account) {
            return []
        }
        let storyId = menuContext.storyItem.id
        let isExpired = menuContext.storyItem.expirationTimestamp <= Int32(Date().timeIntervalSince1970)
        return [.action(ContextMenuActionItem(text: WGStrings.GhostMode.Action.readStory, icon: wgGhostMenuIcon("Chat/Context Menu/Eye"), action: { _, f in
            f(.default)
            let _ = (WGGhostExplicitReads.readStory(account: context.account, peerId: peerId, storyId: storyId, isExpired: isExpired)
            |> deliverOnMainQueue).start(next: { success in
                wgGhostToast(context: context, text: success ? WGStrings.GhostMode.Action.readStoryDone : WGStrings.GhostMode.Action.failed)
            })
        }))]
    }

    // MARK: Gallery (self-destructing media)

    private static func galleryItems(_ menuContext: WGGalleryMenuContext) -> [ContextMenuItem] {
        let context = menuContext.context
        let account = context.account.id.wg
        guard let message = menuContext.message, message.flags.contains(.Incoming), message.wgRawContainsSecretMedia else { // raw: kept media opens in the regular gallery (WGRestrictionHooks.secretMediaDisplay)
            return []
        }
        let peerId = message.id.peerId
        // Secret chats report "opened" through their own layer, which an explicit read here can
        // not reach; ghost mode keeps that report on the device (`.messageContents`).
        if peerId.namespace == Namespaces.Peer.SecretChat || message.id.namespace != Namespaces.Message.Cloud {
            return []
        }
        if !WGGhostPolicy.hides(.readReceipts, peerId: peerId, account: account) {
            return []
        }
        let messageId = message.id
        return [.action(ContextMenuActionItem(text: WGStrings.GhostMode.Action.readMedia, icon: wgGhostMenuIcon("Chat/Context Menu/Eye"), action: { _, f in
            f(.default)
            let _ = (WGGhostExplicitReads.readContents(account: context.account, peerId: peerId, messageIds: [messageId.id])
            |> deliverOnMainQueue).start(next: { success in
                wgGhostToast(context: context, text: success ? WGStrings.GhostMode.Action.readMediaDone : WGStrings.GhostMode.Action.failed)
            })
        }))]
    }

    // MARK: Profile

    private static func profileItems(_ peerInfoContext: WGPeerInfoContext) -> [ContextMenuItem] {
        if peerInfoContext.isSettings {
            return []
        }
        let context = peerInfoContext.context
        let account = context.account.id.wg
        let peer = peerInfoContext.peer
        if peer.id == context.account.peerId {
            return []
        }
        WGGhostPeerTraits.shared.learn(peer, account: account)
        var items: [ContextMenuItem] = []

        let explicit = WGGhostPolicy.explicitException(for: peer.id, account: account)
        let source = WGGhostPolicy.exceptionSource(for: peer.id, account: account)
        if WGGhostPolicy.isEnabled(account) || explicit != nil {
            let key = peer.id.wgGhostKey
            let navigationController = peerInfoContext.controller?.navigationController as? NavigationController
            switch source {
            case .explicit:
                items.append(.action(ContextMenuActionItem(text: WGStrings.GhostMode.Profile.editException, icon: wgGhostMenuIcon("Chat/Context Menu/Settings"), action: { _, f in
                    f(.default)
                    navigationController?.pushViewController(wgGhostExceptionController(context: context, peerId: peer.id))
                })))
                items.append(.action(ContextMenuActionItem(text: WGStrings.GhostMode.Profile.removeException, textColor: .destructive, icon: { theme in
                    return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Delete"), color: theme.contextMenu.destructiveColor)
                }, action: { _, f in
                    f(.default)
                    wgGhostUpdateExceptions(account: account) { exceptions in
                        exceptions.removeValue(forKey: key)
                    }
                    wgGhostToast(context: context, text: WGStrings.GhostMode.Profile.removed)
                })))
            case .type, .folder:
                // Excepted through its type or a folder: «Убрать» pulls this one chat back into ghost mode.
                items.append(.action(ContextMenuActionItem(text: WGStrings.GhostMode.Profile.removeException, icon: wgGhostMenuIcon("Chat/Context Menu/EyeLocked"), action: { _, f in
                    f(.default)
                    wgGhostUpdateExceptions(account: account) { exceptions in
                        exceptions[key] = .forcedGhost
                    }
                    wgGhostToast(context: context, text: WGStrings.GhostMode.Profile.forced)
                })))
            case .forced:
                items.append(.action(ContextMenuActionItem(text: WGStrings.GhostMode.Profile.restoreException, icon: wgGhostMenuIcon("Chat/Context Menu/Eye"), action: { _, f in
                    f(.default)
                    wgGhostUpdateExceptions(account: account) { exceptions in
                        exceptions.removeValue(forKey: key)
                    }
                    wgGhostToast(context: context, text: WGStrings.GhostMode.Profile.added)
                })))
            case .none:
                items.append(.action(ContextMenuActionItem(text: WGStrings.GhostMode.Profile.addException, icon: wgGhostMenuIcon("Chat/Context Menu/Eye"), action: { _, f in
                    f(.default)
                    wgGhostUpdateExceptions(account: account) { exceptions in
                        exceptions[key] = WGGhostException()
                    }
                    wgGhostToast(context: context, text: WGStrings.GhostMode.Profile.added)
                })))
            }
        }

        if case let .user(user) = peer, user.botInfo == nil, !user.flags.contains(.isSupport), !user.isDeleted {
            items.append(.action(ContextMenuActionItem(text: WGStrings.GhostMode.Profile.peek, icon: wgGhostMenuIcon("Chat/Context Menu/Eye"), action: { _, f in
                f(.default)
                let _ = (WGGhostPeekOnline.peek(context: context, peerId: user.id)
                |> deliverOnMainQueue).start(next: { result in
                    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                    let name = EnginePeer.user(user).compactDisplayTitle
                    switch result {
                    case let .presence(presence):
                        if let presence = presence {
                            let (status, _) = stringAndActivityForUserPresence(strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat, presence: presence, relativeTo: Int32(Date().timeIntervalSince1970))
                            wgGhostToast(context: context, text: WGStrings.GhostMode.Profile.peekResult(name: name, status: status))
                        } else {
                            wgGhostToast(context: context, text: WGStrings.GhostMode.Profile.peekHidden(name: name))
                        }
                    case .failed:
                        wgGhostToast(context: context, text: WGStrings.GhostMode.Action.failed)
                    }
                })
            })))
        }
        return items
    }
}
