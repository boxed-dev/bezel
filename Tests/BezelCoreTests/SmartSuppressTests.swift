import Testing
import BezelCore

@Suite("SmartSuppress")
struct SmartSuppressTests {
    @Test func needsAttentionAlwaysExpands() {
        let hint = TerminalHint(termProgram: "iTerm.app", bundleID: "com.googlecode.iterm2")
        #expect(SmartSuppress.shouldAutoExpand(
            needsAttention: true,
            frontmostBundleID: "com.googlecode.iterm2",
            sessionTerminal: hint
        ))
    }

    @Test func suppressWhenSameTerminalBundle() {
        let hint = TerminalHint(termProgram: "iTerm.app", bundleID: "com.googlecode.iterm2")
        #expect(!SmartSuppress.shouldAutoExpand(
            needsAttention: false,
            frontmostBundleID: "com.googlecode.iterm2",
            sessionTerminal: hint
        ))
    }

    @Test func expandWhenDifferentTerminal() {
        let hint = TerminalHint(termProgram: "iTerm.app", bundleID: "com.googlecode.iterm2")
        #expect(SmartSuppress.shouldAutoExpand(
            needsAttention: false,
            frontmostBundleID: "com.apple.Terminal",
            sessionTerminal: hint
        ))
    }

    @Test func expandWhenNoFrontmost() {
        let hint = TerminalHint(termProgram: "ghostty", bundleID: "com.mitchellh.ghostty")
        #expect(SmartSuppress.shouldAutoExpand(
            needsAttention: false,
            frontmostBundleID: nil,
            sessionTerminal: hint
        ))
    }

    @Test func ghosttyProgramMatchSuppresses() {
        let hint = TerminalHint(termProgram: "ghostty")
        #expect(!SmartSuppress.shouldAutoExpand(
            needsAttention: false,
            frontmostBundleID: "com.mitchellh.ghostty",
            sessionTerminal: hint
        ))
    }

    @Test func blockingOverridesBundleMatch() {
        let hint = TerminalHint(termProgram: "Apple_Terminal", tty: "/dev/ttys001")
        #expect(SmartSuppress.shouldAutoExpand(
            needsAttention: true,
            frontmostBundleID: "com.apple.Terminal",
            sessionTerminal: hint
        ))
    }

    @Test func tabMatchSuppressesNonBlocking() {
        let session = TerminalHint(itermSession: "w0t0p0:ABC123")
        let front = FrontTabHint(
            bundleID: "com.googlecode.iterm2",
            itermSession: "w0t0p0:ABC123"
        )
        #expect(!SmartSuppress.shouldAutoExpand(
            needsAttention: false,
            front: front,
            sessionTerminal: session
        ))
    }

    @Test func tabMismatchDoesNotSuppress() {
        let session = TerminalHint(itermSession: "w0t0p0:ABC123")
        let front = FrontTabHint(
            bundleID: "com.googlecode.iterm2",
            itermSession: "w0t0p0:OTHER"
        )
        #expect(SmartSuppress.shouldAutoExpand(
            needsAttention: false,
            front: front,
            sessionTerminal: session
        ))
    }

    @Test func blockingOverridesTabMatch() {
        let session = TerminalHint(tty: "/dev/ttys003")
        let front = FrontTabHint(bundleID: "com.apple.Terminal", tty: "/dev/ttys003")
        #expect(SmartSuppress.shouldAutoExpand(
            needsAttention: true,
            front: front,
            sessionTerminal: session
        ))
    }
}
