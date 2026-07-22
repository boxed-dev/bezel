import Foundation

/// Codex CLI adapter: normalize hook JSON + discover sessions from rollout JSONL.
///
/// Truth model: hooks = live phase; JSONL under `sessions/` = discovery; process = liveness.
public enum CodexAdapter {
    public static let source: AgentSource = .codex
    /// Cap home-dir walks — never parse hundreds of rollouts on a poll tick.
    public static let defaultDiscoveryLimit = 24
    private static let rolloutHeadBytes = 65_536

    public struct DiscoveredSession: Sendable, Hashable {
        public var id: SessionID
        public var cwd: String?
        public var title: String?
        public var updatedAt: Date
        public var rolloutPath: String?
    }

    /// Stamp `_source=codex` and normalize event names into a `HookPayload`.
    public static func normalizeHookJSON(_ data: Data) throws -> HookPayload {
        guard var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookPayloadError.invalidJSON
        }
        obj["_source"] = source.rawValue
        if let event = obj["hook_event_name"] as? String {
            obj["hook_event_name"] = EventNormalizer.pascalCase(event)
        } else if let event = obj["hookEventName"] as? String {
            obj["hook_event_name"] = EventNormalizer.pascalCase(event)
        }
        let enriched = try JSONSerialization.data(withJSONObject: obj)
        return try HookPayload.parse(enriched)
    }

    /// Walk `codexHome/sessions/**/*.jsonl` (fixture or `~/.codex`) and parse `session_meta` lines.
    public static func discoverSessions(
        codexHome: URL,
        limit: Int = defaultDiscoveryLimit
    ) throws -> [Session] {
        try discoverRaw(codexHome: codexHome, limit: limit).map { raw in
            Session(
                id: raw.id,
                source: source,
                phase: .idle,
                cwd: raw.cwd,
                title: DisplayNames.sessionTitle(
                    sessionTitle: raw.title,
                    cwd: raw.cwd,
                    agentType: nil
                ),
                updatedAt: raw.updatedAt
            )
        }
    }

    public static func discoverRaw(
        codexHome: URL,
        limit: Int = defaultDiscoveryLimit
    ) throws -> [DiscoveredSession] {
        let sessionsRoot = codexHome.appendingPathComponent("sessions", isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: sessionsRoot.path) else { return [] }

        var candidates: [(url: URL, mtime: Date)] = []
        let enumerator = fm.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let mtime = values?.contentModificationDate ?? Date.distantPast
            candidates.append((url, mtime))
        }

        // Parse only the newest files by mtime — avoids reading entire Codex history.
        let capped = max(limit, 0)
        let newest = candidates
            .sorted { $0.mtime > $1.mtime }
            .prefix(capped)

        var found: [DiscoveredSession] = []
        found.reserveCapacity(newest.count)
        for item in newest {
            if let session = parseRollout(item.url) {
                found.append(session)
            }
        }
        return found.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Pure `hooks.json`-style merge for Codex (Claude-compatible event names).
    public static func mergeHooksJSON(existing: Data?, hookCommand: String) throws -> Data {
        var root = try decodeRoot(existing)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let events = [
            "SessionStart", "SessionEnd", "Stop", "UserPromptSubmit",
            "PostToolUse", "PermissionRequest",
        ]
        for name in events {
            var list = hooks[name] as? [[String: Any]] ?? []
            list = list.filter { !isBezelCommand(($0["hooks"] as? [[String: Any]])?.first?["command"] as? String) }
            // Flatten Cursor-style or use Codex nested groups.
            list.append([
                "matcher": "",
                "hooks": [[
                    "type": "command",
                    "command": hookCommand,
                    "timeout": name == "PermissionRequest" ? 86400 : 10,
                ]],
            ])
            hooks[name] = list
        }
        root["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys, .prettyPrinted])
    }

    // MARK: - Private

    /// Read only the head of the rollout — `session_meta` is near the start.
    private static func parseRollout(_ url: URL) -> DiscoveredSession? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: rolloutHeadBytes)
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        for line in text.split(whereSeparator: \.isNewline) {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  (obj["type"] as? String) == "session_meta",
                  let payload = obj["payload"] as? [String: Any]
            else { continue }

            let idRaw = (payload["id"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            let cwd = payload["cwd"] as? String
            let title = payload["thread_name"] as? String
            let updatedAt: Date
            if let ts = obj["timestamp"] as? String {
                updatedAt = ISO8601DateFormatter().date(from: ts) ?? Date(timeIntervalSince1970: 0)
            } else {
                updatedAt = Date(timeIntervalSince1970: 0)
            }
            return DiscoveredSession(
                id: SessionID(idRaw),
                cwd: cwd,
                title: title,
                updatedAt: updatedAt,
                rolloutPath: url.path
            )
        }
        return nil
    }

    private static func decodeRoot(_ data: Data?) throws -> [String: Any] {
        guard let data, !data.isEmpty else { return [:] }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookPayloadError.invalidJSON
        }
        return obj
    }

    private static func isBezelCommand(_ command: String?) -> Bool {
        guard let command else { return false }
        return command.contains(".bezel/bezel-hook.sh") || command.contains("BEZEL_SOURCE=")
    }
}
