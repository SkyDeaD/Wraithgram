import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import PresentationDataUtils
import AlertUI
import WGCore
import WGSettingsUI
import WGFeaturesShared

extension WGMenuTabID {
    static let ghostActivities = WGMenuTabID("ghostMode.activities")
}

extension WGMenuSectionID {
    static let ghostActivitiesMain = WGMenuSectionID("ghostMode.activities.main")
    static let ghostExceptionTypes = WGMenuSectionID("ghostMode.exceptions.types")
}

/// Rows of the «Приватность» category (PLAN §2.1): preview, the ghost-mode group and its rows, the
/// exceptions and send-delay tabs, «Следы»; plus «Скрыть сообщения заблокированных» in the
/// «Сообщения › Чаты» section where PLAN §2.2 puts it.
enum WGGhostMenu {
    static func register() {
        WGGhostPreview.register()
        WGGhostMenu.registerGhostSection()
        WGGhostMenu.registerActivitiesTab()
        WGGhostMenu.registerExceptionsTab()
        WGGhostMenu.registerSendDelayTab()
        WGGhostMenu.registerTraces()
        WGGhostMenu.registerChatsSection()
    }

    // MARK: Ghost mode

    private static func registerGhostSection() {
        let section = WGMenuSectionID.privacyGhostMode

        WGMenuRegistry.register(WGMenuRow(
            id: "ghostMode.group",
            section: section,
            order: 100,
            title: { WGStrings.GhostMode.Menu.group },
            subtitle: { WGStrings.GhostMode.Menu.groupInfo },
            kind: .expandableGroup(master: .account(WGGhostSettings.isEnabled), children: [
                WGMenuRow(id: "ghostMode.hideReadReceipts", section: section, order: 100, title: { WGStrings.GhostMode.Menu.hideReadReceipts }, subtitle: { WGStrings.GhostMode.Menu.hideReadReceiptsInfo }, kind: .toggle(.account(WGGhostSettings.hideReadReceipts)), searchKeywords: { [WGStrings.GhostMode.Menu.keywordRead] }),
                WGMenuRow(id: "ghostMode.hideStoryViews", section: section, order: 200, title: { WGStrings.GhostMode.Menu.hideStoryViews }, subtitle: { WGStrings.GhostMode.Menu.hideStoryViewsInfo }, kind: .toggle(.account(WGGhostSettings.hideStoryViews)), searchKeywords: { [WGStrings.GhostMode.Menu.keywordStories] }),
                WGMenuRow(id: "ghostMode.hideOnline", section: section, order: 300, title: { WGStrings.GhostMode.Menu.hideOnline }, subtitle: { WGStrings.GhostMode.Menu.hideOnlineInfo }, kind: .toggle(.account(WGGhostSettings.hideOnline)), searchKeywords: { [WGStrings.GhostMode.Menu.keywordOnline] }),
                WGMenuRow(id: "ghostMode.hideTyping", section: section, order: 400, title: { WGStrings.GhostMode.Menu.hideTyping }, subtitle: { WGStrings.GhostMode.Menu.hideTypingInfo }, kind: .toggle(.account(WGGhostSettings.hideTyping)), searchKeywords: { [WGStrings.GhostMode.Menu.keywordTyping] })
            ]),
            searchKeywords: { [WGStrings.GhostMode.Menu.keywordGhost] }
        ))

        WGMenuRegistry.register(WGMenuRow(
            id: "ghostMode.readOnAction",
            section: section,
            order: 300,
            title: { WGStrings.GhostMode.Menu.readOnAction },
            subtitle: { WGStrings.GhostMode.Menu.readOnActionInfo },
            kind: .toggle(.account(WGGhostSettings.readOnAction)),
            isEnabled: { context in
                return WGGhostSettings.isEnabled.value(for: context.accountID)
            }
        ))

        WGMenuRegistry.register(WGMenuRow(
            id: "ghostMode.alwaysOnline",
            section: section,
            order: 400,
            title: { WGStrings.GhostMode.Menu.alwaysOnline },
            subtitle: { WGStrings.GhostMode.Menu.alwaysOnlineInfo },
            kind: .toggle(.account(WGGhostSettings.alwaysOnline)),
            searchKeywords: { [WGStrings.GhostMode.Menu.keywordOnline] },
            // Grey while ghost mode hides "online": the switch must not look active when it is not.
            isEnabled: { context in
                return !WGGhostPolicy.isFunctionOn(.online, account: context.accountID)
            }
        ))

        WGMenuRegistry.register(WGMenuRow(
            id: "ghostMode.readLocally",
            section: section,
            order: 700,
            title: { WGStrings.GhostMode.Menu.readLocally },
            subtitle: { WGStrings.GhostMode.Menu.readLocallyInfo },
            icon: .bundle("Chat/Context Menu/ReadAll"),
            kind: .action({ context in
                WGGhostMenu.confirm(context, title: WGStrings.GhostMode.Menu.readLocallyConfirmTitle, text: WGStrings.GhostMode.Menu.readLocallyConfirmText, action: WGStrings.GhostMode.Menu.readLocally, perform: {
                    let accountContext = context.context
                    let _ = (WGGhostReadAll.readLocally(context: accountContext)
                    |> deliverOnMainQueue).start(next: { count in
                        context.presentToast(WGStrings.GhostMode.Menu.readLocallyDone(count: count))
                    })
                })
            }),
            searchKeywords: { [WGStrings.GhostMode.Menu.keywordRead] },
            label: { context in
                let count = WGGhostReadLedger.shared.localReadCount(account: context.accountID)
                return count > 0 ? "\(count)" : nil
            }
        ))

        WGMenuRegistry.register(WGMenuRow(
            id: "ghostMode.readOnServer",
            section: section,
            order: 800,
            title: { WGStrings.GhostMode.Menu.readOnServer },
            subtitle: { WGStrings.GhostMode.Menu.readOnServerInfo },
            icon: .bundle("Chat/Context Menu/MarkAsRead"),
            kind: .action({ context in
                WGGhostMenu.confirm(context, title: WGStrings.GhostMode.Menu.readOnServerConfirmTitle, text: WGStrings.GhostMode.Menu.readOnServerConfirmText, action: WGStrings.GhostMode.Menu.readOnServer, perform: {
                    let accountContext = context.context
                    let _ = (WGGhostReadAll.readOnServer(context: accountContext)
                    |> deliverOnMainQueue).start(next: { count in
                        context.presentToast(WGStrings.GhostMode.Menu.readOnServerDone(count: count))
                    })
                })
            }),
            searchKeywords: { [WGStrings.GhostMode.Menu.keywordRead] },
            label: { context in
                let pending = WGGhostReadLedger.shared.pendingKeys(account: context.accountID)
                let count = pending.kept.count + pending.local.count
                return count > 0 ? "\(count)" : nil
            }
        ))
    }

    static func confirm(_ context: WGMenuContext, title: String, text: String, action: String, perform: @escaping () -> Void) {
        let presentationData = context.presentationData
        let alert = textAlertController(context: context.context, title: title, text: text, actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .defaultAction, title: action, action: perform)
        ])
        context.present(alert)
    }

    // MARK: Activity statuses

    static func activityTitle(_ kind: WGGhostActivityKind) -> String {
        switch kind {
        case .typingText:
            return WGStrings.GhostMode.Activity.typingText
        case .recordingVoice:
            return WGStrings.GhostMode.Activity.recordingVoice
        case .recordingInstantVideo:
            return WGStrings.GhostMode.Activity.recordingInstantVideo
        case .uploadingInstantVideo:
            return WGStrings.GhostMode.Activity.uploadingInstantVideo
        case .uploadingVideo:
            return WGStrings.GhostMode.Activity.uploadingVideo
        case .uploadingPhoto:
            return WGStrings.GhostMode.Activity.uploadingPhoto
        case .uploadingFile:
            return WGStrings.GhostMode.Activity.uploadingFile
        case .choosingSticker:
            return WGStrings.GhostMode.Activity.choosingSticker
        case .playingGame:
            return WGStrings.GhostMode.Activity.playingGame
        case .speakingInGroupCall:
            return WGStrings.GhostMode.Activity.speakingInGroupCall
        case .interactingWithEmoji:
            return WGStrings.GhostMode.Activity.interactingWithEmoji
        case .seeingEmojiInteraction:
            return WGStrings.GhostMode.Activity.seeingEmojiInteraction
        }
    }

    private static func registerActivitiesTab() {
        // Shown only while «Не отправлять «печатает»» is on: an empty tab has no link (no dead screen).
        WGMenuRegistry.register(
            tab: WGMenuTabDescriptor(
                id: .ghostActivities,
                parent: .category(.privacy),
                title: { WGStrings.GhostMode.Menu.activities },
                topView: WGMenuTopView(content: .emoji("✍️"), text: { WGStrings.GhostMode.Menu.activitiesInfo }),
                searchKeywords: { [WGStrings.GhostMode.Menu.keywordTyping] }
            ),
            linkIn: .privacyGhostMode,
            order: 200,
            subtitle: { WGStrings.GhostMode.Menu.activitiesInfo },
            icon: .bundle("Chat/Context Menu/Edit"),
            label: { context in
                let account = context.accountID
                var shown = 0
                for kind in WGGhostActivityKind.allCases where WGGhostSettings.shownActivity(kind).value(for: account) {
                    shown += 1
                }
                return WGStrings.GhostMode.Menu.activitiesShown(shown: "\(shown)", total: "\(WGGhostActivityKind.allCases.count)")
            }
        )
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(
            id: .ghostActivitiesMain,
            screen: .tab(.ghostActivities),
            order: 200,
            header: { WGStrings.GhostMode.Menu.activitiesHeader },
            footer: { _ in WGStrings.GhostMode.Menu.activitiesFooter },
            isVisible: { context in
                return WGGhostSettings.hideTyping.value(for: context.accountID)
            }
        ))
        var order = 100
        for kind in WGGhostActivityKind.allCases {
            WGMenuRegistry.register(WGMenuRow(
                id: "ghostMode.activityShown.\(kind.rawValue)",
                section: .ghostActivitiesMain,
                order: order,
                title: { WGGhostMenu.activityTitle(kind) },
                kind: .toggle(.account(WGGhostSettings.shownActivity(kind)))
            ))
            order += 100
        }
    }

    // MARK: Exceptions

    /// PLAN §2.1: «Чаты / Папки / Типы» as a segment in the navbar of the skeleton's tab. Chats and
    /// folders are runtime rows of their sections (WGGhostExceptionRows); the types are settings.
    private static func registerExceptionsTab() {
        let tab = WGMenuTabID.privacyGhostExceptions
        WGMenuRegistry.register(segments: [
            WGMenuSegment(id: "chats", title: { WGStrings.GhostMode.Exceptions.chats }),
            WGMenuSegment(id: "folders", title: { WGStrings.GhostMode.Exceptions.folders }),
            WGMenuSegment(id: "types", title: { WGStrings.GhostMode.Exceptions.typesSegment })
        ], for: tab)

        WGMenuRegistry.register(section: WGMenuSectionDescriptor(
            id: WGGhostExceptionRows.chatsSection,
            screen: .tab(tab),
            order: 300,
            segment: "chats",
            footer: { _ in WGStrings.GhostMode.Exceptions.chatsInfo }
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "ghostMode.exceptions.add",
            section: WGGhostExceptionRows.chatsSection,
            order: 100,
            title: { WGStrings.GhostMode.Exceptions.add },
            icon: .bundle("Chat/Context Menu/AddUser"),
            kind: .action({ context in
                WGGhostExceptionRows.presentPicker(context)
            }),
            searchKeywords: { [WGStrings.GhostMode.Exceptions.chatsInfo] },
            label: { context in
                let count = WGGhostSettings.exceptions.value(for: context.accountID).count
                return count > 0 ? "\(count)" : nil
            }
        ))
        WGMenuRegistry.register(dynamicRowsIn: WGGhostExceptionRows.chatsSection, { context in
            return WGGhostExceptionRows.chatRows(context)
        })

        WGMenuRegistry.register(section: WGMenuSectionDescriptor(
            id: WGGhostExceptionRows.foldersSection,
            screen: .tab(tab),
            order: 400,
            segment: "folders",
            header: { WGStrings.GhostMode.Exceptions.foldersInfo },
            footer: { _ in WGStrings.GhostMode.Exceptions.foldersFooter }
        ))
        WGMenuRegistry.register(dynamicRowsIn: WGGhostExceptionRows.foldersSection, { context in
            return WGGhostExceptionRows.folderRows(context)
        })

        WGMenuRegistry.register(section: WGMenuSectionDescriptor(
            id: .ghostExceptionTypes,
            screen: .tab(tab),
            order: 500,
            segment: "types",
            header: { WGStrings.GhostMode.Exceptions.typesHeader },
            footer: { _ in WGStrings.GhostMode.Exceptions.typesFooter }
        ))
        WGMenuRegistry.register(WGMenuRow(id: "ghostMode.exceptAllChannels", section: .ghostExceptionTypes, order: 100, title: { WGStrings.GhostMode.Exceptions.allChannels }, kind: .toggle(.account(WGGhostSettings.exceptAllChannels))))
        WGMenuRegistry.register(WGMenuRow(id: "ghostMode.exceptAllGroups", section: .ghostExceptionTypes, order: 200, title: { WGStrings.GhostMode.Exceptions.allGroups }, kind: .toggle(.account(WGGhostSettings.exceptAllGroups))))
    }

    // MARK: Send delay

    private static func registerSendDelayTab() {
        let main = WGMenuSectionID.main(of: .privacySendDelay)
        WGMenuRegistry.register(WGMenuRow(
            id: "sendDelay.isEnabled",
            section: main,
            order: 100,
            title: { WGStrings.GhostMode.SendDelay.toggle },
            subtitle: { WGStrings.GhostMode.SendDelay.toggleInfo },
            kind: .toggle(.account(WGGhostSettings.sendDelayEnabled))
        ))
        // One delay for text and media since 2026-10-27 (were two sliders).
        WGMenuRegistry.register(WGMenuRow(
            id: "sendDelay.seconds",
            section: main,
            order: 200,
            title: { WGStrings.GhostMode.SendDelay.delay },
            kind: .slider(.account(WGGhostSettings.sendDelaySeconds), range: WGSendDelaySeconds.range, step: 1.0, format: { value in
                return WGStrings.GhostMode.SendDelay.seconds(count: Int(value))
            }),
            isVisible: { context in
                return WGGhostSettings.sendDelayEnabled.value(for: context.accountID)
            }
        ))
    }

    // MARK: Traces

    private static func registerTraces() {
        WGMenuRegistry.register(WGMenuRow(id: "ghostMode.confirmCalls", section: .privacyTraces, order: 100, title: { WGStrings.GhostMode.Traces.confirmCalls }, subtitle: { WGStrings.GhostMode.Traces.confirmCallsInfo }, kind: .toggle(.global(WGGhostSettings.confirmCalls))))
        WGMenuRegistry.register(WGMenuRow(id: "ghostMode.warnBeforeStories", section: .privacyTraces, order: 200, title: { WGStrings.GhostMode.Traces.warnBeforeStories }, subtitle: { WGStrings.GhostMode.Traces.warnBeforeStoriesInfo }, kind: .toggle(.global(WGGhostSettings.warnBeforeStories))))
        WGMenuRegistry.register(WGMenuRow(id: "ghostMode.hidePhoneInSettings", section: .privacyTraces, order: 300, title: { WGStrings.GhostMode.Traces.hidePhone }, subtitle: { WGStrings.GhostMode.Traces.hidePhoneInfo }, kind: .toggle(.global(WGGhostSettings.hidePhoneInSettings))))
    }

    // MARK: Messages › Chats

    private static func registerChatsSection() {
        WGMenuRegistry.register(WGMenuRow(
            id: "ghostMode.hideBlockedMessages",
            section: .messagesChats,
            order: 450,
            title: { WGStrings.GhostMode.Blocked.toggle },
            subtitle: { WGStrings.GhostMode.Blocked.toggleInfo },
            kind: .toggle(.account(WGGhostSettings.hideBlockedMessages))
        ))
    }
}
