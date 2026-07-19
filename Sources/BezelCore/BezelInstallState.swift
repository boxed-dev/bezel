import Foundation

/// Durable install / uninstall markers under `~/.bezel`.
/// Explicit uninstall must never be undone by `syncInstalledBridgeIfNeeded`.
public enum BezelInstallState {
    public static let directoryName = ".bezel"
    public static let userUninstalledMarkerName = "user-uninstalled"
    public static let bridgeFileName = "bezel-bridge"
    public static let hookFileName = "bezel-hook.sh"
    public static let bridgeVersionFileName = "bridge-version"

    public static func homeDirectory() -> String {
        ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    }

    public static func bezelHome(home: String? = nil) -> URL {
        URL(fileURLWithPath: home ?? homeDirectory(), isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    public static func markerURL(home: String? = nil) -> URL {
        bezelHome(home: home).appendingPathComponent(userUninstalledMarkerName)
    }

    public static func isUserUninstalled(home: String? = nil) -> Bool {
        FileManager.default.fileExists(atPath: markerURL(home: home).path)
    }

    /// Create `~/.bezel` at 0700 (re-assert even if the directory already exists).
    @discardableResult
    public static func ensureBezelHome(home: String? = nil) -> Bool {
        let dir = bezelHome(home: home)
        let fm = FileManager.default
        do {
            try fm.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    public static func markUserUninstalled(home: String? = nil) -> Bool {
        guard ensureBezelHome(home: home) else { return false }
        let url = markerURL(home: home)
        do {
            try Data().write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
            return true
        } catch {
            return false
        }
    }

    public static func clearUserUninstalled(home: String? = nil) {
        try? FileManager.default.removeItem(at: markerURL(home: home))
    }

    /// Delete managed bridge/hook/version files (leaves uninstall marker and other user files).
    @discardableResult
    public static func removeManagedArtifacts(home: String? = nil) -> Bool {
        let root = bezelHome(home: home)
        let fm = FileManager.default
        var ok = true
        for name in [bridgeFileName, hookFileName, bridgeVersionFileName] {
            let url = root.appendingPathComponent(name)
            guard fm.fileExists(atPath: url.path) else { continue }
            do {
                try fm.removeItem(at: url)
            } catch {
                ok = false
            }
        }
        return ok
    }

    /// Restrictive mode for installed executables/scripts: owner rwx, not world-writable.
    public static let managedExecutablePermissions: Int = 0o755
}
