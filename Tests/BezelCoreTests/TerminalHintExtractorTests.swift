import Testing
import BezelCore

@Suite("TerminalHintExtractor")
struct TerminalHintExtractorTests {
    @Test func extractsITermAndTmux() {
        let hint = TerminalHintExtractor.extract(from: [
            "TERM_PROGRAM": "iTerm.app",
            "ITERM_SESSION_ID": "w0t0p0:UUID",
            "TMUX": "/tmp/tmux-1000/default,123,0",
            "TMUX_PANE": "%3",
            "__CFBundleIdentifier": "com.googlecode.iterm2",
        ])
        #expect(hint.termProgram == "iTerm.app")
        #expect(hint.itermSession == "w0t0p0:UUID")
        #expect(hint.tmuxPane == "%3")
        #expect(hint.bundleID == "com.googlecode.iterm2")
    }

    @Test func extractsWarpFocusURL() {
        let hint = TerminalHintExtractor.extract(from: [
            "TERM_PROGRAM": "WarpTerminal",
            "WARP_FOCUS_URL": "warp://session/abc",
        ])
        #expect(hint.warpFocusURL == "warp://session/abc")
    }

    @Test func extractsKittyWindow() {
        let hint = TerminalHintExtractor.extract(from: [
            "TERM_PROGRAM": "kitty",
            "KITTY_WINDOW_ID": "42",
        ])
        #expect(hint.kittyWindow == "42")
    }

    @Test func mergeInjectsUnderscoreKeys() {
        var obj: [String: Any] = ["hook_event_name": "SessionStart"]
        TerminalHintExtractor.merge(
            into: &obj,
            env: [
                "TERM_PROGRAM": "ghostty",
                "KITTY_WINDOW_ID": "1",
            ],
            tty: "/dev/ttys001"
        )
        #expect(obj["_term_app"] as? String == "ghostty")
        #expect(obj["_tty"] as? String == "/dev/ttys001")
        #expect(obj["_kitty_window"] as? String == "1")
    }

    @Test func mergeCapturesITermTmuxWarpForBridge() {
        var obj: [String: Any] = [:]
        TerminalHintExtractor.merge(
            into: &obj,
            env: [
                "TERM_PROGRAM": "iTerm.app",
                "ITERM_SESSION_ID": "w0t0p0:UUID",
                "TMUX": "/tmp/tmux-1000/default,123,0",
                "TMUX_PANE": "%3",
                "WARP_FOCUS_URL": "warp://session/abc",
                "__CFBundleIdentifier": "com.googlecode.iterm2",
            ],
            tty: "/dev/ttys009"
        )
        #expect(obj["_term_app"] as? String == "iTerm.app")
        #expect(obj["_iterm_session"] as? String == "w0t0p0:UUID")
        #expect(obj["_tty"] as? String == "/dev/ttys009")
        #expect(obj["_tmux"] as? String == "/tmp/tmux-1000/default,123,0")
        #expect(obj["_tmux_pane"] as? String == "%3")
        #expect(obj["_warp_focus_url"] as? String == "warp://session/abc")
        #expect(obj["_term_bundle"] as? String == "com.googlecode.iterm2")
    }

    @Test func fromHookObjectReadsUnderscoreKeys() {
        let obj: [String: Any] = [
            "_term_app": "iTerm.app",
            "_iterm_session": "w0t0p0:abc",
            "_tty": "/dev/ttys001",
        ]
        let hint = TerminalHintExtractor.fromHookObject(obj)
        #expect(hint?.termProgram == "iTerm.app")
        #expect(hint?.itermSession == "w0t0p0:abc")
        #expect(hint?.tty == "/dev/ttys001")
    }

    @Test func mergeFallsBackToEnvTTYWhenNoLiveCapture() {
        var obj: [String: Any] = [:]
        // Explicit nil tty + no CTTY in this test process → env BEZEL_TTY / TTY.
        // Pass empty env keys first to ensure merge uses BEZEL_TTY when resolve returns nil
        // OR live CTTY when available (either is acceptable for `_tty` presence).
        TerminalHintExtractor.merge(
            into: &obj,
            env: ["BEZEL_TTY": "/dev/ttys042"],
            tty: nil
        )
        // Live CTTY wins when present; otherwise env fallback.
        let tty = obj["_tty"] as? String
        #expect(tty != nil)
        if TerminalHintExtractor.resolveControllingTTY() == nil {
            #expect(tty == "/dev/ttys042")
        }
    }

    @Test func resolveControllingTTYDoesNotCrash() {
        // May be nil under CI/launchd with no CTTY — API must remain safe.
        _ = TerminalHintExtractor.resolveControllingTTY()
    }
}
