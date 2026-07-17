import Testing
import BezelCore

@Suite("OnboardingFlow")
struct OnboardingFlowTests {
    @Test func welcomeContinuesToGlance() {
        var s = OnboardingStateModel()
        s = OnboardingFlow.reduce(state: s, intent: .continueTapped)
        #expect(s.step == .glance)
        #expect(s.effects.isEmpty)
    }

    @Test func connectEmitsInstallHooks() {
        var s = OnboardingStateModel(step: .connect)
        s = OnboardingFlow.reduce(state: s, intent: .continueTapped)
        #expect(s.effects == [.installHooks])
        #expect(s.configureStatus.contains("Configuring"))
    }

    @Test func connectFinishedAdvancesToJump() {
        var s = OnboardingStateModel(step: .connect, configureStatus: "…")
        s = OnboardingFlow.reduce(state: s, intent: .connectFinished(success: true))
        #expect(s.step == .jump)
        #expect(s.configureStatus == "Ready.")
    }

    @Test func connectFinishedFailureSurfacesStatus() {
        var s = OnboardingStateModel(step: .connect)
        s = OnboardingFlow.reduce(
            state: s,
            intent: .connectFinished(success: false, status: "Competing Claude hooks detected.")
        )
        #expect(s.step == .jump)
        #expect(s.configureStatus.contains("Competing"))
    }


    @Test func jumpContinueOpensAccessibilityThenStayReady() {
        var s = OnboardingStateModel(step: .jump)
        s = OnboardingFlow.reduce(state: s, intent: .continueTapped)
        #expect(s.effects == [.openAccessibilitySettings])
        #expect(s.step == .stayReady)
    }

    @Test func accessibilitySkipAllowed() {
        var s = OnboardingStateModel(step: .jump)
        s = OnboardingFlow.reduce(state: s, intent: .accessibilitySkipped)
        #expect(s.step == .stayReady)
    }

    @Test func stayReadyAppliesLoginThenYoureSet() {
        var s = OnboardingStateModel(step: .stayReady, launchAtLogin: true)
        s = OnboardingFlow.reduce(state: s, intent: .continueTapped)
        #expect(s.effects == [.applyLaunchAtLogin(true)])
        #expect(s.step == .youreSet)
    }

    @Test func finishCompletes() {
        var s = OnboardingStateModel(step: .youreSet)
        s = OnboardingFlow.reduce(state: s, intent: .finish)
        #expect(s.effects == [.complete])
    }
}
