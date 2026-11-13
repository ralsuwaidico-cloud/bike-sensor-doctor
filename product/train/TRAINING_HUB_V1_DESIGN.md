# Training Hub v1.0 — Option D (Hybrid Interaction): architecture and design package

Status: **Current Draft — Phase 0 (audit and design) — awaiting owner visual review** · Version 0.1 · 13 Nov 2026 · Level 3
Design direction selected by the owner: Option D. **Not approved for production. Nothing was built.**
No production code, onboarding, workout data, scheduling logic, firmware or release branch was touched.
Code read (read-only): release branch `ios/checkpoint-f-ride`, commit `4e2e9dc`. Nothing was run. Screens are static
drawings with illustrative sample data.

**Two things I could not find:** (1) the "previously reviewed Cyclift Pulse direction" is not in the repository or the
project documents (the only "Pulse" on record is a watch face name), so the two symbols below are my reading of the
brief — please send the reference if one exists; (2) the screenshots of the current Train screens mentioned in the
brief were not attached, so the comparison in §6 is made from the code, not from pictures.

## 1. Images (`design-v10/`)

| File | Shows | Mock-up no. |
|---|---|---|
| `TH1_train_button_symbol_and_states.png` | Two Pulse refinements, in the dock, button states, six themes | 1 |
| `TH2_compact_panel.png` | One workout, multiple, rest day, workout active; Arctic; small iPhone | 2–5, 15, 16 |
| `TH3_compact_panel_special_states.png` | Nothing planned, missed, paused, completed, unsupported sport, sensor unavailable | — |
| `TH4_expanded_hub_profiles.png` | Expanded hub: Profiles A–D, Arctic, small iPhone | 6, 15, 16 |
| `TH5_strength_preparation_logging_rest.png` | Preparation, active logging, rest timer, bodyweight; Arctic; small | 7–9, 15, 16 |
| `TH6_active_cycling.png` | Cycling recording; power meter disconnected; Arctic; small | 10, 15, 16 |
| `TH7_finish_states.png` | Complete, no sets, partial, save failed, discard confirmation; Arctic; small | 11–14 |

## 2. What exists today (audit)

| Area | Today | Where |
|---|---|---|
| Centre button | Opens a full-page "Training Hub" drawn over the current tab; while a ride is recording it opens the Ride screen instead. Icon and label change with today's action ("Ride now" bicycle, "Train now" dumbbell, "Riding") | `ContentView.swift` `RootView`, `RideTabBar.centreCopy` |
| Hub | Today card, missed row, "also today", optional items. It is inserted with **no transition and no animation**, a deliberate fix after taps landed on moving controls (runs 200–206) | `HomeDashboardView.swift` `TrainingHubView` |
| "Other session" | A separate sheet ("Train now") listing planned items and up to four routines | `StrengthWorkout.swift` `TrainNowSheet` |
| Strength preparation | A sheet with the exercise list; **"Why?" and "Swap" buttons under every exercise**; equipment; one insight | `StrengthWorkoutScreen` |
| Active strength | A full-screen cover: next-set card with Log, set rows per exercise, Add set, Pause/Resume, an always-visible Discard, and **three ways to reach Finish** (toolbar, next-set card, bottom button) | `StrengthSessionView`, `StrengthNextSet.swift` |
| Active ride | The Ride screen is a tab; while recording it removes the dock and owns the bottom of the screen | `RootView` (`rideOwnsBottom`), `Ride/` |
| Presentations at the root | Five independent owners (`trainSheet`, `strengthWorkout`, `resumeSession`, `homeSheet`, `holdSheet`) plus the hub overlay, with more sheets nested inside (why, swap, equipment, finish, check-in) | `RootView` |
| Session identity (strength) | One `activeSession`; starting another is refused; it is stored and survives a restart; pause and resume exist; a planned workout already done cannot be started again | `Models.swift` `startStrengthSession` |
| Finish (strength) | Saves only sets ticked done; if none, refuses to save and offers "Mark done without details" or Discard | `finishActiveSession`, `finishSheet` |
| Ride recording | States idle / running / paused / ended; recorded by the board or the phone; any elapsed time can be saved (audit finding) | `RideRecorder.swift` |
| Health hold | The centre button opens a hold sheet when training is paused by the health check | `CyCentreState.hold` |

Classification for the proposed design:

| | Items |
|---|---|
| **Implemented today** | Single active strength session with restart recovery · pause/resume · log a set from one card · rest period per exercise · previous performance text · add set · save only done sets · "mark done without details" · ride recording states · sensor availability with source and quality · health hold |
| **Available for reuse** | `Store.todayAction` / `homeToday` (what is planned, missed, done) · `CyCentreState` · `StrengthSession` / `SetEntry` records · `NextSet` picking logic · `RideRecorder` · templates (saved routines) |
| **Requires modification** | One presentation owner instead of five · centre button always opening the compact panel · active ride presented by Train rather than living in a tab · explicit Undo and Skip-set actions · a single Finish entry · Why/Swap moved to the exercise detail · a save result that can fail visibly · bodyweight with added load stored unambiguously |
| **Future capability** | Assisted bodyweight · interrupted/restored state for a phone-recorded ride (not verified today) · per-sport quick start beyond cycling and strength |
| **Not supported** | Recording running, swimming or any other sport · anything on the Waveshare BikeComputer, Apple Watch or LILYGO watch beyond what each workstream has verified |

Not established in this read: whether a ride and a strength session can be active at the same time today
(`startStrengthSession` does not check the ride recorder). The design below forbids it; the code must be checked.

## 3. UX architecture

### 3.1 Journey

```
Any tab ── tap Train ──▶ COMPACT PANEL (over the dimmed page)
                              │ swipe up            │ Start / Resume
                              ▼                     ▼
                        EXPANDED HUB ── select ──▶ PREPARATION ── Start ──▶ ACTIVE ── Finish ──▶ REVIEW ── Save ──▶ back to the originating tab
                              │ swipe down / Close        │ back                │ minimise              │ Back to workout
                              ▼                           ▼                     ▼
                        compact / dismissed            hub               originating tab, session continues (button shows it)
```

### 3.2 One presentation, six positions

| Position | What it is | Leaves by |
|---|---|---|
| Closed | Nothing presented | Tap Train |
| Compact | Panel over the dimmed page | Swipe up → Expanded · swipe down, tap outside, Close → Closed · Start → Preparation or Active |
| Expanded | Full-height hub | Swipe down → Compact (when at the top of its list) · Close → Closed · select → Preparation |
| Preparation | Pushed inside the expanded hub | Back → Expanded · Start → Active |
| Active | Full screen, owned by the same presentation | Minimise → Closed (session continues) · Finish → Review |
| Review | Compact sheet over the active screen | Back to workout → Active · Save → Closed · Discard (confirmed) → Closed |

One owner decides which position is shown. A request made while a transition is running is held and applied when it
ends; a repeated request for the current position is ignored. Compact and expanded are two heights of the **same**
sheet, never two sheets. The active screen is never stacked on top of the sheet: the sheet finishes leaving first.

Rules:

- Reopening Train shows Compact, except with a session in progress: then Compact shows only that session and Resume.
- An active session can be minimised but never dismissed by a swipe; the only ways out are Finish and (confirmed) Discard.
- Opening Train from any tab keeps that tab underneath; closing returns to it with its scroll position.
- Health hold keeps today's behaviour: the panel shows the hold reason and no Start.
- If an editor with unsaved changes is open when Train is tapped, the approved unsaved-change rule applies
  (documented in `product/plan/PLAN_UI_LAB_SCOPE.md` §9; not yet implemented anywhere).

### 3.3 Session lifecycle

| State | Meaning | Valid actions |
|---|---|---|
| Prepared | Chosen, not started; nothing recorded | Start · back |
| Active | Time is counting; records are being written | Log / undo / skip / add set · change exercise · pause · finish · minimise |
| Paused | Time is not counting | Resume · finish · minimise |
| Review | Finish was requested | Save · save as incomplete · mark done without details (only with no data) · back to workout · discard |
| Saved | One record stored; plan item marked done where it applies | — |
| Discarded | Nothing stored; plan item stays open | — |
| Interrupted | App was closed or suspended mid-session | On next launch → Restored |
| Restored | The same session, same identity, resumed in Paused | As Paused |
| Failed save | Saving did not complete; the session is still held in full | Try again · back to workout |
| Completed without details | Plan item marked done; **no** sets, loads or duration recorded | — |

One session identity from Prepared to Saved. Start from Plan, the compact panel or the hub all address the same
planned item, so a second record cannot be created. Only one session is active at a time, across sports.

### 3.4 Sport differences

| | Strength | Endurance (cycling today) |
|---|---|---|
| Unit of work | Exercise → set | Time, optionally intervals |
| Athlete input during the session | Reps, load, log | None required |
| Live values | Athlete-entered | Sensor-measured only; missing shown as "—" with the reason |
| Rest | Timer strip after a logged set | Part of the interval structure |
| Record | Exercises, sets, reps, external load, completion, duration, source, timestamps | Samples, duration, distance, sources, gaps |
| Bodyweight | "Bodyweight" or "Bodyweight + added load"; never a forced kilogram entry | — |

### 3.5 Boundaries

- **Plan** owns schedules, programmes, templates and changes. Train shows today's and the next session and a missed
  session, but moving one opens Plan and follows its confirmation rules. No automatic rescheduling.
- **Progress** reads saved, valid records. "Mark done without details" and quick logs never become measured performance.
- **Hardware** workstreams are separate; a phone recording screen claims nothing about them.

## 4. The Train button

Two refinements of one mark (`TH1`): **Pulse A — Line** (one upright peak on a level line) and **Pulse B — Forward**
(the peak leans forward and ends in a point). Single-weight stroke, no glow, no animation, readable at dock size, drawn
in the theme's own colours; in High Contrast it is the same stroke on the accent disc. The dock's structure is unchanged.

| State | Indication | Real state behind it |
|---|---|---|
| Idle | Symbol | — |
| Pressed | Slightly smaller and darker | Touch down |
| Compact panel open | Thin ring | Panel is up |
| Expanded hub open | Ring; symbol becomes a down chevron | Hub is up; tap closes |
| Workout active | Discipline-coloured ring and running time under the button | A session is being recorded |
| Workout paused | Dashed ring, stopped time | Session paused |
| Awaiting completion | Ring and "Finish" | Finish was requested and not concluded |

No red dot, no warning colour. A missed session is stated in words inside the panel, not on the button.

## 5. Interaction details

| Gesture | Result |
|---|---|
| Tap Train | Compact panel |
| Swipe up on the panel / tap the cue | Expanded hub |
| Swipe down on the hub (at top of list) | Compact |
| Swipe down on compact · tap outside · Close | Dismiss |
| Tap Start | Planned strength → Preparation; a session in progress → Active; ride → ride preparation |
| Tap an exercise row (preparation) | Exercise detail: prescription, **why it was prescribed**, **request an alternative** |
| Log set | Stores the set, starts the rest strip, shows "Undo" until the next log |
| Finish | Opens Review; never ends the session by itself |

Relocated actions: Why? and Swap → exercise detail (one tap on the row) · equipment and "why this workout" → the "•••"
menu on preparation · Discard → Review sheet only · Add set / Skip set → small text actions under Log.

Accessibility: every row and button at least 44 pt; the panel announces "Train, today, compact" / "expanded" and offers
"Expand" and "Close" as actions so no swipe is required; the steppers are adjustable elements; Reduce Motion changes
the panel's movement to a fade; text sizes scale and the compact panel grows up to the expanded height when needed.

## 6. Comparison with today (from the code; no screenshots were available)

| | Today | Proposed |
|---|---|---|
| Presentation owners at the root for Train-related flows | 5 plus the hub overlay | 1 |
| Ways to reach Finish in an active strength session | 3 | 1 |
| Visible buttons under each exercise on preparation | 2 (Why?, Swap) | 0 — the row opens the detail |
| Discard during a strength session | Always visible beside Pause | Inside Review, confirmed |
| Taps from the centre button to the preparation screen | 2 (hub, then Start) | 2 (panel, then Start) — **no reduction** |
| Page behind when Train opens | Covered | Visible, dimmed |

I have not counted taps or screens for flows I could not trace with confidence; those are left out rather than estimated.

Preserved: every function in §2. Gaps to decide: where the post-workout check-in appears (today it replaces the finish
sheet); where the coach's single insight on preparation goes; whether the Ride tab's settings and layouts stay reachable
during a ride.

## 7. Risks and conflicts

1. **Animated sheet versus the existing no-animation fix.** The current hub was made transition-free because taps hit
   moving controls. A rising panel reintroduces motion and must be proven with the same kind of repeated-tap tests.
2. **Shared presenter work is unfinished.** The UI Lab presenter (proto/ui-lab) has not had two consecutive clean runs;
   Round 2 is on hold. Training Hub must not merge or bypass it; its prototype needs its own isolated presenter instance.
3. **Active ride ownership.** Today the Ride tab owns the screen bottom during recording; moving it under Train changes
   an approved rule (RA-01) and needs an impact assessment.
4. **Data model.** "Bodyweight + added load", assisted work, explicit skipped sets and a failed-save state are not
   represented today; they need a schema assessment before any production proposal.
5. **Unverified:** ride restoration after the app is closed; simultaneous ride and strength sessions.

## 8. Acceptance criteria (for a future prototype; Phase 2 is not authorised)

Layout: compact panel shows one primary session and one Start; it fits a small iPhone without scrolling at default text
size; no second large Start; no sport the athlete did not select; unsupported sports are marked and offer no recording.
Navigation: every transition in §3.2 works from all four tabs; repeated and rapid taps never produce two presentations,
a lost request or a stuck screen; closing returns to the originating tab and scroll position.
Recording: one session identity; no duplicate record from any entry point; nothing recorded is lost when a presentation
closes, the app is suspended or saving fails; unlogged sets are never marked complete; "mark done" stores no measurements.
Safe termination: an active session cannot be ended by a swipe; Discard always asks when data would be lost; Save and
Discard are never equally prominent.
Responsiveness: the panel responds to the first tap; no control is tappable while it is still moving to a different place.
Accessibility: 44 pt targets; VoiceOver can do everything without a swipe gesture; Dynamic Type to accessibility sizes
without truncation of the session name or Start; Reduce Motion honoured; High Contrast legible.
Each is to be shown on standard and small simulators first; none of it is device validation.

## 9. Open questions

1. Which Pulse refinement — A or B — and is either close to the direction you reviewed?
2. Should Start on a planned strength workout open Preparation (as drawn) or go straight to the active screen?
3. May the active ride move from the Ride tab to the Train presentation?
4. Is a minimised active session allowed (browse the app while recording), or must the active screen stay in front?
5. Where should the post-workout check-in sit: after Save, or inside Review?
