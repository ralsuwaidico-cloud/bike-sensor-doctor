/* Home, Sensors (status + pairing) and the recovered-ride notice. */
#include "ui.h"
#include <stdio.h>
#include <string.h>

void ui_onboard_after_pair(plat_sens_kind_t k, bool forward);

/* ---------------- Home */
static lv_obj_t *h_status, *h_sub, *h_ftp;

static void home_update(void)
{
    app_live_t lv; app_live(&lv);
    char bat[24]; ui_battery_text(bat, sizeof bat);
    const plat_link_info_t *pw = &lv.link[PLAT_SENS_POWER], *hr = &lv.link[PLAT_SENS_HR];
    char b[96];
    snprintf(b, sizeof b, "#%06x " LV_SYMBOL_BLUETOOTH " PWR#  #%06x HR#  %s",
             ui_hex(ui_link_color(pw->link)), ui_hex(ui_link_color(hr->link)), bat);
    lv_label_set_text(h_status, b);
    if (lv.power_ok) snprintf(b, sizeof b, "%d W  %d rpm%s", lv.watts, lv.cad_ok ? lv.rpm : 0, lv.demo ? "  (sim)" : "");
    else if (pw->link == PLAT_LINK_NOT_PAIRED) snprintf(b, sizeof b, "power meter not paired");
    else if (pw->link == PLAT_LINK_CONNECTED) snprintf(b, sizeof b, "meter connected, NO DATA");
    else snprintf(b, sizeof b, "meter %s", ui_link_text(pw->link));
    lv_label_set_text(h_sub, b);
}

static void go_ride(lv_event_t *e) { (void)e; app_ride_start(); ui_ride_show(); }
static void go_sensors(lv_event_t *e) { (void)e; ui_sensors_show(); }
static void go_history(lv_event_t *e) { (void)e; ui_history_show(app_demo()); }
static void go_settings(lv_event_t *e) { (void)e; ui_settings_show(); }

static lv_obj_t *icon_btn(lv_obj_t *scr, const char *sym, const char *cap, int cx, int cy, lv_event_cb_t cb)
{
    lv_obj_t *b = lv_button_create(scr);
    lv_obj_remove_style_all(b);
    lv_obj_remove_flag(b, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_size(b, 54, 50);
    lv_obj_set_style_radius(b, 18, 0);
    lv_obj_set_style_bg_color(b, C_PANEL, 0);
    lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(b, C_FAINT, LV_STATE_PRESSED);
    lv_obj_set_pos(b, cx - 27, cy - 25);
    lv_obj_t *i = ui_label(b, &lv_font_montserrat_20, C_FG, sym); lv_obj_align(i, LV_ALIGN_TOP_MID, 0, 5);
    lv_obj_t *c = ui_label(b, &lv_font_montserrat_12, C_MUT, cap); lv_obj_align(c, LV_ALIGN_BOTTOM_MID, 0, -4);
    lv_obj_add_event_cb(b, cb, LV_EVENT_CLICKED, NULL);
    return b;
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

    lv_obj_t *start = lv_button_create(scr);
    lv_obj_remove_style_all(start);
    lv_obj_remove_flag(start, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_size(start, 180, 50);
    lv_obj_set_style_radius(start, LV_RADIUS_CIRCLE, 0);
    lv_obj_set_style_bg_color(start, C_GREEN, 0);
    lv_obj_set_style_bg_opa(start, LV_OPA_COVER, 0);
    lv_obj_set_style_bg_color(start, lv_color_hex(0x8FF0B4), LV_STATE_PRESSED);
    lv_obj_align(start, LV_ALIGN_TOP_MID, 0, 84);
    lv_obj_t *sl = ui_label(start, &lv_font_montserrat_20, C_INK, LV_SYMBOL_PLAY "  START RIDE");
    lv_obj_center(sl);
    lv_obj_add_event_cb(start, go_ride, LV_EVENT_CLICKED, NULL);

    h_sub = ui_label(scr, &lv_font_montserrat_12, C_MUT, "");
    lv_obj_align(h_sub, LV_ALIGN_TOP_MID, 0, 138);

    icon_btn(scr, LV_SYMBOL_BLUETOOTH, "Sensors", 62, 180, go_sensors);
    icon_btn(scr, LV_SYMBOL_LIST, "History", 120, 188, go_history);
    icon_btn(scr, LV_SYMBOL_SETTINGS, "Settings", 178, 180, go_settings);
    ui_screen_show(scr);
}

/* ---------------- Sensors: status of each link + pair buttons */
static lv_obj_t *s_rows[3];

static void sensors_update(void)
{
    app_live_t lv; app_live(&lv);
    char b[128];
    for (int k = 0; k < 3; k++) {
        const plat_link_info_t *l = &lv.link[k];
        const char *nm = k == PLAT_SENS_POWER ? "POWER" : k == PLAT_SENS_HR ? "HEART RATE" : "SPEED / GPS";
        char val[40] = "";
        if (k == PLAT_SENS_POWER) {
            if (lv.power_ok) snprintf(val, sizeof val, "%d W  %d rpm", lv.watts, lv.cad_ok ? lv.rpm : 0); else snprintf(val, sizeof val, "NO DATA");
        } else if (k == PLAT_SENS_HR) {
            if (lv.hr_ok) snprintf(val, sizeof val, "%d bpm", lv.bpm); else snprintf(val, sizeof val, l->link == PLAT_LINK_NOT_PAIRED ? "optional" : "NO DATA");
        } else snprintf(val, sizeof val, "not on this board");
        char sig[24] = "";
        if (l->link == PLAT_LINK_CONNECTED && l->rssi) snprintf(sig, sizeof sig, "  %d dBm", l->rssi);
        snprintf(b, sizeof b, "#8494a0 %s#\n#%06x %s#%s\n%s", nm, ui_hex(ui_link_color(l->link)), ui_link_text(l->link), sig, val);
        lv_label_set_text(s_rows[k], b);
    }
}

static void pair_power(lv_event_t *e) { (void)e; ui_pair_show(PLAT_SENS_POWER, false); }
static void pair_hr(lv_event_t *e) { (void)e; ui_pair_show(PLAT_SENS_HR, false); }
static void sensor_test(lv_event_t *e) { (void)e; ui_sensor_test_show(false); }
static void back_home(lv_event_t *e) { (void)e; ui_home_show(); }

void ui_sensors_show(void)
{
    lv_obj_t *scr = ui_screen_new(UI_SCR_SENSORS, sensors_update);
    ui_title(scr, "SENSORS");
    lv_obj_t *list = ui_scroll_area(scr, 52, 180);
    ui_pill(list, "SENSOR TEST", C_CYAN, C_INK, 150, 34, sensor_test, NULL);
    for (int k = 0; k < 3; k++) {
        s_rows[k] = ui_label(list, &lv_font_montserrat_14, C_FG, "");
        lv_label_set_recolor(s_rows[k], true);
        if (k == 0) ui_pill(list, "PAIR POWER", C_PANEL, C_CYAN, 140, 34, pair_power, NULL);
        if (k == 1) ui_pill(list, "PAIR HR", C_PANEL, C_CYAN, 140, 34, pair_hr, NULL);
    }
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 40, back_home, NULL);
    lv_obj_align(bk, LV_ALIGN_TOP_MID, 0, 184);
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
    bc_sensor_pair_t *sp = p_kind == PLAT_SENS_POWER ? &pr->power : &pr->hr;
    memcpy(sp->mac, p_found[i].mac, 6); sp->addr_type = p_found[i].addr_type; sp->paired = true;
    snprintf(sp->name, sizeof sp->name, "%s", p_found[i].name);
    app_profile_save();
    plat_pair(p_kind, &p_found[i]);
}

static void pair_forget(lv_event_t *e)
{
    (void)e;
    bc_profile_t *pr = app_profile();
    bc_sensor_pair_t *sp = p_kind == PLAT_SENS_POWER ? &pr->power : &pr->hr;
    memset(sp, 0, sizeof *sp); app_profile_save();
    plat_pair(p_kind, NULL);
}

static void pair_update(void)
{
    bc_profile_t *pr = app_profile();
    const bc_sensor_pair_t *sp = p_kind == PLAT_SENS_POWER ? &pr->power : &pr->hr;
    app_live_t lv; app_live(&lv);
    char b[96];
    if (sp->paired) {
        const plat_link_info_t *l = &lv.link[p_kind];
        if (p_kind == PLAT_SENS_POWER && lv.power_ok) snprintf(b, sizeof b, "#56e08c %s#\n%d W  %d rpm", sp->name, lv.watts, lv.cad_ok ? lv.rpm : 0);
        else if (p_kind == PLAT_SENS_HR && lv.hr_ok) snprintf(b, sizeof b, "#56e08c %s#\n%d bpm", sp->name, lv.bpm);
        else snprintf(b, sizeof b, "#56e08c %s#\n%s%s", sp->name, ui_link_text(l->link), p_kind == PLAT_SENS_POWER ? " - pedal to wake" : "");
    } else snprintf(b, sizeof b, "%s", p_kind == PLAT_SENS_POWER ? "Pedal so the meter wakes up,\nthen tap it below." : "Wear the strap (wet the pads),\nthen tap it below.");
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
    if (p_onb) ui_onboard_after_pair(p_kind, true); else ui_sensors_show();
}
static void pair_back(lv_event_t *e) { (void)e; plat_scan_end(); if (p_onb) ui_onboard_after_pair(p_kind, false); else ui_sensors_show(); }

void ui_pair_show(plat_sens_kind_t kind, bool onboarding)
{
    p_kind = kind; p_onb = onboarding; p_nfound = -1; p_t0 = plat_ms();
    lv_obj_t *scr = ui_screen_new(UI_SCR_SENSORS, pair_update);
    ui_title(scr, kind == PLAT_SENS_POWER ? "POWER METER" : "HR STRAP");
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
    if (!app_profile()->onboarded) ui_onboard_start();
    else if (app_take_recovered(&s)) ui_recovered_show(&s);
    else ui_home_show();
}
