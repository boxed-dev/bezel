import Foundation

public enum NotchSurface: Sendable, Equatable {
    case quiet
    case sessionList
    case approval
    case question
    case planReview
}

public enum NotchSurfaceMapper {
    /// Map from the decision-queue head.
    public static func map(sessionCount: Int, headKind: AttentionKind?) -> NotchSurface {
        switch headKind {
        case .planReview: return .planReview
        case .permission: return .approval
        case .question: return .question
        case nil:
            if sessionCount == 0 { return .quiet }
            return .sessionList
        }
    }
}
