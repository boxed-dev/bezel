import Foundation
import BezelCore

/// Polls Codex JSONL + OpenCode SQLite and merges presence into `SessionStore`.
/// Hooks remain phase truth; discovery only fills SESSIONS gaps.
///
/// I/O runs off the main actor — home Codex trees and OpenCode DBs can be large.
@MainActor
final class SessionDiscoveryMonitor {
    private let store: SessionStore
    private var timer: Timer?
    private var isRunning = false
    private var inFlight = false
    private let interval: TimeInterval = 20

    init(store: SessionStore) {
        self.store = store
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard isRunning, !inFlight else { return }
        inFlight = true
        Task { [weak self] in
            let discovered = await Task.detached(priority: .utility) {
                SessionDiscovery.collectFromHome()
            }.value
            self?.finishRefresh(discovered)
        }
    }

    private func finishRefresh(_ discovered: [Session]) {
        defer { inFlight = false }
        guard isRunning else { return }
        store.mergeDiscovered(discovered)
    }
}
