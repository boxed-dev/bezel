import Testing
import BezelCore

@Suite("TerminalHint.merge")
struct TerminalHintMergeTests {
    @Test func keepsITermSessionWhenLaterHookOmitsIt() {
        let rich = TerminalHint(
            termProgram: "iTerm.app",
            itermSession: "w0t0p0:abc",
            tty: "/dev/ttys001"
        )
        let weak = TerminalHint(termProgram: "iTerm.app")
        let merged = rich.merging(weak)
        #expect(merged.itermSession == "w0t0p0:abc")
        #expect(merged.tty == "/dev/ttys001")
        #expect(merged.termProgram == "iTerm.app")
    }

    @Test func adoptsNewTTYWhenPreviouslyMissing() {
        let a = TerminalHint(termProgram: "ghostty")
        let b = TerminalHint(tty: "/dev/ttys002")
        let merged = a.merging(b)
        #expect(merged.termProgram == "ghostty")
        #expect(merged.tty == "/dev/ttys002")
    }

    @Test func adoptsFreshAgentPIDAndTermSession() {
        let a = TerminalHint(termProgram: "Apple_Terminal", agentPID: 1)
        let b = TerminalHint(termSessionID: "TERM-9", agentPID: 42)
        let merged = a.merging(b)
        #expect(merged.termSessionID == "TERM-9")
        #expect(merged.agentPID == 42)
    }
}
