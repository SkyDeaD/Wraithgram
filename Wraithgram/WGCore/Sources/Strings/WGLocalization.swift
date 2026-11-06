import Foundation
import SwiftSignalKit

/// A language Wraithgram has strings for, named in that language.
public struct WGLanguageInfo: Equatable {
    public let code: String
    public let nativeName: String
}

/// Runtime of the Wraithgram strings. Code reads strings only through the generated `WGStrings`
/// accessors; this class resolves the language and looks keys up.
///
/// Language: the manual override (`core.language`, "" follows Telegram) → Telegram's language as
/// the UI layer reports it → "en". A missing key falls back to English, never to Russian.
/// Region and variant suffixes are dropped (`ru-RU`, `ru-raw` → `ru`).
public final class WGLocalization {
    public static let shared = WGLocalization(dataSource: WGGeneratedStringsDataSource())

    /// "" follows Telegram's language. App Group scope, so the extensions use it too.
    public static let languageOverride = WGSetting<String>("core.language", default: "", scope: .appGroup, flags: [.extensions])

    static let fallbackLanguage = "en"

    private let dataSource: WGStringsDataSource
    private let lock = WGUnfairLock()
    private var telegramLanguageCode: String = ""
    /// The language a custom Telegram language pack is built on (`strings.baseLanguageCode`): a pack
    /// has its own code («jdflag»), and Wraithgram follows the base language then, not English.
    private var telegramBaseLanguageCode: String = ""
    private var resolvedLanguageCode: String = WGLocalization.fallbackLanguage
    private var tables: [String: [String: String]] = [:]
    private let languageCell = WGValueCell<String>(WGLocalization.fallbackLanguage)
    private var overrideDisposable: Disposable?

    init(dataSource: WGStringsDataSource) {
        self.dataSource = dataSource
        self.resolve()
        // Resolution is thread-safe, so the change is applied on the writer's thread at once.
        self.overrideDisposable = WGLocalization.languageOverride.signal.start(next: { [weak self] _ in
            self?.resolve()
        })
    }

    deinit {
        self.overrideDisposable?.dispose()
    }

    /// From the UI layer whenever Telegram's `PresentationData` changes
    /// (`presentationData.strings.primaryComponent.languageCode`).
    /// `baseCode` — `presentationData.strings.baseLanguageCode`, the base of a custom language pack.
    public func setTelegramLanguageCode(_ code: String, baseCode: String = "") {
        let normalized = WGLocalization.normalizedLanguageCode(code)
        let normalizedBase = WGLocalization.normalizedLanguageCode(baseCode)
        let changed = self.lock.withLock { () -> Bool in
            if self.telegramLanguageCode == normalized && self.telegramBaseLanguageCode == normalizedBase {
                return false
            }
            self.telegramLanguageCode = normalized
            self.telegramBaseLanguageCode = normalizedBase
            return true
        }
        if changed {
            self.resolve()
        }
    }

    /// Resolved: override ?? Telegram's ?? "en".
    public var languageCode: String {
        return self.lock.withLock {
            return self.resolvedLanguageCode
        }
    }

    /// The resolved language first, then every change.
    public var languageCodeSignal: Signal<String, NoError> {
        return self.languageCell.signal()
    }

    /// Languages with Wraithgram strings, each named in itself, for the language picker.
    public var availableLanguages: [WGLanguageInfo] {
        return self.dataSource.languages.map { code in
            let name = self.table(for: code)["core.languageNativeName"] ?? code
            return WGLanguageInfo(code: code, nativeName: name)
        }
    }

    // MARK: - Lookup (used by the generated accessors)

    func string(_ key: String) -> String {
        let language = self.languageCode
        if let value = self.table(for: language)[key] {
            return value
        }
        if language != WGLocalization.fallbackLanguage, let value = self.table(for: WGLocalization.fallbackLanguage)[key] {
            return value
        }
        WGLog.debug("strings", "missing string \(key)")
        return key
    }

    func format(_ key: String, _ arguments: [(String, String)]) -> String {
        return WGLocalization.substitute(self.string(key), arguments)
    }

    func plural(_ key: String, count: Int, _ arguments: [(String, String)]) -> String {
        let language = self.languageCode
        var template = WGLocalization.pluralTemplate(self.table(for: language), key: key, category: WGPluralRules.category(for: count, language: language))
        if template == nil && language != WGLocalization.fallbackLanguage {
            let fallback = WGLocalization.fallbackLanguage
            template = WGLocalization.pluralTemplate(self.table(for: fallback), key: key, category: WGPluralRules.category(for: count, language: fallback))
        }
        var allArguments = arguments
        allArguments.append(("count", String(count)))
        guard let resolvedTemplate = template else {
            WGLog.debug("strings", "missing plural \(key)")
            return key
        }
        return WGLocalization.substitute(resolvedTemplate, allArguments)
    }

    /// One table per language, parsed once from the generated JSON chunks.
    func table(for language: String) -> [String: String] {
        if let table = self.lock.withLock({ self.tables[language] }) {
            return table
        }
        var table: [String: String] = [:]
        for chunk in self.dataSource.chunks(for: language) ?? [] {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(chunk.utf8), options: [])) as? [String: String] else {
                assertionFailure("Damaged string table of \(language)")
                continue
            }
            table.merge(object, uniquingKeysWith: { current, _ in current })
        }
        return self.lock.withLock { () -> [String: String] in
            if let existing = self.tables[language] {
                return existing
            }
            self.tables[language] = table
            return table
        }
    }

    // MARK: - Pure helpers

    static func normalizedLanguageCode(_ code: String) -> String {
        let lowercased = code.lowercased()
        if let separator = lowercased.firstIndex(where: { $0 == "-" || $0 == "_" }) {
            return String(lowercased[lowercased.startIndex ..< separator])
        }
        return lowercased
    }

    /// Named substitution: `{name}` → value, `{{` / `}}` → literal braces. Values are inserted as
    /// is and never scanned again; nothing goes through `String(format:)`.
    static func substitute(_ template: String, _ arguments: [(String, String)]) -> String {
        if !template.contains("{") && !template.contains("}") {
            return template
        }
        var result = ""
        var index = template.startIndex
        while index < template.endIndex {
            let character = template[index]
            let next = template.index(after: index)
            if character == "{" {
                if next < template.endIndex && template[next] == "{" {
                    result.append("{")
                    index = template.index(after: next)
                    continue
                }
                if let close = template[next...].firstIndex(of: "}") {
                    let name = String(template[next ..< close])
                    if let argument = arguments.first(where: { $0.0 == name }) {
                        result.append(argument.1)
                        index = template.index(after: close)
                        continue
                    }
                }
            } else if character == "}" {
                if next < template.endIndex && template[next] == "}" {
                    result.append("}")
                    index = template.index(after: next)
                    continue
                }
            }
            result.append(character)
            index = next
        }
        return result
    }

    static func pluralTemplate(_ table: [String: String], key: String, category: WGPluralCategory) -> String? {
        if let value = table["\(key)#\(category.rawValue)"] {
            return value
        }
        if let value = table["\(key)#other"] {
            return value
        }
        for fallback in WGPluralCategory.allCases {
            if let value = table["\(key)#\(fallback.rawValue)"] {
                return value
            }
        }
        return nil
    }

    private func resolve() {
        let override = WGLocalization.normalizedLanguageCode(WGLocalization.languageOverride.value)
        let supported = self.dataSource.languages
        let code = self.lock.withLock { () -> String in
            let resolved: String
            if !override.isEmpty && supported.contains(override) {
                resolved = override
            } else if supported.contains(self.telegramLanguageCode) {
                resolved = self.telegramLanguageCode
            } else if supported.contains(self.telegramBaseLanguageCode) {
                resolved = self.telegramBaseLanguageCode
            } else {
                resolved = WGLocalization.fallbackLanguage
            }
            self.resolvedLanguageCode = resolved
            return resolved
        }
        self.languageCell.update(code)
    }
}

/// CLDR plural categories.
public enum WGPluralCategory: String, CaseIterable {
    case zero
    case one
    case two
    case few
    case many
    case other
}

/// CLDR cardinal rules for whole numbers in the languages Wraithgram ships.
enum WGPluralRules {
    static func category(for count: Int, language: String) -> WGPluralCategory {
        let n = count.magnitude
        switch language {
        case "ru", "uk", "be":
            let mod10 = n % 10
            let mod100 = n % 100
            if mod10 == 1 && mod100 != 11 {
                return .one
            }
            if mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) {
                return .few
            }
            return .many
        case "ar":
            if n == 0 {
                return .zero
            }
            if n == 1 {
                return .one
            }
            if n == 2 {
                return .two
            }
            let mod100 = n % 100
            if mod100 >= 3 && mod100 <= 10 {
                return .few
            }
            if mod100 >= 11 {
                return .many
            }
            return .other
        default:
            return n == 1 ? .one : .other
        }
    }
}

protocol WGStringsDataSource {
    var languages: [String] { get }
    func chunks(for language: String) -> [String]?
}

struct WGGeneratedStringsDataSource: WGStringsDataSource {
    var languages: [String] {
        return WGStringsData.languages
    }

    func chunks(for language: String) -> [String]? {
        return WGStringsData.chunks(for: language)
    }
}
