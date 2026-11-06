import Foundation
import UIKit
import CoreText
import SwiftSignalKit
import WGCore
import WGHooks
import WGAppearanceSettings

/// A font the user added from Files (owner, 2026-10-27: «в выбор шрифтов добавить кастомный, чтобы
/// можно было заливать»). The file is copied into the app's container and registered for this
/// process only (CTFontManager, `.process` scope) at launch: nothing is installed system-wide and
/// nothing leaves the device.
struct WGCustomFont: Equatable {
    /// File name inside `WGCustomFonts.directory`.
    let fileName: String
    /// The family the file declares: what the menu shows and what CoreText resolves faces from.
    let familyName: String
}

enum WGCustomFontImportResult {
    case added(WGCustomFont)
    case notAFont
    case tooMany
}

enum WGCustomFonts {
    /// `appearance.font.family` of a custom font: the prefix and the file name.
    static let valuePrefix = "custom:"
    static let maximumCount = 10

    private static let queue = Queue(name: "org.wraithgram.appearance.fonts", qos: .utility)
    private static let fileExtensions: Set<String> = ["ttf", "otf", "ttc"]

    static var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        // Not ".../fonts": the font.v2 migration deletes that directory of an earlier build.
        return base.appendingPathComponent("wraithgram/appearance/userFonts", isDirectory: true)
    }

    /// The fonts in the order they were added (an in-memory setting read: the menu asks per row).
    static var fonts: [WGCustomFont] {
        return WGAppearanceSettings.customFonts.value.compactMap { entry in
            let parts = entry.components(separatedBy: "\t")
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
                return nil
            }
            return WGCustomFont(fileName: parts[0], familyName: parts[1])
        }
    }

    static func settingValue(_ font: WGCustomFont) -> String {
        return WGCustomFonts.valuePrefix + font.fileName
    }

    static func isCustomValue(_ value: String) -> Bool {
        return value.hasPrefix(WGCustomFonts.valuePrefix)
    }

    /// The font a stored `appearance.font.family` names, if it is a custom one still in the list.
    static func font(forSettingValue value: String) -> WGCustomFont? {
        guard WGCustomFonts.isCustomValue(value) else {
            return nil
        }
        let fileName = String(value.dropFirst(WGCustomFonts.valuePrefix.count))
        return WGCustomFonts.fonts.first(where: { $0.fileName == fileName })
    }

    /// The fonts the user added, for the other features that draw in them (WGUserFontsHooks: the island
    /// badge studio).
    static func registerProvider() {
        WGUserFontsHooks.fonts.register({
            return WGCustomFonts.fonts.compactMap { font -> WGUserFont? in
                guard let url = WGCustomFonts.fileURL(font) else {
                    return nil
                }
                return WGUserFont(familyName: font.familyName, fileURL: url)
            }
        })
    }

    private static func fileURL(_ font: WGCustomFont) -> URL? {
        return WGCustomFonts.directory?.appendingPathComponent(font.fileName)
    }

    // MARK: Import and removal (main thread; the file work runs on the fonts queue)

    /// Checks that CoreText reads the picked file as a font, copies it, adds it to the list and makes
    /// it the app font (applied after a restart, like every font).
    static func importFont(at sourceURL: URL, completion: @escaping (WGCustomFontImportResult) -> Void) {
        if WGCustomFonts.fonts.count >= WGCustomFonts.maximumCount {
            completion(.tooMany)
            return
        }
        WGCustomFonts.queue.async {
            let result = WGCustomFonts.copyFont(at: sourceURL)
            Queue.mainQueue().async {
                guard let font = result else {
                    completion(.notAFont)
                    return
                }
                var entries = WGAppearanceSettings.customFonts.value
                entries.append("\(font.fileName)\t\(font.familyName)")
                WGAppearanceSettings.customFonts.set(entries)
                WGAppearanceSettings.fontFamily.set(WGCustomFonts.settingValue(font))
                completion(.added(font))
            }
        }
    }

    private static func copyFont(at sourceURL: URL) -> WGCustomFont? {
        guard let directory = WGCustomFonts.directory else {
            return nil
        }
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(sourceURL as CFURL) as? [CTFontDescriptor], let first = descriptors.first else {
            return nil
        }
        guard let familyName = CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String, !familyName.isEmpty else {
            return nil
        }
        var fileExtension = sourceURL.pathExtension.lowercased()
        if !WGCustomFonts.fileExtensions.contains(fileExtension) {
            fileExtension = descriptors.count > 1 ? "ttc" : "ttf"
        }
        let fileName = "font-\(UInt32.random(in: 0 ... UInt32.max)).\(fileExtension)"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: directory.appendingPathComponent(fileName))
        } catch {
            WGLog.warning("appearance", "custom font copy failed")
            return nil
        }
        return WGCustomFont(fileName: fileName, familyName: familyName.replacingOccurrences(of: "\t", with: " "))
    }

    /// Drops the font from the list; the app font falls back to the system one if it was chosen. The
    /// file itself is deleted at the next launch (`cleanUp`): the running app may still draw with it.
    static func remove(_ font: WGCustomFont) {
        if WGAppearanceSettings.fontFamily.value == WGCustomFonts.settingValue(font) {
            WGAppearanceSettings.fontFamily.reset()
        }
        let entries = WGAppearanceSettings.customFonts.value.filter { !$0.hasPrefix(font.fileName + "\t") }
        WGAppearanceSettings.customFonts.set(entries)
    }

    // MARK: Launch

    /// Registers the chosen font's file for this process. Nil when the file is gone or unreadable.
    static func registerForLaunch(_ font: WGCustomFont) -> String? {
        guard let url = WGCustomFonts.fileURL(font), FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            // Already registered by this process is fine; anything else shows up as a missing family.
            error?.release()
        }
        if UIFont.fontNames(forFamilyName: font.familyName).isEmpty {
            return nil
        }
        return font.familyName
    }

    /// Deletes files no longer in the list (removed fonts), off the main thread, once per launch.
    static func cleanUp() {
        let kept = Set(WGCustomFonts.fonts.map(\.fileName))
        WGCustomFonts.queue.async {
            guard let directory = WGCustomFonts.directory, let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
                return
            }
            for name in names where !kept.contains(name) {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
        }
    }

    // MARK: Menu (main thread)

    private static var menuFonts: [String: UIFont] = [:]

    /// The font's regular face for the menu sample, read straight from its file (not registered:
    /// a font added in this session is drawn before any restart). Cached per file.
    static func menuFont(_ font: WGCustomFont, size: CGFloat) -> UIFont? {
        let key = "\(font.fileName)_\(size)"
        if let cached = WGCustomFonts.menuFonts[key] {
            return cached
        }
        guard let url = WGCustomFonts.fileURL(font), let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], let first = descriptors.first else {
            return nil
        }
        let result = CTFontCreateWithFontDescriptor(first, size, nil) as UIFont
        WGCustomFonts.menuFonts[key] = result
        return result
    }
}
