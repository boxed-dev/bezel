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

    @Test func connectFinishedFailureStaysOnConnect() {
        var s = OnboardingStateModel(step: .connect)
        s = OnboardingFlow.reduce(
            state: s,
            intent: .connectFinished(success: false, status: "Competing Claude hooks detected.")
        )
        #expect(s.step == .connect)
        #expect(s.configureStatus.contains("Competing"))
    }

    @Test func connectContinueAnywayAdvancesToJump() {
        var s = OnboardingStateModel(step: .connect, configureStatus: "Connect failed.")
        s = OnboardingFlow.reduce(state: s, intent: .connectContinueAnyway)
        #expect(s.step == .jump)
    }

    @Test func jumpContinueOpensPrivacySettingsThenStayReady() {
        var s = OnboardingStateModel(step: .jump)
        s = OnboardingFlow.reduce(state: s, intent: .continueTapped)
        #expect(s.effects == [.openAutomationSettings, .openAccessibilitySettings])
        #expect(s.step == .stayReady)
    }

    @Test func accessibilitySkipAllowed() {
        var s = OnboardingStateModel(step: .jump)
        s = OnboardingFlow.reduce(state: s, intent: .accessibilitySkipped)
        #expect(s.step == .stayReady)
    }

    @Test func stayReadyAppliesLoginWhenEnabled() {
        var s = OnboardingStateModel(step: .stayReady, launchAtLogin: true)
        s = OnboardingFlow.reduce(state: s, intent: .continueTapped)
        #expect(s.effects == [.applyLaunchAtLogin(true)])
        #expect(s.step == .stayReady)
    }

    @Test func stayReadySkipsLoginWhenDisabled() {
        var s = OnboardingStateModel(step: .stayReady, launchAtLogin: false)
        s = OnboardingFlow.reduce(state: s, intent: .continueTapped)
        #expect(s.effects == [.applyLaunchAtLogin(false)])
        #expect(s.step == .youreSet)
    }

    @Test func launchAtLoginSuccessAdvancesToYoureSet() {
        var s = OnboardingStateModel(step: .stayReady, launchAtLogin: true)
        s = OnboardingFlow.reduce(state: s, intent: .launchAtLoginFinished(success: true))
        #expect(s.step == .youreSet)
        #expect(s.launchAtLogin == true)
    }

    @Test func launchAtLoginFailureClearsToggleAndStays() {
        var s = OnboardingStateModel(step: .stayReady, launchAtLogin: true)
        s = OnboardingFlow.reduce(
            state: s,
            intent: .launchAtLoginFinished(success: false, status: "Could not enable Open at Login.")
        )
        #expect(s.step == .stayReady)
        #expect(s.launchAtLogin == false)
        #expect(s.launchAtLoginStatus.contains("Could not enable"))
    }

    @Test func finishCompletes() {
        var s = OnboardingStateModel(step: .youreSet)
        s = OnboardingFlow.reduce(state: s, intent: .finish)
        #expect(s.effects == [.complete])
    }
}
