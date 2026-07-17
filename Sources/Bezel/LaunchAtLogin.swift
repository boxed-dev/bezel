import Foundation
import ServiceManagement

/// Launch-at-login via `SMAppService.mainApp` (macOS 13+ Login Item / BTM).
///
/// Prefer installing Bezel as a proper `.app` under `/Applications` (bundle id
/// `app.bezel.macos` in Info.plist). Background Task Management registration is
/// most reliable from that layout; an unpackaged `swift run` binary may report
/// `.notFound` or throw until packaging lands — this type still compiles and calls
/// `SMAppService` either way.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status == .enabled { return }
            try service.register()
        } else {
            if service.status == .notRegistered { return }
            try service.unregister()
        }
    }
}
