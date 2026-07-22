import Testing
import Foundation
import BezelCore

@Suite("HookDispatcher")
struct HookDispatcherTests {
    @Test func scriptArgs_includeSourceClaude() {
        #expect(HookDispatcher.scriptArgs(source: .claude) == ["--source", "claude"])
    }

    @Test func scriptArgs_includeSourceCodex() {
        #expect(HookDispatcher.scriptArgs(source: .codex) == ["--source", "codex"])
    }

    @Test func scriptArgs_includeSourceOpenCodeAndCursor() {
        #expect(HookDispatcher.scriptArgs(source: .opencode) == ["--source", "opencode"])
        #expect(HookDispatcher.scriptArgs(source: .cursor) == ["--source", "cursor"])
    }

    @Test func script_defaultsToClaudeViaEnv() {
        let script = HookDispatcher.script(bridgePath: "/Users/x/.bezel/bezel-bridge")
        #expect(script.contains("BEZEL_SOURCE"))
        #expect(script.contains("--source \"$SOURCE\""))
        #expect(script.contains("SOURCE=\"${BEZEL_SOURCE:-claude}\""))
        #expect(script.contains("/Users/x/.bezel/bezel-bridge"))
    }

    @Test func commandLine_forCodexSetsEnv() {
        let cmd = HookDispatcher.commandLine(source: .codex, hookPath: "$HOME/.bezel/bezel-hook.sh")
        #expect(cmd.contains("BEZEL_SOURCE=codex"))
        #expect(cmd.contains("$HOME/.bezel/bezel-hook.sh"))
    }

    @Test func commandLine_forClaudeIsBareHook() {
        let cmd = HookDispatcher.commandLine(source: .claude, hookPath: "/Users/x/.bezel/bezel-hook.sh")
        #expect(cmd == "/Users/x/.bezel/bezel-hook.sh")
        #expect(!cmd.contains("BEZEL_SOURCE="))
    }

    @Test func resolveSource_prefersEnvThenDefault() {
        #expect(HookDispatcher.resolveSource(env: ["BEZEL_SOURCE": "codex"]) == .codex)
        #expect(HookDispatcher.resolveSource(env: ["BEZEL_SOURCE": "cursor"]) == .cursor)
        #expect(HookDispatcher.resolveSource(env: [:]) == .claude)
        #expect(HookDispatcher.resolveSource(env: ["BEZEL_SOURCE": "nope"]) == .claude)
    }
}
