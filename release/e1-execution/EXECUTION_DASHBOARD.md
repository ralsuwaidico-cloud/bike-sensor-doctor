# Cyclift — execution dashboard

Status: **Live tracker** · started 15 Nov 2026 · updated at every checkpoint.
Authorization: E1 safety implementation on the isolated branch `ios/e1-safety` (owner directive, 15 Nov). **Not authorized:** TestFlight upload, protected-branch merge, firmware, activation of redesigned features or of capabilities whose safety rules are undecided.

Evidence words used here: **written** = code exists on the branch · **compiled** = built in CI · **unit-tested** / **simulator-tested** = executed in CI, run number given · nothing here is physical-device evidence.

## 1. E1 tasks

Plan of 16 Nov: `release/execution-plan/2026-11-16_EXECUTION_PLAN.md`. Reference points: build 216 = `fb52ae27` (branch `baseline/build-216`); last E1 commit with every test job green = `a017ed6d` (run 235, branch `baseline/e1-run-235`); E1 candidate = `a6ded926` (run 236: compiled, 2 test failures); E1 head = `b167f514` (diagnostics only; run 237 in progress). Statuses below are for `a6ded926` and come from run 236 unless stated.

| Task | What | Status on `a6ded926` |
|---|---|---|
| E1-A1–A3 | Unreadable store never overwritten; record-by-record decoding; newer store read-only | Simulator-tested |
| E1-A4 | Six build-216 fixtures open, save and relaunch with no difference | Unit-tested on Linux only (run 92); does not run on iOS |
| E1-A5 | Backup policy; stale, unreadable, interrupted and repeated-recovery cases | Simulator-tested · direction confirmed by owner 16 Nov |
| E1-A6 | One-time clean-up; nothing on a failed write | Simulator-tested |
| E1-B1 | One write per save; rollback; retry not a duplicate; failed save completes nothing | Simulator-tested (data level) |
| E1-B2 | "Not saved" shown to the athlete | Implemented; **no screen test** |
| E1-C | Full-body edit without equipment; planner matrix | Simulator-tested |
| E1-D1 | Layout CI fails on zero tests or zero screenshots | Simulator-tested |
| E1-D2 | Largest-text clipping on Home, Profile, Plan; truncation check | **Open** |
| E1-E | Every automatic increase held in both engines | Simulator-tested |
| E1-F1, F3 | Ride completes the right planned ride; injectable clock | Simulator-tested · one stall-timing test failed on run 236, cause not established |
| E1-F4 | Delete all data | Copies tested; **exports and diagnostics untested** |
| E1-F5 | One start policy on every route, fail closed; external-ride marker; location gate | Simulator-tested at the policy level; **no screen-level route tests** |
| E1-G | Release accounting | Not started |
| — | Plan-edit flow test | Failed on run 236 (passed on 235); cause not established |
| — | Physical-device check | Not possible without an authorized build |

## 2. Parallel workstreams that do not touch E1 files

| Workstream | Branch (to create) | Owns | Can start |
|---|---|---|---|
| A · Foundation and navigation | `ios/ux-foundation` | Named destinations, dock (Navigation v1.2 rev 1.1), design tokens, string catalogue | Design-system and dock as new files now; the edit of `ContentView` waits for E1 (it now hosts the recovery screen) |
| B · Onboarding and Profile | `ios/ux-athlete` | New onboarding pages, Profile v2.0, shared editors, roster model | New views now; stored fields wait for the E1 schema guard |
| C · Training Hub | `ios/ux-train` | Panel, recorder presentation, review | New views now; save states wait for E1-B |
| D · Plan, Home, Progress | `ios/ux-plan` | Plan views, Progress hero, approved Home changes | After A |
| Coach foundation | `ios/c0-coach` | Policy table, decision ledger, typed proposals (new files) | Now, in shadow mode |

16 Nov: the owner authorized isolated UX1 preparation (theme system, navigation, shared components) on `ios/ux1-foundation`, new files only until Checkpoint 1. Not yet started in code. Coach foundation proposed to start now as new files in shadow mode (plan, section 6).

## 3. Shared contracts to agree before integration

1. **Save result** — `Store.durably`, `saveFailure`, `storage` (in E1). Every recorder and the Coach read these; nothing else may report "saved".
2. **Storage file** — schema 4, additive fields only; unknown fields carried; newer schema read-only.
3. **Named destinations** — one enum replacing tab numbers 0–4; ride start goes through one gate.
4. **Athlete record** — one roster, one set of profile fields, edited by the same editor from onboarding and Profile.
5. **Coach proposal** — typed change, evidence, origin (fact / rule / AI), policy version, outcome, reversal.
6. **Review** — three optional ratings; "not answered" is a stored value.

## 4. Approval status of every main screen

| Screen | Baseline | Status |
|---|---|---|
| Navigation | v1.2 rev 1.1 | **Approved** visual baseline · Train emblem pending (placeholder needs approval) |
| Onboarding | v3.3 structure; Page 2 = v3.4 Athletic Roster; Page 3 and 7 changes; Coach wording of 15 Nov | Page 2 **selected**; visuals of pages 1, 3–7 **not approved** |
| Profile | v2.0 six sections, via Home avatar | Architecture **approved**; visuals pending |
| Home | Build-216 Home + decisions of 12 Nov | Redesign **not approved**; quick-menu retirement undecided |
| Plan | Schedule-first: Weekly Calendar + Recurring Plan | Direction **approved**; integration design pending |
| Train | Training Hub v1.4 | **Approved** design baseline · cycling minimise blocked |
| Progress | Compact hero | Hero **approved** · stage criteria unresolved (no stage shown) |
| Coach | Design review v2 + progression rule of 15 Nov | Direction **approved** · screens, thresholds, allowlist pending |

## 5. Decisions that genuinely block development

| # | Decision | Blocks |
|---|---|---|
| 1 | Confirm the backup failure policy (`decisions/2026-11-15_e1-backup-failure-policy.md`) | E1 acceptance |
| 2 | Enforce location permission at ride start? Today a phone ride starts without it and the UI tests rely on that | E1-F5 completeness |
| 3 | Visuals of onboarding pages 1, 3–7; Profile visuals; temporary Train mark; Home quick menu; primary sports | UX1 |
| 4 | Thresholds of a "small" step; protective allowlist; old 7/6 ratings; fueling rules | UX3 Coach |

Resolved 15 Nov: all automatic increases held (owner); synthetic build-216 fixtures accepted as strong evidence (owner); set-order differences are not data loss (owner).

## 6. Earliest safe integrated TestFlight checkpoint

**E1**, after its acceptance gate and a separate release request. Not before the full iOS run on the release commit is green and E1-G is done.

## 7. Conflicts between the directive and the repository documentation

| Conflict | Records | Resolution taken | Needs a decision? |
|---|---|---|---|
| Scope of the interim hold | Decision record of 15 Nov; directive E1-E | Owner decided 15 Nov: all automatic increases held in both engines | No — resolved |
| Layout defects | Readiness package: triage at a checkpoint; directive E1-D: fix in E1 | Directive followed; added as E1-D2 | No |
| Diagnostics "pass unmodified" | E0 report; run 225 | One assertion restated with the reason in the file (timestamp rounding, no data lost); all others unchanged | No — disclosed |
| Themes and Arabic | Readiness package: six themes in UX1; directive of 15 Nov §8: later capability releases; **directive of 16 Nov: six themes in UX1 (Week 2), engine ready for Arabic/RTL** | Latest directive followed | No |

## 8. CI evidence, by commit

A result counts only for the commit in its row.

| Run | Commit | Result |
|---|---|---|
| Fast logic 75–78 | `d59193cf` … `d3a6aca0` | Failed on my test tooling, not on product code |
| Fast logic 79 | `62bb022d` | 404 executed, 1 skipped, 1 failed (my time-fit change; reverted) |
| Fast logic 80 | `ed761478` | Cancelled by my own later push |
| Fast logic 81 | `75859cff` | 405 executed, 1 skipped, 1 failed (wrong premise in my healthy-store test; corrected with the reason) |
| Fast logic 83, 84 | `58f637dd`, `03bc29a8` | 406 executed, 1 skipped, 1 failed test (member order of one stored set; not data loss) |
| Fast logic 86 | `410eeda5` | Passed; total not recorded (reporting fault of mine, fixed in the next commit) |
| Fast logic 87 | `9f19af51` | **416 executed, 0 failed, 2 skipped** (read-only-folder tests; iOS only). Six build-216 fixtures: 0 differences each |
| iOS 226 (quick) | `d59193cf` | Cancelled on owner authorization during screen tests. Before that: Debug and Release compiled; 688 unit tests executed, 2 tests failed (both since corrected); failed-write test passed; all 16 E0 diagnostics passed. Logs readable on `ci-logs` under `ios/run-226/` |
| iOS 227–232 | — | Cancelled while queued or replaced; no results |
| iOS 233 | `58f637dd` | Cancelled on owner authorization while queued; no results |
| iOS 234 (full) | `9f19af51` | Compile failure in all eight iOS test jobs: one error, a missing case in the Ride screen start hint (my omission). No tests ran. Watch job passed |
| Fast logic 90 | `a017ed6d` | **416 executed, 0 failed, 2 skipped** (the two read-only-folder tests). Six build-216 fixtures: schema 4 → 4, 28 fields → 28, 0 differences each |
| iOS 235 (full) | `a017ed6d` | Debug and Release compiled, 0 errors. **Unit: 709 executed, 707 passed, 0 failed, 2 skipped** (the two build-216 fixture tests; fixtures exist only on Linux, where run 90 ran them). Both read-only-folder tests passed on iOS. Smoke 21 passed; flows 8 passed; journeys 3 passed; layout: small 3 tests/79 screenshots, owner 2/77, standard 1/33 (after one simulator launch failure and retry: infrastructure), promax 1/13; watch 6 screenshots. Release job red by design: archive refused, nothing signed or uploaded. Largest-text truncation still present (Home ring value, Profile rows, Plan legend) and not caught by the automatic check. The unit summary line wrongly prints "Executed 4 tests" (reporting fault; the log total is 709) |

| Fast logic 91 | `a6ded926` | **426 executed, 0 failed, 3 skipped** (three read-only-folder tests; iOS only). Nine of the ten new data-contract tests ran and passed. Six build-216 fixtures: 0 differences each, no field added |
| Fast logic 92 | `a6ded926` | Passed (same commit as run 91, on `ios/e1-safety`) |
| iOS 236 (full) | `a6ded926` | **Not green: 2 test failures, 0 compile errors.** Debug and Release compiled. Unit: 724 executed, 721 passed, **1 failed**, 2 skipped (build-216 fixture tests, Linux only). Failed: `testE0_Ride_DeliberateStallProducesExactlyThatManyGapSamples` — expected 2–3 gap seconds after a 2.6 s stall, got 25; the test took 27.6 s (2.6 s on run 235). Samples matched elapsed time and no route fix was lost; where the extra 25 s went is not established (suspect: first GPS start in the test process now that CI grants location; not proven). All 6 new ride-gate tests and all 10 data-contract tests passed, including the three read-only-folder tests skipped on Linux. Smoke: 26 executed, 20 passed, 6 skipped by design, 0 failed (3 ride-screen tests passed). Flows: 8 executed, 7 passed, **1 failed** — `PlanEditPreviewApplyTests.testEditDurationGoesThroughPreviewAndApply`, duration slider not found after More → Edit; passed on run 235; cause not established. Journeys 3 passed. Layout: small 3 passed/79 screenshots, owner 2/77, standard 1/33 (one simulator launch retry), promax 1/13. Watch 6 screenshots. Release and archive not run because tests failed |
| iOS 237 (full, ID 43812843862), logic 93 | `b167f514` | **Failed.** Logic 93: success. Debug and Release compiled. Unit: 724 executed, 0 failed, 9 skipped (2 build-216 fixture tests; 7 `W12AndDockTests` that skip themselves on a Monday — an accounting gap, not yet addressed). Flows: 8 executed, 8 passed. Journeys: 3 passed. Smoke: 26 executed, 19 passed, 6 skipped by design, **1 failed** (`testAvatarOpensTheMenuAndEveryRowItsOwnPage`: avatar button not found when re-opening the menu). Layout small: **1 of 3 failed** (`testRC2OwnerScreens`: Plan day strip had no visible frame at the largest text size). Layout owner: **1 failed**, 1 passed, 1 skipped (`testRC2OwnerScreens`: screen query timed out). Layout standard and Pro Max: passed. Watch: 6 screenshots. |
| Finding across iOS 235–237 | `a017ed6d`, `a6ded926`, `b167f514` | Five different UI/timing tests failed across runs 236 and 237; none failed twice, and each passed in the other two runs. Both run-236 failures passed on 237 with no product change (stall test: sleep 2.602 s, 2 gap seconds, as expected). Per-test durations show no general slowdown. **Conclusion: intermittent; cause not established.** It is not known whether `a6ded926` introduced the instability or whether run 235 was a lucky pass. No test was weakened. |
| iOS 238 (full, ID 43822797515), logic 94 (ID 43822797491) | `3edad7ed` | Started 16 Nov. Adds two data-level tests for Delete-all coverage (exports, diagnostic reports, diagnostic history) and automatic failure screenshots in the Home-navigation and layout tests. No product code and no expectation changed. Logic 94: **success** (428 executed, 0 failed, 10 skipped) — the two Delete-all tests are unit-tested on Linux. iOS 238: results pending |
| Logic 95 (ID 43824977730), Linux only | `e99072d3` on `ios/c0-coach` | **Success**: 443 executed, 0 failed, 10 skipped; includes the 15 `CoachShadowTests`. Coach foundation is written and unit-tested on Linux. **Not compiled in the iOS app** (no iOS run started, by design). Shadow mode: cannot change plan, rides or strength logs |
| Logic 96 (ID 43825208367), Linux only | `9d764de5` on `ios/ux1-foundation` | **Success**: 441 executed, 0 failed, 10 skipped; includes the 13 `ThemeTokensTests`. Theme tokens and preference are written and unit-tested on Linux. **Not compiled in the iOS app; no screen uses them.** Colour values provisional |

Owner decisions of 15–16 Nov, implemented in `a6ded926` (record: `decisions/2026-11-16_e1-ride-authorization-external-rides-location.md`): one ride-start policy read from the athlete record, failing closed; BikeComputer rides begun during a hold kept and marked; phone-GPS rides need location permission; wider failed-save and recovery tests at data level. Still open: largest-text clipping and a truncation check, a screen test for "Not saved", Delete-all coverage for exports and diagnostics, release accounting.
