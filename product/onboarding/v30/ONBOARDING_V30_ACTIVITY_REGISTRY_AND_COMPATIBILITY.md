# Onboarding v3.0 — activity architecture, capability and measurement registry, compatibility plan

**Version:** 0.1 · 15 Nov 2026 · **Status:** Current Draft — proposal · nothing implemented; no storage changed; **no migration has been attempted or tested**
Builds on `../v20/ATHLETE_MODEL_AND_MIGRATION.md` and Training Hub `v11/B_ACTIVITY_REGISTRY_AND_CAPABILITY_MATRIX.md` (both unchanged).

## C. Architecture
Three domains. Every activity has: a **durable identifier** (never reused or renamed), domain, role (*training* or *occasional recovery*), icon, measurement contract, and a **capability state that belongs to the app build, not to the athlete**: Records today · Importable (verified) · Loggable by hand · Timer · Not supported yet.
Setup shows a short starter library (11 tiles); everything else is reached by search. Recents and favourites are kept per athlete for the Training Hub [PROPOSAL].

## H. Registry — starter library
"Today" = as read in code, not run.
| Activity | Id | Domain · role | Measurements with a real source today | Capability today | Plan today | Proposed later |
|---|---|---|---|---|---|---|
| Road cycling | `roadCycling` (exists) | Endurance · training | time; speed, distance, route (GPS); heart rate (watch/strap); power, cadence (power meter); laps | Records | yes | — |
| Indoor cycling | `indoorCycling` (exists) | Endurance · training | time; heart rate; power, cadence; speed/distance only from a sensor | Records (same recorder; no indoor mode) | as cycling | indoor template without GPS |
| Mountain bike | `mountainBike` (exists) | Endurance · training | as road cycling | Records (label of the same recorder) | as cycling | — |
| Commuting | `commuting` (exists; search only) | Endurance · training | as road cycling | Records | as cycling | — |
| Running | `running` (exists) | Endurance · training | none | **Not supported** | no | recording, or log by hand |
| Swimming | `swimming` (exists) | Endurance · training | none | Not supported | no | timer + manual lengths |
| Walking | *new* | Endurance · training **or** recovery (open) | none | Not supported | no | to be decided |
| Gym training | `strength` (exists) | Strength · training | sets, reps, load, rest (athlete-entered); duration | Records | yes | further set types only when built |
| Bodyweight | *new id* **or** maps to `strength` + bodyweight equipment (open) | Strength · training | reps; duration | Records (as strength) | yes | — |
| Stretching & mobility | *new* | Rest & Recovery · occasional | none (a "mobility" plan entry exists, no recorder) | Not supported | planner can place a mobility session | timer, optional sequence |
| Breathing | *new* | Rest & Recovery · occasional | none | Not supported | no | timer |
| Sauna & cold | *new* | Rest & Recovery · occasional | none | Not supported | no | log afterwards; no durations recommended |
| Other | `other` (exists; search only) | — | none | Not supported | no | log by hand |
Rules: no recovery activity is described as improving recovery; recovery entries never count as training, never change adherence and are never Athlete Evolution evidence; sleep is imported information, not a selectable activity; no composite fitness or readiness score.

## K. Field-by-field compatibility plan
| Field | Today | v3.0 | Compatibility |
|---|---|---|---|
| `trainingMode` | cycling / strength / hybrid | same values; "Endurance" label for `cycling` | none needed |
| `sports` | 8 values, default `[roadCycling]` | same list, plus new identifiers | additive; **reader must tolerate unknown values — unconfirmed**; no silent rewrite of existing lists; one "confirm your activities" prompt where the list is the untouched default and disagrees with the type |
| recovery activities | — | new optional list | absent = none |
| favourites / recents | — | new optional lists | absent = none |
| `priority`, `level`, experience, goals | exist | unchanged | none |
| where you ride, days-can-move, rest-day preference | — | new optional values | absent = not stated; planner behaviour unchanged until wired |
| `heightCm`, units | exist | asked in setup | none |
| availability, equipment, exclusions, supersets, split, FTP, HR | exist | unchanged | none |
| `onboardingStage` | 101–105 (and legacy 1–9) | eight chapters, proposed 301–308 | mapping: A→1 (→2 if a type is set), B→3, C→5, D→6, E→8; partial answers kept; nothing asked twice |
| `onboarded`, plan versions, plan | exist | unchanged | migration never regenerates a plan |
| history (rides, strength sessions, weights, FTP, zones) | exists | untouched | never rewritten from new preferences or current weight |
| storage | one on-device JSON file | same | additive optional fields; no account, cloud or restore |

## Independent tests required before any implementation proposal (none written or run)
1. Old five-stage file at each stage opens at the mapped chapter with answers intact. 2. Legacy 1–9 stage file. 3. Approved-plan file: plan, versions and history byte-identical after first launch. 4. File containing an activity identifier unknown to the build loads and preserves it. 5. Older build reading a newer file (rollback). 6. Strength-only athlete with default `sports`: prompt appears, nothing rewritten. 7. Round trip: each onboarding answer reads identically in Profile and back; exactly one stored copy. 8. Unsupported-only athlete: setup completes, zero planned sessions exist. 9. Plan-affecting Profile edit: no change without approval; decline restores inputs. 10. Weight or FTP change leaves past records unchanged. 11. Kill and relaunch in every chapter. 12. Existing tests updated, never weakened; the two open failures resolved or explained first.
