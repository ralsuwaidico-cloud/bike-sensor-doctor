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

const char *bc_stor_short(bc_stor_state_t s)
{
    switch (s) {
    case BC_STOR_OK: return "storage ok";
    case BC_STOR_FULL: return "storage full";
    case BC_STOR_FS_UNAVAILABLE: return "no filesystem";
    case BC_STOR_DIR_CORRUPTED: return "dir corrupted";
    case BC_STOR_WRITE_FAILED: return "write failed";
    case BC_STOR_DIAG_UNAVAILABLE: return "diag off";
    case BC_STOR_DIAG_FULL: return "reports full";
    case BC_STOR_NOT_CHECKED: default: return "not checked";
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

bool bc_stor_root_damaged(const bc_stor_facts_t *f)
{
    return f && f->root_scanned && (f->root.erased > 0 || f->root.garbage > 0);
}

bc_stor_state_t bc_stor_classify(const bc_stor_facts_t *f)
{
    if (!f) return BC_STOR_NOT_CHECKED;
    if (!f->partition_found || !f->mounted) return BC_STOR_FS_UNAVAILABLE;
    /* 0.7.4 (QA QF-12): FatFs never writes an erased (0xFF) or malformed directory entry, so ANY such entry in the root means
       the directory is damaged - even if some slots are still free and a probe would succeed. Nothing is written then. */
    if (bc_stor_root_damaged(f)) return BC_STOR_DIR_CORRUPTED;
    if (f->probe_attempted && f->probe_ok) return BC_STOR_OK;
    bool known_space = f->total_bytes > 0;
    uint64_t one = f->cluster_bytes ? f->cluster_bytes : 4096;
    bool no_space = known_space && f->free_bytes < one;
    if (f->root_scanned && f->root.entries > 0 && f->root.free_slots == 0) return BC_STOR_FULL;   /* full of valid entries */
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

/* ------------------------------------------------------------------ rc3 (QA QF-28): FAT consistency before deleting */
typedef struct {
    bc_fat_read_fn rd; void *ctx; uint32_t vol_len;
    uint32_t bps, spc, clus_bytes, fat_off, root_off, root_len, data_off, nclus; bool fat12;
    uint8_t *fat; uint8_t *bm; uint8_t *buf;
    bc_fat_check_t *o;
} fck_t;
static void fbad(fck_t *k, const char *why) { if (k->o->ok) { k->o->ok = false; snprintf(k->o->why, sizeof k->o->why, "%s", why); } }
static uint32_t fnext(const fck_t *k, uint32_t c)
{
    if (k->fat12) { uint32_t o = c + c / 2; uint32_t v = k->fat[o] | (k->fat[o + 1] << 8); return (c & 1) ? v >> 4 : v & 0xFFF; }
    return (uint32_t)(k->fat[2 * c] | (k->fat[2 * c + 1] << 8));
}
static uint32_t feoc(const fck_t *k) { return k->fat12 ? 0xFF8 : 0xFFF8; }
static uint32_t fbadc(const fck_t *k) { return k->fat12 ? 0xFF7 : 0xFFF7; }
static bool fvisit(fck_t *k, uint32_t c) { uint32_t i = c - 2; if (k->bm[i / 8] & (1u << (i % 8))) return false; k->bm[i / 8] |= (uint8_t)(1u << (i % 8)); return true; }
/* walks a chain; for a directory (dir_depth >= 0) parses every cluster */
static void fdir(fck_t *k, const uint8_t *ents, uint32_t len, int depth, bool *end);
static uint32_t fchain(fck_t *k, uint32_t c, int dir_depth)
{
    uint32_t n = 0; bool end = false;
    for (;;) {
        if (c < 2 || c >= k->nclus + 2) { k->o->bad_chains++; fbad(k, "chain leaves the volume"); return n; }
        if (!fvisit(k, c)) { k->o->crosslinks++; fbad(k, "cluster in two chains (cross-link / loop)"); return n; }
        n++; k->o->reachable++;
        if (dir_depth >= 0 && !end) {
            uint32_t off = k->data_off + (c - 2) * k->clus_bytes;
            if (off + k->clus_bytes > k->vol_len || !k->rd(k->ctx, off, k->buf, k->clus_bytes)) { fbad(k, "directory read error"); return n; }
            uint8_t tmp[32 * 4]; uint32_t done = 0;   /* parse in place: entries are copied out in small groups (recursion reuses buf) */
            while (done < k->clus_bytes && !end) {
                uint32_t m = k->clus_bytes - done < sizeof tmp ? k->clus_bytes - done : (uint32_t)sizeof tmp;
                memcpy(tmp, k->buf + done, m);
                fdir(k, tmp, m, dir_depth, &end);
                if (!end && done + m < k->clus_bytes) {   /* recursion may have overwritten buf: read the cluster again */
                    if (!k->rd(k->ctx, off, k->buf, k->clus_bytes)) { fbad(k, "directory read error"); return n; }
                }
                done += m;
            }
        }
        uint32_t v = fnext(k, c);
        if (v == 0) { k->o->bad_chains++; fbad(k, "free cluster inside a chain"); return n; }
        if (v == fbadc(k)) { k->o->bad_chains++; fbad(k, "bad-cluster mark inside a chain"); return n; }
        if (v >= feoc(k)) return n;
        if (n > k->nclus) { fbad(k, "chain longer than the volume"); return n; }
        c = v;
    }
}
static void fdir(fck_t *k, const uint8_t *ents, uint32_t len, int depth, bool *end)
{
    for (uint32_t i = 0; i + 32 <= len; i += 32) {
        const uint8_t *e = ents + i;
        if (e[0] == 0x00) { *end = true; return; }                  /* end of directory */
        if (e[0] == 0xE5) continue;                                  /* deleted */
        bc_fat_root_t one; bc_fat_root_scan(e, 32, &one);
        if (one.erased || one.garbage) { k->o->bad_entries++; fbad(k, one.erased ? "erased directory entry" : "malformed directory entry"); continue; }
        if (one.lfn) continue;
        uint8_t attr = e[11];
        if (attr & 0x08) continue;                                   /* volume label */
        if (e[0] == '.') continue;                                   /* "." / ".." */
        uint32_t start = (uint32_t)(e[26] | (e[27] << 8));
        uint32_t size = (uint32_t)e[28] | ((uint32_t)e[29] << 8) | ((uint32_t)e[30] << 16) | ((uint32_t)e[31] << 24);
        if (attr & 0x10) {
            k->o->dirs++;
            if (depth >= 6) { fbad(k, "directories nested too deep"); continue; }
            if (!start) { k->o->bad_chains++; fbad(k, "directory without a cluster"); continue; }
            fchain(k, start, depth + 1);
        } else {
            k->o->files++;
            uint32_t want = (size + k->clus_bytes - 1) / k->clus_bytes;
            if (!size) { if (start) { k->o->bad_chains++; fbad(k, "empty file with clusters"); } continue; }
            if (!start) { k->o->bad_chains++; fbad(k, "file without clusters"); continue; }
            uint32_t got = fchain(k, start, -1);
            if (got != want && k->o->ok) { k->o->bad_chains++; fbad(k, "file size does not match its chain"); }
        }
    }
}
static bool fgeom(fck_t *k, const uint8_t *b)
{
    if (b[510] != 0x55 || b[511] != 0xAA) return false;
    uint32_t bps = le16(b + 11), spc = b[13], rsv = le16(b + 14), nfat = b[16], rootent = le16(b + 17), fatsz = le16(b + 22);
    uint32_t tot = le16(b + 19); if (!tot) tot = (uint32_t)b[32] | ((uint32_t)b[33] << 8) | ((uint32_t)b[34] << 16) | ((uint32_t)b[35] << 24);
    if ((bps != 512 && bps != 1024 && bps != 2048 && bps != 4096) || !spc || (spc & (spc - 1)) || !rsv || !nfat || nfat > 2 || !rootent || !fatsz) return false;
    k->bps = bps; k->spc = spc; k->clus_bytes = bps * spc; k->fat_off = rsv * bps;
    k->root_off = (rsv + nfat * fatsz) * bps; k->root_len = (rootent * 32 + bps - 1) / bps * bps;
    k->data_off = k->root_off + k->root_len;
    uint32_t data_sec = tot > k->data_off / bps ? tot - k->data_off / bps : 0;
    k->nclus = data_sec / spc; k->fat12 = k->nclus < 4085;
    if (!k->nclus || k->nclus >= 65525) return false;
    uint32_t need = k->fat12 ? (k->nclus + 2) * 3 / 2 + 2 : (k->nclus + 2) * 2;
    return need <= fatsz * bps;
}
size_t bc_fat_check_work(const uint8_t *b, size_t n)
{
    if (!b || n < 512) return 0;
    fck_t k; memset(&k, 0, sizeof k);
    if (!fgeom(&k, b)) return 0;
    uint32_t fatsz = le16(b + 22) * k.bps;
    return fatsz + (k.nclus + 7) / 8 + k.clus_bytes;
}
bool bc_fat_check(bc_fat_read_fn rd, void *ctx, uint32_t vol_len, void *work, size_t work_cap, bc_fat_check_t *o)
{
    memset(o, 0, sizeof *o); o->ok = true;
    fck_t k; memset(&k, 0, sizeof k); k.rd = rd; k.ctx = ctx; k.vol_len = vol_len; k.o = o;
    uint8_t boot[512];
    if (!rd || !rd(ctx, 0, boot, sizeof boot)) { fbad(&k, "boot sector read error"); return false; }
    if (!fgeom(&k, boot)) { fbad(&k, "not a FAT12/16 volume"); return false; }
    uint32_t fatsz = le16(boot + 22) * k.bps;
    size_t need = fatsz + (k.nclus + 7) / 8 + k.clus_bytes;
    if (!work || work_cap < need) { fbad(&k, "no work memory"); return false; }
    if (k.data_off + (uint64_t)k.nclus * k.clus_bytes > vol_len) { fbad(&k, "volume shorter than its boot sector says"); return false; }
    k.fat = work; k.bm = k.fat + fatsz; k.buf = k.bm + (k.nclus + 7) / 8;
    memset(k.bm, 0, (k.nclus + 7) / 8);
    if (!rd(ctx, k.fat_off, k.fat, fatsz)) { fbad(&k, "FAT read error"); return false; }
    o->clusters = k.nclus;
    /* root directory: fixed region, read one cluster-sized piece at a time */
    bool end = false;
    for (uint32_t off = 0; off < k.root_len && !end; off += k.clus_bytes) {
        uint32_t m = k.root_len - off < k.clus_bytes ? k.root_len - off : k.clus_bytes;
        if (!rd(ctx, k.root_off + off, k.buf, m)) { fbad(&k, "root directory read error"); return false; }
        for (uint32_t done = 0; done < m && !end; done += 256) {
            uint8_t tmp[256]; uint32_t g = m - done < 256 ? m - done : 256; memcpy(tmp, k.buf + done, g);
            fdir(&k, tmp, g, 0, &end);
            if (!end && done + 256 < m && !rd(ctx, k.root_off + off, k.buf, m)) { fbad(&k, "root directory read error"); return false; }
        }
    }
    for (uint32_t c = 2; c < k.nclus + 2; c++) {
        uint32_t v = fnext(&k, c);
        if (v != 0 && v != fbadc(&k)) { o->used++; uint32_t i = c - 2; if (!(k.bm[i / 8] & (1u << (i % 8)))) o->lost++; }
    }
    if (o->lost) fbad(&k, "clusters marked used but in no file (lost)");
    return o->ok;
}
