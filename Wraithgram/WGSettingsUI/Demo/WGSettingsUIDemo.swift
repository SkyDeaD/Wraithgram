import Foundation
import UIKit
import Display
import TelegramPresentationData
import ItemListUI
import WGCore
import WGSettingsUI

// Demo registration of the menu skeleton. NOT part of the normal launch: it exists so the
// orchestrator can check every row type and every preview in the simulator before wave 2.
// Enable it by adding `//Wraithgram/WGSettingsUI:WGSettingsUIDemo` to the deps of WGFeatures and
// calling `WGSettingsUIDemo.register()` right after `WGSettingsUI.register()` (see USAGE.md).

enum WGSettingsUIDemoSettings {
    static let toggle = WGSetting<Bool>("menuDemo.toggle", default: false)
    static let choice = WGSetting<String>("menuDemo.choice", default: "a")
    static let longChoice = WGSetting<String>("menuDemo.longChoice", default: "1")
    static let slider = WGSetting<Double>("menuDemo.slider", default: 50.0)
    static let discrete = WGSetting<String>("menuDemo.discrete", default: "medium")
    static let cards = WGSetting<String>("menuDemo.cards", default: "round")
    static let group = WGSetting<Bool>("menuDemo.group", default: false)
    static let groupFirst = WGSetting<Bool>("menuDemo.groupFirst", default: true)
    static let groupSecond = WGSetting<Bool>("menuDemo.groupSecond", default: false)
    static let groupThird = WGSetting<Bool>("menuDemo.groupThird", default: false)
    static let listFirst = WGSetting<Bool>("menuDemo.listFirst", default: true)
    static let listSecond = WGSetting<Bool>("menuDemo.listSecond", default: false)
    static let listThird = WGSetting<Bool>("menuDemo.listThird", default: false)
    static let restart = WGSetting<Bool>("menuDemo.restart", default: false, flags: [.requiresRestart])
    static let accountToggle = WGAccountSetting<Bool>("menuDemo.accountToggle", default: false)
    static let transparency = WGSetting<Double>("menuDemo.transparency", default: 50.0)
    static let segmentToggle = WGSetting<Bool>("menuDemo.segmentToggle", default: false)

    static func touchAll() {
        let _ = toggle
        let _ = choice
        let _ = longChoice
        let _ = slider
        let _ = discrete
        let _ = cards
        let _ = group
        let _ = groupFirst
        let _ = groupSecond
        let _ = groupThird
        let _ = listFirst
        let _ = listSecond
        let _ = listThird
        let _ = restart
        let _ = accountToggle
        let _ = transparency
        let _ = segmentToggle
    }
}

/// A custom preview: a rounded square whose corner radius follows the demo slider while it is
/// dragged (draft), then the stored value.
private final class WGDemoPreviewView: UIView, WGMenuPreviewView {
    private let shapeView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.addSubview(self.shapeView)
    }

    required init?(coder: NSCoder) {
        preconditionFailure()
    }

    func update(context: WGMenuContext) {
        let theme = context.presentationData.theme
        self.backgroundColor = wgPreviewBackgroundColor(theme: theme)
        self.shapeView.backgroundColor = theme.list.itemAccentColor
        let value = context.displayValue(.global(WGSettingsUIDemoSettings.slider))
        self.shapeView.layer.cornerRadius = CGFloat(value) / 100.0 * 30.0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = 60.0
        self.shapeView.frame = CGRect(x: floor((self.bounds.width - side) / 2.0), y: floor((self.bounds.height - side) / 2.0), width: side, height: side)
    }
}

private func wgDemoCardImage(_ kind: String, theme: PresentationTheme) -> UIImage? {
    let size = CGSize(width: 40.0, height: 40.0)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
        theme.list.itemAccentColor.setFill()
        let rect = CGRect(origin: CGPoint(), size: size)
        switch kind {
        case "round":
            UIBezierPath(ovalIn: rect).fill()
        case "squircle":
            UIBezierPath(roundedRect: rect, cornerRadius: 12.0).fill()
        default:
            UIBezierPath(rect: rect).fill()
        }
    }
}

public enum WGSettingsUIDemo {
    public static let tabId = WGMenuTabID("menuDemo.tab")

    public static func register() {
        assert(Thread.isMainThread)
        WGSettingsUIDemoSettings.touchAll()
        WGSettingsUI.showsEmptyScreens = true

        let tabId = WGSettingsUIDemo.tabId
        WGMenuRegistry.register(
            tab: WGMenuTabDescriptor(
                id: tabId,
                parent: .category(.more),
                title: { WGStrings.Menu.Demo.title },
                topView: WGMenuTopView(content: .animation("ChatListFolders"), text: { WGStrings.Menu.Demo.topText }),
                segments: [
                    WGMenuSegment(id: "first", title: { WGStrings.Menu.Demo.segmentFirst }),
                    WGMenuSegment(id: "second", title: { WGStrings.Menu.Demo.segmentSecond })
                ]
            ),
            linkIn: .moreTabs,
            order: 900,
            subtitle: { WGStrings.Menu.Demo.subtitle },
            icon: .system("hammer"),
            label: { _ in
                return WGSettingsUIDemoSettings.toggle.value ? WGStrings.Menu.Demo.on : nil
            }
        )

        let previews = WGMenuSectionID("menuDemo.previews")
        let rows = WGMenuSectionID("menuDemo.rows")
        let more = WGMenuSectionID("menuDemo.more")
        let second = WGMenuSectionID("menuDemo.second")
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: previews, screen: .tab(tabId), order: 100, segment: "first", header: { WGStrings.Menu.Demo.previewsHeader }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: rows, screen: .tab(tabId), order: 200, segment: "first", header: { WGStrings.Menu.Demo.rowsHeader }, footer: { _ in WGStrings.Menu.Demo.rowsFooter }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: more, screen: .tab(tabId), order: 300, segment: "first"))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: second, screen: .tab(tabId), order: 400, segment: "second", header: { WGStrings.Menu.Demo.secondHeader }))

        // Previews.
        WGMenuRegistry.register(WGMenuRow(id: "menuDemo.miniChat", section: previews, order: 100, title: { "" }, kind: .preview(.miniChat(WGMiniChatConfiguration(scope: "menuDemo", height: 236.0, content: { _ in
            var content = WGMiniChatContent.sample(header: WGMiniChatContent.sampleHeader())
            content.messages.append(WGPreviewMessage(id: 3, isOutgoing: true, text: WGStrings.Menu.Preview.pendingText, isPending: true, ageSeconds: 60))
            return content
        })))))
        WGMenuRegistry.register(WGMenuRow(id: "menuDemo.transparency", section: previews, order: 200, title: { WGStrings.Menu.Demo.transparency }, kind: .slider(.global(WGSettingsUIDemoSettings.transparency), range: 0.0 ... 100.0, step: 5.0, format: { value in
            return "\(Int(value)) %"
        })))
        WGMenuRegistry.register(WGMenuRow(id: "menuDemo.miniChatList", section: previews, order: 300, title: { "" }, kind: .preview(.miniChatList(WGMiniChatListConfiguration(scope: "menuDemo", height: 228.0, rows: { _ in
            return WGPreviewChatListRow.samples()
        })))))
        WGMenuRegistry.register(WGMenuRow(id: "menuDemo.customPreview", section: previews, order: 400, title: { "" }, kind: .preview(.custom(height: 120.0, make: { _ in
            return WGDemoPreviewView(frame: CGRect())
        }))))

        // Modifiers: the second demo message follows the transparency slider (draft while dragging)
        // and is marked «edited»; the first chat row gets typing while the demo toggle is on.
        WGPreviewModifiers.registerChatModifier(id: "menuDemo.transparency", order: 100) { messages, context in
            guard context.previewScope == "menuDemo" else {
                return
            }
            let transparency = context.displayValue(.global(WGSettingsUIDemoSettings.transparency))
            for i in 0 ..< messages.count where messages[i].id == 2 {
                messages[i].alpha = CGFloat(max(0.15, 1.0 - transparency / 100.0))
                messages[i].isEdited = true
                messages[i].mark = WGPreviewMark(icon: .bundle("Chat/Context Menu/Delete"))
            }
        }
        WGPreviewModifiers.registerChatListModifier(id: "menuDemo.typing", order: 100) { rows, context in
            guard context.previewScope == "menuDemo", WGSettingsUIDemoSettings.toggle.value, !rows.isEmpty else {
                return
            }
            rows[0].isTyping = true
        }

        // One row of every kind.
        WGMenuRegistry.register(WGMenuRow(id: "menuDemo.toggle", section: rows, order: 100, title: { WGStrings.Menu.Demo.toggle }, subtitle: { WGStrings.Menu.Demo.toggleExample }, kind: .toggle(.global(WGSettingsUIDemoSettings.toggle)), searchKeywords: { [WGStrings.Menu.Demo.keywords] }))
        WGMenuRegistry.register(WGMenuRow(id: "menuDemo.choice", section: rows, order: 200, title: { WGStrings.Menu.Demo.choice }, icon: .bundle("Chat/Context Menu/Customize"), kind: .choice(.global(WGSettingsUIDemoSettings.choice), options: [
            WGMenuChoiceOption(value: "a", title: { WGStrings.Menu.Demo.optionA }),
            WGMenuChoiceOption(value: "b", title: { WGStrings.Menu.Demo.optionB }),
            WGMenuChoiceOption(value: "c", title: { WGStrings.Menu.Demo.optionC })
        ])))
        var longOptions: [WGMenuChoiceOption] = []
        for index in 1 ... 9 {
            longOptions.append(WGMenuChoiceOption(value: "\(index)", title: { WGStrings.Menu.Demo.optionNumber(number: "\(index)") }))
        }
        WGMenuRegistry.register(WGMenuRow(id: "menuDemo.longChoice", section: rows, order: 300, title: { WGStrings.Menu.Demo.longChoice }, icon: .bundle("Chat/Context Menu/List"), kind: .choice(.global(WGSettingsUIDemoSettings.longChoice), options: longOptions)))
        WGMenuRegistry.register(WGMenuRow(id: "menuDemo.slider", section: rows, order: 400, title: { WGStrings.Menu.Demo.slider }, kind: .slider(.global(WGSettingsUIDemoSettings.slider), range: 0.0 ... 100.0, step: 1.0, format: { value in
            return "\(Int(value))"
        })))
        WGMenuRegistry.register(WGMenuRow(id: "menuDemo.discrete", section: rows, order: 500, title: { WGStrings.Menu.Demo.discrete }, kind: .discreteChoice(.global(WGSettingsUIDemoSettings.discrete), options: [
            WGMenuChoiceOption(value: "off", title: { WGStrings.Menu.Demo.levelOff }),
            WGMenuChoiceOption(value: "medium", title: { WGStrings.Menu.Demo.levelMedium }),
            WGMenuChoiceOption(value: "high", title: { WGStrings.Menu.Demo.levelHigh })
        ])))
        WGMenuRegistry.register(WGMenuRow(id: "menuDemo.cards", section: rows, order: 600, title: { WGStrings.Menu.Demo.cards }, kind: .cards(.global(WGSettingsUIDemoSettings.cards), options: [
            WGMenuCardOption(value: "round", title: { WGStrings.Menu.Demo.shapeRound }, image: { theme in wgDemoCardImage("round", theme: theme) }),
            WGMenuCardOption(value: "squircle", title: { WGStrings.Menu.Demo.shapeSquircle }, image: { theme in wgDemoCardImage("squircle", theme: theme) }),
            WGMenuCardOption(value: "square", title: { WGStrings.Menu.Demo.shapeSquare }, image: { theme in wgDemoCardImage("square", theme: theme) })
        ])))
        WGMenuRegistry.register(WGMenuRow(id: "menuDemo.group", section: rows, order: 700, title: { WGStrings.Menu.Demo.group }, kind: .expandableGroup(master: .global(WGSettingsUIDemoSettings.group), children: [
            WGMenuRow(id: "menuDemo.groupFirst", section: rows, order: 100, title: { WGStrings.Menu.Demo.groupFirst }, kind: .toggle(.global(WGSettingsUIDemoSettings.groupFirst))),
            WGMenuRow(id: "menuDemo.groupSecond", section: rows, order: 200, title: { WGStrings.Menu.Demo.groupSecond }, kind: .toggle(.global(WGSettingsUIDemoSettings.groupSecond))),
            WGMenuRow(id: "menuDemo.groupThird", section: rows, order: 300, title: { WGStrings.Menu.Demo.groupThird }, kind: .toggle(.global(WGSettingsUIDemoSettings.groupThird)))
        ])))
        WGMenuRegistry.register(WGMenuRow(id: "menuDemo.list", section: rows, order: 750, title: { WGStrings.Menu.Demo.list }, kind: .expandableList(children: [
            WGMenuRow(id: "menuDemo.listFirst", section: rows, order: 100, title: { WGStrings.Menu.Demo.groupFirst }, kind: .toggle(.global(WGSettingsUIDemoSettings.listFirst))),
            WGMenuRow(id: "menuDemo.listSecond", section: rows, order: 200, title: { WGStrings.Menu.Demo.groupSecond }, kind: .toggle(.global(WGSettingsUIDemoSettings.listSecond))),
            WGMenuRow(id: "menuDemo.listThird", section: rows, order: 300, title: { WGStrings.Menu.Demo.groupThird }, kind: .toggle(.global(WGSettingsUIDemoSettings.listThird)))
        ], summary: { count in
            return WGStrings.Menu.Demo.listCount(selected: "\(count.selected)", total: "\(count.total)")
        })))
        WGMenuRegistry.register(WGMenuRow(id: "menuDemo.action", section: rows, order: 800, title: { WGStrings.Menu.Demo.action }, icon: .bundle("Chat/Context Menu/Info"), kind: .action({ context in
            context.presentToast(WGStrings.Menu.Demo.actionDone)
        })))

        WGMenuRegistry.register(WGMenuRow(id: "menuDemo.restart", section: more, order: 100, title: { WGStrings.Menu.Demo.restart }, kind: .toggle(.global(WGSettingsUIDemoSettings.restart))))
        WGMenuRegistry.register(WGMenuRow(id: "menuDemo.accountToggle", section: more, order: 200, title: { WGStrings.Menu.Demo.accountToggle }, subtitle: { WGStrings.Menu.Demo.accountToggleInfo }, kind: .toggle(.account(WGSettingsUIDemoSettings.accountToggle))))
        WGMenuRegistry.register(WGMenuRow(id: "menuDemo.dependent", section: more, order: 300, title: { WGStrings.Menu.Demo.dependent }, kind: .action({ context in
            context.presentToast(WGStrings.Menu.Demo.actionDone)
        }), isVisible: { _ in
            return WGSettingsUIDemoSettings.toggle.value
        }))
        WGMenuRegistry.register(WGMenuRow(id: "menuDemo.custom", section: more, order: 400, title: { WGStrings.Menu.Demo.custom }, kind: .custom({ context in
            return ItemListTextItem(presentationData: context.itemListPresentationData, text: .plain(WGStrings.Menu.Demo.custom), sectionId: context.sectionId)
        })))

        WGMenuRegistry.register(WGMenuRow(id: "menuDemo.segmentToggle", section: second, order: 100, title: { WGStrings.Menu.Demo.segmentToggle }, kind: .toggle(.global(WGSettingsUIDemoSettings.segmentToggle))))
    }
}
