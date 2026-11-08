# Hardware-readiness report — Cyclift Watch on the LILYGO T-Watch 2021 (8 Nov 2026)

Status in one line: **nothing has been measured on the physical watch yet.** Everything "confirmed" below comes from
LILYGO's published schematic, pin diagram and library for the T-Watch 2021 (round, T-Micro32 Plus); everything that
needs the real device is marked **pending** with the exact step that resolves it. No firmware has been flashed.

## 1. Exact board

| Question | From the manufacturer files | Pending on the real watch |
|---|---|---|
| Model | LILYGO **T-Watch 2021** (round 1.28" GC9A01), module **T-Micro32 Plus** (ESP32-D0WDQ6-V3 dual core, 240 MHz) | — |
| Revision | three exist: **V1.0**, **V1.1**, **V2** (V2 adds GPS, BME280, SD and swaps pins) | **Owner reads the silkscreen inside the back cover** (photo is enough) — the pin map, button mapping and the absence of GPS differ |
| Programming dongle | **T-U2T** (CP2104 USB-to-TTL, USB-C plug, auto-reset) — the watch's own USB-C is **charge only** | **Owner confirms the T-U2T is in the box**; without it the watch cannot be read, backed up or programmed |

## 2. Capabilities (schematic-verified vs to-verify)

| Part | Schematic / library | Verify on device (read-only unless noted) |
|---|---|---|
| Display GC9A01 240 × 240 SPI | pins MOSI 13 · SCLK 14 · CS 15 · DC 19 · RST 27 · BL 21 (V1.x) | first flash (M1) — a display cannot be exercised without running code |
| Touch CST816S (I2C 0x15) | tap / swipe / long press decoded in the controller | I2C scan in M1 |
| Buttons | Reset → EN (not readable) · Boot → IO0 (strapping) · **Key 1 IO35 · Key 2 IO34** (swapped on V1.0) | M1 prints key levels — this decides which revision's map is right |
| IMU BMA423 (0x19) | 12-bit, step counter, wrist-raise interrupt on IO32 | I2C scan in M1; rep counting stays experimental until real-movement tests |
| RTC PCF8563 (0x51) | 32.768 kHz crystal | drift measured over 24 h in M2 |
| Compass QMC5883L (0x0D / 0x2C) | present on some builds | I2C scan in M1 |
| BLE | ESP32 classic BLE 4.2 (NimBLE) — no BLE 5 features, no ANT+ | range / reconnect in M3 |
| Battery / charging | TP4054 charger, battery ADC on IO36, CHARGING on IO2, PWR_ON IO5; **no fuel gauge** | capacity, drain and the ADC-to-percent curve measured in M4 |
| Vibration motor | IO4 (V1.x) | M1 |
| Flash | 8 MB (library build flags, factory partition table) | **`esptool flash_id` — read-only, M0** |
| PSRAM | 2 MB (README) | printed at boot in M1 |
| GPS / barometer / SD | **absent on V1.x** | the watch mirrors the phone's GPS over BLE; it never claims its own |

Dependencies on the phone / external sensors: GPS position and route guidance (phone), power / cadence / heart rate
(BLE sensors via the phone or BikeComputer — the watch has **no optical HR**), training plan, coach messages, recovery
data and Health export (phone). On the watch alone: clock, activity timers, manual set logging, rest timers,
experimental rep counting from the IMU, step count, local storage of logged sets until the next sync.

## 3. Factory backup and recovery (verified procedure, not yet executed)

1. Plug the T-U2T into the watch, a data USB cable from the T-U2T to the computer; the CP2104 appears as a serial port.
2. **M0 — read-only identification + backup (no write):** `esptool chip_id`, `esptool flash_id`, then
   `tools/backup_factory_firmware.sh <port>` = `esptool read_flash 0x0 0x800000 factory-8mb.bin` + SHA-256; two copies
   kept (owner's computer + repository release asset, private). Nothing is written to the watch in M0.
3. Restore path A: `esptool write_flash 0x0 factory-8mb.bin` → byte-identical factory state.
4. Restore path B (bootloader always reachable): hold **Boot**, press **Reset** → ROM download mode; the chip cannot be
   bricked by a bad application image because the ROM bootloader is in mask ROM.
5. Our firmware uses two 3 MB OTA slots (`partitions_8mb_ota.csv`); a failed boot rolls back to the previous slot.

M0 can be run from the owner's PC by me through the linked desktop session (install `esptool` via pip, read only), or
by the owner following the two commands — **either way it needs the owner's go-ahead because it touches the device.**

## 4. Proposed first firmware milestones (each a separate approval)

| Milestone | What is flashed | What it proves | Risk |
|---|---|---|---|
| **M0** | nothing (read-only) | chip, flash size, MAC; full factory backup + SHA | none to the watch |
| **M1 — diagnostics** | `firmware/src/app/main.cpp` (W0 state): serial print of chip / flash / PSRAM, I2C scan, button levels, battery ADC, motor pulse, display test pattern, touch echo | revision, pin map, every peripheral answers, display + touch + keys work | factory firmware replaced → restored from the M0 backup |
| **M2 — faces + clock** | Orbit/Chrono/Pulse on LVGL with the scene renderer, RTC + time sync over BLE | fonts at real size, readability in daylight, RTC drift, idle battery | as M1 |
| **M3 — BLE + cockpit** | phone link (status, telemetry mirror), Cockpit / Performance / Navigation live | latency, reconnect, frame rate, RAM/PSRAM | as M1 |
| **M4 — strength + measurements** | set logging, rest timers, two-press keys, battery/perf logging | the measured table (frame rate, touch latency, RAM, flash, BLE stability, drain) | as M1 |

## 5. Blockers

- Revision and T-U2T presence unconfirmed (owner, 2 minutes).
- Every on-device figure (frame rate, latency, RAM, battery, BLE) is **pending**; estimates in the gallery are labelled as such.
- PlatformIO toolchain is not available in this cloud workspace; firmware compiles run in GitHub Actions (job added in the watch workflow) — the first compile result is the real flash-size figure.
- Flashing of any kind waits for the owner's explicit approval of the exact M-step.
