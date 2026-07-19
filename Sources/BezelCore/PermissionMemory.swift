import Foundation

public struct PermissionMemoryEntry: Codable, Equatable, Sendable {
    public var tool: String
    public var ruleContent: String
    public var normalizedKey: String
    public var recordedAt: Date

    public init(tool: String, ruleContent: String, normalizedKey: String, recordedAt: Date = Date()) {
        self.tool = tool
        self.ruleContent = ruleContent
        self.normalizedKey = normalizedKey
        self.recordedAt = recordedAt
    }
}

/// Local Always-allow memory — opt-in only at the App layer.
public enum PermissionMemory {
    public static let fileName = "permission-memory.json"

    public static func fileURL(home: String? = nil) -> URL {
        BezelInstallState.bezelHome(home: home).appendingPathComponent(fileName)
    }

    public static func normalizeKey(tool: String, ruleContent: String) -> String {
        let t = tool.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let r = ruleContent.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(t)|\(r)"
    }

    public static func load(home: String? = nil) -> [PermissionMemoryEntry] {
        guard let data = try? Data(contentsOf: fileURL(home: home)),
              let entries = try? JSONDecoder().decode([PermissionMemoryEntry].self, from: data)
        else {
            return []
        }
        return entries
    }

    @discardableResult
    public static func save(_ entries: [PermissionMemoryEntry], home: String? = nil) -> Bool {
        guard BezelInstallState.ensureBezelHome(home: home) else { return false }
        guard let data = try? JSONEncoder().encode(entries) else { return false }
        do {
            try data.write(to: fileURL(home: home), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public static func recordAlways(tool: String, ruleContent: String, home: String? = nil) -> Bool {
        let key = normalizeKey(tool: tool, ruleContent: ruleContent)
        var entries = load(home: home)
        entries.removeAll { $0.normalizedKey == key }
        entries.insert(
            PermissionMemoryEntry(tool: tool, ruleContent: ruleContent, normalizedKey: key),
            at: 0
        )
        return save(entries, home: home)
    }

    /// Match stored Always rule when Claude sent no suggestions — exact tool+rule key only.
    public static func matchingSuggestions(
        tool: String?,
        ruleContent: String?,
        suggestions: [[String: Any]],
        home: String? = nil
    ) -> [[String: Any]]? {
        guard suggestions.isEmpty else { return nil }
        guard let entry = matchEntry(tool: tool, ruleContent: ruleContent, home: home) else { return nil }
        return [[
            "type": "addRules",
            "rules": [[
                "toolName": entry.tool,
                "ruleContent": entry.ruleContent,
            ]],
        ]]
    }

    public static func matchEntry(
        tool: String?,
        ruleContent: String?,
        home: String? = nil
    ) -> PermissionMemoryEntry? {
        guard let tool, let ruleContent else { return nil }
        let key = normalizeKey(tool: tool, ruleContent: ruleContent)
        return load(home: home).first { $0.normalizedKey == key }
    }
}
