/*
 * NimBLE central: paired power meter + optional HR strap + pairing scan. See ble_central.h for the safety rules.
 * The power-meter sequence is the one proven in 0.1.x / PORTING_SPEC §1–§5: connect → MTU exchange (≤ 2 s) →
 * discover 0x1828 → 0x2A63 → CCCD → write 01 00 → decode notifications with bc_core.
 */
#include "ble_central.h"
#include <string.h>
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "services/gap/ble_svc_gap.h"
#include "bc_xds.h"
#include "bc_hr.h"
#include "hw.h"
#include "ble_link.h"
void ble_store_config_init(void);

static const char *TAG = "ble";
static portMUX_TYPE s_mux = portMUX_INITIALIZER_UNLOCKED;
#define LOCK() portENTER_CRITICAL(&s_mux)
#define UNLOCK() portEXIT_CRITICAL(&s_mux)

typedef struct {
    int kind;
    uint16_t svc_uuid, chr_uuid;
    bool paired; ble_addr_t addr; char name[20];
    plat_link_t state;
    uint16_t conn, svc_s, svc_e, val, cccd; bool disc_started;
    int8_t rssi; uint32_t reconnects, connects, gaps; int backoff_s; uint32_t retry_at;
    uint32_t state_since;
    bc_xds_live_t xds; bc_hr_live_t hr;
} link_t;

static link_t L[2] = {
    { .kind = PLAT_SENS_POWER, .svc_uuid = 0x1828, .chr_uuid = 0x2A63, .conn = BLE_HS_CONN_HANDLE_NONE, .backoff_s = 1 },
    { .kind = PLAT_SENS_HR, .svc_uuid = 0x180D, .chr_uuid = 0x2A37, .conn = BLE_HS_CONN_HANDLE_NONE, .backoff_s = 1 },
};
static uint8_t s_own;
static bool s_synced, s_scanning;
static int s_pair_kind = -1;
static link_t *s_connecting;
static plat_found_t s_found[2][8]; static int s_nfound[2]; static uint32_t s_found_ms[2][8];
static uint8_t s_seen[48][6]; static int s_seen_n; static uint32_t s_seen_total;
static esp_timer_handle_t s_mtu_timer;

static const char *st_name(plat_link_t s)
{
    switch (s) { case PLAT_LINK_NOT_PAIRED: return "NOT PAIRED"; case PLAT_LINK_SEARCHING: return "SEARCHING"; case PLAT_LINK_CONNECTING: return "CONNECTING";
                 case PLAT_LINK_CONNECTED: return "CONNECTED"; case PLAT_LINK_RETRY: return "RECONNECTING"; default: return "OFF"; }
}

static void set_state(link_t *l, plat_link_t s)
{
    LOCK(); l->state = s; l->state_since = hw_millis(); UNLOCK();
    ESP_LOGI(TAG, "%s → %s", l->kind == PLAT_SENS_POWER ? "power" : "hr", st_name(s));
}

static link_t *by_conn(uint16_t c) { for (int i = 0; i < 2; i++) if (L[i].conn == c) return &L[i]; return NULL; }

static void fail(link_t *l, const char *why)
{
    ESP_LOGW(TAG, "%s: %s", l->kind == PLAT_SENS_POWER ? "power" : "hr", why);
    if (l->conn != BLE_HS_CONN_HANDLE_NONE) ble_gap_terminate(l->conn, BLE_ERR_REM_USER_CONN_TERM);
    else {
        if (s_connecting == l) s_connecting = NULL;
        l->retry_at = hw_millis() + (uint32_t)l->backoff_s * 1000;
        l->backoff_s = l->backoff_s >= 16 ? 16 : l->backoff_s * 2;
        set_state(l, l->paired ? PLAT_LINK_RETRY : PLAT_LINK_NOT_PAIRED);
    }
}

/* ---- GATT chain */
static int on_cccd(uint16_t conn, const struct ble_gatt_error *err, struct ble_gatt_attr *attr, void *arg)
{
    link_t *l = by_conn(conn); if (!l) return 0;
    if (err->status == 0) { l->backoff_s = 1; s_connecting = NULL; set_state(l, PLAT_LINK_CONNECTED); ESP_LOGI(TAG, "subscribed 0x%04X", l->chr_uuid); }
    else fail(l, "CCCD write failed");
    return 0;
}

static int on_dsc(uint16_t conn, const struct ble_gatt_error *err, uint16_t chr_val, const struct ble_gatt_dsc *dsc, void *arg)
{
    link_t *l = by_conn(conn); if (!l) return 0;
    if (err->status == 0 && dsc && ble_uuid_cmp(&dsc->uuid.u, BLE_UUID16_DECLARE(BLE_GATT_DSC_CLT_CFG_UUID16)) == 0) l->cccd = dsc->handle;
    if (err->status == BLE_HS_EDONE) {
        if (!l->cccd) { fail(l, "no CCCD"); return 0; }
        static const uint8_t on[2] = { 0x01, 0x00 };   /* notifications on — the ONLY write this firmware sends */
        ble_gattc_write_flat(conn, l->cccd, on, sizeof on, on_cccd, NULL);
    }
    return 0;
}

static int on_chr(uint16_t conn, const struct ble_gatt_error *err, const struct ble_gatt_chr *chr, void *arg)
{
    link_t *l = by_conn(conn); if (!l) return 0;
    if (err->status == 0 && chr) l->val = chr->val_handle;
    if (err->status == BLE_HS_EDONE) {
        if (!l->val) { fail(l, "characteristic not found"); return 0; }
        ble_gattc_disc_all_dscs(conn, l->val, l->svc_e, on_dsc, NULL);
    }
    return 0;
}

static int on_svc(uint16_t conn, const struct ble_gatt_error *err, const struct ble_gatt_svc *svc, void *arg)
{
    link_t *l = by_conn(conn); if (!l) return 0;
    if (err->status == 0 && svc) { l->svc_s = svc->start_handle; l->svc_e = svc->end_handle; }
    if (err->status == BLE_HS_EDONE) {
        if (!l->svc_s) { fail(l, "service not found"); return 0; }
        ble_gattc_disc_chrs_by_uuid(conn, l->svc_s, l->svc_e, BLE_UUID16_DECLARE(l->chr_uuid), on_chr, NULL);
    }
    return 0;
}

static void start_discovery(link_t *l)
{
    if (!l || l->disc_started || l->conn == BLE_HS_CONN_HANDLE_NONE) return;
    l->disc_started = true;
    ble_gattc_disc_svc_by_uuid(l->conn, BLE_UUID16_DECLARE(l->svc_uuid), on_svc, NULL);
}

static link_t *s_mtu_link;
static int on_mtu(uint16_t conn, const struct ble_gatt_error *err, uint16_t mtu, void *arg)
{
    ESP_LOGI(TAG, "MTU exchange: status %d, mtu %u", err->status, mtu);
    esp_timer_stop(s_mtu_timer);
    start_discovery(by_conn(conn));                  /* discovery only after the MTU exchange (PORTING_SPEC §2) */
    return 0;
}
static void mtu_fallback(void *arg) { ESP_LOGW(TAG, "no MTU response in 2 s — discovering anyway"); start_discovery(s_mtu_link); }

/* ---- scanning */
static int kind_of(const struct ble_hs_adv_fields *f)
{
    for (int i = 0; i < f->num_uuids16; i++) {
        uint16_t u = ble_uuid_u16(&f->uuids16[i].u);
        if (u == 0x1828) return PLAT_SENS_POWER;
        if (u == 0x180D) return PLAT_SENS_HR;
    }
    if (f->name && f->name_len >= 3 && memcmp(f->name, "XDS", 3) == 0) return PLAT_SENS_POWER;
    return -1;
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
    l->svc_s = l->svc_e = l->val = l->cccd = 0; l->disc_started = false;
    set_state(l, PLAT_LINK_CONNECTING);
    ble_link_central_busy(true);                      /* phone advertising pauses while we initiate (meter first, always) */
    int rc = ble_gap_connect(s_own, &l->addr, 10000, NULL, gap_event, l);
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

static int gap_event(struct ble_gap_event *ev, void *arg)
{
    switch (ev->type) {
    case BLE_GAP_EVENT_DISC: {
        const ble_addr_t *a = &ev->disc.addr;
        int i; for (i = 0; i < s_seen_n; i++) if (!memcmp(s_seen[i], a->val, 6)) break;
        if (i == s_seen_n) { if (s_seen_n < 48) memcpy(s_seen[s_seen_n++], a->val, 6); s_seen_total++; }
        struct ble_hs_adv_fields f;
        if (ble_hs_adv_parse_fields(&f, ev->disc.data, ev->disc.length_data) != 0) return 0;
        int k = kind_of(&f);
        if (k < 0) {   /* a scan response often carries only the name: attach it to a device already listed */
            LOCK();
            for (int kk = 0; kk < 2 && k < 0; kk++) for (int j = 0; j < s_nfound[kk]; j++) if (!memcmp(s_found[kk][j].mac, a->val, 6)) { k = kk; break; }
            UNLOCK();
        }
        for (int j = 0; j < 2; j++) {
            link_t *l = &L[j];
            bool same_mac = !memcmp(l->addr.val, a->val, 6);
            bool same_name = l->name[0] && f.name && f.name_len == strlen(l->name) && !memcmp(f.name, l->name, f.name_len);
            if (l->paired && !same_mac && same_name && k == l->kind) {   /* the meter changed its address: follow it by name */
                ESP_LOGI(TAG, "paired %s seen under a new address", l->name);
                memcpy(l->addr.val, a->val, 6); l->addr.type = a->type; same_mac = true;
            }
            if (l->paired && same_mac) { LOCK(); l->rssi = ev->disc.rssi; UNLOCK(); if (k < 0) k = l->kind; }
        }
        if (k < 0) return 0;
        note_found(k, a, &f, ev->disc.rssi);
        link_t *l = &L[k];
        if (l->paired && !memcmp(l->addr.val, a->val, 6) && (l->state == PLAT_LINK_SEARCHING || l->state == PLAT_LINK_RETRY) &&
            (int32_t)(hw_millis() - l->retry_at) >= 0 && !s_connecting) {
            l->addr.type = a->type;
            ESP_LOGI(TAG, "paired %s seen (rssi %d) — connecting", k == PLAT_SENS_POWER ? "meter" : "strap", ev->disc.rssi);
            connect_to(l);
        }
        return 0;
    }
    case BLE_GAP_EVENT_CONNECT: {
        link_t *l = (link_t *)arg;
        ble_link_central_busy(false);
        if (ev->connect.status != 0) { s_connecting = NULL; fail(l, "connect failed / timeout"); return 0; }
        l->conn = ev->connect.conn_handle; l->connects++;
        LOCK(); if (l->kind == PLAT_SENS_POWER) bc_xds_live_reset(&l->xds); else bc_hr_live_reset(&l->hr); UNLOCK();
        s_mtu_link = l;
        ble_gattc_exchange_mtu(l->conn, on_mtu, NULL);
        esp_timer_stop(s_mtu_timer); esp_timer_start_once(s_mtu_timer, 2000 * 1000);
        return 0;
    }
    case BLE_GAP_EVENT_NOTIFY_RX: {
        link_t *l = by_conn(ev->notify_rx.conn_handle);
        if (!l || ev->notify_rx.attr_handle != l->val) return 0;
        uint8_t buf[32]; uint16_t n = OS_MBUF_PKTLEN(ev->notify_rx.om); if (n > sizeof buf) n = sizeof buf;
        os_mbuf_copydata(ev->notify_rx.om, 0, n, buf);
        uint32_t now = hw_millis();
        LOCK();
        uint32_t prev = l->kind == PLAT_SENS_POWER ? (l->xds.have ? l->xds.last_ms : 0) : (l->hr.have ? l->hr.last_ms : 0);
        bool ok = l->kind == PLAT_SENS_POWER ? bc_xds_live_feed(&l->xds, buf, n, now) : bc_hr_live_feed(&l->hr, buf, n, now);
        if (ok && prev && now - prev > 2500) l->gaps++;
        UNLOCK();
        return 0;
    }
    case BLE_GAP_EVENT_DISCONNECT: {
        link_t *l = by_conn(ev->disconnect.conn.conn_handle);
        ESP_LOGW(TAG, "disconnected, reason 0x%x", ev->disconnect.reason);
        if (!l) return 0;
        l->conn = BLE_HS_CONN_HANDLE_NONE;
        if (s_connecting == l) s_connecting = NULL;
        LOCK(); l->reconnects++; UNLOCK();
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

/* ---- manager: every 500 ms decide whether to scan */
static void tick(void *arg)
{
    if (!s_synced) return;
    ble_link_tick();
    uint32_t now = hw_millis();
    if (s_connecting && now - s_connecting->state_since > 15000) {   /* stuck connect/discovery */
        link_t *l = s_connecting;
        ESP_LOGW(TAG, "connection set-up took > 15 s — retrying");
        if (l->conn != BLE_HS_CONN_HANDLE_NONE) ble_gap_terminate(l->conn, BLE_ERR_REM_USER_CONN_TERM);
        else { ble_gap_conn_cancel(); s_connecting = NULL; fail(l, "connect timeout"); }
        return;
    }
    if (s_connecting) return;
    static uint32_t s_rssi_t;
    if (now - s_rssi_t > 2000) {   /* live link RSSI, read here (timer task) so the display never waits on the radio */
        s_rssi_t = now;
        for (int i = 0; i < 2; i++) { int8_t r; if (L[i].conn != BLE_HS_CONN_HANDLE_NONE && ble_gap_conn_rssi(L[i].conn, &r) == 0) { LOCK(); L[i].rssi = r; UNLOCK(); } }
    }
    bool need = s_pair_kind >= 0;
    for (int i = 0; i < 2 && !s_standby; i++) {   /* connected standby (0.6.0): no scanning for paired sensors; live connections are kept */
        link_t *l = &L[i];
        if (!l->paired) continue;
        if (l->state == PLAT_LINK_RETRY && (int32_t)(now - l->retry_at) >= 0) set_state(l, PLAT_LINK_SEARCHING);
        if (l->state == PLAT_LINK_SEARCHING) need = true;
    }
    /* drop pairing-list entries not heard for 20 s */
    LOCK();
    for (int k = 0; k < 2; k++) for (int i = 0; i < s_nfound[k]; i++) if (now - s_found_ms[k][i] > 20000) {
        s_found[k][i] = s_found[k][s_nfound[k] - 1]; s_found_ms[k][i] = s_found_ms[k][s_nfound[k] - 1]; s_nfound[k]--; i--;
    }
    UNLOCK();
    if (need) scan_start(); else scan_stop();
}

static void on_sync(void)
{
    ble_hs_util_ensure_addr(0);
    ble_hs_id_infer_auto(0, &s_own);
    s_synced = true;
    ESP_LOGI(TAG, "host synced");
    ble_link_on_sync(s_own);
}
static void on_reset(int reason) { ESP_LOGW(TAG, "host reset %d", reason); s_synced = false; s_scanning = false; }
static void host_task(void *p) { nimble_port_run(); nimble_port_freertos_deinit(); }
/* the manager runs in its own task (not the shared esp_timer task), so a slow radio call can never stall the
   display tick or any other timer */
/* 0.6.0: the link side (notifications, incl. ride-history sync batches) every 100 ms, the sensor side every 500 ms */
static void mgr_task(void *p) { for (int i = 0;; i++) { if (i % 5 == 0) tick(NULL); else ble_link_tick(); vTaskDelay(pdMS_TO_TICKS(100)); } }

void ble_central_start(void)
{
    esp_timer_create_args_t m = { .callback = mtu_fallback, .name = "ble_mtu" };
    ESP_ERROR_CHECK(esp_timer_create(&m, &s_mtu_timer));
    ESP_ERROR_CHECK(nimble_port_init());
    ble_hs_cfg.sync_cb = on_sync;
    ble_hs_cfg.reset_cb = on_reset;
    ble_att_set_preferred_mtu(247);
    ble_link_configure_security();
    ble_link_register_gatt();                         /* phone-link service; GAP + GATT services too */
    ble_svc_gap_device_name_set("BikeComputer");
    ble_store_config_init();                          /* bonds persist in NVS (CONFIG_BT_NIMBLE_NVS_PERSIST) */
    nimble_port_freertos_init(host_task);
    xTaskCreatePinnedToCore(mgr_task, "ble_mgr", 4096, NULL, 4, NULL, 0);
}

void ble_central_set_paired(plat_sens_kind_t kind, const uint8_t mac[6], uint8_t addr_type, const char *name)
{
    if (kind > PLAT_SENS_HR) return;
    link_t *l = &L[kind];
    if (l->conn != BLE_HS_CONN_HANDLE_NONE) ble_gap_terminate(l->conn, BLE_ERR_REM_USER_CONN_TERM);
    LOCK();
    l->paired = mac != NULL;
    if (mac) { memcpy(l->addr.val, mac, 6); l->addr.type = addr_type; snprintf(l->name, sizeof l->name, "%s", name ? name : ""); }
    l->backoff_s = 1; l->retry_at = 0;
    UNLOCK();
    set_state(l, mac ? PLAT_LINK_SEARCHING : PLAT_LINK_NOT_PAIRED);
}

void ble_central_set_standby(bool standby) { s_standby = standby; }
void ble_central_scan_for(int kind) { s_pair_kind = kind; if (kind >= 0) { LOCK(); s_nfound[kind] = 0; UNLOCK(); } }

int ble_central_found(plat_sens_kind_t kind, plat_found_t *out, int max)
{
    if (kind > PLAT_SENS_HR) return 0;
    LOCK();
    int n = s_nfound[kind] < max ? s_nfound[kind] : max;
    memcpy(out, s_found[kind], sizeof(plat_found_t) * (size_t)n);
    UNLOCK();
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
    /* live RSSI of connected links (NimBLE calls are thread-safe) */
    /* NOTE: no Bluetooth calls here — this runs in the UI task and must never wait on the radio (RSSI is read by tick()) */
    LOCK();
    int w, rpm, bpm; bool back = false;
    o->power_ok = L[0].state == PLAT_LINK_CONNECTED && bc_xds_live_power(&L[0].xds, now, &w) == BC_LIVE_OK; if (o->power_ok) o->watts = w;
    o->cad_ok = L[0].state == PLAT_LINK_CONNECTED && bc_xds_live_cadence(&L[0].xds, now, &rpm, &back) == BC_LIVE_OK; if (o->cad_ok) { o->rpm = rpm; o->backwards = back; }
    o->hr_ok = L[1].state == PLAT_LINK_CONNECTED && bc_hr_live_bpm(&L[1].hr, now, &bpm) == BC_LIVE_OK; if (o->hr_ok) o->bpm = bpm;
    for (int i = 0; i < 2; i++) {
        plat_link_info_t *li = &o->link[i];
        li->link = L[i].paired ? L[i].state : PLAT_LINK_NOT_PAIRED;
        snprintf(li->name, sizeof li->name, "%s", L[i].name);
        li->rssi = L[i].rssi;
        uint32_t pk = i == 0 ? L[0].xds.packets : L[1].hr.packets, last = i == 0 ? L[0].xds.last_packet_ms : L[1].hr.last_packet_ms;
        bool hv = i == 0 ? L[0].xds.have : L[1].hr.have; uint32_t lv = i == 0 ? L[0].xds.last_ms : L[1].hr.last_ms;
        li->packets = pk; li->age_ms = pk ? now - last : UINT32_MAX; li->reconnects = L[i].reconnects;
        li->valid_age_ms = hv ? now - lv : UINT32_MAX;
        li->gaps = L[i].gaps;
        li->rejected = i == 0 ? L[0].xds.rejected + L[0].xds.short_packets : L[1].hr.rejected;
    }
    UNLOCK();
    o->link[PLAT_SENS_SPEED].link = PLAT_LINK_UNSUPPORTED;
}
