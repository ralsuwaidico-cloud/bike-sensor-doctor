# Firmware 0.6.0 — connected standby, Quick Settings handle, Wi-Fi page, phone services (25 Oct 2026)

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

## Simulator and host tests
- `test/sim`: 138 screens, 0 issues (including the new handle-coverage check); 263 functional checks, 0 failed.
  New scenarios: 14 connectivity (10 simulated minutes dark with the live stream flowing, standby + reconnect without touch,
  ride in the dark keeps meter + phone + journal, deep sleep explained and explicit, wake gestures 3/2/any), 15 phone services
  (status, scan incl. UTF-8 name and 5 GHz exclusion, wrong/right password, no-internet, forget, busy during a ride, sync in
  batches with paging, transport back-pressure, disconnect mid-sync, profile get/set/older/partial, restart keeps the synced
  profile, settings get/set/older, phone-link-off ordering).
- `test/host`: 1649 checks, 0 failures (tap detector vectors, profile migration, codec vectors for every 1.1/1.2 message).
- LVGL heap peak 52 984 B of 93 840 (0.5.0: 51 624).

## Not hardware-verified (explicit)
Everything in this release, in particular: Bluetooth staying up with the screen off on the real NimBLE stack; the 1 s
advertising interval and reconnection without touch; CST816S register writes (DisAutoSleep) and the 15 ms poll; deep-sleep
wake tap check; hotspot discovery and association; DNS check timing; the sync/provisioning/profile messages against the
real iPhone app; power draw in standby and screen-off. The battery charging-current risk (HW-1) is unchanged by firmware.

## Behavioural changes vs 0.5.0
- Auto deep sleep: default off (was 10 min); existing profiles migrated once.
- Quick Settings: handle; Wi-Fi row tap opens the page (hold toggles); State row; "Deep sleep — link off".
- Screen-off row shows the configured wake gesture; Power settings gained "Wake gesture".
- Wi-Fi networks: a saved or open network opens a detail page before connecting (one extra tap, gives Forget/Back).
- Reconnection to a lost saved network gives up after 10 rounds until the rider rescans.
