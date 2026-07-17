import Foundation

public enum TerminalHintExtractor {
    public static func extract(from env: [String: String]) -> TerminalHint {
        TerminalHint(
            termProgram: env["TERM_PROGRAM"],
            bundleID: env["__CFBundleIdentifier"],
            itermSession: env["ITERM_SESSION_ID"],
            tty: env["BEZEL_TTY"] ?? env["TTY"],
            tmux: env["TMUX"],
            tmuxPane: env["TMUX_PANE"],
            kittyWindow: env["KITTY_WINDOW_ID"],
            warpFocusURL: env["WARP_FOCUS_URL"]
        )
    }

    public static func merge(into object: inout [String: Any], env: [String: String], tty: String? = nil) {
        let hint = extract(from: env)
        if let v = hint.termProgram { object["_term_app"] = v }
        if let v = hint.bundleID { object["_term_bundle"] = v }
        if let v = hint.itermSession { object["_iterm_session"] = v }
        if let v = env["TERM_SESSION_ID"] { object["_term_session"] = v }
        if let v = hint.kittyWindow { object["_kitty_window"] = v }
        if let v = hint.tmux { object["_tmux"] = v }
        if let v = hint.tmuxPane { object["_tmux_pane"] = v }
        if let v = hint.warpFocusURL { object["_warp_focus_url"] = v }
        if let tty {
            object["_tty"] = tty
        } else if let v = hint.tty {
            object["_tty"] = v
        }
    }
}
