# Plan v2.0 — product and UX specification

Status: **Current Draft** · Version 0.5 · 12 Nov 2026 · Level 3 (product specification)
Source: `docs/cyclift-governance`, `product/plan/PLAN_V2_SPECIFICATION.md`
Basis: owner brief "Plan Tab Redesign v2.0", the owner's reviews of v0.1 and v0.2 (all 12 Nov), Master Project
Instructions v2.0, Brand Book v0.2 (current design baseline).
The owner approved the overall product direction on 12 Nov, subject to the decisions recorded below. The document
stays a Current Draft until the open questions of §20 are reviewed.

**Specification only.** No code, UI Lab prototype, production branch, TestFlight build, database, migration or firmware
was touched. Nothing here is implemented unless a row says "Exists".

Reading key: **Exists** = in the production app today (source read on the release branch, commit `4e2e9dc`; not
re-tested for this document) · **Partial** = part exists, the rest is named · **Future** = not built and not to be
shown as available · **Design** = new in this specification, buildable on existing data.

Wireframes (grey-scale, layout only): `wireframes/W1…W7` show the design that existing capabilities can support;
`wireframes/W8_FUTURE_not_built.png` shows Future capabilities for direction only; `W4` (revised), `W9a`, `W9b` and
`W10` are new in v0.3 (Recurring Plan on the small iPhone; rescheduled, shortened, overridden and removed sessions).

Companion documents (v0.3): `product/metrics/PLAN_ADHERENCE_METRICS_PROPOSAL.md` · 
`product/coach/AUTOADAPT_CORRECTION_PROPOSAL.md` · `product/plan/PLAN_UI_LAB_SCOPE.md`.

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

## Decisions recorded from the owner's review of the v0.4 visuals (12 Nov)

| # | Decision | Where applied |
|---|---|---|
| V1 | **B — Athletic Dynamic is the selected visual direction.** C is not to be used unless specifically approved | §22.5, §23 |
| V2 | Workout structure bars appear only where actual prescription data supports them | §22.4 |
| V3 | A compact **Add a goal** action sits inside the program area — not a separate card | §23.1 |
| V4 | Adding a sport is not the same as creating a goal | §23.2 |
| V5 | Exactly one compact Coach suggestion row, with a specific summary, only when a proposal is actionable; no space reserved otherwise; it opens the shared proposal detail | §23.4 |
| V6 | Planning intelligence lives behind contextual screens, never as landing-screen widgets, and is marked implemented, proposed or future | §23.5 |

Static screens for review: `visual-v05-B/B1…B6`. **Awaiting visual approval — no UI Lab code was written.**

## Visual direction recorded from the owner's review of v0.3 (12 Nov)

The v0.3 wireframes were judged too close to plain settings screens. Plan must look like a premium athletic product:
deep or layered surfaces, strong typography, restrained accent colour, purposeful gradients, and a **horizontally
swipeable circular date selector**. The functional decisions of v0.3 are unchanged. The draft visual direction is §22;
static alternatives are in `visual-v04/`. **Awaiting the owner's visual approval — no UI Lab code was written.**

## Decisions recorded from the owner's review of v0.2 (12 Nov)

| # | Decision | Where applied |
|---|---|---|
| R1 | A rescheduled missed workout keeps its original scheduled date and a linked replacement. Schedule adherence, training fulfillment and actual training volume are three different things. A completed rescheduled workout is never counted twice | §6.7, §12, metrics proposal |
| R2 | A shortened replacement records its actual completed duration and workload. A 30-minute replacement is not the completion of a 45-minute prescription | §6.7, §15, metrics proposal |
| R3 | Soft training conflicts warn, explain and can be overridden. Only hard technical or data-integrity constraints block. Unvalidated physiological rules are never presented as absolute restrictions | §6.6 |
| R4 | A session can be rescheduled to any future date within the active training program. No two-week limit | §6.6 |
| R5 | Skip and Remove both stay. Skip is a record of intentional non-completion. Remove deletes an uncompleted future occurrence, with Undo. Audit history and completed records are always kept | §6.4, §6.8, §12 |
| R6 | Increases that were already applied are not reversed. Future increases need approval. Automatic protective reductions are audited separately, distinguishing advice from changes to scheduled workouts | §11, auto-adaptation correction proposal |
| R7 | The UI Lab prototype is conditionally authorised: it may start only after this version and its open questions are reviewed. Nothing was started | §16, UI Lab scope |

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

Recurring Plan (revised in v0.3, W4 and W9a): seven rows and the availability row end at y 530 / 569 / 572 on the
three sizes. The feasibility warning is no longer a separate block under the list — it is shown on the affected
weekday row and inside that weekday's sheet (§7.4) — so the content ends **53 pt above the dock line** on the small
iPhone (530 against 583) in every state. Text sizes and touch areas are unchanged from v0.2.

Common actions are one or two taps from landing (select a date, open a session, add a session, open a weekday).
Complex workflows — changing a goal, building a routine, a recurring change with preview, an event program — take as
many steps as they need; no artificial tap limit is imposed on them.

---

## 6. Weekly Calendar (W1, W1b, W2, W3)

### 6.1 Week navigation and date selector
*(v0.4: the date strip becomes the circular date scroller of §22.2. The rules below still hold.)*
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
| Skip (record that I chose not to do it) | ✓ | — | — | ✓ | — |
| Remove (delete this occurrence) | today or a future date, not started | — | — | — | — |
| Restore | — | — | — | — | ✓ |
| Ask Coach | ✓ | — | — | ✓ | — |

"Start in Train" hands the session to the existing execution flow (ride recorder, strength session, connected
devices). Plan executes nothing. Skip and Remove are defined in §6.8.

### 6.5 Add session (sheet, W5)
Discipline · Workout or routine · Date (prefilled) · Duration (prefilled from the routine or the usual length). Body
region appears only for a strength session without a routine. One button. States "This week only".

### 6.6 Move to any day (sheet, W5, W10) — replaces today's swap-two-days

1. **Destination:** any future date **within the active training program** (decision R4). There is no fixed
   two-week limit. Until a program object exists (Future), "the active program" means the period for which the app
   holds a plan; how far that reaches today, and how a session moved beyond it is kept, is a technical question to be
   answered before this is built (§20, question T1).
2. **Checks** run on the destination and are shown as short lines. They come in two kinds:

   | Kind | Examples | Behaviour |
   |---|---|---|
   | **Soft training conflict** | The day's available time is exceeded · another session is already on that day · the week's time budget for the discipline is exceeded · a planned rest day is used · strength sessions closer together than the planner normally places them · two demanding sessions on adjacent days | **Warn, explain, allow.** One plain sentence says what the conflict is and what it may mean ("This puts strength on two days in a row. The planner normally leaves a day between them."). The athlete may continue with "Move anyway". The override is written to history |
   | **Hard constraint** | The destination is in the past · the session is completed or in progress · the destination is outside the active program · the move would create a second copy of the same occurrence or break a link between an original and its replacement · the stored plan cannot represent the result | **Block**, with the reason and the nearest valid alternative |

   Wording rule: a soft conflict is described as the planner's normal practice or the athlete's own setting, never
   as a medical or physiological law. No rule that has not been validated is shown as "not allowed".
   The existing health-check behaviour of the production app (sessions paused after a "see a doctor" or illness
   answer) is **not changed by Plan**: a moved session is treated on its new date exactly like any other session on
   that date. Whether Plan should add its own block in that case is question Q5 in §20; the drafted default is a
   clear warning, not a block.
3. Affected sessions are listed (nothing else moves unless the athlete chooses it).
4. **Preview → approve.**
5. Effect: this occurrence only; the recurring plan is untouched; the session keeps a link to its original date; a
   **history entry with Undo** is written. Undo is itself previewed and never overwrites a later change.

A move made **before** the session's day is replanning: the session stays one prescribed occurrence with a new date
and an origin link. A move made **after** the day has passed is a reschedule of a missed session (§6.7).

Today: only "swap with another day of the same week" exists. Move to any day is **new behaviour (Future)**.

### 6.7 Missed sessions — truthfulness (W3, W10)

A missed session **stays on its original date with the status Missed, permanently**. Whatever the athlete does next is
recorded as a *new, linked* thing — never by rewriting the missed occurrence.

| Choice | What is recorded | What the athlete sees |
|---|---|---|
| Reschedule… | The original stays Missed with resolution "rescheduled → date". A new scheduled session is created on the new date, linked to the original. Both belong to **one prescribed occurrence** | Original: "Missed" + "↳ Rescheduled to Thu 12 Nov". New: "Planned" + "↳ Rescheduled from Mon 9 Nov (missed)" |
| Shorten or replace… | The original stays Missed with resolution "replaced". A new session (shorter, or a different workout) is created, linked to the original and marked as a **replacement**. The original prescription (45 min) is kept beside the replacement's own plan (30 min) | New: "↳ Replaces Lower Body A, 45 min (missed Mon 9 Nov)" |
| Skip | The original becomes Skipped (an athlete decision), resolution "skipped" | "Skipped" |
| Ask Coach | Opens prepared options (§11); whatever is chosen follows the rows above | — |
| Leave unresolved | Nothing changes; the session stays Missed with no resolution | "Missed" |

Rules:
1. **A missed session never becomes Done.** Completing the rescheduled or replacement session completes *that*
   session; the original remains Missed on its date.
2. Nothing is rescheduled, shortened or stacked automatically.
3. **Three separate facts, never merged (decision R1):**
   - **Schedule adherence** — was it done on the day it was scheduled? A session missed on Monday and done on
     Thursday was **not** adherent to the schedule.
   - **Training fulfillment** — was the prescribed training done at all? The same session **is** fulfilled, late.
   - **Actual training volume** — what was really done, counted once, on the day it was done.
   The definitions are proposed in `product/metrics/PLAN_ADHERENCE_METRICS_PROPOSAL.md`. They are proposals; no
   calculation was implemented or altered.
4. **No double counting.** An original and its rescheduled or replacement session are one prescribed occurrence.
   Completing the linked session adds one completed record — it never also counts as an additional planned session,
   and its minutes are counted once.
5. **A shortened replacement is recorded as what it was (decision R2).** Its record holds the actual completed
   duration and workload. A completed 30-minute replacement of a 45-minute prescription shows
   "Done · 30 of 45 min prescribed" and counts as **partially fulfilled**, never as the 45-minute session done.
6. History entries are written for reschedule, replace and skip, each with Undo.

Today: the Missed state exists (derived); rescheduling exists only as a day swap; the link, the resolution and the
retained prescription do not exist (Future, §15 items 1–3, 12).

### 6.8 Skip and Remove — both kept (decision R5)

| | Skip | Remove |
|---|---|---|
| Meaning | "I chose not to do this session." A record of intentional non-completion | "This session should not be in my schedule." Deletes an uncompleted future occurrence |
| Applies to | Any planned session, or a missed session | A session of today or a future date that is not started |
| What stays visible | The row stays on its date with the status Skipped; Restore is offered | The row disappears; a confirmation with **Undo** is shown; the removal is in Plan history |
| Recurring plan | Unchanged | Unchanged (this occurrence only) |
| Records | Completed records are never touched | Completed or in-progress sessions cannot be removed |
| History | Entry with Undo | Entry with Undo; the entry keeps what was removed (workout, date, duration) so it can be restored exactly |
| In the metrics proposal | Counts as scheduled and not done | Leaves the schedule; counted separately as "removed" so that removing sessions cannot quietly raise a percentage |

Today: skip and remove both exist as actions; a removal is recoverable only through plan versions. The explicit
removal record is new (§15 item 13).

---

## 7. Recurring Plan (W4, W9a, W9b)

**Purpose:** the normal training structure — a template. Not a calendar, not a performance view: no dates, no status.

### 7.0 Progressive disclosure (v0.3)

The section shows the least that describes a normal week and opens everything else on request.

| Level | What is shown | Opens |
|---|---|---|
| 1 — Section | Seven compact weekday rows · one "Availability & preferences" row. Nothing else: no headings, no explanatory text, no cards, no Home metrics | — |
| 2 — Weekday sheet | That weekday's sessions, duration, routine, and its warning if it has one | Tap a weekday row |
| 3 — Availability editing (own screen) | Days, time per day, weekly time, equipment, preferences, pause | Tap the availability row, or More › Availability & preferences |
| 3 — Routine editing (own screen) | Exercises, sets, reps, supersets | Weekday sheet › Routine › Edit, or More › Routines |

Small-iPhone layout (375 × 667, W9a): header 40 · goal row 44 · selector 40 · seven rows of 46 · availability row
48 — content ends at y 530; the dock line is at y 583. **Clearance 53 pt.** Row text stays 12.5 pt and every row
keeps a touch area of at least 44 pt; nothing was shrunk to obtain the clearance. The list is a scroll view whose
bottom inset equals the dock zone plus 16 pt, so at larger text sizes rows grow and scroll, and the last row can
always be brought fully above the dock (W9b).

### 7.1 Weekly template
Seven rows: `Mon  [icon]  Full Body A  ········  30 min  ›`. Rest reads "Rest". Two sessions on a weekday read
"Full Body A + Zone 2 Ride". Time windows are **Future** and are not shown.
Below: one "Availability & preferences" row.

### 7.2 Editing a weekday — scope is always explicit (W5, W9a)

| Scope | Effect | Today |
|---|---|---|
| **This occurrence only** | Changes the session on one date; the template is unchanged | Exists (session edit) |
| **Temporary date range** | An exception to the template between two dates; the template itself is unchanged and resumes afterwards | **Future** — offered only when it exists |
| **All future occurrences** | The template changes; future generated sessions follow | Exists (week editor with preview) |

Until date-range exceptions are built, the sheet offers the two scopes that work, never a disabled or placeholder
third option.

Then a preview and approval. **Never rewritten silently:** the recurring pattern (by a single-session edit); future
sessions the athlete edited by hand or marked fixed (listed in the preview as "kept as you set it"); completed records.

### 7.3 Availability & preferences (own screen, W9b)
Regroups what exists — nothing is asked twice and nothing is removed: training days · time per day · two-a-day ·
weekly time per discipline (the existing budgets) · equipment · strength split · supersets · priorities · training
pause (unwell, injured, away). Each row opens its existing editor.

### 7.4 Feasibility — contextual warnings
A warning appears **where the problem is**, and only when there is one:
- on the affected weekday row: a warning mark and the row's right-hand text replaced by the short reason
  ("2 h · over by 1 h"); spoken as "Saturday, Long Ride, 2 hours, exceeds your available time by 1 hour";
- inside that weekday's sheet: the same reason in one line with **Fix**, which opens the existing Fix plan (raise the
  budget · edit the days · shorten or skip a session · keep as it is);
- a week-level problem that belongs to no single day (the weekly budget of a discipline is exceeded) marks the
  availability row instead ("Availability & preferences · over budget").

There is no separate warning block under the list. Goal / program conflicts use the same pattern when programs
exist (Future).

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
  time · a week over budget · strength sessions too close together · hard sessions on adjacent days · a missed session
  with a feasible later slot · a shorter alternative of the same intent. With recovery data absent, recommendations
  are schedule-based only and no recovery reason is invented.
- **Increases need approval.** Today the app applies small progressions automatically by default, through two
  separate code paths. The correction is proposed in `product/coach/AUTOADAPT_CORRECTION_PROPOSAL.md`; nothing was
  changed. Increases that were already applied are **not reversed** (decision R6).
- **Protective reductions are audited separately** in the same proposal, which lists each one and states whether it
  is advice or a change to a scheduled workout.

---

## 12. Interaction rules (complete)

**Scope**
1. One occurrence never changes the recurring plan.
2. A recurring change always states its scope: this occurrence only · temporary date range (when it exists) · all future occurrences.
3. A change never flows upward silently (session → recurring plan → goal).

**Approval**
4. Every consequential change is previewed; nothing is saved before approval; Cancel leaves stored data equal.
5. Increases in load, volume or frequency are proposals and are never applied automatically.
6. Protective reductions and holds are listed with their reason. Which of them may change a scheduled workout
   without approval is set out, one by one, in the auto-adaptation correction proposal and awaits the owner's decision.
6a. Increases applied before the approval rule arrives are kept as they are; nothing is reversed retroactively.

**Protection**
7. Completed sessions and their records are never modified by any Plan action.
8. Sessions edited by hand or marked fixed survive every regeneration and are listed as kept.
9. A missed occurrence is never rewritten, moved or converted to Done; resolutions are linked records (§6.7).
10. Nothing is rescheduled or stacked automatically.
10a. An original and its rescheduled or replacement session are one prescribed occurrence; nothing is counted twice.
10b. A replacement records its own actual duration and workload; it never stands for the original prescription.
10c. Soft training conflicts warn and can be overridden; only hard technical or data-integrity constraints block.
11. Planned rest days are preserved unless the athlete chooses otherwise; using one is called out in the preview.

**History**
12. Every applied change writes a history entry with Undo; Undo is previewed and never overwrites a later change.
13. Session states stay distinct in data: planned · scheduled · completed · missed · skipped · removed · rescheduled.
13a. Skip keeps a visible record; Remove deletes an uncompleted future occurrence and keeps a history entry with Undo.
13b. Audit history and completed records are never deleted by any Plan action.

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
      linked session ──finish──► COMPLETED with its own actual duration and workload; the original stays MISSED
SCHEDULED ──move (before its day)──► SCHEDULED on the new date (linked: movedFrom) + history entry
SCHEDULED ──skip──► SKIPPED ──restore──► SCHEDULED
SCHEDULED (today or later, not started) ──remove──► REMOVED: no row; history entry keeps the content ──undo──► SCHEDULED
```

---

## 13. Twelve journeys

Start · actions and transitions · data change · confirmation · error or cancel. **(F)** = needs a Future capability.

| # | Journey | Start | Actions and transitions | Data change | Confirmation | Error / cancel |
|---|---|---|---|---|---|---|
| 1 | Create a recurring hybrid week | Recurring Plan (empty) or onboarding | Tap a weekday → sheet → workout, duration; repeat. Or accept the week suggested from availability and goal | Template; coming weeks generated | Preview → "Use this week" | Feasibility warning if days and time do not fit; Cancel saves nothing |
| 2 | Change one workout only | Weekly Calendar › session ••• › Edit this session | Sheet (duration, exercises, supersets) → before / after review | That session only; history entry | "Apply to this session" | A blocked edit explains why and offers an alternative; Cancel leaves it equal |
| 3 | Permanently change availability | More › Availability & preferences | Change days / time → preview of future weeks, listing kept sessions | Availability, template, future generated sessions | Approve in preview | Conflicts with fixes; Cancel keeps the old availability |
| 4 | Miss a workout and reschedule **(F: any-day move, link)** | Weekly Calendar, the missed date | "Missed" row → Reschedule… → choose date → checks → preview | Original stays Missed (resolution: rescheduled); new linked session; history entry | "Reschedule" (or "Move anyway" after a soft warning) | Soft conflict: warning with explanation, may be overridden. Hard constraint: blocked with the reason. Cancel leaves it Missed and unresolved |
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
| 12 | Completed record of a linked session: actual duration and workload stored beside the retained original prescription | Shortened replacements reported as what they were (R2) |
| 13 | Removal record (what was removed, from which date, when) | Remove with exact Undo; "removed" count (R5) |
| 14 | Override record on a move (which soft conflicts were accepted) | Traceability of overrides (R3) |

Not needed: any change to completed records, to routines, or to existing plan versions.

---

## 16. Phases (each needs separate authorisation)

| Phase | Content | Depends on |
|---|---|---|
| 0 | Approve this specification | — |
| 1 | UI Lab prototype — exact scope in `product/plan/PLAN_UI_LAB_SCOPE.md`. Conditionally authorised (R7); not started | Review of v0.3 and of §20 |
| 2 | Production restructure **with existing data only**: two sections, date selector, session rows, one menu, single routine entry, removal of ring and Next-session card, Quick log to Train, wording | Release stabilised; Defect 6 resolved; integration review |
| 3 | Approval-only increases (auto-adaptation correction) | `product/coach/AUTOADAPT_CORRECTION_PROPOSAL.md`, separately authorised |
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
| Recurring Plan on the small size (revised) | Ends at y 530 against 583 in every state — 53 pt clear; warnings sit on the affected row, not in an extra block (W4, W9a) |
| Recurring Plan at large accessibility text | Rows take two lines and the list scrolls; the bottom inset keeps the last row clear of the dock (W9b) |
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

**Decisions of 12 Nov (v0.3)**
30. An original and its linked rescheduled or replacement session never produce two planned sessions or two completions in any count shown.
31. A completed replacement shows its actual duration beside the original prescription and is never labelled as the original session done.
32. A soft conflict shows a warning with a plain explanation and a way to continue; a hard constraint blocks with its reason. No soft conflict is worded as a prohibition.
33. A session can be moved to any future date inside the active program.
34. Skip leaves a visible Skipped row with Restore; Remove deletes a future uncompleted occurrence, offers Undo, and writes a history entry from which it can be restored exactly.
35. On the smallest supported iPhone, Recurring Plan content ends at least 16 pt above the dock zone at default text size, with no text or touch area made smaller than in the other sections.
36. Recurring Plan shows no explanatory paragraph, no Home metric and no warning block; warnings appear only on the affected row and in its sheet.

**Honesty**
27. No Future capability (events, times, date ranges, endurance library, calendar, advanced adaptation, weekly review) appears as a control before it works.
28. All six themes pass the contrast script; High Contrast uses borders.
29. Results are reported by evidence level; simulator results are not called device results.

## 20. Questions — decided, remaining, and new

### Decided on 12 Nov (were questions 1–6 and 11 of v0.2)

| v0.2 question | Decision |
|---|---|
| 1 Adherence after a reschedule | R1 — three separate measures; no double counting |
| 2 Replacement sessions | R2 — recorded as what was actually done |
| 3 Overriding a failed check | R3 — soft conflicts warn and can be overridden; only hard constraints block |
| 4 How far ahead | R4 — any future date within the active program |
| 5 Skipped vs removed | R5 — both kept |
| 6 Already-applied progressions | R6 — not reversed |
| 11 UI Lab start | R7 — conditional on the review of this version |

### The four remaining questions, with recommended defaults

| # | Question | Recommended default | Reason |
|---|---|---|---|
| Q1 | Place labels and times on session rows are Future. Is duration plus a short description enough for phase 2? | **Yes.** Rows show duration and a short description (exercise count, or ride type and zone). No time, window or place until those fields exist | The fields do not exist in the data today; showing them would mean inventing values |
| Q2 | Where does "Log a past session" sit in Train? | **Decide it in the Train specification, not here.** Until then nothing moves: the prototype shows only Plan's side (session › More › "Log this session" handing over to the existing logging screen), and production keeps today's entry points | Train has no specification yet; moving the entry without one risks a function being lost between two tabs |
| Q3 | Plan stops opening the Weekly overview and Day pages (shared with Home). Agree? | **Yes.** Plan's Weekly Calendar replaces them inside Plan; the pages stay in the app and stay reachable from Home | They repeat Home content, which the brief rules out; nothing is deleted |
| Q4 | Week starts on Monday? | **Yes, Monday**, as the app does today. A setting for another first day is Future | No change to existing week arithmetic or stored weeks |

### New questions raised by the 12 Nov decisions

| # | Question | Recommended default |
|---|---|---|
| Q5 | A move onto a date covered by the existing health-check pause (after a "see a doctor" or illness answer): warn, or block inside Plan? | **Warn clearly; do not add a block in Plan.** The existing production pause is left exactly as it is and applies to the moved session like any other |
| Q6 | A move made **before** the session's day: does schedule adherence follow the new date? | **Yes** — that is replanning, shown separately as "moved in advance". Only sessions missed first count as not adherent (metrics proposal §4) |
| Q7 | Removed sessions and percentages | **Removed sessions leave schedule adherence but stay in training fulfillment when they came from the program**, and are always shown as a count (metrics proposal §4) |
| Q8 | When is a completed session "partial"? | **Shown as actual-of-prescribed minutes, with no pass mark invented.** A session-count threshold is proposed for your decision in the metrics proposal §5 |
| Q9 | Which protective reductions may change a scheduled workout without approval? | Listed one by one in the auto-adaptation correction proposal §5, each with a recommendation |
| T1 | (Technical, to be answered from the code before building) How far ahead the stored plan reaches, and how a session moved beyond it is kept | Not yet investigated |

## 21. Limits of this document

- Written from the production source and existing audits; the app was not run for it.
- Competitor behaviour comes from two public pages and the owner's brief.
- All sizes are design estimates from wireframes.
- The coach's weekly-review structure and the strength session screen were not audited in depth.
- The planner's spacing rules were seen in its code comments (strength at least 48 h apart; strength kept away from hard rides where a choice exists) but **not extracted in full**; the checks in §6.6 must be built from the real list.

## 22. Visual direction (v0.4 — draft, awaiting visual approval)

Static mock-ups: `visual-v04/V1…V4`. They are drawn pictures with sample data, using only the six-theme UI Lab
prototype tokens of Brand Book §4.3. Nothing was built or run; sizes are design values, not device measurements.

### 22.1 Principles
- Depth comes from the theme's own tokens: background, two surface levels, border, accent, and the discipline
  colours (endurance blue / cyan, strength amber). Gradients and glows are mixes of those tokens; **no new token**.
- Dark themes: restrained luminosity behind the header and on the selected date. Light themes: layered surfaces and
  an accent-tinted header area instead of large flat white.
- High Contrast: no gradients, no shadows; borders and flat fills carry everything (V4).
- Circles are used for **navigation and selection only** — dates, and workout types inside a picker. There are no
  progress, recovery or score rings on Plan, and nothing from Home is reused.
- Status keeps its own treatment and is never colour alone: Planned (plain word) · Done (tick and word, title
  slightly dimmed) · Missed (dashed outline and word) · Rescheduled (link line "↳ Rescheduled from / to …").
  No green or red judgement is applied.

### 22.2 Circular date scroller (Weekly Calendar)
| Aspect | Rule |
|---|---|
| Content of a circle | Day number. Above it the weekday letter; below it the discipline marks (round = endurance, square = strength, dash = rest, nothing = empty; at most two, then "+") |
| What it never shows | Completion, percentages, rings that fill. It is a date control |
| Size | Circle 44 pt; cell about 52 pt (49.5 pt on the small iPhone); the whole control 82 pt high |
| Selected · today | Selected: accent ring or fill with a soft glow. Today: accent outline. Both can be true at once |
| Swiping | Horizontal swipe moves by week and snaps; the neighbouring weeks' edge days are visible, dimmed, as a cue. The ‹ › buttons stay, so swiping is never the only way |
| Selecting | Tap a circle: the sessions below change in place. The selection is kept when switching section and back |
| Vertical scrolling | The scroller takes horizontal drags only; a vertical drag that starts on it scrolls the page (the same technique that fixed the Home graph) |
| VoiceOver | One adjustable element per week plus one button per day: "Wednesday 11 November, today, selected, 2 sessions: ride, strength" |
| Dynamic Type | Numbers scale to a cap inside the 44 pt circle; the full date is always in the day header below |
| Reduce Motion | Week changes cross-fade instead of sliding; the glow does not animate |
| Multiple sessions · empty · rest | Two marks then "+" · no mark · a dash |

### 22.3 Workout picker carousel
Inside **Add session** and **Replace workout** only — never on the landing screen. One horizontal row of circular
type selectors: Strength · Cycling · Recovery · Routines · Program. Choosing one filters the list beneath, which
uses the existing routines and exercise systems. "Program" lists the sessions the current plan prescribes; named
program workouts are Future. Everything below the carousel stays ordinary rows, because rows are clearer for names
and durations.

### 22.4 Workout structure bar
A small segmented bar on a session row, **only when the prescription holds the data**: for a ride, its generated
steps (segment width = duration, height = intensity zone); for a strength session, one block per exercise (width =
sets). It describes the plan, not performance, and it is absent when a session has no structure. In the mock-ups the
bars are sample data.

### 22.5 The three alternatives
| | A · Premium Minimal | B · Athletic Dynamic | C · Balanced Premium |
|---|---|---|---|
| Sessions | One layered surface, hairlines, a thin discipline accent | Separate cards washed with the discipline colour, solid icon badges, structure bar | Separate layered cards, tinted icon badge, thin accent, structure bar |
| Selected date | Accent fill with a halo | Endurance-to-accent gradient with a strong glow | Accent ring with a soft glow (accent fill on light themes) |
| Background | Quiet surface gradient | Two discipline-coloured glows | One accent glow at the top |
| Row height (design value) | about 54 pt | about 74 pt | about 62 pt, about 78 pt with a bar |
| Strength | Most sessions visible; calmest | Most athletic and distinctive | Rich without crowding; discipline colour stays meaningful |
| Weakness | Closest to the v0.3 look; least character | Colour is loud; amber wash sits close to the warning colour; fewest rows visible | Fewer rows visible than A |

My recommendation was C. **The owner selected B (12 Nov); B is the direction.** One point carried forward from the
comparison: B's amber strength wash sits close to the warning colour, so warnings in B always carry the ⚠ mark and
a word, never colour alone (Brand Book §15 open item).

### 22.6 Cost in space — stated plainly
The circular scroller is 24 pt taller than the v0.3 date strip. On the small iPhone, with a suggestion row showing,
design C shows **two full session rows and the start of a third** before scrolling (v0.3: three); without the
suggestion row, three. A shows four. The first session and Add session stay visible in every case. To be measured
in a prototype, not assumed.

### 22.7 Not changed by this section
Sections, actions, states, links, conflicts, scopes, approval, routine and availability editing, counting rules, and
the Recurring Plan structure of v0.3. The Recurring Plan, sheets and Goal & Program screens have **not** yet been
redrawn in the new visual language; they follow once a direction is chosen. Horizontal phase navigation belongs to
the Program screen and stays Future with programs.

### 22.8 Questions for visual approval
1. Which direction: A, B or C (or C with named elements of another)?
2. Structure bars on rows: keep, or reserve for the session detail?
3. Is two-and-a-bit rows on the small iPhone acceptable for the richer look, or should small screens use the compact row of A?
4. Week-by-week snapping (drawn), or free day-by-day scrolling?

## 23. Plan in direction B — goals, Coach entry, planning intelligence (v0.5 draft)

Screens: `visual-v05-B/B1` Weekly Calendar · `B2` Recurring Plan · `B3` Add a goal sheet · `B4` goal setup and
program preview · `B5` Coach planning proposal · `B6` small iPhone. Obsidian and Arctic. Sample data throughout.

Status words used below: **Implemented** = in the production app today (read from source, not re-tested here) ·
**Proposed** = designed here, buildable on existing data, not built · **Future** = needs capabilities that do not exist.

### 23.1 Add a goal — placement
A pill inside the program row, at its right edge ("+ Add a goal"). The row itself still opens Goal & Program. It adds
**no height** to the landing screen. The pill is 32 pt tall with a 44 pt touch area.

### 23.2 Add a goal — the sheet (B3)
| Choice | What it starts | Status |
|---|---|---|
| Improve general fitness | Goal set-up with existing goal types | Implemented as a goal type; the sheet is Proposed |
| Build strength or muscle | The same | Implemented as goal types; sheet Proposed |
| Improve endurance or cycling performance | The same (endurance, power, sprint, climbing) | Implemented as goal types; sheet Proposed |
| Prepare for an event | Event set-up (B4) | **Future.** Cycling events first; marathon, running races and triathlon need running and swimming, which the app does not support |
| Health target as I age | A target on a **measured or entered value the app really has** (for example training sessions per week, weekly training time, strength sessions per week). No biological age, no age score, no prediction | **Future** — the list of supported values must be agreed first |
| Custom goal | A named goal with the athlete's own words, mapped to priorities by the athlete | **Future** |
| *Not a goal:* Add a sport or discipline | Adds a kind of session to the plan; it changes what can be scheduled, not what the athlete is aiming for | **Future** (running is next under Coach Decision 11) |

In a build, a choice is shown only when it works; the picture shows the intended complete sheet.
The sheet's subtitle states the goals the athlete already has.

### 23.3 Goal set-up and program preview (B4)
1. **Set-up** asks only what is needed: the goal's details · **priority** against existing goals (primary or
   secondary — one primary at a time) · and shows what the plan will use: time available (from Availability),
   recent training (from logs), and any entered values. A missing value is shown as "Not entered"; it is never guessed.
2. **Feasibility** is stated in words, from available time, weeks to the date and logged training — "Fits your time,
   with two changes", "Fits only if cycling takes priority", or "Does not fit: here is the nearest plan that does".
   It is a scheduling assessment, **not a performance prediction**, and says so.
3. **Preview** lists how the recurring plan and future schedule would change, what is kept because the athlete set
   it, and any choice the athlete must make. Phases appear as a horizontal row on this screen only.
4. **Nothing is applied without approval.** Approve · Adjust · Not now. Completed sessions never change.

Status: priorities between goals — Implemented (primary goal exists). Feasibility from weekly time — partly
Implemented (budget and fit report exist for the week; nothing for a dated goal). Event phases, milestones and the
preview of a program — Future.

### 23.4 Coach suggestion row (B1, B5)
- At most one row, between the date scroller and the day header, 44 pt high. Absent — with no gap — when there is no
  actionable proposal (B1, third phone).
- It carries a **specific** summary under a small "Coach suggests" label: "Move Thursday's ride to Friday" ·
  "Reduce next week's planned volume" · "Adjust training for your new event" · "Resolve Saturday's time conflict".
  With several proposals: the most time-critical one, plus "+2".
- Tapping opens the shared proposal detail (B5): what would change · why, in plain words · a preview on the date
  scroller · other options · Approve · Not now · Decline. It is the same component as in the Coach conversation.
  It is not Home's insight card and not a chat.

Status: proposals with approval — Implemented for session-level changes (rules-based). The specific-summary row and
the shared detail — Proposed. Volume and event proposals — Future.

### 23.5 Planning intelligence — where each capability lives
| Capability | Where the athlete meets it | Status |
|---|---|---|
| Primary and secondary goal priorities | Goal & Program; goal set-up | Implemented (primary goal); explicit secondary ranking Proposed |
| Goal feasibility from available time | Goal set-up › feasibility; Recurring Plan warnings | Partly Implemented (weekly fit report); dated-goal feasibility Future |
| Event-based program phases | Goal & Program › phases (horizontal) | Future |
| Weekly planning review | Offered through the Coach row when the coming week needs attention; a sheet | Future |
| Shorter workout alternatives | Session › Replace workout; missed-session choices; proposal "other options" | Partly Implemented (alternatives list); linked shortened replacements Future |
| Program milestones | Goal & Program | Future |
| Coach-assisted future adjustments | Coach row → proposal detail | Implemented for session-level rules; program-level Future |
| Protection of priority sessions in a conflict | Inside feasibility and proposals: when two sessions compete for time, the one serving the primary goal is kept and the other is offered shorter, moved or dropped — always as a proposal | Proposed as a rule; today the fit report lists conflicts without ranking by goal (to be confirmed in code before building) |

None of these appears as a permanent widget on the landing screen.

### 23.6 Screen density (measured in the static mock-ups, not on a device)
Row heights in B: session card about 73 pt with 8 pt gaps; Coach row 44 pt; date scroller 82 pt.

| Device | With Coach row | Without Coach row |
|---|---|---|
| Small iPhone (375 × 667) | **2 full workout rows**, and most of a third, above the dock | **3 full rows** |
| Standard iPhone (393 × 852) | 4 full rows | 5 full rows |

Add a goal costs no height. The Coach row costs 50 pt only while a proposal exists. On the small iPhone the
Recurring Plan ends 33 pt above the dock (21 pt above the v0.3 "dock line"), with seven 46 pt rows and the
availability row; text sizes and 44 pt touch targets are unchanged. A day with three or more sessions scrolls on the
small iPhone; the first two sessions and Add session are always visible.

### 23.7 Questions for visual approval
1. Is two full rows (with a Coach suggestion) acceptable on the small iPhone, or should the Coach row collapse to a
   one-line 36 pt strip there?
2. Should choices that do not work yet be hidden from the Add a goal sheet (recommended), or shown as "coming later"?
3. Which measured values may a "health target as I age" use? None is proposed as approved.

## Change log

| Version | Date | Change |
|---|---|---|
| 0.1 | 12 Nov 2026 | First draft |
| 0.2 | 12 Nov 2026 | Owner decisions 5–10 applied; goals-to-schedule chain (§4); landing reduced to the approved minimum; explicit scopes; missed-session data semantics and links (§6.7); Move to any day; Coach limited to one row and prepared options; Quick log to Train; Future capabilities removed from the main wireframes and collected in W8; acceptance criteria and unresolved questions rewritten |
| 0.3 | 12 Nov 2026 | Owner decisions R1–R7 applied: three separate measures and no double counting (§6.7); shortened replacements recorded as done (§6.7, §15); soft conflicts warn and can be overridden, hard constraints block (§6.6); move horizon is the active program; Skip and Remove both defined (§6.8); no retroactive reversal (§11, §12); Recurring Plan redesigned for the small iPhone with progressive disclosure and contextual warnings (§7, W4, W9a, W9b); questions regrouped with recommended defaults (§20); three companion documents added |
| 0.4 | 12 Nov 2026 | Visual direction added as a draft (§22): circular date scroller, picker carousel, structure bar, three static alternatives with a recommendation; functional content unchanged |
| 0.5 | 12 Nov 2026 | Direction B selected by the owner; Add a goal, Coach suggestion row, goal set-up and program preview, planning-intelligence map with implemented / proposed / future marks, density assessment (§23); static screens B1–B6 |
