// Compiled into IntentsExtensionLib (filegroup //Wraithgram/WGHooks:SiriIntentsHookSources).
// Messages Siri may read aloud (announce, «read my messages»): protected chats are left out
// (WGContentPrivacyHooks.hidesContent, handler in WGFeaturesShared — W3-4 chat lock).

import Foundation
import Intents
import SwiftSignalKit
import Postbox
import TelegramCore

/// WRAITH hook target: `INSearchForMessagesIntent` handling, the messages before they are handed to
/// Siri. `INMessage.conversationIdentifier` is the chat's `PeerId.toInt64()` (IntentMessages.swift).
func wgSiriHidingProtectedMessages(_ messages: Signal<[INMessage], NoError>, accountId: AccountRecordId) -> Signal<[INMessage], NoError> {
    if WGContentPrivacyHooks.hidesContent.isEmpty {
        return messages
    }
    return messages
    |> map { messages -> [INMessage] in
        return messages.filter { message in
            guard let conversationIdentifier = message.conversationIdentifier, let rawValue = Int64(conversationIdentifier) else {
                return true
            }
            return !WGContentPrivacyHooks.hidesContent(accountId: accountId, peerId: PeerId(rawValue))
        }
    }
}
