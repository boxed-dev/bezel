import Foundation

public enum AgentBoardColumn: String, Sendable, CaseIterable {
    case active
    case attention
    case finished
}

/// Maps sessions into Agent Board columns (in-notch Kanban).
public enum AgentBoardMapper {
    public static func column(for session: Session, attentionSessionIDs: Set<SessionID>) -> AgentBoardColumn {
        if attentionSessionIDs.contains(session.id) {
            return .attention
        }
        switch session.phase {
        case .done, .idle:
            return .finished
        case .working, .waitingPermission, .waitingQuestion, .planReview, .error:
            return .active
        }
    }

    public static func partition(
        sessions: [Session],
        attentionSessionIDs: Set<SessionID>,
        finishedWindow: TimeInterval = 3600,
        now: Date = Date()
    ) -> [AgentBoardColumn: [Session]] {
        var buckets: [AgentBoardColumn: [Session]] = [
            .active: [],
            .attention: [],
            .finished: [],
        ]
        for session in sessions {
            let col = column(for: session, attentionSessionIDs: attentionSessionIDs)
            if col == .finished {
                if now.timeIntervalSince(session.updatedAt) <= finishedWindow {
                    buckets[.finished, default: []].append(session)
                }
                continue
            }
            buckets[col, default: []].append(session)
        }
        for key in AgentBoardColumn.allCases {
            buckets[key]?.sort { $0.updatedAt > $1.updatedAt }
        }
        return buckets
    }
}
