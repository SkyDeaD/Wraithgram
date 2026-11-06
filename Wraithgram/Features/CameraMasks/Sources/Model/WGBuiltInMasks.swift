import Foundation
import WGCore

/// The masks that ship with the app. They are ordinary manifests rendered by the same engine as
/// catalog and own masks (one code path), and they never touch the disk or the network.
enum WGBuiltInMasks {
    static let ids: [String] = [
        "autoBlur", "pixelate", "heavyFaceBlur", "backgroundBlur",
        "colorNoir", "sepiaVintage", "chrome", "fade", "warmTone", "coldTone",
        "emojiFire", "emojiSkull", "emojiGhost", "emojiAlien", "emojiClown", "emojiRobot", "emojiCool"
    ]

    static func manifest(id: String) -> WGMaskManifest? {
        let effects: [WGMaskEffect]
        switch id {
        case "autoBlur":
            effects = [WGMaskEffect.filter("blur.gaussianFace", params: ["radius": .number(28.0)])]
        case "heavyFaceBlur":
            effects = [WGMaskEffect.filter("blur.gaussianFace", params: ["radius": .number(45.0)])]
        case "pixelate":
            effects = [WGMaskEffect.filter("blur.pixelFace", params: ["scale": .number(24.0)])]
        case "backgroundBlur":
            effects = [WGMaskEffect.filter("blur.background", params: ["radius": .number(18.0)])]
        case "colorNoir":
            effects = [WGMaskEffect(type: .colorFilter, preset: .noir)]
        case "sepiaVintage":
            effects = [WGMaskEffect(type: .colorFilter, preset: .sepia)]
        case "chrome":
            effects = [WGMaskEffect(type: .colorFilter, preset: .chrome)]
        case "fade":
            effects = [WGMaskEffect(type: .colorFilter, preset: .fade)]
        case "warmTone":
            effects = [WGMaskEffect(type: .colorFilter, preset: .warm)]
        case "coldTone":
            effects = [WGMaskEffect(type: .colorFilter, preset: .cold)]
        default:
            guard let emoji = WGBuiltInMasks.emoji(id: id) else {
                return nil
            }
            effects = [WGMaskEffect(type: .emojiHead, emoji: emoji)]
        }
        return WGMaskManifest(id: id, name: [:], effects: effects)
    }

    /// Glyph of the mask's chip.
    static func glyph(id: String) -> String {
        if let emoji = WGBuiltInMasks.emoji(id: id) {
            return emoji
        }
        switch id {
        case "autoBlur", "heavyFaceBlur":
            return "🌫"
        case "pixelate":
            return "🟪"
        case "backgroundBlur":
            return "🧍"
        case "colorNoir":
            return "⚫️"
        case "sepiaVintage":
            return "🟤"
        case "chrome":
            return "💿"
        case "fade":
            return "🌁"
        case "warmTone":
            return "🌅"
        case "coldTone":
            return "🧊"
        default:
            return "🎭"
        }
    }

    private static func emoji(id: String) -> String? {
        switch id {
        case "emojiFire":
            return "🔥"
        case "emojiSkull":
            return "💀"
        case "emojiGhost":
            return "👻"
        case "emojiAlien":
            return "👽"
        case "emojiClown":
            return "🤡"
        case "emojiRobot":
            return "🤖"
        case "emojiCool":
            return "😎"
        default:
            return nil
        }
    }

    static func title(id: String) -> String {
        switch id {
        case "autoBlur":
            return WGStrings.CameraMasks.BuiltIn.autoBlur
        case "heavyFaceBlur":
            return WGStrings.CameraMasks.BuiltIn.heavyFaceBlur
        case "pixelate":
            return WGStrings.CameraMasks.BuiltIn.pixelate
        case "backgroundBlur":
            return WGStrings.CameraMasks.BuiltIn.backgroundBlur
        case "colorNoir":
            return WGStrings.CameraMasks.BuiltIn.colorNoir
        case "sepiaVintage":
            return WGStrings.CameraMasks.BuiltIn.sepiaVintage
        case "chrome":
            return WGStrings.CameraMasks.BuiltIn.chrome
        case "fade":
            return WGStrings.CameraMasks.BuiltIn.fade
        case "warmTone":
            return WGStrings.CameraMasks.BuiltIn.warmTone
        case "coldTone":
            return WGStrings.CameraMasks.BuiltIn.coldTone
        case "emojiFire":
            return WGStrings.CameraMasks.BuiltIn.emojiFire
        case "emojiSkull":
            return WGStrings.CameraMasks.BuiltIn.emojiSkull
        case "emojiGhost":
            return WGStrings.CameraMasks.BuiltIn.emojiGhost
        case "emojiAlien":
            return WGStrings.CameraMasks.BuiltIn.emojiAlien
        case "emojiClown":
            return WGStrings.CameraMasks.BuiltIn.emojiClown
        case "emojiRobot":
            return WGStrings.CameraMasks.BuiltIn.emojiRobot
        case "emojiCool":
            return WGStrings.CameraMasks.BuiltIn.emojiCool
        default:
            return id
        }
    }
}
