import SwiftUI
import BezelCore

struct SettingsView: View {
    @Environment(SessionStore.self) private var store
    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError = ""
    @State private var hooksStatus = ""
    @State private var hooksStatusOK = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                Section("Status") {
                    LabeledContent("Socket") {
                        Text(SocketPath.resolve())
                            .font(PacManTheme.scoreFont(size: 11, weight: .regular))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Active sessions") {
                        Text("\(store.activeCount)")
                            .font(PacManTheme.scoreFont(size: 13))
                            .monospacedDigit()
                            .foregroundStyle(PacManTheme.pacYellow)
                    }
                    if let usage = store.usage {
                        LabeledContent("Claude usage") {
                            Text(usage.helpText)
                                .font(PacManTheme.scoreFont(size: 11, weight: .semibold))
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
                        .foregroundStyle(PacManTheme.blinky)
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
                            .foregroundStyle(PacManTheme.blinky)
                    }
                    Toggle(
                        "Arcade sound alerts",
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
                    Button("Install Codex hooks") {
                        Task {
                            let result = await ConfigInstaller.installCodexHooks()
                            hooksStatusOK = result.ok
                            hooksStatus = result.ok
                                ? "Codex hooks installed (~/.codex/hooks.json)."
                                : result.message
                        }
                    }
                    Button("Install Cursor hooks") {
                        Task {
                            let result = await ConfigInstaller.installCursorHooks()
                            hooksStatusOK = result.ok
                            hooksStatus = result.ok
                                ? "Cursor hooks installed (~/.cursor/hooks.json)."
                                : result.message
                        }
                    }
                    Button("Connect all agents") {
                        Task {
                            let result = await ConfigInstaller.installConnectedAgentHooks()
                            hooksStatusOK = result.ok
                            hooksStatus = result.ok
                                ? "Claude + Codex + Cursor hooks connected."
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
                    // Competing-island repair stays available but is not primary chrome (E3).
                    DisclosureGroup("Repair competing hooks") {
                        Text("Only if Connect fails because vibe-island or CodeIsland owns Claude hooks. Never runs automatically.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Button("Replace vibe-island / CodeIsland hooks") {
                            Task {
                                let result = await ConfigInstaller.replaceCompetingIslandHooks()
                                hooksStatusOK = result.ok
                                hooksStatus = result.ok
                                    ? "Competing hooks removed; Bezel installed."
                                    : result.message
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    }
                    if !hooksStatus.isEmpty {
                        Label(hooksStatus, systemImage: hooksStatusOK ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(hooksStatusOK ? PacManTheme.moss : PacManTheme.blinky)
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
        .preferredColorScheme(.dark)
        .onAppear {
            launchAtLoginEnabled = LaunchAtLogin.isEnabled
        }
    }

    private var header: some View {
        ZStack {
            PacManTheme.maze
            MazePelletField(spacing: 14, opacity: 0.08)
            LinearGradient(
                colors: [PacManTheme.mazeWall.opacity(0.35), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            HStack(spacing: 12) {
                PacManNotchMark(width: 72, height: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text("BEZEL")
                        .font(PacManTheme.scoreFont(size: 13, weight: .heavy))
                        .tracking(2.2)
                        .foregroundStyle(PacManTheme.pacYellow)
                    Text(versionLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(PacManTheme.secondary)
                }
                Spacer()
                Group {
                    if store.listenFailed {
                        PowerPelletPulse(diameter: 8)
                    } else {
                        PacManChomper(diameter: 10)
                    }
                }
                .help(store.listenFailed ? "Hook socket not listening" : "Listening for agent hooks")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(height: 56)
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
        PacManTheme.usageColor(Double(usage.primaryPercent ?? 0))
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
