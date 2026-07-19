import Testing
import Foundation
import BezelCore

@Suite("BezelInstallState")
struct BezelInstallStateTests {
    @Test func tempHomeMarkerSurvivesArtifactRemoval() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(atPath: home) }

        #expect(BezelInstallState.ensureBezelHome(home: home))
        let root = BezelInstallState.bezelHome(home: home)
        let bridge = root.appendingPathComponent(BezelInstallState.bridgeFileName)
        try "fake".write(to: bridge, atomically: true, encoding: .utf8)

        #expect(BezelInstallState.markUserUninstalled(home: home))
        #expect(BezelInstallState.isUserUninstalled(home: home))

        #expect(BezelInstallState.removeManagedArtifacts(home: home))
        #expect(!FileManager.default.fileExists(atPath: bridge.path))
        #expect(BezelInstallState.isUserUninstalled(home: home))
    }

    @Test func clearUserUninstalledRemovesMarker() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(atPath: home) }

        #expect(BezelInstallState.markUserUninstalled(home: home))
        BezelInstallState.clearUserUninstalled(home: home)
        #expect(!BezelInstallState.isUserUninstalled(home: home))
    }

    @Test func ensureBezelHomeIsOwnerOnly() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(atPath: home) }

        #expect(BezelInstallState.ensureBezelHome(home: home))
        let path = BezelInstallState.bezelHome(home: home).path
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        let perms = attrs[.posixPermissions] as? NSNumber
        #expect(perms?.intValue == 0o700)

        // Re-assert even if someone loosened the directory.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        #expect(BezelInstallState.ensureBezelHome(home: home))
        let again = try FileManager.default.attributesOfItem(atPath: path)
        #expect((again[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    @Test func managedExecutablePermissionsNotWorldWritable() {
        let mode = BezelInstallState.managedExecutablePermissions
        #expect((mode & 0o002) == 0)
        #expect((mode & 0o020) == 0)
    }

    @Test func homeDirectoryRespectsHOMEEnv() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(atPath: home) }

        // BezelInstallState.homeDirectory() reads ProcessInfo environment — when
        // tests pass an explicit `home:` they must not depend on process HOME.
        let root = BezelInstallState.bezelHome(home: home)
        #expect(root.path.hasPrefix(home))
        #expect(root.lastPathComponent == ".bezel")
    }

    private func makeTempHome() throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bezel-install-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }
}
