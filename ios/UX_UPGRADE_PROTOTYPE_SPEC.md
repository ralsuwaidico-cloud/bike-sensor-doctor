# Cyclift V1 upgrade — prototype, interaction specification and approval checklist

Companion to `UX_UPGRADE_CHECKPOINT_A.md`. Documentation only. The clickable prototype is published as the artifact "Cyclift V1 Prototype"; its source is `design/ux-prototype/index.html` on branch `impl/v1-ux`. All values in the prototype are examples, never account data.

---

## 1. What the prototype demonstrates

Ten required screens, each reachable from the picker and from the screens themselves: Home · Progress overview · Cycling analytics · Strength analytics · Recovery (empty state and with-data state) · Horizon Map · Horizon Focus · Liquid Dock · Training Hub · Hub completed.
Supporting screens so that every control has a defined action: Training Overview, Recommendation details, Goal details, Day details (incl. "Before this plan started"), Sensor details, Consistency, Body & discomfort (Checkpoint E concept, marked), Milestones, History (with filters), Report, and the unchanged Plan and Profile tabs.

Toolbar: light/dark, Reduce Motion (instant dock movement, static glow), "Behind this screen" (per screen: the production data function behind each number, where each tap goes, what the empty state says). Controls that would open an unchanged production screen show the exact action they perform instead.

Sample week: plan approved Tue 3 Nov; today Wed 4 Nov; Mon 2 Nov shows the W12 pre-start dash; Tue ride done; adherence 1 of 5 since Tue.

---

## 2. Interaction specification

### 2.1 Liquid Dock (N-001…N-008)
- One component (`CyLiquidDock`, from the existing `CyFloatingTabBar`), used only by `RootView`; five slots in today's order (Home, Plan, centre, Progress, Profile); tab indices 0–4 unchanged; pages stay alive (`tabPage` ZStack unchanged).
- Geometry: floating capsule 14 pt from the sides, 20 pt above the home indicator (safe-area aware), 64 pt tall, radius 32, `.ultraThinMaterial` + 1 pt hairline, soft shadow. Tab targets 64 × ≥ 72 pt. Centre button 54 pt, raised 10 pt.
- Selection motion: the indicator pill moves to the new slot with a spring (response 0.5 s, damping 0.72) and stretches ~18 % wider for the first 220 ms, then settles. No particles, no bounce beyond one overshoot.
- Haptic: one `UISelectionFeedbackGenerator` tap on tab change. None while `RideRecorder.state == .running`.
- Reduce Motion: indicator jumps; glow becomes a static ring; haptic kept.
- VoiceOver: "Home, tab 1 of 5, selected"; centre labels per state (below). Labels cap at XXL Dynamic Type; icons always shown.
- During a recorded ride the dock is hidden (ride controls own the bottom); it returns when the ride ends or is paused for more than 5 s.

### 2.2 Centre button and Training Hub (T-001…T-010)
- Always opens the Training Hub (a presented page over the current tab; closing returns to that tab with its scroll position).
- State comes from the existing `store.homeToday().centre` / `TodayAction`:

| State | Look | VoiceOver | Hub opens on |
|---|---|---|---|
| Pending | teal, training icon, breathing glow (3.2 s cycle, opacity 0 → 0.7, scale 1 → 1.18) until the hub has been opened once today | "Training hub, one workout pending" | the pending card with Start |
| In progress | blue, play icon, no glow | "…, workout in progress" | Resume |
| Completed | green tick | "…, workout completed" | recorded results + anything remaining |
| Rest day | neutral card2 | "…, rest day" | rest context + optional sessions |
| Multiple | pending look + count badge | "…, 2 workouts pending" | each workout as its own card |
| Missed | pending look + small amber dot | "…, one missed session" | existing Move to today / reschedule |

- Health hold: unchanged — the hub shows the existing hold card and the Start action stays disabled (`HomeHold` / `HealthHoldSheet`).
- Hub card = the existing Today card layouts (`HomeToday.make` single/multi/rest/first/hold) moved from Home; Start/Resume/View results/Why/More call the existing routes. Prescriptions unchanged.
- Home keeps one compact reminder line (title + "Open the Training Hub"); it may be removed if the owner prefers.

### 2.3 Home cards (H-001…H-010)
- Weekly ring: `homeWeek()`; text "n of N sessions · window from the plan's effective start to Sunday"; percentage = plannedDone ÷ planned; never counts unplanned days.
- Cycling and strength cards: current week from the ledger; sparkline/bars = `TrendChartMath` weekly buckets (8 weeks); weeks before the plan draw nothing.
- Calendar: `CyCalendarStrip` with day states `beforePlan` (dash, muted), planned ride/lift/both, rest, done, active, missed, rescheduled (dashed dot). Tap → Day details.
- Coach insight: `homeCoach()` text; tap → Recommendation details; opening a card never changes the plan.
- Recovery card: always present. No data → "No readings yet · Connect Apple Health" (opens the existing Health permission flow). With data → latest sleep / resting HR / HRV with source and date. No score.
- Goal card: primary goal + what is measured so far + what is needed.

### 2.4 Coach recommendation workflow (H-009, §7.7)
Why → original → proposed → practical difference → schedule preview (strip) → Approve → `commitCoachChange` (plan version, Undo under Plan › Plan changes). Proposal types without a preview path (`Store.apply(CoachProposal)` fallback, adaptive accept) are shown as **advisory** with no Approve button; they remain the engine's deferred items.

### 2.5 Progress and drill-downs (P-001…P-012)
- Overview cards: Cycling, Strength, Recovery, then Consistency and Body & discomfort, then Milestones, History, Report. One range control (7 d · 4 wk · 12 wk · 1 yr) shared by the page and its detail pages (the existing `ChartRange` plus 7 d).
- Every tile shows a SourceTag: measured (sensor/GPS/Watch/board), imported (Health), entered, calculated, estimate, unavailable.
- Cycling: power and NP only from rides with recorded power; power zones only when `ftpSource != unknown`; FTP history from `ftpEvidence()` + entered values; "Set FTP in Profile" opens the existing editor.
- Strength: exercise picker → top-set line; e1RM uses the existing Progress formula and is labelled "estimate"; volume = Σ weight × reps, bodyweight sets count reps only.
- Recovery (B–D): latest value per kind from `HealthReads` with source and date; a 7-night sleep history needs stored reads → Checkpoint E only. Until then the page shows the latest night.
- Milestones: `checkpoints()` as three compact rows with "needs … so far …".
- History: `Timeline.build`, filters type/period/source; rows → existing detail views; imports listed once.
- Report: composed from the above; every section may say "insufficient evidence".

### 2.6 Cyclift Horizon (R-001…R-012)
- Map mode: MapKit `Map` with `MapPolyline` from the recorder's samples (as the existing details sheet), user position and heading; overlays: phase strip, primary metric with target band and on/below/above text (never colour alone), four secondary tiles, one coach line, sensor chips, route line "Recorded path shown · no planned route" (no navigation is implied).
- Focus mode: phase countdown ring (from `RideStepStrip` data), primary metric large, 5-minute trend, secondary tiles, coach line, sensor chips. Free ride: elapsed time replaces the countdown.
- Primary metric rule: the target metric of the current step (HR when no power; power when a meter is paired and FTP is valid; otherwise HR; cadence for cadence steps).
- Sensor states (existing `DeviceState`): receiving → live; stale → greyed value + "14 s ago"; not paired → "—" with the reason; the details screen lists every source. A missing Watch never blocks a phone-only ride.
- Controls: Pause / Lap / Hold-to-end (1.5 s press; a short tap does nothing); End → existing `RideResultSheet`. Board-owned rides use `device.control(...)` as today.
- Mode switching changes views only; `RideRecorder` and `LocationService` are never recreated. Dark presentation; no continuous decorative animation.

### 2.7 Empty states and sample data
Every empty state names what is missing, what is needed and one next step, in one card. Production never shows sample values; the design gallery keeps its demo data as today.

---

## 3. W12 — exact minimal change (analysis, not implemented)

Finding from the build-153 code:
- `TrainingLedger.riding/lifting(weekOf:)` count `planned` from `store.plan` entries in the week. Since the run-147 fix, `regenerate` writes nothing into days before approval, so `planned`, `plannedDone`, skipped and missed already exclude pre-start days. **No change to the ledger or the engine is needed for adherence.**
- The remaining gaps are presentational and one counting edge:
  1. Day strips (Home `HomeWeekStrip`, Plan day strip, Progress) show a day with no entry as rest (moon). They need to know the plan's effective start.
  2. `TrendChartMath.fullWeeks` / `rangeSummary` and `Checkpoints.countedWeeks` may count the partial first week as a full week — to be verified by test, adjusted only if they do.

Minimal change set:
- `Store.planEffectiveStart: Date?` — computed, no storage: the `effectiveDate` of the first `planVersions` entry with `cause == .profile` (written at onboarding approval), else the earliest `plan` date.
- `CyDayStatus.beforePlan` (additive) and `CyDaySport` mapping: a day `< planEffectiveStart` with no recorded ride/log → `beforePlan`, dash glyph, label "Before this plan started". Recorded activity on such a day keeps its real status.
- The same mapping applied in `HomeWeekStrip`, Plan's day strip and any Progress week view; the Day details screen shows the explanation.
- If the test in (2) fails: treat weeks whose Monday `< planEffectiveStart` as partial in `fullWeeks` and `countedWeeks` (one guard each).

Regression tests to write first (harness, then simulator):
- `testRegenerateNeverWritesIntoPastDays` (exists) extended: ledger `planned` for the approval week counts only days ≥ the effective start.
- `testPreStartDayWithRecordedRideKeepsItsStatus`: a ride recorded on Mon before Tuesday's approval shows as completed/extra, never as beforePlan.
- `testPreStartDaysAreNeverMissedOrRest`: Home/Plan day state for Mon = beforePlan; `missed` is nil; rest count excludes it.
- `testAdherenceDenominatorStartsAtEffectiveDate`: 1 done ÷ 5 planned = 20 % for the sample week.
- `testPartialFirstWeekIsNotAFullWeek`: trend summary and checkpoint `countedWeeks` exclude the approval week when it started after Monday.
- UI: LayoutAudit asserts the dash and the VoiceOver label on SE AX3 and standard.

---

## 4. Approval checklist (also inside the prototype, with a Copy button)

1. **Home** — composition and density; ring/cycling/strength prominence and mini charts; calendar day states; coach and recovery/goal cards; keep or drop the compact Today reminder.
2. **Progress overview** — category order; amount of information on the overview; Milestones/History/Report rows.
3. **Cycling analytics** — tile set and source tags; honesty of Unknown FTP / no power; chart style and ranges.
4. **Strength analytics** — exercise picker and progression; "estimate" labelling of e1RM; volume and muscle coverage.
5. **Recovery** — empty state; with-data presentation (source + date); coach-note wording.
6. **Horizon · Map** — map base with overlays; metric hierarchy; sensor chips and "no planned route"; hold-to-end.
7. **Horizon · Focus** — countdown ring and primary metric; stale-sensor treatment; default mode for interval workouts.
8. **Liquid Dock** — floating look; liquid motion amount; 54 pt centre and six states; Reduce Motion behaviour.
9. **Training Hub** — full card with Start/Why/More; Also today / Optional; close behaviour.
10. **Hub · completed** — recorded results; remaining/next wording; green centre state.

Each: Approve / Changes needed + notes. Checkpoint B begins only after all ten are answered and none is "Changes needed" without a reworked version approved.
