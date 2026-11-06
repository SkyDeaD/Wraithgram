// Compiled into TopMessageReactions (filegroup //Wraithgram/Features/Interface:TopMessageReactionsPointSources).
// Owner: W2-5 («Свои недавние реакции»).

import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import WGCore

public enum WGRecentReactionsHooks {
    /// Transformer of the "top" reactions a message's reaction panel starts with (Telegram's
    /// cloud list). Called once per panel: return signals, keep resolved files cached.
    public static let topReactions = WGHookPoint<(Signal<[RecentReactionItem], NoError>, AccountContext, EngineRawMessage) -> Signal<[RecentReactionItem], NoError>>("reactions.top")
}

func wgTopReactions(_ signal: Signal<[RecentReactionItem], NoError>, context: AccountContext, message: EngineRawMessage) -> Signal<[RecentReactionItem], NoError> {
    if WGRecentReactionsHooks.topReactions.isEmpty {
        return signal
    }
    var result = signal
    for handler in WGRecentReactionsHooks.topReactions.handlers {
        result = handler(result, context, message)
    }
    return result
}
