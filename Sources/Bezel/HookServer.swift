import Foundation
import BezelCore
import Darwin

/// Unix-domain socket server. Must start before ConfigInstaller writes hooks.
final class HookServer: @unchecked Sendable {
    private let store: SessionStore
    private let queue = DispatchQueue(label: "app.bezel.hookserver")
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    init(store: SessionStore) {
        self.store = store
    }

    func start() {
        let path: String
        do {
            path = try SocketPath.ensureParentDirectory()
        } catch {
            NSLog("Bezel: failed to create socket directory: \(error)")
            return
        }

        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            NSLog("Bezel: socket() failed")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                for (i, b) in pathBytes.enumerated() { dest[i] = b }
            }
        }

        let oldMask = umask(0o077)
        let bindOK: Int32 = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        umask(oldMask)

        guard bindOK == 0 else {
            NSLog("Bezel: bind(\(path)) failed errno=\(errno)")
            close(fd)
            return
        }

        chmod(path, 0o700)
        guard listen(fd, 32) == 0 else {
            NSLog("Bezel: listen failed")
            close(fd)
            return
        }

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptOne()
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        acceptSource = source
        NSLog("Bezel: HookServer listening on \(path)")
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        listenFD = -1
        try? FileManager.default.removeItem(atPath: SocketPath.resolve())
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
        queue.async { [weak self] in
            self?.handle(clientFD: client)
        }
    }

    private func handle(clientFD: Int32) {
        defer { close(clientFD) }

        var data = Data()
        var buf = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = Darwin.read(clientFD, &buf, buf.count)
            if n == 0 { break }
            if n < 0 {
                if errno == EINTR { continue }
                break
            }
            data.append(contentsOf: buf[0..<n])
            if data.count > IPCConstants.maxPayloadBytes {
                writeAll(clientFD, DecisionJSON.permissionDeny(message: "Payload too large"))
                return
            }
        }

        guard !data.isEmpty else {
            writeAll(clientFD, DecisionJSON.emptyAck())
            return
        }

        let payload: HookPayload
        do {
            payload = try HookPayload.parse(data)
        } catch {
            writeAll(clientFD, DecisionJSON.parseFailed())
            return
        }

        let kind = payload.routeKind

        if kind == .event {
            DispatchQueue.main.async { [store] in
                store.apply(envelope: payload)
            }
            writeAll(clientFD, DecisionJSON.emptyAck())
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        let box = ResponseBox(DecisionJSON.permissionDeny(message: "Timed out"))

        DispatchQueue.main.async { [store] in
            store.apply(envelope: payload)
            let sid = SessionID(payload.sessionID ?? "unknown")
            if kind == .permission {
                store.enqueuePermission(
                    PendingPermission(
                        sessionID: sid,
                        toolName: payload.toolName,
                        summary: payload.toolName.map { "Allow \($0)?" } ?? "Permission request",
                        resume: { data in
                            box.value = data
                            semaphore.signal()
                        }
                    )
                )
            } else {
                store.enqueueQuestion(
                    PendingQuestion(
                        sessionID: sid,
                        prompt: payload.question ?? "Agent question",
                        resume: { data in
                            box.value = data
                            semaphore.signal()
                        }
                    )
                )
            }
        }

        _ = semaphore.wait(timeout: .now() + IPCConstants.blockingRecvTimeoutSeconds)
        writeAll(clientFD, box.value)
    }

    private func writeAll(_ fd: Int32, _ data: Data) {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var written = 0
            let total = data.count
            while written < total {
                let n = Darwin.write(fd, base.advanced(by: written), total - written)
                if n <= 0 { break }
                written += n
            }
        }
    }
}

private final class ResponseBox: @unchecked Sendable {
    var value: Data
    init(_ value: Data) { self.value = value }
}
