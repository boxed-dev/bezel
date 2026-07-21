import SwiftUI
import AppKit
import BezelCore

enum OnboardingState {
    private static let key = "bezel.onboarding.completed"
    static var hasCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    func show(store: SessionStore) {
        if window == nil {
            let root = OnboardingRoot(store: store) { [weak self] in
                OnboardingState.hasCompleted = true
                self?.window?.close()
                self?.window = nil
            }
            let hosting = NSHostingController(rootView: root)
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.title = "Bezel"
            win.titlebarAppearsTransparent = true
            win.isMovableByWindowBackground = true
            win.contentViewController = hosting
            win.center()
            win.isReleasedWhenClosed = false
            window = win
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct OnboardingRoot: View {
    let store: SessionStore
    let onDone: () -> Void
    @State private var flow = OnboardingStateModel()

    private let accent = PacManTheme.pacYellow
    private let danger = PacManTheme.blinky

    var body: some View {
        ZStack {
            PacManTheme.maze.ignoresSafeArea()
            MazePelletField(spacing: 18, opacity: 0.07).ignoresSafeArea()
            RadialGradient(
                colors: [PacManTheme.mazeWall.opacity(0.28), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 40)
                group
                    .padding(.horizontal, 40)
                Spacer()
                footer
                    .padding(.horizontal, 40)
                    .padding(.bottom, 36)
            }
        }
        .frame(minWidth: 520, minHeight: 640)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var group: some View {
        // `.id(step)` + transition → steps crossfade/slide instead of hard-swapping.
        ZStack {
            switch flow.step {
            case .welcome: welcome
            case .glance: glance
            case .connect: connect
            case .jump: jump
            case .stayReady: stayReady
            case .youreSet: youreSet
            }
        }
        .id(flow.step)
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .offset(y: 10)),
                removal: .opacity
            )
        )
        .animation(.easeOut(duration: 0.3), value: flow.step)
    }

    private var welcome: some View {
        WelcomeStepView()
    }

    private var glance: some View {
        GlanceStepView()
    }

    private var connect: some View {
        VStack(alignment: .leading, spacing: 24) {
            titleBlock(
                "Bezel will wire itself into the agents on this Mac.",
                subtitle: "You can change this later."
            )
            DetectedAgentsList()
            if store.listenFailed {
                Text("Hook socket isn’t listening. Connect can’t reach Bezel until the listener starts.")
                    .font(.system(size: 12))
                    .foregroundStyle(danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            configureStatusLabel
        }
    }

    private var jump: some View {
        VStack(alignment: .leading, spacing: 24) {
            titleBlock(
                "Jump returns you to the exact session.",
                subtitle: "macOS needs Automation for Terminal and Ghostty (Apple Events), and Accessibility as a fallback for focus."
            )
            Text("You can enable these later from Settings → Privacy & Security.")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
            // Keep Connect result visible after advance (esp. socket probe failure).
            configureStatusLabel
        }
    }

    @ViewBuilder
    private var configureStatusLabel: some View {
        if !flow.configureStatus.isEmpty {
            Text(flow.configureStatus)
                .font(.system(size: 12))
                .foregroundStyle(statusLooksFailed(flow.configureStatus) ? danger : accent)
        }
    }

    private var stayReady: some View {
        VStack(alignment: .leading, spacing: 24) {
            titleBlock(
                "Keep Bezel available when you start your Mac.",
                subtitle: "It stays in the menu bar — quiet until needed."
            )
            Toggle(
                "Open at login",
                isOn: Binding(
                    get: { flow.launchAtLogin },
                    set: { dispatch(.setLaunchAtLogin($0)) }
                )
            )
            .toggleStyle(.switch)
            if !flow.launchAtLoginStatus.isEmpty {
                Text(flow.launchAtLoginStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var youreSet: some View {
        VStack(spacing: 20) {
            Text("Bezel is ready.")
                .font(.system(size: 28, weight: .semibold))
            Text("Start an agent — we’ll meet you at the notch.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if store.activeCount > 0 {
                Text("\(store.activeCount) session(s) live")
                    .font(.system(size: 12))
                    .foregroundStyle(accent)
            }
        }
    }

    private var footer: some View {
        ZStack {
            HStack {
                if flow.step != .welcome && flow.step != .youreSet {
                    Button("Back") {
                        withAnimation(.easeOut(duration: 0.3)) {
                            dispatch(.backTapped)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if flow.step == .connect, connectFailedVisible {
                    Button("Continue anyway") {
                        withAnimation(.easeOut(duration: 0.3)) {
                            dispatch(.connectContinueAnyway)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 12)
                }
                if flow.step == .jump {
                    Button("Skip for now") {
                        withAnimation(.easeOut(duration: 0.3)) {
                            dispatch(.accessibilitySkipped)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 12)
                }
                Button(primaryLabel) {
                    advance()
                }
                .modifier(PrimaryActionModifier())
                .keyboardShortcut(.defaultAction)
            }
            // Step progress — centered, quiet, never steals the primary action.
            ProgressDots(current: flow.step.rawValue, total: OnboardingStep.allCases.count)
        }
    }

    private var connectFailedVisible: Bool {
        statusLooksFailed(flow.configureStatus)
    }

    private var primaryLabel: String {
        switch flow.step {
        case .welcome: "Continue"
        case .connect: "Connect"
        case .jump: "Open Privacy Settings"
        case .youreSet: "Done"
        default: "Continue"
        }
    }

    private func advance() {
        withAnimation(.easeOut(duration: 0.3)) {
            dispatch(.continueTapped)
        }
        runEffects()
    }

    private func dispatch(_ intent: OnboardingIntent) {
        flow = OnboardingFlow.reduce(state: flow, intent: intent)
    }

    private func runEffects() {
        let effects = flow.effects
        for effect in effects {
            switch effect {
            case .installHooks:
                Task {
                    // Block Connect messaging when HookServer.bind/listen failed at launch.
                    guard store.isHookServerListening else {
                        withAnimation(.easeOut(duration: 0.3)) {
                            dispatch(.connectFinished(
                                success: false,
                                status: "Bezel socket failed to start — restart the app."
                            ))
                        }
                        return
                    }
                    let result = await ConfigInstaller.installClaudeHooks()
                    withAnimation(.easeOut(duration: 0.3)) {
                        dispatch(.connectFinished(success: result.ok, status: result.message))
                    }
                }
            case .openAutomationSettings:
                openPrivacyPane("Privacy_Automation")
            case .openAccessibilitySettings:
                openPrivacyPane("Privacy_Accessibility")
            case .applyLaunchAtLogin(let enabled):
                applyLaunchAtLoginEffect(enabled)
            case .complete:
                onDone()
            }
        }
    }

    private func applyLaunchAtLoginEffect(_ enabled: Bool) {
        guard enabled else {
            do {
                try LaunchAtLogin.setEnabled(false)
            } catch {
                // Unregister soft-fails; toggle already off and we advanced.
            }
            return
        }
        do {
            try LaunchAtLogin.setEnabled(true)
            if LaunchAtLogin.isEnabled {
                withAnimation(.easeOut(duration: 0.3)) {
                    dispatch(.launchAtLoginFinished(success: true))
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    dispatch(
                        .launchAtLoginFinished(
                            success: false,
                            status: "Could not enable Open at Login. Install Bezel as an app under /Applications, then try again."
                        )
                    )
                }
            }
        } catch {
            withAnimation(.easeOut(duration: 0.3)) {
                dispatch(
                    .launchAtLoginFinished(
                        success: false,
                        status: "Could not enable Open at Login: \(error.localizedDescription)"
                    )
                )
            }
        }
    }

    /// Best-effort deep link into System Settings privacy panes (Automation / Accessibility).
    private func openPrivacyPane(_ anchor: String) {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func statusLooksFailed(_ status: String) -> Bool {
        let lower = status.lowercased()
        return lower.contains("fail")
            || lower.contains("compet")
            || lower.contains("could not")
            || lower.contains("error")
            || lower.contains("denied")
    }

    private func titleBlock(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Step views

/// Welcome — breathing notch glyph, wordmark drift-in.
private struct WelcomeStepView: View {
    @State private var breathing = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 20) {
            PacManNotchMark(width: 140, height: 34)
                .scaleEffect(breathing ? 1.05 : 1)
                .opacity(breathing ? 0.95 : 0.7)
                .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: breathing)
            Text("BEZEL")
                .font(PacManTheme.scoreFont(size: 40, weight: .heavy))
                .tracking(6)
                .foregroundStyle(PacManTheme.pacYellow)
            Text("Your agents live in the notch — chomp when busy, ghosts when they need you.")
                .font(.system(size: 16))
                .foregroundStyle(PacManTheme.secondary)
                .multilineTextAlignment(.center)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            breathing = true
            withAnimation(.easeOut(duration: 0.45)) { appeared = true }
        }
    }
}

/// The glance — Working / Waiting / Done rows stagger in to teach the model.
private struct GlanceStepView: View {
    @State private var shownRows = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("When an agent needs you, the notch powers up.")
                    .font(.system(size: 22, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("When it doesn’t, Bezel stays quiet in the maze.")
                    .font(.system(size: 15))
                    .foregroundStyle(PacManTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                phaseDemo("Working", icon: AnyView(PacManChomper(diameter: 14)), index: 0)
                phaseDemo("Waiting", icon: AnyView(MiniGhost(color: PacManTheme.pinky, size: 14, waiting: true)), index: 1)
                phaseDemo("Done", icon: AnyView(MiniGhost(color: PacManTheme.moss, size: 14)), index: 2)
            }
        }
        .onAppear {
            shownRows = 0
            for i in 0...2 {
                withAnimation(.easeOut(duration: 0.35).delay(0.18 + Double(i) * 0.12)) {
                    shownRows = i + 1
                }
            }
        }
    }

    private func phaseDemo(_ label: String, icon: AnyView, index: Int) -> some View {
        HStack(spacing: 10) {
            icon.frame(width: 16, height: 16)
            Text(label)
                .font(.system(size: 14, weight: .medium))
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(PacManTheme.mazeWall.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(shownRows > index ? 1 : 0)
        .offset(x: shownRows > index ? 0 : -8)
    }
}

/// Quiet step dots — current step is a steel pill, the rest recede.
private struct ProgressDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Capsule(style: .continuous)
                    .fill(i == current
                        ? PacManTheme.pacYellow
                        : PacManTheme.pellet.opacity(i < current ? 0.35 : 0.14))
                    .frame(width: i == current ? 16 : 5, height: 5)
            }
        }
        .animation(.snappy(duration: 0.25), value: current)
        .accessibilityLabel("Step \(current + 1) of \(total)")
    }
}

struct NotchGlyph: View {
    var body: some View {
        PacManNotchMark()
    }
}

struct DetectedAgentsList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            agentRow("Claude Code", found: FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.claude"))
            Text("More agents later.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private func agentRow(_ name: String, found: Bool) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 14, weight: .medium))
            Spacer()
            Text(found ? "Found" : "Not found")
                .font(.system(size: 12))
                .foregroundStyle(found ? PacManTheme.pacYellow : .secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct BezelPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PacManTheme.scoreFont(size: 14, weight: .heavy))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                PacManTheme.pacYellow.opacity(configuration.isPressed ? 0.75 : 1),
                in: Capsule()
            )
            .foregroundStyle(PacManTheme.maze)
            .shadow(color: PacManTheme.pacYellow.opacity(0.35), radius: configuration.isPressed ? 4 : 8, y: 1)
    }
}

private struct PrimaryActionModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(BezelPrimaryButtonStyle())
    }
}
