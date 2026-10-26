# Partition table change in 0.7.3 — safety proof

0.7.3 stores ESP-IDF core dumps in flash so a crash leaves evidence that survives the reset. That needs a `coredump` partition.
The space is taken from the **second app slot (`ota_1`), which has never been used**. Nothing that holds data moves.

| Name | Type / subtype | 0.7.2 offset + size | 0.7.3 offset + size | Change |
|---|---|---|---|---|
| nvs | data / nvs | 0x9000 + 0x6000 | 0x9000 + 0x6000 | none (settings, profile, Wi-Fi networks, phone bonds) |
| otadata | data / ota | 0xF000 + 0x2000 | 0xF000 + 0x2000 | none |
| phy_init | data / phy | 0x11000 + 0x1000 | 0x11000 + 0x1000 | none |
| ota_0 | app / ota_0 | 0x20000 + 0x400000 | 0x20000 + 0x400000 | none (the running firmware) |
| ota_1 | app / ota_1 | 0x420000 + 0x400000 | 0x420000 + **0x3F0000** | 64 KB shorter, same start |
| **coredump** | data / coredump | — | **0x810000 + 0x10000** | new, inside the old ota_1 range |
| storage | data / fat | 0x820000 + 0x7E0000 | 0x820000 + 0x7E0000 | none (rides, history, journal, diagnostics) |

Binary tables: 0.7.2 `pc-kit/fw-v0.7.2/BC072-partitions.bin` SHA-256 `812e16cc…`, 0.7.3 `pc-kit/fw-v0.7.3/BC073-partitions.bin`
SHA-256 `f08892b0…` (both carry a valid MD5 row; checked by the test).

## What was proven, and how

Automated: `test/host/test_partitions.c` (`make` in `test/host`, 63 checks, 0 failed). It parses both **binary** tables (and
verifies their MD5 rows with its own RFC 1321 implementation), the CSV, every OTA-selector image and every app image in the kit:

1. **No data region moves.** nvs, otadata, phy_init, ota_0 and storage have identical type, subtype, offset and size in both
   tables. The CSV and the 0.7.3 binary agree entry by entry.
2. **`coredump` takes space only from the old `ota_1`.** ota_1 keeps its start (0x420000); the new partition (0x810000–
   0x81FFFF) lies entirely inside the old ota_1 range (0x420000–0x81FFFF). All entries are 4 KB aligned, apps 64 KB aligned, no
   overlaps, all inside 16 MB.
3. **ota_1 has never been used.** Every installer in the kit (0.4.0 … 0.7.2, and 0.7.3) writes an **erased** OTA selector
   (`BC0xx-otadata.bin`, 8 KB of 0xFF — verified for all 7 images), and with an erased selector the bootloader starts `ota_0`
   ("No factory image, trying OTA 0", seen in the QEMU boot of 0.7.2). No firmware calls the OTA update API
   (`esp_ota_begin` is not used anywhere in `main/`). So nothing in ota_1 is ever executed and nothing reads 0x810000–0x81FFFF.
4. **Every app fits either slot**: largest app in the kit = 0.7.3, 1 828 720 bytes = **44 %** of the shorter 0x3F0000 slot.
5. **Old firmware with the new table runs unchanged.** 0.4.0–0.7.2 look up `nvs` (by type), `storage` (by label), `otadata`
   (by type) and run from `ota_0`: all identical. They were built with core dumps off and never reference a `coredump` partition;
   an extra partition is invisible to them. Therefore **rolling back by writing only an old app (ROLLBACK-TO-v071 / -v050) stays
   valid** with the 0.7.3 table on the board.
6. **New firmware with the old table** (only if someone writes the 0.7.3 app without the table): ESP-IDF logs "No core dump
   partition found" and simply has nowhere to write a dump; `plat_crash_info()` returns "no dump". Everything else works (the RTC
   log tail and the event log still record crashes).
7. **Restoring a full backup restores the old table**: the `backup-*.bin` files are complete 16 MB images starting at 0x0, so
   writing one back (RESTORE-CHOSEN-BACKUP) rewrites 0x8000 with the table that was on the board when the backup was taken —
   together with that time's settings and rides.

## What the installer does (INSTALL-v0.7.3.ps1)

* Reads the **full 16 MB backup first** and verifies it: size, a known firmware at 0x20000 (0.4.0 … 0.7.2, or 0.7.3 when
  re-installing) with a matching checksum, and **a known partition table at 0x8000** (the 0.7.x table `812e16cc…` or the 0.7.3
  table). Anything else stops the installer before anything is written.
* Shows one line: *"The partition table changes: 64 KB of the unused second app slot become a crash-record area; settings,
  pairings, rides and the running slot do not move."* and asks for YES.
* Writes the app (0x20000), the OTA selector (0xF000) and — only if the board still has the old table — the partition table
  (0x8000), in one esptool call that verifies every region. The bootloader is never written.
* If the write were interrupted while the table is being written, the board would not boot until the installer (or any
  restore) is run again; the ROM download mode that esptool uses is in mask ROM and cannot be damaged, so this is always
  recoverable from the PC.
