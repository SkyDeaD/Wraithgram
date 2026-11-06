import Foundation
import UIKit
import ObjectiveC
import PhotosUI
import UniformTypeIdentifiers
import Display
import WGCore
import WGSettingsUI
import WGAppearanceSettings

/// The system color picker for one color setting. The value is written once, when the picker
/// closes — not on every move of the finger (the old picker posted a settings notification per
/// frame, each rebuilding every chat cell) — and only if a color was picked in it: the picker
/// starts on the current or the theme's color, and closing it untouched must leave «Automatic» as it
/// is.
enum WGColorPicker {
    private static var key: UInt8 = 0

    static func present(context: WGMenuContext, setting: WGSetting<String>, fallback: UIColor) {
        let picker = UIColorPickerViewController()
        picker.supportsAlpha = false
        if let rgb = wgAppearanceParseColor(setting.value) {
            picker.selectedColor = UIColor(rgb: rgb)
        } else {
            picker.selectedColor = fallback
        }
        let delegate = WGColorPickerDelegate(setting: setting)
        picker.delegate = delegate
        objc_setAssociatedObject(picker, &WGColorPicker.key, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        context.presentNative(picker)
    }
}

private final class WGColorPickerDelegate: NSObject, UIColorPickerViewControllerDelegate {
    private let setting: WGSetting<String>
    private var didPick = false

    init(setting: WGSetting<String>) {
        self.setting = setting
        super.init()
    }

    func colorPickerViewController(_ viewController: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
        self.didPick = true
    }

    func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
        if !self.didPick {
            return
        }
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        guard viewController.selectedColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return
        }
        let r = UInt32(max(0.0, min(1.0, red)) * 255.0)
        let g = UInt32(max(0.0, min(1.0, green)) * 255.0)
        let b = UInt32(max(0.0, min(1.0, blue)) * 255.0)
        self.setting.set(wgAppearanceColorString((r << 16) | (g << 8) | b))
    }
}

/// File and photo pickers for animated backgrounds. The delegates live as long as their picker
/// (associated object); the work after a pick runs off the main thread.
enum WGPickers {
    private static var key: UInt8 = 0

    static func pickBackground(context: WGMenuContext, kind: WGAnimatedBackgroundKind) {
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: WGStrings.Appearance.Background.fromPhotos, style: .default, handler: { _ in
            WGPickers.pickBackgroundFromPhotos(context: context, kind: kind)
        }))
        sheet.addAction(UIAlertAction(title: WGStrings.Appearance.Background.fromFiles, style: .default, handler: { _ in
            WGPickers.pickBackgroundFromFiles(context: context, kind: kind)
        }))
        sheet.addAction(UIAlertAction(title: context.presentationData.strings.Common_Cancel, style: .cancel, handler: nil))
        context.presentNative(sheet)
    }

    private static func startImport(_ url: URL, context: WGMenuContext, kind: WGAnimatedBackgroundKind, cleanup: (() -> Void)?) {
        context.presentToast(WGStrings.Appearance.Background.preparing)
        WGAnimatedBackgrounds.importFile(at: url, kind: kind, completion: { success in
            cleanup?()
            context.presentToast(success ? WGStrings.Appearance.Background.ready : WGStrings.Appearance.Background.failed)
        })
    }

    private static func pickBackgroundFromFiles(context: WGMenuContext, kind: WGAnimatedBackgroundKind) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.gif, .movie, .mpeg4Movie, .quickTimeMovie], asCopy: true)
        picker.allowsMultipleSelection = false
        let delegate = WGDocumentPickerDelegate(pick: { url in
            WGPickers.startImport(url, context: context, kind: kind, cleanup: {
                try? FileManager.default.removeItem(at: url)
            })
        })
        picker.delegate = delegate
        objc_setAssociatedObject(picker, &WGPickers.key, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        context.presentNative(picker)
    }

    /// «Добавить шрифт…»: a font file from Files (owner 2026-10-27). The picked copy is temporary;
    /// WGCustomFonts copies it into the app's container.
    static func pickFont(context: WGMenuContext) {
        var types: [UTType] = [.font]
        for fileExtension in ["ttf", "otf", "ttc"] {
            if let type = UTType(filenameExtension: fileExtension), !types.contains(type) {
                types.append(type)
            }
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.allowsMultipleSelection = false
        let delegate = WGDocumentPickerDelegate(pick: { url in
            WGCustomFonts.importFont(at: url, completion: { result in
                try? FileManager.default.removeItem(at: url)
                switch result {
                case let .added(font):
                    context.presentToast(WGStrings.Appearance.Font.added(name: font.familyName))
                case .notAFont:
                    context.presentToast(WGStrings.Appearance.Font.notAFont)
                case .tooMany:
                    context.presentToast(WGStrings.Appearance.Font.tooMany)
                }
            })
        })
        picker.delegate = delegate
        objc_setAssociatedObject(picker, &WGPickers.key, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        context.presentNative(picker)
    }

    private static func pickBackgroundFromPhotos(context: WGMenuContext, kind: WGAnimatedBackgroundKind) {
        var configuration = PHPickerConfiguration()
        configuration.selectionLimit = 1
        configuration.filter = .any(of: [.videos, .images])
        let picker = PHPickerViewController(configuration: configuration)
        let delegate = WGPhotoPickerDelegate(pick: { url in
            WGPickers.startImport(url, context: context, kind: kind, cleanup: {
                try? FileManager.default.removeItem(at: url)
            })
        }, failed: {
            context.presentToast(WGStrings.Appearance.Background.failed)
        })
        picker.delegate = delegate
        objc_setAssociatedObject(picker, &WGPickers.key, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        context.presentNative(picker)
    }
}

private final class WGDocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let pick: (URL) -> Void

    init(pick: @escaping (URL) -> Void) {
        self.pick = pick
        super.init()
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first {
            self.pick(url)
        }
    }
}

/// Photos hands out GIFs as images: the GIF representation is asked for first, then a movie. The
/// provided file is temporary, so it is copied before the callback returns.
private final class WGPhotoPickerDelegate: NSObject, PHPickerViewControllerDelegate {
    private let pick: (URL) -> Void
    private let failed: () -> Void

    init(pick: @escaping (URL) -> Void, failed: @escaping () -> Void) {
        self.pick = pick
        self.failed = failed
        super.init()
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else {
            return
        }
        let typeIdentifier: String
        let fileExtension: String
        if provider.hasItemConformingToTypeIdentifier(UTType.gif.identifier) {
            typeIdentifier = UTType.gif.identifier
            fileExtension = "gif"
        } else if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            typeIdentifier = UTType.movie.identifier
            fileExtension = "mov"
        } else {
            self.failed()
            return
        }
        let pick = self.pick
        let failed = self.failed
        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
            guard let url else {
                DispatchQueue.main.async {
                    failed()
                }
                return
            }
            let copyURL = FileManager.default.temporaryDirectory.appendingPathComponent("wg-background-\(UInt32.random(in: 0 ... UInt32.max)).\(fileExtension)")
            do {
                try FileManager.default.copyItem(at: url, to: copyURL)
            } catch {
                DispatchQueue.main.async {
                    failed()
                }
                return
            }
            DispatchQueue.main.async {
                pick(copyURL)
            }
        }
    }
}
