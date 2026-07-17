# Bezel — Implementation Plan (execute next)

Companion to `docs/TDD-DAG.md`. This is the **order of work** for the next sessions.

---

## Goal

Ship **Phase 1 vertical slice**: Claude Code → Bezel notch → Allow/Deny + AskUserQuestion, with TDD at Core seams. Jump is best-effort after permissions work.

---

## Current baseline

| Item | State |
|------|-------|
| Scaffold / build / DynamicNotchKit | ✅ |
| S1 Routing, S2 Normalizer, S3 Payload | ✅ 8 tests |
| HookServer + bridge + SessionStore | ✅ DecisionIngress + SessionReducer; HookServer I/O + wait |
| DecisionJSON | ✅ minimal, **needs golden fixtures N4** |
| ConfigInstaller | ✅ writes disk, **merger not pure N7** |
| Onboarding UI | ✅, **flow not pure N14** |
| AskUserQuestion | ❌ |
| Socket e2e | ✅ UnixSocket helpers + roundtrip suite |
| Terminal jump | ❌ |

---

## Execution order (follow the DAG)

### Sprint A — Core purity (W1–W3) · ~1 day

Do **not** touch UI except as needed to compile.

| Step | Node | TDD | Deliverable |
|------|------|-----|-------------|
| A1 | **N4** | RED golden DecisionJSON → GREEN | `Tests/Fixtures/decisions/` + canonical compare helper |
| A2 | **N8** | RED env→TerminalHint → GREEN | `TerminalHintExtractor` in BezelCore; bridge calls it |
| A3 | **N5** | RED phase table → GREEN | `SessionReducer`; thin `SessionStore` |
| A4 | **N6** | RED AskUserQuestion fixture → GREEN | `AskUserQuestionEncoder` |
| A5 | **N7** | RED merge cases → GREEN | `ClaudeSettingsMerger` |
| A6 | **N9** | RED roundtrip → GREEN | `TestHookServer` + temp socket e2e |

**Exit A:** `swift test` covers S4–S9; permission allow/deny roundtrip works **without** launching the GUI.

### Sprint B — App wiring (W4–W5) · ~1 day

| Step | Node | TDD | Deliverable |
|------|------|-----|-------------|
| B1 | **N10** | reuse N5/N9 | HookServer → reducer only |
| B2 | **N11** | store resolve tests | Notch Allow/Deny → S4 bytes |
| B3 | **N13** | temp `$HOME` install test | ConfigInstaller → merger |
| B4 | **N12** | store question tests | Question card → S6 |
| B5 | **N14** | OnboardingFlow tests | Pure steps; SwiftUI binds to flow |

**Exit B:** Bezel GUI can complete permission + question against local bridge injection.

### Sprint C — Jump + ship (W6–W7) · ~1 day

| Step | Node | TDD | Deliverable |
|------|------|-----|-------------|
| C1 | **N15** | RED jump plan fixtures | `TerminalJumpPlan` |
| C2 | **N16** | manual | `TerminalJumper` AppKit |
| C3 | **N17** | manual script | Claude live smoke |
| C4 | **N18** | checklist | Phase 1 acceptance |

**Exit C:** Phase 1 done per `docs/PLAN.md`.

---

## File ownership (where code goes)

```
Sources/BezelCore/
  PermissionRouting.swift      # S1 — exists
  EventNormalizer.swift        # S2 — exists
  HookPayload.swift            # S3 — exists
  DecisionJSON.swift           # S4 — tighten
  SessionReducer.swift         # S5 — NEW
  AskUserQuestionEncoder.swift # S6 — NEW
  ClaudeSettingsMerger.swift   # S7 — NEW
  TerminalHintExtractor.swift  # S9 — NEW
  TerminalJumpPlan.swift       # S10 — NEW
  OnboardingFlow.swift         # S11 — NEW
  SocketPath.swift / IPCConstants.swift

Sources/BezelBridge/
  main.swift                   # thin: parse stdin → extractor → UnixClient

Sources/Bezel/
  HookServer.swift             # I/O only
  SessionStore.swift           # holds state, calls reducer
  NotchController.swift        # SwiftUI
  ConfigInstaller.swift        # disk I/O around merger
  Onboarding.swift             # view of OnboardingFlow
  TerminalJumper.swift         # NEW — AppKit

Tests/BezelCoreTests/
  … one file per seam …
Tests/Fixtures/
  decisions/  hooks/  env/
```

---

## First three cycles (start here)

### Cycle 1 — N4 DecisionJSON
1. Add `Tests/Fixtures/decisions/permission-allow.json` (literal from Claude docs).
2. RED: `DecisionJSON.permissionAllow()` must equal fixture (canonical JSON).
3. GREEN: fix encoder.
4. Repeat for deny.

### Cycle 2 — N5 SessionReducer
1. RED: `SessionReducerTests` table (SessionStart → working).
2. GREEN: create reducer; call from store.
3. Next row: PermissionRequest → waitingPermission.

### Cycle 3 — N9 Socket roundtrip
1. RED: test starts server on `BEZEL_SOCKET_PATH`, sends SessionStart, expects `{}`.
2. GREEN: extract shared listen helper or use existing HookServer behind a protocol.
3. Next: PermissionRequest → inject allow → match N4 fixture.

---

## Risks & mitigations

| Risk | Mitigation |
|------|------------|
| HookServer hard to test (Darwin + MainActor) | Protocol `DecisionResponder` + in-memory fake for unit; e2e only for BSD socket |
| Touching real `~/.claude` | All installer tests set `HOME` to temp dir |
| Dual routing drift | Single `PermissionRouting` in Core; bridge imports it (already) |
| DynamicNotchKit focus steal | Manual QA in N17; defer custom panel |
| Scope creep (26 agents) | Hard stop after Claude in N18 |

---

## Stop conditions

- **Pause Jump (N15–N16)** if N17 Claude permission works — ship Jump next day.
- **Do not** start Codex/Cursor until N18 checked.
- **Do not** add telemetry, accounts, or Electron.

---

## Commands

```bash
cd /Users/rishabh/Vibe
swift test          # every red/green
swift build
./scripts/run-bezel.sh
```

---

## Sprint D — Correctness DAG (executed)

Follow the fix plan nodes F0–F24. Highlights:

| Node | Deliverable |
|------|-------------|
| F2/F3 | Lifecycle hooks + safe merger identity |
| F8/F9/F12/F15 | Timeout model + queue reap + store expire |
| F10/F11/F14 | Shared UnixSocket + inbound read timeout + e2e |
| F16 | Non-blocking bridge no-recv |
| F17–F19 | Observation notch, onboarding skip, single instance |
| F20/F21 | wezterm activateOnly; dead API removal |

Commands: `swift test` · `swift build` · `./scripts/run-bezel.sh`

