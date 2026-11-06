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
import PromptUI
import Pasteboard
import WGCore
import WGHooks
import WGFeaturesShared

/// Items of the message context menu (`WGMessageMenuHooks`): «История правок», «Изменить локально»
/// / «Сбросить», «Закладка» / «Убрать закладку», «Удалить у себя» for kept deleted messages, and
/// «Копировать» that copies the local edit when there is one. All strings are localized, prompts
/// are Telegram's own alert with a text field.
enum WGAntiDeleteMessageMenu {
    private static func icon(_ name: String) -> (PresentationTheme) -> UIImage? {
        return { theme in
            return generateTintedImage(image: UIImage(bundleImageName: name), color: theme.contextMenu.primaryColor)
        }
    }

    static func rootNavigationController(_ context: AccountContext) -> NavigationController? {
        return context.sharedContext.mainWindow?.viewController as? NavigationController
    }

    static func present(_ controller: ViewController, context: AccountContext) {
        context.sharedContext.mainWindow?.present(controller, on: .root)
    }

    /// The message a single-message action applies to: the long-pressed one, or the album item with text.
    private static func primaryMessage(_ messages: [Message]) -> Message? {
        if messages.count == 1 {
            return messages[0]
        }
        return messages.first(where: { !$0.text.isEmpty }) ?? messages.first
    }

    static func items(_ menu: WGMessageMenuContext) -> [WGMessageMenuEntry] {
        guard let message = WGAntiDeleteMessageMenu.primaryMessage(menu.messages) else {
            return []
        }
        let context = menu.context
        let state = WGAntiDeleteMessageState(attributes: message.attributes)
        var result: [WGMessageMenuEntry] = []

        if state.deleted != nil {
            WGAntiDeleteReplyQuote.remember(message, context: context)
        }

        if let history = state.history {
            result.append(WGMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(text: WGStrings.AntiDelete.MessageMenu.history(count: history.versions.count), icon: WGAntiDeleteMessageMenu.icon("Chat/Context Menu/Time"), action: { _, f in
                f(.dismissWithoutContent)
                WGAntiDeleteMessageMenu.rootNavigationController(context)?.pushViewController(wgMakeEditVersionsController(context: context, messageId: message.id))
            }))))
        }

        if WGAntiDeleteSettings.localEdit.value && (!message.text.isEmpty || state.localEdit != nil) {
            result.append(WGMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(text: WGStrings.AntiDelete.MessageMenu.localEdit, icon: WGAntiDeleteMessageMenu.icon("Chat/Context Menu/Pencil"), action: { _, f in
                f(.dismissWithoutContent)
                WGAntiDeleteMessageMenu.promptLocalEdit(context: context, message: message)
            }))))
        }
        if state.localEdit != nil {
            result.append(WGMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(text: WGStrings.AntiDelete.MessageMenu.resetLocalEdit, icon: WGAntiDeleteMessageMenu.icon("Chat/Context Menu/Reload"), action: { _, f in
                f(.dismissWithoutContent)
                let _ = WGAntiDeleteOperations.setLocalEdit(postbox: context.account.postbox, messageId: message.id, text: nil, entities: []).start()
            }))))
        }

        if WGBookmarkSettings.enabled.value {
            if state.bookmark != nil {
                result.append(WGMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(text: WGStrings.Bookmarks.MessageMenu.remove, icon: WGAntiDeleteMessageMenu.icon("Chat/Context Menu/TagRemove"), action: { _, f in
                    f(.dismissWithoutContent)
                    WGAntiDeleteMessageMenu.setBookmark(context: context, messageId: message.id, title: nil)
                }))))
            } else {
                result.append(WGMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(text: WGStrings.Bookmarks.MessageMenu.add, icon: WGAntiDeleteMessageMenu.icon("Chat/Context Menu/Tag"), action: { _, f in
                    f(.dismissWithoutContent)
                    WGAntiDeleteMessageMenu.promptBookmark(context: context, message: message)
                }))))
            }
        }

        let keptIds = menu.messages.filter { $0.wgIsDeleted }.map(\.id)
        if !keptIds.isEmpty {
            result.append(WGMessageMenuEntry(position: .bottom, item: .action(ContextMenuActionItem(text: WGStrings.AntiDelete.MessageMenu.deleteForMe, textColor: .destructive, icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Delete"), color: theme.contextMenu.destructiveColor)
            }, action: { _, f in
                f(.dismissWithoutContent)
                let _ = WGAntiDeleteOperations.deleteKept(postbox: context.account.postbox, accountId: context.account.id, messageIds: keptIds).start()
            }))))
        }
        return result
    }

    /// «Копировать» copies what the bubble shows: the local edit when there is one.
    static func filter(_ items: [ContextMenuItem], _ menu: WGMessageMenuContext) -> [ContextMenuItem] {
        guard menu.messages.count == 1, let localEdit = WGAntiDeleteMessageState(attributes: menu.messages[0].attributes).localEdit else {
            return items
        }
        let copyTitle = menu.presentationData.strings.Conversation_ContextMenuCopy
        return items.map { item -> ContextMenuItem in
            guard case let .action(action) = item, action.text == copyTitle else {
                return item
            }
            return .action(ContextMenuActionItem(text: action.text, icon: action.icon, action: { _, f in
                storeMessageTextInPasteboard(localEdit.text, entities: localEdit.entities)
                f(.default)
            }))
        }
    }

    private static func promptLocalEdit(context: AccountContext, message: Message) {
        let current = message.wgEffectiveText.text
        let controller = promptController(context: context, text: WGStrings.AntiDelete.MessageMenu.localEditTitle, subtitle: WGStrings.AntiDelete.MessageMenu.localEditText, value: current, placeholder: WGStrings.AntiDelete.MessageMenu.localEditPlaceholder, characterLimit: 4096, apply: { value in
            guard let value else {
                return
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || value == message.text {
                // Empty or back to the original: the local edit goes away.
                let _ = WGAntiDeleteOperations.setLocalEdit(postbox: context.account.postbox, messageId: message.id, text: nil, entities: []).start()
                return
            }
            if value == current {
                return
            }
            let _ = WGAntiDeleteOperations.setLocalEdit(postbox: context.account.postbox, messageId: message.id, text: value, entities: []).start()
        })
        WGAntiDeleteMessageMenu.present(controller, context: context)
    }

    private static func promptBookmark(context: AccountContext, message: Message) {
        var suggested = message.wgEffectiveText.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if suggested.count > 32 {
            suggested = String(suggested.prefix(32))
        }
        if suggested.isEmpty {
            suggested = WGStrings.Bookmarks.MessageMenu.defaultTitle
        }
        let controller = promptController(context: context, text: WGStrings.Bookmarks.MessageMenu.titlePrompt, subtitle: WGStrings.Bookmarks.MessageMenu.titlePromptText, value: suggested, placeholder: WGStrings.Bookmarks.MessageMenu.titlePlaceholder, characterLimit: 64, apply: { value in
            guard let value else {
                return
            }
            var title = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty {
                title = WGStrings.Bookmarks.MessageMenu.defaultTitle
            }
            WGAntiDeleteMessageMenu.setBookmark(context: context, messageId: message.id, title: title)
        })
        WGAntiDeleteMessageMenu.present(controller, context: context)
    }

    static func setBookmark(context: AccountContext, messageId: MessageId, title: String?) {
        let _ = (WGAntiDeleteOperations.setBookmark(postbox: context.account.postbox, accountId: context.account.id, messageId: messageId, title: title)
        |> deliverOnMainQueue).start(completed: {
            // The bubble redraws with the message update; the search row and lists follow the index.
            WGMessageDecorationHooks.redraw(messageIds: [messageId])
        })
    }
}
