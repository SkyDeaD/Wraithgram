import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ChatListUI
import WGCore
import WGHooks
import WGFeaturesShared

/// Entry point of the WGSecurity feature module. Owner: W3-4.
///
/// Settings, migrations and what the extensions need are in WGFeaturesShared
/// (`Sources/Security/`, registered before this module); here — the app: the common check
/// (`WGLocalAuthGate`), the chat lock, the secret folder, the account switch check and the account
/// button, screenshots, the passcode extras and the «Безопасность» menu.
public enum WGSecurityModule {
    private static var listRefreshDisposable: Disposable?

    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `WGFeatures.registerAll()`, before `WGHookRegistry.freeze()`.
    public static func register() {
        WGSecurityMenu.register()
        WGChatLockHandlers.register()
        WGScreenshotPrivacy.register()
        WGPasscodeExtras.register()
        WGAccountSwitchGuard.shared.register()
        WGAccountHeaderButton.register()

        WGChatListHooks.folders.register({ signal, context in
            return WGSecretFolder.shared.folders(signal, context: context)
        })

        WGLifecycleHooks.rootControllersDidLoad.register({ context, _ in
            WGAuthEnvironment.shared.start(sharedContext: context.sharedContext)
            WGAccountSwitchGuard.shared.start(context: context)
            WGAccountsList.shared.start(context: context)
            WGSecretFolder.shared.startMembership(context: context)
            WGSecurityModule.observeListPolicies()
        })
        WGLifecycleHooks.applicationDidEnterBackground.register({
            // The folder first: the chat lock covers the folder's open chats by its state.
            WGSecretFolder.shared.lockAll()
            WGChatLock.shared.applicationDidEnterBackground()
        })
        WGLifecycleHooks.applicationDidBecomeActive.register({
            WGAuthEnvironment.shared.refreshDevice()
            WGChatLock.shared.applicationDidBecomeActive()
        })
    }

    /// «Пароль на чаты» and «Защищать все чаты» change what every chat list row shows; the rows of
    /// single chats are laid out again by `WGChatListHooks.accessoryPeers`, the whole lists — by one
    /// re-emission of the PresentationData (only on these two switches, never on a timer).
    private static func observeListPolicies() {
        if WGSecurityModule.listRefreshDisposable != nil {
            return
        }
        var isFirst = true
        WGSecurityModule.listRefreshDisposable = (combineLatest(WGSecuritySharedSettings.chatLockEnabled.signal, WGSecuritySharedSettings.chatLockAllChats.signal)
        |> deliverOnMainQueue).start(next: { _, _ in
            if isFirst {
                isFirst = false
                return
            }
            WGThemeHooks.invalidate()
        })
    }
}
