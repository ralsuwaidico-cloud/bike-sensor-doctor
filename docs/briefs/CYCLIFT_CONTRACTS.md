# Cyclift 1.0 — parallel workstreams, contracts and merge rules (26 Oct 2026)

Briefs: `CYCLIFT_BRIEF_2026-10-26.txt` (Rashed 10:35), `ATHLETICS_RELEASE_BRIEF_2026-10-26.md` (accounts/store — still valid,
name now **Cyclift**), `HYBRID_ROUTINES_BRIEF_2026-10-25.txt`, `PAIRING_SYNC_BRIEF_2026-10-25.txt`.
Integration owner: the main session. Release branch: `ios/dev`. Nothing merges into `ios/dev` unless its own CI run is green.

## Names
- App: **Cyclift** (home screen, launch, onboarding, login, About, legal, store). Store listing name subject to App Store
  availability + trademark check (owner decides; do not assume legally available).
- Device: **BikeComputer** stays the name of the ESP32 accessory ("BikeComputer Link" BLE service name unchanged).
- IDs unchanged: bundle `com.ralsuwaidico.bikecomputer` (+ .watchkitapp), Android package, URL scheme, BLE UUIDs,
  Application Support path, Supabase table names, PRODUCT_NAME.

## Branches (each pushes to its own branch; ios.yml runs on `ios/**`, never with `[testflight]`)
| Workstream | Branch | Owns (may edit) | Must not edit |
|---|---|---|---|
| A2 Brand + accounts | `ios/cyclift-brand` | strings that name the app, `Assets.xcassets` icons/launch, `ios/tools/make_icon.py`, `Cloud/**`, `OnboardingView.swift` (entry/login stage only), `ios/legal/**`, `BikeComputer/Resources/*.md`, `ios/store/**`, `docs/site/**`, `backend/**`, `ios/REBRAND.md`, `RELEASE_CHECKLIST.md`, android `strings.xml`/icons | ride/sensor/plan files |
| A3 Sources | `ios/cyclift-sources` | `Sources/**` (SensorHub internals, adapters, BLE direct sensors), `Connections.swift`, `ConnectionsView.swift`, `HealthImport.swift`, `DeviceLink.swift` (only to feed the hub), `docs/INTEGRATIONS.md` | ride layouts, RideDashboard/RideView |
| A4 Ride layouts + coach | `ios/cyclift-ride` | `RideView.swift`, `RideDashboard.swift`, new `Ride/**` layout files, `Shared/CoachCore.swift` (additive only), ride settings | Sources internals (consume the contract only) |
| A5 Strength / schedule | audit only (0.8.0 build 40 shipped it) → fixes go on `ios/cyclift-ride`? NO: on `ios/cyclift-strength` | `Strength*.swift`, `Hybrid.swift`, `Planning.swift`, `PlanView.swift`, `HomeView.swift` | others |
| Shared, any change needs the owner | — | `Models.swift`, `BikeComputerApp.swift`, `ContentView.swift`, `project.yml`, `ci/**`, tests' seed fixtures | |
If a workstream needs a change in a shared file, it keeps it minimal and additive and lists it in its report.

## Live metric contract (implemented as a working first version in `Sources/SensorHub.swift`)
- Everything that shows or uses live power / heart rate / cadence / speed reads `SensorHub.reading(kind) -> MetricReading?`
  (`@EnvironmentObject var hub: SensorHub`). `nil` → show `kind.missingText` ("No power source", …).
- Label = the metric ("POWER · W"); the source is shown separately from `reading.sourceLabel`
  ("Power meter via BikeComputer", "Apple Watch", a direct sensor's name). No brand in labels, no brand as default.
- `reading.quality`: `.unverified` power must be visibly marked; the coach treats it as provisional.
- Priority (first wins, ties by freshness), `SourcePriority.rank`: HR — BikeComputer strap / direct strap / Watch (Watch
  first when the rider chose it); speed — wheel sensor / board / phone GPS; power & cadence — board / direct sensor.
- Adapters `offer` readings and `withdraw` on disconnect; the hub never averages or invents.
- Source management model (A3): `SourceDescriptor` (id, name, method, live/imported, relayedBy) + per-source status:
  connection/authorization state, last update, available metrics, data quality. Providers without a real-time API
  (Garmin, WHOOP, Oura cloud APIs) are `timing = .imported` only and are listed as **planned** unless implemented and
  authorized; standard BLE broadcast (e.g. a watch or band broadcasting HR as 0x180D) is a direct BLE HR source.

## Ride layout contract (A4)
- `enum RideLayout: String, Codable { case coach, gauges, classic, rings, analytics }` stored in `AppSettings.rideLayout`
  (decodeIfPresent, default `.coach`). Switching never touches `RideRecorder`, the hub or BLE.
- Every layout embeds the same `CoachPanel` (cue + Why?), reads metrics only via the hub, fits one screen without scrolling
  (iPhone SE … Pro Max), handles any subset of sensors.

## Merge order (owner)
1. A3 sources (contract internals) → 2. A4 ride → 3. A5 strength fixes → 4. A2 brand/accounts (strings last, fewest
   conflicts) → final `[testflight]` RC on `ios/dev` + launch smoke tests on all seeds (24/30/33/36/40).
Firmware: stays 0.7.0 unless the audit finds brand hard-coding that matters to the app; any change → 0.7.1 with its own kit.
