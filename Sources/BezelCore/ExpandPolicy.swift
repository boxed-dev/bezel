import Foundation

/// Notch expand/collapse policy — pure, no UI imports.
public enum ExpandAction: Equatable, Sendable {
    case expand
    case compact
    case noop
}

public enum ExpandPolicy {
    /// Observed transition since the last watcher tick.
    public struct Transition: Equatable, Sendable {
        public var attentionGained: Bool
        public var attentionCleared: Bool
        public var activeCountIncreased: Bool
        public var isSessionStart: Bool
        public var isHovering: Bool

        public init(
            attentionGained: Bool = false,
            attentionCleared: Bool = false,
            activeCountIncreased: Bool = false,
            isSessionStart: Bool = false,
            isHovering: Bool = false
        ) {
            self.attentionGained = attentionGained
            self.attentionCleared = attentionCleared
            self.activeCountIncreased = activeCountIncreased
            self.isSessionStart = isSessionStart
            self.isHovering = isHovering
        }
    }

    /// Karpathy quiet defaults: no brief peek on SessionStart; no expand on active-count alone.
    public static func evaluate(_ transition: Transition) -> ExpandAction {
        if transition.attentionGained {
            return .expand
        }
        if transition.attentionCleared && !transition.isHovering {
            return .compact
        }
        if transition.isSessionStart {
            return .noop
        }
        if transition.activeCountIncreased {
            return .noop
        }
        return .noop
    }
}
