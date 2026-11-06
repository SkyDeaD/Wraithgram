import Foundation
import UIKit
import Display
import TelegramCore
import AccountContext
import PromptUI
import PresentationDataUtils
import WGCore
import WGSettingsUI
import WGCameraPipeline
import WGFeaturesShared

/// Menu rows of the zone: «Медиа и звонки › Кружки и камера» (masks, round video settings, gallery,
/// photo watermark), the «Маски и камера» section of «Звонки», «Приватность › Анонимный режим».
/// Every row is a binding to a registry setting: writing it rebuilds the screen, nothing else.
enum WGCameraMasksMenu {
    static let tab = WGMenuTabID.mediaCameraVideoMessages

    static let sectionQuality = WGMenuSectionID("media.cameraVideoMessages.quality")
    static let sectionCamera = WGMenuSectionID("media.cameraVideoMessages.camera")
    static let sectionRecording = WGMenuSectionID("media.cameraVideoMessages.recording")
    static let sectionSound = WGMenuSectionID("media.cameraVideoMessages.sound")
    static let sectionWatermark = WGMenuSectionID("media.cameraVideoMessages.watermark")
    static let sectionGallery = WGMenuSectionID("media.cameraVideoMessages.gallery")
    static let sectionPhotoWatermark = WGMenuSectionID("media.cameraVideoMessages.photoWatermark")
    static let sectionReset = WGMenuSectionID("media.cameraVideoMessages.reset")
    static let sectionCalls = WGMenuSectionID("media.calls.cameraMasks")

    static let masksTab = WGMenuTabID("cameraMasks.masks")
    static let studioTab = WGMenuTabID("cameraMasks.studio")
    static let virtualCameraTab = WGMenuTabID("cameraMasks.virtualCamera")

    static func register() {
        WGCameraMasksMenu.registerSections()
        WGCameraMasksMenu.registerPreview()
        WGCameraMasksMenu.registerMasks()
        WGCameraMasksMenu.registerQuality()
        WGCameraMasksMenu.registerCamera()
        WGCameraMasksMenu.registerRecording()
        WGCameraMasksMenu.registerSound()
        WGCameraMasksMenu.registerWatermark()
        WGCameraMasksMenu.registerGallery()
        WGCameraMasksMenu.registerPhotoWatermark()
        WGCameraMasksMenu.registerReset()
        WGCameraMasksMenu.registerCalls()
        WGCameraMasksMenu.registerAnonymousMode()
    }

    private static func registerSections() {
        let screen = WGMenuScreenID.tab(WGCameraMasksMenu.tab)
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGCameraMasksMenu.sectionQuality, screen: screen, order: 300, header: { WGStrings.CameraMasks.Round.Section.quality }, footer: { _ in WGStrings.CameraMasks.Round.qualityFooter }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGCameraMasksMenu.sectionCamera, screen: screen, order: 400, header: { WGStrings.CameraMasks.Round.Section.camera }, footer: { _ in WGStrings.CameraMasks.Round.cameraFooter }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGCameraMasksMenu.sectionRecording, screen: screen, order: 500, header: { WGStrings.CameraMasks.Round.Section.recording }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGCameraMasksMenu.sectionSound, screen: screen, order: 600, header: { WGStrings.CameraMasks.Round.Section.sound }, footer: { _ in WGStrings.CameraMasks.Round.soundFooter }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGCameraMasksMenu.sectionWatermark, screen: screen, order: 700, header: { WGStrings.CameraMasks.Round.Section.watermark }, footer: { _ in WGStrings.CameraMasks.Round.watermarkFooter }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGCameraMasksMenu.sectionGallery, screen: screen, order: 800, header: { WGStrings.CameraMasks.Round.Section.gallery }, footer: { _ in WGStrings.CameraMasks.Round.galleryFooter }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGCameraMasksMenu.sectionPhotoWatermark, screen: screen, order: 900, header: { WGStrings.CameraMasks.Photo.section }, footer: { _ in WGStrings.CameraMasks.Photo.footer }))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGCameraMasksMenu.sectionReset, screen: screen, order: 1000))
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(id: WGCameraMasksMenu.sectionCalls, screen: .tab(.mediaCalls), order: 800, header: { WGStrings.CameraMasks.Calls.section }, footer: { _ in WGStrings.CameraMasks.Calls.footer }))
    }

    private static func registerPreview() {
        WGMenuRegistry.register(WGMenuRow(
            id: "cameraMasks.roundVideo.preview",
            section: .preview(of: WGCameraMasksMenu.tab),
            order: 100,
            title: { "" },
            kind: .preview(.custom(height: 236.0, make: { _ in
                return WGRoundVideoPreviewView(frame: .zero)
            }))
        ))
    }

    // MARK: Masks

    private static func registerMasks() {
        WGMenuRegistry.register(WGMenuRow(
            id: "cameraMasks.masks.enabled",
            section: .main(of: WGCameraMasksMenu.tab),
            order: 100,
            title: { WGStrings.CameraMasks.Masks.enabled },
            subtitle: { WGStrings.CameraMasks.Masks.enabledInfo },
            kind: .toggle(.global(WGMaskSettings.enabled)),
            searchKeywords: { [WGStrings.CameraMasks.Masks.keywords] }
        ))
        WGMenuRegistry.register(
            tab: WGMenuTabDescriptor(
                id: WGCameraMasksMenu.masksTab,
                parent: .tab(WGCameraMasksMenu.tab),
                title: { WGStrings.CameraMasks.Masks.title },
                makeScreen: { context in
                    return wgMakeMaskLibraryScreen(context: context.context, target: .current)
                },
                searchKeywords: { [WGStrings.CameraMasks.Masks.keywords] }
            ),
            linkIn: .main(of: WGCameraMasksMenu.tab),
            order: 200,
            subtitle: { WGStrings.CameraMasks.Masks.chooseInfo },
            icon: .system("theatermasks"),
            label: { context in
                return WGMaskEngine.title(WGMaskSelection(storage: WGMaskSettings.selection.value))
            }
        )
        WGMenuRegistry.register(
            tab: WGMenuTabDescriptor(
                id: WGCameraMasksMenu.studioTab,
                parent: .tab(WGCameraMasksMenu.tab),
                title: { WGStrings.CameraMasks.Studio.title },
                makeScreen: { context in
                    return wgMakeMaskStudioHome(context: context.context)
                },
                searchKeywords: { [WGStrings.CameraMasks.Studio.keywords] }
            ),
            linkIn: .main(of: WGCameraMasksMenu.tab),
            order: 300,
            subtitle: { WGStrings.CameraMasks.Studio.info },
            icon: .system("paintbrush"),
            label: { _ in
                let count = WGMaskStore.shared.currentEntries.count
                return count > 0 ? "\(count)" : nil
            }
        )
    }

    // MARK: Quality

    private static func registerQuality() {
        let section = WGCameraMasksMenu.sectionQuality
        WGMenuRegistry.register(WGMenuRow(
            id: "cameraMasks.roundVideo.resolution",
            section: section,
            order: 100,
            title: { WGStrings.CameraMasks.Round.resolution },
            kind: .choice(.global(WGRoundVideoSettings.resolution), options: [
                WGMenuChoiceOption(value: "standard", title: { WGStrings.CameraMasks.Round.asTelegram }),
                WGMenuChoiceOption(value: "400", title: { WGStrings.CameraMasks.Round.side(side: "400") }),
                WGMenuChoiceOption(value: "512", title: { WGStrings.CameraMasks.Round.side(side: "512") }),
                WGMenuChoiceOption(value: "640", title: { WGStrings.CameraMasks.Round.side(side: "640") })
            ]),
            searchKeywords: { [WGStrings.CameraMasks.Round.qualityKeywords] }
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "cameraMasks.roundVideo.bitrate",
            section: section,
            order: 200,
            title: { WGStrings.CameraMasks.Round.bitrate },
            kind: .slider(.global(WGRoundVideoSettings.bitrate), range: 0.0 ... 4000.0, step: 500.0, format: { value in
                if value < 500.0 {
                    return WGStrings.CameraMasks.Round.asTelegram
                }
                // What is really recorded: above Telegram's size limit the bitrate is lowered
                // (WGRoundVideoConfig.recording), so the slider says so instead of the chosen value.
                if let maximum = WGRoundVideoServerLimits.maximumVideoKbps(audioKbps: WGRoundVideoServerLimits.audioKbps), Double(maximum) < min(4000.0, value) {
                    return WGStrings.CameraMasks.Round.bitrateLimited(value: String(format: "%.1f", Double(maximum) / 1000.0))
                }
                return WGStrings.CameraMasks.Round.bitrateValue(value: String(format: "%.1f", value / 1000.0))
            })
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "cameraMasks.roundVideo.codec",
            section: section,
            order: 300,
            title: { WGStrings.CameraMasks.Round.codec },
            kind: .choice(.global(WGRoundVideoSettings.codec), options: [
                WGMenuChoiceOption(value: WGRoundVideoCodec.h264.rawValue, title: { WGStrings.CameraMasks.Round.codecH264 }),
                WGMenuChoiceOption(value: WGRoundVideoCodec.hevc.rawValue, title: { WGStrings.CameraMasks.Round.codecHevc })
            ])
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "cameraMasks.roundVideo.frameRate",
            section: section,
            order: 400,
            title: { WGStrings.CameraMasks.Round.frameRate },
            subtitle: { WGStrings.CameraMasks.Round.frameRateInfo },
            kind: .choice(.global(WGRoundVideoSettings.frameRate), options: [
                WGMenuChoiceOption(value: "30", title: { WGStrings.CameraMasks.Round.fps(fps: "30") }),
                WGMenuChoiceOption(value: "60", title: { WGStrings.CameraMasks.Round.fps(fps: "60") })
            ])
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "cameraMasks.roundVideo.stabilization",
            section: section,
            order: 500,
            title: { WGStrings.CameraMasks.Round.stabilization },
            kind: .choice(.global(WGRoundVideoSettings.stabilization), options: [
                WGMenuChoiceOption(value: WGRoundVideoStabilization.standard.rawValue, title: { WGStrings.CameraMasks.Round.stabilizationStandard }),
                WGMenuChoiceOption(value: WGRoundVideoStabilization.off.rawValue, title: { WGStrings.CameraMasks.Round.stabilizationOff }),
                WGMenuChoiceOption(value: WGRoundVideoStabilization.cinematic.rawValue, title: { WGStrings.CameraMasks.Round.stabilizationCinematic })
            ])
        ))
    }

    // MARK: Camera

    private static func registerCamera() {
        let section = WGCameraMasksMenu.sectionCamera
        WGMenuRegistry.register(WGMenuRow(
            id: "cameraMasks.roundVideo.rearCamera",
            section: section,
            order: 100,
            title: { WGStrings.CameraMasks.Round.rearCamera },
            subtitle: { WGStrings.CameraMasks.Round.rearCameraInfo },
            kind: .toggle(.global(WGRoundVideoSettings.startWithRearCamera))
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "cameraMasks.roundVideo.startZoom",
            section: section,
            order: 200,
            title: { WGStrings.CameraMasks.Round.startZoom },
            kind: .choice(.global(WGRoundVideoSettings.startZoom), options: [
                WGMenuChoiceOption(value: WGRoundVideoStartZoom.one.rawValue, title: { WGStrings.CameraMasks.Round.zoomOne }),
                WGMenuChoiceOption(value: WGRoundVideoStartZoom.two.rawValue, title: { WGStrings.CameraMasks.Round.zoomTwo }),
                WGMenuChoiceOption(value: WGRoundVideoStartZoom.last.rawValue, title: { WGStrings.CameraMasks.Round.zoomLast })
            ])
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "cameraMasks.roundVideo.rememberZoom",
            section: section,
            order: 300,
            title: { WGStrings.CameraMasks.Round.rememberZoom },
            subtitle: { WGStrings.CameraMasks.Round.rememberZoomInfo },
            kind: .toggle(.global(WGRoundVideoSettings.rememberZoom))
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "cameraMasks.roundVideo.zoomSlider",
            section: section,
            order: 400,
            title: { WGStrings.CameraMasks.Round.zoomSlider },
            subtitle: { WGStrings.CameraMasks.Round.zoomSliderInfo },
            kind: .toggle(.global(WGRoundVideoSettings.zoomSlider))
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "cameraMasks.roundVideo.rearHalfZoom",
            section: section,
            order: 450,
            title: { WGStrings.CameraMasks.Round.rearHalfZoom },
            subtitle: { WGStrings.CameraMasks.Round.rearHalfZoomInfo },
            kind: .toggle(.global(WGRoundVideoSettings.rearHalfZoom)),
            isVisible: { _ in WGRoundVideoConfig.hasUltraWideCamera }
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "cameraMasks.roundVideo.flipAnimation",
            section: section,
            order: 500,
            title: { WGStrings.CameraMasks.Round.flipAnimation },
            subtitle: { WGStrings.CameraMasks.Round.flipAnimationInfo },
            kind: .toggle(.global(WGRoundVideoSettings.flipAnimation))
        ))
    }

    // MARK: Recording

    private static func registerRecording() {
        let section = WGCameraMasksMenu.sectionRecording
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.roundVideo.countdown", section: section, order: 100, title: { WGStrings.CameraMasks.Round.countdown }, subtitle: { WGStrings.CameraMasks.Round.countdownInfo }, kind: .toggle(.global(WGRoundVideoSettings.countdown))))
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.roundVideo.viewOnce", section: section, order: 200, title: { WGStrings.CameraMasks.Round.viewOnce }, subtitle: { WGStrings.CameraMasks.Round.viewOnceInfo }, kind: .toggle(.global(WGRoundVideoSettings.viewOnceByDefault))))
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.roundVideo.sendAsVideo", section: section, order: 300, title: { WGStrings.CameraMasks.Round.sendAsVideo }, subtitle: { WGStrings.CameraMasks.Round.sendAsVideoInfo }, kind: .toggle(.global(WGRoundVideoSettings.sendAsRegularVideo))))
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.roundVideo.saveToGallery", section: section, order: 400, title: { WGStrings.CameraMasks.Round.saveToGallery }, subtitle: { WGStrings.CameraMasks.Round.saveToGalleryInfo }, kind: .toggle(.global(WGRoundVideoSettings.saveCopyToGallery))))
    }

    // MARK: Sound

    private static func registerSound() {
        let section = WGCameraMasksMenu.sectionSound
        WGMenuRegistry.register(WGMenuRow(
            id: "cameraMasks.roundVideo.microphone",
            section: section,
            order: 100,
            title: { WGStrings.CameraMasks.Round.microphone },
            kind: .choice(.global(WGRoundVideoSettings.microphoneMode), options: [
                WGMenuChoiceOption(value: WGRoundVideoMicrophoneMode.standard.rawValue, title: { WGStrings.CameraMasks.Round.asTelegram }),
                WGMenuChoiceOption(value: WGRoundVideoMicrophoneMode.videoRecording.rawValue, title: { WGStrings.CameraMasks.Round.microphoneVideo }),
                WGMenuChoiceOption(value: WGRoundVideoMicrophoneMode.voiceChat.rawValue, title: { WGStrings.CameraMasks.Round.microphoneVoice })
            ])
        ))
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.roundVideo.normalize", section: section, order: 200, title: { WGStrings.CameraMasks.Round.normalize }, subtitle: { WGStrings.CameraMasks.Round.normalizeInfo }, kind: .toggle(.global(WGRoundVideoSettings.normalizeAudio))))
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.roundVideo.mute", section: section, order: 300, title: { WGStrings.CameraMasks.Round.mute }, subtitle: { WGStrings.CameraMasks.Round.muteInfo }, kind: .toggle(.global(WGRoundVideoSettings.muteAudio))))
    }

    // MARK: Watermark (round)

    static func fontOptions() -> [WGMenuChoiceOption] {
        return [
            WGMenuChoiceOption(value: WGWatermarkFont.regular.rawValue, title: { WGStrings.CameraMasks.Watermark.fontRegular }),
            WGMenuChoiceOption(value: WGWatermarkFont.bold.rawValue, title: { WGStrings.CameraMasks.Watermark.fontBold }),
            WGMenuChoiceOption(value: WGWatermarkFont.mono.rawValue, title: { WGStrings.CameraMasks.Watermark.fontMono }),
            WGMenuChoiceOption(value: WGWatermarkFont.italic.rawValue, title: { WGStrings.CameraMasks.Watermark.fontItalic })
        ]
    }

    static func colorOptions() -> [WGMenuChoiceOption] {
        return [
            WGMenuChoiceOption(value: WGWatermarkColor.white.rawValue, title: { WGStrings.CameraMasks.Watermark.colorWhite }),
            WGMenuChoiceOption(value: WGWatermarkColor.black.rawValue, title: { WGStrings.CameraMasks.Watermark.colorBlack }),
            WGMenuChoiceOption(value: WGWatermarkColor.red.rawValue, title: { WGStrings.CameraMasks.Watermark.colorRed }),
            WGMenuChoiceOption(value: WGWatermarkColor.yellow.rawValue, title: { WGStrings.CameraMasks.Watermark.colorYellow })
        ]
    }

    /// A row that edits a text setting in a prompt.
    static func textRow(id: String, section: WGMenuSectionID, order: Int, title: @escaping () -> String, prompt: @escaping () -> String, setting: WGSetting<String>, limit: Int, isVisible: ((WGMenuContext) -> Bool)?) -> WGMenuRow {
        return WGMenuRow(
            id: id,
            section: section,
            order: order,
            title: title,
            kind: .action({ context in
                context.present(promptController(context: context.context, text: prompt(), value: setting.value, placeholder: WGStrings.CameraMasks.Watermark.placeholder, characterLimit: limit, apply: { value in
                    if let value {
                        setting.set(value.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }))
            }),
            isVisible: isVisible,
            label: { _ in
                let value = setting.value
                return value.isEmpty ? WGStrings.CameraMasks.Watermark.noText : value
            }
        )
    }

    private static func registerWatermark() {
        let section = WGCameraMasksMenu.sectionWatermark
        let isOn: (WGMenuContext) -> Bool = { _ in
            return WGRoundVideoSettings.watermark.value
        }
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.roundVideo.watermark", section: section, order: 100, title: { WGStrings.CameraMasks.Round.watermark }, kind: .toggle(.global(WGRoundVideoSettings.watermark)), searchKeywords: { [WGStrings.CameraMasks.Watermark.keywords] }))
        WGMenuRegistry.register(WGCameraMasksMenu.textRow(id: "cameraMasks.roundVideo.watermarkText", section: section, order: 200, title: { WGStrings.CameraMasks.Watermark.text }, prompt: { WGStrings.CameraMasks.Watermark.textPrompt }, setting: WGRoundVideoSettings.watermarkText, limit: 48, isVisible: isOn))
        WGMenuRegistry.register(WGMenuRow(
            id: "cameraMasks.roundVideo.watermarkPosition",
            section: section,
            order: 300,
            title: { WGStrings.CameraMasks.Watermark.position },
            kind: .choice(.global(WGRoundVideoSettings.watermarkPosition), options: [
                WGMenuChoiceOption(value: WGRoundWatermarkPosition.bottom.rawValue, title: { WGStrings.CameraMasks.Watermark.positionBottom }),
                WGMenuChoiceOption(value: WGRoundWatermarkPosition.top.rawValue, title: { WGStrings.CameraMasks.Watermark.positionTop }),
                WGMenuChoiceOption(value: WGRoundWatermarkPosition.center.rawValue, title: { WGStrings.CameraMasks.Watermark.positionCenter })
            ]),
            isVisible: isOn
        ))
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.roundVideo.watermarkFont", section: section, order: 400, title: { WGStrings.CameraMasks.Watermark.font }, kind: .choice(.global(WGRoundVideoSettings.watermarkFont), options: WGCameraMasksMenu.fontOptions()), isVisible: isOn))
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.roundVideo.watermarkSize", section: section, order: 500, title: { WGStrings.CameraMasks.Watermark.size }, kind: .slider(.global(WGRoundVideoSettings.watermarkSize), range: 2.0 ... 12.0, step: 1.0, format: { value in WGStrings.CameraMasks.Watermark.percent(value: "\(Int(value))") }), isVisible: isOn))
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.roundVideo.watermarkOpacity", section: section, order: 600, title: { WGStrings.CameraMasks.Watermark.opacity }, kind: .slider(.global(WGRoundVideoSettings.watermarkOpacity), range: 10.0 ... 100.0, step: 5.0, format: { value in WGStrings.CameraMasks.Watermark.percent(value: "\(Int(value))") }), isVisible: isOn))
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.roundVideo.watermarkColor", section: section, order: 700, title: { WGStrings.CameraMasks.Watermark.color }, kind: .choice(.global(WGRoundVideoSettings.watermarkColor), options: WGCameraMasksMenu.colorOptions()), isVisible: isOn))
    }

    // MARK: Gallery (video → round, SG-F5)

    private static func registerGallery() {
        let section = WGCameraMasksMenu.sectionGallery
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.roundVideo.galleryAsRound", section: section, order: 100, title: { WGStrings.CameraMasks.Round.galleryAsRound }, subtitle: { WGStrings.CameraMasks.Round.galleryAsRoundInfo }, kind: .toggle(.global(WGRoundVideoSettings.galleryVideosAsRound))))
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.roundVideo.galleryMenuItem", section: section, order: 150, title: { WGStrings.CameraMasks.Round.galleryMenuItem }, subtitle: { WGStrings.CameraMasks.Round.galleryMenuItemInfo }, kind: .toggle(.global(WGRoundVideoSettings.galleryMenuItem)), isVisible: { _ in !WGRoundVideoSettings.galleryVideosAsRound.value }))
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.gallery.hideCamera", section: section, order: 200, title: { WGStrings.CameraMasks.Gallery.hideCamera }, subtitle: { WGStrings.CameraMasks.Gallery.hideCameraInfo }, kind: .toggle(.global(WGGalleryCameraSettings.hideCamera))))
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.gallery.noLivePreview", section: section, order: 300, title: { WGStrings.CameraMasks.Gallery.noLivePreview }, subtitle: { WGStrings.CameraMasks.Gallery.noLivePreviewInfo }, kind: .toggle(.global(WGGalleryCameraSettings.noLivePreview)), isVisible: { _ in !WGGalleryCameraSettings.hideCamera.value }))
    }

    // MARK: Photo watermark

    private static func registerPhotoWatermark() {
        let section = WGCameraMasksMenu.sectionPhotoWatermark
        let isOn: (WGMenuContext) -> Bool = { _ in
            return WGPhotoWatermarkSettings.enabled.value
        }
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.photoWatermark.preview", section: section, order: 50, title: { "" }, kind: .preview(.custom(height: 190.0, make: { _ in WGPhotoWatermarkPreviewView(frame: .zero) }))))
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.photoWatermark.enabled", section: section, order: 100, title: { WGStrings.CameraMasks.Photo.enabled }, subtitle: { WGStrings.CameraMasks.Photo.enabledInfo }, kind: .toggle(.global(WGPhotoWatermarkSettings.enabled)), searchKeywords: { [WGStrings.CameraMasks.Watermark.keywords] }))
        WGMenuRegistry.register(WGCameraMasksMenu.textRow(id: "cameraMasks.photoWatermark.text", section: section, order: 200, title: { WGStrings.CameraMasks.Watermark.text }, prompt: { WGStrings.CameraMasks.Watermark.textPrompt }, setting: WGPhotoWatermarkSettings.text, limit: 40, isVisible: isOn))
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.photoWatermark.tiled", section: section, order: 300, title: { WGStrings.CameraMasks.Photo.tiled }, kind: .toggle(.global(WGPhotoWatermarkSettings.tiled)), isVisible: isOn))
        WGMenuRegistry.register(WGMenuRow(
            id: "cameraMasks.photoWatermark.position",
            section: section,
            order: 400,
            title: { WGStrings.CameraMasks.Watermark.position },
            kind: .choice(.global(WGPhotoWatermarkSettings.position), options: [
                WGMenuChoiceOption(value: WGPhotoWatermarkPosition.bottomRight.rawValue, title: { WGStrings.CameraMasks.Photo.bottomRight }),
                WGMenuChoiceOption(value: WGPhotoWatermarkPosition.bottomLeft.rawValue, title: { WGStrings.CameraMasks.Photo.bottomLeft }),
                WGMenuChoiceOption(value: WGPhotoWatermarkPosition.topRight.rawValue, title: { WGStrings.CameraMasks.Photo.topRight }),
                WGMenuChoiceOption(value: WGPhotoWatermarkPosition.topLeft.rawValue, title: { WGStrings.CameraMasks.Photo.topLeft }),
                WGMenuChoiceOption(value: WGPhotoWatermarkPosition.center.rawValue, title: { WGStrings.CameraMasks.Watermark.positionCenter })
            ]),
            isVisible: { context in isOn(context) && !WGPhotoWatermarkSettings.tiled.value }
        ))
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.photoWatermark.font", section: section, order: 500, title: { WGStrings.CameraMasks.Watermark.font }, kind: .choice(.global(WGPhotoWatermarkSettings.font), options: WGCameraMasksMenu.fontOptions()), isVisible: isOn))
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.photoWatermark.size", section: section, order: 600, title: { WGStrings.CameraMasks.Watermark.size }, kind: .slider(.global(WGPhotoWatermarkSettings.size), range: 2.0 ... 12.0, step: 1.0, format: { value in WGStrings.CameraMasks.Watermark.percent(value: "\(Int(value))") }), isVisible: isOn))
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.photoWatermark.opacity", section: section, order: 700, title: { WGStrings.CameraMasks.Watermark.opacity }, kind: .slider(.global(WGPhotoWatermarkSettings.opacity), range: 10.0 ... 100.0, step: 5.0, format: { value in WGStrings.CameraMasks.Watermark.percent(value: "\(Int(value))") }), isVisible: isOn))
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.photoWatermark.color", section: section, order: 800, title: { WGStrings.CameraMasks.Watermark.color }, kind: .choice(.global(WGPhotoWatermarkSettings.color), options: WGCameraMasksMenu.colorOptions()), isVisible: isOn))
    }

    // MARK: Reset

    private static func registerReset() {
        WGMenuRegistry.register(WGMenuRow(
            id: "cameraMasks.roundVideo.reset",
            section: WGCameraMasksMenu.sectionReset,
            order: 100,
            title: { WGStrings.CameraMasks.Round.reset },
            kind: .action({ context in
                let presentationData = context.presentationData
                context.present(textAlertController(context: context.context, title: WGStrings.CameraMasks.Round.resetTitle, text: WGStrings.CameraMasks.Round.resetText, actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .destructiveAction, title: WGStrings.CameraMasks.Round.resetConfirm, action: {
                        for setting in WGRoundVideoSettings.resettableKeys {
                            setting.reset()
                        }
                    })
                ]))
            }),
            isEnabled: { _ in
                return WGRoundVideoSettings.resettableKeys.contains(where: { !$0.isDefault() })
            },
            isDestructive: true
        ))
    }

    // MARK: Calls

    private static func registerCalls() {
        let section = WGCameraMasksMenu.sectionCalls
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.calls.masks", section: section, order: 100, title: { WGStrings.CameraMasks.Calls.masks }, subtitle: { WGStrings.CameraMasks.Calls.masksInfo }, kind: .toggle(.global(WGMaskSettings.inCalls)), searchKeywords: { [WGStrings.CameraMasks.Masks.keywords] }))
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.virtualCamera.enabled", section: section, order: 200, title: { WGStrings.CameraMasks.VirtualCamera.enabled }, subtitle: { WGStrings.CameraMasks.VirtualCamera.enabledInfo }, kind: .toggle(.global(WGVirtualCameraSettings.enabled)), searchKeywords: { [WGStrings.CameraMasks.VirtualCamera.keywords] }))
        WGMenuRegistry.register(WGMenuRow(id: "cameraMasks.virtualCamera.loop", section: section, order: 300, title: { WGStrings.CameraMasks.VirtualCamera.loop }, kind: .toggle(.global(WGVirtualCameraSettings.loop)), isVisible: { _ in WGVirtualCameraSettings.enabled.value }))
        WGMenuRegistry.register(
            tab: WGMenuTabDescriptor(
                id: WGCameraMasksMenu.virtualCameraTab,
                parent: .tab(.mediaCalls),
                title: { WGStrings.CameraMasks.VirtualCamera.library },
                makeScreen: { context in
                    return wgMakeVirtualCameraScreen(context: context.context)
                },
                searchKeywords: { [WGStrings.CameraMasks.VirtualCamera.keywords] }
            ),
            linkIn: WGCameraMasksMenu.sectionCalls,
            order: 400,
            subtitle: { WGStrings.CameraMasks.VirtualCamera.libraryInfo },
            icon: .system("photo.on.rectangle"),
            label: { _ in
                if let item = WGVirtualCameraSettings.selectedItem {
                    return item.title
                }
                return nil
            }
        )
    }

    // MARK: Anonymous mode

    private static func registerAnonymousMode() {
        let tab = WGMenuTabID.privacyAnonymousMode
        WGMenuRegistry.register(WGMenuRow(
            id: "cameraMasks.anonymous.active",
            section: .main(of: tab),
            order: 100,
            title: { WGStrings.CameraMasks.Anonymous.toggle },
            subtitle: { WGStrings.CameraMasks.Anonymous.toggleInfo },
            kind: .toggle(.account(WGAnonymousMode.isActive)),
            searchKeywords: { [WGStrings.CameraMasks.Anonymous.keywords] }
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "cameraMasks.anonymous.mask",
            section: .main(of: tab),
            order: 200,
            title: { WGStrings.CameraMasks.Anonymous.mask },
            kind: .action({ context in
                context.push(wgMakeMaskLibraryScreen(context: context.context, target: .anonymous))
            }),
            label: { _ in
                return WGMaskEngine.title(WGMaskSelection(storage: WGAnonymousMode.mask.value))
            }
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "cameraMasks.anonymous.voice",
            section: .main(of: tab),
            order: 300,
            title: { WGStrings.CameraMasks.Anonymous.voice },
            kind: .action({ context in
                let presets = WGAnonymousMode.allVoicePresets()
                let sheet = UIAlertController(title: WGStrings.CameraMasks.Anonymous.voice, message: nil, preferredStyle: .actionSheet)
                for preset in presets {
                    let title = (preset.id == WGAnonymousMode.voice.value ? "✓ " : "") + preset.title()
                    sheet.addAction(UIAlertAction(title: title, style: .default, handler: { _ in
                        WGAnonymousMode.voice.set(preset.id)
                    }))
                }
                sheet.addAction(UIAlertAction(title: context.presentationData.strings.Common_Cancel, style: .cancel))
                context.presentNative(sheet)
            }),
            isVisible: { _ in
                return !WGAnonymousMode.voicePresets.isEmpty
            },
            label: { _ in
                let value = WGAnonymousMode.voice.value
                return WGAnonymousMode.allVoicePresets().first(where: { $0.id == value })?.title()
            }
        ))
    }
}
