# ADR-0002: Unix domain socket IPC

**Date**: 2026-07-18  
**Status**: accepted  
**Deciders**: Bezel builders

## Context

Hooks need sub-100ms local IPC with optional long-lived blocking for approvals.

## Decision

Use a Unix domain socket at `~/Library/Application Support/Bezel/bezel.sock` (mode 0700). One JSON object per connection; bridge half-closes write (`SHUT_WR`); server replies for blocking events then closes. Max payload 10MB with deny-before-drop.

## Alternatives Considered

### TCP localhost
- **Cons**: Port conflicts, easier to scrape
- **Why not**: UDS is enough and safer by default

### `/tmp/bezel-<uid>.sock`
- **Pros**: Matches CodeIsland
- **Cons**: World-readable parent dir noise
- **Why not**: App Support is cleaner for a premium local app

## Consequences

### Positive
- Proven pattern from CodeIsland/Vibe Island
- No cloud dependency

### Negative
- Stale sockets need unlink-on-start

### Risks
- Listener not up before hooks install → auto-deny — start server first
