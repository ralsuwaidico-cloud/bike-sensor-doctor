# Bike Sensor Doctor

One-button Android app (Kotlin, Jetpack Compose) that diagnoses an XDS / Branta bicycle power meter
(`XDS-A001-9769`, `C0:A1:25:07:97:69`) and explains, in plain language, whether it works, whether anything could be
fixed, and why a Garmin Edge 820 cannot see it. Real Bluetooth hardware only; nothing is simulated.

Press **DIAGNOSE & FIX MY POWER METER** and the app automatically: checks Bluetooth → scans for the meter → connects →
reads battery/firmware → inspects services → listens 15 s still, then 30 s while you pedal → tries safe fixes
(reconnect cycle automatically; one community-documented "start" request only with your approval) → retests →
shows WORKING / FIXED / COMPATIBILITY ISSUE / NEEDS ATTENTION / INCONCLUSIVE. The technical report and raw log are
saved silently in the app's private storage; "Send report to Claude" shares them when troubleshooting.

- `docs/INSTALL_NOKIA_5_3.md` — getting the APK and installing it
- `docs/PHASE2_PROTOCOL_RESEARCH.md` — what is known about the XDS protocol, with sources
- `docs/TEST_RESULTS.md` — what has and has not been verified
- `docs/DIAGNOSTIC_REPORT_TEMPLATE.md` — template for recording a session

## Code map
```
ble/Uuids.kt, Parsers.kt, BleScanner.kt, GattManager.kt   Bluetooth layer (scan, GATT, standard + community parsers)
log/EventLog.kt                                           timestamped hex log, counters, CSV/JSON
diag/AutoDiagnostic.kt                                    the one-button orchestrator and verdict logic
diag/ReportBuilder.kt, PhaseResult.kt                     technical report
ui/MainActivity.kt, Screens.kt, DoctorViewModel.kt        permission/Bluetooth gates, home, running, result, live watts
.github/workflows/build-apk.yml                           builds the APK and publishes it as a GitHub Release
```

## Safety rules enforced in code
Never flashes firmware, factory-resets, changes calibration, or writes to unknown characteristics. Writes are limited to
reversible notification subscriptions and one 4-byte community-documented request that is sent only after the user
taps YES in an approval dialog explaining its source and risk.

## Garmin compatibility — the honest limit
The Edge 820 pairs power meters over ANT+ or the standard Bluetooth Cycling Power service. This sensor offers neither
(it has a private XDS Bluetooth format and no ANT+ radio). No Android app can change that; the only known route is a
separate bridge device (see the protocol research).
