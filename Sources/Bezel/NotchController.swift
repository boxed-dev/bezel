import SwiftUI
import AppKit
import DynamicNotchKit
import BezelCore

@MainActor
final class NotchController {
    private let store: SessionStore
    private var notch: DynamicNotch<ExpandedHUD, CompactLeading, CompactTrailing>?
    private var observationTask: Task<Void, Never>?

    init(store: SessionStore) {
        self.store = store
    }

    func start() {
        let store = self.store
        let notch = DynamicNotch(
            hoverBehavior: .all
        ) {
            ExpandedHUD(store: store)
        } compactLeading: {
            CompactLeading(store: store)
        } compactTrailing: {
            CompactTrailing(store: store)
        }
        self.notch = notch

        Task {
            await notch.compact()
        }

        observationTask = Task { [weak self] in
            // Re-assert compact when attention changes; expand on permission.
            var lastAttention = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard let self else { break }
                let needs = self.store.needsAttention
                if needs && !lastAttention {
                    await self.notch?.expand()
                }
                lastAttention = needs
            }
        }
    }

    func stop() {
        observationTask?.cancel()
        Task {
            await notch?.hide()
        }
    }
}

struct CompactLeading: View {
    @Bindable var store: SessionStore

    var body: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        if store.needsAttention { return Color(red: 0.77, green: 0.65, blue: 0.45) } // tungsten
        if store.activeCount > 0 { return Color(red: 0.55, green: 0.64, blue: 0.71) } // steel
        return Color.secondary.opacity(0.5)
    }
}

struct CompactTrailing: View {
    @Bindable var store: SessionStore

    var body: some View {
        if store.activeCount > 0 {
            Text("\(store.activeCount)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

struct ExpandedHUD: View {
    @Bindable var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Bezel")
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .tracking(1.2)
                Spacer()
                Text(store.activeCount == 0 ? "Quiet" : "\(store.activeCount) active")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let pending = store.pendingPermission {
                PermissionCard(pending: pending) {
                    store.resolvePermission(allow: true)
                } onDeny: {
                    store.resolvePermission(allow: false)
                }
            } else if store.sessions.isEmpty {
                Text("Start an agent — we’ll meet you at the notch.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.sessions.prefix(4)) { session in
                    SessionRow(session: session)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 280, maxWidth: 360)
    }
}

struct SessionRow: View {
    let session: Session

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(phaseColor)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title ?? session.id.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(session.phase.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let tool = session.lastTool {
                Text(tool)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var phaseColor: Color {
        switch session.phase {
        case .waitingPermission, .waitingQuestion, .planReview:
            return Color(red: 0.77, green: 0.65, blue: 0.45)
        case .working:
            return Color(red: 0.55, green: 0.64, blue: 0.71)
        case .done:
            return Color(red: 0.45, green: 0.55, blue: 0.48)
        case .error:
            return .red.opacity(0.8)
        case .idle:
            return .secondary.opacity(0.4)
        }
    }
}

struct PermissionCard: View {
    let pending: PendingPermission
    let onAllow: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Permission Request")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(pending.summary)
                .font(.system(size: 13, weight: .medium))
            HStack(spacing: 8) {
                Button("Deny") { onDeny() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Allow") { onAllow() }
                    .keyboardShortcut("y", modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
