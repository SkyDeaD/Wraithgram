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

private enum WGChoiceListEntry: ItemListNodeEntry {
    case option(index: Int, title: String, isSelected: Bool)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int {
        switch self {
        case let .option(index, _, _):
            return index
        }
    }

    static func <(lhs: WGChoiceListEntry, rhs: WGChoiceListEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let select = arguments as! (Int) -> Void
        switch self {
        case let .option(index, title, isSelected):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .right, checked: isSelected, zeroSeparatorInsets: false, sectionId: self.section, action: {
                select(index)
            })
        }
    }
}

/// A choice with more than six options: a list screen with checkmarks (fewer go to an action sheet).
func wgMakeChoiceListController(context: AccountContext, title: String, options: [WGMenuChoiceOption], binding: WGMenuBinding<String>, menuContext: WGMenuContext) -> ViewController {
    var dismissImpl: (() -> Void)?
    let select: (Int) -> Void = { index in
        guard index >= 0 && index < options.count else {
            return
        }
        binding.set(options[index].value, in: menuContext)
        dismissImpl?()
    }

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, WGSettingsStore.shared.revision, WGLocalization.shared.languageCodeSignal)
    |> map { presentationData, _, _ -> (ItemListControllerState, (ItemListNodeState, (Int) -> Void)) in
        let current = binding.value(in: menuContext)
        var entries: [WGChoiceListEntry] = []
        for (index, option) in options.enumerated() {
            entries.append(.option(index: index, title: option.title(), isSelected: option.value == current))
        }
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)
        return (controllerState, (listState, select))
    }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        if let navigationController = controller?.navigationController as? NavigationController {
            let _ = navigationController.popViewController(animated: true)
        }
    }
    return controller
}
