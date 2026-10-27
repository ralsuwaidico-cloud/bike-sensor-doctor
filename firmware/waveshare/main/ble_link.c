#include "ble_link.h"
#include "ble_central.h"
#include <string.h>
#include "esp_log.h"
#include "esp_random.h"   /* esp_random, esp_fill_random */
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
#include "app_psvc.h"
#include "nvs.h"

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
static bool s_standby, s_sync_sub, s_events_sub;
/* 0.7.0 identity: a random static address stored in NVS ("link"/"idaddr"); a new one on every forget/repair so a phone that
   kept old keys sees a brand-new device instead of failing to encrypt forever. plat_device_id (INFO tag 07) stays the
   factory Bluetooth MAC, so the phone's records stay keyed to the same board. */
static uint8_t s_id_addr[6]; static uint8_t s_id_gen; static bool s_id_random;
static bool s_repair_pending;        /* forget/repair asked from the UI task: done on the host task in ble_link_tick */
/* 0.7.3: every other UI request is a flag too; ble_link_tick (host task) applies it — no NimBLE call from the UI task */
static volatile bool s_req_apply_enabled, s_req_disconnect, s_req_standby_changed;
static uint8_t s_enc_fail_streak;   /* s_events_sub: 0.6.0 Events characteristic (chr 2 in plat_phone_notify_svc) */
/* 0.6.0 phone services: writes from the phone wait here for the app task (app_psvc_pump); replies wait here for the BLE task */
typedef struct { uint8_t chr, len, tries, b[BC_LINK_MAX]; } svc_msg_t;
#define SVC_Q 12
static svc_msg_t s_svc_in[SVC_Q]; static int s_svc_in_n;
static svc_msg_t s_svc_out[SVC_Q]; static int s_svc_out_n;
static uint32_t s_svc_dropped;
static uint8_t s_sync_end[32]; static size_t s_sync_end_len;
/* 0.7.3 Link 1.2.3: the negotiated ATT MTU of the phone connection (chunk sizing) and notify back-pressure (ride priority) */
static uint16_t s_mtu;
static uint32_t s_notify_fail_ms; static bool s_notify_failed;
#define BULK_MIN_FREE_MBUFS 4        /* of CONFIG_BT_NIMBLE_MSYS_1_BLOCK_COUNT 12: diag chunks never take the last ones */
#define BULK_FAIL_QUIET_MS 500u      /* no bulk traffic for 0.5 s after NimBLE refused a notification */
#define SVC_MAX_TRIES 30             /* a refused service notification is retried for ~3 s (100 ms ticks), then dropped */

static void set_state(plat_phone_state_t st) { LOCK(); s_st.state = st; UNLOCK(); }

static int count_bonds(void)
{
    int n = 0;
    if (!s_synced) return s_st.bonds;                /* 0.7.3: NimBLE not running (recovery mode, early boot report): last known */
    ble_store_util_count(BLE_STORE_OBJ_TYPE_OUR_SEC, &n);
    return n;
}

/* ---- 0.7.0 identity address (random static, persisted) */
static bool id_load(uint8_t addr[6], uint8_t *gen)
{
    nvs_handle_t h; size_t n = 6; bool ok = false;
    if (nvs_open("link", NVS_READONLY, &h) != ESP_OK) return false;
    if (nvs_get_blob(h, "idaddr", addr, &n) == ESP_OK && n == 6) { ok = true; if (nvs_get_u8(h, "idgen", gen) != ESP_OK) *gen = 1; }
    nvs_close(h);
    return ok;
}
static void id_save(const uint8_t addr[6], uint8_t gen)
{
    nvs_handle_t h;
    if (nvs_open("link", NVS_READWRITE, &h) != ESP_OK) return;
    nvs_set_blob(h, "idaddr", addr, 6); nvs_set_u8(h, "idgen", gen); nvs_commit(h); nvs_close(h);
}
static void id_generate(uint8_t addr[6])
{
    ble_addr_t a;
    if (ble_hs_id_gen_rnd(0, &a) == 0) memcpy(addr, a.val, 6);              /* random STATIC (top two bits 11) */
    else { esp_fill_random(addr, 6); addr[5] |= 0xC0; }
}
/* applies the stored (or a fresh) identity; must run with no advertising/connection in flight. Returns the own-addr type. */
static uint8_t id_apply(bool fresh)
{
    uint8_t gen = s_id_gen;
    if (fresh || !id_load(s_id_addr, &gen)) { id_generate(s_id_addr); gen = (uint8_t)(gen + 1); if (!gen) gen = 1; id_save(s_id_addr, gen); }
    s_id_gen = gen;
    int rc = ble_hs_id_set_rnd(s_id_addr);
    s_id_random = rc == 0;
    ESP_LOGI(TAG, "identity %s ..:%02X:%02X gen %u (rc %d)", s_id_random ? "random-static" : "PUBLIC (fallback)",
             s_id_addr[1], s_id_addr[0], s_id_gen, rc);   /* 0.7.3: addresses in logs are cut to their last 2 bytes */
    LOCK(); memcpy(s_st.id_addr, s_id_random ? s_id_addr : (uint8_t[6]){0}, 6); s_st.id_gen = s_id_gen; UNLOCK();
    return s_id_random ? BLE_OWN_ADDR_RANDOM : s_own;
}
static plat_phone_disc_t disc_map(uint16_t code)
{
    switch (code & 0xFF) {
    case 0x13: return PLAT_PHONE_DISC_PHONE_ENDED;       /* remote user terminated */
    case 0x16: return PLAT_PHONE_DISC_BOARD_ENDED;       /* local host terminated */
    case 0x08: case 0x22: return PLAT_PHONE_DISC_TIMEOUT;/* supervision / LMP response timeout */
    case 0x06: return PLAT_PHONE_DISC_KEY_MISSING;       /* PIN or key missing: the other side has no (matching) bond */
    case 0x05: return PLAT_PHONE_DISC_AUTH_FAILED;
    case 0x3E: return PLAT_PHONE_DISC_FAILED_TO_ESTABLISH;
    default: return code ? PLAT_PHONE_DISC_OTHER : PLAT_PHONE_DISC_NONE;
    }
}

/* ---- advertising */
static int gap_cb(struct ble_gap_event *ev, void *arg);
static void adv_start(void)
{
    if (s_adv || !s_enabled || !s_synced || s_busy || s_repair_pending || s_conn != BLE_HS_CONN_HANDLE_NONE) return;
    struct ble_hs_adv_fields f = { 0 }, sr = { 0 };
    f.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    f.uuids128 = (ble_uuid128_t *)&UUID_SVC; f.num_uuids128 = 1; f.uuids128_is_complete = 1;
    const char *name = ble_svc_gap_device_name();
    sr.name = (const uint8_t *)name; sr.name_len = (uint8_t)strlen(name); sr.name_is_complete = 1;
    int rc = ble_gap_adv_set_fields(&f);
    if (rc == 0) rc = ble_gap_adv_rsp_set_fields(&sr);
    /* active: 200-320 ms; connected standby: ~1 s (the bonded phone still finds us without any touch, at a fraction of the power) */
    struct ble_gap_adv_params p = { .conn_mode = BLE_GAP_CONN_MODE_UND, .disc_mode = BLE_GAP_DISC_MODE_GEN,
                                    .itvl_min = s_standby ? 0x0640 : 0x140, .itvl_max = s_standby ? 0x0700 : 0x200 };
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
            bc_info_t i = { .ver_major = BC_LINK_VER_MAJOR, .ver_minor = BC_LINK_VER_MINOR,
                            .caps = BC_CAP_LIVE | BC_CAP_GPS_IN | BC_CAP_HR_IN | BC_CAP_WEATHER_IN | BC_CAP_RIDE_CTRL | BC_CAP_TIME_SYNC |
                                    BC_CAP_RIDE_SYNC | BC_CAP_WIFI_PROV | BC_CAP_PROFILE_SYNC | BC_CAP_SETTINGS | BC_CAP_DIAG_XFER,
                            .max_msg = BC_LINK_MAX };
            snprintf(i.fw, sizeof i.fw, "%.23s", esp_app_get_description()->version);
            snprintf(i.name, sizeof i.name, "%.23s", ble_svc_gap_device_name());
            i.has_device_id = plat_device_id(i.device_id);
            size_t n = bc_link_encode_info(&i, buf, sizeof buf);
            return os_mbuf_append(c->om, buf, n) == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
        }
        if (attr == h_live) { LOCK(); size_t n = s_live_len; memcpy(buf, s_live_buf, n); UNLOCK(); return os_mbuf_append(c->om, buf, n) == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES; }
        if (attr == h_ctrl) { LOCK(); size_t n = s_resp_len; memcpy(buf, s_resp_buf, n); UNLOCK(); return os_mbuf_append(c->om, buf, n) == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES; }
        if (attr == h_sync) { LOCK(); size_t n = s_sync_end_len; memcpy(buf, s_sync_end, n); UNLOCK(); return os_mbuf_append(c->om, buf, n) == 0 ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES; }   /* last SYNC_END */
        return 0;   /* events: reserved */
    }
    if (c->op == BLE_GATT_ACCESS_OP_WRITE_CHR) {
        int n = write_in(c->om, buf, sizeof buf);
        if (n < 0) { LOCK(); s_st.rx_rejected++; UNLOCK(); return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN; }
        if (attr == h_input) { handle_input(buf, (size_t)n); return 0; }
        if (attr == h_ctrl && n >= 1 && buf[0] == BC_MSG_CTRL_REQ) {
            bc_ctrl_req_t q;
            LOCK();
            if (bc_link_decode_ctrl_req(buf, (size_t)n, &q)) { s_ctrl = q; s_ctrl_pending = true; s_st.rx_msgs++; s_last_rx_ms = hw_millis(); }
            else s_st.rx_rejected++;
            UNLOCK();
            return 0;
        }
        if (attr == h_ctrl || attr == h_sync) {
            /* 0.6.0 phone services (Wi-Fi provisioning, profile/settings, ride-history sync): encrypted links only; the app task
               decodes and applies them (app_psvc) — nothing is parsed here beyond the type byte */
            if (!s_encrypted) { LOCK(); s_st.rx_rejected++; UNLOCK(); return BLE_ATT_ERR_INSUFFICIENT_AUTHEN; }
            if (n < BC_LINK_HDR || n > BC_LINK_MAX) { LOCK(); s_st.rx_rejected++; UNLOCK(); return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN; }
            LOCK();
            if (s_svc_in_n < SVC_Q) { svc_msg_t *m = &s_svc_in[s_svc_in_n++]; m->chr = attr == h_sync ? 1 : 0; m->len = (uint8_t)n; memcpy(m->b, buf, (size_t)n); s_st.rx_msgs++; s_last_rx_ms = hw_millis(); }
            else { s_svc_dropped++; s_st.rx_rejected++; }
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

static void on_disconnect(uint16_t reason)
{
    bool was_repair = s_st.state == PLAT_PHONE_REPAIR;
    int bonds = count_bonds();                        /* 0.7.3: NimBLE's host lock is never taken inside our spinlock */
    LOCK();
    s_conn = BLE_HS_CONN_HANDLE_NONE; s_encrypted = s_live_sub = s_ctrl_sub = s_sync_sub = s_events_sub = false; s_st.passkey = 0; s_st.rssi = 0;
    s_live_new = s_resp_new = false; s_svc_in_n = 0; s_svc_out_n = 0; s_st.svc_ready = false; s_mtu = 0; s_st.att_mtu = 0; s_notify_failed = false;
    s_st.last_disc_code = reason; s_st.last_disc = disc_map(reason); s_st.bonds = (uint8_t)bonds; s_st.bonded = bonds > 0;
    UNLOCK();
    app_psvc_on_disconnect();
    /* a failed encryption keeps the REPAIR state visible after the phone drops the link; it clears on the next good connection */
    set_state(was_repair || s_st.last_disc == PLAT_PHONE_DISC_KEY_MISSING || s_st.last_disc == PLAT_PHONE_DISC_AUTH_FAILED ? PLAT_PHONE_REPAIR
              : s_enabled ? PLAT_PHONE_ADVERTISING : PLAT_PHONE_OFF);
    s_adv = false;
    adv_start();
}

static int gap_cb(struct ble_gap_event *ev, void *arg)
{
    switch (ev->type) {
    case BLE_GAP_EVENT_CONNECT:
        s_adv = false;
        if (ev->connect.status != 0) { adv_start(); return 0; }
        { int bonds = count_bonds();                  /* 0.7.3: outside the spinlock (0.7.0-0.7.2 called it inside: NimBLE host lock under portENTER_CRITICAL) */
          uint16_t mtu = ble_att_mtu(ev->connect.conn_handle);   /* 23 until the phone's MTU exchange */
          LOCK(); s_conn = ev->connect.conn_handle; s_st.connects++; s_st.bonds = (uint8_t)bonds; s_mtu = mtu; s_st.att_mtu = mtu; UNLOCK(); }
        set_state(PLAT_PHONE_CONNECTED);
        { struct ble_gap_conn_desc d; if (ble_gap_conn_find(ev->connect.conn_handle, &d) == 0)
            ESP_LOGI(TAG, "phone connected: peer %s ..:%02X:%02X, bonds %d, itvl %u, our identity gen %u", d.peer_id_addr.type ? "random" : "public",
                     d.peer_id_addr.val[1], d.peer_id_addr.val[0], count_bonds(), d.conn_itvl, s_id_gen); }
        return 0;
    case BLE_GAP_EVENT_DISCONNECT:
        ESP_LOGI(TAG, "phone disconnected: reason 0x%x (%s), bonds %d", ev->disconnect.reason,
                 (const char *[]){"-", "phone ended it", "board ended it", "timeout / out of range", "key missing on one side", "authentication failed", "failed to establish", "other"}[disc_map(ev->disconnect.reason)],
                 count_bonds());
        on_disconnect(ev->disconnect.reason);
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
        int bonds = count_bonds();
        LOCK(); s_encrypted = ok; s_st.passkey = 0; s_st.bonds = (uint8_t)bonds; s_st.bonded = bonds > 0; if (!ok) s_st.enc_fails++; UNLOCK();
        if (ok) { s_enc_fail_streak = 0; set_state(PLAT_PHONE_READY); }
        else {
            /* status 0x206 = "PIN or key missing": the phone asked for encryption with keys this board does not hold any more
               (iOS shows "Peer removed pairing information"); 0x205 = authentication failed. Both mean: pair again. */
            s_enc_fail_streak++;
            LOCK(); s_st.last_disc_code = (uint16_t)ev->enc_change.status; s_st.last_disc = disc_map((uint16_t)ev->enc_change.status); UNLOCK();
            set_state(PLAT_PHONE_REPAIR);
        }
        ESP_LOGI(TAG, "encryption %s (status 0x%x%s, bonds %d, authenticated %d)", ok ? "ON" : "FAILED", ev->enc_change.status,
                 (ev->enc_change.status & 0xFF) == 0x06 ? " = key missing: the phone kept old keys" : (ev->enc_change.status & 0xFF) == 0x05 ? " = authentication failed" : "",
                 bonds, ok ? d.sec_state.authenticated : 0);
        return 0;
    }
    case BLE_GAP_EVENT_REPEAT_PAIRING: {
        /* the phone forgot us but we remember it: drop our old bond for this peer and let it pair again (no identity change:
           the phone has no stale keys in this direction) */
        struct ble_gap_conn_desc d;
        if (ble_gap_conn_find(ev->repeat_pairing.conn_handle, &d) == 0) { ble_store_util_delete_peer(&d.peer_id_addr); ESP_LOGI(TAG, "repeat pairing: old bond for this phone dropped, pairing again"); }
        { int bonds = count_bonds(); LOCK(); s_st.bonds = (uint8_t)bonds; UNLOCK(); }
        return BLE_GAP_REPEAT_PAIRING_RETRY;
    }
    case BLE_GAP_EVENT_SUBSCRIBE:
        LOCK();
        if (ev->subscribe.attr_handle == h_live) s_live_sub = ev->subscribe.cur_notify;
        if (ev->subscribe.attr_handle == h_ctrl) s_ctrl_sub = ev->subscribe.cur_notify;
        if (ev->subscribe.attr_handle == h_sync) s_sync_sub = ev->subscribe.cur_notify;
        if (ev->subscribe.attr_handle == h_events) s_events_sub = ev->subscribe.cur_notify;
        s_st.svc_ready = s_encrypted && s_ctrl_sub;
        UNLOCK();
        ESP_LOGI(TAG, "subscribe: live %d ctrl %d sync %d events %d", s_live_sub, s_ctrl_sub, s_sync_sub, s_events_sub);
        return 0;
    case BLE_GAP_EVENT_MTU:
        ESP_LOGI(TAG, "phone MTU %u", ev->mtu.value);
        if (ev->mtu.conn_handle == s_conn) { LOCK(); s_mtu = ev->mtu.value; s_st.att_mtu = ev->mtu.value; UNLOCK(); }   /* diag chunk sizing */
        return 0;
    default:
        return 0;
    }
}

uint8_t ble_link_on_sync(uint8_t own)
{
    s_own = own;
    s_own = id_apply(false);          /* stored identity, or a first one on a fresh board */
    s_synced = true;
    adv_start();
    return s_own;
}

/* forget / repair run here (host task): stop radio activity, wipe bonds, new identity, advertise again */
static void do_repair(void)
{
    adv_stop();
    if (s_conn != BLE_HS_CONN_HANDLE_NONE) { ble_gap_terminate(s_conn, BLE_ERR_REM_USER_CONN_TERM); return; }   /* finish after the disconnect event */
    ble_store_clear();
    s_own = id_apply(true);
    s_repair_pending = false; s_enc_fail_streak = 0;
    LOCK(); s_st.bonds = 0; s_st.bonded = false; s_st.enc_fails = 0; UNLOCK();
    set_state(s_enabled ? PLAT_PHONE_ADVERTISING : PLAT_PHONE_OFF);
    ESP_LOGI(TAG, "repair: bonds wiped, new identity gen %u, advertising again", s_id_gen);
    adv_start();
}

void ble_link_central_busy(bool busy)
{
    s_busy = busy;
    if (busy) adv_stop(); else adv_start();
}

void ble_link_tick(void)
{
    if (!s_synced) return;
    if (s_req_apply_enabled) {
        s_req_apply_enabled = false;
        if (!s_enabled) { adv_stop(); if (s_conn != BLE_HS_CONN_HANDLE_NONE) ble_gap_terminate(s_conn, BLE_ERR_REM_USER_CONN_TERM); }
    }
    if (s_req_disconnect) { s_req_disconnect = false; if (s_conn != BLE_HS_CONN_HANDLE_NONE) ble_gap_terminate(s_conn, BLE_ERR_REM_USER_CONN_TERM); }
    if (s_req_standby_changed) { s_req_standby_changed = false; if (s_adv) { adv_stop(); adv_start(); } }
    if (s_repair_pending) { do_repair(); if (s_repair_pending) return; }
    if (s_conn == BLE_HS_CONN_HANDLE_NONE) { adv_start(); return; }
    uint8_t buf[BC_LINK_MAX]; size_t n = 0; bool live = false, resp = false;
    LOCK();
    if (s_encrypted && s_live_sub && s_live_new) { n = s_live_len; memcpy(buf, s_live_buf, n); s_live_new = false; live = true; }
    UNLOCK();
    uint32_t now = hw_millis();
    { uint16_t m = ble_att_mtu(s_conn); if (m && m != s_mtu) { LOCK(); s_mtu = m; s_st.att_mtu = m; UNLOCK(); } }   /* never miss the exchange */
    if (live && n) {
        struct os_mbuf *om = ble_hs_mbuf_from_flat(buf, (uint16_t)n);
        if (om && ble_gatts_notify_custom(s_conn, h_live, om) == 0) { LOCK(); s_st.tx_msgs++; UNLOCK(); }
        else { LOCK(); if (!s_live_new) s_live_new = true; s_st.notify_fails++; s_notify_failed = true; s_notify_fail_ms = now; UNLOCK(); }   /* 0.7.3: retried next tick */
    }
    LOCK();
    if (s_encrypted && s_ctrl_sub && s_resp_new) { n = s_resp_len; memcpy(buf, s_resp_buf, n); s_resp_new = false; resp = true; }
    UNLOCK();
    if (resp && n) {
        struct os_mbuf *om = ble_hs_mbuf_from_flat(buf, (uint16_t)n);
        if (om && ble_gatts_notify_custom(s_conn, h_ctrl, om) == 0) { LOCK(); s_st.tx_msgs++; UNLOCK(); }
        else { LOCK(); if (!s_resp_new) s_resp_new = true; s_st.notify_fails++; s_notify_failed = true; s_notify_fail_ms = now; UNLOCK(); }
    }
    /* phone-service replies: all that are queued, each on its characteristic (subscribed or not: a read of Sync returns the last END) */
    for (int guard = 0; guard < SVC_Q; guard++) {
        svc_msg_t m; bool have = false;
        LOCK();
        if (s_svc_out_n && s_encrypted) { m = s_svc_out[0]; s_svc_out_n--; memmove(&s_svc_out[0], &s_svc_out[1], sizeof m * (size_t)s_svc_out_n); have = true; }
        else if (s_svc_out_n) s_svc_out_n = 0;
        UNLOCK();
        if (!have) break;
        bool sub = m.chr == 2 ? s_events_sub : m.chr ? s_sync_sub : s_ctrl_sub;
        if (!sub) continue;
        struct os_mbuf *om = ble_hs_mbuf_from_flat(m.b, m.len);
        if (om && ble_gatts_notify_custom(s_conn, m.chr == 2 ? h_events : m.chr ? h_sync : h_ctrl, om) == 0) { LOCK(); s_st.tx_msgs++; UNLOCK(); continue; }
        /* 0.7.3: NimBLE refused it (no mbuf / controller queue full; it freed `om`): put it back at the head and stop for
           this tick — 0.6.0-0.7.2 dropped it, so a pulled report chunk could vanish under load */
        LOCK();
        s_notify_failed = true; s_notify_fail_ms = now; s_st.notify_fails++;
        if (++m.tries < SVC_MAX_TRIES && s_svc_out_n < SVC_Q) { memmove(&s_svc_out[1], &s_svc_out[0], sizeof m * (size_t)s_svc_out_n); s_svc_out[0] = m; s_svc_out_n++; }
        else s_svc_dropped++;
        UNLOCK();
        break;
    }
    static uint32_t t;
    if (now - t > 2000) { t = now; int8_t r; if (ble_gap_conn_rssi(s_conn, &r) == 0) { LOCK(); s_st.rssi = r; UNLOCK(); } }
}

/* ---- plat API (UI task) */
void plat_phone_set_enabled(bool on)
{
    s_enabled = on;
    s_req_apply_enabled = true;                       /* advertising stop / disconnect happen on the host task (ble_link_tick) */
    if (!on) set_state(PLAT_PHONE_OFF);
    else if (s_conn == BLE_HS_CONN_HANDLE_NONE) set_state(PLAT_PHONE_ADVERTISING);   /* the host task starts advertising */
}

void plat_phone_status(plat_phone_status_t *o)
{
    LOCK();
    *o = s_st;
    o->last_rx_age_ms = s_last_rx_ms ? hw_millis() - s_last_rx_ms : UINT32_MAX;
    UNLOCK();
    if (!s_enabled) o->state = PLAT_PHONE_OFF;
    if (o->state == PLAT_PHONE_OFF || o->state == PLAT_PHONE_ADVERTISING) { o->bonds = (uint8_t)count_bonds(); o->bonded = o->bonds > 0; }
    if (s_repair_pending) o->state = PLAT_PHONE_REPAIR;
    if (plat_bt_unavailable(NULL, 0)) o->state = PLAT_PHONE_UNAVAILABLE;   /* 0.7.4: never "searching" when there is no radio */
}

/* UI task: only a flag; the host task does the work (no Bluetooth call from the UI task) */
void plat_phone_forget(void) { s_repair_pending = true; ESP_LOGI(TAG, "forget requested: wiping remembered phones and taking a new identity"); }
void plat_phone_repair(void) { s_enabled = true; s_repair_pending = true; ESP_LOGI(TAG, "repair requested"); }

void plat_phone_disconnect(void) { s_req_disconnect = true; }   /* host task: ble_link_tick */

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

int plat_phone_take_svc(uint8_t *chr, uint8_t *buf, size_t cap)
{
    int n = 0;
    LOCK();
    if (s_svc_in_n) { svc_msg_t *m = &s_svc_in[0]; n = m->len <= cap ? m->len : (int)cap; *chr = m->chr; memcpy(buf, m->b, (size_t)n); s_svc_in_n--; memmove(&s_svc_in[0], &s_svc_in[1], sizeof *m * (size_t)s_svc_in_n); }
    UNLOCK();
    return n;
}

bool plat_phone_notify_svc(uint8_t chr, const uint8_t *buf, size_t n)
{
    if (n == 0 || n > BC_LINK_MAX) return true;                      /* nothing to send */
    bool ok;
    LOCK();
    if (chr == 1 && buf[0] == BC_MSG_SYNC_END && n <= sizeof s_sync_end) { memcpy(s_sync_end, buf, n); s_sync_end_len = n; }
    if (s_conn == BLE_HS_CONN_HANDLE_NONE || !s_encrypted) ok = true;  /* nobody to notify: dropped, like the radio would */
    else if (s_svc_out_n < SVC_Q) { svc_msg_t *m = &s_svc_out[s_svc_out_n++]; m->chr = chr; m->len = (uint8_t)n; m->tries = 0; memcpy(m->b, buf, n); ok = true; }
    else ok = false;
    UNLOCK();
    return ok;
}

bool plat_phone_bulk_room(void)
{
    uint32_t now = hw_millis();
    LOCK();
    bool ok = s_conn != BLE_HS_CONN_HANDLE_NONE && s_encrypted && s_ctrl_sub && !s_live_new && !s_resp_new && s_svc_out_n == 0 &&
              !(s_notify_failed && now - s_notify_fail_ms < BULK_FAIL_QUIET_MS);
    UNLOCK();
    return ok && os_msys_num_free() >= BULK_MIN_FREE_MBUFS;     /* a plain counter read: no host lock */
}

void plat_phone_set_standby(bool standby)
{
    if (s_standby == standby) return;
    s_standby = standby;
    /* restart advertising with the new interval when nobody is connected (connections are untouched) — on the host task */
    s_req_standby_changed = true;
}

void plat_phone_publish_live(const bc_live_t *l)
{
    uint8_t buf[BC_LINK_MAX];
    size_t n = bc_link_encode_live(l, buf, sizeof buf, ++s_seq, hw_millis());
    LOCK(); memcpy(s_live_buf, buf, n); s_live_len = n; s_live_new = n > 0; UNLOCK();
}
