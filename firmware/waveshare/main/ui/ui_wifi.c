/*
 * Wi-Fi manager screens (Settings > Wi-Fi, Quick Settings > Wi-Fi). 0.6.0: a device's Wi-Fi settings — on/off, scan /
 * rescan, list with signal bars + open/saved tags, network detail (connect, new password, hold to forget, back), ring
 * keyboard fallback for passwords and hidden names (the phone app is the primary way to enter a password), connecting
 * screen with Cancel and plain states (CONNECTED + internet check, WRONG PASSWORD, NOT FOUND, timeout), saved networks.
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
static plat_wifi_ap_t w_sel;     /* network shown on the detail page */
static bool w_sel_known, d_from_saved;

static void wipe(void) { memset(w_pass, 0, sizeof w_pass); }

/* 0.6.0: SSIDs are UTF-8 (an iPhone is "Rashed’s iPhone" with U+2019). The label fonts only have ASCII, so for DISPLAY the
   typographic quotes/dashes become ' " - and any other non-ASCII character a '?'. Matching and joining always use the
   original bytes. max = characters shown; longer names get ".." */
static void ssid_display(const char *in, char *out, size_t cap, int max)
{
    size_t o = 0; int shown = 0; const unsigned char *p = (const unsigned char *)in;
    while (*p && o + 3 < cap) {
        char c; int len = 1; unsigned cp = *p;
        if (cp >= 0xF0) len = 4; else if (cp >= 0xE0) len = 3; else if (cp >= 0xC0) len = 2;
        if (len == 1) c = (char)cp;
        else {
            unsigned v = cp & (0x3F >> (len - 1)); for (int i = 1; i < len && p[i]; i++) v = (v << 6) | (p[i] & 0x3F);
            c = (v == 0x2018 || v == 0x2019) ? '\'' : (v == 0x201C || v == 0x201D) ? '"' : (v == 0x2013 || v == 0x2014) ? '-' : (v == 0xA0) ? ' ' : '?';
        }
        if (shown >= max) { out[o++] = '.'; out[o++] = '.'; break; }
        out[o++] = c; shown++;
        for (int i = 0; i < len && *p; i++) p++;
    }
    out[o] = 0;
}

/* signal bars (4) + "open" for unsecured + a check for saved networks, right-aligned in a row */
static int bars_of(int rssi) { return rssi >= -55 ? 4 : rssi >= -65 ? 3 : rssi >= -75 ? 2 : 1; }
static void row_signal(lv_obj_t *row, const plat_wifi_ap_t *a)
{
    int n = bars_of(a->rssi);
    for (int i = 0; i < 4; i++) {
        lv_obj_t *b = lv_obj_create(row); lv_obj_remove_style_all(b);
        lv_obj_set_size(b, 4, 5 + 4 * i); lv_obj_set_style_radius(b, 1, 0);
        lv_obj_set_style_bg_color(b, i < n ? (a->saved ? C_GREEN : C_FG) : C_FAINT, 0); lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0);
        lv_obj_align(b, LV_ALIGN_BOTTOM_RIGHT, -10 - (3 - i) * 6, -11);
        lv_obj_remove_flag(b, LV_OBJ_FLAG_CLICKABLE);
    }
    const char *tag = a->saved ? LV_SYMBOL_OK : !a->secured ? "open" : "";
    if (tag[0]) { lv_obj_t *t = ui_label(row, &lv_font_montserrat_12, a->saved ? C_GREEN : C_AMBER, tag); lv_obj_align(t, LV_ALIGN_RIGHT_MID, -38, 0); }
}
static const char *internet_text(const plat_wifi_status_t *s) { return s->internet == 1 ? "internet ok" : s->internet == 2 ? "no internet (DNS failed)" : "internet: checking"; }

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
    lv_obj_t *n = ui_label(m_list, &lv_font_montserrat_12, C_MUT, "Optional. Rides, coaching and history work without Wi-Fi. 2.4 GHz networks only (no 5 GHz). Easiest: set it up from the phone app.");
    lv_obj_set_width(n, lv_pct(100)); lv_label_set_long_mode(n, LV_LABEL_LONG_WRAP);
    m_last_state = s.state; m_last_on = on;
}

static void main_update(void)
{
    plat_wifi_status_t s; plat_wifi_status(&s);
    if ((int)s.state != m_last_state || m_last_on != app_profile()->wifi_on) build_rows();
    char b[160];
    char dn[40]; ssid_display(s.ssid, dn, sizeof dn, 20);
    if (s.state == PLAT_WIFI_CONNECTED) snprintf(b, sizeof b, "#56e08c CONNECTED#  %s\n%s\n%d dBm   %s", s.internet == 1 ? "#56e08c internet ok#" : s.internet == 2 ? "#ffb64d no internet#" : "", dn, s.rssi, s.ip[0] ? s.ip : "no IP yet");
    else if (s.state == PLAT_WIFI_FAILED || (s.state == PLAT_WIFI_IDLE && s.err != PLAT_WIFI_ERR_NONE))
        snprintf(b, sizeof b, "#ffb64d %s#\n%s\n%s", state_text(&s), dn, bc_wifi_err_text((bc_wifi_err_t)s.err));
    else if (s.state == PLAT_WIFI_CONNECTING) snprintf(b, sizeof b, "#ffb64d CONNECTING...#\n%s", dn);
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

static void detail_show(void);
static void pick_cb(lv_event_t *e)
{
    int i = (int)(intptr_t)lv_event_get_user_data(e);
    snprintf(w_ssid, sizeof w_ssid, "%s", n_aps[i].ssid);
    w_sel = n_aps[i]; w_sel_known = true; d_from_saved = false;
    if (!n_aps[i].saved && n_aps[i].secured) keyboard_show(false);   /* new secured network: straight to the password */
    else detail_show();                                             /* saved or open: connect / forget / back */
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
    n_n = plat_wifi_results(n_aps, 16);
    char b[40]; snprintf(b, sizeof b, "%d found  -  2.4 GHz only", n_n); lv_label_set_text(n_info, b);
    lv_obj_clean(n_list);
    bool ride = app_ride_state() == BC_RIDE_RUNNING || app_ride_state() == BC_RIDE_PAUSED;
    if (ride) { lv_obj_t *w = ui_label(n_list, &lv_font_montserrat_12, C_AMBER, "ride running: scanning shares the radio with the power meter"); lv_obj_set_width(w, lv_pct(100)); lv_label_set_long_mode(w, LV_LABEL_LONG_WRAP); }
    for (int i = 0; i < n_n; i++) {
        char left[28]; ssid_display(n_aps[i].ssid, left, sizeof left, 14);
        lv_obj_t *r = ui_row_btn(n_list, left, NULL, C_MUT, pick_cb, (void *)(intptr_t)i);
        row_signal(r, &n_aps[i]);
    }
    if (!n_n) {
        lv_obj_t *z = ui_label(n_list, &lv_font_montserrat_14, C_FG, "No 2.4 GHz network found."); lv_obj_set_width(z, lv_pct(100)); lv_label_set_long_mode(z, LV_LABEL_LONG_WRAP);
    }
    ui_row_btn(n_list, "Other network...", LV_SYMBOL_EDIT, C_CYAN, other_cb, NULL);
    lv_obj_t *t = ui_label(n_list, &lv_font_montserrat_12, C_MUT, "iPhone hotspot: Settings > Personal Hotspot > Maximize Compatibility ON (2.4 GHz), keep that screen open, then Rescan. 5 GHz-only networks cannot appear here.");
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
static void d_connect_cb(lv_event_t *e)
{
    (void)e;
    if (w_sel_known && w_sel.saved) { plat_wifi_connect(w_ssid, NULL, false); connecting_show(); }
    else if (w_sel_known && !w_sel.secured) { plat_wifi_connect(w_ssid, "", true); connecting_show(); }
    else if (!w_sel_known) { plat_wifi_connect(w_ssid, NULL, false); connecting_show(); }      /* saved list entry */
    else keyboard_show(false);
}
static void d_forget_cb(lv_event_t *e) { (void)e; plat_wifi_forget(w_ssid); if (d_from_saved) saved_show(); else networks_show(); }
static void d_back_cb(lv_event_t *e) { (void)e; if (d_from_saved) saved_show(); else networks_show(); }
static void d_pass_cb(lv_event_t *e) { (void)e; keyboard_show(false); }

/* one network: name, secured/open, signal, saved; CONNECT, change password, HOLD: FORGET, BACK */
static void detail_show(void)
{
    plat_wifi_status_t s; plat_wifi_status(&s);
    bool saved = w_sel_known ? w_sel.saved : true;
    bool connected = s.state == PLAT_WIFI_CONNECTED && !strcmp(s.ssid, w_ssid);
    lv_obj_t *scr = ui_screen_new(UI_SCR_SETTINGS, NULL);
    ui_title(scr, "NETWORK");
    char dn[48]; ssid_display(w_ssid, dn, sizeof dn, 22);
    lv_obj_t *n = ui_label(scr, &bc_bold16, C_FG, dn); lv_obj_set_width(n, 176); lv_label_set_long_mode(n, LV_LABEL_LONG_WRAP); lv_obj_set_style_text_align(n, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(n, LV_ALIGN_TOP_MID, 0, 48);
    char info[96];
    if (w_sel_known) snprintf(info, sizeof info, "%s  -  signal %d dBm (%d/4)%s", w_sel.secured ? "secured" : "open network", w_sel.rssi, bars_of(w_sel.rssi), saved ? "  -  saved" : "");
    else snprintf(info, sizeof info, "saved network%s", connected ? "  -  connected now" : "");
    lv_obj_t *i = ui_label(scr, &lv_font_montserrat_12, connected ? C_GREEN : C_MUT, info); lv_obj_set_width(i, 180); lv_label_set_long_mode(i, LV_LABEL_LONG_WRAP); lv_obj_set_style_text_align(i, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(i, LV_ALIGN_TOP_MID, 0, 86);
    lv_obj_t *c = ui_pill(scr, connected ? "RECONNECT" : "CONNECT", C_CYAN, C_INK, 140, 34, d_connect_cb, NULL); lv_obj_align(c, LV_ALIGN_TOP_MID, 0, 118);
    if (saved && (!w_sel_known || w_sel.secured)) { lv_obj_t *pw = ui_pill(scr, "NEW PASSWORD", C_PANEL, C_CYAN, 140, 26, d_pass_cb, NULL); lv_obj_set_style_text_font(lv_obj_get_child(pw, 0), &lv_font_montserrat_12, 0); lv_obj_align(pw, LV_ALIGN_TOP_MID, 0, 156); }
    if (saved) { lv_obj_t *f = ui_hold_btn(scr, "HOLD: FORGET", C_PANEL, C_RED, 120, 26, 1500, d_forget_cb, NULL); lv_obj_set_style_text_font(lv_obj_get_child(f, 0), &lv_font_montserrat_12, 0); lv_obj_align(f, LV_ALIGN_TOP_MID, 0, 186); }
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 30, d_back_cb, NULL); lv_obj_set_pos(bk, 14, 120);
    lv_obj_set_style_text_font(lv_obj_get_child(bk, 0), &lv_font_montserrat_14, 0);
    ui_screen_show(scr);
}

static void saved_pick(lv_event_t *e)
{
    int i = (int)(intptr_t)lv_event_get_user_data(e);
    snprintf(w_ssid, sizeof w_ssid, "%s", s_saved[i]);
    w_sel_known = false; d_from_saved = true;
    detail_show();
}

static void saved_show(void)
{
    lv_obj_t *scr = ui_screen_new(UI_SCR_SETTINGS, NULL);
    ui_title(scr, "SAVED");
    lv_obj_t *l = ui_scroll_area(scr, 54, 176);
    int n = plat_wifi_saved(s_saved, PLAT_WIFI_MAX_SAVED);
    for (int i = 0; i < n; i++) {
        char left[28]; ssid_display(s_saved[i], left, sizeof left, 14);
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
    char kt[40]; ssid_display(w_ssid, kt, sizeof kt, 16);
    k_title = ui_label(scr, &lv_font_montserrat_12, C_CYAN, for_ssid ? "NAME" : kt);
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
    ui_qs_handle_allow(false);           /* the ring's top key sits where the handle would be */
}

/* ---------------- connecting / result */
static lv_obj_t *c_state, *c_msg, *c_btn, *c_btn2; static uint32_t c_t0, c_connects0, c_failures0; static int c_done;

static void c_done_cb(lv_event_t *e) { (void)e; wifi_main(); }
static void c_retry_cb(lv_event_t *e) { (void)e; keyboard_show(false); }
static void c_cancel_cb(lv_event_t *e) { (void)e; plat_wifi_disconnect(); networks_show(); }
static lv_obj_t *c_cancel;

static void conn_update(void)
{
    plat_wifi_status_t s; plat_wifi_status(&s);
    if (c_done) return;
    uint32_t el = plat_ms() - c_t0;
    if (s.connects > c_connects0 && s.state == PLAT_WIFI_CONNECTED) {
        if (c_done != 1) { c_done = 1; lv_label_set_text(c_state, "CONNECTED"); lv_obj_set_style_text_color(c_state, C_GREEN, 0); lv_label_set_text(lv_obj_get_child(c_btn, 0), "DONE"); show(c_btn, true); show(c_cancel, false); }
        char b[96]; snprintf(b, sizeof b, "%d dBm (%d/4)\nIP %s\n%s", s.rssi, bars_of(s.rssi), s.ip, internet_text(&s)); lv_label_set_text(c_msg, b);
        return;
    } else if (s.failures > c_failures0 || el > 35000) {
        c_done = 2;
        bool timeout = el > 35000 && s.failures == c_failures0;
        plat_wifi_err_t err = timeout ? PLAT_WIFI_ERR_TIMEOUT : s.err;
        lv_label_set_text(c_state, err == PLAT_WIFI_ERR_WRONG_PASSWORD ? "WRONG PASSWORD" : err == PLAT_WIFI_ERR_NOT_FOUND ? "NOT FOUND" : "NOT CONNECTED");
        lv_obj_set_style_text_color(c_state, C_AMBER, 0);
        char b[160];
        if (err == PLAT_WIFI_ERR_NOT_FOUND) snprintf(b, sizeof b, "%s\n2.4 GHz only. iPhone hotspot: Maximize Compatibility on, hotspot screen open.", bc_wifi_err_text((bc_wifi_err_t)err));
        else snprintf(b, sizeof b, "%s", bc_wifi_err_text((bc_wifi_err_t)err));
        lv_label_set_text(c_msg, b);
        lv_label_set_text(lv_obj_get_child(c_btn, 0), "BACK"); show(c_btn, true); show(c_cancel, false);
        show(c_btn2, err == PLAT_WIFI_ERR_WRONG_PASSWORD || err == PLAT_WIFI_ERR_OTHER || err == PLAT_WIFI_ERR_TIMEOUT);
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
    char dn[40]; ssid_display(w_ssid, dn, sizeof dn, 18);
    lv_obj_t *n = ui_label(scr, &bc_bold16, C_FG, dn); lv_obj_set_width(n, 170); lv_label_set_long_mode(n, LV_LABEL_LONG_DOT); lv_obj_set_style_text_align(n, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(n, LV_ALIGN_TOP_MID, 0, 56);
    c_state = ui_label(scr, &bc_bold16, C_AMBER, "CONNECTING"); lv_obj_align(c_state, LV_ALIGN_TOP_MID, 0, 84);
    c_msg = ui_label(scr, &lv_font_montserrat_14, C_FG, ""); lv_obj_set_width(c_msg, 180); lv_label_set_long_mode(c_msg, LV_LABEL_LONG_WRAP);
    lv_obj_align(c_msg, LV_ALIGN_TOP_MID, 0, 108);
    c_btn = ui_pill(scr, "DONE", C_CYAN, C_INK, 100, 36, c_done_cb, NULL); lv_obj_align(c_btn, LV_ALIGN_TOP_MID, 0, 176); show(c_btn, false);
    c_btn2 = ui_pill(scr, "TRY AGAIN", C_PANEL, C_CYAN, 120, 30, c_retry_cb, NULL); lv_obj_align(c_btn2, LV_ALIGN_TOP_MID, 0, 142); show(c_btn2, false);
    c_cancel = ui_pill(scr, "CANCEL", C_PANEL, C_MUT, 100, 32, c_cancel_cb, NULL); lv_obj_align(c_cancel, LV_ALIGN_TOP_MID, 0, 178);
    lv_obj_set_style_text_font(lv_obj_get_child(c_cancel, 0), &lv_font_montserrat_14, 0);
    ui_screen_show(scr);
}
