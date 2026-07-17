import Foundation

public enum SocketPath {
    public static let appSupportDirectoryName = "Bezel"
    public static let socketFileName = "bezel.sock"
    public static let envOverrideKey = "BEZEL_SOCKET_PATH"

    /// Resolved Unix socket path. Override with `BEZEL_SOCKET_PATH`.
    public static func resolve() -> String {
        if let override = ProcessInfo.processInfo.environment[envOverrideKey], !override.isEmpty {
            return override
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent(appSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(socketFileName)
            .path
    }

    /// Ensures the parent directory exists with restrictive permissions.
    @discardableResult
    public static func ensureParentDirectory() throws -> String {
        let path = resolve()
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return path
    }
}
