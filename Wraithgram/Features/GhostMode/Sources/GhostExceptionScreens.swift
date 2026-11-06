import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import ItemListPeerItem
import LocalizedPeerData
import PresentationDataUtils
import AlertUI
import ChatListUI
import WGCore
import WGSettingsUI
import WGFeaturesShared

// «Исключения»: the rows of its «Чаты» and «Папки» segments, one chat's exception and its own
// status list. Each screen / provider follows one signal (presentation data + the account's
// settings + Wraithgram's language) and owns its subscriptions; nothing is kept after it closes.

private func wgGhostLanguageAndSettings(_ setting: Signal<[String: WGGhostException], NoError>) -> Signal<[String: WGGhostException], NoError> {
    return combineLatest(setting, WGLocalization.shared.languageCodeSignal)
    |> map { value, _ -> [String: WGGhostException] in
        return value
    }
}

/// One line describing what a chat's exception lets through.
func wgGhostExceptionSummary(_ exception: WGGhostException) -> String {
    if exception.kind == .include {
        return WGStrings.GhostMode.Exceptions.summaryForced
    }
    var parts: [String] = []
    if exception.readMessages {
        parts.append(WGStrings.GhostMode.Exceptions.summaryReads)
    }
    if exception.readStories {
        parts.append(WGStrings.GhostMode.Exceptions.summaryStories)
    }
    if exception.showOnline {
        parts.append(WGStrings.GhostMode.Exceptions.summaryOnline)
    }
    if exception.showTyping {
        parts.append(WGStrings.GhostMode.Exceptions.summaryTyping)
    } else if exception.ownShownActivities != nil {
        parts.append(WGStrings.GhostMode.Exceptions.summaryOwnStatuses)
    }
    if parts.isEmpty {
        return WGStrings.GhostMode.Exceptions.summaryNone
    }
    return parts.joined(separator: " • ")
}

/// Writes the exceptions of an account and recomputes "online" (the chat on screen may have just
/// become an exception: it goes online without leaving and re-entering).
func wgGhostUpdateExceptions(account: WGAccountID, _ f: (inout [String: WGGhostException]) -> Void) {
    var exceptions = WGGhostSettings.exceptions.value(for: account)
    f(&exceptions)
    WGGhostSettings.exceptions.set(exceptions, for: account)
    WGGhostPresence.shared.exceptionsDidChange()
}

// MARK: - «Исключения» › «Чаты» and «Папки» (runtime rows of the segmented tab)

/// The «Чаты» and «Папки» segments of «Исключения»: rows built at runtime from the account's
/// exceptions and the user's folders (`WGMenuRegistry.register(dynamicRowsIn:)`). Each provider runs
/// one signal per opening of the tab and nothing is kept after it closes.
enum WGGhostExceptionRows {
    static let chatsSection = WGMenuSectionID("ghostMode.exceptions.chats")
    static let foldersSection = WGMenuSectionID("ghostMode.exceptions.folders")

    /// «Выбрать чаты»: Telegram's chat picker over the chats excluded so far.
    static func presentPicker(_ menuContext: WGMenuContext) {
        let context = menuContext.context
        let account = context.account.id.wg
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        var selected = Set<EnginePeer.Id>()
        for (key, exception) in WGGhostSettings.exceptions.value(for: account) where exception.kind == .exclude {
            if let peerKey = WGPeerKey(string: key) {
                selected.insert(PeerId(wgKey: peerKey))
            }
        }
        let controller = context.sharedContext.makeContactMultiselectionController(ContactMultiselectionControllerParams(context: context, mode: .chatSelection(ContactMultiselectionControllerMode.ChatSelection(
            title: WGStrings.GhostMode.Exceptions.addTitle,
            searchPlaceholder: presentationData.strings.Common_Search,
            selectedChats: selected,
            additionalCategories: nil,
            chatListFilters: nil
        )), alwaysEnabled: true))
        let _ = (controller.result
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak controller] result in
            guard case let .result(peerIds, _) = result else {
                controller?.dismiss()
                return
            }
            var chosen = Set<EnginePeer.Id>()
            for peerId in peerIds {
                if case let .peer(value) = peerId {
                    chosen.insert(value)
                }
            }
            wgGhostUpdateExceptions(account: account) { exceptions in
                for (key, exception) in exceptions where exception.kind == .exclude {
                    if let peerKey = WGPeerKey(string: key), !chosen.contains(PeerId(wgKey: peerKey)) {
                        exceptions.removeValue(forKey: key)
                    }
                }
                for peerId in chosen where exceptions[peerId.wgGhostKey]?.kind != .exclude {
                    exceptions[peerId.wgGhostKey] = WGGhostException()
                }
            }
            controller?.dismiss()
        })
        menuContext.present(controller, arguments: ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }

    /// Every chat with its own exception, sorted by name, with what it lets through; swipe to remove.
    static func chatRows(_ providerContext: WGMenuContext) -> Signal<[WGMenuRow], NoError> {
        let context = providerContext.context
        let account = context.account.id.wg
        let revealed = ValuePromise<EnginePeer.Id?>(nil, ignoreRepeated: true)

        let peers: Signal<[EnginePeer.Id: EnginePeer], NoError> = WGGhostSettings.exceptions.signal(for: account)
        |> map { exceptions -> [EnginePeer.Id] in
            return exceptions.keys.compactMap { key -> EnginePeer.Id? in
                return WGPeerKey(string: key).flatMap { PeerId(wgKey: $0) }
            }
        }
        |> distinctUntilChanged
        |> mapToSignal { peerIds -> Signal<[EnginePeer.Id: EnginePeer], NoError> in
            return context.engine.data.subscribe(EngineDataMap(peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init)))
            |> map { map -> [EnginePeer.Id: EnginePeer] in
                var result: [EnginePeer.Id: EnginePeer] = [:]
                for (peerId, peer) in map {
                    if let peer = peer {
                        result[peerId] = peer
                    }
                }
                return result
            }
        }

        return combineLatest(WGGhostSettings.exceptions.signal(for: account), peers, revealed.get(), context.sharedContext.presentationData)
        |> map { exceptions, peers, revealedPeerId, presentationData -> [WGMenuRow] in
            var items: [(EnginePeer, WGGhostException)] = []
            for (key, exception) in exceptions {
                guard let peerKey = WGPeerKey(string: key), let peer = peers[PeerId(wgKey: peerKey)] else {
                    continue
                }
                items.append((peer, exception))
            }
            items.sort(by: { lhs, rhs in
                let lhsTitle = lhs.0.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                let rhsTitle = rhs.0.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
            })
            if items.isEmpty {
                return [WGMenuRow(id: "ghostMode.exceptions.chatsEmpty", section: WGGhostExceptionRows.chatsSection, order: 1000, title: { "" }, kind: .custom({ rowContext in
                    return ItemListTextItem(presentationData: rowContext.itemListPresentationData, text: .plain(WGStrings.GhostMode.Exceptions.empty), sectionId: rowContext.sectionId)
                }))]
            }
            var rows: [WGMenuRow] = []
            for (index, item) in items.enumerated() {
                let peer = item.0
                let exception = item.1
                let peerId = peer.id
                let isRevealed = revealedPeerId == peerId
                rows.append(WGMenuRow(id: "ghostMode.exceptions.peer.\(peerId.wgKey.stringValue)", section: WGGhostExceptionRows.chatsSection, order: 1000 + index, title: { "" }, kind: .custom({ rowContext in
                    let presentationData = rowContext.presentationData
                    let remove: (EnginePeer.Id) -> Void = { peerId in
                        wgGhostUpdateExceptions(account: account) { exceptions in
                            exceptions.removeValue(forKey: peerId.wgGhostKey)
                        }
                    }
                    return ItemListPeerItem(presentationData: rowContext.itemListPresentationData, systemStyle: .glass, dateTimeFormat: presentationData.dateTimeFormat, nameDisplayOrder: presentationData.nameDisplayOrder, context: rowContext.context, peer: peer, presence: nil, text: .text(wgGhostExceptionSummary(exception), .secondary), label: .none, editing: ItemListPeerItemEditing(editable: true, editing: false, revealed: isRevealed), revealOptions: ItemListPeerItemRevealOptions(options: [ItemListPeerItemRevealOption(type: .destructive, title: WGStrings.GhostMode.Exceptions.remove, action: {
                        remove(peerId)
                    })]), switchValue: nil, enabled: true, selectable: true, sectionId: rowContext.sectionId, action: {
                        rowContext.push(wgGhostExceptionController(context: rowContext.context, peerId: peerId))
                    }, setPeerIdWithRevealedOptions: { peerId, fromPeerId in
                        if peerId != nil || fromPeerId != nil {
                            revealed.set(peerId)
                        }
                    }, removePeer: { peerId in
                        remove(peerId)
                    })
                })))
            }
            return rows
        }
    }

    /// The user's folders as switches. Membership is resolved live from the folder definitions (no
    /// stored snapshots of peer ids that go stale); a deleted folder simply stops matching.
    static func folderRows(_ providerContext: WGMenuContext) -> Signal<[WGMenuRow], NoError> {
        let context = providerContext.context
        let account = context.account.id.wg
        let toggle: (Int32, Bool) -> Void = { id, value in
            var folders = WGGhostSettings.exceptFolders.value(for: account)
            if value {
                folders.insert(id)
            } else {
                folders.remove(id)
            }
            WGGhostSettings.exceptFolders.set(folders, for: account)
            WGGhostPresence.shared.exceptionsDidChange()
        }
        // A folder hidden from the app (a locked secret folder) is not listed; an exception already
        // set on it stays in force.
        return combineLatest(WGGhostSettings.exceptFolders.signal(for: account), wgChatListFolders(context.engine.peers.updatedChatListFilters(), context: context))
        |> map { selected, filters -> [WGMenuRow] in
            var rows: [WGMenuRow] = []
            var order = 1000
            for filter in filters {
                guard case let .filter(id, title, _, _) = filter else {
                    continue
                }
                let text = title.text.isEmpty ? "#\(id)" : title.text
                let isOn = selected.contains(id)
                rows.append(WGMenuRow(id: "ghostMode.exceptFolders.\(id)", section: WGGhostExceptionRows.foldersSection, order: order, title: { text }, kind: .custom({ rowContext in
                    return ItemListSwitchItem(presentationData: rowContext.itemListPresentationData, systemStyle: .glass, title: text, value: isOn, sectionId: rowContext.sectionId, style: .blocks, updated: { value in
                        toggle(id, value)
                    })
                })))
                order += 1
            }
            if rows.isEmpty {
                rows.append(WGMenuRow(id: "ghostMode.exceptFolders.empty", section: WGGhostExceptionRows.foldersSection, order: 1000, title: { "" }, kind: .custom({ rowContext in
                    return ItemListTextItem(presentationData: rowContext.itemListPresentationData, text: .plain(WGStrings.GhostMode.Exceptions.foldersEmpty), sectionId: rowContext.sectionId)
                })))
            }
            return rows
        }
    }
}

// MARK: - One chat

private final class WGGhostExceptionArguments {
    let update: ((inout WGGhostException) -> Void) -> Void
    let openStatuses: () -> Void
    let chooseReadOnAction: () -> Void
    let remove: () -> Void

    init(update: @escaping ((inout WGGhostException) -> Void) -> Void, openStatuses: @escaping () -> Void, chooseReadOnAction: @escaping () -> Void, remove: @escaping () -> Void) {
        self.update = update
        self.openStatuses = openStatuses
        self.chooseReadOnAction = chooseReadOnAction
        self.remove = remove
    }
}

private enum WGGhostExceptionEntry: ItemListNodeEntry {
    case info(String)
    case readMessages(String, Bool)
    case readStories(String, Bool)
    case showOnline(String, String, Bool)
    case showTyping(String, Bool)
    case statuses(String, String)
    case readOnAction(String, String)
    case footer(String)
    case remove(String)

    var section: ItemListSectionId {
        switch self {
        case .info:
            return 0
        case .readMessages, .readStories, .showOnline, .showTyping, .statuses, .readOnAction, .footer:
            return 1
        case .remove:
            return 2
        }
    }

    var stableId: Int {
        switch self {
        case .info:
            return 0
        case .readMessages:
            return 1
        case .readStories:
            return 2
        case .showOnline:
            return 3
        case .showTyping:
            return 4
        case .statuses:
            return 5
        case .readOnAction:
            return 6
        case .footer:
            return 7
        case .remove:
            return 8
        }
    }

    static func <(lhs: WGGhostExceptionEntry, rhs: WGGhostExceptionEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! WGGhostExceptionArguments
        switch self {
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .readMessages(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { $0.readMessages = value }
            })
        case let .readStories(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { $0.readStories = value }
            })
        case let .showOnline(title, text, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, text: text, value: value, maximumNumberOfLines: 2, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { $0.showOnline = value }
            })
        case let .showTyping(title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { value in
                arguments.update { $0.showTyping = value }
            })
        case let .statuses(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                arguments.openStatuses()
            })
        case let .readOnAction(title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                arguments.chooseReadOnAction()
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .remove(title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .destructive, alignment: .center, sectionId: self.section, style: .blocks, action: {
                arguments.remove()
            })
        }
    }
}

/// The exception of one chat (from the list or from the profile's «…»).
func wgGhostExceptionController(context: AccountContext, peerId: EnginePeer.Id) -> ViewController {
    let account = context.account.id.wg
    let key = peerId.wgGhostKey
    var pushImpl: ((ViewController) -> Void)?
    var presentImpl: ((ViewController) -> Void)?
    var dismissImpl: (() -> Void)?

    let arguments = WGGhostExceptionArguments(update: { f in
        wgGhostUpdateExceptions(account: account) { exceptions in
            var exception = exceptions[key] ?? WGGhostException()
            f(&exception)
            exceptions[key] = exception
        }
    }, openStatuses: {
        pushImpl?(wgGhostExceptionStatusesController(context: context, peerId: peerId))
    }, chooseReadOnAction: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let set: (Bool?) -> Void = { value in
            wgGhostUpdateExceptions(account: account) { exceptions in
                var exception = exceptions[key] ?? WGGhostException()
                exception.readOnAction = value
                exceptions[key] = exception
            }
        }
        let actionSheet = ActionSheetController(presentationData: presentationData)
        actionSheet.setItemGroups([ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: WGStrings.GhostMode.Exception.readOnActionGlobal, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                set(nil)
            }),
            ActionSheetButtonItem(title: WGStrings.GhostMode.Exception.readOnActionOn, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                set(true)
            }),
            ActionSheetButtonItem(title: WGStrings.GhostMode.Exception.readOnActionOff, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                set(false)
            })
        ]), ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])])
        presentImpl?(actionSheet)
    }, remove: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentImpl?(textAlertController(context: context, title: WGStrings.GhostMode.Exception.removeConfirmTitle, text: WGStrings.GhostMode.Exception.removeConfirmText, actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: WGStrings.GhostMode.Exception.remove, action: {
                wgGhostUpdateExceptions(account: account) { exceptions in
                    exceptions.removeValue(forKey: key)
                }
                dismissImpl?()
            })
        ]))
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, wgGhostLanguageAndSettings(WGGhostSettings.exceptions.signal(for: account)), context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)))
    |> map { presentationData, exceptions, peer -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let exception = exceptions[key] ?? WGGhostException()
        var entries: [WGGhostExceptionEntry] = []
        let title = peer?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? WGStrings.GhostMode.Exception.title
        if exception.kind == .include {
            entries.append(.info(WGStrings.GhostMode.Exception.forcedInfo))
        } else {
            entries.append(.info(WGStrings.GhostMode.Exception.info))
            entries.append(.readMessages(WGStrings.GhostMode.Exception.readMessages, exception.readMessages))
            entries.append(.readStories(WGStrings.GhostMode.Exception.readStories, exception.readStories))
            entries.append(.showOnline(WGStrings.GhostMode.Exception.showOnline, WGStrings.GhostMode.Exception.showOnlineInfo, exception.showOnline))
            entries.append(.showTyping(WGStrings.GhostMode.Exception.showTyping, exception.showTyping))
            if !exception.showTyping {
                let label = exception.ownShownActivities == nil ? WGStrings.GhostMode.Exception.statusesGlobal : WGStrings.GhostMode.Exception.statusesOwn
                entries.append(.statuses(WGStrings.GhostMode.Exception.statuses, label))
            }
            if !exception.readMessages {
                let label: String
                switch exception.readOnAction {
                case .none:
                    label = WGStrings.GhostMode.Exception.readOnActionGlobal
                case .some(true):
                    label = WGStrings.GhostMode.Exception.readOnActionOn
                case .some(false):
                    label = WGStrings.GhostMode.Exception.readOnActionOff
                }
                entries.append(.readOnAction(WGStrings.GhostMode.Exception.readOnAction, label))
            }
            entries.append(.footer(WGStrings.GhostMode.Exception.footer))
        }
        if exceptions[key] != nil {
            entries.append(.remove(exception.kind == .include ? WGStrings.GhostMode.Exception.restore : WGStrings.GhostMode.Exception.remove))
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root), with: nil)
    }
    dismissImpl = { [weak controller] in
        let _ = (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
    }
    return controller
}

// MARK: - Own statuses of one chat

private final class WGGhostStatusesArguments {
    let setOwn: (Bool) -> Void
    let toggle: (WGGhostActivityKind, Bool) -> Void

    init(setOwn: @escaping (Bool) -> Void, toggle: @escaping (WGGhostActivityKind, Bool) -> Void) {
        self.setOwn = setOwn
        self.toggle = toggle
    }
}

private enum WGGhostStatusesEntry: ItemListNodeEntry {
    case own(String, String, Bool)
    case kind(Int, WGGhostActivityKind, String, Bool, Bool)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .own:
            return 0
        case .kind, .footer:
            return 1
        }
    }

    var stableId: Int {
        switch self {
        case .own:
            return 0
        case let .kind(index, _, _, _, _):
            return 10 + index
        case .footer:
            return 1000
        }
    }

    static func <(lhs: WGGhostStatusesEntry, rhs: WGGhostStatusesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! WGGhostStatusesArguments
        switch self {
        case let .own(title, text, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, text: text, value: value, maximumNumberOfLines: 3, sectionId: self.section, style: .blocks, updated: { value in
                arguments.setOwn(value)
            })
        case let .kind(_, kind, title, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(kind, value)
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

/// Statuses a chat still sees while ghost mode hides «печатает» in it: the global list, or its own.
func wgGhostExceptionStatusesController(context: AccountContext, peerId: EnginePeer.Id) -> ViewController {
    let account = context.account.id.wg
    let key = peerId.wgGhostKey
    let update: ((inout WGGhostException) -> Void) -> Void = { f in
        wgGhostUpdateExceptions(account: account) { exceptions in
            var exception = exceptions[key] ?? WGGhostException()
            f(&exception)
            exceptions[key] = exception
        }
    }
    let globalList: () -> [WGGhostActivityKind] = {
        return WGGhostActivityKind.allCases.filter { WGGhostSettings.shownActivity($0).value(for: account) }
    }
    let arguments = WGGhostStatusesArguments(setOwn: { value in
        update { exception in
            // Turning the own list on starts from the global one, so nothing changes until edited.
            exception.ownShownActivities = value ? globalList() : nil
        }
    }, toggle: { kind, value in
        update { exception in
            var list = exception.ownShownActivities ?? globalList()
            list.removeAll(where: { $0 == kind })
            if value {
                list.append(kind)
            }
            exception.ownShownActivities = list
        }
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, wgGhostLanguageAndSettings(WGGhostSettings.exceptions.signal(for: account)), WGSettingsStore.shared.revision)
    |> map { presentationData, exceptions, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let exception = exceptions[key] ?? WGGhostException()
        let own = exception.ownShownActivities
        let shown = Set(own ?? globalList())
        var entries: [WGGhostStatusesEntry] = [.own(WGStrings.GhostMode.Exception.ownList, WGStrings.GhostMode.Exception.ownListInfo, own != nil)]
        for (index, kind) in WGGhostActivityKind.allCases.enumerated() {
            entries.append(.kind(index, kind, WGGhostMenu.activityTitle(kind), shown.contains(kind), own != nil))
        }
        entries.append(.footer(WGStrings.GhostMode.Menu.activitiesFooter))
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(WGStrings.GhostMode.Menu.activities), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, arguments))
    }
    return ItemListController(context: context, state: signal)
}
