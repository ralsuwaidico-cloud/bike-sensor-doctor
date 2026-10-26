/*
 * Fake GATT power meter for the PC harness (firmware 0.7.2). It plays a meter with a real attribute table and drives the
 * SAME portable decisions the NimBLE central uses (bc_gatt: characteristic range + CCCD choice, bc_pipe: stages and
 * recovery, bc_xds: decoding), in the same order as main/ble_central.c: connect -> discover -> pick CCCD -> write ->
 * read back -> notifications only on the handle whose CCCD was enabled. With legacy_pick the 0.7.1 CCCD search is used,
 * which reproduces "connected, no power".
 *
 * What this proves: the decision logic and the recovery timers. What it cannot prove: NimBLE's own callbacks, timing
 * and the real meter's GATT table — those need the hardware test (docs/FIRMWARE_0.7.2.md).
 */
#include "sim.h"
#include "bc_gatt.h"
#include "bc_pipe.h"
#include "bc_xds.h"
#include <stdio.h>
#include <string.h>

typedef struct { uint16_t handle, uuid; uint8_t props; } fa_t;
/* variant 0: XDS-A001 table (docs/PORTING_SPEC.md §2): 2A63 N, 2A65 R, 2A5D R, 2A55 W+I (own CCCD) */
static const fa_t DB_XDS[] = {
    { 0x0020, 0x2800, 0 }, { 0x0021, 0x2803, 0x10 }, { 0x0022, 0x2A63, 0 }, { 0x0023, 0x2902, 0 },
    { 0x0024, 0x2803, 0x02 }, { 0x0025, 0x2A65, 0 }, { 0x0026, 0x2803, 0x02 }, { 0x0027, 0x2A5D, 0 },
    { 0x0028, 0x2803, 0x28 }, { 0x0029, 0x2A55, 0 }, { 0x002A, 0x2902, 0 },
};
/* variant 1: Mesh-Proxy order: 2A63 then 2ADD (write) and 2ADE (notify, own CCCD) */
static const fa_t DB_MESH[] = {
    { 0x0010, 0x2800, 0 }, { 0x0011, 0x2803, 0x10 }, { 0x0012, 0x2A63, 0 }, { 0x0013, 0x2902, 0 },
    { 0x0014, 0x2803, 0x0C }, { 0x0015, 0x2ADD, 0 }, { 0x0016, 0x2803, 0x10 }, { 0x0017, 0x2ADE, 0 }, { 0x0018, 0x2902, 0 },
};

#define F g_sim.fake
static const fa_t *db(int *n, uint16_t *svc_end)
{
    if (F.variant == 1) { *n = (int)(sizeof DB_MESH / sizeof *DB_MESH); *svc_end = 0x0018; return DB_MESH; }
    *n = (int)(sizeof DB_XDS / sizeof *DB_XDS); *svc_end = 0x002A; return DB_XDS;
}
static uint16_t data_cccd(void) { return F.variant == 1 ? 0x0013 : 0x0023; }   /* the meter only streams when THIS is enabled */
static uint16_t data_val(void) { return F.variant == 1 ? 0x0012 : 0x0022; }

static void flog(const char *fmt, const char *a, unsigned x, unsigned y)
{
    char b[96]; snprintf(b, sizeof b, fmt, a, x, y);
    snprintf(F.log[F.nlog % 8], sizeof F.log[0], "%s", b); F.nlog++;
    if (g_sim.verbose) printf("  [pipe] %s\n", b);
}

static void note_change(void)
{
    if (!bc_pipe_take_change(&F.pipe)) return;
    char b[96];
    if (F.pipe.stage == BC_STG_SUBSCRIBED) snprintf(b, sizeof b, "power -> SUBSCRIBED (cccd 0x%04X read back %02X %02X)", F.pipe.cccd, F.pipe.cccd_readback & 0xFF, F.pipe.cccd_readback >> 8);
    else if (F.pipe.stage == BC_STG_VALID) { int w = 0; bc_xds_live_power(&F.xds, g_sim.now_ms, &w); snprintf(b, sizeof b, "power -> VALID %d W", w); }
    else snprintf(b, sizeof b, "power -> %s %s", bc_stage_name(F.pipe.stage), F.pipe.err);
    flog("%s", b, 0, 0);
}

/* discovery + CCCD choice + write + read back, exactly as ble_central.c (synchronous here) */
static void subscribe(void)
{
    int n; uint16_t svc_end; const fa_t *d = db(&n, &svc_end);
    bc_gatt_chr_t ch[16]; int nch = 0;
    for (int i = 0; i < n; i++) if (d[i].uuid == 0x2803 && i + 1 < n && nch < 16) { ch[nch].def_handle = d[i].handle; ch[nch].val_handle = d[i + 1].handle; ch[nch].uuid16 = d[i + 1].uuid; ch[nch].props = d[i].props; nch++; }
    int i = bc_gatt_find_chr(ch, nch, 0x2A63);
    if (i < 0) { bc_pipe_error(&F.pipe, "no 0x2A63", g_sim.now_ms); return; }
    uint16_t val = ch[i].val_handle;
    uint16_t end = F.legacy_pick ? svc_end : bc_gatt_chr_end(ch, nch, i, svc_end);   /* 0.7.1 searched to the service end */
    bc_gatt_attr_t a[16]; int na = 0;
    for (int k = 0; k < n; k++) if (d[k].handle > val && d[k].handle <= end && na < 16) { a[na].handle = d[k].handle; a[na].uuid16 = d[k].uuid; na++; }
    uint16_t cccd = 0;
    if (F.legacy_pick) { for (int k = 0; k < na; k++) if (a[k].uuid16 == 0x2902) cccd = a[k].handle; }   /* last one wins (the bug) */
    else cccd = bc_gatt_pick_cccd(a, na, val, end);
    F.discoveries++;
    if (!cccd) { bc_pipe_error(&F.pipe, "no CCCD", g_sim.now_ms); return; }
    uint16_t v = bc_gatt_cccd_value(ch[i].props);
    F.enabled[cccd & 0x3F] = v;  F.cccd_writes++; F.last_cccd = cccd;               /* the ONLY write */
    F.stall = false;                                                                 /* a fresh subscription restarts a stalled stream */
    if (cccd != data_cccd()) F.wrong_writes++;
    uint16_t rb = F.enabled[cccd & 0x3F];                                            /* read back */
    bc_pipe_subscribed(&F.pipe, cccd, rb, g_sim.now_ms);
    F.val = val;
    g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_CONNECTED;
}

void sim_fake_meter(bool on, int variant, bool legacy_pick)
{
    memset(&F, 0, sizeof F);
    F.on = on; F.variant = variant; F.legacy_pick = legacy_pick; F.streaming = true; F.in_range = true; F.watts = 142; F.rpm = 82; F.backoff_s = 1;
    bc_pipe_init(&F.pipe); bc_xds_live_reset(&F.xds);
    if (on) { F.paired = true; F.state = 1; bc_pipe_set_link(&F.pipe, BC_STG_SEARCHING, g_sim.now_ms); g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_SEARCHING; }
}

static void disconnect(void)
{
    memset(F.enabled, 0, sizeof F.enabled);
    F.state = 1; F.retry_at = g_sim.now_ms + (uint32_t)F.backoff_s * 1000; F.backoff_s = F.backoff_s >= 16 ? 16 : F.backoff_s * 2;
    F.disconnects++;
    bc_pipe_set_link(&F.pipe, BC_STG_SEARCHING, g_sim.now_ms);
    g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_RETRY;
}

/* called every 100 ms of simulated time */
void sim_fake_pump(void)
{
    if (!F.on || !F.paired) return;
    uint32_t now = g_sim.now_ms;
    switch (F.state) {
    case 1:   /* searching / waiting for the back-off */
        if ((int32_t)(now - F.retry_at) < 0 || !F.in_range) break;
        F.state = 2; F.t = now; bc_pipe_set_link(&F.pipe, BC_STG_CONNECTING, now); g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_CONNECTING; break;
    case 2:   /* connecting */
        if (now - F.t < 400) break;
        F.state = 3; F.connects++; bc_xds_live_reset(&F.xds); bc_pipe_connected(&F.pipe, now); F.next_pkt = now + 1000;
        subscribe();
        if (F.pipe.stage == BC_STG_ERROR) disconnect();
        break;
    case 3: { /* connected: the meter notifies 0x2A63 at 1 Hz only when ITS CCCD is enabled */
        if ((int32_t)(now - F.next_pkt) >= 0) {
            F.next_pkt = now + 1000;
            if (F.streaming && !F.stall && F.enabled[data_cccd() & 0x3F] == 1) {
                uint8_t p[11] = { (uint8_t)F.watts, (uint8_t)(F.watts >> 8), 0, 0, 0, 0, (uint8_t)F.rpm, (uint8_t)(F.rpm >> 8), (uint8_t)(F.angle & 0xFF), (uint8_t)(F.angle >> 8), 0 };
                F.angle = (uint16_t)((F.angle + 97) % 360);
                size_t n = F.garbage ? 5 : 11;
                if (data_val() == F.val) {
                    bool ok = bc_xds_live_feed(&F.xds, p, n, now);
                    bc_pipe_packet(&F.pipe, p, n, ok, now);
                    if (ok) F.backoff_s = 1;
                }
                F.packets_sent++;
            }
            if (F.enabled[0x18 & 0x3F] || F.enabled[0x2A & 0x3F]) F.other_notifies++;   /* the wrongly enabled characteristic */
        }
        bc_pipe_act_t a = bc_pipe_tick(&F.pipe, now);
        note_change();
        if (a == BC_PIPE_RESUBSCRIBE) { F.resubs++; flog("power: %s - discovering and subscribing again", F.pipe.have_valid ? "data stale > 10 s" : "no packet in 8 s", 0, 0); subscribe(); }
        else if (a == BC_PIPE_RECONNECT) { F.reconnects++; flog("power: %s - reconnecting", F.pipe.err, 0, 0); disconnect(); }
        else if (a == BC_PIPE_DUMP_HEX) { char h[64]; bc_pipe_hex(&F.pipe, 0, h, sizeof h); F.dumps++; flog("power: unreadable data [1] %s", h, 0, 0); }
        if (!F.in_range) { flog("power: %s", "link lost", 0, 0); disconnect(); }
        break; }
    }
    note_change();
}

/* plat_sensors() for the POWER link while the fake meter is on (same rules as ble_central_snapshot) */
void sim_fake_snapshot(plat_sensors_t *o)
{
    uint32_t now = g_sim.now_ms;
    plat_link_info_t *li = &o->link[PLAT_SENS_POWER];
    int w, r; bool bk = false;
    bool on = F.state == 3 && F.pipe.stage >= BC_STG_SUBSCRIBED;
    o->power_ok = on && bc_xds_live_power(&F.xds, now, &w) == BC_LIVE_OK; o->watts = o->power_ok ? w : 0;
    o->cad_ok = on && bc_xds_live_cadence(&F.xds, now, &r, &bk) == BC_LIVE_OK; o->rpm = o->cad_ok ? r : 0; o->backwards = bk;
    li->link = g_sim.link[PLAT_SENS_POWER].link;
    snprintf(li->name, sizeof li->name, "XDS-A001-9769");
    li->rssi = -61;
    li->packets = F.pipe.packets; li->rejected = F.pipe.rejected;
    li->age_ms = bc_pipe_packet_age(&F.pipe, now); li->valid_age_ms = bc_pipe_valid_age(&F.pipe, now);
    li->reconnects = F.disconnects;
    li->stage = (uint8_t)F.pipe.stage; li->stage_age_ms = now - F.pipe.stage_ms;
    snprintf(li->err, sizeof li->err, "%s", F.pipe.err); li->unreadable = F.pipe.unreadable;
    li->svc_uuid = 0x1828; li->cccd = F.pipe.cccd; li->data_handle = F.val;
    li->resubscribes = F.pipe.resubscribes; li->auto_reconnects = F.pipe.reconnects;
}
#undef F
