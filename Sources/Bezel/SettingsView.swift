import SwiftUI
import BezelCore

struct SettingsView: View {
    @Environment(SessionStore.self) private var store
    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var hooksStatus = ""

    var body: some View {
        Form {
            Section("Bezel") {
                LabeledContent("Socket") {
                    Text(SocketPath.resolve())
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent("Active sessions") {
                    Text("\(store.activeCount)")
                }
                Toggle(
                    "Open at login",
                    isOn: Binding(
                        get: { launchAtLoginEnabled },
                        set: { setLaunchAtLogin($0) }
                    )
                )
                Toggle(
                    "8-bit sound alerts",
                    isOn: Binding(
                        get: { BezelSound.isEnabled },
                        set: { BezelSound.isEnabled = $0 }
                    )
                )
            }
            Section("Hooks") {
                Button("Repair Claude hooks") {
                    Task {
                        let result = await ConfigInstaller.repairClaudeHooks()
                        hooksStatus = result.ok
                            ? "Repaired — socket verified."
                            : result.message
                    }
                }
                Button("Replace vibe-island / CodeIsland hooks") {
                    Task {
                        let result = await ConfigInstaller.replaceCompetingIslandHooks()
                        hooksStatus = result.ok
                            ? "Competing hooks removed; Bezel installed."
                            : result.message
                    }
                }
                Button("Remove Bezel hooks", role: .destructive) {
                    Task {
                        let ok = await ConfigInstaller.uninstallClaudeHooks()
                        hooksStatus = ok
                            ? "Bezel hooks removed from Claude settings."
                            : "Failed to remove Bezel hooks."
                    }
                }
                if !hooksStatus.isEmpty {
                    Text(hooksStatus)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
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
        .frame(width: 420, height: 400)
        .padding()
        .onAppear {
            launchAtLoginEnabled = LaunchAtLogin.isEnabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
        } catch {
            // Revert UI to real SMAppService status on failure.
        }
        launchAtLoginEnabled = LaunchAtLogin.isEnabled
    }
}
