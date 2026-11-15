# Cyclift — Independent Engineering and Product Audit

**15 Nov 2026 · Status: investigation complete to the limits stated in section G — stopped at the authorization gate.** Read-only: no production code, test, data, firmware, signing or distribution setting was changed. Nothing was executed by this audit; "executed evidence" means a recorded CI run.

Evidence classes used throughout: **[EX]** verified from executed evidence (recorded run) · **[SRC]** confirmed from source inspection (build 216 tree, commit `4e2e9dc`) · **[HYP]** reasoned hypothesis · **[DES]** design intent · **[UNK]** unknown or blocked.

## A. Findings

### A1. Root causes of the two failing tests

| | Finding | Class |
|---|---|---|
| Plan edit-and-apply | **My earlier hypothesis (a stuck "closing" flag) is wrong.** The screenshot saved at the failing assertion in run 221 shows the review after "Rebuilt without the routine": the change is **blocked by rule SPLIT-001 — "Labelled Full body but missing hip-dominant work (≥ 2 working sets each)"**, with "Your equipment isn't set yet, so this session uses bodyweight exercises only". The only choices offered are "Keep the session as planned" and "Set my equipment"; Apply is correctly disabled. | [EX] screenshot `run-221/layout/…applyenabled.png`; [SRC] `SessionRebuild.swift` 196, 304 |
| | So the planner's own rebuild of a full-body session for an athlete with no equipment produces a session its own validator rejects. This is a **product defect, not a test or sheet defect**: an athlete who chose "Not sure" for equipment (bodyweight until confirmed) cannot change the length of a full-body strength session. The test cannot pass because it expects a way forward that the app does not offer. | [EX]+[SRC]; why the rebuild omits hip-dominant work is [HYP] until reproduced in a unit test |
| | Cancel, repeated edits, stale plans, interruption: code paths exist (`discardProposal`, `repropose`, stale notice) but no executed evidence covers them. | [SRC] / [UNK] |
| Ride GPS samples | The recorder fills wall-clock gaps with empty "gap" samples (`phoneSecond`). `start()` stamps the clock; the test then calls `tick()` five times by hand. In run 221 the test took 7.1 s and the count was exactly 5 too many (10, then 11), while the assertions that every fix is kept (line 22) and that the saved record holds 5 route points (line 28) did not fail. | [EX] run 221 unit log; [SRC] `RideRecorder.swift` 172–180, 214–235 |
| | Conclusion: the count assertion depends on real elapsed time between `start()` and the first tick. **It is a time-dependent test, and no route sample was lost in the recorded run.** It is not "flaky" in an unexplained way: the cause is the recorder's use of the real clock with no injectable time. Dropped samples, filtering and save behaviour are not implicated by this evidence. | [EX]+[SRC]; not reproduced |
| | Backgrounding, lock, phone call, termination, relaunch, multiple recording devices: **no executed evidence exists.** The ride is held in memory until End. | [SRC] / [UNK] |

### A2. Problems discovered independently that were not identified by the owner or ChatGPT

| # | Problem | Evidence | User impact | Disposition |
|---|---|---|---|---|
| 1 | Planner and validator disagree for bodyweight-only athletes (root cause above) | [EX]+[SRC] | Dead end when editing a session; default onboarding path | **Fix (E1)** |
| 2 | **Build 216 was uploaded from a run in which two flow tests failed** — Plan edit and **Delete-all-data** — under an override whose recorded justification cites only the previous run's single Plan-edit failure | [EX] `run-216/flows.txt` (8 tests, 3 failures), `summary-release.txt` | The release record understates what was red; a privacy-relevant journey failed in the shipped build's own run (it passed in run 221) | **Fix process (E1):** an override must list its own run's failures |
| 3 | An unreadable store is treated as "no data": `read` returns nil, the app starts empty, and the next save overwrites the file. No backup copy is kept | [SRC] `Models.swift` 941, 1614–1630 | Possible total, unrecoverable loss after a corrupt or undecodable file (for example a failed migration) | **Fix (E1)** before any schema change |
| 4 | "Saved" does not depend on the write: saving is a side effect of changing state; a write error is stored in one variable shown only on a Profile data screen | [SRC] `Models.swift` 906, 1614–1623; `ProfileScreens.swift` 413 | The athlete can be told a workout is saved when the write failed | **Fix (E1)** |
| 5 | Every change rewrites the whole store, which contains all rides with one sample per second | [SRC] `Models.swift` 565, 1614 | Slower saves and more battery as history grows; larger window for write failure. Size not measured | **Measure (E2)**, then decide |
| 6 | A ride completes its planned session only if the planned day is today | [SRC] `Models.swift` 1363 | A ride saved after midnight, or imported from the BikeComputer the next day, leaves the planned ride "missed" | **Fix (E1)** |
| 7 | Three stored representations of age (`age`, `birthYear`, `dateOfBirth`) | [SRC] `Models.swift` 215–220; `HealthCheckView.swift` 107 | Zones can be computed from a stale value | Fix (E2) |
| 8 | The published unit log names 412 test results of 659 executed; only the failing ride test appears for its class | [EX] `run-221/test.txt` | Individual results of 247 tests cannot be confirmed from the record | Fix the log (E1) |
| 9 | Notification permission is requested at the moment a ride starts | [SRC] `RideRecorder.swift` 179 | A system prompt can appear as the athlete sets off | Redesign timing (U3) |
| 10 | No explicit file-protection class on the store | [SRC] (no occurrence) | Health-related data relies on the system default | Decide (E2) |
| 11 | Supersets already exist in the planning pipeline (10 tests passed); I had classed them as a new capability | [EX] `SupersetPipelineTests` | Scope was overstated | Corrected in tracker |
| 12 | `sports` defaults to road cycling for every athlete, including strength-only; `heightCm`, `gender`, `bikeName` have almost no readers | [SRC] | Orphaned data; a strength athlete "has" a cycling sport | Fix with the roster (U2) |
| 13 | Two different planned-session lengths appear across the approved drawings (30 and 35 min) and the default is 30 | [SRC] `OnboardingDraft.swift` 249; drawings | Cosmetic in design; no app impact | Reject (no action) |

Not found, within the scope examined: a path that fabricates measurements; a duplicate-ride path (ride id and board id are both checked, [SRC]); any generative-AI call.

### A3. ChatGPT's ten findings — challenged

| # | Finding | Verdict | Evidence and explanation | Impact | Correction |
|---|---|---|---|---|---|
| 1 | 17 functions verified mainly by journey evidence | **Confirmed — exactly 17** | Counted in the rev 2 tracker | "Verified" overstated | 15 downgraded; 2 kept where a named suite passed |
| 2 | 20 functions with weak acceptance criteria | **Confirmed, undercounted — I find 29** | Rows with "—", "Regression", "Unchanged" or similar | Not testable as written | 29 rewritten |
| 3 | HOM-03.2 and COA-07.2 misclassified as approved | **Partially confirmed** | The Coach timeline is an "approved design direction" in the Project Instructions, but no specification or drawing is approved | Would have entered scope | Reclassified "proposed" |
| 4 | 17 versus 14 new functions | **Confirmed** | 14 is correct; the PDF sent still says 17 | Minor | Superseded by this tracker (19 further functions added) |
| 5 | Broken formatting on page 2 of the rev 2 PDF | **Confirmed** | Rendered page 2: a paragraph was absorbed into a table row and the header repeated | Readability | This PDF's pages were inspected after export |
| 6 | Incomplete final-resolution visual inspection | **Confirmed** | I reported it then; G3 and G4 were not re-viewed after the last patch | Possible unseen drawing errors | No new drawings in this audit |
| 7 | Sports → Plan and Coach integration unverified | **Confirmed, and stronger** | `sports` is read by no engine; only the Profile picker touches it | The roster would have no effect today | Stated in contract C |
| 8 | Missing lifecycle and persistence evidence for training | **Confirmed for cycling; partly for strength** | Strength: one UI journey passed (start, log, finish, save, check-in, history); relaunch not exercised. Cycling: none | Unknown behaviour under interruption | Device and relaunch tests (E2) |
| 9 | Over-reliance on the existing inventory | **Confirmed** | 19 functions were missing | Incomplete scope | Added |
| 10 | Missing migration and rollback validation | **Confirmed, and stronger** | No fixture, no backup, unreadable store overwritten | Data-loss risk | E1 |

None is disproven. Where I differ: finding 2 is larger than stated; finding 7 and 10 are worse than stated.

### A4. Coach approval — every path that changes load
[SRC] `AdaptiveStore.applyAdaptation` (line 63): with `autoAdapt` (default on, also for older stores) every engine adjustment is applied, including increases (weight step, +1 rep, +1 set, +1 interval, longer ride). A second path, the planner rebuild, raises prescriptions when a session is regenerated (documented as P8, P10, P11 in the correction proposal). Larger changes already go through proposals. **Increases can bypass approval today.** The engine reads effort, performance, pain, missed and skipped sessions; it does not read sleep or HRV [SRC, keyword counts]. Whether each input changes the output correctly is covered by unit suites that passed in run 221 (AdaptationEngineTests 15, CoachRemediationTests 35, CoachCoreTests 16) [EX], but I did not map assertions to rules one by one [UNK].

## C. Cross-system data and behaviour contract (as the app is today)

| Input | Collected | Stored | Read by | Edited → effect | Approval | Missing → | Class |
|---|---|---|---|---|---|---|---|
| Name | Onboarding A; Profile | profile.name | Home, blueprint | immediate | no | Continue disabled | SRC |
| Birth date / age | Onboarding; Health check; Profile | three fields | HR zones | immediate | no | zones from other inputs or none | SRC — conflict |
| Weight | Onboarding; Profile; Health | weightKg + provenance | W/kg, loads | newer source wins | no | unknown, never defaulted | EX (HealthPrecedence, NoFabricatedDefaults) |
| Athlete type | Onboarding A | trainingMode | planner, goals, devices, Home | Profile: direct write, plan regenerates | **none today** | defaults to stored | SRC |
| Sports | Profile picker only | sports | **nothing** | none | no | defaults to road cycling | SRC |
| Priority | Onboarding A | priority | week proposal | direct | none today | balanced | SRC |
| Level | Onboarding A | level, strength experience | planner volume | direct | none | intermediate / beginner | SRC |
| Goals, main goal | Onboarding B | goals, primaryGoal | planner (one effective goal per sport) | direct | none | fitness | SRC |
| Week, lengths | Onboarding C; Profile | availability, minutes | planner, Home | Profile "Saved week": direct | none today | proposal | EX (OnboardingWeekTests) |
| Equipment | Onboarding C | equipment | strength planner, validator | direct | none | bodyweight (provisional) — triggers defect A2-1 | EX+SRC |
| FTP | Onboarding D; Profile; ride suggestion | ftp + source | targets | direct; suggestion needs confirmation | yes for suggestion | heart rate / effort | EX (FTPOwnership) |
| Session edit | Plan / session | proposal → plan version | Plan, Home | preview → apply → undo | **yes** | — | EX failing for bodyweight |
| Coach adjustment | Check-in | applied directly or proposal | plan | — | **only for large changes** | — | SRC |
| Strength log | Train | strength, activeSession | Progress, Coach | editable | no | empty session not saved | EX (EmptySession, journey) |
| Ride | Train | rides (with samples) | Progress, FTP, plan completion | delete only | no | gaps flagged, no interpolation | SRC; unit evidence incomplete |
| Review (effort, performance) | After strength | log | Coach | — | no | old path has defaults 7 / 6 | SRC |

**Scenarios.**  new strength-only, endurance-only and hybrid athletes — journeys passed [EX, general]. Unsupported sports — not selectable in onboarding today [SRC]. No sensors — values absent [EX partial]. Returning athlete / upgrade from 216 — tolerant decoding exists, **no test** [SRC/UNK]. Main-sport change — no concept today. Goal or availability change — direct write, no preview [SRC]. Pause and resume — reasons exist; hold tested in unit suites [EX general]. Several missed sessions — display only; engine counts them; no proposal flow [SRC]. Partial workout — saved as done sets [SRC]. Pain — engine reads it (68 references) [SRC]. Approve or reject a Coach proposal — exists for large changes [SRC].

## D. Risk register

| # | Risk | Sev. | Likelihood | Evidence | Mitigation | Blocks | Owner |
|---|---|---|---|---|---|---|---|
| R1 | Data loss from unreadable store | Critical | Low now; **high during any migration** | SRC | Keep copy, never overwrite, fixture tests | E2, all U | Data |
| R2 | "Saved" shown without confirmed write | High | Low | SRC | Save result surfaced at save time | U3 | Train |
| R3 | Plan increases without approval | High | Certain (default) | SRC | Approval gate, tests first | U builds | Coach |
| R4 | Session edit dead end (bodyweight) | High | Certain for unset equipment | EX | Align generator and validator | E1 | Plan |
| R5 | Ride lost on termination | High | Unknown | SRC | Checkpointing — behind safety gate | cycling minimise | Train |
| R6 | Release shipped over failing tests without full record | Medium | Happened once | EX | Override rule | every build | Release |
| R7 | Store rewrite cost grows with history | Medium | Unknown | SRC | Measure | E2 | Data |
| R8 | Planned ride not completed across midnight / late import | Medium | Occasional | SRC | Rule by planned day | E1 | Plan |
| R9 | Incomplete test record | Medium | Certain | EX | Full per-test log | E1 | Release |
| R10 | Approvals missing for U2–U4 | Medium | Certain | records | Decisions in F | U2+ | Owner |
| R11 | No device evidence for any recording behaviour | High | Certain | none exists | Device checklist | U3, cycling | Train |
| R12 | Age stored three ways | Low | Occasional | SRC | One source | E2 | Profile |

## E. Revised engineering and TestFlight plan
Changed from the previous plan for engineering reasons: (1) a diagnostic step comes first, because nothing has been executed since 11 Nov and root causes above still need reproduction; (2) data protection moves ahead of every model change; (3) navigation becomes the first UX build on its own, because it is the only fully approved baseline and touches no stored data; onboarding and Profile follow once their approvals and the model work exist.

| Step | Scope | Depends on / approvals | Components | Data | Tests | Success | Failure → rollback | Athlete sees | Not included | Build type |
|---|---|---|---|---|---|---|---|---|---|---|
| **E0 Diagnose** | Integration branch from `4e2e9dc`; rerun unit and flows unchanged; reproduce A1 in unit tests; export a build-216 store fixture; full per-test log | Decision F1 | CI config, tests only | none | existing + two reproductions | Both failures reproduced with stated cause | Cause not reproduced → stop and report | nothing | any fix | none |
| **E1 Integrity** | Generator/validator fix; injectable clock in recorder; store copy-before-write and unreadable-store handling; save result at save time; Coach approval gate with listed, undoable protective changes; planned-ride completion rule; override rule | E0; F2, F3 | SessionRebuild, StrengthPlanner, RideRecorder, Models, AdaptiveStore | one marker ("accepted as of update"); no schema break | failing tests pass **unmodified**; new tests written first; fixture round-trip | Full matrix green twice; fixture identical field by field | Any data difference → revert branch; build 216 untouched | Coach increases arrive as proposals; a failed save is said | redesign | Engineering |
| **E2 Model** | Additive fields (main sport, save state); single age source; onboarding stage mapping; store write-time measurement; strength restore after relaunch; device checklist for background, lock, call | E1; F4 | Models, OnboardingDraft | additive, defaulted; forward-only (see below) | migration, interrupted-migration, relaunch | Fixture migrates and reopens; interrupted write leaves old file | Restore the kept copy | nothing new | UI | Engineering |
| **U1 Navigation** | Dock v1.2 on every tab; avatar opens the existing Profile; Ride route kept; temporary mark | E1; F5 | ContentView, ProfileTabView, UI tests | none | hub reliability, all journeys, small device, large text | All journeys pass; nothing unreachable | Feature flag back to old dock | New dock; same pages | new Profile, onboarding | **Integrated UX** |
| **U2 Athlete setup** | Onboarding seven pages with roster; Profile six sections; shared editors; Profile changes through preview | E2; F6, F7 | OnboardingView, ProfileEditors, ProfileSections | uses E2 fields | three journeys adapted; resume on each page; function map | No stored value lost; unsupported sports never planned | Flag to old onboarding | New setup and Profile | Train, Plan redesign | Integrated UX |
| **U3 Train (strength)** | Panel, selector, recorder, minimise for strength, finish, save states, review; notification timing | U1, E1 | TrainingHubView, StrengthWorkout | none | strength journey; minimise/restore; relaunch | No duplicate session | Flag | New Train | cycling layouts, recovery | Integrated UX |
| **U4 Plan, Progress, Home** | Plan v2.0; Progress hero without stages; Home per decision | U1; F8, F9 | PlanView, ProgressView, HomeView | linked replacement if approved | edit/apply/undo; lab defects closed | Spec criteria | Flag | New Plan and Progress | stages | Integrated UX |

**Migration limits to accept:** additive fields are **forward-only** — an older binary reading a newer store ignores unknown fields and, on its next save, drops them. Reinstalling an older build does not restore older data; only the kept copy does. No interrupted-migration behaviour is verified today.

## F. Decision register — only what needs you

| # | Question | Recommendation | Trade-off |
|---|---|---|---|
| F1 | Authorize E0: run the existing tests again on a new branch (no app change, no upload) | **Yes** | Uses CI time; writes run logs to the logs branch |
| F2 | Bodyweight full-body edits: fix the generator so the session passes, or relax the rule for provisional equipment? | **Fix the generator**; never relax a safety rule to pass a test | Slightly more work |
| F3 | Protective reductions stay automatic if listed with reason and Undo | **Yes** | Athlete sees changes after the fact |
| F4 | Additive stored fields; older builds cannot read them back | **Yes**, with the kept copy | Rollback restores the copy, not later data |
| F5 | Temporary Train mark | **Yes**, labelled temporary | — |
| F6 | Visuals of onboarding pages 1, 3–7 and Profile v2.0 | Needed before U2 | — |
| F7 | May indoor cycling, mountain bike or bodyweight be a main sport? | **Yes, as labels**; planner unchanged | Label without separate planning |
| F8 | Plan specification v0.6 as build reference | Needed before U4 | — |
| F9 | Home: v2.3 sign-off or keep production | **Keep production** until v2.3 is verified | Older Home inside the new dock |
| F10 | Split ride samples out of the single store file | Decide after the E2 measurement | Larger change if needed |

## G. Verification ledger

| Item | Evidence |
|---|---|
| Source inspected | Branch `ios/checkpoint-f-ride`, commit `4e2e9dc` — Models, RideRecorder, SessionRebuild, SessionChangePreview, StrengthWorkout (edit sheet), AdaptiveStore, OnboardingView, OnboardingDraft, ProfileEditors, ContentView, RideHealthExport; UI test `PlanEditPreviewApplyTests`; unit test `RideRegressionTests`; workflow `ios.yml` |
| Executed evidence used | Run 221 (43013897973, 11 Nov 11:40 UTC): unit 659 executed, 2 assertion failures in 1 test; flows 8 tests, 1 test failing (4 assertions); journeys 3 passed; smoke 3 passed. Run 216 (42786480539): flows 8 tests, 2 tests failing; upload succeeded |
| Named suites passed in run 221 (from the log) | OnboardingWeekTests 4 · OnboardingAnswersMappingTests 6 · NoFabricatedDefaultsTests 6 · HealthPrecedenceTests 5 · FTPOwnershipTests 3 · EmptyStrengthSessionTests 9 · SupersetPipelineTests 10 · AdaptationEngineTests 15 · CoachCoreTests 16 · CoachRemediationTests 35 · HybridTests 11 · HybridV2Tests 17 · DataIntegrityGapTests 4 · and others (412 named results) |
| Screenshot evidence | `ci-logs: ios/run-221/layout/flows-FAIL-…-applyenabled.png` (viewed) |
| Not executed by this audit | Everything. No simulator, device or CI run was started |
| Unverified | Per-rule correctness of the Coach; all interruption behaviour; migration; store write time; Apple Watch, BikeComputer and sensor behaviour; 247 unit results not named in the log; App Store Connect state |
| Limits | No macOS or device here; I read the central files, not all 24,600 lines; the function inventory was rebuilt from file and test names plus targeted reading, not a line-by-line trace |
| Exported PDF | Pages inspected after export (see chat report) |

## The nine answers
1. **Working** [EX]: onboarding to first plan for the three athlete types; strength start-log-finish-save-check-in-history; hub open and close; week proposal and feasibility; FTP ownership; no fabricated defaults; empty strength session not saved; Health precedence.
2. **Broken**: session edit for athletes without equipment; increases applied without approval; a failed save not shown at save time; unreadable store overwritten; planned ride not completed across midnight or late import; the release override record.
3. **Missing**: roster and capability table; main sport; new navigation, Training Hub, Plan, Progress; Coach timeline; recovery recording; in-progress ride persistence; migration tests; any device evidence.
4. **Wrongly classified (by me)**: 15 functions as verified on journey evidence; 14 on test-file or inspection evidence; supersets as a new capability; Coach timeline as approved. "Implemented and verified" falls from 38 to 9 of 209.
5. **Unverified**: everything under interruption; migration; per-rule Coach behaviour; devices.
6. **Discovered independently**: section A2 (13 items), led by the real cause of the Plan-edit failure, the build-216 override, and the unreadable-store overwrite.
7. **Before the next TestFlight build**: E0 and E1.
8. **Can wait**: all redesigned screens, cycling minimise, recovery, stages, themes.
9. **First**: E0 — rerun and reproduce — because two root causes rest on one screenshot and one log, and nothing has been executed for four days.
