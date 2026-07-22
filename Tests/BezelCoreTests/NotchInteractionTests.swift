import Testing
import BezelCore

@Suite("NotchInteraction")
struct NotchInteractionTests {
    @Test func compactTrailingPrimary_isExpand_neverJump() {
        let action = NotchInteraction.compactTrailingPrimary(context: .usage)
        #expect(action == .expand)
        #expect(action != .resolve)
    }

    @Test func compactTrailingWhenAttention_isExpand() {
        #expect(NotchInteraction.compactTrailingPrimary(context: .attention) == .expand)
        #expect(NotchInteraction.compactTrailingPrimary(context: .liveCount) == .expand)
        #expect(NotchInteraction.compactTrailingPrimary(context: .empty) == .expand)
    }

    @Test func sessionRowPrimary_isSelect_notJump() {
        let id = SessionID("sess-1")
        let action = NotchInteraction.sessionRowPrimary(sessionID: id)
        #expect(action == .select(id))
        if case .select = action {} else {
            Issue.record("primary must be select, never jump")
        }
    }

    @Test func sessionRowSecondary_isJump() {
        let id = SessionID("sess-2")
        #expect(NotchInteraction.sessionRowSecondary(sessionID: id) == .jump(id))
    }

    @Test func usageSurface_primaryActionExpand() {
        #expect(NotchInteraction.compactTrailingPrimary(context: .usage) == .expand)
        #expect(NotchInteraction.compactLeadingPrimary() == .expand)
    }
}
