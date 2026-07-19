import Testing
import Foundation
import BezelCore

@Suite("CompetingMarkers")
struct CompetingMarkersTests {
    @Test(arguments: [
        "open-island",
        "claude-island",
        "vibehub",
        "vibenotch",
        "vibe-island",
        "code-island",
        "vibe_island",
        "vibeisland",
        "codeisland",
        "code_island",
    ])
    func mergeThrowsForCompetingMarker(_ marker: String) throws {
        let root: [String: Any] = [
            "hooks": [
                "SessionStart": [[
                    "matcher": "",
                    "hooks": [[
                        "type": "command",
                        "command": "/opt/\(marker)/hook.sh",
                        "timeout": 10,
                    ]],
                ]],
            ],
        ]
        let found = ClaudeSettingsMerger.competingHookCommands(in: root)
        #expect(!found.isEmpty)
        #expect(found.contains { $0.lowercased().contains(marker) })

        do {
            _ = try ClaudeSettingsMerger.merge(into: root)
            Issue.record("expected competingHooks for \(marker)")
        } catch ClaudeSettingsMerger.MergeError.competingHooks(let commands) {
            #expect(commands.contains { $0.lowercased().contains(marker) })
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test(arguments: ["vibenotch", "open-island", "claude-island", "vibehub"])
    func stripCompetingRemovesMarker(_ marker: String) throws {
        let root: [String: Any] = [
            "hooks": [
                "Notification": [[
                    "matcher": "",
                    "hooks": [[
                        "type": "command",
                        "command": "/bin/\(marker)-alert",
                        "timeout": 5,
                    ]],
                ]],
            ],
        ]
        let stripped = ClaudeSettingsMerger.stripCompeting(from: root)
        let hooks = stripped["hooks"] as? [String: Any] ?? [:]
        #expect(hooks.isEmpty)
    }

    @Test func mergeSucceedsWithoutCompetingMarkers() throws {
        let root: [String: Any] = [
            "hooks": [
                "SessionStart": [[
                    "matcher": "",
                    "hooks": [[
                        "type": "command",
                        "command": "/opt/tools/bezel-logger.sh",
                        "timeout": 10,
                    ]],
                ]],
            ],
        ]
        let merged = try ClaudeSettingsMerger.merge(into: root)
        let hooks = merged["hooks"] as? [String: Any] ?? [:]
        #expect(!hooks.isEmpty)
    }
}
