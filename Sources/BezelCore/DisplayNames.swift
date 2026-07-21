import Foundation

/// Human-readable labels from Claude hook fields (`agent_type`, `session_title`, tool detail).
public enum DisplayNames {
    /// `regression-guard` / `my-plugin:reviewer` → `Regression Guard` / `Reviewer`.
    public static func humanizeAgent(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Agent" }
        let leaf = trimmed.split(separator: ":").last.map(String.init) ?? trimmed
        let parts = leaf.split { $0 == "-" || $0 == "_" || $0 == "." }
        let words = parts.map { part -> String in
            let s = String(part)
            guard let first = s.first else { return s }
            return String(first).uppercased() + s.dropFirst().lowercased()
        }
        return words.joined(separator: " ")
    }

    /// Prefer explicit session title, then project folder, then agent name.
    /// Never returns a raw session UUID/hex id.
    /// Never promotes a vendor brand (`Claude` / `Cursor`) from `agent_type` — that belongs to `source`.
    public static func sessionTitle(
        sessionTitle: String?,
        cwd: String?,
        agentType: String?,
        existing: String? = nil
    ) -> String? {
        if let t = clean(sessionTitle), !looksLikeSessionID(t) { return t }
        if let e = clean(existing), !looksLikeSessionID(e), !isSourceBrandLabel(e) { return e }
        if let cwdBase = cwdBasename(cwd) { return cwdBase }
        if let agent = usefulAgentLabel(agentType) {
            return agent
        }
        return nil
    }

    /// Glanceable primary label for a session row (never a raw session id).
    /// Order: title → cwd → named agent → source brand (`Cursor` / `Claude` / …).
    public static func placeLabel(
        sessionTitle: String?,
        cwd: String?,
        agentType: String?,
        sourceName: String = "Agent"
    ) -> String {
        if let t = clean(sessionTitle), !looksLikeSessionID(t), !isSourceBrandLabel(t) {
            return t
        }
        if let cwdBase = cwdBasename(cwd) { return cwdBase }
        if let agent = usefulAgentLabel(agentType) { return agent }
        let source = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        return source.isEmpty ? "Agent" : source
    }

    /// Short human phrase for what the agent is doing (not a raw shell dump).
    /// Returns `nil` for missing / junk detail (`null`, `null;`, bare `;`, whitespace).
    public static func activitySummary(
        tool: String?,
        detail: String?,
        maxLength: Int = 48
    ) -> String? {
        let toolName = cleanActivity(tool) ?? ""
        if let detail = cleanActivity(detail) {
            let summary = summarizeDetail(detail, tool: toolName)
            let cleaned = cleanActivity(summary)
            if let cleaned, !cleaned.isEmpty { return clip(cleaned, maxLength) }
        }
        if !toolName.isEmpty {
            return humanizeToolVerb(toolName)
        }
        return nil
    }

    /// Session-row secondary line: live activity only while `.working` / waiting;
    /// idle/done never surface a "Running …" leftover from stale tool detail.
    public static func sessionSecondaryLine(
        phase: SessionPhase,
        tool: String?,
        detail: String?,
        maxLength: Int = 48
    ) -> String {
        switch phase {
        case .waitingPermission:
            if let summary = activitySummary(tool: tool, detail: detail, maxLength: min(maxLength, 44)) {
                return summary
            }
            return tool.flatMap { clean($0) }.map { "Allow \($0)?" } ?? "Permission"
        case .waitingQuestion:
            return "Waiting on an answer"
        case .planReview:
            return "Plan ready to review"
        case .working:
            if let summary = activitySummary(tool: tool, detail: detail, maxLength: maxLength) {
                return summary
            }
            return "Working"
        case .idle:
            return "Idle"
        case .done:
            return "Done"
        case .error:
            return "Error"
        }
    }

    public static func looksLikeSessionID(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v == "unknown" { return true }
        if v.hasSuffix("…") || v.hasSuffix("...") {
            let stem = v
                .replacingOccurrences(of: "…", with: "")
                .replacingOccurrences(of: "...", with: "")
            if looksLikeSessionID(stem) { return true }
        }
        // UUID-ish or long hex
        let hex = v.replacingOccurrences(of: "-", with: "")
        if hex.count >= 8, hex.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) {
            return true
        }
        return false
    }

    /// True for vendor/product labels that must come from `AgentSource`, not `agent_type`.
    public static func isSourceBrandLabel(_ value: String) -> Bool {
        let n = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [
            "claude", "codex", "cursor", "gemini", "opencode", "open code",
            "agent", "assistant", "anthropic",
        ].contains(n)
    }

    // MARK: - Private

    private static func usefulAgentLabel(_ agentType: String?) -> String? {
        guard let agent = clean(agentType) else { return nil }
        let human = humanizeAgent(agent)
        if isSourceBrandLabel(human) { return nil }
        return human
    }

    private static func cwdBasename(_ cwd: String?) -> String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        let base = (cwd as NSString).lastPathComponent
        if base.isEmpty || base == "/" || base == "~" { return nil }
        return base
    }

    private static func summarizeDetail(_ detail: String, tool: String) -> String {
        let stripped = stripLeadingCd(collapseWhitespace(detail))
        guard let meaningful = cleanActivity(stripped) else { return "" }
        let target = meaningfulTarget(from: meaningful).flatMap { cleanActivity($0) }
        let kind = toolKind(tool, detail: meaningful)

        switch kind {
        case .shell:
            return shellPhrase(meaningful, target: target)
        case .edit:
            return "Editing \(target ?? shortClause(meaningful))"
        case .read:
            return "Reading \(target ?? shortClause(meaningful))"
        case .search:
            return "Searching \(target.map { "for \($0)" } ?? "…")"
        case .fetch:
            return "Fetching \(target ?? "…")"
        case .task:
            return target.map { "Delegating \($0)" } ?? "Delegating"
        case .generic:
            if looksLikeShellCommand(meaningful) {
                return shellPhrase(meaningful, target: target)
            }
            return shortClause(meaningful)
        }
    }

    private enum ToolKind {
        case shell, edit, read, search, fetch, task, generic
    }

    private static func toolKind(_ tool: String, detail: String) -> ToolKind {
        let t = tool.lowercased()
        if t.isEmpty {
            return looksLikeShellCommand(detail) ? .shell : .generic
        }
        if ["bash", "shell", "bashtool", "powershell", "terminal"].contains(t) { return .shell }
        if ["edit", "write", "multiedit", "streplace", "notebookedit", "create"].contains(t)
            || t.contains("edit") || t.contains("write") { return .edit }
        if t == "read" || t.hasPrefix("read") { return .read }
        if ["glob", "grep", "search", "semanticsearch"].contains(t) || t.contains("search") || t.contains("grep") {
            return .search
        }
        if ["webfetch", "websearch", "fetch"].contains(t) || t.contains("fetch") { return .fetch }
        if t == "task" || t.contains("task") || t.contains("agent") { return .task }
        return .generic
    }

    private static func shellPhrase(_ command: String, target: String?) -> String {
        if let script = target, script.hasSuffix(".sh") || script.hasSuffix(".py") || script.hasSuffix(".rb") {
            if script.hasPrefix("package-") {
                let stem = String(script.dropFirst("package-".count))
                    .replacingOccurrences(of: ".sh", with: "")
                    .replacingOccurrences(of: ".py", with: "")
                if !stem.isEmpty { return "Packaging \(humanizeAgent(stem))" }
            }
            return "Running \(script)"
        }
        if let target, !target.contains(" "), target.count <= 40 {
            return "Running \(target)"
        }
        let short = shortClause(stripShellWrappers(command))
        guard let cleaned = cleanActivity(short) else { return "" }
        if cleaned.lowercased().hasPrefix("running ") { return cleaned }
        return "Running \(cleaned)"
    }

    private static func humanizeToolVerb(_ tool: String) -> String {
        switch toolKind(tool, detail: "") {
        case .shell: return "Running command"
        case .edit: return "Editing"
        case .read: return "Reading"
        case .search: return "Searching"
        case .fetch: return "Fetching"
        case .task: return "Delegating"
        case .generic: return humanizeAgent(tool)
        }
    }

    /// Drop leading `cd … &&` / `cd … ;` so the meaningful command remains.
    private static func stripLeadingCd(_ value: String) -> String {
        var s = value
        // Repeat in case of `cd a && cd b && cmd`
        for _ in 0..<3 {
            guard let regex = try? NSRegularExpression(
                pattern: #"^cd\s+(?:'[^']+'|\"[^\"]+\"|\S+)\s*(?:&&|;)\s*"#,
                options: [.caseInsensitive]
            ) else { break }
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            let next = regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
            if next == s { break }
            s = next
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripShellWrappers(_ value: String) -> String {
        var s = value
        let wrappers = [#"^bash\s+"#, #"^sh\s+"#, #"^zsh\s+"#, #"^/bin/bash\s+"#, #"^/bin/sh\s+"#]
        for pattern in wrappers {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            s = regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func meaningfulTarget(from command: String) -> String? {
        let tokens = tokenize(stripShellWrappers(command))
        guard !tokens.isEmpty else { return nil }
        // Prefer a script/path-looking token over flags.
        for token in tokens {
            if token.hasPrefix("-") { continue }
            if isJunkActivityToken(token) { continue }
            if token.contains("/") || token.contains(".") {
                return (token as NSString).lastPathComponent
            }
        }
        // First non-flag token (e.g. `npm`, `swift`)
        if let first = tokens.first(where: { !$0.hasPrefix("-") && !isJunkActivityToken($0) }) {
            return (first as NSString).lastPathComponent
        }
        return nil
    }

    private static func tokenize(_ value: String) -> [String] {
        value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func looksLikeShellCommand(_ value: String) -> Bool {
        let v = value.lowercased()
        if v.contains("&&") || v.contains("||") || v.hasPrefix("cd ") { return true }
        let first = tokenize(v).first ?? ""
        let shells = ["bash", "sh", "zsh", "npm", "npx", "yarn", "pnpm", "swift", "xcodebuild", "cargo", "make", "python", "python3", "node", "git", "curl", "brew"]
        return shells.contains(first) || first.hasSuffix(".sh")
    }

    private static func shortClause(_ value: String) -> String {
        var s = collapseWhitespace(value)
        // First clause before sentence end / heavy punctuation.
        if let idx = s.firstIndex(where: { $0 == "." || $0 == "\n" || $0 == ";" }) {
            let head = String(s[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
            if head.count >= 8 { s = head }
        }
        // Basename-ify obvious absolute paths in the remaining string.
        s = basenamePaths(in: s)
        return s
    }

    private static func basenamePaths(in value: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"(/(?:Users|home|var|tmp|opt|usr)[^\s:]+)"#,
            options: []
        ) else { return value }
        let ns = value as NSString
        let matches = regex.matches(in: value, options: [], range: NSRange(location: 0, length: ns.length))
        var result = value
        for match in matches.reversed() {
            let path = ns.substring(with: match.range)
            let base = (path as NSString).lastPathComponent
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: base)
            }
        }
        return result
    }

    private static func collapseWhitespace(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func clip(_ value: String, _ max: Int) -> String {
        guard max > 1, value.count > max else { return value }
        return String(value.prefix(max - 1)) + "…"
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Like `clean`, but also rejects placeholder / serializer junk and strips trailing `;`.
    private static func cleanActivity(_ value: String?) -> String? {
        guard var t = clean(value) else { return nil }
        while t.hasSuffix(";") {
            t = String(t.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !t.isEmpty else { return nil }
        if isJunkActivityToken(t) { return nil }
        return t
    }

    private static func isJunkActivityToken(_ value: String) -> Bool {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        let lower = t.lowercased()
        if ["null", "nil", "none", "undefined", "n/a", "na", "(null)", "<null>"].contains(lower) {
            return true
        }
        // Bare punctuation / semicolon noise.
        if t.unicodeScalars.allSatisfy({ CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines).contains($0) }) {
            return true
        }
        return false
    }
}
