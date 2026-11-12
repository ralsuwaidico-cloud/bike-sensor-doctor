# Plan v2.0 — product and UX specification

Status: **Current Draft** · Version 0.2 · 12 Nov 2026 · Level 3 (product specification)
Source: `docs/cyclift-governance`, `product/plan/PLAN_V2_SPECIFICATION.md`
Basis: owner brief "Plan Tab Redesign v2.0" and the owner's review of v0.1 (both 12 Nov), Master Project Instructions
v2.0, Brand Book v0.2 (current design baseline).

**Specification only.** No code, UI Lab prototype, production branch, TestFlight build, database, migration or firmware
was touched. Nothing here is implemented unless a row says "Exists".

Reading key: **Exists** = in the production app today (source read on the release branch, commit `4e2e9dc`; not
re-tested for this document) · **Partial** = part exists, the rest is named · **Future** = not built and not to be
shown as available · **Design** = new in this specification, buildable on existing data.

Wireframes (grey-scale, layout only): `wireframes/W1…W7` show the design that existing capabilities can support;
`wireframes/W8_FUTURE_not_built.png` shows Future capabilities for direction only.

## Decisions recorded from the owner's review of v0.1 (12 Nov)

| # | Decision | Where applied |
|---|---|---|
| 5 | Completion ring and separate Next-session card are removed from Plan | §1, §5 |
| 6 | The date selector shows scheduled disciplines, not completion; session rows keep truthful status labels | §6.1, §6.2 |
| 7 | "Swap two days" is replaced by Move to any day, with feasibility checks, preview, approval, history and Undo | §6.6 |
| 8 | Event programs launch with cycling first; strength may be maintained as a supporting discipline; running and swimming events stay Future | §8, §13 |
| 9 | Ask Coach uses prepared, context-specific options until two-way messaging exists | §11 |
| 10 | Automatic increases in load, volume or frequency require approval; existing behaviour audited, correction planned, no code changed | §11, `product/coach/AUTOADAPT_AUDIT_AND_CORRECTION_PLAN.md` |
| G | Past-session Quick log moves to Train; no functionality is removed | §9, §14 |

---

## 1. What Plan is for

Plan is where the athlete decides future training: what am I training for · what gets me there · when can I
realistically train · what exactly is scheduled · what happens when my schedule changes · what adjustments keep me on
track · how do I create and reuse workouts.

Home shows the current condition. **Plan decides what happens next.** Train executes. Progress analyses.

### What is never on Plan

Consistency, Training Mix and Recovery circles · sleep card · heart-rate, power, volume or performance charts ·
Endurance and Strength summary cards · a Next-session summary · a seven-day status strip · the Coach insight card ·
the Getting Started checklist · completion donuts · weekly scorecards · progress cards.

Removed from today's Plan: the completion ring ("x of y sessions done", recorded / planned minutes) and the separate
Next-session card. Their information remains on Home; nothing else is lost (see §14 for where each existing function lives).

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

---

## 4. Goals drive planning

### 4.1 The chain

```
GOAL ─► PROGRAM ─► WEEKLY PRESCRIPTION ─► ATHLETE AVAILABILITY ─► SCHEDULED SESSIONS
                                                                        │
PROPOSED ADJUSTMENT ◄─ COACH REVIEW ◄─ COMPLETED TRAINING ◄─────────────┘
        │ (athlete approves)
        └──────────────► changes one session, a date range, the recurring plan, or the program
```

| Link | What it is | Who decides | Where the athlete sees it | Today |
|---|---|---|---|---|
| Goal | What the athlete is training for; one primary, optional others; optionally an event | Athlete | Program row → Goal & Program | Exists (goals, primary goal). Event date: Future |
| Program | The structure that serves the goal: phases, progression, easier weeks | Planning engine, from the goal, experience and history | Goal & Program (name, current week, next easier week) | Partial: the planner already shapes weeks by goal, level, easier-week cycle and return-from-break. No named program object |
| Weekly prescription | What a normal week should contain: sessions per discipline, time, rest days, session types | Planning engine proposes; athlete can change | Goal & Program › Weekly prescription; realised as the Recurring Plan | Partial: implied by the template and budgets; not stated as a prescription |
| Athlete availability | Days, time per day, weekly time per discipline, equipment, two-a-day | Athlete | Recurring Plan › Availability & preferences | Exists. Windows and date-range exceptions: Future |
| Scheduled sessions | The real sessions of a real week, generated from the recurring plan and edited by the athlete | Engine generates; athlete edits | Weekly Calendar | Exists |
| Completed training | What was actually done, with its record | The athlete's training | Session rows show a truthful status; detail lives in Train / Progress | Exists |
| Coach review | Rules that compare what was planned with what happened and with availability | Coach (rules-based) | Not shown as a surface | Exists (adaptation engine, hybrid review) |
| Proposed adjustment | A specific change with reason, benefit and impact | **Athlete approves** | One suggestion row → shared proposal detail | Exists for session-level changes. Increases are applied automatically today — to be corrected (decision 10) |

### 4.2 What the athlete is asked to decide — and nothing more

| Decision | Surface |
|---|---|
| My goal (and later, my event) | Goal & Program |
| My days and time | Availability & preferences |
| My normal week | Recurring Plan (seven rows) |
| This week's exceptions | Weekly Calendar (move, edit, replace, skip, add) |
| Whether to accept a suggestion | Proposal detail |

Everything else — phase lengths, progression steps, easier-week timing, spacing rules, budget fitting, load checks —
stays in the planning engine. The interface shows its **result** (the week) and, on request, its **reason** (one line
per session; full reasoning in a proposal).

### 4.3 How a change travels

| Change at | Flows down to | Preview shows |
|---|---|---|
| Goal | Prescription → recurring plan → future generated sessions | Before / after weeks; sessions kept because they were edited by hand, fixed or completed |
| Availability | Recurring plan → future sessions | The same |
| Recurring plan row | Future occurrences in the chosen scope | The same |
| One session | That session only | Before / after of that session |

A change never flows **up** silently: editing a session does not change the recurring plan; changing the recurring
plan does not change the goal.

---

## 5. Information architecture and landing

```
Plan (tab)
├─ Header: "Plan" · More ───────────► Routines · Availability & preferences · Plan history
├─ Goal / program row (one line) ───► Goal & Program (screen)
├─ Selector: Weekly Calendar | Recurring Plan      (exactly two; one rendered at a time)
│
├─ Weekly Calendar
│   ├─ Week navigation  ‹ range ▾ ›   (▾ jumps to a date; "Today" when away from this week)
│   ├─ Seven-date selector with discipline indicators
│   ├─ [one planning-suggestion row — only when a proposal is pending] ► shared proposal detail
│   ├─ Selected day header + compact "Add session" ► sheet
│   └─ Session rows ► session planning detail (sheet); ••• ► contextual menu
│
└─ Recurring Plan
    ├─ Seven weekday rows ► weekday sheet ► scope ► preview ► approve
    ├─ Availability & preferences ► screen
    └─ [one feasibility warning — only when something does not fit] ► Fix
```

**The landing screen contains only:** header and menu · the one-line goal / program row · the selector · the compact
content of the selected section. No large cards, nested cards, blank areas, oversized headings, repeated labels or
decorative buttons.

Heights (pt): header 40 · program row 44 · selector 40 · week navigation 40 · date selector 58 · suggestion row 44 ·
day header 36 · session row 60 · weekday row 46. A row may look compact while its touch area is at least 44 pt.

Design estimates from the wireframe geometry (**not measured on a device**):

| Device | Session list starts at (with / without a suggestion row) | Dock line | Session rows visible without scrolling |
|---|---|---|---|
| Small (375 × 667) | y 346 / 296 | 583 | 3 / 4 |
| Standard (393 × 852) | y 385 / 335 | 742 | 5 / 6 |
| Large (440 × 956) | y 388 / 338 | 846 | 7 / 8 |

Recurring Plan: seven rows + the availability row end at y 530 / 569 / 572; with one warning, y 576 on the small size —
it fits above the dock line (583) with 7 pt to spare, which is tight and must be checked on a device.

Common actions are one or two taps from landing (select a date, open a session, add a session, open a weekday).
Complex workflows — changing a goal, building a routine, a recurring change with preview, an event program — take as
many steps as they need; no artificial tap limit is imposed on them.

---

## 6. Weekly Calendar (W1, W1b, W2, W3)

### 6.1 Week navigation and date selector
- Previous / next week; the range label opens a date jump; "Today" appears when another week is shown.
- Seven dates: weekday letter, day number, and **discipline indicators only** — round mark = endurance, square mark =
  strength (shape as well as colour), dash = scheduled rest, nothing = empty. At most two marks, then "+".
- **No completion, ticks, percentages or colours of success or failure.**
- Today is outlined; the selected date is filled; today is selected on opening.
- Spoken: "Wednesday 11 November, today, selected, 2 sessions: ride, strength".

### 6.2 Session rows
`[discipline icon]  Title ················ status   •••`
`                   duration · short description`

- The second line shows what exists today: duration and a short description (exercise count for strength; zone or
  type for rides). Scheduled time, window and place are **Future** and are not shown until they exist.
- **Truthful status, one word:** Planned · In progress · Done · Missed · Skipped. A moved session carries a link line
  (§6.7). No colour judgement.
- Tap the row → session planning detail. ••• → contextual menu.
- Several sessions → several rows. Long titles truncate on one line (full title in the detail).
- Scheduled rest → one "Rest day" row. Empty date → "Nothing scheduled". "Add session" is always in the day header,
  so empty states need no second button.

### 6.3 Session planning detail (sheet, W5)
Title · date, duration, status · the workout (exercises with sets × reps and supersets, or ride structure with zones
and intervals — both exist) · "Why this session" in one line (stored coach reason — exists) · primary action · Move ·
Edit · Replace · More.
Exercise editing and the superset option stay exactly as they are today, reached through Edit.

### 6.4 Actions by state

| Action | Planned | In progress | Done | Missed | Skipped |
|---|---|---|---|---|---|
| View workout | ✓ | ✓ | ✓ opens the record | ✓ | ✓ |
| Start in Train | today only | Resume | — | — | — |
| Edit this session | ✓ | — | — | — | — |
| Move session | ✓ | — | — | as Reschedule | after Restore |
| Replace workout | ✓ | — | — | as Shorten or replace | — |
| Assign routine | strength | — | — | — | — |
| Remove from this week | ✓ | — | — | — | — |
| Skip | ✓ | — | — | ✓ | — |
| Restore | — | — | — | — | ✓ |
| Ask Coach | ✓ | — | — | ✓ | — |

"Start in Train" hands the session to the existing execution flow (ride recorder, strength session, connected
devices). Plan executes nothing.

### 6.5 Add session (sheet, W5)
Discipline · Workout or routine · Date (prefilled) · Duration (prefilled from the routine or the usual length). Body
region appears only for a strength session without a routine. One button. States "This week only".

### 6.6 Move to any day (sheet, W5) — replaces today's swap-two-days
1. Choose any destination date in the visible or a later week.
2. **Feasibility checks**, each one short line: the destination day's available time · sessions already on that day ·
   the week's time budget per discipline · documented spacing rules that exist today (strength sessions 48 h apart;
   no hard ride the day after a hard ride) · whether a planned rest day is being used.
3. Affected sessions are listed (nothing else moves unless the athlete chooses it).
4. **Preview → approve.** A check that fails is a warning the athlete may override, except a hold from the health
   check, which blocks with its reason.
5. Effect: this occurrence only; the recurring plan is untouched; the session is linked to its original date; a
   **history entry with Undo** is written. Undo is itself previewed and never overwrites a later change.

Today: only "swap with another day of the same week" exists. Move to any day is **new behaviour (Future)** and needs
the origin link of §12.

### 6.7 Missed sessions — truthfulness (W3)

A missed session **stays on its original date with the status Missed, permanently**. Whatever the athlete does next is
recorded as a *new, linked* thing — never by rewriting the missed occurrence.

| Choice | What is recorded | What the athlete sees |
|---|---|---|
| Reschedule… | The original stays Missed with resolution "rescheduled → date". A new scheduled session is created on the new date, linked to the original | Original: "Missed" + "↳ Rescheduled to Thu 12 Nov". New: "Planned" + "↳ Rescheduled from Mon 9 Nov (missed)" |
| Shorten or replace… | The original stays Missed with resolution "replaced". A new session (shorter, or a different workout) is created, linked to the original and marked as a **replacement** | New: "↳ Replaces Lower Body A, 45 min (missed Mon 9 Nov)" |
| Skip | The original becomes Skipped (an athlete decision), resolution "skipped" | "Skipped" |
| Ask Coach | Opens prepared options (§11); whatever is chosen follows the rows above | — |
| Leave unresolved | Nothing changes; the session stays Missed with no resolution | "Missed" |

Rules:
1. **A missed session never becomes Done.** Completing the rescheduled or replacement session completes *that*
   session; the original remains Missed.
2. Nothing is rescheduled, shortened or stacked automatically.
3. **Adherence reporting must not be misled.** How Home's consistency treats these cases is Home's definition and is
   not changed here; the data must make every reading possible and none silent:
   - the planned (original) session and its outcome are always kept;
   - a rescheduled or replacement session is flagged as such and points to its original;
   - a replacement keeps both durations (planned 45 min → replacement 30 min), so a shortened session is never
     reported as the full session;
   - whether "missed, then rescheduled and completed" counts as one adherent session, a late one, or neither, is an
     **open decision** (§20) — until decided, the default is the most conservative reading: the original counts as
     missed, the new session counts as a completed session in its own week, and both facts are visible.
4. History entries are written for reschedule, replace and skip, each with Undo.

Today: the Missed state exists (derived); rescheduling exists only as a day swap; the link and resolution do not exist
(Future, §15 items 2–3).

---

## 7. Recurring Plan (W4)

**Purpose:** the normal training structure — a template. Not a calendar, not a performance view: no dates, no status.

### 7.1 Weekly template
Seven rows: `Mon  [icon]  Full Body A  ········  30 min  ›`. Rest reads "Rest". Two sessions on a weekday read
"Full Body A + Zone 2 Ride". Time windows are **Future** and are not shown.
Below: one "Availability & preferences" row. Below that, **at most one** feasibility warning, only when needed.

### 7.2 Editing a weekday — scope is always explicit (W5)

| Scope | Effect | Today |
|---|---|---|
| **This occurrence only** | Changes the session on one date; the template is unchanged | Exists (session edit) |
| **Temporary date range** | An exception to the template between two dates; the template itself is unchanged and resumes afterwards | **Future** — offered only when it exists |
| **All future occurrences** | The template changes; future generated sessions follow | Exists (week editor with preview) |

Until date-range exceptions are built, the sheet offers the two scopes that work, never a disabled or placeholder
third option.

Then a preview and approval. **Never rewritten silently:** the recurring pattern (by a single-session edit); future
sessions the athlete edited by hand or marked fixed (listed in the preview as "kept as you set it"); completed records.

### 7.3 Availability & preferences (screen)
Regroups what exists — nothing is asked twice and nothing is removed: training days · time per day · two-a-day ·
weekly time per discipline (the existing budgets) · equipment · strength split · supersets · priorities · training
pause (unwell, injured, away). Each row opens its existing editor.

### 7.4 Feasibility
One line, only when something does not fit: a session longer than the day's time · more sessions than days · a weekly
budget exceeded · a documented spacing rule. "Fix" opens the existing Fix plan (raise the budget · edit the days ·
shorten or skip a session · keep as it is). Goal / program conflicts join this line when programs exist (Future).

---

## 8. Goal & Program (W6; Future parts in W8)

Reached only from the one-line row. With existing data the screen shows: **Goals** (primary, others) · **Weekly
prescription** (sessions per discipline, rest days, weekly time — read from the recurring plan and budgets) · **This
week** (position in the easier-week cycle) · **Change goal** (existing preview before saving).

**Future — not shown until built:** a named program with phases and milestones; event type and date; feasibility.
Event programs start with **cycling events**, with strength kept as a supporting discipline (fewer strength sessions,
stated as a trade-off). Running and swimming events (marathon, half marathon, triathlon) wait for those disciplines.
The event flow, when built: event and date → baseline, naming what is unknown → feasibility in plain words, with the
nearest realistic alternative when the goal is not realistic → phases backward from the date → fit to real
availability → preview → approval. No tapering or event-specific coaching is claimed before it exists and is tested.

Weekly targets live here as the prescription. There is no scorecard anywhere on Plan.

---

## 9. Routines and logging

**Routines** — one library, one entry point (More › Routines; the same screen when a sheet asks for "Workout or
routine"). Exists: create, edit (exercises, sets, reps, supersets), assign to a session, default per weekday,
per-session changes that never alter the routine. Design: duplicate; save a completed workout as a routine.
Future: saved endurance workouts — not shown until built.
Routine entry points are removed from the toolbar menu and from "Manage plan" (they exist twice today).

**Quick log of a past session moves to Train.** Today "Quick log" and "Log exercises" sit in Plan's menu and in
"Manage plan". In v2.0 they live in Train ("Log a past session"), because recording training is execution, not
planning. From Plan, a Missed or Planned strength session keeps a path: session detail › More › "Log this session",
which hands over to Train's logging screen for that session and returns to Plan. No logging function is removed.

---

## 10. Weekly Planning Review (Future — W8)

A workflow, not a card; offered, never forced; absent when nothing needs attention. Triggers: the coming week is
near · availability changed · unresolved conflicts · a meaningful proposal. One sheet: Scheduled · Fits your
availability? · Conflicts · Coach suggests (each with Preview) · Needs your approval. Actions: Review changes · Keep
the schedule · Not now. It uses the shared proposal detail for every change.
It is not offered in the More menu until it exists.

---

## 11. Coach in Plan

Sequence: **Observe → Explain → Recommend → Preview → Request approval.** The Coach is rules-based and is described so.

- **Exactly one compact row** may appear on Plan — "1 planning suggestion · Review" — and only while an actionable
  proposal is pending. No advice text, no reasoning, no buttons other than opening it. Several pending proposals read
  "3 planning suggestions" and open a short list.
- **Reasoning, trade-offs and approval live in the shared proposal detail** (W6): what would change · why (including
  any recovery or load reason, in words) · expected benefit · possible impact · Approve · Not now · Decline. It is the
  same component the Coach conversation uses.
- **Ask Coach** (on a Planned or Missed session) opens **prepared, context-specific options**, not a text field:
  for a missed strength session, for example — "Move it to Thursday (fits your time)", "Do a 30-minute version on
  Thursday", "Skip it this week". Each option opens the same preview and approval. Options are generated by rules from
  the schedule; when no sensible option exists, it says so. Free-text conversation is Future.
- **Useful scheduling recommendations the rules can make from existing data:** a session that does not fit a day's
  time · a week over budget · strength sessions too close together · a hard ride after a hard ride · a missed session
  with a feasible later slot · a shorter alternative of the same intent. With recovery data absent, recommendations
  are schedule-based only and no recovery reason is invented.
- **Increases need approval.** Today the app applies small progressions automatically by default. The audit and the
  safe-correction plan are in `product/coach/AUTOADAPT_AUDIT_AND_CORRECTION_PLAN.md`; nothing was changed. Protective
  reductions stay automatic (Coach Decision 1).

---

## 12. Interaction rules (complete)

**Scope**
1. One occurrence never changes the recurring plan.
2. A recurring change always states its scope: this occurrence only · temporary date range (when it exists) · all future occurrences.
3. A change never flows upward silently (session → recurring plan → goal).

**Approval**
4. Every consequential change is previewed; nothing is saved before approval; Cancel leaves stored data equal.
5. Increases in load, volume or frequency are proposals and are never applied automatically.
6. Protective reductions and holds may apply automatically and are always listed with their reason.

**Protection**
7. Completed sessions and their records are never modified by any Plan action.
8. Sessions edited by hand or marked fixed survive every regeneration and are listed as kept.
9. A missed occurrence is never rewritten, moved or converted to Done; resolutions are linked records (§6.7).
10. Nothing is rescheduled or stacked automatically.
11. Planned rest days are preserved unless the athlete chooses otherwise; using one is called out in the preview.

**History**
12. Every applied change writes a history entry with Undo; Undo is previewed and never overwrites a later change.
13. Session states stay distinct in data: planned · scheduled · completed · missed · skipped / removed · rescheduled.

**Surface**
14. Only valid actions are shown for a session's state (§6.4). No disabled placeholders for Future capabilities.
15. At most one suggestion row on Weekly Calendar and one feasibility warning on Recurring Plan.
16. Sheets for short tasks; screens for Goal & Program, Routines, Availability & preferences, Plan history.
17. Every control has a touch area of at least 44 pt, an accessible name and a value.
18. No drag and drop in v2.0; Move is a menu action with a preview.
19. Execution always hands over to Train.

### State transitions

```
recurring row ──generate──► PLANNED ──(dated in a real week)──► SCHEDULED
SCHEDULED ──start──► IN PROGRESS ──finish──► COMPLETED                      (record kept; never altered)
SCHEDULED ──day passes──► MISSED            (stays MISSED for good)
      MISSED ──reschedule──► MISSED [resolution: rescheduled] + new SCHEDULED (linked: rescheduledFrom)
      MISSED ──replace──► MISSED [resolution: replaced] + new SCHEDULED (linked: replaces; both durations kept)
      MISSED ──skip──► SKIPPED
SCHEDULED ──move──► SCHEDULED on the new date (linked: movedFrom) + history entry
SCHEDULED ──skip──► SKIPPED ──restore──► SCHEDULED
SCHEDULED ──remove from this week──► REMOVED (history entry; Undo)
```

---

## 13. Twelve journeys

Start · actions and transitions · data change · confirmation · error or cancel. **(F)** = needs a Future capability.

| # | Journey | Start | Actions and transitions | Data change | Confirmation | Error / cancel |
|---|---|---|---|---|---|---|
| 1 | Create a recurring hybrid week | Recurring Plan (empty) or onboarding | Tap a weekday → sheet → workout, duration; repeat. Or accept the week suggested from availability and goal | Template; coming weeks generated | Preview → "Use this week" | Feasibility warning if days and time do not fit; Cancel saves nothing |
| 2 | Change one workout only | Weekly Calendar › session ••• › Edit this session | Sheet (duration, exercises, supersets) → before / after review | That session only; history entry | "Apply to this session" | A blocked edit explains why and offers an alternative; Cancel leaves it equal |
| 3 | Permanently change availability | More › Availability & preferences | Change days / time → preview of future weeks, listing kept sessions | Availability, template, future generated sessions | Approve in preview | Conflicts with fixes; Cancel keeps the old availability |
| 4 | Miss a workout and reschedule **(F: any-day move, link)** | Weekly Calendar, the missed date | "Missed" row → Reschedule… → choose date → checks → preview | Original stays Missed (resolution: rescheduled); new linked session; history entry | "Reschedule" | No feasible day: says so and offers Shorten, Skip, Leave; Cancel leaves it Missed and unresolved |
| 5 | Replace 60 min with a shorter alternative | Session ••• › Replace workout | Shorter alternatives of the same intent → preview | That session's workout and minutes; for a missed one, a linked replacement **(F)** | Apply | No shorter version for that type: says so; Cancel |
| 6 | Create and assign a strength routine | More › Routines › New | Name, exercises, sets, reps → Save → ••• › Assign to a session / Use on a weekday | Routine; the session's routine or the weekday default | Saved; weekday use asks scope | An empty routine cannot be saved; Cancel discards |
| 7 | Two workouts on one day | Weekly Calendar › Add session | Sheet → "Add to this week" | Second session on that date | Row appears; a line notes if the day's time is exceeded | If two-a-day is off: offers to allow it for this date; Cancel |
| 8 | Prepare for a marathon **(F — running not supported)** | Goal & Program | Not offered until running is a supported discipline. When it is: the event flow of §8 | Event, program, generated sessions | Approve program | Unrealistic: plain warning + alternative; Cancel creates nothing |
| 9 | Cycling event while maintaining strength **(F — first event program)** | Goal & Program › Add event | Cycling event and date → strength as supporting discipline → prescription shows the trade-off → preview | Event, program, prescription, generated sessions | Approve | Too little time for both: the athlete chooses the priority; Cancel |
| 10 | Approve a Coach weekly adjustment | Weekly Calendar › suggestion row | Proposal detail: changes, why, benefit, impact → approve all or part | Approved changes only; history entries; coach record of the decision | Approve / Not now / Decline | Not now keeps it pending; Decline closes it; nothing changes without approval |
| 11 | No recovery device, no calendar | Any Plan screen | Everything works from schedule and logged training; reasons are schedule-based | — | — | No recovery text is invented; Plan shows no "connect" prompts |
| 12 | Event date changes **(F)** | Goal & Program › Event | Edit date → recalculated program → preview: phases, kept sessions, feasibility | Event date, phases, future sessions; completed weeks untouched | Approve | Date too close: warning + options; Cancel keeps the program |

Realistic cases to test in a prototype (owner C): one workout · two workouts · three with long names · a missed
session with choices · a rescheduled pair · a shortened replacement · no goal set · rest day · empty day · next week ·
large accessibility text — all drawn in W1–W7.

---

## 14. Reuse map — every existing function has a place

| Existing function (production) | Place in v2.0 | Change |
|---|---|---|
| Week view, day rows, several sessions per day | Weekly Calendar | Layout |
| Completion ring; recorded / planned minutes | **Removed from Plan** (Home keeps the summary) | Removed surface, no data change |
| Next-session card with Start | Selected day's row + session detail › Start in Train | Merged |
| Open session; start ride or strength session | Session detail › Start in Train | Handover unchanged |
| Session edit: type, body region, duration | Session › Edit | Unchanged |
| **Exercise editing; supersets** | Session › Edit; Routines | Unchanged |
| Before / after review of an edit | Every preview | Unchanged (Defect 6 must be resolved first) |
| "Move" (swap two days) | Move to any day | **Replaced — new behaviour (Future)** |
| "Swap" (alternatives) | Replace workout | Renamed |
| Remove; skip; add session | Same actions | Wording |
| **Routines**: create, edit, assign, weekday default | More › Routines; sheets | One entry point |
| **Availability**, time per day, two-a-day | Availability & preferences | Regrouped |
| **Training preferences**: equipment, split, supersets, priorities, level | Availability & preferences | Regrouped |
| **Weekly budgets** and Fix plan | Feasibility warning › Fix | Unchanged |
| **Plan versions and Undo** | More › Plan history | More causes later |
| Pending proposals strip and review sheet | One suggestion row → shared proposal detail | One design |
| Goals and goal change with preview | Goal & Program | Regrouped |
| Training pause | Availability & preferences | Regrouped |
| **Quick log; Log exercises** | **Train** ("Log a past session"); from Plan via session › More › Log this session | **Moved, not removed** |
| Weekly overview page, Day page (shared with Home) | No longer opened from Plan; Home keeps them | Plan stops linking to them |
| **Session execution handoff** to recorder, strength session, devices | Start in Train | Unchanged |

### Future dependencies

| Capability | Needs | Status |
|---|---|---|
| Move to any day with links | Origin link, checks beyond the current week | Future |
| Missed resolution and linked replacement | Resolution field, link, both durations | Future |
| Temporary date-range exceptions | Exception model in the recurring plan | Future |
| Scheduled times and windows | Time fields; later, conflict checks | Future |
| Named programs, phases, milestones | Program model | Future |
| Event programs (cycling first) | Event model, feasibility rules; evidence for any taper claim | Future |
| Running, swimming events | Those disciplines (Coach Decision 11: running next) | Future |
| Saved endurance workouts | Workout template for rides | Future |
| Weekly Planning Review | Coach event store; review rules | Future |
| External calendars | Consent, privacy review, calendar access | Future |
| Advanced adaptive programs | Program model + validated rules | Future |
| Approval-only increases | Correction in the auto-adjustment rule | Planned, not implemented |

---

## 15. Data-model changes needed (not implemented)

Additive only; each needs an impact assessment (store and migrations, cloud sync, Apple Watch, BikeComputer link,
detachable Watch, and the 25 production UI-test references to Plan identifiers).

| # | Addition | For |
|---|---|---|
| 1 | Session: `movedFrom` (original date) | Move to any day; "rescheduled" state |
| 2 | Session: `missedResolution` (none · rescheduled · replaced · skipped) and link to the resolving session | Missed truthfulness |
| 3 | Session: `replaces` (original session id) + original planned minutes kept | Shortened or alternative sessions without misleading adherence |
| 4 | Recurring plan: date-range exceptions | Temporary scope |
| 5 | Session and template: optional time and window | Scheduled times |
| 6 | Program (name, goal, start, end, phases, prescription) and session → program link | Goal & Program |
| 7 | Event (type, date, name, target) | Event preparation |
| 8 | Saved endurance workout | Routine library |
| 9 | History causes: move, reschedule, replace, routine, program, event | Traceability |
| 10 | Coach event store (observation, proposal, decision, outcome) | Shared proposal detail, review |
| 11 | Discipline list beyond cycling and strength | Running and swimming events |

Not needed: any change to completed records, to routines, or to existing plan versions.

---

## 16. Phases (each needs separate authorisation)

| Phase | Content | Depends on |
|---|---|---|
| 0 | Approve this specification | — |
| 1 | UI Lab prototype of landing, both sections, sheets and missed-session states, with sample data and interaction tests | Phase 0 |
| 2 | Production restructure **with existing data only**: two sections, date selector, session rows, one menu, single routine entry, removal of ring and Next-session card, Quick log to Train, wording | Release stabilised; Defect 6 resolved; integration review |
| 3 | Approval-only increases (auto-adjustment correction) | Its own plan |
| 4 | Move to any day; missed resolution and links | Items 1–3 |
| 5 | Date-range exceptions; times and windows | Items 4–5 |
| 6 | Routine additions; saved endurance workouts | Item 8 |
| 7 | Programs and prescription as objects; Weekly Planning Review; coach events | Items 6, 10 |
| 8 | Cycling event programs | Item 7 |
| 9 | Other disciplines' events; external calendar; advanced adaptation | Separate designs |

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
| Initial content | Header, goal row, selector, week, dates, the day's sessions and Add session are visible on all three sizes (§5) |
| Scrolling for common actions | None, up to 3 / 5 / 7 sessions with a suggestion row |
| Heights | No landing element taller than 60 pt; no card inside a card |
| Dock | Content ends above the dock line; lists scroll under an inset equal to the dock |
| Truncation | The goal row truncates on the small size (W1) — full name one tap away; long session titles truncate on one line (W2) |
| Touch | Every control ≥ 44 pt; the ••• target is separate from the row |
| Missed choices on the small size | Row + five choices end at y 558, above the dock line 583 (W7) — fits, tight |
| Recurring Plan with a warning on the small size | Ends at y 576 against 583 (W4) — fits by 7 pt; to be checked on a device |
| Large accessibility text | Selector stacks; goal row takes two lines; session rows three lines; seven date cells stay, with capped text and full spoken labels. Estimate on the small size: two sessions end at y 538, above 583 (W7) |
| Colour | Shapes for disciplines, words for status |
| Reading order | Title, More, goal row, selector, week controls, dates, suggestion, day header, Add, sessions |

**Not verified:** all of this is design estimate from wireframe geometry. Nothing was built, run in a simulator, or
tried on a physical iPhone or with VoiceOver.

## 19. Acceptance criteria (for a future prototype or build)

**Structure**
1. Exactly two primary sections; one rendered at a time; Weekly Calendar is the default.
2. The landing screen contains only: header and menu, one-line goal row, selector, and the selected section.
3. Weekly Calendar contains only: week navigation, seven-date selector, session rows, one Add session action, and at most one suggestion row.
4. Recurring Plan contains only: seven weekday rows, the availability entry, and at most one feasibility warning.
5. None of the Home components of §1 appears anywhere in Plan; no completion ring; no Next-session card.

**Density and access**
6. On the smallest supported iPhone at default text size, the date selector, the first session and Add session are visible without scrolling.
7. Every control has a touch area ≥ 44 pt, an accessible name and a value.
8. Layout holds at the largest accessibility text size without clipped or overlapping text.
9. The eleven realistic cases of §13 each render without overflow on small, standard and large sizes.

**Behaviour**
10. The date selector shows no completion information; session rows show one truthful status word.
11. Each of the seven dates shows that date's sessions; previous, next, jump and Today work.
12. Actions appear only in the states of §6.4.
13. Editing, moving or replacing one occurrence leaves the recurring plan byte-equal.
14. Every recurring edit asks for scope; each scope changes exactly what §7.2 says; no unavailable scope is shown.
15. No change is saved without a preview; Cancel leaves stored data equal.
16. Move to any day runs the checks of §6.6, writes a history entry, and Undo restores the previous state exactly.
17. A missed session is never altered automatically, never becomes Done, and keeps its original date and status after any resolution.
18. A rescheduled or replacement session is linked to its original, and both planned durations are retained.
19. Completed sessions are never altered by any Plan action.
20. Hand-edited and fixed future sessions survive every regeneration and are listed as kept.
21. No increase in load, volume or frequency is applied without approval.
22. The suggestion row is absent when no proposal is pending; the proposal detail is the same component as in the Coach conversation.
23. Ask Coach offers only prepared options; no text field.
24. Routines are managed in one place; every existing routine, availability, preference, budget, version, Undo, exercise-editing and superset function is still reachable.
25. Quick log is reachable in Train and from a session's More menu; no logging function is lost.
26. Start in Train reaches the existing execution flow for rides and strength.

**Honesty**
27. No Future capability (events, times, date ranges, endurance library, calendar, advanced adaptation, weekly review) appears as a control before it works.
28. All six themes pass the contrast script; High Contrast uses borders.
29. Results are reported by evidence level; simulator results are not called device results.

## 20. Unresolved questions

1. **Adherence after a reschedule.** When a missed session is rescheduled and then completed, does consistency count it as adherent, late, or missed plus one extra? (Default in this draft: the conservative reading, both facts visible.) This is a Home / metrics definition and needs your decision before phase 4.
2. **Replacement sessions and adherence.** Does a completed 30-minute replacement of a 45-minute session count as that session done, or as a separate, shorter session? Same default.
3. **Overriding a failed check** when moving (for example strength on consecutive days): allow with a warning, as drafted, or block?
4. **How far ahead** can a session be moved — the current and next week only (today's limit on viewing), or further?
5. **Skipped vs removed:** keep both (skip leaves a visible row; remove deletes it with Undo), or only one?
6. **Already-applied automatic progressions** when the approval rule arrives: keep them (drafted) or return them to pending?
7. **Place labels and times** on rows are Future; is duration plus a short description enough for phase 2?
8. **"Log a past session" in Train:** where exactly it sits is a Train design question — Train has no specification yet.
9. **Weekly overview and Day pages:** Plan stops opening them. Agree?
10. **Week start** Monday, as today?
11. May the **UI Lab prototype (phase 1)** start once this version is approved?

## 21. Limits of this document

- Written from the production source and existing audits; the app was not run for it.
- Competitor behaviour comes from two public pages and the owner's brief.
- All sizes are design estimates from wireframes.
- The coach's weekly-review structure and the strength session screen were not audited in depth.
- "Documented spacing rules" refers to rules found in the planner's code and feasibility text (strength 48 h apart, no hard ride after a hard ride); their full list was not extracted.

## Change log

| Version | Date | Change |
|---|---|---|
| 0.1 | 12 Nov 2026 | First draft |
| 0.2 | 12 Nov 2026 | Owner decisions 5–10 applied; goals-to-schedule chain (§4); landing reduced to the approved minimum; explicit scopes; missed-session data semantics and links (§6.7); Move to any day; Coach limited to one row and prepared options; Quick log to Train; Future capabilities removed from the main wireframes and collected in W8; acceptance criteria and unresolved questions rewritten |
