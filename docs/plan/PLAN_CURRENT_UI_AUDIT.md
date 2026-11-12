# Plan page — read-only audit of the current production UI

Date: 12 Nov 2026 · Method: reading the production source only (branch `ios/checkpoint-f-ride`, commit `4e2e9dc`).
Nothing was changed, built or run for this audit. Test evidence is quoted from the existing build-216 completeness
audit (`iphone-app/APP_COMPLETENESS_AUDIT_BUILD216.md`), not re-run.

Files read: `PlanView.swift`, `PlanSummaries.swift`, `PlanWeekTimeline.swift`, and the parts of
`HomeDetailPages.swift`, `SessionChangePreview.swift`, `AvailabilityEditor.swift`, `ProfileScreens.swift`,
`StrengthLog.swift` and `ContentView.swift` that Plan opens.

## 1. What the Plan page contains today (top to bottom)

| Band | Content | Tap opens |
|---|---|---|
| A | Week selector: previous / next, "This week", date range. Past weeks unlimited; future limited to next week | — |
| (conditional) | "n changes waiting for your review" strip | Session change review sheet (first proposal) |
| (conditional) | "Riding is 40 min over · Fix plan" row | Fix plan sheet |
| B | Completion ring: "3 of 4 sessions done", "x recorded of y planned", missed / skipped counts | Weekly overview page (shared with Home) |
| C | Weekly timeline: seven rows, one per day, with a chip per session (sport icon, duration, state mark ✓ ◐ × ! ✱) | Day name → Day page (shared with Home). Chip → that session. Empty day → Add session |
| D | "Next session" card with Start / Resume / Open and the coach's stored reason | The session |
| E | Day cards: today's sessions as full cards, every other day's sessions as one-line cards, empty days as "free · add" | The session, or Add session |
| F | Manage plan: Your week · Plan changes · Routines · Quick log | Week editor sheet · versions list · routines sheet · quick log sheet |
| Toolbar | "More" menu: Quick log · Log exercises · Routines | The same sheets |

A session opens as a sheet: strength → the strength session screen; anything else → session detail with
**Move** (swap with another day), **Edit** (type, body region, duration, supersets), **Swap** (replace with an
alternative) and **Remove**. Significant edits go to a before / after review before anything is saved.

## 2. What already works (keep)

| Area | Evidence (build-216 audit) |
|---|---|
| Plan generation, week builder, approval | "Fully validated" — JourneyTests, Rc3EngineTests, HybridTests, RoutinesTests |
| The six-band Plan screen: ring → overview, day → Day page, chip → session, reason line | "Fully validated" — PlanSummariesTests, PlanProgressRecoveryScreensTests, layout audit on four devices |
| Day rows and chips as separate controls for touch and VoiceOver | Owner requirement of 8 Nov, covered by tests |
| One data source: Plan uses the same week ledger and overview as Home | By construction (`planWeekSummary` → `homeWeekOverview`) |
| Edits are previewed before saving; every applied change is a version with Undo | Engine tests; versions list |
| "Fix plan" only appears with a real fix | BudgetFix tests |
| Nothing is estimated: no planned-vs-recorded numbers are invented | By construction |

Known open defect that touches Plan: **Defect 6** — the review sheet opened from a strength session's Edit could stay
on screen after Apply. A fix is on the release branch but its Apply path has not been validated (three owner
decisions are still open). Any Plan redesign must not hide this.

## 3. What is duplicated

| # | Duplication | Where |
|---|---|---|
| D1 | **The week is shown three times**: ring summary (B), timeline with all sessions (C), and day cards with all sessions again (E). Every session is tappable in both C and E and opens the same sheet | PlanView body |
| D2 | **The next session is shown three times**: its chip in C, its own card in D, and (when it is today) a full card in E — plus Home and the Training Hub | PlanView body |
| D3 | **Quick log and Routines appear twice**: toolbar menu and Manage plan. "Log exercises" appears only in the menu | Toolbar + band F |
| D4 | **Adding a session to an empty day appears twice**: "Free · tap to add" in C and "free · add" in E | C + E |
| D5 | **Three histories of change**: "changes waiting for your review" (proposals), "Plan changes" (versions), and the coach's own notes — with the Coach conversation designed in Home v2.3 this becomes four entry points unless they are joined | Strip, band F, Coach |
| D6 | Dead code: a day-list sheet (`dayListSheet`) is still in the file but nothing opens it; the History list (`TimelineSection`) lives in this file although it is only used by Progress | PlanView.swift |

## 4. What is confusing

| # | Issue | Why it confuses |
|---|---|---|
| C1 | **Move / Swap wording.** "Move" actually swaps two days ("the two days swap"); "Swap" replaces the session type | The words suggest the opposite of what happens |
| C2 | **Two destinations per day row.** The day name opens the Day page; a chip opens the session; the row background also opens the day | Correct and tested, but not discoverable — nothing says the chip and the row differ |
| C3 | **State marks are text glyphs** (✓ ◐ × ! ✱) and differ from Home v2.3 (dot, hollow dot, cross, arrow). The owner removed ticks from Home | Two visual languages for the same states |
| C4 | **Coach-adjusted** is a chip mark (✱) and a pill ("planned · coach-adjusted") with no route to *why* it was adjusted from the chip itself | The reason exists (stored rationale) but is one or two taps away |
| C5 | **Week navigation is asymmetric**: unlimited back, one week forward, with no explanation | Looks like a bug to a user |
| C6 | **Day page cannot change anything** and says so in a footnote ("changing a session happens on the session itself") | A page that needs a sentence to explain what it does not do |
| C7 | **Two visual systems on one flow.** Plan uses the older system-grouped style (`BC`, `DS`); the pages it pushes (Weekly overview, Day) use the newer `CyTheme`. Neither follows the six themes of Home v2 | The look changes when the user taps |
| C8 | **Manage plan** mixes configuration (Your week), history (Plan changes), library (Routines) and an action (Quick log) under one heading | Four different kinds of thing in one list |
| C9 | Length. With seven timeline rows, a next-session card, seven or more day cards and four manage rows, the page is long and the most useful part (this week at a glance) is repeated instead of deepened | Scrolling to see information already shown |

## 5. What can be simplified (proposal input)

1. **Show the week once.** Keep one week view; remove the second list. Selecting a day reveals that day's sessions beneath the week strip (the Home schedule pattern), instead of listing all seven days twice.
2. **One "next" surface.** The selected day defaults to today; today's unfinished session carries the Start / Resume action. No separate Next-session card.
3. **One state language** shared with Home v2.3 (icon + mark), with the same accessibility wording.
4. **One place for change**: pending proposals open the Coach proposal detail designed in Home v2.3; applied changes stay in "Plan changes". Plan links to both; it does not hold a third version.
5. **Rename Move / Swap** to say what happens ("Swap days", "Replace session"). Wording change only — the behaviour is validated and stays.
6. **Split Manage plan** into "Your week" (availability and budgets) and a compact "More" row (Plan changes, Routines, Log a session) — each item once.
7. **Remove dead code** when Plan is implemented (not now).
8. **Explain the forward limit** ("Next week is built when this week ends") or lift it — owner decision.

## 6. Dependencies (what Plan touches)

| Dependency | Used for | Shared with |
|---|---|---|
| `Store.planWeekSummary`, `homeWeekOverview`, training ledger | Ring, timeline, next session, minutes | Home |
| `HomeWeekOverviewView`, `HomeDayDetailView`, `HomeRoute`, `HomeAction` | Pushed pages and their actions | Home, Training Hub |
| `WorkoutDetail`, `StrengthWorkoutScreen` | Session sheets | Home, Training Hub |
| `SessionChangeSheet`, `PlanChangeSheet`, `PlanVersionsView`, proposals | Review, versions, Undo | Coach, strength edit (Defect 6) |
| `FixPlanSheet`, `BudgetFix`, `fitReport` | Budget conflicts | Profile (week) |
| `WeekPage` / `WeekBuilder` | "Your week" | Onboarding, Profile |
| `TemplatesView`, quick and detailed strength log sheets | Routines, logging | Strength, Profile |
| `RideRecorder`, `DeviceLink`, `WatchLink` | Start a ride from a session; targets to the BikeComputer | Ride, hardware |
| Accessibility identifiers `planDay-n`, `planChip-…`, `planRing`, `planNextSession`, `planProposalStrip`, `fixPlan`, `planChanges`, `planWeekSettings`, `planMenu…` | 25 references in the UI tests | Production tests — a production redesign must migrate these deliberately |

## 7. Limits of this audit

- Source reading only. I did not run the app or look at the Plan screen on a device for this audit.
- "Works" statements rest on the build-216 audit and its test names, not on a new run.
- The strength session screen, the week builder and the routines editor were not audited in depth; they are reached from Plan but belong to their own pages.
