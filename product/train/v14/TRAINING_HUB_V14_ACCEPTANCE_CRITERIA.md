# Training Hub v1.4 — Acceptance and regression criteria

Status: **Current Draft — for use only if a prototype is separately approved.** · Version 0.1 · 14 Nov 2026 · Level 3
Each line is a check with a pass condition. None has been run.

## A. Session identity and minimise / resume (strength)

| ID | Check | Pass |
|---|---|---|
| A1 | Start tapped 10 times in 2 s | Exactly one session exists |
| A2 | Train emblem tapped 50 times at random intervals | Exactly one panel; never a second session; no missed close |
| A3 | Minimise, wait 60 s, resume | Same session identity; elapsed has advanced 60 s ± 1 s; exercise, set and typed values unchanged |
| A4 | Minimise during a 90 s rest, resume after 30 s | Rest shows 60 s ± 1 s left; never restarts |
| A5 | Minimise, wait until rest ends, resume | Rest shows 0:00; no set logged |
| A6 | Log a set, minimise, resume | Undo still offered; using it removes exactly that set |
| A7 | Log two sets | Undo refers to the second only |
| A8 | While minimised, try every start route | Only Resume is offered |
| A9 | Switch tabs 20 times while recording | One timer; no duplicate Health workout; no extra sensor subscription |
| A10 | End the app, relaunch | The session returns paused with all logged sets |

## B. Recorder layout

| ID | Check | Pass |
|---|---|---|
| B1 | Frames of Log, − / +, rest, Undo, Next across all states | Identical to the point |
| B2 | Every control | ≥ 44 × 44 pt on the smallest supported iPhone |
| B3 | Number pad open | Log fully visible and tappable |
| B4 | Largest accessibility text | Nothing truncated; Log fixed; all actions reachable |
| B5 | VoiceOver | Order as specified; reps and weight adjustable; rest read with remaining time |
| B6 | Reduce Motion | No sliding or spinning; states still distinguishable |

## C. Sensor truth (cycling)

| ID | Check | Pass |
|---|---|---|
| C1 | Meter connected, rider coasting | Shows 0 W; recorded as 0 |
| C2 | No update for the stale threshold | Value dimmed with its age; not recorded as new |
| C3 | Meter disconnected | "—" with reason; stored samples empty; no carried-forward value |
| C4 | No meter paired | "—", "No power meter"; never 0 |
| C5 | Paused | No value forced to 0; nothing recorded |
| C6 | Summary after a gap | Gap duration stated; averages over measured seconds only |

## D. Finish, save, review

| ID | Check | Pass |
|---|---|---|
| D1 | Save with 9 of 11 sets | Record has 9 sets; plan marked partial; nothing invented |
| D2 | Finish with no sets | Save not offered; "mark done" stored as marked |
| D3 | Forced save failure | No success shown; session kept; retry writes exactly one record |
| D4 | Unknown save result | Treated as not saved; "Check again" never creates a second record |
| D5 | Discard | Requires confirmation; plan unchanged |
| D6 | Skip review | Workout saved; all ratings unknown; nothing equal to 7 or 6 stored |
| D7 | Answer one rating only | Others stay unknown (or the review is not stored, per the owner's choice) |
| D8 | Drag a slider | Value follows the finger in whole steps 1–10; page does not scroll |
| D9 | Pain with area but no level | No level stored or sent |

## E. Regression — must still pass unchanged

Strength session journey · hub tap reliability · ride control plan (Lap + Pause / Resume + End) · ride disconnect tests ·
no second strength session · part-logged session survives restart · superset alternation · one Health export per ride ·
all layout stages · the existing journeys. The two tests failing on the release head today must be explained first so they
are not mistaken for regressions.

## F. Cycling gate (only after separate approval)

Force-quit at minute 20 of a phone-recorded ride → on relaunch the ride is offered with at least 19 minutes of samples and the
gap marked missing · 60-minute locked-phone ride on a real phone with no unexplained gaps · call during a ride · sensor drop
and return · no duplicate ride or Health workout after restore.
