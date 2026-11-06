import Foundation
import UIKit
import Display
import AppBundle
import TelegramPresentationData

// Owner's decision (2026-10-21): line template glyphs, 24 pt in a 26 pt zone, no tiles, no glow,
// brightness 83 % on the mock-up scale. Every menu glyph is tinted by this one function.
public func wgMenuIconColor(theme: PresentationTheme) -> UIColor {
    if theme.overallDarkAppearance {
        return UIColor(rgb: 0xE3E3E8)
    } else {
        return UIColor(rgb: 0xB6B6BD)
    }
}

/// Name of the ghost glyph in this module's asset catalog (`Assets/WGSettingsUI.xcassets`).
let wgGhostGlyphName = "WGSettingsUI/Ghost"

/// The root header's ghost: the app icon's ghost cut out whole (body, eyes, dust) as a 64 pt
/// template, so it stays sharp at that size (the row glyph is a 24 pt raster).
private let wgHeaderGhostName = "WGSettingsUI/HeaderGhost"

/// Side of the root header's ghost.
let wgSettingsHeaderMarkSide: CGFloat = 64.0

private let wgMenuIconSize = CGSize(width: 24.0, height: 24.0)

/// Main-thread cache: menu screens are rebuilt on every settings change, and a fresh UIImage per
/// rebuild would make ItemList re-apply every icon (it compares images by identity).
private final class WGMenuIconCache {
    static let shared = WGMenuIconCache()

    private var images: [String: UIImage] = [:]
    // The tile is asked for by Telegram's Settings, which may build its rows off the main thread:
    // static lets are initialized once and thread-safely.
    private static let tile: UIImage? = wgRenderSettingsTile()

    func image(for icon: WGMenuIcon, color: UIColor) -> UIImage? {
        assert(Thread.isMainThread)
        let key = "\(icon)|\(color.wgHexKey)"
        if let image = self.images[key] {
            return image
        }
        guard let image = wgRenderMenuIcon(icon, color: color) else {
            return nil
        }
        self.images[key] = image
        return image
    }

    func settingsTile() -> UIImage? {
        return WGMenuIconCache.tile
    }

    func mark(color: UIColor) -> UIImage? {
        assert(Thread.isMainThread)
        let key = "headerMark|\(color.wgHexKey)"
        if let image = self.images[key] {
            return image
        }
        guard let image = wgRenderHeaderMark(color: color) else {
            return nil
        }
        self.images[key] = image
        return image
    }
}

private extension UIColor {
    var wgHexKey: String {
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 0.0
        self.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "%02x%02x%02x%02x", Int(red * 255.0), Int(green * 255.0), Int(blue * 255.0), Int(alpha * 255.0))
    }
}

/// Glyph for a menu row, 24 pt, tinted with `wgMenuIconColor(theme:)`.
public func wgMenuIcon(_ icon: WGMenuIcon, theme: PresentationTheme) -> UIImage? {
    return WGMenuIconCache.shared.image(for: icon, color: wgMenuIconColor(theme: theme))
}

/// Same glyph tinted with an arbitrary color (accent marks in previews).
func wgMenuIcon(_ icon: WGMenuIcon, color: UIColor) -> UIImage? {
    return WGMenuIconCache.shared.image(for: icon, color: color)
}

/// The «Wraithgram» row in Telegram's Settings: the standard 30 pt tile, like its neighbours.
public func wgSettingsTileIcon() -> UIImage? {
    return WGMenuIconCache.shared.settingsTile()
}

/// The mark in the root header: the plain ghost (owner, 2026-10-27: no tile, gradient or corners),
/// 64 pt, in the theme's primary text color so it reads on light and dark backgrounds.
func wgSettingsHeaderMark(theme: PresentationTheme) -> UIImage? {
    return WGMenuIconCache.shared.mark(color: theme.list.itemPrimaryTextColor)
}

private let wgBrandColors: [UIColor] = [UIColor(rgb: 0x5B5B66), UIColor(rgb: 0x1F1F24)]

private func wgRenderMenuIcon(_ icon: WGMenuIcon, color: UIColor) -> UIImage? {
    let tinted: UIImage?
    switch icon {
    case let .bundle(name):
        tinted = generateTintedImage(image: UIImage(bundleImageName: name), color: color)
    case let .system(name):
        let configuration = UIImage.SymbolConfiguration(pointSize: 18.0, weight: .regular)
        tinted = UIImage(systemName: name, withConfiguration: configuration)?.withTintColor(color, renderingMode: .alwaysOriginal)
    case .ghost:
        if let image = UIImage(bundleImageName: wgGhostGlyphName) {
            tinted = generateTintedImage(image: image, color: color)
        } else {
            tinted = wgVectorGhost(size: wgMenuIconSize, color: color)
        }
    }
    guard let tinted else {
        return nil
    }
    if tinted.size == wgMenuIconSize {
        return tinted
    }
    // Aspect-fit into the 24 pt canvas so every row's glyph sits on the same grid.
    let scale = min(wgMenuIconSize.width / max(1.0, tinted.size.width), wgMenuIconSize.height / max(1.0, tinted.size.height), 1.0)
    let fittedSize = CGSize(width: floor(tinted.size.width * scale), height: floor(tinted.size.height * scale))
    let renderer = UIGraphicsImageRenderer(size: wgMenuIconSize)
    return renderer.image { _ in
        tinted.draw(in: CGRect(origin: CGPoint(x: floor((wgMenuIconSize.width - fittedSize.width) / 2.0), y: floor((wgMenuIconSize.height - fittedSize.height) / 2.0)), size: fittedSize))
    }
}

/// Name of the «Wraithgram» row's tile in this module's asset catalog: the old Wraithgram's picture
/// (dark square, white ghost), drawn whole — not a glyph on a generated background.
private let wgSettingsTileName = "WGSettingsUI/SettingsTile"

private func wgRenderHeaderMark(color: UIColor) -> UIImage? {
    let side = wgSettingsHeaderMarkSide
    if let image = UIImage(bundleImageName: wgHeaderGhostName) {
        return generateTintedImage(image: image, color: color)
    }
    // The asset catalog is missing: the row glyph, scaled up (soft, but never a blank header).
    let glyph = UIImage(bundleImageName: wgGhostGlyphName).flatMap { generateTintedImage(image: $0, color: color) } ?? wgVectorGhost(size: CGSize(width: side, height: side), color: color)
    guard let glyph else {
        return nil
    }
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
    return renderer.image { _ in
        glyph.draw(in: CGRect(x: 0.0, y: 0.0, width: side, height: side))
    }
}

private func wgRenderSettingsTile() -> UIImage? {
    // As the old Wraithgram drew it (owner, 2026-10-27): the full picture through Telegram's own tile
    // renderer for app icons in Settings (30 pt, corner radius 8, the same gloss as its neighbours).
    if let image = UIImage(bundleImageName: wgSettingsTileName) {
        return renderAttachAppIcon(iconImage: image)
    }
    return wgRenderBrandMark(size: 30.0, cornerRadius: 8.0, glyphSize: 19.0)
}

private func wgRenderBrandMark(size: CGFloat, cornerRadius: CGFloat, glyphSize: CGFloat) -> UIImage? {
    let glyph = UIImage(bundleImageName: wgGhostGlyphName).flatMap { generateTintedImage(image: $0, color: .white) } ?? wgVectorGhost(size: CGSize(width: glyphSize, height: glyphSize), color: .white)
    let canvas = CGSize(width: size, height: size)
    let renderer = UIGraphicsImageRenderer(size: canvas)
    return renderer.image { rendererContext in
        let context = rendererContext.cgContext
        let bounds = CGRect(origin: CGPoint(), size: canvas)
        context.addPath(UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath)
        context.clip()

        let colors = wgBrandColors.map(\.cgColor) as CFArray
        var locations: [CGFloat] = [0.0, 1.0]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: &locations) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: size, y: size), options: [])
        }
        if let glyph {
            let glyphRect = CGRect(x: floor((size - glyphSize) / 2.0), y: floor((size - glyphSize) / 2.0), width: glyphSize, height: glyphSize)
            glyph.draw(in: glyphRect)
        }
    }
}

/// Fallback when the asset catalog of this module is not linked into the app yet: a simple ghost
/// (round head, wavy hem, two eyes) so the entry row is never blank.
private func wgVectorGhost(size: CGSize, color: UIColor) -> UIImage? {
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { rendererContext in
        let context = rendererContext.cgContext
        let width = size.width * 0.72
        let height = size.height * 0.84
        let originX = (size.width - width) / 2.0
        let originY = (size.height - height) / 2.0
        let radius = width / 2.0

        let body = UIBezierPath()
        body.move(to: CGPoint(x: originX, y: originY + radius))
        body.addArc(withCenter: CGPoint(x: originX + radius, y: originY + radius), radius: radius, startAngle: CGFloat.pi, endAngle: 0.0, clockwise: true)
        body.addLine(to: CGPoint(x: originX + width, y: originY + height))
        let waves = 3
        let waveWidth = width / CGFloat(waves)
        for i in 0 ..< waves {
            let startX = originX + width - CGFloat(i) * waveWidth
            let endX = startX - waveWidth
            body.addQuadCurve(to: CGPoint(x: endX, y: originY + height), controlPoint: CGPoint(x: (startX + endX) / 2.0, y: originY + height - waveWidth * 0.7))
        }
        body.close()

        let eyeRadius = width * 0.1
        let eyeY = originY + radius * 0.95
        body.append(UIBezierPath(ovalIn: CGRect(x: originX + width * 0.32 - eyeRadius, y: eyeY - eyeRadius, width: eyeRadius * 2.0, height: eyeRadius * 2.4)))
        body.append(UIBezierPath(ovalIn: CGRect(x: originX + width * 0.68 - eyeRadius, y: eyeY - eyeRadius, width: eyeRadius * 2.0, height: eyeRadius * 2.4)))
        body.usesEvenOddFillRule = true

        context.setFillColor(color.cgColor)
        context.addPath(body.cgPath)
        context.fillPath(using: .evenOdd)
    }
}
