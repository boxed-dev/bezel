import Testing
import Foundation
import BezelCore

@Suite("DecisionTimeout")
struct DecisionTimeoutTests {
    @Test func permissionTimeoutDenyShape() throws {
        let entry = DecisionEntry(
            key: DecisionKey(sessionID: SessionID("s1"), requestID: "r1"),
            kind: .permission,
            summary: "Allow Bash?",
            hookEventName: "PermissionRequest"
        )
        let data = DecisionTimeout.denyData(for: entry)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hook = root?["hookSpecificOutput"] as? [String: Any]
        let decision = hook?["decision"] as? [String: Any]
        #expect(decision?["behavior"] as? String == "deny")
        #expect(decision?["message"] as? String == "Timed out")
    }

    @Test func questionTimeoutUsesPreToolUse() throws {
        let entry = DecisionEntry(
            key: DecisionKey(sessionID: SessionID("s1"), requestID: "r2"),
            kind: .question,
            summary: "Q?",
            hookEventName: "PreToolUse"
        )
        let data = DecisionTimeout.denyData(for: entry)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hook = root?["hookSpecificOutput"] as? [String: Any]
        #expect(hook?["permissionDecision"] as? String == "deny")
        #expect(hook?["hookEventName"] as? String == "PreToolUse")
    }

    @Test func queueRemoveClearsHead() {
        var q = DecisionQueue()
        let key = DecisionKey(sessionID: SessionID("s1"), requestID: "r1")
        let entry = DecisionEntry(key: key, kind: .permission, summary: "x", hookEventName: "PermissionRequest")
        _ = q.enqueue(entry)
        #expect(q.head != nil)
        _ = q.remove(key)
        #expect(q.head == nil)
    }

    /// Timeout deny shape does not depend on which agent enqueued the permission.
    @Test(
        "permission timeout deny identical across sources",
        arguments: ["claude", "codex", "opencode", "cursor"]
    )
    func permissionTimeoutDenyIdenticalAcrossSources(source: String) throws {
        let entry = DecisionEntry(
            key: DecisionKey(sessionID: SessionID("\(source)-s1"), requestID: "r1"),
            kind: .permission,
            summary: "Allow Bash?",
            hookEventName: "PermissionRequest"
        )
        let data = DecisionTimeout.denyData(for: entry)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hook = root?["hookSpecificOutput"] as? [String: Any]
        let decision = hook?["decision"] as? [String: Any]
        #expect(decision?["behavior"] as? String == "deny")
        #expect(decision?["message"] as? String == "Timed out")
    }
}
