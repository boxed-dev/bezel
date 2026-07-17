import AppKit
import ApplicationServices
import Foundation
import BezelCore

/// Focuses the terminal/IDE surface for a session.
///
/// Strategies (see `TerminalJumpPlan`):
/// - **iTerm2:** `iterm2:///reveal?sessionid=` when `_iterm_session` is present
/// - **Terminal.app:** AppleScript tab select by tty
/// - **Ghostty:** AppleScript `focus` on terminal matching `tty` (or cwd). Ghostty 1.3+
///   exposes `tty` + `focus` in its scripting dictionary (Automation TCC). Accessibility
///   (`AXIsProcessTrusted`) is required as a fallback to raise the Ghostty app when
///   AppleScript cannot honor the hint; there is no public URL scheme for surface focus.
/// - **tmux:** `tmux select-pane` then host strategy
/// - **Warp / Cursor / missing hints:** `.activateOnly` degrade only
enum TerminalJumper {
    static func jump(session: Session) {
        let hint = session.terminal ?? TerminalHint()
        let strategy = TerminalJumpPlan.plan(for: hint)
        execute(strategy: strategy, hint: hint, session: session)
    }

    private static func execute(strategy: TerminalJumpStrategy, hint: TerminalHint, session: Session) {
        switch strategy {
        case .itermReveal:
            jumpITerm(hint: hint)
        case .warpURL:
            jumpWarp(hint: hint)
        case .ghosttyFocus:
            jumpGhostty(hint: hint, cwd: session.cwd)
        case .terminalTTY:
            jumpTerminalTTY(hint: hint)
        case .kittyWindow:
            jumpKitty(hint: hint)
        case .tmuxThenHost:
            jumpTmuxThenHost(hint: hint, session: session)
        case .activateOnly:
            activate(bundleID: hint.bundleID ?? bundleIDGuess(for: hint))
        case .unsupported:
            NSLog("Bezel Jump: unsupported — no TERM_PROGRAM / bundle / session hints")
        }
    }

    // MARK: - Per-terminal

    private static func jumpITerm(hint: TerminalHint) {
        guard let id = hint.itermSession, !id.isEmpty else {
            fail("iTerm reveal requires _iterm_session / ITERM_SESSION_ID")
            activate(bundleID: "com.googlecode.iterm2")
            return
        }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+")
        let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
        guard let url = URL(string: "iterm2:///reveal?sessionid=\(encoded)") else {
            fail("could not build iterm2:///reveal URL for sessionid=\(id)")
            return
        }
        if !NSWorkspace.shared.open(url) {
            fail("NSWorkspace failed to open iterm2:///reveal?sessionid=\(id)")
            activate(bundleID: "com.googlecode.iterm2")
        }
    }

    private static func jumpWarp(hint: TerminalHint) {
        guard let s = hint.warpFocusURL, let url = URL(string: s) else {
            fail("Warp jump missing _warp_focus_url; degrading to activate")
            activate(bundleID: "dev.warp.Warp-Stable")
            return
        }
        if !NSWorkspace.shared.open(url) {
            fail("failed to open Warp focus URL \(s)")
            activate(bundleID: "dev.warp.Warp-Stable")
        }
    }

    /// Ghostty real focus: AppleScript match by tty (preferred) or working directory, then `focus`.
    /// Requires Automation permission for Ghostty. AX used only to raise the app if scripting fails.
    private static func jumpGhostty(hint: TerminalHint, cwd: String?) {
        let tty = hint.tty
        if tty == nil && (cwd == nil || cwd?.isEmpty == true) {
            fail("Ghostty jump has no _tty or cwd to match; cannot honor surface focus")
            activate(bundleID: "com.mitchellh.ghostty")
            return
        }

        var script = """
        tell application "Ghostty"
          set matches to {}
        """
        if let tty, !tty.isEmpty {
            let escaped = appleScriptEscape(tty)
            let short = appleScriptEscape(tty.replacingOccurrences(of: "/dev/", with: ""))
            script += """

          set matches to every terminal whose tty is "\(escaped)"
          if (count of matches) = 0 then
            set matches to every terminal whose tty contains "\(short)"
          end if
        """
        }
        if let cwd, !cwd.isEmpty {
            let escaped = appleScriptEscape(cwd)
            script += """

          if (count of matches) = 0 then
            set matches to every terminal whose working directory is "\(escaped)"
          end if
          if (count of matches) = 0 then
            set matches to every terminal whose working directory contains "\(escaped)"
          end if
        """
        }
        script += """

          if (count of matches) = 0 then
            error "Bezel: no Ghostty terminal matched tty/cwd"
          end if
          focus item 1 of matches
        end tell
        """

        if runAppleScript(script) {
            return
        }

        fail("Ghostty AppleScript focus failed (need Automation for Ghostty; tty=\(tty ?? "nil") cwd=\(cwd ?? "nil"))")
        _ = requireAccessibility(for: "raise Ghostty after AppleScript miss")
        // Activate is a last-resort raise only; surface focus already failed loudly above.
        activate(bundleID: "com.mitchellh.ghostty")
    }

    private static func jumpTerminalTTY(hint: TerminalHint) {
        guard let tty = hint.tty, !tty.isEmpty else {
            fail("Terminal.app jump requires _tty")
            activate(bundleID: "com.apple.Terminal")
            return
        }

        // Terminal.app scripting uses Automation; AX helps when TCC blocks Apple Events.
        if !AXIsProcessTrusted() {
            NSLog("Bezel Jump: Accessibility not trusted — Terminal.app tab select may fail. Enable in System Settings → Privacy & Security → Accessibility.")
        }

        let needle = appleScriptEscape(tty.replacingOccurrences(of: "/dev/", with: ""))
        let full = appleScriptEscape(tty)
        let script = """
        tell application "Terminal"
          activate
          repeat with w in windows
            repeat with t in tabs of w
              set tabTTY to tty of t as text
              if tabTTY is "\(full)" or tabTTY contains "\(needle)" then
                set frontmost of w to true
                set selected of t to true
                return
              end if
            end repeat
          end repeat
          error "Bezel: no Terminal.app tab for tty \(full)"
        end tell
        """
        if !runAppleScript(script) {
            fail("Terminal.app tty tab select failed for \(tty)")
            activate(bundleID: "com.apple.Terminal")
        }
    }

    private static func jumpKitty(hint: TerminalHint) {
        guard let windowID = hint.kittyWindow, !windowID.isEmpty else {
            fail("kitty jump missing _kitty_window / KITTY_WINDOW_ID; degrading to activate")
            activate(bundleID: "net.kovidgoyal.kitty")
            return
        }
        if runProcess(
            launchPath: "/usr/bin/env",
            arguments: ["kitty", "@", "focus-window", "--match", "id:\(windowID)"]
        ) {
            return
        }
        fail("kitty @ focus-window failed for id=\(windowID) (is remote control enabled?)")
        activate(bundleID: "net.kovidgoyal.kitty")
    }


    private static func jumpTmuxThenHost(hint: TerminalHint, session: Session) {
        selectTmuxPane(hint: hint)
        let hostStrategy = TerminalJumpPlan.hostPlan(for: hint)
        if hostStrategy == .tmuxThenHost || hostStrategy == .unsupported {
            // Should not happen after hostPlan strips tmux; still fail loudly.
            fail("tmuxThenHost could not resolve a host strategy (term=\(hint.termProgram ?? "nil"))")
            activate(bundleID: hint.bundleID ?? bundleIDGuess(for: hint))
            return
        }
        execute(strategy: hostStrategy, hint: hint, session: session)
    }

    private static func selectTmuxPane(hint: TerminalHint) {
        guard let pane = hint.tmuxPane, !pane.isEmpty else {
            if hint.tmux != nil {
                NSLog("Bezel Jump: TMUX set but TMUX_PANE missing; skipping select-pane")
            }
            return
        }

        var args = ["select-pane", "-t", pane]
        if let tmux = hint.tmux, let socket = tmux.split(separator: ",", maxSplits: 1).first, !socket.isEmpty {
            args = ["-S", String(socket), "select-pane", "-t", pane]
        }

        if !runProcess(launchPath: "/usr/bin/tmux", arguments: args) {
            // Fallback: let local tmux client resolve via env
            var env = ProcessInfo.processInfo.environment
            if let tmux = hint.tmux { env["TMUX"] = tmux }
            env["TMUX_PANE"] = pane
            if !runProcess(launchPath: "/usr/bin/tmux", arguments: ["select-pane", "-t", pane], environment: env) {
                fail("tmux select-pane -t \(pane) failed")
            }
        }
    }

    // MARK: - Helpers

    private static func activate(bundleID: String?) {
        guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            if let bundleID {
                NSLog("Bezel Jump: activate failed — app not found for bundle %@", bundleID)
            } else {
                NSLog("Bezel Jump: activate failed — no bundle ID")
            }
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    @discardableResult
    private static func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            NSLog("Bezel Jump: could not create NSAppleScript")
            return false
        }
        _ = script.executeAndReturnError(&error)
        if let error {
            NSLog("Bezel Jump: AppleScript error: %@", error)
            return false
        }
        return true
    }

    @discardableResult
    private static func runProcess(
        launchPath: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            NSLog("Bezel Jump: process %@ %@ failed: %@", launchPath, arguments.joined(separator: " "), "\(error)")
            return false
        }
    }

    private static func requireAccessibility(for operation: String) -> Bool {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            NSLog(
                "Bezel Jump: Accessibility not granted; cannot %@. Enable in System Settings → Privacy & Security → Accessibility.",
                operation
            )
        }
        return trusted
    }

    private static func fail(_ message: String) {
        NSLog("Bezel Jump: %@", message)
    }

    private static func appleScriptEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func bundleIDGuess(for hint: TerminalHint) -> String? {
        let program = (hint.termProgram ?? "").lowercased()
        if program.contains("iterm") { return "com.googlecode.iterm2" }
        if program.contains("ghostty") { return "com.mitchellh.ghostty" }
        if program.contains("apple_terminal") || program == "terminal" { return "com.apple.Terminal" }
        if program.contains("warp") { return "dev.warp.Warp-Stable" }
        if program.contains("kitty") { return "net.kovidgoyal.kitty" }
        if program.contains("wezterm") { return "com.github.wez.wezterm" }
        if program.contains("cursor") { return "com.todesktop.230313mzl4w4u92" }
        return hint.bundleID
    }
}
