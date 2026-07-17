import Testing
import Foundation
@testable import BezelCore

@Suite("DecisionJSON")
struct DecisionJSONTests {
    @Test func permissionAllowMatchesFixture() throws {
        let fixture = try loadFixture("permission-allow")
        #expect(JSONCanonical.equal(DecisionJSON.permissionAllow(), fixture))
    }

    @Test func permissionDenyMatchesFixture() throws {
        let fixture = try loadFixture("permission-deny")
        #expect(JSONCanonical.equal(DecisionJSON.permissionDeny(), fixture))
    }

    @Test func emptyAckMatchesFixture() throws {
        let fixture = try loadFixture("empty-ack")
        #expect(JSONCanonical.equal(DecisionJSON.emptyAck(), fixture))
    }

    @Test func denyEscapesQuotesInMessage() throws {
        let data = DecisionJSON.permissionDeny(message: #"say "no""#)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let hook = obj?["hookSpecificOutput"] as? [String: Any]
        let decision = hook?["decision"] as? [String: Any]
        #expect(decision?["behavior"] as? String == "deny")
        #expect(decision?["message"] as? String == #"say "no""#)
    }

    private func loadFixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "decisions")
            ?? Bundle.module.url(forResource: name, withExtension: "json")
        guard let url else {
            // Fallback: relative to package root when Bundle.module resources lag
            let path = FileManager.default.currentDirectoryPath
            let candidates = [
                "\(path)/Tests/Fixtures/decisions/\(name).json",
                "\(path)/../Fixtures/decisions/\(name).json",
            ]
            for c in candidates {
                if let d = try? Data(contentsOf: URL(fileURLWithPath: c)) { return d }
            }
            Issue.record("Missing fixture \(name).json")
            throw FixtureError.missing
        }
        return try Data(contentsOf: url)
    }

    private enum FixtureError: Error { case missing }
}
