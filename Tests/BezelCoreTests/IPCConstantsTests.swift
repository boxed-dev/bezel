import Testing
import BezelCore

@Suite("IPCConstants")
struct IPCConstantsTests {
    @Test func blockingTimeoutIsTenMinutes() {
        #expect(IPCConstants.blockingRecvTimeoutSeconds == 600)
    }

    @Test func inboundReadTimeoutIsFiveSeconds() {
        #expect(IPCConstants.inboundReadTimeoutSeconds == 5)
    }

    @Test func eventTimeoutIsShort() {
        #expect(IPCConstants.eventTimeoutSeconds <= 1)
    }
}
