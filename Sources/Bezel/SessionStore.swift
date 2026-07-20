import Foundation
import Observation
import BezelCore

@MainActor
@Observable
final class SessionStore {
    private(set) var sessions: [Session] = []
    private(set) var decisionQueue = DecisionQueue()
    private var resumes: [DecisionKey: (Data) -> Void] = [:]
    /// SessionEnd tombstones — block late PostToolUse/etc. from resurrecting zombies.
    private var endedAt: [SessionID: Date] = [:]
    /// Bumps on every session mutation so notch compact views always refresh.
    private(set) var presenceEpoch: UInt64 = 0
    /// Claude.ai plan usage (5h / 7d) — NOT session count.
    private(set) var usage: ClaudeUsageSnapshot?
    /// Bumps when usage changes so compact trailing remeasures.
    private(set) var usageEpoch: UInt64 = 0
    /// Bumps on SessionStart so ExpandPolicy can stay quiet.
    private(set) var sessionStartEpoch: UInt64 = 0

    /// Opt-in local Always memory (default off — no surprise auto-allow).
    var permissionMemoryEnabled = false

    /// Set by AppDelegate from `HookServer.start()` — Connect must not claim listening if false.
    private(set) var isHookServerListening = false

    /// Inverse of `isHookServerListening` for status menu / Settings banners.
    var listenFailed: Bool { !isHookServerListening }

    /// Live sessions (not done). Stored-style access via sessions so Observation tracks reliably.
    var activeCount: Int { sessions.filter { $0.phase != .done }.count }
    var needsAttention: Bool { decisionQueue.head != nil }
    /// Working / waiting sessions — leading-dot activity, not the % meter.
    var liveActivityCount: Int {
        sessions.filter {
            $0.phase == .working
                || $0.phase == .waitingPermission
                || $0.phase == .waitingQuestion
                || $0.phase == .planReview
        }.count
    }

    /// Rounded Claude plan % for compact trailing (`nil` until first fetch).
    var usagePercent: Int? { usage?.primaryPercent }

    func setHookServerListening(_ listening: Bool) {
        isHookServerListening = listening
    }

    func applyUsage(_ snapshot: ClaudeUsageSnapshot) {
        if let current = usage,
           current.fiveHour?.usedPercent == snapshot.fiveHour?.usedPercent,
           current.sevenDay?.usedPercent == snapshot.sevenDay?.usedPercent
        {
            // Still refresh metadata quietly when source is newer oauth.
            if snapshot.fetchedAt <= current.fetchedAt { return }
        }
        usage = snapshot
        usageEpoch &+= 1
    }

    /// Highest-priority / oldest decision currently needing attention.
    var attentionHead: DecisionEntry? { decisionQueue.head }

    /// Highest-priority session for compact trailing click-to-jump.
    var neediestSession: Session? {
        if let head = attentionHead,
           let session = sessions.first(where: { $0.id == head.key.sessionID })
        {
            return session
        }
        let live = sessions.filter { $0.phase != .done }
        let priority: [SessionPhase] = [
            .waitingPermission, .waitingQuestion, .planReview, .working, .idle, .error,
        ]
        return live.min { a, b in
            let ia = priority.firstIndex(of: a.phase) ?? priority.count
            let ib = priority.firstIndex(of: b.phase) ?? priority.count
            if ia != ib { return ia < ib }
            return a.updatedAt > b.updatedAt
        }
    }

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

    /// True when Claude sent permission suggestions for the Always option.
    var permissionHasAlwaysOption: Bool {
        guard let json = pendingPermission?.permissionSuggestionsJSON else { return false }
        return !PermissionSuggestions.array(from: json).isEmpty
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
        pruneIdleSessions()
        presenceEpoch &+= 1
    }

    /// Visible in list/board — drops stale idle rows.
    var visibleSessions: [Session] {
        IdleSessionPrune.prune(sessions.filter { $0.phase != .done })
    }

    func attentionSessionIDs() -> Set<SessionID> {
        var ids = Set(decisionQueue.entries.map(\.key.sessionID))
        for s in sessions where s.phase == .waitingPermission || s.phase == .waitingQuestion || s.phase == .planReview {
            ids.insert(s.id)
        }
        return ids
    }

    private func pruneIdleSessions(now: Date = Date()) {
        let pruned = IdleSessionPrune.prune(sessions, now: now)
        if pruned.count != sessions.count {
            sessions = pruned
        }
    }

    func remove(id: SessionID) {
        let before = sessions.count
        sessions.removeAll { $0.id == id }
        if sessions.count != before {
            presenceEpoch &+= 1
        }
    }

    func apply(envelope: HookPayload) {
        let sid = SessionID(envelope.sessionID ?? SessionID.unknown.rawValue)
        let event = HookEventName(raw: envelope.hookEventName)
        pruneTombstones()

        // SessionEnd is the only true "remove from list" event (see SessionReducer).
        if event == .sessionEnd {
            remove(id: sid)
            endedAt[sid] = Date()
            return
        }

        if event == .sessionStart {
            endedAt.removeValue(forKey: sid)
            sessionStartEpoch &+= 1
        }

        let existing = sessions.first(where: { $0.id == sid })
        let next: Session
        if let existing {
            next = SessionReducer.apply(session: existing, envelope: envelope)
        } else {
            let tombstoned = SessionPresence.isTombstoned(endedAt: endedAt[sid])
            guard SessionPresence.shouldCreateSession(
                event: event,
                routeKind: envelope.routeKind,
                isTombstoned: tombstoned
            ) else {
                return
            }
            next = SessionReducer.seed(from: envelope)
        }
        var enriched = next
        if let hint = TerminalHintExtractor.fromHookJSON(envelope.rawJSON) {
            // Merge — never wipe a good ITERM_SESSION_ID/tty when a later hook lacks it.
            enriched.terminal = (next.terminal ?? TerminalHint()).merging(hint)
        }
        upsert(enriched)
    }

    private func pruneTombstones(now: Date = Date()) {
        endedAt = endedAt.filter {
            SessionPresence.isTombstoned(endedAt: $0.value, now: now)
        }
    }

    func enqueuePermission(
        key: DecisionKey,
        toolName: String?,
        summary: String,
        hookEventName: String,
        permissionSuggestionsJSON: Data? = nil,
        requestedRuleContent: String? = nil,
        resume: @escaping (Data) -> Void
    ) {
        let entry = DecisionEntry(
            key: key,
            kind: .permission,
            toolName: toolName,
            summary: summary,
            hookEventName: hookEventName,
            permissionSuggestionsJSON: permissionSuggestionsJSON,
            requestedRuleContent: requestedRuleContent
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
    /// - Parameter always: when true, echo Claude `permission_suggestions` as `updatedPermissions`.
    func resolvePermission(allow: Bool, always: Bool = false) {
        guard let pending = pendingPermission else { return }
        let data: Data
        if pending.hookEventName == "PreToolUse" {
            data = allow
                ? DecisionJSON.preToolUseAllow(reason: "Allowed from Bezel")
                : DecisionJSON.preToolUseDeny(reason: "Denied from Bezel")
        } else if allow {
            let updates: [[String: Any]]?
            if always {
                if let json = pending.permissionSuggestionsJSON {
                    updates = PermissionSuggestions.array(from: json)
                    if permissionMemoryEnabled,
                       let detail = PermissionSuggestions.alwaysAllowDetail(from: json),
                       let tool = pending.toolName
                    {
                        _ = PermissionMemory.recordAlways(tool: tool, ruleContent: detail)
                    }
                } else if permissionMemoryEnabled,
                          let memory = PermissionMemory.matchingSuggestions(
                              tool: pending.toolName,
                              ruleContent: pending.requestedRuleContent,
                              suggestions: []
                          )
                {
                    updates = memory
                } else {
                    updates = nil
                }
            } else {
                updates = nil
            }
            data = DecisionJSON.permissionAllow(updatedPermissions: updates)
        } else {
            data = DecisionJSON.permissionDeny()
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
    ///   When false, HookServer already settled deny on the socket — only drop UI state.
    ///   Resume uses the same kind-correct bytes as `DecisionTimeout` / HookServer timeout settle.
    func expireDecision(key: DecisionKey, signalResume: Bool = true) {
        guard let entry = decisionQueue.remove(key) else {
            // Already completed — still drop a leftover resume if any.
            resumes.removeValue(forKey: key)
            return
        }
        let resume = resumes.removeValue(forKey: key)
        if signalResume {
            // Same deny shape HookServer settles on timeout (first writer on SettledResponseBox wins).
            resume?(DecisionTimeout.denyData(for: entry))
        }
        refreshSessionAfterDecision(sessionID: key.sessionID)
    }

    func jump(to session: Session) {
        _ = FlowStatsStore.recordJump()
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
            guard !SessionPresence.isTombstoned(endedAt: endedAt[sessionID]) else { return }
            let tool = toolName ?? ""
            let sid = DecisionJSON.escapeJSONString(sessionID.rawValue)
            let toolEscaped = DecisionJSON.escapeJSONString(tool)
            let event: String
            switch kind {
            case .planReview:
                event = #"{"hook_event_name":"PreToolUse","session_id":"\#(sid)","tool_name":"ExitPlanMode"}"#
            case .permission:
                event = #"{"hook_event_name":"PermissionRequest","session_id":"\#(sid)","tool_name":"\#(toolEscaped)"}"#
            case .question:
                event = #"{"hook_event_name":"PreToolUse","session_id":"\#(sid)","tool_name":"AskUserQuestion"}"#
            }
            if let synthetic = try? HookPayload.parse(Data(event.utf8)) {
                upsert(SessionReducer.seed(from: synthetic))
            }
        }
    }
}
