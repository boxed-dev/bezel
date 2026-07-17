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
}
