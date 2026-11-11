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

## C. Things the prototype deliberately does not do

- It does not compute any metric. Every number and status word is sample text.
- It does not replace any working production view. Integration is a later, separately approved step, one screen at a time.
- It shares no test, workflow or build setting with the production pipeline.
