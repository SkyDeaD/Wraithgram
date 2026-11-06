import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import PresentationDataUtils
import WGCore

/// One screen pattern for the zone's lists (replacement rules, filter words, notification
/// exceptions, channels in the local mode): an «add» row, the items, a footer. The screen rebuilds
/// from one signal (settings revision + presentation data + language + the screen's own data);
/// actions go through closures, nothing is stored in the screen.
struct WGEditableListItem: Equatable {
    let id: String
    let title: String
    let label: String
    let peer: EnginePeer?

    init(id: String, title: String, label: String = "", peer: EnginePeer? = nil) {
        self.id = id
        self.title = title
        self.label = label
        self.peer = peer
    }
}

private final class WGEditableListArguments {
    let context: AccountContext
    let add: (() -> Void)?
    let select: (String) -> Void

    init(context: AccountContext, add: (() -> Void)?, select: @escaping (String) -> Void) {
        self.context = context
        self.add = add
        self.select = select
    }
}

private enum WGEditableListEntry: ItemListNodeEntry {
    case add(String)
    case item(Int, WGEditableListItem)
    case empty(String)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .add:
            return 0
        case .item, .empty, .footer:
            return 1
        }
    }

    var stableId: Int {
        switch self {
        case .add:
            return 0
        case .empty:
            return 1
        case let .item(index, _):
            return 100 + index
        case .footer:
            return Int.max
        }
    }

    static func ==(lhs: WGEditableListEntry, rhs: WGEditableListEntry) -> Bool {
        switch lhs {
        case let .add(text):
            if case .add(text) = rhs {
                return true
            }
            return false
        case let .item(index, item):
            if case let .item(rhsIndex, rhsItem) = rhs, index == rhsIndex, item == rhsItem {
                return true
            }
            return false
        case let .empty(text):
            if case .empty(text) = rhs {
                return true
            }
            return false
        case let .footer(text):
            if case .footer(text) = rhs {
                return true
            }
            return false
        }
    }

    static func <(lhs: WGEditableListEntry, rhs: WGEditableListEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! WGEditableListArguments
        switch self {
        case let .add(text):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.add?()
            })
        case let .item(_, item):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, context: item.peer == nil ? nil : arguments.context, iconPeer: item.peer, title: item.title, label: item.label, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                arguments.select(item.id)
            })
        case let .empty(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

struct WGEditableListContent {
    let title: String
    let addTitle: String?
    let emptyText: String
    let footer: String?
    let items: [WGEditableListItem]
}

/// `content` is re-evaluated on every settings change and on `extra` (peer data etc.).
func wgMakeEditableListScreen(context: AccountContext, extra: Signal<Void, NoError> = .single(Void()), content: @escaping () -> WGEditableListContent, add: (() -> Void)?, select: @escaping (String) -> Void) -> ViewController {
    let arguments = WGEditableListArguments(context: context, add: add, select: select)
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, WGSettingsStore.shared.revision, WGLocalization.shared.languageCodeSignal, extra)
    |> map { presentationData, _, _, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let value = content()
        var entries: [WGEditableListEntry] = []
        if let addTitle = value.addTitle {
            entries.append(.add(addTitle))
        }
        if value.items.isEmpty {
            entries.append(.empty(value.emptyText))
        } else {
            for (index, item) in value.items.enumerated() {
                entries.append(.item(index, item))
            }
        }
        if let footer = value.footer {
            entries.append(.footer(footer))
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(value.title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }
    return ItemListController(context: context, state: signal)
}

/// An action sheet with plain buttons and Cancel, presented over `controller`.
func wgPresentActionSheet(context: AccountContext, title: String?, actions: [(title: String, isDestructive: Bool, action: () -> Void)], present: (ViewController) -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let actionSheet = ActionSheetController(presentationData: presentationData)
    var items: [ActionSheetItem] = []
    if let title {
        items.append(ActionSheetTextItem(title: title, parseMarkdown: false))
    }
    for item in actions {
        let action = item.action
        items.append(ActionSheetButtonItem(title: item.title, color: item.isDestructive ? .destructive : .accent, action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()
            action()
        }))
    }
    actionSheet.setItemGroups([
        ActionSheetItemGroup(items: items),
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])
    ])
    present(actionSheet)
}
