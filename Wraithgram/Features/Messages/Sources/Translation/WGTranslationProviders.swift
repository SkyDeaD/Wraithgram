import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import WGCore
import WGHooks
import WGFeaturesShared

/// Answers Telegram's translation requests with the chosen service. Telegram (the default) answers
/// nil: upstream does the request. Google is used only after the user accepted the notice
/// (`WGMessagesPolicy.translationService`); system translation only on iOS 18+.
enum WGTranslationProviders {
    static func register() {
        WGTranslationHooks.translateTexts.register({ request in
            let service = WGMessagesPolicy.translationService
            if service == .telegram {
                return nil
            }
            return WGTranslationEngine.translate(request.texts, toLang: request.toLang, service: service)
        })
        WGTranslationHooks.translateMessages.register({ request in
            let service = WGMessagesPolicy.translationService
            if service == .telegram {
                return nil
            }
            return WGTranslationProviders.translateMessages(request, service: service)
        })
    }

    /// Like upstream: translates the stored messages and keeps the result in
    /// `TranslationMessageAttribute` (text, poll options and solution, voice transcription), through
    /// `WGStoredMessagesTranslation` (WGFeaturesShared), which the chat translation without Premium
    /// shares. Rich messages (an InstantPage body) are left to Telegram: `wgTranslateMessages`
    /// (WGHooks) sends them to Telegram's translation next to this one.
    static func translateMessages(_ request: WGMessagesTranslationRequest, service: WGTranslationServiceKind) -> Signal<Void, TranslationError> {
        let toLang = request.toLang
        return WGStoredMessagesTranslation.translate(postbox: request.account.postbox, messageIds: request.messageIds, toLang: toLang, translateTexts: { texts in
            return WGTranslationEngine.translate(texts, toLang: toLang, service: service)
        })
    }
}
