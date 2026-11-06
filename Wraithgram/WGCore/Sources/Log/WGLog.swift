import Foundation
import os

/// The one logger of Wraithgram code.
///
/// Release builds: `debug` and `info` do not even evaluate their message; warnings and errors go to
/// the unified system log with the message marked private. Nothing is written to files. Never log
/// user ids, phone numbers, peer ids or message text, in any build.
/// Debug builds: everything also goes to an in-memory ring buffer that is exported only by an
/// explicit user action (`exportRingBuffer`).
public enum WGLog {
    public static func debug(_ category: StaticString, _ message: @autoclosure () -> String) {
        #if DEBUG
        WGLogSink.shared.write(level: .debug, category: category, message: message())
        #endif
    }

    public static func info(_ category: StaticString, _ message: @autoclosure () -> String) {
        #if DEBUG
        WGLogSink.shared.write(level: .info, category: category, message: message())
        #endif
    }

    public static func warning(_ category: StaticString, _ message: @autoclosure () -> String) {
        WGLogSink.shared.write(level: .warning, category: category, message: message())
    }

    public static func error(_ category: StaticString, _ message: @autoclosure () -> String) {
        WGLogSink.shared.write(level: .error, category: category, message: message())
    }

    /// DEBUG only: the ring buffer as text, oldest line first. Release returns "".
    public static func exportRingBuffer() -> String {
        #if DEBUG
        return WGLogSink.shared.exportRingBuffer()
        #else
        return ""
        #endif
    }

    static func bootstrap(process: WGProcessKind) {
        WGLogSink.shared.setProcess(process)
    }
}

final class WGLogSink {
    enum Level: String {
        case debug = "D"
        case info = "I"
        case warning = "W"
        case error = "E"
    }

    static let shared = WGLogSink()
    static let ringCapacity = 2000

    private let lock = WGUnfairLock()
    private var loggers: [String: Logger] = [:]
    private var processTag: String = "app"
    private var ring: [String] = []
    private var ringNext: Int = 0

    private init() {
    }

    func setProcess(_ process: WGProcessKind) {
        self.lock.withLock {
            self.processTag = process.rawValue
        }
    }

    func write(level: Level, category: StaticString, message: String) {
        let categoryName = "\(category)"
        let logger = self.logger(category: categoryName)
        #if DEBUG
        switch level {
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .warning:
            logger.warning("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        }
        self.appendToRing(level: level, category: categoryName, message: message)
        #else
        switch level {
        case .debug, .info:
            break
        case .warning:
            logger.warning("\(message, privacy: .private)")
        case .error:
            logger.error("\(message, privacy: .private)")
        }
        #endif
    }

    private func logger(category: String) -> Logger {
        return self.lock.withLock { () -> Logger in
            if let logger = self.loggers[category] {
                return logger
            }
            let logger = Logger(subsystem: "org.wraithgram", category: category)
            self.loggers[category] = logger
            return logger
        }
    }

    #if DEBUG
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private func appendToRing(level: Level, category: String, message: String) {
        let time = WGLogSink.timeFormatter.string(from: Date())
        self.lock.withLock {
            let line = "\(time) \(self.processTag) \(level.rawValue) [\(category)] \(message)"
            if self.ring.count < WGLogSink.ringCapacity {
                self.ring.append(line)
            } else {
                self.ring[self.ringNext] = line
            }
            self.ringNext = (self.ringNext + 1) % WGLogSink.ringCapacity
        }
    }

    func exportRingBuffer() -> String {
        return self.lock.withLock { () -> String in
            if self.ring.count < WGLogSink.ringCapacity {
                return self.ring.joined(separator: "\n")
            }
            let ordered = Array(self.ring[self.ringNext...]) + Array(self.ring[..<self.ringNext])
            return ordered.joined(separator: "\n")
        }
    }
    #endif
}
