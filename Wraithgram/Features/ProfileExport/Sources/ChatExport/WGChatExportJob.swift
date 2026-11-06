import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import WGCore

// One export: a state machine on its own utility queue (never the main thread, never Postbox's),
// with a journal on disk after every committed page so a killed process can continue where it was.
//
// Per chat: windows of ≤ 200 messages are read oldest first and turned into plain items (no
// `Message` is kept), up to one page of 1000 is buffered; when a page is complete its media are
// downloaded and linked into the tree, the page goes to `messagesN.html` and to `result.json`, both
// are flushed, and the journal is written. Memory stays at one page; disk space is checked before
// every chat.

struct WGChatExportProgress: Equatable {
    var jobId: String
    var title: String
    var stage: WGChatExportStage
    var isRunning: Bool
    var chatName: String?
    var chatIndex: Int
    var chatCount: Int
    var messages: Int
    var files: Int
    var bytes: Int64
    /// `noSpace`, `writeFailed`, `chatNotFound`.
    var errorCode: String?
}

final class WGChatExportJob {
    static let minimumFreeSpace: Int64 = 150 * 1024 * 1024
    static let windowRetries = 4

    let id: String
    let directory: URL
    let context: AccountContext
    private let queue = Queue(name: "org.wraithgram.chatExport", qos: .utility)
    private let environment: WGChatExportEnvironment
    private let format: WGChatExportFormat
    private let progressPromise: ValuePromise<WGChatExportProgress>

    // Queue only.
    private var journal: WGChatExportJournal
    private var json: WGChatExportStream?
    private let currentDisposable = MetaDisposable()
    private var isStopped = false
    private var buffer: [WGChatExportItem] = []
    private var loadedCursor: MessageIndex?
    private var lastWrittenItem: WGChatExportItem?
    private var retries = 0

    static var rootDirectory: URL? {
        return WGProfileExportPaths.supportDirectory("export")
    }

    var progress: Signal<WGChatExportProgress, NoError> {
        return self.progressPromise.get()
    }

    private var outputURL: URL {
        return self.directory.appendingPathComponent("output", isDirectory: true).appendingPathComponent(self.journal.outputName, isDirectory: true)
    }

    /// The finished tree (to save or share). Valid once the progress says `.finished`.
    var resultURL: URL {
        return self.outputURL
    }

    init(context: AccountContext, journal: WGChatExportJournal, directory: URL, environment: WGChatExportEnvironment) {
        self.id = journal.id
        self.context = context
        self.journal = journal
        self.directory = directory
        self.environment = environment
        self.format = WGChatExportFormat(languageCode: WGLocalization.shared.languageCode)
        self.progressPromise = ValuePromise(WGChatExportJob.makeProgress(journal, chatName: nil, isRunning: true), ignoreRepeated: true)
    }

    deinit {
        self.currentDisposable.dispose()
    }

    static func makeJournal(id: String, accountId: Int64, mode: WGChatExportMode, options: WGChatExportOptions, title: String) -> WGChatExportJournal {
        let now = Int32(Date().timeIntervalSince1970)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.string(from: Date())
        let outputName: String
        switch mode {
        case .chat:
            outputName = "ChatExport_\(date)"
        case .account:
            outputName = "DataExport_\(date)"
        }
        return WGChatExportJournal(version: 1, id: id, accountId: accountId, mode: mode, options: options, title: title, outputName: outputName, createdAt: now, stage: .planning, chats: [], chatIndex: 0, cursor: nil, chatStarted: false, sectionsDone: false, nextPage: 1, jsonLength: 0, jsonMessagesInChat: 0, messagesTotal: 0, filesTotal: 0, bytesTotal: 0, errorCode: nil)
    }

    private static func makeProgress(_ journal: WGChatExportJournal, chatName: String?, isRunning: Bool) -> WGChatExportProgress {
        return WGChatExportProgress(jobId: journal.id, title: journal.title, stage: journal.stage, isRunning: isRunning, chatName: chatName, chatIndex: journal.chatIndex, chatCount: journal.chats.count, messages: journal.messagesTotal, files: journal.filesTotal, bytes: journal.bytesTotal, errorCode: journal.errorCode)
    }

    static func freeSpace() -> Int64? {
        let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    // MARK: - Control

    func start() {
        self.queue.async {
            self.isStopped = false
            if self.journal.stage == .failed {
                // A failed job (no space, a write error) continues from its journal.
                if self.journal.chats.isEmpty {
                    self.journal.stage = .planning
                } else if self.journal.mode == .account && !self.journal.sectionsDone {
                    self.journal.stage = .sections
                } else {
                    self.journal.stage = .chats
                }
                self.journal.errorCode = nil
            }
            self.run()
        }
    }

    /// Stops the job and deletes everything it wrote.
    func cancel(completion: @escaping () -> Void) {
        self.queue.async {
            self.isStopped = true
            self.currentDisposable.set(nil)
            self.json?.close()
            self.json = nil
            try? FileManager.default.removeItem(at: self.directory)
            Queue.mainQueue().async {
                completion()
            }
        }
    }

    // MARK: - State machine (queue)

    private func publish(isRunning: Bool = true) {
        var chatName: String?
        if self.journal.chatIndex < self.journal.chats.count {
            chatName = self.journal.chats[self.journal.chatIndex].name
        }
        self.progressPromise.set(WGChatExportJob.makeProgress(self.journal, chatName: chatName, isRunning: isRunning && !self.isStopped))
    }

    private func saveJournal() {
        guard let data = try? JSONEncoder().encode(self.journal) else {
            return
        }
        try? data.write(to: self.directory.appendingPathComponent("job.json"), options: .atomic)
    }

    private func fail(_ code: String) {
        self.journal.stage = .failed
        self.journal.errorCode = code
        self.json?.close()
        self.json = nil
        self.saveJournal()
        self.publish(isRunning: false)
    }

    private func run() {
        if self.isStopped {
            return
        }
        self.publish()
        switch self.journal.stage {
        case .planning:
            self.plan()
        case .sections:
            self.sections()
        case .chats:
            self.nextChat()
        case .finished, .failed:
            self.publish(isRunning: false)
        }
    }

    private func next(_ step: @escaping () -> Void) {
        self.queue.async {
            if !self.isStopped {
                step()
            }
        }
    }

    private func openJSON(length: UInt64) -> Bool {
        if !self.journal.options.json {
            return true
        }
        do {
            self.json?.close()
            self.json = try WGChatExportStream(url: self.outputURL.appendingPathComponent("result.json"), length: length)
            return true
        } catch {
            return false
        }
    }

    private func appendJSON(_ text: String) -> Bool {
        guard self.journal.options.json else {
            return true
        }
        guard let json = self.json else {
            return false
        }
        do {
            try json.append(text)
            return true
        } catch {
            return false
        }
    }

    /// Flushes `result.json` and records its length in the journal.
    private func commitJSON() -> Bool {
        guard self.journal.options.json else {
            return true
        }
        guard let json = self.json, let length = try? json.commit() else {
            return false
        }
        self.journal.jsonLength = length
        return true
    }

    private func writeFile(_ relativePath: String, _ text: String) -> Bool {
        let url = self.outputURL.appendingPathComponent(relativePath)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try Data(text.utf8).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private func plan() {
        let postbox = self.context.account.postbox
        let accountPeerId = self.environment.accountPeerId
        let peers: Signal<[Peer], NoError>
        switch self.journal.mode {
        case let .chat(peerKey):
            peers = postbox.transaction { transaction -> [Peer] in
                if let peer = transaction.getPeer(PeerId(wgKey: peerKey)) {
                    return [peer]
                }
                return []
            }
        case .account:
            peers = WGChatExportAccount.chatPeers(postbox: postbox, queue: self.queue)
        }
        self.currentDisposable.set((peers |> deliverOn(self.queue)).start(next: { [weak self] peers in
            guard let self = self, !self.isStopped else {
                return
            }
            if peers.isEmpty, case .chat = self.journal.mode {
                self.fail("chatNotFound")
                return
            }
            var chats: [WGChatExportChat] = []
            for (index, peer) in peers.enumerated() {
                var directory = ""
                if case .account = self.journal.mode {
                    directory = String(format: "chats/chat_%03d", index + 1)
                }
                chats.append(WGChatExportChat(peer: peer.id.wgKey, name: WGChatExportConvert.name(peer, environment: self.environment), type: WGChatExportConvert.chatType(peer, accountPeerId: accountPeerId), directory: directory, messages: 0, done: false, incomplete: false))
            }
            self.journal.chats = chats
            do {
                try FileManager.default.createDirectory(at: self.outputURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                self.fail("writeFailed")
                return
            }
            if self.journal.options.html && !self.writeFile("css/style.css", WGChatExportHTML.stylesheet) {
                self.fail("writeFailed")
                return
            }
            if case .account = self.journal.mode {
                self.journal.stage = .sections
            } else {
                self.journal.stage = .chats
            }
            self.saveJournal()
            self.next {
                self.run()
            }
        }))
    }

    // MARK: Sections (account export)

    private func sections() {
        guard self.openJSON(length: 0) else {
            self.fail("writeFailed")
            return
        }
        let options = self.journal.options
        let accountPeerId = self.environment.accountPeerId
        self.currentDisposable.set((WGChatExportAccount.collect(context: self.context, queue: self.queue)
        |> deliverOn(self.queue)).start(next: { [weak self] data in
            guard let self = self, !self.isStopped else {
                return
            }
            var photoMedia: [WGChatExportMedia?] = []
            for photo in data.photos {
                guard options.photos, let representation = largestImageRepresentation(photo.image.representations), let peer = data.peer.flatMap({ PeerReference($0._asPeer()) }) else {
                    photoMedia.append(nil)
                    continue
                }
                let media = WGChatExportMedia(kind: .photo, reference: .media(media: .avatarList(peer: peer, media: photo.image), resource: representation.resource), size: representation.resource.size, fileName: nil, mimeType: "image/jpeg", width: Int(representation.dimensions.width), height: Int(representation.dimensions.height), duration: nil, stickerEmoji: nil, targetName: "photo_\(photo.index + 1)@\(self.format.fileDate(photo.date)).jpg")
                media.state = .pending
                photoMedia.append(media)
            }
            var storyMedia: [WGChatExportMedia?] = []
            for story in data.stories {
                storyMedia.append(self.storyMedia(story, accountPeer: data.peer, options: options))
            }
            let photoDirectory = self.outputURL.appendingPathComponent("profile_pictures", isDirectory: true)
            let storyDirectory = self.outputURL.appendingPathComponent("stories", isDirectory: true)
            self.saveMedia(photoMedia.compactMap { $0 }, peerId: accountPeerId, folder: photoDirectory, byKind: false, completion: {
                self.saveMedia(storyMedia.compactMap { $0 }, peerId: accountPeerId, folder: storyDirectory, byKind: false, completion: {
                    let photoPaths = photoMedia.map { media -> String? in
                        return media?.relativePath.map { "profile_pictures/" + $0 }
                    }
                    let storyPaths = storyMedia.map { media -> String? in
                        return media?.relativePath.map { "stories/" + $0 }
                    }
                    self.finishSections(data, photoPaths: photoPaths, storyPaths: storyPaths)
                })
            })
        }))
    }

    private func storyMedia(_ story: EngineStoryItem, accountPeer: EnginePeer?, options: WGChatExportOptions) -> WGChatExportMedia? {
        guard let peer = accountPeer.flatMap({ PeerReference($0._asPeer()) }) else {
            return nil
        }
        let media = story.media._asMedia()
        let datePart = self.format.fileDate(story.timestamp)
        if let image = media as? TelegramMediaImage, options.photos, let representation = largestImageRepresentation(image.representations) {
            let result = WGChatExportMedia(kind: .photo, reference: .media(media: .story(peer: peer, id: story.id, media: image), resource: representation.resource), size: representation.resource.size, fileName: nil, mimeType: "image/jpeg", width: Int(representation.dimensions.width), height: Int(representation.dimensions.height), duration: nil, stickerEmoji: nil, targetName: "story_\(story.id)@\(datePart).jpg")
            result.state = .pending
            return result
        }
        if let file = media as? TelegramMediaFile, options.videos {
            if options.sizeLimitBytes > 0, let size = file.size, size > options.sizeLimitBytes {
                return nil
            }
            let result = WGChatExportMedia(kind: .video, reference: .media(media: .story(peer: peer, id: story.id, media: file), resource: file.resource), size: file.size, fileName: nil, mimeType: file.mimeType, width: nil, height: nil, duration: file.duration.flatMap { Int($0) }, stickerEmoji: nil, targetName: "story_\(story.id)@\(datePart).mp4")
            result.state = .pending
            return result
        }
        return nil
    }

    private func finishSections(_ data: WGChatExportAccountData, photoPaths: [String?], storyPaths: [String?]) {
        if self.journal.options.json {
            let prefix = "{\n" + WGChatExportAccount.jsonSections(data, photoPaths: photoPaths, storyPaths: storyPaths, format: self.format) + ",\n\"chats\":{\"about\":\(WGChatExportJSON.string(WGStrings.ChatExport.Output.chatsAbout)),\"list\":["
            guard self.appendJSON(prefix), self.commitJSON() else {
                self.fail("writeFailed")
                return
            }
        }
        if self.journal.options.html {
            for (path, page) in WGChatExportAccount.htmlLists(data, photoPaths: photoPaths, storyPaths: storyPaths, format: self.format) {
                if !self.writeFile(path, page) {
                    self.fail("writeFailed")
                    return
                }
            }
            if let header = try? JSONEncoder().encode(WGChatExportAccount.personalHeader(data).map { [$0.0, $0.1] }) {
                try? header.write(to: self.directory.appendingPathComponent("personal.json"), options: .atomic)
            }
        }
        self.journal.sectionsDone = true
        self.journal.stage = .chats
        self.saveJournal()
        self.next {
            self.run()
        }
    }

    /// Downloads media one by one into `folder` (into its kind's subfolder when `byKind`).
    private func saveMedia(_ items: [WGChatExportMedia], peerId: PeerId, folder: URL, byKind: Bool, completion: @escaping () -> Void) {
        self.saveMediaStep(items[...], peerId: peerId, folder: folder, byKind: byKind, completion: completion)
    }

    private func saveMediaStep(_ remaining: ArraySlice<WGChatExportMedia>, peerId: PeerId, folder: URL, byKind: Bool, completion: @escaping () -> Void) {
        if self.isStopped {
            return
        }
        guard let media = remaining.first else {
            completion()
            return
        }
        let rest = remaining.dropFirst()
        switch media.state {
        case .notIncluded, .tooLarge, .saved, .unavailable:
            self.next {
                self.saveMediaStep(rest, peerId: peerId, folder: folder, byKind: byKind, completion: completion)
            }
            return
        case .pending:
            break
        }
        self.currentDisposable.set((WGChatExportLoader.save(media, postbox: self.context.account.postbox, peerId: peerId, folder: folder, subfolder: byKind ? media.kind.directory : nil, connectionStatus: self.context.account.network.connectionStatus)
        |> deliverOn(self.queue)).start(next: { [weak self] bytes in
            guard let self = self else {
                return
            }
            if bytes > 0 {
                self.journal.filesTotal += 1
                self.journal.bytesTotal += bytes
            }
            self.publish()
            self.next {
                self.saveMediaStep(rest, peerId: peerId, folder: folder, byKind: byKind, completion: completion)
            }
        }))
    }

    // MARK: Chats

    private var currentChat: WGChatExportChat? {
        if self.journal.chatIndex < self.journal.chats.count {
            return self.journal.chats[self.journal.chatIndex]
        }
        return nil
    }

    private func chatDirectoryURL(_ chat: WGChatExportChat) -> URL {
        return chat.directory.isEmpty ? self.outputURL : self.outputURL.appendingPathComponent(chat.directory, isDirectory: true)
    }

    private func nextChat() {
        if self.json == nil && self.journal.options.json {
            // Started or resumed here: the file is cut back to the committed length.
            guard self.openJSON(length: self.journal.jsonLength) else {
                self.fail("writeFailed")
                return
            }
        }
        guard let chat = self.currentChat else {
            self.finish()
            return
        }
        if let free = WGChatExportJob.freeSpace(), free < WGChatExportJob.minimumFreeSpace {
            self.fail("noSpace")
            return
        }
        if !self.journal.chatStarted {
            var header = ""
            if case .account = self.journal.mode, self.journal.chatIndex > 0 {
                header = ",\n"
            }
            header += WGChatExportJSON.chatHeader(name: chat.name, type: chat.type, peerId: PeerId(wgKey: chat.peer))
            guard self.appendJSON(header), self.commitJSON() else {
                self.fail("writeFailed")
                return
            }
            try? FileManager.default.createDirectory(at: self.chatDirectoryURL(chat), withIntermediateDirectories: true, attributes: nil)
            self.journal.chatStarted = true
            self.journal.nextPage = 1
            self.journal.jsonMessagesInChat = 0
            self.journal.cursor = nil
            self.saveJournal()
        }
        self.buffer.removeAll()
        self.lastWrittenItem = nil
        self.loadedCursor = self.journal.cursor?.index
        self.retries = 0
        self.publish()
        self.loadWindow()
    }

    private func loadWindow() {
        guard let chat = self.currentChat else {
            return
        }
        let peerId = PeerId(wgKey: chat.peer)
        self.currentDisposable.set((WGChatExportLoader.window(postbox: self.context.account.postbox, peerId: peerId, after: self.loadedCursor, queue: self.queue)
        |> deliverOn(self.queue)).start(next: { [weak self] window in
            guard let self = self, !self.isStopped else {
                return
            }
            self.retries = 0
            for message in window.messages {
                self.buffer.append(WGChatExportConvert.item(message, environment: self.environment, options: self.journal.options, format: self.format))
            }
            if let last = window.messages.last {
                self.loadedCursor = last.index
            }
            self.drain(reachedEnd: window.reachedEnd || window.messages.isEmpty)
        }, error: { [weak self] _ in
            guard let self = self, !self.isStopped else {
                return
            }
            self.retries += 1
            if self.retries <= WGChatExportJob.windowRetries {
                WGLog.info("chatExport", "history window timed out, retry \(self.retries)")
                self.next {
                    self.loadWindow()
                }
            } else {
                WGLog.warning("chatExport", "history stays incomplete after retries")
                self.journal.chats[self.journal.chatIndex].incomplete = true
                self.drain(reachedEnd: true)
            }
        }))
    }

    /// Writes complete pages; at the end of the history, the rest and the chat's footer.
    private func drain(reachedEnd: Bool) {
        if self.buffer.count > WGChatExportHTML.pageSize {
            self.writePage(count: WGChatExportHTML.pageSize, hasNext: true, completion: {
                self.drain(reachedEnd: reachedEnd)
            })
        } else if reachedEnd {
            if self.buffer.isEmpty {
                self.finishChat()
            } else {
                self.writePage(count: self.buffer.count, hasNext: false, completion: {
                    self.finishChat()
                })
            }
        } else {
            self.next {
                self.loadWindow()
            }
        }
    }

    private func writePage(count: Int, hasNext: Bool, completion: @escaping () -> Void) {
        guard let chat = self.currentChat else {
            return
        }
        let items = Array(self.buffer.prefix(count))
        let chatDirectory = self.chatDirectoryURL(chat)
        let media = items.compactMap { $0.media }
        self.saveMedia(media, peerId: PeerId(wgKey: chat.peer), folder: chatDirectory, byKind: true, completion: {
            if self.journal.options.html {
                let assetPrefix = chat.directory.isEmpty ? "" : "../../"
                let page = WGChatExportHTML.messagesPage(chatTitle: chat.name, items: items, previous: self.lastWrittenItem, pageNumber: self.journal.nextPage, hasNext: hasNext, assetPrefix: assetPrefix, format: self.format)
                let path = (chat.directory.isEmpty ? "" : chat.directory + "/") + WGChatExportHTML.pageFileName(self.journal.nextPage)
                if !self.writeFile(path, page) {
                    self.fail("writeFailed")
                    return
                }
            }
            if self.journal.options.json {
                var text = ""
                for (offset, item) in items.enumerated() {
                    text += (self.journal.jsonMessagesInChat + offset) == 0 ? "\n" : ",\n"
                    text += WGChatExportJSON.message(item, chatDirectory: chat.directory, format: self.format)
                }
                guard self.appendJSON(text), self.commitJSON() else {
                    self.fail("writeFailed")
                    return
                }
            }
            if let last = items.last {
                self.journal.cursor = WGChatExportCursor(last.index)
                self.lastWrittenItem = last
            }
            self.journal.nextPage += 1
            self.journal.jsonMessagesInChat += items.count
            self.journal.messagesTotal += items.count
            self.journal.chats[self.journal.chatIndex].messages += items.count
            self.buffer.removeFirst(min(count, self.buffer.count))
            self.saveJournal()
            self.publish()
            self.next(completion)
        })
    }

    private func finishChat() {
        guard let chat = self.currentChat else {
            return
        }
        if self.journal.options.html && chat.messages == 0 && self.journal.nextPage == 1 {
            let path = (chat.directory.isEmpty ? "" : chat.directory + "/") + WGChatExportHTML.pageFileName(1)
            let page = WGChatExportHTML.messagesPage(chatTitle: chat.name, items: [], previous: nil, pageNumber: 1, hasNext: false, assetPrefix: chat.directory.isEmpty ? "" : "../../", format: self.format)
            if !self.writeFile(path, page) {
                self.fail("writeFailed")
                return
            }
        }
        guard self.appendJSON(WGChatExportJSON.chatFooter), self.commitJSON() else {
            self.fail("writeFailed")
            return
        }
        self.journal.chats[self.journal.chatIndex].done = true
        self.journal.chatIndex += 1
        self.journal.chatStarted = false
        self.journal.cursor = nil
        self.journal.nextPage = 1
        self.journal.jsonMessagesInChat = 0
        self.saveJournal()
        self.next {
            self.nextChat()
        }
    }

    private func finish() {
        if case .account = self.journal.mode {
            guard self.appendJSON("\n]}\n}\n"), self.commitJSON() else {
                self.fail("writeFailed")
                return
            }
            if self.journal.options.html {
                var links: [(title: String, subtitle: String?, href: String)] = []
                for chat in self.journal.chats {
                    var subtitle = WGStrings.ChatExport.Output.messages(count: chat.messages)
                    if chat.incomplete {
                        subtitle += " · " + WGStrings.ChatExport.Output.incomplete
                    }
                    links.append((chat.name, subtitle, "../" + chat.directory + "/" + WGChatExportHTML.pageFileName(1)))
                }
                let chatsPage = WGChatExportHTML.linksPage(title: WGStrings.ChatExport.Output.chats, header: [], links: links, assetPrefix: "../")
                var header: [(String, String)] = []
                if let data = try? Data(contentsOf: self.directory.appendingPathComponent("personal.json")), let pairs = try? JSONDecoder().decode([[String]].self, from: data) {
                    header = pairs.compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil }
                }
                let index = WGChatExportHTML.linksPage(title: WGStrings.ChatExport.Output.title, header: header, links: [
                    (WGStrings.ChatExport.Output.chats, WGStrings.ChatExport.Output.chatsCount(count: self.journal.chats.count), "lists/chats.html"),
                    (WGStrings.ChatExport.Output.contacts, nil, "lists/contacts.html"),
                    (WGStrings.ChatExport.Output.frequent, nil, "lists/frequent.html"),
                    (WGStrings.ChatExport.Output.sessions, nil, "lists/sessions.html"),
                    (WGStrings.ChatExport.Output.webSessions, nil, "lists/web_sessions.html"),
                    (WGStrings.ChatExport.Output.profilePictures, nil, "lists/profile_pictures.html"),
                    (WGStrings.ChatExport.Output.stories, nil, "lists/stories.html")
                ], assetPrefix: "")
                guard self.writeFile("lists/chats.html", chatsPage), self.writeFile("export_results.html", index) else {
                    self.fail("writeFailed")
                    return
                }
            }
        }
        self.json?.close()
        self.json = nil
        try? FileManager.default.removeItem(at: self.directory.appendingPathComponent("personal.json"))
        self.journal.stage = .finished
        self.saveJournal()
        self.publish(isRunning: false)
    }
}
