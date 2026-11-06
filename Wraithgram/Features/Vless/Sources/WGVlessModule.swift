import Foundation
import Display
import SwiftSignalKit
import AccountContext
import WGCore
import WGHooks
import WGSettingsUI
import WGFeaturesShared

/// Entry point of the WGVless feature module («Ещё › VPN по подписке»). Owner: W3-5.
public enum WGVlessModule {
    static let serversTab = WGMenuTabID("vless.servers")
    static let mainSection = WGMenuSectionID("vless.main")
    static let optionsSection = WGMenuSectionID("vless.options")

    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `WGFeatures.registerAll()`, before `WGHookRegistry.freeze()`.
    public static func register() {
        WGVlessSettings.declare()
        let _ = WGVlessLegacy.loopbackPort

        WGVlessModule.registerMenu()

        // «О приложении › Сторонние компоненты» (requests/W3-5.md R5): the core is Xray-core
        // (MPL-2.0) with its Go dependencies (BSD / MIT / Apache-2.0); listed only in builds that
        // carry the core.
        WGMenuRegistry.register(license: WGMenuLicense(
            id: "vless.xrayCore",
            name: "Xray-core",
            license: "MPL-2.0",
            url: "https://github.com/XTLS/Xray-core",
            note: { WGStrings.Vless.License.note },
            order: 100,
            isVisible: {
                return WGXrayCore.isBundled
            }
        ))

        WGLifecycleHooks.rootControllersDidLoad.register({ context, _ in
            WGVlessController.shared.attach(context: context)
        }, order: 0)

        // Telegram's proxy screen links here: with the VPN on, Telegram's proxy is the core's loopback
        // entry, which that screen does not list.
        WGVpnEntryPoint.makeScreen = { context in
            guard let context = context as? AccountContext else {
                return nil
            }
            return wgVlessMakeServersController(context: context)
        }
        WGVpnEntryPoint.stateText = {
            if !WGXrayCore.isBundled {
                return WGStrings.Vless.ProxyEntry.notBundled
            }
            return WGVlessSettings.enabled.value ? WGStrings.Vless.ProxyEntry.on : WGStrings.Vless.ProxyEntry.off
        }

        WGVlessLegacy.registerMigration()

        // Starts the core in the background if the VPN was on (nothing is loaded otherwise).
        WGVlessController.shared.setup()
    }

    private static func registerMenu() {
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(
            id: WGVlessModule.mainSection,
            screen: .tab(.moreVpn),
            order: 300,
            footer: { _ in
                return WGXrayCore.isBundled ? nil : WGStrings.Vless.Status.notBundled
            }
        ))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(
            id: WGVlessModule.optionsSection,
            screen: .tab(.moreVpn),
            order: 400,
            footer: { _ in WGStrings.Vless.Menu.footer }
        ))

        WGMenuRegistry.register(WGMenuRow(
            id: "vless.enabled",
            section: WGVlessModule.mainSection,
            order: 100,
            title: { WGStrings.Vless.Menu.enable },
            subtitle: { WGStrings.Vless.Menu.enableInfo },
            kind: .toggle(.global(WGVlessSettings.enabled)),
            searchKeywords: { [WGStrings.Vless.Menu.keywords] },
            isEnabled: { _ in
                // Switching on needs the core in this build and a chosen server; switching off is
                // always possible.
                if WGVlessSettings.enabled.value {
                    return true
                }
                return WGXrayCore.isBundled && !WGVlessSettings.selectedServer.value.isEmpty
            }
        ))

        WGMenuRegistry.register(
            tab: WGMenuTabDescriptor(
                id: WGVlessModule.serversTab,
                parent: .tab(.moreVpn),
                title: { WGStrings.Vless.Menu.servers },
                makeScreen: { context in
                    return wgVlessMakeServersController(context: context.context)
                },
                searchKeywords: { [WGStrings.Vless.Menu.keywords] }
            ),
            linkIn: WGVlessModule.mainSection,
            order: 200,
            subtitle: { WGStrings.Vless.Menu.serversInfo },
            icon: .bundle("Chat/Context Menu/Globe"),
            label: { _ in
                let id = WGVlessSettings.selectedServer.value
                if id.isEmpty {
                    return WGStrings.Vless.Menu.noServer
                }
                return WGVlessStore.shared.server(id: id)?.1.name
            }
        )

        WGMenuRegistry.register(WGMenuRow(
            id: "vless.proxyBypassOnVpn",
            section: WGVlessModule.optionsSection,
            order: 100,
            title: { WGStrings.Vless.Menu.bypass },
            subtitle: { WGStrings.Vless.Menu.bypassInfo },
            kind: .toggle(.global(WGNetworkSpoofSharedSettings.proxyBypassOnVpn))
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "vless.sendHwid",
            section: WGVlessModule.optionsSection,
            order: 200,
            title: { WGStrings.Vless.Menu.hwid },
            subtitle: { WGStrings.Vless.Menu.hwidInfo },
            kind: .toggle(.global(WGVlessSettings.sendHwid))
        ))
    }
}
