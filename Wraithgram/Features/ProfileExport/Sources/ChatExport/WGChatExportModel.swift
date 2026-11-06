import Foundation
import Postbox
import TelegramCore
import WGCore

// Chat export: the options, the job journal and the small formatting helpers shared by the writers.
// The output is the Telegram Desktop export tree (HTML pages of up to 1000 messages, `result.json`,
// media folders) so existing tools read it.

enum WGChatExportSettings {
    static let photos = WGSetting<Bool>("chatExport.photos", default: false)
    static let videos = WGSetting<Bool>("chatExport.videos", default: false)
    static let voiceMessages = WGSetting<Bool>("chatExport.voiceMessages", default: false)
    static let videoMessages = WGSetting<Bool>("chatExport.videoMessages", default: false)
    static let stickers = WGSetting<Bool>("chatExport.stickers", default: false)
    static let gifs = WGSetting<Bool>("chatExport.gifs", default: false)
    static let files = WGSetting<Bool>("chatExport.files", default: false)
    /// Megabytes; "0" = no limit.
    static let sizeLimit = WGSetting<String>("chatExport.sizeLimit", default: "8")
    /// "html", "json" or "both".
    static let format = WGSetting<String>("chatExport.format", default: "both")

    static let sizeLimitValues = ["8", "64", "512", "0"]

    static func declare() {
        let _ = WGChatExportSettings.photos
        let _ = WGChatExportSettings.videos
        let _ = WGChatExportSettings.voiceMessages
        let _ = WGChatExportSettings.videoMessages
        let _ = WGChatExportSettings.stickers
        let _ = WGChatExportSettings.gifs
        let _ = WGChatExportSettings.files
        let _ = WGChatExportSettings.sizeLimit
        let _ = WGChatExportSettings.format
    }

    static func currentOptions() -> WGChatExportOptions {
        let megabytes = Int64(WGChatExportSettings.sizeLimit.value) ?? 8
        let format = WGChatExportSettings.format.value
        return WGChatExportOptions(
            photos: WGChatExportSettings.photos.value,
            videos: WGChatExportSettings.videos.value,
            voiceMessages: WGChatExportSettings.voiceMessages.value,
            videoMessages: WGChatExportSettings.videoMessages.value,
            stickers: WGChatExportSettings.stickers.value,
            gifs: WGChatExportSettings.gifs.value,
            files: WGChatExportSettings.files.value,
            sizeLimitBytes: max(0, megabytes) * 1024 * 1024,
            html: format != "json",
            json: format != "html"
        )
    }
}

struct WGChatExportOptions: Codable, Equatable {
    var photos: Bool
    var videos: Bool
    var voiceMessages: Bool
    var videoMessages: Bool
    var stickers: Bool
    var gifs: Bool
    var files: Bool
    /// 0 = no limit.
    var sizeLimitBytes: Int64
    var html: Bool
    var json: Bool

    var includesMedia: Bool {
        return self.photos || self.videos || self.voiceMessages || self.videoMessages || self.stickers || self.gifs || self.files
    }
}

enum WGChatExportMode: Codable, Equatable {
    case chat(WGPeerKey)
    case account
}

enum WGChatExportStage: String, Codable {
    case planning
    case sections
    case chats
    case finished
    case failed
}

/// One chat of the job.
struct WGChatExportChat: Codable, Equatable {
    var peer: WGPeerKey
    var name: String
    /// Telegram Desktop's chat type ("personal_chat", "private_supergroup", …).
    var type: String
    /// Directory of the chat inside the tree, relative to the root ("" for a one-chat export).
    var directory: String
    var messages: Int
    var done: Bool
    /// History could not be loaded to the end (the server kept failing); the chat is still exported.
    var incomplete: Bool
}

/// The last message written to disk, as a history index. The peer is kept: a supergroup's history
/// starts with the messages of the group it was migrated from.
struct WGChatExportCursor: Codable, Equatable {
    var peer: WGPeerKey
    var timestamp: Int32
    var namespace: Int32
    var id: Int32

    init(_ index: MessageIndex) {
        self.peer = index.id.peerId.wgKey
        self.timestamp = index.timestamp
        self.namespace = index.id.namespace
        self.id = index.id.id
    }

    var index: MessageIndex {
        return MessageIndex(id: MessageId(peerId: PeerId(wgKey: self.peer), namespace: self.namespace, id: self.id), timestamp: self.timestamp)
    }
}

/// Everything needed to continue a job after the process was killed. Written after every
/// committed page (and every chat), atomically.
struct WGChatExportJournal: Codable {
    var version: Int
    var id: String
    var accountId: Int64
    var mode: WGChatExportMode
    var options: WGChatExportOptions
    var title: String
    /// Name of the export folder (`ChatExport_2026-10-22`, `DataExport_2026-10-22`).
    var outputName: String
    var createdAt: Int32
    var stage: WGChatExportStage
    var chats: [WGChatExportChat]
    var chatIndex: Int
    var cursor: WGChatExportCursor?
    /// The current chat's header is in `result.json` (its folder exists).
    var chatStarted: Bool
    /// Account export: the sections before the chats are written.
    var sectionsDone: Bool
    /// The next HTML page of the current chat (1 = `messages.html`).
    var nextPage: Int
    /// Bytes of `result.json` that belong to committed work; a resumed job truncates to it.
    var jsonLength: UInt64
    /// Messages of the current chat already in `result.json` (for the commas).
    var jsonMessagesInChat: Int
    var messagesTotal: Int
    var filesTotal: Int
    var bytesTotal: Int64
    /// Why the job stopped: `noSpace`, `writeFailed`, `chatNotFound`.
    var errorCode: String?
}

// MARK: - Formatting

/// Formatting for the export tree. Not thread-safe: one instance per job, used on its queue.
final class WGChatExportFormat {
    private let isoFormatter: DateFormatter
    private let timeFormatter: DateFormatter
    private let fullFormatter: DateFormatter
    private let dayFormatter: DateFormatter
    private let fileFormatter: DateFormatter

    init(languageCode: String) {
        let posix = Locale(identifier: "en_US_POSIX")
        self.isoFormatter = DateFormatter()
        self.isoFormatter.locale = posix
        self.isoFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        self.fileFormatter = DateFormatter()
        self.fileFormatter.locale = posix
        self.fileFormatter.dateFormat = "dd-MM-yyyy_HH-mm-ss"
        let locale = Locale(identifier: languageCode)
        self.timeFormatter = DateFormatter()
        self.timeFormatter.locale = locale
        self.timeFormatter.dateFormat = "HH:mm"
        self.fullFormatter = DateFormatter()
        self.fullFormatter.locale = locale
        self.fullFormatter.dateStyle = .medium
        self.fullFormatter.timeStyle = .medium
        self.dayFormatter = DateFormatter()
        self.dayFormatter.locale = locale
        self.dayFormatter.dateStyle = .long
        self.dayFormatter.timeStyle = .none
    }

    private static func date(_ timestamp: Int32) -> Date {
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    /// `2026-10-22T14:05:09`, local time, as Telegram Desktop writes it.
    func iso(_ timestamp: Int32) -> String {
        return self.isoFormatter.string(from: WGChatExportFormat.date(timestamp))
    }

    func time(_ timestamp: Int32) -> String {
        return self.timeFormatter.string(from: WGChatExportFormat.date(timestamp))
    }

    func full(_ timestamp: Int32) -> String {
        return self.fullFormatter.string(from: WGChatExportFormat.date(timestamp))
    }

    func day(_ timestamp: Int32) -> String {
        return self.dayFormatter.string(from: WGChatExportFormat.date(timestamp))
    }

    func fileDate(_ timestamp: Int32) -> String {
        return self.fileFormatter.string(from: WGChatExportFormat.date(timestamp))
    }

    func sameDay(_ lhs: Int32, _ rhs: Int32) -> Bool {
        return Calendar.current.isDate(WGChatExportFormat.date(lhs), inSameDayAs: WGChatExportFormat.date(rhs))
    }

    static func fileSize(_ bytes: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func duration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let rest = seconds % 60
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, rest)
        }
        return String(format: "%d:%02d", minutes, rest)
    }
}

enum WGChatExportEscape {
    static func html(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&":
                result.append("&amp;")
            case "<":
                result.append("&lt;")
            case ">":
                result.append("&gt;")
            case "\"":
                result.append("&quot;")
            case "'":
                result.append("&#39;")
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    /// HTML with line breaks kept.
    static func htmlMultiline(_ text: String) -> String {
        return WGChatExportEscape.html(text).replacingOccurrences(of: "\n", with: "<br>")
    }

    /// A JSON string literal, quotes included.
    static func json(_ text: String) -> String {
        var result = "\""
        result.reserveCapacity(text.utf8.count + 2)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"":
                result.append("\\\"")
            case "\\":
                result.append("\\\\")
            case "\n":
                result.append("\\n")
            case "\r":
                result.append("\\r")
            case "\t":
                result.append("\\t")
            default:
                if scalar.value < 0x20 || scalar.value == 0x2028 || scalar.value == 0x2029 {
                    result.append(String(format: "\\u%04x", scalar.value))
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        result.append("\"")
        return result
    }

    /// Only links that are safe to open from a page in a browser.
    static func safeLink(_ url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let scheme = URL(string: trimmed)?.scheme?.lowercased() else {
            // A bare domain («example.com») is a web link.
            if !trimmed.isEmpty && !trimmed.contains(":") {
                return "https://" + trimmed
            }
            return nil
        }
        switch scheme {
        case "http", "https", "tg", "mailto", "tel":
            return trimmed
        default:
            return nil
        }
    }

    /// A file or folder name without path separators or control characters.
    static func fileName(_ name: String) -> String {
        var result = ""
        for scalar in name.unicodeScalars {
            if scalar == "/" || scalar == "\\" || scalar == ":" || scalar.value < 0x20 {
                result.append("_")
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if result.isEmpty {
            return "file"
        }
        if result.count > 120 {
            result = String(result.suffix(120))
        }
        return result
    }
}
