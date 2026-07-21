import SwiftUI
import Observation
import AppKit
import Combine
import DynamicNotchKit
import BezelCore

// MARK: - Design tokens (Pac-Man arcade theme — see PacManTheme.swift)

private typealias BezelChrome = PacManTheme

/// Consistent usage-meter tint across compact + expanded surfaces.
func bezelUsageColor(_ pct: Double) -> Color {
    PacManTheme.usageColor(pct)
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

/// Human label for an agent source (Claude, Codex, …).
func bezelSourceName(_ source: AgentSource) -> String {
    switch source {
    case .claude: return "Claude"
    case .codex: return "Codex"
    case .cursor: return "Cursor"
    case .gemini: return "Gemini"
    case .opencode: return "OpenCode"
    case .unknown: return "Agent"
    }
}

/// Short display name for where a session lives (title → cwd → agent → source).
func bezelSessionPlace(_ session: Session) -> String {
    DisplayNames.placeLabel(
        sessionTitle: session.title,
        cwd: session.cwd,
        agentType: session.agentType,
        sourceName: bezelSourceName(session.source)
    )
}

/// Tracked-caps eyebrow label — sits above decision heroes to attribute the asker.
private struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.7)
            .foregroundStyle(BezelChrome.pinky.opacity(0.95))
    }
}

/// Small keyboard-shortcut badge rendered inside action buttons.
private struct KeyHint: View {
    let text: String
    var onFill = false

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .foregroundStyle(onFill ? BezelChrome.ink.opacity(0.62) : BezelChrome.tertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(onFill ? BezelChrome.ink.opacity(0.12) : Color.white.opacity(0.07))
            }
    }
}

@MainActor
final class NotchController {
    private let store: SessionStore
    private var notch: DynamicNotch<ExpandedHUD, CompactLeading, CompactTrailing>?
    private var isWatching = false
    private var lastAttention = false
    private var lastActiveCount = 0
    private var lastUsageEpoch: UInt64 = 0
    private var lastSessionStartEpoch: UInt64 = 0
    private var leaveCollapseTask: Task<Void, Never>?
    private var attentionWatcherGeneration: UInt64 = 0
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
        lastSessionStartEpoch = store.sessionStartEpoch
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

    /// Expand/collapse via ExpandPolicy + SmartSuppress (quiet by default).
    private func armAttentionWatcher() {
        guard isWatching else { return }
        withObservationTracking {
            _ = store.needsAttention
            _ = store.activeCount
            _ = store.liveActivityCount
            _ = store.presenceEpoch
            _ = store.usageEpoch
            _ = store.usagePercent
            _ = store.surface
            _ = store.sessionStartEpoch
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isWatching else { return }
                self.attentionWatcherGeneration &+= 1
                let generation = self.attentionWatcherGeneration
                let needs = self.store.needsAttention
                let active = self.store.activeCount
                let usageEpoch = self.store.usageEpoch
                let hovering = self.notch?.isHovering ?? false
                let isSessionStart = self.store.sessionStartEpoch != self.lastSessionStartEpoch

                let transition = ExpandPolicy.Transition(
                    attentionGained: needs && !self.lastAttention,
                    attentionCleared: !needs && self.lastAttention,
                    activeCountIncreased: active > self.lastActiveCount,
                    isSessionStart: isSessionStart,
                    isHovering: hovering
                )
                let action = ExpandPolicy.evaluate(transition)
                let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                let sessionTerminal = self.attentionSession()?.terminal

                switch action {
                case .expand:
                    let frontHint = FrontTabProbe.probe(
                        bundleID: frontBundle,
                        sessionTerminal: sessionTerminal
                    )
                    if SmartSuppress.shouldAutoExpand(
                        needsAttention: needs,
                        front: frontHint,
                        sessionTerminal: sessionTerminal
                    ) {
                        if needs && !self.lastAttention {
                            BezelSound.play(.attention)
                        }
                        await self.notch?.expand()
                    }
                case .compact:
                    await self.notch?.compact()
                case .noop:
                    if active < self.lastActiveCount && active == 0 {
                        BezelSound.play(.done)
                    }
                }

                guard generation == self.attentionWatcherGeneration, self.isWatching else { return }

                self.lastAttention = needs
                self.lastActiveCount = active
                self.lastUsageEpoch = usageEpoch
                self.lastSessionStartEpoch = self.store.sessionStartEpoch
                self.armAttentionWatcher()
            }
        }
    }

    private func attentionSession() -> Session? {
        guard let head = store.attentionHead else { return nil }
        return store.sessions.first { $0.id == head.key.sessionID }
    }

    func stop() {
        isWatching = false
        attentionWatcherGeneration &+= 1
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
        let _ = store.presenceEpoch
        HStack(spacing: 6) {
            Group {
                if store.needsAttention {
                    PowerPelletPulse(diameter: 11)
                } else if store.liveActivityCount > 0 {
                    PacManChomper(diameter: 13)
                } else if store.activeCount > 0 {
                    MiniGhost(color: BezelChrome.clyde, size: 12)
                } else {
                    Circle()
                        .fill(BezelChrome.pellet.opacity(0.35))
                        .frame(width: 4, height: 4)
                }
            }
            .frame(width: 14, height: 14)

            if !store.needsAttention, store.activeCount > 0 {
                CompactActivityRotator(store: store)
            }
        }
        .frame(minWidth: store.needsAttention ? 14 : 130, alignment: .leading)
    }
}

struct CompactTrailing: View {
    @Bindable var store: SessionStore

    var body: some View {
        // Read epochs so Observation invalidates on session + usage changes.
        let _ = store.presenceEpoch
        let _ = store.usageEpoch
        Button {
            if let session = store.neediestSession {
                BezelHaptics.alignment()
                store.jump(to: session)
            }
        } label: {
            trailingContent
        }
        .buttonStyle(.plain)
        .frame(minWidth: 18, minHeight: 12)
        .animation(BezelMotion.hoverSpring, value: store.presenceEpoch)
        .animation(BezelMotion.hoverSpring, value: store.usageEpoch)
        .help(trailingHelp)
    }

    @ViewBuilder
    private var trailingContent: some View {
        if store.needsAttention {
            let pending = store.decisionQueue.entries.count
            PacManScoreText(
                text: pending > 1 ? "!\(pending)" : "!",
                color: BezelChrome.blinky
            )
        } else if store.activeCount > 1 {
            CompactSessionBadge(count: store.activeCount)
        } else if store.liveActivityCount > 0 {
            PacManScoreText(
                text: "\(store.liveActivityCount)",
                color: BezelChrome.inky
            )
        } else if store.activeCount == 1, let usage = store.usage {
            if UsageGlance.showsResetCountdown(usage) {
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    usageText(usage, now: timeline.date)
                }
            } else if let text = UsageGlance.compactText(usage) {
                usageTextLabel(text, usage: usage)
            }
        }
    }

    private var trailingHelp: String {
        if store.needsAttention {
            let pending = store.decisionQueue.entries.count
            return "\(pending) decision\(pending == 1 ? "" : "s") waiting — click to jump"
        }
        if let usage = store.usage {
            return (UsageGlance.compactText(usage).map { "\($0) — click to jump" })
                ?? (usage.helpText + " — click to jump")
        }
        if store.liveActivityCount > 0 {
            return "\(store.liveActivityCount) live — click to jump"
        }
        return "Jump to session"
    }

    @ViewBuilder
    private func usageText(_ usage: ClaudeUsageSnapshot, now: Date) -> some View {
        if let text = UsageGlance.compactText(usage, now: now) {
            usageTextLabel(text, usage: usage)
        }
    }

    private func usageTextLabel(_ text: String, usage: ClaudeUsageSnapshot) -> some View {
        PacManScoreText(
            text: text,
            color: bezelUsageColor(Double(usage.primaryPercent ?? 0))
        )
    }
}

// MARK: - Expanded HUD
// Premium notch UX:
// • Attention mode: decision is the hero; sessions fade to a quiet strip
// • Quiet mode: sessions breathe; brand is the calm center
// • Wide, short, no cards — ink atmosphere + typography hierarchy

struct ExpandedHUD: View {
    @Bindable var store: SessionStore
    @State private var surfaceMode: HUDSurfaceMode = .list
    @State private var showNavMenu = false

    var body: some View {
        ZStack {
            islandSurface
            atmosphere
            VStack(alignment: .leading, spacing: 0) {
                topBar
                if store.needsAttention {
                    decisionHero
                        .padding(.top, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    contextStrip
                        .padding(.top, 14)
                        .opacity(0.55)
                } else {
                    quietBody
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .frame(minWidth: 580, idealWidth: 640, maxWidth: 720)
        .animation(BezelMotion.islandSpring, value: store.needsAttention)
        .animation(BezelMotion.contentSpring, value: store.activeCount)
        .animation(BezelMotion.contentSpring, value: surfaceMode)
        .onChange(of: store.needsAttention) { _, needs in
            if needs { surfaceMode = .list; showNavMenu = false }
        }
    }

    private var islandSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(BezelChrome.maze)
            MazePelletField(spacing: 16, opacity: 0.11)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(BezelChrome.mazeWall.opacity(0.35), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }

    private var atmosphere: some View {
        ZStack {
            RadialGradient(
                colors: store.needsAttention
                    ? [BezelChrome.blinky.opacity(0.22), BezelChrome.pinky.opacity(0.06), .clear]
                    : [BezelChrome.mazeWall.opacity(0.18), BezelChrome.inky.opacity(0.05), .clear],
                center: .top,
                startRadius: 4,
                endRadius: 220
            )
            LinearGradient(
                colors: [BezelChrome.pacYellow.opacity(0.04), .clear],
                startPoint: .topLeading,
                endPoint: .center
            )
        }
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 0) {
                HStack(spacing: 6) {
                    PacManChomper(diameter: 11)
                    Text("BEZEL")
                        .font(PacManTheme.scoreFont(size: 11, weight: .heavy))
                        .tracking(2.8)
                        .foregroundStyle(BezelChrome.pacYellow.opacity(store.needsAttention ? 1 : 0.88))
                }
                Spacer(minLength: 12)
                metricsStripLite
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    statusIcon
                    Text(statusLabel)
                        .font(PacManTheme.scoreFont(size: 10, weight: .semibold))
                        .foregroundStyle(statusTint.opacity(0.95))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4.5)
                .background {
                    Capsule(style: .continuous)
                        .fill(BezelChrome.mazeWall.opacity(0.22))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(BezelChrome.hairline, lineWidth: 0.5)
                        }
                }
                .help(statusHelp)

                if !store.needsAttention {
                    Button {
                        withAnimation(BezelMotion.contentSpring) { showNavMenu.toggle() }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(PacManTheme.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showNavMenu, arrowEdge: .bottom) {
                        navMenu
                            .padding(10)
                    }
                }
            }

            if showNavMenu && !store.needsAttention {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var metricsStripLite: some View {
        HStack(spacing: 8) {
            if store.activeCount > 0 {
                Text("\(store.activeCount) Sessions")
                    .font(PacManTheme.scoreFont(size: 9, weight: .semibold))
                    .foregroundStyle(PacManTheme.pacYellow.opacity(0.85))
            }
            if let usage = store.usage {
                if let five = usage.fiveHour {
                    metricChip("5H \(Int(five.usedPercent.rounded()))%")
                }
                if let seven = usage.sevenDay {
                    metricChip("7D \(Int(seven.usedPercent.rounded()))%")
                }
            }
        }
    }

    private func metricChip(_ text: String) -> some View {
        Text(text)
            .font(PacManTheme.scoreFont(size: 9))
            .foregroundStyle(PacManTheme.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(PacManTheme.mazeWall.opacity(0.18), in: Capsule())
    }

    private var navMenu: some View {
        VStack(alignment: .leading, spacing: 4) {
            navItem("Session list", selected: surfaceMode == .list) {
                surfaceMode = .list
                showNavMenu = false
            }
            navItem("Agent Board", selected: surfaceMode == .board) {
                surfaceMode = .board
                showNavMenu = false
            }
        }
        .frame(minWidth: 140)
    }

    private func navItem(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(selected ? PacManTheme.pacYellow : PacManTheme.title)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if store.needsAttention {
            Circle().fill(BezelChrome.powerPellet).frame(width: 5, height: 5)
        } else if store.liveActivityCount > 0 {
            PacManShape(mouth: 0.6).fill(BezelChrome.pacYellow).frame(width: 8, height: 8)
        } else {
            Circle().fill(BezelChrome.pellet.opacity(0.5)).frame(width: 4, height: 4)
        }
    }

    /// "CLAUDE · VIBE" — which agent + project owns the pending decision.
    private func attribution(for entry: DecisionEntry) -> String {
        guard let session = store.sessions.first(where: { $0.id == entry.key.sessionID }) else {
            return "Agent"
        }
        let source = bezelSourceName(session.source)
        let place = bezelSessionPlace(session)
        return place == source ? source : "\(source) · \(place)"
    }

    @ViewBuilder
    private var decisionHero: some View {
        switch store.surface {
        case .approval:
            if let pending = store.pendingPermission {
                PermissionBand(
                    pending: pending,
                    attribution: attribution(for: pending),
                    onAllowOnce: {
                        BezelSound.play(.allow)
                        store.resolvePermission(allow: true, always: false)
                    },
                    onAlwaysAllow: {
                        BezelSound.play(.allow)
                        store.resolvePermission(allow: true, always: true)
                    },
                    onDeny: {
                        BezelSound.play(.deny)
                        store.resolvePermission(allow: false)
                    }
                )
            }
        case .planReview:
            if let pending = store.pendingPlanReview {
                PlanReviewBand(pending: pending, attribution: attribution(for: pending)) {
                    BezelSound.play(.allow)
                    store.resolvePlanReview(approve: true)
                } onReject: {
                    BezelSound.play(.deny)
                    store.resolvePlanReview(approve: false)
                }
            }
        case .question:
            if let pending = store.pendingQuestion {
                QuestionBand(pending: pending, attribution: attribution(for: pending)) { answers in
                    BezelSound.play(.allow)
                    store.resolveQuestion(answers: answers)
                }
            }
        case .sessionList, .quiet:
            EmptyView()
        }
    }

    /// Dimmed session context under an active decision — max 2 rows.
    @ViewBuilder
    private var contextStrip: some View {
        let live = store.visibleSessions
        if live.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(BezelChrome.hairline)
                    .frame(height: 1)
                    .padding(.bottom, 6)
                ForEach(live.prefix(2)) { session in
                    SessionRow(
                        session: session,
                        isWaiting: store.attentionHead?.key.sessionID == session.id,
                        compact: true,
                        onJump: {
                            store.jump(to: session)
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var quietBody: some View {
        let live = store.visibleSessions
        VStack(spacing: 0) {
            switch surfaceMode {
            case .list:
                sessionListBody(live: live)
            case .detail(let sid):
                if let session = store.sessions.first(where: { $0.id == sid }) {
                    SessionDetailPanel(
                        session: session,
                        onBack: { withAnimation(BezelMotion.contentSpring) { surfaceMode = .list } },
                        onJump: { store.jump(to: session) }
                    )
                } else {
                    sessionListBody(live: live)
                        .onAppear { surfaceMode = .list }
                }
            case .board:
                AgentBoardView(
                    store: store,
                    onSelect: { session in
                        withAnimation(BezelMotion.contentSpring) {
                            surfaceMode = .detail(session.id)
                        }
                    },
                    onMinimize: {
                        withAnimation(BezelMotion.contentSpring) { surfaceMode = .list }
                    }
                )
            }

            if case .list = surfaceMode, let usage = store.usage {
                usageFooter(usage)
                    .padding(.top, live.isEmpty ? 8 : 12)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func sessionListBody(live: [Session]) -> some View {
        if live.isEmpty {
            HStack(spacing: 8) {
                MiniGhost(color: BezelChrome.clyde, size: 18)
                Text("Press start")
                    .font(PacManTheme.scoreFont(size: 14, weight: .semibold))
                    .foregroundStyle(BezelChrome.pacYellow.opacity(0.9))
                Text("· run an agent in your terminal")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(BezelChrome.secondary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        } else {
            VStack(spacing: 2) {
                ForEach(Array(live.prefix(5)), id: \.id) { session in
                    SessionRow(session: session, compact: false) {
                        withAnimation(BezelMotion.contentSpring) {
                            surfaceMode = .detail(session.id)
                        }
                    } onJump: {
                        store.jump(to: session)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    /// Plan usage (5h / 7d windows) — visible at a glance when the notch is open.
    private func usageFooter(_ usage: ClaudeUsageSnapshot) -> some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(BezelChrome.hairline)
                .frame(height: 1)
            HStack(spacing: 16) {
                Text("USAGE")
                    .font(PacManTheme.scoreFont(size: 9, weight: .heavy))
                    .tracking(1.4)
                    .foregroundStyle(BezelChrome.pacYellow.opacity(0.75))
                    .help("Claude plan usage")
                Spacer(minLength: 8)
                if let five = usage.fiveHour {
                    UsageMeter(label: "5h", window: five)
                }
                if let seven = usage.sevenDay {
                    UsageMeter(label: "7d", window: seven)
                }
            }
        }
    }

    private var statusLabel: String {
        if store.needsAttention { return "POWER!" }
        if store.liveActivityCount > 0 { return "\(store.liveActivityCount)UP" }
        return "READY"
    }

    private var statusHelp: String {
        if store.needsAttention { return "Needs your attention" }
        if store.liveActivityCount > 0 {
            let n = store.liveActivityCount
            return n == 1 ? "1 live agent" : "\(n) live agents"
        }
        return "No live agents"
    }

    private var statusTint: Color {
        if store.needsAttention { return BezelChrome.blinky }
        if store.liveActivityCount > 0 { return BezelChrome.pacYellow }
        return BezelChrome.tertiary
    }
}

// MARK: - Usage meter (quiet-mode footer)

private struct UsageMeter: View {
    let label: String
    let window: ClaudeUsageWindow

    var body: some View {
        let pct = window.usedPercent
        HStack(spacing: 7) {
            Text("\(label) \(Int(pct.rounded()))%")
                .font(PacManTheme.scoreFont(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(bezelUsageColor(pct))
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.09))
                .frame(width: 34, height: 3)
                .overlay(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(bezelUsageColor(pct).opacity(0.85))
                        .frame(width: max(3, 34 * CGFloat(min(100, pct) / 100)), height: 3)
                }
        }
        .help(helpText(pct))
    }

    private func helpText(_ pct: Double) -> String {
        var text = String(format: "%@ window %.0f%% used", label, pct)
        if let resets = window.resetsAt {
            let mins = max(0, Int(resets.timeIntervalSince(Date()) / 60))
            if mins < 60 {
                text += " · resets in \(mins)m"
            } else if mins < 60 * 48 {
                text += " · resets in \(mins / 60)h \(mins % 60)m"
            } else {
                text += " · resets in \(mins / (60 * 24))d"
            }
        }
        return text
    }
}

// MARK: - Session row

struct SessionRow: View {
    let session: Session
    var isWaiting: Bool = false
    var compact: Bool = false
    var onSelect: (() -> Void)?
    var onJump: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        Button {
            BezelHaptics.alignment()
            if let onSelect {
                onSelect()
            } else {
                onJump?()
            }
        } label: {
            HStack(spacing: compact ? 10 : 12) {
                PacManPhaseIcon(
                    phase: session.phase,
                    waiting: isWaiting,
                    alive: session.phase == .working
                )

                Text(primaryTitle)
                    .font(.system(size: compact ? 12 : 13.5, weight: .semibold))
                    .foregroundStyle(BezelChrome.title)
                    .lineLimit(1)
                    .frame(width: compact ? 88 : 108, alignment: .leading)

                Text(secondaryLine)
                    .font(.system(size: compact ? 11 : 12, weight: .medium, design: .default))
                    .foregroundStyle(activityColor)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !compact {
                    telemetryColumns
                }

                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    Text(metaLine(now: timeline.date))
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(BezelChrome.tertiary)
                        .lineLimit(1)
                }
                .frame(width: compact ? 72 : 88, alignment: .trailing)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(hovering ? BezelChrome.pacYellow : BezelChrome.tertiary.opacity(0.55))
                    .offset(x: hovering ? 1 : -2, y: hovering ? -1 : 0)
                    .opacity(hovering ? 1 : 0.6)
            }
            .padding(.vertical, compact ? 6 : 9)
            .padding(.horizontal, 10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? Color.white.opacity(0.055) : .clear)
            }
            .contentShape(Rectangle())
            .opacity(hovering ? 1 : (compact ? 0.85 : 0.94))
            .animation(BezelMotion.hoverSpring, value: hovering)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, -10)
        .onHover { hovering = $0 }
        .help(onSelect == nil ? "Jump to session" : "Open session · arrow jumps to terminal")
    }

    @ViewBuilder
    private var telemetryColumns: some View {
        HStack(spacing: 8) {
            if let model = session.model ?? session.agentType.map({ DisplayNames.humanizeAgent($0) }) {
                Text(DisplayNames.humanizeAgent(model))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(BezelChrome.secondary)
                    .lineLimit(1)
                    .frame(width: 56, alignment: .leading)
            }
            if let branch = session.gitBranch {
                Text(branch)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(PacManTheme.moss.opacity(0.85))
                    .lineLimit(1)
                    .frame(width: 52, alignment: .leading)
            }
            if let cost = session.costUSD {
                Text(String(format: "$%.2f", cost))
                    .font(PacManTheme.scoreFont(size: 10))
                    .foregroundStyle(PacManTheme.pacYellow.opacity(0.9))
            }
            if let a = session.diffAdded, let r = session.diffRemoved, a + r > 0 {
                Text("+\(a)/-\(r)")
                    .font(PacManTheme.scoreFont(size: 9))
                    .foregroundStyle(PacManTheme.secondary)
            }
        }
    }

    private var activityColor: Color {
        ActivityTint.color(
            phase: session.phase,
            tool: session.lastTool,
            detail: session.lastToolDetail
        )
    }

    private var primaryTitle: String {
        DisplayNames.placeLabel(
            sessionTitle: session.title,
            cwd: session.cwd,
            agentType: session.agentType,
            sourceName: bezelSourceName(session.source)
        )
    }

    private var secondaryLine: String {
        DisplayNames.sessionSecondaryLine(
            phase: session.phase,
            tool: session.lastTool,
            detail: session.lastToolDetail
        )
    }

    private var metaLine: String {
        metaLine(now: Date())
    }

    private func metaLine(now: Date) -> String {
        var parts: [String] = []
        let source = bezelSourceName(session.source)
        parts.append(source)
        if let clock = RelativeAge.workingClock(since: session.updatedAt, now: now),
           session.phase == .working || session.phase == .waitingPermission
        {
            parts.append(clock)
        }
        if let term = terminalLabel, term != source { parts.append(term) }
        parts.append(RelativeAge.format(since: session.updatedAt, now: now))
        return parts.joined(separator: " · ")
    }

    private var terminalLabel: String? {
        let p = (session.terminal?.termProgram ?? "").lowercased()
        if p.contains("iterm") { return "iTerm" }
        if p.contains("ghostty") { return "Ghostty" }
        if p.contains("warp") { return "Warp" }
        if p.contains("kitty") { return "Kitty" }
        if p.contains("wez") { return "Wez" }
        if p.contains("terminal") || p.contains("apple") { return "Terminal" }
        if p.contains("vscode") || p.contains("cursor") { return "IDE" }
        return nil
    }
}

// MARK: - Decision heroes

struct PermissionBand: View {
    let pending: DecisionEntry
    var attribution: String? = nil
    let onAllowOnce: () -> Void
    let onAlwaysAllow: () -> Void
    let onDeny: () -> Void

    private var hasAlwaysOption: Bool {
        guard let json = pending.permissionSuggestionsJSON else { return false }
        return !PermissionSuggestions.array(from: json).isEmpty
    }

    private var headline: String {
        let parts = pending.summary.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
        return parts.first.map(String.init) ?? pending.summary
    }

    private var detail: String? {
        let parts = pending.summary.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count > 1 else { return nil }
        return String(parts[1]).trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let attribution {
                Eyebrow(text: attribution)
            }
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(headline)
                        .font(.system(size: 17, weight: .semibold, design: .default))
                        .foregroundStyle(BezelChrome.title)
                        .lineLimit(1)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(BezelChrome.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    BezelTextAction(title: "Deny", hint: "⌘N", key: "n", action: onDeny)
                        .help("Deny once (⌘N)")
                    if hasAlwaysOption {
                        BezelTextAction(
                            title: alwaysTitle,
                            hint: "⇧⌘Y",
                            key: "y",
                            modifiers: [.command, .shift],
                            action: onAlwaysAllow
                        )
                        .help(alwaysHelp)
                    }
                    BezelCTA(title: "Allow", hint: "⌘Y", key: "y", action: onAllowOnce)
                        .help("Allow once (⌘Y)")
                }
            }
        }
    }

    private var alwaysTitle: String {
        guard let json = pending.permissionSuggestionsJSON,
              let detail = PermissionSuggestions.alwaysAllowDetail(from: json)
        else { return "Always" }
        let clipped = detail.count > 14 ? String(detail.prefix(12)) + "…" : detail
        return clipped
    }

    private var alwaysHelp: String {
        guard let json = pending.permissionSuggestionsJSON,
              let detail = PermissionSuggestions.alwaysAllowDetail(from: json)
        else { return "Always allow (⇧⌘Y)" }
        return "Always allow \(detail) (⇧⌘Y)"
    }
}

struct PlanReviewBand: View {
    let pending: DecisionEntry
    var attribution: String? = nil
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var expanded = false
    @State private var loaded: PlanBodyLoader.Loaded?

    private var planBody: PlanBodyLoader.Loaded {
        loaded ?? PlanBodyLoader.load(
            planText: pending.planText,
            planFilePath: pending.planFilePath,
            summary: pending.summary
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let attribution {
                Eyebrow(text: attribution)
            }
            Text("Review this plan")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(BezelChrome.title)

            planCodeBox

            // CTAs stay pinned below the box so expand never buries Approve/Reject.
            HStack(spacing: 4) {
                if let path = pending.planFilePath, !path.isEmpty {
                    BezelTextAction(title: "Open plan", hint: "⌘O", key: "o") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                    .help("Reveal the full plan in your editor (⌘O)")
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    BezelTextAction(title: "Reject", hint: "⌘N", key: "n", action: onReject)
                        .help("Send back for changes (⌘N)")
                    BezelCTA(title: "Approve", hint: "↵", action: onApprove)
                        .help("Approve the plan (↵)")
                }
            }
        }
        .onAppear {
            if loaded == nil {
                loaded = PlanBodyLoader.load(
                    planText: pending.planText,
                    planFilePath: pending.planFilePath,
                    summary: pending.summary
                )
            }
        }
    }

    private var planCodeBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if expanded {
                    ScrollView(.vertical, showsIndicators: true) {
                        planTextView(lineLimit: nil)
                    }
                    .frame(maxHeight: 200)
                } else {
                    planTextView(lineLimit: 5)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            HStack(spacing: 8) {
                Button {
                    withAnimation(.snappy(duration: 0.22)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Text(expanded ? "Hide plan" : "Show plan")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(BezelChrome.pacYellow.opacity(0.92))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expanded ? "Collapse plan preview" : "Expand to read the full plan")

                if planBody.truncated {
                    Text(planBody.fromFile ? "Truncated · open file for full text" : "Truncated")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(BezelChrome.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.38))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(BezelChrome.hairline, lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private func planTextView(lineLimit: Int?) -> some View {
        Text(planBody.text)
            .font(.system(size: 11, weight: .regular, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.88))
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(lineLimit)
            .truncationMode(.tail)
            .textSelection(.enabled)
            .multilineTextAlignment(.leading)
    }
}

struct QuestionBand: View {
    let pending: DecisionEntry
    var attribution: String? = nil
    let onAnswer: ([AskUserQuestionAnswer]) -> Void
    @State private var selectedLabels: [String: [String]] = [:]
    @State private var freeTextByQuestion: [String: String] = [:]
    @FocusState private var focusedQuestion: String?

    private var questions: [QuestionItem] {
        if pending.questions.isEmpty {
            let prompt = pending.prompt ?? pending.summary
            return [QuestionItem(question: prompt, options: [])]
        }
        return pending.questions
    }

    private var canSubmit: Bool {
        questions.allSatisfy { item in
            if item.options.isEmpty {
                let text = (freeTextByQuestion[item.question] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return !text.isEmpty
            }
            return !(selectedLabels[item.question] ?? []).isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header — who is asking + how many answers are still needed.
            HStack(alignment: .firstTextBaseline) {
                if let attribution {
                    Eyebrow(text: attribution)
                }
                Spacer()
                if questions.count > 1 {
                    Text("\(answeredCount)/\(questions.count) answered")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(BezelChrome.tertiary)
                        .monospacedDigit()
                }
            }

            // Bounded scroll — many questions never blow up the notch.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(questions.enumerated()), id: \.offset) { _, item in
                        questionBlock(item)
                    }
                }
                .padding(.trailing, 2)
            }
            .frame(maxHeight: 236)

            // Footer — validation hint left, submit right.
            HStack(alignment: .center) {
                Text(canSubmit ? "Press ↵ to submit" : "Answer every question to continue")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(BezelChrome.tertiary)
                    .animation(.snappy(duration: 0.2), value: canSubmit)
                Spacer()
                BezelCTA(title: "Submit", hint: "↵", action: { onAnswer(buildAnswers()) })
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1 : 0.4)
            }
        }
    }

    private var answeredCount: Int {
        questions.filter { item in
            if item.options.isEmpty {
                return !(freeTextByQuestion[item.question] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return !(selectedLabels[item.question] ?? []).isEmpty
        }.count
    }

    @ViewBuilder
    private func questionBlock(_ item: QuestionItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.question)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(BezelChrome.title.opacity(0.92))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if item.options.isEmpty {
                TextField("Type your answer", text: freeTextBinding(for: item.question))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(BezelChrome.title)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.045))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                focusedQuestion == item.question
                                    ? BezelChrome.pacYellow.opacity(0.65)
                                    : BezelChrome.hairline,
                                lineWidth: focusedQuestion == item.question ? 1 : 0.5
                            )
                    }
                    .focused($focusedQuestion, equals: item.question)
                    .animation(.snappy(duration: 0.18), value: focusedQuestion)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(item.options.enumerated()), id: \.offset) { _, opt in
                        OptionRow(
                            option: opt,
                            selected: (selectedLabels[item.question] ?? []).contains(opt.label),
                            multiSelect: item.multiSelect
                        ) {
                            toggle(option: opt.label, for: item)
                        }
                    }
                }
            }
        }
    }

    private func freeTextBinding(for question: String) -> Binding<String> {
        Binding(
            get: { freeTextByQuestion[question] ?? "" },
            set: { freeTextByQuestion[question] = $0 }
        )
    }

    private func toggle(option: String, for item: QuestionItem) {
        BezelHaptics.generic()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
            var current = selectedLabels[item.question] ?? []
            if item.multiSelect {
                if let idx = current.firstIndex(of: option) { current.remove(at: idx) }
                else { current.append(option) }
            } else {
                current = [option]
            }
            selectedLabels[item.question] = current
        }
    }

    private func buildAnswers() -> [AskUserQuestionAnswer] {
        questions.map { item in
            if item.options.isEmpty {
                let text = (freeTextByQuestion[item.question] ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return AskUserQuestionAnswer(question: item.question, answer: text)
            }
            let labels = selectedLabels[item.question] ?? []
            return AskUserQuestionAnswer(question: item.question, answer: labels.joined(separator: ", "))
        }
    }
}

/// One selectable answer — radio (single) or checkbox (multi), label + description.
private struct OptionRow: View {
    let option: QuestionOption
    let selected: Bool
    let multiSelect: Bool
    let onToggle: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: 10) {
                indicator
                    .padding(.leading, 1)
                VStack(alignment: .leading, spacing: 1.5) {
                    Text(option.label)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                        .foregroundStyle(BezelChrome.title.opacity(selected ? 1 : 0.9))
                        .lineLimit(2)
                    if let description = option.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(BezelChrome.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BezelChrome.pacYellow)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background { rowSurface }
            .overlay { rowStroke }
            .contentShape(Rectangle())
            .animation(.snappy(duration: 0.16), value: selected)
            .animation(.snappy(duration: 0.16), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var rowSurface: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                selected
                    ? BezelChrome.pacYellow.opacity(0.16)
                    : Color.white.opacity(hovering ? 0.075 : 0.045)
            )
    }

    private var rowStroke: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(
                selected ? BezelChrome.pacYellow.opacity(0.65) : BezelChrome.hairline,
                lineWidth: selected ? 1 : 0.5
            )
    }

    @ViewBuilder
    private var indicator: some View {
        if multiSelect {
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .strokeBorder(selected ? BezelChrome.pacYellow : BezelChrome.tertiary, lineWidth: 1.2)
                .background {
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .fill(selected ? BezelChrome.pacYellow.opacity(0.25) : .clear)
                }
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(BezelChrome.maze)
                    }
                }
                .frame(width: 15, height: 15)
        } else {
            Circle()
                .strokeBorder(selected ? BezelChrome.pacYellow : BezelChrome.tertiary, lineWidth: 1.2)
                .background {
                    if selected {
                        Circle()
                            .fill(BezelChrome.pacYellow)
                            .padding(3.5)
                    }
                }
                .frame(width: 15, height: 15)
        }
    }
}

/// Primary luminous action — steel capsule with soft inner light.
private struct BezelCTA: View {
    let title: String
    var hint: String? = nil
    var key: KeyEquivalent? = nil
    var modifiers: EventModifiers = .command
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            BezelHaptics.generic()
            action()
        } label: {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                if let hint {
                    KeyHint(text: hint, onFill: true)
                }
            }
            .foregroundStyle(BezelChrome.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background { ctaSurface }
            .shadow(color: BezelChrome.pacYellow.opacity(hovering ? 0.55 : 0.35), radius: hovering ? 12 : 8, y: 1)
            .scaleEffect(hovering ? 1.02 : 1)
            .animation(.snappy(duration: 0.16), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .modifier(OptionalKeyShortcut(key: key, modifiers: modifiers, prominent: true))
    }

    private var ctaSurface: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(BezelChrome.pacYellow)
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
        }
    }
}

/// Secondary action — subtle hover surface.
private struct BezelTextAction: View {
    let title: String
    var hint: String? = nil
    var key: KeyEquivalent? = nil
    var modifiers: EventModifiers = .command
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            BezelHaptics.generic()
            action()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                if let hint {
                    KeyHint(text: hint)
                }
            }
            .foregroundStyle(hovering ? BezelChrome.title : BezelChrome.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(hovering ? Color.white.opacity(0.06) : .clear)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .modifier(OptionalKeyShortcut(key: key, modifiers: modifiers, prominent: false))
    }
}

private struct OptionalKeyShortcut: ViewModifier {
    let key: KeyEquivalent?
    let modifiers: EventModifiers
    let prominent: Bool

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: modifiers)
        } else if prominent {
            content.keyboardShortcut(.defaultAction)
        } else {
            content
        }
    }
}
