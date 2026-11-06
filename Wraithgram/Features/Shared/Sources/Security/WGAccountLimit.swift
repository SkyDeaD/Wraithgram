import Foundation
import WGCore
import TelegramCore

/// How many accounts can be signed in at once — the one place that says it. Owner decision
/// 2026-10-22: 100, the same in every place that checks it, with and without Premium, no toggle.
/// Upstream: 3, or 4 with Premium. Every check asks `WGLimitHooks.accountLimit` (see
/// WGHooks/HOOKS.md), so code that needs the limit reads `WGLimitHooks.maximumNumberOfAccounts`
/// (with the point empty it answers upstream's) rather than this constant.
public enum WGAccountLimit {
    public static let maximumNumberOfAccounts: Int = 100

    /// From `WGSecurityShared.register()`. App only: the extensions never add accounts.
    static func register() {
        guard WGCore.environment?.process.isApp ?? false else {
            return
        }
        WGLimitHooks.accountLimit.register({ _ in
            return WGAccountLimit.maximumNumberOfAccounts
        })
    }
}
