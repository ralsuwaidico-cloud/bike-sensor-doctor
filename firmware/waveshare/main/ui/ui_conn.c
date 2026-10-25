/*
 * Connections (firmware 0.6.0) — replaces the old "Sensors" page. One category menu for everything the board talks to,
 * each with its own detail page: state, last data, what it measures, pair / reconnect / forget, troubleshooting.
 *
 * Tags on every source: DIRECT = a Bluetooth link of this board, VIA PHONE = relayed by the BikeComputer app,
 * CLOUD = an internet service (none supported yet). Nothing unsupported is ever shown as connected.
 *
 * The red "!" appears only for a connection the rider configured (paired / remembered / saved) or that the ride needs
 * and that is missing right now; optional devices that were never set up stay grey.
 */
#include "ui.h"
#include "app_psvc.h"
#include <stdio.h>
#include <string.h>

typedef enum { CAT_PHONE = 0, CAT_WIFI, CAT_POWER, CAT_HR, CAT_CADENCE, CAT_SPEED, CAT_OTHER, CAT_SYNC, CAT_COUNT } cat_t;
static const char *CAT_NAME[CAT_COUNT] = { "Phone", "Wi-Fi", "Power meter", "Heart rate", "Cadence", "Speed", "Other Bluetooth", "Device sync" };

/* ---- shared status model (menu rows, Home badge) */
typedef struct { char txt[24]; lv_color_t color; bool alert; bool connected; } cat_status_t;

static void age_text(uint32_t age_ms, char *out, size_t cap)
{
    if (age_ms == UINT32_MAX) snprintf(out, cap, "no data yet");
    else if (age_ms < 2000) snprintf(out, cap, "live");
    else if (age_ms < 120000) snprintf(out, cap, "%lus ago", (unsigned long)(age_ms / 1000));
    else snprintf(out, cap, "%lu min ago", (unsigned long)(age_ms / 60000));
}

static void cat_status(cat_t c, cat_status_t *o)
{
    bc_profile_t *p = app_profile();
    app_live_t lv; app_live(&lv);
    plat_phone_status_t ps; plat_phone_status(&ps);
    memset(o, 0, sizeof *o); o->color = C_MUT;
    switch (c) {
    case CAT_PHONE:
        if (!p->phone_on) snprintf(o->txt, sizeof o->txt, "off");
        else if (ps.state == PLAT_PHONE_READY) { snprintf(o->txt, sizeof o->txt, "connected"); o->color = C_GREEN; o->connected = true; }
        else if (ps.state == PLAT_PHONE_PAIRING || ps.state == PLAT_PHONE_CONNECTED) { snprintf(o->txt, sizeof o->txt, "pairing"); o->color = C_AMBER; }
        else if (ps.bonded) { snprintf(o->txt, sizeof o->txt, "! not connected"); o->color = C_RED; o->alert = true; }
        else snprintf(o->txt, sizeof o->txt, "not paired");
        break;
    case CAT_WIFI: {
        plat_wifi_status_t ws; plat_wifi_status(&ws);
        char saved[PLAT_WIFI_MAX_SAVED][33]; int ns = plat_wifi_saved(saved, PLAT_WIFI_MAX_SAVED);
        if (!p->wifi_on) snprintf(o->txt, sizeof o->txt, "off");
        else if (ws.state == PLAT_WIFI_CONNECTED) { snprintf(o->txt, sizeof o->txt, "%.14s", ws.ssid); o->color = C_GREEN; o->connected = true; }
        else if (ws.state == PLAT_WIFI_CONNECTING || ws.state == PLAT_WIFI_SCANNING) { snprintf(o->txt, sizeof o->txt, ws.state == PLAT_WIFI_SCANNING ? "scanning" : "connecting"); o->color = C_AMBER; }
        else if (ws.state == PLAT_WIFI_FAILED && ws.err == PLAT_WIFI_ERR_WRONG_PASSWORD) { snprintf(o->txt, sizeof o->txt, "! wrong password"); o->color = C_RED; o->alert = true; }
        else if (ns > 0) { snprintf(o->txt, sizeof o->txt, "no network"); o->color = C_AMBER; }
        else snprintf(o->txt, sizeof o->txt, "on, none saved");
        break; }
    case CAT_POWER: {
        const plat_link_info_t *l = &lv.link[PLAT_SENS_POWER];
        if (lv.demo) { snprintf(o->txt, sizeof o->txt, "SIMULATED"); o->color = C_DEMO; o->connected = true; }
        else if (!p->power.paired) snprintf(o->txt, sizeof o->txt, "pair");
        else if (lv.power_ok) { snprintf(o->txt, sizeof o->txt, "%d W", lv.watts); o->color = C_GREEN; o->connected = true; }
        else if (l->link == PLAT_LINK_CONNECTED) { snprintf(o->txt, sizeof o->txt, "no data"); o->color = C_AMBER; o->connected = true; }
        else if (l->link == PLAT_LINK_CONNECTING) { snprintf(o->txt, sizeof o->txt, "connecting"); o->color = C_AMBER; }
        else { snprintf(o->txt, sizeof o->txt, "! missing"); o->color = C_RED; o->alert = true; }
        break; }
    case CAT_HR: {
        const plat_link_info_t *l = &lv.link[PLAT_SENS_HR];
        if (lv.hr_ok) { snprintf(o->txt, sizeof o->txt, "%d bpm", lv.bpm); o->color = C_GREEN; o->connected = true; }
        else if (p->hr.paired && l->link != PLAT_LINK_CONNECTED) { snprintf(o->txt, sizeof o->txt, l->link == PLAT_LINK_CONNECTING ? "connecting" : "! strap away"); o->color = l->link == PLAT_LINK_CONNECTING ? C_AMBER : C_RED; o->alert = l->link != PLAT_LINK_CONNECTING; }
        else if (p->hr.paired) { snprintf(o->txt, sizeof o->txt, "no data"); o->color = C_AMBER; o->connected = true; }
        else if (ps.state == PLAT_PHONE_READY) snprintf(o->txt, sizeof o->txt, "none via phone");
        else snprintf(o->txt, sizeof o->txt, "none");
        break; }
    case CAT_CADENCE: {
        const plat_link_info_t *l = &lv.link[PLAT_SENS_CSC];
        if (lv.cad_ok) { snprintf(o->txt, sizeof o->txt, "%d rpm", lv.rpm); o->color = C_GREEN; o->connected = true; }
        else if (p->csc.paired && l->link != PLAT_LINK_CONNECTED) { snprintf(o->txt, sizeof o->txt, "! sensor away"); o->color = C_RED; o->alert = true; }
        else if (p->power.paired || p->csc.paired) { snprintf(o->txt, sizeof o->txt, "no data"); o->color = C_AMBER; }
        else snprintf(o->txt, sizeof o->txt, "none");
        break; }
    case CAT_SPEED: {
        const plat_link_info_t *l = &lv.link[PLAT_SENS_CSC], *g = &lv.link[PLAT_SENS_SPEED];
        if (lv.speed_ok) { snprintf(o->txt, sizeof o->txt, "%d.%d km/h", lv.speed_dmh / 10, lv.speed_dmh % 10); o->color = C_GREEN; o->connected = true; }
        else if (p->csc.paired && l->link != PLAT_LINK_CONNECTED) { snprintf(o->txt, sizeof o->txt, "! sensor away"); o->color = C_RED; o->alert = true; }
        else if (g->link == PLAT_LINK_STALE) { snprintf(o->txt, sizeof o->txt, "GPS stale"); o->color = C_AMBER; }
        else if (g->link == PLAT_LINK_SEARCHING) { snprintf(o->txt, sizeof o->txt, "waiting GPS"); o->color = C_AMBER; }
        else snprintf(o->txt, sizeof o->txt, "none");
        break; }
    case CAT_OTHER: snprintf(o->txt, sizeof o->txt, "scan " LV_SYMBOL_RIGHT); o->color = C_CYAN; break;
    case CAT_SYNC: {
        app_psvc_stats_t st; app_psvc_stats(&st);
        if (ps.state == PLAT_PHONE_READY) { snprintf(o->txt, sizeof o->txt, p->prof_src ? "phone v%lu" : "device only", (unsigned long)p->phone_prof_ver); o->color = C_GREEN; o->connected = true; }
        else if (p->prof_src) { snprintf(o->txt, sizeof o->txt, "phone v%lu", (unsigned long)p->phone_prof_ver); }
        else snprintf(o->txt, sizeof o->txt, "device only");
        break; }
    default: break;
    }
}

void ui_conn_summary(int *connected, int *alerts)
{
    int c = 0, a = 0;
    for (int k = 0; k < CAT_COUNT; k++) { if (k == CAT_OTHER || k == CAT_SYNC) continue; cat_status_t s; cat_status((cat_t)k, &s); c += s.connected; a += s.alert; }
    *connected = c; *alerts = a;
}

/* ---- return target for the Phone and Wi-Fi pages (they are reachable from Settings too) */
static bool s_ret_conn;
void ui_set_return_connections(bool from_connections) { s_ret_conn = from_connections; }
void ui_return(void) { if (s_ret_conn) { s_ret_conn = false; ui_connections_show(); } else ui_settings_show(); }

/* ---- the menu */
static lv_obj_t *m_rows[CAT_COUNT];
static void menu_update(void)
{
    for (int k = 0; k < CAT_COUNT; k++) {
        cat_status_t s; cat_status((cat_t)k, &s);
        if (!m_rows[k]) continue;
        ui_row_set_value(m_rows[k], s.txt, s.color);
    }
}
static void detail_cb(lv_event_t *e) { ui_conn_detail_show((int)(intptr_t)lv_event_get_user_data(e)); }
static void back_home(lv_event_t *e) { (void)e; ui_home_show(); }

void ui_connections_show(void)
{
    s_ret_conn = false;
    lv_obj_t *scr = ui_screen_new(UI_SCR_SENSORS, menu_update);
    ui_title(scr, "CONNECTIONS");
    lv_obj_t *list = ui_scroll_area(scr, 50, 180);
    for (int k = 0; k < CAT_COUNT; k++) {
        m_rows[k] = ui_row_btn(list, CAT_NAME[k], "", C_MUT, detail_cb, (void *)(intptr_t)k);
        lv_obj_set_style_text_font(lv_obj_get_child(m_rows[k], 1), &lv_font_montserrat_12, 0);
    }
    lv_obj_t *n = ui_label(list, &lv_font_montserrat_12, C_MUT, "DIRECT = this board's Bluetooth\nVIA PHONE = relayed by the app\n! = set up but missing now");
    lv_obj_set_width(n, lv_pct(100)); lv_label_set_long_mode(n, LV_LABEL_LONG_WRAP);
    menu_update();
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 40, back_home, NULL);
    lv_obj_align(bk, LV_ALIGN_TOP_MID, 0, 184);
    ui_screen_show(scr);
}
void ui_sensors_show(void) { ui_connections_show(); }   /* old name, kept for the callers and the test harness */

/* ---- detail pages */
static cat_t d_cat;
static lv_obj_t *d_txt, *d_list, *d_val;
static plat_found_t d_found[12]; static int d_nfound = -1; static uint32_t d_t0;

static void back_menu(lv_event_t *e) { (void)e; plat_scan_end(); ui_connections_show(); }
static void pair_power_cb(lv_event_t *e) { (void)e; ui_pair_show(PLAT_SENS_POWER, false); }
static void pair_hr_cb(lv_event_t *e) { (void)e; ui_pair_show(PLAT_SENS_HR, false); }
static void pair_csc_cb(lv_event_t *e) { (void)e; ui_pair_show(PLAT_SENS_CSC, false); }
static void hr_pref_cb(lv_event_t *e) { (void)e; bc_profile_t *p = app_profile(); p->hr_pref = p->hr_pref ? 0 : 1; app_profile_save(); ui_conn_detail_show(CAT_HR); }
static void forget_cb(lv_event_t *e)
{
    plat_sens_kind_t k = (plat_sens_kind_t)(intptr_t)lv_event_get_user_data(e);
    bc_profile_t *pr = app_profile();
    bc_sensor_pair_t *sp = k == PLAT_SENS_POWER ? &pr->power : k == PLAT_SENS_HR ? &pr->hr : &pr->csc;
    memset(sp, 0, sizeof *sp); app_profile_save(); plat_pair(k, NULL);
    ui_conn_detail_show(d_cat);
}
static void reconnect_cb(lv_event_t *e)
{
    plat_sens_kind_t k = (plat_sens_kind_t)(intptr_t)lv_event_get_user_data(e);
    bc_profile_t *pr = app_profile();
    bc_sensor_pair_t *sp = k == PLAT_SENS_POWER ? &pr->power : k == PLAT_SENS_HR ? &pr->hr : &pr->csc;
    if (!sp->paired) return;
    plat_found_t f; memcpy(f.mac, sp->mac, 6); f.addr_type = sp->addr_type; snprintf(f.name, sizeof f.name, "%s", sp->name); f.rssi = 0; f.svcs = 0;
    plat_pair(k, &f);   /* drops the link (if any) and searches again from the stored address */
}
static void wheel_cb(lv_event_t *e)
{
    int d = (int)(intptr_t)lv_event_get_user_data(e);
    bc_profile_t *p = app_profile();
    int v = p->wheel_mm + d; if (v < 1000) v = 1000; if (v > 2600) v = 2600;
    p->wheel_mm = (uint16_t)v; app_profile_save(); plat_csc_wheel_mm(p->wheel_mm);
    char b[20]; snprintf(b, sizeof b, "%u mm", p->wheel_mm); if (d_val) lv_label_set_text(d_val, b);
}
static void sensor_test_cb(lv_event_t *e) { (void)e; ui_sensor_test_show(false); }

static const char *link_word(plat_link_t l, bool paired)
{
    if (!paired) return "NOT PAIRED";
    switch (l) { case PLAT_LINK_CONNECTED: return "CONNECTED"; case PLAT_LINK_CONNECTING: return "CONNECTING"; case PLAT_LINK_SEARCHING: case PLAT_LINK_RETRY: return "DISCONNECTED - searching";
                 case PLAT_LINK_OFF: return "DISABLED"; case PLAT_LINK_UNSUPPORTED: return "UNSUPPORTED"; default: return ui_link_text(l); }
}

static void detail_update(void)
{
    bc_profile_t *p = app_profile();
    app_live_t lv; app_live(&lv);
    static char b[720]; char age[24], sig[20];
    b[0] = 0;
    switch (d_cat) {
    case CAT_POWER: {
        const plat_link_info_t *l = &lv.link[PLAT_SENS_POWER];
        sig[0] = 0; if (l->link == PLAT_LINK_CONNECTED && l->rssi) snprintf(sig, sizeof sig, "  %d dBm", l->rssi);
        age_text(l->valid_age_ms, age, sizeof age);
        if (lv.demo) snprintf(b, sizeof b, "#ff8a1f SIMULATED (demo mode)#\n%d W  %d rpm\nno real meter is read while demo is on", lv.watts, lv.rpm);
        else {
            snprintf(b, sizeof b, "#%06x %s#%s  #8494a0 DIRECT#\n%s\n#8494a0 LAST DATA# %s\n#8494a0 MEASURES# power (W), cadence (rpm)\n",
                     ui_hex(ui_link_color(p->power.paired ? l->link : PLAT_LINK_NOT_PAIRED)), link_word(l->link, p->power.paired), sig, p->power.paired ? p->power.name : "XDS / Branta meter", age);
            size_t n = strlen(b);
            if (lv.power_ok) snprintf(b + n, sizeof b - n, "#56e08c %d W  %d rpm#  (%lu pkts, %lu bad)\n", lv.watts, lv.cad_ok ? lv.rpm : 0, (unsigned long)l->packets, (unsigned long)l->rejected);
            else if (l->link == PLAT_LINK_CONNECTED) snprintf(b + n, sizeof b - n, "#ffb64d NO DATA# - pedal to wake the meter\n");
            n = strlen(b);
            snprintf(b + n, sizeof b - n, "#8494a0 POWER ACCURACY# unverified until a\ncalibration ride is validated\n#8494a0 CALIBRATION# not available: this\nfirmware never writes to the meter's\ncontrol point (safety rule)\n");
            if (p->power.paired && l->link != PLAT_LINK_CONNECTED) { n = strlen(b); snprintf(b + n, sizeof b - n, "#ff5a5a IF IT DOES NOT CONNECT:# wake the\nmeter (pedal), check its battery, stay\nwithin 3 m, or RECONNECT below"); }
        }
        break; }
    case CAT_HR: {
        const plat_link_info_t *l = &lv.link[PLAT_SENS_HR];
        plat_phone_status_t ps; plat_phone_status(&ps);
        sig[0] = 0; if (l->link == PLAT_LINK_CONNECTED && l->rssi) snprintf(sig, sizeof sig, "  %d dBm", l->rssi);
        age_text(l->valid_age_ms, age, sizeof age);
        char shown[40]; if (lv.hr_ok) snprintf(shown, sizeof shown, "#56e08c %d bpm# from %s", lv.bpm, bc_src_name(lv.hr_src)); else snprintf(shown, sizeof shown, "#ffb64d NO DATA#");
        snprintf(b, sizeof b, "%s\n#8494a0 STRAP#  DIRECT\n#%06x %s#%s %s\n#8494a0 WATCH / PHONE#  VIA PHONE\n#%06x %s#\n#8494a0 WHOOP#  CLOUD\n#8494a0 unsupported - planned#\n#8494a0 PREFERENCE# %s\nthe other source is the backup\n",
                 shown, ui_hex(ui_link_color(p->hr.paired ? l->link : PLAT_LINK_NOT_PAIRED)), link_word(l->link, p->hr.paired), sig, p->hr.paired ? p->hr.name : "",
                 ui_hex(lv.phone_hr ? C_GREEN : ps.state == PLAT_PHONE_READY ? C_MUT : C_FAINT),
                 lv.phone_hr ? "live" : ps.state == PLAT_PHONE_READY ? "connected, no HR yet" : "phone not connected",
                 p->hr_pref ? "watch first" : "strap first");
        if (p->hr.paired && l->link != PLAT_LINK_CONNECTED) { size_t n = strlen(b); snprintf(b + n, sizeof b - n, "#ff5a5a STRAP MISSING:# wet the pads, wear it\n30 s, check its battery, or RECONNECT"); }
        break; }
    case CAT_CADENCE: {
        const plat_link_info_t *l = &lv.link[PLAT_SENS_CSC];
        plat_sensors_t s; plat_sensors(&s);
        age_text(l->valid_age_ms, age, sizeof age);
        char shown[48]; if (lv.cad_ok) snprintf(shown, sizeof shown, "#56e08c %d rpm# from %s", lv.rpm, lv.cad_src == BC_SRC_XDS ? "the power meter" : bc_src_name(lv.cad_src)); else snprintf(shown, sizeof shown, "#ffb64d NO DATA#");
        snprintf(b, sizeof b, "%s\n#8494a0 POWER METER#  DIRECT\n#%06x %s# - cadence comes with power\n#8494a0 CADENCE SENSOR#  DIRECT (BLE CSC)\n#%06x %s# %s\n%s\n",
                 shown, ui_hex(ui_link_color(p->power.paired ? lv.link[PLAT_SENS_POWER].link : PLAT_LINK_NOT_PAIRED)), link_word(lv.link[PLAT_SENS_POWER].link, p->power.paired),
                 ui_hex(ui_link_color(p->csc.paired ? l->link : PLAT_LINK_NOT_PAIRED)), link_word(l->link, p->csc.paired), p->csc.paired ? p->csc.name : "",
                 p->csc.paired ? (l->link == PLAT_LINK_CONNECTED ? (s.csc_has_crank ? "crank data: yes" : "this sensor has no crank data") : age) : "pair one if you ride without\nthe power meter");
        if (p->csc.paired && l->link != PLAT_LINK_CONNECTED) { size_t n = strlen(b); snprintf(b + n, sizeof b - n, "#ff5a5a SENSOR MISSING:# spin the crank to\nwake it, check its battery, RECONNECT"); }
        break; }
    case CAT_SPEED: {
        const plat_link_info_t *l = &lv.link[PLAT_SENS_CSC], *g = &lv.link[PLAT_SENS_SPEED];
        plat_sensors_t s; plat_sensors(&s);
        char shown[64]; if (lv.speed_ok) snprintf(shown, sizeof shown, "#56e08c %d.%d km/h# from %s", lv.speed_dmh / 10, lv.speed_dmh % 10, bc_src_name(lv.speed_src)); else snprintf(shown, sizeof shown, "#ffb64d NO DATA#");
        char gps[72]; age_text(g->age_ms, age, sizeof age);
        if (g->link == PLAT_LINK_NOT_PAIRED) snprintf(gps, sizeof gps, "#8494a0 phone not connected#");
        else snprintf(gps, sizeof gps, "#%06x %s# %s", ui_hex(ui_link_color(g->link)), g->link == PLAT_LINK_CONNECTED ? "live" : g->link == PLAT_LINK_STALE ? "STALE" : "waiting for a fix", g->link == PLAT_LINK_CONNECTED ? "" : age);
        snprintf(b, sizeof b, "%s\n#8494a0 WHEEL SENSOR#  DIRECT (BLE CSC)\n#%06x %s# %s\n%s\n#8494a0 PHONE GPS#  VIA PHONE\n%s\n#8494a0 WHEEL# circumference for the sensor\n(700x25c = 2096 mm)\n",
                 shown, ui_hex(ui_link_color(p->csc.paired ? l->link : PLAT_LINK_NOT_PAIRED)), link_word(l->link, p->csc.paired), p->csc.paired ? p->csc.name : "",
                 p->csc.paired ? (l->link == PLAT_LINK_CONNECTED ? (s.csc_has_wheel ? "wheel data: yes" : "this sensor has no wheel data") : "") : "the same sensor as Cadence", gps);
        break; }
    case CAT_OTHER: {
        plat_found_t f[12]; int n = plat_scan_results(f, 12);
        if (n == d_nfound && n >= 0 && !memcmp(f, d_found, sizeof(plat_found_t) * (size_t)n)) return;
        d_nfound = n; memcpy(d_found, f, sizeof(plat_found_t) * (size_t)n);
        lv_obj_clean(d_list);
        for (int i = 0; i < n; i++) {
            char tag[24]; tag[0] = 0;
            if (f[i].svcs & PLAT_SVC_POWER) strcat(tag, "PWR ");
            if (f[i].svcs & PLAT_SVC_HR) strcat(tag, "HR ");
            if (f[i].svcs & PLAT_SVC_CSC) strcat(tag, "CSC ");
            if (f[i].svcs & PLAT_SVC_FTMS) strcat(tag, "TRAINER ");
            if (!tag[0]) snprintf(tag, sizeof tag, "%d", f[i].rssi);
            bool compat = f[i].svcs & (PLAT_SVC_POWER | PLAT_SVC_HR | PLAT_SVC_CSC);
            lv_obj_t *r = ui_row_btn(d_list, f[i].name[0] ? f[i].name : "(no name)", tag, compat ? C_GREEN : C_MUT, NULL, NULL);
            lv_obj_remove_flag(r, LV_OBJ_FLAG_CLICKABLE);
            lv_obj_set_style_text_font(lv_obj_get_child(r, 0), &lv_font_montserrat_12, 0);
            lv_obj_set_style_text_font(lv_obj_get_child(r, 1), &lv_font_montserrat_12, 0);
        }
        if (n == 0) ui_label(d_list, &lv_font_montserrat_12, C_MUT, plat_ms() - d_t0 > 15000 ? "nothing found yet" : "searching...");
        lv_obj_t *h = ui_label(d_list, &lv_font_montserrat_12, C_MUT, "green = compatible: pair it under\nPower meter, Heart rate or Cadence.\nOthers are listed only, not paired.");
        lv_obj_set_width(h, lv_pct(100)); lv_label_set_long_mode(h, LV_LABEL_LONG_WRAP);
        return; }
    case CAT_SYNC: {
        app_psvc_stats_t st; app_psvc_stats(&st);
        plat_phone_status_t ps; plat_phone_status(&ps);
        bc_ride_summary_t h[1]; int nh = app_history(h, 1, false);
        char t1[32], t2[32], t3[32];
        uint32_t now = plat_ms();
        if (st.last_sync_ms) age_text(now - st.last_sync_ms, t1, sizeof t1); else snprintf(t1, sizeof t1, "none this session");
        if (st.last_profile_ms) age_text(now - st.last_profile_ms, t2, sizeof t2); else snprintf(t2, sizeof t2, "not this session");
        if (st.last_settings_ms) age_text(now - st.last_settings_ms, t3, sizeof t3); else snprintf(t3, sizeof t3, "not this session");
        snprintf(b, sizeof b, "#%06x %s#\n#8494a0 ATHLETE PROFILE#\n%s\napplied: %s\n#8494a0 SETTINGS# v%lu\napplied: %s\n#8494a0 RIDE TRANSFER#\n%d ride%s here, newest #%u\nsent this session: %lu%s\n#8494a0 LAST SUCCESSFUL SYNC#\n%s\n\nOnce confirmed on the phone, the\nphone is the authority for the shared\nathlete settings. Rides, sensor\npairings and calibration never\nchange through sync.",
                 ui_hex(ps.state == PLAT_PHONE_READY ? C_GREEN : C_MUT), ps.state == PLAT_PHONE_READY ? "PHONE CONNECTED" : "PHONE NOT CONNECTED",
                 p->prof_src ? "from the phone, version" : "this device only", t2, (unsigned long)p->sett_ver, t3,
                 nh, nh == 1 ? "" : "s", nh ? h[0].id : 0, (unsigned long)st.rides_sent, st.sync_active ? " (sending)" : "", t1);
        /* the profile version goes on its own line */
        if (p->prof_src) { char v[24]; snprintf(v, sizeof v, " %lu", (unsigned long)p->phone_prof_ver); char *at = strstr(b, "version\n"); if (at) { memmove(at + 7 + strlen(v), at + 7, strlen(at + 7) + 1); memcpy(at + 7, v, strlen(v)); } }
        break; }
    default: break;
    }
    if (d_txt) lv_label_set_text(d_txt, b);
}

void ui_conn_detail_show(int cat)
{
    d_cat = (cat_t)cat;
    if (d_cat == CAT_PHONE) { s_ret_conn = true; ui_phone_show(); return; }
    if (d_cat == CAT_WIFI) { s_ret_conn = true; ui_wifi_show(); return; }
    bc_profile_t *p = app_profile();
    lv_obj_t *scr = ui_screen_new(UI_SCR_SENSORS, detail_update);
    ui_title(scr, d_cat == CAT_POWER ? "POWER METER" : d_cat == CAT_HR ? "HEART RATE" : d_cat == CAT_CADENCE ? "CADENCE" : d_cat == CAT_SPEED ? "SPEED" : d_cat == CAT_OTHER ? "BLUETOOTH" : "DEVICE SYNC");
    d_list = ui_scroll_area(scr, 50, 180);
    d_txt = NULL; d_val = NULL;
    if (d_cat != CAT_OTHER) {
        d_txt = ui_label(d_list, &lv_font_montserrat_12, C_FG, "");
        lv_obj_set_width(d_txt, lv_pct(100)); lv_label_set_long_mode(d_txt, LV_LABEL_LONG_WRAP); lv_label_set_recolor(d_txt, true);
    }
    switch (d_cat) {
    case CAT_POWER:
        ui_pill(d_list, p->power.paired ? "PAIR ANOTHER" : "PAIR METER", C_PANEL, C_CYAN, 150, 34, pair_power_cb, NULL);
        if (p->power.paired) { ui_pill(d_list, "RECONNECT", C_PANEL, C_CYAN, 150, 34, reconnect_cb, (void *)PLAT_SENS_POWER);
                               ui_hold_btn(d_list, "HOLD: FORGET", C_PANEL, C_RED, 150, 34, 1500, forget_cb, (void *)PLAT_SENS_POWER); }
        ui_pill(d_list, "SENSOR TEST", C_PANEL, C_CYAN, 150, 34, sensor_test_cb, NULL);
        break;
    case CAT_HR:
        ui_pill(d_list, p->hr.paired ? "PAIR ANOTHER STRAP" : "PAIR HR STRAP", C_PANEL, C_CYAN, 170, 34, pair_hr_cb, NULL);
        if (p->hr.paired) { ui_pill(d_list, "RECONNECT", C_PANEL, C_CYAN, 150, 34, reconnect_cb, (void *)PLAT_SENS_HR);
                            ui_hold_btn(d_list, "HOLD: FORGET", C_PANEL, C_RED, 150, 34, 1500, forget_cb, (void *)PLAT_SENS_HR); }
        ui_pill(d_list, p->hr_pref ? "HR: WATCH FIRST" : "HR: STRAP FIRST", C_PANEL, C_CYAN, 160, 34, hr_pref_cb, NULL);
        break;
    case CAT_CADENCE: case CAT_SPEED:
        ui_pill(d_list, p->csc.paired ? "PAIR ANOTHER" : "PAIR SENSOR", C_PANEL, C_CYAN, 150, 34, pair_csc_cb, NULL);
        if (p->csc.paired) { ui_pill(d_list, "RECONNECT", C_PANEL, C_CYAN, 150, 34, reconnect_cb, (void *)PLAT_SENS_CSC);
                             ui_hold_btn(d_list, "HOLD: FORGET", C_PANEL, C_RED, 150, 34, 1500, forget_cb, (void *)PLAT_SENS_CSC); }
        if (d_cat == CAT_SPEED) {
            lv_obj_t *row = lv_obj_create(d_list); lv_obj_remove_style_all(row); lv_obj_set_size(row, lv_pct(100), 40); lv_obj_remove_flag(row, LV_OBJ_FLAG_SCROLLABLE);
            lv_obj_t *m = ui_pill(row, "-10", C_PANEL, C_CYAN, 48, 34, wheel_cb, (void *)(intptr_t)-10); lv_obj_align(m, LV_ALIGN_LEFT_MID, 0, 0);
            char v[20]; snprintf(v, sizeof v, "%u mm", p->wheel_mm);
            d_val = ui_label(row, &lv_font_montserrat_14, C_FG, v); lv_obj_align(d_val, LV_ALIGN_CENTER, 0, 0);
            lv_obj_t *pl = ui_pill(row, "+10", C_PANEL, C_CYAN, 48, 34, wheel_cb, (void *)(intptr_t)10); lv_obj_align(pl, LV_ALIGN_RIGHT_MID, 0, 0);
        }
        break;
    case CAT_OTHER:
        d_nfound = -1; d_t0 = plat_ms(); plat_scan_begin(PLAT_SENS_ANY);
        break;
    default: break;
    }
    detail_update();
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 40, back_menu, NULL);
    lv_obj_align(bk, LV_ALIGN_TOP_MID, 0, 184);
    ui_screen_show(scr);
}
