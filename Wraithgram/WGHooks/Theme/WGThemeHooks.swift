// Compiled into TelegramPresentationData (filegroup //Wraithgram/WGHooks:TelegramPresentationDataHookSources).
// One chain of PresentationData transformers instead of edits all over the theme code:
// AMOLED, bubbles, separators, checkmarks… are applied to the PresentationData the app
// publishes. Cells keep reading the theme as upstream does; a change of a feature's appearance
// settings calls `WGThemeHooks.invalidate()` once (on slider release), which re-emits the
// PresentationData and re-lays out the screens — no notification fan-out.

import Foundation
import UIKit
import SwiftSignalKit
import WGCore

public struct WGThemeContext {
    /// The PresentationData for the very first frame (`currentPresentationDataAndSettings`).
    public let isInitial: Bool
}

public enum WGThemeHooks {
    /// Transformer chain over every PresentationData the app publishes. Must be fast and must
    /// return the same object when nothing applies. To force a re-layout while only a
    /// feature's own snapshot changed, return a PresentationData with a new theme instance.
    public static let presentationData = WGHookPoint<(PresentationData, WGThemeContext) -> PresentationData>("theme.presentationData")

    /// Re-emits the app's PresentationData through the chain. Call after a feature's appearance
    /// settings changed (never on every slider tick).
    public static func invalidate() {
        let value = wgThemeRevisionCounter.modify { $0 &+ 1 }
        wgThemeRevisionPromise.set(value)
    }

    /// For screens that replace the app's theme with their own (a chat's theme, a gift theme, a
    /// preview of the other appearance): runs that PresentationData through the chain too. A theme
    /// that already came out of the chain is returned unchanged, so calling it on the app's own
    /// PresentationData is harmless.
    public static func transformSubstitutedPresentationData(_ presentationData: PresentationData) -> PresentationData {
        if WGThemeHooks.presentationData.isEmpty || wgIsChainTheme(presentationData.theme) {
            return presentationData
        }
        return wgTransformPresentationData(presentationData, isInitial: false)
    }
}

/// The shape of a message bubble image (`messageBubbleImage`): radii and which neighbours it
/// merges with (`.extracted` draws no tail).
public struct WGBubbleShape {
    public var maxCornerRadius: CGFloat
    public var minCornerRadius: CGFloat
    public var neighbors: MessageBubbleImageNeighbors
    public let incoming: Bool
    /// nil = upstream (the tail follows `neighbors`); `false` = no tail, the corners stay as the
    /// neighbours make them.
    public var drawsTail: Bool?
}

public extension WGThemeHooks {
    /// Transformer of bubble shapes (bubble editor: radii, tails). Images are cached per theme:
    /// after a change call `invalidate()` and return a new theme instance from `presentationData`.
    static let bubbleShape = WGHookPoint<(inout WGBubbleShape) -> Void>("theme.bubbleShape")
}

func wgBubbleShape(maxCornerRadius: CGFloat, minCornerRadius: CGFloat, incoming: Bool, neighbors: MessageBubbleImageNeighbors) -> (CGFloat, CGFloat, MessageBubbleImageNeighbors, Bool?) {
    if WGThemeHooks.bubbleShape.isEmpty {
        return (maxCornerRadius, minCornerRadius, neighbors, nil)
    }
    var shape = WGBubbleShape(maxCornerRadius: maxCornerRadius, minCornerRadius: minCornerRadius, neighbors: neighbors, incoming: incoming, drawsTail: nil)
    for handler in WGThemeHooks.bubbleShape.handlers {
        handler(&shape)
    }
    return (shape.maxCornerRadius, shape.minCornerRadius, shape.neighbors, shape.drawsTail)
}

/// Whether a bubble that has a tail in Telegram (no neighbours below) keeps it. Media bubbles cut
/// their own tail into the image corners (`ImageCorner.Tail`) and ask the same features as the
/// bubble images, so «Без хвостиков» also reaches a photo without a caption.
public func wgBubbleDrawsTail(incoming: Bool) -> Bool {
    if WGThemeHooks.bubbleShape.isEmpty {
        return true
    }
    let (_, _, _, drawsTail) = wgBubbleShape(maxCornerRadius: 16.0, minCornerRadius: 8.0, incoming: incoming, neighbors: .none)
    return drawsTail ?? true
}

private let wgThemeRevisionCounter = Atomic<Int>(value: 0)
private let wgThemeRevisionPromise = ValuePromise<Int>(0, ignoreRepeated: true)

func wgTransformPresentationData(_ presentationData: PresentationData, isInitial: Bool) -> PresentationData {
    if WGThemeHooks.presentationData.isEmpty {
        return presentationData
    }
    let context = WGThemeContext(isInitial: isInitial)
    var result = presentationData
    for handler in WGThemeHooks.presentationData.handlers {
        result = handler(result, context)
    }
    wgNoteChainTheme(result.theme)
    return result
}

// Themes that came out of the chain (held weakly): a screen that substitutes its own theme asks
// the chain only for themes it has not seen, so a theme is never transformed twice.
private final class WGWeakTheme {
    weak var value: PresentationTheme?

    init(_ value: PresentationTheme) {
        self.value = value
    }
}

private let wgChainThemesLock = NSLock()
private var wgChainThemes: [ObjectIdentifier: WGWeakTheme] = [:]

private func wgNoteChainTheme(_ theme: PresentationTheme) {
    wgChainThemesLock.lock()
    if wgChainThemes.count > 64 {
        wgChainThemes = wgChainThemes.filter { $0.value.value != nil }
    }
    wgChainThemes[ObjectIdentifier(theme)] = WGWeakTheme(theme)
    wgChainThemesLock.unlock()
}

private func wgIsChainTheme(_ theme: PresentationTheme) -> Bool {
    wgChainThemesLock.lock()
    defer {
        wgChainThemesLock.unlock()
    }
    return wgChainThemes[ObjectIdentifier(theme)]?.value === theme
}

/// Re-emits `signal`'s latest value on `WGThemeHooks.invalidate()`.
func wgWithThemeRevision<T>(_ signal: Signal<T, NoError>) -> Signal<T, NoError> {
    if WGThemeHooks.presentationData.isEmpty {
        return signal
    }
    return combineLatest(signal, wgThemeRevisionPromise.get())
    |> map { value, _ -> T in
        return value
    }
}
