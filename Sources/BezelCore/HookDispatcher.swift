import Foundation

/// Pure hook-script template + `--source` dispatch for BezelBridge.
///
/// Claude installs call the bare hook (defaults to `claude`).
/// Codex / OpenCode / Cursor installers prefix `BEZEL_SOURCE=<agent>`.
public enum HookDispatcher {
    public static func scriptArgs(source: AgentSource) -> [String] {
        ["--source", source.rawValue]
    }

    /// Managed `bezel-hook.sh` body. Source comes from `BEZEL_SOURCE` (default `claude`).
    public static func script(bridgePath: String) -> String {
        """
        #!/bin/bash
        # Bezel hook dispatcher — managed, do not edit
        set -euo pipefail
        BRIDGE="\(bridgePath)"
        SOURCE="${BEZEL_SOURCE:-claude}"
        if [[ ! -x "$BRIDGE" ]]; then
          echo "Bezel: bezel-bridge missing or not executable at $BRIDGE" >&2
          exit 1
        fi
        exec "$BRIDGE" --source "$SOURCE" "$@"
        """
    }

    /// Shell command line written into agent hook configs.
    /// Claude stays a bare path so existing ClaudeSettingsMerger identity matches.
    public static func commandLine(source: AgentSource, hookPath: String) -> String {
        if source == .claude {
            return hookPath
        }
        return "BEZEL_SOURCE=\(source.rawValue) \(hookPath)"
    }

    public static func resolveSource(env: [String: String]) -> AgentSource {
        guard let raw = env["BEZEL_SOURCE"], let parsed = AgentSource(rawValue: raw) else {
            return .claude
        }
        return parsed
    }
}
