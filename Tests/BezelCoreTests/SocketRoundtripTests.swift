import Testing
import Foundation
import BezelCore
import Darwin

/// Minimal server using production `UnixSocket` helpers (not a HookServer fork).
final class TestSocketServer: @unchecked Sendable {
    private let path: String
    private var listenFD: Int32 = -1
    private let acceptQueue = DispatchQueue(label: "bezel.test.socket.accept")
    private let workQueue = DispatchQueue(label: "bezel.test.socket.work", attributes: .concurrent)
    private var source: DispatchSourceRead?
    var onPermission: (() -> Data)?

    init(path: String) {
        self.path = path
    }

    func start() throws {
        guard let fd = UnixSocket.bindListen(path: path, backlog: 8) else {
            throw POSIXError(.EADDRINUSE)
        }
        listenFD = fd
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
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
        guard listenFD >= 0, let client = UnixSocket.acceptClient(listenFD: listenFD) else { return }
        workQueue.async { self.handle(client) }
    }

    private func handle(_ client: Int32) {
        defer { close(client) }
        let data = UnixSocket.readAll(
            fd: client,
            limit: IPCConstants.maxPayloadBytes,
            timeoutSeconds: IPCConstants.inboundReadTimeoutSeconds
        )
        guard !data.isEmpty else {
            UnixSocket.writeAll(fd: client, DecisionJSON.emptyAck())
            return
        }
        guard let payload = try? HookPayload.parse(data) else {
            UnixSocket.writeAll(fd: client, DecisionJSON.parseFailed())
            return
        }
        if payload.routeKind == .event {
            UnixSocket.writeAll(fd: client, DecisionJSON.emptyAck())
        } else {
            UnixSocket.writeAll(fd: client, onPermission?() ?? DecisionJSON.permissionAllow())
        }
    }
}

enum TestBridgeClient {
    static func send(_ data: Data, path: String) -> Data? {
        guard let fd = UnixSocket.connect(path: path, timeoutSeconds: 2) else { return nil }
        defer { close(fd) }
        UnixSocket.writeAll(fd: fd, data)
        shutdown(fd, SHUT_WR)
        let response = UnixSocket.readAll(fd: fd, limit: 65_536, timeoutSeconds: 2)
        return response.isEmpty ? nil : response
    }
}

@Suite("Socket roundtrip")
struct SocketRoundtripTests {
    private func tempSocketPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("bezel-test-\(UUID().uuidString).sock")
            .path
    }

    @Test func sessionStartGetsEmptyAck() throws {
        let path = tempSocketPath()
        let server = TestSocketServer(path: path)
        try server.start()
        defer { server.stop() }
        // Brief settle for DispatchSource
        Thread.sleep(forTimeInterval: 0.05)

        let payload = Data(#"{"hook_event_name":"SessionStart","session_id":"s1"}"#.utf8)
        let response = TestBridgeClient.send(payload, path: path)
        #expect(response != nil)
        #expect(JSONCanonical.equal(response!, DecisionJSON.emptyAck()))
    }

    @Test func permissionAllowRoundtrip() throws {
        let path = tempSocketPath()
        let server = TestSocketServer(path: path)
        server.onPermission = { DecisionJSON.permissionAllow() }
        try server.start()
        defer { server.stop() }
        Thread.sleep(forTimeInterval: 0.05)

        let payload = Data(
            #"{"hook_event_name":"PermissionRequest","session_id":"s1","tool_name":"Bash"}"#.utf8
        )
        let response = TestBridgeClient.send(payload, path: path)
        #expect(response != nil)
        #expect(JSONCanonical.equal(response!, DecisionJSON.permissionAllow()))
    }

    @Test func emptyPingGetsEmptyAck() throws {
        let path = tempSocketPath()
        let server = TestSocketServer(path: path)
        try server.start()
        defer { server.stop() }
        Thread.sleep(forTimeInterval: 0.05)

        #expect(SocketLiveness.probe(path: path, timeoutSeconds: 1))
    }

    @Test func unixSocketBindListenRoundtrip() throws {
        let path = tempSocketPath()
        guard let listen = UnixSocket.bindListen(path: path, backlog: 2) else {
            Issue.record("bindListen failed")
            return
        }
        defer {
            close(listen)
            try? FileManager.default.removeItem(atPath: path)
        }

        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            if let client = UnixSocket.acceptClient(listenFD: listen) {
                let data = UnixSocket.readAll(fd: client, limit: 1024, timeoutSeconds: 1)
                UnixSocket.writeAll(fd: client, data)
                close(client)
            }
            group.leave()
        }

        guard let fd = UnixSocket.connect(path: path, timeoutSeconds: 1) else {
            Issue.record("connect failed")
            return
        }
        let msg = Data("ping".utf8)
        UnixSocket.writeAll(fd: fd, msg)
        shutdown(fd, SHUT_WR)
        let echo = UnixSocket.readAll(fd: fd, limit: 1024, timeoutSeconds: 1)
        close(fd)
        _ = group.wait(timeout: .now() + 2)
        #expect(echo == msg)
    }
}
