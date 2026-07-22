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

    @Test func parsesUsedPercentAlias() throws {
        let json = Data(#"""
        {"seven_day":{"used_percent":62.4,"resets_at":1738857600}}
        """#.utf8)
        let snap = try #require(ClaudeUsageParser.parse(json, source: "statusline"))
        #expect(snap.sevenDay?.usedPercent == 62.4)
        #expect(snap.primaryPercent == 62)
    }

    @Test func parsesMillisecondEpochResets() throws {
        let json = Data(#"""
        {"five_hour":{"used_percentage":10,"resets_at":1738425600000}}
        """#.utf8)
        let snap = try #require(ClaudeUsageParser.parse(json, source: "statusline"))
        #expect(snap.fiveHour?.resetsAt?.timeIntervalSince1970 == 1_738_425_600)
    }

    @Test func parsesStringEpochResets() throws {
        let json = Data(#"""
        {"seven_day":{"utilization":"44","resets_at":"1738857600"}}
        """#.utf8)
        let snap = try #require(ClaudeUsageParser.parse(json, source: "oauth"))
        #expect(snap.sevenDay?.usedPercent == 44)
        #expect(snap.sevenDay?.resetsAt?.timeIntervalSince1970 == 1_738_857_600)
    }

    @Test func bezelCacheWinsOverVibeIslandFallback() {
        let bezel = ClaudeUsageSnapshot(
            sevenDay: ClaudeUsageWindow(usedPercent: 40),
            fetchedAt: Date(timeIntervalSince1970: 100),
            source: "statusline-cache"
        )
        let vibe = ClaudeUsageSnapshot(
            sevenDay: ClaudeUsageWindow(usedPercent: 99),
            fetchedAt: Date(timeIntervalSince1970: 999),
            source: "vibe-island-cache"
        )
        let picked = UsageSourcePolicy.selectDiskSnapshot(bezel: bezel, vibeIsland: vibe)
        #expect(picked?.source == "statusline-cache")
        #expect(picked?.primaryPercent == 40)
    }

    @Test func vibeIslandUsedOnlyWhenBezelMissing() {
        let vibe = ClaudeUsageSnapshot(
            sevenDay: ClaudeUsageWindow(usedPercent: 55),
            fetchedAt: Date(timeIntervalSince1970: 50),
            source: "vibe-island-cache"
        )
        #expect(UsageSourcePolicy.selectDiskSnapshot(bezel: nil, vibeIsland: vibe)?.primaryPercent == 55)
        #expect(UsageSourcePolicy.selectDiskSnapshot(bezel: nil, vibeIsland: nil) == nil)
    }

    @Test func flowStatsRecordJumpDoesNotAffectGlance() {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("bezel-flow-\(UUID().uuidString)", isDirectory: true)
            .path
        defer { try? FileManager.default.removeItem(atPath: home) }

        let snap = ClaudeUsageSnapshot(
            sevenDay: ClaudeUsageWindow(usedPercent: 33),
            source: "test"
        )
        let before = UsageGlance.compactText(snap)
        _ = FlowStatsStore.recordJump(home: home)
        #expect(UsageGlance.compactText(snap) == before)
        #expect(before == "33%")
    }
}
