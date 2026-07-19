import Testing
import Foundation
import BezelCore

@Suite("ClaudeUsage")
struct ClaudeUsageTests {
    @Test func parsesStatusLineUsedPercentage() throws {
        let json = Data(#"""
        {"five_hour":{"used_percentage":23.5,"resets_at":1738425600},"seven_day":{"used_percentage":41.2,"resets_at":1738857600}}
        """#.utf8)
        let snap = try #require(ClaudeUsageParser.parse(json, source: "test"))
        #expect(snap.fiveHour?.usedPercent == 23.5)
        #expect(snap.sevenDay?.usedPercent == 41.2)
        #expect(snap.primaryPercent == 41)
        #expect(snap.fiveHour?.resetsAt?.timeIntervalSince1970 == 1_738_425_600)
    }

    @Test func parsesOAuthUtilizationISODates() throws {
        let json = Data(#"""
        {"five_hour":{"utilization":0.0,"resets_at":"2026-07-19T05:09:59.808608+00:00"},"seven_day":{"utilization":38.0,"resets_at":"2026-07-23T10:59:59.808633+00:00"}}
        """#.utf8)
        let snap = try #require(ClaudeUsageParser.parse(json, source: "oauth"))
        #expect(snap.fiveHour?.usedPercent == 0)
        #expect(snap.sevenDay?.usedPercent == 38)
        #expect(snap.primaryPercent == 38)
        #expect(snap.helpText.contains("5h 0%"))
        #expect(snap.helpText.contains("7d 38%"))
    }

    @Test func primaryFallsBackToSevenDay() throws {
        let json = Data(#"""
        {"seven_day":{"used_percentage":55}}
        """#.utf8)
        let snap = try #require(ClaudeUsageParser.parse(json, source: "test"))
        #expect(snap.primaryPercent == 55)
    }

    @Test func rejectsEmptyObject() {
        let json = Data(#"{}"#.utf8)
        #expect(ClaudeUsageParser.parse(json, source: "test") == nil)
    }

    @Test func loadCachedRoundtrip() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("bezel-usage-\(UUID().uuidString)", isDirectory: true)
            .path
        defer { try? FileManager.default.removeItem(atPath: home) }

        #expect(ClaudeUsagePath.ensureCacheDirectory(home: home))
        let url = ClaudeUsagePath.rateLimitsURL(home: home)
        try Data(#"""
        {"five_hour":{"used_percentage":12},"seven_day":{"used_percentage":40}}
        """#.utf8).write(to: url)

        let snap = try #require(ClaudeUsagePath.loadCached(home: home))
        #expect(snap.primaryPercent == 40)
        #expect(snap.source == "statusline-cache")
    }
}
