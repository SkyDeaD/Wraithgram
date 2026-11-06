import Foundation

// When an account (a user or a bot) was created, as far as it can be known. All times are unix
// seconds, UTC. This file is the contract between the estimate (anchors + resolver) and the feature
// (evidence, cache, profile row): fields may be added, existing ones are not changed or removed.

/// A closed interval of time the account was created in.
public struct WGRegDateRange: Codable, Equatable {
    public var from: Int32
    public var to: Int32

    public init(from: Int32, to: Int32) {
        self.from = from
        self.to = to
    }
}

/// Where the answer came from; decides how the row is marked.
public enum WGRegDateSource: String, Codable {
    /// Telegram's own `peerSettings.registration_month` ("MM.YYYY"): not a guess.
    case telegram
    /// A remote service with Swiftgram's contract (`from` / `to` / `valid_until`).
    case remote
    /// Estimated by the account's ID from the built-in anchors, possibly narrowed by evidence.
    case estimate
}

/// The finest unit the range honestly supports for display.
public enum WGRegDatePrecision: Int, Codable, Comparable {
    case year = 0
    case month = 1
    case day = 2

    public static func < (lhs: WGRegDatePrecision, rhs: WGRegDatePrecision) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

public struct WGRegDateResult: Codable, Equatable {
    /// When the account was created, no wider than the data allows.
    public var range: WGRegDateRange
    /// The best single moment inside `range` (account age).
    public var point: Int32
    public var precision: WGRegDatePrecision
    public var source: WGRegDateSource
    /// Evidence from the device narrowed the range (e.g. «не позже» the oldest profile photo).
    public var isNarrowed: Bool
    /// `WGRegDateResolver.dataVersion` the result was computed with: an estimate is recomputed when
    /// the anchors change.
    public var dataVersion: Int

    public init(range: WGRegDateRange, point: Int32, precision: WGRegDatePrecision, source: WGRegDateSource, isNarrowed: Bool, dataVersion: Int) {
        self.range = range
        self.point = point
        self.precision = precision
        self.source = source
        self.isNarrowed = isNarrowed
        self.dataVersion = dataVersion
    }
}

/// What the device knows about an account besides its ID.
public struct WGRegDateEvidence: Equatable {
    public var userId: Int64
    /// `peerSettings.registration_month` exactly as Telegram sent it ("MM.YYYY"), when it did.
    public var telegramMonth: String?
    /// The account certainly existed at this moment: the earliest dated trace seen on the device
    /// (oldest profile photo, oldest message or membership, name / photo change date…). An upper bound.
    public var existedAt: Int32?
    /// The account certainly did not exist before this moment (a lower bound), when anything gives one.
    public var notBefore: Int32?
    /// The answer of a remote service, when one is configured or was migrated from the old client.
    public var remote: WGRegDateRange?

    public init(userId: Int64, telegramMonth: String? = nil, existedAt: Int32? = nil, notBefore: Int32? = nil, remote: WGRegDateRange? = nil) {
        self.userId = userId
        self.telegramMonth = telegramMonth
        self.existedAt = existedAt
        self.notBefore = notBefore
        self.remote = remote
    }
}
