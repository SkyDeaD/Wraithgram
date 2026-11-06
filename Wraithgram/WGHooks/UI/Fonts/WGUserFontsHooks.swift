// The fonts the user added in «Оформление» › «Шрифт» (W2-4, `WGCustomFonts`), for the features that
// draw text in a font of the user's choice — the island badge studio (W2-5). WGAppearance answers.

import Foundation
import WGCore

/// A font file the user added: the family it declares and where the file is.
public struct WGUserFont: Equatable {
    public let familyName: String
    public let fileURL: URL

    public init(familyName: String, fileURL: URL) {
        self.familyName = familyName
        self.fileURL = fileURL
    }
}

public enum WGUserFontsHooks {
    /// Provider: the fonts the user added, in the order added. The files are not registered with
    /// CoreText (only the chosen app font is, at launch): a feature registers what it draws with.
    /// Main thread; answer from memory.
    public static let fonts = WGHookPoint<() -> [WGUserFont]>("fonts.userFonts")

    public static func userFonts() -> [WGUserFont] {
        var result: [WGUserFont] = []
        for handler in WGUserFontsHooks.fonts.handlers {
            result.append(contentsOf: handler())
        }
        return result
    }
}
