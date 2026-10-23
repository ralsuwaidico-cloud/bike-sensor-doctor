/*
 * XDS / Branta power meter over BLE (NimBLE central). Follows docs/PORTING_SPEC.md §1–§5:
 *   scan for 16-bit UUID 0x1828 or a name beginning "XDS" → connect → MTU exchange (wait ≤ 2 s) → discover 0x1828 →
 *   characteristic 0x2A63 → its CCCD → write 01 00 (notifications) → decode every notification with bc_core.
 * SAFETY: the only write this module ever performs is that CCCD subscription. No control point, no vendor
 * characteristic, no pairing. Reconnect with back-off 1, 2, 4, 8, 16 s, then scan again.
 */
#include "ble_xds.h"
#include <string.h>
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "nvs.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "services/gap/ble_svc_gap.h"
#include "hw.h"

static const char *TAG = "xds";
static portMUX_TYPE s_mux = portMUX_INITIALIZER_UNLOCKED;
static xds_status_t s_st;
static uint8_t s_own_addr_type;
static uint16_t s_conn = BLE_HS_CONN_HANDLE_NONE, s_svc_start, s_svc_end, s_val_handle, s_cccd;
static bool s_disc_started;
static esp_timer_handle_t s_timer;      /* MTU fallback and reconnect back-off */
static int s_backoff_s = 1;
static enum { T_NONE, T_MTU_FALLBACK, T_RETRY } s_timer_kind;
static uint8_t s_seen[32][6]; static int s_seen_n;

#define LOCK() portENTER_CRITICAL(&s_mux)
#define UNLOCK() portEXIT_CRITICAL(&s_mux)
static void set_state(xds_state_t s) { LOCK(); s_st.state = s; UNLOCK(); ESP_LOGI(TAG, "state → %s", ble_xds_state_name(s)); }

const char *ble_xds_state_name(xds_state_t s)
{
    switch (s) { case XDS_OFF: return "OFF"; case XDS_SCANNING: return "SEARCHING"; case XDS_CONNECTING: return "CONNECTING";
                 case XDS_DISCOVERING: return "CONNECTING"; case XDS_SUBSCRIBED: return "CONNECTED"; case XDS_WAIT_RETRY: return "RECONNECTING"; }
    return "?";
}

void ble_xds_snapshot(xds_status_t *out) { LOCK(); *out = s_st; UNLOCK(); }

static int gap_event(struct ble_gap_event *ev, void *arg);
static void start_scan(void);

static void arm_timer(int kind, uint64_t ms) { s_timer_kind = kind; esp_timer_stop(s_timer); esp_timer_start_once(s_timer, ms * 1000); }

static void schedule_retry(void)
{
    set_state(XDS_WAIT_RETRY);
    arm_timer(T_RETRY, (uint64_t)s_backoff_s * 1000);
    s_backoff_s = s_backoff_s >= 16 ? 16 : s_backoff_s * 2;
}

/* ---- GATT: write CCCD → subscribed */
static int on_cccd_written(uint16_t conn, const struct ble_gatt_error *err, struct ble_gatt_attr *attr, void *arg)
{
    if (err->status == 0) { set_state(XDS_SUBSCRIBED); s_backoff_s = 1; ESP_LOGI(TAG, "subscribed to 0x2A63 (CCCD 0x%04x)", s_cccd); }
    else { ESP_LOGW(TAG, "CCCD write failed %d", err->status); ble_gap_terminate(conn, BLE_ERR_REM_USER_CONN_TERM); }
    return 0;
}

static int on_dsc(uint16_t conn, const struct ble_gatt_error *err, uint16_t chr_val_handle, const struct ble_gatt_dsc *dsc, void *arg)
{
    if (err->status == 0 && dsc && ble_uuid_cmp(&dsc->uuid.u, BLE_UUID16_DECLARE(BLE_GATT_DSC_CLT_CFG_UUID16)) == 0) s_cccd = dsc->handle;
    if (err->status == BLE_HS_EDONE) {
        if (!s_cccd) { ESP_LOGW(TAG, "0x2A63 has no CCCD"); ble_gap_terminate(conn, BLE_ERR_REM_USER_CONN_TERM); return 0; }
        static const uint8_t on[2] = { 0x01, 0x00 };   /* notifications on — the ONLY write to the meter */
        ble_gattc_write_flat(conn, s_cccd, on, sizeof on, on_cccd_written, NULL);
    }
    return 0;
}

static int on_chr(uint16_t conn, const struct ble_gatt_error *err, const struct ble_gatt_chr *chr, void *arg)
{
    if (err->status == 0 && chr) s_val_handle = chr->val_handle;
    if (err->status == BLE_HS_EDONE) {
        if (!s_val_handle) { ESP_LOGW(TAG, "0x2A63 not found"); ble_gap_terminate(conn, BLE_ERR_REM_USER_CONN_TERM); return 0; }
        ble_gattc_disc_all_dscs(conn, s_val_handle, s_svc_end, on_dsc, NULL);
    }
    return 0;
}

static int on_svc(uint16_t conn, const struct ble_gatt_error *err, const struct ble_gatt_svc *svc, void *arg)
{
    if (err->status == 0 && svc) { s_svc_start = svc->start_handle; s_svc_end = svc->end_handle; }
    if (err->status == BLE_HS_EDONE) {
        if (!s_svc_start) { ESP_LOGW(TAG, "service 0x1828 not found"); ble_gap_terminate(conn, BLE_ERR_REM_USER_CONN_TERM); return 0; }
        ble_gattc_disc_chrs_by_uuid(conn, s_svc_start, s_svc_end, BLE_UUID16_DECLARE(0x2A63), on_chr, NULL);
    }
    return 0;
}

static void start_discovery(void)
{
    if (s_disc_started || s_conn == BLE_HS_CONN_HANDLE_NONE) return;
    s_disc_started = true;
    set_state(XDS_DISCOVERING);
    ble_gattc_disc_svc_by_uuid(s_conn, BLE_UUID16_DECLARE(0x1828), on_svc, NULL);
}

static int on_mtu(uint16_t conn, const struct ble_gatt_error *err, uint16_t mtu, void *arg)
{
    ESP_LOGI(TAG, "MTU exchange: status %d, mtu %u", err->status, mtu);
    esp_timer_stop(s_timer);
    start_discovery();                       /* discovery only after the MTU exchange (PORTING_SPEC §2) */
    return 0;
}

static void timer_cb(void *arg)
{
    if (s_timer_kind == T_MTU_FALLBACK) { ESP_LOGW(TAG, "no MTU response in 2 s — discovering anyway"); start_discovery(); }
    else if (s_timer_kind == T_RETRY) start_scan();
}

/* ---- scanning */
static bool is_xds(const struct ble_hs_adv_fields *f)
{
    for (int i = 0; i < f->num_uuids16; i++) if (ble_uuid_u16(&f->uuids16[i].u) == 0x1828) return true;
    return f->name && f->name_len >= 3 && memcmp(f->name, "XDS", 3) == 0;
}

static void note_seen(const ble_addr_t *a)
{
    for (int i = 0; i < s_seen_n; i++) if (!memcmp(s_seen[i], a->val, 6)) return;
    if (s_seen_n < 32) memcpy(s_seen[s_seen_n++], a->val, 6);
    LOCK(); s_st.devices_seen++; UNLOCK();
}

static void start_scan(void)
{
    struct ble_gap_disc_params p = { .itvl = 0x50, .window = 0x30, .filter_duplicates = 0, .passive = 0 };
    s_conn = BLE_HS_CONN_HANDLE_NONE; s_svc_start = s_svc_end = s_val_handle = s_cccd = 0; s_disc_started = false;
    int rc = ble_gap_disc(s_own_addr_type, BLE_HS_FOREVER, &p, gap_event, NULL);
    if (rc == 0 || rc == BLE_HS_EALREADY) set_state(XDS_SCANNING);
    else { ESP_LOGE(TAG, "scan failed %d", rc); schedule_retry(); }
}

static int gap_event(struct ble_gap_event *ev, void *arg)
{
    switch (ev->type) {
    case BLE_GAP_EVENT_DISC: {
        note_seen(&ev->disc.addr);
        struct ble_hs_adv_fields f;
        if (ble_hs_adv_parse_fields(&f, ev->disc.data, ev->disc.length_data) != 0 || !is_xds(&f)) return 0;
        LOCK();
        memset(s_st.name, 0, sizeof s_st.name);
        if (f.name) memcpy(s_st.name, f.name, f.name_len < sizeof s_st.name - 1 ? f.name_len : sizeof s_st.name - 1);
        memcpy(s_st.mac, ev->disc.addr.val, 6); s_st.have_mac = true; s_st.rssi = ev->disc.rssi;
        UNLOCK();
        ESP_LOGI(TAG, "found %s rssi %d", f.name ? "XDS meter" : "0x1828 device", ev->disc.rssi);
        ble_gap_disc_cancel();
        set_state(XDS_CONNECTING);
        if (ble_gap_connect(s_own_addr_type, &ev->disc.addr, 10000, NULL, gap_event, NULL) != 0) schedule_retry();
        return 0;
    }
    case BLE_GAP_EVENT_CONNECT:
        if (ev->connect.status != 0) { ESP_LOGW(TAG, "connect failed %d", ev->connect.status); schedule_retry(); return 0; }
        s_conn = ev->connect.conn_handle;
        LOCK(); s_st.connects++; bc_xds_live_reset(&s_st.live); UNLOCK();
        ble_gattc_exchange_mtu(s_conn, on_mtu, NULL);
        arm_timer(T_MTU_FALLBACK, 2000);
        return 0;
    case BLE_GAP_EVENT_NOTIFY_RX:
        if (ev->notify_rx.attr_handle == s_val_handle) {
            uint8_t buf[32]; uint16_t n = OS_MBUF_PKTLEN(ev->notify_rx.om); if (n > sizeof buf) n = sizeof buf;
            os_mbuf_copydata(ev->notify_rx.om, 0, n, buf);
            uint32_t now = hw_millis();
            LOCK(); bc_xds_live_feed(&s_st.live, buf, n, now); UNLOCK();
        }
        return 0;
    case BLE_GAP_EVENT_DISCONNECT:
        ESP_LOGW(TAG, "disconnected, reason 0x%x", ev->disconnect.reason);
        LOCK(); s_st.disconnects++; s_st.last_disconnect_reason = ev->disconnect.reason; UNLOCK();
        s_conn = BLE_HS_CONN_HANDLE_NONE;
        schedule_retry();
        return 0;
    case BLE_GAP_EVENT_DISC_COMPLETE:
        return 0;
    default:
        return 0;
    }
}

static void on_sync(void)
{
    ble_hs_util_ensure_addr(0);
    ble_hs_id_infer_auto(0, &s_own_addr_type);
    start_scan();
}

static void on_reset(int reason) { ESP_LOGW(TAG, "host reset %d", reason); }
static void host_task(void *p) { nimble_port_run(); nimble_port_freertos_deinit(); }

void ble_xds_start(void)
{
    esp_timer_create_args_t ta = { .callback = timer_cb, .name = "xds" };
    ESP_ERROR_CHECK(esp_timer_create(&ta, &s_timer));
    ESP_ERROR_CHECK(nimble_port_init());
    ble_hs_cfg.sync_cb = on_sync;
    ble_hs_cfg.reset_cb = on_reset;
    ble_att_set_preferred_mtu(247);
    ble_svc_gap_device_name_set("BikeComputer");
    nimble_port_freertos_init(host_task);
}

/* RSSI of the live link, read on demand from the UI task (NimBLE calls are thread-safe). */
int ble_xds_link_rssi(void) { int8_t r = 0; if (s_conn != BLE_HS_CONN_HANDLE_NONE && ble_gap_conn_rssi(s_conn, &r) == 0) { LOCK(); s_st.rssi = r; UNLOCK(); } return r; }
