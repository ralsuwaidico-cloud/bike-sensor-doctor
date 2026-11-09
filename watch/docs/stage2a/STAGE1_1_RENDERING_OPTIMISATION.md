# Stage 1.1 — frame-time investigation and rendering optimisation (offline, 9 Nov 2026)

Scope (owner approval 22:48): offline source changes, builds, tests, documentation. No flashing, no hardware change.
The approved Stage 1 firmware `faa2828f…cba7` is archived unchanged in `watch/firmware/releases/stage1-approved/` (CI checks its
fingerprint on every run). The optimised firmware is a separate version: `cyclift-stage1.1-v3poc-T-Watch-2021-V1_1.bin`.

## Method
`watch/firmware/test/v3/perf_main.cpp` runs the watch's own frame loop (every 10 ms: model tick → UI render → LVGL timer;
LVGL refresh period 30 ms; 240 × 240 RGB565; 120-line draw buffer; same LVGL 8.3.11 and configuration) for scripted scenarios:
watch face, ride cockpit in three densities, navigation with both keys, pause/resume, each in English and Arabic.
For every frame that did work it records rebuild/update, pixels sent to the panel, and — under valgrind/callgrind — the
instructions executed, split into the UI step (rebuild or in-place update) and the LVGL draw step, with a per-function profile.
Instruction counts on the computer are a **proxy** for ESP32 CPU work. They are deterministic, so they are used for comparisons
and CI budgets; they are **not** watch frame times.

Calibration against the B2 watch logs: one factor (~45 ns of watch time per computer instruction, plus 0.4 µs per pixel of SPI
transfer at 40 MHz) reproduces the watch's measured averages within about 30 %: face ≈ 0.5 ms (watch 0.4 ms), ride cockpit
≈ 1.5 ms (watch 1.5–2.5 ms), Arabic ≈ 11–13 ms (watch 9–11 ms), cockpit update max ≈ 145 ms (watch 133–153 ms without rebuild).
That supports the explanation below; it does not replace a measurement on the watch.

## Causes of the frame-time spikes
| Observation on the watch (B2) | Cause | Status |
|---|---|---|
| ≈ 0.37 s frames, always in a 30 s window with `rebuilds > 0` | A **screen rebuild** (navigation, toast/banner appearing or going, pause/resume pending → confirmed) recreates every LVGL object and redraws the full screen (57,600 px) in the same loop pass: 4–6.5 M instructions on the computer, of which the UI rebuild itself 2–4 M | confirmed on the computer; share of watch time supported by the calibration |
| 0.13–0.15 s frames during a ride **without** rebuild | The **1 Hz cockpit update** redraws 16,500 px on average (22,056 max): power number, tiles, interval time, command line, gauge marker. 91 % of its cost is drawing; per function: ring arcs 40 %, labels 46 % (letter drawing, compressed-font decoding, bidi), background fill 22 %, **scroll-extent calculation 13.5 %** (objects were scrollable although nothing scrolls) | confirmed on the computer |
| Arabic: average frame 9–11 ms, ~55 frames/s instead of ~90 | **Bug:** in Arabic the screen redrew continuously (33 refreshes/s) even when nothing changed. The UI compared each new value with `lv_label_get_text()`, but LVGL stores Arabic text reshaped, so the comparison never matched and every 10 ms update rewrote the label | confirmed on the computer (deterministic); matches the watch's lower frame rate |
| Every frame | The screen-structure key was built with `snprintf` on every 10 ms frame (65 % of an idle frame) | confirmed on the computer |
| Code runs ~11 CPU cycles per computer instruction | Hypothesis: the watch reads flash in DIO 40 MHz mode (factory bootloader), so code fetched through the flash cache stalls | **unverified**; tested on the watch with the new frame-time report |

Rejected on evidence: LVGL circle-mask cache too small (raising it from 4 to 16 saved 1 %).
Test-harness artefact (corrected, not a watch problem): a first version of the stale-pixel check compared before pending
redraws were sent; with the check fixed, the installed Stage 1 shows 0 stale pictures too.

## Changes (Stage 1.1)
All in `src/ui/v3/cyv3_ui.*`, `lv_conf_v3.h`, `app/v3poc_main.cpp`, `hal/esp32/drivers.hpp`; design, layout, colours, fonts,
Arabic shaping, RTL, themes, navigation and density options unchanged.
1. **Arabic redraw fix** — the UI remembers the text it gave each label and compares with that.
2. **Static ring background** — the ring parts that never change during a ride (track, target band, zone ticks, interval track)
   are drawn once per theme by LVGL's own snapshot function into an opaque 240 × 240 image (115 KB in PSRAM on the watch) and
   placed as the cockpit background; the moving parts (interval progress, marker, numbers) stay live objects.
3. **No scroll work** — every UI object is marked non-scrollable (none scrolls).
4. **Ring arcs skip interior redraws** — the interval arc does not draw areas wholly inside its inner edge.
5. **Plain text by reference** — text without Arabic letters is given to LVGL by reference, so LVGL skips its Arabic-shaping scan
   of every character (Arabic text and dot-truncated labels still get a private, shaped copy).
6. **Integer structure key** instead of `snprintf` on every frame.
7. **LVGL 8.3.11 defect avoided** — `lv_img`'s cover check reads its event parameter as an area (uninitialised bytes under
   memcheck); the ring image answers the cover check itself.
8. **Device only:** LVGL's per-pixel routines in internal instruction RAM (`LV_ATTRIBUTE_FAST_MEM IRAM_ATTR`) — effect unmeasured.
9. **Instrumentation:** each frame is split into input, model, UI, LVGL draw and SPI flush (timed inside the display driver);
   serial `h` prints a histogram and P50/P95/P99/max per frame kind (idle / update / rebuild), `z` resets it. `u` unchanged.
   Boot banner: `Cyclift v3 proof of concept · Stage 1.1 (rendering optimisation) · …` (the install scripts' marker is kept).

## Before → after (computer instructions per frame, millions; callgrind)
| Scenario / frame kind | frames (before / after) | average | P95 | P99 | max |
|---|---|---|---|---|---|
| cockpit standard EN / 1 Hz update | 119 / 119 | 1.85 → 1.03 | 2.26 → 1.31 | 2.79 → 1.59 | 2.99 → 1.72 |
| cockpit focused EN / update | 121 / 121 | 1.28 → 0.71 | 1.72 → 0.98 | 1.96 → 1.08 | 2.10 → 1.18 |
| cockpit standard AR / update | 298* / 119 | (33 redraws/s) → 1.05 | 1.02 → 1.42 | 1.94 → 1.65 | 2.53 → 1.76 |
| cockpit standard EN / rebuild (incl. first ring snapshot) | 2 / 2 | 5.61 → 4.67 | — | — | 5.77 → 5.14 |
| navigation EN / rebuild | 23 / 23 | 3.91 → 3.33 | 5.80 → 4.92 | 5.81 → 4.92 | 5.81 → 4.92 |
| navigation AR / rebuild | 23 / 23 | 4.32 → 3.82 | 6.21 → 5.54 | — | 6.22 → 5.54 |
| pause/resume EN / rebuild | 8 / 8 | 4.87 → 3.72 | 5.83 → 4.28 | — | 5.83 → 4.30 |
| pause/resume AR / rebuild | 8 / 8 | 5.05 → 4.30 | 6.47 → 4.99 | — | 6.50 → 5.07 |
\* first 300 of ~4,000 redraws recorded. Total work over a steady 2-minute ride on the computer: Arabic −97 %, English −34 %.
Redrawn area per update unchanged (the same pixels change).

**Estimated** watch frame times with the calibration (not measured): 1 Hz cockpit update max ≈ 145 ms → ≈ 86 ms; screen
rebuild ≈ 280 ms → ≈ 225 ms; Arabic average ≈ 10 ms → ≈ 1–2 ms. The IRAM change (8) is not in these estimates.

## Targets
| Measure | Target on the watch (to be measured with `h`) | Computer budget in CI |
|---|---|---|
| 1 Hz cockpit update | P99 ≤ 100 ms (ideal ≤ 50 ms): value changes stay smooth and button/touch latency ≤ 0.1 s | ≤ 2.0 M instructions/frame |
| Screen change (rebuild + full redraw) | ≤ 300 ms; never > 400 ms | ≤ 5.5 M (cockpit, pause), ≤ 6.0 M (navigation) |
| Idle frame | ≤ 2 ms | ≤ 20 k instructions |
| Redraws during a steady ride | 1 per second in every language | ≤ 1.1 per second |
| Correct output | no stale pixels, no ghosting, identical design | 132 states byte-identical to the approved Stage 1 rendering; partial updates = full redraw (1,066 checks) |

## Regression results (computer)
* 132 rendered states byte-identical to the approved Stage 1 rendering (SHA-256 list `test/v3/render_reference_sha256.txt`),
  21,739 layout checks, 0 findings; model tests 1,484 checks, 0 failures.
* Partial-update check: 1,066 pictures built from partial updates compared with a full redraw of the same state — 0 differ.
* memcheck (valgrind): 0 errors in the rendering tests and the long scenario run.
* The CI checks fail on the old code (Arabic 33.3 redraws/s; budgets exceeded in 5 groups) and pass on Stage 1.1.

## Reproducible builds
Cause (found earlier): the Arduino core's start-up report prints `__DATE__`/`__TIME__`, which also changes the ELF hash stored in
the image (36 bytes). Fix: fixed `__DATE__`/`__TIME__` for all sources (`platformio.ini`, `[v3poc]`). CI job
`reproducible-build` makes two clean builds and compares them with each other and with the published candidate
(`tools/v3/image_diff.py` lists differing bytes by segment if they ever differ). Toolchain and libraries stay pinned
(`check_versions.py`).

## Not done / open
* Watch frame times, the IRAM effect and SPI flush time are unmeasured until a hardware test is approved.
* Rebuilds still recreate all objects (2–4 M instructions); keeping screens alive between visits would cut this further but
  costs memory and was not needed to keep the design unchanged.
* The redrawn area per update is unchanged (the power number's label box is 146 × 76 px).

## Candidate (CI run 42682987729, commit 8eaebe6) — NOT flashed
| File | SHA-256 | Size |
|---|---|---|
| `cyclift-stage1.1-v3poc-T-Watch-2021-V1_1.bin` (branch `firmware/stage1-candidates`) | `3274b8877df0a23a5e5cb1364868322d79d643d29411b36782b6bfb34eb937ba` | 1,009,632 B |
* Two clean CI builds and the published file are byte-identical (job `reproducible-build`). The start-up report now reads
  `Jan 01 2026 00:00:00`. Header DIO / 40 MHz / 8 MB. Flash use 990,115 B of the 3 MB slot; static RAM 107,248 B.
* Instruction RAM `.iram0.text` 122,511 B (LVGL drawing routines moved there): about 8 KB left — watch this before adding code.
* Emulator (QEMU, display not emulated): starts once from app1 with the installed 8 MB bootloader and runs 40 s without a
  restart, as Stage 1 did.
* The approved Stage 1 file stays `faa2828f…` in `releases/stage1-approved/` (CI fingerprint check passed).
