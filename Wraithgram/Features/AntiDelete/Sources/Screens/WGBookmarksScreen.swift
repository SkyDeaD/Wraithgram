import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramStringFormatting
import AccountContext
import LocalizedPeerData
import WGCore
import WGFeaturesShared

/// «Все закладки» (or the bookmarks of one chat): newest first, a tap opens the message, a swipe
/// removes the bookmark. Bookmarks belong to the account (its own Postbox).
func wgMakeBookmarksController(context: AccountContext, peerId: PeerId?) -> ViewController {
    let postbox = context.account.postbox
    weak var weakController: ViewController?

    let _ = WGAntiDeleteOperations.reconcileBookmarks(postbox: postbox, accountId: context.account.id).start()

    let data = WGAntiDeleteIndexStore.bookmarksSignal(postbox: postbox)
    |> mapToSignal { list -> Signal<([WGBookmarkEntry], [EnginePeer.Id: EnginePeer]), NoError> in
        var entries = list.entries
        if let peerId {
            entries = entries.filter { $0.message.peer == peerId.wgKey }
        }
        let ids = Array(Set(entries.map { PeerId(wgKey: $0.message.peer) }))
        return context.engine.data.get(EngineDataMap(ids.map(TelegramEngine.EngineData.Item.Peer.Peer.init)))
        |> map { result -> ([WGBookmarkEntry], [EnginePeer.Id: EnginePeer]) in
            var peers: [EnginePeer.Id: EnginePeer] = [:]
            for (id, peer) in result {
                if let peer {
                    peers[id] = peer
                }
            }
            return (entries, peers)
        }
    }

    let model = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, data)
    |> map { presentationData, data -> WGADScreenModel in
        let (entries, peers) = data
        var title = WGStrings.Bookmarks.All.title
        if let peerId, let peer = peers[peerId] {
            title = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
        }
        var model = WGADScreenModel(title: .text(title), sections: [])
        if entries.isEmpty {
            model.sections.append(WGADSection(id: "empty", rows: [WGADRow(id: "empty", kind: .footer(WGStrings.Bookmarks.All.empty))]))
            return model
        }
        var rows: [WGADRow] = []
        for entry in entries {
            let messageId = MessageId(wgKey: entry.message)
            guard let peer = peers[messageId.peerId] else {
                continue
            }
            let rowId = "bookmark.\(entry.message.stringValue)"
            let date = stringForMediumDate(timestamp: entry.messageDate, strings: presentationData.strings, dateTimeFormat: presentationData.dateTimeFormat)
            rows.append(WGADRow(id: rowId, kind: .peer(peer: peer, text: entry.title, label: date, removeTitle: WGStrings.Bookmarks.All.remove)))
            let threadId = entry.threadId
            model.tap[rowId] = {
                if let navigationController = weakController?.navigationController as? NavigationController {
                    wgOpenMessage(context: context, navigationController: navigationController, messageId: messageId, threadId: threadId)
                }
            }
            model.remove[rowId] = {
                WGAntiDeleteMessageMenu.setBookmark(context: context, messageId: messageId, title: nil)
            }
        }
        rows.append(WGADRow(id: "footer", kind: .footer(WGStrings.Bookmarks.All.footer)))
        model.sections.append(WGADSection(id: "bookmarks", rows: rows))
        return model
    }

    let controller = wgMakeADListController(context: context, model: model)
    weakController = controller
    return controller
}
