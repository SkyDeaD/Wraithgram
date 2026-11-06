// Compiled into TelegramCore (filegroup //Wraithgram/WGHooks:TelegramCoreHookSources).
// How many accounts can be signed in at once. It is a client-side UI limit only (the server does
// not count the accounts of a device), and upstream spells it in several places: the constants of
// AccountUtils (settings search, the delete-account options), literal 3 / 4 in the three
// "Add account" actions (Settings, logout options, delete-account options) and the Premium limit
// screen. Every one of them asks here, so a feature sets the limit once.
// Callers only need `import TelegramCore`.

import Foundation
import WGCore

extension WGLimitHooks {
    /// Upstream limits: AccountUtils' `maximumNumberOfAccounts` and `maximumPremiumNumberOfAccounts`.
    public static let upstreamAccountLimit: Int = 3
    public static let upstreamPremiumAccountLimit: Int = 4

    /// Policy: how many accounts can be signed in at once. The handler gets the upstream value
    /// (3, or 4 when one of the signed-in accounts has Premium) and returns the limit, or nil to
    /// keep it. The first non-nil answer wins; the point only raises the limit. Asked on the main
    /// thread and in signal maps: answer from memory.
    public static let accountLimit = WGHookPoint<(Int) -> Int?>("limits.accounts")

    /// The limit for an upstream value; `upstream` itself while the point is empty.
    public static func maximumNumberOfAccounts(upstream: Int) -> Int {
        if WGLimitHooks.accountLimit.isEmpty {
            return upstream
        }
        for handler in WGLimitHooks.accountLimit.handlers {
            if let value = handler(upstream) {
                return max(upstream, value)
            }
        }
        return upstream
    }

    /// The limit without / with Premium among the signed-in accounts.
    public static func maximumNumberOfAccounts(isPremium: Bool) -> Int {
        return WGLimitHooks.maximumNumberOfAccounts(upstream: isPremium ? WGLimitHooks.upstreamPremiumAccountLimit : WGLimitHooks.upstreamAccountLimit)
    }

    /// `false` once a feature made the limit the same with and without Premium: then the Premium
    /// offer for accounts and Telegram's "three / four accounts" texts are wrong and are replaced.
    public static var premiumRaisesAccountLimit: Bool {
        return WGLimitHooks.maximumNumberOfAccounts(isPremium: true) > WGLimitHooks.maximumNumberOfAccounts(isPremium: false)
    }
}
