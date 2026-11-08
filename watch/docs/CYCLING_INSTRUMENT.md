# Cycling instrument — Cockpit, Performance, Navigation (owner directive 8 Nov 15:31)

Host-rendered, round-display-checked redesign of the live cycling views. **Not hardware-tested**: nothing has been
flashed; every screenshot here is the host renderer drawing the same scene the device will draw with LVGL.

Code: `firmware/src/domain/ride_telemetry.hpp` (telemetry model, series, GPS mirror), `ride_screens.hpp` (the three
views), `buttons.hpp` (`TwoPress`). Tests: `firmware/test/host/test_domain.cpp` (cycling-instrument block) and the
gallery checks (744 scenes: 31 screens × 6 appearances × 4 text variants, 0 findings).

Screenshots: `ride-gallery-1.png` (three views × six appearances), `ride-gallery-2.png` (degraded states).

## A · Cockpit

Progressive disclosure: one lead metric, three small tiles, one interval line, one coach cue, two controls. Nothing is
decorative; every arc has a defined meaning and source.

| Element | Meaning | Source | When absent |
|---|---|---|---|
| Outer segmented ring | zone ladder of the lead metric (7 power zones when FTP is known; the athlete's HR zones otherwise); the current zone is lit in the grade colour | power meter / HR + FTP or HR zones from the phone | no ring when FTP is unknown and no HR zones |
| Inner arc | target band of the current step (power W) | planned ride step | no arc in a free ride or without a step target |
| Needle | current value on the −120…120° dial | the lead sensor | hidden when the lead is Time |
| Lower arc (150–210°) | share of the current interval completed | planned steps | hidden in a free ride |
| Lead metric | power (fresh ≤ 3 s) → heart rate (≤ 5 s) → GPS speed (≤ 5 s) → elapsed time | — | a stale reading is never promoted |
| Tiles | HR, cadence, speed, distance (whichever exist, max 3) | sensors / phone GPS mirror | a missing sensor leaves no tile |
| Status line | REC/PAUSED dot, elapsed, GPS age or "no GPS / phone lost / GPS stale" | recorder + GPS mirror | — |
| Cue | the one primary coach instruction (≤ 44 chars, 2 lines, 13 px) | phone coach (rule-based) or the watch's local rules, labelled | — |
| Controls | Lap + **Pause** (immediate, one tap); paused → Resume + **End** | — | always present |

Grading: fixed four-colour scheme (`theme_tokens.hpp`), identical across the six appearances; missing data and unknown
FTP are **never graded** (the gauge says "FTP unknown: no target, no zones"). Target vs actual = needle against the target
band; HR zone = position on the ladder.

## B · Performance (real-time graphs)

* Rolling power and heart-rate lines over a 1-min, 5-min or whole-ride window (`Series`, 1 Hz ring of 300 s; longer
  windows are downsampled into buckets — bounded memory for the ESP32).
* **Honest gaps:** a missing second is stored as a gap and breaks the line; averages use present samples only; a bucket
  with no samples is a gap. Nothing is interpolated or invented.
* Time-in-zone bar with the seconds "no reading" shown next to it; rolling 3 s / 30 s averages and the lap average
  (target vs actual via the step line "Interval 2 · 180–216 W · 3:20").
* No source → "no power / HR source" inside the panel, and the header names only the series that exist.

## C · GPS tracking (phone mirror)

The watch has no GPS. `GpsMirror` receives timestamped fixes from the iPhone over BLE and shows: a heading-up breadcrumb
of the last ~300 m around the position marker, speed/heading, GPS age, route progress, distance to the next turn and a
deviation warning (> 50 m). States: Searching / Live / Stale (> 10 s) / PhoneLost / NoSource, each with its own honest
text; the marker is hollow unless Live; animation is allowed only while Live. The trail is bounded (600 points, older
half thinned) while distance stays exact. **A disconnected phone creates no GPS points**: `onFix` refuses fixes while the
link is marked down and refuses a fix repeating the last phone timestamp; the last valid fix is kept with its time and
the trail continues from it on reconnect. Breadcrumbs that leave the dial radius become gaps, never rim artefacts. No
map tiles are drawn and the UI never claims the watch receives GPS itself.

## D · Visual language

Round-screen rules enforced by the layout engine and checks (`ROUND_LAYOUT.md`): measured text, minimum fonts (value 20,
body 13, label 11), max lines, More/paging instead of tiny text, 44 pt controls at y 160, 4.5:1 contrast, six appearances
on centralised tokens with fixed grading colours. Swipe left/right moves Cockpit ⇄ Performance ⇄ Navigation.

## E · Two-press action system

See `BUTTONS.md` → "Two-press action system".

## F · Host tests (all passing, 143 checks)

Gauge ranges and clamping · missing sensors (no gauge, lead falls through) · unknown FTP (no grade, explained) · graph
continuity (gaps stored, line breaks, averages ignore gaps, bounded ring, buckets) · time in zone · GPS freshness
(Searching → Live → Stale) · offline route preservation (last fix kept, no points while disconnected, reconnect resumes)
· duplicate-fix rejection · trail bound · route progress / next turn / deviation / end-of-route bounds · trail projection
gaps · round layout of every view in every state across all appearances · two-press preview / confirm / timeout /
replacement / wake / phone-lost · debouncing · every live view keeps an immediate Pause and a Lap/End control.

## Not yet done

Device rendering with LVGL fonts, real BLE telemetry, haptics and the physical keys are W1 device work and need a
factory-firmware backup plus the owner's flashing approval first.
