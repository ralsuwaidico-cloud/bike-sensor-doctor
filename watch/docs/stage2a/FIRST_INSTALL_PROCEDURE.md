# Cyclift Watch — first hardware installation: exact procedure (PROPOSAL — NOT APPROVED, NOT EXECUTED)

Factory-preserving layout, Stage 1 proof of concept (no Bluetooth). Every step below changes the watch and needs the owner's explicit
approval of this document first. Run on the owner's PC (Python 3.12, esptool 4.8.1, T-U2T on COM4). Never `erase_flash`, never
`--erase-all`, never eFuse commands. All writes use `--flash_mode keep --flash_freq keep --flash_size keep` so esptool changes nothing
it was not told to change. Every write is followed by `verify_flash` (device-side MD5 compare, read-only).

Prefix used below: `ESP = python -m esptool --chip esp32 --port COM4 --baud 921600`
Private folder: `P = %LOCALAPPDATA%\Cyclift_Private\watch_backup_20261109`

## Blockers to clear before the session
1. **Board revision.** The build exists for T-Watch 2021 V1.0, V1.1 and V2 (different display pins). The chip check cannot tell them
   apart; the revision printed on the watch's board (or the presence of a crown/GPS = V2) must be confirmed. Wrong revision = blank
   screen (no damage, recoverable by step R-A).
2. **The firmware file.** `firmware.bin` of `T-Watch-2021-V1_x-v3poc` from the approved commit's CI build, its SHA-256 recorded in the
   approval, checked with `tools/v3/check_image_header.py` (DIO / 40 MHz / 8 MB) and ≤ 3 MB.
3. Emulator evidence for that exact commit green (`stage2a-boot-sim`: S0–S8, C1–C3).

## Order is safety-critical (emulator evidence, run 42615619124)
The factory bootloader with its original 4 MB setting **boot-loops** as soon as the partition table lists anything above 4 MB — even
while the factory app is still selected (C2x). Therefore: program → bootloader patch → table → switch, never the table first; and a
rollback reverses it: switch → table → bootloader.

## Phase 0 — read-only pre-checks (no change)
| # | Command / action | Pass condition |
|---|---|---|
| 0.1 | `ESP flash_id` | ESP32-PICO-V3-02, 8 MB |
| 0.2 | SHA-256 of `P\flash_8MB_read1.bin` | `77ad7105…3767693` |
| 0.3 | SHA-256 of every file in `P\plan_pieces` vs `manifest_sha256.txt` | all equal |
| 0.4 | `ESP read_flash 0x0 0x400000 now.bin`; compare with backup | identical except the factory boot counter in 0x9000–0x9FFF |
| 0.5 | SHA-256 of `cyclift_v3poc.bin` | equals the value in the approval |

## Phase 1 — Cyclift program into the empty upper flash  → checkpoint C1
| # | Command | Expected |
|---|---|---|
| 1.1 | `ESP --after hard_reset write_flash --flash_mode keep --flash_freq keep --flash_size keep 0x400000 cyclift_v3poc.bin` | written |
| 1.2 | `ESP verify_flash 0x400000 cyclift_v3poc.bin` | "verify OK" |
| C1 | watch restarts | **factory LILYGO/OSW firmware starts as before** (emulator C1 ✔). Nothing points to the new program yet. |
Recovery from here: none needed (only previously empty flash changed).

## Phase 2 — bootloader size field 4 MB → 8 MB (code unchanged)  → checkpoint C2
| # | Command | Expected |
|---|---|---|
| 2.1 | `ESP --after no_reset write_flash --flash_mode keep --flash_freq keep --flash_size keep 0x1000 P\plan_pieces\planned_0x001000.bin 0x5000 P\plan_pieces\planned_0x005000.bin` | written |
| 2.2 | `ESP verify_flash 0x1000 …planned_0x001000.bin 0x5000 …planned_0x005000.bin` | "verify OK" (both) |
| C2 | `ESP run` (reset) | **factory firmware starts** (emulator C2 ✔) |
Recovery R-B2: write `original_0x001000.bin` @0x1000 and `original_0x005000.bin` @0x5000, verify. If the watch shows nothing at all,
the ROM loader still answers (download mode is permanent) → R-B2 or R-C.

## Phase 3 — new partition table  → checkpoint C3
| # | Command | Expected |
|---|---|---|
| 3.1 | `ESP --after no_reset write_flash --flash_mode keep --flash_freq keep --flash_size keep 0x8000 …planned_0x008000.bin` | written |
| 3.2 | `ESP verify_flash 0x8000 …planned_0x008000.bin` | "verify OK" |
| C3 | `ESP run` | **factory firmware starts** (emulator C3 ✔) but with **default settings**: it now reads the new, empty settings area; its real settings are untouched in `nvs_fac` and come back with R-B. Expected, not a fault. |
Recovery R-B3: write `original_0x008000.bin` @0x8000 (+ R-B2), verify.

## Phase 4 — the switch (OTA record seq 2)  → checkpoint C4
| # | Command | Expected |
|---|---|---|
| 4.1 | `ESP --after no_reset write_flash --flash_mode keep --flash_freq keep --flash_size keep 0xF000 …planned_0x00f000.bin` | written |
| 4.2 | `ESP verify_flash 0xF000 …planned_0x00f000.bin` | "verify OK" |
| C4 | `ESP run`, then `python -m serial.tools.miniterm COM4 115200` | Cyclift v3 Stage 1 starts; serial shows "Cyclift v3 proof of concept …"; screen shows the Orbit face |

## Phase 5 — post-install read-only verification
| # | Action | Pass condition |
|---|---|---|
| 5.1 | `ESP read_flash 0x0 0x400000 after.bin`; compare with backup | differs only in 0x1000, 0x5000, 0x8000, 0xF000 sectors (+ factory boot counter from C1/C2 boots) |
| 5.2 | compare factory app 0x10000–0x20FFFF and files 0x210000–0x3FFFFF | byte-identical to backup |
| 5.3 | hardware checklist (display, touch, both buttons, menu, cockpit, 44 px targets, brightness, current draw) | owner observation, recorded |

## Recovery levels (each needs a verify step and is approval-gated like the install)
| Level | When | Action | Result |
|---|---|---|---|
| R-A | Cyclift misbehaves, watch reachable | write `original_0x00f000.bin` @0xF000 | factory app starts (default settings view, emulator S7 ✔) |
| R-B | return exactly to factory first 4 MB | write originals in this order: @0xF000, @0x8000, then @0x1000 + @0x5000 | first 4 MB byte-identical to backup (emulator S6 ✔) |
| R-C | anything else / doubt | `ESP write_flash 0x0 P\flash_8MB_read1.bin`, then full read-back | SHA-256 `77ad7105…3767693` |
| Boot loop (Cyclift crashes at start — **no automatic fallback**, emulator S5) | serial shows repeated resets | R-A over USB (automatic reset; fallback: hold BOOT, tap RESET) | factory app |

Stop rules: any failed verify → stop, do R-B for the phase, report. Any unexpected checkpoint result → stop, R-B, report.
