import SwiftUI
import Observation
import AppKit
import Combine
import DynamicNotchKit
import BezelCore

// MARK: - Design tokens (docs/PLAN.md visual)

private enum BezelChrome {
    static let ink = Color(red: 0.027, green: 0.031, blue: 0.039)       // #07080A
    static let steel = Color(red: 0.545, green: 0.639, blue: 0.710)      // #8BA3B5
    static let tungsten = Color(red: 0.77, green: 0.65, blue: 0.45)      // waiting
    static let moss = Color(red: 0.45, green: 0.55, blue: 0.48)          // done
    static let live = Color(red: 0.35, green: 0.82, blue: 0.48)          // live pulse
    static let card = Color.white.opacity(0.06)
    static let cardStroke = Color.white.opacity(0.08)
    static let title = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.35)
}

/// Force Touch trackpad haptics (no-op on Magic Mouse / non-FT trackpads).
enum BezelHaptics {
    static func alignment() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    static func levelChange() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
    }

    static func generic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }
}

@MainActor
final class NotchController {
    private let store: SessionStore
    private var notch: DynamicNotch<ExpandedHUD, CompactLeading, CompactTrailing>?
    private var isWatching = false
    private var lastAttention = false
    private var lastActiveCount = 0
    private var leaveCollapseTask: Task<Void, Never>?
    private var hoverCancellable: AnyCancellable?

    /// Delay before collapsing after mouse leave (avoids flicker at the edge).
    private let leaveCollapseDelay: Duration = .milliseconds(180)

    init(store: SessionStore) {
        self.store = store
    }

    func start() {
        let store = self.store
        // keepVisible: don’t hide mid-hover
        // hapticFeedback: kit fires alignment on hover enter/leave (Force Touch)
        // increaseShadow: subtle depth on hover
        let notch = DynamicNotch(
            hoverBehavior: [.keepVisible, .hapticFeedback, .increaseShadow]
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

        // DynamicNotchKit does NOT auto expand/collapse on hover — we own that.
        hoverCancellable = notch.$isHovering
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hovering in
                self?.handleHoverChange(hovering)
            }

        isWatching = true
        lastAttention = store.needsAttention
        lastActiveCount = store.activeCount
        armAttentionWatcher()
    }

    /// Hover enter → expand. Hover leave → compact — unless a decision is waiting.
    private func handleHoverChange(_ hovering: Bool) {
        leaveCollapseTask?.cancel()
        leaveCollapseTask = nil

        if hovering {
            Task { @MainActor [weak self] in
                guard let self, let notch = self.notch else { return }
                BezelHaptics.alignment()
                await notch.expand()
            }
            return
        }

        // Stay expanded while agent needs Allow / Deny / answer (Vibe Island behavior).
        if store.needsAttention {
            return
        }

        leaveCollapseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.leaveCollapseDelay)
            guard !Task.isCancelled else { return }
            guard let notch = self.notch, !notch.isHovering else { return }
            guard !self.store.needsAttention else { return }
            BezelHaptics.alignment()
            await notch.compact()
        }
    }

    /// Expand on attention / new session; collapse when attention clears (if not hovering).
    private func armAttentionWatcher() {
        guard isWatching else { return }
        withObservationTracking {
            _ = store.needsAttention
            _ = store.activeCount
            _ = store.surface
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isWatching else { return }
                let needs = self.store.needsAttention
                let active = self.store.activeCount
                let hovering = self.notch?.isHovering ?? false

                if needs && !self.lastAttention {
                    BezelSound.play(.attention)
                    await self.notch?.expand()
                } else if !needs && self.lastAttention {
                    // Decision resolved — settle unless still hovering the list.
                    if !hovering {
                        await self.notch?.compact()
                    }
                } else if !needs && active > self.lastActiveCount {
                    BezelSound.play(.sessionUp)
                    await self.notch?.expand()
                    if !hovering {
                        try? await Task.sleep(for: .milliseconds(1400))
                        guard !Task.isCancelled, self.isWatching else { return }
                        if !(self.notch?.isHovering ?? false), !self.store.needsAttention {
                            await self.notch?.compact()
                        }
                    }
                } else if active < self.lastActiveCount && active == 0 {
                    BezelSound.play(.done)
                }

                self.lastAttention = needs
                self.lastActiveCount = active
                self.armAttentionWatcher()
            }
        }
    }

    func stop() {
        isWatching = false
        leaveCollapseTask?.cancel()
        leaveCollapseTask = nil
        hoverCancellable?.cancel()
        hoverCancellable = nil
        Task {
            await notch?.hide()
        }
    }
}

// MARK: - Compact (always-on notch)

struct CompactLeading: View {
    @Bindable var store: SessionStore

    var body: some View {
        ZStack {
            if store.needsAttention {
                Circle()
                    .stroke(BezelChrome.tungsten.opacity(0.55), lineWidth: 1.5)
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulse ? 1.35 : 1.0)
                    .opacity(pulse ? 0.15 : 0.7)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: pulse
                    )
            }
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .shadow(color: statusColor.opacity(0.55), radius: store.needsAttention ? 4 : 0)
        }
        .frame(width: 14, height: 14)
        .onAppear { pulse = store.needsAttention }
        .onChange(of: store.needsAttention) { _, needs in
            pulse = needs
        }
    }

    @State private var pulse = false

    private var statusColor: Color {
        if store.needsAttention { return BezelChrome.tungsten }
        if store.activeCount > 0 { return BezelChrome.steel }
        return BezelChrome.tertiary
    }
}

struct CompactTrailing: View {
    @Bindable var store: SessionStore

    var body: some View {
        Group {
            if store.needsAttention {
                Image(systemName: "bell.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(BezelChrome.tungsten)
            } else if store.activeCount > 0 {
                Text("\(store.activeCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(BezelChrome.steel)
                    .monospacedDigit()
            }
        }
        .frame(minWidth: 10)
    }
}

// MARK: - Expanded HUD

struct ExpandedHUD: View {
    @Bindable var store: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            // Always keep the session list (Vibe Island style); decision sits on top.
            if store.needsAttention {
                decisionStrip
            }

            sessionList
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minWidth: 340, idealWidth: 380, maxWidth: 420)
    }

    @ViewBuilder
    private var decisionStrip: some View {
        switch store.surface {
        case .approval:
            if let pending = store.pendingPermission {
                PermissionCard(pending: pending) {
                    BezelSound.play(.allow)
                    store.resolvePermission(allow: true)
                } onDeny: {
                    BezelSound.play(.deny)
                    store.resolvePermission(allow: false)
                }
            }
        case .planReview:
            if let pending = store.pendingPlanReview {
                PlanReviewCard(pending: pending) {
                    BezelSound.play(.allow)
                    store.resolvePlanReview(approve: true)
                } onReject: {
                    BezelSound.play(.deny)
                    store.resolvePlanReview(approve: false)
                }
            }
        case .question:
            if let pending = store.pendingQuestion {
                QuestionCard(pending: pending) { answers in
                    BezelSound.play(.allow)
                    store.resolveQuestion(answers: answers)
                }
            }
        case .sessionList, .quiet:
            EmptyView()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("BEZEL")
                .font(.system(size: 11, weight: .semibold, design: .default))
                .tracking(2.4)
                .foregroundStyle(BezelChrome.title)
            Spacer(minLength: 8)
            Text(statusLabel)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(statusTint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusTint.opacity(0.12), in: Capsule())
        }
    }

    @ViewBuilder
    private var sessionList: some View {
        let live = store.sessions.filter { $0.phase != .done }
        if live.isEmpty {
            emptyState
        } else {
            VStack(spacing: 6) {
                ForEach(Array(live.prefix(5).enumerated()), id: \.element.id) { index, session in
                    SessionRow(
                        session: session,
                        isWaiting: store.attentionHead?.key.sessionID == session.id
                    ) {
                        store.jump(to: session)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(
                        .spring(response: 0.32, dampingFraction: 0.86).delay(Double(index) * 0.03),
                        value: live.count
                    )
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.topthird.inset.filled")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(BezelChrome.steel.opacity(0.7))
            VStack(alignment: .leading, spacing: 2) {
                Text("Quiet")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BezelChrome.title)
                Text("Start an agent — we’ll meet you here.")
                    .font(.system(size: 11))
                    .foregroundStyle(BezelChrome.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var statusLabel: String {
        if store.needsAttention { return "Needs you" }
        if store.activeCount > 0 { return "\(store.activeCount) live" }
        return "Idle"
    }

    private var statusTint: Color {
        if store.needsAttention { return BezelChrome.tungsten }
        if store.activeCount > 0 { return BezelChrome.live }
        return BezelChrome.secondary
    }
}

// MARK: - Session row (competitor-grade list density)

struct SessionRow: View {
    let session: Session
    var isWaiting: Bool = false
    var onJump: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        Button {
            BezelHaptics.alignment()
            onJump?()
        } label: {
            HStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    agentGlyph
                    terminalBadge
                        .offset(x: 4, y: 4)
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(primaryTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(BezelChrome.title)
                            .lineLimit(1)
                        if isWaiting || session.phase == .waitingPermission
                            || session.phase == .waitingQuestion
                            || session.phase == .planReview {
                            LiveDot(color: BezelChrome.tungsten)
                        } else if session.phase == .working {
                            LiveDot(color: BezelChrome.live)
                        }
                    }
                    Text(secondaryLine)
                        .font(.system(size: 10.5))
                        .foregroundStyle(BezelChrome.secondary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Chip(text: sourceLabel, tint: sourceTint)
                        if let term = terminalLabel {
                            Chip(text: term, tint: BezelChrome.secondary)
                        }
                        Chip(text: relativeAge, tint: BezelChrome.tertiary)
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(hovering ? BezelChrome.steel : BezelChrome.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(rowFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(rowStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Jump to session")
    }

    private var rowFill: Color {
        if isWaiting { return BezelChrome.tungsten.opacity(0.12) }
        return hovering ? Color.white.opacity(0.09) : BezelChrome.card
    }

    private var rowStroke: Color {
        if isWaiting { return BezelChrome.tungsten.opacity(0.35) }
        return BezelChrome.cardStroke
    }

    private var primaryTitle: String {
        session.title ?? shortID
    }

    private var secondaryLine: String {
        if session.phase == .waitingPermission {
            return session.lastTool.map { "Allow \($0)?" } ?? "Permission requested"
        }
        if session.phase == .waitingQuestion {
            return "Agent is asking a question"
        }
        if session.phase == .planReview {
            return "Plan ready for review"
        }
        if let tool = session.lastTool, !tool.isEmpty {
            return tool
        }
        switch session.phase {
        case .working: return "Working…"
        case .idle: return "Idle"
        case .done: return "Done"
        case .error: return "Error"
        default: return session.phase.rawValue
        }
    }

    private var shortID: String {
        let raw = session.id.rawValue
        if raw.count <= 10 { return raw }
        return String(raw.prefix(8)) + "…"
    }

    private var sourceLabel: String {
        switch session.source {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .gemini: return "Gemini"
        case .opencode: return "OpenCode"
        case .unknown: return "Agent"
        }
    }

    private var sourceTint: Color {
        switch session.source {
        case .claude: return Color(red: 0.85, green: 0.55, blue: 0.35)
        case .cursor: return Color(red: 0.4, green: 0.75, blue: 0.95)
        default: return BezelChrome.steel
        }
    }

    private var terminalLabel: String? {
        let p = (session.terminal?.termProgram ?? "").lowercased()
        if p.contains("iterm") { return "iTerm2" }
        if p.contains("ghostty") { return "Ghostty" }
        if p.contains("warp") { return "Warp" }
        if p.contains("kitty") { return "Kitty" }
        if p.contains("wez") { return "WezTerm" }
        if p.contains("terminal") || p.contains("apple") { return "Terminal" }
        if p.contains("vscode") || p.contains("cursor") { return "IDE" }
        return nil
    }

    private var relativeAge: String {
        let seconds = max(0, Int(Date().timeIntervalSince(session.updatedAt)))
        if seconds < 60 { return "<1m" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86_400)d"
    }

    private var agentGlyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(phaseFill.opacity(0.2))
                .frame(width: 28, height: 28)
            // Pixel-ish agent face (SF Symbol stack — lively without asset packs)
            Image(systemName: sourceSymbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(phaseFill)
                .shadow(color: phaseFill.opacity(0.5), radius: session.phase == .working ? 3 : 0)
        }
    }

    private var terminalBadge: some View {
        Image(systemName: "terminal.fill")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(BezelChrome.ink)
            .padding(2)
            .background(BezelChrome.steel.opacity(0.9), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private var sourceSymbol: String {
        switch session.source {
        case .claude: return "sparkles"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .cursor: return "cursorarrow.rays"
        case .gemini: return "diamond.fill"
        case .opencode: return "terminal"
        case .unknown: return "cpu"
        }
    }

    private var phaseFill: Color {
        switch session.phase {
        case .waitingPermission, .waitingQuestion, .planReview:
            return BezelChrome.tungsten
        case .working:
            return BezelChrome.steel
        case .done:
            return BezelChrome.moss
        case .error:
            return .red.opacity(0.85)
        case .idle:
            return BezelChrome.secondary
        }
    }
}


// MARK: - Micro components

private struct LiveDot: View {
    let color: Color
    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .shadow(color: color.opacity(0.8), radius: on ? 3 : 1)
            .opacity(on ? 1 : 0.55)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

private struct Chip: View {
    let text: String
    let tint: Color
    var mono: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: mono ? .monospaced : .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
            .lineLimit(1)
    }
}

// MARK: - Decision cards

struct PermissionCard: View {
    let pending: DecisionEntry
    let onAllow: () -> Void
    let onDeny: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            labelRow(icon: "lock.shield.fill", title: "Permission", tint: BezelChrome.tungsten)
            Text(pending.summary)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(BezelChrome.title)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                DecisionButton(title: "Deny  ⌘N", prominent: false, key: "n", action: onDeny)
                DecisionButton(title: "Allow  ⌘Y", prominent: true, key: "y", action: onAllow)
            }
        }
        .padding(12)
        .background(cardBackground())
    }
}

struct PlanReviewCard: View {
    let pending: DecisionEntry
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            labelRow(icon: "doc.text.fill", title: "Plan review", tint: BezelChrome.steel)
            Text(pending.planText.map { String($0.prefix(320)) } ?? pending.summary)
                .font(.system(size: 11, weight: .regular, design: .default))
                .foregroundStyle(BezelChrome.secondary)
                .lineLimit(7)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                DecisionButton(title: "Reject", prominent: false, action: onReject)
                DecisionButton(title: "Approve", prominent: true, action: onApprove)
            }
        }
        .padding(12)
        .background(cardBackground())
    }
}

struct QuestionCard: View {
    let pending: DecisionEntry
    let onAnswer: ([AskUserQuestionAnswer]) -> Void
    @State private var freeText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            labelRow(icon: "questionmark.bubble.fill", title: "Question", tint: BezelChrome.steel)
            Text(pending.prompt ?? pending.summary)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(BezelChrome.title)
                .fixedSize(horizontal: false, vertical: true)

            if let first = pending.questions.first, !first.options.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(first.options.enumerated()), id: \.offset) { _, opt in
                        Button {
                            onAnswer([
                                AskUserQuestionAnswer(question: first.question, answer: opt.label)
                            ])
                        } label: {
                            HStack {
                                Text(opt.label)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(BezelChrome.title)
                                Spacer()
                                Image(systemName: "return")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(BezelChrome.tertiary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(BezelChrome.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                TextField("Your answer", text: $freeText)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(BezelChrome.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(BezelChrome.title)
                DecisionButton(title: "Submit", prominent: true) {
                    let q = pending.questions.first?.question ?? pending.prompt ?? pending.summary
                    onAnswer([AskUserQuestionAnswer(question: q, answer: freeText)])
                }
                .disabled(freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
        }
        .padding(12)
        .background(cardBackground())
    }
}

// MARK: - Shared decision chrome

private func labelRow(icon: String, title: String, tint: Color) -> some View {
    HStack(spacing: 6) {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.0)
            .foregroundStyle(tint)
        Spacer()
    }
}

private struct DecisionButton: View {
    let title: String
    let prominent: Bool
    var key: KeyEquivalent? = nil
    let action: () -> Void

    init(title: String, prominent: Bool, key: KeyEquivalent? = nil, action: @escaping () -> Void) {
        self.title = title
        self.prominent = prominent
        self.key = key
        self.action = action
    }

    var body: some View {
        Button {
            BezelHaptics.generic()
            action()
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(prominent ? BezelChrome.ink : BezelChrome.title)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(prominent ? BezelChrome.steel : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .modifier(OptionalKeyShortcut(key: key, prominent: prominent))
    }
}

private struct OptionalKeyShortcut: ViewModifier {
    let key: KeyEquivalent?
    let prominent: Bool

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: .command)
        } else if prominent {
            content.keyboardShortcut(.defaultAction)
        } else {
            content.keyboardShortcut(.cancelAction)
        }
    }
}

@ViewBuilder
private func cardBackground() -> some View {
    RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(BezelChrome.cardStroke, lineWidth: 1)
        )
}
