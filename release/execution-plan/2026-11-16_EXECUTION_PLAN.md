# Cyclift — execution plan under the controlled accelerated directive

Status: **Plan for owner review** · 16 Nov 2026 · answers section 10 of the directive of 16 Nov.
Authorized now: E1 safety work on `ios/e1-safety`; isolated UX1 preparation (theme system, navigation, shared components).
Not authorized: merging UX1, protected-branch changes, TestFlight uploads, firmware, activating AI features.

Evidence words: **simulator-tested** means executed in CI on the commit named. Nothing here is physical-device evidence.

## 1. Current E1 state

**Protected reference points (now preserved as named branches that nothing builds on):**

| Reference | Commit | What it is |
|---|---|---|
| `baseline/build-216` | `fb52ae27` | The commit TestFlight build 216 was made from |
| E0 audited commit | `4e2e9dc1` | Release line audited in E0; E1 branched from it |
| `baseline/e1-run-235` | `a017ed6d` | Last E1 commit with every test job green (run 235). Does not contain the 16 Nov ride-start work |
| E1 candidate | `a6ded926` | Ride-start policy, external-ride marker, location gate, contract tests. Run 236: compiled; 2 test failures |
| E1 head | `b167f514` | Same product code as `a6ded926` plus diagnostics in the two failing tests. Run 237 in progress |

There is **no fully verified E1 commit that contains all approved safety work**. `a017ed6d` is the fallback.

**Cleared on `a6ded926` (simulator-tested, run 236):** one ride-start policy read from the athlete record and failing closed; external BikeComputer rides during a hold kept, marked, completing nothing; location gate for phone rides; failed-save, retry and session-matching contracts; backup and recovery cases; correct unit counts.

**Remaining E1 tasks, in order:**

| # | Task | Size | Verifiable on |
|---|---|---|---|
| 1 | Explain and resolve the two failing tests (ride stall timing; plan-edit slider) | Unknown until run 237 reports | iOS |
| 2 | Delete-all coverage for temporary exports and diagnostic data | Small | Linux + iOS |
| 3 | Screen test for the "Not saved" state | Small | iOS |
| 4 | Largest-text clipping on Home, Profile, Plan | Medium, layout only | iOS screenshots |
| 5 | Truncation check in the layout audit (not only overlap) | Medium | iOS |
| 6 | Screen-level tests for the four start routes and the restriction notices | Medium | iOS |
| 7 | Release accounting, then the E1 evidence report | Small | Document |
| 8 | Physical-device check of E1 (owner's iPhone, Apple Watch, BikeComputer) | Needs an authorized build | Device |

Item 8 cannot happen without a build on a phone. The E1 evidence report will request that separately.

**Existing tests on `a6ded926`:** 724 unit, 26 smoke, 8 flows, 3 journeys, 7 layout tests (202 screenshots), 6 watch screenshots; 426 run on Linux. **Known failures:** the two in row 1. **Known gaps:** build-216 fixture tests run only on Linux; the permission prompt is not screen-tested.

**Recovery if a change regresses:** every E1 change is one commit and is reverted on its own; fall back to `baseline/e1-run-235`; testers stay on build 216, which is untouched. Athlete data: the app keeps one previous copy and an older-schema copy and never overwrites an unreadable file. One stated limit: if build 216 is reinstalled over a newer build and saves, it drops fields it does not know, including the external-ride marker.

## 2. UX1 branch structure and isolation

- One branch, `ios/ux1-foundation`, created from the E1 candidate. It is pushed only when it has content, with quick-scope CI, so it does not occupy the runners E1 needs.
- UX1 **adds new files only** until Checkpoint 1 passes. It does not edit `Models.swift`, `RideRecorder.swift`, `StoreRecovery.swift`, `ContentView.swift` or any athlete-data type. Those belong to E1.
- Nothing from UX1 is reachable in the app until its gate: new screens sit behind the existing release flags, off by default.
- Later work branches from it (`ios/ux1-athlete` for onboarding and Profile, `ios/ux-train`, `ios/ux-plan`) once the foundation contract is stable. Coach foundation is separate: `ios/c0-coach`, new files, shadow mode.
- UX1 is rebased onto E1 once E1 is green. E1 never takes commits from UX1.
- Ownership and shared contracts are kept in the dashboard (sections 2 and 3).

## 3. Six themes: approach

**What exists today (verified in the code):** three colour systems side by side — the older `BC` set (used in 41 files), the newer `CyTheme` light/dark set (18 files), and 17 places with hard-coded colours. The six themes exist only in the UI Lab prototype. Production has no theme choice.

**Approach — one engine, six data sets:**

1. One list of semantic tokens (background, surfaces, three text levels, border, accent, discipline colours, status colours, chart and ring colours, interactive states). Screens ask for a token by meaning, never for a colour.
2. Six theme definitions that are data only. No screen has per-theme code.
3. One theme store: holds the choice, persists it, and publishes changes so every screen redraws.
4. The existing `CyTheme` and `BC` names are kept and re-pointed at the current theme, so the 59 files that use them adopt themes without being rewritten. The 17 hard-coded sites are replaced one by one.
5. The choice is saved as an app preference, **not** in the athlete record, so the athlete-data format does not change and build-216 rollback is unaffected. Delete-all-data resets it.
6. Each theme declares whether it is light or dark. A change of the phone's appearance does not change the chosen theme.
7. Layout uses leading/trailing and tokens carry no direction, so Arabic and RTL can be added without touching the engine.
8. Selection lives at Profile → Preferences.

**Tests:** a contrast test over every text/surface pair in all six themes (runs on Linux in seconds); persistence after relaunch; a screenshot matrix of key screens × six themes at standard and largest text; the dock in every theme.

**Missing decisions, flagged rather than guessed:**

- The six token tables in the brand book are **prototype values**. They need your approval before they become production tokens. I will present them as rendered screens, not hex codes.
- Discipline colours disagree across the three systems (strength is purple, rose or amber depending on the source). One set must be chosen; an impact note already exists.
- Whether a "match the phone's light/dark setting" option is wanted in addition to the six fixed themes.
- Power-zone colours per theme are not defined anywhere.

## 4. Critical dependencies per checkpoint

| Checkpoint | Depends on |
|---|---|
| 1 · E1 | Run 237 findings; rows 2–7 above; a green full run on one commit; your approval for a device build |
| 2 · Theme, navigation, onboarding, Profile | Checkpoint 1 (navigation edits the file that hosts the recovery screen); approval of theme tokens and discipline colours; **visuals for onboarding pages 1 and 3–7 and for Profile are not yet approved**; Train emblem still pending (a placeholder is used and labelled) |
| 3 · Training Hub, strength, Plan | Checkpoint 2 components; the E1 save contract; Plan integration design (direction approved, detail pending); the cycling-minimise safety gate in Hub v1.4 |
| 4 · Coach, Progress, Home | Policy engine with **your approved limits** for a "small" step and the protective allowlist; decision ledger; Progress stage criteria; Home redesign is not approved — only approved Home changes go in |
| 5 · Integrated beta | All of the above; physical-device sessions; no open release blocker |

## 5. Tests

**Automated:** Linux logic tests on every push (about 10 minutes); quick iOS scope for UX branches; full iOS scope on E1 and at each checkpoint — unit, smoke, flows, journeys, layout on four phone sizes, watch. Added per checkpoint: theme contrast and screenshot matrix (2), Hub and strength journeys (3), policy-engine tables and "no automatic increase without approval" (4), full regression plus build-216 data fixtures (5).

**Physical device (needs you and an authorized build):** install over build 216 with your real data and confirm nothing is lost; a real outdoor ride with phone GPS; a BikeComputer ride including a disconnect; a ride started from the Apple Watch; a strength session in the gym; denying then granting location; largest text and each theme outdoors; airplane mode; a failed save. I will not label anything device-tested until this has happened.

## 6. Schedule

**Throughput measured, not assumed:** a full iOS run takes about 1 h 30 min (runs 235 and 236). Runs on one branch queue rather than cancel. That allows roughly four to six meaningful full runs a day, and each failed run costs most of two hours.

**My assessment of the six weeks — two changes to the critical path:**

1. **Start the Coach foundation now, not in Week 4.** The policy engine and decision ledger are pure logic, live in new files and are tested on Linux in minutes. They are the highest-risk item and depend on your limits; leaving them to Week 4 puts the largest unknown late.
2. **Week 2 is overloaded as written.** Theme engine, navigation, onboarding and Profile in one week is not realistic when onboarding and Profile visuals are not yet approved. Theme engine and navigation fit in Week 2; onboarding and Profile run into Week 3.

| Week | Target | Gate |
|---|---|---|
| 1 | E1 complete; theme engine and Coach policy engine started as new files | Checkpoint 1; E1 device build if you approve |
| 2 | Theme engine in all existing screens; navigation v1.2 rev 1.1; shared components | Theme and navigation half of Checkpoint 2 |
| 3 | Onboarding v3.4 and Profile v2.0; Training Hub v1.4 started | Checkpoint 2 |
| 4 | Training Hub, strength logging, schedule-first Plan; Coach engine and ledger complete in shadow mode | Checkpoint 3 |
| 5 | Coach timeline and conversation screen, fueling guidance, Progress, approved Home changes | Checkpoint 4 |
| 6 | Integration, device testing, repair | Checkpoint 5 |

**Honest estimate:** six weeks is achievable for an integrated beta if the approvals in section 8 arrive in the week they are needed and Week 6 device testing finds only minor defects. With a round of design changes or a serious device finding, eight weeks is more likely. Safety items do not move to fit the date.

## 7. Risks that could delay the beta

1. Pending design approvals (onboarding pages, Profile visuals, theme tokens, Plan detail). Largest schedule risk.
2. Coach limits and allowlist not decided — automatic progression stays held until they are.
3. The Coach conversation needs an AI model. None is authorized. Without one, the screen ships with rules-based guidance, labelled as such.
4. No physical-device evidence exists for anything since build 216. Device testing may surface defects simulators cannot.
5. CI time: one failed full run costs about two hours; intermittent screen tests (such as plan-edit) multiply that.
6. Re-pointing two colour systems across 59 files can cause visual regressions; the screenshot matrix is the control.
7. Largest-text fixes touch Home, Profile and Plan, which UX1 also restyles — they are done in E1 first to avoid doing them twice.
8. Shared files (`ContentView`, `Models`) are edited by several streams after Checkpoint 1; one stream at a time.

## 8. Decisions that need you

| # | Decision | Needed by |
|---|---|---|
| 1 | A build on your phone for E1 device testing (requested after the E1 evidence report) | End of Week 1 |
| 2 | Theme token values and one set of discipline colours (shown as screens) | Start of Week 2 |
| 3 | "Match phone appearance" option: yes or no | Start of Week 2 |
| 4 | Visuals for onboarding pages 1 and 3–7 and for Profile | During Week 2 |
| 5 | Limits for an automatic "small" step; protective allowlist; fueling rules | Week 2, to keep Week 4 |
| 6 | AI model for the Coach: whether, which, and what athlete data may be sent | Before Week 5 |
| 7 | Home: which changes are approved; whether the quick menu is retired | Before Week 5 |
| 8 | Each merge into a protected branch and each TestFlight upload | At each checkpoint |

Everything else is ordinary implementation and will not be brought to you.
