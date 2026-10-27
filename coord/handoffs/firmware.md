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

## Round 2 (0.7.4-rc1) — see report §8
* Instrumented Bluetooth start (same sequence as nimble_port_init; rc + INTERNAL/DMA heap per step; first failed allocation
  size/caps), kept in the NVS boot-record ring (`bc_bootrec`, 4 × 140 B) with the crash PC/task; printed at the next boot and
  in Device Health. Two failed (non-crashing) Bluetooth starts in a row → Bluetooth disabled until RETRY (no retry loop).
* Device Health buffer moved to PSRAM: free internal DRAM 34,645 B (0.7.3: 23,989; 0.7.2: 37,901). sdkconfig and partition
  table byte-identical to 0.7.3.
* Tests (host/simulated, not hardware): host suites incl. new bootrec (12) and the REAL corrupted-image fixture test (10);
  blehost initfail 3 modes (HCI fail with the 8,256-B allocation named, host-task fail, controller-init fail); stress 500
  cycles PASS, prio PASS (power-meter notifications → snapshot → LIVE to the phone); simulator + ASan simulator 301 screens /
  555 checks 0 failed incl. section 25 (12 failing BT starts: no loop; recovery in all 4 BT×FS combinations stays stable 10 s);
  TSan: 23 reports (0.7.3 baseline 20), all in pre-existing UI→host request flags of ble_link.c and in the harness — open item
  for QA, not introduced by this round.
* Kit (NOT run): firmware/waveshare/pc-kit INSTALL-v0.7.4, ROLLBACK-TO-v073/v072, RESTORE-CHOSEN-BACKUP (knows rc1),
  README-v0.7.4, TEST-v0.7.4, generated by tools/make_kit_074.py; delivered copy /home/claude/coord/deliver/fw-v0.7.4/.
* BLE_CONTRACT.md unchanged (still v1 draft).

## Round 3 (0.7.4-rc2) — QA review of rc1 fixed at the root; see report §9
* QA findings QF-01..QF-20: every one fixed or documented (table in report §9). P1s: QF-01 (rides on damaged storage are never
  silent: warning before SAVE, "NOT SAVED ON BOARD" after, summary kept in RAM/PSRAM ≤ 4 rides and sent by the 1.2.3 ride
  sync; a lost ride does not use up an id), QF-02 (no automatic NVS erase anywhere; "Settings memory needs repair", defaults,
  nothing saved).
* Found while testing QF-01 (pre-existing since 1.1, also on 0.7.3): SYNC_RIDE of a ride with time-in-zones + a coaching text
  > ~43 characters exceeded 180 B → encoder returned 0 → that ride was silently skipped by the sync. Fixed in bc_link.c (text
  cut to the room left; rides that fitted are byte-identical); host test added.
* Boot order: display → storage (skipped in RECOVERY after a storage crash) → new DIAG stage (boot record BEFORE the core dump is
  consumed; NVS crash streak ≥ 4 → RECOVERY; BT rule before app_diag_init so RETRY shows at once; skipped after a crash there)
  → RECOVERY decision → Bluetooth stack (15 s panic watchdog guard) → screens.
* Installer (QF-13): backup and write with `--after no-reset`; the installer itself starts the new firmware and records its
  first 90 s (counts `BT init step` / `BOOTREC` lines). ROLLBACK-TO-v073 warns on screen (QF-16).
* Tests (host/simulated, NOT hardware): host xds 228, core 1901, pipe 89, diag 179, storage 71, bootrec 19, fixture 10,
  partitions 65, lint OK, diag fixture unchanged; blehost stress PASS, prio PASS, initfail 15/11/9; TSan 300 cycles: 7 reports,
  none with a firmware frame as the racing access (rc1: 18); simulator and ASan simulator 308 screens / 581 checks, 0 failed,
  0 sanitizer errors (new section 26 + additions to 24d/25a); idf.py build clean.
* Firmware 0.7.4-rc2: app SHA-256 a495bfde97986f2ba207d50ab92ea8bc1fa75fa45935a5513f23f73ed55ee9d9 (1,846,752 B); DIRAM free
  34,201 B (rc1 34,645); sdkconfig and partition table unchanged (partition table = 0.7.3's, not written on this board).
* Kit (NOT run): /home/claude/coord/deliver/fw-v0.7.4/ (INSTALL-v0.7.4-rc2, fw-v0.7.4-rc2/BC074RC2-*.bin, README/TEST rc2,
  KIT-SHA256SUMS.txt regenerated); the rc1 files moved to /home/claude/coord/deliver/fw-v0.7.4-rc1-superseded/.
* BLE_CONTRACT.md → v1.1 (change log at the top; answers Q-iOS-1..14). Wire changes for Cyclift's Link13 code: samples
  grammar (header `J1 …`, missing value `-1`), RIDEQ_ERR 6, demo rides never in the queue (flags bit0 reserved), RIDEQ flags
  bit4 RAM-only, STORAGE_CLEAN refusal set 2/3/4/5/7.
* Privacy (pre-existing, not changed this round): test/sim/sim_main.c uses a first name as the test rider's profile name
  (also asserted at sim_main.c:1168); consider a synthetic name.
* Next: FW-4 (Link 1.3) on a separate commit series — not started in this round's commits.

## Round 4 — FW-4: Link 1.3 (firmware 0.7.5-dev; rc2 kit untouched, still the physical-test candidate)
Commits on fw/phonefirst after 0139267 (QA reads 0139267; not rewritten): 8251e7b (made-up test rider), 3d721b6 (codec +
coach-mirror core + fixture), 6a2f57c (board logic + UI + sim 27), then the stress/handoff commit. Nothing ran on hardware.
* Contract: BLE_CONTRACT.md v1.1 implemented as written, no contract change. Not implemented: RIDEQ flag bit2 "samples
  truncated (storage full)" + the "STORAGE FULL - SUMMARY ONLY" ride screen (flag always 0; samples simply stop when the
  storage refuses writes, the summary path is QF-01's).
* Behaviour: INFO caps + 0xF800; HELLO_ACK = INFO caps AND app caps; nothing new before HELLO (Cyclift RC1 sees 1.2.3,
  sim 27a). Coach: plan in PSRAM (64 segments), CRC + 0xFFFF rule, seq strictly newer, 12 s without COACH_STATE = phone
  lost; card on ride page 2 in designs A/B/C + instruction/target on page 1; offline: stored plan on the ride clock, else
  last targets; watch HR gone -> "NO HR - RIDE BY FEEL". Queue: newest 50 real rides + RAM-only (bit4) + the recording
  ride (state 0); samples CRC computed lazily and cached; verified ids in rides/synced.txt; delete only after a matching
  ACK with delete_samples, never while recording; chunks paced like diag chunks (bulk room + 200 ms). Storage: status
  after HELLO / request / every clean result; clean refused 2/3/4/5/7, busy while recording; clean bit2 = diag/report.txt,
  diag/probe.txt, demo history. DIAG_AUTO: delete only after DIAG_INFO state 1, only when enabled by HELLO.
* Memory: DIRAM free 36,585 B (rc2 34,201 B): the new state is in PSRAM and app_psvc's 2.7 KB state moved to PSRAM too.
* Fixture: firmware/waveshare/test/host/fixtures/link13_fw_fixture.json + Link13FirmwareFixture.swift (make checks it is current).
* Test rider: "Rider A" / "RiderA" / "Rae" in tests; SCAN_RESULT / PROFILE_SET vectors keep their length — the Swift copies
  of those two vectors (and ios/BikeComputerTests files that still use the real first name) are the iOS agent's to change.
  Old docs (docs/FIRMWARE_0.6.x.md, pc-kit TEST-v0.6/0.7.0/0.7.1, POWER docs) still mention the owner's first name.

## Round 5 — 0.7.4-rc3 (QA rc2 findings QF-21..QF-29, on top of Link 1.3)
* Commit 040e6cb (all nine fixes; they share the platform files), then the kit commit. Not run on hardware.
* QF-21 honest texts without Bluetooth; QF-22 RAM slot freed after phone confirmation (1.2 SYNC_REQ after_ride_id /
  1.3 RIDEQ_ACK); QF-23 RESTART / DEEP SLEEP confirmation page + auto-sleep block; QF-24 id floor from history + RAM,
  samples never overwritten; QF-25 RECUI / RECMIN markers -> minimal text -> halt; QF-26 brownouts apart (power toast),
  RTC run streak, NVS crash-run counter before storage, limiter ladder; QF-27 PSRAM history list + report buffer;
  QF-28 read-only FAT consistency check before any clean-up; QF-29 short interrupted rides kept.
* DIRAM free 44,673 B (rc2 34,201; rc1 34,645; 0.7.2 37,901).
* BLE_CONTRACT.md v1.2 (behaviour only, no wire change). Residual documented there: with BOTH NVS and the FAT unusable
  ride ids can repeat across power cycles (no persistent memory) - Cyclift should include start_epoch_s in its dedup.
  Residual QF-26: RTC lost at every crash AND NVS failing - no counter survives (S4b with both stores gone).
* Kit 0.7.4-rc3: /home/claude/coord/deliver/fw-v0.7.4/ (rc2 files in /home/claude/coord/deliver/fw-v0.7.4-rc2-superseded/).
  App SHA-256 10c9a7a79085c47a304a52789223368b61d8479c6c13ca71626396941585f306 (1,875,840 B).
