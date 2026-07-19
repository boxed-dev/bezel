import Testing
import BezelCore

@Suite("ExpandPolicy")
struct ExpandPolicyTests {
    @Test(arguments: [
        (ExpandPolicy.Transition(attentionGained: true), ExpandAction.expand),
        (ExpandPolicy.Transition(attentionCleared: true, isHovering: false), ExpandAction.compact),
        (ExpandPolicy.Transition(attentionCleared: true, isHovering: true), ExpandAction.noop),
        (ExpandPolicy.Transition(activeCountIncreased: true), ExpandAction.noop),
        (ExpandPolicy.Transition(isSessionStart: true), ExpandAction.noop),
        (ExpandPolicy.Transition(activeCountIncreased: true, isSessionStart: true), ExpandAction.noop),
        (ExpandPolicy.Transition(attentionCleared: true, isSessionStart: true, isHovering: false), ExpandAction.compact),
        (ExpandPolicy.Transition(attentionGained: true, attentionCleared: true), ExpandAction.expand),
        (ExpandPolicy.Transition(), ExpandAction.noop),
    ])
    func tableDriven(transition: ExpandPolicy.Transition, expected: ExpandAction) {
        #expect(ExpandPolicy.evaluate(transition) == expected)
    }

    @Test func attentionGainedWinsOverSessionStart() {
        let t = ExpandPolicy.Transition(attentionGained: true, activeCountIncreased: true, isSessionStart: true)
        #expect(ExpandPolicy.evaluate(t) == .expand)
    }

    @Test func attentionClearedWinsOverActiveIncrease() {
        let t = ExpandPolicy.Transition(attentionCleared: true, activeCountIncreased: true, isHovering: false)
        #expect(ExpandPolicy.evaluate(t) == .compact)
    }
}
