import Foundation
import UIKit
import Display
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountContext
import PromptUI
import WGCore
import WGSettingsUI
import WGFeaturesShared

/// The profile the hyperlink stage links to. It is resolved when it is set: only a user this
/// account can see is accepted (a mention of an unknown user is dropped by Telegram silently when
/// the message is serialized), so a link never disappears without the user knowing.
enum WGHyperlinkTarget {
    private static var titles: [WGPeerKey: String] = [:]

    static func label(menuContext: WGMenuContext) -> String {
        guard let key = WGMessagesSettings.hyperlinkTarget.value(for: menuContext.accountID) else {
            return WGStrings.Sending.Menu.hyperlinkTargetNone
        }
        if let title = WGHyperlinkTarget.titles[key] {
            return title
        }
        let context = menuContext.context
        let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: PeerId(wgKey: key)))
        |> deliverOnMainQueue).start(next: { peer in
            if let peer {
                WGHyperlinkTarget.titles[key] = peer.debugDisplayTitle
            }
        })
        return "\(key.id)"
    }

    static func edit(menuContext: WGMenuContext) {
        let context = menuContext.context
        let accountId = menuContext.accountID
        let current = WGMessagesSettings.hyperlinkTarget.value(for: accountId).map { "\($0.id)" }
        let controller = promptController(context: context, text: WGStrings.Sending.Hyperlink.promptTitle, subtitle: WGStrings.Sending.Hyperlink.promptText, value: current, characterLimit: 64, apply: { value in
            guard let value else {
                return
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                WGMessagesSettings.hyperlinkTarget.set(nil, for: accountId)
                return
            }
            WGHyperlinkTarget.resolve(trimmed, context: context, completion: { peer in
                guard let peer else {
                    menuContext.presentToast(WGStrings.Sending.Hyperlink.notFound)
                    return
                }
                guard case .user = peer else {
                    menuContext.presentToast(WGStrings.Sending.Hyperlink.notUser)
                    return
                }
                WGHyperlinkTarget.titles[peer.id.wgKey] = peer.debugDisplayTitle
                WGMessagesSettings.hyperlinkTarget.set(peer.id.wgKey, for: accountId)
            })
        })
        menuContext.present(controller)
    }

    private static func resolve(_ text: String, context: AccountContext, completion: @escaping (EnginePeer?) -> Void) {
        var value = text
        if value.hasPrefix("@") {
            value.removeFirst()
        }
        if let id = Int64(value), id > 0 {
            let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(id))
            let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
            |> deliverOnMainQueue).start(next: { peer in
                completion(peer)
            })
            return
        }
        let _ = (context.engine.peers.resolvePeerByName(name: value, referrer: nil)
        |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
            guard case let .result(peer) = result else {
                return .complete()
            }
            return .single(peer)
        }
        |> take(1)
        |> deliverOnMainQueue).start(next: { peer in
            completion(peer)
        })
    }
}
