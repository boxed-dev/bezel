import Foundation
import CryptoKit
import BezelCore

enum ConfigInstaller {
    static var bezelHome: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".bezel", isDirectory: true)
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
    /// Fails closed if the bridge binary is not present in the app bundle.
    static func installClaudeHooks() async -> InstallResult {
        let fm = FileManager.default
        try? fm.createDirectory(at: bezelHome, withIntermediateDirectories: true)

        guard let bridgeURL = locateBridgeBinary() else {
            let msg = "bezel-bridge missing from the app bundle."
            NSLog("Bezel: \(msg)")
            return .failure(msg)
        }

        if !installBridge(from: bridgeURL) {
            return .failure("Could not install bezel-bridge into ~/.bezel.")
        }

        let dest = bezelHome.appendingPathComponent("bezel-bridge")
        guard writeHookScript(bridgePath: dest.path) else {
            return .failure("Could not write ~/.bezel/bezel-hook.sh.")
        }
        if let mergeError = mergeClaudeSettingsError() {
            return .failure(mergeError)
        }
        // Connect succeeds only when HookServer answers an empty ping.
        guard SocketLiveness.probe() else {
            let msg = "Bezel socket not answering — is the app running?"
            NSLog("Bezel: socket liveness probe failed after install")
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

    /// Remove Bezel hook entries from Claude settings (foreign hooks preserved).
    /// Does not delete `~/.bezel` binaries — use `scripts/uninstall-bezel.sh` for a full wipe.
    static func uninstallClaudeHooks() async -> Bool {
        stripClaudeSettings()
    }

    /// After HookServer starts: keep bridge + hook script current, and re-merge
    /// Claude settings so lifecycle hooks (SessionEnd/Stop/…) stay registered.
    @discardableResult
    static func syncInstalledBridgeIfNeeded() async -> Bool {
        let fm = FileManager.default
        let dest = bezelHome.appendingPathComponent("bezel-bridge")
        let hookURL = bezelHome.appendingPathComponent("bezel-hook.sh")

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
            try? fm.createDirectory(at: bezelHome, withIntermediateDirectories: true)
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
        return true
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
        let dest = bezelHome.appendingPathComponent("bezel-bridge")
        try? fm.removeItem(at: dest)
        do {
            try fm.copyItem(at: bridgeURL, to: dest)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
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
        let marker = bezelHome.appendingPathComponent("bridge-version")
        guard let raw = try? String(contentsOf: marker, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func writeInstalledBridgeVersion() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let marker = bezelHome.appendingPathComponent("bridge-version")
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
        let url = bezelHome.appendingPathComponent("bezel-hook.sh")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
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
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/settings.json")
    }
}
