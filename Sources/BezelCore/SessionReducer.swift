import Foundation

/// Pure session phase transitions. HookServer and UI must not embed these rules.
public enum SessionReducer {
    public static func apply(session: Session, envelope: HookPayload, now: Date = Date()) -> Session {
        var next = session
        next.cwd = envelope.cwd ?? next.cwd
        next.updatedAt = now
        if let tool = envelope.toolName { next.lastTool = tool }
        if let detail = envelope.toolDetail { next.lastToolDetail = detail }
        if let agent = envelope.agentType, !agent.isEmpty { next.agentType = agent }
        if let source = envelope.source, let parsed = AgentSource(rawValue: source) {
            next.source = parsed
        }
        next.title = DisplayNames.sessionTitle(
            sessionTitle: envelope.sessionTitle,
            cwd: next.cwd,
            agentType: next.agentType,
            existing: next.title
        )

        let event = HookEventName(raw: envelope.hookEventName)

        // `.done` is sticky until a fresh SessionStart — otherwise late Stop/PreToolUse
        // after SessionEnd resurrects zombie sessions in the notch.
        if next.phase == .done && event != .sessionStart && event != .sessionEnd {
            return next
        }

        switch event {
        case .sessionStart:
            next.phase = .working
        case .stop:
            // Turn finished — keep session visible (idle), not gone.
            // SessionEnd is the only true "remove from list" event.
            if !isWaiting(next.phase) {
                next.phase = .idle
            }
        case .sessionEnd:
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
            // Notification+question is a non-blocking event (Phase 1) — do not wait.
            break
        case .unknown:
            break
        }

        if envelope.routeKind == .question {
            next.phase = .waitingQuestion
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
        let sid = SessionID(envelope.sessionID ?? SessionID.unknown.rawValue)
        let source = AgentSource(rawValue: envelope.source ?? "claude") ?? .claude
        let base = Session(id: sid, source: source, phase: .idle, cwd: envelope.cwd, updatedAt: now)
        return apply(session: base, envelope: envelope, now: now)
    }

    private static func isWaiting(_ phase: SessionPhase) -> Bool {
        phase == .waitingPermission || phase == .waitingQuestion || phase == .planReview
    }
}
