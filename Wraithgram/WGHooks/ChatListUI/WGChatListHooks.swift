// Compiled into ChatListUI (filegroup //Wraithgram/WGHooks:ChatListUIHookSources). Chat list
// points live here because their types are ChatListUI's own (ChatListItemNode, the header's
// NavigationBarComponent buttons); features import ChatListUI to register.

import Foundation
import UIKit
import SwiftSignalKit
import AsyncDisplayKit
import Display
import ComponentFlow
import TelegramCore
import TelegramPresentationData
import AccountContext
import ChatListHeaderComponent
import NavigationBarComponent
import ChatListFilterTabContainerNode
import ItemListUI
import WGCore
import WGHooks

public struct WGChatListRowContext {
    public let context: AccountContext
    public let peer: EnginePeer?
    public let messages: [EngineMessage]
    public let theme: PresentationTheme
    /// The «Archived Chats» row: `peer` and `messages` are the archived chat and message it shows.
    /// Asked by the preview points only (`previewText`, `hidesLastMessageAuthor`, `hidesMediaPreview`).
    public var isArchive: Bool = false
}

public struct WGChatListRowLayout {
    public let context: AccountContext
    public let peer: EnginePeer?
    /// The row node (ChatListItemNode). Add feature subviews to it; they are laid out here.
    public let node: ASDisplayNode
    public let titleFrame: CGRect
    public let avatarFrame: CGRect
}

public struct WGChatListHeaderContext {
    public let context: AccountContext
    public let location: ChatListControllerLocation
}

public enum WGChatListHooks {
    /// Policy: the preview text of a row (chat lock hides it, download status replaces it).
    /// First non-nil wins. Layout path, possibly off the main thread: snapshot reads only.
    public static let previewText = WGHookPoint<(WGChatListRowContext) -> NSAttributedString?>("chatList.previewText")

    /// Observer after a row's layout is applied (main thread): row decorations (download status).
    public static let rowDidLayout = WGHookPoint<(WGChatListRowLayout) -> Void>("chatList.rowDidLayout")

    /// Transformer of the header's right buttons (account switcher, «read all», Android-style actions).
    public static let headerRightButtons = WGHookPoint<([NavigationBarComponent.Button], WGChatListHeaderContext) -> [NavigationBarComponent.Button]>("chatList.headerRightButtons")

    /// Transformer of a row's swipe actions (hide «Delete», all of them…). Asked for the right
    /// actions and for the left ones (pin, read) separately.
    public static let revealOptions = WGHookPoint<([ItemListRevealOption], WGChatListRowContext) -> [ItemListRevealOption]>("chatList.revealOptions")

    /// Policy (any `true`): the author line of a group row is hidden together with its preview
    /// (messages of blocked users). Layout path: answer from snapshots.
    public static let hidesLastMessageAuthor = WGHookPoint<(WGChatListRowContext) -> Bool>("chatList.hidesLastMessageAuthor")

    /// Policy (any `true`): the promoted chat of the proxy sponsor (or a PSA chat) is left out of
    /// the list. `isProxy` = the promotion comes from the MTProxy sponsor.
    public static let hidesPromoChat = WGHookPoint<(AccountContext, Bool) -> Bool>("chatList.hidesPromoChat")

    /// Transformer of the folder tabs shown above the list (hide «All chats», reorder). The list's
    /// own filters are not changed: a hidden tab only disappears from the tab strip.
    public static let filterTabs = WGHookPoint<([ChatListFilterTabEntry], AccountContext) -> [ChatListFilterTabEntry]>("chatList.filterTabs")

    /// Providers of a signal that emits whenever a `filterTabs` handler would answer differently (its
    /// setting changed): the tabs are rebuilt then, not only when the folders or their counters do.
    /// The signal should emit its current state first.
    public static let filterTabsChanges = WGHookPoint<(AccountContext) -> Signal<Void, NoError>>("chatList.filterTabsChanges")

    /// Transformer of the account's folders as every list the user sees shows them
    /// (`chatListFilterItems`: the tabs above the list, their pages — so no swipe leads into a
    /// removed folder —, the folder tabs of the forward picker; «Add to folder», the «Chats» tab's
    /// folder menu, Settings › Chat Folders, the folder tags of chat rows; Wraithgram's folder lists
    /// call `wgChatListFolders` too). Combine with your own state signal: the lists are rebuilt
    /// whenever it emits (a secret folder unlocked or locked again).
    public static let folders = WGHookPoint<(Signal<[ChatListFilter], NoError>, AccountContext) -> Signal<[ChatListFilter], NoError>>("chatList.folders")

    /// Policy (any `true`): a row shows no media thumbnails and no message-type icon (a locked chat;
    /// its text is replaced through `previewText`). Layout path, possibly off the main thread:
    /// answer from snapshots.
    public static let hidesMediaPreview = WGHookPoint<(WGChatListRowContext) -> Bool>("chatList.hidesMediaPreview")

    /// Policy (any `true`): a found message is left out of the chat list search (every tab of it —
    /// chats, media, links, files, music, voice). Called for every found message: answer from memory.
    public static let hidesSearchMessages = WGHookPoint<(AccountContext, EngineMessage) -> Bool>("chatList.hidesSearchMessages")

    /// Transformer of the stories strip's source (hide stories: map to empty subscriptions;
    /// combine with your setting's signal to apply live).
    public static let storySubscriptions = WGHookPoint<(Signal<EngineStorySubscriptions, NoError>, AccountContext) -> Signal<EngineStorySubscriptions, NoError>>("chatList.storySubscriptions")

    /// Provider (all handlers merged): chats whose rows a feature decorates in place of the preview
    /// (download status). Their rows re-lay out when the set changes; the set must change rarely
    /// (a download starts or ends), never on a progress tick — progress is drawn by the feature's own
    /// view (`rowDidLayout`). Subscribed once per root chat list (`.chatList` location).
    public static let accessoryPeers = WGHookPoint<(AccountContext) -> Signal<Set<EnginePeer.Id>, NoError>>("chatList.accessoryPeers")
}

// MARK: - Call-site helpers (ChatListUI internal)

/// The context the preview points see: a chat row, or the «Archived Chats» row with the archived chat
/// and message it previews (a locked chat must not show through there either).
private func wgChatListPreviewRowContext(item: ChatListItem) -> WGChatListRowContext? {
    switch item.content {
    case let .peer(peerData):
        return WGChatListRowContext(context: item.context, peer: peerData.peer.peer, messages: peerData.messages, theme: item.presentationData.theme)
    case let .groupReference(groupData):
        guard let message = groupData.message, let first = groupData.peers.first else {
            return nil
        }
        return WGChatListRowContext(context: item.context, peer: first.peer.peer, messages: [message], theme: item.presentationData.theme, isArchive: true)
    case .loading:
        return nil
    }
}

func wgChatListPreviewText(item: ChatListItem) -> NSAttributedString? {
    if WGChatListHooks.previewText.isEmpty {
        return nil
    }
    guard let rowContext = wgChatListPreviewRowContext(item: item) else {
        return nil
    }
    for handler in WGChatListHooks.previewText.handlers {
        if let value = handler(rowContext) {
            return value
        }
    }
    return nil
}

func wgChatListRowDidLayout(_ node: ChatListItemNode, item: ChatListItem, avatarFrame: CGRect) {
    if WGChatListHooks.rowDidLayout.isEmpty {
        return
    }
    var peer: EnginePeer?
    if case let .peer(peerData) = item.content {
        peer = peerData.peer.peer
    }
    let layout = WGChatListRowLayout(context: item.context, peer: peer, node: node, titleFrame: node.titleNode.frame, avatarFrame: avatarFrame)
    for handler in WGChatListHooks.rowDidLayout.handlers {
        handler(layout)
    }
}

func wgChatListHeaderRightButtons(_ buttons: [NavigationBarComponent.Button], context: AccountContext, location: ChatListControllerLocation) -> [NavigationBarComponent.Button] {
    if WGChatListHooks.headerRightButtons.isEmpty {
        return buttons
    }
    var result = buttons
    let headerContext = WGChatListHeaderContext(context: context, location: location)
    for handler in WGChatListHooks.headerRightButtons.handlers {
        result = handler(result, headerContext)
    }
    return result
}


func wgChatListStorySubscriptions(_ signal: Signal<EngineStorySubscriptions, NoError>, context: AccountContext) -> Signal<EngineStorySubscriptions, NoError> {
    if WGChatListHooks.storySubscriptions.isEmpty {
        return signal
    }
    var result = signal
    for handler in WGChatListHooks.storySubscriptions.handlers {
        result = handler(result, context)
    }
    return result
}

func wgChatListHidesLastMessageAuthor(item: ChatListItem) -> Bool {
    if WGChatListHooks.hidesLastMessageAuthor.isEmpty {
        return false
    }
    guard let rowContext = wgChatListPreviewRowContext(item: item) else {
        return false
    }
    for handler in WGChatListHooks.hidesLastMessageAuthor.handlers {
        if handler(rowContext) {
            return true
        }
    }
    return false
}

/// Spoilers of a row's preview (text and media thumbnail) shown uncovered: the message decoration
/// of the shown message (`WGMessageDecoration.revealsSpoilers`, anti-spoiler).
func wgChatListRevealsSpoilers(_ message: EngineMessage, context: AccountContext) -> Bool {
    if !WGMessageDecorationHooks.isActive {
        return false
    }
    return WGMessageDecorationHooks.decoration(for: message._asMessage(), context: context).revealsSpoilers
}

/// For ChatListNode (owner W3-3): the merged set of decorated chats, nil when nobody decorates rows
/// (the node then subscribes to nothing and its state stays upstream's).
func wgChatListAccessoryPeers(context: AccountContext) -> Signal<Set<EnginePeer.Id>, NoError>? {
    if WGChatListHooks.accessoryPeers.isEmpty {
        return nil
    }
    let signals = WGChatListHooks.accessoryPeers.handlers.map { $0(context) }
    return combineLatest(signals)
    |> map { sets -> Set<EnginePeer.Id> in
        var result = Set<EnginePeer.Id>()
        for set in sets {
            result.formUnion(set)
        }
        return result
    }
    |> distinctUntilChanged
}

/// For ChatListNodeEntries (owner W3-3): the promoted chat is left out of the list.
func wgChatListHidesPromoChat(context: AccountContext, isProxy: Bool) -> Bool {
    for handler in WGChatListHooks.hidesPromoChat.handlers {
        if handler(context, isProxy) {
            return true
        }
    }
    return false
}

func wgChatListRevealOptions(_ options: [ItemListRevealOption], item: ChatListItem) -> [ItemListRevealOption] {
    if WGChatListHooks.revealOptions.isEmpty {
        return options
    }
    guard case let .peer(peerData) = item.content else {
        return options
    }
    let rowContext = WGChatListRowContext(context: item.context, peer: peerData.peer.peer, messages: peerData.messages, theme: item.presentationData.theme)
    var result = options
    for handler in WGChatListHooks.revealOptions.handlers {
        result = handler(result, rowContext)
    }
    return result
}

func wgChatListFilterTabs(_ entries: [ChatListFilterTabEntry], context: AccountContext) -> [ChatListFilterTabEntry] {
    if WGChatListHooks.filterTabs.isEmpty {
        return entries
    }
    var result = entries
    for handler in WGChatListHooks.filterTabs.handlers {
        result = handler(result, context)
    }
    return result
}

/// WRAITH hook target: the folder items `reloadFilters` builds the tabs from — re-emitted whenever a
/// `filterTabsChanges` signal does. Without handlers: `signal` unchanged.
func wgChatListFilterItemsWithTabChanges<T>(_ signal: Signal<T, NoError>, context: AccountContext) -> Signal<T, NoError> {
    if WGChatListHooks.filterTabsChanges.isEmpty {
        return signal
    }
    let changes = combineLatest(WGChatListHooks.filterTabsChanges.handlers.map { $0(context) })
    return combineLatest(signal, changes)
    |> map { value, _ -> T in
        return value
    }
}

// The tab the list opens on is chosen from the unfiltered folders (upstream falls back to
// «All chats»), so when a handler hid it the first tab that is still shown is taken instead.
func wgChatListSelectedFilterTab(_ selected: ChatListFilterTabEntryId, tabs: [ChatListFilterTabEntry]) -> ChatListFilterTabEntryId {
    if WGChatListHooks.filterTabs.isEmpty {
        return selected
    }
    if tabs.isEmpty || tabs.contains(where: { $0.id == selected }) {
        return selected
    }
    return tabs[0].id
}

/// WRAITH hook target: every list of folders the user sees — `chatListFilterItems(context:)` (tabs,
/// their pages, the forward picker), «Add to folder», the «Chats» tab's folder menu, Settings › Chat
/// Folders, the folder tags of chat rows, and the folder lists of Wraithgram's own screens. Code that
/// needs the real folders (a feature's own membership, exceptions by folder id) reads the engine.
/// Without handlers: `signal` unchanged.
public func wgChatListFolders(_ signal: Signal<[ChatListFilter], NoError>, context: AccountContext) -> Signal<[ChatListFilter], NoError> {
    if WGChatListHooks.folders.isEmpty {
        return signal
    }
    var result = signal
    for handler in WGChatListHooks.folders.handlers {
        result = handler(result, context)
    }
    return result
}

/// WRAITH hook target: `ChatListItem.asyncLayout`, after the media thumbnails of the preview are chosen.
func wgChatListHidesMediaPreview(item: ChatListItem) -> Bool {
    if WGChatListHooks.hidesMediaPreview.isEmpty {
        return false
    }
    guard let rowContext = wgChatListPreviewRowContext(item: item) else {
        return false
    }
    for handler in WGChatListHooks.hidesMediaPreview.handlers {
        if handler(rowContext) {
            return true
        }
    }
    return false
}

/// WRAITH hook target: the found messages of the chat list search, one by one.
func wgChatListHidesSearchMessage(_ message: EngineMessage, context: AccountContext) -> Bool {
    if WGChatListHooks.hidesSearchMessages.isEmpty {
        return false
    }
    for handler in WGChatListHooks.hidesSearchMessages.handlers {
        if handler(context, message) {
            return true
        }
    }
    return false
}
