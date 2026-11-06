import Foundation
import Security
import WGCore

/// Moves the settings of the old Wraithgram (Swiftgram keys in `UserDefaults`, `WG.*`) to the registry.
/// Only what this zone carries over; keys of features that are not carried over are removed.
enum WGCallsMediaMigrations {
    static func register() {
        WGMigrations.registerGlobal(id: "callsMedia.v1") { legacy in
            moveBool(legacy, "ggCallFakeMuteEnabled", to: WGCallsMediaSettings.silentMute)
            moveBool(legacy, "ggCallDisableRating", to: WGCallsMediaSettings.disableRating)
            moveBool(legacy, "ggCallStatsOverlayEnabled", to: WGCallsMediaSettings.statsOverlay)
            moveBool(legacy, "ggCallSoundboardEnabled", to: WGCallsMediaSettings.soundboard)
            moveBool(legacy, "ggCallSoundboardDuckMicrophone", to: WGCallsMediaSettings.soundboardDuck)
            if let volume = legacy.int("ggCallSoundboardVolume") {
                WGCallsMediaSettings.soundboardVolume.set(max(0.1, min(1.0, Double(volume) / 100.0)))
                legacy.removeLegacyKey("ggCallSoundboardVolume")
            }
            if let json = legacy.string("ggCallSoundboardItems") {
                let items = legacySoundItems(json: json)
                if !items.isEmpty {
                    WGCallsMediaSettings.soundboardItems.set(items)
                }
                legacy.removeLegacyKey("ggCallSoundboardItems")
            }
            for key in ["ggCallStatsOverlayOriginX", "ggCallStatsOverlayOriginY"] {
                legacy.removeLegacyKey(key)
            }

            // The two old switches are one choice since 2026-10-27.
            if let mode = WGCallRecordingMode.merged(audio: legacy.bool("recordAudioCalls"), video: legacy.bool("recordVideoCalls")), mode.isOn {
                WGCallsMediaSettings.recordCalls.set(mode.rawValue)
            }
            legacy.removeLegacyKey("recordAudioCalls")
            legacy.removeLegacyKey("recordVideoCalls")
            moveBool(legacy, "recordOwnVoiceInCalls", to: WGCallsMediaSettings.recordOwnVoice)

            if let quality = legacy.int("outgoingPhotoQuality") {
                // The choices are steps of ten from 60 to 100.
                let step = max(60, min(100, Int((Double(quality) / 10.0).rounded()) * 10))
                WGCallsMediaSettings.photoQuality.set(String(step))
                legacy.removeLegacyKey("outgoingPhotoQuality")
            }
            moveBool(legacy, "sendLargePhotos", to: WGCallsMediaSettings.largePhotos)
            moveBool(legacy, "uploadSpeedBoost", to: WGCallsMediaSettings.uploadBoost)
            if let boost = legacy.string("downloadSpeedBoost") {
                switch boost {
                case "medium":
                    WGCallsMediaSettings.downloadBoost.set(WGDownloadBoostMode.medium.rawValue)
                case "maximum":
                    WGCallsMediaSettings.downloadBoost.set(WGDownloadBoostMode.maximum.rawValue)
                default:
                    break
                }
                legacy.removeLegacyKey("downloadSpeedBoost")
            }

            moveBool(legacy, "GG.downloadStatus.chatList", to: WGCallsMediaSettings.statusInChatList)
            // The folder ring of the old client was never wired; its switch is not carried over.
            legacy.removeLegacyKey("GG.downloadStatus.folders")

            moveBool(legacy, "videoSubtitles", to: WGCallsMediaSettings.subtitles)
            if let language = legacy.string("videoSubtitlesLanguage") {
                WGCallsMediaSettings.subtitlesLanguage.set(language)
                legacy.removeLegacyKey("videoSubtitlesLanguage")
            }
            // Transcription engine and translation backend follow the new rules (Premium / the
            // translation service of the app); the "Saved Messages" notice is gone with that transport.
            for key in ["videoSubtitlesTranscription", "videoSubtitlesTranslationBackend", "videoSubtitlesTelegramNoticeShown"] {
                legacy.removeLegacyKey(key)
            }
        }

        // «Лента» and the music status (Spotify) were removed by the owner on 2026-10-27. Whatever
        // they left goes once: the old client's keys, this app's settings (build 185 and earlier),
        // the Spotify tokens in the Keychain and the feed's watch history. The profile music the
        // status put on the server stays: it is the user's profile now.
        WGMigrations.registerGlobal(id: "callsMedia.removedFeatures.v1") { legacy in
            for key in WGCallsMediaMigrations.removedLegacyKeys {
                legacy.removeLegacyKey(key)
            }
            WGRetiredSettings.remove(prefixes: WGCallsMediaMigrations.removedPrefixes)
            WGCallsMediaMigrations.removeSpotifyKeychainItems()
        }
        WGMigrations.registerAccount(id: "callsMedia.removedFeatures.account.v1") { _, account in
            WGRetiredSettings.remove(prefixes: WGCallsMediaMigrations.removedPrefixes, account: account)
            WGRetiredSettings.removeAccountFiles(["feed-history.json"], account: account)
        }
        // Builds ≤ 185 had two switches, «аудиозвонки» and «видеозвонки»; since 2026-10-27 they are
        // one choice. Their stored values are carried over once, then dropped from the settings file.
        WGMigrations.registerGlobal(id: "calls.record.merge.v1") { _ in
            WGCallsMediaMigrations.mergeRetiredRecording()
        }
        // The photo quality and size moved from global.json to the App Group file the share
        // extension reads (MEDIA-12), under new keys: the values of the old ones are carried over.
        WGMigrations.registerGlobal(id: "downloads.photos.appGroup.v1") { _ in
            if let quality = WGRetiredSettings.value("downloads.photoQuality", as: String.self) {
                WGCallsMediaSettings.photoQuality.set(quality)
            }
            if let largePhotos = WGRetiredSettings.value("downloads.largePhotos", as: Bool.self) {
                WGCallsMediaSettings.largePhotos.set(largePhotos)
            }
            WGRetiredSettings.remove(keys: ["downloads.photoQuality", "downloads.largePhotos"])
        }
    }

    static let retiredRecordingKeys = ["calls.recordAudio", "calls.recordVideo"]

    static func mergeRetiredRecording() {
        let audio = WGRetiredSettings.value("calls.recordAudio", as: Bool.self)
        let video = WGRetiredSettings.value("calls.recordVideo", as: Bool.self)
        if let mode = WGCallRecordingMode.merged(audio: audio, video: video), mode.isOn {
            WGCallsMediaSettings.recordCalls.set(mode.rawValue)
        }
        WGRetiredSettings.remove(keys: WGCallsMediaMigrations.retiredRecordingKeys)
    }

    /// Setting keys of the removed features: `feed.*` (also the account's `feed.peers`) and
    /// `nowPlaying.*` (Client ID, connection state, uploaded documents of each account).
    static let removedPrefixes = ["feed.", "nowPlaying."]

    /// The old Wraithgram's keys of the feed (`WG.videoFeed.*`) and of the music status (`WG.NowPlaying.*`).
    static let removedLegacyKeys: [String] = [
        "GG.videoFeed.isEnabled", "GG.videoFeed.sourceMode", "GG.videoFeed.selectedPeerIds", "GG.videoFeed.showInSettings",
        "GG.videoFeed.includeVideos", "GG.videoFeed.includeGifs", "GG.videoFeed.includeRoundVideos", "GG.videoFeed.includePhotos",
        "GG.videoFeed.onlyUnseen", "GG.videoFeed.onlyUnread", "GG.videoFeed.maxDuration", "GG.videoFeed.shuffle",
        "GG.videoFeed.autoplay", "GG.videoFeed.loopVideos", "GG.videoFeed.startUnmuted", "GG.videoFeed.autoAdvance",
        "GG.videoFeed.doubleTapToReact", "GG.videoFeed.swipeRightToOpenChat", "GG.videoFeed.holdToSpeedUp",
        "GG.videoFeed.suppressReadReceipts", "GG.videoFeed.dontMarkMediaSeen", "GG.videoFeed.dontSaveHistory",
        "GG.videoFeed.watchHistory", "GG.videoFeed.catalog.json", "GG.videoFeed.catalog.fetchedAt",
        "GG.NowPlaying.enabled", "GG.NowPlaying.source", "GG.NowPlaying.debounceInterval", "GG.NowPlaying.profileDocument",
        "GG.NowPlaying.devForceEnabled", "GG.NowPlaying.spotify.clientId", "GG.NowPlaying.spotify.expiresAt"
    ]

    /// Every item of the Spotify service: this app's session and the old client's access and
    /// refresh tokens (same service, same bundle id). Off the launch thread: a Keychain call is IPC.
    private static func removeSpotifyKeychainItems() {
        DispatchQueue.global(qos: .utility).async {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "org.ghostgram.nowplaying.spotify"
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    private static func moveBool(_ legacy: WGLegacyDefaults, _ key: String, to setting: WGSetting<Bool>) {
        if let value = legacy.bool(key) {
            setting.set(value)
            legacy.removeLegacyKey(key)
        }
    }

    private struct LegacyMediaItem: Decodable {
        var id: String
        var title: String
        var fileName: String
        var kind: String
        var createdAt: Double?
    }

    private static func legacySoundItems(json: String) -> [WGCallSoundItem] {
        guard let data = json.data(using: .utf8), let items = try? JSONDecoder().decode([LegacyMediaItem].self, from: data) else {
            return []
        }
        return items.filter { $0.kind == "audio" }.map { item in
            return WGCallSoundItem(id: item.id, title: item.title.isEmpty ? item.id : item.title, fileName: item.fileName, isLegacy: true, createdAt: item.createdAt ?? 0.0)
        }
    }
}
