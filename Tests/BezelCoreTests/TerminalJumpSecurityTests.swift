import Testing
import BezelCore

@Suite("TerminalJumpSecurity")
struct TerminalJumpSecurityTests {
    @Test func appleScriptEscapeQuotesAndBackslash() {
        #expect(TerminalJumpSecurity.appleScriptEscape(#"foo"bar"#) == #"foo\"bar"#)
        #expect(TerminalJumpSecurity.appleScriptEscape(#"a\b"#) == #"a\\b"#)
    }

    @Test func appleScriptEscapeNewlinesAndControls() {
        #expect(TerminalJumpSecurity.appleScriptEscape("a\nb") == #"a\nb"#)
        #expect(TerminalJumpSecurity.appleScriptEscape("a\rb") == #"a\rb"#)
        #expect(TerminalJumpSecurity.appleScriptEscape("a\tb") == #"a\tb"#)
        #expect(TerminalJumpSecurity.appleScriptEscape("a\0b") == #"a\x00b"#)
        // Injection-shaped payload stays inside the literal (no raw quote/newline breakout).
        let evil = "ttys001\"\n end tell\n do shell script \"id\"\n --"
        let escaped = TerminalJumpSecurity.appleScriptEscape(evil)
        #expect(!escaped.contains("\n"))
        #expect(!escaped.contains("\r"))
        #expect(escaped.contains(#"\""#))
        #expect(escaped.contains(#"\n"#))
        #expect(escaped.hasPrefix("ttys001\\\""))
    }

    @Test func warpURLAllowlist() {
        #expect(TerminalJumpSecurity.validatedWarpFocusURL("warp://session/1") != nil)
        #expect(TerminalJumpSecurity.validatedWarpFocusURL("https://app.warp.dev/session/1") != nil)
        #expect(TerminalJumpSecurity.validatedWarpFocusURL("WARP://Session/1") != nil)
        #expect(TerminalJumpSecurity.validatedWarpFocusURL("http://evil.example") == nil)
        #expect(TerminalJumpSecurity.validatedWarpFocusURL("file:///etc/passwd") == nil)
        #expect(TerminalJumpSecurity.validatedWarpFocusURL("javascript:alert(1)") == nil)
        #expect(TerminalJumpSecurity.validatedWarpFocusURL("not a url") == nil)
        #expect(TerminalJumpSecurity.validatedWarpFocusURL("warp://x\0y") == nil)
    }

    @Test func tmuxSocketPathRejectsWeird() {
        #expect(
            TerminalJumpSecurity.validatedTmuxSocketPath(fromTMUXEnv: "/tmp/tmux-501/default,123,0")
                == "/tmp/tmux-501/default"
        )
        #expect(TerminalJumpSecurity.validatedTmuxSocketPath(fromTMUXEnv: "/tmp/ok") == "/tmp/ok")
        #expect(TerminalJumpSecurity.validatedTmuxSocketPath(fromTMUXEnv: "/tmp/bad\npath,1,0") == nil)
        #expect(TerminalJumpSecurity.validatedTmuxSocketPath(fromTMUXEnv: "/tmp/bad\0path,1,0") == nil)
        #expect(TerminalJumpSecurity.validatedTmuxSocketPath(fromTMUXEnv: "/tmp/bad\rpath,1,0") == nil)
        #expect(TerminalJumpSecurity.validatedTmuxSocketPath(fromTMUXEnv: ",1,0") == nil)
        #expect(TerminalJumpSecurity.validatedTmuxSocketPath(fromTMUXEnv: "") == nil)
    }

    @Test func isSafePathArgument() {
        #expect(TerminalJumpSecurity.isSafePathArgument("/dev/ttys001"))
        #expect(!TerminalJumpSecurity.isSafePathArgument(""))
        #expect(!TerminalJumpSecurity.isSafePathArgument("a\nb"))
        #expect(!TerminalJumpSecurity.isSafePathArgument("a\0b"))
    }
}
