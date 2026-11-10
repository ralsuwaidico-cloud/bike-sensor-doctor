# Cyclift Watch — 102 selected features vs the Cyclift iPhone app (cross‑platform audit)

**Date:** 10 Nov 2026 · **iPhone build audited:** TestFlight 216 (`fb52ae27`, `ios/checkpoint-f-ride`) · **Source of
truth:** the repository as it stands — iPhone `impl/checkpoint-f-ride`, watch firmware `watch/w0-foundation` @ ca2cadb6,
BikeComputer `fw/phonefirst` @ c0a10fb0 — not design documents and not earlier claims. **Scope:** audit and planning only;
nothing was implemented and no hardware work was started. The hardware handover (`docs/hardware-handover`) is unchanged.

## How to read the matrix

| Code | Meaning (project instructions §6) |
|---|---|
| **IT** | Implemented in the iPhone app and tested (unit / CI simulator evidence named) |
| **IU** | Implemented but unverified at the level that matters (needs a real device, or no test) |
| **P** | Partial — some of the feature exists, the rest does not |
| **M** | Missing from the iPhone app |
| **B** | Blocked — the hardware or data source does not exist on any Cyclift component, or is unverified on it |

"Needs": **iP** iPhone processing · **WUI** Watch UI · **Sens** external BLE sensors · **AH** Apple Health · **AW** Apple
Watch as the Health source · **HW+** hardware Cyclift does not have. "Where": where the rider should reach it — iPhone /
Watch / both. "Model": does the iPhone already have the data model, calculation, persistence and sync — **Y / partial / N**.

Hardware facts used (from the handover; nothing newly verified): the LILYGO T‑Watch 2021 has a classic ESP32, 240×240
round display, CST816S touch, **BMA423 accelerometer**, PCF8563 RTC, QMC5883 compass, vibration motor, two keys; **no
GPS, barometer, optical HR, SpO₂, temperature/ECG sensor, speaker or microphone**. The Polar Verity Sense is an optical
HR sensor that broadcasts **standard BLE heart rate (0x180D)**; nothing else from it (HRV/PPI, SpO₂, temperature,
accelerometer) has been verified in this project and is treated as unavailable until it is. The watch has **never run
the firmware** (host/linker figures only). Evidence vocabulary: *unit* = BikeComputerTests (CI unit job, many also on the
Linux engine harness); *UI* = BikeComputerUITests (smoke / journeys / layout / flows jobs); runs 214–216 are the build‑216 tree.

---

## A. Feature comparison matrix (102 rows)

### 1 · Watch faces & everyday use (8)

| ID | Feature | iPhone today | Status | Evidence / location | Needs | Where | Model | Dependencies · risks | Priority · phase |
|---|---|---|---|---|---|---|---|---|---|
| WF‑01 | Digital and analog watch faces | n/a | Watch‑only; Orbit / Chrono / Pulse faces host‑rendered (1 464 scenes) | `watch/firmware/src/domain/screens.hpp`, `watch/docs/WATCH_FACES.md` | WUI | Watch | — | RTC + `TimeSync`; never run on device | P2 (M2) |
| WF‑02 | Customizable face complications | nothing to configure them | **M** (phone) / design only (watch) | — | iP settings + WUI | both (configure on phone) | N | settings schema in `AppSettings` + a v1.1 payload | P3 |
| WF‑03 | Daily activity rings and goals | training ring (sessions done/planned); no step/move ring | **P** | `HomeDashboardModel.Ring`, `homeWeekOverview` (HomeSummariesTests, HomeDashboardTests) | iP + WUI; steps need AH/AW | both | partial | no step/calorie model (DA‑01) | P3 |
| WF‑04 | Widgets and glance carousel | no iOS widgets | **M** | no WidgetKit target in `ios/project.yml` | iP | iPhone widgets / Watch glances | N | watch glance = `PlanToday`/`Cached` payloads already defined | P3 |
| WF‑05 | Notifications from iPhone | only the app's own background‑recording notice | **P** | `RideRecorder.swift` (UNUserNotificationCenter) | iP + WUI | Watch | N | forwarding needs ANCS on the watch — not in firmware; privacy decision | P4 |
| WF‑06 | Calls and message controls | nothing | **B** | — | HW+ (no mic/speaker) | Watch | N | at most "decline" via ANCS | not planned |
| WF‑07 | Alarms, stopwatch and timers | strength rest timer only | **P** | `StrengthNextSet.swift`; watch `ui::timers` + `CountdownTimer` (244 host checks) | WUI | Watch | — | alarms need the RTC wake path (unverified) | P2 (M2) |
| WF‑08 | Music playback controls | nothing | **B** | — | HW+ (AVRCP not in firmware) | Watch | N | second BLE profile on a radio shared with the phone link | not planned |

### 2 · Heart & health monitoring (12)

| ID | Feature | iPhone today | Status | Evidence / location | Needs | Where | Model | Dependencies · risks | Priority · phase |
|---|---|---|---|---|---|---|---|---|---|
| HH‑01 | Live heart rate | BLE HR strap, Apple Watch mirror, BikeComputer link; source + age shown | **IT** | `Sources/BLESensors.swift` (0x180D/2A37), `SensorHub`, `WatchLink`; SourcesTests, PipelineTests, RideViewsSmokeTests | Sens + iP | both | Y | Polar = standard HR broadcast: compatible by standard, **not yet tested with this app** | P1 (exists) |
| HH‑02 | Resting heart rate | from Health, per‑day log, usual range | **IT** (unit) / device for the read | `HealthReads.swift`, `RecoveryModel.swift` (RecoveryAnalysisTests ×5) | AH/AW + iP | both (`Cached`) | Y | no Cyclift device measures it | P1 (exists) |
| HH‑03 | HRV | as HH‑02 (SDNN) | **IT** (unit) | same | AH/AW + iP | both | Y | Polar PPI/HRV **not verified** | P1 (exists) |
| HH‑04 | High / low HR alerts | zone cues only; no absolute limit alert | **P** | `CoachPanel.swift`, CoachCoreTests | iP + Sens + WUI (haptic) | both | partial | `AppSettings` limits + safety cue + `Coach.safety` flag exists | P2 |
| HH‑05 | Blood oxygen (SpO₂) | nothing | **B** | — | HW+ | — | N | Health read of AW values possible later | P4 |
| HH‑06 | Respiratory rate | nothing | **B** | — | HW+ | — | N | same | P4 |
| HH‑07 | Skin temperature trends | nothing | **B** | — | HW+ | — | N | same | P4 |
| HH‑08 | Blood pressure insights | nothing | **B** | — | HW+ (no cuff) | — | N | medical‑claim risk | not planned |
| HH‑09 | VO₂ max / cardio fitness | not computed (`vo2` is a workout *type*) | **M** | `Models.swift` WorkoutKind.vo2 | AH/AW read or iP estimate | both | N | estimate = new calculation; AW VO₂max = Health read | P3 |
| HH‑10 | Cardiovascular age | nothing | **M** | — | iP | — | N | depends on HH‑09; non‑medical wording | P4 |
| HH‑11 | Health trends and unusual vitals | flags sleep/HRV lower or RHR higher than the rider's usual range | **P** | `RecoveryModel.RecoveryMetric` (interquartile baseline), RecoveryView; RecoveryAnalysisTests, PlanProgressRecoveryScreensTests | AH + iP | both (`Cached` word + insight) | Y (4 kinds) | only sleep/RHR/HRV/weight read | P1 → P3 |
| HH‑12 | Stress monitoring | nothing (no invented score by rule) | **B** | — | HW+ (all‑day HR/HRV) | — | N | Polar HRV unverified | not planned |

### 3 · Sleep & recovery (13)

| ID | Feature | iPhone today | Status | Evidence / location | Needs | Where | Model | Dependencies · risks | Priority · phase |
|---|---|---|---|---|---|---|---|---|---|
| SR‑01 | Sleep duration and schedule | per‑night duration from Health (source named) | **IT** (unit) | `SleepAggregation`, `HealthReads.history`, SleepAggregationTests | AH/AW + iP | both (`Cached.sleepMin`) | Y (duration) | bed/wake times not stored | P1 / P3 |
| SR‑02 | Sleep stages | not read | **M** | `SleepAggregation` ignores stage values | AH/AW + iP | both | N | available from Apple Watch | P3 |
| SR‑03 | Sleep score | none — **owner rule: no invented score** | **M (decision)** | — | iP | — | N | needs a defined, explained formula | decision |
| SR‑04 | Sleep consistency | not computed | **M** | — | iP | both | N | needs SR‑01 schedule | P3 |
| SR‑05 | Sleep debt | not computed | **M** | — | iP | both | partial | needs SR‑06 | P3 |
| SR‑06 | Sleep need recommendation | usual‑range baseline, no need target | **P** | `RecoveryMetric.baseline` | iP | both | partial | explainable rule only | P3 |
| SR‑07 | Recovery / readiness score | **deliberately a recommendation word** (hold / as planned / watch / easier) | **IT (as designed)** | `RecoveryAdvice`, RecoveryAnalysisTests, PlanProgressRecoveryScreensTests ("no score number") | AH + iP | both (`Cached.recoveryWord`; `recoveryPct` absent by design) | Y | a number is an owner decision | P1 (exists) |
| SR‑08 | Body Battery / energy estimate | nothing | **B** | — | HW+ (all‑day HR) | — | N | — | not planned |
| SR‑09 | Recovery time recommendation | advice words, no hours number | **P** | as SR‑07 | iP | both | partial | needs load history (TP‑07) | P3 |
| SR‑10 | Sleep coaching | nothing beyond "below your usual" | **M** | — | iP | iPhone | N | rules‑based text only | P4 |
| SR‑11 | Recovery trends | 28‑day chart per metric | **IT** | `RecoveryView` CyBarChart, PlanProgressRecoveryScreensTests (runs 214–216) | AH + iP | iPhone (watch: last value) | Y | — | P1 (exists) |
| SR‑12 | Resilience / long‑term stress | nothing | **B** | — | HW+ | — | N | — | not planned |
| SR‑13 | Biological age / pace of aging | nothing | **M (not recommended)** | — | iP | — | N | no validated basis | not planned |

### 4 · Training plans & AI coaching (15)

| ID | Feature | iPhone today | Status | Evidence / location | Needs | Where | Model | Dependencies · risks | Priority · phase |
|---|---|---|---|---|---|---|---|---|---|
| TP‑01 | Today's workout plan | Home today card, Training Hub, Plan | **IT** | JourneyTests, HomeNavigationTests, HubTapReliabilityTests (48/48 + 12/12, runs 214–216) | iP + WUI | both (`PlanToday`, byte‑tested in CyWatchWireTests) | Y | — | P1 → M3 on watch |
| TP‑02 | Adaptive training schedule | check‑in → adaptations, proposals with preview/apply, versions | **IT** (engine) / **defect in one UI path** | AdaptationEngineTests, AdaptiveSmokeTests; PlanEditPreviewApplyTests: change applied, review sheet does not dismiss on the strength‑edit path (APP audit item 6) | iP | iPhone | Y | fix in progress | P1 |
| TP‑03 | AI training coach | rule‑based coach (owner rule) | **IT (rule‑based)** | `Coach*`, `HybridCoach`, `Rc3Engine`; CoachCoreTests, HybridTests, Rc3EngineTests | iP | both | Y | say "rule‑based" | P1 |
| TP‑04 | Live workout coaching cues | ride: one cue + Why; strength: next‑set card | **IT** | `CoachPanel`, `RideStepStrip`, RideViewsSmokeTests; `StrengthNextSet` (StrengthSessionJourneyTests end‑to‑end, runs 214–216) | iP + WUI | both (`Coach` payload) | Y | watch side host‑tested only | P1 → M3 |
| TP‑05 | Personalized HR zones | method (max HR / LTHR), ranges live | **IT** | `RiderProfile.hrZoneMethod`, `RideLive.hrZoneRanges`; RideViewModelTests | iP | both (`Live.hrBand`) | Y | — | P1 |
| TP‑06 | Power zones and FTP | single FTP owner, suggestion → accept, provenance | **IT** | FTPOwnershipTests, RideChainTests, `ios/OWNERSHIP.md` | iP | both | Y | board FTP rules differ (handover A8) | P1 |
| TP‑07 | Training load and strain | TSS per ride + sparkline; acute/chronic fields in adaptation; no strain index | **P** | `PlanView` Timeline.tss, `AdaptiveModels` | iP | both (`Cached.loadPct`) | partial | strength load undefined (SG‑10); one engine | P2 |
| TP‑08 | Training readiness | recommendation words + health‑check gate (no score) | **P (by design)** | `RecoveryAdvice`, `CoachReadiness` | iP | both | Y | owner rule | P1 |
| TP‑09 | Training status / fitness trend | best‑20 trend, records, analytics | **IT** | ProgressAnalyticsTests ×5, PlanProgressRecoveryScreensTests | iP | iPhone | Y | — | P1 |
| TP‑10 | Over/under‑training warnings | weekly review flags vs budget; adaptation findings | **P** | `HybridCoach.weeklyReview` (HybridTests) | iP | both | partial | no ACWR‑style rule | P2 |
| TP‑11 | Suggested daily workouts | plan generator + Other session + templates | **IT** | `Planning.swift`, `StrengthPlanner`, Rc3EngineTests, RoutinesTests | iP | both | Y | — | P1 |
| TP‑12 | Training goal tracking | goals card + Goal page | **IT** | HomeNavigationTests | iP | iPhone | Y | — | P1 |
| TP‑13 | Adherence / missed sessions | missed row, week counts | **IT** | HomeSummariesTests, LayoutAudit | iP | both (counts not in v1 payload) | Y | add to v1.1 | P1 |
| TP‑14 | AI explanation: Why this workout? | Why sheet (rule‑based text) | **IT** | `HomeWhySheet`; RideViewsSmokeTests, hub nested Why (runs 214–216) | iP | both (`Coach.reason`) | Y | — | P1 |
| TP‑15 | Weekly coaching review | HybridCoach weekly review | **IT** (unit) | `Hybrid.swift`, HybridTests | iP | iPhone | Y | — | P1 |

### 5 · Cycling & bike computer (16)

| ID | Feature | iPhone today | Status | Evidence / location | Needs | Where | Model | Dependencies · risks | Priority · phase |
|---|---|---|---|---|---|---|---|---|---|
| CY‑01 | Live power (watts) | BLE Cycling Power / board link / source + age | **IT** | `BLESensors` (0x1818/2A63), `RideLive.power`; SourcesTests, PipelineTests | Sens + iP | both | Y | — | P1 |
| CY‑02 | 3 s / 10 s / average power | 3 s, 30 s, lap, NP in Performance; **no 10 s** | **P** | `RideViewModels.swift` | iP | both | Y | one‑line window | P2 |
| CY‑03 | Cadence (RPM) | CSC + power‑meter cadence | **IT** | `BLESensors` (0x1816/2A5B), RideViewModelTests | Sens + iP | both | Y | — | P1 |
| CY‑04 | Speed, distance, duration | GPS or wheel sensor, recorder | **IT** | `RideRecorder`, `LocationService`; RideRegressionTests, RideViewsSmokeTests | iP + Sens | both | Y | real GPS = device | P1 |
| CY‑05 | HR and HR zones live | yes | **IT** | HH‑01, TP‑05 | Sens + iP | both | Y | — | P1 |
| CY‑06 | Power‑zone target guidance | step targets, band grading | **IT** | `RideStepStrip`, RideViewModelTests | iP | both | Y | — | P1 |
| CY‑07 | Normalized Power / IF / TSS | NP live + results; TSS per ride; IF only inside AdaptationEngine | **P** | `normalizedPower` (DataIntegrityGapTests), `Timeline.tss` | iP | iPhone (watch: NP) | partial | expose IF; one definition | P2 |
| CY‑08 | Power and HR graphs | Performance live graph (120 s) + results charts | **IT** | `LiveGraphView`, `RidePerformanceView`, `RideResultsView` (layout audits) | iP | iPhone | Y | watch graph = design v2 (not in firmware) | P1 |
| CY‑09 | Lap and interval controls | lap/pause/resume/end on phone, Apple Watch, LILYGO command path | **IT** | `RideRecorder.lap`, `RideControlPlan`; RideControlPlanTests, CyWatchSessionTests | iP + WUI | both | Y | LILYGO never on hardware | P1 |
| CY‑10 | Auto pause | none | **M** | no `autoPause` in `RideRecorder` | iP | both | N | needs false‑pause tests | P2 |
| CY‑11 | Route and turn‑by‑turn navigation | GPX route, next turn, off‑route, distance to go | **IT** (unit) / IU (import) | `RouteModel.RouteGuidance`, RouteGuidanceTests ×8 | iP + WUI | both (`Gps` has no turn data) | Y on phone | v1.1 turn payload; Files import = device | P2 |
| CY‑12 | Climb grade and elevation | ascent in results; no live grade | **P** | `RideResultsModel.ascentM` | iP | both | partial | GPS altitude noisy; label estimate | P3 |
| CY‑13 | Real‑time stamina estimate | nothing | **M** | — | iP | both | N | needs CP/W′ (not in profile) | P4 |
| CY‑14 | Power guide / pacing strategy | step targets; no route pacing | **P** | `RideStepsSync` (R‑020 0xC0–0xC4) | iP | both | partial | needs CY‑12 | P3 |
| CY‑15 | Incident detection and live tracking | nothing | **M / decision** | — | iP + network + contacts | iPhone | N | needs a server; Cyclift 1.0 has no accounts | decision |
| CY‑16 | Indoor smart‑trainer controls | nothing (no FTMS) | **M** | — | Sens (FTMS 0x1826) + iP | both | N | new profile + ERG UI; trainer to test | P3 |

### 6 · Strength & gym (10)

| ID | Feature | iPhone today | Status | Evidence / location | Needs | Where | Model | Dependencies · risks | Priority · phase |
|---|---|---|---|---|---|---|---|---|---|
| SG‑01 | Today's strength workout | yes | **IT** | StrengthSessionJourneyTests, LaunchSmoke build‑36 | iP + WUI | both (`PlanToday.exercises`) | Y | — | P1 |
| SG‑02 | Exercise list and instructions | list, previous log, Why per exercise; no instruction text/media | **P** | `StrengthWorkout.exerciseCard`, `InsightCard` | iP | both | partial | content work | P3 |
| SG‑03 | Log sets, reps and weights | next‑set card with adjust buttons, per‑set rows | **IT** | StrengthSessionJourneyTests (4 sets logged, card advances, 4/4; runs 214–216); StrengthAuditTests; layout defect fixed from the run‑209 screenshot | iP + WUI | both (`Event.setLogged`) | Y | watch→phone mapping in CyWatchCoordinator (CyWatchSessionTests) | P1 |
| SG‑04 | Edit or undo a logged set | per‑set rows editable; no undo for a logged set | **P** | `LiveSetRow`; `UndoToastBar` (plan only) | iP + WUI | both | partial | watch needs an "unlog" event (v1 has none) | P2 |
| SG‑05 | Rest timer | phone yes; watch scene host‑tested | **IT** | `StrengthNextSet.restView`; watch `CountdownTimer` | iP / WUI | both | Y | — | P1 |
| SG‑06 | Next / previous exercise | next‑set picker; no explicit previous | **P** | `NextSet.pick` | iP + WUI | both | partial | two‑press keys cover it on the watch | P2 |
| SG‑07 | Skip or substitute exercise | substitution via templates/equipment; no in‑session skip | **P** | `Store.proposeEquipmentEdit`, `StrengthPlanner` | iP | iPhone | partial | new session op | P2 |
| SG‑08 | Automatic rep counting | **experimental on the watch (BMA423), synthetic data only**; phone none | **B (unverified)** | `rep_detector.hpp`, `REP_COUNTING.md` (CW‑022) | WUI/HW + iP store | Watch → phone (`Event.repCount`) | partial | no dataset/accuracy table; stays experimental | P3 (W4) |
| SG‑09 | Automatic set detection | nothing | **B (unverified)** | — | as SG‑08 | Watch | N | depends on SG‑08 | P4 |
| SG‑10 | Strength training load / strain | volume (sets × reps × kg) in Progress; no load index | **P** | `ProgressAnalytics`, `WeekTotals` | iP | both (`Cached.loadPct`) | partial | one load definition with TP‑07 | P2 |

### 7 · Running, walking & multisport (6)

| ID | Feature | iPhone today | Status | Evidence / location | Needs | Where | Model | Dependencies · risks | Priority · phase |
|---|---|---|---|---|---|---|---|---|---|
| RW‑01 | Walking and running sessions | `Sport.running` in the profile only; no run recorder/planner/results | **M** | `Models.swift` | iP (GPS) + WUI | both | N | new activity type through the whole chain | P3 |
| RW‑02 | Live pace, distance, duration | ride recorder has speed/distance; no pace | **P (reuse)** | `RideRecorder` | iP + WUI | both | partial | pace = speed formatting | P3 |
| RW‑03 | Running cadence and stride length | nothing | **B/M** | — | HW (accelerometer unverified) or foot pod | both | N | — | P4 |
| RW‑04 | Running intervals and splits | laps exist for rides | **P (reuse)** | `RideRecorder.lap` | iP | both | partial | — | P3 |
| RW‑05 | Race time predictions | nothing | **M** | — | iP | iPhone | N | needs RW‑01 history | P4 |
| RW‑06 | Automatic activity detection | nothing | **B/M** | — | HW (accelerometer) | Watch | N | unverified | P4 |

### 8 · Daily activity & lifestyle (5)

| ID | Feature | iPhone today | Status | Evidence / location | Needs | Where | Model | Dependencies · risks | Priority · phase |
|---|---|---|---|---|---|---|---|---|---|
| DA‑01 | Steps and distance | nothing (no step model) | **M** | — | AH/AW read or watch accelerometer (unverified) | both | N | Health read straightforward | P3 |
| DA‑02 | Active calories | Health kcal only as ride energy provenance | **P** | `Provenance.swift` | AH + iP | both | partial | keep the kJ‑vs‑kcal rule | P3 |
| DA‑03 | Hydration tracking | nothing | **M** | — | iP (+AH write) | both | N | simple log | P3 |
| DA‑04 | Weight and body composition trends | weight from Health with usual range; no composition | **P** | `RecoveryModel` (.weight) | AH + iP | iPhone | Y (weight) | more Health kinds | P2 |
| DA‑05 | Habit and journal logging | check‑in notes/RPE after workouts; no free journal | **P** | `CheckInFlow` (AdaptiveSmokeTests) | iP | iPhone | partial | — | P3 |

### 9 · Navigation & safety (2)

| ID | Feature | iPhone today | Status | Evidence / location | Needs | Where | Model | Dependencies · risks | Priority · phase |
|---|---|---|---|---|---|---|---|---|---|
| NS‑01 | GPS location and route tracking | track recorded, map, results polyline | **IT** (simulated GPS) | `LocationService`, `RideMapView`, RideViewsSmokeTests | iP | both (watch mirrors `Gps`; no GPS of its own) | Y | background accuracy = device | P1 |
| NS‑02 | Back to start | nothing | **M** | — | iP | both | N (track exists) | compass on watch unverified | P2 |

### 10 · History, insights & integration (5)

| ID | Feature | iPhone today | Status | Evidence / location | Needs | Where | Model | Dependencies · risks | Priority · phase |
|---|---|---|---|---|---|---|---|---|---|
| HI‑01 | Workout history and summaries | rides and strength, results pages, completed‑workout review | **IT** | `HomeDetailPages`, `RideResultsView`; RideViewsSmokeTests, StrengthSessionJourneyTests (review + history) | iP | iPhone (watch: last session not in v1) | Y | — | P1 |
| HI‑02 | Weekly and monthly trends | Progress period picker, trends, records | **IT** | `ProgressAnalyticsView`, PlanProgressRecoveryScreensTests | iP | iPhone | Y | — | P1 |
| HI‑03 | Apple Health integration | export one workout per ride; reads sleep/RHR/HRV/weight; own‑record deletion | **IU** (device) | `RideHealthExport`, `HealthReads`, DataIntegrityGapTests | AH | iPhone | Y | permission prompt and records never checked on a device | P1 (device) |
| HI‑04 | External Bluetooth sensors | HR / power / speed‑cadence, pairing, diagnostics | **IT** (unit) / device for real sensors | `BLESensors`, PairingTests, SourcesTests, DiagTransferTests | Sens + iP | both | Y | Polar untested with the app | P1 (device) |
| HI‑05 | Data quality and sensor freshness | source + age on every value, stale never shown | **IT** | `RideMetric`, `SensorHub`; PipelineTests, RideViewModelTests | iP | both (`Live.*Age`) | Y | — | P1 |

### 11 · Watch controls & system (10)

| ID | Feature | iPhone today | Status | Evidence / location | Needs | Where | Model | Dependencies · risks | Priority · phase |
|---|---|---|---|---|---|---|---|---|---|
| WC‑01 | Start / pause / resume / end | phone, Apple Watch, LILYGO command path → `RideRecorder` | **IT** (phone) · watch host‑only | `RideControlPlan`, `CyWatchCoordinator`; CyWatchSessionTests | iP + WUI | both | Y | one‑recorder rule (`OWNERSHIP.md`) | P1 → M3 |
| WC‑02 | Two‑way iPhone synchronization | wearable protocol v1 both sides, byte‑tested; **never on hardware** | **IU** | `CyWatchWire/Link/Coordinator`, CyWatchWireTests (firmware vectors), CyWatchSessionTests | iP + WUI | both | Y | hardware run = M3 | P1 code / M3 |
| WC‑03 | Disconnected and pending command states | acked/pending per (deviceId, seq); resend on reconnect (host) | **IU** | `CyWatchSession`, watch `EventQueue` | iP + WUI | both | Y | watch "pending" UI = design v2 | P1 → M3 |
| WC‑04 | Physical button shortcuts | watch two‑press keys (host‑tested) | watch‑only | `buttons.hpp`, `BUTTONS.md` | WUI | Watch | — | debounce unverified | M1 |
| WC‑05 | Customizable workout screens | ride tiles order/choice on phone; no watch screen config | **P** | `StoreFile.tiles`, RideSettingsSheet | iP + WUI | both (configure on phone) | partial | v1.1 settings payload | P3 |
| WC‑06 | Wrist / bike / gym view modes | watch design v2 (Cockpit/Performance/Navigation; Exercise/Rep/Rest); phone sends `PlanToday.kind` | design + host | `ride_screens.hpp`, `strength.hpp`, `activity.hpp` | WUI | Watch | Y | unverified on device | M3/M4 |
| WC‑07 | Battery and connection status | phone shows watch `Status` on the Cyclift Watch page | **IU** | `CyWatchView`, `Status` payload | iP + WUI | both | Y | — | P1 → M3 |
| WC‑08 | Screen brightness and timeout | watch quick settings (host) | watch‑only | `app_model` Persist | WUI | Watch | — | backlight PWM unverified | M1 |
| WC‑09 | Haptic feedback and alerts | watch motor + DND suppression (host) | watch‑only | `app_model` | WUI | Watch | — | motor unverified | M1 |
| WC‑10 | Firmware and diagnostic screens | diag image compiles; phone has BikeComputer diagnostics transfer, nothing for the LILYGO | **P** | `Diagnostics/`, DiagTransferTests; watch diag image | iP + WUI | both | partial (board only) | watch diag payload not in v1 | M1 / P3 |

---

## B. Summary counts (iPhone status, 102 features — each row once by its Status column)

| Status | Count | IDs |
|---|---|---|
| **Implemented and tested (IT)** | **34** | HH‑01/02/03 · SR‑01/07/11 · TP‑01/02*/03/04/05/06/09/11/12/13/14/15 · CY‑01/03/04/05/06/08/09/11 · SG‑01/03/05 · NS‑01 · HI‑01/02/05 · WC‑01 (*TP‑02 engine tested; one UI path defective — APP audit item 6) |
| **Implemented but unverified (IU)** — needs a real iPhone / device | **5** | HI‑03, HI‑04 (real sensors incl. Polar), WC‑02, WC‑03, WC‑07 (LILYGO link never on hardware) |
| **Partial (P)** | **26** | WF‑03/05/07 · HH‑04/11 · SR‑06/09 · TP‑07/08/10 · CY‑02/07/12/14 · SG‑02/04/06/07/10 · RW‑02/04 · DA‑02/04/05 · WC‑05/10 |
| **Missing (M)** | **19** | WF‑02/04 · HH‑09/10 · SR‑02/03/04/05/10/13 · CY‑10/13/15/16 · RW‑01/05 · DA‑01/03 · NS‑02 |
| **Hardware‑blocked / unverified sensor (B)** | **13** | WF‑06/08 · HH‑05/06/07/08/12 · SR‑08/12 · SG‑08/09 · RW‑03/06 |
| **Watch‑only (no iPhone counterpart expected)** | **5** | WF‑01 · WC‑04/06/08/09 |
| | **102** | |

Of the 19 missing, four are **owner decisions rather than engineering gaps**: SR‑03 sleep score, SR‑13 biological age,
CY‑15 incident detection/live tracking (needs a server; Cyclift 1.0 has no accounts) — and HH‑08 blood‑pressure insights
sits in the blocked row for the same reason. The "no invented score" rule also makes a numeric readiness score (SR‑07) a
decision, not a gap.

**Readiness statement.** *Everyday use on the iPhone alone* (TestFlight 216): 34 features in the app with test evidence,
5 more exist but need a real iPhone to prove. *Hardware integration:* the protocols and adapters exist on both sides and are
byte‑compatible, but **nothing has run on the LILYGO**; every Watch row is host/linker evidence only.

## C. iPhone application gap list (what must be added to support the selected Watch features)

Ordered by dependency; each small and testable on the engine harness before any watch work:

1. **Wearable protocol v1.1 additions (TLV, additive, cap‑gated):** week adherence counts (TP‑13), next turn + distance to
   go (CY‑11), "unlog set" event (SG‑04), watch screen/complication settings (WC‑05, WF‑02), watch diagnostics payload
   (WC‑10), last‑session summary (HI‑01). New `type` values; unknown types ignored; both encoders kept
   (`ios/INTEGRATION_ARCHITECTURE.md`).
2. **10 s power window** (CY‑02) beside 3 s / 30 s.
3. **Intensity Factor in results** (CY‑07) from existing NP and FTP; one definition shared with `AdaptationEngine.effort`.
4. **Auto pause** (CY‑10): `RideRecorder` rule on speed/GPS with a setting; stop‑and‑go tests.
5. **Absolute HR limit alert** (HH‑04): `AppSettings` limits → `Coach` safety cue → `Coach.safety` → watch haptic.
6. **Back to start** (NS‑02): bearing + distance from the recorded track.
7. **One training‑load definition** (TP‑07 + SG‑10): ride TSS exists; define strength load (explained), weekly
   acute/chronic view feeding `Cached.loadPct`; over/under rule (TP‑10) on top.
8. **More Health kinds** (SR‑02 stages, DA‑01 steps, DA‑02 active energy, HH‑09 VO₂max if written by Apple Watch, DA‑04
   composition): extend `HealthSample.Kind` + `RecoveryLog`; no scores invented.
9. **Running/walking activity** (RW‑01/02/04): reuse recorder/results with pace; new `WorkoutKind`; Health type; filters.
10. **Hydration and journal** (DA‑03/05).
11. **Smart trainer (FTMS)** (CY‑16): new `BLESensorKind` + ERG UI; needs a trainer to test.
12. **Not to build without an owner decision:** scores (SR‑03, SR‑07 as a number, HH‑12), biological age (SR‑13),
    blood‑pressure insights (HH‑08), incident detection + live tracking (CY‑15).

## D. Watch‑specific feature list

**Interface requirements (design v2 covers; firmware host‑tested, device‑unverified):** faces Orbit/Chrono/Pulse (WF‑01);
timers/stopwatch (WF‑07); Cockpit / Performance / Navigation ride views (CY‑01..09, CY‑11 display); Exercise / Rep counter /
Rest timer gym views (SG‑01/03/05/06); lifecycle and pending/disconnected states (WC‑03); two‑press key map (WC‑04); quick
settings brightness/DND (WC‑08/09); battery/link status (WC‑07); glance of today's plan and recovery word (TP‑01, SR‑07).

**Interface work not yet designed/implemented:** complication configuration (WF‑02, phone side), notification list (WF‑05),
turn‑by‑turn card data (CY‑11 payload), unlog/undo gesture (SG‑04), back‑to‑start arrow (NS‑02; compass unverified),
diagnostics screen content (WC‑10).

**Hardware / firmware requirements (all unverified on the device — handover §08 B1–B8):** board revision + T‑U2T dongle
(blocks everything); display/backlight/touch/keys/motor bring‑up (M1); RTC + TimeSync (M2); BLE peripheral link stability
and range (M3); accelerometer rep‑detection dataset (SG‑08/09, W4); compass behaviour (NS‑02); battery life. **Not present
at all:** GPS, barometer, optical HR, SpO₂, temperature, microphone/speaker (WF‑06/08, HH‑05/06/07, barometric CY‑12).
Wrist HR comes only from the **Polar Verity Sense over standard BLE HR**, received by the watch as a BLE central — the
dual‑role radio is **untested** (CW‑018).

## E. Dependency map

```
External sensors ──BLE 0x180D/0x1818/0x1816──▶ iPhone BLESensors ─┐
(Polar Verity Sense = HR only, unverified with the app)             │
Apple Watch ──WatchConnectivity (HR mirror, commands)──▶ WatchLink ─┤
BikeComputer ──Link 1.x (LIVE/CTRL/SYNC; 1.3 on fw/phonefirst)──▶ DeviceLink ─┤
                                                                    ▼
                                         SensorHub → RideRecorder → Store (plan, FTP, history, recovery log)
                                                                    │            ▲
Apple Health ◀── one workout per ride (RideHealthExport) ───────────┘            │ reads: sleep, RHR, HRV, weight (HealthReads)
Apple Health ──▶ HealthReads ────────────────────────────────────────────────────┘ (future: stages, steps, energy, VO₂max)
                                                                    │
Cyclift Watch (LILYGO) ◀── wearable v1: PlanToday, Cached, Live, Gps, Coach, TimeSync ── iPhone CyWatchCoordinator
Cyclift Watch (LILYGO) ── Event (start/pause/resume/end/lap/set logged/rep count), Status, Ack ──▶ iPhone (RideCommand / active strength session)
Cyclift Watch as BLE central ◀── Polar HR (planned W2, untested dual role)
```
Ownership as written in `ios/OWNERSHIP.md`: the phone owns plan, FTP, GPS, workout identity, history and Health writes;
devices display and send events; one recorder per workout; calculations (zones, NP, TSS, load, recovery baselines) run
**once, on the phone**, and devices receive results (bands, targets, words).

## F. Phased plan (does not destabilise the iPhone app)

| Phase | Content | Gate |
|---|---|---|
| **0 — now** | TestFlight 216 in the owner's hands; fix APP audit item 6 (review sheet); device checklist; this document is the shared reference | owner's real‑world test of 216; flows job green |
| **1 — iPhone engine additions, no watch code** | C.2–C.7 as engine code with harness tests; wearable v1.1 payload *definitions* with firmware‑style vectors; Health kinds (C.8) | each item: unit tests on harness + CI; no UI redesign; TestFlight when stable |
| **2 — watch bring‑up (hardware, owner approvals per step)** | M0 identify + factory backup → M1 diagnostics → M2 faces/clock → M3 BLE + cockpit (v1 as it exists) → M4 strength | each M step: owner approval, real‑device evidence, rollback kept |
| **3 — ecosystem features** | v1.1 payloads live on both sides; running/walking; FTMS; hydration/journal | contract tests with firmware vectors; iPhone usable without the watch |
| **4 — decisions / research** | scores, rep/set detection accuracy (W4 dataset), incident detection, VO₂max estimate | owner product decisions; validated data only |

Rules in every phase: iPhone first and usable alone; additive protocol changes only; no invented values or scores; nothing
marked hardware‑tested without device evidence; the hardware handover stays the reference for the device side.
