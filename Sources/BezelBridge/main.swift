import Foundation
import BezelCore
import Darwin

// bezel-bridge — invoked by agent hooks.
// stdin: hook JSON → Unix socket → stdout: decision JSON (blocking only)

@main
enum BezelBridgeMain {
    static func main() {
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

        let env = ProcessInfo.processInfo.environment
        HookEventEnrichment.applySourceAndEvent(
            to: &obj,
            sourceOverride: sourceOverride,
            eventOverride: eventOverride
        )

        // Refresh on every hook event (SessionStart + PostToolUse + …) so Jump
        // never relies on a once-and-stale ITERM_SESSION_ID / tty / PPID.
        let agentPID = Int(getppid())
        if obj["cwd"] == nil {
            obj["cwd"] = FileManager.default.currentDirectoryPath
        }

        // Controlling TTY via /dev/tty (stdin is a pipe under hooks). Env fallback inside merge.
        TerminalHintExtractor.merge(
            into: &obj,
            env: env,
            tty: TerminalHintExtractor.resolveControllingTTY(),
            agentPID: agentPID
        )

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

        // BEZEL_SKIP: fail closed on blocking routes (kind-correct deny), not silent allow.
        if env["BEZEL_SKIP"] != nil {
            if blocking {
                FileHandle.standardOutput.write(
                    DecisionJSON.deny(
                        for: payload.routeKind,
                        hookEventName: payload.hookEventName,
                        message: "Bezel skipped (BEZEL_SKIP)"
                    )
                )
            }
            exit(0)
        }

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
    /// Fire-and-forget or blocking send over the Bezel UDS using shared `UnixSocket.connect`.
    static func send(_ data: Data, blocking: Bool) -> Data? {
        let path: String
        do {
            path = try SocketPath.ensureParentDirectory()
        } catch {
            return nil
        }

        let connectTimeout = blocking
            ? IPCConstants.blockingConnectTimeoutSeconds
            : IPCConstants.eventTimeoutSeconds

        guard let fd = UnixSocket.connect(path: path, timeoutSeconds: connectTimeout) else {
            return nil
        }
        defer { close(fd) }

        UnixSocket.writeAll(fd: fd, data)
        // Half-close write so server sees EOF
        shutdown(fd, SHUT_WR)

        if !blocking {
            // Fire-and-forget: do not wait for ack (avoids 1s tax on every PostToolUse).
            return nil
        }

        let response = UnixSocket.readAll(
            fd: fd,
            limit: IPCConstants.maxPayloadBytes,
            timeoutSeconds: IPCConstants.blockingRecvTimeoutSeconds
        )
        return response.isEmpty ? nil : response
    }
}
