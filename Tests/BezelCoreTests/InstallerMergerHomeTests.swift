import Testing
import Foundation
import BezelCore

/// Temp-HOME style merger + install-state integration (no real ~/.claude mutation).
@Suite("Installer / merger temp HOME")
struct InstallerMergerHomeTests {
    @Test func mergeUninstallRoundTripUnderTempHome() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(atPath: home) }

        let hookPath = (home as NSString).appendingPathComponent(".bezel/bezel-hook.sh")
        #expect(ClaudeSettingsMerger.isBezelHookCommand(hookPath))

        // Seed Claude settings as if Connect wrote them under this HOME.
        let seeded: [String: Any] = [
            "hooks": [
                "SessionEnd": [[
                    "matcher": "",
                    "hooks": [[
                        "type": "command",
                        "command": hookPath,
                        "timeout": 10,
                    ]],
                ]],
                "PermissionRequest": [[
                    "matcher": "",
                    "hooks": [[
                        "type": "command",
                        "command": hookPath,
                        "timeout": 86400,
                    ]],
                ]],
                "PostToolUse": [[
                    "matcher": "",
                    "hooks": [[
                        "type": "command",
                        "command": "/opt/tools/bezel-logger.sh",
                        "timeout": 5,
                    ]],
                ]],
            ],
        ]
        let settingsDir = URL(fileURLWithPath: home).appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: settingsDir, withIntermediateDirectories: true)
        let settingsURL = settingsDir.appendingPathComponent("settings.json")
        let seededData = try JSONSerialization.data(withJSONObject: seeded, options: [.prettyPrinted, .sortedKeys])
        try seededData.write(to: settingsURL)

        let stripped = try ClaudeSettingsMerger.uninstallData(try Data(contentsOf: settingsURL))
        try stripped.write(to: settingsURL, options: .atomic)

        #expect(BezelInstallState.ensureBezelHome(home: home))
        let bridge = BezelInstallState.bezelHome(home: home)
            .appendingPathComponent(BezelInstallState.bridgeFileName)
        try Data("x".utf8).write(to: bridge)
        #expect(BezelInstallState.removeManagedArtifacts(home: home))
        #expect(BezelInstallState.markUserUninstalled(home: home))

        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any]
        let afterHooks = after?["hooks"] as? [String: Any] ?? [:]
        let allCommands = Self.collectCommands(from: afterHooks)
        #expect(allCommands.allSatisfy { !ClaudeSettingsMerger.isBezelHookCommand($0) })
        #expect(allCommands.contains("/opt/tools/bezel-logger.sh"))
        #expect(BezelInstallState.isUserUninstalled(home: home))
        #expect(!FileManager.default.fileExists(atPath: bridge.path))
    }

    @Test func idempotentMergeThenUninstallPreservesForeignHooks() throws {
        let once = try ClaudeSettingsMerger.mergeData(nil)
        let twice = try ClaudeSettingsMerger.mergeData(once)
        #expect(once == twice)

        let foreign: [String: Any] = [
            "hooks": [
                "Notification": [[
                    "matcher": "",
                    "hooks": [[
                        "type": "command",
                        "command": "/usr/local/bin/my-notify",
                        "timeout": 5,
                    ]],
                ]],
            ],
        ]
        let foreignData = try JSONSerialization.data(withJSONObject: foreign)
        let merged = try ClaudeSettingsMerger.mergeData(foreignData)
        let stripped = try ClaudeSettingsMerger.uninstallData(merged)
        let root = try JSONSerialization.jsonObject(with: stripped) as? [String: Any]
        let hooks = root?["hooks"] as? [String: Any]
        let notify = hooks?["Notification"] as? [[String: Any]]
        let cmd = ((notify?.first?["hooks"] as? [[String: Any]])?.first)?["command"] as? String
        #expect(cmd == "/usr/local/bin/my-notify")
    }

    @Test func isBezelHookCommandRejectsBareBezelSubstring() {
        #expect(!ClaudeSettingsMerger.isBezelHookCommand("/opt/tools/bezel-logger.sh"))
        #expect(!ClaudeSettingsMerger.isBezelHookCommand("echo bezel"))
        #expect(!ClaudeSettingsMerger.isBezelHookCommand("/usr/local/bin/bezel"))
        #expect(ClaudeSettingsMerger.isBezelHookCommand("$HOME/.bezel/bezel-hook.sh"))
        #expect(ClaudeSettingsMerger.isBezelHookCommand("/Users/x/.bezel/bezel-hook.sh"))
    }

    @Test func multiSourceHookCommands_emitSourceEnv() {
        let hook = "$HOME/.bezel/bezel-hook.sh"
        #expect(HookDispatcher.commandLine(source: .claude, hookPath: hook) == hook)
        #expect(HookDispatcher.commandLine(source: .codex, hookPath: hook) == "BEZEL_SOURCE=codex \(hook)")
        #expect(HookDispatcher.commandLine(source: .opencode, hookPath: hook) == "BEZEL_SOURCE=opencode \(hook)")
        #expect(HookDispatcher.commandLine(source: .cursor, hookPath: hook) == "BEZEL_SOURCE=cursor \(hook)")
        let script = HookDispatcher.script(bridgePath: "/Users/x/.bezel/bezel-bridge")
        #expect(script.contains("BEZEL_SOURCE:-claude"))
        #expect(!script.contains("--source claude \"")) // not hardcoded-only
        #expect(script.contains("--source \"$SOURCE\""))
    }

    @Test func uninstallScriptIdentityParity() {
        // Shared rules with scripts/uninstall-bezel.sh (no bare "bezel" substring).
        let cases: [(String, Bool)] = [
            ("$HOME/.bezel/bezel-hook.sh", true),
            ("/Users/rishabh/.bezel/bezel-hook.sh", true),
            ("bash /Users/x/.bezel/bezel-hook.sh", true),
            ("/opt/tools/bezel-logger.sh", false),
            ("/usr/local/bin/bezel", false),
        ]
        for (command, expected) in cases {
            #expect(
                ClaudeSettingsMerger.isBezelHookCommand(command) == expected,
                "command=\(command)"
            )
        }
    }

    private static func collectCommands(from hooks: [String: Any]) -> [String] {
        var commands: [String] = []
        for (_, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            for group in groups {
                guard let inner = group["hooks"] as? [[String: Any]] else { continue }
                for hook in inner {
                    if let c = hook["command"] as? String {
                        commands.append(c)
                    }
                }
            }
        }
        return commands
    }

    private func makeTempHome() throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bezel-merger-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }
}
