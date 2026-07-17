import Foundation

public enum ClaudeSettingsMerger {
    /// Portable form used in docs/tests.
    public static let hookCommandPortable = "$HOME/.bezel/bezel-hook.sh"

    /// Absolute path written into settings.json (Claude does not always expand $HOME).
    public static var hookCommand: String {
        let home = ProcessInfo.processInfo.environment["HOME"]
            ?? NSHomeDirectory()
        return (home as NSString).appendingPathComponent(".bezel/bezel-hook.sh")
    }

    /// Markers for notch-hook competitors that must not stack with Bezel.
    public static let competingCommandMarkers: [String] = [
        "vibe-island",
        "vibe_island",
        "vibeisland",
        "codeisland",
        "code-island",
        "code_island",
    ]

    public enum MergeError: Error, Equatable, LocalizedError {
        case competingHooks([String])

        public var errorDescription: String? {
            switch self {
            case .competingHooks(let commands):
                let listed = commands.joined(separator: ", ")
                return "Competing Claude hooks detected (\(listed)). Remove vibe-island/CodeIsland hooks before connecting Bezel."
            }
        }
    }

    /// Catch-all managed events — intentionally excludes PreToolUse.
    /// Interactive PreToolUse (AskUserQuestion|ExitPlanMode) is registered separately
    /// with a long timeout so a 10s catch-all cannot double-bind or kill the wait.
    /// SessionEnd/Stop/UserPromptSubmit are required so sessions can leave `.working`.
    private static let managedEvents: [(name: String, timeout: Int)] = [
        ("SessionStart", 10),
        ("SessionEnd", 10),
        ("Stop", 10),
        ("UserPromptSubmit", 10),
        ("PostToolUse", 10),
        ("PermissionRequest", 86400),
        ("Notification", 86400),
    ]

    /// Merge Bezel hooks into Claude settings JSON object. Idempotent.
    /// - Throws: ``MergeError/competingHooks`` when vibe-island/CodeIsland hooks are present.
    public static func merge(into root: [String: Any]) throws -> [String: Any] {
        let competing = competingHookCommands(in: root)
        if !competing.isEmpty {
            throw MergeError.competingHooks(competing)
        }

        var result = root
        var hooks = result["hooks"] as? [String: Any] ?? [:]

        for (name, timeout) in managedEvents {
            var list = hooks[name] as? [[String: Any]] ?? []
            list = removeBezelEntries(from: list)
            list.append(hookGroup(matcher: "", timeout: timeout))
            hooks[name] = list
        }

        // PreToolUse: interactive matcher only (no Bezel catch-all).
        // Only strip Bezel-managed groups — never delete foreign AskUserQuestion hooks.
        var pre = hooks["PreToolUse"] as? [[String: Any]] ?? []
        pre = removeBezelEntries(from: pre)
        pre.insert(
            hookGroup(matcher: "AskUserQuestion|ExitPlanMode", timeout: 600),
            at: 0
        )
        hooks["PreToolUse"] = pre

        result["hooks"] = hooks
        return result
    }

    public static func mergeData(_ data: Data?) throws -> Data {
        let root = try decodeRoot(data)
        let merged = try merge(into: root)
        return try encodeRoot(merged)
    }

    /// Strip all Bezel-managed hook entries, preserving foreign hooks and other settings keys.
    public static func uninstall(from root: [String: Any]) -> [String: Any] {
        var result = root
        guard let hooks = result["hooks"] as? [String: Any] else {
            return result
        }

        var cleaned: [String: Any] = [:]
        for (event, value) in hooks {
            guard let list = value as? [[String: Any]] else {
                cleaned[event] = value
                continue
            }
            let stripped = removeBezelEntries(from: list)
            if !stripped.isEmpty {
                cleaned[event] = stripped
            }
        }

        if cleaned.isEmpty {
            result.removeValue(forKey: "hooks")
        } else {
            result["hooks"] = cleaned
        }
        return result
    }

    /// Strip Bezel hooks from Claude settings JSON. Idempotent; safe on nil/empty input.
    public static func uninstallData(_ data: Data?) throws -> Data {
        let root = try decodeRoot(data)
        let stripped = uninstall(from: root)
        return try encodeRoot(stripped)
    }

    /// Remove vibe-island / CodeIsland hook groups only (never touches Bezel or unrelated hooks).
    public static func stripCompeting(from root: [String: Any]) -> [String: Any] {
        var result = root
        guard let hooks = result["hooks"] as? [String: Any] else { return result }

        var cleaned: [String: Any] = [:]
        for (event, value) in hooks {
            guard let list = value as? [[String: Any]] else {
                cleaned[event] = value
                continue
            }
            let kept = list.filter { group in
                guard let inner = group["hooks"] as? [[String: Any]] else { return true }
                let hasCompeting = inner.contains { hook in
                    guard let command = hook["command"] as? String else { return false }
                    let lower = command.lowercased()
                    return competingCommandMarkers.contains(where: { lower.contains($0) })
                }
                return !hasCompeting
            }
            if !kept.isEmpty {
                cleaned[event] = kept
            }
        }
        if cleaned.isEmpty {
            result.removeValue(forKey: "hooks")
        } else {
            result["hooks"] = cleaned
        }
        return result
    }

    public static func stripCompetingData(_ data: Data?) throws -> Data {
        let root = try decodeRoot(data)
        return try encodeRoot(stripCompeting(from: root))
    }

    /// True when a hook command string is managed by Bezel.
    /// Exact identity only — never a bare substring match on "bezel".
        public static func isBezelHookCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let unquoted = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if unquoted == hookCommand || unquoted == hookCommandPortable { return true }
        if unquoted.hasSuffix("/.bezel/bezel-hook.sh") { return true }
        if unquoted.hasSuffix("/bezel-hook.sh") { return true }
        // Shell wrappers that only invoke our hook.
        if unquoted.contains("/.bezel/bezel-hook.sh") { return true }
        return false
    }


    /// Commands from non-Bezel hooks that look like vibe-island / CodeIsland.
    public static func competingHookCommands(in root: [String: Any]) -> [String] {
        guard let hooks = root["hooks"] as? [String: Any] else { return [] }
        var found: [String] = []
        var seen = Set<String>()
        for (_, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            for group in groups {
                guard let inner = group["hooks"] as? [[String: Any]] else { continue }
                for hook in inner {
                    guard let command = hook["command"] as? String else { continue }
                    let lower = command.lowercased()
                    if isBezelHookCommand(command) { continue }
                    if competingCommandMarkers.contains(where: { lower.contains($0) }) {
                        if seen.insert(command).inserted {
                            found.append(command)
                        }
                    }
                }
            }
        }
        return found
    }

    private static func hookGroup(matcher: String, timeout: Int) -> [String: Any] {
        [
            "matcher": matcher,
            "hooks": [[
                "type": "command",
                "command": hookCommand,
                "timeout": timeout,
            ]],
        ]
    }

    private static func removeBezelEntries(from list: [[String: Any]]) -> [[String: Any]] {
        list.filter { group in
            guard let inner = group["hooks"] as? [[String: Any]] else { return true }
            let hasBezel = inner.contains { hook in
                guard let command = hook["command"] as? String else { return false }
                return isBezelHookCommand(command)
            }
            return !hasBezel
        }
    }

    private static func decodeRoot(_ data: Data?) throws -> [String: Any] {
        if let data, !data.isEmpty,
           let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            return obj
        }
        return [:]
    }

    private static func encodeRoot(_ root: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }
}
