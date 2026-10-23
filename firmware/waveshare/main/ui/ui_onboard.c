/*
 * First-time onboarding (approved 2026-10-23):
 *   Welcome -> Name -> Age -> Weight -> Experience -> Main goal -> Power meter (skippable) -> HR strap (optional)
 *   -> Wi-Fi (optional) -> Ready.
 * Name: letter groups around the ring. Numbers: spinning wheels. Height lives in Settings only.
 * The same editors are reused from Settings (onboarding=false): SAVE returns to Settings.
 * Every change is saved immediately to the profile (power-loss safe NVS on the device).
 */
#include "ui.h"
#include <stdio.h>
#include <string.h>

typedef enum { ST_WELCOME = 0, ST_NAME, ST_AGE, ST_WEIGHT, ST_EXP, ST_GOAL, ST_POWER, ST_HR, ST_WIFI, ST_READY } step_t;
static bool s_onb;                 /* editors are part of onboarding */
static ui_edit_t s_edit;
static lv_obj_t *s_wheel;

static void go_step(step_t s);
static void save(void) { app_profile_save(); }

/* ---------------- Welcome */
static void welcome_next(lv_event_t *e) { (void)e; go_step(ST_NAME); }

static void show_welcome(void)
{
    lv_obj_t *scr = ui_screen_new(UI_SCR_ONBOARD, NULL);
    ui_title(scr, "BIKE COMPUTER");
    lv_obj_t *h = ui_label(scr, &bc_bold22, C_FG, "Hello!");
    lv_obj_align(h, LV_ALIGN_TOP_MID, 0, 62);
    lv_obj_t *t = ui_label(scr, &lv_font_montserrat_14, C_MUT, "Set-up takes about a minute.\nNo phone or internet needed.\nEverything stays on this device.");
    lv_obj_align(t, LV_ALIGN_TOP_MID, 0, 96);
    ui_nav(scr, NULL, "START", welcome_next, NULL);
    ui_screen_show(scr);
}

/* ---------------- Name: letter groups around the ring.
 * All buttons are created once and only shown/hidden/relabelled, so nothing is deleted inside its own tap handler. */
static const char *GROUPS[6] = { "ABCDE", "FGHIJ", "KLMNO", "PQRST", "UVWXY", "Z_<" };
static const int16_t G_ANG[6] = { 270, 330, 30, 90, 150, 210 };
static lv_obj_t *s_name_lbl, *s_grp[6], *s_let[5], *s_close, *s_name_hint, *s_name_ok, *s_name_back;
static int s_open = -1;
static char s_name[17];
static char s_letter_ch[5];

static void place(lv_obj_t *o, int ang, int r, int size)
{
    int32_t c = lv_trigo_cos((int16_t)ang), sn = lv_trigo_sin((int16_t)ang);   /* scaled by 32767 */
    lv_obj_set_pos(o, UI_R + (int)(r * c / 32767) - size / 2, UI_R + (int)(r * sn / 32767) - size / 2);
}

static void name_draw(void)
{
    char shown[24]; snprintf(shown, sizeof shown, "%s_", s_name);
    lv_label_set_text(s_name_lbl, shown);
    bool open = s_open >= 0;
    for (int g = 0; g < 6; g++) { if (open) lv_obj_add_flag(s_grp[g], LV_OBJ_FLAG_HIDDEN); else lv_obj_remove_flag(s_grp[g], LV_OBJ_FLAG_HIDDEN); }
    lv_obj_t *centre[3] = { s_name_hint, s_name_ok, s_name_back };
    for (int i = 0; i < 3; i++) { if (open) lv_obj_add_flag(centre[i], LV_OBJ_FLAG_HIDDEN); else lv_obj_remove_flag(centre[i], LV_OBJ_FLAG_HIDDEN); }
    if (open) lv_obj_remove_flag(s_close, LV_OBJ_FLAG_HIDDEN); else lv_obj_add_flag(s_close, LV_OBJ_FLAG_HIDDEN);
    int n = open ? (int)strlen(GROUPS[s_open]) : 0;
    for (int i = 0; i < 5; i++) {
        if (i >= n) { lv_obj_add_flag(s_let[i], LV_OBJ_FLAG_HIDDEN); continue; }
        char ch = GROUPS[s_open][i]; s_letter_ch[i] = ch;
        lv_obj_t *l = lv_obj_get_child(s_let[i], 0);
        if (ch == '_') { lv_label_set_text(l, "SPACE"); lv_obj_set_style_text_font(l, &lv_font_montserrat_12, 0); }
        else if (ch == '<') { lv_label_set_text(l, LV_SYMBOL_BACKSPACE); lv_obj_set_style_text_font(l, &lv_font_montserrat_20, 0); }
        else { char t[2] = { ch, 0 }; lv_label_set_text(l, t); lv_obj_set_style_text_font(l, &bc_bold22, 0); }
        /* letters spread around the ring, centred on the group's own position */
        place(s_let[i], G_ANG[s_open] + (i * 2 - (n - 1)) * 23, 84, 50);
        lv_obj_remove_flag(s_let[i], LV_OBJ_FLAG_HIDDEN);
    }
}

static void key_cb(lv_event_t *e)
{
    int i = (int)(intptr_t)lv_event_get_user_data(e);
    char k = s_letter_ch[i];
    size_t n = strlen(s_name);
    if (k == '<') { if (n) s_name[n - 1] = 0; }
    else if (k == '_') { if (n && n < 16 && s_name[n - 1] != ' ') { s_name[n] = ' '; s_name[n + 1] = 0; } }
    else if (n < 16) {
        char c = k;
        if (n > 0 && s_name[n - 1] != ' ') c = (char)(c - 'A' + 'a');   /* "Rashed": capital at the start and after a space */
        s_name[n] = c; s_name[n + 1] = 0;
    }
    s_open = -1; name_draw();
}

static void group_cb(lv_event_t *e) { s_open = (int)(intptr_t)lv_event_get_user_data(e); name_draw(); }
static void close_cb(lv_event_t *e) { (void)e; s_open = -1; name_draw(); }

static void name_done(lv_event_t *e)
{
    (void)e;
    size_t n = strlen(s_name); while (n && s_name[n - 1] == ' ') s_name[--n] = 0;
    snprintf(app_profile()->name, sizeof app_profile()->name, "%s", s_name);
    save();
    if (s_onb) go_step(ST_AGE); else ui_settings_show();
}

static void name_back(lv_event_t *e) { (void)e; if (s_onb) go_step(ST_WELCOME); else ui_settings_show(); }

static void show_name(void)
{
    lv_obj_t *scr = ui_screen_new(UI_SCR_ONBOARD, NULL);
    snprintf(s_name, sizeof s_name, "%s", app_profile()->name);
    s_open = -1;
    s_name_hint = ui_label(scr, &lv_font_montserrat_12, C_CYAN, "YOUR NAME");
    lv_obj_align(s_name_hint, LV_ALIGN_TOP_MID, 0, 74);
    s_name_lbl = ui_label(scr, &bc_bold22, C_FG, "");
    lv_obj_set_width(s_name_lbl, 120); lv_label_set_long_mode(s_name_lbl, LV_LABEL_LONG_SCROLL_CIRCULAR);
    lv_obj_align(s_name_lbl, LV_ALIGN_TOP_MID, 0, 90);
    s_name_ok = ui_pill(scr, s_onb ? "NEXT" : "SAVE", C_CYAN, C_INK, 76, 32, name_done, NULL);
    lv_obj_align(s_name_ok, LV_ALIGN_TOP_MID, 0, 120);
    s_name_back = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_MUT, 30, name_back, NULL);
    lv_obj_align(s_name_back, LV_ALIGN_TOP_MID, 0, 156);
    lv_obj_set_style_text_font(lv_obj_get_child(s_name_back, 0), &lv_font_montserrat_14, 0);
    for (int g = 0; g < 6; g++) {
        char txt[8];
        if (g < 5) snprintf(txt, sizeof txt, "%c-%c", GROUPS[g][0], GROUPS[g][4]); else snprintf(txt, sizeof txt, "Z _ <");
        s_grp[g] = ui_round_btn(scr, txt, C_PANEL, C_FG, 52, group_cb, (void *)(intptr_t)g);
        lv_obj_set_style_text_font(lv_obj_get_child(s_grp[g], 0), &bc_bold16, 0);
        place(s_grp[g], G_ANG[g], 84, 52);
    }
    for (int i = 0; i < 5; i++) s_let[i] = ui_round_btn(scr, "", C_CYAN, C_INK, 50, key_cb, (void *)(intptr_t)i);
    s_close = ui_round_btn(scr, LV_SYMBOL_CLOSE, C_PANEL, C_MUT, 40, close_cb, NULL);
    lv_obj_align(s_close, LV_ALIGN_TOP_MID, 0, 130);
    name_draw();
    ui_screen_show(scr);
}

/* ---------------- wheels */
static char s_opts[1800];
typedef struct { const char *title, *unit, *hint; int sel; } wheel_def_t;

static void build_range(int lo, int hi, int step, int div, const char *first)
{
    size_t n = 0; s_opts[0] = 0;
    if (first) n += (size_t)snprintf(s_opts + n, sizeof s_opts - n, "%s\n", first);
    for (int v = lo; v <= hi && n < sizeof s_opts - 12; v += step) {
        if (div == 10) n += (size_t)snprintf(s_opts + n, sizeof s_opts - n, "%d.%d\n", v / 10, v % 10);
        else n += (size_t)snprintf(s_opts + n, sizeof s_opts - n, "%d\n", v);
    }
    if (n) s_opts[n - 1] = 0;
}

static lv_obj_t *s_hint_lbl;

static void wheel_changed(lv_event_t *e)
{
    (void)e;
    int i = (int)lv_roller_get_selected(s_wheel);
    if (!s_hint_lbl) return;
    if (s_edit == UI_EDIT_EXP) lv_label_set_text(s_hint_lbl, bc_exp_hint(i));
    else if (s_edit == UI_EDIT_GOAL) lv_label_set_text(s_hint_lbl, bc_goal_hint(i));
    else if (s_edit == UI_EDIT_BRIGHT) plat_backlight(10 + i * 10);
    else if (s_edit == UI_EDIT_STYLE) { static const char *H[3] = { "big watts, arc, coach line", "watts top, cadence + HR below", "coach first, colour ring" }; lv_label_set_text(s_hint_lbl, H[i % 3]); }
}

static void wheel_save(lv_event_t *e)
{
    (void)e;
    bc_profile_t *p = app_profile();
    int i = (int)lv_roller_get_selected(s_wheel);
    switch (s_edit) {
    case UI_EDIT_AGE: p->age = (uint8_t)(14 + i); break;
    case UI_EDIT_WEIGHT: p->weight_dg = (uint16_t)(400 + i * 5); bc_profile_refresh_assumption(p); break;
    case UI_EDIT_HEIGHT: p->height_cm = (uint16_t)(i == 0 ? 0 : 119 + i); break;
    case UI_EDIT_EXP: p->exp = (uint8_t)i; bc_profile_refresh_assumption(p); break;
    case UI_EDIT_GOAL: p->goal = (uint8_t)i; break;
    case UI_EDIT_FTP:
        if (i == 0) { p->ftp_how = BC_FTP_NONE; p->ftp_w = 0; bc_profile_refresh_assumption(p); }
        else { p->ftp_w = (uint16_t)(45 + i * 5); p->ftp_how = BC_FTP_ENTERED; snprintf(p->ftp_note, sizeof p->ftp_note, "Entered by you: %u W from a real test.", p->ftp_w); }
        break;
    case UI_EDIT_MAXHR: p->max_hr = (uint8_t)(i == 0 ? 0 : 119 + i); break;
    case UI_EDIT_STYLE: p->ride_style = (uint8_t)i; break;
    case UI_EDIT_BRIGHT: p->brightness = (uint8_t)(10 + i * 10); plat_backlight(p->brightness); break;
    default: break;
    }
    save();
    if (!s_onb) { if (s_edit == UI_EDIT_BRIGHT || s_edit == UI_EDIT_STYLE) ui_display_show(); else ui_settings_show(); return; }
    switch (s_edit) {
    case UI_EDIT_AGE: go_step(ST_WEIGHT); break;
    case UI_EDIT_WEIGHT: go_step(ST_EXP); break;
    case UI_EDIT_EXP: go_step(ST_GOAL); break;
    case UI_EDIT_GOAL: go_step(ST_POWER); break;
    default: ui_settings_show(); break;
    }
}

static void wheel_back(lv_event_t *e)
{
    (void)e;
    if (s_edit == UI_EDIT_BRIGHT) plat_backlight(app_profile()->brightness);
    if (!s_onb) { if (s_edit == UI_EDIT_BRIGHT || s_edit == UI_EDIT_STYLE) ui_display_show(); else ui_settings_show(); return; }
    switch (s_edit) {
    case UI_EDIT_AGE: go_step(ST_NAME); break;
    case UI_EDIT_WEIGHT: go_step(ST_AGE); break;
    case UI_EDIT_EXP: go_step(ST_WEIGHT); break;
    case UI_EDIT_GOAL: go_step(ST_EXP); break;
    default: ui_settings_show(); break;
    }
}

static void show_wheel(void)
{
    bc_profile_t *p = app_profile();
    const char *title = "", *unit = NULL, *hint = NULL; int sel = 0; const lv_font_t *f = &lv_font_montserrat_28; int w = 120;
    s_hint_lbl = NULL;
    switch (s_edit) {
    case UI_EDIT_AGE: title = "AGE"; unit = "yrs"; build_range(14, 90, 1, 1, NULL); sel = p->age >= 14 && p->age <= 90 ? p->age - 14 : 21; break;
    case UI_EDIT_WEIGHT: title = "WEIGHT"; unit = "kg"; build_range(400, 1500, 5, 10, NULL);
        sel = p->weight_dg >= 400 && p->weight_dg <= 1500 ? (p->weight_dg - 400) / 5 : 70; break;
    case UI_EDIT_HEIGHT: title = "HEIGHT"; unit = "cm"; w = 140; build_range(120, 220, 1, 1, "not set"); sel = p->height_cm >= 120 ? p->height_cm - 119 : 0; break;
    case UI_EDIT_EXP: title = "EXPERIENCE"; f = &lv_font_montserrat_20; w = 176;
        snprintf(s_opts, sizeof s_opts, "Beginner\nNovice\nIntermediate\nAdvanced\nCompetitive"); sel = p->exp; hint = bc_exp_hint(p->exp); break;
    case UI_EDIT_GOAL: title = "MAIN GOAL"; f = &lv_font_montserrat_20; w = 176;
        snprintf(s_opts, sizeof s_opts, "Endurance\nRaise FTP\nClimbing\nFitness\nBody comp.\nRace / event"); sel = p->goal; hint = bc_goal_hint(p->goal); break;
    case UI_EDIT_FTP: title = "TESTED FTP"; unit = "W"; w = 140; build_range(50, 500, 5, 1, "auto");
        sel = p->ftp_how == BC_FTP_ENTERED && p->ftp_w >= 50 ? (p->ftp_w - 45) / 5 : 0; break;
    case UI_EDIT_MAXHR: title = "MAX HR"; unit = "bpm"; w = 150; build_range(120, 220, 1, 1, "estimate"); sel = p->max_hr >= 120 ? p->max_hr - 119 : 0; break;
    case UI_EDIT_STYLE: title = "RIDE SCREEN"; f = &lv_font_montserrat_20; w = 176;
        snprintf(s_opts, sizeof s_opts, "A Power Focus\nB Split\nC Coach First"); sel = p->ride_style; hint = " "; break;
    case UI_EDIT_BRIGHT: title = "BRIGHTNESS"; build_range(10, 100, 10, 1, NULL); unit = "%"; sel = p->brightness >= 10 ? (p->brightness - 10) / 10 : 7; break;
    default: break;
    }
    lv_obj_t *scr = ui_screen_new(UI_SCR_ONBOARD, NULL);
    ui_title(scr, title);
    s_wheel = ui_wheel(scr, s_opts, sel, w, 3, f);
    lv_obj_set_style_text_line_space(s_wheel, f == &lv_font_montserrat_28 ? 6 : 10, 0);
    lv_obj_align(s_wheel, LV_ALIGN_TOP_MID, 0, 52);
    lv_obj_add_event_cb(s_wheel, wheel_changed, LV_EVENT_VALUE_CHANGED, NULL);
    if (unit) { lv_obj_t *u = ui_label(scr, &lv_font_montserrat_14, C_MUT, unit); lv_obj_align_to(u, s_wheel, LV_ALIGN_OUT_RIGHT_MID, 2, 0); }
    if (hint) {
        s_hint_lbl = ui_label(scr, &lv_font_montserrat_12, C_MUT, hint);
        lv_obj_align(s_hint_lbl, LV_ALIGN_TOP_MID, 0, 148);
        if (s_edit == UI_EDIT_STYLE) wheel_changed(NULL);
    }
    ui_nav(scr, wheel_back, s_onb ? "NEXT" : "SAVE", wheel_save, NULL);
    ui_screen_show(scr);
}

/* ---------------- Wi-Fi (optional) */
static void wifi_set(lv_event_t *e)
{
    bool on = (bool)(intptr_t)lv_event_get_user_data(e);
    app_profile()->wifi_on = on; save();
    plat_wifi_set_enabled(on);
    if (s_onb) go_step(ST_READY); else ui_settings_show();
}
static void wifi_back(lv_event_t *e) { (void)e; if (s_onb) go_step(ST_HR); else ui_settings_show(); }

static void show_wifi(void)
{
    lv_obj_t *scr = ui_screen_new(UI_SCR_ONBOARD, NULL);
    ui_title(scr, "WI-FI");
    lv_obj_t *t = ui_label(scr, &lv_font_montserrat_14, C_MUT, "Optional. Rides, coaching\nand history work offline.\nWi-Fi is for future sync\nand updates.");
    lv_obj_align(t, LV_ALIGN_TOP_MID, 0, 56);
    lv_obj_t *off = ui_pill(scr, "KEEP OFF", C_CYAN, C_INK, 112, 36, wifi_set, (void *)0);
    lv_obj_align(off, LV_ALIGN_TOP_MID, 0, 132);
    lv_obj_t *on = ui_pill(scr, "TURN ON", C_PANEL, C_FG, 96, 32, wifi_set, (void *)1);
    lv_obj_align(on, LV_ALIGN_TOP_MID, 22, 176);
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 36, wifi_back, NULL);
    lv_obj_align(bk, LV_ALIGN_TOP_MID, -52, 174);
    ui_screen_show(scr);
}

/* ---------------- Ready */
static void ready_go(lv_event_t *e)
{
    (void)e;
    app_profile()->onboarded = true; save();
    ui_home_show();
}
static void ready_back(lv_event_t *e) { (void)e; go_step(ST_WIFI); }

static void show_ready(void)
{
    bc_profile_t *p = app_profile();
    bc_profile_refresh_assumption(p); save();
    lv_obj_t *scr = ui_screen_new(UI_SCR_ONBOARD, NULL);
    ui_title(scr, "READY");
    lv_obj_t *n = ui_label(scr, &bc_bold22, C_FG, bc_profile_display_name(p));
    lv_obj_align(n, LV_ALIGN_TOP_MID, 0, 54);
    char b[48]; snprintf(b, sizeof b, "FTP %u W", p->ftp_w);
    lv_obj_t *f = ui_label(scr, &bc_bold22, C_FG, b);
    lv_obj_align(f, LV_ALIGN_TOP_MID, 0, 84);
    lv_obj_t *tag = ui_label(scr, &bc_bold16, bc_ftp_established(p) ? C_GREEN : C_AMBER, bc_ftp_label(p));
    lv_obj_align(tag, LV_ALIGN_TOP_MID, 0, 110);
    lv_obj_t *t = ui_label(scr, &lv_font_montserrat_12, C_MUT, bc_ftp_established(p) ? "" : "starting assumption,\nlearns from real rides");
    lv_obj_align(t, LV_ALIGN_TOP_MID, 0, 130);
    ui_nav(scr, ready_back, "RIDE ON", ready_go, NULL);
    ui_screen_show(scr);
}

/* ---------------- flow */
static void go_step(step_t s)
{
    s_onb = true;
    switch (s) {
    case ST_WELCOME: show_welcome(); break;
    case ST_NAME: s_edit = UI_EDIT_NAME; show_name(); break;
    case ST_AGE: s_edit = UI_EDIT_AGE; show_wheel(); break;
    case ST_WEIGHT: s_edit = UI_EDIT_WEIGHT; show_wheel(); break;
    case ST_EXP: s_edit = UI_EDIT_EXP; show_wheel(); break;
    case ST_GOAL: s_edit = UI_EDIT_GOAL; show_wheel(); break;
    case ST_POWER: ui_pair_show(PLAT_SENS_POWER, true); break;
    case ST_HR: ui_pair_show(PLAT_SENS_HR, true); break;
    case ST_WIFI: s_edit = UI_EDIT_WIFI; show_wifi(); break;
    case ST_READY: show_ready(); break;
    }
}

void ui_onboard_start(void) { go_step(ST_WELCOME); }

/* called by the pairing screen */
void ui_onboard_after_pair(plat_sens_kind_t k, bool forward)
{
    if (k == PLAT_SENS_POWER) go_step(forward ? ST_HR : ST_GOAL);
    else go_step(forward ? ST_WIFI : ST_POWER);
}

void ui_edit_show(ui_edit_t what, bool onboarding)
{
    s_onb = onboarding; s_edit = what;
    if (what == UI_EDIT_NAME) show_name();
    else if (what == UI_EDIT_WIFI) show_wifi();
    else show_wheel();
}
