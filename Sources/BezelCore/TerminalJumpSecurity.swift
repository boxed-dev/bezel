import Foundation

/// Pure helpers for TerminalJumper: AppleScript escaping, Warp URL allowlist, tmux -S path checks.
public enum TerminalJumpSecurity {
    /// Escape a value for interpolation into an AppleScript double-quoted string.
    /// Escapes `\`, `"`, and C0/C1 controls (newlines, CR, tab, null, etc.) so they cannot
    /// break out of the literal or confuse the script parser.
    public static func appleScriptEscape(_ value: String) -> String {
        var out = String()
        out.reserveCapacity(value.utf8.count + 8)
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x5C: // \
                out += "\\\\"
            case 0x22: // "
                out += "\\\""
            case 0x0A:
                out += "\\n"
            case 0x0D:
                out += "\\r"
            case 0x09:
                out += "\\t"
            case 0x08:
                out += "\\b"
            case 0x0C:
                out += "\\f"
            case 0x00..<0x20, 0x7F...0x9F:
                // Other controls: hex form keeps source single-line and non-executable.
                out += String(format: "\\x%02X", scalar.value)
            default:
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// Schemes permitted for Warp focus deep links before `NSWorkspace.open`.
    public static let allowedWarpURLSchemes: Set<String> = ["warp", "https"]

    /// Returns a URL only when the scheme is allowlisted (`warp`, `https`).
    public static func validatedWarpFocusURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("\0"),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              allowedWarpURLSchemes.contains(scheme)
        else {
            return nil
        }
        return url
    }

    /// Socket path from `TMUX` env (`path,pid,pane`) for `tmux -S`.
    /// Rejects empty / control-contaminated paths (null, newline, CR).
    public static func validatedTmuxSocketPath(fromTMUXEnv tmux: String) -> String? {
        guard let first = tmux.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first else {
            return nil
        }
        let socket = String(first)
        guard !socket.isEmpty, isSafePathArgument(socket) else {
            return nil
        }
        return socket
    }

    /// Reject null bytes / newlines / CR in path-like process arguments.
    public static func isSafePathArgument(_ path: String) -> Bool {
        !path.isEmpty
            && !path.contains("\0")
            && !path.contains("\n")
            && !path.contains("\r")
    }
}
