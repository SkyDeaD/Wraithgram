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

/// Per-screen UI state that is never persisted.
struct WGMenuScreenState: Equatable {
    var expandedGroups = Set<String>()
    /// Slider values while a finger is on the slider (previews follow them; the setting is not written).
    var drafts: [String: Double] = [:]
    var segmentIndex: Int = 0
    var query: String = ""
}

/// Mutable bits the screen's closures share. Touched only on the main queue.
private final class WGMenuScreenHolder {
    var menuContext: WGMenuContext?
    var results: [WGMenuSearchEntry] = []
    var token: Int = 0
    /// The runtime rows of this screen (`WGMenuRegistry.register(dynamicRowsIn:)`), by id.
    var dynamicRowsById: [String: WGMenuRow] = [:]

    func row(_ id: String) -> WGMenuRow? {
        if let row = WGMenuStorage.shared.rowsById[id] {
            return row
        }
        return self.dynamicRowsById[id]
    }
}

final class WGMenuScreenArguments {
    let activate: (WGMenuEntryId) -> Void
    let toggle: (WGMenuEntryId, Bool) -> Void
    let toggleExpanded: (WGMenuEntryId) -> Void
    let groupChildToggled: (WGMenuEntryId, String) -> Void
    let sliderUpdated: (WGMenuEntryId, Double) -> Void
    let sliderCommitted: (WGMenuEntryId, Double) -> Void
    let indexSelected: (WGMenuEntryId, Int) -> Void
    let queryUpdated: (String) -> Void
    let dismissInput: () -> Void
    private let rowLookup: (String) -> WGMenuRow?

    init(rowLookup: @escaping (String) -> WGMenuRow?, activate: @escaping (WGMenuEntryId) -> Void, toggle: @escaping (WGMenuEntryId, Bool) -> Void, toggleExpanded: @escaping (WGMenuEntryId) -> Void, groupChildToggled: @escaping (WGMenuEntryId, String) -> Void, sliderUpdated: @escaping (WGMenuEntryId, Double) -> Void, sliderCommitted: @escaping (WGMenuEntryId, Double) -> Void, indexSelected: @escaping (WGMenuEntryId, Int) -> Void, queryUpdated: @escaping (String) -> Void, dismissInput: @escaping () -> Void) {
        self.rowLookup = rowLookup
        self.activate = activate
        self.toggle = toggle
        self.toggleExpanded = toggleExpanded
        self.groupChildToggled = groupChildToggled
        self.sliderUpdated = sliderUpdated
        self.sliderCommitted = sliderCommitted
        self.indexSelected = indexSelected
        self.queryUpdated = queryUpdated
        self.dismissInput = dismissInput
    }

    private func row(_ entryId: WGMenuEntryId) -> WGMenuRow? {
        if case let .row(id) = entryId {
            return self.rowLookup(id)
        }
        return nil
    }

    func miniChatConfiguration(_ entryId: WGMenuEntryId) -> WGMiniChatConfiguration? {
        if let row = self.row(entryId), case let .preview(preview) = row.kind, case let .miniChat(configuration) = preview {
            return configuration
        }
        return nil
    }

    func sliderFormat(_ entryId: WGMenuEntryId) -> (Double) -> String {
        if let row = self.row(entryId), case let .slider(_, _, _, format) = row.kind {
            return format
        }
        return { value in
            return "\(value)"
        }
    }

    func cardImages(_ entryId: WGMenuEntryId, _ theme: PresentationTheme) -> [UIImage?] {
        if let row = self.row(entryId), case let .cards(_, options) = row.kind {
            return options.map { $0.image(theme) }
        }
        return []
    }

    func previewMaker(_ entryId: WGMenuEntryId) -> ((WGMenuContext) -> UIView)? {
        if let row = self.row(entryId), case let .preview(preview) = row.kind, case let .custom(_, make) = preview {
            return make
        }
        return nil
    }

    func customBuilder(_ entryId: WGMenuEntryId) -> ((WGMenuContext) -> ListViewItem)? {
        if let row = self.row(entryId), case let .custom(builder) = row.kind {
            return builder
        }
        return nil
    }
}

/// Root of the Wraithgram menu.
public func wgMakeSettingsController(context: AccountContext) -> ViewController {
    return wgMakeGeneratedMenuScreen(context: context, screen: .root, tabDescriptor: nil, focusRowId: nil)
}

/// Builds any menu screen. `focusRowId` (from search) scrolls to the row and highlights it once.
func wgMakeMenuScreen(context: AccountContext, screen: WGMenuScreenID, focusRowId: String?) -> ViewController? {
    guard case let .tab(tabId) = screen else {
        return wgMakeGeneratedMenuScreen(context: context, screen: screen, tabDescriptor: nil, focusRowId: focusRowId)
    }
    guard let tab = WGMenuStorage.shared.tabs[tabId] else {
        return nil
    }
    if let makeScreen = tab.makeScreen {
        let handle = WGMenuScreenHandle(context: context)
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let controller = makeScreen(WGMenuContext(context: context, presentationData: presentationData, accountPeer: nil, drafts: [:], handle: handle))
        handle.controller = controller
        return controller
    }
    return wgMakeGeneratedMenuScreen(context: context, screen: screen, tabDescriptor: tab, focusRowId: focusRowId)
}

private func wgMakeGeneratedMenuScreen(context: AccountContext, screen: WGMenuScreenID, tabDescriptor: WGMenuTabDescriptor?, focusRowId: String?) -> ViewController {
    let storage = WGMenuStorage.shared
    let handle = WGMenuScreenHandle(context: context)

    var initialState = WGMenuScreenState()
    if let focusRowId, let groupId = storage.groupByChildId[focusRowId] {
        initialState.expandedGroups.insert(groupId)
    }
    // A search result inside a segmented tab opens on the segment that holds the row.
    if let focusRowId, let segments = tabDescriptor?.segments, !segments.isEmpty {
        let rowId = storage.groupByChildId[focusRowId] ?? focusRowId
        if let row = storage.rowsById[rowId], let segment = storage.sectionsById[row.section]?.segment, let index = segments.firstIndex(where: { $0.id == segment }) {
            initialState.segmentIndex = index
        }
    }
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((inout WGMenuScreenState) -> Void) -> Void = { f in
        statePromise.set(stateValue.modify { state in
            var state = state
            f(&state)
            return state
        })
    }

    let holder = WGMenuScreenHolder()

    let currentContext: () -> WGMenuContext? = {
        return holder.menuContext
    }

    let arguments = WGMenuScreenArguments(rowLookup: { id in
        return holder.row(id)
    }, activate: { entryId in
        guard let menuContext = currentContext() else {
            return
        }
        switch entryId {
        case let .category(rawValue):
            if let category = WGMenuCategory(rawValue: rawValue) {
                handle.open(screen: .category(category), focusRowId: nil)
            }
        case let .result(index):
            guard index < holder.results.count else {
                return
            }
            let result = holder.results[index]
            handle.controller?.view.endEditing(true)
            handle.open(screen: result.target, focusRowId: result.focusRowId)
        case let .row(id):
            guard let row = holder.row(id) else {
                return
            }
            switch row.kind {
            case let .tab(tabId):
                handle.open(screen: .tab(tabId), focusRowId: nil)
            case let .action(action):
                // Actions go through the access gates too (export, import, a feature's own).
                wgMenuWithAccess(.action(rowId: row.id), path: wgMenuScreenPathIds(screen), context: context, perform: {
                    if let currentContext = currentContext() {
                        action(currentContext)
                    }
                    return nil
                })
            case let .choice(binding, options):
                wgPresentChoice(row: row, binding: binding, options: options, menuContext: menuContext)
            default:
                break
            }
        default:
            break
        }
    }, toggle: { entryId, value in
        guard let menuContext = currentContext(), case let .row(id) = entryId, let row = holder.row(id) else {
            return
        }
        switch row.kind {
        case let .toggle(binding):
            binding.set(value, in: menuContext)
        case let .expandableGroup(master, _):
            master.set(value, in: menuContext)
        default:
            break
        }
    }, toggleExpanded: { entryId in
        guard case let .row(id) = entryId else {
            return
        }
        updateState { state in
            if state.expandedGroups.contains(id) {
                state.expandedGroups.remove(id)
            } else {
                state.expandedGroups.insert(id)
            }
        }
    }, groupChildToggled: { _, childId in
        guard let menuContext = currentContext(), let child = storage.rowsById[childId], case let .toggle(binding) = child.kind else {
            return
        }
        binding.set(!binding.value(in: menuContext), in: menuContext)
    }, sliderUpdated: { entryId, value in
        guard case let .row(id) = entryId, let row = holder.row(id), case let .slider(binding, _, _, _) = row.kind else {
            return
        }
        updateState { state in
            state.drafts[binding.key] = value
        }
    }, sliderCommitted: { entryId, value in
        guard let menuContext = currentContext(), case let .row(id) = entryId, let row = holder.row(id), case let .slider(binding, _, _, _) = row.kind else {
            return
        }
        binding.set(value, in: menuContext)
        updateState { state in
            state.drafts.removeValue(forKey: binding.key)
        }
    }, indexSelected: { entryId, index in
        guard let menuContext = currentContext(), case let .row(id) = entryId, let row = holder.row(id) else {
            return
        }
        switch row.kind {
        case let .discreteChoice(binding, options):
            if index >= 0 && index < options.count {
                binding.set(options[index].value, in: menuContext)
            }
        case let .cards(binding, options):
            if index >= 0 && index < options.count {
                binding.set(options[index].value, in: menuContext)
            }
        default:
            break
        }
    }, queryUpdated: { query in
        updateState { state in
            state.query = query
        }
    }, dismissInput: {
        handle.controller?.view.endEditing(true)
    })

    let accountPeer: Signal<EnginePeer?, NoError> = .single(nil)
    |> then(context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId)))

    let focusTag: ItemListItemTag? = focusRowId.flatMap { rowId in
        return WGMenuEntryTag(id: storage.groupByChildId[rowId] ?? rowId)
    }

    // Runtime rows of this screen's sections, one signal for all of them (none — a constant).
    let dynamicRows = wgMenuDynamicRows(screen: screen, context: context, handle: handle)

    // One signal per screen: presentation data + the settings revision + the WG language + this
    // screen's state (+ its runtime rows). The subscription belongs to the ItemListController and
    // dies with it.
    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        WGSettingsStore.shared.revision,
        WGLocalization.shared.languageCodeSignal,
        statePromise.get(),
        accountPeer,
        dynamicRows
    )
    |> map { presentationData, _, _, state, accountPeer, dynamicRows -> (ItemListControllerState, (ItemListNodeState, WGMenuScreenArguments)) in
        let menuContext = WGMenuContext(context: context, presentationData: presentationData, accountPeer: accountPeer, drafts: state.drafts, handle: handle)
        holder.menuContext = menuContext
        holder.token += 1
        var dynamicRowsById: [String: WGMenuRow] = [:]
        for rows in dynamicRows.values {
            for row in rows {
                assert(storage.rowsById[row.id] == nil, "WGMenu: dynamic row \(row.id) clashes with a registered row")
                dynamicRowsById[row.id] = row
            }
        }
        holder.dynamicRowsById = dynamicRowsById

        let built = wgBuildMenuEntries(screen: screen, tab: tabDescriptor, menuContext: menuContext, state: state, dynamicRows: dynamicRows, token: holder.token)
        holder.results = built.results

        let title: ItemListControllerTitle
        switch screen {
        case .root:
            title = .text("")
        case let .category(category):
            title = .text(category.title)
        case .tab:
            let tabTitle = tabDescriptor?.title() ?? ""
            if let segments = tabDescriptor?.segments, !segments.isEmpty {
                title = .textWithTabs(tabTitle, segments.map { $0.title() }, min(state.segmentIndex, segments.count - 1))
            } else {
                title = .text(tabTitle)
            }
        }

        var rightNavigationButton: ItemListNavigationButton?
        if built.resettable.contains(where: { !$0.isDefault(menuContext) }) {
            rightNavigationButton = ItemListNavigationButton(content: .text(WGStrings.Menu.Common.reset), style: .regular, enabled: true, action: {
                wgConfirmScreenReset(bindings: built.resettable, menuContext: menuContext)
            })
        }

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: title, leftNavigationButton: nil, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: built.entries, style: .blocks, ensureVisibleItemTag: focusTag, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    handle.controller = controller
    controller.titleControlValueChanged = { index in
        updateState { state in
            state.segmentIndex = index
        }
    }

    if let focusTag {
        var didHighlight = false
        controller.afterTransactionCompleted = { [weak controller] in
            guard !didHighlight, let controller else {
                return
            }
            controller.forEachItemNode { itemNode in
                if let itemNode = itemNode as? ItemListItemNode, let tag = itemNode.tag, tag.isEqual(to: focusTag) {
                    didHighlight = true
                    itemNode.displayHighlight()
                }
            }
        }
    }

    return controller
}

struct WGMenuBuildResult {
    var entries: [WGMenuEntry] = []
    var resettable: [WGMenuAnyBinding] = []
    var results: [WGMenuSearchEntry] = []
}

/// The runtime rows of the screen's sections, by section, as one signal.
private func wgMenuDynamicRows(screen: WGMenuScreenID, context: AccountContext, handle: WGMenuScreenHandle) -> Signal<[WGMenuSectionID: [WGMenuRow]], NoError> {
    let storage = WGMenuStorage.shared
    var signals: [Signal<(WGMenuSectionID, [WGMenuRow]), NoError>] = []
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let providerContext = WGMenuContext(context: context, presentationData: presentationData, accountPeer: nil, drafts: [:], handle: handle)
    for section in storage.sections(for: screen) {
        guard let providers = storage.dynamicRowProviders[section.id] else {
            continue
        }
        for provider in providers {
            let sectionId = section.id
            signals.append(provider(providerContext)
            |> map { rows -> (WGMenuSectionID, [WGMenuRow]) in
                return (sectionId, rows)
            })
        }
    }
    if signals.isEmpty {
        return .single([:])
    }
    return combineLatest(signals)
    |> map { values -> [WGMenuSectionID: [WGMenuRow]] in
        var result: [WGMenuSectionID: [WGMenuRow]] = [:]
        for (sectionId, rows) in values {
            result[sectionId, default: []].append(contentsOf: rows)
        }
        return result
    }
}

/// Whether a screen would show anything. Tabs without rows are not linked (no dead screens); the
/// demo registration switches this off to show the whole skeleton.
func wgMenuScreenHasContent(_ screen: WGMenuScreenID, menuContext: WGMenuContext, depth: Int = 0) -> Bool {
    let storage = WGMenuStorage.shared
    if storage.showsEmptyTabs {
        return true
    }
    if depth > 8 {
        return false
    }
    if case let .tab(tabId) = screen, let tab = storage.tabs[tabId], tab.makeScreen != nil {
        return true
    }
    for section in storage.sections(for: screen) {
        if let isVisible = section.isVisible, !isVisible(menuContext) {
            continue
        }
        // Runtime rows are not known here: such a section always counts as content.
        if storage.hasDynamicRows(in: section.id) {
            return true
        }
        for row in storage.rows(in: section.id) {
            if wgMenuRowIsVisible(row, menuContext: menuContext, depth: depth + 1) {
                return true
            }
        }
    }
    return false
}

func wgMenuRowIsVisible(_ row: WGMenuRow, menuContext: WGMenuContext, depth: Int = 0) -> Bool {
    if let isVisible = row.isVisible, !isVisible(menuContext) {
        return false
    }
    if case let .tab(tabId) = row.kind {
        return wgMenuScreenHasContent(.tab(tabId), menuContext: menuContext, depth: depth)
    }
    return true
}

private func wgBuildMenuEntries(screen: WGMenuScreenID, tab: WGMenuTabDescriptor?, menuContext: WGMenuContext, state: WGMenuScreenState, dynamicRows: [WGMenuSectionID: [WGMenuRow]], token: Int) -> WGMenuBuildResult {
    var result = WGMenuBuildResult()
    switch screen {
    case .root:
        wgBuildRootEntries(menuContext: menuContext, state: state, result: &result)
    case .category, .tab:
        wgBuildSectionEntries(screen: screen, tab: tab, menuContext: menuContext, state: state, dynamicRows: dynamicRows, token: token, result: &result)
    }
    return result
}

private func wgBuildRootEntries(menuContext: WGMenuContext, state: WGMenuScreenState, result: inout WGMenuBuildResult) {
    // «Версия 13.0 (186)»: the build number follows the version, as on the About screen.
    result.entries.append(WGMenuEntry(id: .header, key: WGMenuSortKey(section: 0, rank: 1, order: 0, tie: ""), section: 0, payload: .header(title: WGStrings.Menu.title, version: WGStrings.Menu.Root.version(version: wgAppVersionString())), menuContext: menuContext))
    result.entries.append(WGMenuEntry(id: .search, key: WGMenuSortKey(section: 1, rank: 1, order: 0, tie: ""), section: 1, payload: .search(text: state.query, placeholder: WGStrings.Menu.Root.searchPlaceholder), menuContext: menuContext))

    let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
    if !query.isEmpty {
        let results = wgMenuSearch(query: query, menuContext: menuContext)
        result.results = results
        if results.isEmpty {
            result.entries.append(WGMenuEntry(id: .empty, key: WGMenuSortKey(section: 2, rank: 2, order: 0, tie: ""), section: 2, payload: .footer(WGStrings.Menu.Search.noResults), menuContext: menuContext))
        } else {
            for (index, entry) in results.enumerated() {
                result.entries.append(WGMenuEntry(id: .result(index), key: WGMenuSortKey(section: 2, rank: 1, order: index, tie: ""), section: 2, payload: .navigation(title: entry.title, subtitle: entry.path.joined(separator: " › "), label: nil, icon: entry.icon, enabled: true, destructive: false), menuContext: menuContext))
            }
        }
        return
    }

    var categoryEntries: [WGMenuEntry] = []
    for (index, category) in WGMenuCategory.allCases.enumerated() {
        if !wgMenuScreenHasContent(.category(category), menuContext: menuContext) {
            continue
        }
        categoryEntries.append(WGMenuEntry(id: .category(category.rawValue), key: WGMenuSortKey(section: 3, rank: 1, order: index, tie: ""), section: 3, payload: .navigation(title: category.title, subtitle: category.subtitle, label: nil, icon: category.icon, enabled: true, destructive: false), menuContext: menuContext))
    }
    if !categoryEntries.isEmpty {
        result.entries.append(WGMenuEntry(id: .sectionHeader("root.categories"), key: WGMenuSortKey(section: 3, rank: 0, order: 0, tie: ""), section: 3, payload: .sectionHeader(WGStrings.Menu.Root.categories), menuContext: menuContext))
        result.entries.append(contentsOf: categoryEntries)
    }

    result.entries.append(WGMenuEntry(id: .sectionFooter("root.links"), key: WGMenuSortKey(section: 4, rank: 2, order: 0, tie: ""), section: 4, payload: .footer(WGStrings.Menu.Root.footer(version: wgAppVersionString())), menuContext: menuContext))
}

private func wgBuildSectionEntries(screen: WGMenuScreenID, tab: WGMenuTabDescriptor?, menuContext: WGMenuContext, state: WGMenuScreenState, dynamicRows: [WGMenuSectionID: [WGMenuRow]], token: Int, result: inout WGMenuBuildResult) {
    let storage = WGMenuStorage.shared
    var sectionIndex: ItemListSectionId = 0

    if let tab, let topView = tab.topView {
        result.entries.append(WGMenuEntry(id: .topView, key: WGMenuSortKey(section: Int.min, rank: 1, order: 0, tie: ""), section: sectionIndex, payload: .topView(content: topView.content, text: topView.text()), menuContext: menuContext))
        sectionIndex += 1
    }

    var selectedSegment: String?
    if let segments = tab?.segments, !segments.isEmpty {
        selectedSegment = segments[max(0, min(state.segmentIndex, segments.count - 1))].id
    }

    var emittedAnySection = false
    for section in storage.sections(for: screen) {
        if let segment = section.segment, let selectedSegment, segment != selectedSegment {
            continue
        }
        if let isVisible = section.isVisible, !isVisible(menuContext) {
            continue
        }
        var rowContext = menuContext
        rowContext.sectionId = sectionIndex

        var rowEntries: [WGMenuEntry] = []
        var sectionBindings: [WGMenuAnyBinding] = []
        for row in storage.rows(in: section.id) {
            if !wgMenuRowIsVisible(row, menuContext: rowContext) {
                continue
            }
            let payload = wgMenuRowPayload(row: row, menuContext: rowContext, state: state, token: token)
            rowEntries.append(WGMenuEntry(id: .row(row.id), key: WGMenuSortKey(section: section.order, sectionTie: section.id.rawValue, rank: 1, order: row.order, tie: row.id), section: sectionIndex, payload: payload, menuContext: rowContext))
            sectionBindings.append(contentsOf: row.anyBindings)
        }
        // Runtime rows: after the registered ones by `order`, never in the navbar reset.
        if let sectionDynamicRows = dynamicRows[section.id] {
            for row in sectionDynamicRows {
                if !wgMenuRowIsVisible(row, menuContext: rowContext) {
                    continue
                }
                let payload = wgMenuRowPayload(row: row, menuContext: rowContext, state: state, token: token)
                rowEntries.append(WGMenuEntry(id: .row(row.id), key: WGMenuSortKey(section: section.order, sectionTie: section.id.rawValue, rank: 1, order: row.order, tie: row.id), section: sectionIndex, payload: payload, menuContext: rowContext))
            }
            rowEntries.sort(by: { $0.key < $1.key })
        }
        if rowEntries.isEmpty {
            continue
        }
        emittedAnySection = true
        result.resettable.append(contentsOf: sectionBindings)

        if let header = section.header {
            result.entries.append(WGMenuEntry(id: .sectionHeader(section.id.rawValue), key: WGMenuSortKey(section: section.order, sectionTie: section.id.rawValue, rank: 0, order: 0, tie: ""), section: sectionIndex, payload: .sectionHeader(header()), menuContext: rowContext))
        }
        result.entries.append(contentsOf: rowEntries)

        var footerParts: [String] = []
        if let footer = section.footer?(rowContext), !footer.isEmpty {
            footerParts.append(footer)
        }
        if sectionBindings.contains(where: { $0.isPendingRestart(rowContext) }) {
            footerParts.append(WGStrings.Core.requiresRestartFooter)
        }
        if !footerParts.isEmpty {
            result.entries.append(WGMenuEntry(id: .sectionFooter(section.id.rawValue), key: WGMenuSortKey(section: section.order, sectionTie: section.id.rawValue, rank: 2, order: 0, tie: ""), section: sectionIndex, payload: .footer(footerParts.joined(separator: "\n\n")), menuContext: rowContext))
        }
        sectionIndex += 1
    }

    if !emittedAnySection {
        result.entries.append(WGMenuEntry(id: .empty, key: WGMenuSortKey(section: Int.max, rank: 2, order: 0, tie: ""), section: sectionIndex, payload: .footer(WGStrings.Menu.Common.emptyTab), menuContext: menuContext))
    }
}

private func wgMenuRowPayload(row: WGMenuRow, menuContext: WGMenuContext, state: WGMenuScreenState, token: Int) -> WGMenuEntryPayload {
    let enabled = row.isEnabled?(menuContext) ?? true
    let subtitle = row.subtitle?()
    switch row.kind {
    case let .toggle(binding):
        return .toggle(title: row.title(), subtitle: subtitle, icon: row.icon, value: binding.value(in: menuContext), enabled: enabled)
    case let .choice(binding, options):
        let current = binding.value(in: menuContext)
        let valueTitle = options.first(where: { $0.value == current })?.title() ?? current
        return .choice(title: row.title(), subtitle: subtitle, icon: row.icon, valueTitle: valueTitle, enabled: enabled)
    case let .slider(binding, range, step, _):
        return .slider(title: row.title(), value: menuContext.displayValue(binding), lower: range.lowerBound, upper: range.upperBound, step: step, enabled: enabled)
    case .tab, .action:
        return .navigation(title: row.title(), subtitle: subtitle, label: row.label?(menuContext), icon: row.icon, enabled: enabled, destructive: row.isDestructive)
    case let .expandableGroup(master, children):
        let childPayloads = wgMenuGroupChildPayloads(children, menuContext: menuContext)
        return .group(title: row.title(), icon: row.icon, value: master.value(in: menuContext), expanded: state.expandedGroups.contains(row.id), children: childPayloads, enabled: enabled)
    case let .expandableList(children, summary):
        let childPayloads = wgMenuGroupChildPayloads(children, menuContext: menuContext)
        let count = WGMenuGroupCount(values: childPayloads.map { $0.value })
        return .list(title: row.title(), icon: row.icon, summary: count.summary(summary), expanded: state.expandedGroups.contains(row.id), children: childPayloads, enabled: enabled)
    case let .preview(preview):
        switch preview {
        case let .miniChat(configuration):
            var previewContext = menuContext
            previewContext.previewScope = configuration.scope
            var content = configuration.content(previewContext)
            content.messages = WGPreviewModifiers.applyChat(content.messages, context: previewContext)
            return .miniChat(content: content, accountPeer: menuContext.accountPeer, height: configuration.height, token: configuration.isLive ? token : nil)
        case let .miniChatList(configuration):
            var previewContext = menuContext
            previewContext.previewScope = configuration.scope
            let rows = WGPreviewModifiers.applyChatList(configuration.rows(previewContext), context: previewContext)
            return .miniChatList(rows: rows, height: configuration.height)
        case let .custom(height, _):
            return .customPreview(height: height, token: token)
        }
    case .custom:
        return .custom(token: token)
    case let .discreteChoice(binding, options):
        let current = binding.value(in: menuContext)
        return .discrete(labels: options.map { $0.title() }, selectedIndex: options.firstIndex(where: { $0.value == current }) ?? 0, enabled: enabled)
    case let .cards(binding, options):
        let current = binding.value(in: menuContext)
        return .cards(titles: options.map { $0.title() }, selectedIndex: options.firstIndex(where: { $0.value == current }) ?? 0, enabled: enabled)
    }
}

/// The visible toggle children of an expandable row, as its item draws them.
private func wgMenuGroupChildPayloads(_ children: [WGMenuRow], menuContext: WGMenuContext) -> [WGMenuGroupChildPayload] {
    var result: [WGMenuGroupChildPayload] = []
    for child in children {
        if let isVisible = child.isVisible, !isVisible(menuContext) {
            continue
        }
        if case let .toggle(binding) = child.kind {
            result.append(WGMenuGroupChildPayload(id: child.id, title: child.title(), value: binding.value(in: menuContext), enabled: child.isEnabled?(menuContext) ?? true))
        }
    }
    return result
}

/// ≤ 6 options → action sheet with checkmarks; more → a list screen.
private func wgPresentChoice(row: WGMenuRow, binding: WGMenuBinding<String>, options: [WGMenuChoiceOption], menuContext: WGMenuContext) {
    let current = binding.value(in: menuContext)
    if options.count > 6 {
        menuContext.push(wgMakeChoiceListController(context: menuContext.context, title: row.title(), options: options, binding: binding, menuContext: menuContext))
        return
    }
    let presentationData = menuContext.presentationData
    let actionSheet = ActionSheetController(presentationData: presentationData)
    var items: [ActionSheetItem] = [ActionSheetTextItem(title: row.title(), parseMarkdown: false)]
    for option in options {
        items.append(ActionSheetCheckboxItem(title: option.title(), label: "", value: option.value == current, action: { [weak actionSheet] _ in
            actionSheet?.dismissAnimated()
            binding.set(option.value, in: menuContext)
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
    menuContext.present(actionSheet)
}

private func wgConfirmScreenReset(bindings: [WGMenuAnyBinding], menuContext: WGMenuContext) {
    let presentationData = menuContext.presentationData
    menuContext.present(textAlertController(context: menuContext.context, title: WGStrings.Menu.Common.resetTitle, text: WGStrings.Menu.Common.resetText, actions: [
        TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
        TextAlertAction(type: .destructiveAction, title: WGStrings.Menu.Common.reset, action: {
            for binding in bindings {
                binding.reset(menuContext)
            }
        })
    ]))
}
