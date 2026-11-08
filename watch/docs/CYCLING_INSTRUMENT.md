# Cycling instrument — Cockpit, Performance, Navigation (design v2, owner directives 8 Nov 15:31 + 16:07)

Host-rendered, round-display-checked redesign of the live cycling views. **Not hardware-tested**: nothing has been
flashed; every screenshot here is the host renderer drawing the same scene the device will draw with LVGL.

Code: `firmware/src/domain/ride_telemetry.hpp` (telemetry model, series, GPS mirror), `ride_screens.hpp` (the three
views), `buttons.hpp` (`TwoPress`). Tests: `firmware/test/host/test_domain.cpp` (cycling-instrument block) and the
gallery checks (744 scenes: 31 screens × 6 appearances × 4 text variants, 0 findings).

Screenshots: `ride-gallery-1.png` (three views × six appearances), `ride-gallery-2.png` (degraded states).

## Design principle (v2): one screen, one question

| Screen | Question | What is on it | What moved away |
|---|---|---|---|
| Cockpit | How am I performing right now? | status indicator · one dominant number + large unit · 270° orbital gauge (zone ladder, target band, position marker) · ≤ 2 secondary metrics · one command (≤ 16 chars) or interval countdown · one Pause pill | Lap / End → controls overlay + physical keys; coaching sentence → overlay "Why?"; distance/speed → secondary slot only when relevant |
| Performance | How has my effort changed? | one large chart per page (power · HR · cadence · target vs actual), current value + 30 s trend, axis min/max, target band + mid-line, "now", page dots | time-in-zone bar and averages text (→ summary) |
| Navigation | Where am I, and where do I go? | auto-scaled map dial, breadcrumb, route ahead, next-turn dot, N, scale bar, one state line | speed/heading/distance (shown only when no route is loaded) |

Controls overlay (tap the status line / swipe up / Key 2 preview): Lap · Pause/Resume · End ride (confirms) · the command's reason.

## Coaching commands (`ride::command`)

Priority: PHONE LOST (safety) → power vs the step band (EASE OFF / HOLD mid W / PUSH TO mid W; cadence outside its range while power is on target → CADENCE UP / DOWN) → heart rate vs the step zone (HR ABOVE TARGET / HOLD HR lo–hi / HR BELOW TARGET) → INTERVAL mm:ss → nothing (free ride). The command is computed from the same target that is printed above the number, so it can never contradict it; the explanation is one tap away.

## Status taxonomy (`ride::LinkState`, `ride::RouteState`)

PHONE LOST (link down) · NO GPS (phone linked, no source / no fix) · GPS STALE n s (last fix > 10 s) · GPS n s (live) — and separately: no route · on route · OFF ROUTE n m (> 50 m). Never merged into one warning.

## Gauge definitions

| Arc / element | Metric | Source | Min → max | Target | Current | Colour | Missing data | Update |
|---|---|---|---|---|---|---|---|---|
| Cockpit outer ring (270°) | zone ladder of the lead metric | power + FTP (7 zones) or HR + the athlete's HR zones | 0 → 1.5 × FTP; HR zone 1 low → zone 5 top | — | lit segment = current zone | lit segment in the grade colour, track = theme line | no FTP and no HR zones → plain track | 1 Hz |
| Cockpit inner arc | step target band | planned step | ring scale | the band | — | fixed light blue | no band → hidden | on step change |
| White dot | current lead value | lead sensor | ring scale | — | position | text colour | no fresh lead → hidden | 1 Hz |
| Bottom arc (140–220°) | interval progress | planned steps | 0 → 100 % | — | filled share | accent | free ride → hidden | 1 Hz |
| Number colour | grade of the lead vs band | grading.hpp | — | band ± 5 % | — | red / yellow / light blue / green; white with no target | never graded without a target | 1 Hz |
| Performance chart | power · HR · cadence | 1 Hz ring 300 s; 60 s / 10 s buckets for longer windows | rounded data range incl. target | band + mid-line | last sample dot; header = 3 s average | accent / accent2, never a grade colour | gap breaks the trace | 1 Hz |
| Navigation dial | position, trail, route ahead | phone GPS over BLE | auto 2–25 m/px | route line | marker (hollow when not live) | trail grey, route accent, off-route yellow | distinct states, no invented movement | per fix |

## Navigation states

A tracking without a route · B following a loaded route (route ahead, next turn, distance, off-route) · C disconnected / unavailable (last fix kept and timed, hollow marker, "reconnecting…", NO GPS SOURCE). Heading-up (position at 60 % down) or north-up. Auto-scale in 1-2-5 steps with a 50 / 100 / 200 / 500 m bar. All gallery coordinates are SIMULATED (`simPath()`); the watch never claims its own GPS or map tiles.

## Evidence

Gallery v2: `docs/gallery-v2.html` (published as "Cyclift Watch Gallery"), native 240 × 240 PNGs in `docs/native/`, measured text sizes in `docs/TEXT_SIZES.md`. 1 248 scenes (52 screens × 6 appearances × 4 text lengths), 0 findings; 172 host checks. Hardware-tested: **pending** (nothing flashed).

## Host tests

Gauge ranges and clamping · missing sensors · unknown FTP · series gaps, averages, buckets, bound · time in zone · GPS freshness / offline preservation / reconnect / duplicate rejection / trail bound · route progress, next turn, deviation, end-of-route · trail projection gaps · auto-scale and heading-up / north-up projection · command consistency (HOLD / EASE OFF / PUSH TO / CADENCE UP / HR ABOVE / INTERVAL / none / PHONE LOST, ≤ 16 chars) · link and route states and their labels · two-press preview / confirm / expiry / replacement / wake / disconnected · accidental double press · every ride view keeps an immediate Pause, paused views keep End, the overlay keeps Lap + End.
