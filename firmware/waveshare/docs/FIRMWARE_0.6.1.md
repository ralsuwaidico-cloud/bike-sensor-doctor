# Firmware 0.6.1 — bug-fix release (25 Oct 2026)

App image: `pc-kit/fw-v0.6.1/BC061-app.bin` sha256 d2b0498f554f5290e31be9bfcf8ad9b0c6630acd641e2d413a64ff7b1039852d
(1 771 808 B / 0x1b0920). Bootloader, partition table and OTA selector are byte-identical to 0.5.0/0.6.0, so the installer
writes only 0xf000 + 0x20000. Settings and ride history are untouched. No new features.

## 1. Root cause of "touch dead after screen-off / sleep wake" (0.6.0 rev 3, reported by Rashed on the real board)

Three defects, all in the rev-3 wake gate (`bc_gate_t`, the filter between the CST816S driver and LVGL), all invisible in the
simulator because the simulator polled the touch controller continuously while the device does not:

1. **Event-driven reads.** `esp_lvgl_port` registers the CST816S interrupt and puts the LVGL input in `LV_INDEV_MODE_EVENT`
   (`esp_lvgl_port_touch.c:72`): the controller is read only when TP_INT fires — at its scan rate while a finger is down,
   once for the release, then **never** until the next contact. The gate's GUARD state could only end *inside a read*
   (`bc_gate_feed`), so after the wake touch's release report it stayed in GUARD until the next touch arrived.
2. **Wrong rule on the first read after the guard.** In rev 3, *any* press seen after the guard had expired was treated as
   "a finger that landed during the guard" and swallowed to its release. On the device the first read after a quiet guard
   *is* the next tap (see 1), so every tap after a wake was swallowed, its release put the gate back into GUARD, and the
   cycle repeated: Home looked normal and nothing responded until RESET. Exactly Rashed's symptom.
3. **A lost release report locked the gate forever.** If the controller's single release report was missed, SWALLOW never
   ended; nothing in the firmware could recover it.

The same mechanism hit the deep-sleep wake (boot started in SWALLOW waiting for a release the driver would never report) and
the hold-to-start path (the swallow after a fired hold).

## 2. Fixes

| # | Change | Where |
|---|---|---|
| F1 | GUARD ends on a timer (`bc_gate_tick`, called every 250 ms from `app_power_tick`), not only inside a read | bc_power.c, app_power.c |
| F2 | A **new** press after an expired guard passes; only a finger already down when the guard ends is swallowed (`pressed && was`) | bc_power.c |
| F3 | **Forced reads while the gate blocks**: `plat_touch_poll()` → `lv_indev_read()` → the port's I2C read, every 250 ms in SWALLOW/GUARD, so a release that raised no interrupt is still observed (the finger-off state is persistent) | plat.h, plat_esp.c, hw.c, app_power.c |
| F4 | **Watchdog**: a SWALLOW with *no touch report at all* for 1.5 s is abandoned (guard, then open). A finger the driver keeps reporting is swallowed for as long as it stays — resting a finger on START RIDE through a wake can never become a hold-to-start | bc_power.c (`last_feed_ms`) |
| F5 | Deep-sleep wake: a 1.5 s GUARD instead of a SWALLOW without a finger the gate has seen | app_power.c |
| F6 | After every screen wake the CST816S is asked for its chip id; no answer → TP_RST pulse (GPIO13 low 10 ms) + re-read, logged | hw.c `hw_touch_wake_check` |
| F7 | **SAFE MODE**: BOOT (GPIO0) held while RESET is pressed → gate forced open, wake = any touch, brightness 80 %, timeout 5 min, red "SAFE MODE" badge on Home; nothing saved or erased | main.c, hw.c, app_power.c, ui_home.c |
| F8 | Serial diagnostics (kept in the release): `TOUCH gate <state> (<why>)` on every transition, `TOUCH report n ...` for the first 5 reports after boot, every CST816S register write with its result, `touch diag (...)` chip id / firmware / DisAutoSleep / INT level / indev mode at init, after a reset pulse and 10 s after boot, `touch wake check` on every wake. Device Health shows the gate state and report count | hw.c, app_power.c, main.c, ui_tools.c |
| F9 | The build stamp no longer starts with `#` (LVGL read `#8494a0` as a colour command and ate it). Now `Oct 25 hh:mm id xxxxxxxx` | plat_esp.c |

One monotonic ms clock (`plat_ms()` = `hw_millis()`) is used by the gate, the hold detector and the guard; no s/µs mixing.
The register writes (0xFE DisAutoSleep on screen-off, 0xF9 = 2 s on wake) are unchanged from rev 1, which responded to touch;
the controller is verified after each wake (F6) and, failing that, reset — the "simpler display-off" fallback is therefore
F3+F4 (touch controller left as it is, forced reads), which is what the gate now does regardless of the register writes.

## 3. Settings layout audit

New simulator checks on every screenshot: **OVERFLOW** (text larger than its label box), **EDGE** (any corner of the text
rectangle outside the inscribed circle), **OVERLAP** (two visible texts, or a text and an unrelated control, sharing pixels —
texts under an opaque panel are excluded). A sweep (scenario 7b) visits Settings, Display, Power, Quick Settings in five option
states each, all eight Connections pages with and without the phone, Wi-Fi, Device Health and Phone, scrolled top to bottom:
80 extra screens, 0 issues. Findings fixed:

- Rows (`ui_row_btn`): 44 px tall (was 40); title and value measured; both fit → the value takes the slack; otherwise the title
  keeps its text (up to 70 %) and the value ends in "..." (DOTS only on the label that is really too long, CLIP otherwise, so
  LVGL never rewrites a stored text); `ui_row_set_value()` sizes before storing a new value. Values that wrapped onto two lines
  ("! not\nconnected", "Power\nsettings") no longer do.
- Titles: never wider than the circle at their height; a long title drops its letter spacing before shortening (Welcome).
- Descriptions (`ui_note`): wrapped to the list width inside lists, to the circle's chord elsewhere (Power page notes).
- Wi-Fi "network not found": bounded 184 × 66 box, shorter text, no longer runs under BACK.
- Heart-rate page: a coloured span that wrapped onto two lines broke LVGL's recolor ("relayed#8494a0 WHOOP") — shortened.
- Connections menu: "! not found" → "! missing" (fits beside "Power meter"); Ride sensors page "NO STRAP / PHONE" → "NO SOURCE".
- Quick Settings row "Quick Settings ▾ swipe" → "Quick Settings ▾".

## 4. Tests

- `test/host`: 1896 checks, 0 failures (gate: device read sequence, tick-driven guard, lost release, held finger, watchdog).
- `test/sim`: 243 screens, 0 issues; 391 functional checks, 0 failed. New scenario 18 runs the harness in **event mode**
  (reads only while a finger is down + one release report, exactly like the device): boot → Connections/Settings/History;
  20 × screen-off → one touch → release → Connections opens, 0 wake presses; a lost release report → recovered; deep sleep →
  wake → Connections/Settings/History; plain taps never start; 1 s hold starts exactly one ride; coach-cue wake and
  phone-command wake leave touch working. With the rev-3 gate rules re-applied, this scenario fails 20/20 ("unresponsive")
  — the regression is reproduced and the fix proven in the simulator.
- `idf.py build`: OK (ESP-IDF 5.5.1), 58 % of the app slot free; LVGL heap peak 56 456 / 93 840 B (60 %).

## 5. Hardware-only (not verified here)

Any-touch wake latency and the swallow/guard on the real CST816S, the forced reads through `lv_indev_read` in event mode,
`hw_touch_wake_check` and the TP_RST pulse, deep-sleep wake + boot-time guard, SAFE MODE button sampling, hold feel at the
real poll rate — plus everything listed in FIRMWARE_0.6.0.md §hardware-only. `pc-kit/TEST-v0.6.1.txt` section 1 is Rashed's
acceptance list; the serial log (READ-LOG-v0.6.0.bat) shows the gate transitions in plain text.
