import Foundation
import WGCore
import WGFeaturesShared

/// Keys of the old client (its Swiftgram layer) that map to WGExtras settings. Runs once.
enum WGExtrasMigrations {
    static func register() {
        WGMigrations.registerGlobal(id: "extras.v1") { legacy in
            // «В историю» in the share sheet: on by default there, our switch hides it.
            if let value = legacy.bool("showRepostToStoryV2") {
                if !value {
                    WGExtrasSettings.hideRepostToStory.set(true)
                }
                legacy.removeLegacyKey("showRepostToStoryV2")
            }
            legacy.removeLegacyKey("showRepostToStory")
            // A hidden key of the old client (no switch): the system share sheet everywhere.
            if let value = legacy.bool("forceSystemSharing") {
                if value {
                    WGExtrasSettings.systemShareSheet.set(true)
                }
                legacy.removeLegacyKey("forceSystemSharing")
            }
        }
        // «Скрыть поиск в таббаре» removed (owner, 2026-10-28): nothing in this Telegram puts the
        // search button next to the tab bar, the switch did nothing. Its stored value goes too.
        WGMigrations.registerGlobal(id: "extras.hideTabBarSearch.removed.v1") { _ in
            WGRetiredSettings.remove(keys: ["extras.hideTabBarSearch"])
        }
        // «Данные сообщения (JSON)» in the message menu removed (owner, 2026-10-29).
        WGMigrations.registerGlobal(id: "extras.messageJson.removed.v1") { legacy in
            WGRetiredSettings.remove(keys: ["extras.messageJson"])
            legacy.removeLegacyKey("contextShowJson")
        }
    }
}
