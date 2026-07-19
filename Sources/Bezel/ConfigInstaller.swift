import Foundation
import CryptoKit
import BezelCore

enum ConfigInstaller {
    static var bezelHome: URL {
        BezelInstallState.bezelHome()
    }

    enum InstallResult: Equatable {
        case success
        case failure(String)

        var ok: Bool {
            if case .success = self { return true }
            return false
        }

        var message: String {
            switch self {
            case .success: return "Ready."
            case .failure(let m): return m
            }
        }
    }

    /// Install Claude Code hooks pointing at bezel-bridge. Safe to call repeatedly.
    /// Fails closed: probes HookServer first; writes Claude settings only after probe succeeds.
    /// On late probe failure, rolls back Bezel hooks from settings.
    static func installClaudeHooks() async -> InstallResult {
        // Fail closed — never leave hooks registered if the socket is dead.
        guard SocketLiveness.probe() else {
            let msg = "Bezel socket not answering — is the app running?"
            NSLog("Bezel: socket liveness probe failed before install")
            return .failure(msg)
        }

        guard BezelInstallState.ensureBezelHome() else {
            return .failure("Could not create ~/.bezel with secure permissions.")
        }

        guard let bridgeURL = locateBridgeBinary() else {
            let msg = "bezel-bridge missing from the app bundle."
            NSLog("Bezel: \(msg)")
            return .failure(msg)
        }

        if !installBridge(from: bridgeURL) {
            return .failure("Could not install bezel-bridge into ~/.bezel.")
        }

        let dest = bezelHome.appendingPathComponent(BezelInstallState.bridgeFileName)
        guard writeHookScript(bridgePath: dest.path) else {
            return .failure("Could not write ~/.bezel/bezel-hook.sh.")
        }

        // Explicit Connect clears prior uninstall so sync may maintain the install.
        BezelInstallState.clearUserUninstalled()

        if let mergeError = mergeClaudeSettingsError() {
            return .failure(mergeError)
        }

        _ = ClaudeUsagePath.ensureCacheDirectory()
        injectStatusLineUsageBridge()

        // Belt-and-suspenders: if the socket dies during install, roll back settings.
        guard SocketLiveness.probe() else {
            NSLog("Bezel: socket liveness probe failed after merge — rolling back hooks")
            _ = stripClaudeSettings()
            let msg = "Bezel socket not answering — is the app running?"
            return .failure(msg)
        }
        return .success
    }

    /// Re-copy bridge, rewrite hook script, re-merge Claude settings, verify socket.
    static func repairClaudeHooks() async -> InstallResult {
        await installClaudeHooks()
    }

    /// Strip vibe-island/CodeIsland hooks, then install Bezel. Explicit user action only.
    static func replaceCompetingIslandHooks() async -> InstallResult {
        if !stripCompetingClaudeSettings() {
            return .failure("Could not remove competing island hooks from Claude settings.")
        }
        return await installClaudeHooks()
    }

    /// Remove Bezel hooks from Claude settings and delete managed `~/.bezel` artifacts.
    /// Writes a durable uninstall marker so launch sync never re-merges.
    static func uninstallClaudeHooks() async -> Bool {
        let settingsOK = stripClaudeSettings()
        let artifactsOK = BezelInstallState.removeManagedArtifacts()
        let markerOK = BezelInstallState.markUserUninstalled()
        if !settingsOK {
            NSLog("Bezel: uninstall — settings strip failed")
        }
        if !artifactsOK {
            NSLog("Bezel: uninstall — could not remove all managed ~/.bezel files")
        }
        if !markerOK {
            NSLog("Bezel: uninstall — could not write user-uninstalled marker")
        }
        return settingsOK && markerOK
    }

    /// After HookServer starts: keep bridge + hook script current, and re-merge
    /// Claude settings so lifecycle hooks (SessionEnd/Stop/…) stay registered.
    /// Never re-merges after an explicit user uninstall.
    @discardableResult
    static func syncInstalledBridgeIfNeeded() async -> Bool {
        if BezelInstallState.isUserUninstalled() {
            NSLog("Bezel: sync skipped — user uninstalled marker present")
            return true
        }

        let fm = FileManager.default
        let dest = bezelHome.appendingPathComponent(BezelInstallState.bridgeFileName)
        let hookURL = bezelHome.appendingPathComponent(BezelInstallState.hookFileName)

        let hasInstall = fm.fileExists(atPath: dest.path) || fm.fileExists(atPath: hookURL.path)
        guard hasInstall else {
            return true
        }

        guard let bridgeURL = locateBridgeBinary() else {
            NSLog("Bezel: installed hooks present but bundle bezel-bridge missing; cannot sync")
            return false
        }

        if bridgeNeedsSync(source: bridgeURL, dest: dest) {
            NSLog("Bezel: bridge version/hash mismatch — re-installing bridge + hook script")
            guard BezelInstallState.ensureBezelHome() else {
                return false
            }
            guard installBridge(from: bridgeURL) else {
                return false
            }
            guard writeHookScript(bridgePath: dest.path) else {
                return false
            }
        }

        // Idempotent: upgrades older installs to SessionEnd/Stop/UserPromptSubmit.
        if !mergeClaudeSettings() {
            NSLog("Bezel: settings re-merge skipped or failed (competing hooks or I/O)")
            return false
        }
        _ = ClaudeUsagePath.ensureCacheDirectory()
        injectStatusLineUsageBridge()
        return true
    }

    /// Ensures Claude’s statusLine writes `rate_limits` into `~/.bezel/cache/rl.json`.
    /// Does not replace the user’s statusLine — injects a managed bridge block.
    @discardableResult
    static func injectStatusLineUsageBridge() -> Bool {
        let home = BezelInstallState.homeDirectory()
        let statusURL = URL(fileURLWithPath: home)
            .appendingPathComponent(".claude/statusline.sh")
        let fm = FileManager.default
        guard fm.fileExists(atPath: statusURL.path),
              var script = try? String(contentsOf: statusURL, encoding: .utf8)
        else {
            return false
        }

        let begin = "# ── Bezel: rate_limits bridge (managed, do not remove) ───"
        let end = "# ── End Bezel bridge ─────────────────────────────────────"
        let block = """
        \(begin)
        _bezel_rl=$(printf '%s' "$input" | /usr/bin/jq -c '.rate_limits // empty' 2>/dev/null)
        if [ -n "$_bezel_rl" ]; then
          mkdir -p "$HOME/.bezel/cache" 2>/dev/null
          printf '%s\\n' "$_bezel_rl" > "$HOME/.bezel/cache/rl.json"
        fi
        \(end)
        """

        if script.contains(begin) {
            // Refresh managed block in place.
            if let startRange = script.range(of: begin),
               let endRange = script.range(of: end)
            {
                let full = startRange.lowerBound..<endRange.upperBound
                script.replaceSubrange(full, with: block.trimmingCharacters(in: .newlines))
            } else {
                return true
            }
        } else if let inputLine = script.range(of: "input=$(cat)") {
            let insertAt = inputLine.upperBound
            script.insert(contentsOf: "\n\n\(block)\n", at: insertAt)
        } else {
            script = block + "\n" + script
        }

        do {
            try script.write(to: statusURL, atomically: true, encoding: .utf8)
            return true
        } catch {
            NSLog("Bezel: statusLine usage bridge inject failed: \(error)")
            return false
        }
    }

    /// Locate bezel-bridge next to the running executable (Contents/MacOS).
    /// DEBUG builds may fall back to SPM `.build` outputs for local iteration.
    private static func locateBridgeBinary() -> URL? {
        if let execDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            let candidate = execDir.appendingPathComponent("bezel-bridge")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        #if DEBUG
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for rel in [".build/debug/bezel-bridge", ".build/release/bezel-bridge"] {
            let build = cwd.appendingPathComponent(rel)
            if FileManager.default.isExecutableFile(atPath: build.path) {
                return build
            }
        }
        #endif

        return nil
    }

    private static func installBridge(from bridgeURL: URL) -> Bool {
        let fm = FileManager.default
        let dest = bezelHome.appendingPathComponent(BezelInstallState.bridgeFileName)
        try? fm.removeItem(at: dest)
        do {
            try fm.copyItem(at: bridgeURL, to: dest)
            try fm.setAttributes(
                [.posixPermissions: BezelInstallState.managedExecutablePermissions],
                ofItemAtPath: dest.path
            )
            return true
        } catch {
            NSLog("Bezel: failed to copy bridge: \(error)")
            return false
        }
    }

    private static func bridgeNeedsSync(source: URL, dest: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dest.path) else { return true }

        let bundleVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let installedVersion = readInstalledBridgeVersion()
        if let bundleVersion, let installedVersion, bundleVersion != installedVersion {
            return true
        }

        guard let srcHash = sha256(of: source), let dstHash = sha256(of: dest) else {
            return true
        }
        return srcHash != dstHash
    }

    private static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1024 * 1024)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func readInstalledBridgeVersion() -> String? {
        let marker = bezelHome.appendingPathComponent(BezelInstallState.bridgeVersionFileName)
        guard let raw = try? String(contentsOf: marker, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func writeInstalledBridgeVersion() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let marker = bezelHome.appendingPathComponent(BezelInstallState.bridgeVersionFileName)
        try? version.write(to: marker, atomically: true, encoding: .utf8)
    }

    @discardableResult
    private static func writeHookScript(bridgePath: String) -> Bool {
        // Production hook: bridge only. No nc fallback, no silent empty ack on miss.
        let script = """
        #!/bin/bash
        # Bezel hook dispatcher — managed, do not edit
        set -euo pipefail
        BRIDGE="\(bridgePath)"
        if [[ ! -x "$BRIDGE" ]]; then
          echo "Bezel: bezel-bridge missing or not executable at $BRIDGE" >&2
          exit 1
        fi
        exec "$BRIDGE" --source claude "$@"
        """
        let url = bezelHome.appendingPathComponent(BezelInstallState.hookFileName)
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: BezelInstallState.managedExecutablePermissions],
                ofItemAtPath: url.path
            )
            writeInstalledBridgeVersion()
            return true
        } catch {
            NSLog("Bezel: write hook script failed: \(error)")
            return false
        }
    }

    /// - Returns: `nil` on success, user-facing error string on failure.
    private static func mergeClaudeSettingsError() -> String? {
        let settingsURL = claudeSettingsURL
        let fm = FileManager.default

        let existing: Data?
        if fm.fileExists(atPath: settingsURL.path) {
            existing = try? Data(contentsOf: settingsURL)
        } else {
            try? fm.createDirectory(
                at: settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            existing = nil
        }

        do {
            let out = try ClaudeSettingsMerger.mergeData(existing)
            try out.write(to: settingsURL, options: .atomic)
            return nil
        } catch let error as ClaudeSettingsMerger.MergeError {
            NSLog("Bezel: Connect refused — \(error.localizedDescription)")
            return error.localizedDescription
        } catch {
            NSLog("Bezel: failed to write Claude settings: \(error)")
            return "Could not write ~/.claude/settings.json."
        }
    }

    private static func mergeClaudeSettings() -> Bool {
        mergeClaudeSettingsError() == nil
    }

    private static func stripCompetingClaudeSettings() -> Bool {
        let settingsURL = claudeSettingsURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: settingsURL.path) else { return true }
        do {
            let existing = try Data(contentsOf: settingsURL)
            let out = try ClaudeSettingsMerger.stripCompetingData(existing)
            try out.write(to: settingsURL, options: .atomic)
            return true
        } catch {
            NSLog("Bezel: failed to strip competing hooks: \(error)")
            return false
        }
    }

    @discardableResult
    private static func stripClaudeSettings() -> Bool {
        let settingsURL = claudeSettingsURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: settingsURL.path) else {
            return true
        }
        do {
            let existing = try Data(contentsOf: settingsURL)
            let out = try ClaudeSettingsMerger.uninstallData(existing)
            try out.write(to: settingsURL, options: .atomic)
            return true
        } catch {
            NSLog("Bezel: failed to strip Claude settings: \(error)")
            return false
        }
    }

    private static var claudeSettingsURL: URL {
        URL(fileURLWithPath: BezelInstallState.homeDirectory())
            .appendingPathComponent(".claude/settings.json")
    }
}
