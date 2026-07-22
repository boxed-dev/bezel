import Testing
import Foundation
import BezelCore

@Suite("SessionLabel")
struct SessionLabelTests {
    @Test func formatsProviderProjectPhase() {
        let session = Session(
            id: SessionID("s1"),
            source: .claude,
            phase: .working,
            cwd: "/Users/x/Vibe",
            title: "Vibe"
        )
        #expect(SessionLabel.format(session: session) == "Claude · Vibe · working")
    }

    @Test func mapsWaitingPermissionToWaiting() {
        let session = Session(
            id: SessionID("s1"),
            source: .claude,
            phase: .waitingPermission,
            cwd: "/Users/x/Vibe",
            title: "Vibe"
        )
        #expect(SessionLabel.format(session: session) == "Claude · Vibe · waiting")
    }

    @Test func usesCwdBasenameAsProject() {
        let session = Session(
            id: SessionID("s1"),
            source: .codex,
            phase: .idle,
            cwd: "/Users/x/Projects/api",
            title: nil
        )
        #expect(SessionLabel.format(session: session) == "Codex · api · idle")
    }

    @Test func providerNames_claudeCodexOpenCodeCursor() {
        #expect(AgentSource.claude.displayName == "Claude")
        #expect(AgentSource.codex.displayName == "Codex")
        #expect(AgentSource.opencode.displayName == "OpenCode")
        #expect(AgentSource.cursor.displayName == "Cursor")

        #expect(
            SessionLabel.format(session: Session(
                id: SessionID("1"),
                source: .opencode,
                phase: .done,
                cwd: "/tmp/app"
            )) == "OpenCode · app · done"
        )
        #expect(
            SessionLabel.format(session: Session(
                id: SessionID("2"),
                source: .cursor,
                phase: .idle,
                cwd: "/Users/x/Vibe"
            )) == "Cursor · Vibe · idle"
        )
    }

    @Test func waitingQuestionAndPlanReviewMapToWaiting() {
        #expect(
            SessionLabel.format(session: Session(
                id: SessionID("q"),
                source: .claude,
                phase: .waitingQuestion,
                cwd: "/tmp/proj"
            )) == "Claude · proj · waiting"
        )
        #expect(
            SessionLabel.format(session: Session(
                id: SessionID("p"),
                source: .claude,
                phase: .planReview,
                cwd: "/tmp/proj"
            )) == "Claude · proj · waiting"
        )
    }
}
