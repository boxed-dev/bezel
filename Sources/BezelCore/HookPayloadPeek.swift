import Foundation

/// Best-effort field extraction from truncated or invalid hook JSON.
public enum HookPayloadPeek {
    /// Route kind + event name when full `HookPayload.parse` is impossible (oversized / corrupt).
    public static func routeKind(from data: Data) -> (kind: RouteKind, hookEventName: String)? {
        if let payload = try? HookPayload.parse(data) {
            return (payload.routeKind, payload.hookEventName)
        }
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        let eventRaw = extractJSONString(in: text, keys: [
            "hook_event_name", "hookEventName", "eventName", "event",
        ])
        let tool = extractJSONString(in: text, keys: ["tool_name", "toolName"])
        let question = extractJSONString(in: text, keys: ["question"])

        guard eventRaw != nil || tool != nil || question != nil else { return nil }

        let event = EventNormalizer.pascalCase(eventRaw ?? "Unknown")
        let kind = PermissionRouting.routeKind(
            hookEventName: event,
            toolName: tool,
            source: nil,
            question: question
        )
        return (kind, event)
    }

    /// Kind-correct deny for oversized / unparseable payloads (falls back to permission deny).
    public static func denyResponse(for data: Data, message: String) -> Data {
        if let peeked = routeKind(from: data) {
            return DecisionJSON.deny(
                for: peeked.kind,
                hookEventName: peeked.hookEventName,
                message: message
            )
        }
        return DecisionJSON.deny(for: .permission, message: message)
    }

    private static func extractJSONString(in text: String, keys: [String]) -> String? {
        for key in keys {
            let pattern = "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\""
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges >= 2,
                  let valueRange = Range(match.range(at: 1), in: text)
            else { continue }
            let raw = String(text[valueRange])
            return unescapeJSONString(raw)
        }
        return nil
    }

    private static func unescapeJSONString(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "\\" {
                let next = s.index(after: i)
                guard next < s.endIndex else { break }
                switch s[next] {
                case "\\": out.append("\\")
                case "\"": out.append("\"")
                case "n": out.append("\n")
                case "r": out.append("\r")
                case "t": out.append("\t")
                default: out.append(s[next])
                }
                i = s.index(after: next)
            } else {
                out.append(ch)
                i = s.index(after: i)
            }
        }
        return out
    }
}
