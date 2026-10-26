# Cyclift — sensors and integrations

Status: Cyclift 1.0 (workstream A3, 26 Oct 2026). Code: `ios/BikeComputer/Sources/` (hub, direct BLE sensors, decoders,
planned providers), `ConnectionsView.swift` (dashboard), `Connections.swift` (status colours), `HealthImport.swift`.
Contract: `docs/briefs/CYCLIFT_CONTRACTS.md` → "Live metric contract".

The app works with **no sensors at all** (phone GPS gives speed, distance and the route; the coach uses heart rate,
speed, cadence or perceived exertion when power is missing). The BikeComputer is one optional device among others.

---

## 1. Audit (before this work, base `20032f0`)

| Source | What existed | Hard-coding / gaps found |
|---|---|---|
| BikeComputer link (`DeviceLink.swift`) | Complete: BLE central to the ESP32 board ("BikeComputer Link" service), stages, Repair, restore id `bikecomputer.central`, live power / cadence / HR / ride state at 1 Hz, GPS + watch HR + time sent to the board. Fed the hub through `SensorHub.refresh`. | Fine as a device. The hub showed the board's HR with the protocol label (`BCLink.Source.label`: "Strap", "XDS", …) and also re-offered heart rate the phone itself had sent to the board (watch → phone → board → phone echo). |
| Board-relayed sensors (power meter, HR strap, CSC) | Shown as rows read from the board's LIVE message (`meterLink`, `hrSource`). | Row title **"Power meter (XDS)"**, detail texts "The XDS pairs on the BikeComputer", "cadence from the XDS", "pedal once so the XDS wakes"; the whole sensor section was titled "Bluetooth sensors (via the BikeComputer)" — i.e. a rider without the board had no way to use a sensor. Speed/cadence detail said "not supported by firmware 0.6.0" while the row said "pair on the board" (contradiction). |
| Direct BLE sensors on the phone | **Missing.** No 0x180D / 0x1818 / 0x1816 support on the phone at all. | — |
| Apple Watch HR (`WatchLink.swift`) | Complete: WatchConnectivity, HR with sample time, dropped after 6 s, forwarded to the board. | Uses the app name "Athletics" in user strings (A2 renames). |
| Phone GPS (`LocationService.swift`) | Complete: 1 Hz fixes, accuracy, to the board; hub offers speed. | — |
| Apple Health (`Connections.swift` `HealthAccess`, `HealthImport.swift`) | Real: authorization, workout import (cycling + strength, dedupe), "connected" only from HealthKit's own status. | — |
| Garmin / WHOOP | Two gray rows "not connected · arrives with the account service". | Implied they would arrive soon; no statement of what they can/cannot do (no live data). Oura absent. |
| Source model | `SourceDescriptor`, `MetricReading`, `SourcePriority` (working first version). | No per-source status (state, last update, quality, metrics); dashboard did not use the hub. |

Brand strings found with `grep -rn "XDS\|Branta" ios/` (strap: no brand found, only generic "strap"):

| File:line | String | Owner | Action |
|---|---|---|---|
| ConnectionsView.swift:33, 171, 174, 430, 438 | "Power meter (XDS)", "from the XDS", … | A3 | **fixed** → "Power meter via BikeComputer", "power meter" |
| RideView.swift:150 | `unit: "WATTS · XDS"` | A4 | report → "POWER · W" + source from `reading.sourceLabel` |
| RideView.swift:288–289 | `source: "XDS via board · unverified"`, `"XDS via board"` | A4 | report → hub `sourceLabel` / quality |
| RideView.swift:329 | `SensorRow(name: "Power meter (XDS)")` | A4 | report |
| RideView.swift:418–421 | ride summary tiles `source: "XDS"` | A4 | report → "Power meter" |
| ProfileView.swift:238 | `LabeledContent("XDS power meter", …)` | shared / owner | report → "Power meter" |
| OnboardingView.swift:285 | `"Power meter (XDS, pairs on the board)"` | A2 (onboarding) | report → "Power meter (pairs on the BikeComputer or this phone)" |
| Models.swift:958 | `src.append("XDS")` (board ride sources) | shared | report → "Power meter" |
| RideRecorder.swift:149 | `sources: ["BikeComputer", "XDS"]` | A4 / shared | report → "Power meter" |
| Models.swift:366 | HR preference title "Strap / band via BikeComputer first" | shared | report → "Strap or band first" (a strap can now pair on the phone) |
| Shared/BCLink.swift:35 | `Source.xds.label = "XDS"` | protocol | kept (wire protocol enum); the hub no longer prints it |
| project.yml | `NSBluetoothAlwaysUsageDescription` mentions only the BikeComputer | shared (A2 edits the app name in the same line) | report → add "and Bluetooth heart-rate, power, speed and cadence sensors" |

Firmware: no brand hard-coding in the app↔board protocol that matters to the app (the `xds` source tag is a wire value),
so firmware stays 0.7.0.

---

## 2. Architecture (1.0)

```
 adapters ──offer/withdraw──▶ SensorHub ──reading(kind)──▶ ride layouts, coach, watch mirror
   BikeComputer link (DeviceLink, polled 1 Hz in hub.refresh)        one value per metric,
   Direct BLE sensors (BLESensors, notifications + 1 Hz tick)        priority + freshness
   Apple Watch (WatchLink, polled 1 Hz)
   Phone GPS (LocationService, polled 1 Hz)
                              SensorHub.sources ──▶ Connections dashboard (status per source)
 imported: Apple Health (real) · Garmin / WHOOP / Oura (planned, never connected)
```

- **Metric contract** (unchanged API): `MetricKind`, `MetricReading`, `SourceDescriptor`, `ConnectionMethod`,
  `DataTiming`, `DataQuality`, `SourcePriority`, `SensorHub.reading/value/offer/withdraw/refresh`. Added:
  `SourceState`, `SourceStatus`, `SourceStateRules`, `hub.sources`, `hub.status(id)`, `hub.readings(from:)`,
  `hub.pruneStale()`, `hub.attach(store:)`, `hub.ble`, `hub.health`.
- **Priority** (first wins, ties → freshest): HR — strap on the BikeComputer, strap paired on the phone, Apple Watch
  (watch first when the rider chose "Apple Watch first"); speed — wheel sensor, board, phone GPS; power and cadence —
  power meter via the board, then a direct sensor. Freshness: HR 6 s, speed 5 s, power/cadence 3 s. Never averaged.
- **Echo rule**: heart rate the board reports with source `appleWatch` / `phoneStrap` came from this phone and is not
  offered again as a board source.
- **Source status** (`SourceStatus`): descriptor (id, name, method, live/imported, relayed by), state (connected /
  connecting / disconnected / notAuthorized / notConfigured / planned), available metrics, what it provides, last
  successful update, data quality, `configured` (the rider set it up → only then may "missing" be red).
- **Colours** (unchanged rules, `ConnectionRules`): green connected · red ! only configured-and-missing · amber
  connecting/limited · gray optional/not set up/planned.

### Direct BLE sensors (`Sources/BLESensors.swift`, decoders in `Sources/BLEDecoders.swift`)
- Own `CBCentralManager`, restore identifier `cyclift.sensors.central`; `DeviceLink` is untouched and the board's
  peripheral (remembered + stale identifiers) is never listed as a sensor. The central is created lazily: only when the
  rider opens "Add a sensor" or has paired sensors (then at launch, so iOS can restore background connections).
- Scans for standard services Heart Rate `0x180D`, Cycling Power `0x1818`, Cycling Speed and Cadence `0x1816`. Pairs
  **only on the rider's tap**; remembers paired sensors by peripheral identifier in `AppSettings.bleSensors`
  (additive, `decodeIfPresent` default `[]`); keeps a pending connect so they reconnect automatically.
- **Read / notify only.** It subscribes to `2A37`, `2A63`, `2A5B`; it never writes a characteristic value (no control
  point, calibration or settings). Subscribing writes only the standard notification descriptor, done by iOS.
- Decoding: `2A37` 8/16-bit value (flag bit 0), contact-not-detected dropped, energy/RR ignored; `2A63` SINT16 power,
  optional fields skipped by flag, crank data (bit 5) → cadence (1/1024 s); `2A5B` wheel → speed with the profile's
  wheel circumference (`wheelMm`, default 2096) and crank → cadence (1/1024 s). 16-bit time and counter wrap handled;
  cadence/speed become 0 after 3 s without a new revolution while connected; a gap > 4 s is a restart, not a slow turn.
- Offers readings with method `.bleDirect` and the sensor's own name (or a generic one: "Heart-rate sensor", "Power
  meter", "Speed / cadence sensor"); power is `.unverified` until verified; withdrawn on disconnect.
- Heart rate from a strap paired on the phone is forwarded to a connected BikeComputer (source `phoneStrap`) only when
  the board has no strap of its own and the watch is not sending — so a board-recorded ride keeps HR.

---

## 3. Providers (verified 26 Oct 2026 against official docs)

None of the cloud integrations is implemented in 1.0: each needs a developer app, credentials and (for some) business
approval that the project does not have. They appear in Connections as **"Planned — not available yet"**, gray, with
one line on what they will provide. They are never shown as connected or available.

| Provider | Official API | Data timing | Access | Live HR today |
|---|---|---|---|---|
| **Garmin** | Garmin Connect Developer Program — Health API (daily summaries, HR, sleep, stress, …) and Activity API | After the user's device syncs with Garmin Connect ("at which point it is accessible via the API") — no live stream | Business tier: application + approval (free for approved business developers; some data needs a commercial licence). The overview page now also lists a Personal tier (own data, pull only). | Many Garmin watches can **broadcast heart rate** (watch setting "Broadcast Heart Rate"); a broadcasting watch is a standard BLE HR source (0x180D on Bluetooth-capable models — model support varies). |
| **WHOOP** | WHOOP Developer Platform, REST API v2 with OAuth 2.0 (scopes incl. `read:recovery`, `read:cycles`, `read:sleep`, `read:workout`, `read:profile`, `read:body_measurement`, `offline` for refresh tokens); webhooks for workout/sleep/recovery updates | After the fact (records + summaries; no continuous HR samples via the API) | WHOOP membership required to develop; apps submitted for approval; new apps start in a limited tier | **Heart Rate Broadcast** in the WHOOP app exposes standard BLE heart rate; works as a direct BLE HR source while enabled. |
| **Oura** | Oura API v2, OAuth 2.0 (scopes `email personal daily heartrate workout tag session spo2`), personal access tokens deprecated; webhooks | After the ring syncs through the Oura app (webhook notifications follow a sync); `heartrate` is a historical time series | OAuth client registration | **None** — Oura does not stream live HR to other apps. |

Sources:
- Garmin Health API: https://developer.garmin.com/gc-developer-program/health-api/
- Garmin Connect Developer Program overview (tiers): https://developer.garmin.com/gc-developer-program/overview
- Garmin Activity API: https://developer.garmin.com/gc-developer-program/activity-api/
- Garmin "Broadcasting Heart Rate Data" (watch manual): https://www8.garmin.com/manuals/webhelp/fenix66s6xpro/EN-GB/GUID-D8D363C2-0690-48D4-95E2-A3557E7D53C2.html
- WHOOP developer overview (membership, approval): https://developer.whoop.com/docs/developing/overview
- WHOOP OAuth (auth/token URLs, `offline` scope): https://developer.whoop.com/docs/developing/oauth
- WHOOP getting started: https://developer.whoop.com/docs/developing/getting-started
- WHOOP Heart Rate Broadcast (support): https://support.whoop.com/hc/en-us/articles/360023430193-Heart-Rate-Broadcast
- Oura authentication (OAuth2, scopes, token lifetime): https://cloud.ouraring.com/docs/authentication
- Oura OpenAPI (endpoints, webhooks, PAT deprecation): https://api.ouraring.com/v2/static/json/openapi-1.37.json
- Earlier device-family research (Polar, Wahoo, COROS, Pixel Watch, …): `docs/research/WEARABLES_LIVE_HR.md`
- Bluetooth SIG specifications: Heart Rate Service 1.0, Cycling Power Service 1.1, Cycling Speed and Cadence Service 1.0
  (https://www.bluetooth.com/specifications/specs/)

Notes: the WHOOP scope list was confirmed from the developer docs' OAuth page plus a secondary integration guide
(https://openwearables.io/docs/providers/whoop-api-integration.md); the WHOOP API reference page itself could not be
fetched from this environment. Nothing here has been tested with real Garmin / WHOOP / Oura hardware.

### What it would take to build them (post-1.0)
1. Register a developer app with each provider (Garmin business application; WHOOP app + approval; Oura OAuth client).
2. A small server component (the existing Supabase backend) to hold client secrets, do the OAuth code exchange and
   receive webhooks — secrets must never ship in the app.
3. Import adapters with `timing = .imported`, mapping to rides / recovery entries with dedupe (like Apple Health).

---

## 4. Limitations (1.0)
- Direct BLE: only devices that advertise one of the three standard services appear in the search list (a few
  broadcasting watches advertise HR only while broadcasting; some only after bonding). No ANT+ (iPhone has no ANT+).
- A sensor connected to another app/phone may refuse a second connection.
- Power from a direct meter is shown as **unverified** (no reference check exists in the app yet).
- No calibration / zero-offset: the app never writes to sensors by design.
- Speed from a Cycling Power meter's wheel data is used only when the meter has no CSC service.
- Everything Bluetooth is proven only by unit tests (decoders, rules) and the simulator build; real-sensor behaviour
  needs a device test.
