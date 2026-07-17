import Testing
import Foundation
import BezelCore

@Suite("ClaudeSettingsMerger")
struct ClaudeSettingsMergerTests {
    @Test func emptyRootGetsBezelHooks() throws {
        let data = try ClaudeSettingsMerger.mergeData(nil)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hooks = root?["hooks"] as? [String: Any]
        #expect(hooks?["PermissionRequest"] != nil)
        #expect(hooks?["SessionStart"] != nil)
        let pre = hooks?["PreToolUse"] as? [[String: Any]]
        let matchers = pre?.compactMap { $0["matcher"] as? String } ?? []
        #expect(matchers.contains(where: { $0.contains("AskUserQuestion") }))
        let interactive = pre?.first { ($0["matcher"] as? String)?.contains("AskUserQuestion") == true }
        let timeout = ((interactive?["hooks"] as? [[String: Any]])?.first)?["timeout"] as? Int
        #expect(timeout == 600)
    }

    /// M1: no Bezel catch-all PreToolUse alongside AskUserQuestion (double-bind / 10s kill).
    @Test func preToolUseHasNoBezelCatchAll() throws {
        let data = try ClaudeSettingsMerger.mergeData(nil)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let pre = (root?["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]] ?? []
        let bezelGroups = pre.filter { group in
            ((group["hooks"] as? [[String: Any]]) ?? []).contains { hook in
                ClaudeSettingsMerger.isBezelHookCommand(hook["command"] as? String ?? "")
            }
        }
        #expect(bezelGroups.count == 1)
        let matcher = bezelGroups[0]["matcher"] as? String ?? ""
        #expect(matcher.contains("AskUserQuestion"))
        #expect(matcher != "")
        #expect(bezelGroups.allSatisfy { ($0["matcher"] as? String ?? "") != "" })
    }

    @Test func refusesCompetingIslandHooks() throws {
        let existing: [String: Any] = [
            "hooks": [
                "PermissionRequest": [[
                    "matcher": "",
                    "hooks": [[
                        "type": "command",
                        "command": "$HOME/.vibe-island/hook.sh",
                        "timeout": 10,
                    ]],
                ]],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: existing)
        do {
            _ = try ClaudeSettingsMerger.mergeData(data)
            Issue.record("expected competingHooks error")
        } catch let ClaudeSettingsMerger.MergeError.competingHooks(commands) {
            #expect(commands.contains(where: { $0.contains("vibe-island") }))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test func preservesForeignHooks() throws {
        let existing: [String: Any] = [
            "hooks": [
                "PreToolUse": [[
                    "matcher": "Bash",
                    "hooks": [["type": "command", "command": "/usr/local/bin/other-hook", "timeout": 5]],
                ]],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: existing)
        let merged = try ClaudeSettingsMerger.mergeData(data)
        let root = try JSONSerialization.jsonObject(with: merged) as? [String: Any]
        let pre = (root?["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]] ?? []
        let commands = pre.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }
        #expect(commands.contains("/usr/local/bin/other-hook"))
        #expect(commands.contains(where: { $0.contains("bezel") }))
    }

    @Test func mergeIsIdempotent() throws {
        let once = try ClaudeSettingsMerger.mergeData(nil)
        let twice = try ClaudeSettingsMerger.mergeData(once)
        let a = try JSONSerialization.jsonObject(with: once)
        let b = try JSONSerialization.jsonObject(with: twice)
        let ca = try JSONSerialization.data(withJSONObject: a, options: [.sortedKeys])
        let cb = try JSONSerialization.data(withJSONObject: b, options: [.sortedKeys])
        #expect(ca == cb)

        let root = try JSONSerialization.jsonObject(with: twice) as? [String: Any]
        let perm = (root?["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]] ?? []
        let bezelCount = perm.filter { group in
            ((group["hooks"] as? [[String: Any]]) ?? []).contains { hook in
                (hook["command"] as? String)?.contains("bezel") == true
            }
        }.count
        #expect(bezelCount == 1)
    }

    @Test func uninstallStripsBezelPreservesForeign() throws {
        let existing: [String: Any] = [
            "model": "sonnet",
            "hooks": [
                "PreToolUse": [[
                    "matcher": "Bash",
                    "hooks": [["type": "command", "command": "/usr/local/bin/other-hook", "timeout": 5]],
                ]],
                "Stop": [[
                    "matcher": "",
                    "hooks": [["type": "command", "command": "/opt/foreign/stop.sh", "timeout": 3]],
                ]],
            ],
        ]
        let merged = try ClaudeSettingsMerger.mergeData(
            try JSONSerialization.data(withJSONObject: existing)
        )
        let stripped = try ClaudeSettingsMerger.uninstallData(merged)
        let root = try JSONSerialization.jsonObject(with: stripped) as? [String: Any]
        #expect(root?["model"] as? String == "sonnet")

        let hooks = root?["hooks"] as? [String: Any] ?? [:]
        #expect(hooks["PermissionRequest"] == nil)
        #expect(hooks["SessionStart"] == nil)

        let allCommands = hooks.values
            .compactMap { $0 as? [[String: Any]] }
            .flatMap { $0 }
            .flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }
        #expect(allCommands.contains("/usr/local/bin/other-hook"))
        #expect(allCommands.contains("/opt/foreign/stop.sh"))
        #expect(allCommands.allSatisfy { !ClaudeSettingsMerger.isBezelHookCommand($0) })
    }

    @Test func uninstallIsIdempotentOnEmpty() throws {
        let once = try ClaudeSettingsMerger.uninstallData(nil)
        let twice = try ClaudeSettingsMerger.uninstallData(once)
        #expect(JSONCanonical.equal(once, twice))
    }

    /// File I/O under a temp directory only — never touches real ~/.claude.
    @Test func uninstallRoundTripOnTempHomeSettingsFile() throws {
        let fm = FileManager.default
        let tmpHome = fm.temporaryDirectory
            .appendingPathComponent("bezel-merger-home-\(UUID().uuidString)", isDirectory: true)
        let settingsURL = tmpHome.appendingPathComponent(".claude/settings.json")
        try fm.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? fm.removeItem(at: tmpHome) }

        let realClaude = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/settings.json")
        #expect(settingsURL.path != realClaude.path)

        let seed: [String: Any] = [
            "hooks": [
                "PreToolUse": [[
                    "matcher": "Bash",
                    "hooks": [["type": "command", "command": "/tmp/foreign-hook.sh", "timeout": 5]],
                ]],
            ],
        ]
        let merged = try ClaudeSettingsMerger.mergeData(
            try JSONSerialization.data(withJSONObject: seed)
        )
        try merged.write(to: settingsURL, options: .atomic)

        let fromDisk = try Data(contentsOf: settingsURL)
        let stripped = try ClaudeSettingsMerger.uninstallData(fromDisk)
        try stripped.write(to: settingsURL, options: .atomic)

        let final = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any]
        let pre = (final?["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]] ?? []
        let commands = pre.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }
        #expect(commands == ["/tmp/foreign-hook.sh"])
        #expect(!fm.fileExists(atPath: realClaude.path) || settingsURL.path.hasPrefix(tmpHome.path))
    }

    @Test func registersLifecycleHooksSessionEndStopUserPromptSubmit() throws {
        let data = try ClaudeSettingsMerger.mergeData(nil)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hooks = root?["hooks"] as? [String: Any]
        for name in ["SessionEnd", "Stop", "UserPromptSubmit", "SessionStart", "PostToolUse"] {
            #expect(hooks?[name] != nil, "missing \(name)")
            let groups = hooks?[name] as? [[String: Any]] ?? []
            let timeout = ((groups.first?["hooks"] as? [[String: Any]])?.first)?["timeout"] as? Int
            #expect(timeout == 10, "\(name) timeout")
        }
        let perm = hooks?["PermissionRequest"] as? [[String: Any]] ?? []
        let permTimeout = ((perm.first?["hooks"] as? [[String: Any]])?.first)?["timeout"] as? Int
        #expect(permTimeout == 86400)
    }

    @Test func preservesForeignAskUserQuestionMatcher() throws {
        let existing: [String: Any] = [
            "hooks": [
                "PreToolUse": [[
                    "matcher": "AskUserQuestion",
                    "hooks": [["type": "command", "command": "/usr/local/bin/my-ask-hook", "timeout": 30]],
                ]],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: existing)
        let merged = try ClaudeSettingsMerger.mergeData(data)
        let root = try JSONSerialization.jsonObject(with: merged) as? [String: Any]
        let pre = (root?["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]] ?? []
        let commands = pre.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }
        #expect(commands.contains("/usr/local/bin/my-ask-hook"))
        #expect(commands.contains(ClaudeSettingsMerger.hookCommand))
    }

    @Test func bezelLoggerPathIsNotBezelHook() {
        #expect(!ClaudeSettingsMerger.isBezelHookCommand("/opt/tools/bezel-logger.sh"))
        #expect(ClaudeSettingsMerger.isBezelHookCommand(ClaudeSettingsMerger.hookCommand))
        #expect(ClaudeSettingsMerger.isBezelHookCommand("/Users/x/.bezel/bezel-hook.sh"))
        #expect(ClaudeSettingsMerger.isBezelHookCommand("$HOME/.bezel/bezel-hook.sh"))
    }

    @Test func stripCompetingRemovesIslandPreservesForeign() throws {
        let existing: [String: Any] = [
            "hooks": [
                "PermissionRequest": [[
                    "matcher": "",
                    "hooks": [[
                        "type": "command",
                        "command": "$HOME/.vibe-island/hook.sh",
                        "timeout": 10,
                    ]],
                ]],
                "PreToolUse": [[
                    "matcher": "Bash",
                    "hooks": [["type": "command", "command": "/usr/local/bin/other-hook", "timeout": 5]],
                ]],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: existing)
        let stripped = try ClaudeSettingsMerger.stripCompetingData(data)
        let root = try JSONSerialization.jsonObject(with: stripped) as? [String: Any]
        let hooks = root?["hooks"] as? [String: Any] ?? [:]
        #expect(hooks["PermissionRequest"] == nil)
        let pre = hooks["PreToolUse"] as? [[String: Any]] ?? []
        let commands = pre.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }
        #expect(commands == ["/usr/local/bin/other-hook"])
    }
}
