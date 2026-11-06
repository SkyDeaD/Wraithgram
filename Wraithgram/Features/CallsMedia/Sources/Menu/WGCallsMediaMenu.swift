import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import ItemListUI
import PresentationDataUtils
import WGCore
import WGSettingsUI

/// The zone's menu: «Медиа и звонки › Звонки / Загрузки и качество» and the «Субтитры к видео»
/// section of «Сообщения › Перевод». Section orders on the skeleton tabs start at 300 (100 and 200
/// are the skeleton's preview and main sections); masks in calls (W3-2) use 800+. «Лента» and the
/// music status were removed by the owner on 2026-10-27 (with their tab «Лента и музыка»).
enum WGCallsMediaMenu {
    static let recordingsTab = WGMenuTabID("calls.recordings")
    static let soundsTab = WGMenuTabID("calls.sounds")

    static func register() {
        WGCallsMediaMenu.registerCalls()
        WGCallsMediaMenu.registerDownloads()
        WGCallsMediaMenu.registerSubtitles()
    }

    private static func toggle(_ id: String, section: WGMenuSectionID, order: Int, setting: WGSetting<Bool>, title: @escaping () -> String, subtitle: (() -> String)? = nil, isVisible: ((WGMenuContext) -> Bool)? = nil, keywords: @escaping () -> [String] = { [] }) -> WGMenuRow {
        return WGMenuRow(id: id, section: section, order: order, title: title, subtitle: subtitle, kind: .toggle(.global(setting)), isVisible: isVisible, searchKeywords: keywords)
    }

    // MARK: Calls

    private static func registerCalls() {
        let screen = WGMenuScreenID.tab(.mediaCalls)
        let recording = WGMenuSectionID("calls.recording")
        let microphone = WGMenuSectionID("calls.microphone")
        let callScreen = WGMenuSectionID("calls.screen")
        let sounds = WGMenuSectionID("calls.soundboard")
        let network = WGMenuSectionID("calls.network")

        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: recording, screen: screen, order: 300, header: { WGStrings.Calls.Menu.recordingHeader }, footer: { _ in WGStrings.Calls.Menu.recordingFooter }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: microphone, screen: screen, order: 400, header: { WGStrings.Calls.Menu.microphoneHeader }, footer: { _ in WGStrings.Calls.Menu.silentMuteFooter }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: callScreen, screen: screen, order: 500, header: { WGStrings.Calls.Menu.screenHeader }, footer: { _ in WGStrings.Calls.Menu.screenFooter }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: sounds, screen: screen, order: 600, header: { WGStrings.Calls.Menu.soundboardHeader }, footer: { _ in WGStrings.Calls.Menu.soundboardFooter }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: network, screen: screen, order: 700, header: { WGStrings.Calls.Menu.networkHeader }, footer: { _ in WGStrings.Calls.Menu.forceTcpFooter }))

        let isRecording: (WGMenuContext) -> Bool = { _ in
            return WGCallsMediaSettings.recordingMode.isOn
        }
        // One choice instead of «аудиозвонки» + «видеозвонки» (2026-10-27).
        WGMenuRegistry.register(WGMenuRow(id: "calls.record", section: recording, order: 100, title: { WGStrings.Calls.Menu.record }, subtitle: { WGStrings.Calls.Menu.recordInfo }, kind: .choice(.global(WGCallsMediaSettings.recordCalls), options: [
            WGMenuChoiceOption(value: WGCallRecordingMode.off.rawValue, title: { WGStrings.Calls.Menu.recordOff }),
            WGMenuChoiceOption(value: WGCallRecordingMode.audio.rawValue, title: { WGStrings.Calls.Menu.recordAudioOnly }),
            WGMenuChoiceOption(value: WGCallRecordingMode.audioAndVideo.rawValue, title: { WGStrings.Calls.Menu.recordAudioAndVideo })
        ]), searchKeywords: { [WGStrings.Calls.Menu.keywordRecording] }))
        WGMenuRegistry.register(toggle("calls.recordOwnVoice", section: recording, order: 200, setting: WGCallsMediaSettings.recordOwnVoice, title: { WGStrings.Calls.Menu.recordOwnVoice }, isVisible: isRecording))
        WGMenuRegistry.register(tab: WGMenuTabDescriptor(id: WGCallsMediaMenu.recordingsTab, parent: screen, title: { WGStrings.Calls.Recordings.title }, makeScreen: { context in
            return wgMakeCallRecordingsScreen(menuContext: context)
        }), linkIn: recording, order: 400, subtitle: { WGStrings.Calls.Menu.recordingsInfo }, icon: .bundle("Chat/Context Menu/VoiceChat"), label: { context in
            return WGStrings.Calls.Menu.recordingsCount(count: WGCallsMediaSettings.recordings.value(for: context.accountID).count)
        })

        WGMenuRegistry.register(toggle("calls.silentMute", section: microphone, order: 100, setting: WGCallsMediaSettings.silentMute, title: { WGStrings.Calls.Menu.silentMute }, subtitle: { WGStrings.Calls.Menu.silentMuteInfo }))

        WGMenuRegistry.register(toggle("calls.disableRating", section: callScreen, order: 100, setting: WGCallsMediaSettings.disableRating, title: { WGStrings.Calls.Menu.disableRating }))
        WGMenuRegistry.register(toggle("calls.statsOverlay", section: callScreen, order: 200, setting: WGCallsMediaSettings.statsOverlay, title: { WGStrings.Calls.Menu.statsOverlay }, subtitle: { WGStrings.Calls.Menu.statsOverlayInfo }))

        let soundboardOn: (WGMenuContext) -> Bool = { _ in
            return WGCallsMediaSettings.soundboard.value
        }
        WGMenuRegistry.register(toggle("calls.soundboard", section: sounds, order: 100, setting: WGCallsMediaSettings.soundboard, title: { WGStrings.Calls.Menu.soundboard }, keywords: { [WGStrings.Calls.Menu.keywordSounds] }))
        WGMenuRegistry.register(WGMenuRow(id: "calls.soundboardVolume", section: sounds, order: 200, title: { WGStrings.Calls.Menu.soundboardVolume }, kind: .slider(.global(WGCallsMediaSettings.soundboardVolume), range: 0.1 ... 1.0, step: 0.05, format: { value in
            return "\(Int((value * 100.0).rounded())) %"
        }), isVisible: soundboardOn))
        WGMenuRegistry.register(toggle("calls.soundboardDuck", section: sounds, order: 300, setting: WGCallsMediaSettings.soundboardDuck, title: { WGStrings.Calls.Menu.soundboardDuck }, subtitle: { WGStrings.Calls.Menu.soundboardDuckInfo }, isVisible: soundboardOn))
        WGMenuRegistry.register(tab: WGMenuTabDescriptor(id: WGCallsMediaMenu.soundsTab, parent: screen, title: { WGStrings.Calls.Sounds.title }, makeScreen: { context in
            return wgMakeSoundLibraryScreen(menuContext: context)
        }), linkIn: sounds, order: 400, subtitle: { WGStrings.Calls.Menu.soundsInfo }, icon: .bundle("Chat/Context Menu/AddMusic"), label: { _ in
            return WGStrings.Calls.Menu.soundsCount(count: WGCallsMediaSettings.soundboardItems.value.count)
        })

        WGMenuRegistry.register(toggle("calls.forceTcp", section: network, order: 100, setting: WGCallsMediaSettings.forceTcp, title: { WGStrings.Calls.Menu.forceTcp }))
    }

    // MARK: Downloads and quality

    private static func registerDownloads() {
        let screen = WGMenuScreenID.tab(.mediaDownloads)
        let status = WGMenuSectionID("downloads.status")
        let boost = WGMenuSectionID("downloads.boost")
        let photos = WGMenuSectionID("downloads.photos")
        let gallery = WGMenuSectionID("downloads.gallery")

        WGMenuRegistry.register(WGMenuRow(id: "downloads.preview", section: .preview(of: .mediaDownloads), order: 100, title: { "" }, kind: .preview(.miniChatList(WGMiniChatListConfiguration(scope: "downloads", height: 152.0, rows: { _ in
            var rows = Array(WGPreviewChatListRow.samples().prefix(2))
            if WGCallsMediaSettings.statusInChatList.value, !rows.isEmpty {
                rows[0].text = "⬇︎ " + WGStrings.Downloads.Preview.fileName + " · 42 %"
                rows[0].isTyping = false
            }
            return rows
        })))))

        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: status, screen: screen, order: 300, header: { WGStrings.Downloads.Menu.statusHeader }, footer: { _ in WGStrings.Downloads.Menu.statusFooter }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: boost, screen: screen, order: 400, header: { WGStrings.Downloads.Menu.boostHeader }, footer: { _ in WGStrings.Downloads.Menu.boostFooter }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: photos, screen: screen, order: 500, header: { WGStrings.Downloads.Menu.photosHeader }, footer: { _ in WGStrings.Downloads.Menu.photosFooter }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: gallery, screen: screen, order: 600, header: { WGStrings.Downloads.Menu.galleryHeader }, footer: { _ in WGStrings.Downloads.Menu.galleryFooter }))

        WGMenuRegistry.register(toggle("downloads.statusInChatList", section: status, order: 100, setting: WGCallsMediaSettings.statusInChatList, title: { WGStrings.Downloads.Menu.statusInChatList }))
        WGMenuRegistry.register(toggle("downloads.statusInChat", section: status, order: 200, setting: WGCallsMediaSettings.statusInChat, title: { WGStrings.Downloads.Menu.statusInChat }))

        // Both boosts ask once before they switch on: the server may answer with flood waits.
        WGMenuRegistry.register(WGMenuRow(id: "downloads.uploadBoost", section: boost, order: 100, title: { WGStrings.Downloads.Menu.uploadBoost }, kind: .custom({ context in
            return ItemListSwitchItem(presentationData: context.itemListPresentationData, systemStyle: .glass, title: WGStrings.Downloads.Menu.uploadBoost, value: WGCallsMediaSettings.uploadBoost.value, enableInteractiveChanges: false, maximumNumberOfLines: 2, sectionId: context.sectionId, style: .blocks, updated: { value in
                if value {
                    WGCallsMediaMenu.confirmBoost(context: context, apply: {
                        WGCallsMediaSettings.uploadBoost.set(true)
                    })
                } else {
                    WGCallsMediaSettings.uploadBoost.set(false)
                }
            })
        }), searchKeywords: { [WGStrings.Downloads.Menu.keywordSpeed] }))
        WGMenuRegistry.register(WGMenuRow(id: "downloads.downloadBoost", section: boost, order: 200, title: { WGStrings.Downloads.Menu.downloadBoost }, kind: .action({ context in
            WGCallsMediaMenu.chooseDownloadBoost(context: context)
        }), searchKeywords: { [WGStrings.Downloads.Menu.keywordSpeed] }, label: { _ in
            return WGCallsMediaMenu.downloadBoostTitle(WGDownloadBoostMode(rawValue: WGCallsMediaSettings.downloadBoost.value) ?? .off)
        }))

        var qualityOptions = [WGMenuChoiceOption(value: "", title: { WGStrings.Downloads.Menu.photoQualityDefault })]
        for value in ["60", "70", "80", "90", "100"] {
            qualityOptions.append(WGMenuChoiceOption(value: value, title: { value + " %" }))
        }
        WGMenuRegistry.register(WGMenuRow(id: "downloads.photoQuality", section: photos, order: 100, title: { WGStrings.Downloads.Menu.photoQuality }, kind: .choice(.global(WGCallsMediaSettings.photoQuality), options: qualityOptions)))
        WGMenuRegistry.register(toggle("downloads.largePhotos", section: photos, order: 200, setting: WGCallsMediaSettings.largePhotos, title: { WGStrings.Downloads.Menu.largePhotos }, subtitle: { WGStrings.Downloads.Menu.largePhotosInfo }))

        WGMenuRegistry.register(toggle("gallery.copyPhoto", section: gallery, order: 100, setting: WGCallsMediaSettings.copyPhotoItem, title: { WGStrings.Gallery.Menu.copyPhoto }))
        WGMenuRegistry.register(toggle("gallery.airPlay", section: gallery, order: 200, setting: WGCallsMediaSettings.airPlayItem, title: { WGStrings.Gallery.Menu.airPlay }, subtitle: { WGStrings.Gallery.Menu.airPlayInfo }))
    }

    private static func confirmBoost(context: WGMenuContext, apply: @escaping () -> Void) {
        let presentationData = context.presentationData
        context.present(textAlertController(context: context.context, title: WGStrings.Downloads.Boost.warningTitle, text: WGStrings.Downloads.Boost.warningText, actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .defaultAction, title: WGStrings.Downloads.Boost.warningConfirm, action: {
                apply()
            })
        ]))
    }

    private static func downloadBoostTitle(_ mode: WGDownloadBoostMode) -> String {
        switch mode {
        case .off:
            return WGStrings.Downloads.Boost.off
        case .medium:
            return WGStrings.Downloads.Boost.medium
        case .maximum:
            return WGStrings.Downloads.Boost.maximum
        }
    }

    private static func chooseDownloadBoost(context: WGMenuContext) {
        let current = WGDownloadBoostMode(rawValue: WGCallsMediaSettings.downloadBoost.value) ?? .off
        var actions: [(title: String, isDestructive: Bool, action: () -> Void)] = []
        for mode in [WGDownloadBoostMode.off, .medium, .maximum] {
            let title = (mode == current ? "✓ " : "") + WGCallsMediaMenu.downloadBoostTitle(mode)
            actions.append((title, false, {
                if mode == .off || current != .off {
                    WGCallsMediaSettings.downloadBoost.set(mode.rawValue)
                } else {
                    WGCallsMediaMenu.confirmBoost(context: context, apply: {
                        WGCallsMediaSettings.downloadBoost.set(mode.rawValue)
                    })
                }
            }))
        }
        wgPresentMediaActionSheet(context: context.context, title: WGStrings.Downloads.Menu.downloadBoost, actions: actions, present: { context.present($0) })
    }

    // MARK: Subtitles

    private static func registerSubtitles() {
        let section = WGMenuSectionID("subtitles.main")
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: section, screen: .tab(.messagesTranslation), order: 400, header: { WGStrings.Subtitles.Menu.header }, footer: { _ in WGStrings.Subtitles.Menu.footer }))
        WGMenuRegistry.register(toggle("subtitles.enabled", section: section, order: 100, setting: WGCallsMediaSettings.subtitles, title: { WGStrings.Subtitles.Menu.enabled }, subtitle: { WGStrings.Subtitles.Menu.enabledInfo }, keywords: { [WGStrings.Subtitles.Menu.keyword] }))
        WGMenuRegistry.register(toggle("subtitles.translate", section: section, order: 200, setting: WGCallsMediaSettings.subtitlesTranslate, title: { WGStrings.Subtitles.Menu.translate }, isVisible: { _ in WGCallsMediaSettings.subtitles.value }))
        var options = [WGMenuChoiceOption(value: "", title: { WGStrings.Subtitles.Menu.languageAuto })]
        for code in ["en", "ru", "uk", "be", "kk", "de", "fr", "es", "it", "pt", "pl", "tr", "ar", "fa", "he", "hi", "zh", "ja", "ko"] {
            options.append(WGMenuChoiceOption(value: code, title: {
                // Language names come from the system in the language of the interface.
                let interface = Locale(identifier: WGLocalization.shared.languageCode)
                return interface.localizedString(forLanguageCode: code) ?? code
            }))
        }
        WGMenuRegistry.register(WGMenuRow(id: "subtitles.language", section: section, order: 300, title: { WGStrings.Subtitles.Menu.language }, kind: .choice(.global(WGCallsMediaSettings.subtitlesLanguage), options: options), isVisible: { _ in WGCallsMediaSettings.subtitles.value && WGCallsMediaSettings.subtitlesTranslate.value }))
    }
}
