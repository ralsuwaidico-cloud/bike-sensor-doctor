# Cyclift Watch — Stage 1 black screen: investigation (9 Nov 2026)

## What happened on the watch
* First installation of `cyclift-stage1-v3poc-T-Watch-2021-V1_1.bin` (SHA-256 `faa2828f…aead5cba7`): every write verified,
  checkpoints C1–C4 passed, post-install flash map correct.
* Stage 1 ran: serial banner after 565 ms, 2 MB PSRAM and 8 MB flash detected, LVGL frame loop running, no reset in 60 s.
* **Owner: screen completely black, no visible backlight even in a dark room.** During a 120 s hands-on window the serial log
  showed no key or touch events (the owner may not have pressed anything once the screen stayed dark).
* Recovery Level B (owner-approved) restored the factory first 4 MB: 4 sectors written in reverse order, each read back and
  verified; LILYGO firmware starts once, with its original settings (its boot counter advanced in the original area); factory
  table and selection restored; Cyclift program left in the upper flash.

## Offline comparison with the factory firmware (LILYGO `software/SmartWatch`, byte-identical to what the watch runs)
| # | Item | Factory firmware (works) | Stage 1 (black) | Finding |
|---|---|---|---|---|
| 1 | Power hold IO5 | `pinMode OUTPUT`, HIGH in `setupPower()` before the display | HIGH at the start of `setup()`, before the display | same |
| 1 | Backlight IO21 | LEDC channel 1, **12 kHz**, 8-bit, active-high (`displayOff` drives LOW); brightness from settings | `ledcAttach(21, 2 kHz, 8)`, duty 60 %, active-high | same polarity; only PWM frequency differs. Stage 1 runs with `CORE_DEBUG_LEVEL=2`, so a failed LEDC attach would normally print an `E` line — none appeared (evidence, not proof) |
| 2 | Other power signal before the backlight | none (only IO5) | none | no missing enable signal found in the factory code |
| 3 | GC9A01 init | Arduino_GFX `tftInit()` | TFT_eSPI 2.5.43 `GC9A01_Init.h` | **identical** 182-step command/data sequence (programmatic diff); reset pulse differs (factory 50/50/50 ms, TFT_eSPI 5/20 ms + 150 ms) — both long enough for the controller |
| 4 | SPI | HSPI, 40 MHz, mode 0, SCLK 14 / MOSI 13 / CS 15 / DC 19 / RST 27 | VSPI, 40 MHz, mode 0, same pins | pins identical; different SPI peripheral |
| 5 | TFT_eSPI on Arduino-ESP32 3.3.12 | — | direct SPI register access via `REG_SPI_BASE(VSPI=3)` | the widely reported register-base breakage is for ESP32-S3/C3; for the classic ESP32 the macro is **identical in ESP-IDF 4.4.1 and 5.5** (→ SPI3 0x3FF65000). **Not shown to be defective.** |
| 6 | Anything else on IO21 | — | nothing else configures IO21 (I²C on 26/25; no pin-less `Wire.begin()`) | no override found |
| 7 | "Frames drawn" | — | counts LVGL timer passes; each flush waits for the SPI peripheral to finish, so transfers do execute, but the panel has no read-back line (no MISO) | **does not prove pixels reached the panel** |

Key point: a *completely dark backlight* cannot be caused by panel initialisation or SPI data — the backlight is a separate LED
driver on IO21. So either IO21 is not actually driven high on this board by Stage 1, or the backlight supply is missing. The
code comparison does not show why, so it needs a measurement on the watch.

## Diagnostic firmware (built, NOT installed — needs separate approval)
`cyclift-display-diag-T-Watch-2021-V1_1.bin` (env `T-Watch-2021-V1_1-display-diag`, source `src/app/stage1_display_diag.cpp`):
1. T1 power hold IO5 HIGH (with read-back).
2. T2 backlight IO21 as a **plain digital pin**: HIGH 5 s, LOW 2 s, HIGH (read-back logged).
3. T3 backlight through LEDC at the factory's **12 kHz**: logs whether `ledcAttach`/`ledcWrite` succeed; duty 255 → 128 → 32 → 255.
4. T4 panel through **TFT_eSPI 2.5.43** (the Stage 1 driver): RED, GREEN, BLUE, 3 s each.
5. T5 panel through an **independent raw-SPI driver** on HSPI with the factory's reset timing and init sequence: WHITE,
   YELLOW, CYAN, 3 s each.
6. Repeats every 20 s, or immediately when a side key is pressed (so it can be watched without the PC).
Verbose core logging (`CORE_DEBUG_LEVEL=5`); no Bluetooth, Wi-Fi, sleep, touch or sensors; writes nothing to flash.

### How the result will be read
| Owner sees | Meaning |
|---|---|
| glow in T2 but not T3 | backlight works; the PWM setup is the fault |
| no glow in T2 or T3 | IO21 or the backlight supply on this board is not as documented → hardware/pin question |
| glow, R/G/B in T4 | TFT_eSPI works; Stage 1 black screen came from the backlight setup |
| glow, nothing in T4 but W/Y/C in T5 | TFT_eSPI/VSPI path is at fault on this framework; switch driver |
| glow, nothing in T4 or T5 | panel interface problem (reset/pins/supply) |

### Proposed hardware test (needs approval; same factory-preserving procedure, same four sectors, recovery identical)
Install the diagnostic file to app1 exactly as Stage 1 was (phases 1–4, verify after each write), run one serial session of
~2 minutes while the owner watches the screen and notes what he sees at each step, then Recovery Level B as already executed.

## Update 20:25 — owner saw the Cyclift interface on the watch, then black (timeline correlation)
| Time (Dubai) | Installer step | Watch state |
|---|---|---|
| 19:37:13–19:37:23 | pre-check: full read, then reset into normal start | factory app |
| 19:38:51 / 19:39:30 / 19:40:16 | C1 / C2 / C3 resets | factory app each time (boot counter evidence) |
| 19:40:48 | Phase 4 switch written (download mode) | — |
| 19:41:03 | C4: reset into normal start | **Cyclift running** (banner) |
| 19:42:11 | C4 re-check: reset | **Cyclift running** (banner, 565 ms first frame) |
| 19:42:34–19:43:34 | observe: reset, 60 s listening | **Cyclift running**; automatic 30 s performance line + one on request; one touch event logged ("swipe U") |
| 19:43:49–19:45:37 | post-install full read: `esptool read_flash` with `--before default_reset --after no_reset` | **chip held in the ROM download mode — no firmware running** |
| 19:46:14–19:48:14 | 120 s listening window (no reset) | **zero bytes received**, although Stage 1 prints a performance line every 30 s → confirms nothing was running |
| 19:52:57–19:55:15 | Recovery B; confirmation = reset (factory app started 19:54:18), then read-back + verify with `--after no_reset` | chip again left in the ROM download mode |

**Most likely cause of both black screens: the installer/recovery scripts finished with esptool commands that leave the chip in
its ROM download mode (`--after no_reset`).** In that mode no firmware runs, all pins return to their power-on default (IO21 not
driven → backlight off), and nothing is printed. Stage 1 itself drew its interface; Stage 1 contains no screen-off, dimming or sleep
code (only `begin()` sets the backlight, nothing changes it later). Expected confirmation: unplugging and re-plugging the watch (or
its reset button) starts the firmware normally. Process fix: every session must end with a reset into normal start.

Separate open item: touch. The CST816S answered at least once (one swipe event at 19:42–19:43), but the owner saw no response to
taps. Possible causes: taps landing where the current screen has no action, or unreliable reads from the touch controller. The
diagnostic build should log raw touch reads before any conclusion.
