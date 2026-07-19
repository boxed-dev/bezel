import Foundation
import Darwin
import BezelCore

/// Keeps `SessionStore.usage` fresh from OAuth + statusLine cache.
@MainActor
final class UsageMonitor {
    private let store: SessionStore
    private var timer: Timer?
    private var fileSource: DispatchSourceFileSystemObject?
    private var cacheDirFD: Int32 = -1
    private var isRunning = false

    /// OAuth poll — Claude’s `/usage` source of truth.
    private let oauthInterval: TimeInterval = 45

    init(store: SessionStore) {
        self.store = store
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        _ = ClaudeUsagePath.ensureCacheDirectory()
        refreshFromDisk()
        watchCacheDirectory()
        Task { await refreshFromOAuth() }
        timer = Timer.scheduledTimer(withTimeInterval: oauthInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshFromOAuth()
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
        fileSource?.cancel()
        fileSource = nil
        if cacheDirFD >= 0 {
            close(cacheDirFD)
            cacheDirFD = -1
        }
    }

    func refreshFromDisk() {
        // Prefer Bezel cache; fall back to Vibe Island’s if present (same Claude statusLine data).
        var candidates: [(ClaudeUsageSnapshot, Date)] = []
        if let snap = ClaudeUsagePath.loadCached() {
            candidates.append((snap, snap.fetchedAt))
        }
        let vibeURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".vibe-island/cache/rl.json")
        if let data = try? Data(contentsOf: vibeURL),
           let snap = ClaudeUsageParser.parse(data, source: "vibe-island-cache"),
           let mtime = (try? vibeURL.resourceValues(forKeys: [.contentModificationDateKey]))
            .flatMap(\.contentModificationDate)
        {
            candidates.append((
                ClaudeUsageSnapshot(
                    fiveHour: snap.fiveHour,
                    sevenDay: snap.sevenDay,
                    fetchedAt: mtime,
                    source: snap.source
                ),
                mtime
            ))
        }
        guard let best = candidates.max(by: { $0.1 < $1.1 })?.0 else { return }
        store.applyUsage(best)
    }

    func refreshFromOAuth() async {
        guard let snap = await ClaudeUsageFetcher.fetch() else { return }
        store.applyUsage(snap)
        // Keep on-disk cache aligned so statusLine + OAuth agree.
        persist(snap)
    }

    private func persist(_ snap: ClaudeUsageSnapshot) {
        guard ClaudeUsagePath.ensureCacheDirectory() else { return }
        var obj: [String: Any] = [:]
        if let five = snap.fiveHour {
            var w: [String: Any] = ["used_percentage": five.usedPercent]
            if let reset = five.resetsAt {
                w["resets_at"] = Int(reset.timeIntervalSince1970)
            }
            obj["five_hour"] = w
        }
        if let seven = snap.sevenDay {
            var w: [String: Any] = ["used_percentage": seven.usedPercent]
            if let reset = seven.resetsAt {
                w["resets_at"] = Int(reset.timeIntervalSince1970)
            }
            obj["seven_day"] = w
        }
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj)
        else { return }
        try? data.write(to: ClaudeUsagePath.rateLimitsURL(), options: .atomic)
    }

    private func watchCacheDirectory() {
        let dir = ClaudeUsagePath.cacheDirectory().path
        cacheDirFD = open(dir, O_EVTONLY)
        guard cacheDirFD >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: cacheDirFD,
            eventMask: [.write, .rename, .extend, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.refreshFromDisk()
        }
        source.setCancelHandler { [weak self] in
            if let self, self.cacheDirFD >= 0 {
                close(self.cacheDirFD)
                self.cacheDirFD = -1
            }
        }
        fileSource = source
        source.resume()
    }
}
