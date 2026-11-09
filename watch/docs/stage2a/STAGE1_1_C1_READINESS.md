# Stage 1.1 — C1 readiness report (C1 NOT approved)

Date: 10 Nov 2026. Scope of approval so far: **C0 only** (copy firmware and tools to the PC). Nothing on the watch was
read, written, erased or restarted for this report. The watch still runs approved Stage 1 `faa2828f…` from app1.

Evidence: branch `watch/v3-poc`, CI "Cyclift Watch (host tests)" run 42692347780 (commit de64a86, all six jobs green);
memory report from run 42696925327 (`mem-report.log`).

## 1. C0 — copy and fingerprint verification

| File on the PC (`Documents\Cyclift_Stage2a\`) | SHA-256 read back from the PC | Matches |
|---|---|---|
| `stage1_1_firmware\cyclift-stage1.1-v3poc-T-Watch-2021-V1_1.bin` (1,009,632 B) | `3274b8877df0a23a5e5cb1364868322d79d643d29411b36782b6bfb34eb937ba` | approved value; byte-for-byte equal (`cmp`) to the CI artifact; two clean CI rebuilds give the same bytes |
| `stage1_firmware\cyclift-stage1-v3poc-T-Watch-2021-V1_1.bin` (983,360 B) | `faa2828f8fd22d59877c4c9535eb09e1a15db3176f2b5cd1c438810aead5cba7` | approved Stage 1, untouched (date unchanged since 9 Nov) |
| `tools\cy_update_s11.py` (new, = `pc_update_s11_runner.py`) | `10ab9b0b…241c7` | repo file at de64a86 |
| `tools\cy_recover_b.py` (updated, = `pc_recovery_b_runner.py`) | `953a7b32…b15b89` | repo file at de64a86 |
| `tools\backup_C0_20261110\cy_recover_b.py` (previous version kept) | `996151aa…d7c3` | the file that was there before C0 |
| `tools\device_session.py` | `6c2e3d91…0336` | unchanged, equals repo |

The private watch backup was not touched or copied anywhere.

## 2. Memory — what "about 8 KB left" means

The 8 KB is **IRAM**: the 128 KB block of internal RAM that holds machine code which must run without the flash cache
(interrupt handlers, Wi-Fi/Bluetooth/flash drivers). It is **not** the working memory (heap) that the app allocates from.

| Measure | Stage 1.1 | Source |
|---|---|---|
| IRAM code (static) | 123,540 B of 131,072 B (`iram0_0_seg`, 0x40080000, len 0x20000) → **7,532 B free** | linker sections + `memory.ld` |
| of which LVGL drawing moved to IRAM (Stage 1.1 change) | 51,404 B | same build with `CYW_NO_FAST_MEM`: 72,136 B |
| DRAM static (data + bss) | 107,248 B of 124,580 B (`dram0_0_seg`) → 17,332 B free; identical with or without the IRAM change | linker sections + `memory.ld` |
| PSRAM | ring image 115 KB allocated from PSRAM (2 MB) | source: `heap_caps_malloc(…SPIRAM…)` |
| Free internal heap after start | not yet measured for Stage 1.1 (Stage 1 on the watch: 187,880 B) | B2 serial report |
| Minimum free heap while running | not yet measured for Stage 1.1 (Stage 1: 160,112 B) | B2 serial report |
| Largest contiguous free block | **not measurable** with the fixed candidate (no command reports it) | — |
| Task stack headroom | **not measurable** with the fixed candidate | — |

Why the IRAM margin is not a runtime risk: IRAM size is decided entirely when the firmware is linked. If code ever
grows past the limit, the **build fails**; it cannot run out of IRAM on the watch. The unused IRAM tail is only usable
for 32-bit-aligned special allocations, so normal heap use does not compete for it. Stage 1.1 does not change DRAM
or heap layout at all (DRAM static is identical with and without the change).

Expected Stage 1.1 heap: same static DRAM as Stage 1 plus no new internal-RAM buffers (the 115 KB image is in PSRAM),
so free/minimum heap should be close to the Stage 1 figures. **This is a prediction**; the actual numbers are read in
C2 with the existing `u` command (free heap, minimum free heap, PSRAM).

Bluetooth:
- The linker keeps 56,156 B of internal RAM (0x3FFB0000–0x3FFBDB5C) for the Bluetooth controller. Stage 1.1 has no
  Bluetooth, so Arduino core 3.3.12 releases that memory to the heap at start (the core's own comment says ~36 KB;
  the exact amount returned is not measured) (verified in the core source: `btMemRelease(BT_MODE_BLE)` when no Bluetooth library is linked).
- The existing Bluetooth (NimBLE) watch app already uses 128,424 B of the 131,072 B IRAM (2,648 B free). Adding the 51 KB
  LVGL-in-IRAM change would need ~179 KB: **the build would fail.** With Bluetooth, the reserved RAM is also kept, so
  the heap is smaller than in Stage 1/1.1.

Decision proposed (reliability over speed): **LVGL-in-IRAM is a Stage 1.1 measurement option only. Any build that adds
Bluetooth or other features must use `CYW_NO_FAST_MEM`** (already a CI build target; its rendering output is
identical — only speed differs). C2 can measure how much of the Stage 1.1 gain comes from IRAM vs. the redraw
reductions only if a second, separately named candidate is approved; this report does not request that.

## 3. Interrupted-write simulation (QEMU, synthetic images, nothing flashed)

Starting point identical to the watch after B1: 8 MB bootloader header, new partition table, OTA record → app1,
app1 = approved Stage 1, app0 = factory stand-in. esptool writes sector by sector (erase 4 KB, then write), so each
case cuts the write at a point, erases the rest of that sector, and leaves later sectors either old or erased.

| Case | Result |
|---|---|
| Stage 1 baseline / stopped before the first erase | Stage 1 starts from app1 (1 start) — PASS |
| Cut at 0 %, 0.2 %, 25 %, 50 %, 75 %, 99 % × (rest old, rest erased) — 12 cases | bootloader rejects app1, starts app0 — 12 PASS |
| Last sector missing | app0 starts — PASS |
| One bit flipped in a complete image | app0 starts — PASS |
| Header sector erased | app0 starts — PASS |
| Complete Stage 1.1 | Stage 1.1 starts from app1, 1 start, no fallback — PASS |

18/18 S10 cases pass (run 42692347780; the first run exposed a wrong expectation for "0 %, rest old", which is the
same as "nothing erased yet" and correctly keeps Stage 1; the cases were split and fixed).

What this proves and what it does not:
- Exact bootloader behaviour: the IDF bootloader checks the image checksum **and** the appended SHA-256 of app1. Any
  incomplete or damaged image fails, and it then tries app0. The factory LILYGO app in app0 is the fallback.
- The fallback is **not** "automatic recovery": the OTA record still points to app1, so every restart repeats the
  check and lands in app0 until app1 is repaired. The factory app then runs with the Cyclift layout (B1 showed it works).
- A **complete but faulty** image (valid checksum, crashes at start) does **not** fall back (scenario S5): it reboots
  repeatedly. Stage 1.1 starting correctly was shown in the emulator only, not on hardware.
- The emulator models the bootloader logic, not the physical flash or USB link.

## 4. Recovery procedure

| Situation | Action (tools already on the PC) |
|---|---|
| Write fails or verify fails during C1 | tool stops and restarts the watch with a boot check (no further writes); next step R-S1 (Stage 1 back from `s11_rollback_stage1_padded.bin`) or a repeat write — each needs your approval (C3) |
| Watch shows factory LILYGO instead of Cyclift | app1 incomplete — repeat C1 write, or R-S1 (Stage 1 back) |
| Stage 1.1 misbehaves | R-S1: Stage 1 back into app1, verified by a repeat precheck |
| Factory firmware wanted | R-A: original OTA record |
| Full factory layout | R-B (now accepts Stage 1 **or** Stage 1.1 in app1; done once on 9 Nov) |
| Nothing starts at all | ROM download mode is permanent on this chip (no secure boot, no flash encryption): the tools enter it through the T-U2T auto-reset; if that fails, hold the **IO0 (third) button** while plugging USB in, then R-S1 / R-A / R-B; R-C (full 8 MB backup) needs separate approval |

## 5. C1 write-plan audit (tool `cy_update_s11.py`, simulation-tested)

- One write: address **0x400000**, length **1,011,712 B (0xF7000)**, last byte **0x4F6FFF** = Stage 1.1 (1,009,632 B)
  padded with 0xFF to whole sectors. Lies entirely inside app1 (0x400000–0x6FFFFF).
- Not written: bootloader (0x1000), partition table (0x8000), OTA record (0xE000), factory app0 (0x10000), settings
  (nvs 0x700000), files (spiffs 0x210000, littlefs 0x706000).
- Before writing (read-only): chip, flash size, full read compared with the backup; app1 = `faa2828f`; factory app and
  file areas equal the backup; OTA selects app1; Stage 1.1 file SHA = `3274b887…`; write size/address asserted.
- After writing: esptool verify; full read shows only the app1 span changed (nvs may change by itself);
  restart with boot button released, one start, banner must contain "Stage 1.1".
- Simulation: 1 write command total, only `flash_id/read/write/verify` used; verify-failure and wrong-file paths stop
  safely; R-A and R-B still work afterwards.

## 6. Remaining risks

1. Hardware behaviour of Stage 1.1 (touch, Arabic, ring, buttons) is emulator-verified only — C2 covers it.
2. Free/minimum heap for Stage 1.1 predicted, not measured; largest free block and stack headroom not measurable
   with this candidate.
3. USB disconnect during the write: covered by the S10 results (factory app starts, re-run the write). The watch
   has no battery, so the cable must stay connected.
4. Stage 1.1's IRAM use blocks adding Bluetooth with the same setting — handled by the decision in section 2.
