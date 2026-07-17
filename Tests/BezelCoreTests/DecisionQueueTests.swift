import Testing
import Foundation
import BezelCore

@Suite("DecisionQueue")
struct DecisionQueueTests {
    @Test func secondConcurrentPermissionDoesNotDropFirst() {
        var queue = DecisionQueue()
        let t0 = Date(timeIntervalSince1970: 1000)
        let t1 = Date(timeIntervalSince1970: 1001)

        let a = entry(
            session: "s1",
            request: "r1",
            kind: .permission,
            at: t0,
            summary: "Allow Bash?"
        )
        let b = entry(
            session: "s2",
            request: "r2",
            kind: .permission,
            at: t1,
            summary: "Allow Edit?"
        )

        queue.enqueue(a)
        queue.enqueue(b)

        #expect(queue.entries.count == 2)
        #expect(queue.head?.key.requestID == "r1")
        #expect(queue.head?.key.sessionID == SessionID("s1"))

        let removed = queue.remove(a.key)
        #expect(removed?.key.requestID == "r1")
        #expect(queue.entries.count == 1)
        #expect(queue.head?.key.requestID == "r2")
        #expect(queue.head?.summary == "Allow Edit?")
    }

    @Test func planReviewOutranksOlderPermission() {
        var queue = DecisionQueue()
        let older = entry(
            session: "s1",
            request: "p1",
            kind: .permission,
            at: Date(timeIntervalSince1970: 1),
            summary: "Allow Bash?"
        )
        let plan = entry(
            session: "s2",
            request: "plan1",
            kind: .planReview,
            at: Date(timeIntervalSince1970: 99),
            summary: "Review plan"
        )
        queue.enqueue(older)
        queue.enqueue(plan)
        #expect(queue.head?.kind == .planReview)
        #expect(queue.head?.key.requestID == "plan1")
    }

    @Test func oldestWinsWithinSamePriority() {
        let entries = [
            entry(session: "s2", request: "b", kind: .question, at: Date(timeIntervalSince1970: 20), summary: "q2"),
            entry(session: "s1", request: "a", kind: .question, at: Date(timeIntervalSince1970: 10), summary: "q1"),
        ]
        #expect(DecisionQueue.selectHead(from: entries)?.key.requestID == "a")
    }

    @Test func sameKeyReplacesWithoutGrowingQueue() {
        var queue = DecisionQueue()
        let key = DecisionKey(sessionID: SessionID("s1"), requestID: "same")
        let first = DecisionEntry(
            key: key,
            kind: .permission,
            enqueuedAt: Date(timeIntervalSince1970: 1),
            summary: "first",
            hookEventName: "PermissionRequest"
        )
        let second = DecisionEntry(
            key: key,
            kind: .permission,
            enqueuedAt: Date(timeIntervalSince1970: 2),
            summary: "second",
            hookEventName: "PermissionRequest"
        )
        let displaced = queue.enqueue(first)
        #expect(displaced == nil)
        let replaced = queue.enqueue(second)
        #expect(replaced?.summary == "first")
        #expect(queue.entries.count == 1)
        #expect(queue.head?.summary == "second")
    }

    @Test func extractRequestIDPrefersToolUseId() {
        let json = #"{"hook_event_name":"PermissionRequest","session_id":"s1","tool_use_id":"tu_abc","tool_name":"Bash"}"#
        let id = DecisionKeyFactory.extractRequestID(from: Data(json.utf8))
        #expect(id == "tu_abc")
    }

    @Test func attentionKindMapsExitPlanModeToPlanReview() {
        let kind = DecisionQueue.attentionKind(
            routeKind: .permission,
            toolName: "ExitPlanMode",
            hookEventName: "PreToolUse"
        )
        #expect(kind == .planReview)
    }

    @Test func surfaceMapsFromHeadKind() {
        #expect(NotchSurfaceMapper.map(sessionCount: 1, headKind: .planReview) == .planReview)
        #expect(NotchSurfaceMapper.map(sessionCount: 1, headKind: .permission) == .approval)
        #expect(NotchSurfaceMapper.map(sessionCount: 1, headKind: .question) == .question)
        #expect(NotchSurfaceMapper.map(sessionCount: 2, headKind: nil) == .sessionList)
        #expect(NotchSurfaceMapper.map(sessionCount: 0, headKind: nil) == .quiet)
    }

    private func entry(
        session: String,
        request: String,
        kind: AttentionKind,
        at: Date,
        summary: String
    ) -> DecisionEntry {
        DecisionEntry(
            key: DecisionKey(sessionID: SessionID(session), requestID: request),
            kind: kind,
            enqueuedAt: at,
            summary: summary,
            hookEventName: kind == .permission ? "PermissionRequest" : "PreToolUse"
        )
    }
}
