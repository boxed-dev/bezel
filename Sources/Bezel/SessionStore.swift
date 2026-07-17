import Foundation
import Observation
import BezelCore

@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [Session] = []
    private(set) var decisionQueue = DecisionQueue()
    private var resumes: [DecisionKey: (Data) -> Void] = [:]

    var activeCount: Int { sessions.filter { $0.phase != .done }.count }
    var needsAttention: Bool { decisionQueue.head != nil }

    /// Highest-priority / oldest decision currently needing attention.
    var attentionHead: DecisionEntry? { decisionQueue.head }

    var pendingPermission: DecisionEntry? {
        guard let head = decisionQueue.head, head.kind == .permission else { return nil }
        return head
    }

    var pendingQuestion: DecisionEntry? {
        guard let head = decisionQueue.head, head.kind == .question else { return nil }
        return head
    }

    var pendingPlanReview: DecisionEntry? {
        guard let head = decisionQueue.head, head.kind == .planReview else { return nil }
        return head
    }

    var surface: NotchSurface {
        NotchSurfaceMapper.map(
            sessionCount: sessions.filter { $0.phase != .done }.count,
            headKind: decisionQueue.head?.kind
        )
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
        let sid = SessionID(envelope.sessionID ?? SessionID.unknown.rawValue)
        let existing = sessions.first(where: { $0.id == sid })
        let next: Session
        if let existing {
            next = SessionReducer.apply(session: existing, envelope: envelope)
        } else {
            next = SessionReducer.seed(from: envelope)
        }
        var enriched = next
        if let hint = TerminalHintExtractor.fromHookJSON(envelope.rawJSON) {
            enriched.terminal = hint
        }
        upsert(enriched)
    }

    func enqueuePermission(
        key: DecisionKey,
        toolName: String?,
        summary: String,
        hookEventName: String,
        resume: @escaping (Data) -> Void
    ) {
        let entry = DecisionEntry(
            key: key,
            kind: .permission,
            toolName: toolName,
            summary: summary,
            hookEventName: hookEventName
        )
        enqueue(entry, resume: resume)
        syncSessionPhase(for: key.sessionID, kind: .permission, toolName: toolName)
    }

    func enqueueQuestion(
        key: DecisionKey,
        prompt: String,
        questions: [QuestionItem],
        hookEventName: String,
        rawQuestionsJSON: Data? = nil,
        resume: @escaping (Data) -> Void
    ) {
        let entry = DecisionEntry(
            key: key,
            kind: .question,
            toolName: "AskUserQuestion",
            summary: prompt,
            hookEventName: hookEventName,
            questions: questions,
            rawQuestionsJSON: rawQuestionsJSON,
            prompt: prompt
        )
        enqueue(entry, resume: resume)
        syncSessionPhase(for: key.sessionID, kind: .question, toolName: "AskUserQuestion")
    }

    func enqueuePlanReview(
        key: DecisionKey,
        plan: PlanContent,
        hookEventName: String,
        resume: @escaping (Data) -> Void
    ) {
        let entry = DecisionEntry(
            key: key,
            kind: .planReview,
            toolName: "ExitPlanMode",
            summary: "Review plan",
            hookEventName: hookEventName,
            planText: plan.plan,
            planFilePath: plan.planFilePath
        )
        enqueue(entry, resume: resume)
        syncSessionPhase(for: key.sessionID, kind: .planReview, toolName: "ExitPlanMode")
    }

    /// Resolve the currently displayed permission (queue head of kind `.permission`).
    func resolvePermission(allow: Bool) {
        guard let pending = pendingPermission else { return }
        let data: Data
        if pending.hookEventName == "PreToolUse" {
            data = allow
                ? DecisionJSON.preToolUseAllow(reason: "Allowed from Bezel")
                : DecisionJSON.preToolUseDeny(reason: "Denied from Bezel")
        } else {
            data = allow ? DecisionJSON.permissionAllow() : DecisionJSON.permissionDeny()
        }
        complete(key: pending.key, data: data)
    }

    func resolvePlanReview(approve: Bool) {
        guard let pending = pendingPlanReview else { return }
        let data: Data
        if approve {
            do {
                data = try PlanReviewEncoder.approve(
                    plan: pending.planText ?? "",
                    planFilePath: pending.planFilePath,
                    hookEventName: pending.hookEventName
                )
            } catch {
                data = DecisionJSON.deny(
                    for: .permission,
                    hookEventName: pending.hookEventName,
                    message: "Could not encode plan approval"
                )
            }
        } else {
            data = PlanReviewEncoder.reject(hookEventName: pending.hookEventName)
        }
        complete(key: pending.key, data: data)
    }

    func resolveQuestion(answers: [AskUserQuestionAnswer]) {
        guard let pending = pendingQuestion else { return }
        let dicts: [[String: Any]]
        if let raw = pending.rawQuestionsJSON,
           let parsed = try? JSONSerialization.jsonObject(with: raw) as? [[String: Any]],
           !parsed.isEmpty {
            dicts = parsed
        } else {
            dicts = pending.questions.map { $0.asDictionary() }
        }
        let data: Data
        do {
            data = try AskUserQuestionEncoder.encode(questions: dicts, answers: answers)
        } catch {
            data = DecisionJSON.preToolUseDeny(reason: "Could not encode answer")
        }
        complete(key: pending.key, data: data)
    }

    /// Drop a timed-out decision from the queue.
    /// - Parameter signalResume: when true, invoke resume with timeout deny (UI-path cancel).
    ///   When false, HookServer already wrote deny to the socket — only drop UI state.
    func expireDecision(key: DecisionKey, signalResume: Bool = true) {
        guard let entry = decisionQueue.remove(key) else {
            // Already completed — still drop a leftover resume if any.
            resumes.removeValue(forKey: key)
            return
        }
        let resume = resumes.removeValue(forKey: key)
        if signalResume {
            resume?(DecisionTimeout.denyData(for: entry))
        }
        refreshSessionAfterDecision(sessionID: key.sessionID)
    }

    func jump(to session: Session) {
        TerminalJumper.jump(session: session)
    }

    // MARK: - Private

    private func enqueue(_ entry: DecisionEntry, resume: @escaping (Data) -> Void) {
        if let displaced = decisionQueue.enqueue(entry) {
            // Same key replaced — complete the old wait so the socket cannot hang forever.
            let deny = DecisionTimeout.denyData(for: displaced, message: "Superseded by newer request")
            resumes[displaced.key]?(deny)
        }
        resumes[entry.key] = resume
    }

    private func complete(key: DecisionKey, data: Data) {
        guard decisionQueue.remove(key) != nil else { return }
        let resume = resumes.removeValue(forKey: key)
        resume?(data)
        refreshSessionAfterDecision(sessionID: key.sessionID)
    }

    private func refreshSessionAfterDecision(sessionID: SessionID) {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
        let remaining = decisionQueue.entries(for: sessionID)
        if let next = DecisionQueue.selectHead(from: remaining) {
            var updated = session
            updated.phase = DecisionQueue.phase(for: next.kind)
            updated.updatedAt = Date()
            if let tool = next.toolName { updated.lastTool = tool }
            upsert(updated)
        } else {
            upsert(SessionReducer.afterDecision(session: session))
        }
    }

    private func syncSessionPhase(for sessionID: SessionID, kind: AttentionKind, toolName: String?) {
        if let existing = sessions.first(where: { $0.id == sessionID }) {
            var updated = existing
            updated.phase = DecisionQueue.phase(for: kind)
            updated.updatedAt = Date()
            if let toolName { updated.lastTool = toolName }
            upsert(updated)
        } else {
            let tool = toolName ?? ""
            let event: String
            switch kind {
            case .planReview:
                event = #"{"hook_event_name":"PreToolUse","session_id":"\#(sessionID.rawValue)","tool_name":"ExitPlanMode"}"#
            case .permission:
                event = #"{"hook_event_name":"PermissionRequest","session_id":"\#(sessionID.rawValue)","tool_name":"\#(tool)"}"#
            case .question:
                event = #"{"hook_event_name":"PreToolUse","session_id":"\#(sessionID.rawValue)","tool_name":"AskUserQuestion"}"#
            }
            if let synthetic = try? HookPayload.parse(Data(event.utf8)) {
                upsert(SessionReducer.seed(from: synthetic))
            }
        }
    }
}
