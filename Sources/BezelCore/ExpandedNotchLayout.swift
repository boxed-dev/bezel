import Foundation

/// Expanded HUD pillars — order is normative: USAGE → NEEDS YOU → SESSIONS.
public enum ExpandedSection: Sendable, Equatable {
    case usage
    case needsYou
    case sessions
}

/// Pure section planner for the expanded notch. Empty pillars are omitted.
public enum ExpandedNotchLayout {
    public static func sections(
        hasUsage: Bool,
        needsYou: Bool,
        hasSessions: Bool
    ) -> [ExpandedSection] {
        var result: [ExpandedSection] = []
        if hasUsage { result.append(.usage) }
        if needsYou { result.append(.needsYou) }
        if hasSessions { result.append(.sessions) }
        return result
    }
}
