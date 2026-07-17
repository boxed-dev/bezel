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
    @State private var step = 0
    @State private var launchAtLogin = true
    @State private var configureStatus = ""

    private let accent = Color(red: 0.55, green: 0.64, blue: 0.71)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.027, green: 0.031, blue: 0.039),
                    Color(red: 0.07, green: 0.078, blue: 0.102),
                ],
                startPoint: .top,
                endPoint: .bottom
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
        switch step {
        case 0: welcome
        case 1: glance
        case 2: connect
        case 3: jump
        case 4: stayReady
        default: youreSet
        }
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            NotchGlyph()
                .frame(height: 36)
            Text("Bezel")
                .font(.system(size: 42, weight: .semibold))
                .tracking(4)
            Text("Your agents, at the edge of the screen.")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var glance: some View {
        VStack(alignment: .leading, spacing: 24) {
            titleBlock(
                "When an agent needs you, Bezel opens from the notch.",
                subtitle: "When it doesn’t, it disappears."
            )
            VStack(alignment: .leading, spacing: 10) {
                phaseDemo("Working", color: accent)
                phaseDemo("Waiting", color: Color(red: 0.77, green: 0.65, blue: 0.45))
                phaseDemo("Done", color: Color(red: 0.45, green: 0.55, blue: 0.48))
            }
        }
    }

    private var connect: some View {
        VStack(alignment: .leading, spacing: 24) {
            titleBlock(
                "Bezel will wire itself into the agents on this Mac.",
                subtitle: "You can change this later."
            )
            DetectedAgentsList()
            if !configureStatus.isEmpty {
                Text(configureStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(accent)
            }
        }
    }

    private var jump: some View {
        VStack(alignment: .leading, spacing: 24) {
            titleBlock(
                "Jump returns you to the exact session.",
                subtitle: "macOS needs Accessibility for that."
            )
            Text("You can enable this later from Settings.")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
    }

    private var stayReady: some View {
        VStack(alignment: .leading, spacing: 24) {
            titleBlock(
                "Keep Bezel available when you start your Mac.",
                subtitle: "It stays in the menu bar — quiet until needed."
            )
            Toggle("Open at login", isOn: $launchAtLogin)
                .toggleStyle(.switch)
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
        HStack {
            if step > 0 && step < 5 {
                Button("Back") { withAnimation(.easeOut(duration: 0.3)) { step -= 1 } }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(primaryLabel) {
                advance()
            }
            .buttonStyle(BezelPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
    }

    private var primaryLabel: String {
        switch step {
        case 0: "Continue"
        case 2: "Connect"
        case 3: "Enable Accessibility"
        case 5: "Done"
        default: "Continue"
        }
    }

    private func advance() {
        switch step {
        case 2:
            configureStatus = "Configuring Claude Code…"
            Task {
                let ok = await ConfigInstaller.installClaudeHooks()
                configureStatus = ok ? "Ready." : "Claude Code not found — skipped."
                try? await Task.sleep(for: .milliseconds(500))
                withAnimation(.easeOut(duration: 0.3)) { step = 3 }
            }
        case 3:
            // Open Accessibility pane; do not block.
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
            withAnimation(.easeOut(duration: 0.3)) { step = 4 }
        case 4:
            // Login item — SMAppService in later polish; store preference for now.
            UserDefaults.standard.set(launchAtLogin, forKey: "bezel.launchAtLogin")
            withAnimation(.easeOut(duration: 0.3)) { step = 5 }
        case 5:
            onDone()
        default:
            withAnimation(.easeOut(duration: 0.3)) { step += 1 }
        }
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

    private func phaseDemo(_ label: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 14, weight: .medium))
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct NotchGlyph: View {
    var body: some View {
        Capsule()
            .fill(.white.opacity(0.12))
            .overlay(
                Capsule()
                    .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
            )
            .frame(width: 120, height: 28)
    }
}

struct DetectedAgentsList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            agentRow("Claude Code", found: FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.claude"))
            agentRow("Codex", found: FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.codex"))
            agentRow("Cursor", found: FileManager.default.fileExists(atPath: NSHomeDirectory() + "/.cursor"))
        }
    }

    private func agentRow(_ name: String, found: Bool) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 14, weight: .medium))
            Spacer()
            Text(found ? "Found" : "Not found")
                .font(.system(size: 12))
                .foregroundStyle(found ? Color(red: 0.55, green: 0.64, blue: 0.71) : .secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct BezelPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(
                Color(red: 0.55, green: 0.64, blue: 0.71).opacity(configuration.isPressed ? 0.7 : 1),
                in: Capsule()
            )
            .foregroundStyle(Color(red: 0.07, green: 0.08, blue: 0.1))
    }
}
