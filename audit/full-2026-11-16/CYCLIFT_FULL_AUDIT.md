# Cyclift — full project, codebase and CI audit

**Version:** 0.1 · 16 Nov 2026, 23:10 Dubai · Level 2 · Status: Current Draft — for owner review.
**How this was done.** Read from the live GitHub repository `bike-sensor-doctor` (71 branches, 13 workflows), the Actions run list, the CI log branch and the source tree at `ios/lab` commit `679d8cae`. Nothing was merged, deleted, cancelled, uploaded or changed. No new CI run was started.
**Words used.** *Verified* = I read it in the repository or in a run's own output today. *Simulator* = seen running in an iOS simulator in CI; never a phone. *Hypothesis* and *Recommendation* are marked.

---

## A. Executive report

### A1. What actually exists today
- **Production line:** build 216 (`baseline/build-216` `fb52ae27`, release head `ios/checkpoint-f-ride` `4e2e9dc1`). 135 Swift files, about 39,400 lines, 81 unit-test files, 16 screen-test files.
- **Redesign:** about 5,200 lines in 19 new files on `ios/lab`, all in the shared app behind one switch (`CyProduct.redesign`), which is on only in the Cyclift Lab build. All of it was written on 16 Nov.
- **Cyclift Lab on TestFlight:** still version 0.1.0 (3), built from `59e2f033` — the old interface with themes. Nothing newer has been uploaded.
- **E1 safety line:** `ios/e1-safety` `33374d48`, 8 commits not in Lab.
- **Other components in the same repository:** firmware (1,432 files), a 22-file Android app, an 8-file Apple Watch app, and `watch/v3-poc` (170 commits) for the detachable watch.

### A2. What is genuinely working (simulator evidence, synthetic athlete)
| Item | Evidence |
|---|---|
| Navigation v1.2, Profile v2.0 six sections | Lab 8, 9, 11, 12 |
| Six themes; switching through Profile › Appearance | Lab 11, 12 (passed) |
| Plan v2.0 renders this week on real athlete state | Lab 9 (screenshots only) |
| Compact Train panel → full Hub | Lab 11 (checks passed) |
| Progress hero in the "no stage" state | Lab 11 (checks passed) |
| Strength recorder opens on the planned session; reps ± work | Lab 12 (stopped at Log set) |
| Lab isolation, Delete all data, Restore | Every Lab run since 5 |
| Production build compiles with the redesign off; unit tests pass | iOS 265 (`679d8cae`), logic 117 (499 Linux tests) |

### A3. What is incomplete
- **No end-to-end journey has completed once.** Onboarding, Coach conversation, strength save, review and cycling demonstration have compiled but have not been seen working.
- **No Cyclift Lab run has ever passed in full** (15 runs: 13 failed or still running, 2 cancelled).
- Home v2.x, the preparation screen, Plan interactions, in-session substitution: not started.

### A4. What is blocked
- **macOS build machines.** Lab 13 waited 44 minutes for a machine; iOS 264 was cancelled after 15 minutes without ever getting one. This, not the code, is the main delay tonight.
- **E1:** no fully verified commit; the last four full runs failed or were cancelled.
- **Cycling recording behind the new screen:** the cycling safety gate.
- **AI chat, fueling copy, stage criteria:** owner or specialist decisions.

### A5. What has been overlooked (found in this audit)
1. **A defect I introduced.** In the redesign the Home Coach card now always opens the Coach page, but the page lists only one of the app's two kinds of Coach proposal. Suggestions from the hybrid coach (the card in today's screenshots, "Make Wed's tempo an endurance ride", is one), the FTP suggestion and the "rate your session" prompt can no longer be opened from Home in Lab. *Verified in source.*
2. **Production behaviour was changed without a screen test.** Today's work edited code that production runs: the onboarding approve path, the strength save function, Delete all data, the next-set rule and the Coach's pain rules. Only compile and unit tests have run on these. The full screen-test suite has **never** run on any `ios/lab` commit.
3. **Checks that skipped quietly.** Several Lab checks were written as "if the control exists, test it". The Coach-card check never ran in Lab runs 5–10 and reported nothing. Passing Lab checks are therefore weaker evidence than they look.
4. **No Arabic and no localisation at all.** There are no translated strings and no right-to-left handling in the app. *Verified.*
5. **No data import.** The app exports the athlete's data but cannot import it. "Export → delete → import → recover" is not possible today.
6. **The Lab build still contains the account/cloud code and library.** Its keys are absent (checked in every run), so it is inactive, but "no production backend" is true by missing configuration, not by absent code.
7. **The demo strip is missing on full-screen pages and sheets** (recorder, Coach page, review, onboarding sheets). Only some carry their own "demo" wording.
8. **Repository housekeeping.** The repository is public and about 4.5 GB. Its default branch `main` is the Android project from 20 Oct, not Cyclift. The root status file is from 28 Oct. A `UI Lab prototype` run has sat queued since 11 Nov. Every new non-iOS branch triggers an unneeded Android build.
9. **Five different "proposal" types and two coach engines** exist in the app, plus the new policy layer. The redesign's Coach page understands one of them.

### A6. The five biggest risks
| # | Risk | Why it matters |
|---|---|---|
| 1 | Shared production code changed today without full screen tests | A fault in save, onboarding approval or Delete all data would reach production when Lab is promoted |
| 2 | Width without depth: ten redesigned areas written in one day, none verified end to end | Rework and false confidence; the same pattern produced Lab 0.1.0 |
| 3 | E1 is stalled and drifting from Lab (8 commits apart; both edit the Plan week row and the CI script) | The safety release keeps slipping while attention is on Lab |
| 4 | New optional record fields and build 216 | If 216 re-saves a newer record it drops reviews, skip counts and timed/added/assisted details; untested |
| 5 | CI capacity | Each Lab run takes 40–80 minutes including queueing; a new push cancels the queued one |

### A7. The five most important next actions
1. **Stop adding features until the three journeys pass once** (onboarding → plan; strength → save → review; cycling demonstration), then join them through Progress and Coach.
2. **Fix the Coach-card defect** so every existing Coach action is reachable again.
3. **Run the full production screen suite once on the current Lab commit** (needs your approval: about 90 minutes of machine time). It is the only way to know today's shared-code edits did not break build-216 behaviour.
4. **Bring the 8 E1 commits into Lab** (a trial merge is clean) so there is one line of code again, and decide whether E1 ships from that line.
5. **Batch pushes:** one push per verified batch, not one per fix, so runs stop cancelling each other.

---

## B. Development tracker

States: **W** written · **C** compiles (run named) · **S** runs in simulator · **V** visually reviewed by me · **F** functionally tested · **D** on real application state (not sample data). "—" = no.

### B1. iPhone app — redesign (branch `ios/lab` `679d8cae`; Lab only)
| Feature (design) | Files | W | C | S | V | F | D | Missing | Depends on | Next action |
|---|---|---|---|---|---|---|---|---|---|---|
| Navigation v1.2 r1.1 | `Shell/CyCradleDock.swift` | ✓ | ✓ | ✓ | ✓ | dock checks | ✓ | Train emblem not selected | owner | none |
| Profile v2.0 | `Shell/CyProfileV2.swift` | ✓ | ✓ | ✓ | structure | opening, themes | ✓ | visual approval; section pages reuse old editors | owner | review on phone |
| Themes ×6 | `DesignSystem/Theme*.swift` | ✓ | ✓ | ✓ | ✓ | switching | ✓ | persistence across relaunch not tested | — | add check |
| Plan v2.0 (B) | `Redesign/PlanScreenV2.swift`, `PlanV2Host.swift` | ✓ | ✓ | ✓ | this week | — | ✓ | all interactions untested; legacy editors behind it; Plan history "not available" | — | interaction checks |
| Onboarding 7 pages + Roster v3.4 | `Redesign/OnboardingV34.swift`, `AthleticRoster.swift` | ✓ | iOS 261 | — | — | — | ✓ | sport per session; rest-day reminder; stage; visuals of pages 1, 3–7 not approved | Lab 13 | read run |
| Training Hub compact panel | `Shell/CyTrainPanel.swift` | ✓ | ✓ | ✓ | ✓ | open/expand | ✓ | recovery shortcuts; sensor row | — | — |
| Strength recorder v1.4 | `Redesign/StrengthRecorderV14.swift` | ✓ | iOS 262 | ✓ | ✓ | reps ± only | ✓ | log→save not yet seen; preparation screen; substitution | Lab 15 | read run |
| Skips, timed, added, assisted, superset rest | same + `Strength.swift`, `NextSet.swift` | ✓ | iOS 265 | — | — | Linux rules only | ✓ | history does not show skip counts; export untested | Lab 15 | screen test |
| Review v1.4 (three optional sliders, optional pain) | `Redesign/ReviewV14.swift` | ✓ | iOS 265 | — | — | Linux rules only | ✓ | never seen running; rides still use the old check-in | — | add to journey test |
| Cycling v1.4 screen | `Redesign/CyclingRecorderV14.swift`, `CyclingReadout.swift` | ✓ | iOS 262 | — | — | — | simulated in Lab | not connected to the real recorder; no Map | safety gate | read Lab 15 |
| Progress hero | `Redesign/ProgressScreenV2.swift` | ✓ | ✓ | ✓ | ✓ | no-stage checks | analysis ✓; stage none | stage engine; v2.3 sections; Evolution details | stage criteria | — |
| Coach page + conversation + shadow policy | `Redesign/CoachTimelineV2.swift`, `CoachCenter.swift`, `CoachChat.swift`, `CoachShadow.swift` | ✓ | iOS 261 | — | — | Linux rules only | ✓ | hybrid proposals, FTP, rating prompt absent (defect A5-1); AI; fueling | Lab 13 | fix defect |
| Home v2.x | prototype only (`proto/ui-lab`) | — | — | — | — | — | — | whole screen | foundation stable | port after journeys |
| Preparation screen v1.4 | — | — | | | | | | whole screen | — | after journeys |

### B2. iPhone app — production (build 216 line) and safety
| Item | State | Evidence | Next action |
|---|---|---|---|
| Build 216 | Released to TestFlight earlier; protected baseline | `baseline/build-216` | none |
| Redesign switch off in production | Verified by unit test and by source | iOS 265 | keep |
| E1 safety fixes | Written; no fully verified commit | last full runs 243, 246, 248 failed; 252 cancelled; 258 compile-only passed | resume after merge decision |
| Open E1 items | Progress large-text bubble; Delete All Data definition; "Not saved" screen test; large-text truncation; ride-start tests; release accounting; phone check | dashboard | unchanged |
| Data export | Exists | `ProfileView.swift` | — |
| Data import / restore from export | **Does not exist** | source | decide if required |
| Arabic / localisation | **Does not exist** | source | decide scope |

### B3. Apple Watch, detachable watch, firmware, Android
| Component | Where | State | Next action |
|---|---|---|---|
| Apple Watch app | `ios/BikeComputerWatch` (8 files), in production target only | Existing; not part of Lab; not touched this week | none now |
| Detachable watch UI (LILYGO) | `watch/v3-poc` (170 commits, last 12 Nov) | Host tests passed (Watch run 61); never merged; not hardware-tested by me | preserve; separate workstream |
| Firmware | `firmware/` + `firmware/stage1-candidates`, `fw/phonefirst`, `esp32/phase-a` | Not touched; flashing not authorised | preserve |
| Android app | `android/` (22 files), `main` | Old; last run 26 Oct | retire or archive decision |
| Hardware handover docs | `docs/hardware-handover` (124 commits) | Documentation branch | preserve |

### B4. Shared services and integration
| Item | State |
|---|---|
| Athlete model | One (`Store`, `RiderProfile`). The redesign adds optional fields only. No second model found |
| Planner | One (`PlanEngine`, `StrengthPlanner`). Onboarding old and new share one approval path |
| Coach | Two older engines (`HybridCoach`, `AdaptationEngine`) plus the new shadow policy. Automatic increases held for approval |
| Sensors, GPS, HealthKit | Production only; compiled out or absent in Lab (checked in every run) |
| Cloud account | Code present in both builds; not configured in Lab |

### B5. End-to-end journeys
| Journey | Status |
|---|---|
| New athlete → onboarding → approved plan | Never completed in the redesign (test ran in the wrong order twice). Existing five-stage flow: last passed in older full runs, not since today's refactor |
| Existing athlete → edit goals → update plan | Not tested in the redesign |
| Plan → strength → save → review → Progress → Coach | Partly: reached the recorder (Lab 12). Save, review, Progress, Coach never executed |
| Plan → cycling → record → finish → save | Lab: demonstration only, not yet seen running. Production: existing Ride screen, GPS-route test fixed on E1 only |
| Missed workout → Plan update → Coach | Never tested in the redesign |
| Theme change → relaunch → kept | Switching passed; relaunch persistence not tested |
| Workout interrupted → restore → continue | Minimise/return written into the test; not yet executed. App kill and relaunch: not tested |
| Save failure → retry, no duplicate | Linux rule test passes; the "Not saved" screen has no screen test (also an open E1 item) |
| Export → delete → import → recover | Impossible: no import |

---

## C. CI and branch reconciliation

### C1. Workflows
| Workflow | Runs on | What it proves | What it does not | Finding |
|---|---|---|---|---|
| **iOS apps** (`ios.yml`) | push to `ios/**`; macOS | Production build + unit tests (compile mode, ~13–30 min), or full screen suite (~90 min) | Compile mode runs no screen test | Used in compile mode all day; full mode has not passed on E1 or ever run on Lab |
| **Cyclift Lab** (`lab.yml`) | push to `ios/lab`; macOS, 75-min limit | Lab build, isolation, screenshots, Lab journeys | Production behaviour | Never fully passed; 40–80 min each; one queued run is replaced by the next push |
| **Fast logic tests** (`logic.yml`) | Linux, 2–3 min | Pure rules (499 tests) | Any screen | Efficient; keep |
| Lab Apple identifier / signed build / TestFlight upload | `ios/lab`, specific files only | One-off setup; upload locked to `59e2f033` | — | Idle; correct |
| UI Lab prototype (`ui-lab.yml`) | `proto/**` | Old prototype app | — | **Run #5 queued since 11 Nov — stuck.** Workflow now redundant |
| Build APK, Android app | every non-iOS branch push | Android | — | **Runs on each new baseline or docs branch — wasted** |
| iOS compile check (`ios-check.yml`) | `ios-check/**` | Older compile check | — | Superseded by compile mode of iOS apps |
| Watch host tests, Firmware, App Store listing | their own branches | — | — | Idle |

### C2. Runs that matter now
| Run | ID | Commit | Status | Duration | Still relevant? |
|---|---|---|---|---|---|
| Lab 13 | 43920996524 | `4d7a48fd` | Running (queued 44 min, running since 22:25 Dubai) | 85+ min | Partly: lacks the Log set fix and record extensions |
| Lab 15 | 43929638567 | `679d8cae` | Queued behind 13 | — | Yes: current head |
| iOS 265 | 43929638595 | `679d8cae` | Passed (compile + unit) | 31 min | Yes |
| Logic 117 | 43929638581 | `679d8cae` | Passed, 499 tests | 3 min | Yes |
| iOS 264 | 43928882408 | `29599aa9` | **Failed — no machine was assigned; cancelled after 15 min.** Not a code failure | 18 min | Superseded by 265 |
| Lab 14, Lab 10 | 43928882780, 43907348491 | — | Cancelled by GitHub when a newer run was queued | — | Superseded |
| Lab 12 | 43914879601 | `2b9ec7c0` | Failed: 3 of 7 passed | 78 min | Evidence for the recorder opening |
| Lab 11 | 43910358119 | `0af9fa64` | Failed: 3 of 5 passed | 57 min | Evidence for panel, Hub, Progress, themes |
| iOS 258 | 43900899855 | E1 `33374d48` | Passed (compile + unit) | 17 min | Yes, for E1 |
| iOS 252 | 43858295217 | E1 `b0f6f70b` | Cancelled at 79 min; cause not established | — | Open question |
| UI Lab #5 | 43097844335 | `07ab9977` | Queued 5 days | — | Obsolete; cancelling it loses nothing (needs your approval) |

**Concurrency.** Lab and iOS runs are set never to cancel a *running* run, but GitHub keeps only one *queued* run per branch, so each new push replaces the waiting one. That cancelled Lab 10 and 14. Nothing useful was lost, because each later run contained the earlier work, but it means pushing often does not get results sooner.

### C3. Branches
| Branch | Head | Relation to `ios/lab` | Contains | Verdict |
|---|---|---|---|---|
| `ios/lab` | `679d8cae` | — | All redesign work | **Current development line** |
| `ios/e1-safety` | `33374d48` | 8 commits not in Lab; Lab has 47 it lacks | Plan 44-pt touch targets, Plan layout tests, GPS-route test fix, compile-only CI mode | **Integrate** — trial merge is clean; both edit `PlanWeekTimeline.swift`, `ios.yml`, `ci/build.sh` |
| `ios/ux1-foundation` | `8d2be12b` | Fully inside Lab | Theme system, navigation, Profile, Plan | Retire after confirmation |
| `ios/c0-coach` / `baseline/c0-coach-compiled-240` | `929bab28` | Same content, now in Lab as two re-applied commits | Policy foundation | Retire after confirmation |
| `fix/e1-held-validation`, `baseline/e1-run-235`, `baseline/lab-1`, `baseline/ux1-compiled-241` | — | Inside Lab | Fallback points | Preserve as fallbacks |
| `baseline/build-216`, `ios/checkpoint-f-ride` | `fb52ae27`, `4e2e9dc1` | Inside Lab | Production baseline and release head | **Preserve — protected** |
| `ios/e0-diag2`, `ios/e0-repro`, `ios/e0-diagnostic` | — | 1–2 diagnostic-only commits | Reproduction tests marked "not for release" | Preserve; do not integrate |
| `proto/ui-lab`, `-plan`, `-progress` (+ `-out`) | 13 Nov | Separate prototype app, 20–22 commits each | Home v2.1–2.3, Plan, Progress, Coach prototypes on sample data | **Reuse source, never merge.** Plan and Progress already ported; Home and the proposal sheet not yet |
| `watch/v3-poc`, `watch/w0-foundation` | 12 Nov, 8 Nov | Unrelated history | Detachable watch UI | Preserve; separate workstream |
| `firmware/stage1-candidates`, `fw/phonefirst`, `esp32/phase-a` | — | Unrelated | Firmware | Preserve; no flashing |
| `docs/cyclift-governance`, `docs/hardware-handover`, `ci-logs` | — | Documentation and logs | — | Keep |
| `ios/v1`, `ios/v1-ux`, `ios/rc3`, `ios/s2`, `impl/hub-reliability`, `ios/home-*`, `wip/*`, `ios/cyclift-*`, `ios/rc2-*`, `ios/coach`, `fix/coach`, `ios/quality`, `ios/dev`, `ios/phonefirst-dev`, `ios/rel-*`, `release/tf-b75a295`, `audit/onboarding`, `fix/*` (older), `asc-listing/*`, `ios-check/quality` | 26 Oct – 8 Nov | Older history that led to build 216 | Superseded development | *Hypothesis:* all contained in 216's history by content. Not verified branch by branch. Review before retiring; nothing found that is newer than Lab |
| `main`, `design/*` | 15–20 Oct | Android project | Old | Archive decision |

No uncommitted local changes exist in my working copy. No branch was found holding redesign work newer than `ios/lab`.

---

## D. Is the current plan the fastest safe route?

**The single-codebase, Lab-first structure is sound and is working as intended:** one athlete model, one planner, one switch, isolation verified on every run.

**The way I have been executing it is not the fastest safe route.** Since 20:00 I wrote ten areas in parallel and pushed after each, while no journey had passed and CI was queueing for machines. That produced a wide surface of compiled but unproven code, tests that failed for their own faults, and edits to production-shared code with no full regression behind them.

**Recommendation — reorganise the order, not the architecture:**
1. Freeze new features. Get the three journeys green, one push per batch.
2. Fix the Coach-card defect.
3. One approved full production regression on the Lab head.
4. Merge E1's 8 commits into Lab; run E1's gates from the single line.
5. Then resume: Home v2.x, preparation screen, Plan interactions — one area at a time, each closed with a passing journey before the next starts.
6. Housekeeping when convenient: cancel the stuck prototype run, stop Android builds on unrelated branches, repoint the default branch.
