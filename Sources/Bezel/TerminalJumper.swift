import AppKit
import ApplicationServices
import Foundation
import Darwin
import BezelCore

/// Focuses the terminal/IDE surface for a session — tab/pane, not just the app.
///
/// Precision order (see `TerminalJumpMatch`):
/// tty → iTerm session id → tmux pane → TERM_SESSION_ID/kitty/warp → agent PID →
/// unique cwd → activate-only last resort.
/// Never picks arbitrarily among same-cwd sessions.
enum TerminalJumper {
    static func jump(session: Session) {
        let hint = session.terminal ?? TerminalHint()
        let strongest = TerminalJumpMatch.strongestIdentity(for: hint)?.rawValue ?? "none"
        NSLog(
            "Bezel Jump: session=%@ identity=%@ term=%@ iterm=%@ tty=%@ tmuxPane=%@ pid=%@ cwd=%@",
            session.id.rawValue,
            strongest,
            hint.termProgram ?? "nil",
            hint.itermSession ?? "nil",
            hint.tty ?? "nil",
            hint.tmuxPane ?? "nil",
            hint.agentPID.map(String.init) ?? "nil",
            session.cwd ?? "nil"
        )
        let strategy = TerminalJumpPlan.plan(for: hint, cwd: session.cwd)
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
        case .ideWorkspace:
            jumpIDEWorkspace(hint: hint, cwd: session.cwd)
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

    // MARK: - iTerm2

    private static let itermFocusRetries = 4
    private static let itermFocusRetryDelay: TimeInterval = 0.2

    @discardableResult
    private static func jumpITerm(hint: TerminalHint) -> Bool {
        // Always normalize — legacy sessions may still hold w0t0p0:GUID.
        let sessionID = TerminalHintExtractor.normalizeITermSessionID(hint.itermSession)
        let tty = hint.tty

        if (sessionID == nil || sessionID?.isEmpty == true) && (tty == nil || tty?.isEmpty == true) {
            fail("iTerm jump needs ITERM_SESSION_ID or tty")
            degradeActivate(bundleID: "com.googlecode.iterm2", reason: "missing iTerm session id/tty")
            return false
        }

        // CC Status Bar: short retries absorb slow iTerm tab updates.
        for attempt in 0..<itermFocusRetries {
            for key in TerminalJumpMatch.itermSelectKeys(for: hint) {
                switch key {
                case .tty:
                    if let tty, selectITermSession(sessionID: nil, tty: tty) {
                        NSLog("Bezel Jump: iTerm selected by tty %@", tty)
                        return true
                    }
                case .itermSession:
                    if let sessionID, selectITermSession(sessionID: sessionID, tty: nil) {
                        NSLog("Bezel Jump: iTerm selected by unique id %@", sessionID)
                        return true
                    }
                }
            }
            if attempt < itermFocusRetries - 1 {
                Thread.sleep(forTimeInterval: itermFocusRetryDelay)
            }
        }

        // Reveal URL last; GUIDs work with iterm2:///reveal. Never claim success
        // unless select confirms.
        if let id = sessionID, !id.isEmpty {
            if openITermReveal(sessionID: id),
               selectITermSession(sessionID: id, tty: tty)
            {
                return true
            }
            NSLog("Bezel Jump: iTerm reveal opened but select unconfirmed for %@", id)
        }

        fail(
            "iTerm tab select FAILED (session=\(sessionID ?? "nil") tty=\(tty ?? "nil")) — enable Automation for Bezel→iTerm"
        )
        degradeActivate(bundleID: "com.googlecode.iterm2", reason: "iTerm select failed")
        return false
    }

    private static func openITermReveal(sessionID: String) -> Bool {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+")
        let encoded = sessionID.addingPercentEncoding(withAllowedCharacters: allowed) ?? sessionID
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
            return true
        }
        if let url = URL(string: "iterm2:///reveal?sessionid=\(encoded)"),
           NSWorkspace.shared.open(url)
        {
            return true
        }
        return false
    }

    /// CodeIsland / CC Status Bar style: exact `unique ID` / exact tty, then
    /// deminiaturize + select session → tab → window → activate.
    @discardableResult
    private static func selectITermSession(sessionID: String?, tty: String?) -> Bool {
        let guid = TerminalHintExtractor.normalizeITermSessionID(sessionID)
            .map(TerminalJumpSecurity.appleScriptEscape)
        let fullTTY: String?
        if let tty, !tty.isEmpty {
            fullTTY = tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
        } else {
            fullTTY = nil
        }
        let ttyEsc = fullTTY.map(TerminalJumpSecurity.appleScriptEscape)

        guard guid != nil || ttyEsc != nil else { return false }

        var matchBody = "set matched to false\n"
        if let guid {
            matchBody += """
                              try
                                if unique ID of s is "\(guid)" then set matched to true
                              end try
                              if not matched then
                                try
                                  if (id of s as text) is "\(guid)" then set matched to true
                                end try
                              end if
            """
        }
        if let ttyEsc {
            matchBody += """
                              if not matched then
                                try
                                  if tty of s is "\(ttyEsc)" then set matched to true
                                end try
                              end if
            """
        }

        for appName in ["iTerm2", "iTerm"] {
            let script = """
            tell application "\(appName)"
              if not (it is running) then error "Bezel: iTerm not running"
              activate
              repeat with w in windows
                try
                  if miniaturized of w then set miniaturized of w to false
                end try
                repeat with t in tabs of w
                  repeat with s in sessions of t
            \(matchBody)
                    if matched then
                      try
                        select w
                      end try
                      select t
                      select s
                      try
                        tell s to select
                      end try
                      set index of w to 1
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

    // MARK: - Warp

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

    // MARK: - Ghostty

    /// Ghostty does not reliably expose `tty` via AppleScript (CodeIsland note).
    /// Precision path: OSC-stamp a unique title token onto the TTY, then AX-press
    /// the matching tab (CC Status Bar). Fallbacks: AppleScript pid / unique cwd.
    @discardableResult
    private static func jumpGhostty(hint: TerminalHint, cwd: String?) -> Bool {
        let tty = hint.tty
        let agentPID = hint.agentPID
        let hasTTY = tty.map { !$0.isEmpty } ?? false
        let hasPID = (agentPID ?? 0) > 0
        let hasCWD = cwd.map { !$0.isEmpty } ?? false

        if !hasTTY && !hasPID && !hasCWD {
            fail("Ghostty jump has no _tty, agent PID, or cwd")
            degradeActivate(bundleID: "com.mitchellh.ghostty", reason: "no Ghostty tty/pid/cwd")
            return false
        }

        // 1) CCSB-style: stamp title token on tty, AX-press tab (most reliable).
        if let tty, !tty.isEmpty {
            if focusGhosttyByTTYToken(tty) {
                return true
            }
            // Optional AppleScript tty property (future Ghostty builds).
            if focusGhosttyByTTYProperty(tty) {
                return true
            }
            NSLog("Bezel Jump: Ghostty tty-token/AX failed for %@", tty)
        }

        // 2) Agent PID when Ghostty exposes foreground pid.
        if let agentPID, agentPID > 0, focusGhosttyByPID(agentPID) {
            return true
        }

        // 3) Cwd only when exactly one match — never pick item 1 of many.
        if let cwd, !cwd.isEmpty {
            let count = countGhosttyCwdMatches(cwd)
            guard TerminalJumpMatch.allowCwdFallback(matchCount: count) else {
                if count > 1 {
                    fail("Ghostty cwd AMBIGUOUS (\(count) matches for \(cwd)) — refusing arbitrary pick")
                } else {
                    fail("Ghostty cwd unmatched for \(cwd)")
                }
                degradeActivate(bundleID: "com.mitchellh.ghostty", reason: "Ghostty cwd not unique")
                return false
            }
            if focusGhosttyByCwd(cwd) {
                return true
            }
        }

        fail("Ghostty focus FAILED — enable Automation + Accessibility for Bezel→Ghostty")
        degradeActivate(bundleID: "com.mitchellh.ghostty", reason: "Ghostty focus failed")
        return false
    }

    /// Write OSC 0 title with `[BEZEL:ttysNNN]`, wait for AX refresh, press tab.
    private static func focusGhosttyByTTYToken(_ tty: String) -> Bool {
        let token = TerminalHintExtractor.bezelTTYToken(for: tty)
        let title = "Bezel \(token)"
        guard stampTTYTitle(tty: tty, title: title) else {
            NSLog("Bezel Jump: could not write OSC title to %@", tty)
            return false
        }
        usleep(150_000) // 150ms — CC Status Bar wait for title/AX refresh
        if focusGhosttyTabByTitleToken(token) {
            NSLog("Bezel Jump: Ghostty AX tab pressed for %@", token)
            return true
        }
        return false
    }

    private static func stampTTYTitle(tty: String, title: String) -> Bool {
        let path = tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
        let seq = "\u{001B}]0;\(title)\u{0007}"
        let fd = open(path, O_WRONLY | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        return seq.withCString { ptr in
            write(fd, ptr, strlen(ptr)) >= 0
        }
    }

    private static func focusGhosttyTabByTitleToken(_ token: String) -> Bool {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.mitchellh.ghostty")
        guard let app = apps.first else { return false }
        if app.isHidden { app.unhide() }
        // Avoid NSRunningApplication.activate — triggers Ghostty quick terminal.
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }

        // Swift 6: avoid shared mutable CFStringRef concurrency diagnostic.
        guard AXIsProcessTrusted() else {
            let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
            NSLog("Bezel Jump: Accessibility DENIED — needed for Ghostty tab AXPress")
            return false
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement]
        else {
            return false
        }

        for window in windows {
            if let tab = findAXTab(in: window, titleContains: token) {
                let press = AXUIElementPerformAction(tab, kAXPressAction as CFString)
                if press == .success {
                    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                    return true
                }
            }
        }
        return false
    }

    private static func findAXTab(in element: AXUIElement, titleContains needle: String, depth: Int = 0) -> AXUIElement? {
        guard depth < 12 else { return nil }
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String,
           role == "AXRadioButton" || role == "AXButton" || role == "AXTab" || role == "AXTabGroup"
        {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String,
               title.contains(needle)
            {
                return element
            }
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else {
            return nil
        }
        for child in children {
            if let hit = findAXTab(in: child, titleContains: needle, depth: depth + 1) {
                return hit
            }
        }
        return nil
    }

    /// Legacy / future Ghostty AppleScript `tty` property — best-effort only.
    private static func focusGhosttyByTTYProperty(_ tty: String) -> Bool {
        let escaped = TerminalJumpSecurity.appleScriptEscape(tty)
        let short = TerminalJumpSecurity.appleScriptEscape(tty.replacingOccurrences(of: "/dev/", with: ""))
        let script = """
        tell application "Ghostty"
          activate
          try
            set matches to every terminal whose tty is "\(escaped)"
            if (count of matches) = 0 then
              set matches to every terminal whose tty contains "\(short)"
            end if
            if (count of matches) = 1 then
              focus item 1 of matches
              return "ok"
            end if
          end try
          error "Bezel: Ghostty has no tty property or no unique match"
        end tell
        """
        return runAppleScript(script, automationTarget: "Ghostty") == .success
    }

    private static func focusGhosttyByPID(_ pid: Int) -> Bool {
        let script = """
        tell application "Ghostty"
          activate
          try
            set matches to every terminal whose pid is \(pid)
            if (count of matches) ≠ 1 then
              error "Bezel: Ghostty pid match count " & (count of matches)
            end if
            focus item 1 of matches
          on error errMsg
            error errMsg
          end try
        end tell
        """
        return runAppleScript(script, automationTarget: "Ghostty") == .success
    }

    private static func countGhosttyCwdMatches(_ cwd: String) -> Int {
        let escaped = TerminalJumpSecurity.appleScriptEscape(cwd)
        let script = """
        tell application "Ghostty"
          set matches to every terminal whose working directory is "\(escaped)"
          return (count of matches) as text
        end tell
        """
        guard let text = runAppleScriptReturningString(script, automationTarget: "Ghostty"),
              let count = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return 0
        }
        return count
    }

    private static func focusGhosttyByCwd(_ cwd: String) -> Bool {
        let escaped = TerminalJumpSecurity.appleScriptEscape(cwd)
        let script = """
        tell application "Ghostty"
          activate
          set matches to every terminal whose working directory is "\(escaped)"
          if (count of matches) ≠ 1 then
            error "Bezel: Ghostty cwd not unique"
          end if
          focus item 1 of matches
        end tell
        """
        return runAppleScript(script, automationTarget: "Ghostty") == .success
    }

    // MARK: - Terminal.app

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

    // MARK: - TTY hunt / kitty / tmux / IDE

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
        let hostStrategy = TerminalJumpPlan.hostPlan(for: hint, cwd: session.cwd)
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

    /// Cursor / VS Code: workspace reopen only — cannot target a specific agent chat tab.
    private static func jumpIDEWorkspace(hint: TerminalHint, cwd: String?) {
        guard let cwd, !cwd.isEmpty else {
            degradeActivate(
                bundleID: hint.bundleID ?? bundleIDGuess(for: hint),
                reason: "IDE workspace jump missing cwd"
            )
            return
        }
        guard TerminalJumpSecurity.isSafePathArgument(cwd) else {
            fail("IDE workspace path rejected")
            degradeActivate(bundleID: hint.bundleID ?? bundleIDGuess(for: hint), reason: "unsafe cwd")
            return
        }

        let program = (hint.termProgram ?? "").lowercased()
        let bundle = (hint.bundleID ?? "").lowercased()
        let isCursor = program.contains("cursor") || bundle.contains("cursor")
            || bundle.contains("todesktop")

        // Prefer CLI reopen-in-window; fall back to `open -a`.
        if isCursor {
            if runProcess(launchPath: "/usr/bin/env", arguments: ["cursor", "-r", cwd]) {
                NSLog("Bezel Jump: cursor -r %@", cwd)
                return
            }
            if runProcess(
                launchPath: "/usr/bin/open",
                arguments: ["-a", "Cursor", cwd]
            ) {
                NSLog("Bezel Jump: open -a Cursor %@", cwd)
                return
            }
        } else {
            if runProcess(launchPath: "/usr/bin/env", arguments: ["code", "-r", cwd]) {
                NSLog("Bezel Jump: code -r %@", cwd)
                return
            }
        }

        fail("IDE workspace CLI failed for \(cwd) — activating app only (no chat-tab precision)")
        degradeActivate(
            bundleID: hint.bundleID ?? bundleIDGuess(for: hint),
            reason: "IDE CLI reopen failed"
        )
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

    // MARK: - AppleScript / process helpers

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

    private static func runAppleScriptReturningString(_ source: String, automationTarget: String) -> String? {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&error)
        if let error {
            NSLog("Bezel Jump: AppleScript error (%@): %@", automationTarget, error)
            return nil
        }
        return result.stringValue
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
