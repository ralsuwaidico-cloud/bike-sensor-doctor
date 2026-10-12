# Waveshare ESP32-S3 migration matrix

What transfers from the Android app to the dedicated cycling computer, and what must be rewritten. Do **not**
start firmware yet — this is the map for when the hardware arrives.

## Reuse verbatim (pure logic, no Android) — port the algorithm, rewrite in C++
These live under `app/src/main/java/com/rashed/bikesensordoctor/core/` and have **no Android imports**. Each has
JUnit tests that double as the spec; re-implement the same behaviour and port the test vectors.

| Module | What it does | Port notes |
|---|---|---|
| `XdsDecoder.kt` | 11-byte 0x2A63 packet → power/L/R/cadence(signed)/angle/error | Direct struct read, little-endian. Already has C example in PORTING_SPEC.md. |
| `RideStats.kt` | ride state machine, 3 s & 10 s rolling power, avg/max, energy, staleness blanking | Plain arithmetic + a ring buffer of (t,power). |
| `Zones.kt` | Coggan 7 power zones + Zone 2, 5 HR zones, watt ranges | Pure tables; copy the fractions. |
| `BleStandard.kt` | standard HR (0x2A37), standard power (0x2A63), CSC crank cadence, battery | For any ANT+/BLE-standard sensor the ESP32 also talks to. |
| `ConnectionPolicy.kt` | reconnect decision (STOP / autoConnect / scheduled retry) + back-off | Concept ports; the BLE calls themselves are platform code. |
| `HealthClassifier.kt` | link facts → plain status enum | Pure. |

## Re-implement on ESP32 (platform-specific — same design, different APIs)
| Android file | ESP32-S3 equivalent |
|---|---|
| `ble/GattManager.kt`, `BleScanner.kt` | NimBLE central: scan filter on 0x1828, connect, subscribe 0x2A63 CCCD, full teardown + settle before reconnect (the error-133 fix maps to NimBLE's `ble_gap_terminate` + delay). |
| `ride/SensorManager.kt` | NimBLE connection supervisor + NVS-stored last address. |
| `ride/RideService.kt` | not needed — the MCU is always "foregrounded"; just a main loop. |
| `ride/GpsTracker.kt` | only if a GPS module is added; else no speed/distance. |
| `ride/RideHistory.kt`, GPX/CSV | write to SD card / flash; GPX/FIT formatting logic ports as string building. |
| `ui/Dashboard.kt` (Compose) | LVGL (or Waveshare's GFX) on the 360×360 round panel. The *layout model* (one big power arc 135°+270°, a cadence arc, four tiles, zone colour) ports; the rendering is rewritten. |
| `Prefs.kt` | NVS key-value. |

## Rewrite entirely / not applicable
- Android permissions, foreground service, Compose, Activity lifecycle, `BikeApp`/`DoctorViewModel`.
- The Diagnose & Repair flow (`diag/`) is an Android development aid; the verified findings are already folded
  into the firmware design, so it need not be ported.

## Hardware facts the firmware must honour (verified 2026-10-12 on PC)
- Sensor streams 0x2A63 at **1 Hz** after a plain CCCD subscribe — **no start command**, no bonding.
- One connection at a time; a clean single owner connects reliably (8/8, 5/5 rapid reconnects on the PC).
- Forward pedaling = **positive** cadence; keep the magnitude + a "reverse" flag.
- Power needs load; 0 W when freewheeling is correct, not a fault.
