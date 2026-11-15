# Cyclift — E0 Diagnostic Evidence Report

> **Correction, 15 Nov 2026 (after first issue).** This report said that nine diagnostic tests failed in run 223. That was a counting error of mine. **Run 223 contained 12 new diagnostic tests: eight failed and four passed** (12 failed assertions inside those eight tests; 671 tests executed, 663 passed, 0 skipped). Run 224, an accidental duplicate of the same commit, gave the identical result. The two wrong passages are struck through below, not removed. No finding changes.


**15 Nov 2026 · E0 only. No product code was changed, no existing test was changed, nothing was uploaded, no athlete data was touched. E1 is not started and not authorized.**

Evidence classes: **[REPRODUCED]** a diagnostic test run in CI today showed it · **[BASELINE]** the unchanged existing tests showed it today · **[RECORDED]** an earlier recorded run shows it · **[SOURCE]** read in source only · **[HYPOTHESIS]** · **[UNRESOLVED]**. Everything ran on CI simulators; **nothing here is physical-device evidence.**

**E0 status: the reproductions are complete; three items remain unresolved and are listed in section 6. One duplicate run (224) is still queued and is not needed for any conclusion below.**

## 1. Source commit and branches

| Item | Value |
|---|---|
| Audited commit | `4e2e9dc15349f38316133dfe83b99f41fac7cea8` (branch `ios/checkpoint-f-ride`) |
| Baseline branch | `ios/e0-diagnostic` → exactly that commit, no change |
| Reproduction branch | `ios/e0-repro`, commit `c2cecde2`: one new test file (`E0DiagnosticTests.swift`, 12 tests) and five added lines in the CI log script so every test is listed by name. No product file and no existing test differs from the audited commit |
| Difference from the shipped build 216 | Build 216 is commit `fb52ae27`; the audited commit is later and differs in two product files (the session-change review sheet). So the baseline is the release line, not a byte-identical copy of build 216 |

## 2. Commands and run identifiers

All runs used the repository's own workflow (`ios.yml`, scope full, upload off) — the same script that produced earlier runs. Fast logic tests used `logic.yml`.

| Run | Id | Branch / commit | Purpose | Result |
|---|---|---|---|---|
| iOS 222 | 43712242641 | e0-diagnostic / 4e2e9dc | **Unchanged baseline** | Unit passed; flows failed (1 test); release refused to archive; nothing uploaded |
| Logic 72 | 43712244487 | same | Linux engine tests | 386 tests, 0 failures |
| iOS 223 | 43718826051 | e0-repro / c2cecde2 | **Reproductions** + second sample of every existing test | Unit: 671 executed, ~~9 diagnostic tests failed as designed~~ **8 of the 12 new diagnostic tests failed and 4 passed (corrected 15 Nov, see note at top)**; flows failed (same 1 test); nothing uploaded |
| Logic 73 | 43718826039 | same | Linux engine tests | Started with 223; result not read |
| iOS 224 | 43718835472 | e0-repro / c2cecde2 | Duplicate I started by mistake | Queued when this was written |

Every iOS run also performed the workflow's usual App Store Connect check (bundle ids and tester groups "already registered"); it makes no change when they exist.

## 3. Original test results (unchanged tests)

| Job | Run 222 (baseline) | Run 223 (second sample) |
|---|---|---|
| Unit | 659 executed, 0 failures | 659 existing tests: all passed (663 passed in total with 4 passing diagnostics) |
| Flows | 8 tests, **1 failed**: Plan edit → preview → apply (4 assertions) | Same 1 failed |
| Delete-all-data (inside flows) | Passed (71 s) | Passed |
| Smoke | 3 passed | 3 passed |
| Journeys | hybrid, cycling, strength passed | passed |
| Layout × 4 | "ok (0 screenshots)" — **every layout test skipped** | Same |
| Watch | passed | passed |

The complete per-test list (671 lines) is in the logs branch at `ios/run-223/test.txt`. The baseline log of run 222 is preserved unmodified at `ios/run-222/`.

## 4. Reproduction results (new diagnostic tests, run 223)

Each diagnostic asserts the behaviour an athlete needs, so a **failure means the defect was reproduced**.

| Diagnostic | Outcome | What it showed |
|---|---|---|
| Plan edit, full body, no equipment | **Failed — reproduced** | 16 of 16 duration requests (20–150 min, with and without the routine) cannot be applied. With equipment recorded, 4 of 4 can |
| Unreadable store at launch | **Failed — reproduced** | A truncated 2,629-byte store was replaced at launch by a new 4,856-byte one; the app started not onboarded; no other file exists beside it |
| Stage of replacement | **Failed — reproduced** | Creating the store object alone: file intact, 0 writes. Creating it as the app does at launch: replaced, 1 write. First later change: replaced |
| One bad strength record | **Failed — reproduced** | One undecodable record of two → strength history loaded as 0; the valid record was gone from the file after launch |
| Malformed-record matrix (12 lists) | **Failed — reproduced** | See table in section 5 |
| Failed write | **Failed — reproduced** | With storage read-only, saving a strength session returned "success"; 2 sessions in memory, 1 after relaunch; the only trace is an internal error text |
| Newer store opened by this build | **Failed — reproduced** | Unknown fields were dropped on the first save **and the schema number was rewritten from 99 to 4** |
| Round trip | **Failed** | What is in memory differs from what a relaunch reads back; the file itself is stable. Cause not isolated |
| Automatic writes while loading | Passed | Current-format file: 0 writes at launch. Older (schema 1) file: 4 writes at launch |
| Ride: 20 repeats of the existing steps | Passed | 0 of 20 produced extra samples; slowest start 0.010 s |
| Ride: deliberate 2.6 s stall | Passed | Exactly 2 gap samples; all 5 route fixes kept |
| Diagnostics never touch app data | Passed | Fixtures are under the temporary directory, on a simulator |

## 5. Confirmed root causes

**5.1 Plan edit dead end [REPRODUCED + BASELINE].** With no equipment recorded, the planner fills the hip slot with nothing (short sessions) or with "Back extension", which the validator does not count as hip-dominant work. Every rebuilt session therefore has hip coverage 0 and is blocked by rule SPLIT-001; while the athlete's routine is attached it is blocked by ROUTINE-001 instead. Recorded rows: 45 min → "Air squat, Decline push-up, Inverted row, Box step-down" (hip 0). With dumbbells and a bench the planner chooses "Dumbbell swing" and the session passes. The failure is **deterministic**: the flow test failed in both runs today and in runs 219–221, and the diagnostic reproduced it in every one of 16 cases. Bodyweight hip exercises exist in the catalogue (glute bridge, hip thrust, single-leg variants); **why the planner does not select them is still a hypothesis** (section 6).

**5.2 Ride sample count [REPRODUCED mechanism; original failure not reproduced].** Extra samples are gap markers equal to elapsed wall-clock seconds; a 2.6 s stall gives exactly 2. The existing test passed in runs 216, 222 and 223 and in 20 of 20 diagnostic repeats, and failed once (run 221, five extra samples, test took 7.1 s). Classification: **environment-dependent timing**, not data loss — in every run all five route fixes were kept. What stalled that one runner for about five seconds is unknown.

**5.3 Data loss — exactly when and how [REPRODUCED].**

| Question | Answer |
|---|---|
| When is an unreadable file overwritten? | **During launch**, by the automatic plan generation that runs before any athlete action. Not by reading. If plan generation did not run, the first later change overwrites it |
| Is there any backup or recovery? | No. Only `store.json` exists. A manual export exists; there is no import [SOURCE] |
| One bad record in **workouts (plan)** or **rides** | The **whole store** is treated as empty — profile, plan and all history — and is overwritten at launch |
| One bad record in **strength** or **templates** | That **whole list** loads empty (2 → 0, 1 → 0); the rest survives. The athlete is told nothing. The file is rewritten on the next save |
| One bad record in Coach lists (adaptations, proposals, pain clearances, plan versions, trash, board sync) | The list loads empty; these fixture lists had no valid records to lose, so loss of valid neighbours is **shown by the same code pattern, not by this test** |
| Custom exercises | The malformed record was **accepted as a custom exercise** (count 0 → 1) |
| Can a failed save look like success? | Yes |
| Automatic writes during loading | Plan generation (launch, midnight); migration from an older format (4 writes); trash purge; one-time cleanup |
| What survives an interrupted write? | Writes are atomic [SOURCE], so the previous file survives a crash mid-write. Not tested here |
| What cannot be recovered? | Anything overwritten after a failed read; anything saved only in memory after a failed write; a ride in progress when the app is terminated [SOURCE] |
| Rollback to an older build | Loses every field the newer build added, on the older build's first save |

**5.4 Layout audits [BASELINE + RECORDED + SOURCE].** A CI script edit of mine on 9 Nov (commit `004936d1`) put a clean-up command between the audit's settings and the test command, so the settings applied to the clean-up, not the tests. Every layout test has reported "skipped — LAYOUT_DIR not set" since. **Thirteen runs** reported a green layout audit with zero tests: 207–212, 214–216 and 218–221; today's 222 and 223 show the same. **One uploaded build is affected: 216.** Its release note's "all four layout audits green" was untrue, and the app has had no small-iPhone or large-text check since run 205.

## 6. Remaining hypotheses and unknowns

| Item | Status |
|---|---|
| Why the planner skips bodyweight hip exercises when equipment is unset | **[HYPOTHESIS]** — likely the availability check for exercises listed as "barbell or bodyweight". Needs one more diagnostic that prints the candidate pool |
| Round-trip difference between memory and disk | **[UNRESOLVED]** — expected cause is timestamps stored to the second; not confirmed |
| Delete-all-data failure in run 216 | **[UNRESOLVED]** — see section 7.3 |
| What stalled run 221 | **[UNRESOLVED]** — one occurrence |
| Behaviour on a real iPhone (storage full, protected data while locked, termination during a ride) | **Not tested** |
| Build-216 fixture | **Not produced.** The diagnostics build stores with today's code; a store written by the shipped build 216 itself has not been captured |

## 7. Newly discovered problems

**7.1 From the reproductions.** (a) A newer store's schema number is rewritten downward by an older build, so the newer build would later re-run migrations on already-migrated data. (b) A malformed record can be accepted as a custom exercise. (c) Loading an older-format store writes the file four times before the athlete does anything.

**7.2 From reading source during E0 [SOURCE].** (d) The "location allowed" check before a phone ride is ignored — the function takes the value and never uses it — so a ride can start with no location access and record no route. (e) The health-check pause hides Start only on the Ride screen; the Plan button, both Watch routes and the BikeComputer route start a ride without checking it. (f) The CI summary's unit-test count is taken from the last matching line and was wrong (3 or 4 instead of the total) in runs 208–212. (g) The published log was capped at 400 lines, so 245 of 659 unit results were never individually visible.

**7.3 Delete-all-data, run 216.** Available evidence: one filtered log and one unrelated screenshot. No crash report, simulator log or result bundle was collected for that test. The failure text is "Lost connection to the application" inside the helper that waits for the Home screen. That helper is called twice: at the start, and at the very end as a check that the deleted athlete does **not** reappear. The test ran 167 s, longer than any passing run (66–163 s), which suggests it reached the final check — after deletion and relaunch had already been asserted — but the log cannot prove which call failed. It has passed in 8 of 9 recorded runs (214, 215, 218–223). **I cannot distinguish an app crash after relaunch from a simulator fault. The defect stays open; it is not "fixed".**

**7.4 Release mechanism for build 216.** The flows job is marked advisory for internal builds by your decision of 10 Nov, so a red flows job does not stop an internal upload. The commit also carried a `[full-override: …]` note, which bypasses a different gate (the quick-check requirement). Nothing in the pipeline requires a failing test to be **named and acknowledged**, so the Delete-all-data failure went into the build's own run unrecorded.

## 8. Navigation safety (U1 is not safe to release on its own)

**Hard-coded page numbers [SOURCE]:** Home 0, Plan 1, Ride 2, Progress 3, Profile 4.

| Where | What it does |
|---|---|
| `ContentView` 39, 134, 154 | Ride colour scheme; "Ride owns the bottom of the screen"; centre tap while recording — all test `tab == 2` |
| `ContentView` 51–55 | Five pages kept alive by number |
| `ContentView` 87, 98, 171 | Train sheet, Home actions and the centre button open Ride with `tab = 2` |
| `HomeView` 46, 59, 137, 164 | Plan (1) and Profile (4) from the checklist, quick menu and recovery |
| `HomeDashboardView` 123, 341, 387, 419 | Plan (1), Profile (4) and "Free ride" (2) |
| `StrengthLog` 505, 517 | "Revise my days" (1); Coach "Start" (2) |
| `CyLiquidDock` 29–42 | Dock items and the centre slot by number |

**Every route that can start a ride:** the Ride screen (phone or BikeComputer); **Plan › "Start this workout"**, which starts recording and stays on Plan; the Apple Watch command; the detachable-watch coordinator; a ride begun on the BikeComputer itself, which the phone adopts. Three of these start a ride while another page is showing.

**Effect of the approved three-tab dock:** Ride and Profile leave the dock but must remain pages; "Ride owns the screen" must follow the recorder, not the tab; leaving Ride or Profile has no defined return; six UI test steps tap a "Profile" tab that will not exist, including the Delete-all-data test. No deep links or notification routes exist, and the strength session is presented independently of tabs — those are not at risk.

**Proposed semantic model (design only, not implemented):** destinations named `home`, `plan`, `progress`, `ride`, `profile`; Train as an action, not a destination; one rule "ride owns the screen = a ride is recording or paused and the Ride destination is showing"; a remembered return destination for Ride and Profile; tests locate controls by identifier, not by tab label. The Navigation v1.2 visual baseline is unchanged by this. **Safeguards before U1:** the semantic model first, behind a flag; the layout audit repaired; a device check of the left Train control against the swipe-back edge.

## 9. Recommended E1 scope — smallest coherent changes (not authorized)

| # | Change | Class | Independently revertable? |
|---|---|---|---|
| E1-1 | Never write over a store that could not be read: move the original aside byte-for-byte, start in a recovery state, show it | Critical data integrity | Yes |
| E1-2 | Keep one previous copy before the first write of each launch and before any migration | Critical data integrity | Yes |
| E1-3 | Decode lists record by record: keep valid records, set bad ones aside, tell the athlete; reject malformed custom exercises | Critical data integrity | Yes |
| E1-4 | Never lower a schema number; carry unknown fields through a save | Critical data integrity | Yes |
| E1-5 | Saving returns committed or failed; "saved" is shown only on committed; a failed save is shown where it happens | Critical data integrity | Yes |
| E1-6 | Planner selects a hip-dominant exercise for full-body sessions with bodyweight; when a rule still blocks, the review offers a correction | Required before upload | Yes |
| E1-7 | One ride-start gate (health pause, location) used by all five routes | Required before upload | Yes |
| E1-8 | CI: repair the layout audit; fail when required tests are skipped; assert minimum test and screenshot counts per job; uncapped per-test log; collect crash logs and result bundles on failure | Required before upload | Yes |
| E1-9 | Release policy: any failing test in a release run must be listed by name with a written reason; privacy and data-integrity tests can never be waived | Required before upload | n/a |
| E1-10 | Injectable clock in the ride recorder (test-only use) | Required infrastructure | Yes |
| Not in E1 | Navigation, onboarding, Profile, Train, Plan, Progress, Coach redesign; ride persistence during recording (cycling safety gate) | Approved UX / later | — |

Coach changes (review defaults, approval gating) depend on the decisions in the Coach design-review package and are deliberately **not** bundled here.

## 10. Proposed acceptance and regression tests

- The ~~nine~~ **eight** diagnostics that failed today become E1's acceptance tests and must pass **unmodified**; the ~~three~~ **four** that passed stay as regressions.
- The existing Plan-edit flow test must pass unmodified.
- New: interrupted-write test; record-by-record decode per list with valid neighbours in all twelve lists; a store written by build 216 itself opens identically (needs the fixture); layout job fails when zero screenshots are produced; delete-all-data repeated 20 times with crash-log capture.
- Device checklist (not simulator): storage full; phone locked during a save; termination during a strength session and during a ride.

## Corrections to my earlier statements

| Earlier statement | Correction |
|---|---|
| "Overwritten at the next save" (audit) | Overwritten **during launch** |
| "The override note cited only one failure" (audit) | The note concerned a different gate; the real gap is that failures need not be acknowledged |
| "Stuck closing flag" (before the audit) | Withdrawn; cause is 5.1 |
| "All four layout audits green" (build-216 release note) | Untrue; no layout test ran |
| "Onboarding default 'Not sure'" as the affected group | Any store with no equipment recorded, including upgrades |

## Approval requests

1. Accept this as the E0 evidence record, with the three unresolved items left open.
2. Authorize one further diagnostic-only run to settle the planner hypothesis, the round-trip difference and to repeat Delete-all-data 20 times with crash logs (CI logging change only; no product change).
3. Decide whether the build-216 fixture should be captured from your own TestFlight install (it would need a data export from you) or built from the build-216 commit in CI.
4. Authorize E1 with the scope in section 9 — or tell me what to remove.
5. Confirm the release policy in E1-9.

**I have stopped here. E1 is not started.**
