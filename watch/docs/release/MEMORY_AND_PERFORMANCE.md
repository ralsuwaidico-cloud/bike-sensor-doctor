# Cyclift Watch — memory and performance, Stage 1.3 RC1 (11 Nov 2026)

"Measured on the watch" means serial output from the physical watch. Everything else is static (linker, CI 42916312090)
or computer-side (host build, callgrind). The RC1 runtime numbers on the watch do not exist yet (HARDWARE_ACCEPTANCE H11–H12).

## 1. Static memory (compile time, CI)

| Image | IRAM used / 131,072 B | DRAM static / 124,580 B | Image size |
|---|---|---|---|
| Stage 1 (approved, faa2828f…) | 72,136 | 92,616 | 983,360 B |
| Stage 1.1 (installed, 3274b887…) — LVGL drawing in IRAM | 123,540 | 107,248 | 1,009,632 B |
| Stage 1.2 (offline candidate, 2760f5a7…) | 72,464 | 96,536 | 1,016,192 B |
| **Stage 1.3 RC1 (4ea0ea90…)** | **72,464** (58,608 free) | **97,192** (+656 B vs 1.2) | **1,194,112 B** |
| v2 app with Bluetooth (reference) | 128,424 | 111,888 | 2,270,976 B |

RC1 grows the image by 177,920 B (new Inter/Noto sizes, 76 px digits, 12 icons) — flash only (app slot 3 MB).
Internal RAM is unchanged except 656 B of static data; fonts and icons live in flash.

## 2. The ~10.7 KB recovery (brief item 5) — verified statically
Stage 1.1 frame recorder: 14,456 B static (`perf::ring` 512 × 24 B = 12,288 B + sort buffer 2,048 B + histogram 120 B). Stage 1.2 and RC1: ring 128
samples → `perf::ring` 3,072 B + `pct::v` 512 B + hist 120 B + counters = 3,716 B. Saving **10,740 B**, confirmed again in
the RC1 CI symbol list (`perf::ring 3072`, `perf::pct::v 512`, `perf::hist 120`). This is static RAM; the watch-side effect
is to be read with `M` (H11).

## 3. Heap (watch, measured vs predicted)

| | Value | Source |
|---|---|---|
| Stage 1 reported free | 187,728–188,804 B | watch (B2, install) |
| Stage 1.1 reported free / min | 121,028 / 94,500 B | watch (C2, 10 Nov) |
| Stage 1.1 usable 8-bit heap | ≈113.5 KB | derived: reported − IRAM tail |
| RC1 predicted reported / usable | ≈182 KB / ≈123.5 KB | prediction = Stage 1.2 prediction − 656 B static; **not measured** |
| Acceptance budget | 8-bit internal heap min ≥ 80 KB during the 10-min ride | HARDWARE_ACCEPTANCE H11 |

## 4. LVGL pool (brief item 5: 64 KB → 32 KB?)
- Computer: every state renders identically with a 32 KB and a 16 KB pool; 12 KB fails (Stage 1.2 study, CI).
- RC1 computer soak (30,000 random inputs, every screen): sampled pool peak **15,208 B**; LVGL memory at a fixed reference
  state stays 8,176–8,208 B (no growth).
- Decision: **not adopted in RC1.** The pool stays 64 KB until `M` on the watch shows the sampled peak with the real
  fonts, PSRAM placement and panel driver. Proposal for RC2: 32 KB if the watch peak is ≤ 20 KB (≥ 12 KB headroom);
  saves 32,768 B of internal RAM — the largest single gain available before Bluetooth.

## 5. Performance (computer proxy, callgrind instructions per frame; budgets in `test/v3/perf_budgets.json`)

| Work | Budget | RC1 max | Watch reference |
|---|---|---|---|
| Cockpit 1 Hz update | 2.0 M | 1.75 M | Stage 1.1 p50 71 ms, max 112 ms EN / 105 ms AR (watch, C2) |
| Cockpit rebuild | 5.5 M | 5.13 M | Stage 1.1 213–362 ms (watch) |
| Navigation rebuild (face ↔ menu ↔ cockpit) | 6.0 M | 5.53 M | — |
| **New pages rebuild** (Today, Week, Quick Settings, widgets, not-in-release) | 7.0 M (set 10 % above first measurement) | 6.38 M | not measured; scaling from Stage 1.1 suggests ≈ 300–450 ms on the watch with IRAM drawing off — an estimate only |
| Idle frame | 0.02 M | 0.01 M | — |
| Cockpit redraws | ≤ 1.1 /s, ≤ 23,000 px | 1.00 /s, 22,056 px | — |

Known open performance risk: Stage 1.2/RC1 turn LVGL drawing in IRAM off (needed for Bluetooth). Functions that moved out
of IRAM carry about 21 % of the ride-update work on the computer; the watch effect is unknown until H12.
