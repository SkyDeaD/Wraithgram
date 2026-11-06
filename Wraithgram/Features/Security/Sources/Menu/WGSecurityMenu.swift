import Foundation
import UIKit
import SwiftSignalKit
import Postbox
import Display
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import ItemListPeerItem
import LocalizedPeerData
import WGCore
import WGSettingsUI
import WGFeaturesShared

/// «Безопасность»: «Защита чатов», «Код-пароль», «Аккаунты». «Двойное дно» registers nothing (not
/// ported, owner 2026-10-22), so that tab is not shown. The category, and the export / import / reset
/// of the settings, ask the common check while any protection is on — switching a protection off is
/// what an intruder with an unlocked phone would do.
enum WGSecurityMenu {
    static let chatsSection = WGMenuSectionID("security.chatProtection.chats")
    static let folderSection = WGMenuSectionID("security.chatProtection.folder")
    static let folderListSection = WGMenuSectionID("security.chatProtection.folderList")
    static let moreSection = WGMenuSectionID("security.chatProtection.more")
    static let passcodeOptionsSection = WGMenuSectionID("security.passcode.options")
    static let accountSettingsSection = WGMenuSectionID("security.accounts.settings")

    static func register() {
        WGSecurityMenu.registerAccessGate()
        WGSecurityMenu.registerChatProtection()
        WGSecurityMenu.registerPasscode()
        WGSecurityMenu.registerAccounts()
    }

    // MARK: Access

    /// A protection is on: entering «Безопасность» or exporting / importing / resetting needs the check.
    static func isAnyProtectionOn(account: WGAccountID) -> Bool {
        if WGSecuritySharedSettings.chatLockEnabled.value || WGSecuritySettings.accountSwitchAuth.value || WGSecuritySettings.passcodeLockOnLaunch.value {
            return true
        }
        return WGSecuritySettings.secretFolderId.value(for: account) != 0
    }

    private static let guardedActions: Set<String> = ["menu.export", "menu.import", "menu.reset"]

    private static func registerAccessGate() {
        WGMenuAccessGates.gate.register({ request, proceed in
            let isSecurity = request.path.contains(.category(.security)) && !request.unlocked.contains(.category(.security))
            var isGuardedAction = false
            if case let .action(rowId) = request.target {
                isGuardedAction = WGSecurityMenu.guardedActions.contains(rowId)
            }
            guard isSecurity || isGuardedAction else {
                return false
            }
            if !WGSecurityMenu.isAnyProtectionOn(account: request.context.account.id.wg) {
                return false
            }
            WGLocalAuthGate.shared.authenticate(context: request.context, reason: WGStrings.Security.Auth.reasonSettings, completion: { granted in
                if granted {
                    proceed()
                }
            })
            return true
        }, order: 100)
    }

    // MARK: Защита чатов

    private static func registerChatProtection() {
        let tab = WGMenuTabID.securityChatProtection
        let main = WGMenuSectionID.main(of: tab)
        let enabled: (WGMenuContext) -> Bool = { _ in WGSecuritySharedSettings.chatLockEnabled.value }

        WGMenuRegistry.register(section: WGMenuSectionDescriptor(
            id: WGSecurityMenu.chatsSection,
            screen: .tab(tab),
            order: 250,
            footer: { _ in WGStrings.Security.ChatLock.footer },
            isVisible: enabled
        ))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGSecurityMenu.folderSection, screen: .tab(tab), order: 300, header: { WGStrings.Security.Folder.header }, footer: { _ in WGStrings.Security.Folder.footer }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGSecurityMenu.folderListSection, screen: .tab(tab), order: 350, header: { WGStrings.Security.Folder.chooseHeader }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGSecurityMenu.moreSection, screen: .tab(tab), order: 400, footer: { _ in WGStrings.Security.Screenshot.footer }))

        WGMenuRegistry.register(WGMenuRow(
            id: "security.chatLock.enabled",
            section: main,
            order: 100,
            title: { WGStrings.Security.ChatLock.toggle },
            subtitle: { WGStrings.Security.ChatLock.toggleInfo },
            kind: .toggle(.global(WGSecuritySharedSettings.chatLockEnabled)),
            searchKeywords: { [WGStrings.Security.ChatLock.keywords] }
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "security.chatLock.allChats",
            section: main,
            order: 200,
            title: { WGStrings.Security.ChatLock.allChats },
            subtitle: { WGStrings.Security.ChatLock.allChatsInfo },
            kind: .toggle(.global(WGSecuritySharedSettings.chatLockAllChats)),
            isVisible: enabled
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "security.chatLock.autolock",
            section: main,
            order: 300,
            title: { WGStrings.Security.ChatLock.autolock },
            subtitle: { WGStrings.Security.ChatLock.autolockInfo },
            kind: .toggle(.global(WGSecuritySettings.chatLockAutolock)),
            isVisible: enabled
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "security.chatLock.autolockTimeout",
            section: main,
            order: 400,
            title: { WGStrings.Security.ChatLock.timeout },
            kind: .choice(.global(WGSecuritySettings.chatLockAutolockTimeout), options: [
                WGMenuChoiceOption(value: "0", title: { WGStrings.Security.ChatLock.timeoutImmediately }),
                WGMenuChoiceOption(value: "15", title: { WGStrings.Security.ChatLock.timeoutSeconds(count: 15) }),
                WGMenuChoiceOption(value: "30", title: { WGStrings.Security.ChatLock.timeoutSeconds(count: 30) }),
                WGMenuChoiceOption(value: "60", title: { WGStrings.Security.ChatLock.timeoutMinutes(count: 1) }),
                WGMenuChoiceOption(value: "300", title: { WGStrings.Security.ChatLock.timeoutMinutes(count: 5) })
            ]),
            isVisible: { _ in WGSecuritySharedSettings.chatLockEnabled.value && WGSecuritySettings.chatLockAutolock.value }
        ))

        // The chosen chats of the account.
        WGMenuRegistry.register(WGMenuRow(
            id: "security.chatLock.choose",
            section: WGSecurityMenu.chatsSection,
            order: 100,
            title: { WGStrings.Security.ChatLock.choose },
            icon: .bundle("Chat/Context Menu/AddUser"),
            kind: .action({ context in
                WGSecurityMenu.presentChatPicker(context)
            }),
            isVisible: { _ in !WGSecuritySharedSettings.chatLockAllChats.value },
            label: { context in
                let count = WGSecuritySharedSettings.chatLockPeers.value(for: context.accountID).count
                return count > 0 ? "\(count)" : nil
            }
        ))
        WGMenuRegistry.register(dynamicRowsIn: WGSecurityMenu.chatsSection, { context in
            return WGSecurityMenu.chatRows(context)
        })

        // Secret folder.
        WGMenuRegistry.register(WGMenuRow(
            id: "security.secretFolder.open",
            section: WGSecurityMenu.folderSection,
            order: 100,
            title: { WGStrings.Security.Folder.open },
            icon: .bundle("Chat/Context Menu/Lock"),
            kind: .action({ context in
                WGSecretFolder.shared.open(context)
            }),
            isVisible: { context in WGSecuritySettings.secretFolderId.value(for: context.accountID) != 0 },
            searchKeywords: { [WGStrings.Security.Folder.keywords] }
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "security.secretFolder.protectChats",
            section: WGSecurityMenu.folderSection,
            order: 200,
            title: { WGStrings.Security.Folder.protectChats },
            subtitle: { WGStrings.Security.Folder.protectChatsInfo },
            kind: .toggle(.account(WGSecuritySettings.secretFolderProtectChats)),
            isVisible: { context in WGSecuritySettings.secretFolderId.value(for: context.accountID) != 0 }
        ))
        WGMenuRegistry.register(dynamicRowsIn: WGSecurityMenu.folderListSection, { context in
            return WGSecurityMenu.folderRows(context)
        })

        // Accounts and screenshots.
        WGMenuRegistry.register(WGMenuRow(
            id: "security.accountSwitchAuth",
            section: WGSecurityMenu.moreSection,
            order: 100,
            title: { WGStrings.Security.Accounts.switchAuth },
            subtitle: { WGStrings.Security.Accounts.switchAuthInfo },
            kind: .toggle(.global(WGSecuritySettings.accountSwitchAuth))
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "security.screenshotPrivacy",
            section: WGSecurityMenu.moreSection,
            order: 200,
            title: { WGStrings.Security.Screenshot.toggle },
            subtitle: { WGStrings.Security.Screenshot.toggleInfo },
            kind: .toggle(.global(WGSecuritySettings.screenshotPrivacy)),
            searchKeywords: { [WGStrings.Security.Screenshot.keywords] }
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "security.screenshotPrivacyChatList",
            section: WGSecurityMenu.moreSection,
            order: 300,
            title: { WGStrings.Security.Screenshot.chatList },
            kind: .toggle(.global(WGSecuritySettings.screenshotPrivacyChatList)),
            isVisible: { _ in WGSecuritySettings.screenshotPrivacy.value }
        ))
    }

    /// «Выбрать чаты»: Telegram's chat picker over the chats protected so far.
    private static func presentChatPicker(_ menuContext: WGMenuContext) {
        let context = menuContext.context
        let account = context.account.id.wg
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        var selected = Set<EnginePeer.Id>()
        for key in WGSecuritySharedSettings.chatLockPeers.value(for: account) {
            selected.insert(PeerId(wgKey: key))
        }
        let controller = context.sharedContext.makeContactMultiselectionController(ContactMultiselectionControllerParams(context: context, mode: .chatSelection(ContactMultiselectionControllerMode.ChatSelection(
            title: WGStrings.Security.ChatLock.choose,
            searchPlaceholder: presentationData.strings.Common_Search,
            selectedChats: selected,
            additionalCategories: nil,
            chatListFilters: nil
        )), alwaysEnabled: true))
        let _ = (controller.result
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak controller] result in
            guard case let .result(peerIds, _) = result else {
                controller?.dismiss()
                return
            }
            var keys = Set<WGPeerKey>()
            for peerId in peerIds {
                if case let .peer(value) = peerId {
                    keys.insert(value.wgKey)
                }
            }
            WGSecuritySharedSettings.chatLockPeers.set(keys, for: account)
            controller?.dismiss()
        })
        menuContext.present(controller, arguments: ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }

    /// The protected chats of the account, sorted by name; swipe to remove.
    private static func chatRows(_ providerContext: WGMenuContext) -> Signal<[WGMenuRow], NoError> {
        let context = providerContext.context
        let account = context.account.id.wg
        let revealed = ValuePromise<EnginePeer.Id?>(nil, ignoreRepeated: true)
        let peers: Signal<[EnginePeer], NoError> = WGSecuritySharedSettings.chatLockPeers.signal(for: account)
        |> map { keys -> [EnginePeer.Id] in
            return keys.map { PeerId(wgKey: $0) }
        }
        |> mapToSignal { peerIds -> Signal<[EnginePeer], NoError> in
            return context.engine.data.subscribe(EngineDataMap(peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init)))
            |> map { map -> [EnginePeer] in
                return map.values.compactMap { $0 }
            }
        }
        return combineLatest(peers, revealed.get(), context.sharedContext.presentationData, WGSecuritySharedSettings.chatLockAllChats.signal)
        |> map { peers, revealedPeerId, presentationData, allChats -> [WGMenuRow] in
            if allChats {
                return []
            }
            let sorted = peers.sorted(by: { lhs, rhs in
                let lhsTitle = lhs.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                let rhsTitle = rhs.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
            })
            var rows: [WGMenuRow] = []
            for (index, peer) in sorted.enumerated() {
                let peerId = peer.id
                let isRevealed = revealedPeerId == peerId
                rows.append(WGMenuRow(id: "security.chatLock.peer.\(peerId.wgKey.stringValue)", section: WGSecurityMenu.chatsSection, order: 1000 + index, title: { "" }, kind: .custom({ rowContext in
                    let presentationData = rowContext.presentationData
                    let remove: (EnginePeer.Id) -> Void = { peerId in
                        var keys = WGSecuritySharedSettings.chatLockPeers.value(for: account)
                        keys.remove(peerId.wgKey)
                        WGSecuritySharedSettings.chatLockPeers.set(keys, for: account)
                    }
                    return ItemListPeerItem(presentationData: rowContext.itemListPresentationData, systemStyle: .glass, dateTimeFormat: presentationData.dateTimeFormat, nameDisplayOrder: presentationData.nameDisplayOrder, context: rowContext.context, peer: peer, presence: nil, text: .none, label: .none, editing: ItemListPeerItemEditing(editable: true, editing: false, revealed: isRevealed), revealOptions: ItemListPeerItemRevealOptions(options: [ItemListPeerItemRevealOption(type: .destructive, title: WGStrings.Security.ChatLock.remove, action: {
                        remove(peerId)
                    })]), switchValue: nil, enabled: true, selectable: false, sectionId: rowContext.sectionId, action: nil, setPeerIdWithRevealedOptions: { peerId, fromPeerId in
                        if peerId != nil || fromPeerId != nil {
                            revealed.set(peerId)
                        }
                    }, removePeer: { peerId in
                        remove(peerId)
                    })
                })))
            }
            return rows
        }
    }

    /// The account's folders as a single choice («Нет» first).
    private static func folderRows(_ providerContext: WGMenuContext) -> Signal<[WGMenuRow], NoError> {
        let context = providerContext.context
        let account = context.account.id.wg
        return combineLatest(WGSecretFolder.folderChoices(context: context), WGSecuritySettings.secretFolderId.signal(for: account))
        |> map { folders, selectedId -> [WGMenuRow] in
            var choices: [(Int32, String?)] = [(0, nil)]
            for (id, title) in folders {
                choices.append((id, title))
            }
            var rows: [WGMenuRow] = []
            for (index, choice) in choices.enumerated() {
                let id = choice.0
                let title = choice.1
                let checked = id == selectedId
                rows.append(WGMenuRow(id: "security.secretFolder.choice.\(id)", section: WGSecurityMenu.folderListSection, order: 1000 + index, title: { title ?? WGStrings.Security.Folder.none }, kind: .custom({ rowContext in
                    return ItemListCheckboxItem(presentationData: rowContext.itemListPresentationData, systemStyle: .glass, title: title ?? WGStrings.Security.Folder.none, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: rowContext.sectionId, action: {
                        if WGSecuritySettings.secretFolderId.value(for: account) != id {
                            WGSecuritySettings.secretFolderId.set(id, for: account)
                            // A newly chosen folder starts locked.
                            WGSecretFolder.shared.lockAll()
                        }
                    })
                })))
            }
            if folders.isEmpty {
                rows.append(WGMenuRow(id: "security.secretFolder.empty", section: WGSecurityMenu.folderListSection, order: 5000, title: { "" }, kind: .custom({ rowContext in
                    return ItemListTextItem(presentationData: rowContext.itemListPresentationData, text: .plain(WGStrings.Security.Folder.noFolders), sectionId: rowContext.sectionId)
                })))
            }
            return rows
        }
    }

    // MARK: Код-пароль

    private static func registerPasscode() {
        let tab = WGMenuTabID.securityPasscode
        let main = WGMenuSectionID.main(of: tab)
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGSecurityMenu.passcodeOptionsSection, screen: .tab(tab), order: 300, footer: { _ in WGStrings.Security.Passcode.footer }))

        WGMenuRegistry.register(WGMenuRow(
            id: "security.passcode.open",
            section: main,
            order: 100,
            title: { WGStrings.Security.Passcode.open },
            icon: .bundle("Chat/Context Menu/Lock"),
            kind: .action({ context in
                WGPasscodeExtras.openTelegramPasscode(context)
            }),
            searchKeywords: { [WGStrings.Security.Passcode.keywords] }
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "security.passcode.lockNow",
            section: main,
            order: 200,
            title: { WGStrings.Security.Passcode.lockNow },
            subtitle: { WGStrings.Security.Passcode.lockNowInfo },
            kind: .action({ context in
                WGPasscodeExtras.lockNow(context)
            })
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "security.passcode.lockOnLaunch",
            section: WGSecurityMenu.passcodeOptionsSection,
            order: 100,
            title: { WGStrings.Security.Passcode.lockOnLaunch },
            subtitle: { WGStrings.Security.Passcode.lockOnLaunchInfo },
            kind: .toggle(.global(WGSecuritySettings.passcodeLockOnLaunch))
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "security.passcode.moreAutolockOptions",
            section: WGSecurityMenu.passcodeOptionsSection,
            order: 200,
            title: { WGStrings.Security.Passcode.moreAutolock },
            subtitle: { WGStrings.Security.Passcode.moreAutolockInfo },
            kind: .toggle(.global(WGSecuritySettings.passcodeMoreAutolockOptions))
        ))
    }

    // MARK: Аккаунты

    private static func registerAccounts() {
        let tab = WGMenuTabID.securityAccounts
        let main = WGMenuSectionID.main(of: tab)
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGSecurityMenu.accountSettingsSection, screen: .tab(tab), order: 300, header: { WGStrings.Security.AccountSettings.header }, footer: { _ in WGStrings.Security.AccountSettings.footer }))

        WGMenuRegistry.register(WGMenuRow(
            id: "security.accounts.headerButton",
            section: main,
            order: 100,
            title: { WGStrings.Security.Accounts.headerButton },
            subtitle: { WGStrings.Security.Accounts.headerButtonInfo },
            kind: .toggle(.global(WGSecuritySettings.accountsHeaderButton))
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "security.accounts.copySettings",
            section: WGSecurityMenu.accountSettingsSection,
            order: 100,
            title: { WGStrings.Security.AccountSettings.copy },
            icon: .bundle("Chat/Context Menu/Copy"),
            kind: .action({ context in
                WGAccountSettingsCopy.present(context)
            }),
            searchKeywords: { [WGStrings.Security.AccountSettings.keywords] }
        ))
    }
}
