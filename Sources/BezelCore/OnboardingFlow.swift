import Foundation

public enum OnboardingStep: Int, Sendable, CaseIterable, Equatable {
    case welcome = 0
    case glance
    case connect
    case jump
    case stayReady
    case youreSet
}

public enum OnboardingIntent: Sendable, Equatable {
    case continueTapped
    case backTapped
    case connectFinished(success: Bool, status: String = "")
    /// Explicit bypass after a failed Connect (user stays on `.connect` until this or success).
    case connectContinueAnyway
    case accessibilitySkipped
    case accessibilityOpened
    case setLaunchAtLogin(Bool)
    case launchAtLoginFinished(success: Bool, status: String = "")
    case finish
}

public enum OnboardingEffect: Sendable, Equatable {
    case installHooks
    case openAccessibilitySettings
    case openAutomationSettings
    case applyLaunchAtLogin(Bool)
    case complete
}

public struct OnboardingStateModel: Sendable, Equatable {
    public var step: OnboardingStep
    public var launchAtLogin: Bool
    public var configureStatus: String
    public var launchAtLoginStatus: String
    public var effects: [OnboardingEffect]

    public init(
        step: OnboardingStep = .welcome,
        launchAtLogin: Bool = true,
        configureStatus: String = "",
        launchAtLoginStatus: String = "",
        effects: [OnboardingEffect] = []
    ) {
        self.step = step
        self.launchAtLogin = launchAtLogin
        self.configureStatus = configureStatus
        self.launchAtLoginStatus = launchAtLoginStatus
        self.effects = effects
    }
}

public enum OnboardingFlow {
    public static func reduce(state: OnboardingStateModel, intent: OnboardingIntent) -> OnboardingStateModel {
        var next = state
        next.effects = []

        switch intent {
        case .continueTapped:
            switch next.step {
            case .welcome:
                next.step = .glance
            case .glance:
                next.step = .connect
            case .connect:
                next.configureStatus = "Configuring Claude Code…"
                next.effects = [.installHooks]
            case .jump:
                // Best-effort: Automation (Terminal/Ghostty) + Accessibility (fallback focus).
                next.effects = [.openAutomationSettings, .openAccessibilitySettings]
                next.step = .stayReady
            case .stayReady:
                next.launchAtLoginStatus = ""
                next.effects = [.applyLaunchAtLogin(next.launchAtLogin)]
                // Advance only after effect reports success (or when toggle is off).
                if !next.launchAtLogin {
                    next.step = .youreSet
                }
            case .youreSet:
                next.effects = [.complete]
            }
        case .backTapped:
            if let prev = OnboardingStep(rawValue: next.step.rawValue - 1) {
                next.step = prev
            }
        case .connectFinished(let success, let status):
            if !status.isEmpty {
                next.configureStatus = status
            } else {
                next.configureStatus = success
                    ? "Ready."
                    : "Connect failed."
            }
            // Only leave Connect on success; failure stays so the user can retry or continue anyway.
            if success {
                next.step = .jump
            }
        case .connectContinueAnyway:
            if next.step == .connect {
                next.step = .jump
            }
        case .accessibilitySkipped:
            next.step = .stayReady
        case .accessibilityOpened:
            next.step = .stayReady
        case .setLaunchAtLogin(let value):
            next.launchAtLogin = value
            next.launchAtLoginStatus = ""
        case .launchAtLoginFinished(let success, let status):
            if !status.isEmpty {
                next.launchAtLoginStatus = status
            }
            if success {
                next.step = .youreSet
            } else {
                // Do not claim enabled when SMAppService registration fails.
                next.launchAtLogin = false
                next.step = .stayReady
            }
        case .finish:
            next.effects = [.complete]
        }
        return next
    }
}
