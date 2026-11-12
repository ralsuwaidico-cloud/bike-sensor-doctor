# Home v2.2 — change log and verification record (UI Lab prototype)

Date: 12 Nov 2026 · Source: owner's "Home v2.2 — Consolidated Owner Review and UI Lab Revision".
Scope: **design prototype only**, in the existing isolated workspace (branch `proto/ui-lab`, app `CycliftUILab`).
Nothing here is integrated into the Cyclift app and nothing is owner-approved.

## 1. Isolation — what was and was not touched

| Item | Touched? |
|---|---|
| Production iOS code, release branch (`ios/checkpoint-f-ride`), production tests, production CI workflow | No |
| TestFlight / release pipeline | No — no upload of any kind |
| Defect 6 validation work | No |
| Training engines, coaching logic, onboarding | No |
| Apple Watch app, detachable Watch firmware | No |
| Adaptive Lifestyle Coach planning documents | No |
| New prototype project | No — the existing UI Lab was continued and its components reused |

Only the "UI Lab prototype" workflow ran on the prototype pushes.

## 2. Changes from v2.1 to v2.2

| Area | v2.1 | v2.2 |
|---|---|---|
| Consistency | Ring with percentage | Unchanged |
| Training Mix — centre | The word "Mix" | Ratio of **completed training time**, endurance : strength (sample: 66:34). 100:0 / 0:100 for one discipline. "—" when nothing is completed |
| Training Mix — rings | Completed ÷ planned per discipline | Unchanged; the sheet now explains that rings and centre are different measurements and shows the planned split |
| Recovery | Heart inside three availability arcs | Heart and arcs removed. Single ring with a percentage (**sample data, marked**) — or a status word, "Partial data", or "Awaiting data" with no number |
| Schedule | Session icons inside circles (overlapping on two-session days), ticks | One icon per session, no circles, with a state mark beneath: filled dot (completed), hollow dot (planned), cross (missed), arrow (rescheduled); moon for rest |
| Sport cards | Compact, no sparklines | Unchanged |
| Sleep | Bar with target | Larger "last night" value; 7-day average and target labelled; sheet separates last night / average / target / recommendation |
| Coach | One sentence + actions | Observation → recommendation → Review / Not now, with Why? |
| Trends | Stacked bar chart | **Interactive multi-series line graph** — three views, 7 days / 4 weeks, tap and drag selection, vertical guide, value panel, series switching, gaps for missing data, daily sheet, methodology sheet |
| Key metrics | Rows or grid (switch) | Rows only (approved direction); chevrons; weekly load in RPE×min |
| Getting Started | Conditional placement | Unchanged; now verified by a test |
| Dock | Floating | Unchanged; verified not to cover the final rows |
| Tests | None | 22 automated interaction tests (prototype only) |

Decisions I made that were not spelled out in the instruction (please confirm or change):
1. **4-week view uses 7-day rolling totals** for training load and minutes (units "RPE×min/7d", "min/7d"). Daily values
   with rest days at zero drew an unreadable sawtooth over 28 days. Recovery, resting HR, HRV and sleep stay daily.
2. **"7 days" means the last seven days** (Thu–Wed in the sample), not the calendar week, so the graph is never mostly empty mid-week.
3. **Scrubbing is a horizontal drag**; a vertical swipe over the graph scrolls the page.
4. Recovery captions: "Sample score" (numeric), the status word (qualitative), "Partial data", "Awaiting data".

## 3. Documented prototype formulas (everything else is literal sample data)

| Value | Formula | Status |
|---|---|---|
| Mix centre ratio | endurance minutes ÷ (endurance + strength minutes), rounded to a whole percent; strength = 100 − that. No completed minutes → no ratio | Prototype formula over sample minutes (77 and 40 → 66:34). Recomputed independently by test 02 |
| Mix planned ratio (sheet) | Same formula over planned minutes | Prototype formula |
| Ring fractions | completed ÷ planned per discipline | As v2.1 |
| 4-week load / minutes | Sum of the day and the six days before it | Prototype formula over sample days |
| Weekly load | Σ session effort × minutes (existing engine definition) | Sample number, existing production method |
| Recovery percentage | **None** — literal sample numbers | Must not be produced in the app without an approved, validated method |
| Sleep average | Mean of recorded nights | Sample number |

## 4. Status of each part — what kind of evidence exists

| Part | Visually implemented (screenshot) | Interaction-tested (simulator) | Data | Production calculation exists? | Needs before production |
|---|---|---|---|---|---|
| Consistency ring | Yes | T01 | Sample | Yes (adherence) | Integration |
| Mix rings | Yes | T01 | Sample | Yes (week totals) | Mapping |
| Mix centre ratio | Yes | T02, T03 | Sample + prototype formula | Inputs yes; the ratio itself no | Small new calculation |
| Recovery — status word / partial / awaiting | Yes | T05, T06 | Sample | Yes (qualitative recovery wording) | Mapping |
| Recovery — percentage | Yes | T04 | **Sample only** | **No** | **Scientific validation + owner approval** |
| Schedule marks | Yes | T07 | Sample | Yes | Mapping |
| Sport cards | Yes | Not tested (unchanged) | Sample | Yes | Integration |
| Sleep bar | Yes | T08 | Sample | Readings yes; user target no | Target setting |
| Coach card | Yes | T09, T10 | Sample | Yes (rule-based coach) | Mapping of observation / recommendation |
| Graph — load, minutes, RHR, HRV, sleep | Yes | T11–T16 | Sample | Underlying data yes; per-day series builder no | Mapping / calculation |
| Graph — recovery % | Yes | T11 | **Sample only** | **No** | **Validation** |
| Key metric rows | Yes | T17 | Sample | Yes | Mapping |
| Getting Started placement | Yes | T20 | Sample | Yes (setup steps) | Integration |
| Floating dock | Yes | T18, T19 | — | Tab bar exists | Home v2 Stage B decision |
| Large text | Yes | T21 | — | — | Real-device check |
| Loading | Yes | T22 | — | — | — |

## 5. Verification actually performed

All on GitHub-hosted macOS (Xcode 26.6), iOS 26.5 Simulator, iPhone 17 and iPhone SE (3rd generation).

| Check | Result |
|---|---|
| Token contrast check | 6 themes, 294 pairs, 0 failures, lowest text ratio 4.79 |
| Prototype build | Succeeded (7 warnings) |
| Interaction tests — run 43204124295 (commit e72a9a0) | iPhone 17: **22 of 22 passed**. iPhone SE: **20 of 22 passed, 2 failed** |
| Screenshots | 107 screens + 22 full-length images |

**Interaction tests are not a clean pass.** Across the last two full runs every one of the 22 tests passed on both
simulators at least once, but no single run was green on both:

| Run | iPhone 17 | iPhone SE |
|---|---|---|
| 43190660048 (387bd10) | 20 / 22 — failed T07 (a day sheet still on screen 6 s after Close), T11 (wait expired although the value was correct) | 22 / 22 |
| 43204124295 (e72a9a0) | 22 / 22 | 20 / 22 — failed T01 (Recovery sheet did not open after the Mix sheet was closed), T17 ("Timed out while evaluating UI query") |

Reading: the failures move between simulators and tests from run to run and involve opening or closing sheets on a
slow shared simulator, which points to test-timing instability. That is an inference, not a demonstrated cause: an
intermittent real defect (a tap made immediately after a sheet closes being ignored) is not excluded. It stays an
**open item**. No assertion was weakened to obtain a pass.

One real prototype defect was found and fixed by the tests: in the first v2.2 build a vertical swipe starting on the
graph did not always scroll the page. The graph's touch handling was rebuilt to claim horizontal drags only; T13 has
passed on both simulators in every run since.

Evidence files: `docs/evidence/interaction-tests-run-43204124295.txt`; screenshots on branch `proto/ui-lab-out`.

## 6. Not verified

- Nothing was run on a physical iPhone. Touch feel, scrubbing comfort, legibility outdoors and one-handed reach are untested.
- VoiceOver was not exercised; labels and values exist and are read by the tests, which is not the same as a VoiceOver review.
- Sport-card taps, theme switching and the optional-steps list were not interaction-tested (screenshots only).
- The full-length images are produced by an image renderer, not by scrolling a device; ring arcs can start at a different angle there.
- A passing prototype test says nothing about the production app.

## 7. Open questions for the owner

1. 4-week view: keep 7-day rolling totals for load and minutes, or show daily values / weekly bars?
2. "7 days": last seven days (current) or the calendar week?
3. Recovery percentage: the prototype shows it as marked sample data. Should production plan for the qualitative ring as the launch state?
4. Two-session days on iPhone SE: is the pair of icons legible enough?
5. Sleep target: introduce a user-set target, or drop the target until one exists?

## 8. Stop point

Work stops here. Plan, Training Hub, Progress, Profile and Onboarding are not started. No TestFlight upload. No production integration.
