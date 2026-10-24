#include "ble_link.h"
#include <string.h>
#include "esp_log.h"
#include "esp_random.h"
#include "esp_app_desc.h"
#include "freertos/FreeRTOS.h"
#include "host/ble_hs.h"
#include "host/ble_store.h"
#include "host/util/util.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"
#include "bc_link.h"
#include "plat.h"
#include "hw.h"

static const char *TAG = "link";
static portMUX_TYPE s_mux = portMUX_INITIALIZER_UNLOCKED;
#define LOCK() portENTER_CRITICAL(&s_mux)
#define UNLOCK() portEXIT_CRITICAL(&s_mux)

/* B1CE0000-7E3A-4C55-9D2B-5A0E1C7C00xx (little-endian byte order for NimBLE) */
#define U(xx) BLE_UUID128_INIT(0x00, 0x00, 0x7C, 0x1C, 0x0E, 0x5A, 0x2B, 0x9D, 0x55, 0x4C, 0x3A, 0x7E, xx, 0x00, 0xCE, 0xB1)
static const ble_uuid128_t UUID_SVC = U(0x00), UUID_INFO = U(0x02), UUID_LIVE = U(0x03), UUID_INPUT = U(0x04), UUID_CTRL = U(0x05);
static const ble_uuid128_t UUID_SYNC = U(0x06), UUID_EVENTS = U(0x07);

static uint16_t h_info, h_live, h_input, h_ctrl, h_sync, h_events;
static uint16_t s_conn = BLE_HS_CONN_HANDLE_NONE;
static bool s_enabled, s_synced, s_adv, s_busy, s_encrypted, s_live_sub, s_ctrl_sub;
static uint8_t s_own;
static plat_phone_status_t s_st = { .phone_batt = 0xFF, .watch_batt = 0xFF, .last_rx_age_ms = UINT32_MAX };
static plat_phone_in_t s_in;
static uint32_t s_last_rx_ms;
static bc_ctrl_req_t s_ctrl; static bool s_ctrl_pending;
static uint8_t s_live_buf[BC_LINK_MAX]; static size_t s_live_len; static bool s_live_new;
static uint8_t s_resp_buf[BC_LINK_MAX]; static size_t s_resp_len; static bool s_resp_new;
static uint16_t s_seq;

static void set_state(plat_phone_state_t st) { LOCK(); s_st.state = st; UNLOCK(); }

static int count_bonds(void)
{
    int n = 0;
    ble_store_util_count(BLE_STORE_OBJ_TYPE_OUR_SEC, &n);
    return n;
}

/* ---- advertising */
static int gap_cb(struct ble_gap_event *ev, void *arg);
static void adv_start(void)
{
    if (s_adv || !s_enabled || !s_synced || s_busy || s_conn != BLE_HS_CONN_HANDLE_NONE) return;
    struct ble_hs_adv_fields f = { 0 }, sr = { 0 };
    f.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    f.uuids128 = (ble_uuid128_t *)&UUID_SVC; f.num_uuids128 = 1; f.uuids128_is_complete = 1;
    const char *name = ble_svc_gap_device_name();
    sr.name = (const uint8_t *)name; sr.name_len = (uint8_t)strlen(name); sr.name_is_complete = 1;
    int rc = ble_gap_adv_set_fields(&f);
    if (rc == 0) rc = ble_gap_adv_rsp_set_fields(&sr);
    struct ble_gap_adv_params p = { .conn_mode = BLE_GAP_CONN_MODE_UND, .disc_mode = BLE_GAP_DISC_MODE_GEN, .itvl_min = 0x140, .itvl_max = 0x200 };
    if (rc == 0) rc = ble_gap_adv_start(s_own, NULL, BLE_HS_FOREVER, &p, gap_cb, NULL);
    if (rc == 0 || rc == BLE_HS_EALREADY) { s_adv = true; set_state(PLAT_PHONE_ADVERTISING); }
    else ESP_LOGW(TAG, "advertising start failed %d", rc);
}
static void adv_stop(void) { if (s_adv) { ble_gap_adv_stop(); s_adv = false; } }

/* ---- GATT */
static int write_in(struct os_mbuf *om, uint8_t *buf, size_t cap)
{
    uint16_t n = OS_MBUF_PKTLEN(om); if (n > cap) return -1;
    os_mbuf_copydata(om, 0, n, buf);
    return n;
}

static void handle_input(const uint8_t *b, size_t n)
{
    uint32_t now = hw_millis();
    bool ok = false;
    LOCK();
    switch (n >= 1 ? b[0] : 0) {
    case BC_MSG_IN_GPS: { bc_in_gps_t v; if ((ok = bc_link_decode_gps(b, n, &v))) { s_in.gps.v = v; s_in.gps.rx_ms = now; } break; }
    case BC_MSG_IN_HR: { bc_in_hr_t v; if ((ok = bc_link_decode_hr(b, n, &v))) { s_in.hr.v = v; s_in.hr.rx_ms = now; } break; }
    case BC_MSG_IN_TIME: { bc_in_time_t v; if ((ok = bc_link_decode_time(b, n, &v))) { s_in.time.v = v; s_in.time.rx_ms = now; } break; }
    case BC_MSG_IN_WEATHER: { bc_in_weather_t v; if ((ok = bc_link_decode_weather(b, n, &v))) { s_in.weather.v = v; s_in.weather.rx_ms = now; } break; }
    case BC_MSG_IN_BATTERY: { bc_in_battery_t v; if ((ok = bc_link_decode_battery(b, n, &v))) { s_st.phone_batt = v.phone_pct; s_st.watch_batt = v.watch_pct; } break; }
    default: break;
    }
    if (ok) { s_st.rx_msgs++; s_last_rx_ms = now; } else s_st.rx_rejected++;
    UNLOCK();
}

static int chr_access(uint16_t conn, uint16_t attr, struct ble_gatt_access_ctxt *c, void *arg)
{
    uint8_t buf[BC_LINK_MAX];
    if (c->op == BLE_GATT_ACCESS_OP_READ_CHR) {
        if (attr == h_info) {
            bc_info_t i = { .ver_major = BC_LINK_VER_MAJOR, .ver_minor = BC_LINK_VER_MINOR, .caps = BC_CAP_LIVE | BC_CAP_GPS_IN | BC_CAP_HR_IN | BC_CAP_WEATHER_IN | BC_CAP_RIDE_CTRL | BC_CAP_TIME_SYNC, .max_msg = BC_LINK_MAX };
            snprintf(i.fw, sizeof i.fw, "%.23s", esp_app_get_description()->version);
            snprintf(i.name, sizeof i.name, "%.23s", ble_svc_gap_device_name());
            size_t n = bc_link_encode_info(&i, buf, sizeof buf);
            return os_mbuf_append(c->om, buf, n) == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
        }
        if (attr == h_live) { LOCK(); size_t n = s_live_len; memcpy(buf, s_live_buf, n); UNLOCK(); return os_mbuf_append(c->om, buf, n) == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES; }
        if (attr == h_ctrl) { LOCK(); size_t n = s_resp_len; memcpy(buf, s_resp_buf, n); UNLOCK(); return os_mbuf_append(c->om, buf, n) == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES; }
        return 0;   /* sync / events: empty until Phase 5 */
    }
    if (c->op == BLE_GATT_ACCESS_OP_WRITE_CHR) {
        int n = write_in(c->om, buf, sizeof buf);
        if (n < 0) { LOCK(); s_st.rx_rejected++; UNLOCK(); return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN; }
        if (attr == h_input) { handle_input(buf, (size_t)n); return 0; }
        if (attr == h_ctrl) {
            bc_ctrl_req_t q;
            LOCK();
            if (bc_link_decode_ctrl_req(buf, (size_t)n, &q)) { s_ctrl = q; s_ctrl_pending = true; s_st.rx_msgs++; s_last_rx_ms = hw_millis(); }
            else s_st.rx_rejected++;
            UNLOCK();
            return 0;
        }
        return BLE_ATT_ERR_WRITE_NOT_PERMITTED;
    }
    return BLE_ATT_ERR_UNLIKELY;
}

#define SEC_R (BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_READ_ENC | BLE_GATT_CHR_F_READ_AUTHEN)
#define SEC_W (BLE_GATT_CHR_F_WRITE_NO_RSP | BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_ENC | BLE_GATT_CHR_F_WRITE_AUTHEN)
static const struct ble_gatt_svc_def SVCS[] = {
    { .type = BLE_GATT_SVC_TYPE_PRIMARY, .uuid = &UUID_SVC.u,
      .characteristics = (struct ble_gatt_chr_def[]) {
          { .uuid = &UUID_INFO.u, .access_cb = chr_access, .flags = SEC_R, .val_handle = &h_info },
          { .uuid = &UUID_LIVE.u, .access_cb = chr_access, .flags = SEC_R | BLE_GATT_CHR_F_NOTIFY, .val_handle = &h_live },
          { .uuid = &UUID_INPUT.u, .access_cb = chr_access, .flags = SEC_W, .val_handle = &h_input },
          { .uuid = &UUID_CTRL.u, .access_cb = chr_access, .flags = SEC_R | SEC_W | BLE_GATT_CHR_F_NOTIFY, .val_handle = &h_ctrl },
          { .uuid = &UUID_SYNC.u, .access_cb = chr_access, .flags = SEC_R | SEC_W | BLE_GATT_CHR_F_NOTIFY, .val_handle = &h_sync },
          { .uuid = &UUID_EVENTS.u, .access_cb = chr_access, .flags = SEC_R | BLE_GATT_CHR_F_NOTIFY, .val_handle = &h_events },
          { 0 } } },
    { 0 },
};

void ble_link_register_gatt(void)
{
    ble_svc_gap_init();
    ble_svc_gatt_init();
    int rc = ble_gatts_count_cfg(SVCS);
    if (rc == 0) rc = ble_gatts_add_svcs(SVCS);
    ESP_LOGI(TAG, "GATT service registered (%d)", rc);
}

void ble_link_configure_security(void)
{
    ble_hs_cfg.sm_io_cap = BLE_SM_IO_CAP_DISP_ONLY;   /* we show a 6-digit code, the phone types it */
    ble_hs_cfg.sm_bonding = 1;
    ble_hs_cfg.sm_mitm = 1;
    ble_hs_cfg.sm_sc = 1;
    ble_hs_cfg.sm_our_key_dist = BLE_SM_PAIR_KEY_DIST_ENC | BLE_SM_PAIR_KEY_DIST_ID;
    ble_hs_cfg.sm_their_key_dist = BLE_SM_PAIR_KEY_DIST_ENC | BLE_SM_PAIR_KEY_DIST_ID;
}

static void on_disconnect(void)
{
    LOCK();
    s_conn = BLE_HS_CONN_HANDLE_NONE; s_encrypted = s_live_sub = s_ctrl_sub = false; s_st.passkey = 0; s_st.rssi = 0;
    s_live_new = s_resp_new = false;
    UNLOCK();
    set_state(s_enabled ? PLAT_PHONE_ADVERTISING : PLAT_PHONE_OFF);
    s_adv = false;
    adv_start();
}

static int gap_cb(struct ble_gap_event *ev, void *arg)
{
    switch (ev->type) {
    case BLE_GAP_EVENT_CONNECT:
        s_adv = false;
        if (ev->connect.status != 0) { adv_start(); return 0; }
        LOCK(); s_conn = ev->connect.conn_handle; s_st.connects++; UNLOCK();
        set_state(PLAT_PHONE_CONNECTED);
        ESP_LOGI(TAG, "phone connected");
        return 0;
    case BLE_GAP_EVENT_DISCONNECT:
        ESP_LOGI(TAG, "phone disconnected (0x%x)", ev->disconnect.reason);
        on_disconnect();
        return 0;
    case BLE_GAP_EVENT_ADV_COMPLETE:
        s_adv = false; adv_start();
        return 0;
    case BLE_GAP_EVENT_PASSKEY_ACTION:
        if (ev->passkey.params.action == BLE_SM_IOACT_DISP) {
            struct ble_sm_io io = { .action = BLE_SM_IOACT_DISP, .passkey = 100000 + esp_random() % 900000 };
            LOCK(); s_st.passkey = io.passkey; UNLOCK();
            set_state(PLAT_PHONE_PAIRING);
            ESP_LOGI(TAG, "pairing: code shown on screen");
            ble_sm_inject_io(ev->passkey.conn_handle, &io);
        } else if (ev->passkey.params.action == BLE_SM_IOACT_NUMCMP) {
            struct ble_sm_io io = { .action = BLE_SM_IOACT_NUMCMP, .numcmp_accept = 1 };
            LOCK(); s_st.passkey = ev->passkey.params.numcmp; UNLOCK();
            set_state(PLAT_PHONE_PAIRING);
            ble_sm_inject_io(ev->passkey.conn_handle, &io);
        }
        return 0;
    case BLE_GAP_EVENT_ENC_CHANGE: {
        struct ble_gap_conn_desc d;
        bool ok = ev->enc_change.status == 0 && ble_gap_conn_find(ev->enc_change.conn_handle, &d) == 0 && d.sec_state.encrypted && d.sec_state.authenticated;
        LOCK(); s_encrypted = ok; s_st.passkey = 0; s_st.bonded = count_bonds() > 0; UNLOCK();
        set_state(ok ? PLAT_PHONE_READY : PLAT_PHONE_CONNECTED);
        ESP_LOGI(TAG, "encryption %s (status %d, bonds %d)", ok ? "on" : "off", ev->enc_change.status, count_bonds());
        return 0;
    }
    case BLE_GAP_EVENT_REPEAT_PAIRING: {
        /* the phone forgot us but we remember it: drop our old bond and pair again */
        struct ble_gap_conn_desc d;
        if (ble_gap_conn_find(ev->repeat_pairing.conn_handle, &d) == 0) ble_store_util_delete_peer(&d.peer_id_addr);
        return BLE_GAP_REPEAT_PAIRING_RETRY;
    }
    case BLE_GAP_EVENT_SUBSCRIBE:
        LOCK();
        if (ev->subscribe.attr_handle == h_live) s_live_sub = ev->subscribe.cur_notify;
        if (ev->subscribe.attr_handle == h_ctrl) s_ctrl_sub = ev->subscribe.cur_notify;
        UNLOCK();
        return 0;
    case BLE_GAP_EVENT_MTU:
        ESP_LOGI(TAG, "phone MTU %u", ev->mtu.value);
        return 0;
    default:
        return 0;
    }
}

void ble_link_on_sync(uint8_t own) { s_own = own; s_synced = true; adv_start(); }

void ble_link_central_busy(bool busy)
{
    s_busy = busy;
    if (busy) adv_stop(); else adv_start();
}

void ble_link_tick(void)
{
    if (!s_synced) return;
    if (s_conn == BLE_HS_CONN_HANDLE_NONE) { adv_start(); return; }
    uint8_t buf[BC_LINK_MAX]; size_t n = 0; bool live = false, resp = false;
    LOCK();
    if (s_encrypted && s_live_sub && s_live_new) { n = s_live_len; memcpy(buf, s_live_buf, n); s_live_new = false; live = true; }
    UNLOCK();
    if (live && n) { struct os_mbuf *om = ble_hs_mbuf_from_flat(buf, (uint16_t)n); if (om && ble_gatts_notify_custom(s_conn, h_live, om) == 0) { LOCK(); s_st.tx_msgs++; UNLOCK(); } }
    LOCK();
    if (s_encrypted && s_ctrl_sub && s_resp_new) { n = s_resp_len; memcpy(buf, s_resp_buf, n); s_resp_new = false; resp = true; }
    UNLOCK();
    if (resp && n) { struct os_mbuf *om = ble_hs_mbuf_from_flat(buf, (uint16_t)n); if (om && ble_gatts_notify_custom(s_conn, h_ctrl, om) == 0) { LOCK(); s_st.tx_msgs++; UNLOCK(); } }
    static uint32_t t; uint32_t now = hw_millis();
    if (now - t > 2000) { t = now; int8_t r; if (ble_gap_conn_rssi(s_conn, &r) == 0) { LOCK(); s_st.rssi = r; UNLOCK(); } }
}

/* ---- plat API (UI task) */
void plat_phone_set_enabled(bool on)
{
    s_enabled = on;
    if (!on) { adv_stop(); if (s_conn != BLE_HS_CONN_HANDLE_NONE) ble_gap_terminate(s_conn, BLE_ERR_REM_USER_CONN_TERM); set_state(PLAT_PHONE_OFF); }
    else if (s_conn == BLE_HS_CONN_HANDLE_NONE) set_state(PLAT_PHONE_ADVERTISING);   /* the manager task starts advertising */
}

void plat_phone_status(plat_phone_status_t *o)
{
    LOCK();
    *o = s_st;
    o->last_rx_age_ms = s_last_rx_ms ? hw_millis() - s_last_rx_ms : UINT32_MAX;
    UNLOCK();
    if (!s_enabled) o->state = PLAT_PHONE_OFF;
    if (o->state == PLAT_PHONE_OFF || o->state == PLAT_PHONE_ADVERTISING) o->bonded = count_bonds() > 0;
}

void plat_phone_forget(void)
{
    if (s_conn != BLE_HS_CONN_HANDLE_NONE) ble_gap_terminate(s_conn, BLE_ERR_REM_USER_CONN_TERM);
    ble_store_clear();
    LOCK(); s_st.bonded = false; UNLOCK();
    ESP_LOGI(TAG, "all remembered phones forgotten");
}

void plat_phone_disconnect(void) { if (s_conn != BLE_HS_CONN_HANDLE_NONE) ble_gap_terminate(s_conn, BLE_ERR_REM_USER_CONN_TERM); }

void plat_phone_inputs(plat_phone_in_t *o) { LOCK(); *o = s_in; UNLOCK(); }

bool plat_phone_take_ctrl(bc_ctrl_req_t *o)
{
    bool have;
    LOCK(); have = s_ctrl_pending; if (have) { *o = s_ctrl; s_ctrl_pending = false; } UNLOCK();
    return have;
}

void plat_phone_ctrl_respond(const bc_ctrl_resp_t *r)
{
    uint8_t buf[BC_LINK_MAX];
    size_t n = bc_link_encode_ctrl_resp(r, buf, sizeof buf, ++s_seq, hw_millis());
    LOCK(); memcpy(s_resp_buf, buf, n); s_resp_len = n; s_resp_new = n > 0; UNLOCK();
}

void plat_phone_publish_live(const bc_live_t *l)
{
    uint8_t buf[BC_LINK_MAX];
    size_t n = bc_link_encode_live(l, buf, sizeof buf, ++s_seq, hw_millis());
    LOCK(); memcpy(s_live_buf, buf, n); s_live_len = n; s_live_new = n > 0; UNLOCK();
}
