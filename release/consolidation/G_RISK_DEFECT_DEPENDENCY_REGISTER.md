# G — Risk, Defect and Dependency Register

**Version:** 0.1 · 15 Nov 2026 · **Status:** Audit and plan — **Pending Owner Approval**. Read-only audit; nothing changed. "Today" = build 216 source (commit `4e2e9dc`), read, not run in this audit. Nothing was repaired.

## 1. The eight blockers
| # | Blocker | Severity | Evidence | Affected | Proposed solution | Test strategy |
|---|---|---|---|---|---|---|
| 1 | Plan edit-and-apply fails | High | Run 221 flows: `PlanEditPreviewApplyTests` — "Apply is enabled once the review has no blocking conflict" failed, then three dependent assertions. Passed neither in runs 217–221. **Cause not confirmed.** Hypotheses from the source: (a) the review keeps a `closing` flag set by Cancel; the test cancels first, and if the same view state is reused Apply stays disabled; (b) the seeded session remains blocked after the offered alternatives | Editing a planned session; change history; undo | Simulator diagnostic first; then smallest fix; if (b), a product decision on a session with no applicable alternative | The existing test, unmodified; add a cancel-then-apply unit test |
| 2 | Ride GPS-route sample test fails | Medium (data-loss risk appears low) | Run 221 unit: expected 5 samples, got 10; then 6 vs 11. The assertions that every fix is kept and that the saved record has 5 route points did **not** fail. The recorder fills wall-clock gaps with empty "gap" samples; the test ticks by hand and took 7 s, so gaps were inserted. Passed in run 216. **Likely timing sensitivity, not route loss — unconfirmed** | Ride sample count on slow devices; none seen in saved routes | Give the recorder an injectable clock; keep assertions | Deterministic clock test; a real 10-minute ride on a device comparing seconds and samples |
| 3 | Cycling minimise and persistence | High (blocked) | The ride lives in memory (`RideRecorder.samples`); background recording relies on location mode; nothing is written until End | Any ride ended by termination | Periodic checkpoint and recovery, behind the safety gate; not in these releases | Gate document; device tests: lock, background, call, termination |
| 4 | Save integrity | High | `persist()` writes the whole store atomically and keeps an error in `lastSaveError` only; duplicates prevented by ride id and board id; Health export marked once | Every save | Result type recorded/pending/confirmed/failed/unknown; show and retry | Fault-injection tests compiled out of release builds |
| 5 | Coach approval | High | `applyAdaptation`: with `autoAdapt` (default on) every adjustment is applied — weight step, +1 rep, +1 set, +1 interval, longer ride. A second path (planner rebuild) raises loads (P8, P10, P11 in the proposal) | Plan, trust | The pending correction proposal; tests first | One test per increase: not applied without approval; applied history untouched |
| 6 | Progress proof of concept | Medium | Lab run 43472777501: 5 of 8 (standard), 6 of 8 (small). Open: single accessible element for the track, duplicated element under Reduce Motion, header hit testing | Progress M5 | Fix in the lab branch before promotion | The eight lab tests on both sizes, twice |
| 7 | Shared onboarding/Profile editors | Medium | `AthleteTypeEditor`, `GoalCardsEditor`, `WeekBuilder` serve both; all write through `OnboardingAnswers.apply`; Profile edits apply directly | M2 | Keep one mapping; new views over it; Profile edits become proposals | Onboarding journeys; Profile edit → preview → undo |
| 8 | Navigation ownership | Medium | Five pages kept alive (0 Home, 1 Plan, 2 Ride, 3 Progress, 4 Profile); hub overlay; five sheet presenters in `ContentView`; tests address `centreButton` | M3 | One session owner; keep the Ride page route; migrate identifiers with the tests | Hub reliability tests; all journeys; double-tap |

## 2. Other risks
| Risk | Level | Note |
|---|---|---|
| Missing approvals gate M2, M4, M5 | High | Document H |
| Migration without a build-216 fixture | High | M0/M1 |
| Design drawn, never run: every "approved" screen | Medium | simulator and device evidence per milestone |
| Accessibility: large text in Plan; Progress track | Medium | per milestone |
| Themes: production tokens differ from the six-theme set | Medium | no migration now |
| Delete-all-data journey failed once (run 216), passed in 221 | Low | watch for recurrence |
| Physical-device evidence | Medium | none gathered in this audit; simulator results are not device results |
| Unverified "Cyclift Watch" card in Devices | Low | hide in M2 |
| TestFlight tester membership | Unknown | cannot be checked from here |

## 3. Pending decisions
Emblem · Home design · Profile visuals · onboarding pages 1 and 3–7 · Plan specification · stage rules · whether a shared-recorder sport may be main · Intensity storage · linked replacement for missed sessions.
