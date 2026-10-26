/* Settings (everything from onboarding can be edited here, plus height, FTP, max HR, ride screen style, brightness,
 * Wi-Fi, demo mode) and the Diagnostics page. */
#include "ui.h"
#include <stdio.h>
#include <string.h>

static void edit_cb(lv_event_t *e) { ui_edit_show((ui_edit_t)(intptr_t)lv_event_get_user_data(e), false); }
static void sensors_cb(lv_event_t *e) { (void)e; ui_connections_show(); }
static void diag_cb(lv_event_t *e) { (void)e; ui_diag_menu_show(); }
static void display_cb(lv_event_t *e) { (void)e; ui_display_show(); }
static void wifi_cb(lv_event_t *e) { (void)e; ui_set_return_connections(false); ui_wifi_show(); }
static void phone_cb(lv_event_t *e) { (void)e; ui_set_return_connections(false); ui_phone_show(); }
static void power_cb(lv_event_t *e) { (void)e; ui_power_settings_show(); }
static void home_cb(lv_event_t *e) { (void)e; ui_home_show(); }
static void demo_cb(lv_event_t *e) { (void)e; app_set_demo(!app_demo()); ui_settings_show(); }
static void setup_cb(lv_event_t *e) { (void)e; app_profile_reset(); ui_onboard_start(); }

static int s_scroll_y;
static lv_obj_t *s_list;
static void remember_scroll(lv_event_t *e) { (void)e; s_scroll_y = lv_obj_get_scroll_y(s_list); }

void ui_settings_show(void)
{
    bc_profile_t *p = app_profile();
    lv_obj_t *scr = ui_screen_new(UI_SCR_SETTINGS, NULL);
    ui_title(scr, "SETTINGS");
    lv_obj_t *l = ui_scroll_area(scr, 50, 176);
    s_list = l;
    char v[32];
    ui_row_btn(l, "Name", bc_profile_display_name(p), C_CYAN, edit_cb, (void *)UI_EDIT_NAME);
    snprintf(v, sizeof v, "%u", p->age); ui_row_btn(l, "Age", v, C_CYAN, edit_cb, (void *)UI_EDIT_AGE);
    snprintf(v, sizeof v, "%u.%u kg", (unsigned)(p->weight_dg / 10), (unsigned)(p->weight_dg % 10)); ui_row_btn(l, "Weight", v, C_CYAN, edit_cb, (void *)UI_EDIT_WEIGHT);
    if (p->height_cm) snprintf(v, sizeof v, "%u cm", p->height_cm); else snprintf(v, sizeof v, "not set");
    ui_row_btn(l, "Height", v, C_CYAN, edit_cb, (void *)UI_EDIT_HEIGHT);
    ui_row_btn(l, "Level", bc_exp_name(p->exp), C_CYAN, edit_cb, (void *)UI_EDIT_EXP);
    ui_row_btn(l, "Goal", bc_goal_name(p->goal), C_CYAN, edit_cb, (void *)UI_EDIT_GOAL);
    snprintf(v, sizeof v, "%u W %s", p->ftp_w, bc_ftp_established(p) ? "" : "prov.");
    ui_row_btn(l, "FTP", v, bc_ftp_established(p) ? C_GREEN : C_AMBER, edit_cb, (void *)UI_EDIT_FTP);
    if (p->ftp_note[0]) { lv_obj_t *n = ui_label(l, &lv_font_montserrat_12, C_MUT, p->ftp_note); lv_obj_set_width(n, lv_pct(100)); lv_label_set_long_mode(n, LV_LABEL_LONG_WRAP); }
    if (p->max_hr) snprintf(v, sizeof v, "%u", p->max_hr); else snprintf(v, sizeof v, "est. %d", bc_profile_max_hr(p));
    ui_row_btn(l, "Max HR", v, C_CYAN, edit_cb, (void *)UI_EDIT_MAXHR);
    snprintf(v, sizeof v, "%c  " LV_SYMBOL_RIGHT, ui_ride_design(p->ride_style)->letter); ui_row_btn(l, "Display", v, C_CYAN, display_cb, NULL);
    { int c, a; ui_conn_summary(&c, &a); snprintf(v, sizeof v, a ? "! %d  " LV_SYMBOL_RIGHT : "%d on  " LV_SYMBOL_RIGHT, a ? a : c); ui_row_btn(l, "Connections", v, a ? C_RED : C_CYAN, sensors_cb, NULL); }
    ui_row_btn(l, "Wi-Fi", p->wifi_on ? "on" : "off", C_CYAN, wifi_cb, NULL);
    { plat_phone_status_t ps; plat_phone_status(&ps); ui_row_btn(l, "Phone", !p->phone_on ? "off" : ps.state == PLAT_PHONE_READY ? "connected" : ps.state == PLAT_PHONE_REPAIR ? "! repair" : ps.bonded ? "remembered" : "not paired", ps.state == PLAT_PHONE_READY ? C_GREEN : ps.state == PLAT_PHONE_REPAIR ? C_RED : C_CYAN, phone_cb, NULL); }
    { char bs[16]; app_power_batt_short(bs, sizeof bs); ui_row_btn(l, "Power", bs, C_CYAN, power_cb, NULL); }
    ui_row_btn(l, "Demo mode", app_demo() ? "ON" : "off", app_demo() ? C_DEMO : C_MUT, demo_cb, NULL);
    ui_row_btn(l, "Diagnostics", LV_SYMBOL_RIGHT, C_CYAN, diag_cb, NULL);
    lv_obj_t *again = ui_hold_btn(l, "HOLD: SET UP AGAIN", C_PANEL, C_AMBER, lv_pct(100), 40, 2000, setup_cb, NULL);
    lv_obj_set_style_text_font(ui_hold_label(again), &lv_font_montserrat_12, 0);
    { plat_health_t h; plat_health(&h); char fb[64]; snprintf(fb, sizeof fb, "firmware %s\nbuild %s", plat_fw_version(), h.build);
      lv_obj_t *f = ui_label(l, &lv_font_montserrat_12, C_MUT, fb); lv_obj_set_width(f, lv_pct(100)); lv_label_set_long_mode(f, LV_LABEL_LONG_WRAP); }
    lv_obj_add_event_cb(l, remember_scroll, LV_EVENT_SCROLL_END, NULL);
    lv_obj_update_layout(l);
    lv_obj_scroll_to_y(l, s_scroll_y, LV_ANIM_OFF);
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_HOME, C_PANEL, C_FG, 44, home_cb, NULL);
    lv_obj_align(bk, LV_ALIGN_TOP_MID, 0, 182);
    ui_screen_show(scr);
}

/* ---------------- Diagnostics */
static lv_obj_t *d_txt;
static void diag_update(void)
{
    static char b[700]; char st[480], mem[96];
    plat_selftest_text(st, sizeof st); plat_mem_text(mem, sizeof mem);
    snprintf(b, sizeof b, "%s\n#8494a0 firmware# %s\n#8494a0 reset# %s\n#8494a0 boot# %lu\n%s", st, plat_fw_version(), plat_reset_reason(),
             (unsigned long)plat_boot_count(), mem);
    lv_label_set_text(d_txt, b);
}
static void back_settings(lv_event_t *e) { (void)e; ui_diag_menu_show(); }

void ui_diag_show(void)
{
    lv_obj_t *scr = ui_screen_new(UI_SCR_DIAG, diag_update);
    ui_title(scr, "SELF-TEST");
    lv_obj_t *l = ui_scroll_area(scr, 50, 178);
    d_txt = ui_label(l, &lv_font_montserrat_12, C_FG, "");
    lv_obj_set_width(d_txt, lv_pct(100));
    lv_label_set_long_mode(d_txt, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_align(d_txt, LV_TEXT_ALIGN_LEFT, 0);
    lv_label_set_recolor(d_txt, true);
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 44, back_settings, NULL);
    lv_obj_align(bk, LV_ALIGN_TOP_MID, 0, 182);
    ui_screen_show(scr);
}
