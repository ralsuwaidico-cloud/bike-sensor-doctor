# Cyclift Home — Option B implementation spec (v2, after QA review)

Owner decision 28 Oct 13:27: Option B. QA review of v1: /home/claude/qa-ux/HOME_OPTION_B_REVIEW.md (GO-with-changes, 4 P0 / 13 P1 / 9 P2).
This v2 resolves every P0 and P1 and states how each P2 is handled. Nothing here changes a coaching calculation or stored data.

## Layout (top to bottom)
1. Header: date (caption, secondary) + "Hi <name>" (title2, not a large title). No navigation large title.
2. Optional one-line banners, only while true, each one line with a chevron: unsent crash report (DiagCrashBanner, as today),
   phone/board profile mismatch (only when a ride is today). Never more than one at a time; crash report wins.
3. TODAY card (always).
4. COACH card (only when the coach slot has an item, see below).
5. THIS WEEK card (always, except in stop/supervised/illness states where it shows only "No sessions planned while paused").
At default text size on 393×852 everything fits without scrolling. At larger sizes the rule is: workout title and primary button
are always above the fold; the page may scroll (vertical only).

## TODAY card
- Eyebrow "Today's training" + status chip (Planned shows no chip; In progress, Done, Skipped, Missed, Rest day, Paused).
- Title = workout display title (from the plan; never hardcoded). Subtitle = duration · plain intensity · (rides only) "Zone n".
  Plain intensity mapping (new, display only): Z1 "Very easy", Z2 "Easy", Z3 "Moderate", Z4 "Hard", Z5+ "Very hard";
  strength by prescribed RPE: ≤6 "Light", 7 "Moderate", ≥8 "Hard"; capped by readiness (pending/needs clearance show the capped value).
- "Eased by coach — see change" line when today's session carries an applied coach adjustment (P1-13).
- Sensor line (rides only, P1-9): shown only if the rider uses a BikeComputer (remembered) AND the link is not ready when the card
  renders: "BikeComputer not connected — the phone can record with GPS". Never a power-meter claim Home cannot know.
- Primary button (one model shared with the tab-bar Train now, P2-20):
  | Status | Button | Destination |
  |---|---|---|
  | planned strength | Start workout | StrengthWorkoutScreen (logger) |
  | planned ride | Start ride | Ride tab, recording armed |
  | in progress strength | Resume workout | StrengthWorkoutScreen |
  | in progress ride (recorder active) | Open ride · mm:ss (live timer) | Ride tab |
  | done (logged/imported) | View results | ride results / strength session detail |
  | done (marked without details) | Add details | QuickStrengthLog / ride edit for that session (P2-23) |
  | skipped | Move to another day | Reschedule picker (new) |
  | rest day | Recovery guidance | new RecoveryGuidance sheet (static, honest text) |
  | health stop / supervised-only / illness pause | Review health check | HealthCheckView |
- Secondary row (each ≥44 pt tall, P1-17): "Why this workout?" (Coach.why sheet) and "More ⋯" (menu: Edit, Swap, Move to another day,
  Skip / Unskip). Hidden on rest days and in health-hold states (P1-11). The whole card is tappable with a chevron → workout detail (P1-15).
- Missed (P1-7): a past planned session not done or skipped is "missed" (new derived status, display only). If today has its own
  session, the card shows TODAY's session as primary and one extra row "Missed Tue · Endurance 60 min — Move to today / another day".
  If today is free, the missed session is shown with "Move to today". Moving a past session is allowed only into today or a free future
  day of the current week (new Store.reschedule(id, to:), Undo toast).
- Multi-session day (P1-8): title "Today · 2 sessions"; one row per session (kind title, duration · intensity, status), each row with
  its own ≥44 pt primary button and its own More menu. No invented time of day. A recorded ride completes at most ONE planned ride
  (the first not-done ride that day) — fix in the status/attribution layer, covered by a test.

## Health precedence (P0-1, P0-2, P1-14)
- stop / supervised-only / illness pause: TODAY card becomes the hold card (title by state: "See a doctor before training",
  "Train with your doctor's team", "Rest while you are ill"), button "Review health check", secondary "What this means" (sheet with
  the CoachReadiness restriction text). COACH card hidden. THIS WEEK shows "No sessions planned while paused" — no fraction, no Up next.
- Train now (tab bar) during these states opens a hold sheet with the same text and "Review health check"; it does not offer Ride or
  routines. The Ride screen's Start and the strength logger's Start also check readiness and show the same hold (defence in depth).
- pending health check / needs clearance: a compact line card above TODAY: "Health check needed — answer <n> questions (n =
  HealthScreen.questions.count). Until then: easy rides, moderate lifts." / "Clearance needed for hard training". Workout card shows the
  capped intensity. Coach card still allowed.

## COACH card — a slot, filled only from existing engine outputs (P0-3)
Priority (first that exists wins; otherwise no card):
1. A pending coach proposal (AdaptationEngine proposal awaiting approval): "Coach suggests: <proposal title>" + Accept / Details.
2. An applied adjustment to today's or the next session (AdjustmentHomeLine source): one sentence + "See change".
3. An FTP suggestion (store.ftpSuggestion): "Update FTP to <x> W?" + Review.
4. Weekly gap / "Revise my training days" offer (weekly review source): one sentence + action.
5. Low confidence (AdaptationEngine low-confidence state): "Rate your sessions after training so the coach can adjust." + no button.
Each item shows its evidence line from the engine ("Based on 3 rated sessions"). No free text is invented; the hybrid one-liner that
repeats today's workout is removed. Never a recovery/readiness score.

## THIS WEEK card (P0-4)
- One source: WeekTotals (TrainingLedger), the same as Plan and Progress (already on fix/rc2-ux, 34bf239), Monday–Sunday.
- Line 1: "<done> of <planned> sessions done" where planned = planned sessions not skipped this week; done = those completed.
  Extra unplanned sessions: "+1 extra" after it; skipped: "1 skipped" (secondary text).
- Segmented bar = planned count (max 7 segments; above that a plain bar).
- Line 2 (hybrid only): "Rides <d> of <p> · Lifts <d> of <p>" with the same rule; cycling-only / strength-only users see no split.
- Line 3: "Up next: <weekday> · <title> <duration>" from the plan (first future session), or "Nothing else planned this week".
- Tap → Plan on the current week. Test: Home, Plan and Progress show identical numbers for the same data.

## First-time and day 1 (P1-16)
- No plan: card "Build your first week" + "Create my plan"; secondary actions ordered by training mode (strength-only: "Log a lift"
  first). No coach card. Week card hidden.
- Day 1 with a plan: normal planned state; coach slot usually empty (no data) → no card.

## Accessibility (P1-17, P2-18, P2-19)
- All tappable text ≥44 pt tall. Secondary grey raised to ≥4.5:1 on the card colour.
- VoiceOver order: header, banner, today card (title, status, subtitle, primary, why, more), coach, week. Each card one element with
  a summary label plus actions.

## Moved items (P2-21, P2-22)
- Crash banner: stays on Home only while an unsent report exists (as today). No Profile badge in this milestone.
- Insight card, proposals with Accept/Undo, weekly review → COACH slot (above). Movement coverage strip → Plan. Last-week review → Progress.
  Connections card → Profile › Connections (sensor line covers ride days). Next days → Plan (Up next stays). FTP line → Progress.

## Not changed
Coaching calculations, health rules, stored data. Only display, navigation, the new reschedule action, missed (derived, display),
recovery guidance text, and the one-ride-completes-one-plan attribution fix (with test).

## v2.1 — resolutions of QA v2 findings (N1–N13), binding for implementation
- N1: add `plannedDone` (planned sessions completed) and `extra` (completed unplanned) to TrainingLedger.SportWeek / WeekTotals;
  the wording "<plannedDone> of <planned> sessions done · +<extra> extra · <n> skipped" is used identically on Home, Plan and Progress;
  parity test across the three screens. Skipped sessions are removed from `planned` in the split as well (fix mockups).
- N2: no invented evidence counts. The coach card shows the first sentence of the engine's own reason string as its evidence line;
  no "Based on N sessions" until the engine exposes such a field (not in this milestone).
- N3: coach texts in mockups must be real engine outputs: ride example becomes "Tuesday's threshold ride becomes a tempo ride"
  (one-level ease); eased-session example uses an endurance ride 60 → 55 min. Mockups updated before implementation.
- N4: Start ride opens the Ride screen; it never starts recording by itself (recording starts only from Start ride on the Ride screen).
- N5: coach-slot priority adds hybrid coach proposals at priority 1 (same as other proposals) and InsightCard content at priority 4.5
  (after weekly gap, before low confidence).
- N6: an applied ease shows only on the workout card ("Eased by coach — see change"), not again in the coach slot. Health-check caps
  read "Kept easy until your health check".
- N7: fit-without-scrolling applies to the common states; the worst case (health banner + ride sensor line + coach) may scroll; the
  title and primary button stay above the fold.
- N8: illness and supervised-only holds both have "What this means"; the tab-bar centre button keeps its look but opens the hold sheet.
- N9: coach footer and inline links get 44 pt hit areas (padding, not larger text).
- N10: Skip, Move and Swap are disabled while a session is in progress.
- N11: strength Resume always opens StrengthWorkoutScreen.
- N12: several missed sessions: show only the most recent missed one on Home with "+n more in Plan".
- N13: the low-confidence "rate your sessions" card appears only after at least one completed session without a rating.
