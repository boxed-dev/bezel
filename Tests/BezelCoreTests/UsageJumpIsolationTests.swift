import Testing
import BezelCore

/// D3 — usage surfaces never map to jump; epoch updates are orthogonal to TerminalJumper.
@Suite("Usage jump isolation")
struct UsageJumpIsolationTests {
    @Test func usageSurface_primaryActionExpand() {
        #expect(NotchInteraction.compactTrailingPrimary(context: .usage) == .expand)
        #expect(NotchInteraction.compactLeadingPrimary() == .expand)
    }

    @Test func usageContextNeverProducesJumpSecondary() {
        // Jump is session-row secondary only — usage has no jump seam.
        let jump = NotchInteraction.sessionRowSecondary(sessionID: SessionID("s1"))
        #expect(jump == .jump(SessionID("s1")))
        #expect(NotchInteraction.compactTrailingPrimary(context: .usage) != .resolve)
    }

    @Test func usageSourcePolicyNeverImpliesJump() {
        let bezel = ClaudeUsageSnapshot(
            sevenDay: ClaudeUsageWindow(usedPercent: 12),
            source: "statusline-cache"
        )
        let picked = UsageSourcePolicy.selectDiskSnapshot(bezel: bezel, vibeIsland: nil)
        #expect(picked?.primaryPercent == 12)
        // Policy returns a snapshot only — callers must applyUsage, never jump.
        #expect(UsageGlance.compactText(picked!) == "12%")
    }
}
