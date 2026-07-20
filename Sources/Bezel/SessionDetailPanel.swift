import SwiftUI
import BezelCore

struct SessionDetailPanel: View {
    let session: Session
    var onBack: () -> Void
    var onJump: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                        Text("Back")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(PacManTheme.pacYellow.opacity(0.9))
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: onJump) {
                    Label("Jump", systemImage: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PacManTheme.secondary)
                }
                .buttonStyle(.plain)
            }

            SessionRow(session: session, compact: false, onJump: onJump)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 12) {
                    if let todos = session.todos, !todos.isEmpty {
                        detailSection("TODOS") {
                            ForEach(todos) { todo in
                                HStack(spacing: 8) {
                                    Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 11))
                                        .foregroundStyle(todo.done ? PacManTheme.moss : PacManTheme.tertiary)
                                    Text(todo.label)
                                        .font(.system(size: 12))
                                        .foregroundStyle(PacManTheme.title.opacity(todo.done ? 0.55 : 0.92))
                                        .strikethrough(todo.done)
                                }
                            }
                        }
                    }

                    if let reply = session.lastReply, !reply.isEmpty {
                        detailSection("LAST REPLY") {
                            Text(reply)
                                .font(.system(size: 11.5))
                                .foregroundStyle(PacManTheme.secondary)
                                .lineLimit(8)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let events = session.toolEvents, !events.isEmpty {
                        detailSection("TOOLS") {
                            ForEach(events.prefix(12)) { event in
                                HStack(spacing: 8) {
                                    Text(event.label)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(PacManTheme.title.opacity(0.88))
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    Text(RelativeAge.format(since: event.at))
                                        .font(.system(size: 10))
                                        .foregroundStyle(PacManTheme.tertiary)
                                }
                            }
                        }
                    }

                    telemetryStrip
                }
                .padding(.trailing, 2)
            }
            .frame(maxHeight: 220)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private var telemetryStrip: some View {
        let chips = telemetryChips
        if !chips.isEmpty {
            detailSection("STATS") {
                FlowLayout(spacing: 8) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip)
                            .font(PacManTheme.scoreFont(size: 10))
                            .foregroundStyle(PacManTheme.pacYellow.opacity(0.85))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(PacManTheme.mazeWall.opacity(0.2), in: Capsule())
                    }
                }
            }
        }
    }

    private var telemetryChips: [String] {
        var out: [String] = []
        if let model = session.model { out.append(model) }
        if let branch = session.gitBranch { out.append(branch) }
        if let tin = session.tokensIn, let tout = session.tokensOut {
            out.append("\(formatK(tin)) / \(formatK(tout))")
        }
        if let cost = session.costUSD { out.append(String(format: "$%.2f", cost)) }
        if let a = session.diffAdded, let r = session.diffRemoved {
            out.append("+\(a)/-\(r)")
        }
        if let msgs = session.messageCount { out.append("\(msgs) msgs") }
        return out
    }

    private func detailSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(PacManTheme.scoreFont(size: 9, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(PacManTheme.pacYellow.opacity(0.75))
            content()
        }
    }

    private func formatK(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000) }
        return "\(n)"
    }
}

/// Simple horizontal chip flow for stats.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var frames: [CGRect] = []
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return (CGSize(width: maxWidth, height: y + rowHeight), frames)
    }
}
