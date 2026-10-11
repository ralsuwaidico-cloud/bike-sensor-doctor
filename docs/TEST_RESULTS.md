# Test results — honest status as of 2026-10-11 (one-button version)

You asked me not to claim a feature works until it has been tested. Here is exactly where things stand.

## What was NOT possible in my build environment

- The environment that wrote this project has **no Android SDK and no access to Google's/Maven Central package
  servers** (network policy). Therefore:
  - **The project has not been compiled.** There may be compile errors (typos, API signature mismatches) that a first
    Gradle build will surface. They are usually one-line fixes; send me the error text and I will fix them.
  - **No APK was produced here.** The GitHub Actions workflow (`.github/workflows/build-apk.yml`) or Android Studio
    will produce it (see `docs/INSTALL_NOKIA_5_3.md`).
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
