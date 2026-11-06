import Foundation
import UIKit
import Display
import TelegramCore
import TelegramPresentationData
import ItemListUI

/// Highlight / ensure-visible tag of a menu row (the row id).
struct WGMenuEntryTag: ItemListItemTag, Equatable {
    let id: String

    func isEqual(to other: ItemListItemTag) -> Bool {
        if let other = other as? WGMenuEntryTag {
            return other.id == self.id
        }
        return false
    }
}

enum WGMenuEntryId: Hashable {
    case header
    case topView
    case search
    case empty
    case sectionHeader(String)
    case sectionFooter(String)
    case row(String)
    case category(String)
    case result(Int)
}

/// Strict total order that does not depend on array position: (section order, rank, row order, id).
/// Rank: 0 — section header, 1 — rows, 2 — footer. ItemList asserts strictly increasing entries and
/// merges by this order, so it must stay stable across rebuilds.
struct WGMenuSortKey: Comparable {
    let section: Int
    let sectionTie: String
    let rank: Int
    let order: Int
    let tie: String

    init(section: Int, sectionTie: String = "", rank: Int, order: Int, tie: String) {
        self.section = section
        self.sectionTie = sectionTie
        self.rank = rank
        self.order = order
        self.tie = tie
    }

    static func <(lhs: WGMenuSortKey, rhs: WGMenuSortKey) -> Bool {
        if lhs.section != rhs.section {
            return lhs.section < rhs.section
        }
        if lhs.sectionTie != rhs.sectionTie {
            return lhs.sectionTie < rhs.sectionTie
        }
        if lhs.rank != rhs.rank {
            return lhs.rank < rhs.rank
        }
        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        return lhs.tie < rhs.tie
    }
}

struct WGMenuGroupChildPayload: Equatable {
    let id: String
    let title: String
    let value: Bool
    let enabled: Bool
}

/// Only what an item draws: ItemList updates a row exactly when this changes.
enum WGMenuEntryPayload: Equatable {
    case header(title: String, version: String)
    case topView(content: WGMenuTopView.Content, text: String)
    case search(text: String, placeholder: String)
    case sectionHeader(String)
    case footer(String)
    case navigation(title: String, subtitle: String?, label: String?, icon: WGMenuIcon?, enabled: Bool, destructive: Bool)
    case toggle(title: String, subtitle: String?, icon: WGMenuIcon?, value: Bool, enabled: Bool)
    case choice(title: String, subtitle: String?, icon: WGMenuIcon?, valueTitle: String, enabled: Bool)
    case slider(title: String, value: Double, lower: Double, upper: Double, step: Double, enabled: Bool)
    case discrete(labels: [String], selectedIndex: Int, enabled: Bool)
    case cards(titles: [String], selectedIndex: Int, enabled: Bool)
    case group(title: String, icon: WGMenuIcon?, value: Bool, expanded: Bool, children: [WGMenuGroupChildPayload], enabled: Bool)
    /// An expandable row without a master switch; `summary` is nil while no child is on.
    case list(title: String, icon: WGMenuIcon?, summary: String?, expanded: Bool, children: [WGMenuGroupChildPayload], enabled: Bool)
    /// `token` is set for live previews (drafts, overlays): they rebuild with every rebuild of the screen.
    case miniChat(content: WGMiniChatContent, accountPeer: EnginePeer?, height: CGFloat, token: Int?)
    case miniChatList(rows: [WGPreviewChatListRow], height: CGFloat)
    case customPreview(height: CGFloat, token: Int)
    case custom(token: Int)
}

struct WGMenuEntry: ItemListNodeEntry {
    let id: WGMenuEntryId
    let key: WGMenuSortKey
    let section: ItemListSectionId
    let payload: WGMenuEntryPayload
    /// Not compared: builders of previews and custom rows read it.
    let menuContext: WGMenuContext

    var stableId: WGMenuEntryId {
        return self.id
    }

    var tag: ItemListItemTag? {
        if case let .row(id) = self.id {
            return WGMenuEntryTag(id: id)
        }
        return nil
    }

    static func ==(lhs: WGMenuEntry, rhs: WGMenuEntry) -> Bool {
        return lhs.id == rhs.id && lhs.key == rhs.key && lhs.section == rhs.section && lhs.payload == rhs.payload
    }

    static func <(lhs: WGMenuEntry, rhs: WGMenuEntry) -> Bool {
        return lhs.key < rhs.key
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! WGMenuScreenArguments
        let theme = presentationData.theme
        let entryId = self.id
        let tag = self.tag
        switch self.payload {
        case let .header(title, version):
            return WGHeaderItem(theme: theme, fontSize: presentationData.fontSize, title: title, version: version, sectionId: self.section)
        case let .topView(content, text):
            return WGTopViewItem(context: self.menuContext.context, theme: theme, content: content, text: text, sectionId: self.section)
        case let .search(text, placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: ""), text: text, placeholder: placeholder, type: .regular(capitalization: false, autocorrection: false), returnKeyType: .search, clearType: .always, sectionId: self.section, textUpdated: { value in
                arguments.queryUpdated(value)
            }, action: {
                arguments.dismissInput()
            })
        case let .sectionHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text.uppercased(), sectionId: self.section)
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .navigation(title, subtitle, label, icon, enabled, destructive):
            if destructive {
                return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: enabled ? .destructive : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                    arguments.activate(entryId)
                }, tag: tag)
            }
            let iconImage = icon.flatMap { wgMenuIcon($0, theme: theme) }
            if let label {
                return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: iconImage, title: title, enabled: enabled, label: label, labelStyle: .coloredText(theme.list.itemAccentColor), additionalDetailLabel: subtitle, wgAdditionalDetailMaximumNumberOfLines: 2, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                    arguments.activate(entryId)
                }, tag: tag)
            } else {
                return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: iconImage, title: title, enabled: enabled, label: subtitle ?? "", labelStyle: subtitle != nil ? .multilineDetailText : .text, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                    arguments.activate(entryId)
                }, tag: tag)
            }
        case let .toggle(title, subtitle, icon, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: icon.flatMap { wgMenuIcon($0, theme: theme) }, title: title, text: subtitle, value: value, enabled: enabled, maximumNumberOfLines: 2, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(entryId, value)
            }, tag: tag)
        case let .choice(title, subtitle, icon, valueTitle, enabled):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: icon.flatMap { wgMenuIcon($0, theme: theme) }, title: title, enabled: enabled, label: valueTitle, labelStyle: .coloredText(theme.list.itemAccentColor), additionalDetailLabel: subtitle, wgAdditionalDetailMaximumNumberOfLines: 2, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: {
                arguments.activate(entryId)
            }, tag: tag)
        case let .slider(title, value, lower, upper, step, enabled):
            let format = arguments.sliderFormat(entryId)
            return WGSliderItem(theme: theme, fontSize: presentationData.fontSize, title: title, value: value, range: lower ... max(lower, upper), step: step, format: format, enabled: enabled, sectionId: self.section, tag: tag, updated: { value in
                arguments.sliderUpdated(entryId, value)
            }, committed: { value in
                arguments.sliderCommitted(entryId, value)
            })
        case let .discrete(labels, selectedIndex, enabled):
            return WGDiscreteSliderItem(theme: theme, labels: labels, selectedIndex: selectedIndex, enabled: enabled, sectionId: self.section, tag: tag, selected: { index in
                arguments.indexSelected(entryId, index)
            })
        case let .cards(titles, selectedIndex, enabled):
            let images = arguments.cardImages(entryId, theme)
            var cards: [WGChoiceCard] = []
            for i in 0 ..< titles.count {
                cards.append(WGChoiceCard(title: titles[i], image: i < images.count ? images[i] : nil))
            }
            return WGChoiceCardsItem(theme: theme, cards: cards, selectedIndex: selectedIndex, enabled: enabled, sectionId: self.section, tag: tag, selected: { index in
                arguments.indexSelected(entryId, index)
            })
        case let .group(title, icon, value, expanded, children, enabled):
            let subItems = children.map { child in
                return ItemListExpandableSwitchItem.SubItem(id: AnyHashable(child.id), title: child.title, isSelected: child.value, isEnabled: child.enabled)
            }
            return ItemListExpandableSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: icon.flatMap { wgMenuIcon($0, theme: theme) }, title: title, value: value, isExpanded: expanded, subItems: subItems, enabled: enabled, sectionId: self.section, style: .blocks, updated: { value in
                arguments.toggle(entryId, value)
            }, selectAction: {
                arguments.toggleExpanded(entryId)
            }, subAction: { subItem in
                if let childId = subItem.id.base as? String {
                    arguments.groupChildToggled(entryId, childId)
                }
            }, tag: tag)
        case let .list(title, icon, summary, expanded, children, enabled):
            let subItems = children.map { child in
                return WGExpandableListItem.SubItem(id: child.id, title: child.title, isSelected: child.value, isEnabled: child.enabled)
            }
            return WGExpandableListItem(presentationData: presentationData, icon: icon.flatMap { wgMenuIcon($0, theme: theme) }, title: title, summary: summary, isExpanded: expanded, subItems: subItems, enabled: enabled, sectionId: self.section, tag: tag, toggleExpanded: {
                arguments.toggleExpanded(entryId)
            }, subAction: { subItem in
                arguments.groupChildToggled(entryId, subItem.id)
            })
        case let .miniChat(content, accountPeer, height, _):
            let configuration = arguments.miniChatConfiguration(entryId)
            var previewContext = self.menuContext
            previewContext.previewScope = configuration?.scope
            let draftScope: (() -> Void) -> Void
            if let featureScope = configuration?.draftScope {
                draftScope = { body in
                    featureScope(previewContext, body)
                }
            } else {
                draftScope = { body in
                    body()
                }
            }
            var previewPresentationData = self.menuContext.presentationData
            if let makePresentationData = configuration?.presentationData {
                draftScope {
                    previewPresentationData = makePresentationData(previewContext)
                }
            }
            return WGMiniChatPreviewItem(context: self.menuContext.context, presentationData: previewPresentationData, content: content, accountPeer: accountPeer, height: height, sectionId: self.section, menuContext: previewContext, draftScope: draftScope, makeOverlays: configuration?.overlays)
        case let .miniChatList(rows, height):
            return WGMiniChatListPreviewItem(context: self.menuContext.context, presentationData: self.menuContext.presentationData, rows: rows, height: height, sectionId: self.section)
        case let .customPreview(height, _):
            let menuContext = self.menuContext
            let make = arguments.previewMaker(entryId)
            return WGPreviewHostItem(theme: theme, sectionId: self.section, height: height, make: {
                return make?(menuContext) ?? UIView()
            }, update: { view in
                (view as? WGMenuPreviewView)?.update(context: menuContext)
            })
        case .custom:
            if let builder = arguments.customBuilder(entryId) {
                return builder(self.menuContext)
            }
            return ItemListTextItem(presentationData: presentationData, text: .plain(""), sectionId: self.section)
        }
    }
}
