import Foundation
import TelegramPresentationData
import TelegramStringFormatting
import WGCore

/// The texts of the row and of its explanation. Month names and dates are Telegram's own formatting
/// (`stringForMonth(strings:month:ofYear:)` is what the new-chat info card shows the registration
/// month with), so they follow Telegram's language like the rest of the profile; the rest is
/// Wraithgram's strings. Built at display time only.
struct WGRegDateRowTexts: Equatable {
    /// «≈ март 2016».
    let value: String
    /// «8 лет 7 мес.» on the right of the label.
    let age: String
    /// What a long press copies: «≈ март 2016 · 8 лет 7 мес.».
    let copy: String
}

enum WGRegDateText {
    static func row(_ snapshot: WGRegDateSnapshot, now: Int32, strings: PresentationStrings) -> WGRegDateRowTexts {
        let value = WGRegDateText.value(WGRegDateLayout.display(snapshot.result), strings: strings)
        let age = WGRegDateText.age(WGRegDateLayout.age(snapshot.result, now: now))
        return WGRegDateRowTexts(value: value, age: age, copy: "\(value) · \(age)")
    }

    static func value(_ display: WGRegDateDisplay, strings: PresentationStrings) -> String {
        switch display {
        case let .month(year, month, approximate):
            let text = WGRegDateText.month(year: year, month: month, strings: strings)
            return approximate ? WGStrings.RegDate.Profile.approximate(date: text) : text
        case let .day(timestamp, approximate):
            let text = stringForDate(timestamp: timestamp, strings: strings)
            return approximate ? WGStrings.RegDate.Profile.approximate(date: text) : text
        case let .year(year, approximate):
            let text = "\(year)"
            return approximate ? WGStrings.RegDate.Profile.approximate(date: text) : text
        case let .monthRange(fromYear, fromMonth, toYear, toMonth):
            return WGStrings.RegDate.Profile.range(from: WGRegDateText.month(year: fromYear, month: fromMonth, strings: strings), to: WGRegDateText.month(year: toYear, month: toMonth, strings: strings))
        case let .yearRange(from, to):
            return WGStrings.RegDate.Profile.range(from: "\(from)", to: "\(to)")
        }
    }

    /// «март 2016» — the upstream formatter (month 0…11, year since 1900).
    static func month(year: Int, month: Int, strings: PresentationStrings) -> String {
        return stringForMonth(strings: strings, month: Int32(max(1, min(12, month)) - 1), ofYear: Int32(year - 1900))
    }

    static func age(_ age: WGRegDateAge) -> String {
        let text: String
        if age.years == 0 && age.months == 0 {
            text = WGStrings.RegDate.Age.lessThanMonth
        } else if age.years > 0 && age.months > 0 && !age.yearsOnly {
            text = WGStrings.RegDate.Age.yearsMonths(years: WGStrings.RegDate.Age.years(count: age.years), months: WGStrings.RegDate.Age.months(count: age.months))
        } else if age.years > 0 {
            text = WGStrings.RegDate.Age.years(count: age.years)
        } else {
            text = WGStrings.RegDate.Age.months(count: age.months)
        }
        return age.approximate ? WGStrings.RegDate.Age.approximate(age: text) : text
    }
}
