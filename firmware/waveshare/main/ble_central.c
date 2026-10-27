/*
 * NimBLE central: paired power meter + optional HR strap + optional CSC sensor + pairing scan. See ble_central.h for the
 * safety rules. Sequence per link (0.7.2): connect → MTU exchange (≤ 2 s) → discover services → pick the service
 * (power: 0x1828 for XDS-named meters, else 0x1818; bc_gatt_power_services) → discover its characteristics → the data
 * characteristic's OWN descriptor range (up to the next characteristic declaration) → its CCCD (bc_gatt_pick_cccd) →
 * write 01 00 (02 00 if it only indicates) → read the CCCD back → decode notifications on the data handle with bc_core.
 *
 * 0.7.2 root cause fixed here: up to 0.7.1 on_dsc() searched descriptors from the 0x2A63 value handle to the END OF THE
 * SERVICE and kept the LAST 0x2902, i.e. the CCCD of a later characteristic (on the XDS: the 0x2A55 control point). The
 * board reported "connected" and never received a power packet. Every stage is now tracked by bc_pipe (serial tag "pipe").
 *
 * 0.7.3 (docs/CRASH_0.7.2.md): ONE task owns the links. In 0.7.2 the manager task ran tick() — and with it the automatic
 * re-subscribe (disc_begin), reconnect (ble_gap_terminate) and the stuck-connect handling — in parallel with the NimBLE host
 * task's GATT/GAP callbacks that change the same link_t fields, and the MTU fallback timer started discovery from the
 * esp_timer task while the MTU answer could start it on the host task (double discovery). Now the manager task and the
 * timer only post NimBLE events; tick(), ble_link_tick(), the MTU fallback and pairing changes all run on the host task.
 * GATT callbacks carry the link slot + a discovery generation in `arg`, so an answer to an older discovery (one that was
 * replaced by a re-subscribe, or belongs to a previous connection) is ignored instead of being applied to the new one; a
 * re-subscribe is never started while a discovery/subscription is still in flight.
 */
#include "ble_central.h"
#include <string.h>
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_heap_caps.h"
#include <stdio.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "services/gap/ble_svc_gap.h"
#include "bc_xds.h"
#include "bc_hr.h"
#include "bc_csc.h"
#include "bc_cp.h"
#include "bc_gatt.h"
#include "bc_pipe.h"
#include "hw.h"
#include "ble_link.h"
void ble_store_config_init(void);

static const char *TAG = "ble";
static portMUX_TYPE s_mux = portMUX_INITIALIZER_UNLOCKED;
#define LOCK() portENTER_CRITICAL(&s_mux)
#define UNLOCK() portEXIT_CRITICAL(&s_mux)

#define NSV 12
#define NCH 16
#define NDS 16
typedef struct {
    int kind;
    uint16_t chr_uuid; uint16_t cand[2]; int ncand;  /* data characteristic + the services to look in, in order */
    bool paired, disabled; ble_addr_t addr; char name[20];
    plat_link_t state;
    uint16_t conn, svc_s, svc_e, svc_uuid, val, cccd, chr_end, cccd_val; bool disc_started;
    uint8_t dgen;                                    /* 0.7.3 discovery generation: callbacks of older ones are ignored */
    bool busy; uint32_t busy_since;                  /* 0.7.3 a discovery / CCCD write / read-back is in flight (since) */
    struct { uint16_t s, e, uuid; } sv[NSV]; int nsv, svc_try; bool svc_seen;
    bc_gatt_chr_t ch[NCH]; int nch;
    bc_gatt_attr_t ds[NDS]; int nds;
    bc_pfmt_t fmt;                                   /* power: XDS 11-byte packet or standard Cycling Power */
    int8_t rssi; uint32_t reconnects, connects, gaps; int backoff_s; uint32_t retry_at;
    uint32_t state_since;
    uint32_t other_notifies; bool other_logged, valid_seen;
    bc_pipe_t pipe;
    bc_xds_live_t xds; bc_cp_cad_t cp; bc_hr_live_t hr; bc_csc_live_t csc;
} link_t;

/* 0.6.0: three links. Index = slot, not plat kind (CSC is kind 3, slot 2). */
#define NL 3
static link_t L[NL] = {
    { .kind = PLAT_SENS_POWER, .chr_uuid = 0x2A63, .cand = { 0x1828, 0x1818 }, .ncand = 2, .conn = BLE_HS_CONN_HANDLE_NONE, .backoff_s = 1 },
    { .kind = PLAT_SENS_HR, .chr_uuid = 0x2A37, .cand = { 0x180D }, .ncand = 1, .conn = BLE_HS_CONN_HANDLE_NONE, .backoff_s = 1 },
    { .kind = PLAT_SENS_CSC, .chr_uuid = 0x2A5B, .cand = { 0x1816 }, .ncand = 1, .conn = BLE_HS_CONN_HANDLE_NONE, .backoff_s = 1 },
};
static int slot_of(int kind) { return kind == PLAT_SENS_POWER ? 0 : kind == PLAT_SENS_HR ? 1 : kind == PLAT_SENS_CSC ? 2 : -1; }
static const char *kind_name(int kind) { return kind == PLAT_SENS_POWER ? "power" : kind == PLAT_SENS_HR ? "hr" : "csc"; }
static volatile uint16_t s_wheel_mm = 2096;
/* Connections > Other Bluetooth: every advertiser, with the services it announces */
#define NANY 12
static plat_found_t s_any[NANY]; static int s_nany; static uint32_t s_any_ms[NANY];
static uint8_t s_own;
static volatile bool s_synced, s_scanning;
static volatile int s_pair_kind = -1;
static volatile bool s_sensors_on = true;
static link_t *s_connecting;
static plat_found_t s_found[NL][8]; static int s_nfound[NL]; static uint32_t s_found_ms[NL][8];
static uint8_t s_seen[48][6]; static int s_seen_n; static uint32_t s_seen_total;
static esp_timer_handle_t s_mtu_timer;
/* 0.7.3: work handed to the host task */
static struct ble_npl_event s_ev_tick, s_ev_link, s_ev_mtu, s_ev_req;
static volatile bool s_events_ready;
typedef struct { bool pending; bool paired; uint8_t mac[6], addr_type; char name[20]; bool set_disabled, disabled; } pair_req_t;
static pair_req_t s_req[NL];                         /* guarded by LOCK; applied on the host task */

/* GATT callback argument: link slot + discovery generation (never a pointer that could outlive the procedure) */
static void *cb_arg(const link_t *l) { return (void *)(uintptr_t)((unsigned)(l - L) | ((unsigned)l->dgen << 8)); }
static link_t *link_of(uint16_t conn, void *arg)
{
    unsigned v = (unsigned)(uintptr_t)arg, slot = v & 0xFF, gen = (v >> 8) & 0xFF;
    if (slot >= NL) return NULL;
    link_t *l = &L[slot];
    if (l->conn != conn || l->dgen != gen) return NULL;   /* an older discovery or a previous connection: ignore */
    return l;
}

static const char *st_name(plat_link_t s)
{
    switch (s) { case PLAT_LINK_NOT_PAIRED: return "NOT PAIRED"; case PLAT_LINK_SEARCHING: return "SEARCHING"; case PLAT_LINK_CONNECTING: return "CONNECTING";
                 case PLAT_LINK_CONNECTED: return "SUBSCRIBED"; case PLAT_LINK_RETRY: return "RECONNECTING"; default: return "OFF"; }
}

/* ---- pipeline log: one serial line per stage change, tag "pipe" (sensor data and counts only, nothing personal) */
static void pipe_line(link_t *l, char *b, size_t cap)
{
    const bc_pipe_t *p = &l->pipe; uint32_t now = hw_millis();
    int n = snprintf(b, cap, "%s → %s", kind_name(l->kind), bc_stage_name(p->stage));
    if (n < 0 || (size_t)n >= cap) return;
    switch (p->stage) {
    case BC_STG_SUBSCRIBED:
        if (p->cccd_readback == 0xFFFF) snprintf(b + n, cap - (size_t)n, " (cccd 0x%04X written %02X %02X, read back n/a; 0x%04X in 0x%04X)", p->cccd, l->cccd_val & 0xFF, l->cccd_val >> 8, l->chr_uuid, l->svc_uuid);
        else snprintf(b + n, cap - (size_t)n, " (cccd 0x%04X read back %02X %02X; 0x%04X in 0x%04X)", p->cccd, p->cccd_readback & 0xFF, p->cccd_readback >> 8, l->chr_uuid, l->svc_uuid);
        break;
    case BC_STG_VALID: {
        int v = 0, r = 0; bool bk = false;
        if (l->kind == PLAT_SENS_POWER) { bc_xds_live_power(&l->xds, now, &v); bool c = bc_xds_live_cadence(&l->xds, now, &r, &bk) == BC_LIVE_OK;
                                          if (c) snprintf(b + n, cap - (size_t)n, " %d W %d rpm (pkts %lu)", v, r, (unsigned long)p->packets); else snprintf(b + n, cap - (size_t)n, " %d W (pkts %lu)", v, (unsigned long)p->packets); }
        else if (l->kind == PLAT_SENS_HR) { bc_hr_live_bpm(&l->hr, now, &v); snprintf(b + n, cap - (size_t)n, " %d bpm (pkts %lu)", v, (unsigned long)p->packets); }
        else snprintf(b + n, cap - (size_t)n, " (pkts %lu)", (unsigned long)p->packets);
        break; }
    case BC_STG_ERROR: snprintf(b + n, cap - (size_t)n, " %s", p->err); break;
    case BC_STG_RECEIVING: case BC_STG_STALE:
        snprintf(b + n, cap - (size_t)n, " (pkts %lu, rejected %lu%s%s)", (unsigned long)p->packets, (unsigned long)p->rejected, p->err[0] ? ", " : "", p->err); break;
    default: break;
    }
}
static void pipe_log(link_t *l)
{
    char line[128]; bool ch;
    LOCK(); ch = bc_pipe_take_change(&l->pipe); if (ch) pipe_line(l, line, sizeof line); UNLOCK();
    if (ch) ESP_LOGI("pipe", "%s", line);
}

static void set_state(link_t *l, plat_link_t s)
{
    uint32_t now = hw_millis();
    LOCK();
    l->state = s; l->state_since = now;
    switch (s) {
    case PLAT_LINK_NOT_PAIRED: bc_pipe_set_link(&l->pipe, BC_STG_NOT_PAIRED, now); break;
    case PLAT_LINK_SEARCHING: case PLAT_LINK_RETRY: bc_pipe_set_link(&l->pipe, BC_STG_SEARCHING, now); break;   /* keeps ERROR visible */
    case PLAT_LINK_CONNECTING: bc_pipe_set_link(&l->pipe, BC_STG_CONNECTING, now); break;
    default: break;
    }
    UNLOCK();
    ESP_LOGI(TAG, "%s → %s", kind_name(l->kind), st_name(s));
    pipe_log(l);
}

static link_t *by_conn(uint16_t c) { for (int i = 0; i < NL; i++) if (L[i].conn == c) return &L[i]; return NULL; }

static void fail(link_t *l, const char *why)
{
    ESP_LOGW(TAG, "%s: %s", kind_name(l->kind), why);
    l->busy = false; l->dgen++;                      /* every answer still in flight for this link is now stale */
    LOCK(); bc_pipe_error(&l->pipe, why, hw_millis()); UNLOCK();
    pipe_log(l);
    if (l->conn != BLE_HS_CONN_HANDLE_NONE) ble_gap_terminate(l->conn, BLE_ERR_REM_USER_CONN_TERM);
    else {
        if (s_connecting == l) s_connecting = NULL;
        l->retry_at = hw_millis() + (uint32_t)l->backoff_s * 1000;
        l->backoff_s = l->backoff_s >= 16 ? 16 : l->backoff_s * 2;
        set_state(l, l->paired ? PLAT_LINK_RETRY : PLAT_LINK_NOT_PAIRED);
    }
}

/* ---- GATT chain: services → characteristics → the data characteristic's own descriptors → CCCD write → read back */
static uint16_t u16_of(const ble_uuid_t *u) { return u->type == BLE_UUID_TYPE_16 ? ble_uuid_u16(u) : 0; }
static void try_next_service(link_t *l);

static int on_cccd_read(uint16_t conn, const struct ble_gatt_error *err, struct ble_gatt_attr *attr, void *arg)
{
    link_t *l = link_of(conn, arg); if (!l) return 0;
    uint16_t rb = 0xFFFF;
    if (err->status == 0 && attr && attr->om && OS_MBUF_PKTLEN(attr->om) >= 2) { uint8_t v[2]; os_mbuf_copydata(attr->om, 0, 2, v); rb = (uint16_t)(v[0] | (v[1] << 8)); }
    else ESP_LOGW("pipe", "%s: CCCD 0x%04X read back failed (status %d) - written OK, continuing", kind_name(l->kind), l->cccd, err->status);
    if (rb != 0xFFFF && rb != l->cccd_val) {
        char why[21]; snprintf(why, sizeof why, "CCCD reads %02X %02X", rb & 0xFF, rb >> 8);
        fail(l, why);
        return 0;
    }
    l->busy = false;
    if (s_connecting == l) s_connecting = NULL;
    LOCK(); bc_pipe_subscribed(&l->pipe, l->cccd, rb, hw_millis()); UNLOCK();
    set_state(l, PLAT_LINK_CONNECTED);              /* "CONNECTED" = subscribed; the pipeline says whether data flows */
    return 0;
}

static int on_cccd(uint16_t conn, const struct ble_gatt_error *err, struct ble_gatt_attr *attr, void *arg)
{
    link_t *l = link_of(conn, arg); if (!l) return 0;
    if (err->status != 0) { fail(l, "CCCD write failed"); return 0; }
    if (ble_gattc_read(conn, l->cccd, on_cccd_read, cb_arg(l)) != 0) { struct ble_gatt_error e = { .status = BLE_HS_EUNKNOWN }; on_cccd_read(conn, &e, NULL, cb_arg(l)); }
    return 0;
}

static int on_dsc(uint16_t conn, const struct ble_gatt_error *err, uint16_t chr_val, const struct ble_gatt_dsc *dsc, void *arg)
{
    link_t *l = link_of(conn, arg); if (!l) return 0;
    if (err->status == 0 && dsc) { if (l->nds < NDS) { l->ds[l->nds].handle = dsc->handle; l->ds[l->nds].uuid16 = u16_of(&dsc->uuid.u); l->nds++; } return 0; }
    if (err->status != BLE_HS_EDONE) { fail(l, "descriptor discovery"); return 0; }
    l->cccd = bc_gatt_pick_cccd(l->ds, l->nds, l->val, l->chr_end);   /* ONLY this characteristic's CCCD (0.7.2 fix) */
    ESP_LOGI("pipe", "%s: 0x%04X value 0x%04X, descriptors 0x%04X..0x%04X (%d), CCCD 0x%04X", kind_name(l->kind), l->chr_uuid, l->val, l->val + 1, l->chr_end, l->nds, l->cccd);
    if (!l->cccd) { fail(l, "no CCCD"); return 0; }
    uint8_t on[2] = { (uint8_t)(l->cccd_val & 0xFF), (uint8_t)(l->cccd_val >> 8) };   /* 01 00 notify / 02 00 indicate — the ONLY write this firmware sends */
    if (ble_gattc_write_flat(conn, l->cccd, on, sizeof on, on_cccd, cb_arg(l)) != 0) fail(l, "CCCD write failed");
    return 0;
}

static int on_chr(uint16_t conn, const struct ble_gatt_error *err, const struct ble_gatt_chr *chr, void *arg)
{
    link_t *l = link_of(conn, arg); if (!l) return 0;
    if (err->status == 0 && chr) {
        if (l->nch < NCH) { bc_gatt_chr_t *c = &l->ch[l->nch++]; c->def_handle = chr->def_handle; c->val_handle = chr->val_handle; c->props = chr->properties; c->uuid16 = u16_of(&chr->uuid.u); }
        return 0;
    }
    if (err->status != BLE_HS_EDONE) { fail(l, "characteristic discovery"); return 0; }
    int i = bc_gatt_find_chr(l->ch, l->nch, l->chr_uuid);
    if (i < 0) { ESP_LOGW("pipe", "%s: no 0x%04X in service 0x%04X (%d characteristics)", kind_name(l->kind), l->chr_uuid, l->svc_uuid, l->nch); try_next_service(l); return 0; }
    LOCK(); l->val = l->ch[i].val_handle; UNLOCK();   /* the UI snapshot reads it */
    l->chr_end = bc_gatt_chr_end(l->ch, l->nch, i, l->svc_e);
    l->cccd_val = bc_gatt_cccd_value(l->ch[i].props);
    if (l->kind == PLAT_SENS_POWER) l->fmt = bc_gatt_power_format(l->svc_uuid);
    if (!l->cccd_val) { fail(l, "not notifiable"); return 0; }
    if (l->chr_end <= l->val) { fail(l, "no CCCD"); return 0; }
    l->nds = 0;
    if (ble_gattc_disc_all_dscs(conn, l->val, l->chr_end, on_dsc, cb_arg(l)) != 0) fail(l, "descriptor discovery");
    return 0;
}

static void try_next_service(link_t *l)
{
    while (l->svc_try >= 0 && l->svc_try < l->ncand && l->svc_try < 2) {
        uint16_t want = l->cand[l->svc_try++];
        for (int i = 0; i < l->nsv && i < NSV; i++) if (l->sv[i].uuid == want) {
            l->svc_seen = true; l->svc_s = l->sv[i].s; l->svc_e = l->sv[i].e; LOCK(); l->svc_uuid = want; UNLOCK(); l->nch = 0;
            ESP_LOGI("pipe", "%s: service 0x%04X 0x%04X..0x%04X", kind_name(l->kind), want, l->svc_s, l->svc_e);
            if (ble_gattc_disc_all_chrs(l->conn, l->svc_s, l->svc_e, on_chr, cb_arg(l)) != 0) fail(l, "characteristic discovery");
            return;
        }
    }
    char why[21];
    if (l->svc_seen) snprintf(why, sizeof why, "no 0x%04X", l->chr_uuid); else snprintf(why, sizeof why, "no service 0x%04X", l->cand[0]);
    fail(l, why);
}

static int on_svc(uint16_t conn, const struct ble_gatt_error *err, const struct ble_gatt_svc *svc, void *arg)
{
    link_t *l = link_of(conn, arg); if (!l) return 0;
    if (err->status == 0 && svc) { if (l->nsv < NSV) { l->sv[l->nsv].s = svc->start_handle; l->sv[l->nsv].e = svc->end_handle; l->sv[l->nsv].uuid = u16_of(&svc->uuid.u); l->nsv++; } return 0; }
    if (err->status != BLE_HS_EDONE) { fail(l, "service discovery"); return 0; }
    try_next_service(l);
    return 0;
}

/* (re)discovery from scratch on the live connection — also the automatic RESUBSCRIBE of the pipeline. Host task only. */
static void disc_begin(link_t *l)
{
    if (l->conn == BLE_HS_CONN_HANDLE_NONE) return;
    /* val / cccd stay as they are until the new discovery sets them, so a re-subscribe never drops packets in between */
    l->dgen++; l->busy = true; l->busy_since = hw_millis();   /* answers to an older discovery on this link are ignored from now on */
    l->svc_s = l->svc_e = l->chr_end = 0; LOCK(); l->svc_uuid = 0; UNLOCK();
    l->nsv = l->nch = l->nds = 0; l->svc_try = 0; l->svc_seen = false;
    if (l->kind == PLAT_SENS_POWER) l->ncand = bc_gatt_power_services(l->name, l->cand);
    if (ble_gattc_disc_all_svcs(l->conn, on_svc, cb_arg(l)) != 0) fail(l, "service discovery");
}

static void start_discovery(link_t *l)
{
    if (!l || l->disc_started || l->conn == BLE_HS_CONN_HANDLE_NONE) return;
    l->disc_started = true;
    disc_begin(l);
}

static link_t *s_mtu_link; static uint16_t s_mtu_conn = BLE_HS_CONN_HANDLE_NONE;
static int on_mtu(uint16_t conn, const struct ble_gatt_error *err, uint16_t mtu, void *arg)
{
    ESP_LOGI(TAG, "MTU exchange: status %d, mtu %u", err->status, mtu);
    link_t *l = link_of(conn, arg);
    if (l && s_mtu_link == l && s_mtu_timer) esp_timer_stop(s_mtu_timer);
    start_discovery(l);                              /* discovery only after the MTU exchange (PORTING_SPEC §2) */
    return 0;
}
/* esp_timer task: only hands the fallback to the host task */
static void mtu_fallback_timer(void *arg) { (void)arg; if (s_events_ready) ble_npl_eventq_put(nimble_port_get_dflt_eventq(), &s_ev_mtu); }
static void mtu_fallback_ev(struct ble_npl_event *ev)
{
    (void)ev;
    link_t *l = s_mtu_link;
    if (!l || l->disc_started || l->conn == BLE_HS_CONN_HANDLE_NONE || l->conn != s_mtu_conn) return;   /* answered, or a different connection by now */
    ESP_LOGW(TAG, "no MTU response in 2 s — discovering anyway");
    start_discovery(l);
}

/* ---- scanning */
static uint16_t svcs_of(const struct ble_hs_adv_fields *f)
{
    uint16_t m = 0;
    for (int i = 0; i < f->num_uuids16; i++) {
        uint16_t u = ble_uuid_u16(&f->uuids16[i].u);
        if (u == 0x1828 || u == 0x1818) m |= PLAT_SVC_POWER;
        if (u == 0x180D) m |= PLAT_SVC_HR;
        if (u == 0x1816) m |= PLAT_SVC_CSC;
        if (u == 0x180F) m |= PLAT_SVC_BATTERY;
        if (u == 0x1826) m |= PLAT_SVC_FTMS;
    }
    if (f->name && f->name_len >= 3 && memcmp(f->name, "XDS", 3) == 0) m |= PLAT_SVC_POWER;
    return m;
}
static int slot_of_svcs(uint16_t m)
{
    if (m & PLAT_SVC_POWER) return 0;
    if (m & PLAT_SVC_HR) return 1;
    if (m & PLAT_SVC_CSC) return 2;
    return -1;
}
static void note_any(const ble_addr_t *a, const struct ble_hs_adv_fields *f, int rssi, uint16_t svcs)
{
    uint32_t now = hw_millis();
    LOCK();
    int i;
    for (i = 0; i < s_nany; i++) if (!memcmp(s_any[i].mac, a->val, 6)) break;
    if (i == s_nany) {
        if (s_nany < NANY) s_nany++;
        else { int w = 0; for (int j = 1; j < NANY; j++) if (s_any[j].rssi < s_any[w].rssi) w = j; i = w; }   /* replace the weakest */
        memset(&s_any[i], 0, sizeof s_any[i]); memcpy(s_any[i].mac, a->val, 6); s_any[i].addr_type = a->type;
    }
    s_any[i].rssi = rssi; s_any[i].svcs |= svcs;
    if (f->name && f->name_len) { size_t n = f->name_len < 19 ? f->name_len : 19; memcpy(s_any[i].name, f->name, n); s_any[i].name[n] = 0; }
    s_any_ms[i] = now;
    UNLOCK();
}

static volatile bool s_standby;   /* 0.6.0 connected standby */
static int gap_event(struct ble_gap_event *ev, void *arg);

static void scan_start(void)
{
    if (s_scanning || !s_synced || s_connecting) return;
    struct ble_gap_disc_params p = { .itvl = 0x50, .window = 0x30, .filter_duplicates = 0, .passive = 0 };
    int rc = ble_gap_disc(s_own, BLE_HS_FOREVER, &p, gap_event, NULL);
    if (rc == 0 || rc == BLE_HS_EALREADY) s_scanning = true; else ESP_LOGW(TAG, "scan start failed %d", rc);
}
static void scan_stop(void) { if (s_scanning) { ble_gap_disc_cancel(); s_scanning = false; } }

static void connect_to(link_t *l)
{
    scan_stop();
    s_connecting = l;
    l->svc_s = l->svc_e = l->cccd = 0; LOCK(); l->val = 0; UNLOCK(); l->disc_started = false; l->busy = false; l->dgen++;
    l->other_notifies = 0; l->other_logged = false;
    set_state(l, PLAT_LINK_CONNECTING);
    ble_link_central_busy(true);                      /* phone advertising pauses while we initiate (meter first, always) */
    int rc = ble_gap_connect(s_own, &l->addr, 10000, NULL, gap_event, (void *)(uintptr_t)(l - L));
    if (rc != 0) { ESP_LOGW(TAG, "connect start failed %d", rc); s_connecting = NULL; ble_link_central_busy(false); fail(l, "connect failed"); }
}

static void note_found(int kind, const ble_addr_t *a, const struct ble_hs_adv_fields *f, int rssi)
{
    uint32_t now = hw_millis();
    LOCK();
    int i;
    for (i = 0; i < s_nfound[kind]; i++) if (!memcmp(s_found[kind][i].mac, a->val, 6)) break;
    if (i == s_nfound[kind]) { if (s_nfound[kind] < 8) s_nfound[kind]++; else i = 7; memset(&s_found[kind][i], 0, sizeof s_found[kind][i]); }
    memcpy(s_found[kind][i].mac, a->val, 6); s_found[kind][i].addr_type = a->type; s_found[kind][i].rssi = rssi;
    if (f->name && f->name_len) { size_t n = f->name_len < 19 ? f->name_len : 19; memcpy(s_found[kind][i].name, f->name, n); s_found[kind][i].name[n] = 0; }
    s_found_ms[kind][i] = now;
    UNLOCK();
}

static bool link_wanted(const link_t *l) { return l->paired && !l->disabled && s_sensors_on; }

static int gap_event(struct ble_gap_event *ev, void *arg)
{
    switch (ev->type) {
    case BLE_GAP_EVENT_DISC: {
        const ble_addr_t *a = &ev->disc.addr;
        int i; for (i = 0; i < s_seen_n; i++) if (!memcmp(s_seen[i], a->val, 6)) break;
        if (i == s_seen_n) { if (s_seen_n < 48) memcpy(s_seen[s_seen_n++], a->val, 6); s_seen_total++; }
        struct ble_hs_adv_fields f;
        if (ble_hs_adv_parse_fields(&f, ev->disc.data, ev->disc.length_data) != 0) return 0;
        uint16_t svcs = svcs_of(&f);
        if (s_pair_kind == (int)PLAT_SENS_ANY) note_any(a, &f, ev->disc.rssi, svcs);
        int k = slot_of_svcs(svcs);   /* k = link SLOT */
        if (k < 0) {   /* a scan response often carries only the name: attach it to a device already listed */
            LOCK();
            for (int kk = 0; kk < NL && k < 0; kk++) for (int j = 0; j < s_nfound[kk]; j++) if (!memcmp(s_found[kk][j].mac, a->val, 6)) { k = kk; break; }
            UNLOCK();
        }
        for (int j = 0; j < NL; j++) {
            link_t *l = &L[j];
            bool same_mac = !memcmp(l->addr.val, a->val, 6);
            bool same_name = l->name[0] && f.name && f.name_len == strlen(l->name) && !memcmp(f.name, l->name, f.name_len);
            if (l->paired && !same_mac && same_name && k == j) {   /* the meter changed its address: follow it by name */
                ESP_LOGI(TAG, "paired %s seen under a new address", kind_name(l->kind));
                memcpy(l->addr.val, a->val, 6); l->addr.type = a->type; same_mac = true;
            }
            if (l->paired && same_mac) { LOCK(); l->rssi = ev->disc.rssi; UNLOCK(); if (k < 0) k = j; }
        }
        if (k < 0) return 0;
        note_found(k, a, &f, ev->disc.rssi);
        LOCK(); for (int j = 0; j < s_nfound[k]; j++) if (!memcmp(s_found[k][j].mac, a->val, 6)) s_found[k][j].svcs |= svcs; UNLOCK();
        link_t *l = &L[k];
        if (link_wanted(l) && !memcmp(l->addr.val, a->val, 6) && (l->state == PLAT_LINK_SEARCHING || l->state == PLAT_LINK_RETRY) &&
            (int32_t)(hw_millis() - l->retry_at) >= 0 && !s_connecting && l->conn == BLE_HS_CONN_HANDLE_NONE) {
            l->addr.type = a->type;
            ESP_LOGI(TAG, "paired %s seen (rssi %d) — connecting", kind_name(l->kind), ev->disc.rssi);
            connect_to(l);
        }
        return 0;
    }
    case BLE_GAP_EVENT_CONNECT: {
        unsigned slot = (unsigned)(uintptr_t)arg; if (slot >= NL) return 0;
        link_t *l = &L[slot];
        ble_link_central_busy(false);
        if (ev->connect.status != 0) { if (s_connecting == l) s_connecting = NULL; fail(l, "connect failed / timeout"); return 0; }
        l->conn = ev->connect.conn_handle; l->connects++; l->dgen++; l->busy = false; l->disc_started = false;
        if (!link_wanted(l)) { ESP_LOGI(TAG, "%s: connected after it was switched off - closing", kind_name(l->kind)); ble_gap_terminate(l->conn, BLE_ERR_REM_USER_CONN_TERM); return 0; }
        LOCK(); if (l->kind == PLAT_SENS_POWER) { bc_xds_live_reset(&l->xds); bc_cp_cad_reset(&l->cp); } else if (l->kind == PLAT_SENS_HR) bc_hr_live_reset(&l->hr); else bc_csc_live_reset(&l->csc);
        bc_pipe_connected(&l->pipe, hw_millis()); UNLOCK();
        pipe_log(l);
        s_mtu_link = l; s_mtu_conn = l->conn;
        if (ble_gattc_exchange_mtu(l->conn, on_mtu, cb_arg(l)) != 0) start_discovery(l);
        if (s_mtu_timer) { esp_timer_stop(s_mtu_timer); esp_timer_start_once(s_mtu_timer, 2000 * 1000); }
        return 0;
    }
    case BLE_GAP_EVENT_NOTIFY_RX: {
        link_t *l = by_conn(ev->notify_rx.conn_handle);
        if (!l) return 0;
        if (!l->val || ev->notify_rx.attr_handle != l->val) {   /* not the data characteristic: counted, never decoded */
            l->other_notifies++;
            if (!l->other_logged) { l->other_logged = true; ESP_LOGW("pipe", "%s: notification on handle 0x%04X ignored (data handle 0x%04X)", kind_name(l->kind), ev->notify_rx.attr_handle, l->val); }
            return 0;
        }
        uint8_t buf[32]; uint16_t n = ev->notify_rx.om ? OS_MBUF_PKTLEN(ev->notify_rx.om) : 0; if (n > sizeof buf) n = sizeof buf;
        if (n && os_mbuf_copydata(ev->notify_rx.om, 0, n, buf) != 0) n = 0;
        uint32_t now = hw_millis();
        bool first_valid = false;
        LOCK();
        uint32_t prev = l->kind == PLAT_SENS_POWER ? (l->xds.have ? l->xds.last_ms : 0) : l->kind == PLAT_SENS_HR ? (l->hr.have ? l->hr.last_ms : 0) : (l->csc.have_prev ? l->csc.last_ms : 0);
        bool ok = l->kind == PLAT_SENS_POWER ? (l->fmt == BC_PFMT_CPS ? bc_cp_live_feed(&l->xds, &l->cp, buf, n, now) : bc_xds_live_feed(&l->xds, buf, n, now))
                : l->kind == PLAT_SENS_HR ? bc_hr_live_feed(&l->hr, buf, n, now) : bc_csc_live_feed(&l->csc, buf, n, now);
        if (ok && prev && now - prev > 2500) l->gaps++;
        bc_pipe_packet(&l->pipe, buf, n, ok, now);
        if (ok && !l->valid_seen) { l->valid_seen = true; first_valid = true; }
        if (ok) l->backoff_s = 1;                        /* back-off resets only when real data flows (not on a bare subscribe) */
        UNLOCK();
        if (first_valid) { LOCK(); bc_pipe_tick(&l->pipe, now); UNLOCK(); pipe_log(l); }   /* log the first VALID at once */
        return 0;
    }
    case BLE_GAP_EVENT_DISCONNECT: {
        link_t *l = by_conn(ev->disconnect.conn.conn_handle);
        ESP_LOGW(TAG, "disconnected, reason 0x%x", ev->disconnect.reason);
        if (!l) return 0;
        l->conn = BLE_HS_CONN_HANDLE_NONE; l->busy = false; l->dgen++; l->disc_started = false;
        if (s_connecting == l) s_connecting = NULL;
        if (s_mtu_link == l) { s_mtu_link = NULL; s_mtu_conn = BLE_HS_CONN_HANDLE_NONE; if (s_mtu_timer) esp_timer_stop(s_mtu_timer); }
        LOCK(); l->reconnects++;
        if (l->pipe.stage != BC_STG_ERROR && !l->pipe.err[0]) snprintf(l->pipe.err, sizeof l->pipe.err, "link lost 0x%x", ev->disconnect.reason);
        l->valid_seen = false; UNLOCK();
        l->retry_at = hw_millis() + (uint32_t)l->backoff_s * 1000;
        l->backoff_s = l->backoff_s >= 16 ? 16 : l->backoff_s * 2;
        set_state(l, l->paired ? PLAT_LINK_RETRY : PLAT_LINK_NOT_PAIRED);
        return 0;
    }
    case BLE_GAP_EVENT_DISC_COMPLETE:
        s_scanning = false;
        return 0;
    default:
        return 0;
    }
}

/* ---- pairing changes from the UI: applied here, on the host task */
static void apply_requests(void)
{
    for (int i = 0; i < NL; i++) {
        pair_req_t r; LOCK(); r = s_req[i]; s_req[i].pending = false; s_req[i].set_disabled = false; UNLOCK();
        link_t *l = &L[i];
        if (r.set_disabled) {
            LOCK(); l->disabled = r.disabled; UNLOCK();
            ESP_LOGI(TAG, "%s link %s", kind_name(l->kind), r.disabled ? "disabled (staged boot / after a crash)" : "enabled");
            if (r.disabled && l->conn != BLE_HS_CONN_HANDLE_NONE) ble_gap_terminate(l->conn, BLE_ERR_REM_USER_CONN_TERM);
            if (r.disabled && s_connecting == l && l->conn == BLE_HS_CONN_HANDLE_NONE) { ble_gap_conn_cancel(); s_connecting = NULL; }
            if (!r.disabled && l->paired && l->state != PLAT_LINK_CONNECTED && l->conn == BLE_HS_CONN_HANDLE_NONE) { l->retry_at = 0; set_state(l, PLAT_LINK_SEARCHING); }
        }
        if (!r.pending) continue;
        if (l->conn != BLE_HS_CONN_HANDLE_NONE) ble_gap_terminate(l->conn, BLE_ERR_REM_USER_CONN_TERM);
        else if (s_connecting == l) { ble_gap_conn_cancel(); s_connecting = NULL; }
        LOCK();
        l->paired = r.paired;
        if (r.paired) { memcpy(l->addr.val, r.mac, 6); l->addr.type = r.addr_type; memcpy(l->name, r.name, sizeof l->name); }
        l->backoff_s = 1; l->retry_at = 0;
        bc_pipe_init(&l->pipe); l->pipe.stage_ms = hw_millis();          /* a new pairing / RETRY starts a clean pipeline */
        UNLOCK();
        set_state(l, r.paired ? PLAT_LINK_SEARCHING : PLAT_LINK_NOT_PAIRED);
    }
}

/* ---- manager: every 500 ms decide whether to scan (host task) */
static void tick(void)
{
    if (!s_synced) return;
    ble_link_tick();
    apply_requests();
    uint32_t now = hw_millis();
    /* 0.7.2 pipeline: stage from the clock + automatic recovery for every live connection */
    for (int i = 0; i < NL; i++) {
        link_t *l = &L[i];
        if (l->conn == BLE_HS_CONN_HANDLE_NONE) continue;
        if (l->busy && now - l->busy_since > 20000) { fail(l, "set-up timeout"); continue; }   /* a GATT answer never came */
        bool busy = l->busy;
        LOCK(); bc_pipe_act_t a = busy ? BC_PIPE_NONE : bc_pipe_tick(&l->pipe, now); UNLOCK();   /* no recovery while a discovery is in flight */
        pipe_log(l);
        switch (a) {
        case BC_PIPE_RESUBSCRIBE:
            ESP_LOGW("pipe", "%s: %s - discovering and subscribing again", kind_name(l->kind), l->pipe.have_valid ? "data stale > 10 s" : "subscribed, no packet in 8 s");
            disc_begin(l);
            break;
        case BC_PIPE_RECONNECT:
            ESP_LOGW("pipe", "%s: %s - reconnecting (back-off %d s)", kind_name(l->kind), l->pipe.err, l->backoff_s);
            l->dgen++; l->busy = false;
            ble_gap_terminate(l->conn, BLE_ERR_REM_USER_CONN_TERM);
            break;
        case BC_PIPE_DUMP_HEX: {
            ESP_LOGW("pipe", "%s: unreadable data - %lu packets, none decodes; first packets (sensor data only):", kind_name(l->kind), (unsigned long)l->pipe.packets);
            for (int k = 0; k < l->pipe.nhex && k < BC_PIPE_HEX_N; k++) { char h[64]; LOCK(); bc_pipe_hex(&l->pipe, k, h, sizeof h); UNLOCK(); ESP_LOGW("pipe", "%s   [%d] %s", kind_name(l->kind), k + 1, h); }
            break; }
        default: break;
        }
    }
    link_t *sc = s_connecting;
    if (sc && now - sc->state_since > 15000) {   /* stuck connect/discovery */
        ESP_LOGW(TAG, "connection set-up took > 15 s — retrying");
        if (sc->conn != BLE_HS_CONN_HANDLE_NONE) { sc->dgen++; sc->busy = false; ble_gap_terminate(sc->conn, BLE_ERR_REM_USER_CONN_TERM); }
        else { ble_gap_conn_cancel(); s_connecting = NULL; fail(sc, "connect timeout"); }
        return;
    }
    if (s_connecting) return;
    static uint32_t s_rssi_t;
    if (now - s_rssi_t > 2000) {   /* live link RSSI, read here so the display never waits on the radio */
        s_rssi_t = now;
        for (int i = 0; i < NL; i++) { int8_t r; if (L[i].conn != BLE_HS_CONN_HANDLE_NONE && ble_gap_conn_rssi(L[i].conn, &r) == 0) { LOCK(); L[i].rssi = r; UNLOCK(); } }
    }
    bool need = s_pair_kind >= 0;
    for (int i = 0; i < NL && !s_standby; i++) {   /* connected standby (0.6.0): no scanning for paired sensors; live connections are kept */
        link_t *l = &L[i];
        if (!link_wanted(l)) continue;
        if (l->state == PLAT_LINK_RETRY && (int32_t)(now - l->retry_at) >= 0) set_state(l, PLAT_LINK_SEARCHING);
        if (l->state == PLAT_LINK_SEARCHING) need = true;
    }
    if (!s_sensors_on && s_pair_kind < 0) need = false;
    /* drop pairing-list entries not heard for 20 s */
    LOCK();
    for (int k = 0; k < NL; k++) for (int i = 0; i < s_nfound[k]; i++) if (now - s_found_ms[k][i] > 20000) {
        s_found[k][i] = s_found[k][s_nfound[k] - 1]; s_found_ms[k][i] = s_found_ms[k][s_nfound[k] - 1]; s_nfound[k]--; i--;
    }
    for (int i = 0; i < s_nany; i++) if (now - s_any_ms[i] > 20000) { s_any[i] = s_any[s_nany - 1]; s_any_ms[i] = s_any_ms[s_nany - 1]; s_nany--; i--; }
    UNLOCK();
    if (need) scan_start(); else scan_stop();
}
static void tick_ev(struct ble_npl_event *ev) { (void)ev; tick(); }
static void link_ev(struct ble_npl_event *ev) { (void)ev; if (s_synced) { ble_link_tick(); apply_requests(); } }
static void req_ev(struct ble_npl_event *ev) { (void)ev; if (s_synced) apply_requests(); }

static void on_sync(void)
{
    ble_hs_util_ensure_addr(0);
    ble_hs_id_infer_auto(0, &s_own);
    s_synced = true;
    ESP_LOGI(TAG, "host synced");
    s_own = ble_link_on_sync(s_own);                  /* 0.7.0: random-static identity for both roles */
}
static void on_reset(int reason) { ESP_LOGW(TAG, "host reset %d", reason); s_synced = false; s_scanning = false; }
static void host_task(void *p) { nimble_port_run(); nimble_port_freertos_deinit(); }
/* the manager task only paces the work: the link side every 100 ms, the sensor side every 500 ms, both run on the host task */
static void mgr_task(void *p)
{
    struct ble_npl_eventq *q = nimble_port_get_dflt_eventq();
    for (int i = 0;; i++) { ble_npl_eventq_put(q, i % 5 == 0 ? &s_ev_tick : &s_ev_link); vTaskDelay(pdMS_TO_TICKS(100)); }
}

/* ---- 0.7.4 start-up: the Bluetooth stack (controller + NimBLE port memory) and the host/link start are separate steps and
   neither aborts. 0.7.3 called ESP_ERROR_CHECK(nimble_port_init()) after the UI had been built: on the owner's board
   "BLE_INIT: hci inits failed" -> abort() in the main task on every start (coord/reports/FW_STORAGE_MEMORY_REPORT.md). By the
   ESP-IDF 5.5.1 source, esp_nimble_hci_init() can only fail there on an INTERNAL-RAM allocation (ble_buf_alloc /
   semaphore) once the controller is enabled - so the free internal heap and its largest block are logged before the stack
   starts and again when it fails, and the board carries on with "Bluetooth unavailable" and the reason. */
static ble_central_init_t s_init;
static void heap_now(uint32_t *fr, uint32_t *lg, uint32_t *dma)
{
    *fr = (uint32_t)heap_caps_get_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
    *lg = (uint32_t)heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
    *dma = (uint32_t)heap_caps_get_free_size(MALLOC_CAP_DMA);
}
static void init_fail(const char *what, int err)
{
    s_init.failed = true; s_init.err = err;
    heap_now(&s_init.fail_free, &s_init.fail_largest, &s_init.fail_dma);
    snprintf(s_init.reason, sizeof s_init.reason, "%s", what);   /* short: shown on the round screen; err code in the log */
    ESP_LOGE(TAG, "Bluetooth unavailable: %s (err 0x%x) - internal heap free %u B (largest block %u B, DMA %u B); before start: free %u, largest %u, DMA %u",
             s_init.reason, (unsigned)err, (unsigned)s_init.fail_free, (unsigned)s_init.fail_largest, (unsigned)s_init.fail_dma,
             (unsigned)s_init.pre_free, (unsigned)s_init.pre_largest, (unsigned)s_init.pre_dma);
}

bool ble_central_stack_init(void)
{
    if (s_init.stack_ok) return true;
    if (s_init.failed) return false;                  /* one attempt per boot: a failed controller start is not retried blindly */
    s_init.attempted = true;
    heap_now(&s_init.pre_free, &s_init.pre_largest, &s_init.pre_dma);
    ESP_LOGI(TAG, "Bluetooth stack starting: internal heap free %u B, largest block %u B, DMA-capable free %u B",
             (unsigned)s_init.pre_free, (unsigned)s_init.pre_largest, (unsigned)s_init.pre_dma);
    esp_err_t e = nimble_port_init();                 /* on failure it disables + deinits the controller itself (nimble_port.c) */
    if (e != ESP_OK) { init_fail("HCI init failed", e); return false; }
    s_init.stack_ok = true;
    heap_now(&s_init.post_free, &s_init.post_largest, &s_init.post_dma);
    ESP_LOGI(TAG, "Bluetooth stack up: it took %d B of internal heap (now free %u B, largest %u B)",
             (int)s_init.pre_free - (int)s_init.post_free, (unsigned)s_init.post_free, (unsigned)s_init.post_largest);
    return true;
}

bool ble_central_start(bool sensors)
{
    s_sensors_on = sensors;
    if (s_events_ready) return true;
    if (!ble_central_stack_init()) return false;
    if (!s_mtu_timer) {
        esp_timer_create_args_t m = { .callback = mtu_fallback_timer, .name = "ble_mtu" };
        esp_err_t e = esp_timer_create(&m, &s_mtu_timer);
        if (e != ESP_OK) { s_mtu_timer = NULL; ESP_LOGW(TAG, "MTU fallback timer not created (0x%x): discovery waits for the MTU exchange only", (unsigned)e); }
    }
    ble_npl_event_init(&s_ev_tick, tick_ev, NULL);
    ble_npl_event_init(&s_ev_link, link_ev, NULL);
    ble_npl_event_init(&s_ev_mtu, mtu_fallback_ev, NULL);
    ble_npl_event_init(&s_ev_req, req_ev, NULL);
    s_events_ready = true;
    ble_hs_cfg.sync_cb = on_sync;
    ble_hs_cfg.reset_cb = on_reset;
    ble_att_set_preferred_mtu(247);
    ble_link_configure_security();
    ble_link_register_gatt();                         /* phone-link service; GAP + GATT services too */
    ble_svc_gap_device_name_set("BikeComputer");
    ble_store_config_init();                          /* bonds persist in NVS (CONFIG_BT_NIMBLE_NVS_PERSIST) */
    nimble_port_freertos_init(host_task);             /* ESP-IDF ignores a failed task creation: checked just below */
    if (!xTaskGetHandle("nimble_host")) { init_fail("no RAM for host task", ESP_ERR_NO_MEM); s_init.stack_ok = false; return false; }
    if (xTaskCreatePinnedToCore(mgr_task, "ble_mgr", 3072, NULL, 4, NULL, 0) != pdPASS)
        ESP_LOGE(TAG, "ble_mgr task not created: sensors and phone link are not paced (no reconnect ticks)");
    s_init.host_started = true;
    return true;
}

const ble_central_init_t *ble_central_init_info(void) { return &s_init; }
bool ble_central_unavailable(void) { return s_init.failed; }

void ble_central_enable_sensors(bool on) { s_sensors_on = on; if (s_events_ready) ble_npl_eventq_put(nimble_port_get_dflt_eventq(), &s_ev_req); }

void ble_central_set_paired(plat_sens_kind_t kind, const uint8_t mac[6], uint8_t addr_type, const char *name)
{
    int si = slot_of(kind); if (si < 0) return;
    pair_req_t *r = &s_req[si];
    LOCK();
    r->pending = true; r->paired = mac != NULL;
    if (mac) { memcpy(r->mac, mac, 6); r->addr_type = addr_type; snprintf(r->name, sizeof r->name, "%s", name ? name : ""); }
    UNLOCK();                                         /* the link itself changes on the host task (apply_requests) */
    if (s_events_ready) ble_npl_eventq_put(nimble_port_get_dflt_eventq(), &s_ev_req);
}

void ble_central_set_disabled(plat_sens_kind_t kind, bool disabled)
{
    int si = slot_of(kind); if (si < 0) return;
    LOCK(); s_req[si].set_disabled = true; s_req[si].disabled = disabled; UNLOCK();
    if (s_events_ready) ble_npl_eventq_put(nimble_port_get_dflt_eventq(), &s_ev_req);
}

void ble_central_set_standby(bool standby) { s_standby = standby; }
void ble_central_scan_for(int kind)
{
    s_pair_kind = kind;
    int si = slot_of(kind);
    LOCK(); if (si >= 0) s_nfound[si] = 0; if (kind == (int)PLAT_SENS_ANY) s_nany = 0; UNLOCK();
}
void ble_central_set_wheel_mm(uint16_t mm) { s_wheel_mm = mm; }

int ble_central_found(plat_sens_kind_t kind, plat_found_t *out, int max)
{
    int n;
    if (max <= 0) return 0;
    if (kind == PLAT_SENS_ANY) { LOCK(); n = s_nany < max ? s_nany : max; memcpy(out, s_any, sizeof(plat_found_t) * (size_t)n); UNLOCK(); }
    else {
        int si = slot_of(kind); if (si < 0) return 0;
        LOCK();
        n = s_nfound[si] < max ? s_nfound[si] : max;
        memcpy(out, s_found[si], sizeof(plat_found_t) * (size_t)n);
        UNLOCK();
    }
    /* strongest first */
    for (int i = 1; i < n; i++) for (int j = i; j > 0 && out[j].rssi > out[j - 1].rssi; j--) { plat_found_t t = out[j]; out[j] = out[j - 1]; out[j - 1] = t; }
    return n;
}

uint32_t ble_central_devices_seen(void) { return s_seen_total; }
bool ble_central_ready(void) { return s_synced; }
bool ble_central_scanning(void) { return s_scanning; }

void ble_central_snapshot(plat_sensors_t *o)
{
    uint32_t now = hw_millis();
    memset(o, 0, sizeof *o);
    /* NOTE: no Bluetooth calls here — this runs in the UI task and must never wait on the radio (RSSI is read by tick()) */
    LOCK();
    int w, rpm, bpm; bool back = false;
    o->power_ok = L[0].state == PLAT_LINK_CONNECTED && bc_xds_live_power(&L[0].xds, now, &w) == BC_LIVE_OK; if (o->power_ok) o->watts = w;
    o->cad_ok = L[0].state == PLAT_LINK_CONNECTED && bc_xds_live_cadence(&L[0].xds, now, &rpm, &back) == BC_LIVE_OK; if (o->cad_ok) { o->rpm = rpm; o->backwards = back; }
    o->hr_ok = L[1].state == PLAT_LINK_CONNECTED && bc_hr_live_bpm(&L[1].hr, now, &bpm) == BC_LIVE_OK; if (o->hr_ok) o->bpm = bpm;
    { int cr, sp; bool on = L[2].state == PLAT_LINK_CONNECTED;
      o->csc_cad_ok = on && bc_csc_live_cadence(&L[2].csc, now, &cr) == BC_LIVE_OK; if (o->csc_cad_ok) o->csc_rpm = cr;
      o->csc_speed_ok = on && bc_csc_live_speed(&L[2].csc, now, s_wheel_mm, &sp) == BC_LIVE_OK; if (o->csc_speed_ok) o->csc_speed_dmh = sp;
      o->csc_has_wheel = on && L[2].csc.has_wheel; o->csc_has_crank = on && L[2].csc.has_crank; }
    for (int i = 0; i < NL; i++) {
        plat_link_info_t *li = &o->link[L[i].kind];
        li->link = L[i].paired ? L[i].state : PLAT_LINK_NOT_PAIRED;
        snprintf(li->name, sizeof li->name, "%s", L[i].name);
        li->rssi = L[i].rssi;
        uint32_t pk = i == 0 ? L[0].xds.packets : i == 1 ? L[1].hr.packets : L[2].csc.packets;
        uint32_t last = i == 0 ? L[0].xds.last_packet_ms : i == 1 ? L[1].hr.last_packet_ms : L[2].csc.last_packet_ms;
        bool hv = i == 0 ? L[0].xds.have : i == 1 ? L[1].hr.have : L[2].csc.have_prev;
        uint32_t lv = i == 0 ? L[0].xds.last_ms : i == 1 ? L[1].hr.last_ms : L[2].csc.last_ms;
        li->packets = pk; li->age_ms = pk ? now - last : UINT32_MAX; li->reconnects = L[i].reconnects;
        const bc_pipe_t *pp = &L[i].pipe;
        li->stage = (uint8_t)(L[i].paired ? pp->stage : BC_STG_NOT_PAIRED); li->stage_age_ms = now - pp->stage_ms;
        snprintf(li->err, sizeof li->err, "%s", pp->err); li->unreadable = pp->unreadable;
        li->svc_uuid = L[i].svc_uuid; li->cccd = pp->cccd; li->data_handle = L[i].val;
        li->resubscribes = pp->resubscribes; li->auto_reconnects = pp->reconnects;
        li->valid_age_ms = hv ? now - lv : UINT32_MAX;
        li->gaps = L[i].gaps;
        li->rejected = i == 0 ? L[0].xds.rejected + L[0].xds.short_packets : i == 1 ? L[1].hr.rejected : L[2].csc.rejected;
        if (pp->stage >= BC_STG_SUBSCRIBED && pp->stage != BC_STG_ERROR) { li->packets = pp->packets; li->rejected = pp->rejected; }
        li->disabled = L[i].paired && (L[i].disabled || !s_sensors_on);
    }
    UNLOCK();
    o->link[PLAT_SENS_SPEED].link = PLAT_LINK_UNSUPPORTED;
}
