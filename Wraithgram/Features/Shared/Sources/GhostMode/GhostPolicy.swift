import Foundation
import Postbox
import TelegramCore
import WGCore

/// The parts of ghost mode that can be switched per function and per chat.
public enum WGGhostFunction {
    case readReceipts
    case storyViews
    case online
    case typing
}

/// Why a chat is (or is not) an exception.
public enum WGGhostExceptionSource: Equatable {
    case none
    /// An explicit entry in the chat list of exceptions.
    case explicit(WGGhostException)
    /// «Все каналы» / «Все группы».
    case type
    /// A folder chosen as an exception.
    case folder
    /// The chat's type or folder is an exception, but the chat was pulled back into ghost mode.
    case forced
}

/// Ghost mode resolved for one account. Every answer is computed from the settings snapshot of
/// WGCore (no disk, no UserDefaults, no JSON) plus the in-memory peer kinds, so it may be asked on
/// any queue, inside Postbox transactions included.
public enum WGGhostPolicy {
    /// The master switch.
    public static func isEnabled(_ account: WGAccountID) -> Bool {
        return WGGhostSettings.isEnabled.value(for: account)
    }

    /// Whether the function is switched on for the account, regardless of chat.
    public static func isFunctionOn(_ function: WGGhostFunction, account: WGAccountID) -> Bool {
        if !WGGhostPolicy.isEnabled(account) {
            return false
        }
        switch function {
        case .readReceipts:
            return WGGhostSettings.hideReadReceipts.value(for: account)
        case .storyViews:
            return WGGhostSettings.hideStoryViews.value(for: account)
        case .online:
            return WGGhostSettings.hideOnline.value(for: account)
        case .typing:
            return WGGhostSettings.hideTyping.value(for: account)
        }
    }

    /// Explicit entry of a chat; a secret chat falls back to its user's entry.
    public static func explicitException(for peerId: PeerId, account: WGAccountID) -> WGGhostException? {
        let exceptions = WGGhostSettings.exceptions.value(for: account)
        if exceptions.isEmpty {
            return nil
        }
        if let exception = exceptions[peerId.wgGhostKey] {
            return exception
        }
        if peerId.namespace == Namespaces.Peer.SecretChat, case let .secretChat(user)? = WGGhostPeerTraits.shared.kind(of: peerId, account: account) {
            return exceptions[user.wgGhostKey]
        }
        return nil
    }

    /// Whether the chat's type or one of its folders is an exception.
    public static func isExceptedByTypeOrFolder(_ peerId: PeerId, account: WGAccountID) -> (byType: Bool, byFolder: Bool) {
        let allChannels = WGGhostSettings.exceptAllChannels.value(for: account)
        let allGroups = WGGhostSettings.exceptAllGroups.value(for: account)
        let folders = WGGhostSettings.exceptFolders.value(for: account)
        if !allChannels && !allGroups && folders.isEmpty {
            return (false, false)
        }
        let kind = WGGhostPeerTraits.shared.kind(of: peerId, account: account)
        var byType = false
        if let kind = kind {
            switch kind {
            case .channel:
                byType = allChannels
            case .basicGroup, .supergroup:
                byType = allGroups
            default:
                break
            }
        }
        let byFolder = WGGhostPeerTraits.shared.isInFolders(folders, peerId: peerId, kind: kind, account: account)
        return (byType, byFolder)
    }

    public static func exceptionSource(for peerId: PeerId, account: WGAccountID) -> WGGhostExceptionSource {
        let explicit = WGGhostPolicy.explicitException(for: peerId, account: account)
        if let explicit = explicit, explicit.kind == .exclude {
            return .explicit(explicit)
        }
        let (byType, byFolder) = WGGhostPolicy.isExceptedByTypeOrFolder(peerId, account: account)
        if !byType && !byFolder {
            return .none
        }
        if explicit?.kind == .include {
            return .forced
        }
        return byType ? .type : .folder
    }

    /// The exception that applies to the chat, nil when ghost mode applies in full.
    public static func effectiveException(for peerId: PeerId, account: WGAccountID) -> WGGhostException? {
        switch WGGhostPolicy.exceptionSource(for: peerId, account: account) {
        case .none, .forced:
            return nil
        case let .explicit(exception):
            return exception
        case .type, .folder:
            return .fullExclusion
        }
    }

    /// Whether ghost mode keeps `function` from the chat (`peerId == nil`: "any chat", i.e. the
    /// function itself).
    public static func hides(_ function: WGGhostFunction, peerId: PeerId?, account: WGAccountID) -> Bool {
        if !WGGhostPolicy.isFunctionOn(function, account: account) {
            return false
        }
        guard let peerId = peerId else {
            return true
        }
        guard let exception = WGGhostPolicy.effectiveException(for: peerId, account: account) else {
            return true
        }
        switch function {
        case .readReceipts:
            return !exception.readMessages
        case .storyViews:
            return !exception.readStories
        case .online:
            return !exception.showOnline
        case .typing:
            return !exception.showTyping
        }
    }

    /// Statuses still sent in the chat while «печатает» is hidden there.
    public static func shownActivities(for peerId: PeerId, account: WGAccountID) -> Set<WGGhostActivityKind> {
        if let exception = WGGhostPolicy.effectiveException(for: peerId, account: account), let own = exception.ownShownActivities {
            return Set(own)
        }
        var result = Set<WGGhostActivityKind>()
        for kind in WGGhostActivityKind.allCases where WGGhostSettings.shownActivity(kind).value(for: account) {
            result.insert(kind)
        }
        return result
    }

    /// «Читать при действиях» for the chat: the exception's own value, else the global switch. Only
    /// meaningful while ghost mode keeps read receipts there.
    public static func readsOnAction(in peerId: PeerId, account: WGAccountID) -> Bool {
        if let exception = WGGhostPolicy.effectiveException(for: peerId, account: account), let value = exception.readOnAction {
            return value
        }
        return WGGhostSettings.readOnAction.value(for: account)
    }
}

/// Send delay («Отложенная отправка»): the one decision every path uses — the stored sends and the
/// standalone senders (share extension, quick forward, Siri) ask the same `WGOutgoingHooks.sendDelay`.
public enum WGSendDelayPolicy {
    /// nil = send now. One delay for text and media. `peer` is the chat as stored (asked inside the
    /// transaction); only when Postbox does not know it does the peer kind cache decide «bot».
    public static func scheduleTime(account: WGAccountID, accountPeerId: PeerId, peerId: PeerId, peer: Peer?, serverTime: Double) -> Int32? {
        if !WGGhostSettings.sendDelayEnabled.value(for: account) {
            return nil
        }
        // «Избранное» is a notebook: a scheduled message there is a reminder, not a hidden send.
        if peerId == accountPeerId {
            return nil
        }
        // Secret chats can not schedule; bots refuse scheduled messages (SCHEDULE_BOT_NOT_ALLOWED).
        if peerId.namespace == Namespaces.Peer.SecretChat {
            return nil
        }
        if let peer {
            if let user = peer as? TelegramUser, user.botInfo != nil {
                return nil
            }
        } else if WGGhostPeerTraits.shared.isBot(peerId, account: account) {
            return nil
        }
        // The server sends at once anything scheduled less than ~10 s ahead: the range keeps a margin.
        let delay = WGSendDelaySeconds.clamped(WGGhostSettings.sendDelaySeconds.value(for: account))
        return Int32(serverTime + delay)
    }

    /// Whether a batch must go out as is: already scheduled, paid, or self-destructing. `attributes`
    /// — of every message of the batch.
    public static func mustSendImmediately(_ attributes: [[MessageAttribute]]) -> Bool {
        for messageAttributes in attributes {
            for attribute in messageAttributes {
                if attribute is OutgoingScheduleInfoMessageAttribute {
                    return true
                }
                if attribute is PaidStarsMessageAttribute {
                    return true
                }
                if let attribute = attribute as? AutoremoveTimeoutMessageAttribute, attribute.timeout == viewOnceTimeout {
                    return true
                }
                if let attribute = attribute as? AutoclearTimeoutMessageAttribute, attribute.timeout == viewOnceTimeout {
                    return true
                }
            }
        }
        return false
    }
}
