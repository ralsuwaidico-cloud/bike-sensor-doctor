/* PC implementation of plat.h for the preview/test harness. Sensor values here are the harness's scripted stand-in for
 * the Bluetooth hardware (set by the scenario), so screens can be tested in every state. Files live in SIM_FS. */
#include "plat.h"
#include "sim.h"
#include "app_psvc.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

sim_hw_t g_sim;
static char s_root[256] = "simfs";

void sim_fs_root(const char *dir) { snprintf(s_root, sizeof s_root, "%s", dir); mkdir(s_root, 0755); }

static void full(const char *rel, char *out, size_t cap)
{
    snprintf(out, cap, "%s/%s", s_root, rel);
    char dir[512]; snprintf(dir, sizeof dir, "%s", out);
    char *sl = strrchr(dir, '/'); if (sl) { *sl = 0; mkdir(dir, 0755); }
}

uint32_t plat_ms(void) { return g_sim.now_ms; }

void plat_sensors(plat_sensors_t *o)
{
    memset(o, 0, sizeof *o);
    o->power_ok = g_sim.power_ok; o->watts = g_sim.watts; o->cad_ok = g_sim.cad_ok; o->rpm = g_sim.rpm;
    o->hr_ok = g_sim.hr_ok; o->bpm = g_sim.bpm;
    o->csc_cad_ok = g_sim.csc_cad_ok; o->csc_rpm = g_sim.csc_rpm; o->csc_speed_ok = g_sim.csc_speed_ok; o->csc_speed_dmh = g_sim.csc_speed_dmh;
    o->csc_has_wheel = g_sim.csc_has_wheel; o->csc_has_crank = g_sim.csc_has_crank;
    for (int k = 0; k < PLAT_SENS_KINDS; k++) { o->link[k] = g_sim.link[k]; }
    o->link[PLAT_SENS_POWER].valid_age_ms = g_sim.power_ok ? 700 : (g_sim.link[0].packets ? 9300 : UINT32_MAX);
    o->link[PLAT_SENS_SPEED].link = PLAT_LINK_UNSUPPORTED;
}

void plat_csc_wheel_mm(uint16_t mm) { g_sim.wheel_mm = mm; }
static plat_sens_kind_t s_scan_kind; static bool s_scanning; static uint32_t s_scan_t0;
void plat_scan_begin(plat_sens_kind_t k) { s_scan_kind = k; s_scanning = true; s_scan_t0 = g_sim.now_ms; }
void plat_scan_end(void) { s_scanning = false; }
int plat_scan_results(plat_found_t *out, int max)
{
    if (!s_scanning || g_sim.now_ms - s_scan_t0 < 1500) return 0;
    int n = 0;
    if (s_scan_kind == PLAT_SENS_ANY) { for (int i = 0; i < g_sim.found_any_n && n < max; i++) out[n++] = g_sim.found_any[i]; return n; }
    for (int i = 0; i < g_sim.found_n[s_scan_kind] && n < max; i++) out[n++] = g_sim.found[s_scan_kind][i];
    return n;
}
void plat_pair(plat_sens_kind_t k, const plat_found_t *d)
{
    g_sim.link[k].link = d ? PLAT_LINK_CONNECTED : PLAT_LINK_NOT_PAIRED;
    if (d) snprintf(g_sim.link[k].name, sizeof g_sim.link[k].name, "%s", d->name);
    g_sim.pair_calls++;
}

bool plat_profile_load(char *buf, size_t cap) { long n = plat_file_read("profile.txt", buf, cap - 1); if (n <= 0) return false; buf[n] = 0; return true; }
bool plat_profile_save(const char *txt) { g_sim.profile_saves++; return plat_file_write("profile.txt", txt, strlen(txt)); }

bool plat_file_append(const char *path, const char *data, size_t len, bool sync)
{
    (void)sync; char p[512]; full(path, p, sizeof p);
    FILE *f = fopen(p, "ab"); if (!f) return false;
    size_t w = fwrite(data, 1, len, f); fclose(f); return w == len;
}
bool plat_file_write(const char *path, const char *data, size_t len)
{
    char p[512], t[520]; full(path, p, sizeof p); snprintf(t, sizeof t, "%s.tmp", p);
    FILE *f = fopen(t, "wb"); if (!f) return false;
    size_t w = fwrite(data, 1, len, f); fclose(f);
    return w == len && rename(t, p) == 0;
}
long plat_file_read(const char *path, char *buf, size_t cap) { return plat_file_read_at(path, 0, buf, cap); }
long plat_file_read_at(const char *path, long off, char *buf, size_t cap)
{
    char p[512]; full(path, p, sizeof p);
    FILE *f = fopen(p, "rb"); if (!f) return -1;
    fseek(f, off, SEEK_SET); long n = (long)fread(buf, 1, cap, f); fclose(f); return n;
}
bool plat_file_rename(const char *from, const char *to)
{
    char a[512], b[512]; full(from, a, sizeof a); full(to, b, sizeof b); return rename(a, b) == 0;
}
bool plat_file_remove(const char *path) { char p[512]; full(path, p, sizeof p); return unlink(p) == 0; }
bool plat_storage_ok(void) { return true; }
long plat_file_size(const char *path) { char p[512]; full(path, p, sizeof p); struct stat st; return stat(p, &st) == 0 ? (long)st.st_size : -1; }
void plat_health(plat_health_t *o)
{
    memset(o, 0, sizeof *o);
    snprintf(o->fw_version, sizeof o->fw_version, "0.6.0-sim"); snprintf(o->build, sizeof o->build, "%.6s %.5s #sim", __DATE__, __TIME__);
    o->uptime_s = g_sim.now_ms / 1000; snprintf(o->reset_reason, sizeof o->reset_reason, "power-on");
    o->boot_count = g_sim.boots; o->crash_total = 2; o->crash_consecutive = 0; o->safe_mode_entries = 0;
    o->heap_free_k = 61; o->heap_min_k = 48; o->psram_free_k = 1890; o->psram_total_k = 2048;
    o->flash_total_k = 16384; o->app_slot_k = 4096; o->app_used_k = -1; o->storage_free_k = 7980; o->storage_total_k = 8000;
    o->battery_mv = plat_battery_mv(); o->battery_pct = g_sim.battery_pct; o->usb_power = g_sim.usb;
    o->ble_ready = true; o->ble_scanning = g_sim.link[0].link == PLAT_LINK_SEARCHING; o->ble_devices_seen = 14;
    o->wifi_networks = plat_wifi_scan_count(); o->wifi_on = g_sim.wifi_on;
    o->display_ok = o->touch_ok = o->imu_ok = o->storage_ok = true;
}
void plat_export_report(const char *text) { g_sim.exports++; plat_file_write("diag/report.txt", text, strlen(text)); }

#include "bc_power.h"
int plat_battery_mv(void) { return g_sim.battery_mv ? g_sim.battery_mv : 3600 + g_sim.battery_pct * 6; }
int plat_battery_pct(void) { return g_sim.battery_mv ? bc_batt_pct_from_mv(g_sim.battery_mv) : g_sim.battery_pct; }
bool plat_usb_power(void) { return g_sim.usb || plat_battery_mv() > 4250; }
void plat_backlight(int pct) { g_sim.backlight = pct; }
void plat_panel_sleep(bool sleep) { g_sim.panel_asleep = sleep; }
void plat_touch_screen_off(bool off) { g_sim.touch_fast_poll = off; if (off) g_sim.touch_screen_offs++; }
bool plat_device_id(uint8_t out[6]) { static const uint8_t id[6] = { 0x8c, 0xfd, 0x49, 0x9b, 0xef, 0x40 }; memcpy(out, id, 6); return true; }
void plat_deep_sleep(int wake_taps) { g_sim.deep_sleeps++; g_sim.asleep = true; g_sim.sleep_wake_taps = wake_taps; }
void plat_sensors_set_standby(bool standby) { g_sim.sensor_standby = standby; if (standby) g_sim.sensor_standbys++; }
bool plat_woke_from_sleep(void) { return g_sim.woke_from_sleep; }
uint32_t plat_uptime_s(void) { return g_sim.now_ms / 1000; }

/* ---- simulated Wi-Fi manager: same API and timing shape as the device (asynchronous, polled) */
#include "bc_wifi.h"
static plat_wifi_status_t ws = { .state = PLAT_WIFI_OFF };
static bc_wifi_store_t wstore; static bool wstore_loaded;
static bool w_enabled, w_quiet, w_user_off;
static uint32_t w_until, w_next_auto; static int w_op;          /* 0 none, 1 scan, 2 connect, 3 auto-scan */
static char w_ssid[33], w_pass[65]; static bool w_save; static unsigned w_attempt;
static plat_wifi_ap_t w_res[16]; static int w_nres, w_scan_count = -1;

static void wstore_io(bool save)
{
    if (save) { unsigned char b[512]; size_t n = bc_wifi_store_pack(&wstore, b, sizeof b); plat_file_write("wifi.bin", (const char *)b, n); return; }
    unsigned char b[512]; long n = plat_file_read("wifi.bin", (char *)b, sizeof b);
    bc_wifi_store_init(&wstore); if (n > 0) bc_wifi_store_unpack(&wstore, b, (size_t)n);
}
static void w_load(void) { if (!wstore_loaded) { wstore_io(false); wstore_loaded = true; } }
void sim_wifi_reboot(void) { wstore_loaded = false; memset(&ws, 0, sizeof ws); ws.state = PLAT_WIFI_OFF; w_enabled = w_quiet = w_user_off = false; w_op = 0; w_nres = 0; }

static int ap_find(const char *ssid) { for (int i = 0; i < g_sim.n_ap; i++) if (g_sim.ap[i].present && !g_sim.ap[i].ghz5_only && !strcmp(g_sim.ap[i].ssid, ssid)) return i; return -1; }

static void start_connect(const char *ssid, const char *pass, bool save)
{
    snprintf(w_ssid, sizeof w_ssid, "%s", ssid); snprintf(w_pass, sizeof w_pass, "%s", pass); w_save = save;
    ws.state = PLAT_WIFI_CONNECTING; ws.err = PLAT_WIFI_ERR_NONE; snprintf(ws.ssid, sizeof ws.ssid, "%s", ssid); ws.ip[0] = 0; ws.rssi = 0;
    w_op = 2; w_until = g_sim.now_ms + (g_sim.wifi_no_answer ? 20000 : 3000);
}

static void finish_scan(void)
{
    w_nres = 0;
    for (int i = 0; i < g_sim.n_ap && w_nres < 16; i++) if (g_sim.ap[i].present && !g_sim.ap[i].ghz5_only) {   /* the ESP32 radio cannot see 5 GHz networks */
        plat_wifi_ap_t *a = &w_res[w_nres++]; memset(a, 0, sizeof *a);
        snprintf(a->ssid, sizeof a->ssid, "%s", g_sim.ap[i].ssid); a->rssi = g_sim.ap[i].rssi; a->secured = g_sim.ap[i].secured; a->channel = g_sim.ap[i].channel ? g_sim.ap[i].channel : 6;
        a->saved = bc_wifi_store_find(&wstore, a->ssid) != NULL;
    }
    for (int i = 1; i < w_nres; i++) for (int j = i; j > 0 && w_res[j].rssi > w_res[j - 1].rssi; j--) { plat_wifi_ap_t t = w_res[j]; w_res[j] = w_res[j - 1]; w_res[j - 1] = t; }
    ws.scan_done = true; ws.scans++; w_scan_count = w_nres;
}

static void pump_core(void);
static void pump(void) { g_sim.wifi_ui_ticks++; pump_core(); }
void sim_wifi_pump(void) { pump_core(); }   /* the device's manager runs in its own task: the harness ticks it */
static void pump_core(void)
{
    w_load();
    if (w_op && (int32_t)(g_sim.now_ms - w_until) >= 0) {
        int op = w_op; w_op = 0;
        if (op == 1 || op == 3) {
            finish_scan();
            if (ws.state == PLAT_WIFI_SCANNING) ws.state = PLAT_WIFI_IDLE;
            if (op == 3) {
                char names[16][33]; int rssi[16]; for (int i = 0; i < w_nres; i++) { memcpy(names[i], w_res[i].ssid, 33); rssi[i] = w_res[i].rssi; }
                int pk = bc_wifi_pick(&wstore, (const char (*)[33])names, rssi, w_nres);
                if (pk >= 0) start_connect(wstore.c[pk].ssid, wstore.c[pk].pass, false);
                else { w_next_auto = g_sim.now_ms + bc_wifi_backoff_s(w_attempt++) * 1000; }
            }
        } else if (op == 2) {
            int a = ap_find(w_ssid); plat_wifi_err_t err = PLAT_WIFI_ERR_NONE;
            if (g_sim.wifi_no_answer) err = PLAT_WIFI_ERR_TIMEOUT;
            else if (a < 0) err = PLAT_WIFI_ERR_NOT_FOUND;
            else if (g_sim.ap[a].secured && strcmp(g_sim.ap[a].pass, w_pass)) err = PLAT_WIFI_ERR_WRONG_PASSWORD;
            else if (g_sim.wifi_no_dhcp) err = PLAT_WIFI_ERR_NO_IP;
            if (err) { ws.state = PLAT_WIFI_FAILED; ws.err = err; ws.failures++; w_next_auto = g_sim.now_ms + bc_wifi_backoff_s(w_attempt++) * 1000; }
            else {
                ws.state = PLAT_WIFI_CONNECTED; ws.connects++; ws.rssi = g_sim.ap[a].rssi; snprintf(ws.ip, sizeof ws.ip, "192.168.1.23"); ws.internet = g_sim.wifi_no_internet ? 2 : 1;
                if (w_save) bc_wifi_store_put(&wstore, w_ssid, w_pass); else bc_wifi_store_touch(&wstore, w_ssid);
                wstore_io(true); w_attempt = 0;
            }
            memset(w_pass, 0, sizeof w_pass);
        }
    }
    /* connection lost when the network disappears */
    if (ws.state == PLAT_WIFI_CONNECTED && ap_find(ws.ssid) < 0) { ws.state = PLAT_WIFI_IDLE; ws.err = PLAT_WIFI_ERR_LOST; ws.ip[0] = 0; w_next_auto = g_sim.now_ms + 5000; }
    /* automatic join of saved networks: never during a ride */
    if (w_enabled && !w_quiet && !w_user_off && !w_op && wstore.n && (ws.state == PLAT_WIFI_IDLE || ws.state == PLAT_WIFI_FAILED) &&
        (int32_t)(g_sim.now_ms - w_next_auto) >= 0) {
        g_sim.wifi_auto_attempts++; w_op = 3; w_until = g_sim.now_ms + 2000; if (ws.state == PLAT_WIFI_IDLE) ws.state = PLAT_WIFI_SCANNING;
    }
}

void plat_wifi_set_enabled(bool on)
{
    w_load(); w_enabled = on; g_sim.wifi_on = on; w_user_off = false; w_attempt = 0; w_next_auto = g_sim.now_ms + 500;
    if (on) { if (ws.state == PLAT_WIFI_OFF) ws.state = PLAT_WIFI_IDLE; } else { ws.state = PLAT_WIFI_OFF; ws.ip[0] = 0; w_op = 0; }
}
void plat_wifi_scan(void) { w_load(); if (!w_enabled || w_op == 2) return; w_op = 1; w_until = g_sim.now_ms + 2000; if (ws.state != PLAT_WIFI_CONNECTED) ws.state = PLAT_WIFI_SCANNING; }
int plat_wifi_results(plat_wifi_ap_t *out, int max) { pump(); int n = w_nres < max ? w_nres : max; memcpy(out, w_res, sizeof(plat_wifi_ap_t) * (size_t)n); return n; }
void plat_wifi_connect(const char *ssid, const char *pass, bool save)
{
    w_load(); if (!w_enabled) return; w_user_off = false;
    if (!pass) { const bc_wifi_cred_t *c = bc_wifi_store_find(&wstore, ssid); pass = c ? c->pass : ""; }
    start_connect(ssid, pass, save);
}
void plat_wifi_disconnect(void) { w_user_off = true; if (ws.state != PLAT_WIFI_OFF) { ws.state = PLAT_WIFI_IDLE; ws.ip[0] = 0; ws.err = PLAT_WIFI_ERR_NONE; } }
void plat_wifi_save(const char *ssid, const char *pass) { w_load(); bc_wifi_store_put(&wstore, ssid, pass); wstore_io(true); }
void plat_wifi_forget(const char *ssid) { w_load(); if (ws.state == PLAT_WIFI_CONNECTED && !strcmp(ws.ssid, ssid)) plat_wifi_disconnect(); bc_wifi_store_remove(&wstore, ssid); wstore_io(true); }
int plat_wifi_saved(char ssids[][33], int max) { w_load(); int n = wstore.n < max ? wstore.n : max; for (int i = 0; i < n; i++) memcpy(ssids[i], wstore.c[i].ssid, 33); return n; }
void plat_wifi_status(plat_wifi_status_t *o) { pump(); *o = ws; }
void plat_wifi_set_quiet(bool riding) { w_quiet = riding; }
int plat_wifi_scan_count(void) { return w_scan_count; }
const char *plat_fw_version(void) { return "0.6.0-sim"; }

/* ---- phone link simulation */
#define PH g_sim.phone
void plat_phone_set_enabled(bool on) { PH.enabled = on; if (!on) { PH.connected = PH.pairing = false; PH.passkey = 0; } }
void plat_phone_status(plat_phone_status_t *o)
{
    memset(o, 0, sizeof *o); o->phone_batt = o->watch_batt = 0xFF; o->last_rx_age_ms = UINT32_MAX;
    o->bonded = PH.bonded; o->rssi = PH.connected ? PH.rssi : 0; o->passkey = PH.pairing ? PH.passkey : 0;
    o->state = !PH.enabled ? PLAT_PHONE_OFF : !PH.connected ? PLAT_PHONE_ADVERTISING : PH.pairing ? PLAT_PHONE_PAIRING : PH.bonded ? PLAT_PHONE_READY : PLAT_PHONE_CONNECTED;
    uint32_t last = 0; if (PH.in.gps.rx_ms > last) last = PH.in.gps.rx_ms; if (PH.in.hr.rx_ms > last) last = PH.in.hr.rx_ms; if (PH.in.time.rx_ms > last) last = PH.in.time.rx_ms;
    if (last) o->last_rx_age_ms = g_sim.now_ms - last;
}
void plat_phone_forget(void) { PH.bonded = PH.connected = PH.pairing = false; PH.passkey = 0; PH.forgets++; }
void plat_phone_disconnect(void) { PH.connected = PH.pairing = false; PH.passkey = 0; }
void plat_phone_inputs(plat_phone_in_t *o) { *o = PH.in; }
bool plat_phone_take_ctrl(bc_ctrl_req_t *o) { if (!PH.ctrl_pending) return false; *o = PH.ctrl; PH.ctrl_pending = false; return true; }
void plat_phone_ctrl_respond(const bc_ctrl_resp_t *r) { PH.last_resp = *r; PH.resps++; }
void plat_phone_publish_live(const bc_live_t *l) { if (PH.connected && PH.bonded) { PH.last_live = *l; PH.lives++; } }
void sim_phone_connect(bool bonded) { if (!PH.enabled) return; PH.connected = true; PH.rssi = -55; PH.bonded = bonded; PH.pairing = !bonded; PH.passkey = bonded ? 0 : 482913; }
void sim_phone_enter_passkey(void) { if (PH.connected && PH.pairing) { PH.pairing = false; PH.bonded = true; PH.passkey = 0; } }
void sim_phone_disconnect(void) { PH.connected = PH.pairing = false; PH.svc_in_n = 0; app_psvc_on_disconnect(); }
static bool ph_ok(void) { return PH.connected && PH.bonded; }
void sim_phone_send_gps(int32_t lat, int32_t lon, uint16_t speed_cms, uint16_t hacc_dm)
{
    if (!ph_ok()) return;
    bc_in_gps_t g = { .lat_e7 = lat, .lon_e7 = lon, .hacc_dm = hacc_dm, .vacc_dm = BC_LINK_NONE16, .speed_ok = true, .speed_cms = speed_cms, .src = BC_SRC_PHONE_GPS, .fix_epoch_ms = 1761300000000ULL };
    uint8_t b[BC_LINK_MAX]; size_t n = bc_link_encode_gps(&g, b, sizeof b, 1, 0);
    if (bc_link_decode_gps(b, n, &PH.in.gps.v)) PH.in.gps.rx_ms = g_sim.now_ms;   /* same validation path as the device */
}
void sim_phone_send_hr(uint8_t bpm, uint8_t src)
{
    if (!ph_ok()) return;
    bc_in_hr_t h = { .bpm = bpm, .src = src, .sample_epoch_ms = 1761300000000ULL, .quality = 2 };
    uint8_t b[BC_LINK_MAX]; size_t n = bc_link_encode_hr(&h, b, sizeof b, 1, 0);
    if (bc_link_decode_hr(b, n, &PH.in.hr.v)) PH.in.hr.rx_ms = g_sim.now_ms;
}
void sim_phone_send_time(uint64_t epoch_ms)
{
    if (!ph_ok()) return;
    bc_in_time_t t = { .epoch_ms = epoch_ms, .uncertainty_ms = 50, .tz_min = 240 };
    uint8_t b[BC_LINK_MAX]; size_t n = bc_link_encode_time(&t, b, sizeof b, 1, 0);
    if (bc_link_decode_time(b, n, &PH.in.time.v)) PH.in.time.rx_ms = g_sim.now_ms;
}
void sim_phone_ctrl(uint8_t cmd, uint16_t ride_id) { if (!ph_ok()) return; PH.ctrl.req_id++; PH.ctrl.cmd = cmd; PH.ctrl.ride_id = ride_id; PH.ctrl_pending = true; }
/* 0.6.0 phone services: the harness writes the same bytes the iPhone app sends (queued like ble_link.c does) and decodes
   every notification the board sends back, exactly as the iPhone app would. */
bool sim_phone_write(int chr, const uint8_t *msg, size_t n)
{
    if (!ph_ok() || PH.svc_in_n >= 8 || n > BC_LINK_MAX) return false;
    PH.svc_in[PH.svc_in_n].chr = (uint8_t)chr; PH.svc_in[PH.svc_in_n].len = n; memcpy(PH.svc_in[PH.svc_in_n].b, msg, n); PH.svc_in_n++;
    return true;
}
int plat_phone_take_svc(uint8_t *chr, uint8_t *buf, size_t cap)
{
    if (!PH.svc_in_n || !ph_ok()) { PH.svc_in_n = 0; return 0; }
    size_t n = PH.svc_in[0].len; if (n > cap) n = cap;
    *chr = PH.svc_in[0].chr; memcpy(buf, PH.svc_in[0].b, n);
    PH.svc_in_n--; memmove(&PH.svc_in[0], &PH.svc_in[1], sizeof PH.svc_in[0] * (size_t)PH.svc_in_n);
    return (int)n;
}
bool plat_phone_notify_svc(uint8_t chr, const uint8_t *b, size_t n)
{
    if (!ph_ok()) return true;                               /* nobody listening: the transport drops it, like NimBLE */
    if (PH.notify_full) return false;                        /* test hook: transport back-pressure */
    PH.notifies++; PH.last_notify_chr = chr;
    switch (b[0]) {
    case BC_MSG_WIFI_SCAN_RESULT: if (PH.n_scan < 32 && bc_link_decode_wifi_scan_result(b, n, &PH.scan[PH.n_scan])) PH.n_scan++; break;
    case BC_MSG_WIFI_SCAN_END: bc_link_decode_wifi_scan_end(b, n, &PH.scan_end); PH.scan_ends++; break;
    case BC_MSG_WIFI_STATUS: bc_link_decode_wifi_status(b, n, &PH.wifi_status); PH.statuses++; break;
    case BC_MSG_SYNC_RIDE: if (PH.n_rides < 64 && bc_link_decode_sync_ride(b, n, &PH.rides[PH.n_rides])) PH.n_rides++; break;
    case BC_MSG_SYNC_END: bc_link_decode_sync_end(b, n, &PH.sync_end); PH.sync_ends++; break;
    case BC_MSG_PROFILE: bc_link_decode_profile(b, n, &PH.profile); PH.profiles++; break;
    case BC_MSG_PROFILE_ACK: bc_link_decode_profile_ack(b, n, &PH.profile_ack); PH.profile_acks++; break;
    case BC_MSG_SETTINGS: bc_link_decode_settings(b, n, &PH.settings); PH.settings_msgs++; break;
    case BC_MSG_EVENT: bc_link_decode_event(b, n, &PH.event); PH.events++; break;
    default: PH.unknown_notifies++; break;
    }
    return true;
}
void plat_phone_set_standby(bool standby) { PH.standby = standby; if (standby) PH.standbys++; }
#undef PH
const char *plat_reset_reason(void) { return "power-on"; }
uint32_t plat_boot_count(void) { return g_sim.boots; }
void plat_restart(void) { g_sim.restart_requested = true; }
void plat_selftest_text(char *b, size_t cap)
{
    snprintf(b, cap, "Display  #56E08C PASS#\nTouch    #56E08C PASS#\nPSRAM    #56E08C PASS#\nFlash    #56E08C PASS#\nNVS      #56E08C PASS#\n"
                     "Storage  #56E08C PASS#\nIMU      #56E08C PASS#\nBattery  #56E08C PASS# 4.11V\nWi-Fi    #FFB64D INFO# off\nBLE      #56E08C PASS#");
}
void plat_mem_text(char *b, size_t cap) { snprintf(b, cap, "heap 180K min 150K psram 1900K"); }
void plat_log(const char *line) { if (g_sim.verbose) printf("  [log] %s\n", line); snprintf(g_sim.last_log, sizeof g_sim.last_log, "%s", line); }
