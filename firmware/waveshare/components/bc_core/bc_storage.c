/* bc_core — PORTABLE CORE. See bc_storage.h. */
#include "bc_storage.h"
#include <stdio.h>
#include <string.h>

const char *bc_stor_name(bc_stor_state_t s)
{
    switch (s) {
    case BC_STOR_OK: return "Storage OK";
    case BC_STOR_FULL: return "Storage full";
    case BC_STOR_FS_UNAVAILABLE: return "Filesystem unavailable";
    case BC_STOR_DIR_CORRUPTED: return "Directory corrupted";
    case BC_STOR_WRITE_FAILED: return "Write failed";
    case BC_STOR_DIAG_UNAVAILABLE: return "Diagnostics unavailable";
    case BC_STOR_DIAG_FULL: return "Reports full (unsent)";
    case BC_STOR_NOT_CHECKED: default: return "Storage not checked";
    }
}

const char *bc_stor_code(bc_stor_state_t s)
{
    switch (s) {
    case BC_STOR_OK: return "ok";
    case BC_STOR_FULL: return "full";
    case BC_STOR_FS_UNAVAILABLE: return "fs_unavailable";
    case BC_STOR_DIR_CORRUPTED: return "dir_corrupted";
    case BC_STOR_WRITE_FAILED: return "write_failed";
    case BC_STOR_DIAG_UNAVAILABLE: return "diag_unavailable";
    case BC_STOR_DIAG_FULL: return "diag_full";
    case BC_STOR_NOT_CHECKED: default: return "not_checked";
    }
}

const char *bc_crashpart_name(bc_crashpart_t c)
{
    switch (c) {
    case BC_CRASHPART_EMPTY: return "Crash partition empty";
    case BC_CRASHPART_DUMP: return "Crash dump stored";
    case BC_CRASHPART_BAD: return "Crash dump unreadable";
    case BC_CRASHPART_MISSING: default: return "Crash partition missing";
    }
}

static uint16_t le16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }

bool bc_fat_root_location(const uint8_t *b, size_t n, uint32_t *root_off, uint32_t *root_len, uint32_t *sector_size)
{
    if (!b || n < 512) return false;
    if (b[510] != 0x55 || b[511] != 0xAA) return false;
    uint16_t bps = le16(b + 11), rsv = le16(b + 14), rootent = le16(b + 17), fatsz = le16(b + 22);
    uint8_t spc = b[13], nfat = b[16];
    if (bps != 512 && bps != 1024 && bps != 2048 && bps != 4096) return false;
    if (spc == 0 || (spc & (spc - 1)) != 0 || rsv == 0 || nfat == 0 || nfat > 2) return false;
    if (rootent == 0 || fatsz == 0) return false;                     /* FAT32 (root is a cluster chain) or not FAT */
    uint32_t off = ((uint32_t)rsv + (uint32_t)nfat * fatsz) * bps;
    uint32_t len = (uint32_t)rootent * 32u;
    len = (len + bps - 1) / bps * bps;
    if (root_off) *root_off = off;
    if (root_len) *root_len = len;
    if (sector_size) *sector_size = bps;
    return true;
}

static bool name_char_ok(uint8_t c)
{
    if (c < 0x20) return false;
    return strchr("\"*+,./:;<=>?[\\]|", c) == NULL;
}

void bc_fat_root_scan(const uint8_t *root, size_t len, bc_fat_root_t *o)
{
    memset(o, 0, sizeof *o);
    if (!root) return;
    for (size_t i = 0; i + 32 <= len; i += 32) {
        const uint8_t *e = root + i;
        o->entries++;
        if (e[0] == 0x00 || e[0] == 0xE5) { o->free_slots++; continue; }
        bool all_ff = true;
        for (int k = 0; k < 32; k++) if (e[k] != 0xFF) { all_ff = false; break; }
        if (all_ff) { o->erased++; continue; }
        uint8_t attr = e[11];
        if (attr == 0x0F) {                                         /* long-file-name part: order 1..20, cluster field 0 */
            uint8_t ord = e[0] & 0x3F;
            if (ord >= 1 && ord <= 20 && e[12] == 0 && e[26] == 0 && e[27] == 0) o->lfn++; else o->garbage++;
            continue;
        }
        bool ok = (attr & 0xC0) == 0;
        if (e[0] == 0x20) ok = false;                               /* a name never starts with a space */
        for (int k = 0; k < 11 && ok; k++) {
            uint8_t c = e[k];
            if (k == 0 && c == 0x05) continue;                      /* 0xE5 stored as 0x05 */
            if (c == '.' && (k == 0 || k == 1) && e[0] == '.') continue;   /* "." / ".." (never in a root, tolerated) */
            if (c >= 0x61 && c <= 0x7A) { ok = false; break; }      /* lower case is never stored in an 8.3 name */
            if (!name_char_ok(c)) { ok = false; break; }
        }
        if (ok) o->used++; else o->garbage++;
    }
}

bc_stor_state_t bc_stor_classify(const bc_stor_facts_t *f)
{
    if (!f) return BC_STOR_NOT_CHECKED;
    if (!f->partition_found || !f->mounted) return BC_STOR_FS_UNAVAILABLE;
    if (f->probe_attempted && f->probe_ok) return BC_STOR_OK;
    bool known_space = f->total_bytes > 0;
    uint64_t one = f->cluster_bytes ? f->cluster_bytes : 4096;
    bool no_space = known_space && f->free_bytes < one;
    if (f->root_scanned && f->root.entries > 0 && f->root.free_slots == 0) {
        uint16_t bad = (uint16_t)(f->root.erased + f->root.garbage);
        /* no slot to create a file: either the directory is full of real entries (full) or it is not a directory any more */
        if (bad * 2u >= f->root.entries) return BC_STOR_DIR_CORRUPTED;
        return BC_STOR_FULL;
    }
    if (no_space) return BC_STOR_FULL;
    if (!f->probe_attempted) return BC_STOR_NOT_CHECKED;
    return BC_STOR_WRITE_FAILED;
}

size_t bc_stor_describe(const bc_stor_facts_t *f, bc_stor_state_t s, char *out, size_t cap)
{
    if (!out || !cap) return 0;
    int n;
    if (!f) n = snprintf(out, cap, "%s", bc_stor_name(s));
    else if (!f->partition_found) n = snprintf(out, cap, "%s: no 'storage' partition", bc_stor_name(s));
    else if (!f->mounted) n = snprintf(out, cap, "%s: mount error %d (not formatted: data kept)", bc_stor_name(s), f->mount_err);
    else {
        n = snprintf(out, cap, "%s: mounted, %lu/%lu KB free", bc_stor_name(s), (unsigned long)(f->free_bytes / 1024), (unsigned long)(f->total_bytes / 1024));
        if (n > 0 && (size_t)n < cap && f->root_scanned)
            n += snprintf(out + n, cap - (size_t)n, ", root dir: used %u, lfn %u, free %u, erased %u, garbage %u", f->root.used, f->root.lfn, f->root.free_slots, f->root.erased, f->root.garbage);
        if (n > 0 && (size_t)n < cap && f->probe_attempted && !f->probe_ok)
            n += snprintf(out + n, cap - (size_t)n, ", probe write failed (errno %d)", f->probe_errno);
    }
    if (n < 0) { out[0] = 0; return 0; }
    return (size_t)n < cap ? (size_t)n : cap - 1;
}
