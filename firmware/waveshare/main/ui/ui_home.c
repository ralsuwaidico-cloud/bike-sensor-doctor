/* Home, sensor pairing (power meter / HR strap / speed-cadence sensor) and the recovered-ride notice. Connections: ui_conn.c */
#include "ui.h"
#include "app_power.h"
#include <stdio.h>
#include <string.h>

void ui_onboard_after_pair(plat_sens_kind_t k, bool forward);

/* ---------------- Home */
static lv_obj_t *h_status, *h_sub, *h_ftp;
static void home_conn_refresh(void);

static void home_update(void)
{
    if (app_ride_state() == BC_RIDE_RUNNING || app_ride_state() == BC_RIDE_PAUSED) { ui_ride_show(); return; }   /* started from the phone */
    app_live_t lv; app_live(&lv);
    char bat[24]; ui_battery_text(bat, sizeof bat);
    const plat_link_info_t *pw = &lv.link[PLAT_SENS_POWER], *hr = &lv.link[PLAT_SENS_HR];
    char b[96];
    plat_wifi_status_t ws; plat_wifi_status(&ws);
    char wf[32] = "";
    if (ws.state != PLAT_WIFI_OFF) snprintf(wf, sizeof wf, " #%06x " LV_SYMBOL_WIFI "#", ui_hex(ws.state == PLAT_WIFI_CONNECTED ? C_GREEN : C_MUT));
    if (app_power_safe_mode()) snprintf(b, sizeof b, "#%06x SAFE MODE (touch gate off)#", ui_hex(C_RED));   /* 0.6.1: BOOT held at reset */
    else snprintf(b, sizeof b, "#%06x " LV_SYMBOL_BLUETOOTH " PWR#  #%06x HR#  %s%s",
             ui_hex(ui_link_color(pw->link)), ui_hex(ui_link_color(hr->link)), bat, wf);
    lv_label_set_text(h_status, b);
    if (lv.power_ok) snprintf(b, sizeof b, "%d W  %d rpm%s", lv.watts, lv.cad_ok ? lv.rpm : 0, lv.demo ? "  (sim)" : "");
    else if (pw->link == PLAT_LINK_NOT_PAIRED) snprintf(b, sizeof b, "power meter not paired");
    else if (pw->link == PLAT_LINK_CONNECTED) snprintf(b, sizeof b, "meter connected, NO DATA");
    else snprintf(b, sizeof b, "meter %s", ui_link_text(pw->link));
    lv_label_set_text(h_sub, b);
    home_conn_refresh();
}

/* START RIDE = hold 1 s (rev 3): a plain tap only shows the hint; the wake gesture and its guard never reach this button */
static void go_ride(lv_event_t *e)
{
    (void)e;
    if (app_ride_state() == BC_RIDE_RUNNING || app_ride_state() == BC_RIDE_PAUSED) { ui_ride_show(); return; }   /* never a second ride */
    app_ride_start();
    ui_toast("RECORDING STARTED");
    ui_ride_show();
}
static void start_hint(lv_event_t *e) { (void)e; ui_toast("hold 1 s to start"); }
static void go_sensors(lv_event_t *e) { (void)e; ui_connections_show(); }
static void go_history(lv_event_t *e) { (void)e; ui_history_show(app_demo()); }
static void go_settings(lv_event_t *e) { (void)e; ui_settings_show(); }

static lv_obj_t *text_btn(lv_obj_t *scr, const char *cap, int cx, int cy, int w, int h, lv_event_cb_t cb)
{
    lv_obj_t *b = lv_button_create(scr);
    lv_obj_remove_style_all(b);
    lv_obj_remove_flag(b, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_size(b, w, h);
    lv_obj_set_style_radius(b, 14, 0);
    lv_obj_set_style_bg_color(b, C_PANEL, 0);
    lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(b, C_FAINT, LV_STATE_PRESSED);
    lv_obj_set_pos(b, cx - w / 2, cy - h / 2);
    lv_obj_t *c = ui_label(b, &lv_font_montserrat_14, C_FG, cap); lv_obj_center(c);
    lv_obj_add_event_cb(b, cb, LV_EVENT_CLICKED, NULL);
    return b;
}

static lv_obj_t *h_conn_right;
static void home_conn_refresh(void)
{
    int c, a; ui_conn_summary(&c, &a);
    char b[32];
    if (a) snprintf(b, sizeof b, "%d on  #ff5a5a ! %d#", c, a); else snprintf(b, sizeof b, "#56e08c %d on#", c);
    if (h_conn_right) lv_label_set_text(h_conn_right, b);
}

void ui_home_show(void)
{
    if (app_ride_state() == BC_RIDE_RUNNING || app_ride_state() == BC_RIDE_PAUSED) { ui_ride_show(); return; }
    bc_profile_t *p = app_profile();
    lv_obj_t *scr = ui_screen_new(UI_SCR_HOME, home_update);
    h_status = ui_label(scr, &lv_font_montserrat_12, C_MUT, "");
    lv_label_set_recolor(h_status, true);
    lv_obj_align(h_status, LV_ALIGN_TOP_MID, 0, 30);
    char b[48]; snprintf(b, sizeof b, "Hi %s", bc_profile_display_name(p));
    lv_obj_t *hi = ui_label(scr, &bc_bold16, C_FG, b);
    lv_label_set_long_mode(hi, LV_LABEL_LONG_DOT); lv_obj_set_size(hi, 168, 20);
    lv_obj_align(hi, LV_ALIGN_TOP_MID, 0, 46);
    snprintf(b, sizeof b, "FTP %u W%s", p->ftp_w, bc_ftp_established(p) ? "" : " provisional");
    h_ftp = ui_label(scr, &lv_font_montserrat_12, bc_ftp_established(p) ? C_MUT : C_AMBER, b);
    lv_obj_align(h_ftp, LV_ALIGN_TOP_MID, 0, 66);

    lv_obj_t *start = ui_hold_btn(scr, LV_SYMBOL_PLAY "  START RIDE", C_GREEN, C_INK, 180, 48, 1000, go_ride, NULL);
    lv_obj_set_style_text_font(ui_hold_label(start), &lv_font_montserrat_20, 0);
    lv_obj_set_style_bg_color(start, lv_color_hex(0x8FF0B4), LV_STATE_PRESSED);
    lv_obj_align(start, LV_ALIGN_TOP_MID, 0, 84);
    lv_obj_add_event_cb(start, start_hint, LV_EVENT_CANCEL, NULL);

    h_sub = ui_label(scr, &lv_font_montserrat_12, C_MUT, "");
    lv_obj_align(h_sub, LV_ALIGN_TOP_MID, 0, 135);

    /* 0.6.0: Connections replaces the old Sensors button — one wide row with the live summary (n connected, ! missing) */
    lv_obj_t *cn = lv_button_create(scr);
    lv_obj_remove_style_all(cn);
    lv_obj_remove_flag(cn, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_size(cn, 184, 30);
    lv_obj_set_style_radius(cn, 15, 0);
    lv_obj_set_style_bg_color(cn, C_PANEL, 0); lv_obj_set_style_bg_opa(cn, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(cn, C_FAINT, LV_STATE_PRESSED);
    lv_obj_align(cn, LV_ALIGN_TOP_MID, 0, 152);
    lv_obj_t *cl = ui_label(cn, &lv_font_montserrat_14, C_FG, "Connections"); lv_obj_align(cl, LV_ALIGN_LEFT_MID, 12, 0);
    h_conn_right = ui_label(cn, &lv_font_montserrat_12, C_MUT, ""); lv_label_set_recolor(h_conn_right, true); lv_obj_align(h_conn_right, LV_ALIGN_RIGHT_MID, -12, 0);
    lv_obj_add_event_cb(cn, go_sensors, LV_EVENT_CLICKED, NULL);
    home_conn_refresh();

    text_btn(scr, "History", 86, 199, 64, 30, go_history);
    text_btn(scr, "Settings", 154, 199, 64, 30, go_settings);
    ui_screen_show(scr);
}

/* ---------------- Pairing (onboarding step or from Sensors) */
static plat_sens_kind_t p_kind; static bool p_onb;
static lv_obj_t *p_list, *p_status, *p_next;
static plat_found_t p_found[6]; static int p_nfound = -1;
static uint32_t p_t0;

static void pair_pick(lv_event_t *e)
{
    int i = (int)(intptr_t)lv_event_get_user_data(e);
    bc_profile_t *pr = app_profile();
    bc_sensor_pair_t *sp = p_kind == PLAT_SENS_POWER ? &pr->power : p_kind == PLAT_SENS_HR ? &pr->hr : &pr->csc;
    memcpy(sp->mac, p_found[i].mac, 6); sp->addr_type = p_found[i].addr_type; sp->paired = true;
    snprintf(sp->name, sizeof sp->name, "%s", p_found[i].name);
    app_profile_save();
    plat_pair(p_kind, &p_found[i]);
}

static void pair_forget(lv_event_t *e)
{
    (void)e;
    bc_profile_t *pr = app_profile();
    bc_sensor_pair_t *sp = p_kind == PLAT_SENS_POWER ? &pr->power : p_kind == PLAT_SENS_HR ? &pr->hr : &pr->csc;
    memset(sp, 0, sizeof *sp); app_profile_save();
    plat_pair(p_kind, NULL);
}

static void pair_update(void)
{
    bc_profile_t *pr = app_profile();
    const bc_sensor_pair_t *sp = p_kind == PLAT_SENS_POWER ? &pr->power : p_kind == PLAT_SENS_HR ? &pr->hr : &pr->csc;
    app_live_t lv; app_live(&lv);
    plat_sensors_t sn; plat_sensors(&sn);
    char b[96];
    if (sp->paired) {
        const plat_link_info_t *l = &lv.link[p_kind];
        if (p_kind == PLAT_SENS_POWER && lv.power_ok) snprintf(b, sizeof b, "#56e08c %s#\n%d W  %d rpm", sp->name, lv.watts, lv.cad_ok ? lv.rpm : 0);
        else if (p_kind == PLAT_SENS_HR && lv.hr_ok) snprintf(b, sizeof b, "#56e08c %s#\n%d bpm", sp->name, lv.bpm);
        else if (p_kind == PLAT_SENS_CSC && (sn.csc_cad_ok || sn.csc_speed_ok)) snprintf(b, sizeof b, "#56e08c %s#\n%d rpm  %d.%d km/h", sp->name, sn.csc_cad_ok ? sn.csc_rpm : 0, sn.csc_speed_dmh / 10, sn.csc_speed_dmh % 10);
        else snprintf(b, sizeof b, "#56e08c %s#\n%s%s", sp->name, ui_stage_word(l), l->stage <= 2 && p_kind != PLAT_SENS_HR ? " - move it to wake" : "");
    } else snprintf(b, sizeof b, "%s", p_kind == PLAT_SENS_POWER ? "Pedal so the meter wakes up,\nthen tap it below." : p_kind == PLAT_SENS_HR ? "Wear the strap (wet the pads),\nthen tap it below." : "Spin the wheel or crank so the\nsensor wakes, then tap it below.");
    lv_label_set_text(p_status, b);
    if (p_next) lv_label_set_text(lv_obj_get_child(p_next, 0), p_onb ? (sp->paired ? "NEXT" : "SKIP") : "DONE");

    plat_found_t f[6]; int n = plat_scan_results(f, 6);
    if (n == p_nfound && n >= 0 && !memcmp(f, p_found, sizeof(plat_found_t) * (size_t)n)) return;
    p_nfound = n; memcpy(p_found, f, sizeof(plat_found_t) * (size_t)n);
    lv_obj_clean(p_list);
    for (int i = 0; i < n; i++) {
        char r[12]; snprintf(r, sizeof r, "%d", f[i].rssi);
        bool mine = sp->paired && !memcmp(sp->mac, f[i].mac, 6);
        ui_row_btn(p_list, f[i].name[0] ? f[i].name : "(no name)", mine ? LV_SYMBOL_OK : r, mine ? C_GREEN : C_MUT, pair_pick, (void *)(intptr_t)i);
    }
    if (n == 0) { lv_obj_t *l = ui_label(p_list, &lv_font_montserrat_12, C_MUT, plat_ms() - p_t0 > 15000 ? "nothing found yet" : "searching..."); (void)l; }
    if (sp->paired && !p_onb) ui_pill(p_list, "FORGET", C_PANEL, C_RED, 110, 32, pair_forget, NULL);
}

static void pair_done(lv_event_t *e)
{
    (void)e; plat_scan_end();
    if (p_onb) ui_onboard_after_pair(p_kind, true); else ui_conn_detail_show(p_kind == PLAT_SENS_POWER ? 2 : p_kind == PLAT_SENS_HR ? 3 : 4);
}
static void pair_back(lv_event_t *e) { (void)e; plat_scan_end(); if (p_onb) ui_onboard_after_pair(p_kind, false); else ui_conn_detail_show(p_kind == PLAT_SENS_POWER ? 2 : p_kind == PLAT_SENS_HR ? 3 : 4); }

void ui_pair_show(plat_sens_kind_t kind, bool onboarding)
{
    p_kind = kind; p_onb = onboarding; p_nfound = -1; p_t0 = plat_ms();
    lv_obj_t *scr = ui_screen_new(UI_SCR_SENSORS, pair_update);
    ui_title(scr, kind == PLAT_SENS_POWER ? "POWER METER" : kind == PLAT_SENS_HR ? "HR STRAP" : "CSC SENSOR");
    if (onboarding) { lv_obj_t *o = ui_label(scr, &lv_font_montserrat_12, C_MUT, kind == PLAT_SENS_POWER ? "you can skip and pair later" : "optional"); lv_obj_align(o, LV_ALIGN_TOP_MID, 0, 48); }
    p_status = ui_label(scr, &lv_font_montserrat_12, C_FG, "");
    lv_label_set_recolor(p_status, true);
    lv_obj_align(p_status, LV_ALIGN_TOP_MID, 0, onboarding ? 64 : 54);
    p_list = ui_scroll_area(scr, 96, 160);
    plat_scan_begin(kind);
    p_next = NULL;
    ui_nav(scr, pair_back, "SKIP", pair_done, NULL);
    /* the nav pill is the last child: keep a handle to relabel it NEXT / SKIP / DONE */
    p_next = lv_obj_get_child(scr, (int32_t)lv_obj_get_child_count(scr) - 1);
    ui_screen_show(scr);
}

/* ---------------- recovered ride notice */
static bc_ride_summary_t r_sum;
static void rec_view(lv_event_t *e) { (void)e; ui_results_show(&r_sum, false); }
static void rec_home(lv_event_t *e) { (void)e; ui_home_show(); }

void ui_recovered_show(const bc_ride_summary_t *s)
{
    r_sum = *s;
    lv_obj_t *scr = ui_screen_new(UI_SCR_OTHER, NULL);
    ui_title(scr, "RECOVERED");
    char d[16]; bc_fmt_duration(s->duration_s, d, sizeof d);
    char b[160]; snprintf(b, sizeof b, "Ride #%u was interrupted\n(restart or power loss).\n%s recorded is saved\nin History.", s->id, d);
    lv_obj_t *t = ui_label(scr, &lv_font_montserrat_14, C_FG, b);
    lv_obj_align(t, LV_ALIGN_TOP_MID, 0, 58);
    ui_nav(scr, rec_home, "VIEW", rec_view, NULL);
    ui_screen_show(scr);
}

void ui_start(void)
{
    bc_ride_summary_t s;
    ui_power_init();
    if (!app_profile()->onboarded) ui_onboard_start();
    else if (app_take_recovered(&s)) ui_recovered_show(&s);
    else ui_home_show();
}
