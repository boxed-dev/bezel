import Foundation

public enum TabMatch: Equatable, Sendable {
    case matched
    case unknown
    case mismatch
}

/// Frontmost tab hint — filled by App via NSWorkspace / optional probes.
public struct FrontTabHint: Equatable, Sendable {
    public var bundleID: String?
    public var itermSession: String?
    public var tty: String?

    public init(bundleID: String? = nil, itermSession: String? = nil, tty: String? = nil) {
        self.bundleID = bundleID
        self.itermSession = itermSession
        self.tty = tty
    }
}

/// Pure compare: session terminal hint vs front tab hint (no AppleScript in Core).
public enum TabVisibility {
    public static func compare(session: TerminalHint?, front: FrontTabHint?) -> TabMatch {
        guard let session else { return .unknown }
        guard let front else { return .unknown }

        if let sid = normalized(session.itermSession), let fid = normalized(front.itermSession) {
            if sid == fid || sid.hasSuffix(fid) || fid.hasSuffix(sid) {
                return .matched
            }
            return .mismatch
        }

        if let stty = normalized(session.tty), let ftty = normalized(front.tty) {
            let sShort = stty.replacingOccurrences(of: "/dev/", with: "")
            let fShort = ftty.replacingOccurrences(of: "/dev/", with: "")
            if stty == ftty || stty.contains(fShort) || ftty.contains(sShort) {
                return .matched
            }
            return .mismatch
        }

        if let sb = normalized(session.bundleID), let fb = normalized(front.bundleID), sb == fb {
            return .unknown
        }

        return .unknown
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }
}
