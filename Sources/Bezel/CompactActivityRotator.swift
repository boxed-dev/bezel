import SwiftUI
import BezelCore

/// Rotating compact activity across live sessions (~1.75s cadence).
struct CompactActivityRotator: View {
    @Bindable var store: SessionStore

    private var candidates: [Session] {
        let live = store.sessions.filter { $0.phase != .done && $0.phase != .idle }
        if !live.isEmpty { return live.sorted { $0.updatedAt > $1.updatedAt } }
        return store.sessions.filter { $0.phase != .done }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        let _ = store.presenceEpoch
        TimelineView(.periodic(from: .now, by: BezelMotion.rotateInterval)) { timeline in
            let sessions = candidates
            let tick = Int(timeline.date.timeIntervalSinceReferenceDate / BezelMotion.rotateInterval)
            let safeIndex = sessions.isEmpty ? 0 : tick % sessions.count
            let session = sessions.isEmpty ? nil : sessions[safeIndex]
            Text(displayText(for: session))
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(textColor(for: session))
                .lineLimit(1)
                .frame(maxWidth: 140, alignment: .leading)
                .animation(BezelMotion.hoverSpring, value: safeIndex)
                .id(safeIndex)
        }
    }

    private func displayText(for session: Session?) -> String {
        guard let session else { return "Ready" }
        return DisplayNames.sessionSecondaryLine(
            phase: session.phase,
            tool: session.lastTool,
            detail: session.lastToolDetail,
            maxLength: 28
        )
    }

    private func textColor(for session: Session?) -> Color {
        guard let session else { return PacManTheme.tertiary }
        return ActivityTint.color(
            phase: session.phase,
            tool: session.lastTool,
            detail: session.lastToolDetail
        )
    }
}

/// Persistent session-count badge for compact trailing.
struct CompactSessionBadge: View {
    let count: Int

    var body: some View {
        Text("\(count) Sessions")
            .font(PacManTheme.scoreFont(size: 9, weight: .semibold))
            .foregroundStyle(PacManTheme.pacYellow.opacity(0.92))
            .lineLimit(1)
    }
}
