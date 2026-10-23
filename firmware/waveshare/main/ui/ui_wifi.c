/*
 * Wi-Fi manager screens (Settings > Wi-Fi): status + on/off, network list with rescan, ring keyboard for passwords and
 * hidden network names, connecting/result screen with plain errors, saved networks (connect / hold to forget).
 * Everything here only posts requests to the background manager (plat_wifi_*) and redraws from its status, so the
 * screen stays responsive while scanning or connecting.
 */
#include "ui.h"
#include <stdio.h>
#include <string.h>
#include "bc_wifi.h"

static void wifi_main(void);
static void networks_show(void);
static void saved_show(void);
static void keyboard_show(bool for_ssid);
static void connecting_show(void);

static char w_ssid[33];          /* network being joined */
static char w_pass[65];          /* typed password (wiped after use) */

static void wipe(void) { memset(w_pass, 0, sizeof w_pass); }

static const char *state_text(const plat_wifi_status_t *s)
{
    switch (s->state) {
    case PLAT_WIFI_OFF: return "OFF";
    case PLAT_WIFI_IDLE: return "ON - not connected";
    case PLAT_WIFI_SCANNING: return "SCANNING...";
    case PLAT_WIFI_CONNECTING: return "CONNECTING...";
    case PLAT_WIFI_CONNECTED: return "CONNECTED";
    case PLAT_WIFI_FAILED: return "NOT CONNECTED";
    }
    return "";
}

/* ---------------- main Wi-Fi screen */
static lv_obj_t *m_status, *m_list; static int m_last_state = -1; static bool m_last_on;

static void back_settings(lv_event_t *e) { (void)e; ui_settings_show(); }
static void toggle_cb(lv_event_t *e)
{
    (void)e;
    bc_profile_t *p = app_profile();
    p->wifi_on = !p->wifi_on; app_profile_save();
    plat_wifi_set_enabled(p->wifi_on);
    wifi_main();
}
static void nets_cb(lv_event_t *e) { (void)e; networks_show(); }
static void saved_cb(lv_event_t *e) { (void)e; saved_show(); }
static void disc_cb(lv_event_t *e) { (void)e; plat_wifi_disconnect(); }

static void build_rows(void)
{
    lv_obj_clean(m_list);
    bool on = app_profile()->wifi_on;
    plat_wifi_status_t s; plat_wifi_status(&s);
    ui_row_btn(m_list, "Wi-Fi", on ? "ON" : "OFF", on ? C_GREEN : C_MUT, toggle_cb, NULL);
    m_status = ui_label(m_list, &lv_font_montserrat_14, C_FG, "");
    lv_obj_set_width(m_status, lv_pct(100)); lv_label_set_long_mode(m_status, LV_LABEL_LONG_WRAP); lv_label_set_recolor(m_status, true);
    if (on) {
        ui_row_btn(m_list, "Networks", LV_SYMBOL_RIGHT, C_CYAN, nets_cb, NULL);
        char saved[PLAT_WIFI_MAX_SAVED][33]; char v[16]; snprintf(v, sizeof v, "%d  " LV_SYMBOL_RIGHT, plat_wifi_saved(saved, PLAT_WIFI_MAX_SAVED));
        ui_row_btn(m_list, "Saved", v, C_CYAN, saved_cb, NULL);
        if (s.state == PLAT_WIFI_CONNECTED) ui_row_btn(m_list, "Disconnect", NULL, C_MUT, disc_cb, NULL);
    }
    lv_obj_t *n = ui_label(m_list, &lv_font_montserrat_12, C_MUT, "Optional. Rides, coaching and history work without Wi-Fi. 2.4 GHz networks only.");
    lv_obj_set_width(n, lv_pct(100)); lv_label_set_long_mode(n, LV_LABEL_LONG_WRAP);
    m_last_state = s.state; m_last_on = on;
}

static void main_update(void)
{
    plat_wifi_status_t s; plat_wifi_status(&s);
    if ((int)s.state != m_last_state || m_last_on != app_profile()->wifi_on) build_rows();
    char b[160];
    if (s.state == PLAT_WIFI_CONNECTED) snprintf(b, sizeof b, "#56e08c CONNECTED#\n%s\n%d dBm   %s", s.ssid, s.rssi, s.ip[0] ? s.ip : "no IP yet");
    else if (s.state == PLAT_WIFI_FAILED || (s.state == PLAT_WIFI_IDLE && s.err != PLAT_WIFI_ERR_NONE))
        snprintf(b, sizeof b, "#ffb64d %s#\n%s\n%s", state_text(&s), s.ssid, bc_wifi_err_text((bc_wifi_err_t)s.err));
    else if (s.state == PLAT_WIFI_CONNECTING) snprintf(b, sizeof b, "#ffb64d CONNECTING...#\n%s", s.ssid);
    else snprintf(b, sizeof b, "%s", state_text(&s));
    lv_label_set_text(m_status, b);
}

static void wifi_main(void)
{
    lv_obj_t *scr = ui_screen_new(UI_SCR_SETTINGS, main_update);
    ui_title(scr, "WI-FI");
    m_list = ui_scroll_area(scr, 50, 178);
    build_rows();
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 40, back_settings, NULL);
    lv_obj_align(bk, LV_ALIGN_TOP_MID, 0, 184);
    ui_screen_show(scr);
}

void ui_wifi_show(void) { wifi_main(); }

/* ---------------- network list */
static lv_obj_t *n_list, *n_info; static uint32_t n_scans_seen = UINT32_MAX; static int n_count = -1;
static plat_wifi_ap_t n_aps[12]; static int n_n;

static void pick_cb(lv_event_t *e)
{
    int i = (int)(intptr_t)lv_event_get_user_data(e);
    snprintf(w_ssid, sizeof w_ssid, "%s", n_aps[i].ssid);
    if (n_aps[i].saved) { plat_wifi_connect(w_ssid, NULL, false); connecting_show(); }
    else if (!n_aps[i].secured) { plat_wifi_connect(w_ssid, "", true); connecting_show(); }
    else keyboard_show(false);
}
static void other_cb(lv_event_t *e) { (void)e; w_ssid[0] = 0; keyboard_show(true); }
static void rescan_cb(lv_event_t *e) { (void)e; plat_wifi_scan(); }
static void back_main(lv_event_t *e) { (void)e; wifi_main(); }

static void nets_update(void)
{
    plat_wifi_status_t s; plat_wifi_status(&s);
    if (s.state == PLAT_WIFI_SCANNING) lv_label_set_text(n_info, "scanning...");
    else if (!s.scan_done) lv_label_set_text(n_info, "starting...");
    if (s.scans == n_scans_seen || s.state == PLAT_WIFI_SCANNING) return;
    n_scans_seen = s.scans;
    n_n = plat_wifi_results(n_aps, 12);
    char b[40]; snprintf(b, sizeof b, "%d found  -  2.4 GHz only", n_n); lv_label_set_text(n_info, b);
    lv_obj_clean(n_list);
    for (int i = 0; i < n_n; i++) {
        char left[24], right[16];
        if (strlen(n_aps[i].ssid) > 14) snprintf(left, sizeof left, "%.13s..", n_aps[i].ssid); else snprintf(left, sizeof left, "%.14s", n_aps[i].ssid);
        if (n_aps[i].saved) snprintf(right, sizeof right, LV_SYMBOL_OK " %d", n_aps[i].rssi);
        else snprintf(right, sizeof right, "%s%d", n_aps[i].secured ? "" : "open ", n_aps[i].rssi);
        ui_row_btn(n_list, left, right, n_aps[i].saved ? C_GREEN : C_MUT, pick_cb, (void *)(intptr_t)i);
    }
    ui_row_btn(n_list, "Other network...", LV_SYMBOL_EDIT, C_CYAN, other_cb, NULL);
    lv_obj_t *t = ui_label(n_list, &lv_font_montserrat_12, C_MUT, "iPhone hotspot: turn on Maximize Compatibility and keep the hotspot screen open.");
    lv_obj_set_width(t, lv_pct(100)); lv_label_set_long_mode(t, LV_LABEL_LONG_WRAP);
    n_count = n_n;
}

static void networks_show(void)
{
    lv_obj_t *scr = ui_screen_new(UI_SCR_SETTINGS, nets_update);
    ui_title(scr, "NETWORKS");
    n_info = ui_label(scr, &lv_font_montserrat_12, C_MUT, ""); lv_obj_align(n_info, LV_ALIGN_TOP_MID, 0, 50);
    n_list = ui_scroll_area(scr, 64, 178);
    n_scans_seen = UINT32_MAX; n_count = -1;
    plat_wifi_scan();
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 38, back_main, NULL); lv_obj_set_pos(bk, 76, 182);
    lv_obj_t *rs = ui_round_btn(scr, LV_SYMBOL_REFRESH, C_CYAN, C_INK, 38, rescan_cb, NULL); lv_obj_set_pos(rs, 126, 182);
    ui_screen_show(scr);
}

/* ---------------- saved networks */
static char s_saved[PLAT_WIFI_MAX_SAVED][33];
static void saved_pick(lv_event_t *e)
{
    int i = (int)(intptr_t)lv_event_get_user_data(e);
    snprintf(w_ssid, sizeof w_ssid, "%s", s_saved[i]);
    /* detail: connect or forget */
    lv_obj_t *scr = ui_screen_new(UI_SCR_SETTINGS, NULL);
    ui_title(scr, "SAVED");
    lv_obj_t *n = ui_label(scr, &bc_bold16, C_FG, w_ssid); lv_obj_set_width(n, 170); lv_label_set_long_mode(n, LV_LABEL_LONG_DOT);
    lv_obj_align(n, LV_ALIGN_TOP_MID, 0, 62);
    extern void ui__wifi_connect_saved(lv_event_t *e);
    extern void ui__wifi_forget(lv_event_t *e);
    lv_obj_t *c = ui_pill(scr, "CONNECT", C_CYAN, C_INK, 150, 40, ui__wifi_connect_saved, NULL); lv_obj_align(c, LV_ALIGN_TOP_MID, 0, 92);
    lv_obj_t *f = ui_hold_btn(scr, "HOLD: FORGET", C_PANEL, C_RED, 150, 40, 1500, ui__wifi_forget, NULL); lv_obj_align(f, LV_ALIGN_TOP_MID, 0, 140);
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 36, saved_cb, NULL); lv_obj_align(bk, LV_ALIGN_TOP_MID, 0, 190);
    ui_screen_show(scr);
}
void ui__wifi_connect_saved(lv_event_t *e) { (void)e; plat_wifi_connect(w_ssid, NULL, false); connecting_show(); }
void ui__wifi_forget(lv_event_t *e) { (void)e; plat_wifi_forget(w_ssid); saved_show(); }

static void saved_show(void)
{
    lv_obj_t *scr = ui_screen_new(UI_SCR_SETTINGS, NULL);
    ui_title(scr, "SAVED");
    lv_obj_t *l = ui_scroll_area(scr, 54, 176);
    int n = plat_wifi_saved(s_saved, PLAT_WIFI_MAX_SAVED);
    for (int i = 0; i < n; i++) {
        char left[24]; if (strlen(s_saved[i]) > 16) snprintf(left, sizeof left, "%.15s..", s_saved[i]); else snprintf(left, sizeof left, "%.16s", s_saved[i]);
        ui_row_btn(l, left, LV_SYMBOL_RIGHT, C_CYAN, saved_pick, (void *)(intptr_t)i);
    }
    if (!n) ui_label(l, &lv_font_montserrat_14, C_MUT, "No saved networks.\nPick one under Networks.");
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 40, back_main, NULL); lv_obj_align(bk, LV_ALIGN_TOP_MID, 0, 184);
    ui_screen_show(scr);
}

/* ---------------- ring keyboard (letter groups around the ring, like the name entry) */
static const char *const K_GROUPS[3][6] = {
    { "abcde", "fghij", "klmno", "pqrst", "uvwxy", "z.-_@" },
    { "ABCDE", "FGHIJ", "KLMNO", "PQRST", "UVWXY", "Z,!? " },
    { "123456", "7890#$", "%&*+/=", "\\^()[]", "{}<>:;", "\"'`|~" },
};
static const char *const K_MODE[3] = { "abc", "ABC", "123" };
static const int16_t K_ANG[6] = { 270, 330, 30, 90, 150, 210 };
#define K_R 92
#define K_KEY 44
static int k_mode, k_open = -1; static bool k_for_ssid, k_show;
static char k_buf[65];
static lv_obj_t *k_backbtn, *k_title, *k_text, *k_hint, *k_grp[6], *k_let[6], *k_close, *k_modebtn, *k_bs, *k_eye, *k_ok;
static char k_letch[6];

static void kplace(lv_obj_t *o, int ang, int r, int size)
{
    int32_t c = lv_trigo_cos((int16_t)ang), s = lv_trigo_sin((int16_t)ang);
    lv_obj_set_pos(o, UI_R + (int)(r * c / 32767) - size / 2, UI_R + (int)(r * s / 32767) - size / 2);
}

static void show(lv_obj_t *o, bool on) { if (on) lv_obj_remove_flag(o, LV_OBJ_FLAG_HIDDEN); else lv_obj_add_flag(o, LV_OBJ_FLAG_HIDDEN); }

static void k_draw(void)
{
    size_t n = strlen(k_buf);
    char vis[24];
    const char *src = k_buf; char masked[65];
    if (!k_for_ssid && !k_show) { for (size_t i = 0; i < n; i++) masked[i] = '*'; masked[n] = 0; src = masked; }
    if (n > 11) snprintf(vis, sizeof vis, "<%.10s_", src + n - 10); else snprintf(vis, sizeof vis, "%.11s_", src);
    lv_label_set_text(k_text, vis);
    char h[32];
    if (k_for_ssid) snprintf(h, sizeof h, "%u / 32", (unsigned)n);
    else snprintf(h, sizeof h, n == 0 ? "empty = open" : n < 8 ? "%u - need 8+" : "%u chars", (unsigned)n);
    lv_label_set_text(k_hint, h);
    lv_obj_set_style_text_color(k_hint, (!k_for_ssid && n > 0 && n < 8) ? C_AMBER : C_MUT, 0);
    bool open = k_open >= 0;
    for (int g = 0; g < 6; g++) {
        show(k_grp[g], !open);
        const char *gs = K_GROUPS[k_mode][g]; char lab[16]; size_t gl = strlen(gs);
        snprintf(lab, sizeof lab, "%.3s\n%s", gs, gl > 3 ? gs + 3 : "");
        for (char *c = lab; *c; c++) if (*c == ' ') *c = '_';
        lv_label_set_text(lv_obj_get_child(k_grp[g], 0), lab);
    }
    show(k_title, !open); show(k_backbtn, !open); show(k_modebtn, !open); show(k_bs, !open); show(k_eye, !open && !k_for_ssid); show(k_ok, !open); show(k_close, open);
    lv_label_set_text(lv_obj_get_child(k_modebtn, 0), K_MODE[k_mode]);
    lv_label_set_text(lv_obj_get_child(k_eye, 0), k_show ? LV_SYMBOL_EYE_CLOSE : LV_SYMBOL_EYE_OPEN);
    int cnt = open ? (int)strlen(K_GROUPS[k_mode][k_open]) : 0;
    for (int i = 0; i < 6; i++) {
        if (i >= cnt) { show(k_let[i], false); continue; }
        char ch = K_GROUPS[k_mode][k_open][i]; k_letch[i] = ch;
        lv_obj_t *l = lv_obj_get_child(k_let[i], 0);
        if (ch == ' ') { lv_label_set_text(l, "SPACE"); lv_obj_set_style_text_font(l, &lv_font_montserrat_12, 0); }
        else { char t[2] = { ch, 0 }; lv_label_set_text(l, t); lv_obj_set_style_text_font(l, &bc_bold22, 0); }
        kplace(k_let[i], K_ANG[k_open] + (i * 2 - (cnt - 1)) * 21, K_R, K_KEY);
        show(k_let[i], true);
    }
}

static void k_group(lv_event_t *e) { k_open = (int)(intptr_t)lv_event_get_user_data(e); k_draw(); }
static void k_close_cb(lv_event_t *e) { (void)e; k_open = -1; k_draw(); }
static void k_key(lv_event_t *e)
{
    int i = (int)(intptr_t)lv_event_get_user_data(e);
    size_t n = strlen(k_buf), max = k_for_ssid ? 32 : 63;
    if (n < max) { k_buf[n] = k_letch[i]; k_buf[n + 1] = 0; }
    k_open = -1; k_draw();
}
static void k_mode_cb(lv_event_t *e) { (void)e; k_mode = (k_mode + 1) % 3; k_draw(); }
static void k_bs_cb(lv_event_t *e) { (void)e; size_t n = strlen(k_buf); if (n) k_buf[n - 1] = 0; k_draw(); }
static void k_eye_cb(lv_event_t *e) { (void)e; k_show = !k_show; k_draw(); }
static void k_ok_cb(lv_event_t *e)
{
    (void)e;
    if (k_for_ssid) {
        if (!bc_wifi_ssid_valid(k_buf)) return;
        snprintf(w_ssid, sizeof w_ssid, "%.32s", k_buf);
        keyboard_show(false);
        return;
    }
    if (!bc_wifi_pass_valid(k_buf)) return;          /* hint already says why */
    snprintf(w_pass, sizeof w_pass, "%s", k_buf);
    memset(k_buf, 0, sizeof k_buf);
    plat_wifi_connect(w_ssid, w_pass, true);
    wipe();
    connecting_show();
}
static void k_back(lv_event_t *e) { (void)e; memset(k_buf, 0, sizeof k_buf); networks_show(); }

static void keyboard_show(bool for_ssid)
{
    k_for_ssid = for_ssid; k_open = -1; k_mode = 0; k_show = false; memset(k_buf, 0, sizeof k_buf);
    lv_obj_t *scr = ui_screen_new(UI_SCR_SETTINGS, NULL);
    k_title = ui_label(scr, &lv_font_montserrat_12, C_CYAN, for_ssid ? "NAME" : w_ssid);
    lv_obj_set_width(k_title, 84); lv_label_set_long_mode(k_title, LV_LABEL_LONG_DOT); lv_obj_align(k_title, LV_ALIGN_TOP_MID, 0, 56);
    k_text = ui_label(scr, &bc_bold16, C_FG, ""); lv_obj_align(k_text, LV_ALIGN_TOP_MID, 0, 72);
    k_hint = ui_label(scr, &lv_font_montserrat_12, C_MUT, ""); lv_obj_align(k_hint, LV_ALIGN_TOP_MID, 0, 92);
    k_modebtn = ui_pill(scr, "abc", C_PANEL, C_CYAN, 46, 30, k_mode_cb, NULL); lv_obj_set_pos(k_modebtn, 70, 108);
    lv_obj_set_style_text_font(lv_obj_get_child(k_modebtn, 0), &lv_font_montserrat_14, 0);
    k_bs = ui_round_btn(scr, LV_SYMBOL_BACKSPACE, C_PANEL, C_FG, 30, k_bs_cb, NULL); lv_obj_set_pos(k_bs, 122, 108);
    lv_obj_set_style_text_font(lv_obj_get_child(k_bs, 0), &lv_font_montserrat_14, 0);
    k_eye = ui_round_btn(scr, LV_SYMBOL_EYE_OPEN, C_PANEL, C_FG, 30, k_eye_cb, NULL); lv_obj_set_pos(k_eye, 158, 108);
    lv_obj_set_style_text_font(lv_obj_get_child(k_eye, 0), &lv_font_montserrat_14, 0);
    k_ok = ui_pill(scr, for_ssid ? "NEXT" : "JOIN", C_CYAN, C_INK, 86, 30, k_ok_cb, NULL); lv_obj_align(k_ok, LV_ALIGN_TOP_MID, 0, 148);
    for (int g = 0; g < 6; g++) {
        k_grp[g] = ui_round_btn(scr, "", C_PANEL, C_FG, K_KEY, k_group, (void *)(intptr_t)g);
        lv_obj_set_style_text_font(lv_obj_get_child(k_grp[g], 0), &lv_font_montserrat_12, 0);
        lv_obj_set_style_text_line_space(lv_obj_get_child(k_grp[g], 0), -2, 0);
        kplace(k_grp[g], K_ANG[g], K_R, K_KEY);
    }
    for (int i = 0; i < 6; i++) k_let[i] = ui_round_btn(scr, "", C_CYAN, C_INK, K_KEY, k_key, (void *)(intptr_t)i);
    k_close = ui_round_btn(scr, LV_SYMBOL_CLOSE, C_PANEL, C_MUT, 36, k_close_cb, NULL); lv_obj_align(k_close, LV_ALIGN_TOP_MID, 0, 120);
    k_backbtn = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 30, k_back, NULL); lv_obj_set_pos(k_backbtn, 34, 108);
    lv_obj_set_style_text_font(lv_obj_get_child(k_backbtn, 0), &lv_font_montserrat_14, 0);
    k_draw();
    ui_screen_show(scr);
}

/* ---------------- connecting / result */
static lv_obj_t *c_state, *c_msg, *c_btn, *c_btn2; static uint32_t c_t0, c_connects0, c_failures0; static int c_done;

static void c_done_cb(lv_event_t *e) { (void)e; wifi_main(); }
static void c_retry_cb(lv_event_t *e) { (void)e; keyboard_show(false); }

static void conn_update(void)
{
    plat_wifi_status_t s; plat_wifi_status(&s);
    if (c_done) return;
    uint32_t el = plat_ms() - c_t0;
    if (s.connects > c_connects0 && s.state == PLAT_WIFI_CONNECTED) {
        c_done = 1;
        lv_label_set_text(c_state, "CONNECTED"); lv_obj_set_style_text_color(c_state, C_GREEN, 0);
        char b[80]; snprintf(b, sizeof b, "%d dBm\nIP %s", s.rssi, s.ip); lv_label_set_text(c_msg, b);
        lv_label_set_text(lv_obj_get_child(c_btn, 0), "DONE"); show(c_btn, true);
    } else if (s.failures > c_failures0 || el > 35000) {
        c_done = 2;
        lv_label_set_text(c_state, "NOT CONNECTED"); lv_obj_set_style_text_color(c_state, C_AMBER, 0);
        const char *t = el > 35000 && s.failures == c_failures0 ? bc_wifi_err_text(BC_WIFI_ERR_TIMEOUT) : bc_wifi_err_text((bc_wifi_err_t)s.err);
        lv_label_set_text(c_msg, t);
        lv_label_set_text(lv_obj_get_child(c_btn, 0), "BACK"); show(c_btn, true);
        show(c_btn2, s.err == PLAT_WIFI_ERR_WRONG_PASSWORD || s.err == PLAT_WIFI_ERR_OTHER || s.err == PLAT_WIFI_ERR_TIMEOUT);
    } else {
        static const char *dots[4] = { "", ".", "..", "..." };
        char b[32]; snprintf(b, sizeof b, "CONNECTING%s", dots[(el / 500) % 4]); lv_label_set_text(c_state, b);
        snprintf(b, sizeof b, "%lu s", (unsigned long)(el / 1000)); lv_label_set_text(c_msg, b);
    }
}

static void connecting_show(void)
{
    plat_wifi_status_t s; plat_wifi_status(&s);
    c_t0 = plat_ms(); c_connects0 = s.connects; c_failures0 = s.failures; c_done = 0;
    lv_obj_t *scr = ui_screen_new(UI_SCR_SETTINGS, conn_update);
    ui_title(scr, "WI-FI");
    lv_obj_t *n = ui_label(scr, &bc_bold16, C_FG, w_ssid); lv_obj_set_width(n, 170); lv_label_set_long_mode(n, LV_LABEL_LONG_DOT);
    lv_obj_align(n, LV_ALIGN_TOP_MID, 0, 56);
    c_state = ui_label(scr, &bc_bold16, C_AMBER, "CONNECTING"); lv_obj_align(c_state, LV_ALIGN_TOP_MID, 0, 84);
    c_msg = ui_label(scr, &lv_font_montserrat_14, C_FG, ""); lv_obj_set_width(c_msg, 180); lv_label_set_long_mode(c_msg, LV_LABEL_LONG_WRAP);
    lv_obj_align(c_msg, LV_ALIGN_TOP_MID, 0, 108);
    c_btn = ui_pill(scr, "DONE", C_CYAN, C_INK, 100, 36, c_done_cb, NULL); lv_obj_align(c_btn, LV_ALIGN_TOP_MID, 0, 176); show(c_btn, false);
    c_btn2 = ui_pill(scr, "TRY AGAIN", C_PANEL, C_CYAN, 120, 30, c_retry_cb, NULL); lv_obj_align(c_btn2, LV_ALIGN_TOP_MID, 0, 142); show(c_btn2, false);
    ui_screen_show(scr);
}
