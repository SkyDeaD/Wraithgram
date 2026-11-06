import Foundation
import WGCore
import WGFeaturesShared

/// Old Wraithgram keys → the settings of this zone. The «Прочее» master switch is not carried over
/// as a setting (every feature has its own toggle now): a flag that only worked behind the master
/// is migrated as its effective old value (master && flag), so nothing turns on that did not work.
enum WGMessagesMigrations {
    static func register() {
        WGMigrations.registerGlobal(id: "messages.v1") { legacy in
            WGMessagesMigrations.migrateGlobal(legacy)
        }
        WGMigrations.registerAccount(id: "messages.account.v1") { legacy, account in
            WGMessagesMigrations.migrateAccount(legacy, account: account)
        }
        // «Антипоиск» and «Язык бурмалды» were removed by the owner on 2026-10-27: the old client's
        // keys and this app's two switches (build 185 and earlier) go once.
        WGMigrations.registerGlobal(id: "messages.removedStages.v1") { legacy in
            for key in ["GG.invisibleText", "GG.burmalda.enabled", "GG.burmalda.dictionary"] {
                legacy.removeLegacyKey(key)
            }
            WGRetiredSettings.remove(keys: ["sending.antiSearch", "sending.burmalda"])
        }
        // Builds ≤ 185 had «…к следующему каналу» and «…к следующей теме» as two switches; since
        // 2026-10-27 they are one. Their stored values are carried over once, then dropped.
        WGMigrations.registerGlobal(id: "chats.scrollToNext.merge.v1") { _ in
            let channel = WGRetiredSettings.value("chats.disableScrollToNextChannel", as: Bool.self)
            let topic = WGRetiredSettings.value("chats.disableScrollToNextTopic", as: Bool.self)
            if WGScrollToNextMerge.merged(channel: channel, topic: topic) == true {
                WGMessagesSettings.disableScrollToNext.set(true)
            }
            WGRetiredSettings.remove(keys: ["chats.disableScrollToNextChannel", "chats.disableScrollToNextTopic"])
        }
        // «Выбрать от автора» in the message menu removed (owner, 2026-10-29): the stored switch of
        // builds ≤ 191 and the old client's key go once.
        WGMigrations.registerGlobal(id: "messageMenu.selectFromAuthor.removed.v1") { legacy in
            WGRetiredSettings.remove(keys: ["messageMenu.selectFromAuthor"])
            legacy.removeLegacyKey("contextShowSelectFromUser")
        }
        // «Безлимитные закрепы»: the old client copied every pinned list of an account to
        // `UserDefaults` (`WG.pinnedOverflowBackup.<account peer>.<group>`, rewritten on each change).
        // The lists themselves, tail included, are in the account's Postbox, which carries over, and the
        // first server list marks the pins beyond the limit as the tail — the copy is only removed.
        WGMigrations.registerAccountPeer(id: "chats.pinnedBackupCleanup.v1") { legacy, _, peer in
            guard let legacyPeerId = WGLegacyKeys.legacyInt64(of: peer) else {
                return
            }
            legacy.removeLegacyKey("GG.pinnedOverflowBackup.\(legacyPeerId).0")
            legacy.removeLegacyKey("GG.pinnedOverflowBackup.\(legacyPeerId).1")
        }
    }

    private static func move(_ legacy: WGLegacyDefaults, _ key: String, to setting: WGSetting<Bool>, gatedBy master: Bool? = nil, invert: Bool = false) {
        guard let value = legacy.bool(key) else {
            return
        }
        var effective = invert ? !value : value
        if let master {
            effective = effective && master
        }
        if effective != setting.defaultValue {
            setting.set(effective)
        }
        legacy.removeLegacyKey(key)
    }

    static func migrateGlobal(_ legacy: WGLegacyDefaults) {
        let master = legacy.bool("MiscSettings.isEnabled") ?? false
        legacy.removeLegacyKey("MiscSettings.isEnabled")
        legacy.removeLegacyKey("MiscSettings.initialized")

        // «Обходы ограничений» (behind the old master).
        move(legacy, "MiscSettings.bypassCopyProtection", to: WGMessagesSettings.copyProtectionBypass, gatedBy: master)
        move(legacy, "MiscSettings.addForwardAuthorAttribution", to: WGMessagesSettings.forwardAttribution, gatedBy: master)
        move(legacy, "MiscSettings.disableViewOnceAutoDelete", to: WGMessagesSettings.keepSelfDestructingMedia, gatedBy: master)
        move(legacy, "MiscSettings.bypassScreenshotProtection", to: WGMessagesSettings.screenshotBypass, gatedBy: master)
        move(legacy, "MiscSettings.blockAds", to: WGMessagesSettings.blockAds, gatedBy: master)
        move(legacy, "MiscSettings.bypassBotRestrictions", to: WGMessagesSettings.contentRestrictionsBypass, gatedBy: master)
        move(legacy, "MiscSettings.antiSpoiler", to: WGMessagesSettings.revealSpoilers, gatedBy: master)

        // Outgoing text.
        move(legacy, "MiscSettings.antiCaps", to: WGMessagesSettings.antiCaps, gatedBy: master)
        move(legacy, "MiscSettings.wordReplacementEnabled", to: WGMessagesSettings.wordReplacement, gatedBy: master)
        // «Антипоиск» and «Язык бурмалды» were removed (owner, 2026-10-27): only their keys go
        // (`messages.removedStages.v1`).
        move(legacy, "GG.hyperlinkSpoof.enabled", to: WGMessagesSettings.hyperlinkSpoof)
        WGMessagesMigrations.migrateReplacementRules(legacy)

        // Replies, stickers, inline bots, the input field.
        move(legacy, "MiscSettings.autoQuoteReply", to: WGMessagesSettings.autoQuoteReply)
        move(legacy, "MiscSettings.autoQuoteReplySkipDiscussions", to: WGMessagesSettings.autoQuoteSkipComments)
        move(legacy, "MiscSettings.anonymousStickers", to: WGMessagesSettings.anonymousStickers)
        move(legacy, "hideInlineBotAttribution", to: WGMessagesSettings.sendWithoutViaBot)
        move(legacy, "keepInlineBotCaption", to: WGMessagesSettings.keepInlineBotCaption)
        move(legacy, "sendWithReturnKey", to: WGMessagesSettings.sendOnReturn)
        move(legacy, "disableSendAsButton", to: WGMessagesSettings.hideSendAsButton)

        // Translation.
        if let backend = legacy.string("translationBackend") {
            switch backend {
            case "gtranslate":
                // The notice is shown once before Google is used (WGTranslationMenu).
                WGMessagesSettings.translationService.set(WGTranslationServiceKind.google.rawValue)
            case "system":
                WGMessagesSettings.translationService.set(WGTranslationServiceKind.system.rawValue)
            default:
                break
            }
            legacy.removeLegacyKey("translationBackend")
        }
        move(legacy, "quickTranslateButton", to: WGMessagesSettings.quickTranslateButton)
        move(legacy, "translateBeforeSending", to: WGMessagesSettings.translateBeforeSending)
        if let language = legacy.string("translateBeforeSendingLanguage"), !language.isEmpty {
            WGMessagesSettings.translateBeforeSendingLanguage.set(language)
            legacy.removeLegacyKey("translateBeforeSendingLanguage")
        }
        // The old per-chat languages were keyed by raw ids without a peer namespace and by the
        // account's peer id: they can not be mapped to chats safely and are not carried over.
        legacy.removeLegacyKey("outgoingLanguageTranslation")

        // Message menu (SG-G1): «show item» flags of the old menu; any hidden one turns the custom menu on.
        let menuKeys: [(String, WGSetting<Bool>)] = [
            ("contextShowReply", WGMessagesSettings.menuShowReply),
            ("contextShowPin", WGMessagesSettings.menuShowPin),
            ("contextShowReport", WGMessagesSettings.menuShowReport),
            ("contextShowRestrict", WGMessagesSettings.menuShowRestrict),
            ("contextShowSaveMedia", WGMessagesSettings.menuShowSaveMedia),
            ("contextShowMessageReplies", WGMessagesSettings.menuShowReplies)
        ]
        var customMenu = false
        for (key, setting) in menuKeys {
            if let value = legacy.bool(key) {
                setting.set(value)
                if !value {
                    customMenu = true
                }
                legacy.removeLegacyKey(key)
            }
        }
        if let value = legacy.bool("contextShowSaveToCloud") {
            WGMessagesSettings.menuSaveToCloud.set(value)
            customMenu = customMenu || value
            legacy.removeLegacyKey("contextShowSaveToCloud")
        }
        if let value = legacy.bool("contextShowHideForwardName") {
            WGMessagesSettings.menuForwardWithoutAuthor.set(value)
            customMenu = customMenu || value
            legacy.removeLegacyKey("contextShowHideForwardName")
        }
        // «Выбрать от автора» was removed (owner, 2026-10-29): only its key goes.
        legacy.removeLegacyKey("contextShowSelectFromUser")
        if customMenu {
            WGMessagesSettings.customMessageMenu.set(true)
        }
        // SG debug item, not carried over (Swiftgram infrastructure).
        legacy.removeLegacyKey("contextShowJson")

        // Gestures.
        if let value = legacy.string("messageDoubleTapActionOutgoing") {
            if value == "edit" {
                WGMessagesSettings.doubleTapToEdit.set(true)
            }
            legacy.removeLegacyKey("messageDoubleTapActionOutgoing")
        }
        if let value = legacy.string("videoPIPSwipeDirection") {
            if value == "none" {
                WGMessagesSettings.disableVideoPipSwipe.set(true)
            }
            legacy.removeLegacyKey("videoPIPSwipeDirection")
        }

        // «Чаты».
        move(legacy, "MiscSettings.unlimitedSearchHistory", to: WGMessagesSettings.unlimitedSearchHistory, gatedBy: master)
        move(legacy, "MiscSettings.hideGreetingSticker", to: WGMessagesSettings.hideGreetingSticker, gatedBy: master)
        move(legacy, "hideChannelBottomButton", to: WGMessagesSettings.hideChannelBottomButton)
        // One switch for channels and topics since 2026-10-27: on when either old one was on.
        if WGScrollToNextMerge.merged(channel: legacy.bool("disableScrollToNextChannel"), topic: legacy.bool("disableScrollToNextTopic")) == true {
            WGMessagesSettings.disableScrollToNext.set(true)
        }
        legacy.removeLegacyKey("disableScrollToNextChannel")
        legacy.removeLegacyKey("disableScrollToNextTopic")
        move(legacy, "disableSnapDeletionEffect", to: WGMessagesSettings.disableDeleteEffect)
        move(legacy, "hideRecordingButton", to: WGMessagesSettings.hideRecordButton)
        if let keywords = legacy.stringArray("messageFilterKeywords") {
            let cleaned = keywords.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if !cleaned.isEmpty {
                WGMessagesSettings.keywords.set(cleaned)
                WGMessagesSettings.keywordFilter.set(true)
            }
            legacy.removeLegacyKey("messageFilterKeywords")
        }

        // «Уведомления» (old App Group keys).
        let modes: [(String, WGSetting<String>)] = [
            ("pinnedMessageNotifications", WGMessagesSettings.pinnedNotifications),
            ("mentionsAndRepliesNotifications", WGMessagesSettings.mentionNotifications)
        ]
        for (key, setting) in modes {
            if let value = legacy.string(key) {
                switch value {
                case "silenced":
                    setting.set(WGNotificationDeliveryMode.silent.rawValue)
                case "disabled":
                    setting.set(WGNotificationDeliveryMode.disabled.rawValue)
                default:
                    break
                }
                legacy.removeLegacyKey(key)
            }
            // The old exception dictionaries were never written by anything.
            legacy.removeLegacyKey(key + "Exceptions")
        }
    }

    /// One rule set from both old systems (the visible «Правила замены» and the hidden
    /// `WG.textReplacement`), deduplicated by the replaced text.
    private static func migrateReplacementRules(_ legacy: WGLegacyDefaults) {
        var rules: [WGTextReplacementRule] = []
        var seen = Set<String>()
        func add(_ source: String?, _ replacement: String?) {
            guard let source = source?.trimmingCharacters(in: .whitespacesAndNewlines), !source.isEmpty, let replacement else {
                return
            }
            let key = source.lowercased()
            if seen.insert(key).inserted {
                rules.append(WGTextReplacementRule(source: source, replacement: replacement))
            }
        }
        if let data = legacy.data("MiscSettings.wordReplacementRules"), let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            for item in array {
                add(item["source"] as? String, item["replacement"] as? String)
            }
        }
        legacy.removeLegacyKey("MiscSettings.wordReplacementRules")
        if let array = legacy.object("GG.textReplacement.rules") as? [[String: Any]] {
            for item in array {
                add(item["source"] as? String, item["replacement"] as? String)
            }
        }
        if legacy.bool("GG.textReplacement.enabled") == true && !rules.isEmpty {
            WGMessagesSettings.wordReplacement.set(true)
        }
        for key in ["GG.textReplacement.rules", "GG.textReplacement.enabled", "GG.textReplacement.draftSource", "GG.textReplacement.draftReplacement"] {
            legacy.removeLegacyKey(key)
        }
        if !rules.isEmpty {
            WGOutgoingPipeline.replacementRules.set(rules)
        }
    }

    static func migrateAccount(_ legacy: WGLegacyDefaults, account: WGAccountID) {
        // With the old per-account profiles on, the shared keys are the active account's values:
        // another account never takes them (a link target or local channels of someone else).
        func value(_ key: String) -> Any? {
            return legacy.legacyAccountValue(key, for: account)
        }
        if let text = value("GG.hyperlinkSpoof.targetId") as? String, let id = Int64(text.trimmingCharacters(in: .whitespaces)), id > 0, let key = WGPeerKey(namespace: 0, id: id) {
            WGMessagesSettings.hyperlinkTarget.set(key, for: account)
        }
        if let values = value("GG.channelCreatorSpoof.enabledPeerIds") as? [Any] {
            var keys = Set<WGPeerKey>()
            for item in values {
                if let number = item as? NSNumber {
                    keys.insert(WGLegacyKeys.peerKey(fromLegacyInt64: number.int64Value))
                }
            }
            if !keys.isEmpty {
                WGMessagesSettings.localCreatorChannels.set(keys, for: account)
            }
        }
    }
}
