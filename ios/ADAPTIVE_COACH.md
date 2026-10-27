# Cyclift — adaptive hybrid-athlete coach (26 Oct 2026)

Brief: `docs/briefs/ADAPTIVE_COACH_BRIEF_2026-10-26.txt` (sections A–G). Branch `ios/cyclift-adapt`, base `fed07b8`.
Everything below is **simulator / CI-tested only**. Nothing has been tried on a real iPhone yet (list at the end).

## 1. What exists (audit before this work, base `fed07b8`)

| Brief item | State at base | Where (base code) | Reused / extended by this work |
|---|---|---|---|
| A1 primary goal (strength / endurance / balanced / general / custom) | partial | `RiderProfile.goal` (cycling goals only), `TrainingPriority` (Hybrid.swift) | `HybridGoal` → sets the existing `priority` |
| A2 total training days | missing | — (only `preferredDays`) | `RiderProfile.trainingDaysPerWeek`, used by `WeeklyAvailability.suggested(for:)` |
| A3/A4 cycling / strength sessions per week | complete | `cyclingDaysPerWeek`, `liftDaysPerWeek`, onboarding `weekStep` | allowed up to 10 when training days are set |
| A5 rest days, fixed / flexible days | complete | `DayAvailability` / `DayAssignment.fixed`, `AvailabilityEditor` | reused unchanged (Hybrid plan › "Rest days, fixed and flexible days") |
| A6 strength split | missing | `PlanEngine.week` used a hard-coded focus rotation | `StrengthSplit` + `SplitSlot` (custom list), followed in day order |
| A7 frequency of each workout type | partial | per-sport counts only | custom split slots carry a per-week count |
| A8 session duration + weekly budget per sport | partial | budgets `hoursPerWeek` / `liftingHoursPerWeek`, `WeeklyAvailability.fit` | `cyclingSessionMinutes`, `strengthSessionMinutes` (budget still wins) |
| A9 equipment | complete | `EquipmentProfile`, `EquipmentPage` (Strength*.swift) | reused unchanged |
| A10 templates to preserve | partial | `WorkoutTemplate`, weekday defaults | `preservedTemplateIds`; the programmer uses them first |
| A "more sessions than days" | partial | doubling pass in `suggested(for:)` | further pass onto the least-loaded training day (never a new day) |
| B build around the rider's exercises | partial | `InsightEngine` coverage suggestions filtered by `canDo` | `StrengthProgrammer` builds sessions from preserved routines → own exercises → other routines → catalogue, `canDo` only |
| B never unavailable equipment / no silent replacement | partial | `InsightEngine` (suggestions only) | replacement only as an approval proposal (`.replace`) |
| C post-workout check-in | missing | quick-log RPE (`StrengthSession.rpe`) only | `CheckIn` on `RideRecord` / `StrengthSession`, `CheckInFlow` after every ride / strength save |
| C strength analysis (sets, reps, kg, RPE, completion, previous) | partial | `StrengthAnalysis.progression`, `InsightEngine.next` | `AdaptationEngine.strengthDecision` (completion vs the routine's own sets, last 2 sessions) |
| C cycling analysis (duration, HR, power, load, quality) | partial | `Timeline.tss`, `HybridCoach.assess` zones, `SensorHub` `DataQuality` | `TrainingAnalyzer` (sRPE load, HR/verified-power estimates, reliability counts) |
| D deterministic adaptation engine | missing | `InsightEngine` (one suggestion, manual Accept), `HybridCoach` proposals | `AdaptationEngine` (pure Swift, no UI) |
| E auto vs approval, visible + reversible | partial | `CoachProposal` Accept / `undoLastProposal` (last one only) | automatic bounded changes + `AdaptiveProposal`; per-change Undo, "Restore original plan" (`Workout.coachOriginal`) |
| F loop + layer separation | partial | rules-only coach texts ("Coach (rules)") | Rules / Analysis / Explanations layers, `CoachExplanationProvider` hook (no model) |
| G tests | missing | — | `AdaptationEngineTests` (15), `AdaptiveSmokeTests` (1) |

## 2. The loop

Plan → Perform → Log → **Rate** (check-in) → **Analyze** → **Adapt** → Repeat.

- After every saved ride (`RideResultSheet`) and every saved strength session (quick log, detailed log, finished
  workout) the same sheet turns into the check-in: performance 1–10, effort 1–10, pain (none / soreness /
  discomfort / pain + where), optional note. Skip is always available.
- Save → `Store.recordCheckIn` writes **only** the check-in field of that record → `Store.runAdaptation()` → the
  Adjustments view ("Coach adjustments") shows what changed and why.
- The engine also runs after every plan rebuild (day editor save, Plan › Rebuild, Fix plan, Hybrid plan › Rebuild).
- Home shows one line only when something is in force or waits for approval: "Coach adjusted 2 sessions — see why".

Code layers (all in `BikeComputer/AdaptationEngine.swift`, no UI):

| Layer | Type | Responsibility |
|---|---|---|
| Rules / constraints | `AdaptiveRules` | bounds, which sessions may change on their own, applying a change to a session copy |
| Quantitative analysis | `TrainingAnalyzer` → `TrainingAnalysis` | sessions, loads, baselines, trends, fatigue / improvement / pain / adherence flags |
| Explanations | `AdaptationExplainer` | template text with the actual numbers, label "Coach (rules-based)", pain advice |
| Optional AI layer | `CoachExplanationProvider` (protocol only) | **not integrated**; `RulesExplanationProvider` is the only implementation and the offline fallback |
| Decisions | `AdaptationEngine.run` | analysis → bounded adjustments vs proposals |
| Store side | `AdaptiveStore.swift` | input building, applying, Undo, Restore, approvals, check-ins |

## 3. Inputs

`AdaptationInput`: profile (budgets, split, preserved routines), plan, rides, strength sessions, availability,
equipment, exercise catalogue, templates, each open strength session's exercises **as originally planned**, keys the
rider undid / declined, keys the rider approved, adjustments in force, units, now, calendar.

Per session (`SessionSignal`, last 35 days, completed only, demo rides never):
- strength: minutes, effort = check-in effort else logged session RPE, performance (check-in), pain, heavy-leg evidence;
  per exercise: done sets × reps × kg, set RPE, completion against the routine's own sets, previous sessions;
- rides: duration, average HR, power **only if verified** (`RideRecord.powerVerified == true`; nil = unknown =
  unverified — every ride in this build, because no meter is validated), check-in, planned minutes / kind of that day.

Missing values stay nil; nothing is invented.

## 4. Formulas (with their sports-science basis, in general terms)

| Quantity | Formula | Basis |
|---|---|---|
| Session load (AU) | effort (CR-10, 1–10) × minutes | session-RPE method (Foster et al., 2001): one sport-neutral internal-load number for riding and lifting |
| Ride load without a rating | HR zone of the average HR → CR-10 anchor (Z1 2, Z2 3, Z3 5, Z4 7, Z5 9) × minutes; labelled "estimate" | HR–RPE relation of the CR-10 scale (Borg; Foster); used for load only, never as effort |
| Ride load from verified power | intensity factor NP/FTP → CR-10 (<0.75 3, <0.85 5, <0.95 7, <1.05 8, else 9) × minutes | intensity factor / TSS concept (Coggan); only with verified power |
| Acute load | sum of the last 7 days | acute:chronic workload concept (Gabbett, 2016) — used only as a warning flag, not a prediction |
| Chronic load | mean weekly load of the 4 weeks before (needs ≥ 3 weeks of history) | rolling 4-week baseline |
| Load spike | acute / chronic > 1.5 | commonly cited "spike" threshold; one of several signals, never alone a diagnosis |
| Personal baselines | mean check-in effort and performance over the 4 weeks before the 2 latest check-ins (needs ≥ 3), else reference effort 6 / performance 7 | individual baselines instead of population norms |
| Estimated 1RM | Epley: kg × (1 + reps / 30); baseline = median of the older sessions in 4 weeks | standard strength estimate for trends only |
| Weekly planned load | Σ minutes × planned CR-10 of the session type (recovery 2 … VO2 8, strength 6) | sizes "> 10 % more load" |

## 5. Thresholds and decisions

**Never react to one workout:** every fatigue or improvement flag needs **two consistent sessions**.

Fatigue flags (scope cycling / strength / combined):
- rising effort at falling performance: the last 2 check-ins of that sport both effort ≥ baseline + 1.5 and
  performance ≤ baseline − 1.5 (within 10 days);
- repeated near-maximal effort: the last 2 sessions of that sport both effort ≥ 9; or ≥ 3 sessions at 9–10 in 7 days (combined);
- rides cut short: the last 2 matched rides < 80 % of planned minutes;
- strength decline: an exercise's estimated 1RM < 95 % of its 4-week median on the last 2 sessions;
- load spike: acute / chronic > 1.5.
- 2 or more flags = severe.

Responses (future, open sessions only; next 7 days):
- next hard ride (Zone ≥ 3): one zone step easier (VO2 → threshold → tempo → endurance); severe → easy endurance in
  the same slot (recovery emphasis); same day, same minutes. Strength fatigue counts here too.
- severe: next endurance / long ride −10 % (5-min steps, never under 20 min).
- next strength session: one set fewer (sets ≥ 3) on every exercise for strength / combined fatigue; on the leg
  exercises only (squat, hinge, single-leg) when the fatigue comes from cycling. No exercise list → −10 % duration.
- no progression anywhere while any flag is up.

Progression (only without fatigue flags and with < 2 missed sessions in 7 days; next session of each exercise within 14 days):
- load: every planned set (the routine's own sets) completed on the last 2 sessions at RPE ≤ 8 (set RPE, else session
  RPE, else check-in effort; unknown = not proven) and the equipment is owned → +1 load step, capped at 2.5 kg **and**
  5 % of the current load (metric step 2.5 kg barbell / 1 kg per hand dumbbell, imperial 5 / 2.5 lb);
- step above the cap, no load recorded, or equipment not owned → +1 rep per set (≤ 20); at 20 reps → +1 set (≤ 5,
  approval if over the lifting budget);
- two sessions in a row short of the planned reps at RPE ≥ 9 → −1 rep per set (never below 3), same weight;
- cycling: the last 2 rated rides performance ≥ 7, effort ≤ 6, completed (≥ 90 % of plan), no concerning pain →
  next threshold / VO2 session +1 interval if it still fits its minutes (15 min warm-up + reps × (work + rest) +
  10 min cool-down), else next endurance / long ride +10 % if it fits the weekly cycling budget **and** that day's
  minutes in the rider's days; otherwise an approval proposal. Unverified power is never used; HR or ratings may be.

Pain (updated for the coach remediation; owner decision 27 Oct 2026, independent reviews F-12, N-06, P3-04, P3-10 to P3-13):
the check-in has three levels, each with a short definition in the sheet.
- **Soreness** (a dull ache in the trained muscles, not in a joint, 1–3 days after training) changes nothing.
- **Discomfort** (something feels off in one spot, not sharp, not in a joint) holds progression in that area until a later
  session of the same activity is rated without it (at most 14 days); nothing is left out.
- **Concerning pain** (sharp, in or around a joint, swelling, changes how you move, or joint pain still there the next
  day) holds the area **until the rider confirms it is gone** (Coach adjustments › "It's fine now", with a confirmation
  step; for pain that lasted or came back the rider is asked to have it assessed first). It is **never released
  automatically**. After at least 7 days with the last 2 sessions of the same activity rated pain-free, the coach only
  asks. The 7-day / 2-session prompt is an owner-chosen **coaching heuristic**, not a rule from the literature. A
  confirmation releases only reports made before it (the check-in time counts, not the session start).
  Coach-built sessions leave out the area's exercises (shoulders/arms → push, pull, carry; back/core → hinge, core,
  squat, carry; hips/legs → squat, hinge, single-leg; knees → squat, single-leg; elsewhere / not sure → everything);
  the rider's own routines keep them but do not progress them. Legs, knees, back and unknown areas also stop cycling
  progression, ease the next hard ride by one zone and make the long ride and steady rides of 90 min or more 10 %
  shorter. "Lasted more than two weeks or came back" is said only when the pain recurred within 14 days or a later
  session still reported it. The rider sees plain advice: stop what hurts; see a doctor or physiotherapist if it is
  sharp, swollen, recurring or worsening; "the app cannot tell what is causing it". No diagnosis, ever.

Low confidence: fewer than 2 usable sessions (a rating, a logged RPE, HR or verified power) in 14 days → the plan is
kept as it is (changes already in force stay), and the coach asks for check-ins, naming rides without HR, rating or
verified power.

Missed sessions: ≥ 2 missed in the last 7 days → nothing increased, nothing crammed into later days. Half or more
missed in each of the last two weeks → proposal "one session fewer per week" (advice; the rider changes the days).

## 6. Automatic vs approval

| Applied automatically (bounded, future, listed, undoable) | Needs the rider's OK (proposal) |
|---|---|
| reps ±1, load +1 step (≤ 2.5 kg and ≤ 5 %), sets ±1 | changing a **fixed** day |
| one zone step easier / recovery emphasis in the same slot | adding / removing weekly sessions |
| intervals +1 inside the planned minutes | changing the strength split |
| duration ±10 % within the week budget and that day's minutes | replacing a saved exercise (equipment / exclusions) |
| | anything over a time budget |
| | more than +10 % planned weekly load from the week's progressions |

Never touched on its own: fixed days, sessions the rider edited (including planned sets typed by hand, which now mark
the session edited), sessions with sets from an accepted insight, skipped or completed sessions, past days, templates,
completed logs, ride history.

Recompute-from-original model: the engine always decides from each session's **original** values and outputs the full
set of changes wanted now; the Store recomputes every open session from `Workout.coachOriginal` (kept on each adjusted
session). So changes never stack, a reason that disappears restores the original, Undo of one change recomputes the
session with the others, and an undone / declined key is never applied again. Approved keys are applied like
automatic ones while their reason holds. Profile switch "Adjust future sessions automatically" (Adjustments view):
off = only approved changes are applied.

## 7. Files

New: `BikeComputer/AdaptiveModels.swift`, `BikeComputer/AdaptationEngine.swift`, `BikeComputer/AdaptiveStore.swift`,
`BikeComputer/AdaptiveViews.swift`, `BikeComputerTests/AdaptationEngineTests.swift`,
`BikeComputerUITests/AdaptiveSmokeTests.swift`, this file.

Changed (additive): `Models.swift` (shared: profile / workout / ride / settings / store fields with tolerant decoding,
interval reps in the steps text, custom split title, weekday-routine hook, `apply(_:allowFixed:)`), `Hybrid.swift`
(`StrengthSession.checkIn`), `Planning.swift` (training days, session length, split rotation, extra-session pass),
`OnboardingView.swift` (shared: optional Hybrid plan card in "Your week"), `ProfileView.swift` (shared: Hybrid plan +
Coach adjustments links), `HomeView.swift` (shared: one line), `StrengthLog.swift` / `StrengthWorkout.swift` /
`RideView.swift` (check-in after save; hand-set sets mark the session edited; coach-built sessions shown),
`RideDashboard.swift` (live coach uses adjusted interval repetitions), `PlanView.swift` (rebuild → adapt,
"coach-adjusted" pill, coach-built exercise names), `AvailabilityEditor.swift` (save / Fix plan → adapt).
Not changed: `BikeComputerApp.swift`, `project.yml` (new files are picked up by the existing source folders),
`LaunchSmokeTests.swift`.

## 8. Limitations and what needs a real device

- Power is never verified in this build (`powerVerified` is never set), so cycling decisions come from check-ins and
  HR only; validated-meter flagging needs the sources workstream.
- HR zones per ride are not stored (only the average), so HR load is an estimate from the average HR.
- Ride ↔ plan matching is by calendar day (first ride session of that day).
- Load steps assume plates / dumbbells exist in that increment; owned weights are not modelled (the why says so).
- Approved changes follow their reason: if the evidence disappears at a later run, the session returns to its plan.
- The custom-split "core / joints" session is built from core, single-leg and pulling patterns; there is no separate
  mobility catalogue.
- Real device: the check-in sheet after a real ride (board and phone recorder), the sheet transitions after Finish
  workout, slider use with gloves / sweat, Dynamic Type sizes in the Hybrid plan form, the Home line after midnight,
  sync of the new fields between two devices.
