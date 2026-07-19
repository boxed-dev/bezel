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
    private var usageMonitor: UsageMonitor?
    private var statusItem: NSStatusItem?
    private var globalHotkeyMonitor: Any?
    private var localHotkeyMonitor: Any?

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
        let listening = server.start()
        store.setHookServerListening(listening)
        if !listening {
            NSLog("Bezel: HookServer failed to start — Connect will be blocked until restart")
        }

        // Keep ~/.bezel bridge + hook script aligned with this app binary.
        // Respects user-uninstalled marker — never re-merges after Settings Remove.
        // Skip sync when bind failed — do not pretend the socket is live.
        if listening {
            Task {
                _ = await ConfigInstaller.syncInstalledBridgeIfNeeded()
            }
        }

        notchController = NotchController(store: store)
        notchController?.start()

        store.permissionMemoryEnabled = PermissionMemorySettings.isEnabled

        let usage = UsageMonitor(store: store)
        usageMonitor = usage
        usage.start()

        // Keep Claude statusLine → ~/.bezel/cache/rl.json bridge alive.
        ConfigInstaller.injectStatusLineUsageBridge()

        setupStatusItem()
        setupDecisionHotkeys()

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
        if let globalHotkeyMonitor {
            NSEvent.removeMonitor(globalHotkeyMonitor)
        }
        if let localHotkeyMonitor {
            NSEvent.removeMonitor(localHotkeyMonitor)
        }
        globalHotkeyMonitor = nil
        localHotkeyMonitor = nil
        usageMonitor?.stop()
        usageMonitor = nil
        hookServer?.stop()
        store.setHookServerListening(false)
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
        if store.listenFailed {
            let warn = NSMenuItem(
                title: "Hook socket not listening",
                action: nil,
                keyEquivalent: ""
            )
            warn.isEnabled = false
            menu.addItem(warn)
            menu.addItem(.separator())
        }
        menu.addItem(NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        ))
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

    /// LSUIElement-friendly: activate + open the SwiftUI Settings scene.
    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        // macOS 13+: showSettingsWindow:; older builds used showPreferencesWindow:.
        let settingsSelector = Selector(("showSettingsWindow:"))
        if NSApp.responds(to: settingsSelector) {
            NSApp.sendAction(settingsSelector, to: nil, from: nil)
            return
        }
        let prefsSelector = Selector(("showPreferencesWindow:"))
        if NSApp.responds(to: prefsSelector) {
            NSApp.sendAction(prefsSelector, to: nil, from: nil)
        }
    }

    @objc private func openOnboarding() {
        OnboardingWindowController.shared.show(store: store)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// ⌘Y Allow / ⌘N Deny when the notch needs attention — global while other apps are frontmost.
    private func setupDecisionHotkeys() {
        globalHotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handleDecisionHotkey(event, swallow: false)
        }
        if globalHotkeyMonitor == nil {
            NSLog(
                "Bezel: global hotkeys unavailable — grant Accessibility for ⌘Y/⌘N while other apps are frontmost"
            )
        }

        localHotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.handleDecisionHotkey(event, swallow: true) {
                return nil
            }
            return event
        }
        if localHotkeyMonitor == nil {
            NSLog("Bezel: local hotkey monitor failed to install")
        }
    }

    /// - Returns: `true` when the event was handled (and may be swallowed locally).
    @discardableResult
    private func handleDecisionHotkey(_ event: NSEvent, swallow: Bool) -> Bool {
        guard store.needsAttention else { return false }
        guard event.modifierFlags.contains(.command) else { return false }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        switch key {
        case "y":
            if event.modifierFlags.contains(.shift) {
                guard store.pendingPermission != nil, store.permissionHasAlwaysOption else { return false }
                store.resolvePermission(allow: true, always: true)
                BezelSound.play(.allow)
                return swallow
            }
            if store.pendingPermission != nil {
                store.resolvePermission(allow: true, always: false)
                BezelSound.play(.allow)
                return swallow
            }
            if store.pendingPlanReview != nil {
                store.resolvePlanReview(approve: true)
                BezelSound.play(.allow)
                return swallow
            }
            return false
        case "n":
            if store.pendingPermission != nil {
                store.resolvePermission(allow: false)
                BezelSound.play(.deny)
                return swallow
            }
            if store.pendingPlanReview != nil {
                store.resolvePlanReview(approve: false)
                BezelSound.play(.deny)
                return swallow
            }
            return false
        default:
            return false
        }
    }
}
