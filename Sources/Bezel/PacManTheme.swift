import SwiftUI
import BezelCore

// MARK: - Pac-Man arcade theme (original shapes — NAMCO-inspired palette, not assets)

/// Classic arcade tokens mapped to notch UX:
/// • Pac-Man chomp = agent working · Ghost = session phase · Power pellet = needs you
enum PacManTheme {
    static let maze = Color(red: 0.02, green: 0.02, blue: 0.08)
    static let mazeWall = Color(red: 0.13, green: 0.18, blue: 0.86)
    static let pacYellow = Color(red: 1.0, green: 0.92, blue: 0.16)
    static let pellet = Color.white.opacity(0.92)
    static let powerPellet = Color.white

    static let blinky = Color(red: 1.0, green: 0.18, blue: 0.18)
    static let pinky = Color(red: 1.0, green: 0.72, blue: 0.82)
    static let inky = Color(red: 0.28, green: 0.92, blue: 0.96)
    static let clyde = Color(red: 1.0, green: 0.72, blue: 0.38)

    static let fruitOrange = Color(red: 1.0, green: 0.55, blue: 0.12)
    static let fruitCherry = Color(red: 0.95, green: 0.22, blue: 0.35)

    static let title = Color.white.opacity(0.96)
    static let secondary = Color.white.opacity(0.58)
    static let tertiary = Color.white.opacity(0.36)
    static let hairline = Color.white.opacity(0.10)

    // Legacy aliases used across NotchController
    static let ink = maze
    static let steel = inky
    static let tungsten = blinky
    static let moss = Color(red: 0.45, green: 0.82, blue: 0.42)
    static let live = pacYellow

    static func ghost(for phase: SessionPhase) -> Color {
        switch phase {
        case .waitingPermission, .waitingQuestion: return pinky
        case .planReview: return clyde
        case .working: return inky
        case .error: return blinky
        case .done: return moss
        case .idle: return tertiary
        }
    }

    static func usageColor(_ pct: Double) -> Color {
        if pct >= 80 { return blinky }
        if pct >= 50 { return fruitOrange }
        return pacYellow
    }

    static func scoreFont(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Shapes

struct PacManShape: Shape {
    var mouth: CGFloat

    var animatableData: CGFloat {
        get { mouth }
        set { mouth = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let gap = 12 + mouth * 38
        var p = Path()
        p.move(to: c)
        p.addArc(
            center: c,
            radius: r,
            startAngle: .degrees(gap),
            endAngle: .degrees(360 - gap),
            clockwise: false
        )
        p.closeSubpath()
        return p
    }
}

struct GhostShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let r = w * 0.42
        var p = Path()
        p.addRoundedRect(
            in: CGRect(x: rect.minX, y: rect.minY, width: w, height: h * 0.82),
            cornerSize: CGSize(width: r, height: r)
        )
        let footW = w / 3
        let baseY = rect.minY + h * 0.78
        for i in 0..<3 {
            let cx = rect.minX + footW * (CGFloat(i) + 0.5)
            p.addEllipse(in: CGRect(x: cx - footW * 0.28, y: baseY, width: footW * 0.56, height: h * 0.22))
        }
        return p
    }
}

// MARK: - Reusable views

struct MazePelletField: View {
    var spacing: CGFloat = 14
    var opacity: Double = 0.14

    var body: some View {
        Canvas { context, size in
            let cols = Int(size.width / spacing) + 1
            let rows = Int(size.height / spacing) + 1
            for row in 0..<rows {
                for col in 0..<cols {
                    let x = CGFloat(col) * spacing + spacing * 0.5
                    let y = CGFloat(row) * spacing + spacing * 0.5
                    let r: CGFloat = (row + col) % 7 == 0 ? 2.2 : 1.2
                    let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(PacManTheme.pellet.opacity(opacity)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct PacManChomper: View {
    var diameter: CGFloat = 14
    var color: Color = PacManTheme.pacYellow

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let mouth = (sin(t * 9) + 1) / 2
            PacManShape(mouth: mouth)
                .fill(color)
                .frame(width: diameter, height: diameter)
                .shadow(color: color.opacity(0.55), radius: 4)
        }
    }
}

struct PowerPelletPulse: View {
    var diameter: CGFloat = 12
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(PacManTheme.blinky.opacity(0.5), lineWidth: 1.5)
                .frame(width: diameter + 4, height: diameter + 4)
                .scaleEffect(pulse ? 1.35 : 1)
                .opacity(pulse ? 0.2 : 0.65)
            Circle()
                .fill(PacManTheme.powerPellet)
                .frame(width: diameter * 0.55, height: diameter * 0.55)
                .shadow(color: PacManTheme.blinky.opacity(0.8), radius: pulse ? 8 : 4)
        }
        .onAppear { pulse = true }
        .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true), value: pulse)
    }
}

struct MiniGhost: View {
    var color: Color
    var size: CGFloat = 14
    var waiting: Bool = false
    @State private var wobble = false

    var body: some View {
        ZStack {
            GhostShape()
                .fill(color)
                .frame(width: size, height: size * 1.05)
            HStack(spacing: size * 0.14) {
                eye(size: size)
                eye(size: size)
            }
            .offset(y: -size * 0.08)
        }
        .scaleEffect(wobble && waiting ? 1.08 : 1)
        .animation(
            waiting ? .easeInOut(duration: 0.45).repeatForever(autoreverses: true) : .default,
            value: wobble
        )
        .onAppear { wobble = waiting }
        .onChange(of: waiting) { _, now in wobble = now }
    }

    private func eye(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(.white).frame(width: size * 0.22, height: size * 0.22)
            Circle().fill(PacManTheme.maze).frame(width: size * 0.11, height: size * 0.11)
                .offset(x: size * 0.03)
        }
    }
}

struct PacManPhaseIcon: View {
    let phase: SessionPhase
    var waiting: Bool = false
    var alive: Bool = false

    var body: some View {
        Group {
            if alive {
                PacManChomper(diameter: 13, color: PacManTheme.pacYellow)
            } else {
                MiniGhost(color: PacManTheme.ghost(for: phase), size: 13, waiting: waiting)
            }
        }
        .frame(width: 14, height: 14)
    }
}

struct PacManScoreText: View {
    let text: String
    var color: Color = PacManTheme.pacYellow

    var body: some View {
        Text(text)
            .font(PacManTheme.scoreFont(size: 11))
            .foregroundStyle(color)
            .shadow(color: color.opacity(0.35), radius: 0, x: 0, y: 1)
            .monospacedDigit()
    }
}

/// Notch-shaped brand mark — chomper + ghost dots for Settings / onboarding.
struct PacManNotchMark: View {
    var width: CGFloat = 64
    var height: CGFloat = 16

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(PacManTheme.mazeWall.opacity(0.22))
            MazePelletField(spacing: 9, opacity: 0.18)
                .clipShape(Capsule(style: .continuous))
            Capsule(style: .continuous)
                .strokeBorder(PacManTheme.mazeWall.opacity(0.45), lineWidth: 0.5)
            HStack(spacing: max(3, width * 0.06)) {
                PacManChomper(diameter: height * 0.72)
                HStack(spacing: max(2, width * 0.035)) {
                    ghostDot(PacManTheme.blinky)
                    ghostDot(PacManTheme.pinky)
                    ghostDot(PacManTheme.inky)
                }
            }
        }
        .frame(width: width, height: height)
    }

    private func ghostDot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: height * 0.34, height: height * 0.34)
    }
}
