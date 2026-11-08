# 01 — BikeComputer (Project A) master brief

Device: **Waveshare ESP32‑S3‑Touch‑LCD‑1.28‑B** (SKU 26959, the 1.28" board in the CNC metal case), programmed and
read over **USB‑C** (CH343P USB‑UART) from the owner's Windows PC with the `pc-kit` installers. The owner is not a
programmer: every install is a double‑click kit that backs up the whole 16 MB flash first and verifies it.

## 1. Where the idea came from (history)

| Phase | What | Where it lives |
|---|---|---|
| **Nokia Android app "Bike Sensor Doctor" → "BikeComputer"** (Oct 2026, v0.6 → v0.12) | the first cycling computer: the owner's Branta/XDS BLE power meter on a Nokia 5.3; Design 7 "AI Scientific Coach" dashboard (large power gauge + RPM/BPM gauges), v0.10 four‑section live dashboard with a combined normalised graph, v0.11 auto‑coach, v0.12 per‑rider layouts (Power Focus / Classic / Compact), automatic FTP learning, meter verification | branch `ios/dev` → `app/` (Kotlin), `docs/TEST_RESULTS*.md`, `docs/evidence/*.png` (build 51 → run 94 screenshots), APKs `BikeComputer-v0.8.0-build51/54.apk`, `v0.9.0-build61.apk`; branches `design/*` |
| **Standing direction, 23 Oct** | "Build the Waveshare as a complete standalone cycling computer FIRST; companion apps later" — all setup on the device, no phone needed; owner approves every major screen from rendered options; first milestone = real power + cadence from the XDS meter on the Waveshare alone; never show simulated values as real; coaching with an identifiable reason, works without HR, offline; carry over FTP = weight × W/kg‑by‑experience (labelled estimate), auto FTP learning, meter verification separate from FTP | `docs/DEVICE_DESIGN_DECISIONS.md` |
| **Phase A diagnostic (23 Oct, fw 0.1.x)** | display, touch, storage, NVS, IMU, battery, Wi‑Fi scan, XDS live via NimBLE; reboot‑loop fix (float printf), crash‑loop safe mode, staged start‑up | `firmware/waveshare` first commits (`6bca247d`, `cd9df786`) |
| **Standalone computer (fw 0.2.0 / 0.2.1)** | onboarding, Home, ride pages A/B/C, coach, results, history, settings, sensors, demo mode, ride‑design registry with preview picker, Device Health + diagnostic export | `6fd1f7eb`, `0e05de7e` |
| **0.3.0 Wi‑Fi**, **0.4.0 BikeComputer Link** (BLE peripheral for the phone, LE Secure Connections passkey pairing, Info/Live/Input/Control), phone GPS speed, watch HR freshness 6 s, installer with full backup | `51a707eb`, `8412804e`, `8b8ae415` |
| **0.5.0 Power** | Quick Settings, screen‑off with recording preserved, triple‑tap wake, deep sleep outside rides, touch lock, auto timeout, battery estimate | `0bb2f6a0`, `docs/POWER_0.5.0.md` |
| **0.6.0 / 0.6.1** | fixes for the owner's 0.5.0 findings (link lost on screen‑off, unreliable wake, pull‑down hard to open), Connections system replaces Sensors, protocol v1.2 (ride sync, Wi‑Fi provisioning, profile sync, settings), any‑touch wake with swallowed gesture, hold‑to‑confirm everywhere, touch‑dead‑after‑sleep fix | `e2029503`, `21012328`, `3defca4f`, `81c68707`, `docs/FIRMWARE_0.6.0/0.6.1.md` |
| **0.7.0 – 0.7.3** | pairing lifecycle (random‑static identity renewal), brand‑neutral labels (Cyclift), power‑meter CCCD fix + per‑sensor pipeline stages, diagnostics report transfer (Link 1.2.3), crash investigation after the 0.7.2 crash loop, RECOVERY MODE, core‑dump partition | `7d0c0490`, `2cb69ffd`, `ec0aad93`, `09256114`, `1cf8cf08`, `docs/CRASH_0.7.2.md`, `docs/FIRMWARE_0.7.0.md`, `FIRMWARE_0.7.2.md`, `FIRMWARE_0.7.3.md`, `docs/PARTITIONS_0.7.3.md` |
| **Phone‑first turn (27 Oct)** | owner brief 12:15 "measure first, don't guess" after the board crashed on 0.7.3 at Bluetooth start; the iPhone becomes the brain (profile, plan, coach decisions, history), the board = sensors + live display + ride clock; **Link 1.3** contract drafted and implemented on both sides | `coord/interfaces/BLE_CONTRACT.md`, `coord/reports/FW_STORAGE_MEMORY_REPORT.md`, `coord/handoffs/firmware.md` |
| **0.7.4‑rc1 → rc5 (27–28 Oct)** | Bluetooth start never aborts (heap logged, "Bluetooth unavailable" state), storage failure categories, boot plan, NVS boot‑record ring, five QA review rounds fixed at the root, Link 1.3 (HELLO gate, coach card on every ride design, offline ride queue, storage clean‑up, diag auto‑retention) | `b478887e` … `0d88933e`; kit `pc-kit/INSTALL-v0.7.4-rc5.bat` |

## 2. Architecture (as built)

- **ESP‑IDF 5.5.1**, NimBLE host, LVGL 8 (vendored under `components/lvgl`, `esp_lvgl_port`), display `esp_lcd_gc9a01`,
  touch `esp_lcd_touch_cst816s`.
- **Portable core `components/bc_core`** (plain C, host‑tested on Linux): `bc_xds` (power‑meter decode), `bc_hr`,
  `bc_csc` (cadence/speed), `bc_cp` (cycling power service), `bc_pipe` (sensor pipeline stages), `bc_ride` (ride
  clock/recording), `bc_coach` (on‑board target band and cues), `bc_profile`, `bc_link` (Link codec), `bc_diag`,
  `bc_power`, `bc_wifi`, `bc_boot` (staged boot / recovery), `bc_demo`.
- **Board layer `main/`**: `hw.c` (pins, SPI/I2C, backlight), `ble_central.c` (sensors: meter first, then strap/CSC),
  `ble_link.c` (GATT server for the phone), `net_wifi.c`, `plat_esp.c`, `diag_esp.c`, `app/*` (app state, power,
  diagnostics, Link 1.3 `app_link13.c`, profile service), `ui/*` (one file per screen: home, ride, results, settings,
  conn, phone, power, recovery, wifi, onboard, tools, thumbs), bitmap fonts `fonts/bc_num80/60/44, bc_bold22/16`.
- **Tests**: `test/host` (C unit tests incl. Link conformance vectors shared with iOS `BCLinkTests`/`LinkV12Tests`,
  diag fixtures, storage, partitions, boot record, Link 1.3 fixture `gen_link13_fixture.c`), `test/sim` (LVGL
  simulator renders every screen and checks the round glass, 339 screens / 701 checks on rc5), `test/blehost`
  (fake‑NimBLE harness incl. stress with Link 1.3 traffic + ride‑queue chunks while the meter streams).
- **CI** `.github/workflows/firmware.yml`: host tests + BLE harness, ESP‑IDF build + simulator; build only, never flashes.
  Last run **40708452283** (c0a10fb0, 28 Oct) both jobs green.

## 3. User‑facing behaviour (approved decisions)

- Onboarding on the device (Welcome → Name → Age → Weight → Experience → Main goal → Power meter → HR strap → Wi‑Fi →
  Ready); number entry = spinning wheel; name entry = letter ring. Height in Settings only.
- Navigation A: ride‑pages carousel + pull‑down control panel; hold 1 s PAUSE, tap RESUME, hold 2 s END; Results SAVE
  (tap) / discard (hold the bin 1.5 s).
- Ride dashboards: Power Focus (default), Split, Coach First — all installed, chosen in Settings › Display with a
  preview, switchable during a ride; since Link 1.3 every design carries the **Cyclift coach card** (phone's coach).
- Home: START RIDE + Connections / History / Settings, status line (meter, HR, battery), FTP labelled PROVISIONAL until
  verified. Demo mode: orange DEMO badge, separate history, never changes FTP, off after restart.
- Diagnostics: Device Health, Sensor Test (REAL/SIMULATED), Self‑test, SEND LOG TO PC, report transfer to the phone.
- Power: screen‑off keeps recording and the phone link; connected standby; deep sleep outside rides; any‑touch wake with
  a swallowed gesture and 400 ms guard; hold‑to‑confirm so a tap can never start a ride.
- Coaching on the board: target band from the phone's plan (COACH_PLAN/COACH_STATE); offline it falls back to its own
  rules; never invents watts when the FTP is unknown (open audit items M‑07…M‑11, BIKE‑005).

## 4. Requirements still binding

- Never show simulated values as real; missing sensors say NO DATA / NO STRAP.
- One recorder per ride (board when the ride started there); the phone imports by `boardId + rideId`, never duplicates.
- Protocol changes are versioned and capability‑gated (05_); shipped messages ≤ 1.2.3 stay byte‑compatible.
- Every install: full 16 MB backup first, verified; rollback kit for the previous version kept; owner approves each flash.

## 5. Current state in one paragraph

The board runs **0.7.3**, which aborts at Bluetooth start (`nimble_port_init` → internal‑RAM allocation failure,
strongly indicated, unconfirmed) and whose FAT root directory is corrupted (all 512 entries erased between 24 and 25 Oct
during 72 crash resets on 0.4–0.6). **0.7.4‑rc5** fixes the abort (Bluetooth never aborts; heap logged; "Bluetooth
unavailable" state), adds storage categories/recovery and Link 1.3, passed five QA rounds (host, simulator, BLE harness)
and is packaged in `pc-kit` — but **has not been installed**: the owner's go for `READ-BOARD-STATE` (read‑only board
dump) and the rc5 install is still pending. Nothing of 0.7.x is hardware‑verified. The Android Nokia app is superseded.
