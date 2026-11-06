import Foundation

/// The container of one extension point (see WGHooks/HOOKS.md for the points themselves).
///
/// Handlers are registered on the main thread while the modules register at launch; after
/// `WGHookRegistry.freeze()` the handler array never changes. Upstream call sites test `isEmpty`
/// first: for a point nobody uses that is one plain load, without locks or allocations.
public final class WGHookPoint<Handler> {
    private struct Entry {
        let order: Int
        let sequence: Int
        let handler: Handler
    }

    public let name: StaticString

    private var entries: [Entry] = []
    private var currentHandlers: [Handler] = []
    private var currentIsEmpty: Bool = true

    public init(_ name: StaticString) {
        self.name = name
    }

    /// Lower `order` runs first; equal orders keep the registration order.
    public func register(_ handler: Handler, order: Int = 0) {
        if WGHookRegistry.isFrozen {
            assertionFailure("\(self.name): register after WGHookRegistry.freeze()")
            WGLog.error("hooks", "\(self.name): handler registered after freeze is ignored")
            return
        }
        assert(Thread.isMainThread, "\(self.name): register on the main thread")
        self.entries.append(Entry(order: order, sequence: self.entries.count, handler: handler))
        let sorted = self.entries.sorted { lhs, rhs in
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            return lhs.sequence < rhs.sequence
        }
        self.currentHandlers = sorted.map { $0.handler }
        self.currentIsEmpty = self.currentHandlers.isEmpty
    }

    public var isEmpty: Bool {
        return self.currentIsEmpty
    }

    public var handlers: [Handler] {
        return self.currentHandlers
    }

    /// Tests only.
    func removeAllForTesting() {
        self.entries.removeAll()
        self.currentHandlers = []
        self.currentIsEmpty = true
    }
}

public enum WGHookRegistry {
    private static let lock = WGUnfairLock()
    private static var frozen = false

    /// After every `register()` of every module. Taking the lock publishes the handler arrays
    /// written on the main thread to whichever thread reads them later.
    public static func freeze() {
        WGHookRegistry.lock.withLock {
            WGHookRegistry.frozen = true
        }
    }

    public static var isFrozen: Bool {
        return WGHookRegistry.lock.withLock {
            return WGHookRegistry.frozen
        }
    }

    /// Tests only.
    static func unfreezeForTesting() {
        WGHookRegistry.lock.withLock {
            WGHookRegistry.frozen = false
        }
    }
}
