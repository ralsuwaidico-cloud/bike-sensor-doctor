# Stage 1.4 RC1 — button system (offline candidate, 12 Nov 2026) — design APPROVED 16:37; install NOT approved

Status: **built and tested on the computer only. Not installed. Nothing flashed.** The watch still runs Stage 1.3 RC1
(4ea0ea90…). Installing needs the owner's separate approval naming the fingerprint below.

Basis: the owner's decisions of 12 Nov 2026 12:59 (G1–G11, "BUTTON DESIGN DECISIONS AND IMPLEMENTATION"). Contains all of
RC2 (clock fix D6, charge-pin debounce, reset reason, rebuild-cause log). RC2 (82500ce2…) is preserved unchanged in
`releases/stage1.3-rc2-candidate/` and was never installed.

| | |
|---|---|
| Candidate name | `cyclift-stage1.4-rc1-v3poc-T-Watch-2021-V1_1.bin` |
| Fingerprint | `f995c5383e60a3331fdc0a0f8aebeefc96f9ec791caceb655b01219dd0d2a076` (1,253,264 B; §8) |
| Boot banner | `Cyclift v3 proof of concept · Stage 1.4 RC1 (button system; …)` |
| Install method (when approved) | the reviewed app1-only update (`cy_update_s14.py`, same structure as the RC1 update): one write at 0x400000, no bootloader / partition / OTA-record / factory change; rollback = installed RC1 |

## 1. What the buttons do (approved model)

| Button | Short press | Hold 1 s | Notes |
|---|---|---|---|
| L1 (left upper, GPIO35) | **Select**: the screen's main action; in a ride: Controls with Pause/Resume highlighted, a second L1 confirms | Quick Settings (outside a ride); in a ride a 2 s hold = End request | never the restart alone |
| L2 (left lower, GPIO34) | **Back**; on a ride page: two presses within 2.5 s = Lap | Home (or back to the ride) | |
| R2 (right lower, GPIO0 Boot) | **Next**: next page / row / widget | touch lock on / off | only harmless actions (G3) |
| R1 (right upper) | hardware reset | — | firmware cannot see or remap it |
| L1 + L2 held 10 s | software restart: countdown from 2 s, release = cancel; in a ride a warning screen asks first | | restart only after all buttons are released |

The touch lock blocks only the touchscreen; every button keeps working (G4). In a ride the lock chip takes the place of
the Pause button (that button cannot be tapped while locked). Full per-screen table: `docs/buttons/BUTTON_SCREEN_MATRIX.md`.

## 2. What changed in the firmware

- `cyv3_keys.hpp` (new): button decoder — 30 ms debounce, short press on release, 1 s hold, L1 2 s End request, L1 + L2
  combination (second key within 1 s, 10 s hold, cancel on release, nothing leaks afterwards). R2 is independent.
- `cyv3_input.hpp` (new): the one path from decoded buttons to the screen logic. The watch loop and the computer tests use the
  same code. The restart is executed only when no button is held (a held R2 = GPIO0 at reset would start download mode).
- Screen logic (`cyv3_model.hpp`): Controls, End confirmation, restart warning, Power / Heart-rate / Cadence pages (Bike
  mode: cockpit + Power), highlight that follows R2 and is kept in view on long lists, ride average power, End command
  with "Ride ended · iPhone keeps the record" / "Unable to end".
- Screens (`cyv3_ui.cpp`): the prototype's Controls (wk-ctl) and End confirmation (wk-end), the chart pages (prototype
  chartPage: band, dashed target line, 90 s line, 3 s / 10 s / Avg), the End ring, the restart countdown, the highlight.
- Watch loop (`v3poc_main.cpp`): every decoded button event is printed (`key: L1 short (120 ms)`), which is also the
  evidence for the G1 identification check. Restart reason kept in RTC memory, printed at the next start
  (`restart cause: user restart (L1 + L2 held 10 s)`).
- Serial console: `m` L1, `b` L2, `N` R2, `k` touch lock (as holding R2).
- **Fix found by the new tests (not a button feature):** Arabic marks that sit just below the text line (e.g. the hamza
  under إ in "إيقاف مؤقت") could be erased by a partial screen update right below them and come back only at the next full
  redraw. Cause: LVGL draws updates in horizontal strips and skips a label whose line box ends above the strip. The label now
  draws itself in that case. Single-line Arabic labels are covered; multi-line Arabic paragraphs are not (no case found).

## 3. Design choices made during implementation (approved by the owner 12 Nov 16:37, with the new wording)

| # | Choice | Why |
|---|---|---|
| D1 | The highlight is always visible on lists (Menu, Quick Settings, Controls, confirmations); the menu outside a ride now opens with "Watch Face" highlighted | G9; a button user must always see where L1 will act. Six approved reference pictures (menu, all densities, EN/AR) changed only by this border |
| D2 | Buttons are highlighted with a 2 px accent **outline** 2 px outside the button; rows with the approved 2 px accent **border** | a border inside an accent (primary) button would be invisible |
| D3 | Controls fall back to the prototype's Large Text list whenever a row of buttons does not fit the round screen (Large Text; Arabic "إيقاف مؤقت") | no cut-off buttons |
| D4 | End confirmation opens on Cancel; choosing End needs R2 then L1 (or a tap) | G8 "explicit confirmation"; a stray L1 can never end a ride |
| D5 | Cancel on the End confirmation returns to the ride page, not to Controls | fewer presses back to riding |
| D6 | In a ride, the restart combination first opens a warning screen (Cancel highlighted) | "avoid restarting during an active workout without an explicit warning" |
| D7 | Widgets: L1 opens the widget's app → "Not in this release" page; Today: L1 = Start (with a plan) | recommendation §3 |
| D8 | Lock chip text shortened to "LOCKED · HOLD NEXT" | the longer "TOUCH LOCKED · …" did not fit the round screen |
| D9 | Chart "No sensor" / "WAITING HR" text placed clear of the target line | it overlapped the dashed line in the prototype position |

New wording (English / Arabic), owner review needed: "Ride ended", "LOCKED · HOLD NEXT", "Hold to end",
"Restart in N", "Release to cancel", "Restart the watch?", "The ride on the watch ends", "Restart",
"المنطقة Z3 140–155 bpm". All other new texts come from the prototype dictionary.

## 4. Tests (computer; all pass on commit 3a8d4e3)

| Test | Result |
|---|---|
| `test_keys` — decoder: debounce, bounce, short/hold/2 s hold, 0.99 s short, combination fire / cancel at 0.3, 2.5 and 9.9 s, late second key, ambiguous overlap, L2 + R2 not a combination, R2 during the combination, determinism | 19 checks, 0 failures |
| `test_buttons` — raw button levels every 10 ms through the watch path: select / back / next, Controls (EN + AR), Pause / Resume / Lap on every page, End request, Cancel, End with phone lost, touch lock (buttons work, touches ignored), restart outside and during a ride, no leaks after a combination, R2 harmless in a ride, 2 × 60 000 random sequences (incl. bounce), determinism | 154 checks, 0 failures (incl. the owner's 6-point "protect workout controls" checklist: combination cancels an armed lap and navigation; a held button never also gives a short press; chattering presses count once — two give exactly one lap; no single press / hold / pair of any length ends a ride; lock never blocks pause / lap / page / End request; ride restart warns first with Cancel highlighted); random runs: 0 rides ended outside the confirmation, 0 restarts outside the 10 s combination / warning |
| `test_nav` — every screen × every input × EN / AR × ride / no ride, 200 000 random inputs | 542 checks, 0 failures |
| `test_model` | 1,840 checks, 0 failures |
| Rendering — 1,201 screen states (6 themes × EN / AR × 3 densities incl. all new screens), glyphs, fit, clipping, overlap, circle, 44 px touch targets, contrast ≥ 3:1, touch navigation, 30 000-input soak | 0 open findings |
| Partial-update check — every 100th frame compared with a full redraw (and every frame of the hold scenarios) | 1,376 + 4,906 pictures, 0 differ |
| Work budgets (callgrind, computer proxy) | all within budget; new: chart update 1.44 M / rebuild 4.63 M, hold update 1.76 M / rebuild 7.21 M instructions |
| Install simulation (`test_reinstall_sim` §12) — app1-only update RC1 → Stage 1.4, one write, first 4 MB untouched, rollback to RC1, Recovery B accepts it, verify failure, refuses while unpinned, refuses a watch not on RC1 | 0 failures |

Not tested: anything on the watch (buttons, feel, timing, glove use, the reset-button position). Firmware compile and the
reproducible-build check run in CI (not available on this computer).

## 5. Not included / known limits

- Strength screens (set page, rest timer, reps / weight editors) are not built; their button map (L1 primary, L2 two-press
  Log Set / Skip rest, R2 next / increase, L2 decrease in editors) is defined and documented only.
- Discard a workout: not built (no iPhone command yet); stays touch-only by design.
- Restart does not keep the watch's ride state (no session recovery). The warning screen says so.
- Pacing, climb, navigation and coach ride pages are not built; R2 cycles the pages that exist.
- D7 (unexplained restarts): the 11:17 recording shows three POWER-ON resets while the watch was handled; this points to the
  reset button / power path, not a firmware crash. The G1 / G11 physical check will confirm or rule this out.

## 6. Before installation: button identification on the installed RC1 (≈ 3 min, no install)

RC1 prints `key1` / `key2` in the running recording (the read-only monitor holds COM4 until ~19:11). RC1 cannot see R2, so
R2 is identified by "nothing happens". The reset button is **not** pressed on purpose: it is identified as the one left.

| # | Owner does | Expected in the log | Records |
|---|---|---|---|
| I1 | Face the screen. Press the **left upper** button once | one `key1`; the menu opens | L1 location |
| I2 | Press the **left lower** button once | one `key2`; back to the face | L2 location |
| I3 | Press the **right lower** button once, gently | no key line, **no `rst:` line**, screen unchanged | R2 location (if the watch restarts instead, this is the reset button: stop and report) |
| I4 | Look only (do not press) at the **right upper** button: sunken, flush or sticking out? | — | reset button location and shape |
| I5 | Hold the watch as on the wrist / bike and press the left upper button firmly 10 times, at a normal pace | ten `key1`, **no `rst:`** | whether L1 operation presses the reset button |

Pass: I1–I3 as expected, I5 = 10 `key1` and 0 `rst:`. Any `rst:` during I5 = reset contact by L1 operation → reported
before installation (affects the design, not the firmware). I analyse the recording; the owner only reports what he saw.

## 7. Consolidated hardware acceptance session (after separate install approval; ≈ 35 min)

Install: app1-only update `cy_update_s14.py` (s14_pre → s14_write → s14_post), one write 0x400000–0x531FFF (1,253,376 B),
verified, boot banner "Stage 1.4 RC1". Rollback = s14_rollback → RC1 (4ea0ea90…). Recording runs throughout; every key is
logged (`key: L1 short (… ms)`), and the start log shows the reset reason.

| # | Area | Owner does | Pass when |
|---|---|---|---|
| A1 | Button identification | L1, L2, R2 once each | log shows `key: L1 short`, `key: L2 short`, `key: R2 short` |
| A2 | Clock | clock set from the PC (`T`), look at the face | time and date shown; "NOT SYNCED" only for data |
| A3 | Menu + highlight | Face → L1 (menu, first row highlighted) → R2 ×3 (highlight moves, list scrolls) → L1 (opens) → L2 (back) → hold L2 (face) | highlight always visible and moves one row per press |
| A4 | Widgets / Today | Face → R2 ×4 (round the widgets); swipe up → Today → R2 (Week) → L2 | as described |
| A5 | Quick Settings + lock | hold L1 1 s → Quick Settings → R2 to "Screen lock" → L1 → tap the screen (ignored) → L1 (menu opens) → hold R2 (unlocked) | touches ignored, buttons work, chip "LOCKED · HOLD NEXT" |
| A6 | Ride start | menu → Activities (simulated ride) | cockpit, "Simulated ride" marker |
| A7 | Pause / Resume | L1 (Controls, Pause highlighted) → L1 (paused) → L1, L1 (resumed) | each confirmed on screen |
| A8 | Lap | L2, L2 quickly; then L2 once and wait 3 s | one lap; the single press does nothing |
| A9 | Ride data pages | R2 ×4 | Power → Heart rate → Cadence → cockpit, dots show the page |
| A10 | End: cancel | hold L1: release at ~1 s (nothing) · hold 2 s → "End workout?" (Cancel highlighted) → L2 | ride continues |
| A11 | Lock during the ride | hold R2 → L1, L1 (pause) → L1, L1 (resume) → L2, L2 (lap) → hold R2 (unlock) | all work while locked |
| A12 | Restart shortcut: cancel only | during the ride hold L1 + L2 → countdown → release at ~5 s | "Restart in N" shown, cancelled, ride continues, no lap / menu leaked. **No restart is executed during the ride.** |
| A13 | End: confirm | hold L1 2 s → R2 (End) → L1 | "Ride ended · iPhone keeps the record", face |
| A14 | Arabic | language Arabic; repeat A3, A7, A10 briefly | right-to-left, labels complete, highlight correct |
| A15 | Large Text | Large Text on; open Controls (list form), A10 | list readable, highlight visible |
| A16 | Restart shortcut, no ride (optional) | with no ride: hold L1 + L2 10 s, release | one restart after release; log `restart cause: user restart (L1 + L2 held 10 s)` |
| A17 | Monitoring | — (automatic) | no unexplained `rst:` line; heap flat |

Stop rule: any ride ended or restarted without confirmation, a button that acts twice, or an unexplained restart → stop
and report; no extended diagnostics unless the fault repeats.

## 8. Fingerprint (recorded 12 Nov 2026 16:40 Dubai)

| | |
|---|---|
| File | `cyclift-stage1.4-rc1-v3poc-T-Watch-2021-V1_1.bin` |
| Size | 1,253,264 B |
| SHA-256 | `f995c5383e60a3331fdc0a0f8aebeefc96f9ec791caceb655b01219dd0d2a076` |
| Built from | commit 3a8d4e3 (CI 43193189780) and again from 5b4c2a5 (docs only; CI 43193637056) — same file |
| Reproducible | each run: two clean builds and the published file byte-identical (reproducible-build job) |
| Integrity | ESP image header DIO / 8 MB / 40 MHz; 6 segments; checksum OK; appended SHA-256 OK; image length = file length; fits the 3 MB slot; banner "Stage 1.4 RC1" |
| Pinned in | `releases/stage1.4-rc1.sha256`, `cy_update_s14.py`, `cy_recover_b.py` (install simulation checks all three agree) |
| Install span | 0x400000–0x531FFF (1,253,376 B), app1 only; ends far below the Cyclift settings area 0x700000; first 4 MB untouched |
