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
    case accessibilitySkipped
    case accessibilityOpened
    case setLaunchAtLogin(Bool)
    case finish
}

public enum OnboardingEffect: Sendable, Equatable {
    case installHooks
    case openAccessibilitySettings
    case applyLaunchAtLogin(Bool)
    case complete
}

public struct OnboardingStateModel: Sendable, Equatable {
    public var step: OnboardingStep
    public var launchAtLogin: Bool
    public var configureStatus: String
    public var effects: [OnboardingEffect]

    public init(
        step: OnboardingStep = .welcome,
        launchAtLogin: Bool = true,
        configureStatus: String = "",
        effects: [OnboardingEffect] = []
    ) {
        self.step = step
        self.launchAtLogin = launchAtLogin
        self.configureStatus = configureStatus
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
                next.effects = [.openAccessibilitySettings]
                next.step = .stayReady
            case .stayReady:
                next.effects = [.applyLaunchAtLogin(next.launchAtLogin)]
                next.step = .youreSet
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
            next.step = .jump
        case .accessibilitySkipped:
            next.step = .stayReady
        case .accessibilityOpened:
            next.step = .stayReady
        case .setLaunchAtLogin(let value):
            next.launchAtLogin = value
        case .finish:
            next.effects = [.complete]
        }
        return next
    }
}
