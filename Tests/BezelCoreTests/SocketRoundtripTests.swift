import Testing
import Foundation
import BezelCore
import Darwin

typealias TestHookServer = TestSocketServer

final class TestSocketServer: @unchecked Sendable {
    private let path: String
    private var listenFD: Int32 = -1
    private let queue = DispatchQueue(label: "bezel.test.socket")
    private var source: DispatchSourceRead?
    var onPermission: (() -> Data)?

    init(path: String) {
        self.path = path
    }

    func start() throws {
        try? FileManager.default.removeItem(atPath: path)
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = path.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: bytes.count) { dest in
                for (i, b) in bytes.enumerated() { dest[i] = b }
            }
        }

        let bindOK: Int32 = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindOK == 0, listen(fd, 8) == 0 else {
            close(fd)
            throw POSIXError(.EADDRINUSE)
        }
        listenFD = fd
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptOne() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
        listenFD = -1
        try? FileManager.default.removeItem(atPath: path)
    }

    private func acceptOne() {
        let fd = listenFD
        guard fd >= 0 else { return }
        var addr = sockaddr_un()
        var len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let client = withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                accept(fd, $0, &len)
            }
        }
        guard client >= 0 else { return }
        queue.async { self.handle(client) }
    }

    private func handle(_ client: Int32) {
        defer { close(client) }
        var data = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = Darwin.read(client, &buf, buf.count)
            if n <= 0 { break }
            data.append(contentsOf: buf[0..<n])
        }
        guard let payload = try? HookPayload.parse(data) else {
            writeAll(client, DecisionJSON.parseFailed())
            return
        }
        if payload.routeKind == .event {
            writeAll(client, DecisionJSON.emptyAck())
        } else {
            writeAll(client, onPermission?() ?? DecisionJSON.permissionAllow())
        }
    }

    private func writeAll(_ fd: Int32, _ data: Data) {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            _ = Darwin.write(fd, base, data.count)
        }
    }
}

enum TestBridgeClient {
    static func send(_ data: Data, path: String) -> Data? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = path.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: bytes.count) { dest in
                for (i, b) in bytes.enumerated() { dest[i] = b }
            }
        }

        let ok: Int32 = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard ok == 0 else { return nil }

        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            _ = Darwin.write(fd, base, data.count)
        }
        shutdown(fd, SHUT_WR)

        var response = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = Darwin.read(fd, &buf, buf.count)
            if n <= 0 { break }
            response.append(contentsOf: buf[0..<n])
        }
        return response
    }
}

@Suite("Socket roundtrip")
struct SocketRoundtripTests {
    private func tempSocketPath() -> String {
        "/tmp/bezel-test-\(UUID().uuidString).sock"
    }

    @Test func eventGetsEmptyAck() throws {
        let path = tempSocketPath()
        setenv("BEZEL_SOCKET_PATH", path, 1)
        defer { unsetenv("BEZEL_SOCKET_PATH") }

        let server = TestHookServer(path: path)
        try server.start()
        defer { server.stop() }
        Thread.sleep(forTimeInterval: 0.05)

        let payload = Data(#"{"hook_event_name":"SessionStart","session_id":"e2e"}"#.utf8)
        let response = try #require(TestBridgeClient.send(payload, path: path))
        #expect(JSONCanonical.equal(response, DecisionJSON.emptyAck()))
    }

    @Test func permissionWaitsThenAllow() throws {
        let path = tempSocketPath()
        setenv("BEZEL_SOCKET_PATH", path, 1)
        defer { unsetenv("BEZEL_SOCKET_PATH") }

        let gate = DispatchSemaphore(value: 0)
        let server = TestHookServer(path: path)
        server.onPermission = {
            _ = gate.wait(timeout: .now() + 2)
            return DecisionJSON.permissionAllow()
        }
        try server.start()
        defer { server.stop() }
        Thread.sleep(forTimeInterval: 0.05)

        let payload = Data(#"{"hook_event_name":"PermissionRequest","session_id":"e2e","tool_name":"Bash"}"#.utf8)
        let group = DispatchGroup()
        var response: Data?
        group.enter()
        DispatchQueue.global().async {
            response = TestBridgeClient.send(payload, path: path)
            group.leave()
        }

        Thread.sleep(forTimeInterval: 0.1)
        gate.signal()
        #expect(group.wait(timeout: .now() + 2) == .success)
        let body = try #require(response)
        #expect(JSONCanonical.equal(body, DecisionJSON.permissionAllow()))
    }
}
