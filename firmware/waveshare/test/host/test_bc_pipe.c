/* Host unit tests for the 0.7.2 sensor pipeline: GATT descriptor choice (the "connected but no power" root cause),
 * standard Cycling Power decoding, the stage machine + recovery timers on a fake clock, and the SENSOR_DIAG wire vectors
 * that docs/BLE_LINK_PROTOCOL.md publishes for the iOS app. Build & run: make -C firmware/waveshare/test/host */
#include "bc_gatt.h"
#include "bc_pipe.h"
#include "bc_cp.h"
#include "bc_xds.h"
#include "bc_link.h"
#include <stdio.h>
#include <string.h>

static int fails = 0, checks = 0;
#define CHECK(c) do { checks++; if (!(c)) { fails++; printf("FAIL %s:%d  %s\n", __FILE__, __LINE__, #c); } } while (0)

/* ---- fake GATT databases (handle order, as ATT Find Information reports them) */
typedef struct { uint16_t handle, uuid; uint8_t props; } fattr_t;   /* props only on 0x2803 rows: the declared characteristic's properties */
/* XDS-A001 service 0x1828 as documented in docs/PORTING_SPEC.md §2 (2A63 N, 2A65 R, 2A5D R, 2A55 W+I) */
static const fattr_t XDS_DB[] = {
    { 0x0020, 0x2800, 0 },
    { 0x0021, 0x2803, 0x10 }, { 0x0022, 0x2A63, 0 }, { 0x0023, 0x2902, 0 },
    { 0x0024, 0x2803, 0x02 }, { 0x0025, 0x2A65, 0 },
    { 0x0026, 0x2803, 0x02 }, { 0x0027, 0x2A5D, 0 },
    { 0x0028, 0x2803, 0x28 }, { 0x0029, 0x2A55, 0 }, { 0x002A, 0x2902, 0 },
};
/* Mesh-Proxy style ordering from the brief: 2A63 then 2ADD (write) and 2ADE (notify, own CCCD) */
static const fattr_t MESH_DB[] = {
    { 0x0010, 0x2800, 0 },
    { 0x0011, 0x2803, 0x10 }, { 0x0012, 0x2A63, 0 }, { 0x0013, 0x2902, 0 },
    { 0x0014, 0x2803, 0x0C }, { 0x0015, 0x2ADD, 0 },
    { 0x0016, 0x2803, 0x10 }, { 0x0017, 0x2ADE, 0 }, { 0x0018, 0x2902, 0 },
};

/* characteristic discovery over a fake DB */
static int fake_chrs(const fattr_t *db, int n, bc_gatt_chr_t *out)
{
    int k = 0;
    for (int i = 0; i < n; i++) if (db[i].uuid == 0x2803 && i + 1 < n) { out[k].def_handle = db[i].handle; out[k].val_handle = db[i + 1].handle; out[k].uuid16 = db[i + 1].uuid; out[k].props = db[i].props; k++; }
    return k;
}
/* descriptor discovery (Find Information) from val+1 to end: EVERY attribute in the range, as NimBLE reports it */
static int fake_dscs(const fattr_t *db, int n, uint16_t val, uint16_t end, bc_gatt_attr_t *out)
{
    int k = 0;
    for (int i = 0; i < n; i++) if (db[i].handle > val && db[i].handle <= end) { out[k].handle = db[i].handle; out[k].uuid16 = db[i].uuid; k++; }
    return k;
}
/* the 0.2.0 .. 0.7.1 logic of ble_central.c on_dsc(): every 0x2902 from the value handle to the SERVICE END, last one wins */
static uint16_t legacy_pick(const bc_gatt_attr_t *a, int n) { uint16_t c = 0; for (int i = 0; i < n; i++) if (a[i].uuid16 == 0x2902) c = a[i].handle; return c; }

static void test_cccd_choice(void)
{
    bc_gatt_chr_t ch[8]; bc_gatt_attr_t d[16];
    /* XDS: the bug — the legacy search takes the CONTROL POINT's CCCD (0x002A) instead of 0x2A63's (0x0023) */
    int nx = (int)(sizeof XDS_DB / sizeof *XDS_DB), nc = fake_chrs(XDS_DB, nx, ch);
    CHECK(nc == 4);
    int i = bc_gatt_find_chr(ch, nc, 0x2A63);
    CHECK(i == 0 && ch[i].val_handle == 0x0022);
    int nd = fake_dscs(XDS_DB, nx, ch[i].val_handle, 0x002A /* svc end */, d);
    CHECK(legacy_pick(d, nd) == 0x002A);                                   /* BUG reproduced: 01 00 went to 0x2A55's CCCD */
    CHECK(bc_gatt_pick_cccd(d, nd, ch[i].val_handle, 0x002A) == 0x0023);   /* fix, even with the old generous range */
    uint16_t end = bc_gatt_chr_end(ch, nc, i, 0x002A);
    CHECK(end == 0x0023);
    nd = fake_dscs(XDS_DB, nx, ch[i].val_handle, end, d);
    CHECK(nd == 1 && bc_gatt_pick_cccd(d, nd, ch[i].val_handle, end) == 0x0023);
    CHECK(bc_gatt_cccd_value(ch[i].props) == 0x0001);
    /* the control point is write+indicate: it would get 02 00 — but it is never subscribed (not the data characteristic) */
    CHECK(bc_gatt_cccd_value(ch[3].props) == 0x0002 && ch[3].uuid16 == 0x2A55);

    /* Mesh-Proxy ordering: 2A63 then 2ADE (notify, own CCCD) */
    int nm = (int)(sizeof MESH_DB / sizeof *MESH_DB); nc = fake_chrs(MESH_DB, nm, ch);
    i = bc_gatt_find_chr(ch, nc, 0x2A63);
    nd = fake_dscs(MESH_DB, nm, ch[i].val_handle, 0x0018, d);
    CHECK(legacy_pick(d, nd) == 0x0018);                                   /* bug: notifications enabled on 2ADE */
    CHECK(bc_gatt_pick_cccd(d, nd, ch[i].val_handle, 0x0018) == 0x0013);
    CHECK(bc_gatt_chr_end(ch, nc, i, 0x0018) == 0x0013);
    CHECK(bc_gatt_chr_end(ch, nc, 2, 0x0018) == 0x0018);                   /* last characteristic: service end */

    /* 2A63 without a CCCD of its own, a later characteristic has one: never borrow it */
    static const fattr_t NO_CCCD[] = { { 1, 0x2800, 0 }, { 2, 0x2803, 0x10 }, { 3, 0x2A63, 0 }, { 4, 0x2803, 0x10 }, { 5, 0x2ADE, 0 }, { 6, 0x2902, 0 } };
    nc = fake_chrs(NO_CCCD, 6, ch); nd = fake_dscs(NO_CCCD, 6, 3, 6, d);
    CHECK(bc_gatt_pick_cccd(d, nd, 3, 6) == 0);
    CHECK(legacy_pick(d, nd) == 6);
    /* a characteristic with a user-description before its CCCD (0x2901 then 0x2902) */
    static const bc_gatt_attr_t UD[] = { { 0x31, 0x2901 }, { 0x32, 0x2902 }, { 0x33, 0x2803 }, { 0x34, 0x2A5D }, { 0x35, 0x2902 } };
    CHECK(bc_gatt_pick_cccd(UD, 5, 0x30, 0x40) == 0x32);
    CHECK(bc_gatt_pick_cccd(UD, 5, 0x30, 0x31) == 0);                     /* out of range */
    CHECK(bc_gatt_pick_cccd(NULL, 0, 1, 2) == 0);
    /* indicate-only / neither */
    CHECK(bc_gatt_cccd_value(0x20) == 0x0002 && bc_gatt_cccd_value(0x30) == 0x0001 && bc_gatt_cccd_value(0x02) == 0);
    CHECK(bc_gatt_find_chr(ch, nc, 0x1234) == -1 && bc_gatt_chr_end(ch, nc, 9, 10) == 0);

    /* which 0x2A63: XDS name -> 0x1828 first (proprietary decoder), others -> 0x1818 first (standard decoder) */
    uint16_t o[2];
    CHECK(bc_gatt_power_services("XDS-A001-9769", o) == 2 && o[0] == 0x1828 && o[1] == 0x1818);
    CHECK(bc_gatt_power_services("4iiii PRECISION", o) == 2 && o[0] == 0x1818 && o[1] == 0x1828);
    CHECK(bc_gatt_power_services(NULL, o) == 2 && o[0] == 0x1818);
    CHECK(bc_gatt_power_format(0x1828) == BC_PFMT_XDS && bc_gatt_power_format(0x1818) == BC_PFMT_CPS && bc_gatt_power_format(0x180D) == BC_PFMT_NONE);
}

/* XDS decoder: byte-for-byte the rules of app/.../core/XdsDecoder.kt (offsets, signedness, plausibility) */
static void test_xds_reverify(void)
{
    const uint8_t a[11] = { 0x8E, 0x00, 0x46, 0x00, 0x48, 0x00, 0x52, 0x00, 0x10, 0x01, 0x00 };   /* 142 W, L 70, R 72, 82 rpm, 272 deg */
    bc_xds_sample_t s; CHECK(bc_xds_decode(a, 11, &s));
    CHECK(s.power_w == 142 && s.left_w == 70 && s.right_w == 72 && s.cadence_signed_rpm == 82 && s.angle_deg == 272 && s.error == 0 && bc_xds_plausible(&s));
    const uint8_t b[11] = { 0x00, 0x00, 0xFF, 0xFF, 0x01, 0x00, 0xA8, 0xFF, 0xF1, 0x00, 0x07 };   /* left -1 (s16), cadence -88, error 7 */
    CHECK(bc_xds_decode(b, 11, &s) && s.left_w == -1 && s.cadence_signed_rpm == -88 && bc_xds_cadence_rpm(&s) == 88 && bc_xds_backwards(&s) && s.error == 7);
    const uint8_t c[11] = { 0xB9, 0x0B, 0, 0, 0, 0, 0, 0, 0x68, 0x01, 0 };   /* 3001 W, angle 360: both implausible like the Kotlin rule */
    CHECK(bc_xds_decode(c, 11, &s) && !bc_xds_plausible(&s));
    const uint8_t d[11] = { 0xB8, 0x0B, 0, 0, 0, 0, 0xFA, 0x00, 0x67, 0x01, 0 };   /* 3000 W, 250 rpm, 359 deg: the limits are accepted */
    CHECK(bc_xds_decode(d, 11, &s) && bc_xds_plausible(&s));
    const uint8_t e[11] = { 0, 0, 0, 0, 0, 0, 0xFB, 0x00, 0, 0, 0 };   /* 251 rpm rejected */
    CHECK(bc_xds_decode(e, 11, &s) && !bc_xds_plausible(&s));
    CHECK(!bc_xds_decode(a, 10, &s));                                   /* short = null in Kotlin */
}

static void test_cp(void)
{
    bc_xds_live_t l; bc_xds_live_reset(&l); bc_cp_cad_t c; bc_cp_cad_reset(&c);
    int w, rpm; bool back;
    /* power only (flags 0): cadence is NO DATA, never guessed */
    const uint8_t p0[4] = { 0x00, 0x00, 0x96, 0x00 };
    CHECK(bc_cp_live_feed(&l, &c, p0, 4, 1000));
    CHECK(bc_xds_live_power(&l, 1000, &w) == BC_LIVE_OK && w == 150);
    CHECK(bc_xds_live_cadence(&l, 1000, &rpm, &back) == BC_LIVE_NO_DATA);
    /* crank data (flags 0x20): 10 revs @ t=0, 11 revs @ 768/1024 s -> 80 rpm */
    bc_xds_live_reset(&l); bc_cp_cad_reset(&c);
    uint8_t k1[8] = { 0x20, 0x00, 0xC8, 0x00, 10, 0, 0x00, 0x00 }, k2[8] = { 0x20, 0x00, 0xD2, 0x00, 11, 0, 0x00, 0x03 };
    CHECK(bc_cp_live_feed(&l, &c, k1, 8, 1000));
    CHECK(bc_xds_live_cadence(&l, 1000, &rpm, &back) == BC_LIVE_NO_DATA);   /* one event: not yet a rate */
    CHECK(bc_cp_live_feed(&l, &c, k2, 8, 1750));
    CHECK(bc_xds_live_power(&l, 1750, &w) == BC_LIVE_OK && w == 210);
    CHECK(bc_xds_live_cadence(&l, 1750, &rpm, &back) == BC_LIVE_OK && rpm == 80 && !back);
    /* same crank event repeated: keeps 80 for up to 3 s, then 0 (coasting) */
    CHECK(bc_cp_live_feed(&l, &c, k2, 8, 2750) && bc_xds_live_cadence(&l, 2750, &rpm, &back) == BC_LIVE_OK && rpm == 80);
    CHECK(bc_cp_live_feed(&l, &c, k2, 8, 5000) && bc_xds_live_cadence(&l, 5000, &rpm, &back) == BC_LIVE_OK && rpm == 0);
    /* all optional fields before the crank data: balance (1) + torque (2) + wheel (6) */
    uint8_t full[17] = { 0x35, 0x00, 0x2C, 0x01, 0x64, 0x34, 0x12, 1, 0, 0, 0, 0x10, 0x00, 20, 0, 0x00, 0x04 };
    bc_cp_meas_t m; CHECK(bc_cp_decode(full, 17, &m) && m.power_w == 300 && m.crank_ok && m.crank_revs == 20 && m.crank_t == 0x0400);
    CHECK(!bc_cp_decode(full, 16, &m));                                   /* crank flagged but missing */
    CHECK(!bc_cp_decode(p0, 3, &m));
    /* negative / huge power rejected and counted */
    bc_xds_live_reset(&l); bc_cp_cad_reset(&c);
    const uint8_t neg[4] = { 0, 0, 0xF6, 0xFF }, huge[4] = { 0, 0, 0xB9, 0x0B };
    CHECK(!bc_cp_live_feed(&l, &c, neg, 4, 100) && !bc_cp_live_feed(&l, &c, huge, 4, 200) && !bc_cp_live_feed(&l, &c, neg, 2, 300));
    CHECK(l.packets == 3 && l.rejected == 2 && l.short_packets == 1 && !l.have);
}

static void test_stages(void)
{
    bc_pipe_t p; bc_pipe_init(&p);
    CHECK(p.stage == BC_STG_NOT_PAIRED && !strcmp(bc_stage_name(BC_STG_VALID), "VALID") && !strcmp(bc_stage_name(BC_STG_NOT_PAIRED), "NOT PAIRED"));
    uint32_t t = 1000;
    bc_pipe_set_link(&p, BC_STG_SEARCHING, t); CHECK(p.stage == BC_STG_SEARCHING && bc_pipe_take_change(&p) && !bc_pipe_take_change(&p));
    bc_pipe_set_link(&p, BC_STG_CONNECTING, t += 500); bc_pipe_connected(&p, t += 300); CHECK(p.stage == BC_STG_CONNECTED);
    CHECK(bc_pipe_tick(&p, t) == BC_PIPE_NONE && p.stage == BC_STG_CONNECTED);   /* not subscribed: tick does nothing */
    bc_pipe_subscribed(&p, 0x0023, 0x0001, t += 200); CHECK(p.stage == BC_STG_SUBSCRIBED && p.cccd == 0x0023 && p.cccd_readback == 1);
    CHECK(bc_pipe_packet_age(&p, t) == UINT32_MAX && bc_pipe_valid_age(&p, t) == UINT32_MAX);
    const uint8_t pk[11] = { 0x8E, 0, 0, 0, 0, 0, 0x52, 0, 0x10, 0x01, 0 };
    bc_pipe_packet(&p, pk, 11, true, t += 1000);
    CHECK(bc_pipe_tick(&p, t) == BC_PIPE_NONE && p.stage == BC_STG_VALID && p.packets == 1);
    CHECK(bc_pipe_tick(&p, t + 3000) == BC_PIPE_NONE && p.stage == BC_STG_VALID);   /* exactly 3 s: still valid */
    CHECK(bc_pipe_tick(&p, t + 3001) == BC_PIPE_NONE && p.stage == BC_STG_STALE);
    bc_pipe_packet(&p, pk, 11, true, t + 3500); CHECK(bc_pipe_tick(&p, t + 3500) == BC_PIPE_NONE && p.stage == BC_STG_VALID);
    /* error, then SEARCHING keeps showing ERROR until the next CONNECTING */
    bc_pipe_error(&p, "CCCD write failed", t + 4000); CHECK(p.stage == BC_STG_ERROR && !strcmp(p.err, "CCCD write failed"));
    bc_pipe_set_link(&p, BC_STG_SEARCHING, t + 5000); CHECK(p.stage == BC_STG_ERROR);
    bc_pipe_set_link(&p, BC_STG_CONNECTING, t + 6000); CHECK(p.stage == BC_STG_CONNECTING && p.packets == 0 && !strcmp(p.err, "CCCD write failed"));
    bc_pipe_connected(&p, t + 6500); bc_pipe_subscribed(&p, 0x23, 1, t + 6600);
    bc_pipe_packet(&p, pk, 11, true, t + 7000); bc_pipe_tick(&p, t + 7000); CHECK(p.stage == BC_STG_VALID && p.err[0] == 0);   /* data clears the error */
    /* receiving but not valid */
    bc_pipe_connected(&p, 50000); bc_pipe_subscribed(&p, 0x23, 1, 50000); bc_pipe_packet(&p, pk, 3, false, 50500);
    CHECK(bc_pipe_tick(&p, 50500) == BC_PIPE_NONE && p.stage == BC_STG_RECEIVING && p.rejected == 1);
    bc_pipe_set_link(&p, BC_STG_NOT_PAIRED, 60000); CHECK(p.stage == BC_STG_NOT_PAIRED && p.packets == 0 && p.err[0] == 0);
}

static void test_recovery(void)
{
    bc_pipe_t p; bc_pipe_init(&p);
    const uint8_t pk[11] = { 0x8E, 0, 0, 0, 0, 0, 0x52, 0, 0x10, 0x01, 0 };
    /* 1. subscribed, nothing arrives: resubscribe at 8 s (once), reconnect at 15 s (once) */
    bc_pipe_set_link(&p, BC_STG_CONNECTING, 0); bc_pipe_connected(&p, 100); bc_pipe_subscribed(&p, 0x23, 1, 1000);
    int resub = 0, recon = 0;
    for (uint32_t t = 1000; t <= 30000; t += 100) {   /* the manager ticks every 500 ms on the device; 100 ms here is stricter */
        bc_pipe_act_t a = bc_pipe_tick(&p, t);
        if (a == BC_PIPE_RESUBSCRIBE) { resub++; CHECK(t == 9000); bc_pipe_subscribed(&p, 0x23, 1, t + 300); }   /* the re-subscribe does not restart the clock */
        if (a == BC_PIPE_RECONNECT) { recon++; CHECK(t == 16000); }
    }
    CHECK(resub == 1 && recon == 1 && !strcmp(p.err, "no data") && p.stage == BC_STG_SUBSCRIBED);
    /* the reconnect happens: new connection, fresh episode */
    bc_pipe_set_link(&p, BC_STG_SEARCHING, 31000); bc_pipe_set_link(&p, BC_STG_CONNECTING, 32000); bc_pipe_connected(&p, 32300);
    CHECK(!p.reconnect_pending && !p.resub_done && p.reconnects == 1 && p.resubscribes == 1);

    /* 2. packets arrive but every one is rejected: hex dump once at 10 s, "unreadable data", no reconnect loop */
    bc_pipe_subscribed(&p, 0x23, 1, 33000);
    int dumps = 0; recon = 0;
    for (uint32_t t = 33000; t <= 60000; t += 100) {
        if (t % 1000 == 0) bc_pipe_packet(&p, pk, (size_t)(4 + (t / 1000) % 3), false, t);
        bc_pipe_act_t a = bc_pipe_tick(&p, t);
        if (a == BC_PIPE_DUMP_HEX) { dumps++; CHECK(t == 43000);   /* 10 s after the first packet */ }
        if (a == BC_PIPE_RECONNECT) recon++;
    }
    CHECK(dumps == 1 && recon == 0 && p.unreadable && !strcmp(p.err, "unreadable data") && p.stage == BC_STG_RECEIVING && p.nhex == 3);
    char h[80]; bc_pipe_hex(&p, 0, h, sizeof h); CHECK(!strcmp(h, "8E 00 00 00"));   /* the first three packets: 4, 5, 6 bytes */
    bc_pipe_hex(&p, 1, h, sizeof h); CHECK(!strcmp(h, "8E 00 00 00 00"));
    bc_pipe_hex(&p, 2, h, sizeof h); CHECK(!strcmp(h, "8E 00 00 00 00 00"));
    bc_pipe_hex(&p, 3, h, sizeof h); CHECK(h[0] == 0);
    bc_pipe_packet(&p, pk, 11, true, 60100); bc_pipe_tick(&p, 60100); CHECK(!p.unreadable && p.stage == BC_STG_VALID && p.err[0] == 0);

    /* 3. valid, then the packets stop: STALE after 3 s, resubscribe after 10 s, reconnect after 25 s */
    resub = recon = 0;
    for (uint32_t t = 60100; t <= 100000; t += 100) {
        bc_pipe_act_t a = bc_pipe_tick(&p, t);
        if (t == 63200) CHECK(p.stage == BC_STG_STALE);
        if (a == BC_PIPE_RESUBSCRIBE) { resub++; CHECK(t == 70200); }
        if (a == BC_PIPE_RECONNECT) { recon++; CHECK(t == 85200); }
    }
    CHECK(resub == 1 && recon == 1 && !strcmp(p.err, "data stopped"));
    /* 4. stale, and every resubscribe brings the data back: the stale budget is re-armed each time, never a reconnect */
    bc_pipe_connected(&p, 100000); bc_pipe_subscribed(&p, 0x23, 1, 100000); bc_pipe_packet(&p, pk, 11, true, 100500);
    resub = recon = 0; bool deliver = false;
    for (uint32_t t = 100500; t <= 140000; t += 100) {
        if (deliver) { bc_pipe_packet(&p, pk, 11, true, t); deliver = false; }
        bc_pipe_act_t a = bc_pipe_tick(&p, t);
        if (a == BC_PIPE_RESUBSCRIBE) { resub++; deliver = true; }
        if (a == BC_PIPE_RECONNECT) recon++;
    }
    CHECK(resub == 3 && recon == 0 && p.resubscribes >= 3);
}

static void hexs(const uint8_t *b, size_t n, char *out)
{
    static const char D[] = "0123456789ABCDEF"; size_t o = 0;
    for (size_t i = 0; i < n; i++) { if (i) out[o++] = ' '; out[o++] = D[b[i] >> 4]; out[o++] = D[b[i] & 15]; }
    out[o] = 0;
}

/* SENSOR_DIAG wire vectors (published in docs/BLE_LINK_PROTOCOL.md; the iOS decoder compares against the same bytes) */
static void test_sensor_diag(void)
{
    uint8_t b[BC_LINK_MAX]; char h[600]; size_t n; bc_sensor_diag_t v, d;
    CHECK(bc_link_age_ds(UINT32_MAX) == 0xFFFF && bc_link_age_ds(400) == 4 && bc_link_age_ds(99) == 0 && bc_link_age_ds(0xFFFFFFF0u) == 0xFFFE);
    /* V1 power VALID: 142 packets, 0 rejected, last packet / valid 0.4 s ago, no error */
    memset(&v, 0, sizeof v); v.sensor = 1; v.stage = BC_STG_VALID; v.packets = 142; v.pkt_age_ds = 4; v.valid_age_ds = 4;
    n = bc_link_encode_sensor_diag(&v, b, sizeof b, 5, 100000); hexs(b, n, h);
    printf("SENSOR_DIAG V1 %s\n", h);
    CHECK(!strcmp(h, "40 00 05 00 A0 86 01 00 01 01 21 02 01 01 03 01 06 04 04 8E 00 00 00 05 02 00 00 06 02 04 00 07 02 04 00"));
    CHECK(bc_link_decode_sensor_diag(b, n, &d) && d.sensor == 1 && d.stage == 6 && d.packets == 142 && d.rejected == 0 && d.pkt_age_ds == 4 && d.valid_age_ds == 4 && d.err[0] == 0);
    /* V2 power SUBSCRIBED, nothing received yet */
    memset(&v, 0, sizeof v); v.sensor = 1; v.stage = BC_STG_SUBSCRIBED; v.pkt_age_ds = v.valid_age_ds = 0xFFFF;
    n = bc_link_encode_sensor_diag(&v, b, sizeof b, 6, 100000); hexs(b, n, h);
    printf("SENSOR_DIAG V2 %s\n", h);
    CHECK(!strcmp(h, "40 00 06 00 A0 86 01 00 01 01 21 02 01 01 03 01 04 04 04 00 00 00 00 05 02 00 00 06 02 FF FF 07 02 FF FF"));
    /* V3 power ERROR "no CCCD" */
    snprintf(v.err, sizeof v.err, "no CCCD"); v.stage = BC_STG_ERROR;
    n = bc_link_encode_sensor_diag(&v, b, sizeof b, 7, 100000); hexs(b, n, h);
    printf("SENSOR_DIAG V3 %s\n", h);
    CHECK(!strcmp(h, "40 00 07 00 A0 86 01 00 01 01 21 02 01 01 03 01 08 04 04 00 00 00 00 05 02 00 00 06 02 FF FF 07 02 FF FF 08 07 6E 6F 20 43 43 43 44"));
    CHECK(bc_link_decode_sensor_diag(b, n, &d) && d.stage == 8 && !strcmp(d.err, "no CCCD") && d.pkt_age_ds == 0xFFFF);
    /* V4 HR strap RECEIVING, all 12 packets rejected, "unreadable data" */
    memset(&v, 0, sizeof v); v.sensor = 2; v.stage = BC_STG_RECEIVING; v.packets = 12; v.rejected = 12; v.pkt_age_ds = 8; v.valid_age_ds = 0xFFFF; snprintf(v.err, sizeof v.err, "unreadable data");
    n = bc_link_encode_sensor_diag(&v, b, sizeof b, 8, 100000); hexs(b, n, h);
    printf("SENSOR_DIAG V4 %s\n", h);
    CHECK(!strcmp(h, "40 00 08 00 A0 86 01 00 01 01 21 02 01 02 03 01 05 04 04 0C 00 00 00 05 02 0C 00 06 02 08 00 07 02 FF FF 08 0F 75 6E 72 65 61 64 61 62 6C 65 20 64 61 74 61"));
    /* V5 CSC STALE: 300 packets, 2 rejected, 5.2 s since the last packet and the last valid one */
    memset(&v, 0, sizeof v); v.sensor = 3; v.stage = BC_STG_STALE; v.packets = 300; v.rejected = 2; v.pkt_age_ds = 52; v.valid_age_ds = 52;
    n = bc_link_encode_sensor_diag(&v, b, sizeof b, 9, 100000); hexs(b, n, h);
    printf("SENSOR_DIAG V5 %s\n", h);
    CHECK(!strcmp(h, "40 00 09 00 A0 86 01 00 01 01 21 02 01 03 03 01 07 04 04 2C 01 00 00 05 02 02 00 06 02 34 00 07 02 34 00"));
    /* a 20-byte error (the maximum) is kept whole */
    memset(&v, 0, sizeof v); v.sensor = 1; memcpy(v.err, "abcdefghijklmnopqrst", 20); v.err[20] = 0;
    n = bc_link_encode_sensor_diag(&v, b, sizeof b, 1, 0); CHECK(bc_link_decode_sensor_diag(b, n, &d) && strlen(d.err) == 20);
    /* not a sensor diag: a LINK_DIAG event, and a LIVE message */
    bc_event_t e = { .event_id = BC_EVT_LINK_DIAG }; n = bc_link_encode_event(&e, b, sizeof b, 1, 0); CHECK(!bc_link_decode_sensor_diag(b, n, &d));
    bc_live_t L; memset(&L, 0, sizeof L); n = bc_link_encode_live(&L, b, sizeof b, 1, 0); CHECK(!bc_link_decode_sensor_diag(b, n, &d));
    /* unknown tags are skipped (forward compatible) */
    memset(&v, 0, sizeof v); v.sensor = 2; v.stage = 6; n = bc_link_encode_sensor_diag(&v, b, sizeof b, 1, 0);
    b[n++] = 0x30; b[n++] = 1; b[n++] = 0x99;
    CHECK(bc_link_decode_sensor_diag(b, n, &d) && d.sensor == 2 && d.stage == 6);
}

int main(void)
{
    test_cccd_choice();
    test_xds_reverify();
    test_cp();
    test_stages();
    test_recovery();
    test_sensor_diag();
    printf("%s: %d checks, %d failures\n", fails ? "FAILED" : "OK", checks, fails);
    return fails ? 1 : 0;
}
