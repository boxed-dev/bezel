import SwiftUI
import BezelCore

/// Unified motion tokens — one spring curve across compact, list, detail, and board.
enum BezelMotion {
    static let islandSpring = Animation.spring(response: 0.4, dampingFraction: 0.88)
    static let contentSpring = Animation.spring(response: 0.38, dampingFraction: 0.9)
    static let hoverSpring = Animation.spring(response: 0.22, dampingFraction: 0.86)
    static let rotateInterval: TimeInterval = 1.75
}

/// Which density the expanded island is showing.
enum HUDSurfaceMode: Equatable {
    case list
    case detail(SessionID)
    case board
}

/// Color-coded verb status for session rows (AgentPeek-style).
enum ActivityTint {
    static func color(phase: SessionPhase, tool: String?, detail: String?) -> Color {
        switch phase {
        case .waitingPermission, .waitingQuestion, .planReview:
            return PacManTheme.pinky
        case .idle:
            return PacManTheme.tertiary
        case .done:
            return PacManTheme.moss
        case .error:
            return PacManTheme.blinky
        case .working:
            break
        }
        let kind = toolKind(tool, detail: detail ?? "")
        switch kind {
        case .shell: return PacManTheme.inky
        case .edit: return PacManTheme.moss
        case .read: return Color(red: 0.45, green: 0.72, blue: 1.0)
        case .search: return PacManTheme.fruitOrange
        case .git: return PacManTheme.clyde
        case .generic: return PacManTheme.pacYellow
        }
    }

    private enum Kind { case shell, edit, read, search, git, generic }

    private static func toolKind(_ tool: String, detail: String) -> Kind {
        let t = tool.lowercased()
        if ["bash", "shell", "bashtool", "powershell", "terminal"].contains(t) { return .shell }
        if t.contains("edit") || t.contains("write") { return .edit }
        if t == "read" || t.hasPrefix("read") { return .read }
        if t.contains("grep") || t.contains("search") || t.contains("glob") { return .search }
        if t.contains("git") || detail.lowercased().contains("git ") { return .git }
        if detail.lowercased().contains("npm") || detail.lowercased().contains("&&") { return .shell }
        return .generic
    }
}
