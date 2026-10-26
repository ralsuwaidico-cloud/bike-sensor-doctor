/*
 * Wi-Fi manager (0.3.0, reworked in 0.6.0 — see docs/WIFI_0.6.0.md). Optional: nothing on the device needs a network.
 *
 * 0.6.0 changes (hotspot investigation): longer scan dwell (120/300 ms) over channels 1-13 (country AE), 32 scan records,
 * WPA2 threshold + PMF capable for iPhone WPA2/WPA3 hotspots, an internet check (DNS) after the address, reconnection
 * backoff 5 -> 60 s that stops after 10 failed rounds until the rider rescans, "save only" for phone provisioning, and the
 * channel of every network for the phone's list. Credentials never appear in logs.
 *
 * All radio work happens in one background task ("wifi_mgr", core 0). The UI only posts commands to a queue and reads
 * a status snapshot, so the screen never waits for Wi-Fi. Rules:
 *  - station mode only; 2.4 GHz (the ESP32-S3 has no 5 GHz radio); WPA/WPA2/WPA3-personal and open networks;
 *  - saved networks (max 5) live in NVS namespace "wifi", never shown on screen and never written to any log;
 *  - when on, it joins the strongest saved network in range and retries after 5, 10, 30, 60 s;
 *  - during a ride (plat_wifi_set_quiet) it never scans or retries on its own, so the Bluetooth power meter, coaching
 *    and recording get the radio; an existing connection is simply kept;
 *  - power save stays on (modem sleep) as required for Wi-Fi + Bluetooth coexistence.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "esp_log.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "lwip/netdb.h"
#include "lwip/sockets.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "freertos/event_groups.h"
#include "nvs.h"
#include "esp_heap_caps.h"
#include "plat.h"
#include "bc_wifi.h"
#include "hw.h"

static const char *TAG = "wifi";
static portMUX_TYPE s_mux = portMUX_INITIALIZER_UNLOCKED;
#define LOCK() portENTER_CRITICAL(&s_mux)
#define UNLOCK() portEXIT_CRITICAL(&s_mux)

typedef enum { CMD_ENABLE, CMD_DISABLE, CMD_SCAN, CMD_CONNECT, CMD_DISCONNECT, CMD_FORGET, CMD_SAVE } cmd_kind_t;
typedef struct { cmd_kind_t k; char ssid[33]; char pass[65]; bool has_pass, save; } cmd_t;

#define BIT_GOT_IP BIT0
#define BIT_DISCONNECTED BIT1

static QueueHandle_t s_q;
static EventGroupHandle_t s_eg;
static esp_netif_t *s_netif;
static bool s_radio_init, s_radio_on, s_enabled, s_user_off, s_associated, s_expect_disc;
static volatile bool s_quiet;
static volatile int s_last_reason;
static bc_wifi_store_t s_store;                 /* task-only */
static plat_wifi_status_t s_st;                 /* under LOCK */
static plat_wifi_ap_t s_aps[32]; static int s_naps;
#define AUTO_MAX_ROUNDS 10
static bool s_auto_halted;                      /* 10 failed reconnection rounds: wait for the rider (Rescan / page / connect) */
static char s_saved[PLAT_WIFI_MAX_SAVED][33]; static int s_nsaved;
static int s_scan_count = -1;
static unsigned s_attempt; static uint32_t s_next_auto_ms;

/* ---- persistence */
static void store_load(void)
{
    nvs_handle_t h; unsigned char buf[512]; size_t n = sizeof buf;
    bc_wifi_store_init(&s_store);
    if (nvs_open("wifi", NVS_READONLY, &h) == ESP_OK) {
        if (nvs_get_blob(h, "nets", buf, &n) == ESP_OK) bc_wifi_store_unpack(&s_store, buf, n);
        nvs_close(h);
    }
    memset(buf, 0, sizeof buf);
}

static void store_save(void)
{
    nvs_handle_t h; unsigned char buf[512];
    size_t n = bc_wifi_store_pack(&s_store, buf, sizeof buf);
    if (n && nvs_open("wifi", NVS_READWRITE, &h) == ESP_OK) { nvs_set_blob(h, "nets", buf, n); nvs_commit(h); nvs_close(h); }
    memset(buf, 0, sizeof buf);
}

static void publish_saved(void)
{
    LOCK();
    s_nsaved = s_store.n;
    for (int i = 0; i < s_store.n; i++) memcpy(s_saved[i], s_store.c[i].ssid, 33);
    for (int i = 0; i < s_naps; i++) s_aps[i].saved = bc_wifi_store_find(&s_store, s_aps[i].ssid) != NULL;
    UNLOCK();
}

static void set_state(plat_wifi_state_t st, plat_wifi_err_t err, const char *ssid)
{
    LOCK();
    s_st.state = st;
    if (st == PLAT_WIFI_CONNECTING) s_st.err = PLAT_WIFI_ERR_NONE;
    if (err != PLAT_WIFI_ERR_NONE) s_st.err = err;
    if (ssid) snprintf(s_st.ssid, sizeof s_st.ssid, "%s", ssid);
    if (st != PLAT_WIFI_CONNECTED) { s_st.ip[0] = 0; s_st.rssi = 0; s_st.internet = 0; }
    UNLOCK();
}

/* ---- events (default event loop task): record and signal only */
static void on_event(void *arg, esp_event_base_t base, int32_t id, void *data)
{
    if (base == WIFI_EVENT && id == WIFI_EVENT_STA_CONNECTED) s_associated = true;
    else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
        wifi_event_sta_disconnected_t *d = data;
        s_last_reason = d->reason;
        xEventGroupSetBits(s_eg, BIT_DISCONNECTED);
        LOCK(); bool was = s_st.state == PLAT_WIFI_CONNECTED; UNLOCK();
        if (was && !s_expect_disc) {   /* lost while connected: retry later (not during a ride) */
            ESP_LOGW(TAG, "connection lost (reason %d)", d->reason);
            set_state(PLAT_WIFI_IDLE, PLAT_WIFI_ERR_LOST, NULL);
            s_attempt = 0; s_next_auto_ms = hw_millis() + 5000;
        }
    } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *e = data;
        LOCK(); snprintf(s_st.ip, sizeof s_st.ip, IPSTR, IP2STR(&e->ip_info.ip)); UNLOCK();
        xEventGroupSetBits(s_eg, BIT_GOT_IP);
    }
}

/* Wi-Fi must never starve ride recording, Bluetooth or the screen of internal RAM */
#define WIFI_MIN_FREE_TO_START (56 * 1024)
#define WIFI_MIN_FREE_RUNNING (20 * 1024)

static bool radio_on(void)
{
    if (!s_radio_on && heap_caps_get_free_size(MALLOC_CAP_INTERNAL) < WIFI_MIN_FREE_TO_START) {
        ESP_LOGW(TAG, "not starting: only %u bytes internal RAM free", (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL));
        set_state(PLAT_WIFI_FAILED, PLAT_WIFI_ERR_OTHER, NULL);
        return false;
    }
    if (!s_radio_init) {
        esp_netif_init();
        esp_err_t e = esp_event_loop_create_default();
        if (e != ESP_OK && e != ESP_ERR_INVALID_STATE) return false;
        s_netif = esp_netif_create_default_wifi_sta();
        esp_netif_set_hostname(s_netif, "bikecomputer");
        wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
        if (esp_wifi_init(&cfg) != ESP_OK) { g_selftest.wifi = HW_FAIL; snprintf(g_selftest.wifi_s, sizeof g_selftest.wifi_s, "radio init failed"); return false; }
        esp_wifi_set_storage(WIFI_STORAGE_RAM);          /* credentials only in our own store */
        esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, on_event, NULL);
        esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, on_event, NULL);
        esp_wifi_set_mode(WIFI_MODE_STA);
        wifi_country_t cc = { .cc = "AE", .schan = 1, .nchan = 13, .policy = WIFI_COUNTRY_POLICY_MANUAL };   /* all 2.4 GHz channels 1-13 */
        esp_wifi_set_country(&cc);
        s_radio_init = true;
    }
    if (!s_radio_on) {
        if (esp_wifi_start() != ESP_OK) return false;
        esp_wifi_set_ps(WIFI_PS_MIN_MODEM);              /* needed for Wi-Fi + Bluetooth sharing the radio */
        s_radio_on = true;
    }
    return true;
}

static void radio_off(void)
{
    if (!s_radio_on) return;
    s_expect_disc = true;
    esp_wifi_disconnect();
    esp_wifi_stop();
    s_radio_on = false; s_expect_disc = false;
    set_state(PLAT_WIFI_OFF, PLAT_WIFI_ERR_NONE, NULL);
}

static void do_scan(void)
{
    LOCK(); plat_wifi_state_t prev = s_st.state; UNLOCK();
    if (prev == PLAT_WIFI_CONNECTING) return;
    if (prev != PLAT_WIFI_CONNECTED) set_state(PLAT_WIFI_SCANNING, PLAT_WIFI_ERR_NONE, NULL);
    else { LOCK(); s_st.state = PLAT_WIFI_SCANNING; UNLOCK(); }
    /* 0.6.0: 120-300 ms per channel (0.5.0 used 40-100 ms and could miss a hotspot that beacons every ~100 ms); the scan takes
       about 2-4 s, Bluetooth keeps its connection events in between (coexistence), and it only runs on request */
    wifi_scan_config_t sc = { .show_hidden = false, .scan_type = WIFI_SCAN_TYPE_ACTIVE, .scan_time.active = { .min = 120, .max = 300 } };
    esp_err_t e = esp_wifi_scan_start(&sc, true);
    uint16_t n = 32; wifi_ap_record_t *rec = calloc(32, sizeof(wifi_ap_record_t));
    if (rec && e == ESP_OK) esp_wifi_scan_get_ap_records(&n, rec); else n = 0;
    plat_wifi_ap_t tmp[32]; int k = 0;
    for (int i = 0; i < n; i++) {
        const char *ss = (const char *)rec[i].ssid;
        if (!ss[0]) continue;                             /* hidden networks: use "Other network" */
        int j; for (j = 0; j < k; j++) if (!strcmp(tmp[j].ssid, ss)) break;
        if (j < k) { if (rec[i].rssi > tmp[j].rssi) tmp[j].rssi = rec[i].rssi; continue; }
        if (k >= 32) continue;
        memset(&tmp[k], 0, sizeof tmp[k]);
        snprintf(tmp[k].ssid, sizeof tmp[k].ssid, "%s", ss);
        tmp[k].rssi = rec[i].rssi; tmp[k].secured = rec[i].authmode != WIFI_AUTH_OPEN; tmp[k].channel = rec[i].primary;
        tmp[k].saved = bc_wifi_store_find(&s_store, ss) != NULL;
        k++;
    }
    free(rec);
    for (int i = 1; i < k; i++) for (int j = i; j > 0 && tmp[j].rssi > tmp[j - 1].rssi; j--) { plat_wifi_ap_t t = tmp[j]; tmp[j] = tmp[j - 1]; tmp[j - 1] = t; }
    LOCK();
    memcpy(s_aps, tmp, sizeof(plat_wifi_ap_t) * (size_t)k); s_naps = k;
    s_st.scan_done = true; s_st.scans++;
    if (s_st.state == PLAT_WIFI_SCANNING) s_st.state = prev == PLAT_WIFI_CONNECTED ? PLAT_WIFI_CONNECTED : (prev == PLAT_WIFI_FAILED ? PLAT_WIFI_FAILED : PLAT_WIFI_IDLE);
    UNLOCK();
    s_scan_count = k;
    g_selftest.wifi = e == ESP_OK ? HW_PASS : HW_FAIL;
    snprintf(g_selftest.wifi_s, sizeof g_selftest.wifi_s, e == ESP_OK ? "%d networks seen" : "scan error", k);
    ESP_LOGI(TAG, "scan: %d networks", k);
}

static void do_disconnect(void)
{
    if (!s_radio_on) return;
    s_expect_disc = true;
    xEventGroupClearBits(s_eg, BIT_DISCONNECTED);
    if (esp_wifi_disconnect() == ESP_OK) xEventGroupWaitBits(s_eg, BIT_DISCONNECTED, pdTRUE, pdFALSE, pdMS_TO_TICKS(2000));
    s_expect_disc = false;
    set_state(PLAT_WIFI_IDLE, PLAT_WIFI_ERR_NONE, NULL);
}

/* blocking in this task only; returns true when an IP address was obtained */
static bool do_connect(const char *ssid, const char *pass, bool save)
{
    LOCK(); bool was_conn = s_st.state == PLAT_WIFI_CONNECTED; UNLOCK();
    if (was_conn) do_disconnect();
    wifi_config_t cfg = { 0 };
    memcpy(cfg.sta.ssid, ssid, strnlen(ssid, 32));
    memcpy(cfg.sta.password, pass, strnlen(pass, 64));
    /* iPhone hotspots announce WPA2/WPA3-Personal (transition) with PMF: WPA2 threshold + PMF capable (not required) lets the
       ESP32 join as WPA2 or, when the AP insists, WPA3-SAE (H2E and hunting-and-pecking both allowed) */
    cfg.sta.threshold.authmode = pass[0] ? WIFI_AUTH_WPA2_PSK : WIFI_AUTH_OPEN;
    cfg.sta.pmf_cfg.capable = true; cfg.sta.pmf_cfg.required = false;
    cfg.sta.sae_pwe_h2e = WPA3_SAE_PWE_BOTH;
    cfg.sta.scan_method = WIFI_ALL_CHANNEL_SCAN;
    cfg.sta.sort_method = WIFI_CONNECT_AP_BY_SIGNAL;
    cfg.sta.failure_retry_cnt = 1;
    esp_wifi_set_config(WIFI_IF_STA, &cfg);
    memset(&cfg, 0, sizeof cfg);
    s_associated = false; s_last_reason = 0;
    xEventGroupClearBits(s_eg, BIT_GOT_IP | BIT_DISCONNECTED);
    set_state(PLAT_WIFI_CONNECTING, PLAT_WIFI_ERR_NONE, ssid);
    ESP_LOGI(TAG, "connecting to a network (%s)", pass[0] ? "password" : "open");
    if (esp_wifi_connect() != ESP_OK) { set_state(PLAT_WIFI_FAILED, PLAT_WIFI_ERR_OTHER, NULL); LOCK(); s_st.failures++; UNLOCK(); return false; }
    EventBits_t b = xEventGroupWaitBits(s_eg, BIT_GOT_IP | BIT_DISCONNECTED, pdTRUE, pdFALSE, pdMS_TO_TICKS(20000));
    if (b & BIT_GOT_IP) {
        set_state(PLAT_WIFI_CONNECTED, PLAT_WIFI_ERR_NONE, ssid);
        LOCK(); s_st.connects++; UNLOCK();
        if (save) bc_wifi_store_put(&s_store, ssid, pass); else bc_wifi_store_touch(&s_store, ssid);
        store_save(); publish_saved();
        s_attempt = 0; s_auto_halted = false;
        ESP_LOGI(TAG, "connected (IP obtained)");   /* 0.7.3: no addresses in logs (they end up in diagnostic reports) */
        /* internet check: one DNS lookup (a connected hotspot without data shows "internet not reachable", never "connected"
           pretending the world is there). Blocks only this task, a few seconds at most. */
        LOCK(); s_st.internet = 0; UNLOCK();
        struct addrinfo hints = { .ai_family = AF_INET, .ai_socktype = SOCK_STREAM }, *res = NULL;
        int rc = getaddrinfo("captive.apple.com", "80", &hints, &res);
        if (res) freeaddrinfo(res);
        LOCK(); s_st.internet = rc == 0 ? 1 : 2; UNLOCK();
        ESP_LOGI(TAG, "internet check: %s", rc == 0 ? "DNS ok" : "no DNS answer");
        return true;
    }
    plat_wifi_err_t err;
    if (b & BIT_DISCONNECTED) err = (plat_wifi_err_t)bc_wifi_map_reason(s_last_reason, pass[0] != 0, false);
    else { err = s_associated ? PLAT_WIFI_ERR_NO_IP : PLAT_WIFI_ERR_TIMEOUT; s_expect_disc = true; esp_wifi_disconnect(); vTaskDelay(pdMS_TO_TICKS(300)); s_expect_disc = false; }
    if (s_associated && err == PLAT_WIFI_ERR_LOST) err = PLAT_WIFI_ERR_NO_IP;
    set_state(PLAT_WIFI_FAILED, err, ssid);
    LOCK(); s_st.failures++; UNLOCK();
    ESP_LOGW(TAG, "connect failed: %s (reason %d)", bc_wifi_err_text((bc_wifi_err_t)err), s_last_reason);
    return false;
}

static void auto_connect(void)
{
    if (!s_enabled || s_quiet || s_user_off || s_store.n == 0 || s_auto_halted) return;
    LOCK(); plat_wifi_state_t st = s_st.state; UNLOCK();
    if (st == PLAT_WIFI_CONNECTED || st == PLAT_WIFI_CONNECTING) return;
    if ((int32_t)(hw_millis() - s_next_auto_ms) < 0) return;
    do_scan();
    char names[16][33]; int rssi[16]; int n;
    LOCK(); n = s_naps; for (int i = 0; i < n; i++) { memcpy(names[i], s_aps[i].ssid, 33); rssi[i] = s_aps[i].rssi; } UNLOCK();
    int pick = bc_wifi_pick(&s_store, (const char (*)[33])names, rssi, n);
    bool ok = false;
    if (pick >= 0 && !s_quiet) { bc_wifi_cred_t c = s_store.c[pick]; ok = do_connect(c.ssid, c.pass, false); memset(&c, 0, sizeof c); }
    if (!ok) {
        s_next_auto_ms = hw_millis() + bc_wifi_backoff_s(s_attempt) * 1000;
        if (++s_attempt >= AUTO_MAX_ROUNDS) { s_auto_halted = true; ESP_LOGW(TAG, "no saved network reachable after %u rounds: waiting for the rider (Rescan / Wi-Fi page)", s_attempt); }
    }
}

static void mgr_task(void *arg)
{
    cmd_t m; uint32_t rssi_t = 0;
    for (;;) {
        if (xQueueReceive(s_q, &m, pdMS_TO_TICKS(1000)) == pdTRUE) {
            switch (m.k) {
            case CMD_ENABLE:
                s_enabled = true; s_user_off = false; s_attempt = 0; s_next_auto_ms = 0; s_auto_halted = false;
                if (radio_on()) set_state(PLAT_WIFI_IDLE, PLAT_WIFI_ERR_NONE, NULL);
                break;
            case CMD_DISABLE: s_enabled = false; radio_off(); break;
            case CMD_SCAN: if (s_enabled && radio_on()) { do_scan(); s_attempt = 0; s_auto_halted = false; s_next_auto_ms = 0; } break;
            case CMD_CONNECT:
                if (!s_enabled) break;
                if (!m.has_pass) { const bc_wifi_cred_t *c = bc_wifi_store_find(&s_store, m.ssid); if (c) memcpy(m.pass, c->pass, sizeof m.pass); }
                s_user_off = false; s_attempt = 0; s_auto_halted = false;
                if (radio_on()) do_connect(m.ssid, m.pass, m.save);
                break;
            case CMD_SAVE:
                if (m.ssid[0]) { bc_wifi_store_put(&s_store, m.ssid, m.pass); store_save(); publish_saved(); s_auto_halted = false; s_next_auto_ms = 0; }
                break;
            case CMD_DISCONNECT: s_user_off = true; do_disconnect(); break;
            case CMD_FORGET: {
                LOCK(); bool cur = s_st.state == PLAT_WIFI_CONNECTED && !strcmp(s_st.ssid, m.ssid); UNLOCK();
                if (cur) { s_user_off = true; do_disconnect(); }
                if (bc_wifi_store_remove(&s_store, m.ssid)) { store_save(); publish_saved(); }
                break; }
            }
            memset(&m, 0, sizeof m);                       /* no password left in RAM */
        } else auto_connect();
        if (s_radio_on && heap_caps_get_free_size(MALLOC_CAP_INTERNAL) < WIFI_MIN_FREE_RUNNING) {
            ESP_LOGW(TAG, "internal RAM low (%u bytes): Wi-Fi switched off to protect the ride and Bluetooth",
                     (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL));
            radio_off(); s_enabled = false;
            set_state(PLAT_WIFI_FAILED, PLAT_WIFI_ERR_OTHER, NULL);
        }
        LOCK(); bool conn = s_st.state == PLAT_WIFI_CONNECTED; UNLOCK();
        if (conn && hw_millis() - rssi_t > 5000) {
            rssi_t = hw_millis(); wifi_ap_record_t ap;
            if (esp_wifi_sta_get_ap_info(&ap) == ESP_OK) { LOCK(); s_st.rssi = ap.rssi; UNLOCK(); }
        }
    }
}

void net_wifi_init(void)
{
    if (s_q) return;
    s_q = xQueueCreate(6, sizeof(cmd_t));
    s_eg = xEventGroupCreate();
    store_load(); publish_saved();
    s_st.state = PLAT_WIFI_OFF;
    xTaskCreatePinnedToCore(mgr_task, "wifi_mgr", 6144, NULL, 3, NULL, 0);
}

static void post(cmd_kind_t k, const char *ssid, const char *pass, bool save)
{
    if (!s_q) return;
    cmd_t m = { .k = k, .save = save };
    if (ssid) snprintf(m.ssid, sizeof m.ssid, "%s", ssid);
    if (pass) { snprintf(m.pass, sizeof m.pass, "%s", pass); m.has_pass = true; }
    if (xQueueSend(s_q, &m, 0) != pdTRUE) ESP_LOGW(TAG, "busy - command dropped");
    memset(&m, 0, sizeof m);
}

/* ---- plat.h */
void plat_wifi_set_enabled(bool on) { post(on ? CMD_ENABLE : CMD_DISABLE, NULL, NULL, false); }
void plat_wifi_scan(void) { post(CMD_SCAN, NULL, NULL, false); }
void plat_wifi_connect(const char *ssid, const char *pass, bool save) { post(CMD_CONNECT, ssid, pass, save); }
void plat_wifi_disconnect(void) { post(CMD_DISCONNECT, NULL, NULL, false); }
void plat_wifi_forget(const char *ssid) { post(CMD_FORGET, ssid, NULL, false); }
void plat_wifi_save(const char *ssid, const char *pass) { post(CMD_SAVE, ssid, pass ? pass : "", true); }
void plat_wifi_set_quiet(bool riding) { s_quiet = riding; }
int plat_wifi_scan_count(void) { return s_scan_count; }
void plat_wifi_status(plat_wifi_status_t *o) { LOCK(); *o = s_st; UNLOCK(); }
int plat_wifi_results(plat_wifi_ap_t *out, int max)
{
    LOCK(); int n = s_naps < max ? s_naps : max; memcpy(out, s_aps, sizeof(plat_wifi_ap_t) * (size_t)n); UNLOCK();
    return n;
}
int plat_wifi_saved(char ssids[][33], int max)
{
    LOCK(); int n = s_nsaved < max ? s_nsaved : max; for (int i = 0; i < n; i++) memcpy(ssids[i], s_saved[i], 33); UNLOCK();
    return n;
}
