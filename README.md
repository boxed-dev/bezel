# Bezel

**Beta** — macOS notch companion for Claude Code.

Monitor agent sessions, approve permissions, answer questions, and jump back to the terminal — from the notch.

> Status: **public beta** (`0.1.0-beta`). Expect sharp edges. Claude Code is the supported agent for this release.

## What it does

| Capability | Description |
|---|---|
| **Sessions** | Live list of Claude sessions at the notch |
| **Permissions** | Allow / Deny from the notch (`⌘Y` / `⌘N`) without switching apps |
| **Questions** | Answer `AskUserQuestion` prompts from the notch |
| **Plan review** | Approve or reject ExitPlanMode plans |
| **Jump** | Focus the originating terminal (iTerm2, Ghostty, Terminal, Warp, …) |
| **Sounds** | Optional 8-bit style alerts (toggle in Settings) |
| **Local only** | Unix socket IPC. No accounts, no telemetry |

## Requirements

- macOS 14+
- Apple Silicon or Intel
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- Xcode 16+ / Swift 6.2 toolchain (to build from source)

## Quick start (beta)

### Build & run

```bash
git clone https://github.com/boxed-dev/bezel.git
cd bezel
./scripts/run-bezel.sh
```

Release package:

```bash
./scripts/package-bezel.sh
open dist/Bezel.app
```

### First launch

1. Complete onboarding → **Connect** (writes hooks to `~/.claude/settings.json`).
2. Restart Claude Code so hooks reload.
3. Start a Claude session — the notch badge should update.
4. When Claude asks for permission, expand the notch and **Allow** / **Deny**.

If Connect refuses because of competing island hooks, open **Settings → Replace vibe-island / CodeIsland hooks** (explicit; never automatic).

### Uninstall hooks

```bash
./scripts/uninstall-bezel.sh
```

Or use **Settings → Remove Bezel hooks**.

## Architecture

```
Claude Code
  → ~/.claude/settings.json hooks
  → ~/.bezel/bezel-hook.sh
  → bezel-bridge
  → Unix socket ~/Library/Application Support/Bezel/bezel.sock
  → HookServer → SessionStore → Notch HUD
  ← decision JSON (blocking events only)
```

| Target | Role |
|---|---|
| **BezelCore** | Pure logic: payload parse, session reducer, decision queue, settings merge, jump planning |
| **bezel-bridge** | CLI invoked by hooks: stdin JSON → enrich terminal env → socket |
| **Bezel** | LSUIElement app: socket server, notch UI, onboarding, settings, jump |

## Development

```bash
swift test          # BezelCore unit + socket roundtrips
swift build
./scripts/run-bezel.sh
```

### Environment (testing only)

| Variable | Purpose |
|---|---|
| `BEZEL_SOCKET_PATH` | Override socket path |
| `BEZEL_AUTO_DECISION=allow\|deny` | Auto-resolve permissions (smoke tests only) |
| `BEZEL_SKIP` | Bridge no-ops when set |

Do not ship with `BEZEL_AUTO_DECISION` set.

## Project docs

- [`docs/PLAN.md`](docs/PLAN.md) — product plan
- [`docs/IMPLEMENTATION.md`](docs/IMPLEMENTATION.md) — build order
- [`docs/TDD-DAG.md`](docs/TDD-DAG.md) — seams & correctness DAG
- [`docs/adr/`](docs/adr/) — architecture decisions
- [`CONTEXT.md`](CONTEXT.md) — domain language

## Beta limitations

- **Claude Code first.** Other agents are not fully supported yet.
- Ad-hoc code signing for local builds (not notarized).
- Jump quality depends on terminal + Accessibility permission.
- If another notch companion owns Claude hooks, Bezel will refuse to merge until you remove or replace them.

## License

MIT — see [LICENSE](LICENSE).

## Contributing

Issues and PRs welcome. For behavior changes, prefer a failing test in `Tests/BezelCoreTests` first.

---

**Bezel** `0.1.0-beta`
