import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import PresentationDataUtils
import TranslateUI
import WGCore
import WGHooks
import WGSettingsUI
import WGFeaturesShared

/// The service choice of the «Перевод» tab. Google is a third-party service: before it is used the
/// user sees what is sent where and confirms; declining keeps Telegram. A Google choice migrated
/// from the old client asks once at launch (nothing goes to Google until then).
enum WGTranslationMenu {
    static func register() {
        WGLifecycleHooks.rootControllersDidLoad.register({ context, _ in
            WGTranslationMenu.askMigratedConsentIfNeeded(context: context)
        })
    }

    static func serviceTitle(_ kind: WGTranslationServiceKind) -> String {
        switch kind {
        case .telegram:
            return WGStrings.Translation.Menu.serviceTelegram
        case .google:
            return WGStrings.Translation.Menu.serviceGoogle
        case .system:
            return WGStrings.Translation.Menu.serviceSystem
        }
    }

    static func chooseService(menuContext: WGMenuContext) {
        let context = menuContext.context
        wgPresentActionSheet(context: context, title: WGStrings.Translation.Menu.service, actions: [
            (WGTranslationMenu.serviceTitle(.telegram), false, {
                WGMessagesSettings.translationService.set(WGTranslationServiceKind.telegram.rawValue)
            }),
            (WGTranslationMenu.serviceTitle(.google), false, {
                WGTranslationMenu.confirmGoogle(context: context, present: { menuContext.present($0) })
            }),
            (WGTranslationMenu.serviceTitle(.system), false, {
                if #available(iOS 18.0, *) {
                    WGMessagesSettings.translationService.set(WGTranslationServiceKind.system.rawValue)
                } else {
                    menuContext.presentToast(WGStrings.Translation.systemUnavailable)
                }
            })
        ], present: { menuContext.present($0) })
    }

    static func confirmGoogle(context: AccountContext, present: @escaping (ViewController) -> Void) {
        if WGMessagesSettings.translationThirdPartyAccepted.value {
            WGMessagesSettings.translationService.set(WGTranslationServiceKind.google.rawValue)
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        present(textAlertController(context: context, title: WGStrings.Translation.Consent.title, text: WGStrings.Translation.Consent.text, actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .defaultAction, title: WGStrings.Translation.Consent.accept, action: {
                WGMessagesSettings.translationThirdPartyAccepted.set(true)
                WGMessagesSettings.translationService.set(WGTranslationServiceKind.google.rawValue)
            })
        ]))
    }

    private static var askedMigratedConsent = false

    private static func askMigratedConsentIfNeeded(context: AccountContext) {
        if WGTranslationMenu.askedMigratedConsent {
            return
        }
        WGTranslationMenu.askedMigratedConsent = true
        guard WGMessagesSettings.translationService.value == WGTranslationServiceKind.google.rawValue, !WGMessagesSettings.translationThirdPartyAccepted.value else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let alert = textAlertController(context: context, title: WGStrings.Translation.Consent.title, text: WGStrings.Translation.Consent.text, actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {
                WGMessagesSettings.translationService.set(WGTranslationServiceKind.telegram.rawValue)
            }),
            TextAlertAction(type: .defaultAction, title: WGStrings.Translation.Consent.accept, action: {
                WGMessagesSettings.translationThirdPartyAccepted.set(true)
            })
        ])
        context.sharedContext.mainWindow?.present(alert, on: .root)
    }

    /// Languages for «Язык отправки»: popular first, then every supported one, named in the
    /// language of the interface.
    static func languageOptions() -> [WGMenuChoiceOption] {
        var codes: [String] = []
        var seen = Set<String>()
        for code in popularTranslationLanguages + supportedTranslationLanguages where seen.insert(code).inserted {
            codes.append(code)
        }
        return codes.map { code in
            return WGMenuChoiceOption(value: code, title: {
                return WGTranslationMenu.languageName(code)
            })
        }
    }

    static func languageName(_ code: String) -> String {
        let locale = Locale(identifier: WGLocalization.shared.languageCode)
        let name = locale.localizedString(forLanguageCode: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}
