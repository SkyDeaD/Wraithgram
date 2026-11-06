import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import WGCore

// Handlers for the two points of requests/W4-1.md R2 (added by W4-R, Wraithgram/WGHooks/Core/WGGiftHooks.swift):
//   - `WGGiftHooks.hasLocalGifts` — the own profile shows its "Gifts" tab when it has only fake
//     gifts (the tab is decided in the frozen PeerInfoData.swift from the server's gift count);
//   - `WGGiftHooks.invalidate()` — an open own profile re-publishes its gift list after a fake gift
//     was added, edited or deleted (otherwise it updates on its next page load).

enum WGFakeGiftsPendingPoints {
    static func register() {
        WGGiftHooks.hasLocalGifts.register({ account, peerId in
            guard WGFakeGiftsSettings.isEnabled.value, peerId == account.peerId else {
                return false
            }
            return !WGFakeGiftsStore.shared.resolvedGifts(accountPeerId: peerId).isEmpty
        })
    }

    /// The store published a new list for an account.
    static func storeDidChange() {
        WGGiftHooks.invalidate()
    }
}
