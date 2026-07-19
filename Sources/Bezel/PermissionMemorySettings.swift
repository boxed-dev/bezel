import Foundation

enum PermissionMemorySettings {
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "bezel.permissionMemory.enabled") as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: "bezel.permissionMemory.enabled") }
    }
}
