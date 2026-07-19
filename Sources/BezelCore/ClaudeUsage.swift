import Foundation

/// One Claude.ai rate-limit window (5-hour or 7-day).
public struct ClaudeUsageWindow: Equatable, Sendable {
    public var usedPercent: Double
    public var resetsAt: Date?

    public init(usedPercent: Double, resetsAt: Date? = nil) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

/// Plan usage snapshot for the compact notch (not session count).
public struct ClaudeUsageSnapshot: Equatable, Sendable {
    public var fiveHour: ClaudeUsageWindow?
    public var sevenDay: ClaudeUsageWindow?
    public var fetchedAt: Date
    public var source: String

    public init(
        fiveHour: ClaudeUsageWindow? = nil,
        sevenDay: ClaudeUsageWindow? = nil,
        fetchedAt: Date = Date(),
        source: String
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.fetchedAt = fetchedAt
        self.source = source
    }

    /// Compact notch meter: 7-day plan usage first (what people mean by “my usage”),
    /// else the 5-hour session window. Hover help shows both.
    public var primaryPercent: Int? {
        if let p = sevenDay?.usedPercent {
            return Int(p.rounded())
        }
        if let p = fiveHour?.usedPercent {
            return Int(p.rounded())
        }
        return nil
    }

    public var helpText: String {
        var parts: [String] = []
        if let p = fiveHour?.usedPercent {
            parts.append(String(format: "5h %.0f%%", p))
        }
        if let p = sevenDay?.usedPercent {
            parts.append(String(format: "7d %.0f%%", p))
        }
        return parts.isEmpty ? "Claude usage" : parts.joined(separator: " · ")
    }
}

/// Parses statusLine `rate_limits` JSON and OAuth `/api/oauth/usage` responses.
public enum ClaudeUsageParser {
    public static func parse(_ data: Data, source: String, fetchedAt: Date = Date()) -> ClaudeUsageSnapshot? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return parse(obj, source: source, fetchedAt: fetchedAt)
    }

    public static func parse(
        _ obj: [String: Any],
        source: String,
        fetchedAt: Date = Date()
    ) -> ClaudeUsageSnapshot? {
        let five = window(from: obj["five_hour"])
        let seven = window(from: obj["seven_day"])
        guard five != nil || seven != nil else { return nil }
        return ClaudeUsageSnapshot(
            fiveHour: five,
            sevenDay: seven,
            fetchedAt: fetchedAt,
            source: source
        )
    }

    private static func window(from value: Any?) -> ClaudeUsageWindow? {
        guard let dict = value as? [String: Any] else { return nil }
        let percent =
            number(dict["used_percentage"])
            ?? number(dict["utilization"])
            ?? number(dict["used_percent"])
        guard let percent else { return nil }
        return ClaudeUsageWindow(
            usedPercent: max(0, min(100, percent)),
            resetsAt: date(dict["resets_at"])
        )
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    private static func date(_ value: Any?) -> Date? {
        switch value {
        case let n as Int:
            return Date(timeIntervalSince1970: TimeInterval(n))
        case let n as Double:
            // Heuristic: ms vs s
            return Date(timeIntervalSince1970: n > 1_000_000_000_000 ? n / 1000 : n)
        case let n as NSNumber:
            let d = n.doubleValue
            return Date(timeIntervalSince1970: d > 1_000_000_000_000 ? d / 1000 : d)
        case let s as String:
            if let epoch = Double(s) {
                return Date(timeIntervalSince1970: epoch > 1_000_000_000_000 ? epoch / 1000 : epoch)
            }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = fractional.date(from: s) { return d }
            let basic = ISO8601DateFormatter()
            basic.formatOptions = [.withInternetDateTime]
            return basic.date(from: s)
        default:
            return nil
        }
    }
}

/// On-disk cache written by the Claude statusLine bridge.
public enum ClaudeUsagePath {
    public static let cacheDirectoryName = "cache"
    public static let rateLimitsFileName = "rl.json"

    public static func cacheDirectory(home: String? = nil) -> URL {
        BezelInstallState.bezelHome(home: home)
            .appendingPathComponent(cacheDirectoryName, isDirectory: true)
    }

    public static func rateLimitsURL(home: String? = nil) -> URL {
        cacheDirectory(home: home).appendingPathComponent(rateLimitsFileName)
    }

    @discardableResult
    public static func ensureCacheDirectory(home: String? = nil) -> Bool {
        guard BezelInstallState.ensureBezelHome(home: home) else { return false }
        let dir = cacheDirectory(home: home)
        do {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            return true
        } catch {
            return false
        }
    }

    /// Load snapshot from Bezel’s statusLine cache (if present).
    public static func loadCached(home: String? = nil) -> ClaudeUsageSnapshot? {
        let url = rateLimitsURL(home: home)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))
            .flatMap(\.contentModificationDate) ?? Date()
        return ClaudeUsageParser.parse(data, source: "statusline-cache", fetchedAt: mtime)
    }
}
