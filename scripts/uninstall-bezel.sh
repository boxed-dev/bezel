#!/usr/bin/env bash
# Strip Bezel hooks from ~/.claude/settings.json (foreign hooks preserved)
# and remove managed files under ~/.bezel.
#
# Hook identity matches ClaudeSettingsMerger.isBezelHookCommand — never a bare
# "bezel" substring (so tools like bezel-logger.sh are left alone).
#
# Writes ~/.bezel/user-uninstalled so the app will not re-merge on launch.
#
# Does NOT touch real settings unless HOME points there — use as the user.
set -euo pipefail

HOME_DIR="${HOME:?HOME must be set}"
SETTINGS="$HOME_DIR/.claude/settings.json"
BEZEL_DIR="$HOME_DIR/.bezel"
MARKER_NAME="user-uninstalled"

echo "→ stripping Bezel hooks from $SETTINGS (if present)"

if [[ -f "$SETTINGS" ]]; then
  python3 - "$SETTINGS" "$HOME_DIR" <<'PY'
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
home = sys.argv[2]
hook_command = str(Path(home) / ".bezel" / "bezel-hook.sh")
hook_command_portable = "$HOME/.bezel/bezel-hook.sh"


def is_bezel_hook_command(command: str) -> bool:
    """Mirror Sources/BezelCore/ClaudeSettingsMerger.isBezelHookCommand."""
    trimmed = command.strip()
    unquoted = trimmed.strip("\"'")
    if unquoted in (hook_command, hook_command_portable):
        return True
    if unquoted.endswith("/.bezel/bezel-hook.sh"):
        return True
    if unquoted.endswith("/bezel-hook.sh"):
        return True
    if "/.bezel/bezel-hook.sh" in unquoted:
        return True
    return False


try:
    root = json.loads(path.read_text(encoding="utf-8"))
except Exception as e:
    print(f"error: could not parse {path}: {e}", file=sys.stderr)
    sys.exit(1)

hooks = root.get("hooks")
if isinstance(hooks, dict):
    cleaned = {}
    for event, groups in hooks.items():
        if not isinstance(groups, list):
            cleaned[event] = groups
            continue
        kept = []
        for group in groups:
            if not isinstance(group, dict):
                kept.append(group)
                continue
            inner = group.get("hooks")
            if not isinstance(inner, list):
                kept.append(group)
                continue
            has_bezel = any(
                isinstance(h, dict)
                and isinstance(h.get("command"), str)
                and is_bezel_hook_command(h["command"])
                for h in inner
            )
            if not has_bezel:
                kept.append(group)
        if kept:
            cleaned[event] = kept
    if cleaned:
        root["hooks"] = cleaned
    else:
        root.pop("hooks", None)

path.write_text(json.dumps(root, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(f"✓ wrote {path}")
PY
else
  echo "  (no settings file — nothing to strip)"
fi

echo "→ removing managed files under $BEZEL_DIR"
mkdir -p "$BEZEL_DIR"
chmod 700 "$BEZEL_DIR" 2>/dev/null || true
rm -f \
  "$BEZEL_DIR/bezel-hook.sh" \
  "$BEZEL_DIR/bezel-bridge" \
  "$BEZEL_DIR/bridge-version"
# Durable marker: ConfigInstaller.syncInstalledBridgeIfNeeded must not re-merge.
: > "$BEZEL_DIR/$MARKER_NAME"
chmod 600 "$BEZEL_DIR/$MARKER_NAME" 2>/dev/null || true
echo "✓ cleaned Bezel install artifacts (user-uninstalled marker set)"

echo "Done. Restart Claude Code if it was running."
