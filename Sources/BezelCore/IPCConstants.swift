import Foundation

public enum IPCConstants {
    /// Max inbound JSON bytes (large Codex diffs).
    public static let maxPayloadBytes = 10_485_760
    /// Connect/send/recv for fire-and-forget events.
    public static let eventTimeoutSeconds: TimeInterval = 1
    /// Connect timeout for blocking events.
    public static let blockingConnectTimeoutSeconds: TimeInterval = 3
    /// Recv timeout for permission/question (Claude settings timeout is 86400).
    public static let blockingRecvTimeoutSeconds: TimeInterval = 86_400
}
