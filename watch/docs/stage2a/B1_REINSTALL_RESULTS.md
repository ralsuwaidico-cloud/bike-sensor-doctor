# B1 — Stage 1 re-installation results (9 Nov 2026, 21:38–21:51 Dubai)

Owner approval: B1 only (21:24). B2 (hands-on validation) and B3 (rollback) not approved and not run.
Firmware: `cyclift-stage1-v3poc-T-Watch-2021-V1_1.bin`, SHA-256 `faa2828f…aead5cba7` (unchanged, re-hashed on the PC). No diagnostic firmware.
Watch powered by USB only (no battery fitted).

## Script changes before the run (offline, CI-tested)
* `pc_reinstall_runner.py` (PC: `cy_reinstall.py`): re-install pre-check for the post-Recovery-B state (approved image already at
  0x400000, Cyclift data area in use); archives (copies) the first-install records to `first_install_20261109\`; stronger C3 check.
* `pc_install_runner.py` (PC: `cy_install.py`) Phase 3: factory-settings reference snapshot taken right before the write. Found by
  the new end-to-end simulation: with the mandatory phase-end restart the factory app advances its own boot counter after the C2
  snapshot, so the old check would have stopped a correct installation at C3.
* `test_reinstall_sim.py`: first install → Recovery B → re-install on a modelled 8 MB flash (12 checks). CI run 42664674354
  (commit 59b16a2): all 5 jobs passed, 52/52 checks. PC copies verified by SHA-256 (cy_install ccb57a4c…, cy_reinstall f2cdec60…,
  device_session 6c2e3d91… unchanged); previous cy_install kept in `tools\backup_A0_20261109\`.

## Run
| Step | Result |
|---|---|
| precheck_re (read-only) | 34 PASS, 0 FAIL: chip ESP32-PICO-V3-02 v3.1, 8 MB, COM4 exclusive, backup 77ad7105…, pieces/manifest, firmware faa2828f…, header DIO/40m/8MB, first 4 MB = backup except factory settings (osw-config), factory table + app0 selected, upper flash = exactly the approved image, recovery files present and validated; baseline factory boot confirmed |
| Phase 1 — 0x400000 write + verify | FLASH VERIFIED; C1 factory start confirmed, boot counter advanced; phase-end boot confirmed |
| Phase 2 — 0x1000, 0x5000 | FLASH VERIFIED; C2 factory start confirmed, counter advanced; boot confirmed |
| Phase 3 — 0x8000 | FLASH VERIFIED; C3 factory start under new table confirmed (Cyclift-area counter 0 → 1); original factory settings unchanged; boot confirmed |
| Phase 4 — 0xF000 (switch) | FLASH VERIFIED; C4 Cyclift Stage 1 start confirmed: one start, banner, first frame 565 ms, heap 188,804 B, PSRAM 2,097,152 B, flash 8 MB |
| post (read-only, full 8 MB) | changed ranges vs pre-check: 0x1000, 0x5000, 0x8000–0xA000 (table + factory counter), 0xF000, 0x700000 (factory counter at C3); factory app, factory files, OTA sector 0 byte-identical; matches the approved map; final restart: **BOOT CONFIRMED, Cyclift** (21:50:20) |
| Owner visual check | **Cyclift interface shown** on the watch |

The watch was left running Cyclift (not in download mode). Touch was not tested (open hardware question; not treated as a firmware defect).
