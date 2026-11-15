# Onboarding v2.0 + Profile v2.0 — Current-state audit and field matrix

**Version:** 0.1 · 15 Nov 2026 · **Status:** Current Draft — for owner review · read-only audit; **no code changed, built or run**
**Evidence:** branch `impl/checkpoint-f-ride`, commit `4e2e9dc`, `ios/BikeComputer`. File and line references are to that commit. "As read" = read in source, not verified by running. No test was run for this audit.

## 1. What onboarding is today (PROVEN, as read)
`OnboardingView.swift` — "onboarding v3": a Welcome page and **five** stages (`static let stages = 5`, titles line 19).
| Stage | Asks | Required to continue | Validation (as read) |
|---|---|---|---|
| Welcome | nothing; "Get started" sets `guest = true` | — | — |
| A · Who you are | name; training type (Cycling / Strength / Hybrid Athlete cards); cycling experience; strength experience; priority (hybrid only); date of birth; weight (Apple Health value offered, never applied silently) | name not empty **and** a type chosen (`canContinue`, case 1) | date of birth and weight optional and clearable; no height; no units |
| B · Your goals | any of ten goals grouped Cycling / Strength / General by type; one main (★) | at least one goal | — |
| C · Your week | seven day cells (ride / lift / both / rest); ride length 20–300 min step 10; strength length 15–120 min step 5; two-a-day (hybrid); equipment preset Gym / Home / Bodyweight / Not sure; supersets | blocked only when there is no training day, or hybrid has no ride day or no lift day (`OnboardingWeek.feasibility`) | other findings are notes, never blocks |
| D · Your ecosystem | device cards (only actions that work); FTP "Don't know / I know it" (cycling types) | nothing; Skip offered | FTP accepted only as 50–600 W, else stays Unknown |
| E · Your training system | preview = dry run of the real planner (`PlanEngine.week`); "Edit week" / "Approve plan" | — | — |

**Saving and resume.** Every change calls `commit()` (line ~93), which writes through `OnboardingAnswers.apply` into the *same* `store.profile`, `availability`, `equipment`, `strengthPrefs` that Profile edits — one copy. The step is saved as `onboardingStage` 101–105; older builds' stages 1–9 are mapped on resume (`resume()`). Reopening lands directly on the saved stage.
**Approval.** `approve()` regenerates this week and next, appends a `PlanVersion`, then sets `onboarded = true`. No plan is active before that; pre-approval placeholder sessions are dropped.
**Storage.** One JSON file, `Application Support/BikeComputer/store.json` (`Models.swift` ~1607–1621), with a one-time migration from older UserDefaults keys. Accounts and cloud are compiled in but off (`ReleaseFlags.accountsEnabled = false`).
**Shared editors.** `AthleteTypeEditor`, `GoalCardsEditor`, `WeekBuilder` (`ProfileEditors.swift`) and `DeviceCardList` are used by both onboarding and Profile.
**Existing tests (not run here):** unit — `OnboardingDraftTests`, `S20DataIntegrityTests`, `DataIntegrityGapTests`, `ModelTests`, `W12AndDockTests`; UI — `OnboardingScreens`, `JourneyTests`, `LaunchSmokeTests`, `DeleteAllDataJourneyTests`. Two unrelated failures remain open (ride GPS-route samples; Plan edit-and-apply).

## 2. Field matrix
Profile destinations use Profile v2.0 sections A–F. "Consumers" lists what was found reading the value; "none found" means no engine reads it.
| Field (stored name) | Onboarding today | Storage owner | Profile v2.0 destination | Consumers (as read) | Editable | Validation | Migration needed |
|---|---|---|---|---|---|---|---|
| Name (`profile.name`) | A | profile | A › Personal details | greetings, summaries | yes | not empty to continue | no |
| Date of birth (`dateOfBirth`; legacy `birthYear`, `age`) | A, optional | profile + provenance | A › Personal details | age → estimated max HR; health check; board sync | yes | date picker; clearable | no (three overlapping fields exist — keep, read through one accessor) |
| Height (`heightCm`) | **not asked** | profile | A › Personal details | shown in the quick-menu fact list only; **no editor, no engine** | no editor today | — | no (field exists); editor is new |
| Weight (`weightKg` + provenance) | A, optional | profile + provenance | A › Personal details | W/kg; energy; newer-of entered vs Apple Health | yes | parsed number; source and date kept | no |
| Units (`settings.units`) | **not asked** | settings | E › Units | display; duplicate on the BikeComputer | Profile only | — | no |
| Gender (`gender`) | not asked | profile | none | **none found; no editor** | no | — | none — leave untouched |
| Training type (`trainingMode`: cycling / strength / hybrid) | A, required | profile | A › Athlete type | planner, goal lists, week builder, device relevance | yes, plan preview | one of three | **label only** ("Endurance" shown for `cycling`); stored value unchanged |
| Priority / balance (`priority`) | A, hybrid | profile | A › Hybrid balance | planner (what is protected when time is short) | yes | forced to the type for non-hybrid | no |
| Hybrid goal (`hybridGoal`, note) | not asked | profile | none proposed | strength planner, adaptive views | elsewhere | — | no — **overlaps `priority`; inconsistency to resolve later** |
| Riding experience (`level`) | A | profile | A › Experience | proposed week; planner | yes | three levels | no |
| Lifting experience (`strengthPrefs.experience`) | A | strength prefs | A › Experience | exercise difficulty cap; proposed week | yes (today in two places) | three levels | no |
| Selected activities (`sports`, 8 values, default `[roadCycling]`) | **not asked** | profile | A › My activities | **none found in any planner or Coach** | Profile only | — | **yes** — see model §4 (default is `[roadCycling]` even for strength-only athletes) |
| Goals (`goals`, `primaryGoal`; derived `goal`, `strengthPrefs.goal`; `legacyGoal`) | B | profile (+ strength prefs) | Plan (B shows a link) | planner reads **one** cycling goal and **one** strength goal derived from the main goal; other picks are stored | yes, plan preview | ≥ 1 | no |
| Week (`availability`; `preferredDays`, `weekIsExplicit`, per-sport days and minutes, weekly hours) | C | availability + profile (kept in step by `OnboardingWeek.write`) | Plan (B shows a link) | planner | yes, plan preview | blocks only with no training day | no |
| Two-a-day | C (screen state, written into the week) | availability | Plan | planner | yes | hybrid only | no |
| Equipment (`equipment.owned`, `excluded`, `confirmed`) | C, preset only | equipment | B › Equipment & restrictions | strength planner | yes, plan preview | "Not sure" = bodyweight until confirmed | no |
| Exercise restrictions (excluded, always-use-instead, temporary) | **not asked** | strength prefs | B › Equipment & restrictions | strength planner | Profile only | — | no |
| Supersets (`prefersSupersets`) | C | strength prefs | B › Strength preferences | strength planner | yes (two places today) | — | no |
| Strength split, strength goal | not asked | profile / strength prefs | B › Strength preferences | strength planner | Profile only | — | no |
| Recovery preference (`recoveryCapacity`) | not asked | profile | B › Recovery preference | Coach safety | Profile only | — | no |
| Health check (`healthScreen`), training pause | not in the five stages; reached from Home and Profile | profile | B › Training pauses & health check | Coach safety, Home | yes | — | no |
| FTP (`ftpW`, `ftpHow`, source, verified flags, date) | D, optional | profile | C › Power | ride targets, zones, board sync | yes, plan preview | 50–600 W; never guessed | no |
| Max / resting / threshold HR, zone method | not asked | profile (+ provenance) | C › Heart rate | zones, ride guidance | Profile only | — | no |
| HRV, sleep (`hrvMs`, `sleepHours`) | not asked | profile, from Apple Health | D › Apple Health (reads) | Home recovery information | switches only | — | no |
| Cadence range, bike name, wheel | not asked | profile | C | coaching, board | Profile only | — | no |
| HR source preference (`hrPrefWatchFirst`) | not asked | profile (+ device copy) | C › Measurement sources | sensor choice | Profile, and on the board | — | no |
| Device and Health connections | D | settings / system | D | recording, sync | yes | system permissions | no |
| Onboarding position (`onboardingStage`), `onboarded`, `guest` | — | store | none | app routing | — | — | **yes** — six-screen numbering needs a mapping (model §6) |

## 3. Findings
**Duplicated:** lifting experience and supersets and equipment preset each have two editors; date of birth is represented three ways; `priority` and `hybridGoal` overlap; HR source and units also live on the BikeComputer.
**Unused:** `sports` (stored, read by no engine); `gender` (no editor, no reader); `heightCm` (no editor, shown once).
**Inconsistent:** `sports` defaults to road cycling for every athlete, including strength-only; the Profile screen tells the athlete other sports "count toward weekly load" (untrue, recorded in Profile v2.0); the third type is titled "Hybrid Athlete" in code and "Hybrid" elsewhere.
**Incorrectly described elsewhere:** the Profile Phase 0 audit called the health check an onboarding-shared editor; as read it is not one of the five stages.
**Not supported:** recording, planning or importing anything other than cycling and strength; goals for other sports; more than one effective goal per sport; any account, cloud or restore.
**Not asked in onboarding today but required by the v2.0 brief:** height, units, selected activities, exercise restrictions, heart-rate baselines.
