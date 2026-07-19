import Testing
import Foundation
import BezelCore

@Suite("UsageGlance")
struct UsageGlanceTests {
    @Test func basicPercent() {
        let snap = ClaudeUsageSnapshot(
            sevenDay: ClaudeUsageWindow(usedPercent: 38),
            source: "test"
        )
        #expect(UsageGlance.compactText(snap) == "38%")
    }

    @Test func hotWindowShowsResetHours() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resets = now.addingTimeInterval(7200)
        let snap = ClaudeUsageSnapshot(
            sevenDay: ClaudeUsageWindow(usedPercent: 72, resetsAt: resets),
            source: "test"
        )
        #expect(UsageGlance.compactText(snap, now: now) == "72% · 2h")
    }

    @Test func belowThresholdNoResetTip() {
        let now = Date()
        let snap = ClaudeUsageSnapshot(
            fiveHour: ClaudeUsageWindow(usedPercent: 69, resetsAt: now.addingTimeInterval(3600)),
            source: "test"
        )
        #expect(UsageGlance.compactText(snap, now: now) == "69%")
    }

    @Test func roundedPercentShowsResetTip() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resets = now.addingTimeInterval(3600)
        let snap = ClaudeUsageSnapshot(
            sevenDay: ClaudeUsageWindow(usedPercent: 69.6, resetsAt: resets),
            source: "test"
        )
        #expect(UsageGlance.compactText(snap, now: now) == "70% · 1h")
    }

    @Test func resetMinutesSuffix() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resets = now.addingTimeInterval(45 * 60)
        let snap = ClaudeUsageSnapshot(
            sevenDay: ClaudeUsageWindow(usedPercent: 80, resetsAt: resets),
            source: "test"
        )
        #expect(UsageGlance.compactText(snap, now: now) == "80% · 45m")
    }

    @Test func resetDaysSuffix() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resets = now.addingTimeInterval(3 * 24 * 3600)
        let snap = ClaudeUsageSnapshot(
            sevenDay: ClaudeUsageWindow(usedPercent: 91, resetsAt: resets),
            source: "test"
        )
        #expect(UsageGlance.compactText(snap, now: now) == "91% · 3d")
    }

    @Test func sevenDayWinsOverFiveHour() {
        let now = Date()
        let snap = ClaudeUsageSnapshot(
            fiveHour: ClaudeUsageWindow(usedPercent: 40, resetsAt: now.addingTimeInterval(3600)),
            sevenDay: ClaudeUsageWindow(usedPercent: 75, resetsAt: now.addingTimeInterval(7200)),
            source: "test"
        )
        #expect(UsageGlance.compactText(snap, now: now) == "75% · 2h")
    }

    @Test func showsResetCountdownWhenHot() {
        let now = Date()
        let snap = ClaudeUsageSnapshot(
            sevenDay: ClaudeUsageWindow(usedPercent: 72, resetsAt: now.addingTimeInterval(3600)),
            source: "test"
        )
        #expect(UsageGlance.showsResetCountdown(snap))
    }

    @Test func nilWhenNoPrimary() {
        let snap = ClaudeUsageSnapshot(source: "test")
        #expect(UsageGlance.compactText(snap) == nil)
    }
}
