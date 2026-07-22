import Foundation

/// Shared seam for applying normalized agent envelopes into session state.
///
/// Adapters (Claude hooks, Codex JSONL, OpenCode SQLite, Cursor hooks) produce
/// `HookPayload` / `Session` values; the app store calls these helpers so source
/// and phase rules stay in BezelCore.
public enum AgentEventIngester {
    /// Discovery-backed providers whose idle rows may be pruned when absent from a refresh.
    public static let discoveryPruneSources: Set<AgentSource> = [.codex, .opencode]

    /// Apply a live hook envelope onto an existing session (or seed a new one).
    public static func apply(envelope: HookPayload, existing: Session?, now: Date = Date()) -> Session {
        if let existing {
            return SessionReducer.apply(session: existing, envelope: envelope, now: now)
        }
        return SessionReducer.seed(from: envelope, now: now)
    }

    /// Merge discovery-only rows (JSONL / SQLite) without inventing live waiting phases.
    /// Existing hook-driven sessions win on phase; discovery fills gaps.
    /// Idle discovery-provider rows missing from `discovered` are pruned so home-dir
    /// history cannot accumulate forever in the SESSIONS list.
    /// Tombstoned IDs (recent SessionEnd) are never re-inserted by discovery.
    public static func mergeDiscovery(
        discovered: [Session],
        into current: [SessionID: Session],
        tombstonedIDs: Set<SessionID> = []
    ) -> [SessionID: Session] {
        var next = current
        let discoveredIDs = Set(discovered.map(\.id))

        for row in discovered {
            if tombstonedIDs.contains(row.id) { continue }
            guard let existing = next[row.id] else {
                next[row.id] = row
                continue
            }
            var merged = existing
            // Hooks own phase; discovery may fill missing place metadata.
            if merged.cwd == nil || merged.cwd?.isEmpty == true {
                merged.cwd = row.cwd
            }
            if merged.title == nil || DisplayNames.looksLikeSessionID(merged.title ?? "") {
                merged.title = row.title ?? merged.title
            }
            if merged.source == .unknown {
                merged.source = row.source
            }
            // Refresh discovery timestamps so recent presence sorts correctly.
            if merged.phase == .idle {
                merged.updatedAt = max(merged.updatedAt, row.updatedAt)
            }
            next[row.id] = merged
        }

        for (id, session) in current {
            guard discoveryPruneSources.contains(session.source) else { continue }
            guard session.phase == .idle else { continue }
            guard !discoveredIDs.contains(id) else { continue }
            next.removeValue(forKey: id)
        }
        return next
    }
}
