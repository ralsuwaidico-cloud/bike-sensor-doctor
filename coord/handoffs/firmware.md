# Firmware handoff — FW-1, FW-2, FW-3 draft (27 Oct 2026)

Branch `fw/phonefirst` (from `ios/dev`), firmware **0.7.4-dev**. Nothing was flashed, read from, reset or erased on the board.
Nothing here is verified on hardware.

## FW-1 findings (details + evidence levels: `coord/reports/FW_STORAGE_MEMORY_REPORT.md`)

| Finding | Evidence |
|---|---|
| Board runs 0.7.3: ELF `fa0edc5ac…`; the existing ws-073 build is byte-identical to the delivered app (`181b2e5c…`) | board log + build |
| Crash = `ESP_ERROR_CHECK(nimble_port_init())`, `ble_central.c:598`, `app_main` → abort (backtrace decoded with that ELF) | board log + ELF |
| "hci inits failed" after a successful controller enable can only come from an internal-RAM allocation (`ble_buf_alloc`, semaphore) in ESP-IDF 5.5.1 | source |
| 0.7.3 vs 0.7.2: −13.9 KB static internal DRAM (app_diag statics 9.6 KB, core-dump stack, ISR stacks), and Bluetooth now starts **after** profile/UI/diag instead of before; BT config identical; 0.7.2's host did start on this board (NVS `link:idaddr` written while 0.7.2 ran) | build + backups |
| → internal-RAM exhaustion at BT start: strongly indicated, **unconfirmed** (heap at that instant never logged; 0.7.4-dev logs it) | inferred |
| "disabled 0x000": 0.7.3 only disabled subsystems in a *staged* boot, and still called `ble_central_start()` when the phone link was "skipped" | board log + source |
| Flash NOT full: 16 MB; app 1.83 MB / 4 MB slot; FAT 5096 KB free / 7964 KB (board log = backup reconstruction, exact match); NVS 1 empty + 1 active page, 115 reclaimable entries | board + backups |
| FAT root directory: 512/512 entries erased (0xFF) → nothing can be created or found → "Logs NOT saved (storage)". **Lost between 24 Oct 20:18 and 25 Oct 13:52** (boots 8→122, **72 crash resets**, firmware 0.4.0–0.6.0); interrupted selftest.txt rewrite measured at boot 39 | backups |
| After the loss, `mkdir()` on every file call churned ~300 directory clusters / ~1900 WL erases; `format_if_mount_failed = true` would have wiped the FAT on any mount failure | backups + source |
| 713 FAT clusters (2.85 MB) wrongly marked used since the first format (FAT bytes 0xFF from offset 1920); cause unknown | backups |
| On the FAT: no saved ride, no report; one 59-byte ride journal (orphaned); NVS has profile (706 B), PHY cal, counters; no phone bond in the latest backup | backups |
| Mechanism that erased all 4 root sectors: **open** (only sector 1 was ever written; WL relocation is power-safe, TRIM ignored, installers never write storage) | — |

## FW-2 changes (commits on `fw/phonefirst`)

* `5d832e2` stage 1: `bc_storage` (categories, FAT BPB + root scan, host-tested), boot plan rule (a subsystem that crashes twice
  in a row while starting is disabled even in a NORMAL boot; new subsystem `BTSTACK`), `pc-kit/READ-BOARD-STATE.{ps1,bat}`,
  `tools/storage_audit.py`.
* `53ffdfb` stage 2 + later commits:
  - `ble_central_stack_init()` / `ble_central_start()` return bool, no ESP_ERROR_CHECK; heap (free / largest / DMA) logged
    before init and on failure; host-task creation checked; "Bluetooth unavailable" + reason on Connections, Phone (WHY? /
    RETRY), Settings, Device Health, recovery SEND LOGS; `PLAT_PHONE_UNAVAILABLE` appended to the enum.
  - Start-up order: Bluetooth stack right after storage, before touch/profile/screens (0.7.2 order). A skipped stack or phone
    link is really not started; recovery SEND LOGS does not restart a Bluetooth disabled after crashes.
  - app_diag state + buffers: one PSRAM allocation (−8.75 KB static internal DRAM vs 0.7.3; DIRAM remaining 32,749 B vs 23,989).
    sdkconfig is byte-identical to 0.7.3 (I tried `SPIRAM_ALLOW_BSS_SEG_EXTERNAL_MEMORY` and reverted it: in IDF 5.5.1 it also
    moves NimBLE host / lwip / Wi-Fi bss to PSRAM — an unverifiable change on the BT data path).
  - Storage: no automatic format; read-only root-directory scan through WL; no probe write into a damaged directory; probe
    moved to `diag/probe.txt` (no root-directory rewrite every boot); categories on recovery screen ("Not saved: Directory
    corrupted"), Diagnostics SAVE REPORT toast, Device Health ("Storage …", "Crash record …"); `plat_esp.c` writes/creates/
    renames nothing unless storage is OK (removes allowed when FULL), `mkdir` only before writes; last errno → Storage full vs
    Write failed.
  - Core dump erased only after its raw copy reached the FAT; core copies deleted with their report (were unbounded).
  - Ride journal: never deleted when it cannot be kept (moved aside as `rides/unsaved-*.jnl`; unreadable → `rides/unreadable-*.jnl`).
  - Touch: own error-tolerant read (the vendored esp_lvgl_port callback `ESP_ERROR_CHECK`ed every I2C read in the UI task);
    I2C bus init no longer aborts. Remaining ESP_ERROR_CHECKs: display/LVGL init only (start-up, no degraded mode exists).
* Tests (all host/simulated — NOT hardware): `test/host` all suites green (xds 228, core 1899, pipe 89, diag 174 incl. the new
  boot-rule cases, **storage 69 (new)**, partitions 63, diag fixture regenerated: only change = phone state 6 now named
  `bt_unavailable` in one synthetic event line → iOS copy `ios/BikeComputerTests/Fixtures/diag_fw_fixture.json` should be
  refreshed by the iOS agent; it stays self-consistent meanwhile); `make lint` OK; `test/blehost`: **initfail** (HCI init failure
  11/11, host-task failure 9/9), stress 300 phone cycles PASS (ASan, no violations), prio PASS; **simulator** 296 screens / 530
  checks, 0 failures, incl. new section 24 (BT unavailable screens, crash twice at the BT stack → disabled + RETRY, recovery
  "Not saved: dir corrupted", SAVE REPORT toast, Device Health category, event log/index byte-identical on damaged storage,
  ride on damaged storage writes nothing) and the 200-cycle stress; `idf.py build` clean, app 1,838,656 B, sdkconfig and
  partition table byte-identical to 0.7.3. Not run this round: simulator ASan build, blehost TSan.

## Needs owner approval (through the lead)
1. **Run `pc-kit/READ-BOARD-STATE.bat`** — read-only, but resets the board into download mode. Gives the core dump, NVS,
   storage and a fresh full backup; optional step 2 records a boot log.
2. Flashing 0.7.4-dev (after QA) — kit not built yet (INT/FW-4). Expected on the board: no abort; either Bluetooth works
   (heap figures in the log) or "Bluetooth unavailable" with the reason; recovery screen / Device Health say
   "Directory corrupted".
3. Storage repair (report §7) — PC-side, writes only the storage region, after (1). Not started.

## Open / next (FW-4)
* Coach screen in every layout, BLE contract implementation (HELLO, COACH, RIDEQ, STORAGE), offline ride queue, retention.
* Privacy note for the lead: `test/sim/plat_host.c` (pre-existing, not mine) contains a hard-coded device id that differs from the
  board's real Bluetooth address (seen in the serial log) in only the last byte — consider replacing it with a neutral value.

## Contract summary for the iOS agent (`coord/interfaces/BLE_CONTRACT.md`, draft v1 = Link 1.3)
* Phone = brain (profiles, plans, adaptive decisions, history, diagnostics storage); board = sensors, live display, ride clock,
  offline recording, minimal diagnostics.
* New INFO caps 0x0800 HELLO, 0x1000 COACH, 0x2000 RIDE_QUEUE, 0x4000 STORAGE, 0x8000 DIAG_AUTO. Phone sends APP_HELLO 0x08
  (Control) with its caps; the board enables new board-initiated messages only after that → old app unaffected.
* COACH_PLAN 0xB0 (multi-part, 10-byte segments, CRC) + COACH_STATE 0xB2 (targets, cadence, interval idx/remaining, next
  interval, instruction code + ≤ 24-B text, session state, HR source) every change + 5 s; board echoes `coach_seq` in LIVE
  tag 0x11, `coach_mode` 0x12 (2 = phone lost, following stored plan). Segment timing on the board's elapsed time.
* RIDEQ 0x90–0x96: list / CRC-verified chunk pull (same layout as DIAG_CHUNK) / ACK with both CRCs → delete-after-verify;
  BUSY while recording; EVENT 0x23 rides_pending.
* STORAGE_STATUS 0xA1 (state + code incl. `dir_corrupted`, FS/diag/ride/app/NVS figures, crash partition) and
  STORAGE_CLEAN 0xA2/0xA3 (only verified-synced items; never unsynced rides / unsent reports / NVS; no BLE repair).
* HR: Apple Watch HR only as fresh phone-relayed IN_HR; on link loss the board shows no watch HR.
* Open questions in §10 of the contract.
