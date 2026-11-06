import Foundation
import WGCore

/// App-side settings of «Безопасность» (WGSecurity reads them; the extensions do not). Declared here,
/// next to the shared ones, so that the old client's keys can be moved in one place before the other
/// zones' migrations run (W2-3 consumes `MiscSettings.isEnabled`).
///
/// Scope rule (fixes the old «конфиги для аккаунтов» trap): every policy is global and says so in its
/// footer; what names a chat or a folder of an account is per account.
public enum WGSecuritySettings {
    // MARK: Chat lock

    /// «Автоблокировка»: one unlock opens every protected chat of the account until the app has been
    /// in the background for `chatLockAutolockTimeout`. Off: a chat is unlocked for as long as it
    /// stays open and asks again next time.
    public static let chatLockAutolock = WGSetting<Bool>("security.chatLock.autolock", default: false)
    /// Seconds in the background before the lock comes back: "0", "15", "30", "60", "300".
    /// "0" also closes an open protected chat when the app goes to the background.
    public static let chatLockAutolockTimeout = WGSetting<String>("security.chatLock.autolockTimeout", default: "0")

    // MARK: Secret folder

    /// The account's secret folder (`ChatListFilter.id`); 0 = none. Folder ids are per account.
    public static let secretFolderId = WGAccountSetting<Int32>("security.secretFolder.id", default: 0)
    /// «Защищать чаты папки»: while the folder is locked its chats are protected everywhere else too.
    public static let secretFolderProtectChats = WGAccountSetting<Bool>("security.secretFolder.protectChats", default: false)

    // MARK: Accounts

    /// «Face ID при смене аккаунта» — one key for every way of switching.
    public static let accountSwitchAuth = WGSetting<Bool>("security.accountSwitchAuth", default: false)
    /// The next account's avatar in the «Чаты» header: tap — switch, long press — the accounts menu.
    public static let accountsHeaderButton = WGSetting<Bool>("security.accounts.headerButton", default: false)

    // MARK: Screenshots

    /// «Скрывать чат на скриншотах»: the chat's header, input and panels come out empty.
    public static let screenshotPrivacy = WGSetting<Bool>("security.screenshotPrivacy", default: false)
    /// The same for the whole chat list.
    public static let screenshotPrivacyChatList = WGSetting<Bool>("security.screenshotPrivacyChatList", default: false)

    // MARK: Passcode

    /// Lock on every cold start (when a passcode is set), whatever the auto-lock timeout says.
    public static let passcodeLockOnLaunch = WGSetting<Bool>("security.passcode.lockOnLaunch", default: false)
    /// More auto-lock values in Telegram's passcode screen.
    public static let passcodeMoreAutolockOptions = WGSetting<Bool>("security.passcode.moreAutolockOptions", default: false)
    /// Whether a Telegram passcode is set, as last seen by the app (AppLock's init asks before any
    /// signal has delivered). Cache, not exported.
    public static let passcodeIsSet = WGSetting<Bool>("security.passcode.isSet", default: false, flags: [.noExport])

    static func declare() {
        let _ = WGSecuritySettings.chatLockAutolock
        let _ = WGSecuritySettings.chatLockAutolockTimeout
        let _ = WGSecuritySettings.secretFolderId
        let _ = WGSecuritySettings.secretFolderProtectChats
        let _ = WGSecuritySettings.accountSwitchAuth
        let _ = WGSecuritySettings.accountsHeaderButton
        let _ = WGSecuritySettings.screenshotPrivacy
        let _ = WGSecuritySettings.screenshotPrivacyChatList
        let _ = WGSecuritySettings.passcodeLockOnLaunch
        let _ = WGSecuritySettings.passcodeMoreAutolockOptions
        let _ = WGSecuritySettings.passcodeIsSet
    }

    /// The timeout as seconds.
    public static var chatLockAutolockSeconds: Double {
        return Double(WGSecuritySettings.chatLockAutolockTimeout.value) ?? 0.0
    }
}
