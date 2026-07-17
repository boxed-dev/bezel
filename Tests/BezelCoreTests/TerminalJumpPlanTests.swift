import Testing
import BezelCore

@Suite("TerminalJumpPlan")
struct TerminalJumpPlanTests {
    @Test func itermWithSession() {
        let hint = TerminalHint(termProgram: "iTerm.app", itermSession: "w0t0p0:abc")
        #expect(TerminalJumpPlan.plan(for: hint) == .itermReveal)
    }

    @Test func itermWithoutSessionIsActivateOnly() {
        let hint = TerminalHint(termProgram: "iTerm.app")
        #expect(TerminalJumpPlan.plan(for: hint) == .activateOnly)
    }

    @Test func ghostty() {
        let hint = TerminalHint(termProgram: "ghostty")
        #expect(TerminalJumpPlan.plan(for: hint) == .ghosttyFocus)
    }

    @Test func ghosttyNeverActivateOnlyEvenWithoutTTY() {
        let hint = TerminalHint(termProgram: "ghostty", bundleID: "com.mitchellh.ghostty")
        #expect(TerminalJumpPlan.plan(for: hint) == .ghosttyFocus)
        #expect(TerminalJumpPlan.hostPlan(for: hint) == .ghosttyFocus)
    }

    @Test func terminalWithTTY() {
        let hint = TerminalHint(termProgram: "Apple_Terminal", tty: "/dev/ttys001")
        #expect(TerminalJumpPlan.plan(for: hint) == .terminalTTY)
    }

    @Test func terminalWithoutTTYIsActivateOnly() {
        let hint = TerminalHint(termProgram: "Apple_Terminal")
        #expect(TerminalJumpPlan.plan(for: hint) == .activateOnly)
    }

    @Test func warpURL() {
        let hint = TerminalHint(termProgram: "WarpTerminal", warpFocusURL: "warp://session/1")
        #expect(TerminalJumpPlan.plan(for: hint) == .warpURL)
    }

    @Test func warpWithoutURLIsActivateOnly() {
        let hint = TerminalHint(termProgram: "WarpTerminal")
        #expect(TerminalJumpPlan.plan(for: hint) == .activateOnly)
    }

    @Test func cursorIsActivateOnly() {
        let hint = TerminalHint(termProgram: "vscode", bundleID: "com.todesktop.230313mzl4w4u92")
        #expect(TerminalJumpPlan.plan(for: hint) == .activateOnly)
    }

    @Test func kittyWindow() {
        let hint = TerminalHint(termProgram: "kitty", kittyWindow: "9")
        #expect(TerminalJumpPlan.plan(for: hint) == .kittyWindow)
    }

    @Test func tmuxPrefersTmuxThenHost() {
        let hint = TerminalHint(termProgram: "iTerm.app", itermSession: "x", tmuxPane: "%1")
        #expect(TerminalJumpPlan.plan(for: hint) == .tmuxThenHost)
    }

    @Test func hostPlanAfterTmuxIsITermReveal() {
        let hint = TerminalHint(termProgram: "iTerm.app", itermSession: "x", tmuxPane: "%1")
        #expect(TerminalJumpPlan.hostPlan(for: hint) == .itermReveal)
    }

    @Test func hostPlanAfterTmuxIsTerminalTTY() {
        let hint = TerminalHint(termProgram: "Apple_Terminal", tty: "/dev/ttys002", tmux: "/tmp/tmux-1/default,1,0", tmuxPane: "%2")
        #expect(TerminalJumpPlan.plan(for: hint) == .tmuxThenHost)
        #expect(TerminalJumpPlan.hostPlan(for: hint) == .terminalTTY)
    }

    @Test func hostPlanAfterTmuxIsGhostty() {
        let hint = TerminalHint(termProgram: "ghostty", tty: "/dev/ttys003", tmuxPane: "%0")
        #expect(TerminalJumpPlan.plan(for: hint) == .tmuxThenHost)
        #expect(TerminalJumpPlan.hostPlan(for: hint) == .ghosttyFocus)
    }

    @Test func emptyIsUnsupported() {
        #expect(TerminalJumpPlan.plan(for: TerminalHint()) == .unsupported)
    }

    @Test func weztermIsActivateOnly() {
        let hint = TerminalHint(termProgram: "WezTerm", bundleID: "com.github.wez.wezterm")
        #expect(TerminalJumpPlan.plan(for: hint) == .activateOnly)
    }
}
