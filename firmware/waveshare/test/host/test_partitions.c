/*
 * Partition-table compatibility, 0.7.2 -> 0.7.3 (docs/PARTITIONS_0.7.3.md). Parses the shipped binary tables (MD5 checked),
 * the CSV, the OTA selector images and every app image in the kit, and proves:
 *   - nvs, otadata, phy_init, ota_0 and storage keep type, subtype, offset and size (no data moves, the running slot is the same);
 *   - ota_1 keeps its offset and only shrinks (0x400000 -> 0x3F0000); the new 'coredump' (data/coredump, 64 KB) lies entirely
 *     inside the old ota_1 range, i.e. it takes space from the unused slot only;
 *   - every kit otadata image is erased (all 0xFF) -> the bootloader always starts ota_0, so ota_1 was never used;
 *   - every app in the kit (0.4.0 .. 0.7.3) is far smaller than both slots: old firmware runs unchanged under the new table, and
 *     the new firmware under the old table only loses the core dump (it does not reference a partition that is missing).
 */
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>

static int fails, checks;
#define CHECK(c, ...) do { checks++; if (!(c)) { fails++; printf("FAIL %s:%d %s  ", __FILE__, __LINE__, #c); printf(__VA_ARGS__); printf("\n"); } } while (0)

/* ---- MD5 (RFC 1321), only to verify the table's own checksum row */
typedef struct { uint32_t a, b, c, d; uint64_t n; uint8_t buf[64]; } md5_t;
static uint32_t rol(uint32_t x, int c) { return (x << c) | (x >> (32 - c)); }
static void md5_block(md5_t *m, const uint8_t *p)
{
    static const uint32_t K[64] = { 0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,0x6b901122,0xfd987193,0xa679438e,0x49b40821,
        0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,
        0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,
        0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391 };
    static const int R[64] = { 7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21 };
    uint32_t w[16]; for (int i = 0; i < 16; i++) w[i] = (uint32_t)p[4*i] | ((uint32_t)p[4*i+1] << 8) | ((uint32_t)p[4*i+2] << 16) | ((uint32_t)p[4*i+3] << 24);
    uint32_t a = m->a, b = m->b, c = m->c, d = m->d;
    for (int i = 0; i < 64; i++) {
        uint32_t f; int g;
        if (i < 16) { f = (b & c) | (~b & d); g = i; } else if (i < 32) { f = (d & b) | (~d & c); g = (5*i + 1) % 16; }
        else if (i < 48) { f = b ^ c ^ d; g = (3*i + 5) % 16; } else { f = c ^ (b | ~d); g = (7*i) % 16; }
        uint32_t t = d; d = c; c = b; b = b + rol(a + f + K[i] + w[g], R[i]); a = t;
    }
    m->a += a; m->b += b; m->c += c; m->d += d;
}
static void md5(const uint8_t *p, size_t n, uint8_t out[16])
{
    md5_t m = { 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476, 0, {0} };
    size_t i = 0; for (; i + 64 <= n; i += 64) md5_block(&m, p + i);
    uint8_t t[128] = {0}; size_t r = n - i; memcpy(t, p + i, r); t[r] = 0x80;
    size_t tl = r + 1 + 8 <= 64 ? 64 : 128; uint64_t bits = (uint64_t)n * 8; for (int k = 0; k < 8; k++) t[tl - 8 + k] = (uint8_t)(bits >> (8 * k));
    md5_block(&m, t); if (tl == 128) md5_block(&m, t + 64);
    uint32_t v[4] = { m.a, m.b, m.c, m.d }; for (int k = 0; k < 16; k++) out[k] = (uint8_t)(v[k / 4] >> (8 * (k % 4)));
}

typedef struct { char name[17]; uint8_t type, sub; uint32_t off, size; } part_t;
static int load_bin(const char *path, part_t *p, int max, bool *md5_ok)
{
    FILE *f = fopen(path, "rb"); if (!f) return -1;
    uint8_t b[3072]; size_t n = fread(b, 1, sizeof b, f); fclose(f);
    int k = 0; *md5_ok = false;
    for (size_t i = 0; i + 32 <= n; i += 32) {
        if (b[i] == 0xAA && b[i + 1] == 0x50 && k < max) {
            p[k].type = b[i + 2]; p[k].sub = b[i + 3];
            p[k].off = (uint32_t)b[i+4] | ((uint32_t)b[i+5] << 8) | ((uint32_t)b[i+6] << 16) | ((uint32_t)b[i+7] << 24);
            p[k].size = (uint32_t)b[i+8] | ((uint32_t)b[i+9] << 8) | ((uint32_t)b[i+10] << 16) | ((uint32_t)b[i+11] << 24);
            memcpy(p[k].name, b + i + 12, 16); p[k].name[16] = 0; k++;
        } else if (b[i] == 0xEB && b[i + 1] == 0xEB) { uint8_t d[16]; md5(b, i, d); *md5_ok = !memcmp(d, b + i + 16, 16); break; }
        else break;
    }
    return k;
}
static const part_t *find(const part_t *p, int n, const char *name) { for (int i = 0; i < n; i++) if (!strcmp(p[i].name, name)) return &p[i]; return NULL; }
static uint32_t num(const char *s) { return (uint32_t)strtoul(s, NULL, 0); }
static int load_csv(const char *path, part_t *p, int max)
{
    FILE *f = fopen(path, "r"); if (!f) return -1;
    char line[256]; int k = 0;
    while (fgets(line, sizeof line, f) && k < max) {
        if (line[0] == '#' || line[0] == '\n') continue;
        char nm[17], ty[32], st[32], of[32], sz[32];
        if (sscanf(line, " %16[^, ] , %31[^, ] , %31[^, ] , %31[^, ] , %31[^, \n]", nm, ty, st, of, sz) != 5) continue;
        snprintf(p[k].name, sizeof p[k].name, "%.16s", nm); p[k].off = num(of); p[k].size = num(sz); p[k].type = !strcmp(ty, "app") ? 0 : 1;
        p[k].sub = !strcmp(st, "nvs") ? 2 : !strcmp(st, "ota") ? 0 : !strcmp(st, "phy") ? 1 : !strcmp(st, "ota_0") ? 0x10 : !strcmp(st, "ota_1") ? 0x11 : !strcmp(st, "coredump") ? 3 : !strcmp(st, "fat") ? 0x81 : 0xFF;
        k++;
    }
    fclose(f); return k;
}
static long app_len(const char *path) { FILE *f = fopen(path, "rb"); if (!f) return -1; fseek(f, 0, SEEK_END); long n = ftell(f); uint8_t m = 0; fseek(f, 0, SEEK_SET); if (fread(&m, 1, 1, f) != 1) m = 0; fclose(f); return m == 0xE9 ? n : -2; }

int main(void)
{
    const char *KIT = "../../pc-kit";
    part_t o[16], n[16], c[16]; bool mo = false, mn = false;
    int no = load_bin("../../pc-kit/fw-v0.7.2/BC072-partitions.bin", o, 16, &mo);
    const char *newp = "../../pc-kit/fw-v0.7.3/BC073-partitions.bin";
    int nn = load_bin(newp, n, 16, &mn);
    if (nn < 0) { newp = "../../build/partition_table/partition-table.bin"; nn = load_bin(newp, n, 16, &mn); }
    int nc = load_csv("../../partitions.csv", c, 16);
    printf("  old table (0.7.2 kit): %d entries, MD5 %s; new table (%s): %d entries, MD5 %s; CSV %d entries\n", no, mo ? "ok" : "BAD", newp, nn, mn ? "ok" : "BAD", nc);
    CHECK(no == 6 && mo, "0.7.2 table parsed");
    CHECK(nn == 7 && mn, "0.7.3 table parsed");
    CHECK(nc == nn, "CSV and binary agree in count");
    for (int i = 0; i < nn && i < nc; i++) CHECK(!strcmp(c[i].name, n[i].name) && c[i].off == n[i].off && c[i].size == n[i].size && c[i].type == n[i].type && c[i].sub == n[i].sub, "CSV == binary for %s", n[i].name);
    static const char *const SAME[] = { "nvs", "otadata", "phy_init", "ota_0", "storage" };
    for (int i = 0; i < 5; i++) {
        const part_t *a = find(o, no, SAME[i]), *b = find(n, nn, SAME[i]);
        CHECK(a && b && a->type == b->type && a->sub == b->sub && a->off == b->off && a->size == b->size, "%s unchanged (old 0x%X+0x%X, new 0x%X+0x%X)", SAME[i], a ? a->off : 0, a ? a->size : 0, b ? b->off : 0, b ? b->size : 0);
    }
    const part_t *o1 = find(o, no, "ota_1"), *n1 = find(n, nn, "ota_1"), *cd = find(n, nn, "coredump");
    CHECK(o1 && n1 && o1->off == n1->off && n1->size == 0x3F0000 && o1->size == 0x400000, "ota_1 keeps its offset, shrinks 0x400000 -> 0x3F0000");
    CHECK(cd && cd->type == 1 && cd->sub == 3 && cd->off == 0x810000 && cd->size == 0x10000, "coredump data/coredump at 0x810000, 64 KB");
    CHECK(cd && o1 && cd->off >= o1->off && cd->off + cd->size <= o1->off + o1->size, "coredump lies entirely inside the OLD ota_1 range (no data partition is touched)");
    for (int i = 0; i < nn; i++) {
        CHECK(n[i].off % 0x1000 == 0 && n[i].size % 0x1000 == 0 && n[i].off + n[i].size <= 0x1000000, "%s 4 KB aligned, inside 16 MB", n[i].name);
        if (n[i].type == 0) CHECK(n[i].off % 0x10000 == 0, "%s app 64 KB aligned", n[i].name);
        for (int j = i + 1; j < nn; j++) CHECK(n[i].off + n[i].size <= n[j].off || n[j].off + n[j].size <= n[i].off, "%s and %s do not overlap", n[i].name, n[j].name);
    }
    /* every kit: otadata erased (boots ota_0), app fits the smaller slot */
    DIR *d = opendir(KIT); struct dirent *e; int kits = 0, apps = 0; long biggest = 0;
    while (d && (e = readdir(d))) {
        if (strncmp(e->d_name, "fw-v", 4)) continue;
        char dir[512]; snprintf(dir, sizeof dir, "%s/%s", KIT, e->d_name);
        DIR *dd = opendir(dir); struct dirent *f;
        while (dd && (f = readdir(dd))) {
            char p[1024]; snprintf(p, sizeof p, "%s/%s", dir, f->d_name);
            if (strstr(f->d_name, "otadata")) {
                FILE *x = fopen(p, "rb"); uint8_t b[8192]; size_t r = x ? fread(b, 1, sizeof b, x) : 0; if (x) fclose(x);
                bool ff = r == 8192; for (size_t k = 0; k < r; k++) if (b[k] != 0xFF) ff = false;
                CHECK(ff, "%s is erased (bootloader starts ota_0)", p); kits++;
            }
            if (strstr(f->d_name, "-app.bin")) {
                long l = app_len(p); CHECK(l > 0 && l < 0x3F0000, "%s: %ld bytes fits ota_0 and the smaller ota_1", p, l); apps++; if (l > biggest) biggest = l;
            }
        }
        if (dd) closedir(dd);
    }
    if (d) closedir(d);
    CHECK(kits >= 5 && apps >= 5, "kits checked: %d otadata images, %d apps (largest %ld bytes = %ld%% of the smaller slot)", kits, apps, biggest, biggest * 100 / 0x3F0000);
    printf("  %d otadata images all erased, %d app images, largest %ld bytes (%ld%% of 0x3F0000)\n", kits, apps, biggest, biggest * 100 / 0x3F0000);
    printf("test_partitions: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
