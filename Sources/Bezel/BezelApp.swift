import SwiftUI
import AppKit
import BezelCore
import Darwin

@main
struct BezelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(appDelegate.store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = SessionStore()
    private var hookServer: HookServer?
    private var notchController: NotchController?
    private var statusItem: NSStatusItem?

    private var instanceLockFD: Int32 = -1

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Bridge closes without reading event acks; never die on SIGPIPE.
        signal(SIGPIPE, SIG_IGN)

        NSApp.setActivationPolicy(.accessory)

        // Single instance: flock + process check before unlinking the socket.
        if let lockFD = SingleInstanceLock.tryAcquire() {
            instanceLockFD = lockFD
        } else {
            NSLog("Bezel: another instance is already running — exiting")
            NSApp.terminate(nil)
            return
        }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "app.bezel.macos")
            .filter { !$0.isTerminated && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty {
            NSLog("Bezel: found other running Bezel process — exiting")
            NSApp.terminate(nil)
            return
        }

        // CRITICAL: listen before any hook install writes settings.
        let server = HookServer(store: store)
        hookServer = server
        server.start()

        // Keep ~/.bezel bridge + hook script aligned with this app binary.
        Task {
            _ = await ConfigInstaller.syncInstalledBridgeIfNeeded()
        }

        notchController = NotchController(store: store)
        notchController?.start()

        setupStatusItem()

        if !OnboardingState.hasCompleted {
            OnboardingWindowController.shared.show(store: store)
        }

        // Demo session so the notch is visibly alive during development.
        #if DEBUG
        store.upsert(
            Session(
                id: SessionID("demo"),
                source: .claude,
                phase: .idle,
                cwd: FileManager.default.currentDirectoryPath,
                title: "Bezel ready"
            )
        )
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        hookServer?.stop()
        notchController?.stop()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.topthird.inset.filled",
                accessibilityDescription: "Bezel"
            )
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Bezel", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Open Onboarding…",
            action: #selector(openOnboarding),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: "Quit Bezel",
            action: #selector(quit),
            keyEquivalent: "q"
        ))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func openOnboarding() {
        OnboardingWindowController.shared.show(store: store)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
