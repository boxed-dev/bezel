import SwiftUI
import BezelCore

struct SettingsView: View {
    @Environment(SessionStore.self) private var store

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
            }
            Section("Hooks") {
                Button("Reinstall Claude hooks") {
                    Task { _ = await ConfigInstaller.installClaudeHooks() }
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
        .frame(width: 420, height: 280)
        .padding()
    }
}
