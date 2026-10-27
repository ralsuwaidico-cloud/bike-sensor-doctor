# BikeComputer — storage and memory report (FW-1)

27 Oct 2026, firmware agent, branch `fw/phonefirst`. Owner brief 12:15 ("measure first, don't guess").
Nothing here was measured on the live board after the 0.7.3 install except what its own serial log printed; a fresh board read
needs `pc-kit/READ-BOARD-STATE.bat` (read-only, resets the board into download mode → **owner approval required**).

**Evidence levels used below**

| Tag | Meaning |
|---|---|
| **B** | measured on the board: its own serial log `first-boot-v073-20261027-120437.txt` (3 boots of 0.7.3) |
| **K** | measured on a full 16 MB flash backup read by the installer kit (the newest is from just *before* 0.7.3 was written) |
| **E** | measured on build artefacts (ELF/map/bin) that are proven identical to what was installed |
| **S** | read in source code (ours or ESP-IDF 5.5.1) — deterministic, but not observed on the board |
| **I** | inferred from the above |
| **U** | unconfirmed hypothesis — needs a board read or a hardware test |

## 0. Summary — what is and is not the problem

| Question | Answer | Level |
|---|---|---|
| Is flash full? | **No.** 16 MB detected; app uses 1.83 MB of its 4 MB slot; the FAT has 5096 KB free of 7964 KB; NVS has 1 empty + 1 active page and 115 reclaimable entries. | B, K, E |
| Is RAM exhausted? | **Internal RAM, very likely yes, at the moment Bluetooth starts.** `nimble_port_init()` fails in `esp_nimble_hci_init()`, which (controller already enabled) can only fail on an internal-RAM allocation. 0.7.3 has 13.6 KB less static internal RAM than 0.7.2 and starts Bluetooth after the UI instead of before it. The heap at that instant was never logged. | B (failure), E (static RAM), S (failure path), **I/U (cause)** |
| Why does the main task panic? | `ESP_ERROR_CHECK(nimble_port_init())` at `main/ble_central.c:598` aborts `app_main` (backtrace decoded with the matching ELF). | B + E |
| Why are diagnostics "not saved (storage)"? | The FAT root directory is **corrupted**: all 512 entries are erased (0xFF), so FatFs can neither find nor create any file although 5 MB are free. Not "storage full". | K + B (free-space figures match exactly) |
| Since when? | Root directory valid on 24 Oct 20:18, gone on 25 Oct 13:52, while the board ran 0.4.0 → 0.5.0 → 0.6.0 and went through **72 crash resets in 114 boots**. Present before 0.7.3. | K |
| Partition-layout error? | No. 0.7.3 table = 0.7.2 table minus 64 KB of the never-used `ota_1` tail → `coredump`; every other offset/size is unchanged; it was found and used by the board. | B, K, E |
| Flash write errors? | None logged by the board; the core dump was erased and written successfully 3× (checksum correct on the next boot). | B |

## 1. Exact firmware on the board

| Item | Value | Level |
|---|---|---|
| App | 0.7.3, compiled "Oct 26 2026 21:40:31", ELF SHA-256 prefix `fa0edc5ac` | B |
| Rebuild | `/home/claude/ws-073` (fix/073 @ 1cf8cf0): ELF `fa0edc5ac7c569e9…`, app bin `181b2e5c751108679a2101bfb1c1942b0302fe537527ceaeba207c5256ea4da5` = the delivered `BC073-app.bin` | E |
| Bootloader | ESP-IDF v5.5.1, compiled 23 Oct 19:27 (never rewritten by any kit) | B |
| Partition table | 0.7.3 table: nvs 0x9000/24K, otadata 0xF000/8K, phy_init 0x11000/4K, ota_0 0x20000/4M, ota_1 0x420000/3.94M, **coredump 0x810000/64K**, storage 0x820000/7.88M | B |
| Chip / flash / PSRAM | ESP32-S3 rev v0.2, 16 MB QIO flash (detected), 2 MB PSRAM (memory test OK) | B |

## 2. Main-task crash (decoded)

Boot log (identical on all three boots):
```
BLE_INIT: BT controller compile version …        <- controller init + enable succeeded (no "controller init/enable failed")
E (1925) BLE_INIT: hci inits failed
E (1927) BLE_INIT: nimble host init failed
ESP_ERROR_CHECK failed: esp_err_t 0xffffffff (ESP_FAIL) … ble_central.c line 598 … nimble_port_init()
abort() was called at PC 0x40384497 on core 0
```
`xtensa-esp32s3-elf-addr2line` on the matching ELF (**E**):
```
0x403844d9 panic_abort            esp_system/panic.c:469
0x403844a1 esp_system_abort       esp_system/port/esp_system_chip.c:87
0x4038e149 abort                  newlib/src/abort.c:38
0x40384497 _esp_error_check_failed esp_system/esp_err.c:49
0x42012ba0 ble_central_start      main/ble_central.c:598
0x4200f8aa app_main               main/main.c:179
0x4212c340 main_task              freertos/app_startup.c:208
```
**What can return "hci inits failed"** (ESP-IDF 5.5.1 source, **S**): `nimble_port_init()` → controller init ✓ → controller
enable ✓ → `esp_nimble_init()` → `esp_nimble_hci_init()` fails when (a) `ble_buf_alloc()` cannot `calloc` the NimBLE msys pools
and HCI transport pools — with `CONFIG_BT_NIMBLE_MEM_ALLOC_MODE_INTERNAL=y` these come **only from internal RAM**
(msys 12×256 + 24×320 B, ACL 24×255 B, events 38×70 B ≈ 20–22 KB incl. headers, the largest single block ≈ 8 KB);
(b) `esp_vhci_host_register_callback()` — fails only if the controller is not enabled (it was); (c) `xSemaphoreCreateBinary()`
— also an allocation. **So by elimination the failure is an internal-RAM allocation failure.** (**I**, not measured)

**0.7.2 → 0.7.3 differences that bear on it**

| Change | Effect | Level |
|---|---|---|
| Static internal DRAM | `idf.py size`: DIRAM remaining 37,901 B (0.7.2) → 23,989 B (0.7.3) = **−13,912 B**; heap region start 0x3FCD23D0 → 0x3FCD59F8 (the board printed `3FCD59F8 len 13D18 (79 KiB)`). Biggest items: `app_diag.c` statics ≈ 9.6 KB (`D` 2800, `buf` 1536, `e` 1344, 2× index 932, report-in 788 …), core-dump stack 1892, ISR stacks +1120. | E |
| sdkconfig | Only: NimBLE host stack 4096→7168, esp_timer stack 3584→4608, ISR stack 1536→2096, core dump to flash on. **BT/NimBLE memory options identical.** | E |
| **Start-up order** | 0.7.2: NVS → storage → display → touch → **`ble_central_start()`** → `app_init()` → `ui_start()`. 0.7.3: NVS → display → storage → diag init (+crash report) → touch → `app_init()` → `ui_start()` → **`ble_central_start()`**. Everything the profile, UI, touch and diagnostics take from internal RAM is now gone before the HCI buffers are requested. | S (git diff) |
| 0.7.2 Bluetooth did start on this board | NVS key `link:idaddr` (written only from the NimBLE host-sync callback) first appears in the backup taken while 0.7.2 was running (26 Oct 20:36). Same chip, same NVS, same BT config → the failure is specific to 0.7.3. | K |
| Internal heap at `app_main` | 111 KB free internal on the first boot, 109 KB after crash boots (all regions incl. the 32 KB DMA reserve). Not logged at the point Bluetooth starts (0.7.3 crashes before its first 60 s health line). | B |

**Status: root cause = internal-RAM exhaustion at Bluetooth start is strongly indicated but UNCONFIRMED** until the board logs
the heap right before `nimble_port_init()` (0.7.4-dev does: "Bluetooth stack starting: internal heap free … largest block …").

**Second defect (B):** the staged-boot logic named the subsystem ("crashed subsystem phone link") but printed `disabled 0x000`
on every boot: in 0.7.3 a subsystem was only disabled in a *staged* boot (after the rider pressed RESTART & DIAGNOSE), and even
a "skipped" phone link still called `ble_central_start()`. Result: 3 identical crashes → RECOVERY.

## 3. Storage — measured on every backup

Tool: `firmware/waveshare/tools/storage_audit.py` (read-only; reconstructs the wear-levelling layer with WL's own rules —
dummy-sector position verified against WL's CRC-protected position records; prints names/sizes/dates only).
Cross-check: the board's own log says `FAT 5096 KB free / 7964 KB`; the reconstruction of the pre-0.7.3 backup gives exactly
5096 / 7964 KB.

| Backup (taken before installing) | App in slot | WL pos / moves | Root directory | FAT clusters EOC | Freed dir-clusters | NVS boots / crashes / safe mode |
|---|---|---|---|---|---|---|
| factory_backup_16MB (23 Oct) | factory | — (storage never formatted; factory table) | — | — | — | — |
| v040 #1 (24 Oct 19:24) | 0.3.0 | 2 / 0 | **valid**: SELFTEST.TXT, RIDES | 715 | 0 | 6 / 0 / 0 |
| v040 #2 (24 Oct 20:18) | 0.4.0 | 2 / 0 | **valid** (selftest = "boot 8") | 715 | 0 | 8 / 0 / 0 |
| v061 (25 Oct 13:52) | 0.6.0 | 45 / 0 | **512/512 entries erased (0xFF)** | 717 | 58 | 122 / 72 / 1 |
| v071 (26 Oct 15:52) | 0.6.1 | 50 | erased | 717 | 58 | 237 / 155 / 5 |
| v072 #1 (26 Oct 20:18) | 0.6.1 | 163 | erased | 717 | 303 | 283 / 185 / 6 |
| v072 #2 (26 Oct 20:36) | 0.7.2 | 163 | erased | 717 | 303 | 292 / 191 / 8 |
| v072 #3 (26 Oct 23:38) | 0.7.2 | 163 | erased | 717 | 303 | 318 / 205 / 10 |
| v073 (27 Oct 12:04) | 0.7.2 | 163 | erased | 717 | 303 | 337 / 217 / 11 |

**Dating:** the root directory was lost between **24 Oct 20:18 and 25 Oct 13:52** (boots 8 → 122, 72 crash resets, firmware
0.4.0 / 0.5.0 / 0.6.0). The orphaned `SELFTEST.TXT` data shows it was still being rewritten at boot 36 ("boot 36" in cluster 2)
and boot 39 ("boot 39" in cluster 4, while cluster 2 was never freed = a rewrite interrupted between the directory update and the
FAT update). (**K**)

**Mechanism — what the code does (S) and what is still open (U):**
* Every boot (0.2.0–0.7.3) rewrote `/data/selftest.txt` in the root directory. With wear levelling + 4 KB sectors, FatFs writes
  a sector as *erase, then program*; a reset, brown-out or deep sleep between the two leaves that sector erased (0xFF). 72 crash
  resets happened in exactly this window. The interrupted rewrite at boot 39 is measured evidence of such an interruption. (S+K)
* WL's dummy-sector relocation itself is power-safe (copy first, then the position record) and WL ignores TRIM — ruled out. (S)
* Installers never write the storage area (only 0xF000, 0x20000, 0x8000). (S)
* **Open (U):** all four root sectors are erased, but only the first ever held entries; the other three held zeros and FatFs
  never rewrites them. No code path that erases exactly these 16 KB was found. A board read cannot date it further.
* After the loss, every file operation in 0.6.x–0.7.2 called `mkdir()` (path helper in `plat_esp.c`): FatFs allocated and wrote
  a directory cluster, failed to register it, and freed it again → 303 freed directory clusters and WL position 45 → 163
  (~1,900 extra sector erases). (K+S)
* `format_if_mount_failed = true` was set: the FAT was **not** reformatted only because it still mounted. Any boot-sector damage
  would have wiped it automatically. (S) — removed in 0.7.4-dev.

**Phantom allocation (K, cause U):** FAT entries for clusters 1280–1992 read 0xFFF (end-of-chain) from the very first backup
after formatting: the FAT sector is 0xFF from byte 1920 on, in both FAT copies. FatFs `f_mkfs` writes the whole FAT as zeros, so
this was written later. These 713 clusters (2.85 MB) are counted as used: the real usable free space is 5096 KB, the FAT holds
only ~8 KB of real data.

**What is in the FAT now (K, pre-0.7.3 backup; nothing reachable through the directory):**

| Data | Size | Note |
|---|---|---|
| RIDES/ directory (cluster 3, orphaned) | 4 KB | contains ACTIVE.JNL |
| RIDES/ACTIVE.JNL (cluster 5) | 59 B | a ride journal header + ≤1 line; NVS `next_ride_id` = 2 → one ride was ever started |
| old SELFTEST.TXT contents (clusters 2, 4) | 8 B each | boot counters only |
| rides/history.txt, rides/r*.txt, diag/* | **never created** | no saved ride and no diagnostic report exists on the board |
| freed directory clusters | 303 × 4 KB | residue, free in the FAT |

## 4. Measurements table (deliverable 1)

| Item | Measured | Level |
|---|---|---|
| Flash size detected | 16 MB (bootloader + `selftest flash PASS 16 MB`) | B |
| Partition table | §1; 0.7.4-dev table byte-identical to 0.7.3 (`cmp`) | B, E |
| App size vs partition | 0.7.2 1,787,840 B; 0.7.3 1,830,352 B (43.6 % of 4 MB `ota_0`); 0.7.4-dev 1,838,656 B; `ota_1` empty in every backup | E, K |
| App content (flash) | own fonts 105 KB, layout thumbnails 90 KB, other const data 78 KB (DROM) | E |
| NVS | 6 pages × 4 KB: 4 full, 1 active (4 empty entries), 1 empty (GC reserve); 23 written / 115 erased (reclaimable) / 142 empty entries; integrity OK. Data: PHY calibration 1904 B, rider profile string 706 B, link identity 6 B, local IRK 23 B, counters. **Not full.** No phone bond (only `local_irk_1`) in the pre-0.7.3 backup. | K (+B: `nvs PASS boot #339`) |
| Filesystem size / free | 7964 KB total, 5096 KB reported free (2852 KB phantom-allocated, §3) | B, K |
| Root directory | 512 entries, 512 erased, 0 usable → `Directory corrupted` | K |
| Core-dump partition | present (0x810000, 64 KB); holds the 0.7.3 crash: 14,276 B, checksum correct; content beyond the summary only after a board read | B |
| Diagnostic storage capacity (design) | event ring `diag/events.bin` 1024 × 32 B = 32 KB; ≤ 12 reports × ≤ 8 KB; index ~1 KB; RTC log ring 2 KB (RAM); core copies `diag/core-<id>.elf` ~14 KB each — **unbounded in 0.7.3** (never deleted with their report; fixed in 0.7.4-dev) | S |
| Stored reports / temp files / incomplete transfers | none on the FAT (directory unusable since 25 Oct); `*.tmp` none; the 59-B ride journal is the only incomplete item | K |
| Flash write errors | none logged; core dump erase/write OK ×3 | B |
| Mount / init errors | mount OK; probe write+read-back of `/data/selftest.txt` FAILED every boot (cannot create in root) | B |
| Memory allocation failures | Bluetooth HCI init (internal RAM) — §2 | B + S |
| Heap | internal free at app_main 111 KB (first boot), 109 KB (crash boots); PSRAM 2048 KB; static DIRAM remaining 23,989 B (0.7.3) vs 37,901 B (0.7.2) vs **32,749 B (0.7.4-dev)** | B, E |
| Stacks | main 8192, LVGL 12288, NimBLE host 7168, esp_timer 4608, ble_mgr 3072, ISR 2096, core-dump 1792 (dump used 1248, 640 left — B); runtime high-water marks of 0.7.3 never logged (crash before the 60 s health line) | E, B |

**Classification:** flash exhaustion — **no** (B,K). RAM exhaustion — **internal RAM at BT start, strongly indicated (I/U)**.
Partition-layout error — **no** (B,K,E). Corruption — **yes, FAT root directory, since 25 Oct (K)**. Write failure — the
symptom (every create fails) is a *consequence* of the corruption, not a flash write error (B,K).

## 5. Data classification (deliverable 2) — nothing deleted

| Data | Where | Size (measured where possible) | Class |
|---|---|---|---|
| Rider profile (FTP, zones, display, sleep, wheel) | NVS `bc:profile` | 706 B | **Essential on device** (offline rides); master copy → phone |
| Sensor pairings (meter / HR / CSC address, type) | inside the profile | (in 706 B) | **Essential on device** |
| Phone bonds + link identity | NVS `nimble_bond`, `link` | 23 B + 7 B now | **Essential on device** |
| PHY RF calibration, Wi-Fi mode | NVS `phy`, `nvs.net80211` | 1.9 KB | **Essential** (system) |
| Boot / crash counters, disabled-subsystem mask | NVS `diag`, `boot` | < 50 B | **Essential** (small) |
| Interrupted-ride journal `rides/active.jnl` | FAT | 59 B now; ~7 B/s while riding | **Needed temporarily while offline** → never deleted unsynced |
| Per-second ride files `rides/r####.txt` | FAT | none exist | **Needed temporarily while offline** → **safe to remove after verified sync** |
| Ride history `rides/history.txt` | FAT | none exists | **Better stored on the phone** (keep last N summaries for the board's Results screen) |
| Crash core dump | `coredump` partition | 14,276 B | **Essential until transferred** (critical evidence) |
| Diagnostic reports `diag/r*.txt` + index | FAT | none exist; ≤ 12 × 8 KB | **Temporary** → **safe to remove after ACK** (already implemented) |
| Raw core copies `diag/core-*.elf` | FAT | none exist; ~14 KB each | **Temporary** → remove with their report (0.7.4-dev) |
| Event ring `diag/events.bin` | FAT | 32 KB fixed | **Essential, minimal** (rolling, bounded) |
| `diag/report.txt` (Device Health export copy) | FAT | ≤ 3.4 KB | **Potentially unnecessary** (duplicate of the serial export + report) |
| `selftest.txt` / `diag/probe.txt` | FAT | 8 B | **Potentially unnecessary** (boot probe only) |
| Demo-ride history | FAT | none | **Potentially unnecessary** |
| Coaching workouts / plans | none stored (built-in coach code) | 0 | → phone-authoritative (BLE_CONTRACT) |
| Fonts, layout thumbnails | app image (flash) | 105 KB + 90 KB | **Essential** (UI); not part of the storage problem |
| `ota_1` slot | flash | 3.94 MB, empty | keep (future OTA / rollback) |

## 6. Why diagnostic storage failed (deliverable 2 of the brief)

1. The FAT root directory has been unusable since 25 Oct (all entries erased) → no file can be created or found. (K)
2. 0.7.3's boot probe therefore failed → `storage_ok = false` → every report stayed in RAM → recovery screen
   "Logs NOT saved (storage)"; the Diagnostics menu would have said "Not saved: storage full" for any failure. (B+S)
3. The crash evidence itself is safe: the core dump is in its own partition (not the FAT) and stays there — 0.7.3 only erases it
   after a stored report (which never happened). 0.7.4-dev additionally refuses to erase it unless the copy succeeded. (B+S)

## 7. Safe repair proposal (needs owner approval; nothing done)

1. `READ-BOARD-STATE.bat` → full backup + separate reads of nvs / otadata / coredump, verified identical (read-only).
2. Offline on the PC (here): rebuild a FAT image from that backup with every recoverable item copied out first (ACTIVE.JNL,
   RIDES/, the core dump as a file), the phantom allocation cleared, NVS untouched; verify it by re-reading it with
   `storage_audit.py` before anything is written.
3. With explicit owner approval only: write **only** the `storage` region (0x820000–0xFFFFFF) and read it back; rollback = write
   the same region from the step-1 backup (`RESTORE-CHOSEN-BACKUP` already restores whole backups). Settings, pairings, ride
   id counter (NVS), app and partition table are not written. No partition-table change is needed.

The firmware never formats, repairs or writes a damaged FAT on its own (0.7.4-dev).

---

## 8. Round 2 (owner requirements 12:27) — additional measurements and changes

### 8.1 Bluetooth start-up failure: what is measured now, and what is still inferred
Firmware 0.7.4-rc1 no longer calls `nimble_port_init()`; it runs the identical ESP-IDF 5.5.1 sequence for the ESP32-S3
(HCI log off) in `ble_central_stack_init()` — `esp_bt_controller_init` → `esp_bt_controller_enable(BLE)` → `esp_nimble_init()`
(HCI transport buffers + host), same clean-up on failure — and records **after every step**: the return code, free and
largest-block heap for INTERNAL|8BIT and for DMA, and (via `heap_caps_register_failed_alloc_callback`) the **size and caps of
the first allocation that failed** during the start. The record is kept in NVS (`bootrec`, §8.3), printed at the next boot
(`BOOTREC previous[-n] … BT: HCI init failed [0 rc 0 int F/L dma F/L] [1 …] [3 rc -1 …] failed alloc N B caps 0x…`) and shown
in Device Health ("Boot records").

| Item | Value | Level |
|---|---|---|
| Steps that succeeded on the board under 0.7.3 | controller init, controller enable (no "controller init/enable failed" line) | B |
| Step that failed | `esp_nimble_init` → `esp_nimble_hci_init` ("hci inits failed") | B |
| What can fail inside it | `ble_buf_alloc()` (msys + HCI pools, `bt_osi_mem_calloc` = INTERNAL\|8BIT with `CONFIG_BT_NIMBLE_MEM_ALLOC_MODE_INTERNAL`), the VHCI callback registration (only if the controller is not enabled — it was), `xSemaphoreCreateBinary` | S |
| Sizes requested by `ble_buf_alloc` with this sdkconfig | msys-1 12 × (256+24) = 3,360 B; **msys-2 24 × (320+24) = 8,256 B (largest)**; ACL 24 × 284 = 6,816 B; events 30 × 72 = 2,160 B + 8 × 72 = 576 B; command ≈ 264 B → **≈ 21.4 KB internal, largest single block ≈ 8.3 KB** | S + I (struct sizes of a 32-bit target) |
| Internal heap free at that moment on 0.7.3 | **not measured** (0.7.3 printed only 111 KB at app_main entry) | — |
| Controller's own internal allocations (closed `libbtdm_app`) | not measurable on the host; the per-step snapshots on the board will give them | — |
| Host-side reproduction | static budget yes (`esp_idf_size` per build: 0.7.2 37,901 B, 0.7.3 23,989 B, 0.7.4-rc1 **34,645 B** free DIRAM); the dynamic pre-Bluetooth allocations no — QEMU cannot run this board's PSRAM (CRASH_0.7.2.md §6) | E |
| Conclusion | internal-RAM shortage at Bluetooth start: **strongly inferred, not confirmed**. The first 0.7.4-rc1 boot record turns it into a measurement (or rules it out: then the failing step / rc says what else it is). | I |

### 8.2 Requirement 1: no endless loop
* A Bluetooth start that FAILS never aborts (0.7.4-dev); a start that CRASHES twice in a row while starting is disabled by the
  boot plan; **new in rc1:** two boots in a row whose Bluetooth start failed without crashing (boot records) also disable it
  (`bc_boot_disable` + NVS) until RETRY — the board then runs stably without Bluetooth. Simulated: 12 consecutive failing
  starts → 0 crashes, 0 RECOVERY, disabled from start 3 (test/sim section 25).

### 8.3 Requirement 4: crash evidence without the file system
| Evidence | Where | Survives | Written |
|---|---|---|---|
| Core dump (ELF + CRC) | `coredump` partition (0x810000, 64 KB) | reset + power loss | by ESP-IDF's core-dump code at the panic (raw flash, no FS) |
| Boot records ring, 4 × 140 B (+CRC) | NVS namespace `bootrec`, one 576-B blob | reset + power loss | app_main only: after the boot plan, after the Bluetooth stage, at RUNNING and at STABLE — never in a panic handler |
| Last ~2 KB of log lines | RTC no-init RAM | reset (not power loss) | log hook, task context |
| Boot / crash counters, disabled-subsystem mask | NVS `diag`, `boot` | reset + power loss | app_main |
No partition-table change. The FAT is used only for the larger, optional items (reports, event ring).

### 8.4 Requirement 3: filesystem — mismatch vs migration vs corruption
| Check | Result | Level |
|---|---|---|
| `storage` offset/size in the pre-0.7.3 table | 0x820000 / 0x7E0000 in every backup since 24 Oct | K |
| `storage` in the 0.7.3 table | 0x820000 / 0x7E0000 (board boot log); the 0.7.3 change only moved the end of `ota_1` (now 0x420000–0x80FFFF) and added `coredump` 0x810000–0x81FFFF | B, E |
| WL configuration / state sectors (end of storage) | valid CRC and identical geometry in every backup | K |
| Regions written by the installers (from their own esptool logs) | 0.1.x: 0x0–0x199FFF; 0.2.1/0.3.0/0.4.0: 0x0–0x5FFF, 0x8000, 0xF000–0x10FFF, 0x20000–≤0x1BFFFF; 0.7.2: 0xF000, 0x20000–0x1D4FFF; 0.7.3: 0x8000, 0xF000, 0x20000–0x1DEFFF. **Nothing at or above 0x820000.** (0.5.0/0.6.x/0.7.1 logs were not on the PC; their scripts write only 0xF000 + 0x20000) | K + S |
| Firmware raw flash writers | only the core dump (0x810000–0x81FFFF, from 0.7.3 on) | S + B ("Erase flash 16384 bytes @ 0x810000") |
| Timing | root directory lost between 24 Oct 20:18 and 25 Oct 13:52 — two days before the 0.7.3 table change | K |
| Verdict | **not** a partition mismatch, **not** a failed migration; **file-system corruption** that happened under 0.4.0–0.6.0 during a period of 72 crash resets; exact erase mechanism still open | K + I |
Every backup is preserved untouched (read-only copies were analysed); no erase or reformat was done or is automated.
Real-image tests: `test/host/test_storage_fixture.c` uses the actual filesystem heads of the 24 Oct and 27 Oct backups
(boot sector, both FATs, root directory; no file contents) — classified OK and "Directory corrupted", free space 5096 KB = the
board's own log.
