import AppKit
import BezelCore

/// Builds `FrontTabHint` for SmartSuppress — probes tab-level ids only when comparison would use them.
enum FrontTabProbe {
    static func probe(bundleID: String?, sessionTerminal: TerminalHint?) -> FrontTabHint {
        guard let bundleID else { return FrontTabHint() }
        var hint = FrontTabHint(bundleID: bundleID)
        guard let session = sessionTerminal else { return hint }

        let bundle = bundleID.lowercased()
        if bundle.contains("iterm"), session.itermSession != nil {
            hint.itermSession = runAppleScript("""
            tell application "iTerm"
              try
                return unique id of current session of current window
              on error
                return ""
              end try
            end tell
            """)
        } else if bundle == "com.apple.terminal", session.tty != nil {
            hint.tty = runAppleScript("""
            tell application "Terminal"
              try
                return tty of selected tab of front window
              on error
                return ""
              end try
            end tell
            """)
        }

        return hint
    }

    private static func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        let value = result.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
