import Foundation
import UIKit
import Display
import TelegramPresentationData
import WGCore

// Declarative menu model: category → tab → section → row.
// Features register rows into existing sections (and may add deeper tabs); the screens are
// generated from the registry. Order is always the declared sparse `order`, never array position.

public enum WGMenuCategory: String, CaseIterable {
    case privacy
    case messages
    case media
    case appearance
    case security
    case more
}

public struct WGMenuTabID: Hashable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct WGMenuSectionID: Hashable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// A screen of the menu: the root, a category or a tab.
public enum WGMenuScreenID: Hashable {
    case root
    case category(WGMenuCategory)
    case tab(WGMenuTabID)
}

/// Menu row icon. Always rendered as a 24 pt template glyph tinted with `wgMenuIconColor(theme:)`.
public enum WGMenuIcon: Equatable {
    /// A glyph from the app asset catalog (Telegram's own glyphs, e.g. "Chat/Context Menu/Eye").
    case bundle(String)
    /// An SF Symbol available on iOS 15.
    case system(String)
    /// The Wraithgram ghost from this module's assets.
    case ghost
}

public struct WGMenuChoiceOption {
    public let value: String
    public let title: () -> String

    public init(value: String, title: @escaping () -> String) {
        self.value = value
        self.title = title
    }
}

public struct WGMenuCardOption {
    public let value: String
    public let title: () -> String
    /// Drawn inside the card; called with the current theme, keep it cheap or cache it.
    public let image: (PresentationTheme) -> UIImage?

    public init(value: String, title: @escaping () -> String, image: @escaping (PresentationTheme) -> UIImage?) {
        self.value = value
        self.title = title
        self.image = image
    }
}

/// Binds a row to a WGSetting or to a WGAccountSetting of the account the menu is open for.
public struct WGMenuBinding<Value: WGSettingValue> {
    public let key: String
    public let requiresRestart: Bool
    let read: (WGAccountID) -> Value
    let write: (Value, WGAccountID) -> Void
    let isDefaultValue: (WGAccountID) -> Bool
    let resetValue: (WGAccountID) -> Void

    public static func global(_ setting: WGSetting<Value>) -> WGMenuBinding<Value> {
        return WGMenuBinding<Value>(
            key: setting.key,
            requiresRestart: setting.flags.contains(.requiresRestart),
            read: { _ in
                return setting.value
            },
            write: { value, _ in
                setting.set(value)
            },
            isDefaultValue: { _ in
                return setting.isDefault
            },
            resetValue: { _ in
                setting.reset()
            }
        )
    }

    public static func account(_ setting: WGAccountSetting<Value>) -> WGMenuBinding<Value> {
        return WGMenuBinding<Value>(
            key: setting.key,
            requiresRestart: setting.flags.contains(.requiresRestart),
            read: { account in
                return setting.value(for: account)
            },
            write: { value, account in
                setting.set(value, for: account)
            },
            isDefaultValue: { account in
                return setting.isDefault(for: account)
            },
            resetValue: { account in
                setting.reset(for: account)
            }
        )
    }

    public func value(in context: WGMenuContext) -> Value {
        return self.read(context.accountID)
    }

    /// Writes through the registry; the menu rebuilds from `WGSettingsStore.shared.revision`.
    public func set(_ value: Value, in context: WGMenuContext) {
        if self.requiresRestart {
            let current = self.read(context.accountID)
            WGMenuRestartTracker.shared.noteBeforeChange(key: self.key, launchValue: current)
        }
        self.write(value, context.accountID)
    }

    public func isDefault(in context: WGMenuContext) -> Bool {
        return self.isDefaultValue(context.accountID)
    }

    public func reset(in context: WGMenuContext) {
        if self.requiresRestart {
            let current = self.read(context.accountID)
            WGMenuRestartTracker.shared.noteBeforeChange(key: self.key, launchValue: current)
        }
        self.resetValue(context.accountID)
    }

    func isPendingRestart(in context: WGMenuContext) -> Bool {
        guard self.requiresRestart else {
            return false
        }
        return WGMenuRestartTracker.shared.differsFromLaunch(key: self.key, current: self.read(context.accountID))
    }
}

/// Type-erased view of a binding, used for the navbar reset button, «Нужен перезапуск» and duplicate checks.
struct WGMenuAnyBinding {
    let key: String
    let isDefault: (WGMenuContext) -> Bool
    let reset: (WGMenuContext) -> Void
    let isPendingRestart: (WGMenuContext) -> Bool

    init<Value>(_ binding: WGMenuBinding<Value>) {
        self.key = binding.key
        self.isDefault = { context in
            return binding.isDefault(in: context)
        }
        self.reset = { context in
            binding.reset(in: context)
        }
        self.isPendingRestart = { context in
            return binding.isPendingRestart(in: context)
        }
    }
}

public enum WGMenuRowKind {
    case toggle(WGMenuBinding<Bool>)
    /// ≤ 6 options → action sheet, more → a list screen. The current value is shown in accent color.
    case choice(WGMenuBinding<String>, options: [WGMenuChoiceOption])
    /// Ticks update only the previews of the screen; the setting is written on release.
    case slider(WGMenuBinding<Double>, range: ClosedRange<Double>, step: Double, format: (Double) -> String)
    /// «Кнопка с подписью»: icon + title + grey subtitle, no chevron.
    case tab(WGMenuTabID)
    case action((WGMenuContext) -> Void)
    /// Master switch with an «N/M» counter; children must be `.toggle` rows.
    case expandableGroup(master: WGMenuBinding<Bool>, children: [WGMenuRow])
    /// The same block without a master switch (2026-10-27): the title, a summary on the right made by
    /// `summary` from the visible children (not called, and nothing shown, while none is on), a
    /// chevron; a tap opens the children in place. Children must be `.toggle` rows.
    case expandableList(children: [WGMenuRow], summary: (WGMenuGroupCount) -> String)
    case preview(WGMenuPreview)
    /// Escape hatch: build any list item. Use `context.sectionId` and `context.itemListPresentationData`.
    case custom((WGMenuContext) -> ListViewItem)
    /// Discrete slider with a label above every tick (2…6 options).
    case discreteChoice(WGMenuBinding<String>, options: [WGMenuChoiceOption])
    /// N cards with a picture, one selected.
    case cards(WGMenuBinding<String>, options: [WGMenuCardOption])
}

public struct WGMenuRow {
    /// Globally unique, "<feature>.<row>". Also the search target and the highlight tag.
    public let id: String
    public let section: WGMenuSectionID
    /// Sparse, step 100. The position on screen is `order`, never array arithmetic.
    public let order: Int
    /// WGStrings accessor, evaluated at display time.
    public let title: () -> String
    /// Grey subtitle; text examples «привет → ПРИВЕТ» go here.
    public let subtitle: (() -> String)?
    public let icon: WGMenuIcon?
    public let kind: WGMenuRowKind
    public let isVisible: ((WGMenuContext) -> Bool)?
    public let searchKeywords: () -> [String]
    /// Accent label on the right of `.tab` / `.action` rows. Must reflect the feature's own state.
    public let label: ((WGMenuContext) -> String?)?
    public let isEnabled: ((WGMenuContext) -> Bool)?
    /// Red action row (resets, deletions). Only meaningful for `.action`.
    public let isDestructive: Bool

    public init(
        id: String,
        section: WGMenuSectionID,
        order: Int,
        title: @escaping () -> String,
        subtitle: (() -> String)? = nil,
        icon: WGMenuIcon? = nil,
        kind: WGMenuRowKind,
        isVisible: ((WGMenuContext) -> Bool)? = nil,
        searchKeywords: @escaping () -> [String] = { [] },
        label: ((WGMenuContext) -> String?)? = nil,
        isEnabled: ((WGMenuContext) -> Bool)? = nil,
        isDestructive: Bool = false
    ) {
        self.id = id
        self.section = section
        self.order = order
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.kind = kind
        self.isVisible = isVisible
        self.searchKeywords = searchKeywords
        self.label = label
        self.isEnabled = isEnabled
        self.isDestructive = isDestructive
    }

    /// The children of an expandable row (with or without a master switch); nil for any other row.
    var groupChildren: [WGMenuRow]? {
        switch self.kind {
        case let .expandableGroup(_, children):
            return children
        case let .expandableList(children, _):
            return children
        default:
            return nil
        }
    }

    var isToggle: Bool {
        if case .toggle = self.kind {
            return true
        } else {
            return false
        }
    }

    var anyBindings: [WGMenuAnyBinding] {
        switch self.kind {
        case let .toggle(binding):
            return [WGMenuAnyBinding(binding)]
        case let .choice(binding, _):
            return [WGMenuAnyBinding(binding)]
        case let .slider(binding, _, _, _):
            return [WGMenuAnyBinding(binding)]
        case let .discreteChoice(binding, _):
            return [WGMenuAnyBinding(binding)]
        case let .cards(binding, _):
            return [WGMenuAnyBinding(binding)]
        case let .expandableGroup(master, children):
            var result = [WGMenuAnyBinding(master)]
            for child in children {
                result.append(contentsOf: child.anyBindings)
            }
            return result
        case let .expandableList(children, _):
            var result: [WGMenuAnyBinding] = []
            for child in children {
                result.append(contentsOf: child.anyBindings)
            }
            return result
        case .tab, .action, .preview, .custom:
            return []
        }
    }
}

/// Segment of a tab screen with parallel views («Чаты / Папки / Типы чатов»), shown in the navbar.
public struct WGMenuSegment {
    public let id: String
    public let title: () -> String

    public init(id: String, title: @escaping () -> String) {
        self.id = id
        self.title = title
    }
}

/// Header of a sub-screen: an emoji or a bundled animated sticker over a short text.
public struct WGMenuTopView {
    public enum Content: Equatable {
        case emoji(String)
        /// Name of a bundled `.tgs` (as `AnimatedStickerNodeLocalFileSource(name:)` expects).
        case animation(String)
    }

    public let content: Content
    public let text: () -> String

    public init(content: Content, text: @escaping () -> String) {
        self.content = content
        self.text = text
    }
}

public struct WGMenuTabDescriptor {
    public let id: WGMenuTabID
    /// The screen this tab is opened from (a category, or a tab for deeper feature tabs).
    public let parent: WGMenuScreenID
    public let title: () -> String
    public let topView: WGMenuTopView?
    public let segments: [WGMenuSegment]
    /// Optional fully custom screen (history lists, editors). `nil` = generated from sections.
    public let makeScreen: ((WGMenuContext) -> ViewController)?
    public let searchKeywords: () -> [String]

    public init(
        id: WGMenuTabID,
        parent: WGMenuScreenID,
        title: @escaping () -> String,
        topView: WGMenuTopView? = nil,
        segments: [WGMenuSegment] = [],
        makeScreen: ((WGMenuContext) -> ViewController)? = nil,
        searchKeywords: @escaping () -> [String] = { [] }
    ) {
        self.id = id
        self.parent = parent
        self.title = title
        self.topView = topView
        self.segments = segments
        self.makeScreen = makeScreen
        self.searchKeywords = searchKeywords
    }
}

public struct WGMenuSectionDescriptor {
    public let id: WGMenuSectionID
    public let screen: WGMenuScreenID
    /// Sparse, step 100.
    public let order: Int
    /// `nil` = shown in every segment of the screen.
    public let segment: String?
    public let header: (() -> String)?
    public let footer: ((WGMenuContext) -> String?)?
    public let isVisible: ((WGMenuContext) -> Bool)?

    public init(
        id: WGMenuSectionID,
        screen: WGMenuScreenID,
        order: Int,
        segment: String? = nil,
        header: (() -> String)? = nil,
        footer: ((WGMenuContext) -> String?)? = nil,
        isVisible: ((WGMenuContext) -> Bool)? = nil
    ) {
        self.id = id
        self.screen = screen
        self.order = order
        self.segment = segment
        self.header = header
        self.footer = footer
        self.isVisible = isVisible
    }
}
