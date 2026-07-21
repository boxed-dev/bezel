import SwiftUI
import BezelCore

struct AgentBoardView: View {
    @Bindable var store: SessionStore
    var onSelect: (Session) -> Void
    var onMinimize: () -> Void

    private var attentionIDs: Set<SessionID> {
        var ids = Set(store.decisionQueue.entries.map(\.key.sessionID))
        for s in store.sessions where s.phase == .waitingPermission || s.phase == .waitingQuestion || s.phase == .planReview {
            ids.insert(s.id)
        }
        return ids
    }

    private var buckets: [AgentBoardColumn: [Session]] {
        AgentBoardMapper.partition(
            sessions: store.sessions.filter { $0.phase != .done },
            attentionSessionIDs: attentionIDs
        )
    }

    private var liveCount: Int {
        store.sessions.filter { $0.phase != .done && $0.phase != .idle }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("AGENT BOARD")
                    .font(PacManTheme.scoreFont(size: 11, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(PacManTheme.pacYellow)
                Text("\(max(liveCount, store.activeCount)) LIVE")
                    .font(PacManTheme.scoreFont(size: 10, weight: .semibold))
                    .foregroundStyle(PacManTheme.moss)
                Spacer()
                Button(action: onMinimize) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(PacManTheme.secondary)
                }
                .buttonStyle(.plain)
                .help("Back to session list")
            }

            HStack(alignment: .top, spacing: 10) {
                boardColumn(.active, title: "ACTIVE", tint: PacManTheme.moss)
                boardColumn(.attention, title: "ATTENTION", tint: PacManTheme.blinky)
                boardColumn(.finished, title: "FINISHED", tint: PacManTheme.tertiary)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    @ViewBuilder
    private func boardColumn(_ column: AgentBoardColumn, title: String, tint: Color) -> some View {
        let items = buckets[column] ?? []
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(title)
                    .font(PacManTheme.scoreFont(size: 9, weight: .heavy))
                    .foregroundStyle(tint.opacity(0.9))
                Text("\(items.count)")
                    .font(PacManTheme.scoreFont(size: 9))
                    .foregroundStyle(PacManTheme.secondary)
            }
            if items.isEmpty {
                Text(emptyLabel(column))
                    .font(.system(size: 10))
                    .foregroundStyle(PacManTheme.tertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(items.prefix(3)) { session in
                    Button {
                        onSelect(session)
                    } label: {
                        boardCard(session)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(PacManTheme.mazeWall.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private func boardCard(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(bezelSessionPlace(session))
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(PacManTheme.title)
                .lineLimit(1)
            Text(
                DisplayNames.sessionSecondaryLine(
                    phase: session.phase,
                    tool: session.lastTool,
                    detail: session.lastToolDetail,
                    maxLength: 36
                )
            )
            .font(.system(size: 10))
            .foregroundStyle(
                ActivityTint.color(
                    phase: session.phase,
                    tool: session.lastTool,
                    detail: session.lastToolDetail
                )
            )
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func emptyLabel(_ column: AgentBoardColumn) -> String {
        switch column {
        case .active: return "No active agents"
        case .attention: return "All clear"
        case .finished: return "No recent finishes"
        }
    }
}
