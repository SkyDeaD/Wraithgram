import Foundation
import UIKit
import Display
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext
import PresentationDataUtils
import PromptUI
import WGCore
import WGSettingsUI
import WGFeaturesShared

// MARK: - Replacement rules

/// One rule set (the old visible and hidden systems are merged). A rule is added or edited with
/// two prompts; the setting is written once per completed edit, never per keystroke.
func wgMakeReplacementRulesScreen(menuContext: WGMenuContext) -> ViewController {
    let context = menuContext.context
    func edit(index: Int?) {
        let rules = WGOutgoingPipeline.replacementRules.value
        let current = index.flatMap { $0 < rules.count ? rules[$0] : nil }
        menuContext.present(promptController(context: context, text: WGStrings.Sending.Rules.sourcePrompt, value: current?.source, characterLimit: 128, apply: { source in
            guard let source = source?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty else {
                return
            }
            menuContext.present(promptController(context: context, text: WGStrings.Sending.Rules.replacementPrompt, value: current?.replacement, characterLimit: 512, apply: { replacement in
                guard let replacement else {
                    return
                }
                var updated = WGOutgoingPipeline.replacementRules.value
                let rule = WGTextReplacementRule(source: source, replacement: replacement)
                if let index, index < updated.count {
                    updated[index] = rule
                } else {
                    updated.removeAll(where: { $0.source.lowercased() == source.lowercased() })
                    updated.append(rule)
                }
                WGOutgoingPipeline.replacementRules.set(updated)
            }))
        }))
    }
    return wgMakeEditableListScreen(context: context, content: {
        let items = WGOutgoingPipeline.replacementRules.value.enumerated().map { index, rule in
            return WGEditableListItem(id: "\(index)", title: rule.source + " → " + rule.replacement)
        }
        return WGEditableListContent(title: WGStrings.Sending.Rules.title, addTitle: WGStrings.Sending.Rules.add, emptyText: WGStrings.Sending.Rules.empty, footer: WGStrings.Sending.Rules.footer, items: items)
    }, add: {
        edit(index: nil)
    }, select: { id in
        guard let index = Int(id) else {
            return
        }
        wgPresentActionSheet(context: context, title: nil, actions: [
            (WGStrings.Sending.Rules.edit, false, {
                edit(index: index)
            }),
            (WGStrings.Sending.Rules.delete, true, {
                var updated = WGOutgoingPipeline.replacementRules.value
                if index < updated.count {
                    updated.remove(at: index)
                    WGOutgoingPipeline.replacementRules.set(updated)
                }
            })
        ], present: { menuContext.present($0) })
    })
}

// MARK: - Keyword filter

func wgMakeKeywordsScreen(menuContext: WGMenuContext) -> ViewController {
    let context = menuContext.context
    return wgMakeEditableListScreen(context: context, content: {
        let items = WGMessagesSettings.keywords.value.enumerated().map { index, word in
            return WGEditableListItem(id: "\(index)", title: word)
        }
        return WGEditableListContent(title: WGStrings.Chats.Keywords.title, addTitle: WGStrings.Chats.Keywords.add, emptyText: WGStrings.Chats.Keywords.empty, footer: WGStrings.Chats.Keywords.footer, items: items)
    }, add: {
        menuContext.present(promptController(context: context, text: WGStrings.Chats.Keywords.prompt, value: nil, characterLimit: 128, apply: { value in
            guard let word = value?.trimmingCharacters(in: .whitespacesAndNewlines), !word.isEmpty else {
                return
            }
            var words = WGMessagesSettings.keywords.value
            if !words.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) {
                words.append(word)
                WGMessagesSettings.keywords.set(words)
            }
        }))
    }, select: { id in
        guard let index = Int(id) else {
            return
        }
        wgPresentActionSheet(context: context, title: nil, actions: [
            (WGStrings.Chats.Keywords.delete, true, {
                var words = WGMessagesSettings.keywords.value
                if index < words.count {
                    words.remove(at: index)
                    WGMessagesSettings.keywords.set(words)
                }
            })
        ], present: { menuContext.present($0) })
    })
}

// MARK: - Peers of the account (local creator mode, notification exceptions)

/// Peers for a list screen: loaded once per set of keys, the list rebuilds when they arrive.
private final class WGPeerTitles {
    private(set) var peers: [WGPeerKey: EnginePeer] = [:]
    private let updated = ValuePromise<Int>(0, ignoreRepeated: false)
    private var counter = 0
    private var requested = Set<WGPeerKey>()

    var signal: Signal<Void, NoError> {
        return self.updated.get() |> map { _ in Void() }
    }

    func load(_ keys: [WGPeerKey], context: AccountContext) {
        let missing = keys.filter { !self.requested.contains($0) }
        if missing.isEmpty {
            return
        }
        for key in missing {
            self.requested.insert(key)
        }
        let _ = (context.engine.data.get(EngineDataMap(missing.map { TelegramEngine.EngineData.Item.Peer.Peer(id: PeerId(wgKey: $0)) }))
        |> deliverOnMainQueue).start(next: { [weak self] result in
            guard let self else {
                return
            }
            for (peerId, peer) in result {
                if let peer {
                    self.peers[peerId.wgKey] = peer
                }
            }
            self.counter += 1
            self.updated.set(self.counter)
        })
    }
}

func wgMakeLocalCreatorScreen(menuContext: WGMenuContext) -> ViewController {
    let context = menuContext.context
    let accountId = menuContext.accountID
    let titles = WGPeerTitles()
    return wgMakeEditableListScreen(context: context, extra: titles.signal, content: {
        let keys = WGMessagesSettings.localCreatorChannels.value(for: accountId).sorted()
        titles.load(keys, context: context)
        let items = keys.map { key -> WGEditableListItem in
            let peer = titles.peers[key]
            return WGEditableListItem(id: key.stringValue, title: peer?.debugDisplayTitle ?? key.stringValue, peer: peer)
        }
        return WGEditableListContent(title: WGStrings.Chats.LocalCreator.title, addTitle: nil, emptyText: WGStrings.Chats.LocalCreator.empty, footer: WGStrings.Chats.LocalCreator.footer, items: items)
    }, add: nil, select: { id in
        guard let key = WGPeerKey(string: id) else {
            return
        }
        wgPresentActionSheet(context: context, title: nil, actions: [
            (WGStrings.Chats.LocalCreator.disable, true, {
                WGLocalCreatorMode.setLocalMode(false, peerId: PeerId(wgKey: key), accountId: accountId)
            })
        ], present: { menuContext.present($0) })
    })
}

/// Per-chat exceptions of SG-H1 (the old client read them in the extension, nothing wrote them).
enum WGNotificationExceptions {
    static func peerKeys(accountId: WGAccountID) -> [WGPeerKey] {
        let pinned = WGMessagesSettings.pinnedNotificationExceptions.value(for: accountId)
        let mentions = WGMessagesSettings.mentionNotificationExceptions.value(for: accountId)
        var keys = Set<WGPeerKey>()
        for key in pinned.keys {
            if let value = WGPeerKey(string: key) {
                keys.insert(value)
            }
        }
        for key in mentions.keys {
            if let value = WGPeerKey(string: key) {
                keys.insert(value)
            }
        }
        return keys.sorted()
    }

    static func modeTitle(_ value: String?) -> String {
        guard let value, let mode = WGNotificationDeliveryMode(rawValue: value) else {
            return WGStrings.Notifications.Exceptions.general
        }
        switch mode {
        case .standard:
            return WGStrings.Notifications.Menu.modeStandard
        case .silent:
            return WGStrings.Notifications.Menu.modeSilent
        case .disabled:
            return WGStrings.Notifications.Menu.modeDisabled
        }
    }

    static func set(_ mode: WGNotificationDeliveryMode?, kind: WGNotificationFilter.Kind, peer: WGPeerKey, accountId: WGAccountID) {
        let setting: WGAccountSetting<[String: String]>
        switch kind {
        case .pinnedMessage:
            setting = WGMessagesSettings.pinnedNotificationExceptions
        case .mentionOrReply:
            setting = WGMessagesSettings.mentionNotificationExceptions
        }
        var values = setting.value(for: accountId)
        values[peer.stringValue] = mode?.rawValue
        setting.set(values, for: accountId)
    }

    static func chooseMode(kind: WGNotificationFilter.Kind, peer: WGPeerKey, accountId: WGAccountID, menuContext: WGMenuContext) {
        let title = kind == .pinnedMessage ? WGStrings.Notifications.Menu.pinned : WGStrings.Notifications.Menu.mentions
        wgPresentActionSheet(context: menuContext.context, title: title, actions: [
            (WGStrings.Notifications.Exceptions.general, false, {
                WGNotificationExceptions.set(nil, kind: kind, peer: peer, accountId: accountId)
            }),
            (WGStrings.Notifications.Menu.modeStandard, false, {
                WGNotificationExceptions.set(.standard, kind: kind, peer: peer, accountId: accountId)
            }),
            (WGStrings.Notifications.Menu.modeSilent, false, {
                WGNotificationExceptions.set(.silent, kind: kind, peer: peer, accountId: accountId)
            }),
            (WGStrings.Notifications.Menu.modeDisabled, false, {
                WGNotificationExceptions.set(.disabled, kind: kind, peer: peer, accountId: accountId)
            })
        ], present: { menuContext.present($0) })
    }
}

func wgMakeNotificationExceptionsScreen(menuContext: WGMenuContext) -> ViewController {
    let context = menuContext.context
    let accountId = menuContext.accountID
    let titles = WGPeerTitles()
    let edit: (WGPeerKey) -> Void = { key in
        wgPresentActionSheet(context: context, title: nil, actions: [
            (WGStrings.Notifications.Menu.pinned, false, {
                WGNotificationExceptions.chooseMode(kind: .pinnedMessage, peer: key, accountId: accountId, menuContext: menuContext)
            }),
            (WGStrings.Notifications.Menu.mentions, false, {
                WGNotificationExceptions.chooseMode(kind: .mentionOrReply, peer: key, accountId: accountId, menuContext: menuContext)
            }),
            (WGStrings.Notifications.Exceptions.remove, true, {
                WGNotificationExceptions.set(nil, kind: .pinnedMessage, peer: key, accountId: accountId)
                WGNotificationExceptions.set(nil, kind: .mentionOrReply, peer: key, accountId: accountId)
            })
        ], present: { menuContext.present($0) })
    }
    return wgMakeEditableListScreen(context: context, extra: titles.signal, content: {
        let keys = WGNotificationExceptions.peerKeys(accountId: accountId)
        titles.load(keys, context: context)
        let pinned = WGMessagesSettings.pinnedNotificationExceptions.value(for: accountId)
        let mentions = WGMessagesSettings.mentionNotificationExceptions.value(for: accountId)
        let items = keys.map { key -> WGEditableListItem in
            let peer = titles.peers[key]
            let label = WGStrings.Notifications.Exceptions.pinnedValue(mode: WGNotificationExceptions.modeTitle(pinned[key.stringValue])) + " · " + WGStrings.Notifications.Exceptions.mentionsValue(mode: WGNotificationExceptions.modeTitle(mentions[key.stringValue]))
            return WGEditableListItem(id: key.stringValue, title: peer?.debugDisplayTitle ?? key.stringValue, label: label, peer: peer)
        }
        return WGEditableListContent(title: WGStrings.Notifications.Exceptions.title, addTitle: WGStrings.Notifications.Exceptions.add, emptyText: WGStrings.Notifications.Exceptions.empty, footer: WGStrings.Notifications.Menu.footer, items: items)
    }, add: {
        guard let navigationController = menuContext.navigationController else {
            return
        }
        let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.excludeSecretChats, .doNotSearchMessages], hasFilters: true, hasContactSelector: false))
        controller.peerSelected = { [weak controller] peer, _ in
            controller?.dismiss()
            edit(peer.id.wgKey)
        }
        navigationController.pushViewController(controller)
    }, select: { id in
        if let key = WGPeerKey(string: id) {
            edit(key)
        }
    })
}
