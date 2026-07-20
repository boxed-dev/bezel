import Foundation

/// Drop stale idle sessions so the notch list stays live (AgentPeek-style).
public enum IdleSessionPrune {
    /// Idle sessions older than this are removed from the HUD.
    public static let idleTTL: TimeInterval = 30 * 60

    public static func shouldRemove(session: Session, now: Date = Date()) -> Bool {
        guard session.phase == .idle else { return false }
        return now.timeIntervalSince(session.updatedAt) >= idleTTL
    }

    public static func prune(_ sessions: [Session], now: Date = Date()) -> [Session] {
        sessions.filter { !shouldRemove(session: $0, now: now) }
    }
}
