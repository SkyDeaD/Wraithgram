import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import WGCore
import WGSettingsUI
import WGFeaturesShared

// Menu rows of «Сообщения › Удалённые и изменённые», the «Сообщения» preview and the bookmark rows
// in «Меню и жесты». One place per setting; titles are computed at display time.

extension WGMenuTabID {
    static let antiDeleteHistory = WGMenuTabID("antiDelete.history")
    static let antiDeleteExclusions = WGMenuTabID("antiDelete.exclusions")
    static let bookmarksAll = WGMenuTabID("bookmarks.all")
}

extension WGMenuSectionID {
    static let antiDeleteEdits = WGMenuSectionID("antiDelete.edits")
    static let antiDeleteStorage = WGMenuSectionID("antiDelete.storage")
}

enum WGAntiDeleteMenu {
    private static var capturesAnything: Bool {
        return WGAntiDeleteSettings.enabled.value || WGAntiDeleteSettings.keepOwn.value || WGAntiDeleteSettings.keepSelfDestructing.value
    }

    private static func percent(_ value: Double) -> String {
        return WGStrings.AntiDelete.Menu.percent(value: "\(Int(value.rounded()))")
    }

    static func register() {
        let main = WGMenuSectionID.main(of: .messagesAntiDelete)

        // MARK: Previews

        WGMenuRegistry.register(WGMenuRow(
            id: "antiDelete.categoryPreview",
            section: .messagesPreview,
            order: 100,
            title: { "" },
            kind: .preview(.miniChat(WGMiniChatConfiguration(scope: "antiDelete", height: 300.0, content: { context in
                return WGAntiDeleteMenu.previewContent(context)
            })))
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "antiDelete.preview",
            section: .preview(of: .messagesAntiDelete),
            order: 100,
            title: { "" },
            kind: .preview(.miniChat(WGMiniChatConfiguration(scope: "antiDelete", height: 300.0, content: { context in
                return WGAntiDeleteMenu.previewContent(context)
            })))
        ))

        // MARK: Deleted messages

        WGMenuRegistry.register(WGMenuRow(
            id: "antiDelete.enabled",
            section: main,
            order: 100,
            title: { WGStrings.AntiDelete.Menu.enabled },
            subtitle: { WGStrings.AntiDelete.Menu.enabledInfo },
            kind: .toggle(.global(WGAntiDeleteSettings.enabled)),
            searchKeywords: { [WGStrings.AntiDelete.Menu.keywords] }
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "antiDelete.keepOwn",
            section: main,
            order: 200,
            title: { WGStrings.AntiDelete.Menu.keepOwn },
            subtitle: { WGStrings.AntiDelete.Menu.keepOwnInfo },
            kind: .toggle(.global(WGAntiDeleteSettings.keepOwn))
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "antiDelete.keepSelfDestructing",
            section: main,
            order: 300,
            title: { WGStrings.AntiDelete.Menu.keepSelfDestructing },
            subtitle: { WGStrings.AntiDelete.Menu.keepSelfDestructingInfo },
            kind: .toggle(.global(WGAntiDeleteSettings.keepSelfDestructing))
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "antiDelete.secretChats",
            section: main,
            order: 400,
            title: { WGStrings.AntiDelete.Menu.secretChats },
            subtitle: { WGStrings.AntiDelete.Menu.secretChatsInfo },
            kind: .toggle(.global(WGAntiDeleteSettings.secretChats)),
            isVisible: { _ in WGAntiDeleteMenu.capturesAnything || WGAntiDeleteSettings.editHistory.value }
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "antiDelete.keepMedia",
            section: main,
            order: 500,
            title: { WGStrings.AntiDelete.Menu.keepMedia },
            subtitle: { WGStrings.AntiDelete.Menu.keepMediaInfo },
            kind: .toggle(.global(WGAntiDeleteSettings.keepMedia)),
            isVisible: { _ in WGAntiDeleteMenu.capturesAnything }
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "antiDelete.transparency",
            section: main,
            order: 600,
            title: { WGStrings.AntiDelete.Menu.transparency },
            kind: .slider(.global(WGAntiDeleteSettings.transparency), range: WGAntiDeleteSettings.transparencyRange, step: 5.0, format: { value in
                return WGAntiDeleteMenu.percent(value)
            })
        ))
        // A reply to a deleted message needs no setting: it always goes as AyuGram's pseudo-reply
        // (an ordinary message with the quote on top) — the preview and «Сохранять удалённые» say so.

        // MARK: Edits and local edits — one section (owner, 2026-10-27: «сожмём вкладку»)

        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: .antiDeleteEdits, screen: .tab(.messagesAntiDelete), order: 300, header: { WGStrings.AntiDelete.Menu.editsHeader }, footer: { _ in WGStrings.AntiDelete.Menu.editsFooter }))
        WGMenuRegistry.register(WGMenuRow(
            id: "antiDelete.editHistory",
            section: .antiDeleteEdits,
            order: 100,
            title: { WGStrings.AntiDelete.Menu.editHistory },
            subtitle: { WGStrings.AntiDelete.Menu.editHistoryInfo },
            kind: .toggle(.global(WGAntiDeleteSettings.editHistory)),
            searchKeywords: { [WGStrings.AntiDelete.Menu.editKeywords] }
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "antiDelete.editHistoryInline",
            section: .antiDeleteEdits,
            order: 200,
            title: { WGStrings.AntiDelete.Menu.editHistoryInline },
            subtitle: { WGStrings.AntiDelete.Menu.editHistoryInlineInfo },
            kind: .toggle(.global(WGAntiDeleteSettings.editHistoryInline)),
            isVisible: { _ in WGAntiDeleteSettings.editHistory.value }
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "antiDelete.versionsTransparency",
            section: .antiDeleteEdits,
            order: 300,
            title: { WGStrings.AntiDelete.Menu.versionsTransparency },
            kind: .slider(.global(WGAntiDeleteSettings.versionsTransparency), range: WGAntiDeleteSettings.transparencyRange, step: 5.0, format: { value in
                return WGAntiDeleteMenu.percent(value)
            }),
            isVisible: { _ in WGAntiDeleteSettings.editHistory.value && WGAntiDeleteSettings.editHistoryInline.value }
        ))

        WGMenuRegistry.register(WGMenuRow(
            id: "antiDelete.localEdit",
            section: .antiDeleteEdits,
            order: 500,
            title: { WGStrings.AntiDelete.Menu.localEdit },
            subtitle: { WGStrings.AntiDelete.Menu.localEditInfo },
            kind: .toggle(.global(WGAntiDeleteSettings.localEdit))
        ))

        // MARK: Storage

        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: .antiDeleteStorage, screen: .tab(.messagesAntiDelete), order: 600, header: { WGStrings.AntiDelete.Menu.storageHeader }, footer: { _ in WGStrings.AntiDelete.Menu.autoClearFooter }))
        WGMenuRegistry.register(
            tab: WGMenuTabDescriptor(
                id: .antiDeleteHistory,
                parent: .tab(.messagesAntiDelete),
                title: { WGStrings.AntiDelete.History.title },
                makeScreen: { context in
                    return wgMakeAntiDeleteHistoryController(context: context.context, kind: .deleted)
                },
                searchKeywords: { [WGStrings.AntiDelete.Menu.historyKeywords] }
            ),
            linkIn: .antiDeleteStorage,
            order: 100,
            subtitle: { WGStrings.AntiDelete.Menu.historyInfo },
            icon: .bundle("Chat/Context Menu/Time"),
            label: { context in
                let deleted = WGAntiDeleteAccounts.shared.summary(account: context.context.account.id, kind: .deleted).totalCount
                let edited = WGAntiDeleteAccounts.shared.summary(account: context.context.account.id, kind: .edited).totalCount
                if deleted + edited == 0 {
                    return nil
                }
                return "\(deleted + edited)"
            }
        )
        WGMenuRegistry.register(
            tab: WGMenuTabDescriptor(
                id: .antiDeleteExclusions,
                parent: .tab(.messagesAntiDelete),
                title: { WGStrings.AntiDelete.Exclusions.title },
                makeScreen: { context in
                    return wgMakeAntiDeleteExclusionsController(context: context.context)
                },
                searchKeywords: { [WGStrings.AntiDelete.Menu.exclusionsKeywords] }
            ),
            linkIn: .antiDeleteStorage,
            order: 200,
            subtitle: { WGStrings.AntiDelete.Menu.exclusionsInfo },
            icon: .bundle("Chat/Context Menu/Ban"),
            label: { context in
                let account = context.accountID
                var count = WGAntiDeleteSettings.excludedPeers.value(for: account).count + WGAntiDeleteSettings.excludedFolders.value(for: account).count
                for setting in [WGAntiDeleteSettings.excludeGroups, WGAntiDeleteSettings.excludeBots, WGAntiDeleteSettings.excludeChannels] where setting.value {
                    count += 1
                }
                return count == 0 ? nil : "\(count)"
            }
        )
        WGMenuRegistry.register(WGMenuRow(
            id: "antiDelete.autoClear",
            section: .antiDeleteStorage,
            order: 300,
            title: { WGStrings.AntiDelete.Menu.autoClear },
            icon: .bundle("Chat/Context Menu/Timer"),
            kind: .choice(.global(WGAntiDeleteSettings.autoClear), options: WGAntiDeleteRetention.allCases.map { retention in
                return WGMenuChoiceOption(value: retention.rawValue, title: { WGAntiDeleteMenu.retentionTitle(retention) })
            })
        ))

        // MARK: Bookmarks («Меню и жесты»)

        let gestures = WGMenuSectionID.main(of: .messagesMenuGestures)
        WGMenuRegistry.register(WGMenuRow(
            id: "bookmarks.enabled",
            section: gestures,
            order: 800,
            title: { WGStrings.Bookmarks.Menu.enabled },
            subtitle: { WGStrings.Bookmarks.Menu.enabledInfo },
            icon: .bundle("Chat/Context Menu/Tag"),
            kind: .toggle(.global(WGBookmarkSettings.enabled)),
            searchKeywords: { [WGStrings.Bookmarks.Menu.keywords] }
        ))
        WGMenuRegistry.register(
            tab: WGMenuTabDescriptor(
                id: .bookmarksAll,
                parent: .tab(.messagesMenuGestures),
                title: { WGStrings.Bookmarks.All.title },
                makeScreen: { context in
                    return wgMakeBookmarksController(context: context.context, peerId: nil)
                },
                searchKeywords: { [WGStrings.Bookmarks.Menu.keywords] }
            ),
            linkIn: gestures,
            order: 900,
            subtitle: { WGStrings.Bookmarks.Menu.allInfo },
            icon: .bundle("Chat/Context Menu/ReadingList")
        )
    }

    static func retentionTitle(_ retention: WGAntiDeleteRetention) -> String {
        switch retention {
        case .never:
            return WGStrings.AntiDelete.AutoClear.never
        case .day:
            return WGStrings.AntiDelete.AutoClear.day
        case .week:
            return WGStrings.AntiDelete.AutoClear.week
        case .month:
            return WGStrings.AntiDelete.AutoClear.month
        case .quarter:
            return WGStrings.AntiDelete.AutoClear.quarter
        case .year:
            return WGStrings.AntiDelete.AutoClear.year
        }
    }

    /// The «Сообщения» preview, as the chat shows it with the current switches: while deleted
    /// messages are kept, a deleted one with the current transparency and a reply to it exactly as
    /// it is sent — AyuGram's pseudo-reply, the quote on top (no author line: a one-to-one chat with
    /// that author); with them off neither exists, as in Telegram. The edited message carries the
    /// history mark only while the history is kept.
    static func previewContent(_ context: WGMenuContext) -> WGMiniChatContent {
        let keepsDeleted = WGAntiDeleteSettings.enabled.value
        let deletedText = WGStrings.AntiDelete.Preview.deletedText
        let transparency = context.displayValue(.global(WGAntiDeleteSettings.transparency))
        var messages: [WGPreviewMessage] = []
        messages.append(WGPreviewMessage(id: 1, isOutgoing: false, text: WGStrings.AntiDelete.Preview.firstText, ageSeconds: 900))
        if keepsDeleted {
            messages.append(WGPreviewMessage(id: 2, isOutgoing: false, text: deletedText, alpha: WGAntiDeleteSettings.alpha(forTransparency: transparency), mark: WGPreviewMark(statusText: WGAntiDeleteDecorations.deletedMark), ageSeconds: 840))
        }
        let historyMark: WGPreviewMark? = WGAntiDeleteSettings.editHistory.value ? WGPreviewMark(statusText: WGAntiDeleteDecorations.historyMark(versionCount: 1)) : nil
        messages.append(WGPreviewMessage(id: 3, isOutgoing: false, text: WGStrings.AntiDelete.Preview.editedText, isEdited: true, mark: historyMark, ageSeconds: 600))
        if keepsDeleted {
            messages.append(WGPreviewMessage(id: 4, isOutgoing: true, text: WGStrings.AntiDelete.Preview.replyText, quote: deletedText, ageSeconds: 300))
        }
        return WGMiniChatContent(header: WGMiniChatContent.sampleHeader(), messages: messages)
    }
}
