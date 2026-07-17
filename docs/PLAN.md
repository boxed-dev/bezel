# Bezel — Build Plan

**Product:** Bezel  
**Process:** `Bezel`  
**Bundle ID:** `app.bezel.macos`  
**Bridge:** `bezel-bridge`  
**Socket:** `~/Library/Application Support/Bezel/bezel.sock`  
**Minimum:** macOS 14+, Swift 6.2  

Premium native notch HUD for AI coding agents. Local-first. No Electron. No telemetry by default.

**Execution docs (authoritative for build order):**
- [`docs/TDD-DAG.md`](./TDD-DAG.md) — seams, TDD rules, dependency DAG
- [`docs/IMPLEMENTATION.md`](./IMPLEMENTATION.md) — sprint sequence + first cycles

Research synthesized from: CodeIsland architecture, Claude hooks protocol, naming/onboarding, notch + terminal jump.

---

## Locked decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Name | **Bezel** (not another Island) |
| 2 | Stack | Pure Swift — Core + bridge + app |
| 3 | IPC | Unix domain socket, JSON, SHUT_WR half-close |
| 4 | Notch MVP | DynamicNotchKit (`compact` always-on); custom NSPanel if multi-monitor/focus breaks |
| 5 | First agent | Claude Code only |
| 6 | Privacy | No Sentry/telemetry; hooks stay local |
| 7 | Onboarding | 6 screens (see below); permissions progressive |

---

## Architecture

```
Claude Code
  → ~/.claude/settings.json hooks
  → ~/.bezel/bezel-hook.sh
  → bezel-bridge
  → UDS ~/Library/Application Support/Bezel/bezel.sock
  → HookServer (NWListener)
  → SessionStore (@MainActor)
  → Notch HUD (DynamicNotchKit) + Approval / Question panels
  ← decision JSON on stdout (blocking events only)
```

### Modules

| Target | Responsibility |
|--------|----------------|
| `BezelCore` | Models, socket path, event normalize, permission route kinds, session graph — heavily tested |
| `bezel-bridge` | stdin JSON → enrich terminal env → socket → stdout decision |
| `Bezel` | LSUIElement app: HookServer, SessionStore, notch, onboarding, ConfigInstaller, TerminalJumper |

### Critical correctness rules

1. **Start HookServer before writing Claude settings** (or PermissionRequest auto-denies).
2. **Dual routing:** bridge `isBlocking` ↔ server `routeKind` must stay in sync (unit-tested).
3. Oversized payload (≥10MB): send valid deny JSON, then drop.
4. Never return `updatedInput` on wildcard PreToolUse (corrupts AskUserQuestion).
5. Half-close (SHUT_WR) is not a disconnect — do not auto-deny on write EOF.
6. Capture `_iterm_session`, `_tty`, `TMUX_PANE`, `TERM_PROGRAM` in the **bridge**, not later.

---

## Onboarding (6 screens)

1. **Welcome** — Bezel wordmark; notch morph once. No config.
2. **The glance** — Working / Waiting / Done. Teach the model.
3. **Connect** — Detect Claude Code → write hooks → verify socket. *Configuring…*
4. **Jump** — Ask Accessibility in context; skip allowed.
5. **Stay ready** — Launch at login toggle (default on); apply only here.
6. **You’re set** — Live idle notch. Done.

Visual: near-black `#07080A`, frosted glass, steel-cyan accent `#8BA3B5`, SF Pro + tracked wordmark. Motion: notch spring, staggered rows, 280–360ms crossfade.

---

## Phases (ship fast)

### Phase 0 — Skeleton (days 1–2) ← NOW
- [x] Plan + identity locked
- [x] SwiftPM package + targets (`BezelCore`, `bezel-bridge`, `Bezel`)
- [x] Core unit tests (routing, normalizer, payload) — 8 passing
- [x] HookServer (UDS) + bridge client
- [x] LSUIElement shell + DynamicNotchKit compact HUD
- [x] Debug demo session + Settings
- [ ] Manual socket roundtrip smoke test with live Bezel process

### Phase 1 — Claude vertical slice (days 3–5)
- [x] ConfigInstaller → `~/.claude/settings.json` + `~/.bezel/` (first cut)
- [x] Permission Allow/Deny from notch (wired)
- [ ] AskUserQuestion answers (UI + JSON)
- [x] SessionStart/End + Stop + UserPromptSubmit + Pre/PostToolUse (merger + reducer + store apply)
- [x] 6-screen onboarding (first cut)
- [ ] Jump: iTerm reveal + Terminal tty + Ghostty (Warp/Cursor degrade)

### Phase 2 — Polish (week 2)
- [ ] ExitPlanMode review
- [ ] Smart suppress (tab-level)
- [ ] Sound (optional, quiet default)
- [ ] Settings: hooks repair, launch at login, display

### Phase 3 — Multi-agent
- [ ] Adapter protocol; Codex + Cursor
- [ ] Then Gemini / OpenCode / …

### Phase 4 — Hard mode
- [ ] Custom NSPanel (if kit limits hit)
- [ ] SSH remote hooks
- [ ] Usage quotas

---

## Acceptance (Phase 1 done)

- Idle RAM reasonable; near-zero CPU when idle
- Permission card < ~100ms after hook
- Allow/Deny roundtrips; Claude does not hang
- Onboarding completes without forced Accessibility
- Uninstall/repair restores hooks cleanly
- External display: floating style works

---

## Non-goals (v1)

- Accounts, cloud sync, paywall in onboarding
- Pixel mascots / 8-bit fanfare
- 26 agents on day one
- Electron / Tauri
- Forking CodeIsland wholesale (patterns only)

---

## Sprint D — Correctness (post Phase 1 wiring)

See `docs/TDD-DAG.md` §Sprint D. Critical fixes shipped in Core:

- Lifecycle hooks registered (`SessionEnd`, `Stop`, `UserPromptSubmit`) so sessions can leave `.working`
- Merger no longer deletes foreign AskUserQuestion hooks; Bezel identity is path-exact
- HookServer: inbound read timeout, blocking wait 600s, timeout reaps decision queue, locked response box
- Bridge: no recv on fire-and-forget events; Claude-only routing (no Gemini gate)
- Session identity: missing `session_id` → `"unknown"` (never a fresh UUID)
- Single-instance flock before socket bind

