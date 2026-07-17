import Foundation
import Observation
import BezelCore

@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [Session] = []
    private(set) var pendingPermission: PendingPermission?
    private(set) var pendingQuestion: PendingQuestion?

    var activeCount: Int { sessions.filter { $0.phase != .done }.count }
    var needsAttention: Bool {
        sessions.contains {
            $0.phase == .waitingPermission || $0.phase == .waitingQuestion || $0.phase == .planReview
        }
    }

    func upsert(_ session: Session) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.insert(session, at: 0)
        }
    }

    func remove(id: SessionID) {
        sessions.removeAll { $0.id == id }
    }

    func apply(envelope: HookPayload) {
        let sid = SessionID(envelope.sessionID ?? UUID().uuidString)
        let existing = sessions.first(where: { $0.id == sid })
        let next: Session
        if let existing {
            next = SessionReducer.apply(session: existing, envelope: envelope)
        } else {
            next = SessionReducer.seed(from: envelope)
        }
        upsert(next)
    }

    func enqueuePermission(_ pending: PendingPermission) {
        pendingPermission = pending
        guard let existing = sessions.first(where: { $0.id == pending.sessionID }) else { return }
        let tool = pending.toolName ?? ""
        let json = #"{"hook_event_name":"PermissionRequest","session_id":"\#(pending.sessionID.rawValue)","tool_name":"\#(tool)"}"#
        guard let synthetic = try? HookPayload.parse(Data(json.utf8)) else { return }
        upsert(SessionReducer.apply(session: existing, envelope: synthetic))
    }

    func enqueueQuestion(_ pending: PendingQuestion) {
        pendingQuestion = pending
        guard let existing = sessions.first(where: { $0.id == pending.sessionID }) else { return }
        let json = #"{"hook_event_name":"PreToolUse","session_id":"\#(pending.sessionID.rawValue)","tool_name":"AskUserQuestion"}"#
        guard let synthetic = try? HookPayload.parse(Data(json.utf8)) else { return }
        upsert(SessionReducer.apply(session: existing, envelope: synthetic))
    }

    func resolvePermission(allow: Bool) {
        guard let pending = pendingPermission else { return }
        let data = allow ? DecisionJSON.permissionAllow() : DecisionJSON.permissionDeny()
        pending.resume(data)
        pendingPermission = nil
        if let s = sessions.first(where: { $0.id == pending.sessionID }) {
            upsert(SessionReducer.afterDecision(session: s))
        }
    }

    func resolveQuestion(questions: [[String: Any]], answers: [AskUserQuestionAnswer]) {
        guard let pending = pendingQuestion else { return }
        let data: Data
        do {
            data = try AskUserQuestionEncoder.encode(questions: questions, answers: answers)
        } catch {
            data = DecisionJSON.permissionDeny(message: "Could not encode answer")
        }
        pending.resume(data)
        pendingQuestion = nil
        if let s = sessions.first(where: { $0.id == pending.sessionID }) {
            upsert(SessionReducer.afterDecision(session: s))
        }
    }
}

struct PendingPermission: Identifiable {
    let id = UUID()
    let sessionID: SessionID
    let toolName: String?
    let summary: String
    let resume: (Data) -> Void
}

struct PendingQuestion: Identifiable {
    let id = UUID()
    let sessionID: SessionID
    let prompt: String
    let resume: (Data) -> Void
}
