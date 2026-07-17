import Foundation
import Darwin

/// Lightweight Unix-socket probe: Connect succeeds only when HookServer answers.
public enum SocketLiveness {
    /// Connect to the Bezel socket, send an empty body (ping), expect `{}` empty ack.
    public static func probe(
        path: String? = nil,
        timeoutSeconds: TimeInterval = IPCConstants.eventTimeoutSeconds
    ) -> Bool {
        let sockPath = path ?? SocketPath.resolve()
        guard let fd = UnixSocket.connect(path: sockPath, timeoutSeconds: timeoutSeconds) else {
            return false
        }
        defer { close(fd) }

        // Empty ping: half-close write so HookServer sees EOF with zero bytes → emptyAck.
        shutdown(fd, SHUT_WR)

        let response = UnixSocket.readAll(
            fd: fd,
            limit: 256,
            timeoutSeconds: timeoutSeconds
        )
        return JSONCanonical.equal(response, DecisionJSON.emptyAck())
    }
}
