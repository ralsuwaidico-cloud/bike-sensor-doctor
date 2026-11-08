# Independent QA review: BikeComputer firmware 0.7.4-rc1

Reviewer: QA agent (independent, read-only). Date: 27 Oct 2026.
Code under review: `a0af3d2` (branch `fw/phonefirst`), compared with 0.7.3 `1cf8cf0` and 0.7.2 `ec0aad9`. Install kit:
`/home/claude/coord/deliver/fw-v0.7.4/`. Findings with file:line evidence are in `FIRMWARE_FINDINGS.csv` (QF-01 to QF-20).

**What this review covers:** code reading, host builds and tests, the simulator, the BLE glue harness, and probes I wrote myself.
No hardware was used. Nothing below has been verified on the board.

## 1. Verdict

**GO, with conditions, for offering rc1 to the owner for a physical test. NO-GO for release.**

- **No P0 found.** The kit writes only the app (0x20000) and otadata (0xF000). The board's partition table is already 0.7.3, so the table is not written. NVS (0x9000–0xEFFF), phy_init, coredump and storage (0x820000 onward) are never written or erased.
- The firmware never formats or writes to the damaged FAT.
- Bluetooth start-up can no longer abort.
- The app binary rebuilt from `a0af3d2` matches the kit binary except for the build time, the ELF SHA and the image hash (70 bytes).
- **Two P1 findings must be fixed before release:**
  - **QF-01:** on the owner's board, rides are silently lost.
  - **QF-02:** an automatic whole-NVS erase path is still in the code.
- **Conditions for the physical test:**
  1. Tell the owner that on this board, a ride recorded on the device (TEST D4) will **not** be saved, because the directory is corrupted, and that no on-screen message says so (QF-01).
  2. Keep the 90 s first-boot serial log. It is the only place the per-step Bluetooth heap figures survive (QF-06): the installer's own two boots disable Bluetooth, and steps A1 and A2 then overwrite the 4-slot ring before step B2 reads it. Better still, move B2 directly after the install.
  3. After the install, expect "NO BLUETOOTH" with **WHY?** (not RETRY) on the first boot. RETRY appears from the next start (QF-07).
  4. ROLLBACK-TO-v073 reinstalls firmware that aborts at every start on this board. Use RESTORE-CHOSEN-BACKUP for going back (QF-16).

## 2. Verdict per owner requirement (12:27)

| # | Requirement | Verdict | Basis |
|---|---|---|---|
| 1 | BLE init failure never loops: record, disable, stable | **Met in code and simulation; needs the board to confirm** | `ESP_ERROR_CHECK` is gone and every step returns a code (`ble_central.c:644-669`). The failure is recorded in RAM and in the NVS ring. My probe of the real `bc_boot.c` and `bc_bootrec.c`: a start that fails 12 times gives 0 crashes and Bluetooth disabled from boot 3 (S1). A start that panics 12 times gives 2 crash resets and then skips Bluetooth (S2). The same holds when NVS writes fail (S3). Sim section 25 passes. Gaps: no RETRY on the disabling boot (QF-07), a hang is not caught (QF-10), the crash streak lives only in RTC (QF-09). |
| 2 | Actual cause of the `nimble_port_init` failure | **Partly; the cause itself needs the board** | The instrumented sequence matches IDF 5.5.1's `nimble_port_init` for the ESP32-S3 (see §4). It records the return code and the INTERNAL and DMA heap after every step, plus the first failed allocation. The cause is still an **inference** (internal-RAM shortage). The 8,256 B "failed allocation" in the tests is injected by the fake (QF-14). The board's ring loses the evidence after a few boots (QF-06). |
| 3 | Filesystem investigated independently; backups kept; no erase without approval | **Partly** | I confirmed the corrupted-image fixture is the real head of `fat_nowl.bin` (byte-identical). It classifies as "Directory corrupted" with 5,096 KB free. `format_if_mount_failed = false`, and there is no `f_mkfs` or `esp_vfs_fat_*format` anywhere. The installers never write storage. But an automatic **NVS** erase remains (QF-02), the corruption heuristic only catches total loss (QF-12), and the installer reboots 0.7.3 between the backup and the write (QF-13). |
| 4 | Crash diagnostics independent of the filesystem | **Partly** | The coredump partition, the NVS ring (4 × 140 B with CRC, written only from `app_main`) and the RTC log tail are all outside the FAT. No panic, abort or shutdown hook touches the FAT or NVS: there are no custom handlers, and the log hook only writes RTC RAM and stdout. Gaps: the ring holds the crash PC/task only when the FAT is *broken* (QF-04), the dump is erased without verifying the copy (QF-05), and the ring is overwritten (QF-06). |
| 5 | Board lightweight; phone owns storage, analytics and coaching | **Not met (design only)** | BLE_CONTRACT v1 is a draft and none of §4–§8 is implemented (FW-4 / IOS-1). rc1 is wire-identical to Link 1.2.3, so it is compatible with the shipped Cyclift (QF-17). |
| 6 | Recovery works with Bluetooth and/or the filesystem unavailable | **Partly** | Recovery needs no Bluetooth, and a mount failure or damaged directory is handled. Sim: all 4 BT×FS combinations stay on a stable recovery screen. But storage, diagnostics init and NVS all run before the recovery decision, so a filesystem that *crashes* loops even in RECOVERY (QF-03; probe S7: 12 boots, 12 crash resets). |
| 7 | Tested: repeated BLE init failures, corrupted storage, crash recovery, power-meter data | **Partly (host and sim yes, hardware no)** | Every suite re-runs green (§3). The simulator re-implements `main.c`'s order (`device_boot`) rather than running `main.c`. The blehost harness runs the real `ble_central.c` and `ble_link.c` on a fake NimBLE. The power-meter path to LIVE is shown only on the fake (prio). |

## 3. Tests I re-ran (copy at `/home/claude/qa-fw/build-copy`; all heavy jobs under `heavy.lock`)

| Suite | Mine | Firmware agent |
|---|---|---|
| host: xds / core / pipe / diag / storage / bootrec / fixture / partitions | 228 / 1899 / 89 / 174 / 69 / 12 / 10 / 65, **0 failed**; diag fixture check OK | same (partitions previously reported as 63; 65 now) |
| blehost stress (ASan, 1000 phone cycles) | PASS, no violations | 500 cycles PASS |
| blehost prio (40/30, 40/150) | PASS / PASS | PASS |
| blehost initfail modes 0/1/2 | 12 / 9 / 7 checks, 0 failed | 3 modes PASS |
| blehost TSan (300 cycles) | 18 reports (see QF-15) | 23 (cycle count differs) |
| simulator normal / ASan | 301 screens, 555 checks, 0 failed / same, 0 ASan or UBSan errors | 301 / 555 |
| `idf.py build` | OK; app 1,841,232 B; DIRAM free 34,645 B; partition table byte-identical | same |
| KIT-SHA256SUMS.txt | all 30 entries match | — |

Logs are in `/home/claude/qa-fw/logs/`.

**Own probes:**
- `probes/boot_probe.c`: the real boot-plan and ring code under adversarial reset sequences (output in `logs/boot_probe.txt`).
- `probes/nvs_census.py`: counts only, no values printed.
- A simulator copy with section 25 shortened to 3 boots, which reproduces QF-07 (`logs/sim_probe_retry.log`).

## 4. Bluetooth start-up versus IDF 5.5.1

`ble_central_stack_init()` uses the same calls in the same order as `nimble_port_init()`
(`components/bt/host/nimble/nimble/porting/nimble/src/nimble_port.c:175-226`) for the ESP32-S3:
- `esp_bt_controller_init`, then `esp_bt_controller_enable(BLE)`, then `esp_nimble_init`;
- on an enable failure, deinit; on an `esp_nimble_init` failure, disable and then deinit;
- no `mem_release` (that is ESP32-only) and no HCI log.

It also inherits IDF's own leaks when the HCI init fails: the npl funcs/mempool, and the transport pools after a semaphore failure. These are harmless because there is no second attempt in the same boot (the `s_init.failed` guard), and RETRY works by restarting the board. A host-task failure leaves `s_events_ready` set, which is latent only (QF-19).

The claim that "hci inits failed" after a successful enable can only be an internal-RAM allocation is consistent with the source:
- `ble_buf_alloc` and `os_msys_buf_alloc` use `bt_osi_mem_calloc`, with `CONFIG_BT_NIMBLE_MEM_ALLOC_MODE_INTERNAL=y`;
- the alternatives are `esp_vhci_host_register_callback` and `xSemaphoreCreateBinary`.

That RAM is the cause on this board is still **unmeasured**.

## 5. Install, rollback and restore kit

- **INSTALL:**
  - Before anything is written, it checks the factory backup, all four 0.7.4 checksums and the 0.7.3/0.7.2 rollback images.
  - It then takes a full 16 MB read and checks it: size, a known app hash at 0x20000 and a known table hash.
  - The single write command is `write-flash [0x8000 table only if the board has the old table] 0xf000 otadata(8 KB, all 0xFF) 0x20000 app`.
  - Erasing reaches only 0x1F1FFF, which is inside ota_0. esptool v5.6 verifies the hash of each region.
- **ROLLBACK-073 / 072:** write only 0xf000 and 0x20000, after checking checksums. The images are byte-identical to the ones delivered earlier.
- **RESTORE:** writes a whole backup the owner chooses (by design). It checks the app identity only.
- **READ-BOARD-STATE:** reads only (`--after no-reset`) and cross-checks each region against the full read.
- Weaknesses: QF-13 and QF-16.

## 6. What only the board can confirm

- That 0.7.4-rc1 does not abort at start, and how Bluetooth starts on this board: the per-step return codes and heap figures, and the first failed allocation. Only these turn the internal-RAM inference into a measurement or rule it out.
- Whether Bluetooth starts at all with the earlier start order (0.7.2 order).
- That the screen shows "Directory corrupted" and no FAT write happens: compare a READ-BOARD-STATE storage read before and after.
- That the RTC crash streak, NVS skip and boot ring persist across real panic, brownout, watchdog and power resets.
- Whether a hang can occur during the Bluetooth start (QF-10).
- Real power-meter to board to Cyclift LIVE data and its latency.
- Recovery-screen stability on the real round display.
