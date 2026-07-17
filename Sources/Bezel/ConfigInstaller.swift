import Foundation
import BezelCore

enum ConfigInstaller {
    static var bezelHome: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".bezel", isDirectory: true)
    }

    /// Install Claude Code hooks pointing at bezel-bridge. Safe to call repeatedly.
    static func installClaudeHooks() async -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: bezelHome, withIntermediateDirectories: true)

        guard let bridgeURL = locateBridgeBinary() else {
            NSLog("Bezel: bezel-bridge not found; writing hook stub only")
            return writeHookScript(bridgePath: bezelHome.appendingPathComponent("bezel-bridge").path)
                && mergeClaudeSettings()
        }

        let dest = bezelHome.appendingPathComponent("bezel-bridge")
        try? fm.removeItem(at: dest)
        do {
            try fm.copyItem(at: bridgeURL, to: dest)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
        } catch {
            NSLog("Bezel: failed to copy bridge: \(error)")
            return false
        }

        _ = writeHookScript(bridgePath: dest.path)
        return mergeClaudeSettings()
    }

    private static func locateBridgeBinary() -> URL? {
        // Prefer sibling of running executable (swift run / .build)
        if let exec = Bundle.main.executableURL?.deletingLastPathComponent() {
            let candidate = exec.appendingPathComponent("bezel-bridge")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        let build = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/debug/bezel-bridge")
        if FileManager.default.isExecutableFile(atPath: build.path) { return build }
        let release = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/release/bezel-bridge")
        if FileManager.default.isExecutableFile(atPath: release.path) { return release }
        return nil
    }

    @discardableResult
    private static func writeHookScript(bridgePath: String) -> Bool {
        let script = """
        #!/bin/bash
        # Bezel hook dispatcher — managed, do not edit
        set -euo pipefail
        BRIDGE="\(bridgePath)"
        if [[ -x "$BRIDGE" ]]; then
          exec "$BRIDGE" --source claude "$@"
        fi
        # Fallback: nc to socket
        SOCK="${BEZEL_SOCKET_PATH:-$HOME/Library/Application Support/Bezel/bezel.sock}"
        INPUT=$(cat)
        EVENT=$(printf '%s' "$INPUT" | /usr/bin/python3 -c 'import sys,json; print(json.load(sys.stdin).get("hook_event_name",""))' 2>/dev/null || true)
        TIMEOUT=2
        case "$EVENT" in
          PermissionRequest) TIMEOUT=86400 ;;
        esac
        printf '%s' "$INPUT" | /usr/bin/nc -U -w "$TIMEOUT" "$SOCK" || true
        exit 0
        """
        let url = bezelHome.appendingPathComponent("bezel-hook.sh")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return true
        } catch {
            NSLog("Bezel: write hook script failed: \(error)")
            return false
        }
    }

    private static func mergeClaudeSettings() -> Bool {
        let settingsURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/settings.json")
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
            return true
        } catch {
            NSLog("Bezel: failed to write Claude settings: \(error)")
            return false
        }
    }
}
