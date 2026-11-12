# Plan v2.0 — product and UX specification

Status: **Current Draft** · Version 0.1 · 12 Nov 2026 · Level 3 (product specification)
Source: `docs/cyclift-governance`, `product/plan/PLAN_V2_SPECIFICATION.md`
Basis: owner brief "Plan Tab Redesign v2.0" (12 Nov), Master Project Instructions v2.0, Brand Book v0.2.

**Specification only.** No code, UI Lab prototype, production branch, TestFlight build, database or firmware was
touched. Nothing here is implemented unless a row says "Exists today".

Reading key used throughout:
**Exists** = in the production app today (source read on the release branch, commit `4e2e9dc`; not re-tested for this document) ·
**Partial** = part exists, the rest is named · **Future** = not built · **Design** = new in this specification.

Wireframes (grey-scale, layout only — not visual design): `wireframes/W1…W6`.

---

## 1. What Plan is for

Plan is where the athlete decides future training. It answers: what am I training for · what program gets me there ·
when can I realistically train · what exactly is scheduled · what happens when my schedule changes · what adjustments
keep me on track · how do I create and reuse workouts.

| Destination | Job | Plan must not |
|---|---|---|
| Home | Current condition and summary | repeat its rings, cards, graphs or coach card |
| **Plan** | **Decide what happens next** | — |
| Train | Execute | contain a second execution engine |
| Progress | Analyse what was done | contain analytics or charts |

### No-duplication check (every item of the brief's §2)

| Home component | In Plan v2.0? |
|---|---|
| Consistency, Training Mix, Recovery circles | No |
| Sleep card; heart-rate, power, volume or performance charts | No |
| Endurance and Strength summary cards | No |
| "Next session" dashboard summary | No — the selected day's own rows carry the session |
| Seven-day status strip as a second dashboard | No — Plan has a **date selector**: it selects a date and shows which disciplines are scheduled; it shows no completion state, percentages or ticks |
| Compact Coach insight card | No — a one-line "planning suggestion" row appears only when a pending proposal exists |
| Getting Started checklist; completion donuts; weekly scorecards | No |

Removed from today's Plan for the same reason: the completion ring with "x of y sessions done" and recorded / planned minutes
(audit D1) and the separate Next-session card (audit D2).

---

## 2. Existing Plan functionality (audit summary)

Full audit: `ui-lab/plan/PLAN_CURRENT_UI_AUDIT.md` (project). Evidence for "works": build-216 completeness audit.

| Capability | State today |
|---|---|
| Weekly view of actual sessions, per-day rows, several sessions per day | Exists |
| Open a session; start a ride or strength session from it | Exists |
| Edit a session (type, body region, duration, supersets) with before / after review | Exists — one path has an unvalidated defect (Defect 6) |
| Swap two days ("Move"); replace with an alternative ("Swap"); remove; add a session | Exists |
| Skipped and missed states, derived per session | Exists |
| Weekly template: per weekday, one or more assignments (sport, type, minutes, fixed or flexible) | Exists (`WeeklyAvailability`, `DayAssignment`) |
| Available minutes per day; weekly hour budgets per sport; conflict report with fixes | Exists (`fitReport`, Fix plan) |
| Strength routines: create, edit, assign to a session, default per weekday | Exists (`WorkoutTemplate`, `weekdayRoutines`) |
| Goals: several goals and a primary goal | Exists (`GoalID`, `primaryGoal`) — no event date, no program object |
| Easier week every n-th week; return after a break; training pause (unwell, injured, away) | Exists (planner rules) |
| Plan changes as versions with Undo | Exists (`PlanVersion`) |
| Coach proposals with approval | Exists (rules-based). Small increases can apply automatically today (`autoAdapt`) — to change under Coach Decision 1 |
| Scheduled time or time window for a session | **Future** — sessions carry a date only |
| A record that a session was moved (from → to) | **Partial** — only as a plan version |
| Programs, phases, weekly targets, events with dates, feasibility of an event | **Future** |
| Saved endurance workouts (reusable interval structures) | **Future** — ride steps are generated from the session type |
| Weekly planning review | **Partial** — a `WeeklyReview` structure exists in the coach code; no planning workflow (not audited in depth) |
| External calendar | **Future** — no calendar access exists |
| Running and other disciplines | **Future** (Coach Decision 11: running next, as logging and integration) |

---

## 3. Borrowed concepts — mapping and honesty

What the two products do is taken from their own public pages (WHOOP "Weekly Plan"; Garmin Coach), read 12 Nov 2026,
and from the owner's brief. I have not used either product for this document, and no claim of superiority is made.

| Concept | Problem it solves | Where it lives in Cyclift | How it avoids Home | Today | Needs |
|---|---|---|---|---|---|
| **WHOOP — weekly targets** (members pick weekly goals; a custom plan is possible) | A week needs a clear, realistic definition of "enough" | Program details › Weekly prescription (sessions per discipline, time, rest days) | Stated as a prescription to plan against, not a progress score | Partial: budgets and template exist | Future: targets as a program property |
| **WHOOP — accountability** (weekly summary; "consistency, not perfection") | A missed session should lead somewhere | Missed-session choices on the day; Weekly Planning Review | Choices and consequences for the remaining week — no badge, no percentage | Partial: missed state exists | Design + Future: resolution record |
| **WHOOP — recovery-aware guidance** | Plan should respect how the athlete is doing | Inside a Coach proposal's "Why" | A reason in a proposal, never a recovery widget | Partial: recovery advice exists, advice-only | Future: any use of a recovery number needs a validated method |
| **Garmin — training programs** (adaptive and prebuilt plans; run, cycling, strength) | Sessions should add up to something | Goal & Program screen | A detail screen behind one row | Partial: goal-shaped weeks, easier weeks | Future: program object, phases |
| **Garmin — event preparation** | Work backward from a date | Goal & Program › Event | Same | Future | Future; marathon also needs running support |
| **Garmin — structured workouts** | Know exactly what to do | Session planning detail; Routines | Planning detail, execution stays in Train | Exists for strength routines and generated ride steps | Future: saved endurance workouts |
| **Garmin — adaptive coaching** (plans adjust; explain why a workout was suggested) | Keep the plan true to reality | Coach proposals with approval | Proposal detail | Partial: rules-based adaptations | Future: program-level adaptation |
| **Garmin — training calendar** | See and move the plan in time | Weekly Calendar | A scheduling tool | Exists (week) | Future: external calendars — not described on the page read, not assumed |
| **Cyclift — life-aware scheduling** | Training must fit real availability | Recurring Plan + availability + windows + temporary changes | — | Partial: per-day minutes, budgets, pause | Future: windows, date-range exceptions |
| **Cyclift — recurring vs actual week** | Change one week without rebuilding the plan | The two sections | — | Partial: both exist in data, not as two clear places | Design |
| **Cyclift — approval before change** | Trust | Every consequential change previews first | — | Exists | — |
| **Cyclift — short-session flexibility** | A short session beats a skipped one | "Shorten or replace" | — | Partial: alternatives list, shortening in Fix plan | Design |

---

## 4. Information architecture

```
Plan (tab)
├─ Header: "Plan" · More menu ─────────► Routines · Availability · Plan history · Plan next week
├─ Program row ───────────────────────► Goal & Program (screen)
│                                         ├─ Goals (primary, secondary) ► sheet
│                                         ├─ Event ► event setup flow (screen, Future)
│                                         ├─ Phase · Weekly prescription · Weekly time · Milestones
│                                         └─ Change goal or program ► preview ► approve
├─ Selector: Weekly Calendar | Recurring Plan        (exactly two; one rendered at a time)
│
├─ Weekly Calendar
│   ├─ Week bar ‹ range ▾ ›  (▾ = jump to date) · "Today" when away from the current week
│   ├─ Date selector (7 dates)
│   ├─ Planning suggestion row (only when a proposal is pending) ► Coach proposal detail
│   ├─ Selected day: header + "Add session" ► Add session (sheet)
│   └─ Session rows ► Session planning detail (sheet)
│        └─ ••• menu: View · Edit this session · Move · Replace · Assign routine · Remove from this week ·
│                     Start in Train · Ask Coach      (only the valid ones)
│
└─ Recurring Plan
    ├─ Seven weekday rows ► Change <weekday> (sheet) ► scope ► preview ► approve
    ├─ Availability & preferences ► screen (existing week editor, regrouped)
    └─ Feasibility line (only when something does not fit) ► Fix (existing Fix plan)
```

Depth: every primary action is at most two taps from the landing screen. Sheets for short tasks; full screens only for
Goal & Program, Routines, Availability and Plan history.

---

## 5. Plan landing (wireframe W1, W6)

Order, top to bottom — nothing else is on the landing screen:

| # | Element | Height (pt) | Behaviour |
|---|---|---|---|
| A | Title "Plan" + More menu | 40 | More: Routines · Availability · Plan history · Plan next week. No search (nothing searchable justifies it yet) |
| B | Program row | 44 | One line: program or goal name · short qualifier. Tap → Goal & Program. No program: "Set a goal or program" |
| C | Selector | 40 | Weekly Calendar (default) · Recurring Plan. The last choice is remembered for the session of use; a fresh launch opens Weekly Calendar |
| D | Section content | — | Only the selected section is rendered |

Design estimates from the wireframe geometry (points; **not measured on a device**):

| Device | Selected-day list starts at | Dock line | Session rows visible without scrolling |
|---|---|---|---|
| Small (375 × 667) | y 346 with a suggestion row · 296 without | 583 | 3 · 4 |
| Standard (393 × 852) | y 385 | 742 | 5 |
| Large (440 × 956) | y 388 | 846 | 7 |

So title, program, selector, week, dates, the day's sessions and "Add session" are all on the first screen on every
size, with touch targets of 44 pt or more.

---

## 6. Weekly Calendar (W1, W2)

**Purpose:** manage the actual scheduled sessions of a real week.

### 6.1 Date selection
- Week bar: previous / next week; the range label opens a date jump (month grid) for direct navigation; "Today"
  appears when another week is shown.
- Seven dates: weekday letter, day number, and **discipline indicators only** — a round mark for endurance, a square
  mark for strength (shape as well as colour), a dash for scheduled rest, nothing for an empty date. At most two marks;
  a third session shows "+". **No completion, no ticks, no percentages** — that is Home's job.
- Today has an outline; the selected date is filled. Today is selected on opening.
- Spoken label per date: "Wednesday 11 November, today, selected, 2 sessions: ride, strength".

### 6.2 Selected-day sessions
Header: date · "Add session". Then one compact row per session (60 pt):

`[discipline icon]  Title  ·······  status word   •••`
`                   duration · time or window · routine or place`

- Status is one quiet word: Planned · In progress · Done · Missed · Skipped · Moved. No colour judgement.
- Tap the row → Session planning detail. Tap ••• → contextual menu.
- Several sessions: several rows, in scheduled order. Long titles truncate on one line; the full title is in the detail.
- Scheduled rest: a single "Rest day" row. Empty date: "Nothing scheduled · Add session". No paragraphs.

### 6.3 Session planning detail (sheet, W4)
Title · date, time or window, duration, place · the workout (exercise list with sets × reps, or ride structure with
zones and intervals) · "Why this session" in one line (the coach's stored reason) · primary action · Move / Edit /
Replace / More.

### 6.4 Actions and when they are valid

| Action | Planned (future / today) | In progress | Done | Missed | Skipped |
|---|---|---|---|---|---|
| View workout | ✓ | ✓ | ✓ (opens the record) | ✓ | ✓ |
| Start in Train | today only | Resume | — | — | — |
| Edit this session | ✓ | — | — | — | — |
| Move session | ✓ | — | — | Reschedule | Restore + move |
| Replace workout | ✓ | — | — | ✓ | — |
| Assign routine | strength only | — | — | — | — |
| Remove from this week | ✓ | — | — | — | — |
| Skip | ✓ | — | — | ✓ | — |
| Ask Coach | ✓ | — | — | ✓ | — |

"Start in Train" hands over to the existing execution flow; Plan executes nothing itself.

### 6.5 Add session (sheet, W4)
Discipline · Workout or routine · Date (prefilled with the selected date) · Time ("Flexible" by default) · Duration
(prefilled from the routine or the athlete's usual length). Extra fields appear only when needed (body region for a
strength session without a routine). One button: "Add to this week". States that the recurring plan is not changed.

### 6.6 Moving a session (sheet, W4)
1. Choose the destination date, and optionally a time or window.
2. Checks, shown as short lines: fits that day's available time · other sessions already on that day · documented
   density rules (for example two hard sessions on consecutive days) · rest-day effect.
3. Affected sessions listed.
4. Preview → "Move this session" or "Choose another day". Nothing is saved before approval.
5. Applies to **this occurrence only**; the recurring plan is untouched; the session shows "Moved", and the move is
   recorded in Plan history with Undo.

### 6.7 Missed sessions (W2)
A missed session keeps its place and its status. Its row offers: **Reschedule… · Shorten or replace… · Skip this
session · Ask Coach · Leave for now.** Nothing is moved automatically and the rest of the week is never loaded up
silently. The record stays truthful: missed stays missed unless the athlete reschedules (then: "Moved") or skips.

---

## 7. Recurring Plan (W3)

**Purpose:** the athlete's normal training structure — a template, not a calendar and not a performance view.

### 7.1 Weekly template
Seven rows (46 pt): `Mon  [icon]  Full Body A  ········  30 min · evening  ›`. Rest days read "Rest". Two sessions on
a weekday show as "Full Body A + Zone 2 Ride". No dates, no status, no history.
All seven rows and the "Availability & preferences" row fit above the dock on all three sizes (design estimate:
content ends at y 530 / 569 / 572 against dock lines 583 / 742 / 846).

### 7.2 Editing a weekday (sheet, W4)
Workout or rest · duration · window (morning / midday / evening / flexible, or a time) · add a second session.
**Scope is always asked and always explained:**

| Scope | Effect |
|---|---|
| Only one date | Becomes a change to that week's session; template unchanged |
| From a date until a date | A temporary exception to the template |
| All future occurrences | The template changes; future generated sessions follow |

Then a preview of what will change, and approval. Completed sessions are never modified. Future sessions the athlete
edited by hand are kept and listed as "kept as you set it" (the planner already protects hand-edited and fixed sessions).

### 7.3 Availability & preferences (screen)
Reuses what onboarding and Profile already hold — nothing is asked twice: training days · available time per day ·
windows · unavailable days · two-a-day allowed · weekly time per discipline · equipment · split · supersets ·
priorities. Each row opens the existing editor for that item.
Temporary change ("I'm away 20–27 Nov", "evenings only next week") is a date-range exception, not a new plan.

### 7.4 Feasibility
Shown as one line under the template only when something does not fit: a session longer than the day's time · more
sessions than days · budget exceeded · a documented density rule · a conflict with the program's prescription.
"Fix" opens alternatives (the existing Fix plan, extended). Never a wall of warnings.

---

## 8. Goal & Program (W5)

Reached only from the program row. One screen:

| Block | Rows | Today |
|---|---|---|
| Goals | Primary · Secondary · Event (type, date) | Goals exist; event date Future |
| This program | Phase · Weekly prescription (sessions per discipline, rest days, time; intensity distribution when defined) · Milestones | Future (phase today = the planner's easier-week cycle only) |
| Action | Change goal or program → preview → approve | Goal change with preview exists |

**Event setup (Future):** event type and date → baseline (recent training, stated experience; missing information is
named, not assumed) → feasibility with a plain statement when the goal is not realistic in the time available, and the
nearest realistic alternative → proposed phases working backward from the date → sessions fitted to real availability
→ preview → approval. No tapering or event-specific coaching is claimed until built and tested.

Weekly targets live here, as the prescription. There is no target scorecard on the landing screen.

---

## 9. Routine library (W5)

One library, one entry point: **More › Routines**, and the same screen when choosing "Assign routine" or "Workout or
routine" in a sheet.

| Action | Where | Today |
|---|---|---|
| Create, edit a routine | Library | Exists (strength) |
| Duplicate | Row menu | Design (small) |
| Assign to a scheduled session | Session ••• › Assign routine | Exists |
| Use in the recurring plan | Weekday sheet › Workout | Exists as weekday default |
| Replace for one occurrence | Session › Replace | Exists (per-session entries never change the routine) |
| Save a completed workout as a routine | Session record › Save as routine | Design |
| Endurance workouts (saved interval structures) | Library, second group | Future |

Routine management is removed from every other place in Plan (today it is in the toolbar menu and in "Manage plan").

---

## 10. Weekly Planning Review (W5)

A workflow, not a card. It is offered — never forced — by the planning suggestion row or from More › Plan next week,
when one of these is true: the coming week is close · availability changed · the plan has unresolved conflicts · the
Coach has a meaningful proposal. When nothing needs attention, nothing is shown.

One sheet, five short blocks: **Scheduled** (sessions, time, rest days) · **Fits your availability?** (only the
misfits) · **Conflicts** · **Coach suggests** (each with Preview) · **Needs your approval** (count).
Actions: Review changes (→ proposal detail, where each change can be approved, modified, postponed or declined) ·
Keep the schedule as it is · Not now.

---

## 11. Coach in Plan

Sequence: **Observe → Explain → Recommend → Preview → Request approval.**

- Plan shows **one compact row** — "1 planning suggestion for this week · Review" — only when a pending, actionable
  proposal exists. It is not Home's coach card and carries no advice text.
- It opens the **same proposal detail** as the Coach conversation (what will change · why · expected benefit ·
  possible impact · approve / not now / decline). One review design in the whole app.
- "Ask Coach" on a session opens the Coach conversation at a prepared, rules-based set of options for that session
  (reschedule, shorten, replace). It is **not** a free-text chatbot; two-way messaging is Future.
- Capabilities and their state: suggest a realistic week (Partial: week builder) · missed-session adjustments (Partial)
  · conflicts (Exists: budgets; Future: time windows) · shorter alternatives (Partial) · routine changes (Exists:
  exercise-level insights) · goal trade-offs (Partial: priority) · event preparation (Future) · feasibility of future
  training (Partial).
- The Coach is rules-based today and is described that way.

---

## 12. Editing and rescheduling rules

1. One occurrence never changes the recurring plan silently.
2. A recurring change always states its scope (one date · a period · all future).
3. Every consequential change is previewed; nothing is saved before approval; Cancel leaves everything equal.
4. Completed sessions and their records are never modified.
5. Hand-edited and fixed sessions are kept through any regeneration and are listed as kept.
6. A missed session is never auto-moved; the remaining week is never auto-loaded.
7. Increases in load, volume or frequency are proposals; they are not applied automatically (Coach Decision 1).
8. Rest days are preserved unless the athlete chooses otherwise; a move onto a rest day is called out in the preview.
9. Every applied change is a history entry with Undo; Undo is itself previewed and never overwrites a later change.
10. Session states are distinct and never rewritten in history: planned · scheduled · completed · missed · skipped /
    removed · rescheduled (Instructions §6).

### State transitions

```
template row ──generate──► PLANNED ──(date in a real week)──► SCHEDULED
SCHEDULED ──start──► IN PROGRESS ──finish──► COMPLETED            (record kept forever)
SCHEDULED ──day passes, not done──► MISSED ──reschedule──► RESCHEDULED (new date; origin kept)
                                     MISSED ──skip──► SKIPPED
                                     MISSED ──replace/shorten──► SCHEDULED (replacement; original kept as missed)
SCHEDULED ──move──► RESCHEDULED ──► behaves as SCHEDULED on the new date
SCHEDULED ──skip──► SKIPPED ──restore──► SCHEDULED
SCHEDULED ──remove from this week──► REMOVED (history entry; Undo)
```

---

## 13. Twelve journeys

Each: Start · Actions → transitions · Data change · Confirmation · Error / cancel. "(F)" marks a Future step.

| # | Journey | Start | Actions and transitions | Data change | Confirmation | Error / cancel |
|---|---|---|---|---|---|---|
| 1 | Create a recurring hybrid week | Plan › Recurring Plan (empty template) or onboarding | Tap a weekday → sheet: workout, duration, window → repeat; or "Suggest a week" from availability → preview of the generated week | Template saved; coming weeks generated | Preview → "Use this week" | Feasibility line if days and time do not fit; Cancel saves nothing |
| 2 | Change one workout only | Weekly Calendar, a date selected | Session ••• › Edit this session → sheet (duration, routine) → review before / after | That session only; template unchanged; history entry | "Apply to this session" | Blocked edits explain why and offer an alternative; Cancel leaves the session equal |
| 3 | Permanently change availability | More › Availability, or Recurring Plan › Availability & preferences | Change days / time → preview of how future weeks change, listing kept sessions | Template and availability; future generated sessions | Approve in preview | Conflicts shown with fixes; Cancel keeps the old availability |
| 4 | Miss a workout and reschedule | Weekly Calendar, the missed date | Row shows "Missed" + choices → Reschedule… → pick date → checks → preview | Session gets the new date and "Moved", origin kept; history entry | "Move this session" | No valid day: says so, offers Shorten / Skip / Leave; Cancel leaves it missed |
| 5 | Replace 60 min with a shorter alternative | Session ••• › Replace workout (or Missed › Shorten or replace) | List of shorter alternatives of the same intent (e.g. 30 min Zone 2) → preview | That session's type and minutes; history entry | Apply | If no shorter version exists for that type: says so; Cancel |
| 6 | Create and assign a strength routine | More › Routines › New | Name → add exercises, sets, reps → Save → row menu "Assign to a day" → pick session or weekday | New routine; session's routine or weekday default | Saved toast; assignment asks scope when it is a weekday | Empty routine cannot be saved (says what is missing); Cancel discards after one confirmation |
| 7 | Two workouts on one day | Weekly Calendar, a date with one session | Add session → sheet → "Add to this week" | Second session on that date, ordered by time or as added | Row appears; note if the day's available time is exceeded | Blocked only if two-a-day is off in availability — offers to allow it for this date |
| 8 | Prepare for a marathon **(F)** | Program row › Goal & Program › Event › Add | Type Marathon, date → baseline questions → feasibility → phases → fit to availability → preview | Event, program, phases, generated sessions | Approve program | Not realistic: plain warning + nearest realistic option; running must be supported first; Cancel creates nothing |
| 9 | Cycling event while keeping strength **(F)** | Goal & Program | Add event (cycling) → choose "maintain strength" → prescription shows fewer strength sessions and why → preview | Program with two disciplines; primary goal = event | Approve | Time too short for both: trade-off shown; athlete chooses priority; Cancel |
| 10 | Approve a Coach weekly adjustment | Weekly Calendar, suggestion row | Review → proposal detail: changes, why, benefit, impact → approve all, or approve one and decline another | Only approved changes; history entries; coach timeline records decision | Approve / Not now / Decline | Not now keeps it open; Decline closes it and is remembered; nothing changes without approval |
| 11 | No recovery device, no calendar | Any Plan screen | Everything works from the schedule and logged sessions; proposals give schedule-based reasons only | — | — | No recovery text is invented; no "connect" nagging on Plan |
| 12 | Event date changes **(F)** | Goal & Program › Event | Edit date → program recalculated → preview: phases shortened / extended, sessions kept, feasibility re-stated | Event date, phases, future sessions; completed weeks untouched | Approve | Date now too close: warning + options (reduce target, keep date as reference); Cancel keeps the old program |

---

## 14. Reuse map

| New surface | Reuses (production) | New work |
|---|---|---|
| Date selector, selected-day rows | `planWeekSummary`, week overview, `PlanDay`, session status | Layout; discipline marks; row design |
| Session planning detail | `WorkoutDetail`, strength session screen, stored rationale ("why") | Regrouping; wording (Move / Replace) |
| Add session | `AddWorkoutSheet` | Routine picker inside; time field (F) |
| Move with preview | `swapDays`, change proposals, `SessionChangeSheet` | Move to any day (today: swap only); checks |
| Missed choices | Session status; alternatives; skip | The choice list; resolution record |
| Recurring Plan | `WeeklyAvailability`, `DayAssignment`, `weekdayRoutines`, week builder | The seven-row view; scope question |
| Availability & preferences | Week editor, equipment, strength preferences, profile | Regrouping only; windows and exceptions (F) |
| Feasibility | `fitReport`, `BudgetFix`, Fix plan sheet, onboarding feasibility | More rules |
| Goal & Program | Goals, primary goal, goal change with preview | Program, phases, event (F) |
| Routines | `TemplatesView`, routine editor, weekday routines | Duplicate; single entry point; endurance workouts (F) |
| Plan history | `PlanVersion`, `PlanVersionsView`, Undo | More causes |
| Planning suggestion + proposal | Pending proposals, review sheet; Coach conversation design | One shared proposal detail |
| Weekly Planning Review | `WeeklyReview` (coach), fit report | The workflow |
| Execution | Train / ride recorder / strength session | None — handover only |

---

## 15. Data-model changes needed (not implemented, not designed in detail)

All additive; none changes existing records. Each needs an impact assessment before work (Instructions §10).

| # | Addition | For | Notes |
|---|---|---|---|
| 1 | Session: optional scheduled time and / or window | Time in rows, move checks | Today the date carries a fixed nominal hour |
| 2 | Session: origin date and "moved" flag | Rescheduled state | Today only visible as a plan version |
| 3 | Session: missed resolution (unresolved · rescheduled · skipped · replaced) | Missed handling | Must never rewrite history |
| 4 | Session: optional place / context ("Gym", "Home") | Row detail | Could derive from equipment preset |
| 5 | Template: window per assignment; date-range exceptions | Life-aware scheduling | |
| 6 | Program: name, goal, start, end, phases, weekly prescription | Goal & Program | |
| 7 | Event: type, date, name, target | Event preparation | |
| 8 | Session link to program and phase | "Assigned program" | |
| 9 | Saved endurance workout (steps, zones, cadence) | Routine library | Ride steps are generated today |
| 10 | Plan history: causes for move, routine, program, event, review | Traceability | Extends an existing list |
| 11 | Coach event store (observation, proposal, decision, outcome) | Shared proposal detail and timeline | Same as the Home v2.3 integration map |
| 12 | Discipline list beyond cycling and strength | Marathon, triathlon | Coach Decision 11 |

Affected components to assess: local store and its migrations, cloud sync, Apple Watch companion, the BikeComputer
link (planned ride steps), the detachable Watch's planned-session data, and the production UI tests that use Plan's
identifiers (25 references).

---

## 16. Phased implementation plan (every phase needs separate authorisation)

| Phase | Content | Depends on |
|---|---|---|
| 0 | Approve this specification | — |
| 1 | UI Lab prototype: landing, Weekly Calendar, Recurring Plan, sheets — sample data, interaction tests | Phase 0; Home sign-off not required |
| 2 | Production Plan restructure **with existing data only**: two sections, date selector, selected-day rows, one menu, single routine entry, wording; remove ring and Next-session card | Release stabilised; Defect 6 resolved; integration review |
| 3 | Scheduling data: time and windows, moved / missed records, move to any day with checks | Model items 1–5 |
| 4 | Routines: duplicate, save-as, endurance workouts | Item 9 |
| 5 | Goal & Program without events: program object, prescription, phases as information | Items 6, 8 |
| 6 | Weekly Planning Review + shared proposal detail + coach events | Item 11; Adaptive Lifestyle Coach Phase 1 |
| 7 | Event programs: cycling first; running-based events after running support; feasibility | Items 7, 12 |
| 8 | External calendar (with consent) and program-level adaptation | Separate design and privacy review |

---

## 17. Six-theme consistency checklist

For each of Obsidian, Arctic, Ocean, Forest, Sandstone, High Contrast (prototype tokens, Brand Book §4.3):

- [ ] Only existing tokens; no new colour for Plan.
- [ ] Discipline marks: endurance and strength tokens **and** different shapes (round / square).
- [ ] Selected date: accent fill with on-accent text; today: outline.
- [ ] Status words use text colours only — no success / danger colouring of Done / Missed.
- [ ] Rows separated by spacing or hairlines; borders only in High Contrast.
- [ ] Primary button and selected segment meet text contrast (script check).
- [ ] Sheets, menus and the date jump use the theme's surfaces.
- [ ] Nothing depends on a gradient to be legible.

Production note: the app ships two palettes today; six-theme checks apply to the UI Lab until a migration is authorised.

## 18. Small-screen and accessibility review (design level)

| Topic | Finding |
|---|---|
| Initial content | All six landing elements visible on all three sizes (§5 table) |
| Scrolling for primary actions | None needed to select a date, open a session or add a session, up to 3 (small) / 5 / 7 sessions |
| Row and card heights | Rows 44–60 pt; no card taller than 60 pt on the landing screen |
| Dock overlap | Content ends above the dock line; lists scroll under a bottom inset equal to the dock |
| Truncation | Program name truncates on the small size (W1) — full name in Goal & Program; long session titles truncate on one line (W2) |
| Touch targets | Every control ≥ 44 pt; the ••• menu has its own 44 pt target separate from the row |
| Empty and rest states | One row each (W2) |
| Multiple sessions | Rows stack; a fourth row scrolls on the small size |
| Dynamic Type | At accessibility sizes the selector stacks, the program row wraps to two lines, session rows grow to three lines, the date selector keeps seven cells with capped text and full spoken labels (W6). Estimate: two sessions still fit above the dock on the small size |
| Colour | Never the only signal: shapes for disciplines, words for status |
| VoiceOver order | Title, More, program, selector, week controls, dates, suggestion, day header, Add, sessions |
| Drag and drop | Not used in v2.0: Move is a menu action with a preview, which is reliable and accessible |

**Not verified:** everything in this section is a design estimate from wireframe geometry. Nothing was built, run on a
simulator, or tried on a physical iPhone or with VoiceOver.

## 19. Acceptance criteria (for a future prototype or build)

1. Exactly two primary sections; only one rendered at a time; Weekly Calendar is the default.
2. None of the Home components in §1 appears anywhere in Plan.
3. On the smallest supported iPhone, at default text size, the date selector, the selected day's first session and
   "Add session" are visible without scrolling.
4. Every control is at least 44 pt and has an accessible name and value.
5. The date selector shows no completion information.
6. Selecting each of seven dates shows that date's sessions; previous / next / jump / Today work.
7. Every session action appears only in the states of §6.4.
8. Moving, editing or replacing one occurrence leaves the recurring template byte-equal.
9. Every recurring edit asks for scope, and each scope changes exactly what §7.2 says.
10. No change is saved without passing a preview; Cancel leaves stored data equal.
11. A missed session is never moved or replaced without an athlete action.
12. Completed sessions are never altered by any Plan action.
13. Every applied change appears in Plan history with a working, previewed Undo.
14. The planning suggestion row is absent when no proposal is pending.
15. The proposal detail opened from Plan is the same component as in the Coach conversation.
16. Routines are managed in one place only.
17. Layout holds at the largest accessibility text size without clipped or overlapping text.
18. All six themes pass the contrast script; High Contrast uses borders.
19. Future capabilities (events, programs, calendar, adaptive programming) are not presented as available.
20. Evidence is reported by level: simulator results are not called device results.

## 20. Decisions needed before a prototype

1. **Strip without completion.** The date selector shows disciplines only, so "what did I finish this week" is not on
   Plan at all. Agree, or should the selected day's rows be the only place status appears (as specified)?
2. **Removing the ring and Next-session card** from Plan (they exist today and are tested). Agree?
3. **Wording:** "Move session", "Replace workout", "Remove from this week" (today: Move = swap two days, Swap, Remove).
4. **Move to any day** instead of today's swap-two-days. This is new behaviour, not just layout.
5. **Time model:** flexible windows (morning / midday / evening) plus optional exact time — enough for v2.0?
6. **"Ask Coach"** as a prepared option list, not free text, until two-way messaging exists. Agree?
7. **Marathon and triathlon** depend on running and swimming support. Should the event flow launch with cycling and
   strength events only?
8. **Place label** ("Gym", "Home") on session rows: wanted, or drop it to keep rows shorter?
9. **Logging a past session** ("Quick log" today lives on Plan): move to Train / Progress, or keep an entry in More?
10. **Automatic small increases** (`autoAdapt`, on by default today) conflict with "nothing without approval". Confirm
    it becomes approval-only when Plan v2 is built (Coach Decision 1 already says so).
11. **Week start** Monday (as today) — keep?
12. Order of phases 2–8, and whether phase 1 (UI Lab prototype) may start once this specification is approved.

## 21. Limits of this document

- Written from the production source and existing audits; the app was not run for it.
- Competitor behaviour comes from two public pages and the owner's brief, not from use of those products.
- All sizes are design estimates.
- The `WeeklyReview` structure and the strength session screen were not audited in depth.
