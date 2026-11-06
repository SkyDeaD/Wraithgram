import Foundation
import TelegramCore
import WGCore
import WGFeaturesShared

// Settings of «VPN по подписке». Global: Telegram's proxy is shared by every account of the app.
// The loopback port is in WGFeaturesShared (the extensions must recognise the loopback entry).

public struct WGVlessSavedProxy: Codable, Equatable, WGSettingValue {
    public var enabled: Bool
    public var activeServer: ProxyServerSettings?

    public init(enabled: Bool, activeServer: ProxyServerSettings?) {
        self.enabled = enabled
        self.activeServer = activeServer
    }
}

public enum WGVlessSettings {
    public static let enabled = WGSetting<Bool>("vless.enabled", default: false)
    /// Identity of the chosen server (`WGVlessServer.id`), "" = none.
    public static let selectedServer = WGSetting<String>("vless.selectedServer", default: "")
    /// Send a random installation id (`x-hwid`) with subscription requests. Off: panels that limit
    /// devices by it will refuse; the user decides.
    public static let sendHwid = WGSetting<Bool>("vless.sendHwid", default: false)
    /// The random id itself, created on first use. Never derived from the device.
    public static let hwid = WGSetting<String>("vless.hwid", default: "", flags: [.noExport])
    /// Telegram's proxy state before the VPN took it over, restored when the VPN is switched off.
    public static let previousProxy = WGSetting<WGVlessSavedProxy?>("vless.previousProxy", default: nil, flags: [.noExport])
    /// Credentials of the loopback SOCKS5 listener (the same pair is in Telegram's proxy entry).
    public static let inboundUser = WGSetting<String>("vless.inboundUser", default: "", flags: [.noExport])
    public static let inboundPassword = WGSetting<String>("vless.inboundPassword", default: "", flags: [.noExport])

    static func declare() {
        let _ = WGVlessSettings.enabled
        let _ = WGVlessSettings.selectedServer
        let _ = WGVlessSettings.sendHwid
        let _ = WGVlessSettings.hwid
        let _ = WGVlessSettings.previousProxy
        let _ = WGVlessSettings.inboundUser
        let _ = WGVlessSettings.inboundPassword
    }

    /// The installation id for `x-hwid`, created when first needed.
    static func installationId() -> String {
        let current = WGVlessSettings.hwid.value
        if !current.isEmpty {
            return current
        }
        let value = UUID().uuidString
        WGVlessSettings.hwid.set(value)
        return value
    }
}
