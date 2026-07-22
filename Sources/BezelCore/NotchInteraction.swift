import Foundation

/// Pure notch click intents — AppKit/SwiftUI map these; never import AppKit here.
public enum NotchPrimaryAction: Equatable, Sendable {
    case expand
    case select(SessionID)
    case resolve
}

public enum NotchSecondaryAction: Equatable, Sendable {
    case jump(SessionID)
}

public enum NotchInteraction {
    public enum CompactTrailingContext: Equatable, Sendable {
        case usage
        case attention
        case liveCount
        case empty
    }

    /// Compact trailing (usage % / count / !) always expands in place — never jump.
    public static func compactTrailingPrimary(context: CompactTrailingContext) -> NotchPrimaryAction {
        _ = context
        return .expand
    }

    /// Compact leading attention color — expand only.
    public static func compactLeadingPrimary() -> NotchPrimaryAction {
        .expand
    }

    /// Session row single-click selects; jump is secondary only.
    public static func sessionRowPrimary(sessionID: SessionID) -> NotchPrimaryAction {
        .select(sessionID)
    }

    public static func sessionRowSecondary(sessionID: SessionID) -> NotchSecondaryAction {
        .jump(sessionID)
    }
}
