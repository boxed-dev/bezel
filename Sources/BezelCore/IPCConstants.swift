import Foundation

public enum IPCConstants {
    /// Max inbound JSON bytes (large diffs).
    public static let maxPayloadBytes = 10_485_760
    /// Connect timeout for fire-and-forget events / liveness probe.
    public static let eventTimeoutSeconds: TimeInterval = 1
    /// Connect timeout for blocking events.
    public static let blockingConnectTimeoutSeconds: TimeInterval = 3
    /// Bezel-side recv timeout for permission/question waits (reaps work-queue threads).
    /// Claude's PermissionRequest hook timeout stays 86400 so Claude does not kill first.
    public static let blockingRecvTimeoutSeconds: TimeInterval = 600
    /// Max time to read inbound payload after accept (half-close expected sooner).
    public static let inboundReadTimeoutSeconds: TimeInterval = 5
}
