# Stage 1.1 — memory reduction investigation, read-only diagnostics, missing functions (10 Nov 2026)

Scope: offline analysis + existing serial commands only. No firmware written, nothing reconfigured; the v3poc firmware keeps
no settings in flash (serial hooks change RAM state only). Stage 1.1 (3274b887…) remains installed and running. C2 IN PROGRESS.

## 1. Root cause of the ~67 KB drop (CONFIRMED)

The serial "heap free" figure is `ESP.getFreeHeap()` = `heap_caps_get_free_size(MALLOC_CAP_INTERNAL)` (arduino-esp32 3.3.12
`Esp.cpp`). On the ESP32, ESP-IDF 5.5 registers the unused tail of the 128 KB IRAM block (up to 0x400A0000) as heap of type
"IRAM" with capabilities `INTERNAL | EXEC | 32BIT` — **no `8BIT`, no `DEFAULT`** (`components/heap/port/esp32/memory_layout.c`).
So the figure includes IRAM that ordinary `malloc`/`new` (strings, LVGL objects, Bluetooth buffers, task stacks) cannot use.

| | Stage 1 (faa2828f) | Stage 1.1 (3274b887) | Change | Source |
|---|---|---|---|---|
| IRAM code (image segments at 0x40080000) | 72,136 B | 123,540 B | **+51,404 B** | `esptool image_info` of both installed files |
| Unused IRAM tail counted as "heap" | 58,936 B | 7,532 B | −51,404 B | 131,072 B region (`memory.ld`) − code |
| Static DRAM (data + bss) | 92,616 B | 107,248 B | **+14,632 B** | PlatformIO "RAM used", CI 42620589450 / 42682987729 |
| of which `.dram0.data` | 18,536 B | 18,232 B | −304 B | image segment 1 |
| Explained total | | | **66,036 B** | |
| Observed drop: free / min | 187,880 / 160,112 | 121,028 / 94,500 | 66,852 / 65,612 B | B2 log / C2 log |

Unexplained remainder ≈ 0.8 KB (runtime allocations, e.g. the Arabic source-text map). The same build without LVGL in IRAM
(`CYW_NO_FAST_MEM`) has IRAM code 72,136 B — byte-identical to Stage 1 — so the IRAM part is entirely the fast-memory option.

The +14,632 B static DRAM is the new frame-time recorder (`perf` namespace): 512 samples × 24 B = 12,288 B, a 2,048 B sort
buffer and 120 B histogram = 14,456 B; ~176 B other. (From the source; per-symbol sizes not yet extracted from the ELF.)

**Usable (byte-addressable) internal heap** = reported − IRAM tail (assumes the IRAM tail stays unallocated, which holds while
nothing requests 32-bit/executable memory — hypothesis, not measured):

| | Stage 1 | Stage 1.1 | Change |
|---|---|---|---|
| free | ~128.9 KB | ~113.5 KB | −15.4 KB |
| minimum | ~101.2 KB | ~87.0 KB | −14.2 KB |

So the real loss is ~15 KB, all from diagnostic instrumentation. Graphics buffers, LVGL settings (64 KB pool, 57.6 KB internal
DMA draw buffer, 120 lines) and compiler flags other than the reproducible-build date/time are unchanged between versions.

## 2. Read-only hardware diagnostics (10 Nov 17:13–17:15, serial hooks only, 0 restarts)
Raw log: `evidence/c2_mem_diag_20261110.txt`.

| State | heap free | min | PSRAM free | LVGL pool used |
|---|---|---|---|---|
| Face / menu | 121,164 | 94,500 | 2,095,104 | 5,028 / 65,536 |
| Ride EN | 119,856 → 119,584 | 94,500 | 1,978,364 | 5,364 |
| Ride AR | 119,456 | 94,500 | 1,978,364 | 5,500 |
| Back on face | 120,108 | 94,500 | 1,978,364 | 4,512 |

- Minimum (94,500) never moved during navigation or rides → it is set during start-up; Stage 1 had the same ~28 KB start-up dip.
- Entering the ride used 116,740 B of PSRAM (the 115,200 B ring image) — confirms it is in external PSRAM, kept for reuse.
- Short-run stability only (~3 min, no downward trend); B2's 10-min Stage 1 ride was flat. A longer soak is part of C2.
- LVGL "peak" (4,622) is below "used" (5,500): reporting quirk of the counter, not a memory problem.

Rendering on the watch (Stage 1.1 frame-time recorder):

| | EN ride | AR ride |
|---|---|---|
| 1 Hz cockpit update p50 / p95 / max | 71.0 / 79.6 / 112.3 ms | 71.4 / 87.0 / 104.7 ms |
| Screen rebuild p50 / max | 212.7 / 362.2 ms (4) | 323.8 ms (1) |
| Idle frames | 99.9 % < 5 ms | 99.9 % < 5 ms |

Stage 1 (B2, max values from `u` only): updates 130–150 ms, rebuilds ~370 ms, Arabic redrawing continuously. Stage 1.1 updates
are roughly halved and the Arabic continuous redraw is gone (idle frames 1–2 ms). Rebuilds: UI object creation dominates
(up to 284 ms); first ride entry includes the one-time ring image. Different methods → indicative comparison only.

## 3. Bluetooth and future features
- IRAM: the existing Bluetooth (NimBLE) app uses 128,424 / 131,072 B (2,648 free). Bluetooth + LVGL-in-IRAM cannot be linked.
  **Fast memory must be off (or reduced to a few KB of hot functions) before Bluetooth.** (Confirmed by arithmetic + CI map.)
- Heap: with Bluetooth, the 56,156 B controller area stays reserved (Stage 1.x gets it back), plus NimBLE host allocations
  (not measured). Rough estimate for Stage 1.1 UI + Bluetooth, instrumentation trimmed: ~50–70 KB usable free (ESTIMATE —
  must be measured on the watch). Workable but tight once sensors, queues and coaching text are added.
- Largest free block and task-stack headroom: still not measurable with installed firmware.

## 4. Disabling fast memory
- Memory: restores the 51,404 B of IRAM tail (reported free back to ~172 KB); usable byte-addressable heap unchanged.
- Speed: NOT measured. The −43 % instruction-count gains come from code changes and are kept; only flash-cache misses (DIO 40 MHz)
  return. Hypothesis: a modest slowdown. Measurement needs the `nofastmem` build on the watch (requires your approval).

## 5. Recommended actions (priority order; none performed)
1. Keep Stage 1.1 installed for C2 — memory is stable and the real loss (~15 KB) is diagnostic buffers.
2. Before Stage 2b/Bluetooth: build Stage 1.2 candidate (needs approval) — fast memory OFF or limited to ≤ 8 KB of measured hot
   draw functions; frame recorder 512 → 128 samples (−11 KB) or moved to PSRAM; report largest free block and stack high-water
   marks; fix LVGL peak counter; serial command to set the time (see 6).
3. Measure on the watch (with approval): Stage 1.2 vs 1.1 frame times, heap, largest block; 30-min soak.
4. Later memory headroom for Bluetooth: LVGL pool 64 KB → 32 KB (peak use ~5.5 KB), keep the 57.6 KB draw buffer unless needed.

## 6. Planned, not implemented (Stage 1 and 1.1 firmware, verified in code and on the watch)
| Function | Status | Note |
|---|---|---|
| Valid time display | NOT IMPLEMENTED | no time source; RTC loses time without battery; shows "--:--" + NOT SYNCED (by design) |
| Time sync from iPhone | NOT IMPLEMENTED | needs Bluetooth (Stage 4 per plan) |
| Clock-screen swipe up → Today | NOT IMPLEMENTED | in prototype v3.3; screen not in firmware |
| Clock-screen swipe down → Quick Settings | NOT IMPLEMENTED | in prototype v3.3 |
| Clock-screen swipe left/right → widgets | NOT IMPLEMENTED | in prototype v3.3 |
Owner check 10 Nov: upper button opens menu ✔, menu swipe scroll ✔, clock-screen swipes no effect (expected per code).
Model and input code identical in Stage 1 and 1.1 (diff + simulation of all swipe directions); computer test "swipe" scenario
added (face swipes, menu scroll, time becoming valid): 1,114 partial redraws = full redraw.
