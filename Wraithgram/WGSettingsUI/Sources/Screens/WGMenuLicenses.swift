import Foundation
import UIKit
import Display
import AccountContext
import WGCore

/// A third-party component bundled with Wraithgram (a library), listed on «О приложении › Сторонние
/// компоненты» with its license. Registered by the feature that ships it. Fonts are not among them:
/// Wraithgram uses only the fonts of iOS (owner decision 2026-10-22).
public struct WGMenuLicense {
    /// Unique, "<feature>.<component>".
    public let id: String
    /// Proper names, shown as is in every language («Xray-core»).
    public let name: String
    /// SPDX identifier(s) («MPL-2.0»), shown on the right.
    public let license: String
    /// The license text or the component's source, opened on tap.
    public let url: String
    /// What it is in Wraithgram, localized at display time («Ядро «VPN по подписке»»).
    public let note: (() -> String)?
    /// Sparse, step 100.
    public let order: Int
    /// nil = always; e.g. only when the component is in this build.
    public let isVisible: (() -> Bool)?

    public init(id: String, name: String, license: String, url: String, note: (() -> String)? = nil, order: Int, isVisible: (() -> Bool)? = nil) {
        self.id = id
        self.name = name
        self.license = license
        self.url = url
        self.note = note
        self.order = order
        self.isVisible = isVisible
    }
}

extension WGMenuTabID {
    /// «О приложении › Сторонние компоненты» (shown once a feature registered a component).
    public static let moreAboutThirdParty = WGMenuTabID("more.about.thirdParty")
}

extension WGMenuSectionID {
    public static let aboutThirdPartyComponents = WGMenuSectionID("more.about.thirdParty.components")
}

/// The tab and its section; called from `WGSettingsUI.register()` before the features.
func wgRegisterLicensesTab() {
    WGMenuRegistry.register(
        tab: WGMenuTabDescriptor(
            id: .moreAboutThirdParty,
            parent: .tab(.moreAbout),
            title: { WGStrings.Menu.About.thirdParty },
            searchKeywords: { [WGStrings.Menu.About.licenseHeader] }
        ),
        linkIn: .aboutLicense,
        order: 200,
        subtitle: { WGStrings.Menu.About.thirdPartyInfo },
        icon: .bundle("Chat/Context Menu/Info")
    )
    WGMenuRegistry.register(section: WGMenuSectionDescriptor(
        id: .aboutThirdPartyComponents,
        screen: .tab(.moreAboutThirdParty),
        order: 300,
        footer: { _ in WGStrings.Menu.About.thirdPartyFooter }
    ))
}

func wgRegisterLicense(_ license: WGMenuLicense) {
    let url = license.url
    let licenseName = license.license
    var isVisible: ((WGMenuContext) -> Bool)?
    if let visible = license.isVisible {
        isVisible = { _ in
            return visible()
        }
    }
    WGMenuRegistry.register(WGMenuRow(
        id: "menu.license.\(license.id)",
        section: .aboutThirdPartyComponents,
        order: license.order,
        title: { license.name },
        subtitle: license.note,
        kind: .action({ menuContext in
            menuContext.context.sharedContext.applicationBindings.openUrl(url)
        }),
        isVisible: isVisible,
        searchKeywords: { [licenseName] },
        label: { _ in licenseName }
    ))
}
