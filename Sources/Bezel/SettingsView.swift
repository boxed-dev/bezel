import SwiftUI
import BezelCore

struct SettingsView: View {
    @Environment(SessionStore.self) private var store
    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError = ""
    @State private var hooksStatus = ""
    @State private var hooksStatusOK = false

    private let accent = Color(red: 0.55, green: 0.64, blue: 0.71)
    private let danger = Color(red: 0.85, green: 0.45, blue: 0.4)
    private let okGreen = Color(red: 0.5, green: 0.72, blue: 0.56)

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                Section("Status") {
                    LabeledContent("Socket") {
                        Text(SocketPath.resolve())
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Active sessions") {
                        Text("\(store.activeCount)")
                            .monospacedDigit()
                    }
                    if let usage = store.usage {
                        LabeledContent("Claude usage") {
                            Text(usage.helpText)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(usageTint(usage))
                        }
                    }
                    if store.listenFailed {
                        Label(
                            "Hook socket isn’t listening. Repair hooks won’t work until Bezel can bind the socket.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.system(size: 11))
                        .foregroundStyle(danger)
                    }
                }
                Section("General") {
                    Toggle(
                        "Open at login",
                        isOn: Binding(
                            get: { launchAtLoginEnabled },
                            set: { setLaunchAtLogin($0) }
                        )
                    )
                    if !launchAtLoginError.isEmpty {
                        Text(launchAtLoginError)
                            .font(.system(size: 11))
                            .foregroundStyle(danger)
                    }
                    Toggle(
                        "Sound alerts",
                        isOn: Binding(
                            get: { BezelSound.isEnabled },
                            set: { BezelSound.isEnabled = $0 }
                        )
                    )
                    Toggle(
                        "Remember Always-allow rules",
                        isOn: Binding(
                            get: { PermissionMemorySettings.isEnabled },
                            set: { enabled in
                                PermissionMemorySettings.isEnabled = enabled
                                store.permissionMemoryEnabled = enabled
                            }
                        )
                    )
                    Text("When enabled, Bezel can replay stored Always rules for matching permissions. Off by default.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Section("Hooks") {
                    Button("Repair Claude hooks") {
                        Task {
                            let result = await ConfigInstaller.repairClaudeHooks()
                            hooksStatusOK = result.ok
                            hooksStatus = result.ok
                                ? "Repaired — socket verified."
                                : result.message
                        }
                    }
                    Button("Replace vibe-island / CodeIsland hooks") {
                        Task {
                            let result = await ConfigInstaller.replaceCompetingIslandHooks()
                            hooksStatusOK = result.ok
                            hooksStatus = result.ok
                                ? "Competing hooks removed; Bezel installed."
                                : result.message
                        }
                    }
                    Button("Remove Bezel hooks", role: .destructive) {
                        Task {
                            let ok = await ConfigInstaller.uninstallClaudeHooks()
                            hooksStatusOK = ok
                            hooksStatus = ok
                                ? "Bezel hooks removed; will not reinstall on launch."
                                : "Failed to remove Bezel hooks."
                        }
                    }
                    if !hooksStatus.isEmpty {
                        Label(hooksStatus, systemImage: hooksStatusOK ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(hooksStatusOK ? okGreen : danger)
                    }
                }
                Section("Onboarding") {
                    Button("Show onboarding again") {
                        OnboardingState.hasCompleted = false
                        OnboardingWindowController.shared.show(store: store)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 460, height: 520)
        .onAppear {
            launchAtLoginEnabled = LaunchAtLogin.isEnabled
        }
    }

    /// Brand strip — glyph, wordmark, version. Makes Settings feel like Bezel, not a system panel.
    private var header: some View {
        HStack(spacing: 12) {
            NotchGlyph()
                .frame(width: 64, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text("Bezel")
                    .font(.system(size: 14, weight: .semibold))
                Text(versionLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Circle()
                .fill(store.listenFailed ? danger : okGreen)
                .frame(width: 7, height: 7)
                .shadow(color: (store.listenFailed ? danger : okGreen).opacity(0.5), radius: 3)
                .help(store.listenFailed ? "Hook socket not listening" : "Listening for agent hooks")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (version, build) {
        case let (v?, b?): return "Version \(v) (\(b))"
        case let (v?, nil): return "Version \(v)"
        default: return "Development build"
        }
    }

    private func usageTint(_ usage: ClaudeUsageSnapshot) -> Color {
        let pct = Double(usage.primaryPercent ?? 0)
        if pct >= 80 { return danger }
        if pct >= 50 { return Color(red: 0.86, green: 0.72, blue: 0.48) }
        return accent
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = ""
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginEnabled = LaunchAtLogin.isEnabled
            if enabled && !launchAtLoginEnabled {
                launchAtLoginError =
                    "Could not enable Open at Login. Install Bezel as an app under /Applications, then try again."
            }
        } catch {
            launchAtLoginEnabled = LaunchAtLogin.isEnabled
            launchAtLoginError = "Could not update Open at Login: \(error.localizedDescription)"
        }
    }
}
