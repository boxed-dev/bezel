import Testing
import BezelCore

@Suite("NotchSurface")
struct NotchSurfaceTests {
    @Test func priorityApprovalOverList() {
        #expect(NotchSurfaceMapper.map(sessionCount: 2, headKind: .permission) == .approval)
    }

    @Test func quietWhenEmpty() {
        #expect(NotchSurfaceMapper.map(sessionCount: 0, headKind: nil) == .quiet)
    }

    @Test func planReviewWins() {
        #expect(NotchSurfaceMapper.map(sessionCount: 1, headKind: .planReview) == .planReview)
    }

    @Test func questionSurface() {
        #expect(NotchSurfaceMapper.map(sessionCount: 1, headKind: .question) == .question)
    }

    @Test func sessionListWhenActiveNoAttention() {
        #expect(NotchSurfaceMapper.map(sessionCount: 3, headKind: nil) == .sessionList)
    }
}
