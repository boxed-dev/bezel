import Testing
import Foundation
import BezelCore

@Suite("PermissionMemory")
struct PermissionMemoryTests {
    @Test func normalizeKeyLowercases() {
        #expect(PermissionMemory.normalizeKey(tool: "Bash", ruleContent: "npm test *") == "bash|npm test *")
    }

    @Test func recordAndLoadRoundtrip() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("bezel-perm-mem-\(UUID().uuidString)", isDirectory: true)
            .path
        defer { try? FileManager.default.removeItem(atPath: home) }

        #expect(PermissionMemory.recordAlways(tool: "Bash", ruleContent: "git status", home: home))
        let entries = PermissionMemory.load(home: home)
        #expect(entries.count == 1)
        #expect(entries[0].tool == "Bash")
        #expect(entries[0].ruleContent == "git status")
    }

    @Test func matchingSuggestionsWhenEmpty() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("bezel-perm-mem-\(UUID().uuidString)", isDirectory: true)
            .path
        defer { try? FileManager.default.removeItem(atPath: home) }

        #expect(PermissionMemory.recordAlways(tool: "Read", ruleContent: "/Users/*", home: home))
        let hit = PermissionMemory.matchingSuggestions(
            tool: "Read",
            ruleContent: "/Users/*",
            suggestions: [],
            home: home
        )
        #expect(hit != nil)
        #expect(hit?.first?["type"] as? String == "addRules")
    }

    @Test func noToolOnlyMatchWhenRuleDiffers() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("bezel-perm-mem-\(UUID().uuidString)", isDirectory: true)
            .path
        defer { try? FileManager.default.removeItem(atPath: home) }

        #expect(PermissionMemory.recordAlways(tool: "Bash", ruleContent: "git status", home: home))
        #expect(PermissionMemory.recordAlways(tool: "Bash", ruleContent: "rm -rf *", home: home))
        let hit = PermissionMemory.matchingSuggestions(
            tool: "Bash",
            ruleContent: "npm test",
            suggestions: [],
            home: home
        )
        #expect(hit == nil)
    }

    @Test func noMatchWhenSuggestionsPresent() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("bezel-perm-mem-\(UUID().uuidString)", isDirectory: true)
            .path
        defer { try? FileManager.default.removeItem(atPath: home) }

        #expect(PermissionMemory.recordAlways(tool: "Bash", ruleContent: "ls", home: home))
        let suggestions: [[String: Any]] = [["type": "addRules", "rules": []]]
        #expect(PermissionMemory.matchingSuggestions(
            tool: "Bash",
            ruleContent: "ls",
            suggestions: suggestions,
            home: home
        ) == nil)
    }

    @Test func matchEntryByKey() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("bezel-perm-mem-\(UUID().uuidString)", isDirectory: true)
            .path
        defer { try? FileManager.default.removeItem(atPath: home) }

        #expect(PermissionMemory.recordAlways(tool: "Write", ruleContent: "*.swift", home: home))
        let hit = PermissionMemory.matchEntry(tool: "Write", ruleContent: "*.swift", home: home)
        #expect(hit?.tool == "Write")
    }
}
