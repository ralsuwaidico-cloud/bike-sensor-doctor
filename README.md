# Bike Computer (formerly Bike Sensor Doctor)

Android cycling computer (Kotlin, Jetpack Compose) for the XDS / Branta power meter `XDS-A001-9769`
(`C0:A1:25:07:97:69`), which speaks a private Bluetooth format and has no ANT+. Real hardware only; nothing is simulated.
Target phone: Nokia 5.3, Android 12. Long-term target: a dedicated round-display cycling computer (see
`docs/PORTING_SPEC.md`).

## What it does
- Opens straight into the dashboard: large power gauge, cadence gauge (with a backwards-pedaling warning), 3-second
  power, four configurable fields (avg/max power, ride time, avg/max cadence, energy, battery, L/R, clock).
- Finds and connects to the remembered sensor automatically; reconnects after drops with back-off; cycles the link if
  it goes silent; shows plain-language status instead of error codes.
- Start / Pause / Resume / Finish ride; rides saved locally (summary JSON + 1 Hz CSV) with History view and CSV share.
- Foreground service keeps recording with the screen off; optional keep-screen-on; battery-optimisation exemption prompt.
- Settings → **Diagnose & Repair**: the guided check from v0.2 (still → pedal → optional 60 s ride) with safe fixes.
- Technical logs saved automatically when a problem state appears; "Send logs" from Settings.

## Code map
```
core/   XdsDecoder.kt, RideStats.kt, HealthClassifier.kt   PORTABLE CORE — no Android imports; port this to the MCU
ble/    Uuids, Parsers, BleScanner, GattManager            Android Bluetooth layer
ride/   SensorManager, RideEngine, RideService, RideHistory, Prefs
diag/   AutoDiagnostic, ReportBuilder                       Diagnose & Repair
ui/     MainActivity, Dashboard.kt, Screens.kt (diagnose), DoctorViewModel
test/   core/CoreTest.kt + Fixtures.kt (48 real packets), ParsersTest.kt
docs/   PORTING_SPEC.md, PHASE2_PROTOCOL_RESEARCH.md, SESSION_2026-10-11_ANALYSIS.md, TEST_RESULTS.md
```

## Safety rules enforced in code
Never flashes firmware, resets, calibrates, or writes to unknown characteristics. The only writes are CCCD notification
subscriptions, plus one community-documented 4-byte control-point write available solely inside Diagnose & Repair after
an explicit approval dialog.

## Verification status
See `docs/TEST_RESULTS.md`. Cadence magnitude verified on hardware (2026-10-11). **Power under load not yet verified.**
