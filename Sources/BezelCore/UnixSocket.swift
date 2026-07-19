import Foundation
import Darwin

/// Shared sockaddr_un / bind / accept / read / write helpers for UDS.
public enum UnixSocket {
    public static func makeAddress(path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                for (i, b) in pathBytes.enumerated() { dest[i] = b }
            }
        }
        return addr
    }

    /// Bind + listen on a Unix path. Removes existing file at path. Sets umask-restricted perms.
    public static func bindListen(
        path: String,
        backlog: Int32 = 32,
        fileMode: mode_t = 0o700
    ) -> Int32? {
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        guard var addr = makeAddress(path: path) else {
            close(fd)
            return nil
        }
        let oldMask = umask(0o077)
        let bindOK: Int32 = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        umask(oldMask)
        guard bindOK == 0 else {
            close(fd)
            return nil
        }
        chmod(path, fileMode)
        guard listen(fd, backlog) == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    public static func acceptClient(listenFD: Int32) -> Int32? {
        var addr = sockaddr_un()
        var len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let client = withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                accept(listenFD, $0, &len)
            }
        }
        return client >= 0 ? client : nil
    }

    /// Read until EOF or deadline. Returns partial data on timeout.
    public static func readAll(
        fd: Int32,
        limit: Int = IPCConstants.maxPayloadBytes,
        timeoutSeconds: TimeInterval = IPCConstants.inboundReadTimeoutSeconds
    ) -> Data {
        let usec = Int32((timeoutSeconds.truncatingRemainder(dividingBy: 1)) * 1_000_000)
        var tv = timeval(
            tv_sec: Int(timeoutSeconds),
            tv_usec: usec
        )
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var data = Data()
        var buf = [UInt8](repeating: 0, count: 65_536)
        while data.count < limit {
            let n = Darwin.read(fd, &buf, buf.count)
            if n == 0 { break }
            if n < 0 {
                if errno == EINTR { continue }
                // EAGAIN / EWOULDBLOCK: SO_RCVTIMEO
                break
            }
            data.append(contentsOf: buf[0..<n])
            if data.count > limit { break }
        }
        return data
    }

    public static func writeAll(fd: Int32, _ data: Data) {
        // Client often half-closes and exits without reading our ack (fire-and-forget events).
        // Without this, write() raises SIGPIPE and terminates the whole Bezel process.
        var nosig: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosig, socklen_t(MemoryLayout<Int32>.size))

        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var written = 0
            let total = data.count
            while written < total {
                let n = Darwin.write(fd, base.advanced(by: written), total - written)
                if n <= 0 { break } // EPIPE / ECONNRESET — client gone; safe to stop
                written += n
            }
        }
    }

    /// Non-blocking connect with poll(POLLOUT) + SO_ERROR check.
    /// Returns a blocking connected fd, or nil on timeout / refused / other failure.
    public static func connect(path: String, timeoutSeconds: TimeInterval) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        guard var addr = makeAddress(path: path) else {
            close(fd)
            return nil
        }

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        let conn: Int32 = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if conn == 0 {
            // Connected immediately (common for local UDS).
            _ = fcntl(fd, F_SETFL, flags)
            return fd
        }
        if errno != EINPROGRESS {
            close(fd)
            return nil
        }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let ready = poll(&pfd, 1, Int32(timeoutSeconds * 1000))
        guard ready > 0, (Int32(pfd.revents) & Int32(POLLOUT)) != 0 else {
            close(fd)
            return nil
        }

        // Async connect completion: POLLOUT alone is not success — check SO_ERROR.
        var soError: Int32 = 0
        var len = socklen_t(MemoryLayout.size(ofValue: soError))
        guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &len) == 0, soError == 0 else {
            close(fd)
            return nil
        }

        _ = fcntl(fd, F_SETFL, flags)
        return fd
    }
}

/// Process-wide single-instance lock next to the Bezel socket.
public enum SingleInstanceLock {
    public static let lockFileName = "bezel.lock"

    public static func lockPath() -> String {
        let sock = SocketPath.resolve()
        let dir = (sock as NSString).deletingLastPathComponent
        return (dir as NSString).appendingPathComponent(lockFileName)
    }

    /// Non-blocking exclusive flock. Returns open fd on success (keep open for process lifetime).
    /// Returns nil if another instance holds the lock.
    public static func tryAcquire() -> Int32? {
        let path = lockPath()
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let fd = open(path, O_RDWR | O_CREAT, 0o600)
        guard fd >= 0 else { return nil }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return nil
        }
        return fd
    }
}
