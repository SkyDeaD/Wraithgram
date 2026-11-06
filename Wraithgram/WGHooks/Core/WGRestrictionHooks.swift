// Compiled into TelegramCore (filegroup //Wraithgram/WGHooks:TelegramCoreHookSources).
// Server-imposed restrictions that features may relax on this device: copy protection,
// platform restriction texts (bots/channels), the right to write to a chat, the screenshot
// notice in secret chats. Each predicate is answered once at the source, so every screen that
// asks the same question gets the same answer (no copies of the check in the UI).
// The answers are read on hot paths (cells): handlers must read in-memory snapshots only.

import Foundation
import Postbox
import WGCore

public enum WGCopyProtectionSubject {
    /// `Peer.isCopyProtectionEnabled` (groups and channels).
    case peer(Peer)
    /// `Message.isCopyProtected()`.
    case message(Message)
    /// `TelegramEngine.EngineData.Item.Peer.CopyProtectionEnabled` (incl. private chats).
    case peerData(PeerId)
}

public enum WGRestrictionHooks {
    /// Policy: `false` lifts copy protection for the subject (forward, save, copy, screenshots
    /// of protected content); `true` forces it; nil = upstream.
    public static let copyProtection = WGHookPoint<(WGCopyProtectionSubject) -> Bool?>("restrictions.copyProtection")

    /// Policy: `false` ignores the peer's platform restriction ("This bot is unavailable…").
    public static let peerRestriction = WGHookPoint<(Peer) -> Bool?>("restrictions.peerRestriction")

    /// Policy for `canSendMessagesToPeer`: `true` lets the input panel open (e.g. the channel
    /// creator's local mode), `false` blocks it.
    public static let canSendMessages = WGHookPoint<(EnginePeer) -> Bool?>("restrictions.canSendMessages")

    /// Policy: `false` = do not tell the other side of a secret chat about a screenshot.
    public static let reportScreenshot = WGHookPoint<(PeerId) -> Bool?>("restrictions.reportScreenshot")

    /// Policy: `false` = do not tell the sender about a screenshot of this self-destructing media
    /// (view once / timer media in its own viewer, cloud and secret chats). Asked after
    /// `reportScreenshot`, through `shouldReportScreenshot(peerId:message:)`.
    public static let reportMediaScreenshot = WGHookPoint<(Message) -> Bool?>("restrictions.reportMediaScreenshot")

    /// Policy: `false` = this self-destructing media (view once, or a timer of a minute or less on a
    /// photo, video or voice) is shown as ordinary media: `Message.containsSecretMedia` is false and
    /// `minAutoremoveOrClearTimeout` nil, so the bubble has no blur, it opens in the regular gallery
    /// and the menus offer what they offer for any media. Asked only for such messages
    /// (`wgRawContainsSecretMedia`), on hot paths (cells); nil = upstream. TelegramCore's own
    /// read/consume logic always uses the raw values (`wgRawContainsSecretMedia`,
    /// `wgRawMinAutoremoveOrClearTimeout`); a handler must use them too.
    public static let secretMediaDisplay = WGHookPoint<(Message) -> Bool?>("restrictions.secretMediaDisplay")

    /// Policy: `false` ignores a message's platform restriction (`RestrictedContentMessageAttribute`).
    /// Asked by `RestrictedContentMessageAttribute.platformText` (PlatformRestrictionMatching), which
    /// every reader of the restriction text goes through — the bubble, copy, previews, sharing — and
    /// so by `EngineRawMessage.restrictionReason` too. The message is nil where only the attribute is
    /// at hand (`platformText`).
    public static let messageRestriction = WGHookPoint<(Message?) -> Bool?>("restrictions.messageRestriction")

    /// For call sites outside TelegramCore (PlatformRestrictionMatching).
    public static func messageRestrictionApplies(_ message: Message?) -> Bool {
        if WGRestrictionHooks.messageRestriction.isEmpty {
            return true
        }
        for handler in WGRestrictionHooks.messageRestriction.handlers {
            if let value = handler(message) {
                return value
            }
        }
        return true
    }

    /// A chat's copy protection read from raw flags outside TelegramCore (a private chat's
    /// `CachedUserData`): the same answer `EngineData…Peer.CopyProtectionEnabled` gives (`.peerData`).
    public static func peerCopyProtectionApplies(_ upstreamValue: Bool, peerId: PeerId) -> Bool {
        if let value = wgCopyProtectionOverride(.peerData(peerId)) {
            return value
        }
        return upstreamValue
    }

    /// For the media viewers outside TelegramCore (GalleryUI): whether a screenshot of `message`
    /// (if known) in the chat `peerId` is reported to the other side.
    public static func shouldReportScreenshot(peerId: PeerId, message: Message?) -> Bool {
        if !wgShouldReportScreenshot(peerId: peerId) {
            return false
        }
        guard let message, !WGRestrictionHooks.reportMediaScreenshot.isEmpty else {
            return true
        }
        for handler in WGRestrictionHooks.reportMediaScreenshot.handlers {
            if let value = handler(message) {
                return value
            }
        }
        return true
    }
}

func wgCopyProtectionOverride(_ subject: WGCopyProtectionSubject) -> Bool? {
    if WGRestrictionHooks.copyProtection.isEmpty {
        return nil
    }
    for handler in WGRestrictionHooks.copyProtection.handlers {
        if let value = handler(subject) {
            return value
        }
    }
    return nil
}

/// `Message.containsSecretMedia` / `minAutoremoveOrClearTimeout`: a feature shows this message's
/// self-destructing media as ordinary media (`WGRestrictionHooks.secretMediaDisplay`).
/// `isSecretMedia`: `wgRawContainsSecretMedia` when the caller has it already.
func wgShowsSecretMediaAsRegular(_ message: Message, isSecretMedia: Bool? = nil) -> Bool {
    if WGRestrictionHooks.secretMediaDisplay.isEmpty {
        return false
    }
    guard isSecretMedia ?? message.wgRawContainsSecretMedia else {
        return false
    }
    for handler in WGRestrictionHooks.secretMediaDisplay.handlers {
        if let value = handler(message) {
            return !value
        }
    }
    return false
}

func wgPeerRestrictionApplies(_ peer: Peer) -> Bool {
    if WGRestrictionHooks.peerRestriction.isEmpty {
        return true
    }
    for handler in WGRestrictionHooks.peerRestriction.handlers {
        if let value = handler(peer) {
            return value
        }
    }
    return true
}

func wgCanSendMessagesOverride(_ peer: EnginePeer) -> Bool? {
    if WGRestrictionHooks.canSendMessages.isEmpty {
        return nil
    }
    for handler in WGRestrictionHooks.canSendMessages.handlers {
        if let value = handler(peer) {
            return value
        }
    }
    return nil
}

func wgShouldReportScreenshot(peerId: PeerId) -> Bool {
    if WGRestrictionHooks.reportScreenshot.isEmpty {
        return true
    }
    for handler in WGRestrictionHooks.reportScreenshot.handlers {
        if let value = handler(peerId) {
            return value
        }
    }
    return true
}
