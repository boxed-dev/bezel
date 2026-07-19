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
    public static func sessionTitle(
        sessionTitle: String?,
        cwd: String?,
        agentType: String?,
        existing: String? = nil
    ) -> String? {
        if let t = clean(sessionTitle) { return t }
        if let e = clean(existing), !looksLikeSessionID(e) { return e }
        if let cwd, !cwd.isEmpty {
            let base = (cwd as NSString).lastPathComponent
            if !base.isEmpty, base != "/", base != "~" { return base }
        }
        if let agent = clean(agentType) {
            return humanizeAgent(agent)
        }
        return clean(existing)
    }

    public static func looksLikeSessionID(_ value: String) -> Bool {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if v == "unknown" { return true }
        if v.hasSuffix("…"), v.count <= 12 { return true }
        // UUID-ish or long hex
        let hex = v.replacingOccurrences(of: "-", with: "")
        if hex.count >= 8, hex.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) {
            return true
        }
        return false
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
