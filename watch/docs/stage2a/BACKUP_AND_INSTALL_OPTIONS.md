# Cyclift Watch — Stage 2a backup result and installation options (9 Nov 2026)

Status: backup **verified**; build configuration corrected on `watch/v3-poc`; nothing installed. Firmware flashing, partition-table
changes on the watch, bootloader changes and restores are **not approved**. No unique hardware identifiers appear in this file.

## 1. The watch (read-only identification)
ESP32-PICO-V3-02 rev v3.1, 8 MB flash (ID 0x20/0x4017), embedded PSRAM, 40 MHz crystal. Secure boot off, flash encryption off,
no keys burned, UART download mode enabled (eFuses read only; nothing written).

## 2. Full 8 MB backup
| Check | Result |
|---|---|
| Device command | `esptool read_flash 0x0 0x800000` at 921 600 baud, run twice (107 s, 103 s), both return code 0 |
| Sizes | 8 388 608 B and 8 388 608 B |
| Byte-for-byte comparison | identical |
| SHA-256 (both) | `77ad7105c68fb7de04e5717fca4e90b08bd9c32adeb5c098e3e00446d3767693` |
| Location | owner's PC only, `%LOCALAPPDATA%\Cyclift_Private\watch_backup_20261109\` (not synced, not in Git, not uploaded) |

Offline structural check of the backup (run on the owner's PC; only summaries left the PC):
| Region | Range | Finding |
|---|---|---|
| ROM-reserved gap | 0x0000–0x0FFF | erased (normal) |
| Bootloader | 0x1000, 17 088 B (to 0x52C0) | valid image, 3 segments, checksum OK, appended SHA-256 OK; header DIO / 4 MB / 40 MHz |
| Partition table | 0x8000 | 4 entries, MD5 OK, identical to the earlier inspection read |
| NVS | 0x9000–0xDFFF | 1 active page, 4 empty (contents deliberately not printed; may hold Wi-Fi/Bluetooth data) |
| OTA data | 0xE000 / 0xF000 | sector 0 seq 1 (CRC OK), sector 1 seq 0 (CRC OK) → app0 selected |
| Factory app (app0) | 0x10000–0x20FFFF | valid image, 1 194 096 B, 7 segments, checksum + SHA-256 OK; image SHA-256 `6bfae0e5237308b128503fa0fb6a09c0e522a12debaf5dd7d8d4803235420f13` (Arduino-ESP32, ESP-IDF v4.4.1, built 20 Apr 2022) |
| spiffs | 0x210000–0x3FFFFF | 99.9 % erased (almost empty file system) |
| Upper flash | 0x400000–0x7FFFFF | 100 % erased (never used) |

Recovery requirements: T-U2T (CH9102) on COM4, esptool 4.8.1, the backup file, and a working USB connection. Because secure boot,
flash encryption and download-mode disabling are all off, the chip's ROM loader (which cannot be overwritten) can always accept a
restore, even if the bootloader area were damaged. Limitations: the restore itself has **not** been tested (needs separate approval);
the backup contains private settings, so it must never be shared; eFuses are not part of flash and need no backup (none will be changed).

## 3. Build configuration corrections (development branch only; not installed)
`watch/firmware/platformio.ini`, both the existing app (`twatch2021`, incl. diag) and the v3 proof of concept (`v3poc`):
* `board_upload.flash_size = 8MB` — esp32dev defaulted to 4 MB, so the bootloader header would have said 4 MB while the partition
  table runs to 8 MB; the bootloader would refuse partitions above 0x400000 and the watch would not boot.
* `board_build.flash_mode = dio`, `board_build.f_flash = 40000000L` — the factory-proven setting (was QIO 80 MHz, untested on this unit).
* `board_upload.maximum_size = 3145728` — the size check now uses the real 3 MB app slot (was the 1.25 MB esp32dev default).
* New offline check `tools/v3/check_image_header.py` (with self-test) runs in CI on every built image: bootloader and app headers must
  say DIO / 40 MHz / 8 MB, images must be valid, the partition table must be valid, inside 8 MB, non-overlapping, and the app must fit.

## 4. Option analysis: keep the factory firmware and use the empty upper 4 MB
### How the ESP32 chooses what to run
1. The ROM loader (inside the chip) loads the second-stage bootloader from 0x1000.
2. The bootloader reads the partition table at 0x8000, then the two OTA-data sectors (0xE000, 0xF000).
3. It takes the valid OTA entry with the highest sequence number *s* and boots app slot `(s − 1) mod (number of OTA app slots)`.
4. It verifies that image (checksum, SHA-256); if it is invalid it tries the other app slots.

Today: one OTA slot, highest seq = 1 → app0 (factory). Simply putting an image in empty flash does nothing: it only runs if the
partition table lists it **and** OTA data points to it.

### What would have to change on the watch (sector by sector)
| Area | Change | Why |
|---|---|---|
| Bootloader 0x1000 (and sector 0x5000, which holds its SHA-256) | factory bootloader re-written with flash-size field 4 MB → 8 MB (esptool updates the hash) | the factory bootloader limits flash access to the size in its header; with 4 MB it should refuse a slot at 0x400000 (to be confirmed on the watch; assume it blocks) |
| Partition table 0x8000 | new table: factory `nvs` relabelled `nvs_fac` (same place, untouched), `otadata`, `app0`, `spiffs` unchanged; add `app1` (ota_1) 0x400000 3 MB, new `nvs` 0x700000 24 KB, `littlefs` 0x706000 to 0x800000 | makes the new slot visible; gives Cyclift its own settings area so the factory settings are never written to (Bluetooth bonding storage always uses the label `nvs`) |
| OTA data sector 1 (0xF000) | seq 0 → seq 2 | (2 − 1) mod 2 = 1 → app1. Sector 0 (seq 1) stays as it is |
| 0x400000–~0x4F0000 and 0x700000–0x7FFFFF | Cyclift firmware and its data | previously erased; nothing original lost |
Untouched: 0x0–0xFFF, NVS 0x9000–0xDFFF, OTA sector 0, factory app 0x10000–0x20FFFF, spiffs 0x210000–0x3FFFFF.

### Does the factory bootloader support it?
* Same partition-table offset (0x8000), standard OTA logic, two OTA slots and app slots anywhere 64 KB-aligned: yes (ESP-IDF v4.4.1).
* Above 4 MB: only after its header says 8 MB (row 1). Must be confirmed on the watch.
* Our app: **correction (9 Nov, later the same day)** — the validated build actually uses espressif32 8.0.0 = Arduino-ESP32 3.3.12
  (ESP-IDF 5.5 family), not 2.0.x as first stated. Compatibility of an ESP-IDF 5.5 app with the factory ESP-IDF 4.4.1 bootloader is
  therefore tested explicitly in the emulator (PRE_INSTALL_VERIFICATION.md). Versions are now pinned.

### Could it stop the factory firmware from booting?
| Failure | Effect | Recovery |
|---|---|---|
| Power/USB lost while the bootloader sector is written | nothing boots | ROM loader still works → re-write the original sector(s) from the backup |
| Partition table wrong | bootloader stops | re-write 0x8000 from the backup |
| app1 invalid or crashes at start | bootloader falls back to app0 (factory) — it runs, but with the new table it sees the empty Cyclift `nvs`, i.e. default settings; its real settings stay untouched in `nvs_fac` | restore 0x8000 and 0xF000 from the backup |
| Factory app runs with an 8 MB bootloader header | expected fine (it only uses the first 4 MB); to be confirmed | — |
None of these is permanent: eFuses are untouched and download mode stays enabled.

### Compared with a conventional full replacement
| | Preserve factory (upper 4 MB) | Full replacement + restore from backup |
|---|---|---|
| Original sectors changed | bootloader (≈2 sectors), partition table, 1 OTA sector | bootloader, partition table, OTA data, factory app, half of spiffs |
| Factory app still on the watch | yes | no |
| Factory settings (NVS) | untouched | left in place but shared with Cyclift |
| Return to factory | re-write ~4 small sectors (seconds) | re-write the whole 8 MB backup (~2–3 min) |
| Install method | custom esptool commands (offsets, crafted OTA data) | standard PlatformIO upload |
| Unknowns to confirm | factory bootloader with 8 MB header; factory app with the new table | none beyond normal first boot |
| Cyclift app slots | one (3 MB); OTA updates of Cyclift itself would need a later layout change | two 3 MB slots (OTA-ready) |

### Proposed rollback / recovery procedure (not approved; for review)
1. Before any change: re-hash the backup (must equal `77ad7105…3767693`), cut the original small pieces from it offline
   (0x1000–0x7FFF, 0x8000–0x8FFF, 0xE000–0xFFFF) and hash each piece.
2. Optional read-only rehearsal: `esptool verify_flash` of the backup against the watch (compares, writes nothing).
3. Quick rollback (factory-preserving option): write those three pieces back, `verify_flash` them, then read back 0x0–0x3FFFFF and
   check it equals the backup's first 4 MB byte-for-byte.
4. Full recovery (either option): `write_flash 0x0` the whole backup (never `erase_flash`), then read all 8 MB back and require the
   SHA-256 to equal `77ad7105…3767693` — a bit-identical original watch.
5. If the watch shows nothing: the ROM loader still answers on COM4 (automatic reset worked; Boot-button entry is the fallback).

Recommendation: the factory-preserving option is technically feasible and has the smaller "blast radius", provided two things are
confirmed in the first approved hardware session (bootloader with 8 MB header; factory app with the new table). The full replacement
is simpler and standard; both are fully recoverable from the verified backup. Owner decision required.
