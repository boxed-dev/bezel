import Foundation

/// Policy for when a hook should create a visible session in the notch.
///
/// Claude often skips or races `SessionStart` (resume, hook timeout, Bezel not up yet).
/// Presence events (`UserPromptSubmit`, `PostToolUse`, …) must still surface the session
/// immediately — otherwise the compact trailing count stays empty until a permission prompt.
///
/// After `SessionEnd`, late stray events must not resurrect zombies (tombstones).
public enum SessionPresence {
    /// Ignore non-start events for this long after SessionEnd.
    public static let tombstoneTTL: TimeInterval = 90

    /// Whether an inbound hook should create a brand-new session row.
    public static func shouldCreateSession(
        event: HookEventName,
        routeKind: RouteKind,
        isTombstoned: Bool
    ) -> Bool {
        // Fresh SessionStart always wins — clears tombstone at the call site.
        if event == .sessionStart {
            return true
        }
        if isTombstoned {
            return false
        }
        // Blocking ingress seeds when not tombstoned (see SessionStore.syncSessionPhase).
        if routeKind != .event {
            return true
        }
        switch event {
        case .userPromptSubmit, .postToolUse, .preToolUse, .sessionStart:
            return true
        case .notification:
            // Notification chatter must not spawn rows; may still update existing sessions.
            return false
        case .stop, .sessionEnd, .permissionRequest, .unknown:
            return false
        }
    }

    /// True when `endedAt` is still within the tombstone window.
    public static func isTombstoned(endedAt: Date?, now: Date = Date(), ttl: TimeInterval = tombstoneTTL) -> Bool {
        guard let endedAt else { return false }
        return now.timeIntervalSince(endedAt) < ttl
    }
}
