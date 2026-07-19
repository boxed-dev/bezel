import Foundation

/// Compact notch trailing label from Claude plan usage.
public enum UsageGlance {
    /// True when compact text includes a live reset countdown suffix.
    public static func showsResetCountdown(_ snapshot: ClaudeUsageSnapshot) -> Bool {
        guard let pct = snapshot.primaryPercent, pct >= 70 else { return false }
        let window = snapshot.sevenDay ?? snapshot.fiveHour
        return window?.resetsAt != nil
    }

    /// `"38%"` or `"38% · 2h"` when primary window ≥70% and `resetsAt` is known.
    public static func compactText(_ snapshot: ClaudeUsageSnapshot, now: Date = Date()) -> String? {
        guard let pct = snapshot.primaryPercent else { return nil }
        let base = "\(pct)%"
        let window = snapshot.sevenDay ?? snapshot.fiveHour
        guard pct >= 70, let window, let resets = window.resetsAt else {
            return base
        }
        let minutes = max(0, Int(resets.timeIntervalSince(now) / 60))
        if minutes < 60 {
            return "\(base) · \(max(1, minutes))m"
        }
        let hours = minutes / 60
        if hours < 48 {
            return "\(base) · \(hours)h"
        }
        return "\(base) · \(minutes / (60 * 24))d"
    }
}
