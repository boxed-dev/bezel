# Sprint A — Core purity (N4–N9)

**Label:** done  
**Blocks:** Sprint B app wiring  
**Blocked by:** none  

## Goal

Extract and TDD BezelCore seams so permission allow/deny roundtrip works without the GUI.

## Acceptance

- [x] DecisionJSON matches golden fixtures (canonical JSON)
- [x] TerminalHintExtractor covers ITERM/TMUX/Warp/Kitty env
- [x] SessionReducer owns all phase transitions; SessionStore is thin
- [x] AskUserQuestionEncoder echoes questions + answers (+ Claude-docs fixture)
- [x] ClaudeSettingsMerger is idempotent and preserves foreign hooks (timeout 600 asserted)
- [x] Socket e2e: event ack + blocking allow (wait/resume) on `/tmp/bezel-test-*.sock` + `BEZEL_SOCKET_PATH`
- [x] `swift test` green — **32 tests / 9 suites**

## Spec review follow-ups (addressed)

- SessionStore no longer writes phases directly
- Kitty extract test, SessionEnd→done, fixture path, delayed permission allow
