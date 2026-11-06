import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import WGCore

// The account part of a full export: personal information, profile photos, contacts, frequent
// contacts, sessions, web sessions, own stories, and the list of chats (main list and archive, all
// of them — the chat lists are loaded to the end first, there is no 5000 limit).

struct WGChatExportAccountData {
    var peer: EnginePeer?
    var about: String?
    var contacts: [EnginePeer] = []
    var frequent: [EnginePeer] = []
    var sessions: [RecentAccountSession] = []
    var webSessions: [WebAuthorization] = []
    var webSessionPeers: [EnginePeer.Id: EnginePeer] = [:]
    var photos: [TelegramPeerPhoto] = []
    var stories: [EngineStoryItem] = []
}

enum WGChatExportAccount {
    static let sectionTimeout: Double = 60.0
    static let storyLimit = 3000

    /// Every chat of the main list and the archive. The views stay open until both lists have no
    /// holes left (the account's chat list hole manager loads them), or until nothing has changed
    /// for a minute.
    static func chatPeers(postbox: Postbox, queue: Queue) -> Signal<[Peer], NoError> {
        let groups: [PeerGroupId] = [.root, Namespaces.PeerGroup.archive]
        let views = combineLatest(groups.map { groupId -> Signal<Int, NoError> in
            return postbox.tailChatListView(groupId: groupId, count: 100000, summaryComponents: ChatListEntrySummaryComponents())
            |> map { view, _ -> Int in
                return view.entries.count
            }
        })
        let holesLeft = views
        |> mapToSignal { _ -> Signal<Bool, NoError> in
            return postbox.transaction { transaction -> Bool in
                for groupId in groups {
                    if !transaction.allChatListHoles(groupId: groupId).isEmpty {
                        return true
                    }
                }
                return false
            }
        }
        let loaded = holesLeft
        |> filter { !$0 }
        |> take(1)
        |> timeout(WGChatExportAccount.sectionTimeout * 5.0, queue: queue, alternate: .single(true))
        return loaded
        |> mapToSignal { _ -> Signal<[Peer], NoError> in
            return postbox.transaction { transaction -> [Peer] in
                var result: [Peer] = []
                var seen = Set<PeerId>()
                for groupId in groups {
                    for peer in transaction.getChatListPeers(groupId: groupId, filterPredicate: nil, additionalFilter: nil) {
                        if seen.insert(peer.id).inserted {
                            result.append(peer)
                        }
                    }
                }
                return result
            }
        }
    }

    static func collect(context: AccountContext, queue: Queue) -> Signal<WGChatExportAccountData, NoError> {
        let engine = context.engine
        let accountPeerId = context.account.peerId

        let personal = engine.data.get(
            TelegramEngine.EngineData.Item.Peer.Peer(id: accountPeerId),
            TelegramEngine.EngineData.Item.Peer.AboutText(id: accountPeerId)
        )
        let contacts = engine.data.get(TelegramEngine.EngineData.Item.Contacts.List(includePresences: false))
        |> map { list -> [EnginePeer] in
            return list.peers
        }
        let frequent = engine.data.get(TelegramEngine.EngineData.Item.Contacts.Top())
        |> mapToSignal { ids -> Signal<[EnginePeer], NoError> in
            return engine.data.get(EngineDataMap(ids.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))))
            |> map { peers -> [EnginePeer] in
                return ids.compactMap { peers[$0] ?? nil }
            }
        }
        let sessionsContext = engine.privacy.activeSessions()
        let sessions = sessionsContext.state
        |> filter { !$0.isLoadingMore }
        |> take(1)
        |> map { state -> [RecentAccountSession] in
            let _ = sessionsContext
            return state.sessions
        }
        |> timeout(WGChatExportAccount.sectionTimeout, queue: queue, alternate: .single([]))
        let webSessionsContext = engine.privacy.webSessions()
        let webSessions = webSessionsContext.state
        |> filter { !$0.isLoadingMore }
        |> take(1)
        |> map { state -> ([WebAuthorization], [EnginePeer.Id: EnginePeer]) in
            let _ = webSessionsContext
            return (state.sessions, state.peers)
        }
        |> timeout(WGChatExportAccount.sectionTimeout, queue: queue, alternate: .single(([], [:])))
        let photos = engine.peers.requestPeerPhotos(peerId: accountPeerId)
        |> take(1)
        |> timeout(WGChatExportAccount.sectionTimeout, queue: queue, alternate: .single([]))
        let stories = WGChatExportAccount.ownStories(context: context, queue: queue)

        return combineLatest(personal, contacts, frequent, sessions, webSessions, photos, stories)
        |> take(1)
        |> map { personal, contacts, frequent, sessions, webSessions, photos, stories -> WGChatExportAccountData in
            var data = WGChatExportAccountData()
            data.peer = personal.0
            data.about = personal.1.knownValue ?? nil
            data.contacts = contacts
            data.frequent = frequent
            data.sessions = sessions
            data.webSessions = webSessions.0
            data.webSessionPeers = webSessions.1
            data.photos = photos
            data.stories = stories
            return data
        }
    }

    /// The account's own stories (the archive holds all of them), page by page up to a limit.
    private static func ownStories(context: AccountContext, queue: Queue) -> Signal<[EngineStoryItem], NoError> {
        return Signal { subscriber in
            let listContext = PeerStoryListContext(account: context.account, peerId: context.account.peerId, isArchived: true, folderId: nil)
            var requested = 0
            let disposable = (listContext.state
            |> deliverOn(queue)).start(next: { state in
                if state.isLoading {
                    return
                }
                if state.loadMoreToken != nil && state.items.count < WGChatExportAccount.storyLimit && requested < 200 {
                    requested += 1
                    listContext.loadMore()
                    return
                }
                subscriber.putNext(state.items.map { $0.storyItem })
                subscriber.putCompletion()
            })
            return ActionDisposable {
                disposable.dispose()
                let _ = listContext
            }
        }
        |> timeout(WGChatExportAccount.sectionTimeout * 3.0, queue: queue, alternate: .single([]))
    }

    // MARK: - Writing

    private static func userName(_ peer: EnginePeer) -> (first: String, last: String) {
        if case let .user(user) = peer {
            return (user.firstName ?? "", user.lastName ?? "")
        }
        return (peer.debugDisplayTitle, "")
    }

    private static func phone(_ peer: EnginePeer) -> String? {
        if case let .user(user) = peer, let phone = user.phone, !phone.isEmpty {
            return "+" + phone
        }
        return nil
    }

    /// The JSON members before `"chats"` (no surrounding braces), with the files they refer to.
    static func jsonSections(_ data: WGChatExportAccountData, photoPaths: [String?], storyPaths: [String?], format: WGChatExportFormat) -> String {
        var parts: [String] = []
        parts.append("\"about\":\(WGChatExportJSON.string(WGStrings.ChatExport.Output.about))")
        if let peer = data.peer {
            let name = WGChatExportAccount.userName(peer)
            parts.append("\"personal_information\":" + WGChatExportJSON.object([
                ("user_id", "\(peer.id.id._internalGetInt64Value())"),
                ("first_name", WGChatExportJSON.string(name.first)),
                ("last_name", WGChatExportJSON.string(name.last)),
                ("phone_number", WGChatExportAccount.phone(peer).map(WGChatExportJSON.string)),
                ("username", peer.addressName.map { WGChatExportJSON.string("@" + $0) }),
                ("bio", data.about.map(WGChatExportJSON.string))
            ]))
        }
        var photoObjects: [String] = []
        for (index, photo) in data.photos.enumerated() {
            let path = index < photoPaths.count ? photoPaths[index] : nil
            photoObjects.append(WGChatExportJSON.object([
                ("date", WGChatExportJSON.string(format.iso(photo.date))),
                ("date_unixtime", WGChatExportJSON.string("\(photo.date)")),
                ("photo", WGChatExportJSON.string(path ?? WGChatExportJSON.notIncluded))
            ]))
        }
        parts.append("\"profile_pictures\":[" + photoObjects.joined(separator: ",") + "]")
        parts.append("\"contacts\":" + WGChatExportJSON.section(about: WGStrings.ChatExport.Output.contactsAbout, objects: data.contacts.map { peer in
            let name = WGChatExportAccount.userName(peer)
            return WGChatExportJSON.object([
                ("user_id", "\(peer.id.id._internalGetInt64Value())"),
                ("first_name", WGChatExportJSON.string(name.first)),
                ("last_name", WGChatExportJSON.string(name.last)),
                ("phone_number", WGChatExportJSON.string(WGChatExportAccount.phone(peer) ?? ""))
            ])
        }))
        parts.append("\"frequent_contacts\":" + WGChatExportJSON.section(about: WGStrings.ChatExport.Output.frequentAbout, objects: data.frequent.map { peer in
            var type = "user"
            if case let .channel(channel) = peer {
                if case .broadcast = channel.info {
                    type = "public_channel"
                } else {
                    type = "public_supergroup"
                }
            } else if case .legacyGroup = peer {
                type = "private_group"
            }
            return WGChatExportJSON.object([
                ("id", "\(peer.id.id._internalGetInt64Value())"),
                ("category", "\"people\""),
                ("type", WGChatExportJSON.string(type)),
                ("name", WGChatExportJSON.string(peer.debugDisplayTitle)),
                ("rating", "0")
            ])
        }))
        parts.append("\"sessions\":" + WGChatExportJSON.section(about: WGStrings.ChatExport.Output.sessionsAbout, objects: data.sessions.map { session in
            return WGChatExportJSON.object([
                ("last_active", WGChatExportJSON.string(format.iso(session.activityDate))),
                ("last_active_unixtime", WGChatExportJSON.string("\(session.activityDate)")),
                ("last_ip", WGChatExportJSON.string(session.ip)),
                ("last_country", WGChatExportJSON.string(session.country)),
                ("last_region", WGChatExportJSON.string(session.region)),
                ("application_name", WGChatExportJSON.string(session.appName)),
                ("application_version", WGChatExportJSON.string(session.appVersion)),
                ("device_model", WGChatExportJSON.string(session.deviceModel)),
                ("platform", WGChatExportJSON.string(session.platform)),
                ("system_version", WGChatExportJSON.string(session.systemVersion)),
                ("created", WGChatExportJSON.string(format.iso(session.creationDate))),
                ("created_unixtime", WGChatExportJSON.string("\(session.creationDate)"))
            ])
        }))
        parts.append("\"web_sessions\":" + WGChatExportJSON.section(about: WGStrings.ChatExport.Output.webSessionsAbout, objects: data.webSessions.map { session in
            let bot = data.webSessionPeers[session.botId]?.addressName.map { "@" + $0 }
            return WGChatExportJSON.object([
                ("last_active", WGChatExportJSON.string(format.iso(session.dateActive))),
                ("last_active_unixtime", WGChatExportJSON.string("\(session.dateActive)")),
                ("last_ip", WGChatExportJSON.string(session.ip)),
                ("last_region", WGChatExportJSON.string(session.region)),
                ("bot_username", bot.map(WGChatExportJSON.string)),
                ("domain_name", WGChatExportJSON.string(session.domain)),
                ("browser", WGChatExportJSON.string(session.browser)),
                ("platform", WGChatExportJSON.string(session.platform)),
                ("created", WGChatExportJSON.string(format.iso(session.dateCreated))),
                ("created_unixtime", WGChatExportJSON.string("\(session.dateCreated)"))
            ])
        }))
        var storyObjects: [String] = []
        for (index, story) in data.stories.enumerated() {
            let path = index < storyPaths.count ? storyPaths[index] : nil
            storyObjects.append(WGChatExportJSON.object([
                ("date", WGChatExportJSON.string(format.iso(story.timestamp))),
                ("date_unixtime", WGChatExportJSON.string("\(story.timestamp)")),
                ("expires", WGChatExportJSON.string(format.iso(story.expirationTimestamp))),
                ("expires_unixtime", WGChatExportJSON.string("\(story.expirationTimestamp)")),
                ("pinned", story.isPinned ? "true" : "false"),
                ("media", WGChatExportJSON.string(path ?? WGChatExportJSON.notIncluded)),
                ("text", WGChatExportJSON.string(story.text))
            ]))
        }
        parts.append("\"stories\":[" + storyObjects.joined(separator: ",") + "]")
        return parts.joined(separator: ",\n")
    }

    /// The pages under `lists/` and the personal header of the index.
    static func htmlLists(_ data: WGChatExportAccountData, photoPaths: [String?], storyPaths: [String?], format: WGChatExportFormat) -> [String: String] {
        let prefix = "../"
        var pages: [String: String] = [:]
        pages["lists/contacts.html"] = WGChatExportHTML.listPage(title: WGStrings.ChatExport.Output.contacts, rows: data.contacts.map { peer in
            return (peer.debugDisplayTitle, [(WGStrings.ChatExport.Output.phone, WGChatExportAccount.phone(peer) ?? "")])
        }, assetPrefix: prefix)
        pages["lists/frequent.html"] = WGChatExportHTML.listPage(title: WGStrings.ChatExport.Output.frequent, rows: data.frequent.map { peer in
            return (peer.debugDisplayTitle, [(WGStrings.ChatExport.Output.username, peer.addressName.map { "@" + $0 } ?? "")])
        }, assetPrefix: prefix)
        pages["lists/sessions.html"] = WGChatExportHTML.listPage(title: WGStrings.ChatExport.Output.sessions, rows: data.sessions.map { session in
            return ("\(session.appName) \(session.appVersion)", [
                (WGStrings.ChatExport.Output.device, "\(session.deviceModel), \(session.platform) \(session.systemVersion)"),
                (WGStrings.ChatExport.Output.ip, session.ip),
                (WGStrings.ChatExport.Output.region, [session.region, session.country].filter { !$0.isEmpty }.joined(separator: ", ")),
                (WGStrings.ChatExport.Output.lastActive, format.full(session.activityDate)),
                (WGStrings.ChatExport.Output.created, format.full(session.creationDate))
            ])
        }, assetPrefix: prefix)
        pages["lists/web_sessions.html"] = WGChatExportHTML.listPage(title: WGStrings.ChatExport.Output.webSessions, rows: data.webSessions.map { session in
            return (session.domain, [
                (WGStrings.ChatExport.Output.bot, data.webSessionPeers[session.botId]?.addressName.map { "@" + $0 } ?? ""),
                (WGStrings.ChatExport.Output.browser, "\(session.browser), \(session.platform)"),
                (WGStrings.ChatExport.Output.ip, session.ip),
                (WGStrings.ChatExport.Output.region, session.region),
                (WGStrings.ChatExport.Output.lastActive, format.full(session.dateActive)),
                (WGStrings.ChatExport.Output.created, format.full(session.dateCreated))
            ])
        }, assetPrefix: prefix)
        var photoLinks: [(title: String, subtitle: String?, href: String)] = []
        for (index, photo) in data.photos.enumerated() {
            if index < photoPaths.count, let path = photoPaths[index] {
                photoLinks.append((format.full(photo.date), nil, prefix + path))
            }
        }
        pages["lists/profile_pictures.html"] = WGChatExportHTML.linksPage(title: WGStrings.ChatExport.Output.profilePictures, header: [], links: photoLinks, assetPrefix: prefix)
        var storyLinks: [(title: String, subtitle: String?, href: String)] = []
        for (index, story) in data.stories.enumerated() {
            if index < storyPaths.count, let path = storyPaths[index] {
                storyLinks.append((format.full(story.timestamp), story.text.isEmpty ? nil : story.text, prefix + path))
            }
        }
        pages["lists/stories.html"] = WGChatExportHTML.linksPage(title: WGStrings.ChatExport.Output.stories, header: [], links: storyLinks, assetPrefix: prefix)
        return pages
    }

    static func personalHeader(_ data: WGChatExportAccountData) -> [(String, String)] {
        guard let peer = data.peer else {
            return []
        }
        let name = WGChatExportAccount.userName(peer)
        return [
            (WGStrings.ChatExport.Output.name, [name.first, name.last].filter { !$0.isEmpty }.joined(separator: " ")),
            (WGStrings.ChatExport.Output.phone, WGChatExportAccount.phone(peer) ?? ""),
            (WGStrings.ChatExport.Output.username, peer.addressName.map { "@" + $0 } ?? ""),
            (WGStrings.ChatExport.Output.bio, data.about ?? "")
        ]
    }
}
