import Testing
import Foundation
import BezelCore

@Suite("SettledResponseBox")
struct SettledResponseBoxTests {
    @Test func firstWriterWinsTimeoutVsAllow() {
        let timeout = DecisionJSON.deny(
            for: .permission,
            hookEventName: "PermissionRequest",
            message: "Timed out"
        )
        let allow = DecisionJSON.permissionAllow()
        let box = SettledResponseBox(placeholder: timeout)

        #expect(box.settle(allow) == true)
        #expect(box.settle(timeout) == false)
        #expect(JSONCanonical.equal(box.get(), allow))
        #expect(box.isSettled)
    }

    @Test func firstWriterWinsAllowVsTimeout() {
        let timeout = DecisionJSON.deny(
            for: .question,
            hookEventName: "PreToolUse",
            message: "Timed out"
        )
        let allow = DecisionJSON.preToolUseAllow(reason: "Allowed from Bezel")
        let box = SettledResponseBox(placeholder: timeout)

        #expect(box.settle(timeout) == true)
        #expect(box.settle(allow) == false)
        #expect(JSONCanonical.equal(box.get(), timeout))
    }

    @Test func concurrentRaceSettlesExactlyOnce() async {
        let timeout = DecisionJSON.permissionDeny(message: "Timed out")
        let allow = DecisionJSON.permissionAllow()
        let box = SettledResponseBox(placeholder: timeout)

        await withTaskGroup(of: Bool.self) { group in
            for i in 0..<64 {
                group.addTask {
                    let data = i.isMultiple(of: 2) ? allow : timeout
                    return box.settle(data)
                }
            }
            var wins = 0
            for await won in group where won {
                wins += 1
            }
            #expect(wins == 1)
        }

        let settled = box.get()
        #expect(
            JSONCanonical.equal(settled, allow) || JSONCanonical.equal(settled, timeout)
        )
    }

    @Test func cancelFlagBlocksLateEnqueue() {
        let flag = DecisionCancelFlag()
        #expect(flag.isCancelled == false)
        flag.cancel()
        #expect(flag.isCancelled)
    }
}
