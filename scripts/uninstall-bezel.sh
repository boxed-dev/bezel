#!/usr/bin/env bash
# Strip Bezel hooks from ~/.claude/settings.json (foreign hooks preserved)
# and remove managed files under ~/.bezel.
#
# Does NOT touch real settings unless HOME points there — use as the user.
set -euo pipefail

HOME_DIR="${HOME:?HOME must be set}"
SETTINGS="$HOME_DIR/.claude/settings.json"
BEZEL_DIR="$HOME_DIR/.bezel"

echo "→ stripping Bezel hooks from $SETTINGS (if present)"

if [[ -f "$SETTINGS" ]]; then
  python3 - "$SETTINGS" <<'PY'
import json, sys
from pathlib import Path

path = Path(sys.argv[1])
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
                and "bezel" in h["command"].lower()
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

if [[ -d "$BEZEL_DIR" ]]; then
  echo "→ removing managed files under $BEZEL_DIR"
  rm -f \
    "$BEZEL_DIR/bezel-hook.sh" \
    "$BEZEL_DIR/bezel-bridge" \
    "$BEZEL_DIR/bridge-version"
  # Leave the directory if the user put other files there.
  rmdir "$BEZEL_DIR" 2>/dev/null || true
  echo "✓ cleaned Bezel install artifacts"
else
  echo "  (no ~/.bezel directory)"
fi

echo "Done. Restart Claude Code if it was running."
