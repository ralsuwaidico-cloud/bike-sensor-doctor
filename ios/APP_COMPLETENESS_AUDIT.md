# Cyclift iPhone — completeness audit (owner directive 8 Nov 2026 19:04)

Scope: every approved iPhone checkpoint, backend → persistence → UI → navigation → journeys. Evidence levels used here
(nothing is marked beyond its evidence):

- **Validated** = unit tests + simulator UI tests green in CI (run 199 full matrix = TestFlight build 199; run 201 all
  simulator jobs green; run 204 pending for the current batch) — *simulator* evidence, not a physical iPhone.
- **Unit-tested** = data/model tests green (CI unit job and the Linux engine harness); the screen exists but no UI test
  drives it beyond the layout audit's screenshots and control checks.
- **Partial** = part of the approved scope exists; the rest is named.
- **Missing** = approved, not built.
- **Device** = can only be verified on a physical iPhone / Apple Watch (CI cannot).

| # | Checkpoint / feature | State | Evidence | Remaining |
|---|---|---|---|---|
| 1 | Onboarding v3 (Welcome + 5 stages, answers written once into the profile, resume) | **Validated** | JourneyTests ×3 personas (install → onboarding → plan → Approve → Home → Profile → Plan → relaunch), OnboardingScreens, DataIntegrityGapTests (answers change the plan) | Checkpoint H page‑1 appearance question is on its own branch (not in this build) |
| 2 | Athlete profile (name, DOB, weight, type, experience, goals, week, equipment, FTP, HR zones) | **Validated** | ProfileMenuTests, HomeNavigationTests (every menu row opens its page), OnboardingDraftTests | Height is read‑only by design |
| 3 | Home (six states, week strip, ring, cards) | **Validated** | HomeDashboardTests, HomeSummariesTests, HomeNavigationTests ×9, LayoutAudit | — |
| 4 | Training Hub (centre button, actions, undo) | **Validated** (run 204 pending for the close fix) | HubTapReliabilityTests 48/48 opens; close miss root‑caused (moving control) and fixed | Run 204 must show 48/48 opens + closes |
| 5 | Plan generation, week builder, approve | **Validated** | JourneyTests, Rc3EngineTests, HybridTests, RoutinesTests | — |
| 6 | Plan edit → preview → apply, versions, proposals | **Unit‑tested** (UI: Checkpoint C acceptance done on build 176) | SessionRebuild/AdaptationEngine tests, PlanSummariesTests, AdaptiveSmokeTests (check‑in → adjustments) | UI test that drives edit → preview → apply end to end |
| 7 | C2 Plan screen (six bands) | **Unit‑tested** | PlanSummariesTests ×4, LayoutAudit screenshots | UI interaction test (ring → overview, day → day page, proposal strip) |
| 8 | Strength: planned sessions, templates, supersets, live session (start/log/pause/finish), quick log, history | **Validated** (lifecycle) / **Unit‑tested** (UI) | QualityReleaseTests, StrengthAuditTests, SupersetPipelineTests, EmptyStrengthSessionTests, LaunchSmoke (centre → strength workout) | UI journey: start session → log sets → finish → history row |
| 9 | Check‑in after workouts → adaptive coach | **Validated** | AdaptiveSmokeTests, AdaptationEngineTests, RideChainTests | — |
| 10 | Ride: Cockpit / Map / Performance, record, pause/resume, end → review → save/discard, results, history | **Validated** | RideViewsSmokeTests ×3 (incl. pause → end → review → save → history), RideViewModelTests, RideResultsModelTests, RideRecorderDisconnectTests | Cockpit/Performance split per owner 19:04 lands in run 204 |
| 11 | GPS map, route history | **Validated** (simulated GPS) | RideViewsSmokeTests, results map polyline | **Device**: real GPS accuracy, background recording |
| 12 | GPX routes, turn guidance, off‑route | **Unit‑tested** | RouteGuidanceTests ×8 | **Device**: file import through the Files picker |
| 13 | Live coaching (rules), Why?, cue gating | **Validated** | CoachCoreTests, CoachRemediation tests, RideViewsSmokeTests (Why opens) | — |
| 14 | Apple Health export (one workout per ride, denial never blocks saving) | **Unit‑tested** | RideHealthWriter decision tests | **Device**: permission prompt and the written workout |
| 15 | Progress analytics (cycling, strength, records, goals) | **Unit‑tested** | ProgressAnalyticsTests ×5, ProgressMetricsTests, LayoutAudit | UI test for period / sport pickers |
| 16 | Recovery (log, freshness, usual range, one recommendation) | **Unit‑tested** | RecoveryAnalysisTests ×5, SleepAggregationTests | **Device**: Health reads; UI test of the page |
| 17 | FTP ownership (single writer, suggestion → accept, tested never replaced silently) | **Validated** | FTPOwnershipTests, RideChainTests | — |
| 18 | Profile › Settings (units, appearance, alerts, ride & coach) | **Validated** | HomeNavigationTests menu pages, ProfileMenuTests | Appearance families (Checkpoint H branch) |
| 19 | Devices & Connections (BikeComputer, Apple Watch, Health, direct BLE sensors, diagnostics) | **Unit‑tested** | SourcesTests, PairingTests, PipelineTests, BCLinkTests, LinkV12Tests, DiagTransferTests | **Device**: every real connection state |
| 20 | Your data: export, Delete all data | **Validated** (cancel path) / **Unit‑tested** (delete) | LaunchSmoke build‑40 export + cancel, DataIntegrityGapTests (delete leaves nothing) | **Device**: Health own‑records deletion |
| 21 | Data migration from builds 24–40 and 121→RC3→quality; relaunch identity | **Validated** | LaunchSmoke ×5 upgrades, S20DataIntegrityTests, DataIntegrityGapTests | — |
| 22 | Apple Watch app (HR mirror, ride commands, Health workout) | **Validated** (build + unit) | watch job in every run, WatchMessage tests | **Device**: pairing, live HR, handoff |
| 23 | Accessibility (Dynamic Type incl. AX sizes, labels, 44 pt) | **Validated** (simulator) | LayoutAudit on 4 sizes, DesignSystemAudit, HomeNavigation AX test | **Device**: VoiceOver acceptance (APP‑034 open) |
| 24 | Health screening / hold | **Validated** (behaviour frozen) | CoachSafety tests, LaunchSmoke | Redesign intentionally not done (APP‑012 NO‑GO) |

## Partial

- **Checkpoint H** (six appearances, fixed grading, onboarding question): built and unit‑tested on `impl/checkpoint-h-appearance`; not in this build by the owner's rule (separate branch, after the Ride milestone). Grading rules await the owner's one review.
- **R‑020 ride steps to the BikeComputer**: phone side complete and cap‑gated; firmware side is a separate approval.
- **Progress goals**: weekly time goals only (hoursPerWeek); no event/target‑date goals (never specified).

## Missing (approved scope with no implementation)

- Nothing from the approved checkpoints A–G is missing in code. The master‑order **Part 8 details (six onboarding screens, Profile structure)** could not be recovered after the context loss — needs the text re‑shared; the current onboarding is the approved five‑stage v3.

## Known defects / open items

- APP‑034 VoiceOver acceptance of the Profile menu — open until a real‑iPhone pass.
- Training Hub close miss (run 200) — fixed, evidence expected in run 204.
- Type‑checker time‑limit build failures (runs 202/203) — fixed (HomeDashboardView label split); no product impact.

## Requires a physical iPhone / Apple Watch (CI cannot prove)

Bluetooth sensor pairing and live data; BikeComputer link; Apple Watch pairing, HR, workout handoff and Health workout write; Apple Health reads (sleep / HRV / resting HR / weight) and the export permission prompt; Health own‑records deletion; real GPS accuracy and background recording; GPX import via Files; VoiceOver; Hub taps with a finger; battery and thermal behaviour over a long ride.
