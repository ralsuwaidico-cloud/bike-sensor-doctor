# Cyclift V1 product-experience upgrade — Checkpoint A

Audit, architecture and staged plan. Documentation only: no application code, firmware or data changed.
Prepared 4 Nov 2026 against the build 153 baseline. The visual and interaction prototypes follow as a separate delivery for approval before Checkpoint B.

---

## 1. Protected baseline (confirmed, not guessed)

| Item | Value | How verified |
|---|---|---|
| Build 153 commit | `781a5b1f905821bca9dcfbd50328e911f14c1cfc` on branch `ios/v1` | GitHub run 41649655899 (`run_number` 153, `head_sha`, conclusion `success`), and the CI summary for run 153 |
| TestFlight | build 153 processed VALID, installable by internal testers; not released | CI `testflight` job, run 153 |
| Rollback tag | `v1-build153-baseline` → that commit | created locally on 4 Nov; pushed with the first Checkpoint B push |
| S2-0 | frozen at `9419d4cd`, build 142 | unchanged |
| Upgrade branch | `impl/v1-ux`, created from the build-153 commit; pushed as `ios/v1-ux` | all upgrade work goes here; `ios/v1` stays at build 153 |

Nothing in this checkpoint touches the data file (`store.json`, schema 4), migrations, firmware, BLE protocol or Watch contract.

---

## 2. Interpretation of the five approved change areas

| Area | What the owner asked for, as I read it | What stays exactly as it is |
|---|---|---|
| **Home (H-001…H-010)** | A light-first analytics dashboard: compact greeting; weekly completion ring with explicit planned/done/remaining and date window; cycling and strength summary cards with mini charts; compact week calendar with distinct day states (incl. W12 "before this plan started"); concise Coach insight; recovery/goal context only with real data. Every card drills down. The large Today card moves to the Training Hub. | Onboarding; what counts as done/missed (the ledger); health hold and caution behaviour (APP-012); the Coach's decision rules; the first-week section's data. |
| **Progress (P-001…P-012)** | Short visual overview (Cycling · Strength · Recovery, then Consistency and Body & Discomfort), each opening a real detail page with ranges, history, sources and honest empty states. Checkpoints become compact milestones. History becomes interactive with filters. Reports per period. | All existing calculations (WeekTotals, ProgressMetrics, checkpoints, e1RM, FTP confidence); history records; FTP stays Unknown until established. |
| **Ride (R-001…R-012) — Cyclift Horizon** | A map-based riding display and a metrics-focused display, a coordinated primary/secondary metric hierarchy, sensor-aware states, one-instruction coaching, safe controls, mode switching that never interrupts recording. | `RideRecorder` (who records, start/pause/end/save), `LocationService`, `SensorHub`, `DeviceLink`/`BCLink`, `WatchLink` and the Watch message contract, `RideCoach` decision logic, the ride Start gate for health holds. |
| **Navigation (N-001…N-008) — Liquid Dock** | One reusable floating translucent capsule with a liquid selection animation, haptics, Reduce Motion, Dynamic Type, VoiceOver and safe areas; a smaller centre button. | Tab destinations and order; page state kept alive across tabs; during an active ride the workout controls win. |
| **Training Hub (T-001…T-010)** | The centre button always opens the Training Hub; the hub holds the full Today card(s) with Start/Resume/Results/Why/More; the button reflects state (pending glow, in progress, completed, rest, multiple, missed). Coach recommendations: explain → original → proposed → difference → preview → approve → save → Undo. | Workout execution and logging engines; prescriptions; what "today's action" is (`Store.homeToday`); health hold routing. |

Interpretation choices I am making unless you say otherwise:
- "Light-first" applies to Home, Progress, Training Hub, detail pages and the dock. The Ride cockpit keeps a dark outdoor presentation (allowed by §2.1).
- Recovery on Home appears only when Apple Health reads (resting HR, HRV, sleep) or a check-in exist; otherwise the card shows what is needed, not a score.
- Body & Discomfort (Checkpoint E) is new personal-health data; it is designed in Checkpoint A but built only after its own consent/privacy review.

---

## 3. Existing components that can be reused

**Design system (new, `ios/BikeComputer/DesignSystem/`)** — already light-first with dark pairs:
- Tokens: `CyTheme` surfaces (canvas, card, card2, line, ink…), identity families cycling / strength / recovery / goal / insight, warn/bad/ok, spacing sp1–sp6, radii rHero/rCard/rField/rChip, `minTap` 44, motion durations; `CyType` Dynamic Type scale; `CyMotion.animation(_:reduce:)` (Reduce Motion aware).
- Cards: `CyMetricTile`, `CyHeroRingCard`, `CySessionCard`, `CyCoachCard`, `CyGoalIndicatorCard`, `CyLiveMetric`.
- Primitives: `CyPrimaryButton`, `CySecondaryButton`, `CyChip`, `CySegmentedControl`, `CyListRow`, `CyRowGroup`, `CyStepper`, `CySwitchRow`, `CyBanner`, `CyEmptyState`, `CyInsufficientDataState`, `CyDeviceStateBadge`, `CySourceTagBadge`.
- Charts (custom SwiftUI): `CyProgressRing`, `CySparkline`, `CyBarChart`, `CyCalendarStrip` (day states), `CyMonthCalendar`, `CyIntervalTimeline`, `CyRestTimerRing`.
- `CyFloatingTabBar` already exists (`CyCards.swift:223`) — used only in the gallery today. It is the natural base for the Liquid Dock.
- `DesignSystemGallery` + `DesignSystemAudit` test (every control in window, ≥ 44 pt, light and dark).

**Data and calculations (reuse as the single source of truth):**
- `WeekTotals` / `store.homeWeek()` — planned vs done riding minutes and strength sessions.
- `ProgressMetrics` — `TrendChartMath` buckets per week, ranges 4/8/12/16 wk and 1 yr, `WeekDetail`; `ProgressGlance`.
- `Timeline.build` — the deduplicated session history (rides, strength, imports).
- `store.checkpoints(.cycling/.strength)` — the 4/8/12-week milestones with `performance` and `missing`.
- `store.liftSummaries()` — top set per lift, e1RM (labelled estimate).
- `RiderProfile.ftpSource` / `ftpBadge` — Unknown / Entered / Estimated / Tested.
- `HealthReads` — weight, resting HR, HRV, sleep hours with source and date.
- `CheckIn` (post-session): RPE, performance, `PainLevel` + `PainArea`.
- `DeviceState` (`Provenance.swift`) and `SensorHub.sources` — the real sensor states.
- `Store.homeToday(...)` — today's action, hold/caution, single/multi/rest/first layouts. The Training Hub reads this unchanged.
- Coach: `coachChangePreview → commitCoachChange`, `proposePlanChange → applyPlanChange`, `proposeUndo`, plan versions — the approved preview-confirm-save-Undo path.
- Swift Charts already in `WeeklyTrendChart`, `Spark`, `RideDetailView` (with `AXChartDescriptor`).
- MapKit: live `Map` + `MapPolyline` in `RideDetailsSheet`; static route in `RideDetailView`. `LocationService` (CoreLocation, background, `.fitness`).

---

## 4. Requested capabilities not supported today

| Capability | Status in build 153 | What it needs |
|---|---|---|
| Floating navigation in the app | `CyFloatingTabBar` exists but is not wired; the shell uses `RideTabBar` (fixed, `.bar` material) | Wire a dock component into `RootView`; keep the `tabPage` ZStack and tab indices |
| Liquid selection animation, haptics | No haptics anywhere in iOS or Watch targets; no selection animation | New, small, in the dock only (`UISelectionFeedbackGenerator` / `.sensoryFeedback`) |
| Weekly completion ring on Home for every week | Only `CyHeroRingCard` in the first-week section | Home card fed by `homeWeek()` with explicit denominator and window |
| Cycling / strength summary cards on Home | Removed by design in RC3 (comment `HomeView:6`) | Two cards reading `homeWeek()` + `TrendChartMath` buckets |
| Day states "before plan started", "rescheduled", "active" in the strips | `CyCalendarStrip` has `CyDayStatus` but no pre-start or rescheduled state; W12 not built | Extend `CyDayStatus` (additive) and the mapping in Home/Plan/Progress |
| Drill-down pages: Training Overview, Cycling Analytics, Strength Analytics, Recovery, Goal, Day, Recommendation | None exist as pages; Progress glance cards only scroll to a section | New SwiftUI pages, reading the existing calculations above |
| Compact Progress overview with three categories | Progress is one long page: glance grid → trend → FTP → strength → checkpoints → timeline | New overview; existing sections move into the detail pages |
| Recovery analytics | Health reads exist (4 kinds); no sleep consistency, no trends UI, no subjective daily data | Detail page over `HealthReads` history (needs storing a short history of reads — today only the latest value is kept per kind) |
| Body & Discomfort daily check-in, body-area selector, soreness/pain trends | Only post-session `CheckIn` with pain level/area | New model + storage (schema field, additive), consent screen, privacy text — **Checkpoint E, separately reviewed** |
| Interactive history with filters and a detail view per session | `TimelineSection`: 12 rows + "Show all", row → detail; no filters | Filters (type, period, source) over `Timeline.build`; detail views exist |
| Progress reports per period | Not present | New report view composed from existing metrics; "insufficient evidence" states |
| Horizon Map mode | Map exists only in a details sheet | Map as the cockpit base with metric overlays; recorded route from `RideRecorder` samples |
| Planned route, upcoming turns, navigation | **Not implemented** (no route import, no turn-by-turn, no offline tiles) | Out of scope for this upgrade; Horizon must not imply it exists. Shown only as "no planned route" |
| Horizon Focus mode | Five existing layouts (coach, gauges, classic, rings, analytics) | A single coordinated primary/secondary hierarchy; existing layouts retired only after owner approval of the prototype |
| Sensor-status row + sensor details screen | `DeviceState`, `SourceStatus` exist; Ride shows a large missing-Watch warning | Compact indicator strip; details screen listing `SensorHub.sources` |
| Centre-button state styling and breathing glow | Label changes only (`Store.TodayAction`) | Dock button reads `homeToday().centre` and renders state; glow with Reduce Motion fallback |
| Training Hub page | `TrainNowSheet` (a chooser) and the Home Today card | New page containing the existing Today card layouts moved from Home, plus results entry |
| Coach recommendation workflow on Home | Coach card opens `HomeProposalSheet`; some accept paths apply directly (`Store.apply(CoachProposal)`, adaptive accept — D-SE-4) | Route Home recommendations through `coachChangePreview → commitCoachChange` only; where no preview exists, show as **advisory** (per §7.7), no new mutation path |
| Reduce Motion in older screens | Honoured by Cy* only; 5 older animation sites ignore it | Fix only on screens being rebuilt |

---

## 5. Proposed navigation and data architecture

### Navigation map (destinations)

```
RootView (ZStack pages 0–4, unchanged indices)
 ├─ 0 Home ──────────── Weekly ring ───────► Training Overview
 │                      Cycling card ──────► Cycling Analytics
 │                      Strength card ─────► Strength Analytics
 │                      Week day ──────────► Day Details (existing WorkoutDetail / day list)
 │                      Coach insight ─────► Recommendation Details (explain → preview → approve)
 │                      Recovery / Goal ───► Recovery Details / Goal Details (only with data)
 │                      compact reminder ──► Training Hub
 ├─ 1 Plan (unchanged; calendar day states shared with Home)
 ├─ ● Training Hub (centre button; sheet/page over the current tab, state kept)
 │                      Start / Resume ────► existing StrengthWorkoutScreen / Ride tab
 │                      View results ──────► existing results sheets
 │                      Why / More ────────► existing Why and More menus
 ├─ 2 Ride = Cyclift Horizon (Map ⇄ Focus; sensor strip ► Sensor details)
 ├─ 3 Progress overview ─ Cycling / Strength / Recovery ► detail pages
 │                        Consistency ► Consistency Analytics
 │                        Body & Discomfort ► check-in + trends (Checkpoint E)
 │                        Milestones ► Checkpoint detail · Reports ► Report · History ► filters + session detail
 └─ 4 Profile (unchanged)
```

The dock is one component (`CyLiquidDock`, built from `CyFloatingTabBar`) used by `RootView` only; it replaces `RideTabBar` on the five main pages. Tab selection stays `@State` in `RootView`; the hub opens as a presented page so navigation history is preserved.

### Data flow (one authoritative source)

```
store.json (schema 4) ──► Store
   plan + rides + strength ──► ledger (done / missed / rescheduled) ──► WeekTotals ──► homeWeek()
                                                                     └► TrendChartMath (weekly buckets, ranges)
                                                                     └► Timeline.build (history)
   profile (+provenance) ──► ftpSource, zones (unchanged)
   healthReads ──► Recovery details (source + date)
   checkIns (per session) ──► Recovery / Body trends (existing)
   [Checkpoint E] dailyCheckIns (new, additive) ──► Body & Discomfort
   homeToday() ──► Training Hub + dock centre state (one function, one truth)
   coach: homeCoach() ──► insight card ──► coachChangePreview ──► commitCoachChange ──► planVersions (Undo)
```
Rules: Home, Progress, Training Hub and Plan read the same functions; no screen computes its own totals. Pre-start days (W12) are excluded from denominators in `WeekTotals`/adherence via one helper used everywhere. Every metric carries a `SourceTag` (measured / imported / entered / calculated / estimated / unavailable).

---

## 6. Staged implementation plan with dependencies

| Checkpoint | Scope | Depends on | Exit evidence |
|---|---|---|---|
| **A** (this) | Audit, architecture, specs, prototypes, owner approval | — | Owner approves prototypes and this plan |
| **B** | Design tokens extended (coaching family, pre-start day state), reusable cards/rings/chart styles, `CyLiquidDock` with liquid animation + haptics + Reduce Motion, dock wired into `RootView` with existing destinations; W12 day state in the shared strip | A approved | Quick run green on SE AX3 + standard; full run; DesignSystemAudit; LaunchSmoke; journeys unchanged |
| **C** | Home dashboard (ring, cycling, strength, calendar, coach insight, recovery/goal with data), Training Hub, centre-button states and glow, Today card moved; drill-downs: Training Overview, Day, Recommendation | B | Journey tests extended to Home cards; Training Hub state tests (pending/started/interrupted/resumed/completed/multi/rest/missed/relaunch); AdaptiveSmoke unchanged |
| **D** | Progress overview, Cycling Analytics, Strength Analytics, Consistency, Milestones, Reports, interactive History | B (C for shared cards) | Layout audits on all four devices; functional tap tests per card; metric parity test Home = Progress |
| **E** | Recovery analytics over Health reads history; Body & Discomfort daily check-in (consent, privacy, storage) | D; owner's separate data-model/privacy approval | Unit tests for storage and migration (additive, idempotent); UI tests for check-in and trends |
| **F** | Cyclift Horizon: Map mode, Focus mode, metric hierarchy, sensor strip + details, coach presentation, safe controls, mode switching | B; owner approval of Horizon prototypes | RideLayoutsSmoke replaced by Horizon smoke; recording-continuity tests; sensor-state tests; phone-only, GPS denied, stale sensor |
| **G** | Full integration, upgrade from build 153 store, cross-screen consistency, performance pass, internal TestFlight | C, D, E, F | Full pipeline green; recordings; TestFlight VALID; trackers |

Each checkpoint is one or more CI runs with the same release gates as today; nothing uploads unless every job is green.

---

## 7. Protected code and functionality (not changed in this upgrade)

| Area | Files / modules | Rule |
|---|---|---|
| Onboarding | `OnboardingView.swift`, `OnboardingDraft.swift`, `ProfileEditors.swift` (stages), `JourneyTests` | No change |
| Training engine | `Planning.swift`, `StrengthPlanner.swift`, `Hybrid.swift`, `AdaptationEngine.swift`, `AdaptiveStore.swift`, `SessionRebuild.swift` (engine parts), `Rc3Engine.swift` rules, `WeekTotals.swift`, `ProgressMetrics.swift` maths | Read-only consumers; no new calculations; no changes to rules |
| Workout execution and logging | `StrengthWorkout.swift`, `StrengthLog.swift`, `StrengthNextSet.swift`, `WorkoutState.swift`, `RideRecorder.swift`, `RideResultSheet` | The Training Hub and Horizon call them; they are not edited |
| Data and migration | `Models.swift` `StoreFile` (schema 4), `Provenance.swift`, `migrationLog`, `planVersions` | Only additive fields in Checkpoint E, with their own migration test |
| Apple Health | `HealthReads.swift`, `HealthImport.swift`, permissions | No change |
| Apple Watch | `WatchLink.swift`, `WatchWorkoutMirror.swift`, `Shared/AppInfo.swift` `WatchMessage`, `BikeComputerWatch/*` | No change |
| BikeComputer | `DeviceLink.swift`, `Shared/BCLink.swift`, firmware | No change; FTP fabrication defect (CR-04) stays open |
| Safety | `CoachSafety.swift`, health hold / caution / `HealthCheckView`, ride Start gate (`RideView.swift:196`), planner gates | Presentation may move; logic untouched; APP-012 NO-GO stands |
| Tests and gates | `ios/ci/build.sh` stages, `TEST_MATRIX.md`, all release-blocking suites | Tests may be **added** or updated for intentionally changed screens, never removed or relaxed |
| Deferred engine items | D-SE-1…6 | Not implemented here |

Files expected to change (Checkpoints B–D): `ContentView.swift` (dock wiring), `HomeView.swift`, `HomeModel.swift` (presentation only), `HomeFirstWeek.swift`, `ProgressView.swift`, `TrendCharts.swift`, `PlanView.swift` (day states only), `DesignSystem/*` (additive), new files under `Home/`, `Progress/`, `Hub/`, `Navigation/`. Checkpoint F: `RideView.swift`, `RideDashboard.swift`, `Ride/*` (presentation), new `Ride/Horizon*`. Checkpoint E: new `Body*` files, one additive `StoreFile` field.

---

## 8. Risk assessment — Ride recording and device integration

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Map rendering competes with 1 Hz recording and BLE on older iPhones | Medium | High (dropped samples, battery) | `RideRecorder` untouched and off the view hierarchy; map updates throttled; Focus mode has no map; performance pass on SE in Checkpoint F |
| Mode switch (Map ⇄ Focus) re-creates views and loses state | Medium | High | Both modes are views over the same `RideRecorder`/`SensorHub` publishers; test: switch 20× during a recorded ride, elapsed/distance continuous |
| Dark-mode forcing on the Ride tab vs light-first app | Low | Low | Keep Ride dark; dock adapts per page |
| Watch/board session conflict from new controls | Low | High | Controls call the existing `start/pause/resume/end` and `device.control(...)`; no new ownership paths; `RideLayoutsSmoke` equivalent kept |
| Stale sensor shown as live | Medium | High (wrong coaching) | Use `DeviceState.stale` / `receivingData` everywhere; a metric with stale state greys out and shows age; unit test on `DeviceStateRules` |
| Implying navigation that does not exist | High if careless | Medium (trust) | Map mode shows recorded route only; copy "No planned route" |
| GPS denied / unavailable | Medium | Medium | Focus mode is the fallback; map shows a permission explanation; existing `LocationService` states |
| Dock animation during a ride | Low | Medium | Dock hidden or static while `RideRecorder.state == .running`; Reduce Motion respected |
| Haptics drain or annoy | Low | Low | Selection-only haptics; none while riding |
| Breaking the health-hold Start gate | Low | High | Gate stays in `RideView` start action; test: hold active → Start disabled in both modes |

---

## 9. Plan for functional metric drill-down pages

Each page = one data source + ranges + source tags + an honest empty state + a back route that preserves state. Tap tests for every card (tap → expected page → change range → back → state preserved).

| Page | Opens from | Data (existing) | Ranges | Content |
|---|---|---|---|---|
| Training Overview | Home ring | `homeWeek()`, `TrendChartMath` | 7 d · 4 wk · 12 wk · 1 yr | Planned/done/remaining per sport, adherence with denominator and window (pre-start days excluded), weekly bars |
| Cycling Analytics | Home cycling card, Progress | ledger rides, `TrendChartMath`, `ftpSource`, `ftpEvidence()`, ride records | same | Riding time, distance, rides; avg power/NP/HR/cadence/speed **only from recorded rides**; time in HR zones; time in power zones only when FTP valid; verified FTP history; ride list → `RideDetailView` |
| Strength Analytics | Home strength card, Progress | strength logs, `liftSummaries()` | same | Sessions planned vs done, exercise picker → progression chart (top set, volume), e1RM labelled "estimate", PRs, muscle-group coverage from the planner's regions, weekly distribution |
| Recovery Details | Home (with data), Progress | `HealthReads` + history, post-session check-ins | same | Sleep hours and consistency, resting HR, HRV trends with source + freshness; subjective fatigue/soreness from check-ins; no readiness score |
| Consistency | Progress | ledger | same | Planned vs completed, missed, rescheduled, streaks (only when ≥ 2 weeks), monthly adherence |
| Goal Details | Home goal card | `profile.goals`, goal-related metrics | — | What the goal tracks, what is measured so far, what is still needed |
| Day Details | Home/Plan day | `plan` for that day, ledger status | — | Existing `WorkoutDetail` / day list; pre-start day shows "Before this plan started" |
| Recommendation Details | Coach insight | `homeCoach()` + `coachChangePreview` | — | Why → original → proposed → difference → schedule preview → Approve (commit) → Undo. If no preview path exists: advisory only |
| Milestones | Progress | `checkpoints()` | — | 4/8/12-week compact cards; tap → what was measured, what is missing |
| Reports | Progress | all of the above | 4 wk · 12 wk · 1 yr | Summary, cycling, strength, consistency, recovery, goals, notable changes, data gaps, next steps; "insufficient evidence" per section |
| History | Progress | `Timeline.build` | filters: type, period, source | Rows → `RideDetailView` / `StrengthSessionDetail`; no merging or double counting |

---

## 10. Design previews and owner approval

Delivery: one clickable HTML prototype (phone-sized, light and dark toggle, real-looking but clearly sample data) with ten screens:
New Home · Progress overview · Cycling detail · Strength detail · Recovery detail · Horizon Map · Horizon Focus · Liquid Dock (with the liquid motion) · Training Hub · Completed-workout state.

Each screen is annotated with: which existing data function feeds every number, which taps lead where, what the empty state says, and the SourceTag on each metric. The interaction specification (dock motion, glow, haptics, mode switching, approval flow) and the visual specification (tokens, type scale, card geometry, chart styles, semantic colours incl. a new coaching/lavender family) ship with it.

Approval gate: you approve the direction screen by screen (or request changes); Checkpoint B starts only after that. Any screen you reject is reworked before any production code for it is written.

---

## 11. Test plan (summary)

- Keep every release-blocking suite: unit (528), LaunchSmoke incl. upgrades from builds 24–40 **plus a new upgrade-from-build-153 store**, AdaptiveSmoke, journeys ×3, LayoutAudit on SE (L, AX3) / standard (L, XXXL) / Pro Max / owner size, DesignSystemAudit, Watch.
- New per checkpoint: dock (destinations, Reduce Motion, VoiceOver names, safe area), Home card taps, Training Hub states, Progress drill-downs with range changes, metric parity (Home = Progress = Hub), W12 day states, Horizon recording continuity and sensor states, performance pass (SE) for map and animations.
- Behaviour contract: new sections W13 (dock), W14 (Training Hub states), W15 (Horizon modes), W16 (drill-down contract) written before Checkpoint B.
- Real-device verification is reported only when done on a real iPhone, Watch or board.

---

## 12. Findings register (52 items) — status at Checkpoint A

All 52 are **Open — scheduled**. Checkpoint assignment: H-001…H-010 → C (H-007 also B for the shared day states; H-009 → C via existing preview path); P-001…P-012 → D (P-007, P-011 → E); R-001…R-012 → F; N-001…N-008 → B; T-001…T-010 → C. They are recorded in the APP tracker's new sheet "UX upgrade findings" at the next tracker sync, cross-referenced to WATCH-004 (session contract, Horizon) and BIKE-012/BIKE-013 (board states, FTP defect) where they span platforms. W12 keeps its own ID; APP-029 stays provisional.

### Status at Checkpoint C (5–6 Nov 2026, build 169)

| IDs | Status | Where | Evidence |
|---|---|---|---|
| H-001 Home matches the projected dashboard · H-002 light-first balance · H-010 unified premium system | Implemented · Simulator tested | `HomeDashboardView.swift`, `HomeView.swift`, `CyTheme` | journey-hybrid-07-home, LayoutAudit Home states ×4 sizes, DesignSystemAudit light/dark |
| H-003 weekly completion ring | Implemented (planned ÷ done, remaining, missed, skipped, W12 window note) | `HomeDashboardModel.swift` | `HomeDashboardTests` ring tests |
| H-004 cycling + strength summaries · H-005 compact charts | Implemented from recorded rides/logs; 8-week mini series (sparkline / bars) | `HomeDashboardModel.swift`, `HomeDashboardView.swift` | `HomeDashboardTests` tile tests |
| H-006 metric cards drill down | Partial — ring → Training overview, tiles → Progress tab, recovery → Recovery page, goal → Goal details; the analytics pages themselves are Checkpoint D | `HomeDashboardView.swift` | LayoutAudit key controls |
| H-007 calendar day states | Implemented (before plan · done · planned · missed · rest · both); rescheduled has no stored marker (deferred, no schema change) | `HomeDashboardModel.days`, `CyCalendarStrip` | `HomeDashboardTests` calendar tests, journeys W12 labels |
| H-008 Today + Coach cards compact | Implemented — compact Today reminder, coach card with the engine's finding | `HomeDashboardView.swift` | journeys, Home states |
| H-009 coach change explain/preview/confirm | Unchanged existing path (HomeProposalSheet → commitCoachChange → Undo) reached from the coach card | `HomeView.swift` | AdaptiveSmokeTests |
| T-001 Today card off Home · T-002 consistent centre destination · T-005 dedicated hub · T-006 multiple · T-007 completed accessible · T-009 Home prioritises analytics | Implemented · Simulator tested | `TrainingHubView` (HomeDashboardView.swift), `ContentView.swift` | LayoutAudit Home states (hub shots for planned/pending/multi/missed/rest/stop/done), LaunchSmoke hub → Start, journeys |
| T-003 pending animation · T-004 button reflects state | Implemented (Checkpoint B looks + hub) | `CyLiquidDock.swift` | DockCopyTests, W12AndDockTests |
| T-008 accessible, efficient motion | Implemented — AX sizes compact header/stacked buttons, Reduce Motion transition | `HomeDashboardView.swift`, `ContentView.swift` | LayoutAudit AX3 |
| T-010 state consistent across devices | Partial — the hub reads the same `homeToday` as the dock; Watch shows no hub state (unchanged) | — | — |
| N-001…N-008 | Implemented at Checkpoint B (build 161) | — | — |
| P-001…P-012, R-001…R-012 | Open — scheduled Checkpoints D/E/F | — | — |

