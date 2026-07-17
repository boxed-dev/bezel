# ADR-0001: Swift three-module split

**Date**: 2026-07-18  
**Status**: accepted  
**Deciders**: Bezel builders

## Context

Bezel must receive events from AI CLI hooks, show a notch HUD, and return permission decisions. CodeIsland and Vibe Island both use a tiny out-of-process bridge plus an in-app socket server.

## Decision

Ship three SwiftPM targets: `BezelCore` (shared models/logic), `bezel-bridge` (hook executable), `Bezel` (LSUIElement app).

## Alternatives Considered

### Single app binary with embedded scripts
- **Pros**: One artifact
- **Cons**: Hooks invoking a full app bundle is slow/fragile
- **Why not**: Bridge must be a tiny, fast CLI

### Go/Rust bridge + Swift UI
- **Pros**: Cross-compile SSH hooks later
- **Cons**: Two toolchains for v1
- **Why not**: Auditability and “know what’s inside” prefer one language first; add remote hooks in Phase 4

## Consequences

### Positive
- Shared types between bridge and app
- Unit-test Core without AppKit
- Clear permission-routing sync surface

### Negative
- Must keep bridge + HookServer route kinds in sync

### Risks
- Divergence → mitigate with shared `RouteKind` in Core + tests
