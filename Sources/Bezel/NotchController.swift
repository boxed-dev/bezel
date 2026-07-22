import SwiftUI
import Observation
import AppKit
import Combine
import DynamicNotchKit
import BezelCore

// MARK: - Design tokens (docs/PLAN.md visual)

private enum BezelChrome {
    /// Near-black ink — brand ground
    static let ink = Color(red: 0.04, green: 0.045, blue: 0.055)
    /// Cool steel accent
    static let steel = Color(red: 0.62, green: 0.70, blue: 0.76)
    /// Warm tungsten — needs attention
    static let tungsten = Color(red: 0.86, green: 0.72, blue: 0.48)
    static let moss = Color(red: 0.48, green: 0.58, blue: 0.50)
    static let live = Color(red: 0.42, green: 0.86, blue: 0.58)
    static let title = Color.white.opacity(0.96)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.34)
    static let hairline = Color.white.opacity(0.08)
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

// MARK: - Shared view helpers

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

/// Consistent usage-meter tint across compact + expanded surfaces.
func bezelUsageColor(_ pct: Double) -> Color {
    if pct >= 80 { return Color.red.opacity(0.9) }
    if pct >= 50 { return BezelChrome.tungsten }
    return BezelChrome.steel
}

/// Short display name for where a session lives (title → cwd basename → id fragment).
func bezelSessionPlace(_ session: Session) -> String? {
    if let title = session.title, !title.isEmpty, !DisplayNames.looksLikeSessionID(title) {
        return title
    }
    if let cwd = session.cwd, !cwd.isEmpty {
        let base = (cwd as NSString).lastPathComponent
        if !base.isEmpty { return base }
    }
    return nil
}

/// Tracked-caps eyebrow label — sits above decision heroes to attribute the asker.
private struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.7)
            .foregroundStyle(BezelChrome.tungsten.opacity(0.9))
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

/// Lets compact surfaces request expand without holding the DynamicNotch directly.
@MainActor
private final class NotchExpandBridge {
    var expand: (() -> Void)?
    func requestExpand() { expand?() }
}

@MainActor
final class NotchController {
    private let store: SessionStore
    private var notch: DynamicNotch<ExpandedHUD, CompactLeading, CompactTrailing>?
    private let expandBridge = NotchExpandBridge()
    private var isWatching = false
    private var lastAttention = false
    private var lastActiveCount = 0
    private var lastUsageEpoch: UInt64 = 0
    private var lastSessionStartEpoch: UInt64 = 0
    private var leaveCollapseTask: Task<Void, Never>?
    private var hoverExpandTask: Task<Void, Never>?
    private var attentionWatcherGeneration: UInt64 = 0
    private var hoverCancellable: AnyCancellable?
    /// Tracks presentation for hover gating (`DynamicNotch.state` is not public).
    private var isExpanded = false

    /// Delay before collapsing after mouse leave (avoids flicker at the edge).
    private let leaveCollapseDelay: Duration = .milliseconds(180)
    /// Poll while kit hover is true but cursor is still over compact wings.
    private let hoverNotchPollInterval: Duration = .milliseconds(16)

    init(store: SessionStore) {
        self.store = store
    }

    func start() {
        let store = self.store
        let expandBridge = self.expandBridge
        // keepVisible / increaseShadow only — kit haptic would fire on wing hover too;
        // we haptic when expand actually happens (physical notch or click).
        let notch = DynamicNotch(
            hoverBehavior: [.keepVisible, .increaseShadow]
        ) {
            ExpandedHUD(store: store)
        } compactLeading: {
            CompactLeading(store: store, onExpand: { expandBridge.requestExpand() })
        } compactTrailing: {
            CompactTrailing(store: store, onExpand: { expandBridge.requestExpand() })
        }
        self.notch = notch
        expandBridge.expand = { [weak self] in
            Task { @MainActor in
                guard let self, let notch = self.notch else { return }
                BezelHaptics.alignment()
                self.isExpanded = true
                await notch.expand()
            }
        }

        Task {
            self.isExpanded = false
            await notch.compact()
        }

        // DynamicNotchKit does NOT auto expand/collapse on hover — we own that.
        // Kit `isHovering` covers compact wings + cutout; we only expand for the cutout.
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

    /// Hover enter → expand only inside the physical notch cutout.
    /// Hover leave → compact — unless a decision is waiting.
    private func handleHoverChange(_ hovering: Bool) {
        leaveCollapseTask?.cancel()
        leaveCollapseTask = nil
        hoverExpandTask?.cancel()
        hoverExpandTask = nil

        if hovering {
            hoverExpandTask = Task { @MainActor [weak self] in
                await self?.expandWhenCursorEntersPhysicalNotch()
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
            self.isExpanded = false
            await notch.compact()
        }
    }

    /// Kit reports hover over leading/trailing wings; wait until the cursor is
    /// inside Apple's notch frame before expanding (click-to-expand stays separate).
    private func expandWhenCursorEntersPhysicalNotch() async {
        while !Task.isCancelled {
            guard let notch, notch.isHovering else { return }
            if isExpanded { return }

            let screen = notch.windowController?.window?.screen
                ?? Self.screenContainingMouse()
                ?? NSScreen.main
            if let screen,
               let bounds = Self.physicalNotchBounds(on: screen) {
                let mouse = NSEvent.mouseLocation
                guard NotchHoverActivation.shouldExpandOnHover(
                    x: mouse.x,
                    y: mouse.y,
                    notchBounds: bounds
                ) else {
                    try? await Task.sleep(for: hoverNotchPollInterval)
                    continue
                }
                BezelHaptics.alignment()
                isExpanded = true
                await notch.expand()
                return
            }

            try? await Task.sleep(for: hoverNotchPollInterval)
        }
    }

    /// Mirrors DynamicNotchKit's `NSScreen.notchFrame` (internal to the kit).
    private static func physicalNotchBounds(on screen: NSScreen) -> NotchBounds? {
        guard
            let left = screen.auxiliaryTopLeftArea?.width,
            let right = screen.auxiliaryTopRightArea?.width
        else { return nil }

        let height = screen.safeAreaInsets.top
        let width = screen.frame.width - left - right
        guard width > 0, height > 0 else { return nil }

        return NotchBounds(
            minX: screen.frame.midX - (width / 2),
            minY: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    private static func screenContainingMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
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
                        self.isExpanded = true
                        await self.notch?.expand()
                    }
                case .compact:
                    self.isExpanded = false
                    await self.notch?.compact()
                case .noop:
                    if active < self.lastActiveCount && active == 0 {
                        BezelSound.play(.done)
                    }
                }

                // Force NotchView to remeasure compact trailing when count/usage changes.
                let usageChanged = usageEpoch != self.lastUsageEpoch
                if (active != self.lastActiveCount || usageChanged), let notch = self.notch {
                    notch.objectWillChange.send()
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
        hoverExpandTask?.cancel()
        hoverExpandTask = nil
        hoverCancellable?.cancel()
        hoverCancellable = nil
        isExpanded = false
        Task {
            await notch?.hide()
        }
    }
}

// MARK: - Compact (always-on notch)

struct CompactLeading: View {
    @Bindable var store: SessionStore
    var onExpand: (() -> Void)? = nil

    var body: some View {
        let _ = store.presenceEpoch
        Button {
            // Primary = expand in place — never jump (NotchInteraction.compactLeadingPrimary).
            _ = NotchInteraction.compactLeadingPrimary()
            onExpand?()
        } label: {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(store.needsAttention ? "Needs you — expand" : "Expand")
        .onAppear { pulse = store.needsAttention }
        .onChange(of: store.needsAttention) { _, needs in
            pulse = needs
        }
    }

    @State private var pulse = false

    private var statusColor: Color {
        if store.needsAttention { return BezelChrome.tungsten }
        if store.liveActivityCount > 0 { return BezelChrome.steel }
        if store.activeCount > 0 { return BezelChrome.moss }
        return BezelChrome.tertiary
    }
}

struct CompactTrailing: View {
    @Bindable var store: SessionStore
    var onExpand: (() -> Void)? = nil

    var body: some View {
        // Read epochs so Observation invalidates on session + usage changes.
        let _ = store.presenceEpoch
        let _ = store.usageEpoch
        Button {
            // Primary = expand — never TerminalJumper / store.jump (A1 / A2).
            _ = NotchInteraction.compactTrailingPrimary(context: trailingContext)
            onExpand?()
        } label: {
            trailingContent
        }
        .buttonStyle(.plain)
        .frame(minWidth: 18, minHeight: 12)
        .animation(.snappy(duration: 0.2), value: store.usageEpoch)
        .help(trailingHelp)
    }

    private var trailingContext: NotchInteraction.CompactTrailingContext {
        if store.needsAttention { return .attention }
        if store.usage != nil { return .usage }
        if store.liveActivityCount > 0 { return .liveCount }
        return .empty
    }

    @ViewBuilder
    private var trailingContent: some View {
        if store.needsAttention {
            let pending = store.decisionQueue.entries.count
            Text(pending > 1 ? "!\(pending)" : "!")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(BezelChrome.tungsten)
                .monospacedDigit()
        } else if let usage = store.usage {
            if UsageGlance.showsResetCountdown(usage) {
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    usageText(usage, now: timeline.date)
                }
            } else if let text = UsageGlance.compactText(usage) {
                usageTextLabel(text, usage: usage)
            }
        } else if store.liveActivityCount > 0 {
            Text("\(store.liveActivityCount)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(BezelChrome.steel)
                .monospacedDigit()
        }
    }

    private var trailingHelp: String {
        if store.needsAttention {
            let pending = store.decisionQueue.entries.count
            return "\(pending) decision\(pending == 1 ? "" : "s") waiting — expand"
        }
        if let usage = store.usage {
            return (UsageGlance.compactText(usage).map { "\($0) — expand" })
                ?? (usage.helpText + " — expand")
        }
        if store.liveActivityCount > 0 {
            return "\(store.liveActivityCount) live — expand"
        }
        return "Expand"
    }

    @ViewBuilder
    private func usageText(_ usage: ClaudeUsageSnapshot, now: Date) -> some View {
        if let text = UsageGlance.compactText(usage, now: now) {
            usageTextLabel(text, usage: usage)
        }
    }

    private func usageTextLabel(_ text: String, usage: ClaudeUsageSnapshot) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(bezelUsageColor(Double(usage.primaryPercent ?? 0)))
            .monospacedDigit()
    }
}

// MARK: - Expanded HUD
// Three pillars only: USAGE / NEEDS YOU / SESSIONS. Jump is secondary never default.

struct ExpandedHUD: View {
    @Bindable var store: SessionStore
    @State private var selectedSessionID: SessionID?

    var body: some View {
        let live = store.sessions.filter { $0.phase != .done }
        let sections = ExpandedNotchLayout.sections(
            hasUsage: store.usage != nil,
            needsYou: store.needsAttention,
            hasSessions: !live.isEmpty
        )
        ZStack {
            islandSurface
            atmosphere
            VStack(alignment: .leading, spacing: 0) {
                // Minimal wordmark — not a dense brand/status capsule hero (E4).
                Text("BEZEL")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(3.2)
                    .foregroundStyle(BezelChrome.title.opacity(0.28))

                if sections.isEmpty {
                    Text("No agents yet")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(BezelChrome.secondary)
                        .padding(.top, 14)
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                            switch section {
                            case .usage:
                                if let usage = store.usage {
                                    usageSection(usage)
                                }
                            case .needsYou:
                                needsYouSection
                            case .sessions:
                                sessionsSection(live: live)
                            }
                        }
                    }
                    .padding(.top, 12)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .frame(minWidth: 580, idealWidth: 640, maxWidth: 720)
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: store.needsAttention)
        .animation(.spring(response: 0.36, dampingFraction: 0.9), value: store.activeCount)
    }

    private var islandSurface: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(BezelChrome.ink)
            .allowsHitTesting(false)
    }

    private var atmosphere: some View {
        ZStack {
            RadialGradient(
                colors: store.needsAttention
                    ? [BezelChrome.tungsten.opacity(0.18), BezelChrome.tungsten.opacity(0.04), .clear]
                    : [BezelChrome.steel.opacity(0.12), BezelChrome.steel.opacity(0.03), .clear],
                center: .top,
                startRadius: 4,
                endRadius: 220
            )
            LinearGradient(
                colors: [.white.opacity(0.03), .clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .allowsHitTesting(false)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(BezelChrome.tertiary)
    }

    /// USAGE glance — primary % + reset; no charts; click is no-op externally.
    private func usageSection(_ usage: ClaudeUsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("USAGE")
            HStack(spacing: 16) {
                Group {
                    if UsageGlance.showsResetCountdown(usage) {
                        TimelineView(.periodic(from: .now, by: 60)) { timeline in
                            if let text = UsageGlance.compactText(usage, now: timeline.date) {
                                usagePrimaryLabel(text, percent: usage.primaryPercent)
                            }
                        }
                    } else if let text = UsageGlance.compactText(usage) {
                        usagePrimaryLabel(text, percent: usage.primaryPercent)
                    }
                }
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

    private func usagePrimaryLabel(_ text: String, percent: Int?) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(bezelUsageColor(Double(percent ?? 0)))
            .monospacedDigit()
    }

    @ViewBuilder
    private var needsYouSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("NEEDS YOU")
            decisionHero
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func sessionsSection(live: [Session]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("SESSIONS")
            VStack(spacing: 2) {
                ForEach(Array(live.prefix(5)), id: \.id) { session in
                    SessionRow(
                        session: session,
                        isWaiting: store.attentionHead?.key.sessionID == session.id,
                        isSelected: selectedSessionID == session.id,
                        compact: store.needsAttention
                    ) {
                        // Primary = select (A3) — never jump.
                        _ = NotchInteraction.sessionRowPrimary(sessionID: session.id)
                        BezelHaptics.alignment()
                        selectedSessionID = session.id
                    } onJump: {
                        _ = NotchInteraction.sessionRowSecondary(sessionID: session.id)
                        BezelHaptics.alignment()
                        store.jump(to: session)
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    /// "CLAUDE · VIBE" — which agent + project owns the pending decision.
    private func attribution(for entry: DecisionEntry) -> String {
        guard let session = store.sessions.first(where: { $0.id == entry.key.sessionID }) else {
            return "Agent"
        }
        // Prefer SessionLabel when available (B1); fall back to source · place.
        let label = SessionLabel.format(session: session)
        let parts = label.split(separator: " · ", maxSplits: 2, omittingEmptySubsequences: true)
        if parts.count >= 2 {
            return "\(parts[0]) · \(parts[1])"
        }
        return bezelSourceName(session.source)
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
}

// MARK: - Usage meter (USAGE section glance)

private struct UsageMeter: View {
    let label: String
    let window: ClaudeUsageWindow

    var body: some View {
        let pct = window.usedPercent
        HStack(spacing: 7) {
            Text("\(label) \(Int(pct.rounded()))%")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
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
    var isSelected: Bool = false
    var compact: Bool = false
    var onSelect: (() -> Void)?
    var onJump: (() -> Void)?
    @State private var hovering = false

    /// Compatibility: trailing closure historically meant jump; treat as select + keep jump via onJump.
    init(
        session: Session,
        isWaiting: Bool = false,
        isSelected: Bool = false,
        compact: Bool = false,
        onSelect: (() -> Void)? = nil,
        onJump: (() -> Void)? = nil
    ) {
        self.session = session
        self.isWaiting = isWaiting
        self.isSelected = isSelected
        self.compact = compact
        self.onSelect = onSelect
        self.onJump = onJump
    }

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            Button {
                // Primary = select / no-op — never jump (A3).
                onSelect?()
            } label: {
                HStack(spacing: compact ? 10 : 14) {
                    PhaseDot(fill: phaseFill, alive: session.phase == .working, waiting: isWaiting)

                    Text(rowLabel)
                        .font(.system(size: compact ? 12 : 13.5, weight: .semibold))
                        .foregroundStyle(BezelChrome.title)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        Text(relativeAge)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(BezelChrome.tertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, compact ? 6 : 9)
                .padding(.horizontal, 10)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            isSelected
                                ? Color.white.opacity(0.08)
                                : (hovering ? Color.white.opacity(0.055) : .clear)
                        )
                }
                .contentShape(Rectangle())
                .opacity(hovering || isSelected ? 1 : (compact ? 0.85 : 0.94))
                .animation(.snappy(duration: 0.18), value: hovering)
                .animation(.snappy(duration: 0.18), value: isSelected)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                    // Secondary jump via long-press (does not steal primary tap).
                    onJump?()
                }
            )

            if onJump != nil {
                Button {
                    onJump?()
                } label: {
                    Text("Jump")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(hovering ? BezelChrome.steel : BezelChrome.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.white.opacity(hovering ? 0.07 : 0.04))
                        }
                }
                .buttonStyle(.plain)
                .help("Jump to session")
            }
        }
        .padding(.horizontal, -10)
        .onHover { hovering = $0 }
        .help("Select session — Jump is secondary")
    }

    /// Provider · project · phase via SessionLabel (B1).
    private var rowLabel: String {
        SessionLabel.format(session: session)
    }

    private var relativeAge: String {
        RelativeAge.format(since: session.updatedAt)
    }

    private var phaseFill: Color {
        switch session.phase {
        case .waitingPermission, .waitingQuestion, .planReview: return BezelChrome.tungsten
        case .working: return BezelChrome.steel
        case .done: return BezelChrome.moss
        case .error: return .red.opacity(0.85)
        case .idle: return BezelChrome.tertiary
        }
    }
}

/// Phase dot with a soft breathing pulse for live sessions.
private struct PhaseDot: View {
    let fill: Color
    var alive: Bool = false
    var waiting: Bool = false
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: 6, height: 6)
            .shadow(color: fill.opacity(waiting || alive ? 0.75 : 0), radius: 5)
            .scaleEffect(pulsing && alive ? 1.3 : 1)
            .opacity(pulsing && alive ? 0.72 : 1)
            .animation(
                alive ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : .default,
                value: pulsing
            )
            .onAppear { pulsing = alive }
            .onChange(of: alive) { _, now in pulsing = now }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let attribution {
                Eyebrow(text: attribution)
            }
            Text("Review this plan")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(BezelChrome.title)

            // Quote-style preview — full plan is one click away when it exists on disk.
            Text(planPreview)
                .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                .foregroundStyle(BezelChrome.secondary)
                .lineLimit(3)
                .truncationMode(.tail)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(BezelChrome.hairline, lineWidth: 0.5)
                }

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
    }

    private var planPreview: String {
        let raw = pending.planText ?? pending.summary
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 280 ? String(trimmed.prefix(279)) + "…" : trimmed
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
                                    ? BezelChrome.steel.opacity(0.6)
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
                        .foregroundStyle(BezelChrome.steel)
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
                    ? BezelChrome.steel.opacity(0.14)
                    : Color.white.opacity(hovering ? 0.075 : 0.045)
            )
    }

    private var rowStroke: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(
                selected ? BezelChrome.steel.opacity(0.55) : BezelChrome.hairline,
                lineWidth: selected ? 1 : 0.5
            )
    }

    @ViewBuilder
    private var indicator: some View {
        if multiSelect {
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .strokeBorder(selected ? BezelChrome.steel : BezelChrome.tertiary, lineWidth: 1.2)
                .background {
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .fill(selected ? BezelChrome.steel.opacity(0.25) : .clear)
                }
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(BezelChrome.steel)
                    }
                }
                .frame(width: 15, height: 15)
        } else {
            Circle()
                .strokeBorder(selected ? BezelChrome.steel : BezelChrome.tertiary, lineWidth: 1.2)
                .background {
                    if selected {
                        Circle()
                            .fill(BezelChrome.steel)
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
            .shadow(color: BezelChrome.steel.opacity(hovering ? 0.55 : 0.35), radius: hovering ? 12 : 8, y: 1)
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
                .fill(BezelChrome.steel)
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .clear],
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
