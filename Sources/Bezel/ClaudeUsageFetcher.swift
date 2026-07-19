import Foundation
import BezelCore

/// Fetches Claude.ai plan usage via OAuth (same source as `/usage`).
enum ClaudeUsageFetcher {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let keychainService = "Claude Code-credentials"

    static func fetch() async -> ClaudeUsageSnapshot? {
        guard let token = readAccessToken() else { return nil }

        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("Bezel/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                return nil
            }
            return ClaudeUsageParser.parse(data, source: "oauth")
        } catch {
            NSLog("Bezel: Claude usage fetch failed — \(error.localizedDescription)")
            return nil
        }
    }

    /// Reads Claude Code OAuth access token from Keychain. Never logs the secret.
    private static func readAccessToken() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-s", keychainService,
            "-w",
        ]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty
        else { return nil }

        if let obj = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] {
            if let oauth = obj["claudeAiOauth"] as? [String: Any],
               let token = oauth["accessToken"] as? String,
               !token.isEmpty
            {
                return token
            }
            if let token = obj["accessToken"] as? String, !token.isEmpty {
                return token
            }
        }
        // Rare: raw token string
        if !raw.hasPrefix("{") { return raw }
        return nil
    }
}
