# Integration map — prototype components ↔ existing production code

**Nothing here is integrated.** This lists how each prototype component would later connect to the working app
(branch `ios/checkpoint-f-ride`), for a separately approved integration step. Production names are from the
Home v2 implementation map and the code audit; they were read, not changed.

## Integration contract (every component)

- Data is passed in as plain values (`Components/Models.swift`); user actions come out as callbacks.
- No component imports or references the production store, engines, Apple Health, BLE or navigation.
- No user-specific text is hard-coded; sample text lives only in `Mock/MockData.swift`.
- A thin adapter per screen (for Home: production `HomeDashboard` → `HomeData`) is the only code that will know both sides.

## A. Components that can reuse existing production code (data and behaviour already exist)

| Prototype component | Production source that already provides the data / behaviour | Note |
|---|---|---|
| `CyWeekStrip` / `CyDayModel` | `HomeDashboard.days`, `CyDay`, `CyDaySport`, `CyDayStatus`; day tap → existing Day page | Multi-session days need the small `sessions` extension already listed in the Home v2 map |
| Consistency ring | `homeWeekOverview` (done, planned, missed, skipped) | Pure presentation of an existing ratio |
| Recovery ring, `CyRecoveryCard` | `RecoveryAnalysis.advice`, `RecoveryFreshness` | Words already exist; "No readings" state already exists |
| `CyTrainingSummaryCard` (Endurance) | `homeWeekOverview`, ride history in `ProgressAnalytics` | Rename + planned-minutes field (map §3) |
| `CyTrainingSummaryCard` (Strength Load) | `homeWeekOverview`, strength volume in `ProgressAnalytics` | Session count primary, volume supporting |
| `CyCoachInsightCard` | `HomeModel.coachItem` (`HomeCoachItem`), existing Why sheet | Layout only |
| `CyGettingStartedCard`, `CyChecklist` | `HomeSummaries.setupItems` (`HomeSetupItem`) | Placement rule + persisted collapse state are new |
| `CyReviewSheet` | Existing review flow (`SessionChangeSheet`, plan change proposals) | The production sheet stays; this is a visual reference until a restyle is approved |
| `CyConfirmSheet` | Existing confirmation dialogs (delete, discard) | Visual reference |
| `CyTabBar` | Existing dock with the centre Training Hub button | Do not replace the working dock; restyle only if approved |
| `CyWorkoutCard` | Hub and Plan session rows (`Workout`, `StrengthWorkout`) | Visual reference for Plan / Hub prototypes later |
| `CyFormField`, `CySegmented`, `CySelectionCard`, `CySportPicker` | Onboarding and Profile controls | For the Onboarding / Profile prototypes later |

## B. Components that need integration work later (new code on the production side)

| Prototype component | What is missing in production | Dependency |
|---|---|---|
| Theme tokens (six themes) | Production has `CyTheme` with its own names and no six-theme layer (the earlier appearance branch was lost). Token names must be mapped or adopted; a `homeTheme` / theme id setting is needed | Home v2 Stage B/D; decision of 10 Nov |
| Load Balance ring + detail sheet | `LoadBalanceMetric` (pure) over the engine's acute / chronic load; detail page listing inputs, bands and limits | Home v2 map §3 and §8; wording approved conditionally |
| `CyTrendChart` (combined trends) | `HomeTrendSeries` builder: per-day consistency %, Load Balance status, Recovery word; gaps preserved | Home v2 map §3 |
| Getting Started placement | Rule "below the circles while an essential step is open, bottom when complete" + persisted collapse | Small model addition |
| Ring row at accessibility sizes | Production Home has no ring list layout | New layout |
| Postpone on the coach row | A "postponed" state does not exist yet | Adaptive Lifestyle Coach Phase 1 (planned, not authorised) |
| Sport picker "support level" notes | Sports other than cycling / strength do not exist | Adaptive Lifestyle Coach Phase 6 (planned) |
| Accessibility identifiers | The prototype has none; production UI tests rely on ids such as `homeRingConsistency`, `homeDay-<weekday>` | Add at integration, keep existing ids |

## Home v2.1 additions (12 Nov 2026)

| Prototype component | Reuses existing production data / behaviour | New integration work later |
|---|---|---|
| Consistency ring + adherence sheet | `homeWeekOverview` counts (done, planned, missed, skipped) | "Rescheduled" as its own state (production has moved sessions but no such label on Home) |
| Training Mix double ring + sheet | Per-sport done / planned totals already computed for the week overview | A small `TrainingMix` value (two fractions); rule for single-sport athletes. **The acute:chronic load analysis is untouched and stays a separate analytics capability** |
| Recovery indicator + sheet | `RecoveryAnalysis` readings, usual range, advice wording | Availability arcs per reading; approved wording for each state; no percentage |
| Compact schedule | `HomeDashboard.days`, `CyDay` | Per-session state marks (completed / planned / missed / rescheduled); two sessions per day |
| Compact sport cards | Week totals; distance; lifted volume | Title "Strength" (not "Strength Load") when the card shows sessions |
| Sleep bar + sheet | Sleep durations already read from Apple Health (`SleepAggregation`) | A user-chosen or documented sleep target and its source field — **no target exists in production and none is to be invented**; seven-day average |
| Coach banner | `HomeCoachItem`, Why sheet, review flow | "Postponed" state (planned in the Adaptive Lifestyle Coach, Phase 1 — not authorised) |
| Trends module | Daily ride and strength minutes from history | `HomeTrendDay` builder (minutes per discipline, planned minutes, per-day rows); 4-week aggregation |
| Key metrics grid | Resting HR / HRV (Health reads), training time, session load, ride power, strength volume | Selection rule per athlete (sports, goals, connected data); comparison wording; metric detail pages |
| Floating dock | Production already has the original floating dock (`CyLiquidDock`) | None for behaviour — the prototype mirrors it; only theme tokens would be shared |
| Gradients / quieter cards | — | Token layer (as in section B) |

## Home v2.2 additions (12 Nov 2026)

Provenance categories requested by the owner: **Existing** = existing engine or stored data · **Mapping** = data
exists, needs an adapter · **Calculation** = needs a new, documented calculation · **Validation** = must not ship
without scientific validation and owner approval.

| Prototype element | Category | Production source / what is missing |
|---|---|---|
| Training Mix centre ratio (completed minutes, endurance : strength) | Calculation (trivial) over Existing data | Ride and strength durations are already stored. New: a `TrainingMix.completedRatio` value with the documented rounding rule and the "no completed time" state |
| Training Mix planned ratio (sheet only) | Mapping | Planned minutes per discipline from the approved week plan |
| Training Mix rings | Existing + Mapping | As in v2.1 |
| **Acute:chronic load analysis (ACWR) engine** | Existing — **kept, untouched** | Stays a separate analytics capability. It is not the Mix ratio and is not shown on the Mix indicator |
| Recovery percentage | **Validation** | No approved numerical recovery model exists. Production must show `.qualitative`, `.partial` or `.awaiting` until a documented method is validated and approved. The prototype percentage is sample text, not a formula |
| Recovery status word, readings, freshness, missing inputs | Existing | `RecoveryAnalysis` advice wording, Health readings, freshness |
| Schedule session marks | Existing + Mapping | Day sessions and their status; "rescheduled" label needs mapping |
| Sleep bar: last night, 7-day average | Existing / Calculation (mean of recorded nights) | Sleep durations from Apple Health |
| Sleep target | Mapping (user setting) | A user-chosen target does not exist yet; none is to be invented. No sleep-need algorithm |
| Coach observation → recommendation | Mapping | The coach item already has a reason and a proposal; they need to be passed as two fields |
| Key metric rows | Existing + Mapping | As in v2.1; weekly load stays session effort × minutes |

### Trend graph series

| View | Series | Unit | Scale | Category | Source in production | Missing-data handling |
|---|---|---|---|---|---|---|
| Training & Recovery | Training load | RPE×min per day | Left, from zero | Existing | Session load (session effort × minutes) already computed per session; needs a per-day sum (Mapping) | Day without a session after today: gap. Past rest day: 0 |
| Training & Recovery | Recovery | % | Right, fixed 0–100 | **Validation** | None. Sample only; hidden in the status-word scenarios | Gap |
| Activity | Endurance | minutes per day | Left, from zero | Existing | Ride durations | Gap for days not yet reached |
| Activity | Strength | minutes per day | Left, from zero | Existing | Strength session durations | Gap |
| Activity | Planned | minutes per day | Left, same scale | Mapping | Planned session durations from the week plan | Gap when no plan |
| Recovery trends | Resting HR | bpm | Own scale | Existing | Apple Health read | Gap; no interpolation |
| Recovery trends | HRV | ms | Own scale | Existing | Apple Health read | Gap |
| Recovery trends | Sleep | hours | Own scale | Existing | Apple Health read | Gap |

Graph behaviour that is new production work (Calculation / Mapping, no science needed): per-day series builder for
7 and 28 days with explicit `nil` for missing days; the selected-day value panel; the daily sheet contents.
Nothing in the graph is a stress, strain or readiness score.

## Home v2.3 additions (12 Nov 2026)

### Coach conversation — data model and integration points

The conversation is a **view over coach events**. It does not replace or rewrite the rule-based coach. The prototype
shows sample history held in memory.

| UI model (prototype) | Meaning | Production source today | What is missing |
|---|---|---|---|
| `CyCoachEntry` kind `observation` | Something the coach noticed | Coach findings / session results (rule-based engines) | A stored, dated event per finding (today most are computed for display and not kept) |
| kind `recommendation` | Advice without a plan change | Coach item reasons | Same: persistence with a date |
| kind `recovery` | Recovery and fatigue advice | `RecoveryAnalysis` wording (advice only) | Persistence; it must stay advice and never raise training |
| kind `proposal` + `CyCoachProposal` | A proposed plan change: changes, reason, benefit, impact, status | Pending proposals and the session change review | Mapping of "benefit" and "impact" texts; a stable proposal id that survives the decision |
| kind `decision` | The athlete's approve / postpone / decline | Proposal apply, dismissed adaptations | A dated record of each decision (declines are remembered today only as exact keys) |
| kind `outcome` | What happened after the decision | Plan versions ("Plan changes") | Link from a plan version back to the proposal that caused it |
| kind `question` / `answer` | Two-way messaging | **Nothing** | Future capability: needs a design for scope, safety and, if any cloud model is used, explicit consent (Decision 3). Not part of this prototype |
| `CyCoachConversation.preview` | Home's "latest relevant insight" | — | The same three-step rule: open proposal → newest recommendation or recovery advice → newest observation |

New production pieces needed (all Calculation / Mapping — no science): a `CoachEvent` store (id, date, kind, text,
proposal id, author) written by the existing engines when they produce a finding, proposal or acknowledgement; a
retention rule; migration is additive (no existing data changes). The approval rule is unchanged: **nothing in the
plan changes without the athlete's approval**, and increases are never applied automatically (Decision 1).

### Other v2.3 items

| Prototype element | Category | Production source / what is missing |
|---|---|---|
| Sleep target chosen by the athlete | Mapping (new user setting) | A `sleepTargetMinutes` setting, optional. No sleep-need calculation, no recommendation |
| Recovery percentage ring | **Future dependency — Validation** | The percentage ring is the intended future design. Required before it can show a number in the app: (1) a documented scoring method, (2) its inputs (sleep, HRV, resting HR and possibly training load) with rules for missing inputs, (3) validation against data, (4) owner approval, (5) integration with the status-word, partial and unavailable fallbacks kept. Until then production shows the fallbacks only. No algorithm was invented in this refinement |
| Sheet presentation guard | Calculation (UI logic) | A single "present" function with a pending slot and the sheet's dismissal callback; the same pattern should be used in the app's Home when Stage B is authorised. Relevant to production Defect 6 (a nested sheet staying on screen) — to be assessed there, not assumed fixed |

## C. Things the prototype deliberately does not do

- It does not compute any metric. Every number and status word is sample text.
- It does not replace any working production view. Integration is a later, separately approved step, one screen at a time.
- It shares no test, workflow or build setting with the production pipeline.
