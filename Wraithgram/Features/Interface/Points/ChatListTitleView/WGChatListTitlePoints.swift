// Compiled into ChatListTitleView (filegroup //Wraithgram/Features/Interface:ChatListTitleViewPointSources).
// Owner: W2-5. The lowest module of the chat list chrome W2-5 owns, so the points here serve the
// title (connection text), the header component and the chat list search
// (ChatListUI, ChatListHeaderComponent and StoryPeerListComponent all depend on this module).

import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore
import AccountContext
import WGCore

/// How the chat list title looks. `.upstream` = Telegram's.
public struct WGChatListTitleStyle: Equatable {
    /// While connecting / updating only the spinner is shown, no «Соединение…» text.
    public var hidesConnectionText: Bool

    public init(hidesConnectionText: Bool) {
        self.hidesConnectionText = hidesConnectionText
    }

    public static let upstream = WGChatListTitleStyle(hidesConnectionText: false)
}

public enum WGChatListTitleHooks {
    /// Provider of the title style (first registered wins). Main thread, on title updates and layout.
    public static let style = WGHookPoint<() -> WGChatListTitleStyle>("chatListTitle.style")
}

public func wgChatListTitleStyle() -> WGChatListTitleStyle {
    if WGChatListTitleHooks.style.isEmpty {
        return .upstream
    }
    return WGChatListTitleHooks.style.handlers[0]()
}

/// The text the title shows for a network status.
public func wgChatListTitleText(_ title: NetworkStatusTitle) -> String {
    if WGChatListTitleHooks.style.isEmpty {
        return title.text
    }
    if title.activity && wgChatListTitleStyle().hidesConnectionText {
        return ""
    }
    return title.text
}

public enum WGChatListSearchHooks {
    /// Transformer of the local peers the chat list search shows for a query (search by numeric
    /// id). Called once per query, off the main thread is fine: return signals, do not block.
    public static let localPeers = WGHookPoint<(Signal<[EngineRenderedPeer], NoError>, String, AccountContext) -> Signal<[EngineRenderedPeer], NoError>>("chatListSearch.localPeers")
}

/// Call site helper for ChatListSearchListPaneNode.
public func wgChatListSearchLocalPeers(_ signal: Signal<[EngineRenderedPeer], NoError>, query: String, context: AccountContext) -> Signal<[EngineRenderedPeer], NoError> {
    if WGChatListSearchHooks.localPeers.isEmpty {
        return signal
    }
    var result = signal
    for handler in WGChatListSearchHooks.localPeers.handlers {
        result = handler(result, query, context)
    }
    return result
}
