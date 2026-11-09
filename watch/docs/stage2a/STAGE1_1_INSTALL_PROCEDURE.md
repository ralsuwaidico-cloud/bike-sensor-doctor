# Stage 1.1 — proposed installation, test and recovery procedure (NOT approved; for review)

Nothing here has been run on the watch. Each step needs the owner's approval as listed at the end.

## Starting point (as left after B2)
Factory-preserving layout installed: factory LILYGO app0, files and settings untouched; bootloader size field, partition table and
OTA record = planned; **app1 (0x400000) = approved Stage 1 `faa2828f…`**; Cyclift data area 0x700000. USB power only (no battery).

## What changes
Only the app1 program slot: the Stage 1.1 image (CI-published `cyclift-stage1.1-v3poc-T-Watch-2021-V1_1.bin`, SHA-256 filled in
the approval) is written to 0x400000, padded with erased bytes to the end of the longer of the two images, so nothing of the old
image remains. Bootloader, partition table, OTA record, factory app/files/settings: **not written**.
Safety property: if the write is interrupted, app1 holds no valid image and the bootloader starts the factory app0
(emulator scenario S5); the watch is never left without a working program.

## Tool (prepared and tested in simulation only)
`watch/tools/stage2a/pc_update_s11_runner.py` → PC `tools\cy_update_s11.py`, built on the CI-tested installer and
`device_session` (every phase ends with a restart and a boot check; FLASH VERIFIED and BOOT CONFIRMED reported separately).
Simulation (`test_reinstall_sim.py`, in CI): update, post-check, rollback to Stage 1, verify-failure path, wrong-file refusal.

| Phase | Writes | Checks |
|---|---|---|
| `s11_pre` | none (full read) | chip/8 MB/COM4; backup, plan pieces; approved Stage 1 file (for rollback) = faa2828f…; Stage 1.1 file = approved SHA; header DIO/40m/8MB; installed layout as planned; app1 = faa2828f… exactly; factory app/files = backup; OTA selects app1; Stage 1 boot confirmed |
| `s11_write` | app1 only | write + verify_flash; Stage 1.1 boot confirmed (banner "Stage 1.1", one start) |
| `s11_post` | none (full read) | only the app1 span (and the Cyclift data area) changed; app1 = Stage 1.1 + erased padding; boot confirmed |

## Hands-on tests after installation (same method as B2; serial hooks only, no writes)
1. **Frame times on the watch** (`h` after `z`): 2 min watch face; 5 min ride in Standard / Focused / Large Text; the same in
   Arabic; 10 screen changes; 2 pause/resume. Record P50/P95/P99/max per frame kind, SPI flush share, idle max.
   Targets: 1 Hz cockpit update P99 ≤ 100 ms (ideal ≤ 50 ms); screen change ≤ 300 ms, none > 400 ms; idle ≤ 2 ms;
   Arabic like English. Compare with Stage 1 numbers from B2.
2. **Visual and functional regression:** repeat V2-1 … V2-13 (screen, both buttons, touch taps/swipes, cockpit + simulated
   metrics, missing sensors, Arabic, text density, restart ×3, USB reconnection ×3, 10-min stability, end state). Owner checks
   that the ring, numbers and Arabic text look exactly as in Stage 1, with no flicker, ghosting or stale values.

## Recovery (in order; no improvised flash operations)
| Level | When | Writes | Result |
|---|---|---|---|
| R-S1 | Stage 1.1 misbehaves, Stage 1 wanted back | app1 ← approved Stage 1 (padded) — `phase('s11_rollback')` | Stage 1 exactly as after B1 (verified by a repeat `s11_pre`) |
| R-A | factory firmware wanted, or app1 unusable | OTA record 0xF000 ← original | factory LILYGO app starts |
| R-B | full return to the factory layout | 0xF000, 0x8000, 0x1000 + 0x5000 ← originals | done once already (9 Nov) |
| R-C | last resort, separate approval | full 8 MB backup | — |

## Approvals needed
| ID | Scope |
|---|---|
| C0 | copy `cy_update_s11.py` and the Stage 1.1 file (fixed SHA-256) to the PC; no watch access |
| C1 | `s11_pre` (read-only) and `s11_write` + `s11_post` (writes app1 only) |
| C2 | hands-on frame-time and regression tests (serial hooks; no writes) |
| C3 | rollback R-S1 / R-A / R-B if needed (R-C separately) |
