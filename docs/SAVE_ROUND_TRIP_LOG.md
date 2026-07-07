# Save round-trip session log

**Date:** 2026-07-07  
**Reference font:** `~/Downloads/~Untitled/PlayfairRomanVF.woff2`

## Phase 0 — Environment baseline

| Check | Result |
|-------|--------|
| Python fontTools | OK |
| vfcommit dry-run (fixture + live path) | `ok: true`, 8 instances (minimal fixture axes) |
| Playfair at `~/Downloads/PlayfairRomanVF.woff2` | Not present |
| Playfair at `~/Downloads/~Untitled/PlayfairRomanVF.woff2` | Present |

## Phase 1 — Write verification

Automated tests perform write + fvar re-analyze (`CommitRoundTripTests`).

| Check | Result |
|-------|--------|
| Instance count (fvar) | PASS — 252 written for live Playfair import |
| vfcommit summary | PASS — `instances_written` matches |
| Re-analyze fvar names | PASS — sample composed name present in output |
| Full grid re-import into InstancePlanner | PASS — fixed STAT v1.2 offset parsing (relative AxisValue offsets) |
| Font Book manual check | Verify locally after Save Copy |

## Phase 2 — Automated tests

- `Tools/vfcommit/tests/test_round_trip_write.py`
- `Tests/VarFontCoreTests/CommitRoundTripTests.swift`
- `Tests/VarFontCoreTests/LiveFontFixture.swift`
- `fixtures/fonts/README.md`

## vfcommit fix

`included_instance_keys` now filters fvar writes and name allocation (previously summary-only).

## Edit matrix coverage

| Edit | Swift test | Python test |
|------|------------|-------------|
| Baseline write | `testPlayfairRomanWriteRoundTrip` | `test_write_and_reopen_fvar_count` |
| Exclude instances | `testExcludeInstancesRoundTrip` | `test_exclude_instances_reduces_fvar_count` |
| Rename stop | `testRenameStopRoundTrip` | `test_rename_stop_reflected_in_stat_name` |
| Registration | `testRegistrationRoundTrip` | — |
| Clarifiers + PS prefix | `testClarifierAndPSPrefixInCommitRequest` | — |
| Roboto Flex (pinned axes) | `testRobotoFlexWriteRoundTrip` | — |
