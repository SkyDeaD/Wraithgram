import Foundation
import TelegramCore
import WGCore
import WGFeaturesShared

/// The «Чаты» section. Most of it is read directly by upstream forks through `WGMessagesPolicy`
/// (greeting sticker, channel button, pull to the next channel / topic, «Send as»); here are the
/// parts that go through hook points. «Безлимитные закрепы» — `WGPinnedChats`.
enum WGChatsHandlers {
    /// «История поиска без лимита» keeps up to this many recent chats (upstream: 20). Every entry is
    /// observed when the search opens, so the list is long but never unbounded.
    static let recentSearchCeiling = 200

    static func register() {
        WGLimitHooks.recentSearchLimit.register({ limit in
            if WGMessagesSettings.unlimitedSearchHistory.value {
                return max(limit, WGChatsHandlers.recentSearchCeiling)
            }
            return nil
        })
    }
}
