# Stage 1.2 candidate — memory/diagnostics build (computer only; NOT installed)

Owner approval 10 Nov 17:18: offline build and tests only. Stage 1.1 (3274b887…) stays installed and running.
Nothing was flashed, erased or rolled back. Branch `watch/v3-poc`, commit 207b427 (firmware) + tool/CI follow-ups.

## Firmware file

| | |
|---|---|
| File | `cyclift-stage1.2-v3poc-T-Watch-2021-V1_1.bin` |
| Size | 1,016,192 B |
| SHA-256 | `2760f5a7f4c4064e3dbbf70e9bd2af9c76be8a8e6f8ecc492cfc0e09f66ae75a` |
| Header | DIO / 40 MHz / 8 MB (esptool image_info); ESP-IDF 5.5 / Arduino 3.3.12 (pinned) |
| Built by | CI run 42826771046 (commit 207b427); published on branch `firmware/stage1-candidates`; CI pins this SHA |
| Reproducible | two clean CI builds + the published file byte-identical (1,016,192 B) |
| Not touched | `releases/stage1-approved` (faa2828f…) and new `releases/stage1.1-installed` (3274b887…), both CI-guarded |

## Changes (all in the v3 proof-of-concept build; UI, Arabic, touch, buttons, navigation unchanged)
1. LVGL drawing in IRAM **off by default** (`CYW_FAST_MEM` opt-in; comparison env `T-Watch-2021-V1_1-v3poc-fastmem`, never published).
2. Frame-time recorder 512 → 128 samples; histogram and exact per-kind maxima still cover all frames since `z`.
3. Serial `M`: byte-addressable internal heap free / min / largest block, DMA largest block, getFreeHeap-style total split into
   8-bit + IRAM-only, PSRAM free / largest / min, IRAM code used/free, static DRAM, LVGL pool used / sampled peak / largest
   free / fragmentation, stack headroom of loopTask (of its size), IDLE0/1, esp_timer, ipc0/1, Tmr Svc.
   LVGL peak is now sampled (total − free) after every rebuild and once per second; LVGL's own counter under-reads.
4. Temporary serial clock commands: `T<seconds>⏎` (local time since 1970, 2024–2099) and `R` (read). The clock now counts as
   valid only if the PCF8563 reports no power loss (VL) and the date is ≥ 2024. Architecture unchanged: the watch shows the
   RTC; the iPhone will set the same RTC over Bluetooth (Stage 4). Without a battery the time is lost when USB is unplugged.
5. Banner `… Stage 1.2 (diagnostics; IRAM rendering off) …`.

## 1. Memory (static: CI linker/symbol report; run-time: prediction until measured on the watch)

| | Stage 1 | Stage 1.1 (installed) | Stage 1.2 |
|---|---|---|---|
| IRAM code / 131,072 B | 72,136 | 123,540 | **72,464** |
| IRAM free (counted in getFreeHeap, not usable by malloc) | 58,936 | 7,532 | **58,608** |
| Static DRAM (data+bss) / 124,580 B | 92,616 | 107,248 | **96,536** |
| of which frame recorder | — | 14,456 | **3,716** |
| of which LVGL pool | 65,536 | 65,536 | 65,536 |
| Reported heap free / min on watch | 187,880 / 160,112 | 121,028 / 94,500 | ≈ 182,800 / ≈ 156,300 (predicted) |
| Usable 8-bit heap free (est.) | ≈ 128.9 KB | ≈ 113.5 KB | ≈ 124.2 KB (predicted; `M` measures it) |

+328 B IRAM and +3,920 B DRAM versus Stage 1 = diagnostics code and the smaller recorder.

## 2. Performance with and without IRAM rendering
- Computer, identical method (callgrind instructions per frame, same scenarios, `perf_compare.py`): Stage 1.1 and Stage 1.2
  are **identical** in every group (e.g. ride update avg / p99 / max 0.83 / 1.53 / 1.75 M; rebuild max 5.13 M). Expected: the
  drawing code is the same; IRAM vs flash placement does not exist on a computer.
- Share of work inside the functions Stage 1.1 had in IRAM (computer profile): ride update 21 %, ride rebuild 6–9 %, menu
  navigation update 31 %, clock-face update 59 %.
- Watch effect: **not measured**. Stage 1.1 on the watch (10 Nov): ride update p50 71 ms (EN) / 71.4 ms (AR), max 112 / 105 ms;
  rebuild 213–362 ms. Illustration only (hypothesis): if those functions ran twice as slowly from flash, a 71 ms update would
  become ≈ 84 ms. The real figure comes from running the same serial script on Stage 1.2 (E2 below).
- Selective IRAM: the 15 hottest drawing functions total 18,205 B of IRAM. The Bluetooth app leaves 2,648 B → not compatible
  with Bluetooth either. Not adopted; revisit only after a Bluetooth build is measured.

## 3. Bluetooth compatibility
- IRAM: Stage 1.2 72,464 B → room restored for the controller/NimBLE (the Bluetooth app uses 128,424 B; a v3 + Bluetooth build
  is expected near that — must be confirmed by building it in Stage 2b).
- Heap: Bluetooth keeps 56,156 B reserved that Stage 1.x returns to the heap, plus NimBLE host allocations (not measured).
  Estimate for v3 + Bluetooth: usable ≈ 124 − 56 = ~68 KB before NimBLE's own use; ~100 KB if the LVGL pool goes to 32 KB.
- Static DRAM: 96,536 B of 124,580 B; the LVGL pool (64 KB) is the only large reserve that can shrink.

## LVGL pool 64 → 32 KB (investigated, NOT adopted)
Computer (64-bit build: objects are larger than on the 32-bit watch, so this is conservative), CI-repeated:
- 32 KB and 16 KB: all 133 states pixel-identical to 64 KB, 21,873 checks, 0 findings; 1,114 partial-update pictures = full redraw.
- 12 KB: allocation failure (renderer stops) → real requirement 12–16 KB on the computer.
- Watch (Stage 1.1, 30-s samples): ≤ 5.5 KB used. LVGL's own peak counter under-reads (fixed in 1.2 by sampling).
Recommendation: adopt 32 KB in a later build only after `M` on Stage 1.2 confirms the sampled peak and largest free block.

## 4. CI and reproducibility (run 42826771046: all six jobs green)
- Host: model tests; time tests 19/19; renders 133 states / 21,873 checks / 0 findings incl. the end-to-end time simulation
  (`T1794331800` → registers → face shows 17:30, TUE 10 NOV; VL set → back to "--:--"); visual 132/132 identical to the
  approved rendering; partial updates 1,114 / 0 differ; redraw-rate and instruction budgets pass; pool study as above;
  device-session tests; install-plan/fp-plan tests; reinstall simulation 0 failures (incl. Stage 1.2 update, rollbacks).
- Firmware compile: all v3poc boards, display-diag, Bluetooth app; version pins; image headers DIO/40 MHz/8 MB.
- Emulator (QEMU): S0–S10 0 failures; S10 = Stage 1.1 → Stage 1.2 interrupted at 0–99 %, last sector missing, bit flip, header
  erased → factory app starts; complete Stage 1.2 → starts once.
- Reproducible build: two clean builds and the published file identical.

## 5. Proposed installation, validation and rollback (NOT approved)
Same method as C1 (Stage 1.1), tool `cy_update_s12.py` (= `pc_update_s12_runner.py`, simulation-tested):
- **E0 copy**: Stage 1.2 file to `Documents\Cyclift_Stage2a\stage1_2_firmware\`, `cy_update_s12.py`, updated `cy_recover_b.py`
  (accepts Stage 1, 1.1 or 1.2 in app1; previous copy kept) and `b2_tests.py` (adds `c2_set_clock()`); read back and verify SHAs.
- **E1 install** (needs CI green on the final tool commit):
  - `s12_pre` read-only: chip/8 MB, backup 77ad7105…, plan pieces, Stage 1 + Stage 1.1 + Stage 1.2 file fingerprints, header,
    full read: layout as installed, app1 = Stage 1.1, factory app/files = backup, OTA → app1, rest of app1 erased, Stage 1.1 running.
  - `s12_write`: ONE write at 0x400000, **1,019,904 B (0xF9000), last byte 0x4F8FFF** (Stage 1.2 + 0xFF padding); verify; restart;
    one start with banner "Stage 1.2".
  - `s12_post`: full read; only the app1 span (and the Cyclift data area) changed.
  - Never written: bootloader, partition table, OTA record, factory app, factory settings, files.
- **E2 validation (serial only + owner)**: the same scripted session as 10 Nov (face/menu, ride EN, ride AR, `u`/`h`) plus `M`
  in each state → direct Stage 1.1 vs 1.2 (IRAM on vs off) comparison; `c2_set_clock()` then the owner confirms the face time;
  owner: touch, buttons, menu scroll, Arabic; 30-min ride soak with `M` every 10 min.
- **E3 rollback** (each needs approval): `s12_rollback` → Stage 1.1 (writes 3274b887… over the same span, verified, banner
  "Stage 1.1"); then optionally `s11_rollback` → Stage 1. R-A / R-B unchanged; ROM download mode always available
  (third button + USB if auto-reset fails). Interrupted write → factory app starts → repeat the write or roll back.

Not done: Today / Quick Settings / Widgets screens, Bluetooth, Stage 2b.
