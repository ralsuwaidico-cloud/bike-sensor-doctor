# 02 — Cyclift Watch / LILYGO (Project B) master brief

Device: **LILYGO T‑Watch 2021** — round 1.28–1.3" GC9A01 240×240, classic ESP32 (T‑Micro32 Plus, 8 MB flash, 2 MB
PSRAM), CST816S touch, BMA423 accelerometer, PCF8563 RTC, QMC5883 compass, vibration motor, Reset + Boot + two user
keys, LiPo on TP4054, programmed through the **T‑U2T** USB‑C dongle. **Board revision (V1.0 / V1.1 / V2) and the T‑U2T
presence are unconfirmed by the owner** — the pin map differs per revision.

## 1. History (all 8 Nov 2026, one day of work; branch `watch/w0-foundation`, 121 commits)

| Step | Owner input | Delivered (host‑tested, never flashed) | Commits |
|---|---|---|---|
| **W0** | directive: new workstream, separately tracked, no flashing without approval | hardware audit (capability matrix, pin maps per revision, factory backup procedure `watch/tools/backup_factory_firmware.sh`), architecture, three face concepts, rep‑counting strategy, BLE protocol v1, firmware skeleton + 66 host tests | `38a20343` |
| **W1 part 1** | 15:14 strict round‑screen fitting, hardware‑verified buttons (2 + Boot), button quality, QA on 14+ screens × 6 appearances | round‑screen layout engine (chord‑aware bands, text fitting), 17 screens, automated round‑display checks, button abstraction | `2ca5ce5d` |
| **Cycling instrument v1** | 15:31 cycling redesign | Cockpit, Performance graphs, GPS mirror, two‑press keys | `f1809e13`, `9d8577c7` |
| **Design v2** | 16:07 v1 rejected: "one screen, one question"; cockpit hierarchy; gauges documented; graph‑focused performance; three GPS states; fix 214 W vs "reduce power"; distinct status words; face refinements; strength screens with dominant rep count; two‑press keys; strict acceptance at native resolution; gallery with before/after, text sizes, memory estimates, limitations | **Design v2** (gallery‑v2, native PNGs, TEXT_SIZES.md) — **approved 16:44 as the design baseline** | `70245e12` |
| **Priorities 3–4** | 16:44 implement the accepted design in firmware; functional interaction | application model (`app_model.hpp`), wire payload codecs, lifecycle screens (prepare / confirm end / review / face picker / today), LVGL scene renderer + measurer, ESP32 drivers (TFT_eSPI GC9A01 flush, CST816S, keys, haptics, battery, PCF8563, LittleFS, NimBLE service), diagnostics build (M1), CI compile job | `22d9d91f`, `251a4630` |
| **First real device build** | — | compile fixes for Arduino‑ESP32 3.x; `pipefail` so a failing `pio run` can no longer pass; LVGL widgets switched off explicitly; **run 42485131249 green** with real RAM/flash figures (07_) | `570893db`, `6639c553`, `563cfee3` |
| **Quick settings + timer + DND** | priority 4 remainder | real persisted brightness/appearance/do‑not‑disturb, countdown timer panel, DND suppresses non‑safety coaching haptics | `b6ab6ca8`, `ca2cadb6` |
| **Pause** | 18:07 "Stop parallel development … Preserve existing Watch work without modifying it." | branch frozen at `ca2cadb6` | — |

## 2. Architecture (as built — `watch/docs/ARCHITECTURE.md`, `watch/firmware/`)

- **PlatformIO + Arduino‑ESP32 (core 3.3.12 via framework‑arduinoespressif32 4.30312) + LVGL 8.3.11 + TFT_eSPI 2.5.43
  + NimBLE‑Arduino 1.4.3**; env `twatch2021` with per‑revision envs `T-Watch-2021-V1_1` (default), `V1_0`, `V2`, and
  `V1_1-diag` (M1 diagnostics image). TFT_eSPI configured from `platformio.ini` build flags (no User_Setup edits).
- **`domain/` is pure C++17, hardware‑free, host‑tested** (`platform = native`): `activity.hpp` (activity registry,
  lifecycle, honest timers), `strength.hpp` (exercise order, supersets, set logging, corrections, undo, rest timer),
  `rep_detector.hpp` (experimental wrist‑motion reps with confidence), `coach.hpp` (coaching message protocol, one primary
  instruction, offline rules, 44‑char wrist contract), `sync.hpp` (frames + CRC‑16, event queue, dedup, clock sync),
  `payloads.hpp` (binary codecs for every message), `grading.hpp` (fixed four grading colours), `navigation.hpp` (orbital
  navigation state machine), `round_layout.hpp` (chord‑aware bands, text fitting, Builder), `layout_checks.hpp`
  (automated round‑display checks), `theme_tokens.hpp` (6 appearances), `screens.hpp` + `ride_screens.hpp` (every scene),
  `ride_telemetry.hpp` (Live readings with age, series, zone time, GPS mirror, commands, auto‑scale), `buttons.hpp`
  (KeyDecoder, TwoPress), `app_model.hpp` (the state machine driving all of it), `render_svg.hpp` (gallery renderer).
- **`ui/`**: `lvgl_renderer.hpp` (scene → LVGL arcs/labels/lines; font measurer; fonts Montserrat 12–48), `lv_conf.h`.
- **`hal/`**: `board_pins.hpp` (per‑revision pins, `LCD_*` names), `hal.hpp` interfaces, `hal/esp32/drivers.hpp`.
- **`app/main.cpp`**: `CYW_DIAG` → M1 diagnostics (chip/flash/PSRAM print, I2C scan, key levels, battery ADC, motor,
  display pattern, touch echo); otherwise the app loop with persistence (`/settings.bin`, `/events.bin`).
- **Tests**: `watch/firmware/test/host/test_domain.cpp` (244 checks incl. payload round‑trips and a full ride + strength
  session through touch, keys and BLE), `gallery.cpp` (61 screens × 6 appearances × 4 text variants = 1 464 scenes, 0
  findings; writes `TEXT_SIZES.md`). CI `.github/workflows/watch.yml`: host‑tests + firmware‑compile (never flashes).

## 3. Design baseline (approved v2) — see 04_

Faces **Orbit · Chrono · Pulse**; six appearances (Cyclift Midnight Blue/Arctic, Sport Graphite/Steel, Bloom Plum/Rose);
fixed grading colours; cycling **Cockpit** (one dominant number + large unit, 270° orbital gauge with zone ladder,
target band, interval arc, ≤ 2 secondary metrics, one command line, single Pause pill), **Performance** (one large chart
per page, swipe pages), **Navigation** (three states: tracking · route ahead + next turn + off‑route · disconnected);
strength Exercise / Rep counter / Rest timer / Controls; Prepare, Confirm End, Review, Face picker, Today, Recovery,
Sleep, HRV, Coach, Notifications/Timers, Quick settings; two‑press physical keys (first press previews, second executes,
2.5 s expiry; touch Pause immediate; End always available).

## 4. Requirements still binding

- Honest data: "--:--" before time sync, "NOT SYNCED", "—" for absent values; no invented points while unlinked; a
  missing sensor is never 0; estimates labelled; rep counting is experimental and confirmed by the athlete.
- Round‑screen acceptance at native 240×240: 0 overflow / overlap / contrast / truncation / touch‑size findings.
- Phone is the recorder and plan owner; the watch sends events (deviceId, seq) and receives acks; never writes Health.
- No flashing before: owner confirms revision + T‑U2T, factory backup taken and SHA‑verified, approval of the exact
  M‑step (M0 read‑only identify/backup → M1 diagnostics → M2 faces+clock → M3 BLE+cockpit → M4 strength+measurements).

## 5. Current state in one paragraph

Everything above exists as code and passes its host checks; the device image **compiles** (RAM 111 856 B static,
flash 2 190 064 B — linker figures from CI, not measurements). **No byte has reached the watch.** Hardware facts come
from the manufacturer's files only; the owner still needs to read the silkscreen revision and confirm the T‑U2T dongle.
Development is paused by the owner's 8 Nov 18:07 directive; the branch is preserved unmodified.
