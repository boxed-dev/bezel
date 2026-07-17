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
}
