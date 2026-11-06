import Foundation
import CFNetwork
import Network
import SwiftSignalKit
import TelegramCore
import WGCore

// The part of the network zone that the extensions also link: «Не использовать прокси с VPN» and the
// identity of the VLESS core's loopback proxy. Both are read by `ProxySettings.effectiveActiveServer`,
// which runs in the app, the notification service and the share extension alike, so the settings
// live in the App Group and the decision is a snapshot read (no system call per layout).

public enum WGNetworkSpoofSharedSettings {
    /// «Не использовать прокси с VPN»: while the system reports a VPN, Telegram connects directly.
    public static let proxyBypassOnVpn = WGSetting<Bool>("networkSpoof.proxyBypassOnVpn", default: false, scope: .appGroup, flags: [.extensions])
    /// Port of the VLESS core's local SOCKS5 listener (0 = the core is not configured). Service state.
    public static let vlessLocalPort = WGSetting<Int>("vless.localPort", default: 0, scope: .appGroup, flags: [.extensions, .noExport])
}

public enum WGNetworkSpoofShared {
    /// Called from `WGFeaturesShared.registerForApp()` and `.registerForExtension()`; check
    /// `WGCore.environment?.process` for what only one of them needs.
    public static func register() {
        let _ = WGNetworkSpoofSharedSettings.proxyBypassOnVpn
        let _ = WGNetworkSpoofSharedSettings.vlessLocalPort

        WGNetworkHooks.useProxy.register({ server in
            return WGSystemVPNMonitor.shared.shouldUseProxy(server)
        }, order: 0)
        WGSystemVPNMonitor.shared.start()
    }

    /// The loopback entry the VLESS core is reached through (never bypassed, never shown as a user proxy).
    public static func isVlessLoopback(_ server: ProxyServerSettings) -> Bool {
        let port = WGNetworkSpoofSharedSettings.vlessLocalPort.value
        if port <= 0 {
            return false
        }
        return server.host == WGNetworkSpoofShared.loopbackHost && Int(server.port) == port
    }

    public static let loopbackHost = "127.0.0.1"
}

/// The way from Telegram's own proxy screen to «VPN по подписке». The proxy screen (SettingsUI) sits
/// below WGVless, so WGVless fills these at launch (app only; they stay nil in the extensions).
/// Arguments and results are type-erased because this module sits below AccountContext and Display.
public enum WGVpnEntryPoint {
    /// Builds the VPN screen: takes an `AccountContext`, returns a `ViewController`. Main thread.
    public static var makeScreen: ((AnyObject) -> AnyObject?)?
    /// Short state for the row's label (on / off / no core). Main thread, snapshot reads only.
    public static var stateText: (() -> String)?
}

/// Tracks whether the system has a VPN up. Re-evaluated only when the network path changes
/// (NWPathMonitor, event driven) or the setting is switched; `effectiveActiveServer` reads the cached flag.
public final class WGSystemVPNMonitor {
    public static let shared = WGSystemVPNMonitor()

    private let queue = DispatchQueue(label: "org.wraithgram.network.vpn", qos: .utility)
    private var lock = os_unfair_lock()
    private var vpnActive = false
    private var monitor: NWPathMonitor?
    private var settingDisposable: Disposable?

    private init() {
    }

    /// Main thread, from `register()`.
    func start() {
        if self.settingDisposable != nil {
            return
        }
        let isApp = WGCore.environment?.process.isApp ?? false
        if !isApp {
            // Extensions live for seconds and only read settings: decide once, nothing to watch.
            if WGNetworkSpoofSharedSettings.proxyBypassOnVpn.value {
                self.store(WGSystemVPNMonitor.detectVPN())
            }
            return
        }
        if WGNetworkSpoofSharedSettings.proxyBypassOnVpn.value {
            // The first network may start before the path monitor answers: decide once, synchronously.
            self.store(WGSystemVPNMonitor.detectVPN())
            self.startMonitor()
        }
        // A VPN switched in Settings while the app was suspended: the path monitor reports the change
        // when the app runs again, and this throttled check on return covers a missed one.
        WGForegroundTaskScheduler.shared.register(id: "networkSpoof.vpnCheck", minimumInterval: 30.0, delay: 1.0, task: { [weak self] done in
            guard let self, WGNetworkSpoofSharedSettings.proxyBypassOnVpn.value else {
                done()
                return EmptyDisposable
            }
            self.queue.async {
                self.update(WGSystemVPNMonitor.detectVPN())
                done()
            }
            return EmptyDisposable
        })
        self.settingDisposable = (WGNetworkSpoofSharedSettings.proxyBypassOnVpn.signal
        |> distinctUntilChanged
        |> deliverOnMainQueue).start(next: { [weak self] enabled in
            guard let self else {
                return
            }
            if enabled {
                self.startMonitor()
                self.queue.async {
                    self.update(WGSystemVPNMonitor.detectVPN())
                }
            } else {
                self.stopMonitor()
            }
            WGNetworkHooks.proxyPolicyDidChange()
        })
    }

    /// The answer of the `useProxy` point (nil = no opinion).
    func shouldUseProxy(_ server: ProxyServerSettings) -> Bool? {
        if !WGNetworkSpoofSharedSettings.proxyBypassOnVpn.value {
            return nil
        }
        if WGNetworkSpoofShared.isVlessLoopback(server) {
            // The VLESS core is the user's own tunnel, not a proxy to skip.
            return nil
        }
        os_unfair_lock_lock(&self.lock)
        let active = self.vpnActive
        os_unfair_lock_unlock(&self.lock)
        return active ? false : nil
    }

    public var isVPNActive: Bool {
        os_unfair_lock_lock(&self.lock)
        let active = self.vpnActive
        os_unfair_lock_unlock(&self.lock)
        return active
    }

    private func startMonitor() {
        if self.monitor != nil {
            return
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            guard let self else {
                return
            }
            self.update(WGSystemVPNMonitor.detectVPN())
        }
        monitor.start(queue: self.queue)
        self.monitor = monitor
    }

    private func stopMonitor() {
        self.monitor?.cancel()
        self.monitor = nil
    }

    private func store(_ value: Bool) {
        os_unfair_lock_lock(&self.lock)
        self.vpnActive = value
        os_unfair_lock_unlock(&self.lock)
    }

    private func update(_ value: Bool) {
        os_unfair_lock_lock(&self.lock)
        let changed = self.vpnActive != value
        self.vpnActive = value
        os_unfair_lock_unlock(&self.lock)
        if changed {
            WGNetworkHooks.proxyPolicyDidChange()
        }
    }

    /// A VPN shows up as a scoped network service on a tunnel interface.
    static func detectVPN() -> Bool {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return false
        }
        guard let scoped = settings["__SCOPED__"] as? [String: Any] else {
            return false
        }
        let prefixes = ["utun", "ipsec", "ppp", "tap", "tun"]
        for name in scoped.keys {
            for prefix in prefixes where name.hasPrefix(prefix) {
                return true
            }
        }
        return false
    }
}
