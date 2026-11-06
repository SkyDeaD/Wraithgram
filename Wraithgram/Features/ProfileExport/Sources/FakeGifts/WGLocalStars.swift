import Foundation
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import PromptUI
import WGCore
import WGSettingsUI

// More › Fake gifts › Stars: «Локальные звёзды» — the Stars balance this device shows instead of the
// real one (`WGStarsHooks.displayedBalance` in TelegramCore; TON is not touched). Only the number on
// screen changes: what Stars pay for is still checked by the server against the real balance.
// Restored 2026-11-01 at the owner's word: the old client had it in «Кастомизация › Сообщения»
// (`WG.fontCustomization.localStarsBalance`), the remake had lost it.

enum WGLocalStars {
    /// nil = the real balance.
    static let balance = WGSetting<Int64?>("fakeGifts.localStars", default: nil)

    static let section = WGMenuSectionID("more.fakeGifts.stars")

    private static var settingDisposable: Disposable?

    static func declare() {
        let _ = WGLocalStars.balance
    }

    /// Main thread, before `WGHookRegistry.freeze()`.
    static func register() {
        WGStarsHooks.displayedBalance.register({ _ in
            return WGLocalStars.balance.value.map { StarsAmount(value: $0, nanos: 0) }
        })
        // A balance already on screen follows the change at once.
        WGLocalStars.settingDisposable = (WGLocalStars.balance.signal
        |> distinctUntilChanged).start(next: { _ in
            WGStarsHooks.invalidate()
        })

        WGMigrations.registerGlobal(id: "fakeGifts.localStars.v1") { legacy in
            let key = "WG.fontCustomization.localStarsBalance"
            if let number = legacy.object(key) as? NSNumber {
                WGLocalStars.balance.set(max(0, number.int64Value))
            }
            legacy.removeLegacyKey(key)
        }

        WGLocalStars.registerMenu()
    }

    private static func registerMenu() {
        WGMenuRegistry.register(section: WGMenuSectionDescriptor(
            id: WGLocalStars.section,
            screen: .tab(.moreFakeGifts),
            order: 300,
            header: { WGStrings.FakeGifts.Stars.header },
            footer: { _ in WGStrings.FakeGifts.Stars.footer }
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "fakeGifts.localStars",
            section: WGLocalStars.section,
            order: 100,
            title: { WGStrings.FakeGifts.Stars.title },
            subtitle: { WGStrings.FakeGifts.Stars.info },
            icon: .bundle("Chat/Context Menu/Stars"),
            kind: .action({ context in
                WGLocalStars.edit(menuContext: context)
            }),
            searchKeywords: { [WGStrings.FakeGifts.Stars.keywords] },
            label: { context in
                guard let value = WGLocalStars.balance.value else {
                    return nil
                }
                return WGLocalStars.formatted(value, groupingSeparator: context.presentationData.dateTimeFormat.groupingSeparator)
            }
        ))
        WGMenuRegistry.register(WGMenuRow(
            id: "fakeGifts.localStars.reset",
            section: WGLocalStars.section,
            order: 200,
            title: { WGStrings.FakeGifts.Stars.reset },
            kind: .action({ _ in
                WGLocalStars.balance.set(nil)
            }),
            isVisible: { _ in WGLocalStars.balance.value != nil },
            isDestructive: true
        ))
    }

    private static func edit(menuContext: WGMenuContext) {
        let current = WGLocalStars.balance.value.map { "\($0)" }
        menuContext.present(promptController(context: menuContext.context, text: WGStrings.FakeGifts.Stars.title, subtitle: WGStrings.FakeGifts.Stars.promptText, value: current, placeholder: WGStrings.FakeGifts.Stars.placeholder, characterLimit: 32, apply: { value in
            guard let value else {
                return
            }
            WGLocalStars.balance.set(WGLocalStars.parse(value))
        }))
    }

    /// The digits of `text` as a balance, at most `Int64.max`; nil when there are none (the real
    /// balance again).
    static func parse(_ text: String) -> Int64? {
        var result: Int64?
        for scalar in text.unicodeScalars {
            guard scalar.value >= 48 && scalar.value <= 57 else {
                continue
            }
            let digit = Int64(scalar.value - 48)
            let value = result ?? 0
            if value > (Int64.max - digit) / 10 {
                return Int64.max
            }
            result = value * 10 + digit
        }
        return result
    }

    static func formatted(_ value: Int64, groupingSeparator: String) -> String {
        let digits = String(value)
        var result = ""
        for (index, character) in digits.enumerated() {
            if index > 0 && (digits.count - index) % 3 == 0 {
                result += groupingSeparator
            }
            result.append(character)
        }
        return result
    }
}
