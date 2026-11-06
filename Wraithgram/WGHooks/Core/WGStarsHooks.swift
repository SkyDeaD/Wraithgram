// Compiled into TelegramCore (filegroup //Wraithgram/WGHooks:TelegramCoreHookSources).
// The account's Stars balance as features show it («Локальные звёзды»: a number shown on this
// device only). TON balances are never touched.

import Foundation
import SwiftSignalKit
import WGCore

public enum WGStarsHooks {
    /// Policy: the Stars balance shown instead of the real one (first non-nil wins; nil = the real
    /// one). Asked on the main queue on every publish of a Stars balance (`StarsContext`) and on
    /// every read of its `currentState`: answer from memory.
    public static let displayedBalance = WGHookPoint<(StarsAmount) -> StarsAmount?>("stars.displayedBalance")

    /// Every live Stars balance publishes its state again through `displayedBalance` — call after
    /// the shown balance changed. Any thread.
    public static func invalidate() {
        wgStarsBalanceInvalidations.putNext(Void())
    }
}

private let wgStarsBalanceInvalidations = ValuePipe<Void>()

/// WRAITH hook target: `StarsContextImpl` (publish) and `StarsContext.currentState` — the state as
/// features show it. A TON state passes as it is.
func wgDisplayedStarsState(_ state: StarsContext.State, ton: Bool) -> StarsContext.State {
    if ton || WGStarsHooks.displayedBalance.isEmpty {
        return state
    }
    for handler in WGStarsHooks.displayedBalance.handlers {
        if let balance = handler(state.balance) {
            var state = state
            state.balance = balance
            return state
        }
    }
    return state
}

/// WRAITH hook target: `StarsContextImpl.init`. `republish` runs on the main queue after
/// `WGStarsHooks.invalidate()`. Nil — nothing subscribed — for TON and while no feature changes
/// the shown balance.
func wgObserveStarsBalanceInvalidation(ton: Bool, _ republish: @escaping () -> Void) -> Disposable? {
    if ton || WGStarsHooks.displayedBalance.isEmpty {
        return nil
    }
    return wgStarsBalanceInvalidations.signal().start(next: { _ in
        Queue.mainQueue().async {
            republish()
        }
    })
}
