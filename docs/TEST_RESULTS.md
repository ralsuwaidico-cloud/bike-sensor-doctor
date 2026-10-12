# Test results — honest status as of 2026-10-11 (one-button version)

You asked me not to claim a feature works until it has been tested. Here is exactly where things stand.

## Build status (updated after CI run #2, 2026-10-11 13:44 Dubai)

- **Compiled successfully** on GitHub Actions: `./gradlew testDebugUnitTest assembleDebug` — green on the first
  attempt after the SDK-setup step was fixed. All 8 parser unit tests passed.
- **APK produced and published**: https://github.com/ralsuwaidico-cloud/bike-sensor-doctor/releases/tag/build-2
  (`BikeSensorDoctor-build2.apk`, 16.5 MB, debug-signed, APK Signature Scheme v2 block verified).
- **Still untested on hardware**: nothing has run on the Nokia 5.3 or against the sensor yet. Every "No" in the
  table below stays "No" until the first real session.

## What was NOT possible in my build environment

- The environment that wrote this project has **no Android SDK and no access to Google's/Maven Central package
  servers** (network policy). Therefore:
  - The project could not be compiled *here*; it was compiled on GitHub Actions instead (see above).
  - **Nothing has run against your sensor.** All behaviour descriptions below are design intent, not observed results.
- The Gradle wrapper (`gradlew`, `gradle/wrapper/*`) **was** generated with Gradle 8.9 and is valid.

## What was checked

| Item | Method | Result |
|---|---|---|
| Kotlin sources | Manual static review of all 11 files for syntax, Android API signatures (API 31 vs 33 GATT callbacks), permission annotations | Reviewed; 3 defects found and fixed before packaging |
| Android 12 permissions | Manifest declares `BLUETOOTH_SCAN` (neverForLocation) + `BLUETOOTH_CONNECT`, legacy ones capped at API 30; runtime request via `RequestMultiplePermissions` | Reviewed |
| Byte parsers (CPS 0x2A63, CSC 0x2A5B, community XDS layout, cadence wrap-around) | 8 JUnit tests in `app/src/test` — pure JVM, run by CI (`testDebugUnitTest`) | Written; **not yet executed** |
| CI workflow | Reviewed against actions/setup-java v4 and android-actions/setup-android v3 usage | Reviewed |

## Feature status matrix

| # | Requirement | Implemented in | Tested on hardware |
|---|---|---|---|
| 1 | BLE scan: names, RSSI, adv data, services | `ble/BleScanner.kt`, Scan tab | No |
| 2 | Identification: RSSI history + near/far procedure, XDS fingerprint flag | `ScannedDevice.looksLikeXds`, Scan tab | No |
| 3 | Connect / reconnect (backoff) / discovery / read / notify | `ble/GattManager.kt` | No |
| 4 | Hex logger, timestamps, counts, CSV/JSON export (share sheet) | `log/EventLog.kt`, Log tab | No |
| 5 | Live dashboard: state, battery, counts, RSSI (3 s poll), verified metrics | Device tab | No |
| 6 | Automatic still-vs-pedaling test with on-screen instructions | `diag/AutoDiagnostic.kt` | No |
| 7 | Error reporting: scan errors, 20 s connect timeout, 10 s op timeout, GATT status decoding incl. 133/0x81 | `BleScanner`, `GattManager.statusText` | No |
| 8 | Standard CPS / CSC parsing when present | `ble/Parsers.kt` | Unit tests written |
| 9 | Diagnostic report, saved silently to app storage; plain-language verdict (WORKING/FIXED/COMPATIBILITY/NEEDS ATTENTION/INCONCLUSIVE) | `diag/ReportBuilder.kt`, `AutoDiagnostic.finish` | No |
| P3 | Safe fixes: automatic reconnect cycle + retest; community 'start' request only after approval dialog + retest | `AutoDiagnostic` step 7 | No |
| 8b | Live watts/cadence screen (verified vs estimated labels) | `ui/Screens.kt` LiveScreen | No |

Guarantees enforced in code: no firmware flashing, no factory reset, no calibration, no writes to the a6ed custom
characteristics, no automatic writes of any kind. The only non-CCCD write path is `experimentalWrite`, reachable
solely from a button that opens a confirmation dialog.

## To fill in after the first run on the Nokia 5.3

Copy `docs/DIAGNOSTIC_REPORT_TEMPLATE.md`, paste the app-generated report, and attach the JSON export.

## v0.3.0 — Bike Computer (2026-10-12)

Verified on hardware (2026-10-11 session, 48 real 0x2A63 packets): connection, service table, battery read, 1 Hz
streaming without any start command, cadence magnitude (~80–88 rpm), crank angle advancing, power 0 under no load.
**Power under load: NOT yet verified** — first ride with v0.3 will show it.

Automated tests (JUnit, pure JVM — run in CI and also executed locally by the review agent, 17/17 passing):
- Decoder: idle packets, negative cadence (real fixture), forward cadence (community samples), malformed/implausible.
- RideStats: real-session replay, 3-s window + staleness, pause/resume/finish timing, implausible rejection, coasting.
- HealthClassifier: permission, Bluetooth off, searching, reconnecting, silent link (BT), decode error (software), sensor fault.

Not yet tested on hardware (new in v0.3): dashboard rendering, auto-reconnect supervisor, foreground service with screen
off, ride history save/share, settings. First things to check on the Nokia are listed in the chat delivery notes.

## v0.7.0 (build 21) — 2026-10-12 — P0 reliability + P1 coach v2

### Simulated (JUnit, run locally and in CI on every build) — ALL PASS (66 tests)
| ID | Test | Result |
|---|---|---|
| P0-3 | RideStats snapshot/restore lossless, resumes counting after restore | PASS |
| P0-5 | SignalState FRESH / COASTING / STALE / NONE; stale never held as a value | PASS |
| P0-6 | LinkMonitor quality %, 3 gaps with duration/reason/activity-before, open gap closed at finish | PASS |
| P0-8 | LoadVerifier passes only on ≥10 packets ≥40 W with cadence >30; never on 0 W spinning or still cranks; ignores implausible/late packets | PASS |
| P1-1…P1-12 | 17 shared vectors in testvectors/coach, ~1,500 asserted ticks incl. the 60-min Zone 2 session | PASS |
| legacy | decoder, ride stats, zones, targets, BLE parsers, connection policy, health classifier | PASS |

Engine defects found and fixed by the vectors before release: (1) coasting 0 W samples polluted the power rolling
mean so the first loaded seconds read "below target" → PUSH; (2) "keep it up" fired while power passed *through*
the target band on its way down (now needs 5 s on target).

### Real-device — NOT YET PERFORMED (needs Rashed on the bike)
| ID | What to do | Status |
|---|---|---|
| P0-1 | Ride ≥ 10 min with a pedaling pause; open the ride in History → Report → "Sensor link": each gap shows reason and "before it: pedaling/cranks still, under load/0 W". Send logs. | pending |
| P0-2 | After the pause, resume pedaling: watts/cadence back within ≤ 10 s, no 20 s stalls. | pending |
| P0-4 | Mid-ride, swipe the app away; reopen: dashboard shows "Ride restored after restart", time/avg intact, RESUME continues. | pending |
| P0-9 | Settings → VERIFY POWER UNDER LOAD, on road/trainer: PASS with credible max watts; POWER UNVERIFIED tag disappears. | pending |
| P1-13 | Zone 2 mode ride with strap: cues match the gauges; no contradictory cue within 10 s; warm-up gives no "push". | pending |
