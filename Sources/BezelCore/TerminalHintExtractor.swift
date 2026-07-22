import Foundation
import Darwin

public enum TerminalHintExtractor {
    /// iTerm2 sets `ITERM_SESSION_ID` as `w0t0p0:<GUID>` but AppleScript
    /// `unique id` / `id` is the GUID only. CodeIsland / Open Island store
    /// the GUID; matching the full env string is a common miss.
    public static func normalizeITermSessionID(_ raw: String?) -> String? {
        guard let raw = nonEmpty(raw) else { return nil }
        if let colon = raw.firstIndex(of: ":") {
            let guid = String(raw[raw.index(after: colon)...])
            return nonEmpty(guid) ?? raw
        }
        return raw
    }

    /// Unique tab title token (CC Status Bar style) for Ghostty AX focus when
    /// AppleScript has no reliable `tty` property.
    public static func bezelTTYToken(for tty: String) -> String {
        let short = tty.replacingOccurrences(of: "/dev/", with: "")
        return "[BEZEL:\(short)]"
    }

    public static func extract(from env: [String: String]) -> TerminalHint {
        let agentPID: Int?
        if let raw = env["BEZEL_AGENT_PID"], let parsed = Int(raw), parsed > 0 {
            agentPID = parsed
        } else {
            agentPID = nil
        }
        return TerminalHint(
            termProgram: env["TERM_PROGRAM"],
            bundleID: env["__CFBundleIdentifier"],
            itermSession: normalizeITermSessionID(env["ITERM_SESSION_ID"]),
            tty: nonEmpty(env["BEZEL_TTY"]) ?? nonEmpty(env["TTY"]),
            tmux: nonEmpty(env["TMUX"]),
            tmuxPane: nonEmpty(env["TMUX_PANE"]),
            kittyWindow: nonEmpty(env["KITTY_WINDOW_ID"]),
            warpFocusURL: nonEmpty(env["WARP_FOCUS_URL"]),
            termSessionID: nonEmpty(env["TERM_SESSION_ID"]),
            agentPID: agentPID
        )
    }

    /// Rebuild a hint from underscore keys the bridge injects into hook JSON.
    public static func fromHookObject(_ obj: [String: Any]) -> TerminalHint? {
        let termProgram = obj["_term_app"] as? String
        let bundleID = obj["_term_bundle"] as? String
        let itermSession = normalizeITermSessionID(obj["_iterm_session"] as? String)
        let tty = obj["_tty"] as? String
        let tmux = obj["_tmux"] as? String
        let tmuxPane = obj["_tmux_pane"] as? String
        let kittyWindow = obj["_kitty_window"] as? String
        let warpFocusURL = obj["_warp_focus_url"] as? String
        let termSessionID = obj["_term_session"] as? String
        let agentPID = intValue(obj["_ppid"])
        let hasAny = [
            termProgram, bundleID, itermSession, tty, tmux, tmuxPane,
            kittyWindow, warpFocusURL, termSessionID,
        ].contains { $0 != nil } || agentPID != nil
        guard hasAny else { return nil }
        return TerminalHint(
            termProgram: termProgram,
            bundleID: bundleID,
            itermSession: itermSession,
            tty: tty,
            tmux: tmux,
            tmuxPane: tmuxPane,
            kittyWindow: kittyWindow,
            warpFocusURL: warpFocusURL,
            termSessionID: termSessionID,
            agentPID: agentPID
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
    /// Captures `_iterm_session`, `_term_session`, `_tty`, `_tmux`/`_tmux_pane`,
    /// `_term_app`, kitty, warp focus URL, and `_ppid` for TerminalJumper.
    ///
    /// Call on **every** hook event so tty / session ids / agent PID stay fresh —
    /// not once-and-stale at SessionStart.
    ///
    /// When `tty` is nil, attempts `resolveControllingTTY()`, then PPID-tree walk
    /// (CC Status Bar), then env `BEZEL_TTY`/`TTY`.
    public static func merge(
        into object: inout [String: Any],
        env: [String: String],
        tty: String? = nil,
        agentPID: Int? = nil
    ) {
        let hint = extract(from: env)
        if let v = hint.termProgram { object["_term_app"] = v }
        if let v = hint.bundleID { object["_term_bundle"] = v }
        if let v = hint.itermSession { object["_iterm_session"] = v }
        if let v = hint.termSessionID { object["_term_session"] = v }
        if let v = hint.kittyWindow { object["_kitty_window"] = v }
        if let v = hint.tmux { object["_tmux"] = v }
        if let v = hint.tmuxPane { object["_tmux_pane"] = v }
        if let v = hint.warpFocusURL { object["_warp_focus_url"] = v }
        if let tty {
            object["_tty"] = tty
        } else if let resolved = resolveControllingTTY() {
            object["_tty"] = resolved
        } else if let walked = resolveTTYFromProcessTree(
            startingPID: agentPID.map { Int32(clamping: $0) }
        ) {
            object["_tty"] = walked
        } else if let v = hint.tty {
            object["_tty"] = v
        }
        if let agentPID, agentPID > 0 {
            object["_ppid"] = agentPID
        } else if let fromEnv = hint.agentPID {
            object["_ppid"] = fromEnv
        }
    }

    /// Walk parent PIDs (CC Status Bar `TtyDetector`) until `ps` reports a TTY.
    /// Depth-limited; returns `/dev/ttys…` or nil.
    public static func resolveTTYFromProcessTree(
        startingPID: Int32? = nil,
        maxDepth: Int = 5,
        psRunner: (_ pid: Int32) -> (tty: String?, ppid: Int32?) = defaultPSLookup
    ) -> String? {
        var current = startingPID ?? getppid()
        guard current > 1 else { return nil }

        for _ in 0..<maxDepth {
            let lookup = psRunner(current)
            if let raw = lookup.tty {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, trimmed != "??", trimmed != "-" {
                    return trimmed.hasPrefix("/dev/") ? trimmed : "/dev/\(trimmed)"
                }
            }
            guard let ppid = lookup.ppid, ppid > 1, ppid != current else { break }
            current = ppid
        }
        return nil
    }

    /// Production `ps` lookup used by `resolveTTYFromProcessTree`.
    public static func defaultPSLookup(pid: Int32) -> (tty: String?, ppid: Int32?) {
        let tty = runPS(arguments: ["-o", "tty=", "-p", String(pid)])
        let ppidRaw = runPS(arguments: ["-o", "ppid=", "-p", String(pid)])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ppid = ppidRaw.flatMap { Int32($0) }
        return (tty, ppid)
    }

    private static func runPS(arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let i = value as? Int, i > 0 { return i }
        if let n = value as? NSNumber {
            let i = n.intValue
            return i > 0 ? i : nil
        }
        if let s = value as? String, let i = Int(s), i > 0 { return i }
        return nil
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
