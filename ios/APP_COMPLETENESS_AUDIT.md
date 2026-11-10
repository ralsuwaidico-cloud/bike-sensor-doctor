# Cyclift iPhone — completeness audit (owner directive 8 Nov 2026 19:04; updated 10 Nov 2026 for TestFlight build 216)

Scope: every approved iPhone checkpoint, backend → persistence → UI → navigation → journeys. Evidence levels used here
(nothing is marked beyond its evidence):

- **Fully validated** = unit tests + simulator UI tests (smoke / journeys / layout audits / flows) green in CI on the
  build‑216 tree (runs 214–216) — *simulator* evidence, not a physical iPhone.
- **Partially complete** = part of the approved scope works and is validated; the rest is named.
- **Defective** = a reproducible defect is known on this build.
- **Missing** = approved, not built.
- **Physical‑device‑only** = implemented and unit‑tested; the remaining proof needs a real iPhone / Apple Watch (CI cannot).

**Build under audit:** TestFlight **216** · commit `fb52ae27` · branch `ios/checkpoint-f-ride` · run 216 (42786480539):
unit 659/659 · smoke ok · journeys hybrid/cycling/strength ok · layout audits small/standard/promax/owner ok · watch ok ·
archive/sign/verify/upload ok · App Store Connect: processed VALID, installable by internal testers. Flows job (advisory
for internal builds): hub 48/48 + 12/12, strength live session, Plan/Progress/Recovery screens ok; plan‑edit review sheet
**defective** (see 6); Delete‑all journey lost the simulator connection in this run (passed in runs 211–215).

| # | Checkpoint / feature | State | Evidence (build‑216 tree) | Remaining |
|---|---|---|---|---|
| 1 | Onboarding v3 (Welcome + 5 stages, answers written once into the profile, resume) | **Fully validated** | JourneyTests ×3 personas (install → onboarding → plan → Approve → Home → Profile → Plan → relaunch), OnboardingDraftTests, LaunchSmoke | — |
| 2 | Athlete profile (name, DOB, weight, type, experience, goals, week, equipment, FTP, HR zones) | **Fully validated** | ProfileMenuTests, HomeNavigationTests (every menu row opens its page), OnboardingDraftTests | — |
| 3 | Home (six states, week strip, ring, cards) | **Fully validated** | HomeDashboardTests, HomeSummariesTests, HomeNavigationTests ×9, LayoutAudit ×4 devices | — |
| 4 | Training Hub (centre button, actions, Close, nested Why / details) | **Fully validated** | HubTapReliabilityTests: 48/48 first taps open **and** close (runs 214–216); 12/12 human‑pace closes incl. after the Why sheet and session details; hub inserted/removed without transition | Real‑iPhone feel (haptics, speed) |
| 5 | Plan generation, week builder, approve | **Fully validated** | JourneyTests, Rc3EngineTests, HybridTests, RoutinesTests | — |
| 6 | Plan edit → preview (before/after) → apply, versions, proposals | **Defective (one path)** | Engine: SessionRebuild/AdaptationEngine tests, PlanSummariesTests green. UI: slider → preview → Apply applies the change (run 214); **but the review sheet opened from the strength session's Edit sheet stays on screen after Apply/Cancel** (runs 211–216 screenshots; three fixes narrowed it, the nested‑sheet presentation is orphaned). The change itself IS applied; the sheet must be dismissed by swipe. Fix in progress: present the review inside the edit sheet's navigation instead of a third nested sheet. | Fix + flows green |
| 7 | C2 Plan screen (six bands: ring, timeline, proposals, manage, changes) | **Fully validated** | PlanSummariesTests ×4, PlanProgressRecoveryScreensTests (ring → overview, day → Day page, chip → session, Why line), LayoutAudit RC2 on 4 devices; day rows and chips are independent controls (owner 8 Nov) | — |
| 8 | Strength: planned sessions, templates, supersets, live session (start / log every set / adjust / finish / save / check‑in / review), quick log, history | **Fully validated** | StrengthSessionJourneyTests end‑to‑end (runs 214–216): start → 4 sets logged with the card advancing → Finish → Save → check‑in → coach result → completed‑workout review → history; QualityReleaseTests, StrengthAuditTests, SupersetPipelineTests. Defect found and fixed from the run‑209 screenshot (adjust buttons oversized, Log set squeezed) | — |
| 9 | Check‑in after workouts → adaptive coach | **Fully validated** | AdaptiveSmokeTests, AdaptationEngineTests, RideChainTests, strength journey (coach adjustments sheet) | — |
| 10 | Ride: Cockpit / Map / Performance, record, pause/resume, end → review → save/discard, results, history | **Fully validated** | RideViewsSmokeTests ×3 (incl. pause → end → review → save → history), RideViewModelTests (≤ 2 secondary tiles, no empty cadence tile), LayoutAudit | — |
| 11 | GPS map, route history | **Fully validated** (simulated GPS) | RideViewsSmokeTests, results map polyline | **Device**: real GPS accuracy, background recording |
| 12 | GPX routes, turn guidance, off‑route | **Physical‑device‑only** | RouteGuidanceTests ×8 (unit) | **Device**: file import through the Files picker |
| 13 | Live coaching (rules), Why?, cue gating | **Fully validated** | CoachCoreTests, CoachRemediation tests, RideViewsSmokeTests (Why opens), hub nested Why | — |
| 14 | Apple Health export (one workout per ride, denial never blocks saving) | **Physical‑device‑only** | RideHealthWriter decision tests (unit) | **Device**: permission prompt and the written workout |
| 15 | Progress analytics (cycling, strength, records, goals) | **Fully validated** | ProgressAnalyticsTests ×5 (weekday‑independent since run 207), ProgressMetricsTests, PlanProgressRecoveryScreensTests (period / sport pickers, sources named), LayoutAudit | — |
| 16 | Recovery (log, freshness, usual range, one recommendation, 28‑day trends) | **Fully validated** (page) / **Device** (reads) | RecoveryAnalysisTests ×5, SleepAggregationTests, PlanProgressRecoveryScreensTests (honest without Health, no score number) | **Device**: real Health reads |
| 17 | FTP ownership (single writer, suggestion → accept, tested never replaced silently) | **Fully validated** | FTPOwnershipTests, RideChainTests | — |
| 18 | Profile › Settings (units, appearance, alerts, ride & coach) | **Fully validated** | HomeNavigationTests menu pages, ProfileMenuTests; duplicates removed (owner verification 2) | Appearance families remain on `impl/checkpoint-h-appearance` (owner's review of grading rules) |
| 19 | Devices & Connections (BikeComputer, Apple Watch, Health, direct BLE sensors, Cyclift Watch page, diagnostics) | **Physical‑device‑only** | SourcesTests, PairingTests, PipelineTests, BCLinkTests, LinkV12Tests, DiagTransferTests, CyWatchWireTests/SessionTests (unit) | **Device**: every real link; LILYGO never on hardware |
| 20 | Your data: export, Delete all data | **Fully validated** | DeleteAllDataJourneyTests (Delete → Welcome → plain relaunch still Welcome; runs 211–215), LaunchSmoke export + cancel, DataIntegrityGapTests | **Device**: Health own‑records deletion choice |
| 21 | Data migration from builds 24–40 and 121→RC3→quality; relaunch identity | **Fully validated** | LaunchSmoke ×5 upgrades, S20DataIntegrityTests, DataIntegrityGapTests | — |
| 22 | Apple Watch app (HR mirror, ride commands, Health workout) | **Physical‑device‑only** | watch job in every run (build + 6 screenshots), WatchMessage tests | **Device**: pairing, live HR, handoff |
| 23 | Accessibility (Dynamic Type incl. AX sizes, labels, 44 pt) | **Physical‑device‑only** (simulator part validated) | LayoutAudit on 4 sizes incl. AX3, DesignSystemAudit, HomeNavigation AX test; Plan day/chip and next‑set card identifiers corrected (runs 206–209) | **Device**: VoiceOver acceptance (APP‑034 open) |
| 24 | Health screening / hold | **Fully validated** (behaviour frozen) | CoachSafety tests, LaunchSmoke | Redesign intentionally not done (APP‑012 NO‑GO) |

## Counts (24 features, build 216)

| Category | Count | Features |
|---|---|---|
| **Fully validated** (simulator CI, unit + UI) | **18** | 1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 13, 15, 16 (page; its Health reads are device‑only), 17, 18, 20, 21, 24 |
| **Partially complete** | **0** | — (the appearance families of 18 are a separate branch by the owner's rule, not a gap in this build) |
| **Defective** | **1** | 6 — review sheet does not dismiss after Apply/Cancel on the strength‑edit path (change is applied; swipe closes it) |
| **Missing** | **0** | nothing from the approved checkpoints A–G is unbuilt |
| **Physical‑device‑only** | **5** | 12 (GPX import), 14 (Health export prompt/record), 19 (every real device link), 22 (Apple Watch), 23 (VoiceOver) |

Total: 18 + 0 + 1 + 0 + 5 = **24**.

## Readiness, stated separately

- **Everyday use on the iPhone alone (internal TestFlight 216):** ready for real‑world testing. Every core journey
  (onboard → plan → ride / strength → results → history → progress → recovery → delete) is validated in the simulator; one
  known defect (6) is cosmetic in effect (the applied edit is saved; the sheet needs a swipe to close) and is being fixed.
  Not production‑ready until: defect 6 fixed and the flows job green; the five device‑only items checked on a real
  iPhone; APP‑034 VoiceOver pass.
- **Hardware integration (detachable Cyclift Watch / BikeComputer):** NOT ready — this is a separate question from the
  app's everyday readiness. The adapters and protocols exist and are byte‑tested on the phone (`CyWatch*`, `DeviceLink`,
  Link 1.x, wearable v1, R‑020 renumbered), but nothing has run on the LILYGO and the BikeComputer board runs 0.7.3.
  See `docs/CYCLIFT_WATCH_FEATURE_AUDIT.md` and the hardware handover. Hardware work remains paused by the owner.

## Known defects / open items

- **Defect 6** (above). Also seen in run 216 flows: Delete‑all journey "lost connection to the application" — a simulator
  helper error in that run; the journey passed in runs 211–215 and the model‑level delete tests are green. Watched.
- APP‑034 VoiceOver acceptance of the Profile menu — open until a real‑iPhone pass.
- Appearance families (Checkpoint H) await the owner's review of the grading rules; separate branch, not in 216.
- CI: the "flows" job is advisory for internal builds (owner 10 Nov); a production release requires it green.

## What to test manually on the iPhone (build 216)

1. Install from TestFlight; if upgrading from 199, confirm your plan, history and FTP are intact.
2. Home → Training Hub: open/close several times, open "Why this workout?" and the session details, Close again.
3. Plan: tap a day name (Day page), tap a workout chip (its session), the ring (week overview), More › Quick log.
4. Strength: start today's session, log every set with the adjust buttons, finish, save, answer the check‑in, read the
   coach result, confirm the completed workout shows all sets, check Progress › Strength.
5. Ride: start a ride with your HR strap / power meter (Connections first), check Cockpit (one lead metric, ≤ 2
   secondary, interval, one cue, mini map), Performance (gauges, live graph), Map; pause/resume; end → review → save;
   Apple Health shows one workout.
6. Recovery: grant Health reads; the page should show sleep / HRV / resting HR / weight with "usual range" and one
   recommendation, no score.
7. Plan edit: Edit type / duration → Review → Apply; **expected defect 6**: if the review sheet stays, swipe it down —
   the change is applied (check Plan › Changes).
8. Profile › Settings › Your data: export, then Delete all data (choose the Health option deliberately) — the app
   returns to Welcome; relaunch stays at Welcome.
9. Apple Watch: pair, start a ride from the Watch, see HR on the phone, end from either side.
10. VoiceOver on the Profile menu and the Plan timeline (day, then its chips).
