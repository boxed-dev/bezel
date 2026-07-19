import Foundation
import os.lock

/// First-writer-wins response holder for HookServer timeout vs UI settlement races.
/// Once settled, later writers are ignored; `get()` always returns the winning bytes.
public final class SettledResponseBox: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var value: Data
    private var settled = false

    public init(placeholder: Data) {
        self.value = placeholder
    }

    /// Settles once. Returns `true` if this call won; `false` if already settled.
    @discardableResult
    public func settle(_ data: Data) -> Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        if settled { return false }
        value = data
        settled = true
        return true
    }

    public var isSettled: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return settled
    }

    /// Bytes that will be / were written to the socket (placeholder until first settle).
    public func get() -> Data {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return value
    }
}

/// Shared cancel flag so a timed-out enqueue wait cannot still push UI later.
public final class DecisionCancelFlag: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var cancelled = false

    public init() {}

    public func cancel() {
        os_unfair_lock_lock(&lock)
        cancelled = true
        os_unfair_lock_unlock(&lock)
    }

    public var isCancelled: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return cancelled
    }
}
