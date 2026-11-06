import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import WGCore
import WGHooks
import WGSettingsUI

/// Entry point of the WGNetworkSpoof feature module («Приватность › Подмены»). Owner: W3-5.
public enum WGNetworkSpoofModule {
    static let phoneTab = WGMenuTabID("networkSpoof.phone")
    static let profilesTab = WGMenuTabID("networkSpoof.profiles")

    /// Declares settings, menu rows, hook handlers and migrations. Called once on the main
    /// thread from `WGFeatures.registerAll()`, before `WGHookRegistry.freeze()`.
    public static func register() {
        WGNetworkSpoofSettings.declare()

        // Own number, on this device only. Hiding the number (W2-1, order 0) wins over replacing it.
        WGPeerInfoHooks.displayedPhoneNumber.register({ request in
            guard request.isAccountPeer else {
                return nil
            }
            let account = request.context.account.id.wg
            guard WGNetworkSpoofSettings.fakePhoneEnabled.value(for: account) else {
                return nil
            }
            let number = WGNetworkSpoofSettings.fakePhone.value(for: account)
            if number.isEmpty {
                return nil
            }
            return .replaced(number)
        }, order: 100)

        // Profile substitution: the whole target peer (namespace included) is opened, so the
        // profile's chat location, shared media and actions all belong to the target.
        WGPeerInfoHooks.redirectPeer.register({ context, peerId in
            if peerId == context.account.peerId {
                return nil
            }
            let account = context.account.id.wg
            guard WGNetworkSpoofSettings.profileRedirectEnabled.value(for: account) else {
                return nil
            }
            guard let target = WGNetworkSpoofSettings.profileRedirects.value(for: account)[peerId.wgKey.stringValue] else {
                return nil
            }
            let targetId = PeerId(wgKey: target)
            return targetId == peerId ? nil : targetId
        }, order: 0)

        WGNetworkSpoofModule.registerMenu()
        WGNetworkSpoofMigrations.register()
    }

    private static func registerMenu() {
        WGMenuRegistry.register(
            tab: WGMenuTabDescriptor(
                id: WGNetworkSpoofModule.phoneTab,
                parent: .tab(.privacySpoofing),
                title: { WGStrings.NetworkSpoof.Phone.title },
                makeScreen: { context in
                    return wgSpoofMakePhoneController(context: context.context)
                },
                searchKeywords: { [WGStrings.NetworkSpoof.Phone.keywords] }
            ),
            linkIn: .main(of: .privacySpoofing),
            order: 200,
            subtitle: { WGStrings.NetworkSpoof.Phone.info },
            icon: .bundle("Chat/Context Menu/Call"),
            label: { context in
                return WGNetworkSpoofSettings.fakePhoneEnabled.value(for: context.accountID) ? WGStrings.NetworkSpoof.Menu.on : WGStrings.NetworkSpoof.Menu.off
            }
        )
        WGMenuRegistry.register(
            tab: WGMenuTabDescriptor(
                id: WGNetworkSpoofModule.profilesTab,
                parent: .tab(.privacySpoofing),
                title: { WGStrings.NetworkSpoof.Profiles.title },
                makeScreen: { context in
                    return wgSpoofMakeProfilesController(context: context.context)
                },
                searchKeywords: { [WGStrings.NetworkSpoof.Profiles.keywords] }
            ),
            linkIn: .main(of: .privacySpoofing),
            order: 300,
            subtitle: { WGStrings.NetworkSpoof.Profiles.info },
            icon: .bundle("Chat/Context Menu/User"),
            label: { context in
                return WGNetworkSpoofSettings.profileRedirectEnabled.value(for: context.accountID) ? WGStrings.NetworkSpoof.Menu.on : WGStrings.NetworkSpoof.Menu.off
            }
        )
    }
}
