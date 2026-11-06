import Foundation
import UIKit
import Display
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext
import UndoUI
import TextFormat
import ChatScheduleTimeController
import WGCore
import WGFeaturesShared
import WGExtrasHooks

/// «В Избранное» and «Переслать без автора» on the chat's selection panel. Both forward the selected
/// messages; a protected chat whose protection Wraithgram lifted sends copies (WGForwardCopy), as the
/// message menu does. Secret chats and protected chats without the bypass never reach here: the
/// panel stops them the same way it stops Telegram's own «Переслать».
enum WGExtrasSelection {
    static func register() {
        WGExtrasUIHooks.selectionAction.register({ action, context, messageIds in
            if messageIds.isEmpty {
                return true
            }
            let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Messages.Messages(ids: Set(messageIds)))
            |> deliverOnMainQueue).start(next: { messagesById in
                let messages = messageIds.compactMap { messagesById[$0]?._asMessage() }.sorted(by: { $0.id < $1.id })
                if messages.isEmpty {
                    return
                }
                switch action {
                case .saveToCloud:
                    WGExtrasForwarding.send(messages, to: context.account.peerId, hideNames: false, context: context, toast: WGStrings.Extras.Selection.savedToCloud)
                case .forwardWithoutAuthor:
                    WGExtrasForwarding.pickPeerAndSend(messages, hideNames: true, context: context)
                }
            })
            return true
        })
    }
}

/// Forwarding without opening the target chat.
enum WGExtrasForwarding {
    /// `threadId` — the forum topic chosen in the picker (nil = the chat itself).
    static func send(_ messages: [Message], to peerId: EnginePeer.Id, threadId: Int64? = nil, hideNames: Bool, context: AccountContext, toast: String) {
        WGForwardSend.send(account: context.account, messages: messages, to: [WGForwardSend.Target(peerId: peerId, threadId: threadId)], hideNames: hideNames, hideCaptions: false, completion: { result in
            WGExtrasForwarding.showResult(result, context: context, toast: toast)
        })
    }

    static func pickPeerAndSend(_ messages: [Message], hideNames: Bool, context: AccountContext) {
        guard let navigationController = context.sharedContext.mainWindow?.viewController as? NavigationController else {
            return
        }
        // As Telegram's own «Переслать»: «Выбрать» for several chats, a comment, the forward options
        // (names start hidden) and the send menu.
        let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.onlyWriteable, .excludeDisabled, .doNotSearchMessages], hasFilters: true, multipleSelection: true, forwardedMessageIds: messages.map { $0.id }, selectForumThreads: true, wgHidesSenderNames: hideNames))
        controller.peerSelected = { [weak controller] peer, threadId in
            controller?.dismiss()
            WGExtrasForwarding.send(messages, to: peer.id, threadId: threadId, hideNames: hideNames, context: context, toast: WGStrings.Extras.Selection.forwarded)
        }
        controller.multiplePeersSelected = { [weak controller] peers, _, text, mode, forwardOptions, _ in
            guard let controller, !peers.isEmpty else {
                return
            }
            let send: (Bool, Int32?, Int32?) -> Void = { silent, scheduleTime, repeatPeriod in
                controller.dismiss()
                WGForwardSend.send(account: context.account, messages: messages, comment: WGExtrasForwarding.commentMessages(text), to: peers.map { WGForwardSend.Target(peerId: $0.id, threadId: nil) }, hideNames: forwardOptions?.hideNames ?? hideNames, hideCaptions: forwardOptions?.hideCaptions ?? false, silent: silent, scheduleTime: scheduleTime, repeatPeriod: repeatPeriod, completion: { result in
                    WGExtrasForwarding.showResult(result, context: context, toast: WGStrings.Extras.Selection.forwarded)
                })
            }
            switch mode {
            case .generic:
                send(false, nil, nil)
            case .silent:
                send(true, nil, nil)
            case .whenOnline:
                send(false, scheduleWhenOnlineTimestamp, nil)
            case .schedule:
                let scheduleMode: ChatScheduleTimeScreen.Mode
                if peers.count == 1, peers[0].id == context.account.peerId {
                    scheduleMode = .reminders
                } else {
                    scheduleMode = .scheduledMessages(peerId: peers[0].id, sendWhenOnlineAvailable: false)
                }
                controller.present(ChatScheduleTimeScreen(context: context, mode: scheduleMode, currentTime: nil, isDark: false, completion: { result in
                    send(result.silentPosting, result.time, result.repeatPeriod)
                }), in: .window(.root))
            }
        }
        navigationController.pushViewController(controller)
    }

    /// The comment typed in the picker, as Telegram's forward sends it: split by the length limit,
    /// with its entities.
    private static func commentMessages(_ text: NSAttributedString) -> [EnqueueMessage] {
        var result: [EnqueueMessage] = []
        for part in breakChatInputText(trimChatInputText(convertMarkdownToAttributes(text))) where part.length != 0 {
            var attributes: [MessageAttribute] = []
            let entities = generateTextEntities(part.string, enabledTypes: .all, currentEntities: generateChatInputTextEntities(part))
            if !entities.isEmpty {
                attributes.append(TextEntitiesMessageAttribute(entities: entities))
            }
            result.append(.message(text: part.string, attributes: attributes, inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: []))
        }
        return result
    }

    private static func showResult(_ result: WGForwardCopy.Result, context: AccountContext, toast: String) {
        let text: String
        if !result.messages.isEmpty {
            text = toast
        } else {
            // Nothing could be copied: say why instead of a «sent» that did not happen.
            text = result.failedCount > 0 ? WGStrings.Restrictions.Copy.failed(count: result.failedCount) : WGStrings.Restrictions.Copy.unsupported(count: result.skippedCount)
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        context.sharedContext.mainWindow?.present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in
            return false
        }), on: .root)
    }
}
