import Testing
import BezelCore

/// Seam: unique-identity ranking + cwd ambiguity policy for TerminalJumper.
@Suite("TerminalJumpMatch")
struct TerminalJumpMatchTests {
    @Test func strongestPrefersTTYOverITermSession() {
        let hint = TerminalHint(
            termProgram: "iTerm.app",
            itermSession: "abc",
            tty: "/dev/ttys001"
        )
        #expect(TerminalJumpMatch.strongestIdentity(for: hint) == .tty)
    }

    @Test func strongestFallsToITermSessionWithoutTTY() {
        let hint = TerminalHint(termProgram: "iTerm.app", itermSession: "abc")
        #expect(TerminalJumpMatch.strongestIdentity(for: hint) == .itermSession)
    }

    @Test func strongestPrefersITermSessionOverTmuxPane() {
        // Execution may still tmuxThenHost; identity rank is for host surface precision.
        let hint = TerminalHint(
            itermSession: "abc",
            tmuxPane: "%1"
        )
        #expect(TerminalJumpMatch.strongestIdentity(for: hint) == .itermSession)
    }

    @Test func strongestPrefersTmuxPaneOverTermSession() {
        let hint = TerminalHint(tmuxPane: "%3", termSessionID: "ABC-123")
        #expect(TerminalJumpMatch.strongestIdentity(for: hint) == .tmuxPane)
    }

    @Test func strongestUsesAgentPIDBeforeActivateOnly() {
        let hint = TerminalHint(termProgram: "ghostty", agentPID: 4242)
        #expect(TerminalJumpMatch.strongestIdentity(for: hint) == .agentPID)
    }

    @Test func emptyHintHasNoStrongIdentity() {
        #expect(TerminalJumpMatch.strongestIdentity(for: TerminalHint()) == nil)
    }

    @Test func cwdFallbackOnlyWhenExactlyOneMatch() {
        #expect(TerminalJumpMatch.allowCwdFallback(matchCount: 1))
        #expect(!TerminalJumpMatch.allowCwdFallback(matchCount: 0))
        #expect(!TerminalJumpMatch.allowCwdFallback(matchCount: 2))
        #expect(!TerminalJumpMatch.allowCwdFallback(matchCount: 5))
    }

    @Test func ghosttyWithTTYIsPrecise_withoutTTYIsNot() {
        let precise = TerminalHint(termProgram: "ghostty", tty: "/dev/ttys009")
        let fuzzy = TerminalHint(termProgram: "ghostty")
        #expect(TerminalJumpMatch.isPreciseSurfaceJump(precise))
        #expect(!TerminalJumpMatch.isPreciseSurfaceJump(fuzzy))
    }

    @Test func itermSelectOrderTTYBeforeSessionID() {
        let hint = TerminalHint(itermSession: "abc", tty: "/dev/ttys001")
        #expect(TerminalJumpMatch.itermSelectKeys(for: hint) == [.tty, .itermSession])
    }

    @Test func itermSelectOrderSessionOnlyWhenNoTTY() {
        let hint = TerminalHint(itermSession: "abc")
        #expect(TerminalJumpMatch.itermSelectKeys(for: hint) == [.itermSession])
    }

    @Test func mergeRefreshesStaleTTYAndITermSession() {
        let stale = TerminalHint(
            termProgram: "iTerm.app",
            itermSession: "OLD",
            tty: "/dev/ttys001",
            agentPID: 100
        )
        let fresh = TerminalHint(
            itermSession: "NEW",
            tty: "/dev/ttys099",
            agentPID: 200
        )
        let merged = stale.merging(fresh)
        #expect(merged.itermSession == "NEW")
        #expect(merged.tty == "/dev/ttys099")
        #expect(merged.agentPID == 200)
        #expect(merged.termProgram == "iTerm.app")
    }

    @Test func mergeKeepsPriorWhenHookOmitsIdentity() {
        let rich = TerminalHint(
            itermSession: "abc",
            tty: "/dev/ttys001",
            termSessionID: "TERM-1",
            agentPID: 9
        )
        let weak = TerminalHint(termProgram: "iTerm.app")
        let merged = rich.merging(weak)
        #expect(merged.itermSession == "abc")
        #expect(merged.tty == "/dev/ttys001")
        #expect(merged.termSessionID == "TERM-1")
        #expect(merged.agentPID == 9)
    }
}
