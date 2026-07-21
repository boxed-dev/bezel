import Testing
import Foundation
import BezelCore

@Suite("IdleSessionPrune")
struct IdleSessionPruneTests {
    @Test func removesStaleIdle() {
        let old = Session(
            id: SessionID("s1"),
            phase: .idle,
            updatedAt: Date(timeIntervalSinceNow: -31 * 60)
        )
        let fresh = Session(
            id: SessionID("s2"),
            phase: .idle,
            updatedAt: Date(timeIntervalSinceNow: -5 * 60)
        )
        let working = Session(id: SessionID("s3"), phase: .working)
        let pruned = IdleSessionPrune.prune([old, fresh, working])
        #expect(pruned.count == 2)
        #expect(!pruned.contains(where: { $0.id == old.id }))
    }
}

@Suite("ToolEventRing")
struct ToolEventRingTests {
    @Test func appendsAndCaps() {
        var ring: [ToolEvent] = []
        for i in 0..<30 {
            // Distinct scripts so summaries don’t collapse to the same label.
            ring = ToolEventRing.append(ring, tool: "Bash", detail: "bash scripts/step-\(i).sh")
        }
        #expect(ring.count == ToolEventRing.maxEvents)
        #expect(ring.first?.label.contains("step-29") == true)
    }

    @Test func rejectsNullJunk() {
        let ring = ToolEventRing.append(nil, tool: "Bash", detail: "null;")
        #expect(ring.isEmpty)
    }
}

@Suite("SessionTelemetry")
struct SessionTelemetryTests {
    @Test func parsesModelAndTokens() throws {
        let json = #"{"model":"opus-4","tokens_in":1200,"tokens_out":340,"cost_usd":0.42}"#
        let obj = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let t = SessionTelemetry.parse(from: obj)
        #expect(t.model == "opus-4")
        #expect(t.tokensIn == 1200)
        #expect(t.tokensOut == 340)
        #expect(t.costUSD == 0.42)
    }

    @Test func mergeIncrementsMessageCount() {
        var s = Session(id: SessionID("s1"), phase: .working)
        s = SessionTelemetry.merge(into: s, telemetry: HookTelemetry(), event: .userPromptSubmit)
        #expect(s.messageCount == 1)
    }
}

@Suite("AgentBoardMapper")
struct AgentBoardMapperTests {
    @Test func mapsAttentionAndActive() {
        let sid = SessionID("s1")
        let waiting = Session(id: sid, phase: .waitingPermission)
        let col = AgentBoardMapper.column(for: waiting, attentionSessionIDs: [sid])
        #expect(col == .attention)
        let working = Session(id: SessionID("s2"), phase: .working)
        #expect(AgentBoardMapper.column(for: working, attentionSessionIDs: []) == .active)
    }
}
