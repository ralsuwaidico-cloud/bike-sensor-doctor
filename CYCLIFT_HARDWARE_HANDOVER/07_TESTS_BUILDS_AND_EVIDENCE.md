# 07 — Tests, builds and evidence (verified against the actual logs on 8 Nov 2026)

## A. BikeComputer firmware

### CI — `.github/workflows/firmware.yml` (build only, never flashes)

Last run **40708452283** (28 Oct 2026, `fw/phonefirst` @ c0a10fb0), both jobs green. Figures copied from the run's
own `::notice` lines:

| Job / step | Result |
|---|---|
| ESP‑IDF 5.5.1 build | ok in 130 s — app **1 877 632 B** `build/bike_computer.bin` (4 MB OTA slot) |
| LVGL simulator (`test/sim`) | ok in 32 s (the per‑screen report is in the job summary; 339 screens / 701 checks were the rc5 figures recorded in `CYCLIFT_WORK_STATUS.md`) |
| Host tests | ok in 20 s — test_bc_diag 195 · test_bc_storage 82 · test_bc_bootrec 21 · test_storage_fixture 10 · test_partitions 65 · **test_bc_link13 147** checks, 0 failed (plus `test_bc_core`, `test_bc_pipe`, `test_bc_xds` run earlier in the same step) |
| BLE harness (`test/blehost`) | ok in 173 s — "RESULT PASS criterion (B, C): every LIVE frame delivered, mean latency ≤ 218 ms, max latency ≤ 640 ms, no ENOMEM"; initfail modes 0/1/2: 15/11/9 checks, 0 failed |

### Independent QA rounds (host/simulator only)

Five reviews of 0.7.4 (rc1 → rc5): findings QF‑01…QF‑29, RC3‑01…RC3‑08, Q‑iOS‑15 — each "fixed at the root" with a
regression test (`coord/handoffs/firmware.md` rounds 2–7; QA reports `/home/claude/qa-fw/FIRMWARE_REVIEW_RC{1,2,3,5}.md`
— local files, see 08 for availability). Verdict on rc5: **GO for install + physical test** — install not performed.

### Physical‑hardware evidence (the only real‑device facts)

| Date | What | Source | Result |
|---|---|---|---|
| 23 Oct | Phase A diagnostic on the board (display, touch, storage, NVS, IMU, battery, Wi‑Fi scan, XDS live) | firmware 0.1.x commits; owner feedback | board works; reboot loop fixed (float printf) |
| 24 Oct 19:24 | 0.4.0 install: board identity ESP32‑S3 rev 0.2, 16 MB QIO, COM3; factory backup (16 MB) present; pre‑install backup verified; 4 regions written, hashes verified | `docs/HW_TEST_LOG_0.4.0.md` P1–P5; `install-v040-20261024-192438.txt` | **PASS** |
| 24 Oct 22:26 | 0.5.0 installed by the owner | log P6 | PASS (features untested) |
| 24–25 Oct | owner's findings on 0.5.0 / 0.6.0 rev 1: link lost on screen‑off, triple‑tap wake unreliable and taps started rides, pull‑down hard to open, touch dead after sleep, pairing broke after data reset | `docs/FIRMWARE_0.6.0.md`, HW‑5/6/8/9 | real defects → fixes in 0.6.x/0.7.0, **fixes never hardware‑verified** |
| 25 Oct 12:12 | board found on 0.6.0 rev 1 | log P7 | INFO |
| 26 Oct | 0.7.2 crash loop on the board (SAFE MODE screen) | `docs/CRASH_0.7.2.md` | real; investigation + 0.7.3 |
| 27 Oct 12:04 | 0.7.3 installed; three boots logged: core dump written and verified, `nimble_port_init` abort decoded with the matching ELF, heap 111 KB at app_main, flash/FAT figures | `first-boot-v073-20261027-120437.txt`, `coord/reports/FW_STORAGE_MEMORY_REPORT.md` (tags B/K/E) | board **crashes at Bluetooth start**; FAT root directory erased |
| since | 0.7.4‑rc1…rc5 | — | **not installed, no hardware evidence** |

Backups on the owner's PC (`Documents/BikeComputer`): `factory_backup_16MB.bin`, `backup-before-v040…`,
`backup-before-v050…`, `backup-before-v071/v072…`, kits and rollback scripts for every version (copies of the folder
were attached to this session).

## B. Cyclift Watch (LILYGO) firmware

### CI — `.github/workflows/watch.yml` (host‑tests + firmware‑compile; never flashes)

| Run | Commit | Result | Notes |
|---|---|---|---|
| 42482951948 | 251a4630 | reported success but **the compile had failed** — `pio run … \| tee` masked the exit code | errors: LVGL widgets left enabled (`lv_img`), Arduino‑ESP32 3.x LEDC API, `fs::File`, NimBLE `notify()` returning void, `TFT_*` macros colliding with pin constants |
| 42484579707 | 570893db | firmware‑compile **failed honestly** after `set -o pipefail` | LVGL calendar/animimg still compiled (undefined `LV_USE_*` default to on) |
| **42485131249** | 6639c553 (13:28 UTC) | **green — first real device build**; `set -o pipefail` confirmed in the log | **App `T-Watch-2021-V1_1`: RAM 34.1 % (111 856 B of 327 680), Flash 69.6 % (2 190 064 B of 3 145 728) — Diagnostics `V1_1-diag`: RAM 32.3 % (105 848 B), Flash 49.1 % (1 545 559 B)**; host: 1 368 scenes, 0 findings |
| 42485993185 | 563cfee3 | green | docs only |
| 42487268861 | b6ab6ca8 | green | quick settings + timer |
| **42487341323** | ca2cadb6 (branch head) | green | App RAM 111 872 B · Flash 2 197 976 B; Diag 105 864 B / 1 545 655 B; host **244 checks**, **1 464 scenes, 0 findings** |

These are **linker figures** (static .data/.bss and image size) from a cloud build. Runtime heap, PSRAM use, frame
rate, touch latency, battery drain, BLE stability: **no measurement exists** — the watch has never run this firmware.

### Host tests (`watch/firmware/test/host`, also run locally)

`test_domain.cpp`: 244 checks — layout engine, text fitting, buttons/two‑press, activities lifecycle, strength logging
and corrections, rep detector (synthetic), coach protocol, sync frames/CRC/queue/dedup/clock, payload codec round
trips, GPS mirror, ride commands, full ride and strength sessions through the AppModel (touch + keys + BLE frames),
quick settings, timer, DND. `gallery.cpp`: 61 screens × 6 appearances × 4 text variants = 1 464 scenes, 0 findings
(overflow, overlap, contrast ≥ 4.5:1, truncation, touch ≥ 44, grading invariance); writes `docs/TEXT_SIZES.md` and
SVG evidence per scene (`gallery-out/`).

### iPhone companion (protocol v1) — `impl/checkpoint-f-ride`

`CyWatchWireTests` (31 checks on the Linux harness: every payload byte‑identical to vectors produced by the firmware
encoder), `CyWatchSessionTests` (frame reassembly, CRC resync, cumulative ack, persisted dedup, event → Store rules).
CI unit job green in run 201 (42488326459). Not hardware‑tested (CoreBluetooth needs a device).

## C. What "tested" means in this package

- **Host / simulator**: code ran on a PC with fake hardware. Proves logic and layout, not timing, radio or power.
- **Compiled**: the toolchain produced an image for the target. Proves nothing about runtime.
- **Hardware‑verified**: a dated log from the real device exists (only the BikeComputer rows above).
