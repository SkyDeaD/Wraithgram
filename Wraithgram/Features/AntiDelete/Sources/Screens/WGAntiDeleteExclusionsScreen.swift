import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import ChatListUI
import LocalizedPeerData
import WGCore
import WGFeaturesShared

// «Исключения»: kinds of chats (groups, bots, channels), chats picked by hand, folders of THIS
// account. Folder membership is computed by the app (category folders included) and kept in an
// account setting the notification service reads too; it follows folder changes while the
// account runs and is refreshed when the app comes back.

enum WGAntiDeleteFolderSync {
    private static var started: [AccountRecordId: Disposable] = [:]
    private static var activeAccountsDisposable: Disposable?

    /// Recomputes the chats of the excluded folders of one account.
    static func sync(context: AccountContext) -> Signal<Never, NoError> {
        let account = context.account.id.wg
        let folderIds = WGAntiDeleteSettings.excludedFolders.value(for: account)
        if folderIds.isEmpty {
            return Signal { subscriber in
                if !WGAntiDeleteSettings.excludedFolderPeers.value(for: account).isEmpty {
                    WGAntiDeleteSettings.excludedFolderPeers.set([], for: account)
                }
                subscriber.putCompletion()
                return EmptyDisposable
            }
        }
        let accountPeerId = context.account.peerId
        let postbox = context.account.postbox
        return context.engine.peers.currentChatListFilters()
        |> take(1)
        |> mapToSignal { filters -> Signal<Set<WGPeerKey>, NoError> in
            var selected: [ChatListFilterData] = []
            for filter in filters {
                if case let .filter(id, _, _, data) = filter, folderIds.contains(id) {
                    selected.append(data)
                }
            }
            return postbox.transaction { transaction -> Set<WGPeerKey> in
                var result = Set<WGPeerKey>()
                for var data in selected {
                    // Membership must not change on every read or mute.
                    data.excludeRead = false
                    data.excludeMuted = false
                    let predicate = chatListFilterPredicate(filter: data, accountPeerId: accountPeerId)
                    for peer in transaction.getChatListPeers(groupId: .root, filterPredicate: predicate, additionalFilter: nil) {
                        result.insert(peer.id.wgKey)
                    }
                    if !data.excludeArchived {
                        for peer in transaction.getChatListPeers(groupId: Namespaces.PeerGroup.archive, filterPredicate: predicate, additionalFilter: nil) {
                            result.insert(peer.id.wgKey)
                        }
                    }
                    for peerId in data.includePeers.peers + data.includePeers.pinnedPeers {
                        result.insert(peerId.wgKey)
                    }
                }
                return result
            }
        }
        |> deliverOn(WGAntiDeleteAccounts.shared.queue)
        |> map { peers -> Void in
            if WGAntiDeleteSettings.excludedFolderPeers.value(for: account) != peers {
                WGAntiDeleteSettings.excludedFolderPeers.set(peers, for: account)
            }
            return Void()
        }
        |> ignoreValues
    }

    /// Follows the folders and the excluded-folder setting of every running account (main thread).
    static func start(sharedContext: SharedAccountContext) {
        if WGAntiDeleteFolderSync.activeAccountsDisposable != nil {
            return
        }
        WGAntiDeleteFolderSync.activeAccountsDisposable = (sharedContext.activeAccountContexts
        |> deliverOnMainQueue).start(next: { accounts in
            var alive = Set<AccountRecordId>()
            for (id, context, _) in accounts.accounts {
                alive.insert(id)
                if WGAntiDeleteFolderSync.started[id] != nil {
                    continue
                }
                let trigger = combineLatest(context.engine.peers.updatedChatListFilters(), WGAntiDeleteSettings.excludedFolders.signal(for: id.wg))
                // A burst of folder updates becomes one recomputation (the previous wait is dropped).
                WGAntiDeleteFolderSync.started[id] = (trigger
                |> mapToSignal { _ -> Signal<Never, NoError> in
                    return Signal<Void, NoError>.single(Void())
                    |> delay(1.0, queue: WGAntiDeleteAccounts.shared.queue)
                    |> mapToSignal { _ -> Signal<Never, NoError> in
                        return WGAntiDeleteFolderSync.sync(context: context)
                    }
                }).start()
            }
            for (id, disposable) in WGAntiDeleteFolderSync.started where !alive.contains(id) {
                disposable.dispose()
                WGAntiDeleteFolderSync.started.removeValue(forKey: id)
            }
        })
    }

    /// Foreground refresh: chats move between category folders without a folder change.
    static func refreshAll(sharedContext: SharedAccountContext) -> Signal<Never, NoError> {
        return sharedContext.activeAccountContexts
        |> take(1)
        |> mapToSignal { accounts -> Signal<Never, NoError> in
            var signal: Signal<Never, NoError> = .complete()
            for (_, context, _) in accounts.accounts {
                signal = signal |> then(WGAntiDeleteFolderSync.sync(context: context))
            }
            return signal
        }
    }
}

func wgMakeAntiDeleteExclusionsController(context: AccountContext) -> ViewController {
    let account = context.account.id.wg
    weak var weakController: ViewController?

    let peers = WGAntiDeleteSettings.excludedPeers.signal(for: account)
    |> mapToSignal { keys -> Signal<[EnginePeer], NoError> in
        let ids = keys.sorted().map { PeerId(wgKey: $0) }
        return context.engine.data.get(EngineDataMap(ids.map(TelegramEngine.EngineData.Item.Peer.Peer.init)))
        |> map { result -> [EnginePeer] in
            return ids.compactMap { id in
                return result[id] ?? nil
            }
        }
    }

    // A folder hidden from the app (a locked secret folder) is not listed; an exclusion already set
    // on it stays in force (the folder sync reads every folder).
    let model = combineLatest(queue: .mainQueue(), WGSettingsStore.shared.revision, peers, wgChatListFolders(context.engine.peers.updatedChatListFilters(), context: context))
    |> map { _, peers, filters -> WGADScreenModel in
        var model = WGADScreenModel(title: .text(WGStrings.AntiDelete.Exclusions.title), sections: [])

        let kinds: [(id: String, title: String, setting: WGSetting<Bool>)] = [
            ("groups", WGStrings.AntiDelete.Exclusions.groups, WGAntiDeleteSettings.excludeGroups),
            ("bots", WGStrings.AntiDelete.Exclusions.bots, WGAntiDeleteSettings.excludeBots),
            ("channels", WGStrings.AntiDelete.Exclusions.channels, WGAntiDeleteSettings.excludeChannels)
        ]
        var kindRows: [WGADRow] = [WGADRow(id: "kinds.header", kind: .header(WGStrings.AntiDelete.Exclusions.kindsHeader))]
        for item in kinds {
            kindRows.append(WGADRow(id: "kind.\(item.id)", kind: .toggle(title: item.title, value: item.setting.value)))
            let setting = item.setting
            model.toggle["kind.\(item.id)"] = { value in
                setting.set(value)
            }
        }
        kindRows.append(WGADRow(id: "kind.edits", kind: .toggle(title: WGStrings.AntiDelete.Exclusions.editsInExclusions, value: WGAntiDeleteSettings.editsInExclusions.value)))
        model.toggle["kind.edits"] = { value in
            WGAntiDeleteSettings.editsInExclusions.set(value)
        }
        kindRows.append(WGADRow(id: "kinds.footer", kind: .footer(WGStrings.AntiDelete.Exclusions.kindsFooter)))
        model.sections.append(WGADSection(id: "kinds", rows: kindRows))

        var chatRows: [WGADRow] = [WGADRow(id: "chats.header", kind: .header(WGStrings.AntiDelete.Exclusions.chatsHeader))]
        chatRows.append(WGADRow(id: "chats.add", kind: .action(title: WGStrings.AntiDelete.Exclusions.addChat, destructive: false)))
        model.tap["chats.add"] = {
            let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.excludeSavedMessages, .doNotSearchMessages], hasContactSelector: false, title: WGStrings.AntiDelete.Exclusions.addChat))
            controller.peerSelected = { [weak controller] peer, _ in
                var current = WGAntiDeleteSettings.excludedPeers.value(for: account)
                current.insert(peer.id.wgKey)
                WGAntiDeleteSettings.excludedPeers.set(current, for: account)
                controller?.dismiss()
            }
            (weakController?.navigationController as? NavigationController)?.pushViewController(controller)
        }
        for peer in peers {
            let rowId = "chat.\(peer.id.wgKey.stringValue)"
            chatRows.append(WGADRow(id: rowId, kind: .peer(peer: peer, text: "", label: "", removeTitle: WGStrings.AntiDelete.Exclusions.remove)))
            let key = peer.id.wgKey
            model.remove[rowId] = {
                var current = WGAntiDeleteSettings.excludedPeers.value(for: account)
                current.remove(key)
                WGAntiDeleteSettings.excludedPeers.set(current, for: account)
            }
        }
        chatRows.append(WGADRow(id: "chats.footer", kind: .footer(WGStrings.AntiDelete.Exclusions.chatsFooter)))
        model.sections.append(WGADSection(id: "chats", rows: chatRows))

        var folderRows: [WGADRow] = [WGADRow(id: "folders.header", kind: .header(WGStrings.AntiDelete.Exclusions.foldersHeader))]
        let excludedFolders = WGAntiDeleteSettings.excludedFolders.value(for: account)
        var hasFolders = false
        for filter in filters {
            guard case let .filter(id, title, emoticon, _) = filter else {
                continue
            }
            hasFolders = true
            let rowId = "folder.\(id)"
            folderRows.append(WGADRow(id: rowId, kind: .toggle(title: (emoticon.map { $0 + " " } ?? "") + title.text, value: excludedFolders.contains(id))))
            model.toggle[rowId] = { value in
                var current = WGAntiDeleteSettings.excludedFolders.value(for: account)
                if value {
                    current.insert(id)
                } else {
                    current.remove(id)
                }
                WGAntiDeleteSettings.excludedFolders.set(current, for: account)
                let _ = WGAntiDeleteFolderSync.sync(context: context).start()
            }
        }
        folderRows.append(WGADRow(id: "folders.footer", kind: .footer(hasFolders ? WGStrings.AntiDelete.Exclusions.foldersFooter : WGStrings.AntiDelete.Exclusions.foldersEmpty)))
        model.sections.append(WGADSection(id: "folders", rows: folderRows))
        return model
    }

    let controller = wgMakeADListController(context: context, model: model)
    weakController = controller
    return controller
}
