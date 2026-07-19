import Testing
import Foundation
import BezelCore

@Suite("SessionPresence")
struct SessionPresenceTests {
    @Test func sessionStartAlwaysCreates() {
        #expect(SessionPresence.shouldCreateSession(
            event: .sessionStart,
            routeKind: .event,
            isTombstoned: true
        ))
    }

    @Test func userPromptSubmitCreatesWhenNotTombstoned() {
        #expect(SessionPresence.shouldCreateSession(
            event: .userPromptSubmit,
            routeKind: .event,
            isTombstoned: false
        ))
    }

    @Test func postToolUseCreatesWhenNotTombstoned() {
        #expect(SessionPresence.shouldCreateSession(
            event: .postToolUse,
            routeKind: .event,
            isTombstoned: false
        ))
    }

    @Test func notificationDoesNotCreate() {
        #expect(!SessionPresence.shouldCreateSession(
            event: .notification,
            routeKind: .event,
            isTombstoned: false
        ))
    }

    @Test func presenceEventsRefuseTombstone() {
        for event: HookEventName in [.userPromptSubmit, .postToolUse, .preToolUse, .notification, .stop] {
            #expect(!SessionPresence.shouldCreateSession(
                event: event,
                routeKind: .event,
                isTombstoned: true
            ))
        }
    }

    @Test func stopAloneDoesNotCreate() {
        #expect(!SessionPresence.shouldCreateSession(
            event: .stop,
            routeKind: .event,
            isTombstoned: false
        ))
    }

    @Test func blockingPermissionCreates() {
        #expect(SessionPresence.shouldCreateSession(
            event: .permissionRequest,
            routeKind: .permission,
            isTombstoned: false
        ))
    }

    @Test func tombstoneTTL() {
        let now = Date()
        #expect(SessionPresence.isTombstoned(endedAt: now.addingTimeInterval(-10), now: now))
        #expect(!SessionPresence.isTombstoned(endedAt: now.addingTimeInterval(-120), now: now))
        #expect(!SessionPresence.isTombstoned(endedAt: nil, now: now))
    }
}
