import Foundation
import UIKit
import Display
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ContextUI
import AppBundle
import TextFormat
import TranslateUI
import WGCore
import WGHooks
import WGFeaturesShared

/// SG-E3, the language of outgoing messages per chat, in the long-press menu of the Send button:
/// «Перевести на <язык>» translates the text in the composer without sending it; «Язык перевода
/// для этого чата» picks the language (popular ones first) and remembers it for the chat — the same
/// value «Переводить перед отправкой» uses, so there is one store, not two.
///
/// The items reach the menu through `WGChatScreenHooks.sendMenuItems`
/// (ChatSendMessageContextScreen shows them as `additionalItems`).
enum WGOutgoingLanguageMenu {
    static func register() {
        // A chat's translation shows without Premium (always since W6-SGD, as in Swiftgram).
        WGChatScreenHooks.translatesChatsWithoutPremium.register({
            return WGMessagesPolicy.translatesChatsWithoutPremium
        })
        WGChatScreenHooks.sendMenuItems.register({ menu in
            return WGOutgoingLanguageMenu.items(context: menu.context, peerId: menu.peerId, predictedLanguage: menu.predictedLanguage, inputText: menu.inputText, replaceInput: menu.replaceInput, dismiss: menu.dismiss, present: menu.present)
        })
    }

    static func items(context: AccountContext, peerId: PeerId, predictedLanguage: String?, inputText: NSAttributedString, replaceInput: @escaping (NSAttributedString) -> Void, dismiss: @escaping () -> Void, present: @escaping (ViewController) -> Void) -> [ContextMenuItem] {
        if peerId.namespace == Namespaces.Peer.SecretChat {
            return []
        }
        let text = inputText.string
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }
        let language = WGMessagesPolicy.outgoingLanguage(accountId: context.account.id, peerId: peerId) ?? predictedLanguage
        var items: [ContextMenuItem] = []
        if let language {
            items.append(.action(ContextMenuActionItem(text: WGStrings.Translation.Send.translateTo(language: WGTranslationMenu.languageName(language)), icon: { theme in
                return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Translate"), color: theme.contextMenu.primaryColor)
            }, action: { _, _ in
                dismiss()
                WGOutgoingLanguageMenu.translateInput(context: context, inputText: inputText, toLang: language, replaceInput: replaceInput)
            })))
        }
        items.append(.action(ContextMenuActionItem(text: language == nil ? WGStrings.Translation.Send.chooseLanguage : WGStrings.Translation.Send.chatLanguage, icon: { theme in
            return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Globe"), color: theme.contextMenu.primaryColor)
        }, action: { _, _ in
            dismiss()
            WGOutgoingLanguageMenu.chooseLanguage(context: context, peerId: peerId, present: present, completion: { code in
                WGOutgoingLanguageMenu.translateInput(context: context, inputText: inputText, toLang: code, replaceInput: replaceInput)
            })
        })))
        return items
    }

    static func translateInput(context: AccountContext, inputText: NSAttributedString, toLang: String, replaceInput: @escaping (NSAttributedString) -> Void) {
        let entities = WGTranslateBeforeSending.protectedEntities(inputText)
        let _ = (context.engine.messages.translate(text: inputText.string, toLang: toLang, entities: entities)
        |> deliverOnMainQueue).start(next: { result in
            if let result, !result.0.isEmpty {
                replaceInput(chatInputStateStringWithAppliedEntities(result.0, entities: result.1))
            }
        })
    }

    static func chooseLanguage(context: AccountContext, peerId: PeerId, present: @escaping (ViewController) -> Void, completion: @escaping (String) -> Void) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = [ActionSheetTextItem(title: WGStrings.Translation.Language.title, parseMarkdown: false)]
        var seen = Set<String>()
        for code in popularTranslationLanguages where seen.insert(code).inserted {
            items.append(ActionSheetButtonItem(title: WGTranslationMenu.languageName(code), color: .accent, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                WGMessagesPolicy.setOutgoingLanguage(code, accountId: context.account.id, peerId: peerId)
                completion(code)
            }))
        }
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        present(actionSheet)
    }
}

/// SG-E2, the translate button next to a message in another language: the decision is here
/// (registered in WGInputAndGestures); the bubble draws the button and opens Telegram's translation.
enum WGQuickTranslateButton {
    /// The language to translate from when the button should be shown; nil = no button.
    static func sourceLanguage(message: Message, context: AccountContext) -> String? {
        guard WGMessagesSettings.quickTranslateButton.value else {
            return nil
        }
        if message.id.peerId.namespace == Namespaces.Peer.SecretChat || message.text.count < 4 {
            return nil
        }
        if message.isCopyProtected() {
            return nil
        }
        guard let language = WGSystemTranslate.detectLanguage(message.text) else {
            return nil
        }
        var interfaceLanguage = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
        if interfaceLanguage.hasSuffix("-raw") {
            interfaceLanguage = String(interfaceLanguage.dropLast(4))
        }
        if normalizeTranslationLanguage(language) == normalizeTranslationLanguage(interfaceLanguage) {
            return nil
        }
        if !supportedTranslationLanguages.contains(normalizeTranslationLanguage(language)) {
            return nil
        }
        return language
    }
}
