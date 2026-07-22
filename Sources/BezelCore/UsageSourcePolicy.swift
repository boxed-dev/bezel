import Foundation

/// Chooses which on-disk usage snapshot wins.
/// Bezel’s Claude cache is primary; vibe-island is an explicit last-resort fallback only.
public enum UsageSourcePolicy {
    /// Prefer Bezel (`statusline-cache` / OAuth-persisted) whenever present.
    /// Use vibe-island cache only when the Bezel snapshot is missing.
    public static func selectDiskSnapshot(
        bezel: ClaudeUsageSnapshot?,
        vibeIsland: ClaudeUsageSnapshot?
    ) -> ClaudeUsageSnapshot? {
        if let bezel { return bezel }
        return vibeIsland
    }
}
