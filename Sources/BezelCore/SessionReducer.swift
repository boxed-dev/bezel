import Foundation

/// Pure session phase transitions. HookServer and UI must not embed these rules.
public enum SessionReducer {
    public static func apply(session: Session, envelope: HookPayload, now: Date = Date()) -> Session {
        var next = session
        next.cwd = envelope.cwd ?? next.cwd
        next.updatedAt = now
        if let tool = envelope.toolName { next.lastTool = tool }
        if let source = envelope.source, let parsed = AgentSource(rawValue: source) {
            next.source = parsed
        }

        let event = HookEventName(raw: envelope.hookEventName)

        switch event {
        case .sessionStart:
            next.phase = .working
            if next.title == nil, let cwd = next.cwd {
                next.title = (cwd as NSString).lastPathComponent
            }
        case .sessionEnd, .stop:
            next.phase = .done
        case .preToolUse:
            if envelope.toolName == "AskUserQuestion" {
                next.phase = .waitingQuestion
            } else if envelope.toolName == "ExitPlanMode" {
                next.phase = .planReview
            } else if !isWaiting(next.phase) {
                next.phase = .working
            }
        case .postToolUse, .userPromptSubmit:
            if !isWaiting(next.phase) {
                next.phase = .working
            }
        case .permissionRequest:
            next.phase = envelope.toolName == "ExitPlanMode" ? .planReview : .waitingPermission
        case .notification:
            if envelope.question != nil {
                next.phase = .waitingQuestion
            }
        case .unknown:
            break
        }

        if envelope.routeKind == .question {
            next.phase = .waitingQuestion
        } else if envelope.routeKind == .permission, event == .permissionRequest {
            // keep permission / planReview from above
        }

        return next
    }

    public static func afterDecision(session: Session, now: Date = Date()) -> Session {
        var next = session
        next.phase = .working
        next.updatedAt = now
        return next
    }

    public static func seed(from envelope: HookPayload, now: Date = Date()) -> Session {
        let sid = SessionID(envelope.sessionID ?? UUID().uuidString)
        let source = AgentSource(rawValue: envelope.source ?? "claude") ?? .claude
        let base = Session(id: sid, source: source, phase: .idle, cwd: envelope.cwd, updatedAt: now)
        return apply(session: base, envelope: envelope, now: now)
    }

    private static func isWaiting(_ phase: SessionPhase) -> Bool {
        phase == .waitingPermission || phase == .waitingQuestion || phase == .planReview
    }
}
