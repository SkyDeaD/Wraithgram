import Foundation
import UIKit
import UniformTypeIdentifiers
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import AccountContext
import ItemListUI
import PresentationDataUtils
import LocalizedPeerData
import ChatListUI
import WGCore
import WGFeaturesShared

// «История»: segments «Удалённые / Изменённые», chats grouped by kind and by folder (category
// folders included), per-chat lists with pages, export / import / clear. Everything reads the
// account's own index (its Postbox) reactively: a capture while the screen is open shows up.

/// A chat folder used as a filter of the history screen.
struct WGADFolderFilter {
    let title: String
    let peerIds: Set<PeerId>
}

private enum WGADChatGroup: Int, CaseIterable {
    case personal
    case groups
    case channels
    case bots
    case secret

    var title: String {
        switch self {
        case .personal:
            return WGStrings.AntiDelete.History.personal
        case .groups:
            return WGStrings.AntiDelete.History.groups
        case .channels:
            return WGStrings.AntiDelete.History.channels
        case .bots:
            return WGStrings.AntiDelete.History.bots
        case .secret:
            return WGStrings.AntiDelete.History.secret
        }
    }

    init(_ peer: EnginePeer) {
        switch peer {
        case let .user(user):
            self = user.botInfo != nil ? .bots : .personal
        case .legacyGroup, .community:
            self = .groups
        case let .channel(channel):
            if case .broadcast = channel.info {
                self = .channels
            } else {
                self = .groups
            }
        case .secretChat:
            self = .secret
        }
    }
}

/// Whether a chat belongs to a folder, without the dynamic rules (read / muted / archived),
/// which would make the grouping change on every read: explicit chats, then the categories.
func wgFolderContains(_ data: ChatListFilterData, peer: EnginePeer, isContact: Bool, accountPeerId: PeerId) -> Bool {
    if data.excludePeers.contains(peer.id) {
        return false
    }
    if data.includePeers.peers.contains(peer.id) || data.includePeers.pinnedPeers.contains(peer.id) {
        return true
    }
    switch peer {
    case let .user(user):
        if user.botInfo != nil {
            return data.categories.contains(.bots)
        }
        if peer.id == accountPeerId {
            return false
        }
        return isContact ? data.categories.contains(.contacts) : data.categories.contains(.nonContacts)
    case .legacyGroup, .community:
        return data.categories.contains(.groups)
    case let .channel(channel):
        if case .broadcast = channel.info {
            return data.categories.contains(.channels)
        }
        return data.categories.contains(.groups)
    case .secretChat:
        return isContact ? data.categories.contains(.contacts) : data.categories.contains(.nonContacts)
    }
}

private func wgAntiDeleteDate(_ timestamp: Int32, presentationData: PresentationData) -> String {
    return stringForMediumDate(timestamp: timestamp, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat, withTime: false)
}

private func wgNativePresenter(_ controller: ViewController?) -> UIViewController? {
    guard var presenter = controller?.view.window?.rootViewController else {
        return nil
    }
    while let presented = presenter.presentedViewController {
        presenter = presented
    }
    return presenter
}

// MARK: - Root

func wgMakeAntiDeleteHistoryController(context: AccountContext, kind initialKind: WGAntiDeleteLogKind, folder: WGADFolderFilter? = nil) -> ViewController {
    let postbox = context.account.postbox
    let accountId = context.account.id
    let segment = ValuePromise<Int>(initialKind == .deleted ? 0 : 1, ignoreRepeated: true)
    weak var weakController: ViewController?

    // Dangling entries (chats the user deleted, messages removed by hand) leave the index on open.
    if folder == nil {
        let _ = (postbox.transaction { transaction -> [(WGAntiDeleteLogKind, PeerId)] in
            var result: [(WGAntiDeleteLogKind, PeerId)] = []
            for kind in WGAntiDeleteLogKind.allCases {
                for peer in WGAntiDeleteIndexStore.readSummary(transaction, kind: kind).peers.keys {
                    result.append((kind, PeerId(wgKey: peer)))
                }
            }
            return result
        }
        |> mapToSignal { items -> Signal<Never, NoError> in
            var signal: Signal<Never, NoError> = .complete()
            for (kind, peerId) in items {
                signal = signal |> then(WGAntiDeleteOperations.reconcile(postbox: postbox, accountId: accountId, kind: kind, peerId: peerId))
            }
            return signal
        }).start()
    }

    let summaries = combineLatest(WGAntiDeleteIndexStore.summarySignal(postbox: postbox, kind: .deleted), WGAntiDeleteIndexStore.summarySignal(postbox: postbox, kind: .edited))
    let data = summaries
    |> mapToSignal { deleted, edited -> Signal<(WGAntiDeleteSummary, WGAntiDeleteSummary, [EnginePeer.Id: EnginePeer], [ChatListFilter], Set<PeerId>), NoError> in
        var ids = Set<PeerId>()
        for key in deleted.peers.keys {
            ids.insert(PeerId(wgKey: key))
        }
        for key in edited.peers.keys {
            ids.insert(PeerId(wgKey: key))
        }
        let peers = context.engine.data.get(EngineDataMap(ids.map(TelegramEngine.EngineData.Item.Peer.Peer.init)))
        |> map { result -> [EnginePeer.Id: EnginePeer] in
            var values: [EnginePeer.Id: EnginePeer] = [:]
            for (id, peer) in result {
                if let peer {
                    values[id] = peer
                }
            }
            return values
        }
        let contacts = postbox.transaction { transaction -> Set<PeerId> in
            return transaction.getContactPeerIds()
        }
        // A folder hidden from the app (a locked secret folder) gets no row of its own here.
        return combineLatest(peers, wgChatListFolders(context.engine.peers.currentChatListFilters(), context: context) |> take(1), contacts)
        |> map { peers, filters, contacts in
            return (deleted, edited, peers, filters, contacts)
        }
    }

    let model = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, segment.get(), data)
    |> map { presentationData, segmentIndex, data -> WGADScreenModel in
        let (deletedSummary, editedSummary, peers, filters, contacts) = data
        let kind: WGAntiDeleteLogKind = segmentIndex == 0 ? .deleted : .edited
        let summary = kind == .deleted ? deletedSummary : editedSummary
        let titles = [WGStrings.AntiDelete.History.deleted, WGStrings.AntiDelete.History.edited]
        var model = WGADScreenModel(title: folder == nil ? .sectionControl(titles, segmentIndex) : .text(folder?.title ?? ""), sections: [])

        var items: [(peer: EnginePeer, summary: WGAntiDeletePeerSummary)] = []
        for (key, value) in summary.sortedPeers {
            let peerId = PeerId(wgKey: key)
            guard let peer = peers[peerId] else {
                continue
            }
            if let folder, !folder.peerIds.contains(peerId) {
                continue
            }
            items.append((peer, value))
        }
        let total = items.reduce(0, { $0 + Int($1.summary.count) })
        if total == 0 {
            model.sections.append(WGADSection(id: "empty", rows: [WGADRow(id: "empty", kind: .footer(kind == .deleted ? WGStrings.AntiDelete.History.emptyDeleted : WGStrings.AntiDelete.History.emptyEdited))]))
        } else {
            model.sections.append(WGADSection(id: "summary", rows: [WGADRow(id: "summary", kind: .footer(kind == .deleted ? WGStrings.AntiDelete.History.totalDeleted(count: total) : WGStrings.AntiDelete.History.totalEdited(count: total)))]))
        }

        for group in WGADChatGroup.allCases {
            let groupItems = items.filter { WGADChatGroup($0.peer) == group }
            if groupItems.isEmpty {
                continue
            }
            var rows: [WGADRow] = [WGADRow(id: "header.\(group.rawValue)", kind: .header(group.title))]
            for item in groupItems {
                let id = "peer.\(item.peer.id.wgKey.stringValue)"
                let count = Int(item.summary.count)
                let text = kind == .deleted ? WGStrings.AntiDelete.History.deletedCount(count: count) : WGStrings.AntiDelete.History.editedCount(count: count)
                rows.append(WGADRow(id: id, kind: .peer(peer: item.peer, text: text, label: wgAntiDeleteDate(item.summary.lastTime, presentationData: presentationData), removeTitle: WGStrings.AntiDelete.History.clear)))
                let peerId = item.peer.id
                model.tap[id] = {
                    (weakController?.navigationController as? NavigationController)?.pushViewController(wgMakeAntiDeleteChatHistoryController(context: context, kind: kind, peerId: peerId))
                }
                model.remove[id] = {
                    wgConfirmClear(context: context, controller: weakController, kind: kind, peerIds: [peerId])
                }
            }
            model.sections.append(WGADSection(id: "group.\(group.rawValue)", rows: rows))
        }

        if folder == nil && !items.isEmpty {
            var rows: [WGADRow] = []
            for filter in filters {
                guard case let .filter(id, title, emoticon, filterData) = filter else {
                    continue
                }
                let members = items.filter { item in
                    var isContact = contacts.contains(item.peer.id)
                    if case let .secretChat(secretChat) = item.peer {
                        isContact = contacts.contains(secretChat.regularPeerId)
                    }
                    return wgFolderContains(filterData, peer: item.peer, isContact: isContact, accountPeerId: context.account.peerId)
                }
                if members.isEmpty {
                    continue
                }
                let rowId = "folder.\(id)"
                let folderTitle = (emoticon.map { $0 + " " } ?? "") + title.text
                let count = members.reduce(0, { $0 + Int($1.summary.count) })
                rows.append(WGADRow(id: rowId, kind: .disclosure(title: folderTitle, label: "\(count)", icon: "Chat/Context Menu/Folder")))
                let peerIds = Set(members.map(\.peer.id))
                model.tap[rowId] = {
                    (weakController?.navigationController as? NavigationController)?.pushViewController(wgMakeAntiDeleteHistoryController(context: context, kind: kind, folder: WGADFolderFilter(title: folderTitle, peerIds: peerIds)))
                }
            }
            if !rows.isEmpty {
                rows.insert(WGADRow(id: "header.folders", kind: .header(WGStrings.AntiDelete.History.folders)), at: 0)
                model.sections.append(WGADSection(id: "folders", rows: rows))
            }
        }

        if folder == nil {
            var actions: [WGADRow] = []
            if total > 0 {
                actions.append(WGADRow(id: "export", kind: .action(title: WGStrings.AntiDelete.History.exportAction, destructive: false)))
                model.tap["export"] = {
                    wgExportHistory(context: context, controller: weakController)
                }
            }
            actions.append(WGADRow(id: "import", kind: .action(title: WGStrings.AntiDelete.History.importAction, destructive: false)))
            model.tap["import"] = {
                wgImportHistory(context: context, controller: weakController)
            }
            if total > 0 {
                actions.append(WGADRow(id: "clear", kind: .action(title: kind == .deleted ? WGStrings.AntiDelete.History.clearDeleted : WGStrings.AntiDelete.History.clearEdited, destructive: true)))
                model.tap["clear"] = {
                    wgConfirmClear(context: context, controller: weakController, kind: kind, peerIds: nil)
                }
            }
            actions.append(WGADRow(id: "actions.footer", kind: .footer(WGStrings.AntiDelete.History.exportFooter)))
            model.sections.append(WGADSection(id: "actions", rows: actions))
        }
        return model
    }

    let controller = wgMakeADListController(context: context, model: model, onSegment: { index in
        segment.set(index)
    })
    weakController = controller
    return controller
}

private func wgConfirmClear(context: AccountContext, controller: ViewController?, kind: WGAntiDeleteLogKind, peerIds: [PeerId]?) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let text: String
    switch kind {
    case .deleted:
        text = WGStrings.AntiDelete.History.clearDeletedText
    case .edited:
        text = WGStrings.AntiDelete.History.clearEditedText
    }
    controller?.present(textAlertController(context: context, title: WGStrings.AntiDelete.History.clearTitle, text: text, actions: [
        TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
        TextAlertAction(type: .destructiveAction, title: WGStrings.AntiDelete.History.clear, action: {
            let _ = WGAntiDeleteOperations.clear(postbox: context.account.postbox, accountId: context.account.id, kind: kind, peerIds: peerIds).start()
        })
    ]), in: .window(.root))
}

// MARK: - Export / import

private func wgExportHistory(context: AccountContext, controller: ViewController?) {
    let _ = (WGAntiDeleteOperations.export(postbox: context.account.postbox, accountId: context.account.id)
    |> deliverOn(WGAntiDeleteAccounts.shared.queue)
    |> map { data -> URL? in
        guard let data else {
            return nil
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wraithgram-history-\(Int(Date().timeIntervalSince1970)).json")
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            return nil
        }
    }
    |> deliverOnMainQueue).start(next: { [weak controller] url in
        guard let url else {
            controller?.present(textAlertController(context: context, title: nil, text: WGStrings.AntiDelete.History.exportFailed, actions: [TextAlertAction(type: .defaultAction, title: context.sharedContext.currentPresentationData.with { $0 }.strings.Common_OK, action: {})]), in: .window(.root))
            return
        }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.completionWithItemsHandler = { _, _, _, _ in
            // The file is plain text: it does not stay in the temporary folder.
            WGAntiDeleteAccounts.shared.queue.justDispatch {
                let _ = try? FileManager.default.removeItem(at: url)
            }
        }
        if let presenter = wgNativePresenter(controller) {
            if let popover = activity.popoverPresentationController {
                popover.sourceView = presenter.view
                popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0.0, height: 0.0)
                popover.permittedArrowDirections = []
            }
            presenter.present(activity, animated: true)
        }
    })
}

/// Keeps the document picker's delegate alive while the picker is shown.
private final class WGADDocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let completion: (URL?) -> Void
    private var keepAlive: WGADDocumentPickerDelegate?

    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
        super.init()
        self.keepAlive = self
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.completion(urls.first)
        self.keepAlive = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.completion(nil)
        self.keepAlive = nil
    }
}

private func wgImportHistory(context: AccountContext, controller: ViewController?) {
    guard let presenter = wgNativePresenter(controller) else {
        return
    }
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
    let delegate = WGADDocumentPickerDelegate(completion: { [weak controller] url in
        guard let url else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let showText: (String) -> Void = { text in
            controller?.present(textAlertController(context: context, title: WGStrings.AntiDelete.History.importTitle, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
        }
        let read = Signal<Data?, NoError> { subscriber in
            let data = try? Data(contentsOf: url)
            let _ = try? FileManager.default.removeItem(at: url)
            subscriber.putNext(data)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        |> runOn(WGAntiDeleteAccounts.shared.queue)
        let _ = (read
        |> mapToSignal { data -> Signal<String, NoError> in
            guard let data else {
                return .single(WGStrings.AntiDelete.History.importInvalid)
            }
            switch WGAntiDeleteExportFile.decode(data) {
            case .failure(.invalidFormat):
                return .single(WGStrings.AntiDelete.History.importInvalid)
            case let .failure(.unsupportedVersion(version)):
                return .single(WGStrings.AntiDelete.History.importNewer(version: "\(version)"))
            case let .success(file):
                return WGAntiDeleteOperations.importFile(postbox: context.account.postbox, accountId: context.account.id, file: file)
                |> map { result -> String in
                    return WGStrings.AntiDelete.History.importDone(added: "\(result.added)", skipped: "\(result.skipped)")
                }
            }
        }
        |> deliverOnMainQueue).start(next: { text in
            showText(text)
        })
    })
    picker.delegate = delegate
    presenter.present(picker, animated: true)
}

// MARK: - One chat

func wgMakeAntiDeleteChatHistoryController(context: AccountContext, kind: WGAntiDeleteLogKind, peerId: PeerId) -> ViewController {
    let postbox = context.account.postbox
    let accountId = context.account.id
    let pageSize = 50
    let limit = ValuePromise<Int>(pageSize, ignoreRepeated: true)
    weak var weakController: ViewController?

    let _ = WGAntiDeleteOperations.reconcile(postbox: postbox, accountId: accountId, kind: kind, peerId: peerId).start()

    struct Item {
        let entry: WGAntiDeleteLogEntry
        let message: Message?
        let archived: WGAntiDeleteArchivedContent?
    }

    let chatPeer = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
    let page = combineLatest(WGAntiDeleteIndexStore.logSignal(postbox: postbox, kind: kind, peerId: peerId), limit.get())
    |> mapToSignal { log, limit -> Signal<(Int, [Item]), NoError> in
        let entries = log.newestFirst(offset: 0, limit: limit)
        return postbox.transaction { transaction -> (Int, [Item]) in
            var items: [Item] = []
            for entry in entries {
                let id = MessageId(peerId: peerId, namespace: entry.namespace, id: entry.id)
                if entry.isArchiveOnly {
                    items.append(Item(entry: entry, message: nil, archived: WGAntiDeleteIndexStore.readArchived(transaction, id: id)))
                } else if let message = transaction.getMessage(id) {
                    items.append(Item(entry: entry, message: message, archived: nil))
                }
            }
            return (log.count, items)
        }
    }

    let model = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, chatPeer, page, limit.get())
    |> map { presentationData, chatPeer, page, currentLimit -> WGADScreenModel in
        let (total, items) = page
        let title = chatPeer?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder) ?? WGStrings.AntiDelete.History.unknownChat
        var model = WGADScreenModel(title: .text(title), sections: [])
        guard let chatPeer else {
            return model
        }
        if items.isEmpty {
            model.sections.append(WGADSection(id: "empty", rows: [WGADRow(id: "empty", kind: .footer(WGStrings.AntiDelete.History.emptyChat))]))
            return model
        }
        var rows: [WGADRow] = [WGADRow(id: "header", kind: .header(kind == .deleted ? WGStrings.AntiDelete.History.deletedCount(count: total) : WGStrings.AntiDelete.History.editedCount(count: total)))]
        for item in items {
            let rowId = "message.\(item.entry.namespace).\(item.entry.id)"
            var rowPeer = chatPeer
            var text = ""
            if let message = item.message {
                if let author = message.author {
                    rowPeer = EnginePeer(author)
                }
                text = message.wgEffectiveText.text
                if text.isEmpty, let token = wgAntiDeleteMediaToken(message.media) {
                    text = wgAntiDeleteMediaTitle(token)
                }
            } else if let archived = item.archived {
                text = archived.text
                if text.isEmpty, let media = archived.mediaDescription {
                    text = wgAntiDeleteMediaTitle(media)
                }
                if let author = archived.authorName, !author.isEmpty {
                    text = author + ": " + text
                }
            }
            text = text.replacingOccurrences(of: "\n", with: " ")
            if text.count > 80 {
                text = String(text.prefix(80)) + "…"
            }
            if kind == .edited {
                text = "✎\(item.entry.count) · " + text
            }
            rows.append(WGADRow(id: rowId, kind: .peer(peer: rowPeer, text: text, label: wgAntiDeleteDate(item.entry.time, presentationData: presentationData), removeTitle: nil)))
            let messageId = MessageId(peerId: peerId, namespace: item.entry.namespace, id: item.entry.id)
            let entry = item.entry
            model.tap[rowId] = {
                wgPresentEntryActions(context: context, controller: weakController, kind: kind, messageId: messageId, entry: entry)
            }
        }
        if total > currentLimit {
            rows.append(WGADRow(id: "more", kind: .action(title: WGStrings.AntiDelete.History.showMore, destructive: false)))
            model.tap["more"] = {
                limit.set(currentLimit + pageSize)
            }
        }
        model.sections.append(WGADSection(id: "messages", rows: rows))
        model.sections.append(WGADSection(id: "actions", rows: [WGADRow(id: "clear", kind: .action(title: kind == .deleted ? WGStrings.AntiDelete.History.clearDeleted : WGStrings.AntiDelete.History.clearEdited, destructive: true))]))
        model.tap["clear"] = {
            wgConfirmClear(context: context, controller: weakController, kind: kind, peerIds: [peerId])
        }
        return model
    }

    let controller = wgMakeADListController(context: context, model: model)
    weakController = controller
    return controller
}

private func wgPresentEntryActions(context: AccountContext, controller: ViewController?, kind: WGAntiDeleteLogKind, messageId: MessageId, entry: WGAntiDeleteLogEntry) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let actionSheet = ActionSheetController(presentationData: presentationData)
    var items: [ActionSheetItem] = []
    if !entry.isArchiveOnly {
        items.append(ActionSheetButtonItem(title: WGStrings.AntiDelete.History.openInChat, color: .accent, action: { [weak actionSheet, weak controller] in
            actionSheet?.dismissAnimated()
            if let navigationController = controller?.navigationController as? NavigationController {
                wgOpenMessage(context: context, navigationController: navigationController, messageId: messageId, threadId: entry.threadId)
            }
        }))
    }
    switch kind {
    case .deleted:
        items.append(ActionSheetButtonItem(title: entry.isArchiveOnly ? WGStrings.AntiDelete.History.removeEntry : WGStrings.AntiDelete.History.deleteForMe, color: .destructive, action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()
            let _ = WGAntiDeleteOperations.deleteKept(postbox: context.account.postbox, accountId: context.account.id, messageIds: [messageId]).start()
        }))
    case .edited:
        items.append(ActionSheetButtonItem(title: WGStrings.AntiDelete.History.versions, color: .accent, action: { [weak actionSheet, weak controller] in
            actionSheet?.dismissAnimated()
            (controller?.navigationController as? NavigationController)?.pushViewController(wgMakeEditVersionsController(context: context, messageId: messageId))
        }))
        items.append(ActionSheetButtonItem(title: WGStrings.AntiDelete.History.clearVersions, color: .destructive, action: { [weak actionSheet] in
            actionSheet?.dismissAnimated()
            let _ = WGAntiDeleteOperations.removeEditHistory(postbox: context.account.postbox, accountId: context.account.id, messageIds: [messageId]).start()
        }))
    }
    actionSheet.setItemGroups([
        ActionSheetItemGroup(items: items),
        ActionSheetItemGroup(items: [
            ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
            })
        ])
    ])
    controller?.present(actionSheet, in: .window(.root))
}

/// Opens a chat on a message; a forum topic opens inside its topic.
func wgOpenMessage(context: AccountContext, navigationController: NavigationController, messageId: MessageId, threadId: Int64?) {
    let _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: messageId.peerId))
    |> deliverOnMainQueue).start(next: { peer in
        guard let peer else {
            return
        }
        if let threadId, peer._asPeer().isForum {
            let _ = context.sharedContext.navigateToForumThread(context: context, peerId: peer.id, threadId: threadId, messageId: messageId, navigationController: navigationController, activateInput: nil, scrollToEndIfExists: false, keepStack: .always, animated: true).start()
            return
        }
        context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), subject: .message(id: .id(messageId), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false), keepStack: .always, useExisting: true))
    })
}
