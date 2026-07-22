import Foundation

/// Axis-aligned bounds in a shared coordinate space (AppKit: bottom-left origin).
public struct NotchBounds: Equatable, Sendable {
    public var minX: Double
    public var minY: Double
    public var width: Double
    public var height: Double

    public init(minX: Double, minY: Double, width: Double, height: Double) {
        self.minX = minX
        self.minY = minY
        self.width = width
        self.height = height
    }

    public var maxX: Double { minX + width }
    public var maxY: Double { minY + height }

    public func contains(x: Double, y: Double) -> Bool {
        guard width > 0, height > 0 else { return false }
        return x >= minX && x < maxX && y >= minY && y < maxY
    }
}

/// Pure geometry for compact hover → expand.
///
/// Activation is the physical camera-notch cutout only — not the compact
/// leading/trailing wings DynamicNotchKit includes in its `onHover` region,
/// and not a wide invisible strip across the top of the screen.
public enum NotchHoverActivation {
    /// - Parameters:
    ///   - x: Cursor X in the same space as `notchBounds`.
    ///   - y: Cursor Y in the same space as `notchBounds`.
    ///   - notchBounds: Physical notch frame (screen auxiliary areas / kit `notchFrame`).
    public static func shouldExpandOnHover(x: Double, y: Double, notchBounds: NotchBounds) -> Bool {
        notchBounds.contains(x: x, y: y)
    }
}
