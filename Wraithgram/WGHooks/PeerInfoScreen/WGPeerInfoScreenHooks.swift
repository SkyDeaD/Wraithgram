// Compiled into PeerInfoScreen (filegroup //Wraithgram/WGHooks:PeerInfoScreenHookSources):
// maps the public points (WGSettingsTabHooks, WGPeerInfoHooks) to PeerInfoScreen's internal
// item types. No feature logic.

import Foundation
import UIKit
import AsyncDisplayKit
import SwiftSignalKit
import Display
import TelegramCore
import TelegramPresentationData
import AccountContext
import WGCore
import WGHooks

/// Sections Wraithgram adds to the Settings tab.
struct WGSettingsTabSections {
    /// Right below «Мой профиль» (shortcuts).
    var afterMyProfile: [(AnyHashable, [PeerInfoScreenItem])] = []
    /// At the end of the tab.
    var bottom: [(AnyHashable, [PeerInfoScreenItem])] = []
}

/// WRAITH hook target: `settingsItems(...)` in PeerInfoSettingsItems.swift, before the sections are
/// assembled: hides Telegram's rows features asked to hide, reorders them, adds Wraithgram's rows.
func wgApplySettingsTabHooks(_ items: inout [SettingsSection: [PeerInfoScreenItem]], context: AccountContext, presentationData: PresentationData) -> WGSettingsTabSections {
    var sections = WGSettingsTabSections()
    // Rows with a section of their own come first after «Мой профиль» (the «Wraithgram» entry).
    for row in WGSettingsTabHooks.visibleRows(placement: .ownSectionAfterMyProfile, context: context) {
        sections.afterMyProfile.append(("wg.section.\(row.id)" as AnyHashable, [PeerInfoScreenDisclosureItem(id: "wg.\(row.id)", text: row.title(), icon: row.icon(presentationData.theme), action: {
            row.action(context, context.sharedContext.mainWindow?.viewController as? NavigationController)
        })]))
    }
    if !WGSettingsTabHooks.hiddenItem.isEmpty {
        for section in SettingsSection.allCases {
            guard let sectionItems = items[section] else {
                continue
            }
            let sectionName = "\(section)"
            items[section] = sectionItems.filter { item in
                return !WGSettingsTabHooks.isItemHidden(WGSettingsTabItemKey(section: sectionName, itemId: item.id), context: context)
            }
        }
    }
    if !WGSettingsTabHooks.itemOrder.isEmpty {
        for section in SettingsSection.allCases {
            guard let sectionItems = items[section], sectionItems.count > 1 else {
                continue
            }
            var ids = sectionItems.map { $0.id }
            for handler in WGSettingsTabHooks.itemOrder.handlers {
                ids = handler("\(section)", ids, context)
            }
            var byId: [AnyHashable: PeerInfoScreenItem] = [:]
            for item in sectionItems where byId[item.id] == nil {
                byId[item.id] = item
            }
            let reordered = ids.compactMap { byId[$0] }
            if reordered.count == sectionItems.count && Set(ids).count == ids.count {
                items[section] = reordered
            }
        }
    }
    if !WGSettingsTabHooks.dynamicRows.isEmpty {
        let navigationController = context.sharedContext.mainWindow?.viewController as? NavigationController
        var dynamicItems: [PeerInfoScreenItem] = []
        for handler in WGSettingsTabHooks.dynamicRows.handlers {
            for row in handler(context, presentationData) {
                dynamicItems.append(PeerInfoScreenDisclosureItem(id: "wg.dynamic.\(row.id)", label: row.label.flatMap { .text($0) } ?? .none, text: row.title, icon: row.icon, action: {
                    row.action(context, navigationController ?? (context.sharedContext.mainWindow?.viewController as? NavigationController))
                }))
            }
        }
        if !dynamicItems.isEmpty {
            sections.afterMyProfile.append(("wg.dynamic" as AnyHashable, dynamicItems))
        }
    }
    if WGSettingsTabHooks.rows.isEmpty {
        return sections
    }
    func makeItem(_ row: WGSettingsTabRow) -> PeerInfoScreenItem {
        return PeerInfoScreenDisclosureItem(id: "wg.\(row.id)", text: row.title(), icon: row.icon(presentationData.theme), action: {
            row.action(context, context.sharedContext.mainWindow?.viewController as? NavigationController)
        })
    }
    let above = WGSettingsTabHooks.visibleRows(placement: .aboveMyProfile, context: context).map(makeItem)
    let below = WGSettingsTabHooks.visibleRows(placement: .belowMyProfile, context: context).map(makeItem)
    if !above.isEmpty || !below.isEmpty {
        items[.myProfile] = above + (items[.myProfile] ?? []) + below
    }
    let bottom = WGSettingsTabHooks.visibleRows(placement: .bottom, context: context).map(makeItem)
    if !bottom.isEmpty {
        sections.bottom.append(("wg.bottom" as AnyHashable, bottom))
    }
    return sections
}

/// WRAITH hook target: the end of `settingsItems(...)`: Wraithgram's sections go to their places.
func wgInsertSettingsTabSections(_ result: inout [(AnyHashable, [PeerInfoScreenItem])], _ sections: WGSettingsTabSections) {
    if !sections.afterMyProfile.isEmpty {
        var index = 0
        for (offset, entry) in result.enumerated() {
            if let section = entry.0.base as? SettingsSection, section.rawValue <= SettingsSection.myProfile.rawValue {
                index = offset + 1
            }
        }
        result.insert(contentsOf: sections.afterMyProfile, at: index)
    }
    result.append(contentsOf: sections.bottom)
}

/// WRAITH hook target: PeerInfoScreen — the Settings tab is rebuilt when a feature changed what it
/// shows (`WGSettingsTabHooks.invalidate()`), not only when Telegram's data changes.
func wgSettingsTabRefreshing<T>(_ signal: Signal<T, NoError>) -> Signal<T, NoError> {
    if !WGSettingsTabHooks.changesTab {
        return signal
    }
    return combineLatest(signal, WGSettingsTabHooks.revision)
    |> map { value, _ -> T in
        return value
    }
}

/// The group the profile was opened from (a member's profile opened from a group message).
func wgPeerInfoSourceChatPeerId(_ interaction: PeerInfoInteraction) -> EnginePeer.Id? {
    return wgPeerInfoSourceMessageId(interaction)?.peerId
}

/// The message the profile was opened from (a tap on its author), if any.
func wgPeerInfoSourceMessageId(_ interaction: PeerInfoInteraction) -> EngineMessage.Id? {
    return (interaction.getController() as? PeerInfoScreenImpl)?.controllerNode.sourceMessageId
}

/// The point context of a profile's info items; nil before the peer is known.
func wgPeerInfoContext(data: PeerInfoScreenData, context: AccountContext, interaction: PeerInfoInteraction) -> WGPeerInfoContext? {
    guard let peer = data.peer else {
        return nil
    }
    let sourceMessageId = wgPeerInfoSourceMessageId(interaction)
    return WGPeerInfoContext(context: context, peer: peer, chatPeer: data.chatPeer, isSettings: false, controller: interaction.getController(), sourceChatPeerId: sourceMessageId?.peerId, sourceMessageId: sourceMessageId, cachedData: data.cachedData)
}

/// WRAITH hook target: `infoItems(...)` in PeerInfoProfileItems.swift — Telegram's items features hide.
func wgPeerInfoHidesItem(_ kind: WGPeerInfoItemKind, data: PeerInfoScreenData, context: AccountContext, interaction: PeerInfoInteraction) -> Bool {
    return WGPeerInfoHooks.hidesItem(kind, context: wgPeerInfoContext(data: data, context: context, interaction: interaction))
}

/// WRAITH hook target: `infoItems(...)` in PeerInfoProfileItems.swift: feature rows (ID, DC, dates).
func wgAppendPeerInfoRows(_ items: inout [PeerInfoScreenItem], data: PeerInfoScreenData, context: AccountContext, interaction: PeerInfoInteraction) {
    if WGPeerInfoHooks.infoRows.isEmpty {
        return
    }
    guard let peerInfoContext = wgPeerInfoContext(data: data, context: context, interaction: interaction) else {
        return
    }
    let rows = WGPeerInfoHooks.rows(context: peerInfoContext)
    // A comment closes its card (a bot's «Открывая это мини-приложение…» under «Открыть приложение»):
    // rows after it got the card's background drawn over the comment. They go in front of it.
    var insertionIndex = items.count
    while insertionIndex > 0 && items[insertionIndex - 1] is PeerInfoScreenCommentItem {
        insertionIndex -= 1
    }
    for row in rows {
        var itemAction: ((ASDisplayNode, Promise<Bool>?) -> Void)?
        if let action = row.action {
            itemAction = { _, _ in
                action()
            }
        }
        var itemLongTapAction: ((ASDisplayNode) -> Void)?
        if let longTapAction = row.longTapAction {
            itemLongTapAction = { _ in
                longTapAction()
            }
        }
        items.insert(PeerInfoScreenLabeledValueItem(id: "wg.\(row.id)", label: row.label, rightLabel: row.rightLabel, text: row.text, action: itemAction, longTapAction: itemLongTapAction, requestLayout: { animated in
            interaction.requestLayout(animated)
        }), at: insertionIndex)
        insertionIndex += 1
    }
}

/// WRAITH hook target: `PeerInfoScreenNode`, right after `paneContainerNode.update(...)` — the shared
/// media area as features see it (WGPeerInfoHooks.paneContainerDidLayout). Without handlers: nothing.
func wgPeerInfoPaneContainerDidLayout(_ node: PeerInfoScreenNode) {
    if WGPeerInfoHooks.paneContainerDidLayout.isEmpty {
        return
    }
    let hasPanes = !node.state.isEditing && !(node.data?.availablePanes ?? []).isEmpty
    let layout = WGPeerInfoPaneLayout(context: node.context, peerId: node.peerId, isSettings: node.isSettings, hasPanes: hasPanes, paneContainer: node.paneContainerNode, controller: node.controller)
    for handler in WGPeerInfoHooks.paneContainerDidLayout.handlers {
        handler(layout)
    }
}
