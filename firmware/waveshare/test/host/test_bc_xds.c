/* Host unit tests for bc_core/bc_xds — same real packets as app/src/test/.../core/Fixtures.kt (XDS-A001-9769, 2026-10-11).
 * Build & run: make -C firmware/waveshare/test/host */
#include "bc_xds.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int fails = 0, checks = 0;
#define CHECK(c) do { checks++; if (!(c)) { fails++; printf("FAIL %s:%d  %s\n", __FILE__, __LINE__, #c); } } while (0)

static const char *SESSION[] = {
    "0|00 00 00 00 00 00 00 00 5A 01 00", "1029|00 00 00 00 00 00 00 00 5A 01 00", "2046|00 00 00 00 00 00 00 00 5A 01 00",
    "3050|00 00 00 00 00 00 00 00 5A 01 00", "4068|00 00 00 00 00 00 00 00 5A 01 00", "5044|00 00 00 00 00 00 00 00 5A 01 00",
    "6089|00 00 00 00 00 00 00 00 5A 01 00", "7072|00 00 00 00 00 00 00 00 5A 01 00", "8088|00 00 00 00 00 00 00 00 5A 01 00",
    "9110|00 00 00 00 00 00 00 00 5A 01 00", "10078|00 00 00 00 00 00 00 00 5A 01 00", "11129|00 00 00 00 00 00 00 00 5A 01 00",
    "12184|00 00 00 00 00 00 00 00 5A 01 00", "13138|00 00 00 00 00 00 00 00 5A 01 00", "14147|00 00 00 00 00 00 00 00 5A 01 00",
    "15164|00 00 00 00 00 00 00 00 5A 01 00", "16163|00 00 00 00 00 00 00 00 5A 01 00", "17198|00 00 00 00 00 00 00 00 5A 01 00",
    "18180|00 00 00 00 00 00 00 00 5A 01 00", "19230|00 00 00 00 00 00 00 00 5A 01 00", "20200|00 00 00 00 00 00 00 00 5A 01 00",
    "21250|00 00 00 00 00 00 00 00 5A 01 00", "22291|00 00 00 00 00 00 00 00 5A 01 00", "23263|00 00 00 00 00 00 00 00 5A 01 00",
    "24268|00 00 00 00 00 00 00 00 5A 01 00", "25308|00 00 00 00 00 00 00 00 5A 01 00", "26321|00 00 00 00 00 00 00 00 5A 01 00",
    "27332|00 00 00 00 00 00 00 00 5A 01 00", "28300|00 00 00 00 00 00 00 00 5A 01 00", "29352|00 00 00 00 00 00 00 00 5A 01 00",
    "30346|00 00 00 00 00 00 00 00 5A 01 00", "31378|00 00 00 00 00 00 00 00 5A 01 00",
    "32368|00 00 00 00 00 00 E8 FF 8C 00 00", "33345|00 00 00 00 00 00 DB FF 0A 00 00", "34377|00 00 00 00 00 00 BF FF 2A 00 00",
    "35376|00 00 00 00 00 00 B6 FF 90 00 00", "36404|00 00 00 00 00 00 B2 FF 0A 01 00", "37412|00 00 00 00 00 00 AA FF 31 00 00",
    "38430|00 00 00 00 00 00 A8 FF F1 00 00", "39432|00 00 00 00 00 00 A8 FF 25 00 00", "40407|00 00 00 00 00 00 AB FF E1 00 00",
    "41491|00 00 00 00 00 00 B0 FF 53 01 00", "42434|00 00 00 00 00 00 AD FF 8B 00 00", "43486|00 00 00 00 00 00 AD FF 1B 01 00",
    "44470|00 00 00 00 00 00 AF FF 2E 00 00", "45497|00 00 00 00 00 00 B9 FF 86 00 00", "46494|00 00 00 00 00 00 AB FF 25 01 00",
    "47554|00 00 00 00 00 00 AE FF 4F 00 00",
};

static size_t hex(const char *s, uint8_t *out) { size_t n = 0; unsigned v; int k; while (sscanf(s, "%2x%n", &v, &k) == 1) { out[n++] = (uint8_t)v; s += k; while (*s == ' ') s++; } return n; }

static void test_real_session(void)
{
    bc_xds_live_t l; bc_xds_live_reset(&l);
    int idle = 0, rotating = 0, backwards = 0;
    for (size_t i = 0; i < sizeof SESSION / sizeof *SESSION; i++) {
        uint32_t t = (uint32_t)atol(SESSION[i]); uint8_t b[16]; size_t n = hex(strchr(SESSION[i], '|') + 1, b);
        CHECK(n == 11);
        CHECK(bc_xds_live_feed(&l, b, n, t));
        int w = -1, rpm = -1; bool bw = false;
        CHECK(bc_xds_live_power(&l, t, &w) == BC_LIVE_OK && w == 0);       /* no load in this capture: 0 W, never invented */
        CHECK(bc_xds_live_cadence(&l, t, &rpm, &bw) == BC_LIVE_OK);
        if (rpm == 0) idle++; else { rotating++; if (bw) backwards++; CHECK(rpm >= 24 && rpm <= 88); }
    }
    CHECK(idle == 32 && rotating == 16 && backwards == 16);
    CHECK(l.packets == 48 && l.rejected == 0 && l.short_packets == 0);
    /* packet 38: A8 FF = -88 rpm, angle 0xF1 = 241 */
    uint8_t b[11]; hex("00 00 00 00 00 00 A8 FF F1 00 00", b); bc_xds_sample_t s; CHECK(bc_xds_decode(b, 11, &s));
    CHECK(s.cadence_signed_rpm == -88 && bc_xds_cadence_rpm(&s) == 88 && bc_xds_backwards(&s) && s.angle_deg == 241);
}

static void test_community_samples(void)
{
    const char *c[] = { "03 00 03 00 00 00 07 00 00 00 00", "07 00 00 00 07 00 0F 00 00 00 00", "02 00 01 00 01 00 18 00 00 00 00" };
    int exp_w[] = { 3, 7, 2 }, exp_c[] = { 7, 15, 24 };
    for (int i = 0; i < 3; i++) { uint8_t b[11]; hex(c[i], b); bc_xds_sample_t s; CHECK(bc_xds_decode(b, 11, &s));
        CHECK(s.power_w == exp_w[i] && s.left_w + s.right_w == s.power_w && bc_xds_cadence_rpm(&s) == exp_c[i] && !bc_xds_backwards(&s)); }
}

static void test_staleness_and_rejection(void)
{
    bc_xds_live_t l; bc_xds_live_reset(&l);
    int w; CHECK(bc_xds_live_power(&l, 0, &w) == BC_LIVE_NO_DATA);               /* nothing yet → NO DATA, not 0 */
    uint8_t ok[11]; hex("C8 00 64 00 64 00 5A 00 10 00 00", ok);                  /* 200 W, 90 rpm */
    CHECK(bc_xds_live_feed(&l, ok, 11, 1000));
    CHECK(bc_xds_live_power(&l, 5000, &w) == BC_LIVE_OK && w == 200);              /* 4.0 s old: still live */
    CHECK(bc_xds_live_power(&l, 5001, &w) == BC_LIVE_NO_DATA);                     /* 4.001 s: blanked, never held */
    uint8_t bad_angle[11]; hex("C8 00 64 00 64 00 5A 00 68 01 00", bad_angle);      /* angle 360 → implausible */
    CHECK(!bc_xds_live_feed(&l, bad_angle, 11, 6000) && l.rejected == 1);
    CHECK(bc_xds_live_power(&l, 6000, &w) == BC_LIVE_NO_DATA);                     /* rejected sample does not refresh */
    uint8_t too_much[11]; hex("B9 0B 00 00 00 00 5A 00 10 00 00", too_much);        /* 3001 W → implausible */
    CHECK(!bc_xds_live_feed(&l, too_much, 11, 6100));
    CHECK(!bc_xds_live_feed(&l, ok, 10, 6200) && l.short_packets == 1);            /* 10 bytes → never guessed */
    CHECK(!bc_xds_link_silent(&l, 12200) && bc_xds_link_silent(&l, 12201));        /* > 6 s after the last packet of any kind */
    bc_xds_sample_t s; CHECK(!bc_xds_decode(ok, 10, &s) && !bc_xds_decode(NULL, 11, &s));
}

int main(void)
{
    test_real_session(); test_community_samples(); test_staleness_and_rejection();
    printf("%s: %d checks, %d failures\n", fails ? "FAILED" : "OK", checks, fails);
    return fails ? 1 : 0;
}
