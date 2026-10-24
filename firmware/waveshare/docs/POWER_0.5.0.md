# Firmware 0.5.0 "Power" — what is implemented, and what is proven where (24 Oct 2026)

0.5.0 = 0.4.0 (XDS power/cadence, phone BLE link, Wi-Fi manager, coaching, history, journal recovery, ride screens
A/B/C) + power management from POWER_FEASIBILITY.md with Rashed's adjustments. Nothing of 0.4.0 was removed; the
whole 0.4.0 simulator scenario (sections 1–12) still passes unchanged, plus the new section 13.

**Status: simulator-tested only. Not installed on the Waveshare. Install needs Rashed's approval
(`pc-kit/INSTALL-v0.5.0.bat`, then `pc-kit/POWER-TEST-v0.5.0.txt`).**

## Where the code is

| Layer | File | Content |
|---|---|---|
| portable core | `components/bc_core/bc_power.{c,h}` | LiPo voltage → % estimate; USB-power inference; low-battery levels with 50 mV hysteresis; triple-tap detector; drain tracker (mV/h per mode, hours left) |
| app | `main/app/app_power.{c,h}` | state machine: screen on/off, lock, sleep, restart, alerts, auto timeout, auto sleep, cue wake, protection setting |
| ui | `main/ui/ui_power.c` | Quick Settings (top layer), screen-off/lock shield, toasts, Settings > Power page, Deep-sleep page |
| ui hooks | `ui_common.c` (timer + top-edge gesture + battery text), `ui_ride.c` (QUICK SET. button on the ride controls), `ui_settings.c` (Power row), `ui_tools.c` (Device Health lines), `ui_home.c` (`ui_power_init` at start) |
| platform | `main/app/plat.h` (+`plat_panel_sleep`, `plat_deep_sleep`, `plat_woke_from_sleep`, `plat_uptime_s`; `plat_backlight(0)` = off), `main/plat_esp.c`, `main/hw.c` (`hw_panel_sleep`, `hw_deep_sleep_touch_wake`, `hw_wake_tap_check`), `main/main.c` (STAGE 0 wake check), `test/sim/plat_host.c` |
| profile | `bc_profile`: new keys `scr_timeout_s` (60), `auto_sleep_min` (10), `bat_protect` (0), `wake_on_cue` (1). Old 0.4.0 profiles load with these defaults; the format stays key=value, unknown keys ignored |

## Features and their verification state

| # | Feature | Behaviour | Simulator | Hardware |
|---|---|---|---|---|
| 1 | Battery estimate | voltage measured (ADC, 3:1 divider, 16-sample average, 5 s filter); "~N %" from a 3.30–4.20 V curve; every display says `~` / `est.` | ✔ curve + labels (host tests, screens c0/c7/c8/c9) | not yet (ADC itself passed in 0.3.0/0.4.0 self-tests) |
| 2 | "USB power likely" | ≥ 4.18 V held 30 s, or +30 mV within 5 min; a clear drop ends it; the word "charging" is never used | ✔ (host + sim: 4.19 V 30 s → USB icon; slow discharge never triggers) | not yet |
| 3 | Quick Settings | swipe down from the top edge on any non-ride screen; in a ride: `QUICK SET.` button on the control panel (pause/resume/end unchanged and first); brightness slider, Wi-Fi, Phone link (sensor BLE untouched), Sensors, Battery row + detail, Touch lock, Screen off, Deep sleep (greyed while riding), HOLD: RESTART, Power settings; closes by swipe up, ^ button, 20 s without a touch | ✔ geometry (all widgets inside the circle), every row exercised | not yet |
| 4 | Brightness | 10–100 %, applied live, saved on release | ✔ | not yet |
| 5 | Screen off | backlight 0, panel SLPIN, widgets not redrawn; app tick, BLE, recording, coach, journal continue; wake = 3 taps within 1.5 s (1 or 2 taps ignored, a long press is not a tap) | ✔ (ride recorded 30 s in the dark: duration, power seconds and journal lines grew; single/double taps ignored) | not yet |
| 6 | Wake on coach warning | screen off in a ride + a WARN cue (NO SENSOR DATA, HR HIGH): screen on for 5 s, then dark again; setting `Wake on warning` | ✔ | not yet |
| 7 | Auto screen timeout | outside rides only, after onboarding: 30 s / 1 / 2 / 5 min / never (default 1 min); never inside a ride | ✔ (60 s, never, 30 s) | not yet |
| 8 | Touch lock | shield swallows every touch; unlock = 3 s hold on the centre button; locked screen is dimmed | ✔ (START RIDE does nothing while locked; short hold does not unlock) | not yet |
| 9 | Deep sleep | refused while a ride runs/paused; journal flushed, profile saved, Wi-Fi + phone radios off (settings kept), backlight 0, panel asleep, `esp_deep_sleep_start()` with ext0 on TP_INT (GPIO5 low), TP_RST (GPIO13) and backlight (GPIO2) held; label "Deep sleep (lowest power)" + recovery text | ✔ state machine, guards, radios, profile save, wake path (`boot()` with `woke_from_sleep`) | **NOT verified**: ext0 wake, GPIO holds, sleep current |
| 10 | Triple-tap wake from deep sleep | boot STAGE 0: if the wake cause is ext0, poll the CST816S ≤ 1.5 s; the wake touch counts as tap 1; < 3 taps → straight back to sleep (< 2 s awake); RESET and USB wakes skip the check | detector logic ✔ (host tests) | **NOT verified** — fallback RESET / USB always boots |
| 11 | Auto deep sleep | idle N min on battery, no ride, not while USB likely: off / 5 / 10 / 30 min (default 10) | ✔ (5 min → sleep; blocked while USB likely) | not yet |
| 12 | Low-battery alerts | toast at ~20 % (3.55 V), ~10 % (3.45 V), ~5 % (3.35 V), 50 mV hysteresis; journal flushed at every alert; **the ride is never paused or ended automatically** | ✔ (critical voltage during a ride: alert only, ride kept running, no sleep) | not yet (thresholds are for a lightly loaded cell; to be tuned with measured sag) |
| 13 | Protection opt-in | `Low batt.: auto-save` (default **off**, labelled NOT VALIDATED): at ~5 % in a ride → end + save + deep sleep 4 s later; outside a ride at 3.30 V → deep sleep | ✔ setting round-trip + label; action path not exercised by default | NOT validated (keep off) |
| 14 | Safe restart | HOLD 1.5 s in Quick Settings: journal flush + profile save + `esp_restart()`; an interrupted ride is recovered by the existing journal replay | ✔ | 0.4.0 restart/recovery verified; the new button not yet |
| 15 | Consumption log | mV/h per mode (idle screen on / ride screen on / ride screen off), hours left to 3.35 V after ≥ 20 min; USB periods ignored; Device Health shows it; one `POWER …` log line every 10 min | ✔ (host: 120 mV/h over 30 min → 3.75 h) | not yet — P19 of the test sheet |
| 16 | Device Health | Battery (estimate), Power source, Drain, Hours left, Screen offs/wakes/auto | ✔ | not yet |

Also in 0.5.0: buttons no longer scale on press (`style_btn`). The transform made LVGL draw the pressed row through a
32-bit layer (~28 KB); over the ride screen + Quick Settings the LVGL heap reached 93 %. Peak LVGL use is now 52 KB of
94 KB (was 72 KB in 0.4.0).

## Safety invariants (checked by test/sim section 13)
- No Quick Settings action pauses or ends a ride; HOLD: END on the ride controls is the only way (phone STOP still needs its confirm).
- Sleep is refused while a ride is running or paused (greyed row, `app_power_sleep()` returns false).
- Every power action flushes the journal first and writes one `POWER …` line to the serial log.
- Percentages carry `~` / `est.`; "USB power likely" is inferred; "charging" never appears (checked with `on_screen("harging")`).
- Low-battery actions beyond alerts exist only behind `bat_protect = 1`, default off, labelled NOT VALIDATED.
- Existing profiles, history and journal formats unchanged; new keys default when missing.

## Test results (24 Oct 2026)
- `test/host`: 1580 checks, 0 failures (was 1330) + xds 228; `make lint` OK (no %f in LVGL fmt).
- `test/sim make run`: 130 screens, 0 with issues; 186 functional checks, 0 failed (was 114 / 125). LVGL max 51 624 B of 93 928.
- `idf.py build` (ESP-IDF 5.5.1): OK. App 1 726 224 B (0x1a5710) in a 4 MB slot, bootloader/partition table/otadata byte-identical to 0.4.0.
- One deprecation warning (`esp_lcd_touch_get_coordinates` in `hw_wake_tap_check`), no errors.

## Install kit (`pc-kit/`)
`fw-v0.5.0/` BC050-app.bin `c7c9f047a2a78ad203012206fadd522c938e11f5bc3fc61cda6b68711a3a25b8`, bootloader `de894772…` (= 0.4.0),
partitions `812e16cc…` (= 0.4.0), otadata `7d2c7ac4…` (= 0.4.0), `SHA256SUMS.txt`.
`INSTALL-v0.5.0.bat/.ps1` (full 16 MB backup first; proves the backup holds 0.4.0 or 0.3.0 at 0x20000 by walking the
image and hashing it; asks YES; writes only 0xf000 + 0x20000), `ROLLBACK-TO-v040.bat/.ps1` (needs `fw-v0.4.0/`),
`RESTORE-BACKUP-BEFORE-v050.bat/.ps1`, `POWER-TEST-v0.5.0.txt` (P0–P20, one step at a time).

## Known limitations
1. Touch wake from deep sleep, GPIO hold behaviour, panel SLPIN/SLPOUT and the sleep current are untested on the board (HW-5). RESET and USB plug are the documented fallbacks; the Deep-sleep page says so.
2. The first ~300 ms after a wake the touch controller is polled without LVGL; if the CST816S needs a reset after the host's deep sleep the check reports "touch not reachable" and the board stays awake (fail-safe).
3. The percentage is a voltage estimate: under ride load it reads low, on USB it is meaningless (shown as USB).
4. Low-battery thresholds (3.55 / 3.45 / 3.35 V) are not tuned to this cell's sag; alerts only by default.
5. Hours-left needs ≥ 20 min of battery-only data per mode and resets on every boot (not persisted yet).
6. "Phone link off" in Quick Settings stops only the phone peripheral; sensor Bluetooth cannot be switched off separately (and should not be during a ride) — the row says so.
7. During screen-off the LVGL timers still run (only widget updates are skipped); a lighter light-sleep mode is not implemented yet.
8. Charging-current risk HW-1 is unchanged by firmware (see HW_RISK_REGISTER.md).
