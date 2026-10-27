# Coach engine handoff (CO-1, CO-2)

Branch `fix/coach`, pushed as `ios/coach`. Reviewed head before this round: `3e801a0`. Final head: `f725cc4` (engine).

## Commits since 3e801a0 (for QA re-check)
| Commit | What | Files |
|---|---|---|
| `4d82b13` | Ride fatigue now sets the planner's shared progression hold (audit G-03), like the adaptive coach already did ("no progression until the signals ease"). Before: during ride fatigue, coach-built lifts still added load (harness P25: squat 60 → 62.5 kg, deadlift 80 → 82.5 kg). Lifting / combined fatigue unchanged (deload). | `StrengthPlanner.swift` (`Store.plannerContext`), test `AuditFixTests.testRideFatigueHoldsThePlannerLikeTheCoach` |
| `f725cc4` | A routine's load or reps go up only after two sessions at the CURRENT prescription (same rule as the planner, G-02). Before: two completed sessions at different weights counted, so a routine went up one step after every session (harness P30: goblet squat 12 → 19 kg in three weeks). | `AdaptationEngine.swift` (`strengthDecision`, `atCurrent`), test `CoachRemediationTests.testRoutineProgressesOnlyAfterTwoSessionsAtTheCurrentWeight` |

No threshold was tuned and no acceptance criterion was weakened or removed.

## Tests
- Linux engine unit tests: **164 run, 0 failed** (162 at 3e801a0 + the 2 new tests).
- Harness (48 athletes P01–P34 + N01–N14, rule probes), debug build, full run **s12 on f725cc4**:
  - original criteria: profiles **44 / 48**, original probes **19 / 20** (X18);
  - every remediation criterion passes (51 of 51), new probes X18-b and X21 pass;
  - with the five documented conflicts set aside, 48 / 48 profiles.
  - Earlier: base (32a0676) 32/34 + 18/20 · s6 45/48 + 19/20 · s7 incomplete (22 profiles, no probes) · s8 (3e801a0) 45/48 + 19/20.
- Results per criterion: `coord/handoffs/coach-TEST_RESULTS_FINAL.csv` (case, criterion, base result, final result, evidence,
  kind, text, s6 / s7 / s8 results, note). The same file is at `/home/claude/coach-remediation/TEST_RESULTS_FINAL.csv`.

## Original criteria still failing (each kept and reported; documented conflict, remediation criterion added)
| Case / criterion | Why it fails | Remediation criterion |
|---|---|---|
| P30-a | needs "a rep instead of a load step > 5 %"; independent review F-17 replaced the 5 % cap with the smallest step (≤ 2.5 kg, caution above 10 %) | P30-b PASS (now on P30; in s8 it was by mistake attached to P29) |
| P30 G7-bounds, P08 G7-bounds | the "≤ 5 %" part of G7: 1 kg dumbbell step on 18 / 19 kg = 5.6 / 5.3 %. P08 appears now because f725cc4 slows routine progression (19 kg instead of 22 kg after 4 weeks) | G7-bounds-b (G7 with the F-17 step) PASS in all 48 |
| P32-a | needs an automatic load-spike cut; F-15 made the load ratio information only (offered, not applied) | P32-b PASS |
| P25-a | needs a leg set cut; F-25: legs already at the 2-set floor for the next key ride are not cut again, the rider is told | P25-b PASS (also checks: no leg progression during ride fatigue, fixed in 4d82b13) |
| X18 | the probe's logs carry no link to the coach cut, so a coach cut cannot be told from an unfinished session | X18-b PASS (linked logs, plus an unfinished control that must not progress) |

Science advisory (not counted): S2 "≤ 25 % of ride minutes in Zone ≥ 3 sessions" fails on most hybrid profiles (≈ 29 %, session-level,
warm-up included). At base it passed only because hybrid rides had no intensity at all (gap M-05); one quality ride of three now.

## Owner checks (harness N-series + unit tests, all pass)
Pain restrictions are never auto-released for soreness / discomfort / concerning pain; the health check never claims clearance and
handles stop / supervised-only / incomplete / returning users; scheduling, progression, cycling intensity, swapping, routines and
data preservation show no regression in s12 (only change vs s8 in original criteria: P08 G7-bounds, explained above).

## Harness changes (in /home/claude/coach-harness, not in git)
P25-b (new), P30-b moved from P29 to P30 and extended to every load step in the simulation, G7-bounds-b (new, all cases),
probes X18-b and X21 (new). Originals unchanged. Runs: out-s8, out-s9/s10/s11 (targeted), out-s12 (full, final).

## CI
"iOS apps" run **80** for `f725cc4`: **success** (simulator unit tests 383 run, 0 failures; archive, export, layout and launch checks passed; no TestFlight upload). Runs 76, 78 and 79 were superseded and cancelled. This handoff commit touches only `coord/`, so it does not start a new iOS run.

## Open
- QA to re-check 4d82b13 and f725cc4.
- Harness probe X06 compares `Workout.liveIntervalPlan` (SwiftUI ride coach is not compiled on Linux), as before.

## Lead round (27 Oct 20:50) — QA pass 4 on 0d9fc24
- P4-01 (P1) fixed: `Workout.markRiderEdited(before:)` judges "health-check pause" on the session as stored before the edit;
  `Store.edit` passes it. Editing a capped ride to Rest drops the safety original (the rider's own rest stays).
- P4-02 fixed: Home "Instead of" alternative now goes through `store.edit` (marked edited, never replaced by a refresh).
- P4-06: P30-b / P32-b titles now state exactly what they check (logic unchanged).
- P4-03, P4-04, P4-05 (F-22), P4-07: documented as known limitations in ios/ADAPTIVE_COACH.md.
- QA pass-4 probes adopted as IndependentReviewPass4ProbeTests (U2 calls store.edit like HomeView now does; noted in header).
- Linux engine tests: 201 run, 0 failed.
