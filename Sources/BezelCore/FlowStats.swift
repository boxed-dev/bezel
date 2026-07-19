import Foundation

/// Local daily jump counter — persisted for future glance UI.
public struct FlowDayStats: Equatable, Sendable, Codable {
    public var dayKey: String
    public var jumps: Int

    public init(dayKey: String, jumps: Int = 0) {
        self.dayKey = dayKey
        self.jumps = jumps
    }

    public static func dayKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let y = c.year ?? 0
        let m = c.month ?? 0
        let d = c.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
}

public enum FlowStatsStore {
    public static let fileName = "flow-stats.json"

    public static func fileURL(home: String? = nil) -> URL {
        BezelInstallState.bezelHome(home: home).appendingPathComponent(fileName)
    }

    public static func load(home: String? = nil, now: Date = Date()) -> FlowDayStats {
        let key = FlowDayStats.dayKey(for: now)
        guard let data = try? Data(contentsOf: fileURL(home: home)),
              let saved = try? JSONDecoder().decode(FlowDayStats.self, from: data),
              saved.dayKey == key
        else {
            return FlowDayStats(dayKey: key)
        }
        return saved
    }

    @discardableResult
    public static func save(_ stats: FlowDayStats, home: String? = nil) -> Bool {
        guard BezelInstallState.ensureBezelHome(home: home) else { return false }
        guard let data = try? JSONEncoder().encode(stats) else { return false }
        do {
            try data.write(to: fileURL(home: home), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public static func recordJump(home: String? = nil, now: Date = Date()) -> FlowDayStats {
        var stats = load(home: home, now: now)
        stats.jumps += 1
        _ = save(stats, home: home)
        return stats
    }
}

/// Relative age for session rows (“now”, “2m”, “1h”).
public enum RelativeAge {
    public static func format(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 45 { return "now" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86_400)d"
    }

    /// Compact working clock: “4m” while tools run.
    public static func workingClock(since date: Date, now: Date = Date()) -> String? {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 15 { return nil }
        if seconds < 3600 { return "\(max(1, seconds / 60))m" }
        return "\(seconds / 3600)h"
    }
}
