import Foundation

/// Don’t auto-expand the notch when the user is already on that session’s terminal.
/// Still show compact `!` / pulse — hover always wins.
public enum SmartSuppress {
    /// - Returns: `true` if Bezel should auto-expand for attention.
    /// Blocking gates always expand — never suppress when `needsAttention`.
    public static func shouldAutoExpand(
        needsAttention: Bool,
        frontmostBundleID: String?,
        sessionTerminal: TerminalHint?
    ) -> Bool {
        shouldAutoExpand(
            needsAttention: needsAttention,
            front: FrontTabHint(bundleID: frontmostBundleID),
            sessionTerminal: sessionTerminal
        )
    }

    /// Tab-aware expand probe — uses `TabVisibility` when front hint has session/tty, else bundle heuristics.
    public static func shouldAutoExpand(
        needsAttention: Bool,
        front: FrontTabHint?,
        sessionTerminal: TerminalHint?
    ) -> Bool {
        if needsAttention { return true }

        switch TabVisibility.compare(session: sessionTerminal, front: front) {
        case .matched:
            return false
        case .mismatch:
            return true
        case .unknown:
            return shouldAutoExpand(
                frontmostBundleID: front?.bundleID,
                sessionTerminal: sessionTerminal
            )
        }
    }

    /// Non-blocking expand probe (session working noise, hover-adjacent paths).
    public static func shouldAutoExpand(
        frontmostBundleID: String?,
        sessionTerminal: TerminalHint?
    ) -> Bool {
        guard let front = normalized(frontmostBundleID), !front.isEmpty else {
            return true
        }
        guard let hint = sessionTerminal else {
            return true
        }

        if let bundle = normalized(hint.bundleID), bundle == front {
            return false
        }

        let program = (hint.termProgram ?? "").lowercased()

        if isITerm(front), isITermHint(program: program, hint: hint) { return false }
        if isGhostty(front), program.contains("ghostty") || front.contains("ghostty") { return false }
        if isTerminal(front), program.contains("apple_terminal") || program == "terminal" { return false }
        if isWarp(front), program.contains("warp") || hint.warpFocusURL != nil { return false }
        if isKitty(front), program.contains("kitty") || hint.kittyWindow != nil { return false }
        if isCursor(front), program.contains("cursor") || program.contains("vscode") { return false }

        return true
    }

    private static func normalized(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isITerm(_ bundle: String) -> Bool {
        bundle.contains("iterm")
    }

    private static func isITermHint(program: String, hint: TerminalHint) -> Bool {
        program.contains("iterm") || hint.itermSession != nil
    }

    private static func isGhostty(_ bundle: String) -> Bool {
        bundle.contains("ghostty")
    }

    private static func isTerminal(_ bundle: String) -> Bool {
        bundle == "com.apple.terminal"
    }

    private static func isWarp(_ bundle: String) -> Bool {
        bundle.contains("warp")
    }

    private static func isKitty(_ bundle: String) -> Bool {
        bundle.contains("kitty")
    }

    private static func isCursor(_ bundle: String) -> Bool {
        bundle.contains("cursor") || bundle.contains("todesktop")
    }
}
