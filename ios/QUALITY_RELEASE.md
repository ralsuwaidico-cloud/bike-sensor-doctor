# Cyclift — quality and coaching correction release (26 Oct 2026)

Triggered by the owner's real-iPhone screenshots. Scope: workout state model, one query layer, safe data migration,
personalised strength programming with per-exercise Why? and Swap, adaptive coaching, Health-style charts, honest FTP
labels and a responsive design pass. Old line numbers refer to `b485265` (before this release); new ones to this branch.

## 1. Root causes (file:line at `b485265`)

| Symptom on the owner's iPhone | Root cause |
|---|---|
| Strength sheet for **Tue 27 Oct (tomorrow)** shows green "completed — Marked done on the calendar" with no exercise logged | Chain of four defects: (1) `Store.startStrengthSession` (Models.swift:789) had no date guard, so tomorrow's session could be started today; (2) `finishActiveSession` (Models.swift:805) saved a log even when no set was ticked and invented a duration with `max(1, …)` (Models.swift:809 → the "1 min"); (3) `addStrength` (Models.swift:939) set `plan[workoutId].done = true` without checking that the planned day had arrived; (4) the sheet trusted the bare flag — `if w.done { completed(w) }` (StrengthWorkout.swift:51) — and looked for the log on the *planned* day (`existingLog(…, on: w.date)`), found none, and printed "Marked done on the calendar." (StrengthWorkout.swift:89) although no manual mark exists. Also `PlanView.swift:316` offered quick log / log exercises for any session up to 24 h ahead. |
| Home "STRENGTH 1/3 · 1 min of 2 h" while Progress says "no sessions logged yet" | Three independent query paths with different predicates: Home counted raw `strength` rows of the week (`Hybrid.swift:195`, minutes `:230`) — including the zero-set 1-minute record; Plan counted `done` flags and *planned* minutes (`PlanView.swift:109-112`); Progress decided "no sessions" from `store.strength.isEmpty` (`ProgressView.swift:52`) and summed rows separately (`Models.swift:1084-1092`). Deleting a log (`deleteStrength`, `Models.swift:946`) removed the row but left the planned session's `done` flag, so screens disagreed about the same week. |
| Exercises generic (Back squat 3×10, Bench 3×10, Deadlift 3×10, Row 3×10, Plank 3×12 · BW), all "no previous log" | Coach-built sessions came from `StrengthProgrammer.entries` (`AdaptiveStore.swift:151`, `AdaptationEngine.swift:710`): one fixed 3×10 list per session type, independent of goal, experience, equipment, cycling load or logged sets. |
| Progress weekly riding chart: x-axis labels overlap | `AxisMarks(values: .stride(by: .weekOfYear))` with a centred "d MMM" label for **every** week (`ProgressView.swift:41`, lifting `:61`): 16 labels in ~300 pt. No scrolling, no selection, no visible-range summary. |
| FTP card "225 W · 3.0 W/kg" badge **tested** while the text says "Estimated as 95 % of the best 20-minute power" | Badge from `FTPHow.label` ("tested", `Models.swift:21`) while the sentence was a ternary that mapped every non-assumed, non-entered value — including `.tested` — to the estimate sentence (`ProgressView.swift:77-79`). Any number typed in Profile (`ProfileView.swift:245`) or onboarding (`OnboardingView.swift:229`) was stored as `.tested`. |
| Home coach actions wrap ("Log / strength", "Alterna- / tive"), long helper paragraph | Three/four equal-width `frame(maxWidth: .infinity)` buttons with long labels (`StrengthLog.swift:503-513`) and a permanent caption paragraph (`StrengthLog.swift:445`). Fixed point sizes (`.system(size:)`) and `minimumScaleFactor` throughout the app shrank text instead of reflowing it. |

## 2. Corrections

### Workout state model and one query layer (`WorkoutState.swift`)
- Explicit states: `planned, started, inProgress, completedLogged, completedManual, skipped, importedHealth`
  (`WorkoutStatus`). Derived only by `TrainingLedger.status` from evidence: a linked or same-day strength log (detailed
  → logged, quick → manual, Apple Health → imported), a recorded ride on the day, or the rider's explicit "Mark done"
  (`Workout.completion = .marked`). Never by a date passing or by being on the calendar; nothing can be completed,
  started or logged against a later day (`Store.isFuture`, `markDone`, `startStrengthSession`, `addStrength`).
- `TrainingLedger` is the ONE query layer: Home (HybridCoach.assess, weekly review), Plan (summary, calendar, day cards),
  History (Timeline.build), Progress (charts, counts) and the coach all read its `lifting(weekOf:)` / `riding(weekOf:)`.
  Definitions: done = detailed logs + quick logs/marked done + imports; minutes = only measured or typed durations
  (sessions without a duration are counted and reported as such); planned sessions are never counted until done.
- Finishing a workout with no ticked set saves nothing; the sheet offers "Mark done without details" or Discard.
  Duration = measured working time, never a made-up minimum.
- UI: status card on every session (strength sheet and ride/other detail): Mark done (optional typed duration), Skip /
  Unskip, Move to today (future), Add details (manual → detailed log, same id, no duplicate), Reopen (back to planned;
  keep the log as an extra session or delete it with Undo). History detail: Edit / Add exercises (edit or delete sets),
  Delete with an **Undo** snackbar (soft delete kept 30 days in `trash`), "needs review" records with Keep / Delete.
  Stable UUIDs everywhere; Undo restores the same ids and the planned sessions exactly as they were.

### Migration (schema 1 → 2, `StoreMigration.v2`, idempotent, never deletes)
- **M1** a planned session marked done for a day after the migration day → planned; logs linked to it stay on their own
  date as extra sessions.
- **M2** a log saved from workout mode with no completed set → kept but flagged *needs review* (not counted until the
  rider confirms); a recorded duration ≤ 2 min becomes "not recorded".
- **M3** a session marked done keeps "completed" only when a counted log or a recorded ride backs it.
- **M4** an FTP labelled "tested" without a recorded test ride is shown as *Unverified* (value kept).
- Every change writes the original values into `migrationNote` and a readable line into `migrationLog`. Running it
  again (or loading a schema-2 file) changes nothing. Coach-built future sessions are rebuilt once by the new planner;
  hand-edited sessions are never touched.
- Audit fixes (3a) need no schema change: `painClearances` is a new optional field (absent → empty), rides keep
  `powerVerified` as stored (nil = unverified, as before). Riders on "Coach decides" whose future coach-built strength
  sessions were empty get exercises at the next rebuild (check-in, detailed log, settings change, new week); sessions
  with the rider's routine, edited, skipped, completed or past sessions and every log are untouched.

### Personalised strength programming (`StrengthPlanner.swift`, deterministic, no model)
- Inputs: goal, hybrid priority, experience, split / session type, frequency, session minutes, equipment (custom items
  allowed), favourites and swap preferences, temporary unavailability, recent and planned cycling load, LOGGED sets of
  the same exercise, check-in RPE / fatigue / pain areas.
- Rules: movement-slot coverage per session type; weekly working sets per region by experience and priority, shared
  across the week's sessions; rep ranges and target RPE by goal and role; double progression from logged sets only
  (never from quick logs, marked sessions, or another exercise — a new exercise says "find your working weight"; a
  load step needs two sessions in a row at the top of the range at a known RPE ≤ 8 — see 3a);
  deload on fatigue check-ins or every 4th consecutive training week; interference: lower body light (one set fewer,
  RPE ≤ 6) the day before a key ride, later the same day, or after a long / hard ride; −25 % lower-body volume in
  high-cycling-load weeks; pain areas exclude movements with that loading (knee flexion, spinal load, overhead, wrist
  extension, impact) and hold loads. Fixed days, session types and the rider's own routines / edits are never changed.
- **Why?** per exercise: muscles and pattern, goal relevance, place in the week, sets/reps/effort with the reason, load
  (last logged performance and the progression rule applied) and the interaction with nearby rides — from the stored
  `SessionRationale`, i.e. the factors the planner actually used.
- **Swap** per exercise: alternatives by pattern, muscles, goal, difficulty, flags — only exercises the rider's
  equipment allows. Reasons: today only · always prefer this · I don't have this equipment (removes it from the
  equipment profile) · temporarily unavailable (3 sessions / 2 weeks) · causes discomfort (excluded, similar-loading
  movements flagged, "get it checked by a doctor or physiotherapist if it persists", no diagnosis). Persisted in
  `StrengthPrefs`; sets/reps kept; weights never transferred between exercises. Profile › Training profile › Strength
  programming lists and undoes every preference.

### Adaptive coaching after workouts
Check-ins (performance, RPE, pain) now also rebuild coach-built sessions through the planner (pain → exclusion + hold,
fatigue → deload) before the existing adaptive engine applies its conservative, explained, individually undoable
adjustments. Progression never comes from manual completions or quick logs (they carry no sets); records waiting for
review are not evidence. The check-in result screen lists every session that check-in changed ("Thu 29 Oct · Strength:
14 → 11 sets, left out: Goblet squat. Knee pain reported …") with one **Undo these changes** (`Store.checkInRebuild`,
`undoCheckInRebuild`): the sessions go back exactly as they were and are kept as the rider's own, so neither the planner
nor the adaptive engine rebuilds them on its own afterwards. Completed logs are never touched.

### Progress
- Health-style weekly charts (`TrendCharts.swift`): horizontally scrollable (`chartScrollableAxes`, opens at the most
  recent week), range picker 8 wk / 16 wk / 1 yr (`chartXVisibleDomain`), touch-and-hold selection
  (`chartXSelection`) with a rule, highlighted bar and callout ("12–18 Oct · 2 h 05 min · 3 rides"), an AVERAGE PER
  WEEK header for the visible weeks that updates while scrolling, labels every 2/4/13 weeks (doubled at accessibility
  sizes) so they never overlap, units on every value, VoiceOver labels per bar and an audio-graph descriptor. Applied to
  riding and lifting time.
- FTP confidence: **Verified test** (completed planned FTP test ride with verified power), **Estimated from verified
  power data**, **Provisional estimate** (weight × level), **Unverified** (typed values, unverified power, "tested"
  without a ride). Not-verified FTPs use 5 % lower targets (`prescriptionFTP` / `prescriptionZones`) with a caution.

### Design system (`DesignSystem.swift`)
Spacing scale, Dynamic Type styles instead of fixed point sizes, `ActionRow` (one row → two per row → one per row, labels
never truncated or hyphenated, full action name for VoiceOver), `FlowRow` (pills and meta text wrap), `InfoButton`
(long helper text behind (i)), ≥ 44 pt targets, short labels (Log · Adjust · Swap · Start), content inset above the
raised centre button, tab bar capped at xxLarge with the large-content viewer, watch HR row reflows.
Final pass: descriptive lines that used to end in "…" (profile header, settings subtitles, plan rows, exercise names,
"Previous:" lines, adjustment titles) now wrap; summary lists (exercise names of a routine) keep a 1–2 line summary at
normal sizes and wrap from XXXL up (`clampLines`). Every small bordered button (Accept / Not now / Undo / Edit / chips /
set toggles) uses the large control size; delete-set and remove buttons and the filter chips have 44 pt targets. Swap
alternatives are plain rows (name in the primary colour, reasons in secondary, chevron). Text-link buttons (Plan ›,
Review ›, Show all, Adjust sets) use `TapTargetStyle` so the 44 × 44 pt area is really tappable (a frame around a plain
button is not), week arrows and ride rows are 44 pt, and the "Why?" disclosure rows are 44 pt tall. `FlowLayout` now
breaks lines with exactly the width it was measured for: at XXXL a History row measured with two lines was placed with
three, drawing the "completed" pill over the ride metrics (seen in the CI screenshot `standard-xxxl-10-history`). Watch: heart rate and ride tile
numerals scale with the wearer's text size (`@ScaledMetric`), shrinking only if a value would not fit on one line.

## 3. Tests
See the CI section at the end for the run, counts and screenshots.
- Unit (`QualityReleaseTests`, 27 new): owner scenario (tomorrow + zero-set finish), states incl. manual / imported /
  skipped and "no date-driven completion", delete + Undo (same ids, no duplicates, 30-day purge), revert / reopen /
  delete workout + Undo, manual → detailed conversion without double counting, edit / delete sets, migration fixture
  (M1–M4, idempotent), cross-screen consistency Home = Plan = Progress = chart = History before and after review,
  different profiles → different programs, equipment incl. custom items, fixed days / own routines kept, interference
  (key ride next day, after a long ride, high-load week), progression from logged sets only (no transfer), pain
  exclusions, swap alternatives / reasons / persistence, always-prefer pick, FTP labels and conservative zones, chart
  bucketing / visible-range aggregate / selection / callout / non-overlapping labels; deload on fatigue and in the 4th
  consecutive training week (quick logs do not count), movement-pattern coverage per session type and a short session
  trimming sets before patterns, a hard logged effort (RPE 9 / missed reps) holding the load, Why? lines equal to the
  planner's recorded decision (load rule, dose, key-ride interaction, place in week), no progression from quick logs or
  "Mark done" (planner and adaptive engine), and a pain check-in changing the next session with an explained, exact Undo.
- Unit (`AuditFixTests`, 15 new): the audit fixes in section 3a (light-load steps, two-session evidence, unknown RPE,
  repeated failure, shared hold after missed sessions, Coach decides → exercises, pain clearing by exposure /
  confirmation, unverified power → relative live coaching, live intervals = plan, PPL rotation across weeks, short
  sessions keep all four patterns across the week, load ratio for constant load / new riders).
- Existing tests updated only where the meaning changed on purpose: FTP label wording (ModelTests, RulesTests) and a
  timeline fixture whose "completed" strength session had no evidence (now explicitly marked done); the planner progression
  test now logs two sessions (one session no longer raises the load, G-02).
- UI: `LayoutAudit` (CI layout stage) on a small iPhone, a standard iPhone and a Pro Max at L / XXXL / AX3 with demo
  data reproducing the owner's case: screenshots of Home, the strength sheet (exercises, Why?, Swap), Plan, History,
  Progress (incl. a selected bar), Profile; hard checks that the coach actions and tab items are inside the window,
  do not overlap, are ≥ 44 pt and hittable; every on-screen text outside the window and every on-screen button under
  44 pt is listed in `layout-report-<device>.txt`. Text sizes per device: small iPhone L + AX3, standard iPhone L + XXXL
  (plus Why?, Swap, tomorrow's session, a selected chart bar, Training profile, Connections), Pro Max L.
- Watch: `ci/watch-shots.sh` builds the watch app for the simulator and screenshots it on the smallest and largest
  Apple Watch at L / XXXL / AX3 (soft stage, published with the layout screenshots).
- Launch smoke (`LaunchSmokeTests`, Release build, 6 tests): fresh install, upgrades from builds 24 / 30 / 33 / 36 / 40
  stores, all tabs, centre button, export / delete-cancel, hybrid sheets at accessibility text size — unchanged and
  passing with the renamed labels.

## 3a. Audit findings addressed (vs 2b2c104)

The independent coach audit of `2b2c104` (outside this repo; its files were not modified) executed the engine with a
Linux harness: 34 end-to-end athlete profiles (P01–P34) and 20 single-rule probes (X01–X20). Fixed here:

| Audit ID | Defect at 2b2c104 | Correction | Where | Tests |
|---|---|---|---|---|
| G-04 (P0) | "Coach decides" (no split chosen) → strength days with **no exercises**, only a generic circuit text | The planner builds every coach-built session with or without a chosen split (the week builder already gives each lift a focus); newly generated weeks are built with the NEW week in view (its rides for interference, its lifts for the session index and weekly volume) | `StrengthPlanner.refreshGeneratedSessions`, `Store.programmedSession`, `Store.applyWeekdayRoutines` | `AuditFixTests.testCoachDecidesSplitGetsRealExercises`; harness P01 |
| G-01 (P0) | Loads never rose below ~50 kg (barbell) / ~20 kg (dumbbell): the plate step had to be ≤ 5 % of the load | Smallest available step (2.5 kg barbell, 1 kg per dumbbell; 5 / 2.5 lb imperial) whatever its percentage, back to the bottom of the rep range; above 10 % the Why? adds "if the first set is harder than RPE 8, go back and add a rep instead" | `StrengthPlanner.prescribeLoad` | `testLightBarbellAndDumbbellLoadsProgressWithTheSmallestStep`; X01, P02 |
| G-02 (P0) | Planner raised the load after ONE good session and read a missing RPE as RPE 8 | A load increase needs the last TWO logged sessions of that exercise, at that weight, with every set at the top of the range and a KNOWN effort ≤ RPE 8. Unknown effort = no progression of load, reps or hold time, and the Why? says why ("an unrated session is not evidence that it was easy") | `StrengthPlanner.prescribeLoad` | `testOneGoodSessionDoesNotRaiseTheLoad`, `testUnknownEffortIsNotEvidence`; X02, X04 |
| G-16 (P1) | Repeated failure (3 × 4 at RPE 10 twice) → same weight forever | Two sessions in a row short of the range at RPE ≥ 9 → about 10 % less (rounded to the step) | `StrengthPlanner.prescribeLoad` | `testTwoFailedSessionsBringTheLoadDown`; X03 |
| G-03 (P0) | After ≥ 2 missed sessions the coach said "nothing is increased" while the planner still added load / reps | One shared hold: `PlannerContext.progressionHold` comes from the same analysis (`adherenceBlock`); while it holds, the planner holds every load, rep and hold time and says so in Why? and the session notes (pain and deload holds as before) | `Store.plannerContext`, `StrengthPlanner.prescribeLoad` / `build` | `testHoldStopsEveryKindOfProgression`, `testMissedSessionsHoldThePlannerLikeTheCoach`; P22 |
| G-06 (P0) | Knee pain after a lift was cleared by any two pain-free check-ins (e.g. two rides) | A concerning report holds its area at least 7 days AND until the next 2 sessions that loaded the same area the same way (a ride for a riding report; a lift containing a movement of that area for a lifting report) are rated pain-free — or until the rider confirms it is gone (Coach adjustments › "Knees: it's fine now", stored as `painClearances`). No more expiry by date. Pain advice text updated | `TrainingAnalyzer` (pain block, `loadedPatterns`), `PainClearance`, `Store.confirmPainGone` / `activePainAreas`, `AdaptiveViews` | `testKneePainFromALiftIsNotClearedByRides`, `testKneePainClearsAfterAWeekAndTwoPainFreeKneeLoadingLifts`, `testConfirmPainGoneIsStoredAndReleasesTheArea`; P34 |
| G-05 (P0) | Power was never trusted, yet the live ride coach cued on unverified watts whenever there was no HR strap and the FTP was not "assumed" | `PowerTrust.meterVerified` is the one source: the pipeline marks power `.good` only from it (`ContentView` → `SensorHub.refresh`), board rides store it (`RideRecord.powerVerified` = false, explicit), and `RideCoach.configure` coaches untrusted power like an assumed FTP: heart rate when there is a strap, otherwise "hold your own steady output" with no zone claimed. No meter can be verified in this build (the Android 60-second check is not ported), so power is advisory | `Models.swift` (`PowerTrust`), `ContentView`, `RideRecorder`, `RideDashboard` | `testUnverifiedPowerFallsBackToRelativeCoaching` |
| G-07 (P1) | Split rotation restarted every week (PPL × 2 never trained legs) | The rotation continues across weeks (`offset` = weeks since 5 Jan 2026 × lifts per week); Profile shows this week's sequence | `StrengthSplit.sessions(…offset:)`, `PlanEngine.week` | `testPushPullLegsTwiceAWeekReachesLegs`; X05 |
| G-08 (P1) | 30-minute sessions dropped all pulling | Trimming keeps squat, hinge, push and pull: accessories / core leave first, then main lifts go to 2 sets, and only then one main pattern is left out — a different one in each session of the week | `StrengthPlanner.build` | `testThirtyMinuteSessionsKeepPulling`; P14 |
| G-09 (P1) | Load-spike flag for new riders ~day 22 (chronic ÷ 4 with only 2–3 weeks of data; acute window included today) | Acute = last 7 completed days; chronic = weekly mean of up to 4 weeks before, divided by the weeks actually covered, only once ≥ 28 days of history exist | `TrainingAnalyzer.analyze` | `testConstantLoadReadsAboutOneAndNewRidersHaveNoRatio`; X17, X19 |
| G-11 (P1) | Ride screen ran threshold as 4 × 8 min / 4 min while the plan said 3 × 8 min / 3 min easy | The live coach takes the planned structure (`Workout.liveIntervalPlan`: the kind's work / rest minutes and `effectiveIntervalReps`, adaptive changes included) | `Models.swift`, `RideCoach.intervalPlan(for:)` | `testLiveIntervalsMatchThePlan`; X06 |
| G-21 (P2) | Live coach used % HRmax bounds even with the LTHR method | `RideCoach.configure` passes the rider's own zone bounds | `RideDashboard` | — |

Found while re-running the harness: once G-09 stopped the false load spikes, riders with their own routines got
progression adjustments again, and re-running the coach re-created the routine's prefilled entries with new ids
(harness G8 "re-running the coach never changes the plan" failed for P08 / P29 / P30). `applyAdaptation` now keeps
the session when only ids differ (`Store.sameContent`) — also keeps entry ids stable for Swap / Why?.

Not addressed here (documented in the audit, out of scope for this release): G-10 quality ride dropped next to leg
days, G-12 coach-cut sets counted as incomplete (X18), G-13 / G-14 / G-15 / G-17 adaptation refinements, G-18 to G-20,
and the missing functions M-01 (health screening), M-02 return after a break (P15), M-06 masters (P16) and M-03 to M-12.

**Harness before / after** (the audit's harness copied to a scratch directory and pointed at this worktree; same
profiles, criteria and probes; the only change to the copy: probe X06 was hard-coded to "fail" because the ride
coach is SwiftUI code the Linux build cannot compile — the copy compares `Workout.liveIntervalPlan`, which
`RideCoach.intervalPlan(for:)` returns unchanged, with the plan's steps):

| | Profiles (P01–P34) | Rule probes (X01–X20) | Total |
|---|---|---|---|
| Audit run on `2b2c104` | 27 / 34 | 11 / 20 | 38 / 54 |
| This branch before the fixes (merge of `ios/dev`, engine unchanged) | 27 / 34 | 11 / 20 | 38 / 54 |
| This branch after the fixes (`ee9480d`) | **32 / 34** | **19 / 20** | **51 / 54** |

Now passing: P01 (Coach decides → exercises), P02 (light main lifts progress: belt squat / swing), P14 (30 min: all four
patterns), P22 (missed sessions: planner holds too), P34 (knee pain not cleared by rides), X01 (40 kg → 42.5 → 45 →
47.5 kg), X02 (one session: 60 kg × 10, not progressed), X03 (failure twice: 60 → 52.5 kg), X04 (no RPE: 80 kg × 10,
not progressed), X05 (PPL × 2: legs / push, then pull / legs), X06 (live 3 × 8 min / 3 min), X17 (constant load: no
ratio before 28 days, then 1.00), X19 (repeated week never flagged). Still failing, not in scope: P15 (no
return-after-break reduction, M-02 — loads continue from the last logged ones), P16 (no masters adjustment, M-06),
X18 (coach-cut sets, G-12). Science-advisory notes (not counted): S1 weekly volume of P14 now passes (pull sets
restored); S2 (share of planned ride minutes in Zone ≥ 3 sessions above 25 %, session-level) unchanged for P01, P05,
P08, P13, P27–P31.

## 4. Remaining limitations
- A check-in's changes are undone together (one Undo per check-in, on its result screen; the adaptive engine's own
  changes stay individually undoable in Coach adjustments). After that Undo those sessions are kept as the rider's own,
  so later logged progress does not reshape them automatically until the rider edits or regenerates the week.
- Exercise metadata (pattern slot, muscles, loading tags, difficulty) is derived from the catalogue's names and
  patterns by rules (`ExerciseLibrary.meta`); unusual custom names may be classified coarsely.
- Power verification depends on the existing pipeline flag; until a ride carries verified power, accepted estimates are
  "Unverified" and targets stay conservative.
- Chart selection: a tap selects a week (second tap clears) and touch-and-drag moves the selection (Swift Charts);
  a horizontal swipe scrolls. Verified in the simulator by a scripted tap; drag feel needs the physical check below.
- Watch: screenshots cover the first screen of the watch app (no phone paired, so no ride mirror) on the smallest and
  largest watch at L / XXXL / AX3; there is no automated frame check on the watch (no watch UI-test target). The text
  size is set by launch argument because `simctl ui content_size` is not available for watchOS simulators.
- The live ride dashboard (`RideDashboard`, `RideView`) keeps its fixed-size, glanceable bike-computer numerals by
  design; it is outside this release's Dynamic Type pass.
- Power stays advisory: no power meter can be verified in this build (`PowerTrust.meterVerified = false`), so no FTP
  can become "Verified test" / "Estimated from verified power data", the power-based adaptation rules stay dormant and
  the live coach never claims a power zone. Enabling it needs a real verification flow (port of the Android
  60-second check) and a hardware test.
- Pain: an area reported as concerning stays held until the rider taps "it's fine now" or two pain-free sessions that
  load it are logged a week or more later. Because the planner leaves knee-loading lifts out while knees are held, a
  lifting knee report in practice clears through the confirmation (or pain-free rides only when the report came from a
  ride). There are no screening questions (audit M-01).
- System controls keep their system metrics: segmented range pickers (32 pt tall, full width), the navigation-bar
  Done and More buttons (UIKit extends their hit area). The layout report lists them; they are not custom targets.

## 5. Check on a physical iPhone
- The owner's store after the update: tomorrow's session reads **Planned**; the 1-minute record appears in History as
  **needs review**; Home, Plan and Progress show the same counts; Keep / Delete work and Undo restores.
- Finish a workout without ticking a set → nothing saved; "Mark done without details" works.
- Swap with each reason, then reopen the app: preferences persist; equipment change visible in Profile.
- Progress charts: scroll, change range, touch-and-hold a bar, VoiceOver audio graph.
- Larger Text (Settings › Accessibility) on the owner's phone and an SE / mini: Home actions, strength sheet, Plan.
- Apple Watch app at large text sizes, with the iPhone paired and a ride running (ride mirror tiles, Pause / End).
- Submit a check-in with "Concerning pain · knees": the result screen lists the changed session(s); Undo these changes
  restores them; reopening the app keeps them.
- Coach adjustments › "Knees: it's fine now" after a knee report: the hold is released, knee-loading exercises come back
  in the next coach-built session; reopening the app keeps it.
- A ride with the power meter and no HR strap: the coach panel says "hold this effort / steady against your own
  output" and never "zone N" from watts; a threshold session runs 3 × 8 min with 3 min easy (as the plan says).
- A rider on "Coach decides": next week's strength days list exercises with Why? and Swap.
