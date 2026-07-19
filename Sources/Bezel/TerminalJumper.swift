import AppKit
import ApplicationServices
import Foundation
import BezelCore

/// Focuses the terminal/IDE surface for a session — tab/pane, not just the app.
enum TerminalJumper {
    static func jump(session: Session) {
        let hint = session.terminal ?? TerminalHint()
        NSLog(
            "Bezel Jump: session=%@ strategy prep term=%@ iterm=%@ tty=%@ tmuxPane=%@ cwd=%@",
            session.id.rawValue,
            hint.termProgram ?? "nil",
            hint.itermSession ?? "nil",
            hint.tty ?? "nil",
            hint.tmuxPane ?? "nil",
            session.cwd ?? "nil"
        )
        let strategy = TerminalJumpPlan.plan(for: hint)
        NSLog("Bezel Jump: strategy=%@", strategy.rawValue)
        execute(strategy: strategy, hint: hint, session: session)
    }

    private static func execute(strategy: TerminalJumpStrategy, hint: TerminalHint, session: Session) {
        switch strategy {
        case .itermReveal:
            _ = jumpITerm(hint: hint)
        case .warpURL:
            jumpWarp(hint: hint)
        case .ghosttyFocus:
            _ = jumpGhostty(hint: hint, cwd: session.cwd)
        case .terminalTTY:
            _ = jumpTerminalTTY(hint: hint)
        case .kittyWindow:
            jumpKitty(hint: hint)
        case .tmuxThenHost:
            jumpTmuxThenHost(hint: hint, session: session)
        case .ttyHunt:
            jumpTTYHunt(hint: hint, cwd: session.cwd)
        case .activateOnly:
            activate(bundleID: hint.bundleID ?? bundleIDGuess(for: hint))
        case .unsupported:
            if let tty = hint.tty, !tty.isEmpty {
                jumpTTYHunt(hint: hint, cwd: session.cwd)
            } else {
                fail("unsupported — no TERM_PROGRAM / bundle / tty / session hints")
            }
        }
    }

    @discardableResult
    private static func jumpITerm(hint: TerminalHint) -> Bool {
        let sessionID = hint.itermSession
        let tty = hint.tty

        if (sessionID == nil || sessionID?.isEmpty == true) && (tty == nil || tty?.isEmpty == true) {
            fail("iTerm jump needs ITERM_SESSION_ID or tty")
            degradeActivate(bundleID: "com.googlecode.iterm2", reason: "missing iTerm session id/tty")
            return false
        }

        if let id = sessionID, !id.isEmpty {
            var allowed = CharacterSet.urlQueryAllowed
            allowed.remove(charactersIn: "&+")
            let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
            let urlEscaped = TerminalJumpSecurity.appleScriptEscape(
                "iterm2:///reveal?sessionid=\(encoded)"
            )
            let reveal = """
            tell application "iTerm"
              activate
              try
                open location "\(urlEscaped)"
              end try
            end tell
            """
            if runAppleScript(reveal, automationTarget: "iTerm") == .success {
                if selectITermSession(sessionID: id, tty: tty) {
                    return true
                }
                NSLog("Bezel Jump: iTerm reveal URL opened for %@", id)
                return true
            }

            if let url = URL(string: "iterm2:///reveal?sessionid=\(encoded)"),
               NSWorkspace.shared.open(url)
            {
                _ = selectITermSession(sessionID: id, tty: tty)
                NSLog("Bezel Jump: iTerm reveal via NSWorkspace for %@", id)
                return true
            }
        }

        if selectITermSession(sessionID: sessionID, tty: tty) {
            return true
        }

        fail(
            "iTerm tab select FAILED (session=\(sessionID ?? "nil") tty=\(tty ?? "nil")) — enable Automation for Bezel→iTerm"
        )
        degradeActivate(bundleID: "com.googlecode.iterm2", reason: "iTerm select failed")
        return false
    }

    @discardableResult
    private static func selectITermSession(sessionID: String?, tty: String?) -> Bool {
        let idEsc = sessionID.map(TerminalJumpSecurity.appleScriptEscape)
        let ttyFull = tty.map(TerminalJumpSecurity.appleScriptEscape)
        let ttyShort = tty.map {
            TerminalJumpSecurity.appleScriptEscape($0.replacingOccurrences(of: "/dev/", with: ""))
        }

        var matchParts: [String] = []
        if let idEsc {
            matchParts.append("""
                  set sid to ""
                  try
                    set sid to unique id of s as text
                  end try
                  if sid is "" then
                    try
                      set sid to id of s as text
                    end try
                  end if
                  if sid is "\(idEsc)" or sid ends with "\(idEsc)" then set matched to true
            """)
            if let sessionID {
                let parts = sessionID.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    let guid = TerminalJumpSecurity.appleScriptEscape(String(parts[1]))
                    matchParts.append("""
                  if sid contains "\(guid)" then set matched to true
            """)
                }
            }
        }
        if let ttyFull, let ttyShort {
            matchParts.append("""
                  set stty to ""
                  try
                    set stty to tty of s as text
                  end try
                  if stty is "\(ttyFull)" or stty contains "\(ttyShort)" then set matched to true
            """)
        }
        guard !matchParts.isEmpty else { return false }

        let body = matchParts.joined(separator: "\n")
        for appName in ["iTerm", "iTerm2"] {
            let script = """
            tell application "\(appName)"
              activate
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with s in sessions of t
                    set matched to false
            \(body)
                    if matched then
                      select t
                      select s
                      return "ok"
                    end if
                  end repeat
                end repeat
              end repeat
              error "Bezel: no iTerm session matched"
            end tell
            """
            if runAppleScript(script, automationTarget: appName) == .success {
                return true
            }
        }
        return false
    }

    private static func jumpWarp(hint: TerminalHint) {
        guard let s = hint.warpFocusURL, !s.isEmpty else {
            fail("Warp jump missing _warp_focus_url; degrading to activate")
            degradeActivate(bundleID: "dev.warp.Warp-Stable", reason: "missing Warp focus URL")
            return
        }
        guard let url = TerminalJumpSecurity.validatedWarpFocusURL(s) else {
            fail("Warp focus URL rejected: \(s)")
            degradeActivate(bundleID: "dev.warp.Warp-Stable", reason: "Warp URL failed allowlist")
            return
        }
        if !NSWorkspace.shared.open(url) {
            fail("failed to open Warp focus URL \(s)")
            degradeActivate(bundleID: "dev.warp.Warp-Stable", reason: "NSWorkspace.open Warp URL failed")
        }
    }

    @discardableResult
    private static func jumpGhostty(hint: TerminalHint, cwd: String?) -> Bool {
        let tty = hint.tty
        if tty == nil && (cwd == nil || cwd?.isEmpty == true) {
            fail("Ghostty jump has no _tty or cwd")
            degradeActivate(bundleID: "com.mitchellh.ghostty", reason: "no Ghostty tty/cwd")
            return false
        }

        var script = """
        tell application "Ghostty"
          activate
          set matches to {}
        """
        if let tty, !tty.isEmpty {
            let escaped = TerminalJumpSecurity.appleScriptEscape(tty)
            let short = TerminalJumpSecurity.appleScriptEscape(tty.replacingOccurrences(of: "/dev/", with: ""))
            script += """

          set matches to every terminal whose tty is "\(escaped)"
          if (count of matches) = 0 then
            set matches to every terminal whose tty contains "\(short)"
          end if
        """
        }
        if let cwd, !cwd.isEmpty {
            let escaped = TerminalJumpSecurity.appleScriptEscape(cwd)
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

        if runAppleScript(script, automationTarget: "Ghostty") == .success {
            return true
        }
        fail("Ghostty focus FAILED — enable Automation Bezel→Ghostty (tty=\(tty ?? "nil"))")
        degradeActivate(bundleID: "com.mitchellh.ghostty", reason: "Ghostty AppleScript focus failed")
        return false
    }

    @discardableResult
    private static func jumpTerminalTTY(hint: TerminalHint) -> Bool {
        guard let tty = hint.tty, !tty.isEmpty else {
            fail("Terminal.app jump requires _tty")
            degradeActivate(bundleID: "com.apple.Terminal", reason: "missing Terminal.app tty")
            return false
        }

        let needle = TerminalJumpSecurity.appleScriptEscape(tty.replacingOccurrences(of: "/dev/", with: ""))
        let full = TerminalJumpSecurity.appleScriptEscape(tty)
        let script = """
        tell application "Terminal"
          activate
          repeat with w in windows
            repeat with t in tabs of w
              set tabTTY to tty of t as text
              if tabTTY is "\(full)" or tabTTY contains "\(needle)" then
                set frontmost of w to true
                set selected of t to true
                return "ok"
              end if
            end repeat
          end repeat
          error "Bezel: no Terminal.app tab for tty \(full)"
        end tell
        """
        if runAppleScript(script, automationTarget: "Terminal") == .success {
            return true
        }
        fail("Terminal.app tty tab select FAILED for \(tty)")
        degradeActivate(bundleID: "com.apple.Terminal", reason: "Terminal.app AppleScript failed")
        return false
    }

    private static func jumpTTYHunt(hint: TerminalHint, cwd: String?) {
        guard let tty = hint.tty, !tty.isEmpty else {
            fail("ttyHunt with no tty")
            return
        }
        NSLog("Bezel Jump: ttyHunt for %@", tty)

        if let owner = ttyOwnerBundleID(tty) {
            NSLog("Bezel Jump: tty owner bundle=%@", owner)
            if owner.contains("ghostty") {
                if jumpGhostty(hint: hint, cwd: cwd) { return }
            } else if owner.contains("iterm") {
                if jumpITerm(hint: hint) { return }
            } else if owner.contains("Terminal") || owner == "com.apple.Terminal" {
                if jumpTerminalTTY(hint: hint) { return }
            }
        }

        if jumpGhostty(hint: hint, cwd: cwd) { return }
        if jumpTerminalTTY(hint: hint) { return }
        if jumpITerm(hint: hint) { return }

        fail("ttyHunt exhausted for \(tty) — iTerm/Ghostty/Terminal only")
        if let owner = ttyOwnerBundleID(tty) {
            degradeActivate(bundleID: owner, reason: "ttyHunt failed; activating owner")
        }
    }

    private static func jumpKitty(hint: TerminalHint) {
        guard let windowID = hint.kittyWindow, !windowID.isEmpty else {
            fail("kitty jump missing window id")
            degradeActivate(bundleID: "net.kovidgoyal.kitty", reason: "missing kitty window id")
            return
        }
        if runProcess(
            launchPath: "/usr/bin/env",
            arguments: ["kitty", "@", "focus-window", "--match", "id:\(windowID)"]
        ) {
            return
        }
        fail("kitty @ focus-window failed for id=\(windowID)")
        degradeActivate(bundleID: "net.kovidgoyal.kitty", reason: "kitty focus-window failed")
    }

    private static func jumpTmuxThenHost(hint: TerminalHint, session: Session) {
        selectTmuxPane(hint: hint)
        let hostStrategy = TerminalJumpPlan.hostPlan(for: hint)
        if hostStrategy == .tmuxThenHost || hostStrategy == .unsupported {
            fail("tmuxThenHost could not resolve host strategy")
            if hint.tty != nil {
                jumpTTYHunt(hint: hint, cwd: session.cwd)
                return
            }
            degradeActivate(
                bundleID: hint.bundleID ?? bundleIDGuess(for: hint),
                reason: "tmux host strategy unresolved"
            )
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
        if !TerminalJumpSecurity.isSafePathArgument(pane) {
            fail("tmux pane id rejected")
            return
        }

        var args = ["select-pane", "-t", pane]
        if let tmux = hint.tmux {
            if let socket = TerminalJumpSecurity.validatedTmuxSocketPath(fromTMUXEnv: tmux) {
                args = ["-S", socket, "select-pane", "-t", pane]
            }
        }

        if !runProcess(launchPath: "/usr/bin/tmux", arguments: args) {
            var env = ProcessInfo.processInfo.environment
            if let tmux = hint.tmux { env["TMUX"] = tmux }
            env["TMUX_PANE"] = pane
            if !runProcess(launchPath: "/usr/bin/tmux", arguments: ["select-pane", "-t", pane], environment: env) {
                fail("tmux select-pane -t \(pane) failed")
            }
        }
    }

    private static func ttyOwnerBundleID(_ tty: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-F", "c", tty]
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
        let commands = text.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("c") else { return nil }
            return String(line.dropFirst()).lowercased()
        }
        for cmd in commands {
            if cmd.contains("ghostty") { return "com.mitchellh.ghostty" }
            if cmd.contains("iterm") { return "com.googlecode.iterm2" }
            if cmd == "terminal" || cmd.contains("terminal") { return "com.apple.Terminal" }
            if cmd.contains("warp") { return "dev.warp.Warp-Stable" }
            if cmd.contains("kitty") { return "net.kovidgoyal.kitty" }
            if cmd.contains("wezterm") { return "com.github.wez.wezterm" }
            if cmd.contains("cursor") { return "com.todesktop.230313mzl4w4u92" }
        }
        return nil
    }

    private enum AppleScriptResult: CustomStringConvertible {
        case success
        case automationDenied
        case failed

        var description: String {
            switch self {
            case .success: "success"
            case .automationDenied: "automationDenied"
            case .failed: "failed"
            }
        }
    }

    private static func degradeActivate(bundleID: String?, reason: String) {
        NSLog(
            "Bezel Jump: DEGRADE activate-only — %@ (this is NOT a successful surface jump)",
            reason
        )
        activate(bundleID: bundleID)
    }

    private static func activate(bundleID: String?) {
        guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            if let bundleID {
                NSLog("Bezel Jump: activate failed — app not found for bundle %@", bundleID)
            } else {
                NSLog("Bezel Jump: activate failed — no bundle ID")
            }
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    @discardableResult
    private static func runAppleScript(_ source: String, automationTarget: String) -> AppleScriptResult {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            NSLog("Bezel Jump: could not create NSAppleScript")
            return .failed
        }
        _ = script.executeAndReturnError(&error)
        if let error {
            NSLog("Bezel Jump: AppleScript error (%@): %@", automationTarget, error)
            if isAutomationDenied(error) {
                NSLog(
                    "Bezel Jump: Automation DENIED for %@ — enable Bezel→%@ under System Settings → Privacy & Security → Automation.",
                    automationTarget,
                    automationTarget
                )
                openAutomationSettings()
                return .automationDenied
            }
            return .failed
        }
        return .success
    }

    private static func isAutomationDenied(_ error: NSDictionary) -> Bool {
        let number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue
            ?? (error["NSAppleScriptErrorNumber"] as? NSNumber)?.intValue
        if number == -1743 || number == -1744 {
            return true
        }
        let message = (
            (error[NSAppleScript.errorMessage] as? String)
                ?? (error["NSAppleScriptErrorMessage"] as? String)
                ?? ""
        ).lowercased()
        return message.contains("not allowed")
            || message.contains("not authorized")
            || message.contains("not permitted")
            || message.contains("apple event")
    }

    private static func openAutomationSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
        ]
        for s in candidates {
            if let url = URL(string: s), NSWorkspace.shared.open(url) {
                return
            }
        }
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
            NSLog("Bezel Jump: process failed: %@", "\(error)")
            return false
        }
    }

    private static func fail(_ message: String) {
        NSLog("Bezel Jump: %@", message)
    }

    private static func bundleIDGuess(for hint: TerminalHint) -> String? {
        let program = (hint.termProgram ?? "").lowercased()
        if program.contains("iterm") { return "com.googlecode.iterm2" }
        if program.contains("ghostty") { return "com.mitchellh.ghostty" }
        if program.contains("apple_terminal") || program == "terminal" { return "com.apple.Terminal" }
        if program.contains("warp") { return "dev.warp.Warp-Stable" }
        if program.contains("kitty") { return "net.kovidgoyal.kitty" }
        if program.contains("wezterm") { return "com.github.wez.wezterm" }
        if program.contains("cursor") || program.contains("vscode") {
            return "com.todesktop.230313mzl4w4u92"
        }
        return hint.bundleID
    }
}
