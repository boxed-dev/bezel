# ADR-0003: DynamicNotchKit for MVP notch HUD

**Date**: 2026-07-18  
**Status**: accepted  
**Deciders**: Bezel builders

## Context

We need a buttery notch overlay in days, not weeks.

## Decision

Use DynamicNotchKit 1.1 for Phase 0–1: `compact` always-on on notch Macs, `expand` on permission/hover. Replace with a custom `NSPanel` if multi-monitor always-on or focus-stealing becomes a problem.

## Consequences

### Positive
- Geometry + springs solved; ship faster

### Negative
- Compact auto-hides on floating/non-notch — must keep expanded or force `.floating` carefully

### Risks
- Kit `canBecomeKey` quirks — monitor during QA
