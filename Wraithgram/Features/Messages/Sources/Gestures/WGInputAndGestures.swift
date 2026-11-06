import Foundation
import UIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext
import ChatMessageItemCommon
import WGCore
import WGHooks
import WGFeaturesShared

/// Input field and gestures:
/// - SG-F8 «Отправка по Return» — `WGInputPanelHooks.sendOnReturn` (chat and attachment composers);
/// - SG-G6 «Скрыть кнопку записи» — `WGInputPanelHooks.hidesRecordButton`;
/// - SG-G7 «Без эффекта удаления» — `WGChatScreenHooks.deleteEffect`;
/// - SG-G2 double tap on an own message → edit (`WGMessageGestureHooks.tap`), SG-G10 no
///   picture-in-picture swipe (`WGGalleryHooks.swipeToPictureInPicture`);
/// - SG-E2 the quick translate button beside a bubble (`WGMessageDecorationHooks.translateButtonLanguage`).
enum WGInputAndGestures {
    static func register() {
        WGInputPanelHooks.sendOnReturn.register({ request in
            if WGMessagesSettings.sendOnReturn.value {
                // Shift+Return still makes a new line on hardware keyboards.
                return !request.modifierFlags.contains(.shift)
            }
            return nil
        })
        WGInputPanelHooks.hidesRecordButton.register({ _ in
            return WGMessagesSettings.hideRecordButton.value
        })
        WGChatScreenHooks.deleteEffect.register({ _ in
            return WGMessagesSettings.disableDeleteEffect.value ? false : nil
        })
        WGMessageGestureHooks.tap.register({ request in
            guard request.tapCount == 2, let action = WGInputAndGestures.doubleTapAction(message: request.message, context: request.context) else {
                return false
            }
            switch action {
            case .edit:
                return request.startEditing()
            }
        })
        WGGalleryHooks.swipeToPictureInPicture.register({ context in
            return WGInputAndGestures.allowsSwipeToPictureInPicture(context: context)
        })
        WGMessageDecorationHooks.translateButtonLanguage.register({ message, context in
            return WGQuickTranslateButton.sourceLanguage(message: message, context: context)
        })
    }

    enum DoubleTapAction {
        case edit
    }

    /// SG-G2: what a double tap on `message` does instead of the quick reaction; nil = upstream.
    static func doubleTapAction(message: Message, context: AccountContext) -> DoubleTapAction? {
        guard WGMessagesSettings.doubleTapToEdit.value else {
            return nil
        }
        if message.effectivelyIncoming(context.account.peerId) {
            return nil
        }
        if message.id.namespace != Namespaces.Message.Cloud {
            return nil
        }
        if message.text.isEmpty && !message.media.contains(where: { $0 is TelegramMediaImage || $0 is TelegramMediaFile }) {
            return nil
        }
        // The rule behind Telegram's own «Edit» (time limit, forwards, stickers, round videos, rights
        // in channels and gigagroups): what cannot be edited keeps the double-tap reaction.
        let limits = EngineConfiguration.Limits(context.currentLimitsConfiguration.with { $0 })
        if !canEditMessage(accountPeerId: context.account.peerId, limitsConfiguration: limits, message: message) {
            return nil
        }
        return .edit
    }

    /// SG-G10: false = a vertical swipe on a gallery video dismisses it instead of starting
    /// picture-in-picture; nil = upstream.
    static func allowsSwipeToPictureInPicture(context: AccountContext) -> Bool? {
        return WGMessagesSettings.disableVideoPipSwipe.value ? false : nil
    }
}
