# Firmware 0.6.0 — Connections, connected standby, Quick Settings handle, Wi-Fi page, phone services, touch-to-wake + hold-to-start (25 Oct 2026, rev 3)

App image: `pc-kit/fw-v0.6.0/BC060-app.bin` sha256 2cccc1fe893493194dbbf5471dd4e05f99b0292ca936c66eabd3c9b5e94f9a00 (1 768 000 B / 0x1afa40). The Settings footer and Device Health show the build stamp (`Oct 25 hh:mm #xxxxxxxx`) so the running build can be confirmed on the glass.

Built on 0.5.0. Everything 0.4.0/0.5.0 did is kept (XDS power/cadence, phone link, Wi-Fi, coaching, history, recording,
screens A/B/C, Quick Settings, screen off, touch lock, battery estimate + alerts, deep sleep, safe restart). Profiles and
ride history from 0.4.0/0.5.0 load unchanged (new keys take defaults; one deliberate migration, see root cause 1).

**Status: simulator-tested only.** Nothing below is hardware-verified until Rashed runs `pc-kit/TEST-v0.6.0.txt`.

## Root causes found for Rashed's 0.5.0 findings

### 1. "When the screen goes off, the phone connection disappears; only a triple tap brings it back"
Two defects, both fixed:
1. **The phone link never advertised after a boot.** `plat_phone_set_enabled(true)` was only called by the Settings › Phone
   and Quick Settings toggles — never at start-up. After every restart or deep-sleep wake the board was invisible to the phone
   until the rider toggled the link off and on (which is what "fiddling with the screen until it reconnects" did).
   Fix: `app_init()` enables the link from the saved profile (`phone_on`, default on) on every boot.
2. **Auto deep sleep defaulted to 10 idle minutes** and judged "on battery" from the voltage. With the battery unplugged the
   charger output can sit anywhere between 4.1 and 4.2 V, so "USB power likely" (≥ 4.18 V for 30 s) is unreliable; after
   10 idle minutes the board went to deep sleep, which switches Bluetooth off — and the defect above kept it off after the wake.
   Fix: auto deep sleep is **off by default** (profiles written by 0.5.0 are migrated to off once, key `pwr_v`), and when
   enabled it never fires during a ride, while a phone is connected, or while USB power is likely; the reason is shown.

Screen-off itself never touched Bluetooth in 0.5.0 (no code path), but the two defects above produced exactly that
experience. 0.6.0 adds the states Rashed asked for and the simulator proves them (scenario 14):

| state | display | phone link | sensors | recording |
|---|---|---|---|---|
| Active | on | on | on | yes |
| Display off | off | on, unchanged | on | continues |
| Connected standby (screen off, no ride) | off | on; advertising every ~1 s when no phone is connected; reconnects without any touch | no scanning (connections kept) | — |
| Deep sleep | off | **off** (explained on its page as "connectivity off") | off | never while a ride runs |

Quick Settings gained a **State** row, explicit **Phone link on/off**, and **Deep sleep — link off** with the explanation.

### 2. "Triple-tap wake is unreliable; I often tap many times"
Analysis of the CST816S + the 0.5.0 detector:
- The controller **auto-sleeps 2 s after the last touch**. From its sleep the first touch only wakes the controller and is not
  reported, so the rider's first tap was lost every time → "three taps" needed four or more.
  Fix: while the screen is off the controller is kept awake (`DisAutoSleep` 0xFE = 1) and polled every 15 ms instead of
  30 ms. Cost: about 1.5 mA extra only while the screen is off (datasheet active current), accepted. Before deep sleep the
  auto-sleep is restored so a touch raises INT and wakes the chip.
- The window was 1.5 s from the first tap, and a slightly long press or a slide reset the count.
  Fix: 2.5 s window from the first tap, press 20–400 ms, gap 60–900 ms, taps anywhere on the glass, slides > 15 px ignored,
  vibration guard (> 6 presses/s locks the detector for 1 s, a press < 60 ms after a complete gesture is bounce), an extra
  human tap after a complete gesture fires it instead of cancelling it (3 taps when 2 are set still wakes).
- Deep-sleep wake: the chip needs ~200–300 ms to boot after the waking touch; the 0.5.0 check then wanted two more taps within
  1.5 s **of the boot**, so taps made during the boot were lost. Fix: the waking touch is tap 1 (a finger still on the glass is
  that same touch), the remaining taps may follow within 2.5 s, press ≤ 450 ms, any position; the rider's setting (2 or 3 taps)
  is kept in RTC memory across the sleep; a hold or a timeout puts the board back to sleep in < 200 ms.
- **Settings › Power › Wake gesture**: 3 taps (default) / 2 taps / any touch (rides only; idle still needs 2 taps so a bag
  cannot wake it). Also settable from the phone (SETTINGS tag 04).
- RESET and USB plug-in remain the dependable wake from deep sleep and are written on the Deep-sleep page.

Hardware trials required before any claim (TEST-v0.6.0.txt P5–P7): 20 screen-off wakes, 20 deep-sleep wakes, 10 accidental
touch trials; target ≥ 19/20 and 0 false wakes. If deep-sleep touch wake stays unreliable on the device, the documented
alternative is RESET/USB and connected standby instead of deep sleep.

### 3. "The pull-down menu is hard to open"
A visible **handle** (44 × 6 px pill, 60 × 28 px touch target) sits at the top of every non-ride screen; tap it or swipe down
from it or from the top 48 px. Opening/closing animates (150 ms); close by swipe-up, the arrow button, or 20 s timeout.
The gesture is consumed by the handle and never reaches the screen below. Ride screens keep their own handle (72 × 20 px),
which opens the ride controls first; those carry the Quick Settings button, so pause/end always win over settings. The
simulator checks on every screenshot that neither handle covers any label or control (design B's status row sits at y = 24,
the ride handle now ends at y = 23). Ring-keyboard screens (name, Wi-Fi password) hide the handle because their top key sits there.

### 4. Wi-Fi
See `WIFI_0.6.0.md`: full Wi-Fi page from Quick Settings (tap; hold toggles), network list with signal bars / open / saved,
network detail (connect, new password, hold to forget, back), connecting screen with Cancel and plain results (CONNECTED +
internet check, WRONG PASSWORD, NOT FOUND with the hotspot hint), UTF-8 names shown with a plain apostrophe, longer scan dwell
on channels 1–13, WPA2+PMF threshold for iPhone hotspots, DNS internet check, reconnection backoff that stops after 10 rounds,
and provisioning from the phone over the encrypted link (primary path; the ring keyboard is the fallback).

### 5. Protocol v1.2 (`docs/BLE_LINK_PROTOCOL.md`, `/docs/LINK_V1_2_SPEC.md`)
Ride-history sync (cap 0x40), Wi-Fi provisioning (0x80), athlete profile sync (0x100, phone-authoritative, versioned, never
touches history/pairings/bonds/Wi-Fi), device settings (0x200, with supported mask), INFO tag 07 device id. Writes arrive on
Control/Sync, are queued by the BLE task and applied by the app task (`main/app/app_psvc.c`, shared with the simulator);
replies go out at up to 32 notifications/s. Byte vectors are in the protocol document and asserted by `test/host`.

### 6. "The Home screen still says Sensors" → the Connections system (rev 2)
`Sensors` is gone. Home has a **Connections** row with a live summary (`N on`, red `! M` for set-up connections that are
missing); Settings and Quick Settings carry the same row. `main/ui/ui_conn.c` is a category menu with one detail page each:

| category | what it shows | direct / via phone / cloud | actions |
|---|---|---|---|
| Phone | pairing code flow, state, signal, last data age, battery of phone/watch, what is relayed (GPS, time, watch HR), profile source, troubleshooting | VIA PHONE link itself | RECONNECT, Phone link on/off, HR preference, HOLD: FORGET |
| Wi-Fi | the full Wi-Fi page (on/off, scan, nearby, saved, hotspot note, signal, forget) | — | as the Wi-Fi page |
| Power meter | XDS/Branta: state, signal, last data, measurements (W, rpm), packets/bad, **power accuracy unverified** label, **calibration not available** (this firmware never writes the meter's control point 0x2A55 — safety rule) | DIRECT | PAIR / PAIR ANOTHER, RECONNECT, HOLD: FORGET, SENSOR TEST |
| Heart rate | strap (DIRECT), watch/phone (VIA PHONE), WHOOP (CLOUD, **unsupported — planned**), current source + preference | mixed, tagged | PAIR HR STRAP, RECONNECT, HOLD: FORGET, HR: STRAP/WATCH FIRST |
| Cadence | cadence from the power meter, or from a paired BLE speed/cadence sensor (0x1816) | DIRECT | PAIR SENSOR, RECONNECT, HOLD: FORGET |
| Speed | wheel sensor (DIRECT, same CSC sensor) first, phone GPS (VIA PHONE) as fallback; wheel circumference editor (default 2096 mm) | mixed, tagged | PAIR SENSOR, RECONNECT, HOLD: FORGET, −10 / +10 mm |
| Other Bluetooth | discovery list of nearby advertisers with name, RSSI and recognised services (PWR 0x1818/0x1828, HR 0x180D, CSC 0x1816, TRAINER 0x1826); green = compatible. Lists only — never pairs | — | — |
| Device sync | athlete profile (device-only / phone-synced, version, last applied), settings version, ride transfer (rides on the device, sent this session), last successful sync | VIA PHONE | — |

Badge rules (unit-tested in scenario 16): red `!` only for a paired meter/strap/CSC sensor or a remembered phone that is
missing right now, and for a saved Wi-Fi network that fails with a wrong password; never for a device that was never set up.
States everywhere: CONNECTED / CONNECTING / DISCONNECTED − searching / NOT PAIRED / DISABLED / UNSUPPORTED.

**New in rev 2 — BLE speed/cadence sensors (CSC, service 0x1816, characteristic 0x2A5B)** are supported directly: a third link
in `ble_central.c` (same safety rule: the only write is the CCCD subscription), decoder `bc_csc.c` (crank → rpm, wheel →
km/h from the circumference, 0 after 3 s without an event, NO DATA after 4 s without a packet, nothing extrapolated).
Cadence from the meter wins; a wheel sensor beats the phone's GPS for speed/distance (`dist_src` = CSC SENSOR, source id 10).
The profile stores `csc.*` and `wheel_mm`; old profiles load unchanged. The phone app sees source id 10 in LIVE/history
(`bc_src_t` BC_SRC_BLE_CSC) — the iOS app must map it (shown as "unknown" until then).

### 7. Charging notifications → see `CHARGE_ALERTS.md`
Decision: **unavailable** on this hardware (no USB/charge sensing, no buzzer, voltage-estimated percentage, HW-1 open).
Settings › Power and Device Health say so. A phone EVENT (battery notice, estimate-labelled) is implemented behind a profile
flag that defaults to off and has no menu toggle until HW-1 is resolved.

### 8. "Triple tap often fails, and the taps sometimes START a ride" → any-touch wake with a swallowed gesture (rev 3)
Rashed's 0.5.0 observation on the board had two parts: wakes needed repeated taps (root cause 2 above), and the taps that
finally woke the screen landed on START RIDE and began a ride. Rev 3 changes the model instead of tuning the detector:
- **Any touch wakes** (default; `wake_taps = 1`, migrated once for 0.5.0/rev-1/rev-2 profiles). A tap, a swipe, a palm —
  the first contact turns the display on at once (backlight fade-in 0 → set level in 150 ms, so the rider sees the wake).
- **The waking gesture is swallowed.** `bc_gate_t` (bc_core) sits between the touch controller and LVGL: on the device the
  port's indev read callback is wrapped (`hw_touch_set_filter` → `app_power_touch_filter`), in the simulator the harness
  read callback calls the same function. While the screen is off nothing reaches LVGL; from the waking contact until every
  finger lifts nothing reaches LVGL; then a **400 ms guard** (`BC_GATE_GUARD_MS`) ignores touches too, and a finger that
  lands inside the guard and stays past its end is swallowed until it lifts. So a wake can never press START RIDE or any
  other control — proven in scenario 17 with a 3 s press on the START RIDE spot and 20 random wake touches.
- 2-tap and 3-tap wakes remain selectable (Settings › Power › Wake gesture) for riders who want fewer accidental wakes
  in a bag; they go through the same swallow + guard. An accidental any-touch wake costs screen time only (auto timeout).
- Deep sleep: ext0 wake needs the configured taps (1 = the waking touch alone); after the boot the gate starts in the
  swallow state, so the finger still on the glass or a tap during the ~1 s boot logo presses nothing. RESET and USB stay
  the documented fallbacks; the deep-sleep page explains all three.
- Why this is reliable on the CST816S: the controller is kept awake while the screen is off (rev 1) so the first contact is
  reported; any-touch needs no timing at all, only *one* reported contact; the swallow depends only on the release, which
  the controller reports when the finger leaves. The remaining unknowns are hardware-only: INT/poll latency of the real
  controller after `DisAutoSleep`, and the deep-sleep boot path (TEST-v0.6.0 1-5 and 3-2, 20 trials each).

### 9. "A tap must not start a ride" → hold-to-confirm everywhere (rev 3)
`bc_hold_t` (bc_core) drives one reusable component, `ui_hold_btn`: press and keep still for the hold time, the pill fills
from the left, the action fires **exactly once**; releasing early or sliding more than 20 px cancels (START RIDE then shows
"hold 1 s to start"); 1.5 s cool-down against bounce/duplicates; a touch that was part of a wake gesture or guard never
counts (it never reaches the button); when a hold fires the rest of that touch is swallowed + guarded, so the finger that
is still on the glass presses nothing on the screen that appears (results page, Home). Hold times: START RIDE 1000 ms →
"RECORDING STARTED" toast + ride screen; HOLD: END 1000 ms (was 2000); PAUSE 1000; delete / forget / restart / deep sleep
1500; unlock 3000. The phone's remote START (BLE control) is unaffected. `app_ride_start` refuses a second start while a
ride runs. Scenario 17: 5 quick taps start nothing; 0.6 s hold starts nothing; slide cancels; one hold starts one ride;
END + lingering finger changes nothing on the results screen; save once.

### 10. Swipe-down from the top zone did not work beside the handle (found by the new sim check, rev 3)
LVGL creates a screen without `LV_OBJ_FLAG_PRESS_LOCK`, so while a finger swiped down from the top zone the pressed object
was re-searched on every read and jumped to whatever control the finger crossed, which then received the press and the
gesture instead of the screen. `ui_power_attach_screen` now gives every screen PRESS_LOCK: the gesture reaches the screen
and a swipe never presses a control it crosses. Scenario 13 now swipes from x = 60, y = 40 (off the handle) and expects
Quick Settings.

## Simulator and host tests
- `test/sim`: 162 screens, 0 issues (handle coverage; rev 3 adds WORDS: no screen shows 'Sensors', Home shows 'Connections'); 345 functional checks, 0 failed.
  New in rev 3: scenario 17 (wake swallow on the START RIDE spot incl. a 1.5 s and a 3 s press, guard, 20 wake touches at
  random places during a ride, 5 plain taps / 0.6 s hold / slide never start, one hold = one ride + toast, lingering finger
  after END presses nothing, save once); scenarios 13/14 rewritten for any-touch default + 2/3-tap variants + swipe wake;
  top-zone swipe beside the handle.
  New in rev 2: scenario 16 (Home Connections row and badge counts; every category opens and returns; Phone/Wi-Fi pages
  return to the menu; `!` rules for a missing paired meter vs a never-paired one; pairing a CSC sensor from Cadence, live
  rpm + speed from it, wheel circumference editor, a ride recording distance from the wheel sensor, pairing kept across a
  restart, `!` when the sensor is away, troubleshooting text, forget; Other Bluetooth discovery with service tags and no
  pairing; Device sync page; Settings / Quick Settings rows; the Charging-alerts row).
  New scenarios: 14 connectivity (10 simulated minutes dark with the live stream flowing, standby + reconnect without touch,
  ride in the dark keeps meter + phone + journal, deep sleep explained and explicit, wake gestures 3/2/any), 15 phone services
  (status, scan incl. UTF-8 name and 5 GHz exclusion, wrong/right password, no-internet, forget, busy during a ride, sync in
  batches with paging, transport back-pressure, disconnect mid-sync, profile get/set/older/partial, restart keeps the synced
  profile, settings get/set/older, phone-link-off ordering).
- `test/host`: 1799 checks, 0 failures (wake gate + hold timing vectors, profile rev-3 migration, tap detector vectors, profile migration, codec vectors for every 1.1/1.2 message, CSC decoder + rates + wrap, EVENT codec, profile keys for CSC/wheel/chg_notice).
- LVGL heap peak 56 200 B of 93 832 (60 %; 0.5.0: 51 624).

## Not hardware-verified (explicit)
Everything in this release, in particular: any-touch wake latency and the swallow/guard on the real CST816S (20 trials);
the hold-to-start feel at the real 30 ms poll; Bluetooth staying up with the screen off on the real NimBLE stack; the 1 s
advertising interval and reconnection without touch; CST816S register writes (DisAutoSleep) and the 15 ms poll; deep-sleep
wake tap check; hotspot discovery and association; DNS check timing; the sync/provisioning/profile messages against the
real iPhone app; power draw in standby and screen-off; a real CSC sensor (crank/wheel) on the third link; the generic
discovery list on the real radio. The battery charging-current risk (HW-1) is unchanged by firmware.

## Behavioural changes vs 0.5.0
- Home: the bottom row is **Connections** (summary badge), History, Settings; the old Sensors page is replaced by the
  Connections menu (reachable from Home, Settings and Quick Settings). Pairing screens return to the matching category.
- Ride screen page 4 is titled CONNECTIONS. Device Health lists the speed/cadence sensor and the charging line.
- Auto deep sleep: default off (was 10 min); existing profiles migrated once.
- Quick Settings: handle; Wi-Fi row tap opens the page (hold toggles); State row; "Deep sleep — link off".
- Screen-off row shows the configured wake gesture; Power settings gained "Wake gesture" (any touch / 2 taps / 3 taps; default any touch).
- START RIDE, HOLD: END and every destructive action are 1 s (or longer) holds with a filling pill; a plain tap only hints.
- A wake touch, and the rest of a touch after a hold fires, never reach a control (400 ms guard).
- Settings footer shows the build stamp; toasts are 156 px wide at y = 34.
- Wi-Fi networks: a saved or open network opens a detail page before connecting (one extra tap, gives Forget/Back).
- Reconnection to a lost saved network gives up after 10 rounds until the rider rescans.
