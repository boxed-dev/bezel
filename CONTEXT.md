# Bezel — Domain Language

## Glossary

**Bezel** — The product. A macOS notch/menu-bar companion that surfaces AI coding agent sessions at the display edge.

**Session** — One running agent conversation, keyed by `session_id` from the agent CLI. Has a phase, cwd, title, and optional terminal hint.

**Phase** — What a session needs right now: `idle`, `working`, `waitingPermission`, `waitingQuestion`, `planReview`, `done`, `error`.

**Island event** — Normalized lifecycle signal from an agent (session start/end, tool use, permission, question, stop). Vendor JSON is never shown to the UI.

**Bridge** — The `bezel-bridge` executable invoked by agent hooks. Forwards events over the socket; blocks only for decisions.

**HookServer** — In-app Unix-socket listener that receives bridge messages and routes them into the session store / decision queues.

**Decision** — Allow, deny, or question answer returned to a blocking hook so the agent can continue.

**Admission** — Rules that drop unwanted sessions before they appear (by launcher app, directory, or first prompt).

**Jump** — Activate the exact terminal tab / IDE pane where a session is running.

**Smart suppress** — Do not auto-expand the notch when the user is already viewing that session’s tab.

**SessionReducer** — Pure function that maps `(Session, HookPayload) → Session` phase transitions. UI and HookServer must not embed phase rules.

**ClaudeSettingsMerger** — Pure merge of Bezel hook entries into Claude `settings.json` data without touching the filesystem.

**TerminalJumpPlan** — Pure choice of how to focus a session’s terminal given a `TerminalHint`.

**SessionID.unknown** — Canonical session id (`"unknown"`) when the agent omits `session_id`. Never invent a random UUID per event.

**DecisionTimeout** — Pure deny payload builder for timed-out or superseded queue entries.

