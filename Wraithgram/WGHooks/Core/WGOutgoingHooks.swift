// Compiled into TelegramCore (filegroup //Wraithgram/WGHooks:TelegramCoreHookSources).
// The outgoing pipeline: every message sent through `enqueueMessages(account:peerId:messages:)`
// (text, media, stickers, forwards, voice) passes these points once, in this order:
//   1. `textStages`  — ordered transformations of text + entities (formatting is preserved);
//   2. `messages`    — the whole batch: attributes, sticker replacement;
//   3. `didEnqueue`  — observers after the messages are stored (e.g. "read on action").
// Stages run on the caller's thread before the Postbox transaction: keep them fast and pure.
// Network work (translation before sending) belongs to the UI point
// `WGChatScreenHooks.willSendText`, which may be asynchronous.
//
// The send delay (`sendDelay`) is asked later, INSIDE the transaction that stores the batch, where the
// chat's peer is at hand (a bot can not take a scheduled message) — and by the standalone senders too
// (share extension, quick forward, Siri), which never pass `enqueueMessages`.

import Foundation
import Postbox
import SwiftSignalKit
import WGCore

public struct WGOutgoingContext {
    public let account: Account
    public let peerId: PeerId
}

/// Text of one outgoing message with its entities (bold, links, custom emoji…).
public struct WGOutgoingText: Equatable {
    public var text: String
    public var entities: [MessageTextEntity]

    public init(text: String, entities: [MessageTextEntity]) {
        self.text = text
        self.entities = entities
    }
}

/// What a text stage knows about the message it transforms.
public struct WGOutgoingTextContext {
    public let account: Account
    public let peerId: PeerId
    /// The message as the UI enqueued it (media, reply, thread, attributes).
    public let message: EnqueueMessage
    public let hasMedia: Bool
    public let threadId: Int64?
}

/// What the send delay decides on. Asked inside the Postbox transaction that stores the batch
/// (`enqueueMessages`) or sends it right away (the standalone senders), with the chat's peer at hand.
public struct WGOutgoingDelayRequest {
    public let accountPeerId: PeerId
    public let peerId: PeerId
    /// The chat as stored in this account's Postbox; nil when it is not there.
    public let peer: Peer?
    /// Attributes of every message of the batch (already scheduled, paid, view-once…).
    public let attributes: [[MessageAttribute]]
    /// The server's time now (`Network.globalTime`).
    public let serverTime: Double
}

/// A message of a standalone sender (share extension, quick forward, Siri) the server accepted. That
/// path stores nothing locally, so `didEnqueue` never hears of it.
public struct WGStandaloneSendContext {
    public let accountPeerId: PeerId
    public let peerId: PeerId
    /// It went out scheduled (the send delay or the sender's own schedule).
    public let isScheduled: Bool
}

public enum WGOutgoingHooks {
    /// Transformer chain over text + entities of every `.message` with non-empty text.
    /// A stage must keep entity ranges valid for the text it returns.
    public static let textStages = WGHookPoint<(inout WGOutgoingText, WGOutgoingTextContext) -> Void>("outgoing.textStages")

    /// Transformer over the whole batch (after the text stages): add attributes,
    /// drop `InlineBotMessageAttribute`, replace a sticker's media, clear bubble-up sets… The send
    /// delay is not here: it needs the chat's peer (`sendDelay`).
    public static let messages = WGHookPoint<(inout [EnqueueMessage], WGOutgoingContext) -> Void>("outgoing.messages")

    /// Observer after the messages are stored (ids in the order of the batch, nil = failed).
    public static let didEnqueue = WGHookPoint<(WGOutgoingContext, [MessageId?]) -> Void>("outgoing.didEnqueue")

    /// Observer: the user set or removed reactions on messages of a chat ("read on action").
    public static let didReact = WGHookPoint<(WGOutgoingContext, [MessageId]) -> Void>("outgoing.didReact")

    /// Policy: the server time to schedule the whole batch for (send delay), nil — send as is. First
    /// non-nil wins. Inside a Postbox transaction, any process: snapshot reads only.
    public static let sendDelay = WGHookPoint<(WGOutgoingDelayRequest) -> Int32?>("outgoing.sendDelay")

    /// Observer: a standalone sender's message was accepted by the server (any process, network queue).
    public static let didSendStandalone = WGHookPoint<(WGStandaloneSendContext) -> Void>("outgoing.didSendStandalone")

    /// Policy: send this cloud file as a fresh upload (download, then upload as a new document) instead
    /// of by reference — e.g. a sound of an inline bot sent without «via», which the server does not
    /// take by the bot's reference. First true wins. Upload path, any thread: attribute checks only.
    public static let reuploadsCloudFile = WGHookPoint<(TelegramMediaFile, [MessageAttribute]) -> Bool>("outgoing.reuploadsCloudFile")

    /// Async transformer of a batch that has forwards, before `enqueueMessages` stores it: forwards the
    /// server would refuse (protected content with the bypass on, kept self-destructing media) become
    /// copies — on every path that forwards (the share sheet, profile media, search, the forward
    /// panel), not only the chat's own forward flow. nil = nothing to change; the first non-nil wins.
    public static let forwardCopies = WGHookPoint<(Account, [EnqueueMessage]) -> Signal<[EnqueueMessage], NoError>?>("outgoing.forwardCopies")
}

/// WRAITH hook target: `enqueueMessages`, after the text stages. The batch as it is (synchronously)
/// when it has no forwards or nobody converts them.
func wgConvertForwardCopies(_ messages: [EnqueueMessage], account: Account) -> Signal<[EnqueueMessage], NoError> {
    if WGOutgoingHooks.forwardCopies.isEmpty || !messages.contains(where: { if case .forward = $0 { return true } else { return false } }) {
        return .single(messages)
    }
    for handler in WGOutgoingHooks.forwardCopies.handlers {
        if let signal = handler(account, messages) {
            return signal
        }
    }
    return .single(messages)
}

/// WRAITH hook target: the upload of a message's cloud file (`mediaContentToUpload`), before it is
/// sent by reference. false (one load) when nobody asks for a fresh upload.
func wgOutgoingReuploadsCloudFile(_ file: TelegramMediaFile, attributes: [MessageAttribute]) -> Bool {
    if WGOutgoingHooks.reuploadsCloudFile.isEmpty {
        return false
    }
    for handler in WGOutgoingHooks.reuploadsCloudFile.handlers {
        if handler(file, attributes) {
            return true
        }
    }
    return false
}

private func wgOutgoingSendDelay(_ request: WGOutgoingDelayRequest) -> Int32? {
    for handler in WGOutgoingHooks.sendDelay.handlers {
        if let value = handler(request) {
            return value
        }
    }
    return nil
}

/// WRAITH hook target: the transaction of `enqueueMessages(account:peerId:messages:)`, before the batch
/// is stored. Every message gets the schedule of the send delay, or none of them does.
func wgApplyOutgoingSendDelay(_ messages: [(Bool, EnqueueMessage)], transaction: Transaction, account: Account, peerId: PeerId) -> [(Bool, EnqueueMessage)] {
    if WGOutgoingHooks.sendDelay.isEmpty || messages.isEmpty {
        return messages
    }
    let request = WGOutgoingDelayRequest(accountPeerId: account.peerId, peerId: peerId, peer: transaction.getPeer(peerId), attributes: messages.map { $0.1.attributes }, serverTime: account.network.globalTime)
    guard let scheduleTime = wgOutgoingSendDelay(request) else {
        return messages
    }
    return messages.map { item -> (Bool, EnqueueMessage) in
        return (item.0, item.1.withUpdatedAttributes { attributes in
            var attributes = attributes
            attributes.append(OutgoingScheduleInfoMessageAttribute(scheduleTime: scheduleTime, repeatPeriod: nil))
            return attributes
        })
    }
}

/// WRAITH hook target: a standalone sender, inside its transaction. The message is not stored locally:
/// the schedule goes straight into the request. Nil — send now.
func wgStandaloneSendDelay(accountPeerId: PeerId, peerId: PeerId, peer: Peer, attributes: [MessageAttribute], serverTime: Double) -> Int32? {
    if WGOutgoingHooks.sendDelay.isEmpty {
        return nil
    }
    return wgOutgoingSendDelay(WGOutgoingDelayRequest(accountPeerId: accountPeerId, peerId: peerId, peer: peer, attributes: [attributes], serverTime: serverTime))
}

/// WRAITH hook target: the server accepted a standalone sender's message.
func wgStandaloneMessageDidSend(accountPeerId: PeerId, peerId: PeerId, isScheduled: Bool) {
    if WGOutgoingHooks.didSendStandalone.isEmpty {
        return
    }
    let context = WGStandaloneSendContext(accountPeerId: accountPeerId, peerId: peerId, isScheduled: isScheduled)
    for handler in WGOutgoingHooks.didSendStandalone.handlers {
        handler(context)
    }
}

func wgMessagesDidReact(account: Account, messageIds: [MessageId]) {
    if WGOutgoingHooks.didReact.isEmpty {
        return
    }
    guard let peerId = messageIds.first?.peerId else {
        return
    }
    let context = WGOutgoingContext(account: account, peerId: peerId)
    for handler in WGOutgoingHooks.didReact.handlers {
        handler(context, messageIds)
    }
}

// MARK: - Call-site helpers (TelegramCore internal)

func wgTransformOutgoingMessages(_ messages: [EnqueueMessage], account: Account, peerId: PeerId) -> [EnqueueMessage] {
    var result = messages
    if !WGOutgoingHooks.textStages.isEmpty {
        result = result.map { wgApplyOutgoingTextStages($0, account: account, peerId: peerId) }
    }
    if !WGOutgoingHooks.messages.isEmpty {
        let context = WGOutgoingContext(account: account, peerId: peerId)
        for handler in WGOutgoingHooks.messages.handlers {
            handler(&result, context)
        }
    }
    return result
}

func wgOutgoingMessagesDidEnqueue(account: Account, peerId: PeerId, ids: [MessageId?]) {
    if WGOutgoingHooks.didEnqueue.isEmpty {
        return
    }
    let context = WGOutgoingContext(account: account, peerId: peerId)
    for handler in WGOutgoingHooks.didEnqueue.handlers {
        handler(context, ids)
    }
}

private func wgApplyOutgoingTextStages(_ message: EnqueueMessage, account: Account, peerId: PeerId) -> EnqueueMessage {
    guard case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = message else {
        return message
    }
    if text.isEmpty {
        return message
    }
    var entities: [MessageTextEntity] = []
    for attribute in attributes {
        if let attribute = attribute as? TextEntitiesMessageAttribute {
            entities = attribute.entities
            break
        }
    }
    let original = WGOutgoingText(text: text, entities: entities)
    var value = original
    let context = WGOutgoingTextContext(account: account, peerId: peerId, message: message, hasMedia: mediaReference != nil, threadId: threadId)
    for handler in WGOutgoingHooks.textStages.handlers {
        handler(&value, context)
    }
    if value == original {
        return message
    }
    var updatedAttributes = attributes.filter { !($0 is TextEntitiesMessageAttribute) }
    if !value.entities.isEmpty {
        updatedAttributes.append(TextEntitiesMessageAttribute(entities: value.entities))
    }
    return .message(text: value.text, attributes: updatedAttributes, inlineStickers: inlineStickers, mediaReference: mediaReference, threadId: threadId, replyToMessageId: replyToMessageId, replyToStoryId: replyToStoryId, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets)
}
