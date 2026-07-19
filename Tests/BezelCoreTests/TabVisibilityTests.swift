import Testing
import BezelCore

@Suite("TabVisibility")
struct TabVisibilityTests {
    struct MatrixCase: Sendable {
        let name: String
        let session: TerminalHint?
        let front: FrontTabHint?
        let expected: TabMatch
    }

    private static let matrix: [MatrixCase] = [
        MatrixCase(
            name: "matched iterm session id",
            session: TerminalHint(itermSession: "w0t0p0:ABC123"),
            front: FrontTabHint(itermSession: "w0t0p0:ABC123"),
            expected: .matched
        ),
MatrixCase(
            name: "mismatch iterm session id",
            session: TerminalHint(itermSession: "w0t0p0:ABC123"),
            front: FrontTabHint(itermSession: "w0t0p0:XYZ999"),
            expected: .mismatch
        ),
MatrixCase(
            name: "matched iterm suffix",
            session: TerminalHint(itermSession: "w0t0p0:ABC123"),
            front: FrontTabHint(itermSession: "ABC123"),
            expected: .matched
        ),
MatrixCase(
            name: "matched tty",
            session: TerminalHint(tty: "/dev/ttys003"),
            front: FrontTabHint(tty: "/dev/ttys003"),
            expected: .matched
        ),
MatrixCase(
            name: "mismatch tty",
            session: TerminalHint(tty: "/dev/ttys003"),
            front: FrontTabHint(tty: "/dev/ttys009"),
            expected: .mismatch
        ),
MatrixCase(
            name: "unknown no front",
            session: TerminalHint(itermSession: "w0t0p0:abc"),
            front: nil,
            expected: .unknown
        ),
MatrixCase(
            name: "unknown bundle only",
            session: TerminalHint(bundleID: "com.googlecode.iterm2"),
            front: FrontTabHint(bundleID: "com.googlecode.iterm2"),
            expected: .unknown
        ),
MatrixCase(
            name: "unknown missing session",
            session: nil,
            front: FrontTabHint(bundleID: "com.apple.Terminal"),
            expected: .unknown
        ),
MatrixCase(
            name: "iterm session beats tty mismatch",
            session: TerminalHint(itermSession: "w0t0p0:AAA", tty: "/dev/ttys001"),
            front: FrontTabHint(itermSession: "w0t0p0:BBB", tty: "/dev/ttys001"),
            expected: .mismatch
        ),
    ]

    @Test(arguments: matrix)
    func compareMatrix(_ row: MatrixCase) {
        #expect(
            TabVisibility.compare(session: row.session, front: row.front) == row.expected,
            Comment(rawValue: row.name)
        )
    }
}
