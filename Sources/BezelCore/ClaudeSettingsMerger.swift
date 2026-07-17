import Foundation

public enum ClaudeSettingsMerger {
    public static let hookCommand = "$HOME/.bezel/bezel-hook.sh"

    private static let managedEvents: [(name: String, timeout: Int)] = [
        ("SessionStart", 10),
        ("SessionEnd", 10),
        ("PreToolUse", 10),
        ("PostToolUse", 10),
        ("PermissionRequest", 86400),
        ("Notification", 86400),
        ("Stop", 10),
        ("UserPromptSubmit", 10),
    ]

    /// Merge Bezel hooks into Claude settings JSON object. Idempotent.
    public static func merge(into root: [String: Any]) -> [String: Any] {
        var result = root
        var hooks = result["hooks"] as? [String: Any] ?? [:]

        for (name, timeout) in managedEvents {
            var list = hooks[name] as? [[String: Any]] ?? []
            list = removeBezelEntries(from: list)
            list.append(hookGroup(matcher: "", timeout: timeout))
            hooks[name] = list
        }

        // Dedicated long-timeout matcher for interactive tools
        var pre = hooks["PreToolUse"] as? [[String: Any]] ?? []
        pre = pre.filter { group in
            let matcher = group["matcher"] as? String ?? ""
            return !matcher.contains("AskUserQuestion")
        }
        pre.insert(
            hookGroup(matcher: "AskUserQuestion|ExitPlanMode", timeout: 600),
            at: 0
        )
        // Keep a catch-all PreToolUse for observe (already added in loop) — ensure order: interactive first
        hooks["PreToolUse"] = pre

        result["hooks"] = hooks
        return result
    }

    public static func mergeData(_ data: Data?) throws -> Data {
        let root: [String: Any]
        if let data, !data.isEmpty,
           let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        {
            root = obj
        } else {
            root = [:]
        }
        let merged = merge(into: root)
        return try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
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
                (hook["command"] as? String)?.contains("bezel") == true
            }
            return !hasBezel
        }
    }
}
