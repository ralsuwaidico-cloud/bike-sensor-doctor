# Independent QA delta review: BikeComputer firmware 0.7.4-rc2

Reviewer: QA agent (independent, read-only). Date: 27 Oct 2026.
Code under review: `0139267` (`52e5d31` contains the rc2 fixes; `0139267` adds BLE_CONTRACT v1.1). Compared with rc1 `a0af3d2`.
Kit: `/home/claude/coord/deliver/fw-v0.7.4/`. Finding table: `FIRMWARE_FINDINGS_RC2.csv`, with the status of QF-01..20 and the new findings QF-21..29.

**What this review covers:** code reading, host builds and tests, the simulator, the BLE glue harness, and my own probes.
Nothing was run on hardware.

## 1. Verdict

**GO for offering rc2 to the owner for the physical test.** No P0, and no open P1. Both rc1 P1s are fixed:
- **QF-01:** a ride on damaged storage is never lost silently.
- **QF-02:** there is no automatic NVS erase left.

I checked all 18 P2s from rc1. 17 are fixed. QF-17 (Link 1.3) stays open by design (FW-4). The new findings are all P2. Six of them are residual edges of the fixes, and QF-27 (internal-RAM) and QF-29 (contract) are observations. Fix them before release.

- **Kit:**
  - All 29 entries in KIT-SHA256SUMS.txt match, and every file is byte-identical to `pc-kit/` at `0139267`.
  - The app I rebuilt from `0139267` differs from `BC074RC2-app.bin` only in the build time, the ELF SHA and the image hash (71 bytes).
  - The partition table is byte-identical to 0.7.3's and is not written on this board.
- **Tell the owner:**
  1. When Bluetooth is unavailable at a start, a ride recorded on the board cannot reach Cyclift. It stays in memory only until sleep, restart or power-off (QF-21, QF-23). The screen still says "Open Cyclift to copy it".
  2. Each power cycle keeps at most 4 rides in memory, even after they have reached the phone (QF-22).

## 2. Verification of the rc1 findings (detail in the CSV)

| Area | How I checked | Result |
|---|---|---|
| Recovery before storage (QF-03) | Rewrote the probe for rc2's `main.c` order (`probes/boot_probe_rc2.c`, using the real `bc_boot.c` and `bc_bootrec.c`). | **Crash in the storage stage:** 3 crash resets, RECOVERY at boot 4, storage not started, stable. **Crash in diagnostics:** same result. The simulator's section 26a agrees. |
| 4-crash forced recovery (QF-09) | Probe cases S4 (RTC lost at every crash) and S6 (each crash more than 20 s after the start). | RECOVERY at boot 5 in both, where rc1 had none in 12 boots. Not covered: NVS failing too (S4b and S6b are unbounded), and a storage-stage crash with RTC lost (S7b), because the NVS check runs after storage (QF-26). 4 brownouts in a row on a healthy board also force RECOVERY (S11). |
| BT fail streak, RETRY, NVS failure (QF-07, QF-08) | Simulator 25a; probe S8. | RETRY now appears on the boot that disables Bluetooth. With NVS writes failing, RETRY leads to a real new attempt. |
| Pinned Bluetooth evidence (QF-06) | Probe S10. | After 2 failed and 10 skipped boots, `last_bt_try` is still boot 2, "HCI init failed". |
| Verified core-dump erase (QF-05) | Code reading. | The FAT copy is read back and its CRC compared with the partition data before the erase. |
| Crash PC and task in the NVS record (QF-04) | Code reading. | The boot record is now written before `app_diag_init`. |
| 15 s Bluetooth start watchdog (QF-10) | Code reading against IDF 5.5.1 and the build's sdkconfig. | The main task subscribes only for the stack start (controller init and enable, `esp_nimble_init`), with panic on expiry; the original 5 s, no-panic setting is restored afterwards. A healthy start is PHY calibration plus controller plus NimBLE, well under 1 s even with a full RF calibration, so **15 s cannot fire on a slow but healthy start**. The idle-task checks get the longer 15 s timeout during the window. A watchdog panic resets as TASK_WDT, which the boot plan counts as a crash with the BTSTACK marker, so the stack is skipped after two. The guard does not cover the host-task part of `ble_central_start`, which is minor. |
| IRAM alloc hook, atomics (QF-11, QF-15) | Code reading; sdkconfig; TSan. | The hook is `IRAM_ATTR`, uses only `__atomic` operations and `xTaskGetCurrentTaskHandle` (in IRAM, since `FREERTOS_PLACE_FUNCTIONS_INTO_FLASH` is unset), and filters by task. TSan at 300 cycles gives 8 reports. **Every racing access is in the fake or the harness**; firmware code appears only as a caller deeper in the stack (rc1: 6 firmware variables). |
| Partial-directory detection (QF-12) | Host tests; real fixtures. | Any erased or garbage root entry now means "Directory corrupted". The real healthy fixture still classifies OK and the real corrupted one as corrupted, so there are no false positives on the real images. |
| Full-storage deletion (QF-18) | Code reading; simulator 26c. | It deletes only reports in state 1 (the phone sent DIAG_ACK with a CRC matching the index) and their core copies, then re-checks. Unsent reports and rides are never touched. **Residual (QF-28):** if FULL comes from allocation-table damage, an unlink can free other files' clusters. This cannot happen on the owner's board, which is "Directory corrupted" with 5 MB free. |
| RAM ride queue (QF-01) | Code reading; simulator 24d. | The warning appears before SAVE and a notice after it. The summary goes to PSRAM through a line round-trip, so its bytes match the file format, and it is sent by the shipped 1.2.3 SYNC_RIDE stream (the simulator checks this). Residuals QF-21 to QF-23. |
| NVS-problem mode (QF-02) | Code reading. | Runs on defaults with no onboarding and no saving. **Residual (QF-24):** `next_ride_id` restarts at 1 on every start, so ride ids are reused. On a healthy FAT that overwrites `rides/r0001.txt`, and it breaks contract §6's "the board never reuses an id". Unverifiable here: whether IDF's PHY, NimBLE store and Wi-Fi behave cleanly with NVS uninitialised. |
| Internal RAM | `idf.py size` on my own rc2 build. | 34,201 B free DIRAM (rc1 34,645; −444 B confirmed). Still 3.7 KB below 0.7.2 (QF-27). |

## 3. Tests I re-ran (copy at `/home/claude/qa-fw/build-rc2`, under `heavy.lock`)

| Suite | Mine | Firmware agent |
|---|---|---|
| host: xds / core / pipe / diag / storage / bootrec / fixture / partitions | 228 / 1901 / 89 / 179 / 71 / 19 / 10 / 65, **0 failed** | identical |
| blehost: stress 1000 cycles, prio ×2, initfail 0/1/2 | PASS; PASS; 15 / 11 / 9 checks, 0 failed | identical |
| TSan (300 cycles) | 8 reports, 0 in firmware code | "7 reports, none with a firmware frame" (count varies by run) |
| simulator, normal and ASan | 308 screens, 581 checks, 0 failed; 0 sanitizer errors | identical |
| `idf.py build` | OK; app 1,846,752 B = kit except build time and hashes | identical |

Probe output is in `logs-rc2/boot_probe_rc2.txt`.

## 4. Installer, rollback, restore

**INSTALL-v0.7.4-rc2.ps1:**
- **Pre-checks, before anything is written:** the factory backup is present at 16 MB, the 4 rc2 files match their SHA-256, and the 0.7.3 and 0.7.2 rollback images are intact.
- **Backup:** `esptool --chip esp32s3 -b 921600 --after no-reset read-flash 0x0 0x1000000 backup-before-v074-<t>.bin`. It is then verified: 16 MB, a known app hash at 0x20000 (segment walk), and a known partition-table hash at 0x8000.
- **Write, only after the owner types YES:** `esptool --chip esp32s3 -b 460800 --after no-reset write-flash [0x8000 table only if the board has the old table] 0xf000 otadata(8 KB, all 0xFF) 0x20000 app`.
  - Erasing reaches 0x1E2FFF at most, which is inside ota_0. esptool v5.6 verifies each region's hash.
  - **NVS (0x9000–0xEFFF), phy_init, coredump and storage (0x820000 onward) are never read for writing, erased or written.**
- **No firmware runs between the backup and the write:**
  - The read ends with no reset.
  - The write call's default `--before default-reset` puts the chip into download mode again.
  - If the owner does not type YES, or the script stops, the board stays in download mode and the script tells the owner to unplug and replug it.
- **Capture:** the script opens the port first, then pulses RTS with DTR low. That is an EN reset with IO0 high, so this is the new firmware's first start. It records 90 s from the first line.
  - The board uses a UART bridge: the real 0.7.3 first-boot log shows `rst:0x1 (POWERON)` after the same pulse, not a USB-JTAG re-enumeration.
  - **If the board crash-loops during the capture:** the crash and reset-reason patterns set CRASHED, which is reported first. rc2 then reaches RECOVERY after 3 crashes (or 4 by the NVS records), and the log keeps everything.
  - A port that cannot be opened leaves the firmware installed but not started, and the script prints the replug hint.

**Rollback and restore:**
- ROLLBACK-073 and ROLLBACK-072 write only 0xf000 and 0x20000, after checking checksums. The 073 script now warns on screen.
- RESTORE writes a backup the owner picks, and knows the rc2 hash.
- READ-BOARD-STATE is unchanged (read-only, `--after no-reset`).

## 5. BLE_CONTRACT v1.1

- **Consistent with itself:** the change log matches the sections. The §6.1 samples grammar matches the firmware: header `J1 id demo ftp how est` from `app.c:250`, data lines `%d %d %d %lu` from `app.c:148`, `-` for a paused second, and recovery parsing that ignores a torn last line.
- **v1.1 edge cases:**
  - `summary_crc32` over the SYNC_RIDE TLVs stays well defined for RAM-only rides, because they are stored through the same line round-trip.
  - The RIDEQ_ERR 6 and flags bit0/bit4 changes are additive.
  - The STORAGE_CLEAN refusal set matches the firmware categories.
- **Gaps:**
  - The "never reuses an id" rule is not met in NVS-problem mode (QF-24).
  - Release of RAM-only rides after RIDEQ_ACK is undefined (QF-22).
  - The firmware still drops an interrupted ride shorter than 10 s with a log line only, against §1 "never silently discard" (QF-29).
- **Backward compatibility:** rc2 is still wire-compatible with Link 1.2.3. The one change is the SYNC_RIDE coaching text, now cut to the room left. Before, a long text made the encoder return 0 and the ride was skipped by the sync. The shipped Cyclift decodes tag 0x18 at any length (`BCLink.swift` decodeSyncRide), and rides that fitted before are encoded byte-identically. The contract's statements about the shipped app (unknown Control types counted as rejected, unknown LIVE tags skipped) still hold.

## 6. What only the board can confirm

- The first-boot log's per-step Bluetooth figures, which turn the RAM inference into a measurement.
- That the 15 s guard never fires on this chip.
- That rc2 starts cleanly with the 0.7.3 RTC state left behind.
- That RAM-only rides reach Cyclift when Bluetooth works.
- That the "Directory corrupted" screen appears and no FAT write happens: compare a READ-BOARD-STATE storage read before and after.
- How the board behaves in NVS-problem mode (IDF PHY, NimBLE store, Wi-Fi), which can only be tested on hardware.
- Real power-meter to board to Cyclift data.
