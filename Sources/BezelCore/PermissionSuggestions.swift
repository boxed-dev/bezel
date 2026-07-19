import Foundation

/// Claude `PermissionRequest.permission_suggestions` — echo as `updatedPermissions` for "always allow".
public enum PermissionSuggestions {
    /// Extract the suggestions array JSON from a hook payload (preserves Claude’s exact objects).
    public static func json(from rawJSON: Data) -> Data? {
        guard let obj = try? JSONSerialization.jsonObject(with: rawJSON) as? [String: Any] else {
            return nil
        }
        let key = obj["permission_suggestions"] != nil ? "permission_suggestions" : "permissionSuggestions"
        guard let arr = obj[key] as? [Any], !arr.isEmpty else { return nil }
        return try? JSONSerialization.data(withJSONObject: arr, options: [.sortedKeys])
    }

    public static func array(from suggestionsJSON: Data) -> [[String: Any]] {
        (try? JSONSerialization.jsonObject(with: suggestionsJSON) as? [[String: Any]]) ?? []
    }

    /// Short label for the Always button, e.g. `rtk ls *` from addRules ruleContent.
    public static func alwaysAllowDetail(from suggestionsJSON: Data) -> String? {
        for entry in array(from: suggestionsJSON) {
            if let rules = entry["rules"] as? [[String: Any]] {
                for rule in rules {
                    if let content = rule["ruleContent"] as? String, !content.isEmpty {
                        return content
                    }
                    if let content = rule["rule_content"] as? String, !content.isEmpty {
                        return content
                    }
                }
            }
            if let mode = entry["mode"] as? String, !mode.isEmpty {
                return mode
            }
        }
        return nil
    }

    /// Command/description from a permission hook — used for exact memory key lookup.
    public static func requestedRuleContent(from rawJSON: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: rawJSON) as? [String: Any] else {
            return nil
        }
        let input = (obj["tool_input"] as? [String: Any])
            ?? (obj["toolInput"] as? [String: Any])
        if let command = input?["command"] as? String, !command.isEmpty {
            return command
        }
        if let desc = input?["description"] as? String, !desc.isEmpty {
            return desc
        }
        return nil
    }

    public static func alwaysAllowButtonTitle(from suggestionsJSON: Data?) -> String {
        guard let suggestionsJSON,
              let detail = alwaysAllowDetail(from: suggestionsJSON)
        else {
            return "Don't ask again"
        }
        let clipped = detail.count > 28 ? String(detail.prefix(25)) + "…" : detail
        return "Don't ask again · \(clipped)"
    }
}
