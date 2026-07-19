import Foundation
import Darwin

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

    /// Rebuild a hint from underscore keys the bridge injects into hook JSON.
    public static func fromHookObject(_ obj: [String: Any]) -> TerminalHint? {
        let termProgram = obj["_term_app"] as? String
        let bundleID = obj["_term_bundle"] as? String
        let itermSession = obj["_iterm_session"] as? String
        let tty = obj["_tty"] as? String
        let tmux = obj["_tmux"] as? String
        let tmuxPane = obj["_tmux_pane"] as? String
        let kittyWindow = obj["_kitty_window"] as? String
        let warpFocusURL = obj["_warp_focus_url"] as? String
        // Prefer dedicated keys; fall back to Apple Terminal session id if present.
        let hasAny = [termProgram, bundleID, itermSession, tty, tmux, tmuxPane, kittyWindow, warpFocusURL]
            .contains { $0 != nil }
        guard hasAny else { return nil }
        return TerminalHint(
            termProgram: termProgram,
            bundleID: bundleID,
            itermSession: itermSession,
            tty: tty,
            tmux: tmux,
            tmuxPane: tmuxPane,
            kittyWindow: kittyWindow,
            warpFocusURL: warpFocusURL
        )
    }

    public static func fromHookJSON(_ data: Data) -> TerminalHint? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return fromHookObject(obj)
    }

    /// Resolve the process controlling TTY path for Jump (`_tty`).
    ///
    /// Under agent hooks, stdin is typically a pipe, so `ttyname_r(STDIN)` fails.
    /// Opening `/dev/tty` reaches the controlling terminal when one exists
    /// (e.g. Terminal.app → Claude Code → bezel-bridge).
    ///
    /// Limitation: returns `nil` when there is no controlling terminal
    /// (launchd/GUI-only launch, `setsid`, fully detached daemons). Callers
    /// should fall back to `BEZEL_TTY` / `TTY` env if needed.
    public static func resolveControllingTTY() -> String? {
        if let name = ttyName(openingPath: "/dev/tty") { return name }
        if let name = ttyName(fd: STDIN_FILENO) { return name }
        if let name = ttyName(fd: STDOUT_FILENO) { return name }
        if let name = ttyName(fd: STDERR_FILENO) { return name }
        return nil
    }

    /// Inject underscore hint keys into a bridge/hook JSON payload.
    /// Captures `_iterm_session`, `_tty`, `_tmux`/`_tmux_pane`, `_term_app` (TERM_PROGRAM),
    /// kitty, and warp focus URL for later TerminalJumper use.
    ///
    /// When `tty` is nil, attempts `resolveControllingTTY()`, then env `BEZEL_TTY`/`TTY`.
    public static func merge(into object: inout [String: Any], env: [String: String], tty: String? = nil) {
        let hint = extract(from: env)
        if let v = hint.termProgram { object["_term_app"] = v }
        if let v = hint.bundleID { object["_term_bundle"] = v }
        if let v = hint.itermSession { object["_iterm_session"] = v }
        if let v = hint.kittyWindow { object["_kitty_window"] = v }
        if let v = hint.tmux { object["_tmux"] = v }
        if let v = hint.tmuxPane { object["_tmux_pane"] = v }
        if let v = hint.warpFocusURL { object["_warp_focus_url"] = v }
        if let tty {
            object["_tty"] = tty
        } else if let resolved = resolveControllingTTY() {
            object["_tty"] = resolved
        } else if let v = hint.tty {
            object["_tty"] = v
        }
    }

    private static func ttyName(fd: Int32) -> String? {
        var buf = [CChar](repeating: 0, count: 1024)
        guard ttyname_r(fd, &buf, buf.count) == 0 else { return nil }
        let name = String(cString: buf)
        return name.isEmpty ? nil : name
    }

    private static func ttyName(openingPath: String) -> String? {
        let fd = open(openingPath, O_RDONLY | O_NOCTTY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        return ttyName(fd: fd)
    }
}
