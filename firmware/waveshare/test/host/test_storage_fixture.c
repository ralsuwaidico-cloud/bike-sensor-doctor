/* 0.7.4: the REAL filesystem heads from the owner's flash backups (de-wear-levelled with tools/storage_audit.py; boot sector,
   both FATs and the 4 root-directory sectors only - FAT metadata, no file contents, no personal data):
     fixtures/storage_v040_head.bin   24 Oct 20:18, before the damage (SELFTEST.TXT + RIDES)
     fixtures/storage_073_head.bin    27 Oct 12:04, the state 0.7.3 found (root directory erased)
   The board's own 0.7.3 log for the second state: mounted, "FAT 5096 KB free / 7964 KB", probe write FAILED.
   The classifier must call it "Directory corrupted" - never "storage full". */
#include "bc_storage.h"
#include <stdio.h>
#include <string.h>

static int checks, fails;
#define CHECK(c, ...) do { checks++; if (!(c)) { fails++; printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static long load(const char *p, uint8_t *b, size_t cap) { FILE *f = fopen(p, "rb"); if (!f) return -1; long n = (long)fread(b, 1, cap, f); fclose(f); return n; }
static unsigned fat12_free(const uint8_t *fat, unsigned clusters)
{
    unsigned n = 0;
    for (unsigned c = 2; c < clusters + 2; c++) { unsigned o = c * 3 / 2, v = fat[o] | (fat[o + 1] << 8); v = (c & 1) ? v >> 4 : v & 0xFFF; if (!v) n++; }
    return n;
}

static void one(const char *path, bool damaged)
{
    static uint8_t img[7 * 4096];
    long n = load(path, img, sizeof img);
    CHECK(n == (long)sizeof img, "%s loaded (%ld bytes)", path, n);
    if (n != (long)sizeof img) return;
    uint32_t off, len, ss;
    CHECK(bc_fat_root_location(img, sizeof img, &off, &len, &ss) && off == 3 * 4096 && len == 4 * 4096 && ss == 4096, "%s: root at sector 3, 4 sectors", path);
    bc_fat_root_t r; bc_fat_root_scan(img + off, len, &r);
    unsigned freec = fat12_free(img + 4096, 1991);
    bc_stor_facts_t f; memset(&f, 0, sizeof f);
    f.partition_found = f.mounted = true; f.total_bytes = 1991ull * 4096; f.free_bytes = (uint64_t)freec * 4096; f.cluster_bytes = 4096;
    f.root_scanned = true; f.root = r; f.probe_attempted = !damaged; f.probe_ok = !damaged;
    bc_stor_state_t s = bc_stor_classify(&f);
    char d[200]; bc_stor_describe(&f, s, d, sizeof d); printf("  %s: %s\n", path, d);
    if (damaged) {
        CHECK(r.erased == 512 && r.free_slots == 0 && r.used == 0, "real 27 Oct image: 512/512 root entries erased");
        CHECK(freec * 4 == 5096, "real image: %u KB free = the board's own log (5096 KB)", freec * 4);
        CHECK(s == BC_STOR_DIR_CORRUPTED, "real image -> Directory corrupted (got %s)", bc_stor_name(s));
        f.probe_attempted = true; f.probe_ok = false; CHECK(bc_stor_classify(&f) == BC_STOR_DIR_CORRUPTED, "with the failed probe too");
    } else {
        CHECK(r.used == 2 && r.free_slots == 510 && r.erased == 0, "real 24 Oct image: SELFTEST.TXT + RIDES, 510 free slots");
        CHECK(s == BC_STOR_OK, "24 Oct image -> OK");
    }
}

int main(void)
{
    one("fixtures/storage_v040_head.bin", false);
    one("fixtures/storage_073_head.bin", true);
    printf("test_storage_fixture: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
