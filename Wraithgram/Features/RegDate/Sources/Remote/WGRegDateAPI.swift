import Foundation
import SwiftSignalKit
import WGCore

/// The remote source of registration dates, Swiftgram's `SGAPI.getSGAPIRegDate` in Wraithgram's
/// architecture: one `GET`, through `WGNetwork` (ephemeral session, the user's SOCKS5 proxy, nothing
/// sent while an MTProxy / WEB proxy is on), 10 s like Swiftgram.
///
/// **Off:** there is no address. Swiftgram's server and its `@SwiftgramBot` token are not used
/// (owner's decision 2026-11-01, inventory 1.3 C3), so with `baseURL == nil` no request is ever made.
/// A server the owner gives later is set here; the contract is `WGRegDateRemoteResponse`. Such a
/// server learns the ID of every profile opened, which the explanation then says.
enum WGRegDateAPI {
    /// The server's base address (`https://…`); nil = the source is off.
    static let baseURL: URL? = nil
    /// DeviceCheck / App Attest are not done now, so there are none.
    static let credentials = WGRegDateAPICredentials.none
    static let requestTimeout: Double = 10.0
    static let maxResponseBytes = 4096

    static var isEnabled: Bool {
        return WGRegDateAPI.baseURL != nil
    }

    /// The answer for `userId`, nil on any failure. Without an address: nil at once, no network.
    static func fetch(userId: Int64, now: Int32) -> Signal<WGRegDateRemoteEntry?, NoError> {
        guard let baseURL = WGRegDateAPI.baseURL, userId > 0 else {
            return .single(nil)
        }
        // `WGNetwork` sends no custom headers yet (requests/W7-RD2.md): a server that needs
        // credentials is not asked rather than asked without them.
        if !WGRegDateAPI.credentials.headers.isEmpty {
            return .single(nil)
        }
        let request = WGNetworkRequest(url: WGRegDateRemoteResponse.url(base: baseURL, userId: userId), maxBytes: WGRegDateAPI.maxResponseBytes)
        return WGNetwork.shared.fetch(request)
        |> map { response -> WGRegDateRemoteEntry? in
            guard let data = response.data else {
                return nil
            }
            return WGRegDateRemoteResponse.parse(data, now: now, fetched: now)
        }
        |> `catch` { _ -> Signal<WGRegDateRemoteEntry?, NoError> in
            return .single(nil)
        }
        |> timeout(WGRegDateAPI.requestTimeout, queue: Queue.concurrentDefaultQueue(), alternate: .single(nil))
    }
}
