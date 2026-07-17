import Foundation
import BezelCore
import Darwin

// bezel-bridge — invoked by agent hooks.
// stdin: hook JSON → Unix socket → stdout: decision JSON (blocking only)

@main
enum BezelBridgeMain {
    static func main() {
        if ProcessInfo.processInfo.environment["BEZEL_SKIP"] != nil {
            exit(0)
        }

        let args = CommandLine.arguments
        var sourceOverride: String?
        var eventOverride: String?
        var i = 1
        while i < args.count {
            if args[i] == "--source", i + 1 < args.count {
                sourceOverride = args[i + 1]
                i += 2
                continue
            }
            if args[i] == "--event", i + 1 < args.count {
                eventOverride = args[i + 1]
                i += 2
                continue
            }
            i += 1
        }

        let stdinData = FileHandle.standardInput.readDataToEndOfFile()
        guard !stdinData.isEmpty || eventOverride != nil else {
            FileHandle.standardOutput.write(DecisionJSON.emptyAck())
            exit(0)
        }

        var payloadData = stdinData
        if payloadData.isEmpty, let eventOverride {
            payloadData = Data(#"{"hook_event_name":"\#(eventOverride)"}"#.utf8)
        }

        // Enrich JSON with terminal metadata + source.
        guard var obj = (try? JSONSerialization.jsonObject(with: payloadData)) as? [String: Any] else {
            FileHandle.standardOutput.write(DecisionJSON.parseFailed())
            exit(0)
        }

        if let eventOverride {
            obj["hook_event_name"] = EventNormalizer.pascalCase(eventOverride)
        } else if let existing = obj["hook_event_name"] as? String {
            obj["hook_event_name"] = EventNormalizer.pascalCase(existing)
        } else if let existing = obj["hookEventName"] as? String {
            obj["hook_event_name"] = EventNormalizer.pascalCase(existing)
        }

        let env = ProcessInfo.processInfo.environment
        if let sourceOverride {
            obj["_source"] = sourceOverride
        } else if obj["_source"] == nil {
            obj["_source"] = "claude"
        }

        obj["_ppid"] = Int(getppid())
        if obj["cwd"] == nil {
            obj["cwd"] = FileManager.default.currentDirectoryPath
        }

        // Capture live TTY + env hints for Jump (_iterm_session, _tty, TMUX_*, TERM_PROGRAM→_term_app, kitty, warp).
        var tty: String?
        var ttyBuf = [CChar](repeating: 0, count: 1024)
        if ttyname_r(STDIN_FILENO, &ttyBuf, ttyBuf.count) == 0 {
            tty = String(decoding: ttyBuf.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
        TerminalHintExtractor.merge(into: &obj, env: env, tty: tty)

        guard let enriched = try? JSONSerialization.data(withJSONObject: obj, options: []) else {
            FileHandle.standardOutput.write(DecisionJSON.parseFailed())
            exit(0)
        }

        let payload: HookPayload
        do {
            payload = try HookPayload.parse(enriched)
        } catch {
            FileHandle.standardOutput.write(DecisionJSON.parseFailed())
            exit(0)
        }

        let blocking = PermissionRouting.isBlocking(payload.routeKind)
        let response = UnixClient.send(
            enriched,
            blocking: blocking
        )

        if blocking {
            FileHandle.standardOutput.write(
                response ?? DecisionJSON.deny(
                    for: payload.routeKind,
                    hookEventName: payload.hookEventName,
                    message: "Bezel unavailable"
                )
            )
        }
        // Non-blocking: no stdout required
        exit(0)
    }
}

enum UnixClient {
    static func send(_ data: Data, blocking: Bool) -> Data? {
        let path: String
        do {
            path = try SocketPath.ensureParentDirectory()
        } catch {
            return nil
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                for (i, b) in pathBytes.enumerated() { dest[i] = b }
            }
        }

        let connectTimeout = blocking
            ? IPCConstants.blockingConnectTimeoutSeconds
            : IPCConstants.eventTimeoutSeconds

        // Non-blocking connect + poll
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        let conn: Int32 = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        if conn < 0 && errno != EINPROGRESS {
            return nil
        }

        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        let ready = poll(&pfd, 1, Int32(connectTimeout * 1000))
        guard ready > 0 else { return nil }

        _ = fcntl(fd, F_SETFL, flags) // back to blocking for IO

        var written = 0
        let bytes = [UInt8](data)
        while written < bytes.count {
            let n = bytes.withUnsafeBufferPointer { buf in
                Darwin.write(fd, buf.baseAddress!.advanced(by: written), bytes.count - written)
            }
            if n <= 0 { return nil }
            written += n
        }

        // Half-close write so server sees EOF
        shutdown(fd, SHUT_WR)

        if !blocking {
            // Fire-and-forget: do not wait for ack (avoids 1s tax on every PostToolUse).
            return nil
        }

        // Blocking recv until EOF — SO_RCVTIMEO enforces a real kernel timeout.
        var timeout = timeval(
            tv_sec: Int(IPCConstants.blockingRecvTimeoutSeconds),
            tv_usec: 0
        )
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var response = Data()
        var buf = [UInt8](repeating: 0, count: 65_536)
        while true {
            let n = Darwin.read(fd, &buf, buf.count)
            if n == 0 { break }
            if n < 0 {
                if errno == EINTR { continue }
                // EAGAIN / EWOULDBLOCK: SO_RCVTIMEO fired
                break
            }
            response.append(contentsOf: buf[0..<n])
            if response.count > IPCConstants.maxPayloadBytes { break }
        }
        return response.isEmpty ? nil : response
    }
}
