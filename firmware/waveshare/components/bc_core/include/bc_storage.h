/*
 * bc_core — STORAGE HEALTH (firmware 0.7.4). Pure C, host-tested (test/host/test_bc_storage.c).
 *
 * Replaces the single "storage OK / FAIL" bit of 0.7.3 (recovery screen "Logs NOT saved (storage)", Diagnostics toast
 * "Not saved: storage full") with the ACTUAL failure category, decided from measured facts:
 *   - is there a 'storage' partition, did it mount (no automatic format any more: format_if_mount_failed = false);
 *   - free / total bytes reported by FatFs;
 *   - a read-only scan of the FAT12/16 root directory (read through the wear-levelling layer, never written);
 *   - the result of the boot-time probe write + read-back of /data/selftest.txt.
 * Measured on the owner's board (27 Oct 2026, docs/FW_STORAGE_MEMORY_REPORT.md): mounted, 5096 KB free of 7964 KB, root
 * directory 512 of 512 entries erased (0xFF) -> creating any file fails although the flash is not full. That case is
 * BC_STOR_DIR_CORRUPTED, not "storage full".
 * Nothing here writes, formats or repairs anything; a repair is a separate, owner-approved procedure.
 */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    BC_STOR_OK = 0,
    BC_STOR_FULL = 1,              /* no free cluster, or the root directory is full of valid entries */
    BC_STOR_FS_UNAVAILABLE = 2,    /* no 'storage' partition, or it does not mount (it is NOT formatted automatically) */
    BC_STOR_DIR_CORRUPTED = 3,     /* mounted with free space, but the root directory has no usable entry (erased/garbage) */
    BC_STOR_WRITE_FAILED = 4,      /* mounted, space and directory look fine, the probe write or its read-back failed */
    BC_STOR_DIAG_UNAVAILABLE = 5,  /* the filesystem works but the diagnostic store could not be used (index/ring/memory) */
    BC_STOR_DIAG_FULL = 6,         /* every report slot holds an UNSENT report; unsent reports are never deleted to make room */
    BC_STOR_NOT_CHECKED = 7        /* not measured yet (early boot) */
} bc_stor_state_t;

/** Short text for the 240x240 round screen (<= 24 characters), e.g. "Directory corrupted". */
const char *bc_stor_name(bc_stor_state_t s);
/** Stable machine code for reports and the BLE storage status (BLE_CONTRACT.md), e.g. "dir_corrupted". */
const char *bc_stor_code(bc_stor_state_t s);

/* crash-dump partition ('coredump', ESP-IDF ELF + CRC32) */
typedef enum { BC_CRASHPART_MISSING = 0, BC_CRASHPART_EMPTY = 1, BC_CRASHPART_DUMP = 2, BC_CRASHPART_BAD = 3 } bc_crashpart_t;
const char *bc_crashpart_name(bc_crashpart_t c);   /* "Crash partition missing", "Crash partition empty", ... */

/** Root directory of a FAT12/16 volume, entry by entry (32 bytes each). */
typedef struct {
    uint16_t entries;        /* entries scanned */
    uint16_t used;           /* valid 8.3 entries (files, directories, volume label) */
    uint16_t lfn;            /* long-file-name entries */
    uint16_t free_slots;     /* first byte 0x00 (never used) or 0xE5 (deleted): what FatFs needs to create a file */
    uint16_t erased;         /* all 32 bytes 0xFF (erased flash) */
    uint16_t garbage;        /* anything else (not a valid entry) */
} bc_fat_root_t;

/** Parse a FAT boot sector: byte offset and length of the FAT12/16 root directory inside the volume.
 *  false for FAT32 (root is a cluster chain), an invalid BPB, or n < 512. */
bool bc_fat_root_location(const uint8_t *boot, size_t n, uint32_t *root_off, uint32_t *root_len, uint32_t *sector_size);
void bc_fat_root_scan(const uint8_t *root, size_t len, bc_fat_root_t *out);

typedef struct {
    bool partition_found;    /* a data/fat partition labelled 'storage' exists */
    bool mounted;            /* esp_vfs_fat_spiflash_mount_rw_wl == ESP_OK */
    int mount_err;           /* esp_err_t of the mount (0 when mounted) */
    uint64_t total_bytes, free_bytes;   /* esp_vfs_fat_info (0/0 if unknown) */
    uint32_t cluster_bytes;  /* allocation unit (0 if unknown) */
    bool root_scanned;       /* the root directory could be read (raw, read-only) */
    bc_fat_root_t root;
    bool probe_attempted, probe_ok;     /* boot probe: write + read back /data/selftest.txt */
    int probe_errno;         /* errno of the failed fopen/fwrite (0 if none) */
} bc_stor_facts_t;

/** Decide the category from the facts (pure; the same input always gives the same answer). */
bc_stor_state_t bc_stor_classify(const bc_stor_facts_t *f);
/** One line for the serial log / Device Health / reports, e.g.
 *  "Directory corrupted: mounted, 5096/7964 KB free, root dir: used 0, lfn 0, free 0, erased 512, garbage 0,
 *  probe write failed (errno 13)". */
size_t bc_stor_describe(const bc_stor_facts_t *f, bc_stor_state_t s, char *out, size_t cap);

#ifdef __cplusplus
}
#endif
