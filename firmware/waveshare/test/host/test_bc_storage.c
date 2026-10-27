/* bc_storage (0.7.4): failure categories from measured facts. The geometry below is the one measured on the owner's board
   (pre-0.7.3 backup, coord/reports/FW_STORAGE_MEMORY_REPORT.md): FAT12, 4096-byte sectors, 1 reserved, 2 FATs of 1 sector, 512 root
   entries (4 sectors), 1998 sectors, 1991 clusters. No personal data: synthetic directory contents only. */
#include "bc_storage.h"
#include <stdio.h>
#include <string.h>

static int checks, fails;
#define CHECK(c, ...) do { checks++; if (!(c)) { fails++; printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static void boot_sector(uint8_t *b)
{
    memset(b, 0, 4096);
    b[0] = 0xEB; b[1] = 0x3C; b[2] = 0x90; memcpy(b + 3, "MSDOS5.0", 8);
    b[11] = 0x00; b[12] = 0x10;           /* 4096 bytes per sector */
    b[13] = 1;                            /* sectors per cluster */
    b[14] = 1; b[15] = 0;                 /* reserved */
    b[16] = 2;                            /* FATs */
    b[17] = 0x00; b[18] = 0x02;           /* 512 root entries */
    b[19] = 0xCE; b[20] = 0x07;           /* 1998 sectors */
    b[21] = 0xF8; b[22] = 1; b[23] = 0;   /* media, 1 sector per FAT */
    memcpy(b + 43, "NO NAME    ", 11); memcpy(b + 54, "FAT     ", 8);
    b[510] = 0x55; b[511] = 0xAA;
}

static void ent(uint8_t *e, const char *name11, uint8_t attr) { memset(e, 0, 32); memcpy(e, name11, 11); e[11] = attr; }

static void test_location(void)
{
    static uint8_t b[4096]; boot_sector(b);
    uint32_t off = 0, len = 0, ss = 0;
    CHECK(bc_fat_root_location(b, sizeof b, &off, &len, &ss) && off == 3 * 4096 && len == 4 * 4096 && ss == 4096, "measured geometry: root at sector 3, 4 sectors (%u %u %u)", off, len, ss);
    b[510] = 0; CHECK(!bc_fat_root_location(b, sizeof b, &off, &len, &ss), "no 55AA signature: not a FAT boot sector");
    boot_sector(b); b[17] = 0; b[18] = 0; CHECK(!bc_fat_root_location(b, sizeof b, &off, &len, &ss), "FAT32 (root entries 0): no fixed root");
    boot_sector(b); b[11] = 0; b[12] = 3; CHECK(!bc_fat_root_location(b, sizeof b, &off, &len, &ss), "bad sector size");
    boot_sector(b); memset(b, 0xFF, 4096); CHECK(!bc_fat_root_location(b, sizeof b, &off, &len, &ss), "erased boot sector");
    CHECK(!bc_fat_root_location(b, 100, &off, &len, &ss), "short buffer");
}

static void test_scan(void)
{
    static uint8_t root[4 * 4096];
    bc_fat_root_t r;
    /* 24 Oct state: SELFTEST.TXT + RIDES, the rest zero */
    memset(root, 0, sizeof root); ent(root, "SELFTESTTXT", 0x20); ent(root + 32, "RIDES      ", 0x10);
    bc_fat_root_scan(root, sizeof root, &r);
    CHECK(r.entries == 512 && r.used == 2 && r.free_slots == 510 && r.erased == 0 && r.garbage == 0, "healthy root: 2 used, 510 free (%u %u %u %u)", r.used, r.free_slots, r.erased, r.garbage);
    /* 25-27 Oct state: all four root sectors erased */
    memset(root, 0xFF, sizeof root);
    bc_fat_root_scan(root, sizeof root, &r);
    CHECK(r.entries == 512 && r.used == 0 && r.free_slots == 0 && r.erased == 512, "erased root: 512 erased, no free slot");
    /* an LFN pair, a deleted entry and one garbage entry */
    memset(root, 0, sizeof root);
    uint8_t *e = root; memset(e, 0, 32); e[0] = 0x41; e[11] = 0x0F; ent(e + 32, "HISTORY TXT", 0x20);
    ent(e + 64, "OLD     TXT", 0x20); e[64] = 0xE5;
    memset(e + 96, 0xA5, 32);
    bc_fat_root_scan(root, sizeof root, &r);
    CHECK(r.lfn == 1 && r.used == 1 && r.garbage == 1 && r.free_slots == 509, "lfn %u used %u garbage %u free %u", r.lfn, r.used, r.garbage, r.free_slots);
    ent(e, "lower   txt", 0x20); bc_fat_root_scan(root, 32, &r); CHECK(r.garbage == 1, "lower-case 8.3 name is not a valid entry");
    ent(e, " SPACE  TXT", 0x20); bc_fat_root_scan(root, 32, &r); CHECK(r.garbage == 1, "leading space is not valid");
    bc_fat_root_scan(NULL, 0, &r); CHECK(r.entries == 0, "NULL root");
}

static void test_classify(void)
{
    bc_stor_facts_t f; memset(&f, 0, sizeof f);
    CHECK(bc_stor_classify(&f) == BC_STOR_FS_UNAVAILABLE, "no partition -> filesystem unavailable");
    f.partition_found = true; f.mount_err = 0x105;
    CHECK(bc_stor_classify(&f) == BC_STOR_FS_UNAVAILABLE, "mount failed -> filesystem unavailable (never formatted)");
    /* the measured board: mounted, 5096 KB free of 7964 KB, root erased, probe failed */
    f.mounted = true; f.mount_err = 0; f.total_bytes = 7964ull * 1024; f.free_bytes = 5096ull * 1024; f.cluster_bytes = 4096;
    f.root_scanned = true; f.root.entries = 512; f.root.erased = 512; f.probe_attempted = true; f.probe_ok = false; f.probe_errno = 13;
    CHECK(bc_stor_classify(&f) == BC_STOR_DIR_CORRUPTED, "measured board state -> Directory corrupted, NOT storage full");
    char line[200]; bc_stor_describe(&f, bc_stor_classify(&f), line, sizeof line);
    CHECK(strstr(line, "Directory corrupted") && strstr(line, "5096/7964 KB free") && strstr(line, "erased 512") && strstr(line, "errno 13"), "description: %s", line);
    /* 0.7.4 (QA QF-12): partial damage - one WL sector of the root erased (128 entries), 384 free slots, probe would pass */
    f.root.free_slots = 384; f.root.erased = 128; f.probe_ok = true;
    CHECK(bc_stor_classify(&f) == BC_STOR_DIR_CORRUPTED && bc_stor_root_damaged(&f), "partial damage (128 erased, 384 free) -> Directory corrupted, not written");
    f.root.erased = 0; f.root.garbage = 1; CHECK(bc_stor_classify(&f) == BC_STOR_DIR_CORRUPTED, "a single malformed entry -> Directory corrupted");
    f.root.garbage = 0; f.root.used = 10; f.root.free_slots = 502;
    CHECK(bc_stor_classify(&f) == BC_STOR_OK, "clean directory + probe OK -> OK");
    /* full of real entries */
    f.probe_ok = false; f.root.free_slots = 0; f.root.erased = 0; f.root.used = 512;
    CHECK(bc_stor_classify(&f) == BC_STOR_FULL, "root full of valid entries -> full");
    /* no free cluster */
    f.root.free_slots = 100; f.root.used = 412; f.free_bytes = 0;
    CHECK(bc_stor_classify(&f) == BC_STOR_FULL, "no free cluster -> full");
    /* space and directory fine, the probe failed anyway */
    f.free_bytes = 4ull << 20;
    CHECK(bc_stor_classify(&f) == BC_STOR_WRITE_FAILED, "space + directory fine, probe failed -> write failed");
    f.root_scanned = false; CHECK(bc_stor_classify(&f) == BC_STOR_WRITE_FAILED, "root not readable, space fine -> write failed");
    f.probe_attempted = false; CHECK(bc_stor_classify(&f) == BC_STOR_NOT_CHECKED, "no probe yet -> not checked");
    CHECK(bc_stor_classify(NULL) == BC_STOR_NOT_CHECKED, "NULL facts");
    /* every name fits the round screen; codes are distinct */
    for (int s = 0; s <= BC_STOR_NOT_CHECKED; s++) {
        CHECK(strlen(bc_stor_name((bc_stor_state_t)s)) <= 24, "name %d fits 24 chars: %s", s, bc_stor_name((bc_stor_state_t)s));
        CHECK(strlen(bc_stor_short((bc_stor_state_t)s)) <= 13, "short name %d fits 13 chars: %s", s, bc_stor_short((bc_stor_state_t)s));
        for (int t = 0; t < s; t++) CHECK(strcmp(bc_stor_code((bc_stor_state_t)s), bc_stor_code((bc_stor_state_t)t)), "codes %d/%d distinct", s, t);
    }
    CHECK(!strcmp(bc_crashpart_name(BC_CRASHPART_MISSING), "Crash partition missing") && strlen(bc_crashpart_name(BC_CRASHPART_BAD)) <= 24, "crash partition names");
    char small[8]; size_t n = bc_stor_describe(&f, BC_STOR_DIR_CORRUPTED, small, sizeof small); CHECK(n == 7 && small[7] == 0, "describe truncates safely");
}


/* ---- rc3 (QA QF-28): FAT consistency check on a synthetic FAT12 volume (1 MB, 4 KB clusters) */
#include <stdlib.h>
#define VOL (1024 * 1024)
static uint8_t *V;
static bool vread(void *ctx, uint32_t off, void *buf, uint32_t n) { (void)ctx; if (off + n > VOL) return false; memcpy(buf, V + off, n); return true; }
enum { BPS = 512, SPC = 8, RSV = 1, NFAT = 2, ROOTENT = 512, FATSZ = 1 };
static uint32_t root_off(void) { return (RSV + NFAT * FATSZ) * BPS; }
static uint32_t data_off(void) { return root_off() + ROOTENT * 32; }
static void fat_set(uint32_t c, uint32_t v)
{
    for (int f = 0; f < NFAT; f++) {
        uint8_t *fat = V + (RSV + f * FATSZ) * BPS; uint32_t o = c + c / 2;
        if (c & 1) { fat[o] = (uint8_t)((fat[o] & 0x0F) | ((v << 4) & 0xF0)); fat[o + 1] = (uint8_t)(v >> 4); }
        else { fat[o] = (uint8_t)v; fat[o + 1] = (uint8_t)((fat[o + 1] & 0xF0) | ((v >> 8) & 0x0F)); }
    }
}
static void dent(uint8_t *e, const char *name11, uint8_t attr, uint16_t start, uint32_t size)
{
    memset(e, 0, 32); memcpy(e, name11, 11); e[11] = attr; e[26] = (uint8_t)start; e[27] = (uint8_t)(start >> 8);
    e[28] = (uint8_t)size; e[29] = (uint8_t)(size >> 8); e[30] = (uint8_t)(size >> 16); e[31] = (uint8_t)(size >> 24);
}
static void mkvol(void)
{
    memset(V, 0, VOL);
    uint8_t *b = V; b[11] = BPS & 0xFF; b[12] = BPS >> 8; b[13] = SPC; b[14] = RSV; b[16] = NFAT; b[17] = ROOTENT & 0xFF; b[18] = ROOTENT >> 8;
    uint16_t tot = VOL / BPS; b[19] = (uint8_t)tot; b[20] = (uint8_t)(tot >> 8); b[22] = FATSZ; b[510] = 0x55; b[511] = 0xAA;
    fat_set(0, 0xFF8); fat_set(1, 0xFFF);
    uint8_t *root = V + root_off();
    dent(root, "HISTORY TXT", 0x20, 2, 5000); fat_set(2, 3); fat_set(3, 0xFFF);                 /* 2 clusters */
    dent(root + 32, "DIAG       ", 0x10, 4, 0); fat_set(4, 0xFFF);                              /* directory */
    uint8_t *d = V + data_off() + (4 - 2) * 4096;
    dent(d, ".          ", 0x10, 4, 0); dent(d + 32, "..         ", 0x10, 0, 0);
    dent(d + 64, "R000007 TXT", 0x20, 5, 9000); fat_set(5, 6); fat_set(6, 7); fat_set(7, 0xFFF);   /* 3 clusters */
    dent(d + 96, "EMPTY   TXT", 0x20, 0, 0);
}
static void test_fat_check(void)
{
    V = calloc(1, VOL);
    static uint8_t work[16384]; bc_fat_check_t c;
    mkvol();
    CHECK(bc_fat_check_work(V, 512) > 0 && bc_fat_check_work(V, 512) <= sizeof work, "work size %zu", bc_fat_check_work(V, 512));
    CHECK(bc_fat_check(vread, NULL, VOL, work, sizeof work, &c) && c.files == 3 && c.dirs == 1 && c.used == 6 && c.reachable == 6 && c.lost == 0,
          "consistent volume: %u files, %u dirs, %u used = %u reachable (%s)", c.files, c.dirs, c.used, c.reachable, c.why);
    mkvol(); fat_set(40, 0xFFF);   /* phantom-used cluster (the owner's FAT had 713) */
    CHECK(!bc_fat_check(vread, NULL, VOL, work, sizeof work, &c) && c.lost == 1 && strstr(c.why, "lost"), "a used cluster in no file: not consistent (%s)", c.why);
    mkvol(); { uint8_t *d = V + data_off() + 2 * 4096; dent(d + 96, "CROSS   TXT", 0x20, 6, 100); }
    CHECK(!bc_fat_check(vread, NULL, VOL, work, sizeof work, &c) && c.crosslinks >= 1, "cross-linked file: not consistent (%s)", c.why);
    mkvol(); dent(V + root_off(), "HISTORY TXT", 0x20, 2, 9000);
    CHECK(!bc_fat_check(vread, NULL, VOL, work, sizeof work, &c) && strstr(c.why, "size"), "size longer than its chain: not consistent (%s)", c.why);
    mkvol(); fat_set(3, 2);
    CHECK(!bc_fat_check(vread, NULL, VOL, work, sizeof work, &c) && c.crosslinks >= 1, "chain loop: not consistent (%s)", c.why);
    mkvol(); fat_set(6, 0);
    CHECK(!bc_fat_check(vread, NULL, VOL, work, sizeof work, &c) && strstr(c.why, "free cluster"), "free cluster inside a chain (%s)", c.why);
    mkvol(); memset(V + root_off() + 64, 0xFF, 32);
    CHECK(!bc_fat_check(vread, NULL, VOL, work, sizeof work, &c) && c.bad_entries == 1, "erased root entry: not consistent (%s)", c.why);
    mkvol(); fat_set(5, 0x900);
    CHECK(!bc_fat_check(vread, NULL, VOL, work, sizeof work, &c) && strstr(c.why, "leaves"), "chain pointing outside the volume (%s)", c.why);
    mkvol(); CHECK(!bc_fat_check(vread, NULL, VOL, work, 100, &c) && strstr(c.why, "work"), "too little work memory: refused");
    /* the REAL head of the owner's corrupted 0.7.3 image (metadata only): never judged consistent */
    FILE *f = fopen("fixtures/storage_073_head.bin", "rb");
    if (f) { memset(V, 0, VOL); size_t n = fread(V, 1, VOL, f); fclose(f);
             CHECK(n > 0 && !bc_fat_check(vread, NULL, VOL, work, sizeof work, &c), "the owner's corrupted image head: not consistent (%s)", c.why); }
    free(V);
}

int main(void)
{
    test_fat_check();
    test_location();
    test_scan();
    test_classify();
    printf("test_bc_storage: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
