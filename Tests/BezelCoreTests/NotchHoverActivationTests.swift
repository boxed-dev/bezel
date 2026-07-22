import Testing
import BezelCore

@Suite("NotchHoverActivation")
struct NotchHoverActivationTests {
    /// Apple-style cutout: centered, ~200×32 in screen coords (origin bottom-left).
    private let physicalNotch = NotchBounds(minX: 400, minY: 900, width: 200, height: 32)

    @Test func cursorInsidePhysicalNotch_activates() {
        #expect(
            NotchHoverActivation.shouldExpandOnHover(x: 500, y: 916, notchBounds: physicalNotch)
        )
    }

    @Test func cursorInCompactLeadingWing_doesNotActivate() {
        // Leading status dot sits left of the camera cutout.
        #expect(
            !NotchHoverActivation.shouldExpandOnHover(x: 360, y: 916, notchBounds: physicalNotch)
        )
    }

    @Test func cursorInCompactTrailingWing_doesNotActivate() {
        // Trailing usage % sits right of the camera cutout.
        #expect(
            !NotchHoverActivation.shouldExpandOnHover(x: 640, y: 916, notchBounds: physicalNotch)
        )
    }

    @Test func cursorInWideTopStripOutsideNotch_doesNotActivate() {
        // Far along the menu bar — must not behave like a full-width hover strip.
        #expect(
            !NotchHoverActivation.shouldExpandOnHover(x: 80, y: 916, notchBounds: physicalNotch)
        )
        #expect(
            !NotchHoverActivation.shouldExpandOnHover(x: 1200, y: 916, notchBounds: physicalNotch)
        )
    }

    @Test func cursorBelowNotch_doesNotActivate() {
        #expect(
            !NotchHoverActivation.shouldExpandOnHover(x: 500, y: 860, notchBounds: physicalNotch)
        )
    }

    @Test func emptyBounds_neverActivates() {
        let empty = NotchBounds(minX: 0, minY: 0, width: 0, height: 0)
        #expect(
            !NotchHoverActivation.shouldExpandOnHover(x: 500, y: 916, notchBounds: empty)
        )
    }
}
