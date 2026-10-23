# Waveshare cycling computer: firmware architecture (0.2.0)

Board: Waveshare ESP32-S3-Touch-LCD-1.28-B. It has a 240 × 240 round GC9A01 display, a CST816S touch controller, a QMI8658 IMU, a battery ADC, 16 MB of flash and 2 MB of PSRAM. **It has no GPS and no ANT+ radio.**

## Layers

```
 ui/*.c            round-screen LVGL screens          ─┐  identical code on the device
 app/app.c         profile, demo, ride session,        │  and in the PC harness (test/sim)
                   journal, history                    │
 components/bc_core  decoders, recorder, coach, FTP   ─┘  pure C99, host unit tests (test/host)
 ───────────── plat.h (the only platform interface) ─────────────
 plat_esp.c + ble_central.c + hw.c + net_wifi.c      the Waveshare
 test/sim/plat_host.c                                the PC harness (scripted sensor values)
```

- **Sensor kinds, not radios.** `plat.h` exposes `PLAT_SENS_POWER`, `PLAT_SENS_HR` and `PLAT_SENS_SPEED`.
  - Today POWER and HR come from BLE (`ble_central.c`).
  - An ANT+ module, or a GPS-equipped Waveshare model, plugs in below `plat.h` without touching the screens.
  - SPEED is reported as `PLAT_LINK_UNSUPPORTED` on this board. Distance and speed are never estimated.
- **Freshness.** Every live value is checked against its age. A value older than 4 s is NO DATA, never held. 6 s with no packets at all means the link is silent.
- **BLE safety.** The only write the firmware sends is the standard CCCD subscription (01 00). It never writes to the control point 0x2A55 or to vendor characteristics, and it never bonds. Reconnection backs off 1 → 16 s.

## Stored data

| What | Where | Format | Survives |
|---|---|---|---|
| Rider profile and settings | NVS `bc/profile` | `key=value` text (`format=bc-profile-1`) | power loss (NVS is atomic) |
| Ride in progress | FAT `/data/rides/active.jnl` | header `J1 id demo ftp how est`, then one line per second (`power cadence hr`, `-` = paused, `-1` = no data), flushed every 10 s | crash or power loss → replayed at start-up |
| Finished real rides | `/data/rides/history.txt` + `/data/rides/rNNNN.txt` (the per-second samples) | one `R1,…` summary line per ride | |
| Demo rides | `/data/demo/history.txt` only | same line, `demo=1` | never mixed with real history; demo samples are discarded |

- The profile text and the per-second ride files are the formats the future phone apps will sync. Unknown keys are ignored, so either side can add fields.
- Firmware updates written by `INSTALL-v0.2.0` do not touch NVS or the FAT partition, so settings and rides are kept across updates.

## Ride, coach, FTP

- **Recorder** (`bc_ride`). Missing samples are excluded from averages. Average power counts 0 W while coasting; average cadence counts only pedalling seconds. Paused time is not ride time. Time in zones is reported only with an *established* FTP.
- **Coach** (`bc_coach`). One instruction at a time, chosen from a single priority ladder:

  no data → HR safety (strap optional) → coasting → warm-up → effort → cadence → hold.

  Every instruction carries its reason with the live number that triggered it.
  - **Established FTP:** Zone 2 band, or tempo for the FTP and climbing goals.
  - **Provisional FTP:** the rider's own steady output is the yardstick. The provisional value is used only as a labelled soft ceiling.
- **FTP honesty.**
  - The onboarding FTP is weight × W/kg for the experience level and is always shown as **PROVISIONAL**.
  - A real ride replaces it only with a steady 20-minute effort: CV ≤ 15 %, at least 1.15 × the rest of the ride, and at least 10 minutes of other riding. The new value is 95 % of that effort.
  - An FTP the rider entered from a real test is never overwritten; the ride only suggests a value.
  - Demo rides never change the FTP.

## Reliability

- Staged start-up logs (`STAGE n … OK`).
- Crash-loop guard: after 3 crash resets the board shows a SAFE MODE screen.
- A `HEALTH` line every 60 s reports heap, minimum heap, LVGL memory and the free stack of the UI, NimBLE and main tasks.
- `test/host make lint` blocks `%f` in LVGL format calls, which caused the 0.1.0 reboot loop.

## 0.2.1 additions
- **Ride-screen designs** are entries in a registry (`DESIGNS[]` in `main/ui/ui_ride.c`): letter, name, hint and a `build(tile)` function that only lays out the shared widgets; `ride_update()` fills whatever the design created from the same app/coach data. Adding a design = one build function + one table line + a thumbnail (`tools/make_thumbs.py` from the PC renders) + `BC_STYLE_COUNT`, and it must pass test/sim.
- **Display never waits on the radio**: no Bluetooth call runs in the UI task; RSSI is read by the BLE manager, which has its own FreeRTOS task (not the shared esp_timer task).
- **Torn-write protection**: if the history file's last line was cut by a power loss, the next save starts on a new line, so only the cut record is lost.
- **Device Health / export**: `plat_health()` + `plat_export_report()` (printed between `BIKE COMPUTER DIAGNOSTIC REPORT BEGIN/END` on the serial port and kept as `/data/diag/report.txt`). Crash and safe-mode totals live in NVS `diag`.
