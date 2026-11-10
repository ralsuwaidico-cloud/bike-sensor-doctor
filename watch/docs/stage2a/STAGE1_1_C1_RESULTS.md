# Stage 1.1 — C1 installation results (10 Nov 2026) — owner-approved C1 only

Firmware: `cyclift-stage1.1-v3poc-T-Watch-2021-V1_1.bin`, SHA-256 `3274b8877df0a23a5e5cb1364868322d79d643d29411b36782b6bfb34eb937ba`.
Tool: `cy_update_s11.py` (= `pc_update_s11_runner.py`, unchanged since review) with `device_session.py` b16d9125… (logging fix).

## Attempt 1 (09:21 Dubai) — stopped, nothing written
- All file checks passed; the read-only full-flash read failed after ~90 s (`read_flash 0x0 failed`), esptool's error text
  was not logged. Tool stopped ("no further writes"), restart confirmed, Stage 1 running. Owner informed; no action taken.
- Fix (owner-approved, tools only, commit 527f3c5): esptool's own error text is logged on any failed command; new test.
  CI 42784578347 all six jobs green. PC copy verified b16d9125…; previous file kept in `tools\backup_C1_20261110\`.

## Attempt 2 (12:59–13:05 Dubai) — PASSED
- `s11_pre` (read-only): chip ESP32-PICO-V3-02 / 8 MB; backup 77ad7105…; plan pieces; Stage 1 file faa2828f…; Stage 1.1 file
  3274b887…, header DIO/40m/8MB, fits app1; full read OK; installed layout = planned; app1 = approved Stage 1; factory app
  and factory files byte-identical to the backup; OTA selects app1; write plan 0x400000–0x4F6FFF (1,011,712 B); rest of app1
  erased; baseline Stage 1 started once. PHASE PASSED, boot confirmed.
- `s11_write`: FLASH WRITE OK 0x400000; FLASH VERIFIED 0x400000 (esptool verify_flash, byte comparison); restart with
  ROM `POWERON_RESET, boot:0x13 (SPI_FAST_FLASH_BOOT)`, one start, banner marker "Stage 1.1". PHASE PASSED.
- `s11_post` (read-only full read vs. s11_pre): 247 changed sectors (= 0xF7000 / 4 KB, the write span); outside the app1
  span and Cyclift data area: none; app1 = Stage 1.1 + erased padding. Final restart: one start, "Stage 1.1". PHASE PASSED.
- Bootloader, partition table, OTA record, factory app, factory settings and files: unchanged (byte comparison).
- End state: watch running Stage 1.1 (not in download mode). Stage 1 file and all recovery files unchanged.

## Not done / open
- Owner visual confirmation of the Cyclift interface: pending.
- C2 hands-on tests and C3 rollback: not approved, not run. No Bluetooth or feature work.
