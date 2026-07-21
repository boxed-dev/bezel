import Foundation

/// One line in the session tool feed (newest first).
public struct ToolEvent: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var label: String
    public var at: Date

    public init(id: String = UUID().uuidString, label: String, at: Date = Date()) {
        self.id = id
        self.label = label
        self.at = at
    }
}

/// Bounded tool history for the notch detail pane.
public enum ToolEventRing {
    public static let maxEvents = 24

    public static func append(
        _ events: [ToolEvent]?,
        tool: String?,
        detail: String?,
        now: Date = Date()
    ) -> [ToolEvent] {
        guard let label = eventLabel(tool: tool, detail: detail) else {
            return events ?? []
        }
        var ring = events ?? []
        if ring.first?.label == label { return ring }
        ring.insert(ToolEvent(label: label, at: now), at: 0)
        if ring.count > maxEvents {
            ring.removeLast(ring.count - maxEvents)
        }
        return ring
    }

    public static func eventLabel(tool: String?, detail: String?) -> String? {
        // Prefer a detail-backed summary. If detail was present but junk (`null;`),
        // do not invent a generic "Running command" from the tool name alone.
        if let detail {
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return DisplayNames.activitySummary(tool: tool, detail: detail, maxLength: 72)
            }
        }
        if let summary = DisplayNames.activitySummary(tool: tool, detail: nil, maxLength: 72) {
            return summary
        }
        if let tool, !tool.isEmpty {
            return DisplayNames.humanizeAgent(tool)
        }
        return nil
    }
}
