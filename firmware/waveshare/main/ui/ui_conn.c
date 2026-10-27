/*
 * Connections (firmware 0.6.0, compact round-screen layout 0.7.2).
 *
 * Home = a live table: PHONE / POWER / HEART / CADENCE (/ SPEED only when a speed/cadence sensor is paired), then Wi-Fi,
 * Other Bluetooth and Device sync below the fold. Each row: short label, status icon, and either the FRESH value
 * ("142 W", "151 BPM", "82 RPM") or a one/two-word state ("NO DATA", "SEARCHING", "OFF"). Values come only from a
 * sensor whose pipeline stage is VALID (bc_pipe.h): "connected" alone is never shown as working.
 *
 * Detail pages (Power meter, Heart rate, Cadence, Speed): one status line, one detail line, ONE primary action visible
 * without scrolling (PAIR / RETRY / TEST), HELP + HOLD: FORGET, and Back — nothing to scroll. Explanations live on the
 * separate Help page of each category.
 *
 * The red "!" (Home / Settings / Quick Settings summary) appears only for a connection the rider configured and that is
 * missing right now; optional devices that were never set up stay grey.
 */
#include "ui.h"
#include "app_psvc.h"
#include "bc_pipe.h"
#include "app_diag.h"
#include <stdio.h>
#include <string.h>

typedef enum { CAT_PHONE = 0, CAT_WIFI, CAT_POWER, CAT_HR, CAT_CADENCE, CAT_SPEED, CAT_OTHER, CAT_SYNC, CAT_COUNT } cat_t;

/* ---- the status model (table rows, detail pages, Device Health, Home summary) */
static void age_text(uint32_t age_ms, char *out, size_t cap)
{
    if (age_ms == UINT32_MAX) snprintf(out, cap, "no data yet");
    else if (age_ms < 2000) snprintf(out, cap, "live");
    else if (age_ms < 120000) snprintf(out, cap, "%lus ago", (unsigned long)(age_ms / 1000));
    else snprintf(out, cap, "%lu min ago", (unsigned long)(age_ms / 60000));
}

const char *ui_stage_word(const plat_link_info_t *l)
{
    if (l->stage != BC_STG_NOT_PAIRED && plat_bt_unavailable(NULL, 0)) return "NO BLUETOOTH";   /* 0.7.4 */
    if (l->disabled) return "DISABLED";              /* 0.7.3: disabled after a crash (staged boot) - RETRY */
    switch ((bc_stage_t)l->stage) {
    case BC_STG_NOT_PAIRED: return "NOT PAIRED";
    case BC_STG_SEARCHING: return l->link == PLAT_LINK_RETRY ? "RETRYING" : "SEARCHING";
    case BC_STG_CONNECTING: case BC_STG_CONNECTED: return "CONNECTING";
    case BC_STG_SUBSCRIBED: return "NO DATA";
    case BC_STG_RECEIVING: return l->unreadable ? "BAD DATA" : "NO DATA";
    case BC_STG_VALID: return "LIVE";
    case BC_STG_STALE: return "STALE";
    case BC_STG_ERROR: return "ERROR";
    }
    return "?";
}

/* one line for Device Health / detail pages: "connected - no data", "reconnecting", "error: no CCCD", ... */
static void stage_line(const plat_link_info_t *l, char *b, size_t cap)
{
    if (l->stage != BC_STG_NOT_PAIRED && plat_bt_unavailable(NULL, 0)) { snprintf(b, cap, "Bluetooth unavailable"); return; }   /* 0.7.4 */
    if (l->disabled) { snprintf(b, cap, "off after a crash"); return; }
    switch ((bc_stage_t)l->stage) {
    case BC_STG_NOT_PAIRED: snprintf(b, cap, "not paired"); break;
    case BC_STG_SEARCHING: snprintf(b, cap, l->link == PLAT_LINK_RETRY ? "reconnecting" : "searching"); break;
    case BC_STG_CONNECTING: snprintf(b, cap, "connecting"); break;
    case BC_STG_CONNECTED: snprintf(b, cap, "connected - setting up"); break;
    case BC_STG_SUBSCRIBED: snprintf(b, cap, "connected - no data"); break;
    case BC_STG_RECEIVING: snprintf(b, cap, l->unreadable ? "unreadable data" : "receiving - not valid yet"); break;
    case BC_STG_VALID: snprintf(b, cap, "live"); break;
    case BC_STG_STALE: snprintf(b, cap, "data stale %lus", (unsigned long)(l->valid_age_ms == UINT32_MAX ? 0 : l->valid_age_ms / 1000)); break;
    case BC_STG_ERROR: snprintf(b, cap, "error: %s", l->err[0] ? l->err : "?"); break;
    }
}

static lv_color_t stage_color(const plat_link_info_t *l)
{
    switch ((bc_stage_t)l->stage) {
    case BC_STG_VALID: return C_GREEN;
    case BC_STG_NOT_PAIRED: return C_MUT;
    case BC_STG_ERROR: case BC_STG_STALE: return C_RED;
    case BC_STG_SUBSCRIBED: case BC_STG_RECEIVING: return l->unreadable ? C_RED : C_AMBER;
    default: return C_AMBER;
    }
}
static const char *icon_for(lv_color_t c)
{
    if (lv_color_eq(c, C_GREEN)) return LV_SYMBOL_OK;
    if (lv_color_eq(c, C_RED)) return LV_SYMBOL_WARNING;
    if (lv_color_eq(c, C_AMBER)) return LV_SYMBOL_REFRESH;
    return LV_SYMBOL_MINUS;
}

/* a paired sensor's row from its pipeline stage; value only at VALID (set by the caller) */
static void sensor_state(const plat_link_info_t *l, ui_row_status_t *o)
{
    if (plat_bt_unavailable(NULL, 0)) {                /* 0.7.4: no radio this boot - never "searching" */
        snprintf(o->value, sizeof o->value, "NO BT"); snprintf(o->line, sizeof o->line, "Bluetooth unavailable");
        o->color = C_RED; o->connected = false; o->alert = true; return;
    }
    if (l->disabled) {
        snprintf(o->value, sizeof o->value, "DISABLED"); snprintf(o->line, sizeof o->line, "off after a crash");
        o->color = C_AMBER; o->connected = false; o->alert = true; return;
    }
    snprintf(o->value, sizeof o->value, "%s", ui_stage_word(l));
    stage_line(l, o->line, sizeof o->line);
    o->color = stage_color(l);
    o->connected = l->stage >= BC_STG_CONNECTED && l->stage != BC_STG_ERROR;
    o->alert = l->stage == BC_STG_SEARCHING || l->stage == BC_STG_ERROR || l->stage == BC_STG_STALE || l->unreadable;
}

void ui_conn_row_status(int row, ui_row_status_t *o)
{
    bc_profile_t *p = app_profile();
    app_live_t lv; app_live(&lv);
    plat_phone_status_t ps; plat_phone_status(&ps);
    memset(o, 0, sizeof *o); o->color = C_MUT;
    switch (row) {
    case UI_ROW_PHONE:
        if (ps.state == PLAT_PHONE_UNAVAILABLE) { snprintf(o->value, sizeof o->value, "NO BT"); snprintf(o->line, sizeof o->line, "Bluetooth unavailable"); o->color = C_RED; o->alert = true; }
        else if (!p->phone_on) { snprintf(o->value, sizeof o->value, "OFF"); snprintf(o->line, sizeof o->line, "link off"); }
        else if (ps.state == PLAT_PHONE_READY) { snprintf(o->value, sizeof o->value, "CONNECTED"); snprintf(o->line, sizeof o->line, "connected"); o->color = C_GREEN; o->connected = o->ok = true; }
        else if (ps.state == PLAT_PHONE_REPAIR) { snprintf(o->value, sizeof o->value, "REPAIR"); snprintf(o->line, sizeof o->line, "repair needed"); o->color = C_RED; o->alert = true; }
        else if (ps.state == PLAT_PHONE_PAIRING || ps.state == PLAT_PHONE_CONNECTED) { snprintf(o->value, sizeof o->value, "PAIRING"); snprintf(o->line, sizeof o->line, "pairing"); o->color = C_AMBER; }
        else if (ps.bonded) { snprintf(o->value, sizeof o->value, "SEARCHING"); snprintf(o->line, sizeof o->line, "not connected"); o->color = C_RED; o->alert = true; }
        else { snprintf(o->value, sizeof o->value, "NOT PAIRED"); snprintf(o->line, sizeof o->line, "not paired"); }
        break;
    case UI_ROW_WIFI: {
        plat_wifi_status_t ws; plat_wifi_status(&ws);
        char saved[PLAT_WIFI_MAX_SAVED][33]; int ns = plat_wifi_saved(saved, PLAT_WIFI_MAX_SAVED);
        if (!p->wifi_on) { snprintf(o->value, sizeof o->value, "OFF"); snprintf(o->line, sizeof o->line, "off"); }
        else if (ws.state == PLAT_WIFI_CONNECTED) { snprintf(o->value, sizeof o->value, "CONNECTED"); snprintf(o->line, sizeof o->line, "%.24s", ws.ssid); o->color = C_GREEN; o->connected = o->ok = true; }
        else if (ws.state == PLAT_WIFI_CONNECTING || ws.state == PLAT_WIFI_SCANNING) { snprintf(o->value, sizeof o->value, ws.state == PLAT_WIFI_SCANNING ? "SCANNING" : "CONNECTING"); snprintf(o->line, sizeof o->line, "%s", ws.state == PLAT_WIFI_SCANNING ? "scanning" : "connecting"); o->color = C_AMBER; }
        else if (ws.state == PLAT_WIFI_FAILED && ws.err == PLAT_WIFI_ERR_WRONG_PASSWORD) { snprintf(o->value, sizeof o->value, "WRONG PW"); snprintf(o->line, sizeof o->line, "wrong password"); o->color = C_RED; o->alert = true; }
        else if (ns > 0) { snprintf(o->value, sizeof o->value, "NO NETWORK"); snprintf(o->line, sizeof o->line, "saved network not in range"); o->color = C_AMBER; }
        else { snprintf(o->value, sizeof o->value, "NONE SAVED"); snprintf(o->line, sizeof o->line, "on, no network saved"); }
        break; }
    case UI_ROW_POWER: {
        const plat_link_info_t *l = &lv.link[PLAT_SENS_POWER];
        if (lv.demo) { snprintf(o->value, sizeof o->value, "%d W", lv.watts); snprintf(o->line, sizeof o->line, "SIMULATED %d W", lv.watts); o->color = C_DEMO; o->connected = o->ok = true; break; }
        if (!p->power.paired) { snprintf(o->value, sizeof o->value, "PAIR"); snprintf(o->line, sizeof o->line, "not paired"); break; }
        sensor_state(l, o);
        if (l->disabled) break;                       /* 0.7.3: disabled after a crash - no value is shown */
        if (lv.power_ok && l->stage == BC_STG_VALID) {
            snprintf(o->value, sizeof o->value, "%d W", lv.watts);
            if (lv.cad_ok && lv.cad_src == BC_SRC_XDS) snprintf(o->line, sizeof o->line, "live %d W %d rpm", lv.watts, lv.rpm); else snprintf(o->line, sizeof o->line, "live %d W", lv.watts);
            o->ok = true;
        } else if (l->stage == BC_STG_VALID) { snprintf(o->value, sizeof o->value, "NO DATA"); o->color = C_AMBER; }
        break; }
    case UI_ROW_HEART: {
        const plat_link_info_t *l = &lv.link[PLAT_SENS_HR];
        if (lv.hr_ok) {
            snprintf(o->value, sizeof o->value, "%d BPM", lv.bpm); snprintf(o->line, sizeof o->line, "live %d bpm %s", lv.bpm, bc_src_name(lv.hr_src));
            o->color = lv.demo ? C_DEMO : C_GREEN; o->connected = o->ok = true;
        } else if (p->hr.paired) sensor_state(l, o);
        else if (ps.state == PLAT_PHONE_READY) { snprintf(o->value, sizeof o->value, "NO DATA"); snprintf(o->line, sizeof o->line, "phone connected - no HR"); o->color = C_AMBER; }
        else { snprintf(o->value, sizeof o->value, "NONE"); snprintf(o->line, sizeof o->line, "no strap, no phone"); }
        break; }
    case UI_ROW_CADENCE: {
        const plat_link_info_t *l = &lv.link[PLAT_SENS_CSC];
        if (lv.cad_ok) {
            snprintf(o->value, sizeof o->value, "%d RPM", lv.rpm); snprintf(o->line, sizeof o->line, "live %d rpm %s", lv.rpm, lv.cad_src == BC_SRC_BLE_CSC ? "SENSOR" : lv.demo ? "DEMO" : "METER");
            o->color = lv.demo ? C_DEMO : C_GREEN; o->connected = o->ok = true;
        } else if (p->csc.paired && l->stage != BC_STG_VALID) sensor_state(l, o);
        else if (p->power.paired && !lv.demo) {
            sensor_state(&lv.link[PLAT_SENS_POWER], o);
            if (lv.link[PLAT_SENS_POWER].stage == BC_STG_VALID) { snprintf(o->value, sizeof o->value, "NO DATA"); snprintf(o->line, sizeof o->line, "meter sends no cadence"); o->color = C_AMBER; }
            o->alert = false;                            /* the POWER row carries the alert */
        } else if (p->csc.paired) { snprintf(o->value, sizeof o->value, "NO DATA"); snprintf(o->line, sizeof o->line, "sensor live, no crank data"); o->color = C_AMBER; }
        else { snprintf(o->value, sizeof o->value, "NONE"); snprintf(o->line, sizeof o->line, "no source"); }
        break; }
    case UI_ROW_SPEED: {
        const plat_link_info_t *l = &lv.link[PLAT_SENS_CSC], *g = &lv.link[PLAT_SENS_SPEED];
        if (lv.speed_ok) { snprintf(o->value, sizeof o->value, "%d.%d KM/H", lv.speed_dmh / 10, lv.speed_dmh % 10); snprintf(o->line, sizeof o->line, "live %d.%d km/h %s", lv.speed_dmh / 10, lv.speed_dmh % 10, bc_src_name(lv.speed_src)); o->color = C_GREEN; o->connected = o->ok = true; }
        else if (p->csc.paired && l->stage != BC_STG_VALID) sensor_state(l, o);
        else if (g->link == PLAT_LINK_STALE) { snprintf(o->value, sizeof o->value, "GPS STALE"); snprintf(o->line, sizeof o->line, "phone GPS stale"); o->color = C_AMBER; }
        else if (g->link == PLAT_LINK_SEARCHING) { snprintf(o->value, sizeof o->value, "NO FIX"); snprintf(o->line, sizeof o->line, "waiting for phone GPS"); o->color = C_AMBER; }
        else { snprintf(o->value, sizeof o->value, "NONE"); snprintf(o->line, sizeof o->line, "no source"); }
        break; }
    default: snprintf(o->value, sizeof o->value, "?"); break;
    }
    o->icon = icon_for(o->color);
}

void ui_conn_summary(int *connected, int *alerts)
{
    int c = 0, a = 0;
    for (int r = 0; r < UI_ROW_COUNT; r++) {
        if (r == UI_ROW_SPEED && !app_profile()->csc.paired) continue;
        if (r == UI_ROW_CADENCE) continue;            /* follows the power meter / CSC rows: not counted twice */
        ui_row_status_t s; ui_conn_row_status(r, &s); c += s.connected; a += s.alert;
    }
    *connected = c; *alerts = a;
}

/* ---- return target for the Phone and Wi-Fi pages (they are reachable from Settings too) */
static bool s_ret_conn;
void ui_set_return_connections(bool from_connections) { s_ret_conn = from_connections; }
void ui_return(void) { if (s_ret_conn) { s_ret_conn = false; ui_connections_show(); } else ui_settings_show(); }

/* ---- compact live row: [icon] LABEL ........ VALUE (0.7.2) */
typedef struct { lv_obj_t *btn, *icon, *name, *val; int row; } trow_t;
#define NTROW 8
static trow_t t_rows[NTROW]; static int t_n;

static lv_obj_t *table_row(lv_obj_t *list, const char *label, lv_event_cb_t cb, void *ud, int row)
{
    lv_obj_t *b = ui_row_btn(list, "", NULL, C_MUT, cb, ud);           /* the standard row button (style, touch size) */
    lv_obj_set_height(b, 31);
    lv_obj_t *ic = lv_obj_get_child(b, 0);                              /* its left label becomes the status icon */
    lv_obj_set_width(ic, 14); lv_obj_set_style_text_font(ic, &lv_font_montserrat_12, 0); lv_obj_align(ic, LV_ALIGN_LEFT_MID, 5, 0);
    lv_obj_t *nm = ui_label(b, &lv_font_montserrat_12, C_FG, label);
    lv_obj_set_style_text_align(nm, LV_TEXT_ALIGN_LEFT, 0); lv_obj_set_width(nm, 64); lv_label_set_long_mode(nm, LV_LABEL_LONG_MODE_CLIP);
    lv_obj_align(nm, LV_ALIGN_LEFT_MID, 22, 0);
    lv_obj_t *v = ui_label(b, &lv_font_montserrat_12, C_MUT, "");
    lv_obj_set_style_text_align(v, LV_TEXT_ALIGN_RIGHT, 0); lv_label_set_long_mode(v, LV_LABEL_LONG_MODE_CLIP);
    lv_obj_align(v, LV_ALIGN_RIGHT_MID, -6, 0);
    if (t_n < NTROW) { t_rows[t_n].btn = b; t_rows[t_n].icon = ic; t_rows[t_n].name = nm; t_rows[t_n].val = v; t_rows[t_n].row = row; t_n++; }
    return b;
}

static void table_update(void)
{
    for (int i = 0; i < t_n; i++) {
        trow_t *t = &t_rows[i];
        if (t->row < 0) continue;
        ui_row_status_t s; ui_conn_row_status(t->row, &s);
        lv_label_set_text(t->icon, s.icon); lv_obj_set_style_text_color(t->icon, s.color, 0);
        bool num = s.ok && s.value[0] >= '0' && s.value[0] <= '9';
        lv_obj_set_style_text_font(t->val, num ? &bc_bold16 : &lv_font_montserrat_12, 0);
        int bw = lv_obj_get_width(t->btn); if (bw < 100) { lv_obj_update_layout(t->btn); bw = lv_obj_get_width(t->btn); }
        int w = bw - 22 - 64 - 8; if (w < 40) w = 40;
        lv_obj_set_width(t->val, w);
        lv_obj_set_height(t->val, lv_font_get_line_height(num ? &bc_bold16 : &lv_font_montserrat_12) + 2);
        lv_label_set_text(t->val, s.value); lv_obj_set_style_text_color(t->val, s.color, 0);
        lv_obj_align(t->val, LV_ALIGN_RIGHT_MID, -6, 0);
    }
}
static void detail_cb(lv_event_t *e) { ui_conn_detail_show((int)(intptr_t)lv_event_get_user_data(e)); }
static void back_home(lv_event_t *e) { (void)e; ui_home_show(); }

void ui_connections_show(void)
{
    s_ret_conn = false;
    lv_obj_t *scr = ui_screen_new(UI_SCR_SENSORS, table_update);
    ui_title(scr, "CONNECTIONS");
    lv_obj_t *list = ui_scroll_area(scr, 50, 186);
    lv_obj_set_style_pad_row(list, 3, 0); lv_obj_set_style_pad_ver(list, 2, 0);
    t_n = 0;
    table_row(list, "PHONE", detail_cb, (void *)(intptr_t)CAT_PHONE, UI_ROW_PHONE);
    table_row(list, "POWER", detail_cb, (void *)(intptr_t)CAT_POWER, UI_ROW_POWER);
    table_row(list, "HEART", detail_cb, (void *)(intptr_t)CAT_HR, UI_ROW_HEART);
    table_row(list, "CADENCE", detail_cb, (void *)(intptr_t)CAT_CADENCE, UI_ROW_CADENCE);
    if (app_profile()->csc.paired) table_row(list, "SPEED", detail_cb, (void *)(intptr_t)CAT_SPEED, UI_ROW_SPEED);
    table_row(list, "WI-FI", detail_cb, (void *)(intptr_t)CAT_WIFI, UI_ROW_WIFI);
    { lv_obj_t *r = table_row(list, "MORE", detail_cb, (void *)(intptr_t)CAT_OTHER, -1);
      lv_label_set_text(lv_obj_get_child(r, 0), LV_SYMBOL_BLUETOOTH); lv_obj_set_style_text_color(lv_obj_get_child(r, 0), C_CYAN, 0);
      lv_obj_t *vl = lv_obj_get_child(r, 2); lv_obj_set_width(vl, 84); lv_label_set_text(vl, "BLUETOOTH"); lv_obj_set_style_text_color(vl, C_CYAN, 0); lv_obj_align(vl, LV_ALIGN_RIGHT_MID, -6, 0); }
    { lv_obj_t *r = table_row(list, "SYNC", detail_cb, (void *)(intptr_t)CAT_SYNC, -1);
      lv_label_set_text(lv_obj_get_child(r, 0), LV_SYMBOL_LOOP); lv_obj_set_style_text_color(lv_obj_get_child(r, 0), C_CYAN, 0);
      plat_phone_status_t ps; plat_phone_status(&ps); bc_profile_t *p = app_profile();
      lv_obj_t *vl = lv_obj_get_child(r, 2); lv_obj_set_width(vl, 84); lv_label_set_text(vl, p->prof_src ? "PHONE" : "DEVICE ONLY");
      lv_obj_set_style_text_color(vl, ps.state == PLAT_PHONE_READY ? C_GREEN : C_MUT, 0); lv_obj_align(vl, LV_ALIGN_RIGHT_MID, -6, 0); }
    table_update();
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 36, back_home, NULL);
    lv_obj_align(bk, LV_ALIGN_TOP_MID, 0, 190);
    ui_screen_show(scr);
}
void ui_sensors_show(void) { ui_connections_show(); }   /* old name, kept for the callers and the test harness */

/* ---- detail pages (no scrolling: status, detail, ONE primary action, Help + hold-to-forget, Back) */
static cat_t d_cat;
static lv_obj_t *d_status, *d_info, *d_primary, *d_list, *d_val;
static int d_primary_kind = -1;
static plat_found_t d_found[12]; static int d_nfound = -1; static uint32_t d_t0;

static plat_sens_kind_t cat_kind(cat_t c) { return c == CAT_POWER ? PLAT_SENS_POWER : c == CAT_HR ? PLAT_SENS_HR : PLAT_SENS_CSC; }
static bc_sensor_pair_t *cat_pair(cat_t c) { bc_profile_t *p = app_profile(); return c == CAT_POWER ? &p->power : c == CAT_HR ? &p->hr : &p->csc; }
static int cat_row(cat_t c) { return c == CAT_POWER ? UI_ROW_POWER : c == CAT_HR ? UI_ROW_HEART : c == CAT_CADENCE ? UI_ROW_CADENCE : UI_ROW_SPEED; }

static void back_menu(lv_event_t *e) { (void)e; plat_scan_end(); ui_connections_show(); }
static void back_detail(lv_event_t *e) { (void)e; ui_conn_detail_show(d_cat); }
static void forget_cb(lv_event_t *e)
{
    (void)e;
    plat_sens_kind_t k = cat_kind(d_cat);
    bc_sensor_pair_t *sp = cat_pair(d_cat);
    memset(sp, 0, sizeof *sp); app_profile_save(); plat_pair(k, NULL);
    ui_conn_detail_show(d_cat);
}
static void retry(plat_sens_kind_t k)
{
    bc_sensor_pair_t *sp = k == PLAT_SENS_POWER ? &app_profile()->power : k == PLAT_SENS_HR ? &app_profile()->hr : &app_profile()->csc;
    if (!sp->paired) return;
    if (plat_bt_unavailable(NULL, 0)) { ui_toast("No Bluetooth this start - restart the board"); return; }   /* 0.7.4 */
    { plat_sensors_t sn; plat_sensors(&sn);
      if (sn.link[k].disabled) { app_diag_retry(k == PLAT_SENS_POWER ? BC_SS_POWER : k == PLAT_SENS_HR ? BC_SS_HR : BC_SS_CSC); ui_toast("starting again"); return; } }
    plat_found_t f; memcpy(f.mac, sp->mac, 6); f.addr_type = sp->addr_type; snprintf(f.name, sizeof f.name, "%s", sp->name); f.rssi = 0; f.svcs = 0;
    plat_pair(k, &f);   /* drops the link (if any) and searches again from the stored address */
    ui_toast("retrying");
}
/* 0 = PAIR, 1 = RETRY, 2 = TEST */
static int primary_kind(void)
{
    bc_sensor_pair_t *sp = cat_pair(d_cat);
    if (!sp->paired) return 0;
    app_live_t lv; app_live(&lv);
    const plat_link_info_t *l = &lv.link[cat_kind(d_cat)];
    if (l->stage == BC_STG_VALID || lv.demo) return 2;
    return 1;
}
static void primary_cb(lv_event_t *e)
{
    (void)e;
    switch (primary_kind()) {
    case 0: ui_pair_show(cat_kind(d_cat), false); break;
    case 1: retry(cat_kind(d_cat)); break;
    default: if (d_cat == CAT_POWER) ui_sensor_test_show(false); else ui_toast("live - nothing to fix"); break;
    }
}
static void help_show(void);
static void help_cb(lv_event_t *e) { (void)e; help_show(); }

static void detail_update(void)
{
    if (d_cat == CAT_OTHER) {
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
        else ui_label(d_list, &lv_font_montserrat_12, C_MUT, "green = pair it under its row");
        return;
    }
    if (d_cat == CAT_SYNC) {
        app_psvc_stats_t st; app_psvc_stats(&st);
        plat_phone_status_t ps; plat_phone_status(&ps);
        bc_profile_t *p = app_profile();
        char t1[24], b[200]; uint32_t now = plat_ms();
        if (st.last_sync_ms) age_text(now - st.last_sync_ms, t1, sizeof t1); else snprintf(t1, sizeof t1, "none this session");
        snprintf(b, sizeof b, "#%06x %s#\n#8494a0 PROFILE# %s v%lu\n#8494a0 SETTINGS# v%lu\n#8494a0 RIDES SENT# %lu\n#8494a0 LAST SYNC# %s",
                 ui_hex(ps.state == PLAT_PHONE_READY ? C_GREEN : C_MUT), ps.state == PLAT_PHONE_READY ? "PHONE CONNECTED" : "PHONE NOT CONNECTED",
                 p->prof_src ? "phone" : "device only", (unsigned long)p->phone_prof_ver, (unsigned long)p->sett_ver, (unsigned long)st.rides_sent, t1);
        lv_label_set_text(d_status, b);
        return;
    }
    ui_row_status_t s; ui_conn_row_status(cat_row(d_cat), &s);
    app_live_t lv; app_live(&lv);
    char b[64];
    snprintf(b, sizeof b, "%s %s", s.icon, s.line);
    lv_label_set_text(d_status, b); lv_obj_set_style_text_color(d_status, s.color, 0);
    /* detail line: the device and the numbers that prove the pipeline (packets / rejected / last valid) */
    bc_sensor_pair_t *sp = cat_pair(d_cat);
    const plat_link_info_t *l = &lv.link[cat_kind(d_cat)];
    if (lv.demo && d_cat == CAT_POWER) snprintf(b, sizeof b, "demo mode - no meter is read");
    else if (sp->paired && l->disabled) snprintf(b, sizeof b, "Retry starts it again");
    else if (d_cat == CAT_HR && !sp->paired) snprintf(b, sizeof b, "watch via phone: %s", lv.phone_hr ? "live" : "no data");
    else if (d_cat == CAT_CADENCE && !sp->paired) snprintf(b, sizeof b, "from the power meter");
    else if (!sp->paired) snprintf(b, sizeof b, "nothing paired");
    else if (l->stage >= BC_STG_SUBSCRIBED && l->stage != BC_STG_ERROR) { char a[16]; age_text(l->valid_age_ms, a, sizeof a); snprintf(b, sizeof b, "%lu pkts  %lu bad  %s", (unsigned long)l->packets, (unsigned long)l->rejected, a); }
    else snprintf(b, sizeof b, "%.19s%s", sp->name, l->rssi && l->stage >= BC_STG_CONNECTED ? "" : "");
    lv_label_set_text(d_info, b);
    int k = primary_kind();
    if (k != d_primary_kind && d_primary) {
        d_primary_kind = k;
        lv_label_set_text(lv_obj_get_child(d_primary, 0), k == 0 ? (d_cat == CAT_HR ? "PAIR STRAP" : d_cat == CAT_POWER ? "PAIR METER" : "PAIR SENSOR") : k == 1 ? "RETRY" : "TEST");
        lv_obj_set_style_bg_color(d_primary, k == 2 ? C_PANEL : C_CYAN, 0);
        lv_obj_set_style_text_color(lv_obj_get_child(d_primary, 0), k == 2 ? C_CYAN : C_INK, 0);
    }
}

void ui_conn_detail_show(int cat)
{
    d_cat = (cat_t)cat;
    if (d_cat == CAT_PHONE) { s_ret_conn = true; ui_phone_show(); return; }
    if (d_cat == CAT_WIFI) { s_ret_conn = true; ui_wifi_show(); return; }
    lv_obj_t *scr = ui_screen_new(UI_SCR_SENSORS, detail_update);
    ui_title(scr, d_cat == CAT_POWER ? "POWER METER" : d_cat == CAT_HR ? "HEART RATE" : d_cat == CAT_CADENCE ? "CADENCE" : d_cat == CAT_SPEED ? "SPEED" : d_cat == CAT_OTHER ? "BLUETOOTH" : "DEVICE SYNC");
    d_status = d_info = d_primary = d_list = d_val = NULL; d_primary_kind = -1;
    if (d_cat == CAT_OTHER) {
        d_list = ui_scroll_area(scr, 50, 180);
        d_nfound = -1; d_t0 = plat_ms(); plat_scan_begin(PLAT_SENS_ANY);
    } else if (d_cat == CAT_SYNC) {
        d_status = ui_label(scr, &lv_font_montserrat_12, C_FG, "");
        lv_label_set_recolor(d_status, true); lv_obj_align(d_status, LV_ALIGN_TOP_MID, 0, 58);
    } else {
        d_status = ui_label(scr, &lv_font_montserrat_14, C_FG, "");
        lv_obj_set_width(d_status, 2 * ui_chord(56) - 16); lv_label_set_long_mode(d_status, LV_LABEL_LONG_MODE_DOTS);
        lv_obj_set_height(d_status, lv_font_get_line_height(&lv_font_montserrat_14) + 1);
        lv_obj_align(d_status, LV_ALIGN_TOP_MID, 0, 56);
        d_info = ui_label(scr, &lv_font_montserrat_12, C_MUT, "");
        lv_obj_set_width(d_info, 2 * ui_chord(80) - 20); lv_label_set_long_mode(d_info, LV_LABEL_LONG_MODE_DOTS);
        lv_obj_set_height(d_info, lv_font_get_line_height(&lv_font_montserrat_12) + 1);
        lv_obj_align(d_info, LV_ALIGN_TOP_MID, 0, 79);
        d_primary = ui_pill(scr, "", C_CYAN, C_INK, 150, 40, primary_cb, NULL);
        lv_obj_align(d_primary, LV_ALIGN_TOP_MID, 0, 100);
        bc_sensor_pair_t *sp = cat_pair(d_cat);
        bool forget = sp->paired && !(d_cat == CAT_CADENCE && !app_profile()->csc.paired);
        lv_obj_t *h = ui_pill(scr, "HELP", C_PANEL, C_CYAN, forget ? 64 : 90, 32, help_cb, NULL);
        lv_obj_set_style_text_font(lv_obj_get_child(h, 0), &lv_font_montserrat_12, 0);
        if (forget) {
            lv_obj_align(h, LV_ALIGN_TOP_MID, -56, 148);
            lv_obj_t *f = ui_hold_btn(scr, "HOLD: FORGET", C_PANEL, C_RED, 104, 32, 1500, forget_cb, NULL);   /* hold 1.5 s: never by accident */
            lv_obj_set_style_text_font(ui_hold_label(f), &lv_font_montserrat_12, 0);
            lv_obj_align(f, LV_ALIGN_TOP_MID, 32, 148);
        } else lv_obj_align(h, LV_ALIGN_TOP_MID, 0, 148);
    }
    detail_update();
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 36, back_menu, NULL);
    lv_obj_align(bk, LV_ALIGN_TOP_MID, 0, 188);
    ui_screen_show(scr);
}

/* ---- Help page per category: the explanations and the rarely used options (scrolls; Back always visible) */
static void pair_cb(lv_event_t *e) { (void)e; ui_pair_show(cat_kind(d_cat), false); }
static void hr_pref_cb(lv_event_t *e) { (void)e; bc_profile_t *p = app_profile(); p->hr_pref = p->hr_pref ? 0 : 1; app_profile_save(); help_show(); }
static void sensor_test_cb(lv_event_t *e) { (void)e; ui_sensor_test_show(false); }
static void wheel_cb(lv_event_t *e)
{
    int d = (int)(intptr_t)lv_event_get_user_data(e);
    bc_profile_t *p = app_profile();
    int v = p->wheel_mm + d; if (v < 1000) v = 1000; if (v > 2600) v = 2600;
    p->wheel_mm = (uint16_t)v; app_profile_save(); plat_csc_wheel_mm(p->wheel_mm);
    char b[20]; snprintf(b, sizeof b, "%u mm", p->wheel_mm); if (d_val) lv_label_set_text(d_val, b);
}
static lv_obj_t *h_diag;
static void help_update(void)
{
    if (!h_diag) return;
    app_live_t lv; app_live(&lv);
    const plat_link_info_t *l = &lv.link[cat_kind(d_cat)];
    char st[48]; stage_line(l, st, sizeof st);
    char b[320];
    snprintf(b, sizeof b, "#8494a0 STAGE# %s\n#8494a0 DATA# %lu pkts, %lu bad\n#8494a0 SOURCE# svc 0x%04X cccd 0x%04X\n#8494a0 AUTO FIXES# %lu resub, %lu reconn%s%s",
             st, (unsigned long)l->packets, (unsigned long)l->rejected, l->svc_uuid, l->cccd, (unsigned long)l->resubscribes, (unsigned long)l->auto_reconnects,
             l->err[0] ? "\n#8494a0 LAST ERROR# " : "", l->err);
    lv_label_set_text(h_diag, b);
}
static void help_show(void)
{
    lv_obj_t *scr = ui_screen_new(UI_SCR_SENSORS, help_update);
    ui_title(scr, "HELP");
    lv_obj_t *l = ui_scroll_area(scr, 50, 182);
    h_diag = NULL; d_val = NULL;
    bc_profile_t *p = app_profile();
    const char *txt = "";
    switch (d_cat) {
    case CAT_POWER: txt = "Pedal to wake the meter. The board subscribes to its data (never writes settings) and repairs itself: no data for 8 s = subscribe again, 15 s = reconnect. Watts are the meter's own reading; accuracy is not verified."; break;
    case CAT_HR: txt = "A strap paired here is read directly. Apple Watch heart rate comes through the phone app (fresh up to 6 s). The other source is the automatic backup."; break;
    case CAT_CADENCE: txt = "Cadence comes from the power meter. A speed/cadence sensor is only needed without the meter."; break;
    case CAT_SPEED: txt = "Speed comes from a wheel sensor (set the wheel size) or the phone's GPS."; break;
    default: break;
    }
    ui_note(l, txt, 0);
    if (d_cat == CAT_POWER || d_cat == CAT_HR || d_cat == CAT_CADENCE || d_cat == CAT_SPEED) {
        h_diag = ui_label(l, &lv_font_montserrat_12, C_FG, "");
        lv_obj_set_width(h_diag, lv_pct(100)); lv_label_set_long_mode(h_diag, LV_LABEL_LONG_MODE_WRAP); lv_label_set_recolor(h_diag, true);
    }
    if (d_cat == CAT_POWER) ui_pill(l, "SENSOR TEST", C_PANEL, C_CYAN, 150, 34, sensor_test_cb, NULL);
    if (d_cat == CAT_HR) { lv_obj_t *b = ui_pill(l, p->hr_pref ? "WATCH FIRST" : "STRAP FIRST", C_PANEL, C_CYAN, 150, 34, hr_pref_cb, NULL); (void)b; }
    if (cat_pair(d_cat)->paired) ui_pill(l, "PAIR ANOTHER", C_PANEL, C_CYAN, 150, 34, pair_cb, NULL);
    if (d_cat == CAT_SPEED) {
        lv_obj_t *row = lv_obj_create(l); lv_obj_remove_style_all(row); lv_obj_set_size(row, lv_pct(100), 40); lv_obj_remove_flag(row, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_t *m = ui_pill(row, "-10", C_PANEL, C_CYAN, 48, 34, wheel_cb, (void *)(intptr_t)-10); lv_obj_align(m, LV_ALIGN_LEFT_MID, 0, 0);
        char v[20]; snprintf(v, sizeof v, "%u mm", p->wheel_mm);
        d_val = ui_label(row, &lv_font_montserrat_14, C_FG, v); lv_obj_align(d_val, LV_ALIGN_CENTER, 0, 0);
        lv_obj_t *pl = ui_pill(row, "+10", C_PANEL, C_CYAN, 48, 34, wheel_cb, (void *)(intptr_t)10); lv_obj_align(pl, LV_ALIGN_RIGHT_MID, 0, 0);
    }
    help_update();
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 36, back_detail, NULL);
    lv_obj_align(bk, LV_ALIGN_TOP_MID, 0, 188);
    ui_screen_show(scr);
}

/* ---- Device Health: one line per sensor ("POWER  live 142 W", "POWER  connected - no data", ...) */
void ui_conn_health_lines(char *b, size_t cap, bool markup)
{
    static const struct { int row; const char *name; } R[] = { { UI_ROW_PHONE, "PHONE" }, { UI_ROW_POWER, "POWER" }, { UI_ROW_HEART, "HEART" }, { UI_ROW_CADENCE, "CADENCE" }, { UI_ROW_SPEED, "SPEED" } };
    size_t n = 0; if (cap) b[0] = 0;
    for (size_t i = 0; i < sizeof R / sizeof *R && n + 1 < cap; i++) {
        if (R[i].row == UI_ROW_SPEED && !app_profile()->csc.paired) continue;
        ui_row_status_t s; ui_conn_row_status(R[i].row, &s);
        int k = markup ? snprintf(b + n, cap - n, "#%06x %s#  %s\n", ui_hex(s.color), R[i].name, s.line) : snprintf(b + n, cap - n, "%-8s %s\n", R[i].name, s.line);
        if (k < 0) break;
        n += (size_t)k; if (n >= cap) { n = cap - 1; break; }
    }
}
