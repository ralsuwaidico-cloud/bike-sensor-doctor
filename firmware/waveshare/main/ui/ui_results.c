/* Ride results (save / discard after a ride, or read-only from History) and the History list. */
#include "ui.h"
#include <stdio.h>
#include <string.h>

static bc_ride_summary_t s_sum;
static bool s_fresh, s_from_hist_demo;

static lv_obj_t *line(lv_obj_t *list, const lv_font_t *f, lv_color_t c, const char *txt)
{
    lv_obj_t *l = ui_label(list, f, c, txt);
    lv_obj_set_width(l, lv_pct(100));
    lv_label_set_long_mode(l, LV_LABEL_LONG_WRAP);
    return l;
}

static void notice_ok(lv_event_t *e) { (void)e; ui_history_show(s_sum.demo); }
/* 0.7.4 (QA QF-01): the outcome of SAVE is always on screen - never a silent loss */
static void save_notice(app_save_result_t r)
{
    lv_obj_t *scr = ui_screen_new(UI_SCR_RESULTS, NULL);
    lv_obj_t *t = ui_title(scr, r == APP_SAVE_RAM_ONLY ? "NOT SAVED ON BOARD" : "RIDE NOT SAVED");
    lv_obj_set_style_text_color(t, C_RED, 0);
    lv_obj_t *list = ui_scroll_area(scr, 66, 164);     /* the title takes two lines on the round screen */
    char b[180];
    bool no_bt = plat_bt_unavailable(NULL, 0);    /* rc3 (QA QF-21): without Bluetooth the phone cannot copy it - never say so */
    if (r == APP_SAVE_RAM_ONLY && no_bt)
        snprintf(b, sizeof b, "Storage: %s.\nRide #%u stays in memory\nonly until power-off or\nsleep. Bluetooth is off:\nnote what you need now.", bc_stor_short(plat_storage_state()), s_sum.id);
    else if (r == APP_SAVE_RAM_ONLY)
        snprintf(b, sizeof b, "Storage: %s.\nRide #%u is kept until\npower-off. Open Cyclift\nnow to copy it.", bc_stor_short(plat_storage_state()), s_sum.id);
    else if (no_bt)
        snprintf(b, sizeof b, "Storage: %s and\n%d rides already wait\nin memory. Bluetooth is\noff: this one is lost.", bc_stor_short(plat_storage_state()), APP_UNSAVED_MAX);
    else
        snprintf(b, sizeof b, "Storage: %s and\n%d unsynced rides already\nwait in memory. Open\nCyclift to copy them.", bc_stor_short(plat_storage_state()), APP_UNSAVED_MAX);
    lv_obj_t *l = ui_label(list, &lv_font_montserrat_14, C_FG, b);
    lv_obj_set_width(l, lv_pct(100)); lv_label_set_long_mode(l, LV_LABEL_LONG_WRAP); lv_obj_set_style_text_align(l, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_t *ok = ui_pill(scr, "OK", C_PANEL, C_FG, 96, 44, notice_ok, NULL);
    lv_obj_align(ok, LV_ALIGN_TOP_MID, 0, 170);
    ui_screen_show(scr);
}
static void save_cb(lv_event_t *e)
{
    (void)e;
    app_save_result_t r = app_ride_save_ex();
    if (r == APP_SAVE_OK || r == APP_SAVE_NOTHING || s_sum.demo) ui_history_show(s_sum.demo);
    else save_notice(r);
}
static void discard_cb(lv_event_t *e) { (void)e; app_ride_discard(); ui_home_show(); }
static void back_hist(lv_event_t *e) { (void)e; ui_history_show(s_from_hist_demo); }

void ui_results_show(const bc_ride_summary_t *s, bool fresh)
{
    s_sum = *s; s_fresh = fresh; s_from_hist_demo = s->demo;
    lv_obj_t *scr = ui_screen_new(UI_SCR_RESULTS, NULL);
    char b[200], d[16];
    snprintf(b, sizeof b, "RIDE #%u%s", s->id, s->demo ? " DEMO" : "");
    lv_obj_t *t = ui_title(scr, b);
    if (s->demo) lv_obj_set_style_text_color(t, C_DEMO, 0);
    lv_obj_t *list = ui_scroll_area(scr, 50, 160);
    bc_fmt_duration(s->duration_s, d, sizeof d);
    line(list, &bc_num44, C_FG, d);
    if (s->paused_s) { char p[16]; bc_fmt_duration(s->paused_s, p, sizeof p); snprintf(b, sizeof b, "paused %s", p); line(list, &lv_font_montserrat_12, C_MUT, b); }
    if (s->demo) line(list, &lv_font_montserrat_12, C_DEMO, "SIMULATED DATA\nnot in your real history");
    if (s->recovered) line(list, &lv_font_montserrat_12, C_AMBER, "recovered after a restart\nor power loss");
    if (s->avg_power >= 0) snprintf(b, sizeof b, "AVG %d W\nMAX %d W", s->avg_power, s->max_power);
    else snprintf(b, sizeof b, "POWER: NO DATA");
    line(list, &bc_bold16, C_FG, b);
    if (s->avg_cad >= 0) snprintf(b, sizeof b, "CADENCE %d rpm", s->avg_cad); else snprintf(b, sizeof b, "CADENCE: NO DATA");
    line(list, &lv_font_montserrat_14, C_VIOLET, b);
    if (s->avg_hr >= 0) snprintf(b, sizeof b, "HR avg %d  max %d", s->avg_hr, s->max_hr); else snprintf(b, sizeof b, "HR: no strap data");
    line(list, &lv_font_montserrat_14, s->avg_hr >= 0 ? C_RED : C_MUT, b);
    if (s->kj > 0) { snprintf(b, sizeof b, "ENERGY %d kJ", s->kj); line(list, &lv_font_montserrat_14, C_FG, b); }
    if (s->power_s && s->duration_s) {
        snprintf(b, sizeof b, "power data %lu%% of ride", (unsigned long)(s->power_s * 100 / s->duration_s));
        line(list, &lv_font_montserrat_12, C_MUT, b);
    }
    /* time in zones: only with an established FTP */
    if (s->zones_valid) {
        snprintf(b, sizeof b, "ZONES (FTP %d W)", s->ftp_w); line(list, &lv_font_montserrat_12, C_CYAN, b);
        for (int z = 0; z < BC_ZONES; z++) {
            if (!s->zone_s[z]) continue;
            char zt[16]; bc_fmt_duration(s->zone_s[z], zt, sizeof zt);
            snprintf(b, sizeof b, "Z%d  %s  %lu%%", z + 1, zt, (unsigned long)(s->power_s ? s->zone_s[z] * 100 / s->power_s : 0));
            line(list, &lv_font_montserrat_14, C_FG, b);
        }
    } else line(list, &lv_font_montserrat_12, C_MUT, "Zones appear once your FTP\nis established by real rides.");
    line(list, &lv_font_montserrat_12, C_CYAN, "COACH");
    line(list, &lv_font_montserrat_14, C_FG, s->coach[0] ? s->coach : "-");
    int ev = fresh ? app_ride_ftp_evidence() : s->ftp_new;
    if (ev > 0) {
        bool entered = app_profile()->ftp_how == BC_FTP_ENTERED || s->ftp_suggested_only;
        if (fresh) snprintf(b, sizeof b, entered ? "FTP evidence %d W\n(your entered FTP is kept)" : "FTP evidence %d W\n(applied when you save)", ev);
        else snprintf(b, sizeof b, s->ftp_suggested_only ? "suggested FTP %d W" : "FTP set to %d W\nfrom this ride", ev);
        line(list, &bc_bold16, C_GREEN, b);
    }
    if (fresh) {
        if (!plat_storage_ok() && !s->demo)          /* 0.7.4: say it BEFORE the rider taps SAVE */
            line(list, &lv_font_montserrat_12, C_RED, plat_bt_unavailable(NULL, 0)
                 ? "Board storage damaged:\nthis ride is kept in memory\nuntil power-off only.\nBluetooth is off: it cannot\nreach Cyclift this start."
                 : "Board storage damaged:\nthis ride is kept in memory\nuntil power-off only.\nOpen Cyclift to copy it.");
        line(list, &lv_font_montserrat_12, C_MUT, "SAVE keeps this ride.\nHold the bin 1.5 s to discard.");
        lv_obj_t *del = ui_hold_btn(scr, LV_SYMBOL_TRASH, C_PANEL, C_RED, 44, 44, 1500, discard_cb, NULL);
        lv_obj_set_style_text_font(ui_hold_label(del), &lv_font_montserrat_20, 0);
        lv_obj_align(del, LV_ALIGN_TOP_LEFT, 54, 166);
        lv_obj_t *sv = ui_pill(scr, "SAVE", C_GREEN, C_INK, 96, 44, save_cb, NULL);
        lv_obj_align(sv, LV_ALIGN_TOP_LEFT, 106, 166);
    } else {
        lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 44, back_hist, NULL);
        lv_obj_align(bk, LV_ALIGN_TOP_MID, 0, 172);
    }
    ui_screen_show(scr);
}

/* ---------------- History */
/* rc3 (QA QF-27): the history list buffer (20 summaries, ~4.7 KB) lives in PSRAM, allocated when History is first opened */
static bc_ride_summary_t *h_rides; static int h_n; static bool h_demo;

static void open_ride(lv_event_t *e) { int i = (int)(intptr_t)lv_event_get_user_data(e); ui_results_show(&h_rides[i], false); }
static void go_home(lv_event_t *e) { (void)e; ui_home_show(); }
static void toggle(lv_event_t *e) { (void)e; ui_history_show(!h_demo); }

void ui_history_show(bool demo)
{
    h_demo = demo;
    if (!h_rides) h_rides = plat_alloc_ext(sizeof *h_rides * 20);
    h_n = h_rides ? app_history(h_rides, 20, demo) : 0;
    lv_obj_t *scr = ui_screen_new(UI_SCR_HISTORY, NULL);
    lv_obj_t *t = ui_title(scr, demo ? "DEMO RIDES" : "HISTORY");
    if (demo) lv_obj_set_style_text_color(t, C_DEMO, 0);
    lv_obj_t *list = ui_scroll_area(scr, 52, 172);
    char l[32], r[16], d[16];
    for (int i = 0; i < h_n; i++) {
        bc_fmt_duration(h_rides[i].duration_s, d, sizeof d);
        snprintf(l, sizeof l, "#%u  %s%s", h_rides[i].id, d, h_rides[i].recovered ? "*" : "");
        if (h_rides[i].avg_power >= 0) snprintf(r, sizeof r, "%d W", h_rides[i].avg_power); else snprintf(r, sizeof r, "--");
        ui_row_btn(list, l, r, C_CYAN, open_ride, (void *)(intptr_t)i);
    }
    if (h_n == 0) {
        lv_obj_t *e = ui_label(list, &lv_font_montserrat_14, C_MUT, demo ? "No demo rides." : "No rides yet.\nYour first real ride\nwill appear here.");
        (void)e;
    }
    ui_pill(list, demo ? "REAL RIDES" : "DEMO RIDES", C_PANEL, demo ? C_CYAN : C_DEMO, 130, 32, toggle, NULL);
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_HOME, C_PANEL, C_FG, 44, go_home, NULL);
    lv_obj_align(bk, LV_ALIGN_TOP_MID, 0, 180);
    ui_screen_show(scr);
}
