/*
 * Power UI (firmware 0.5.0, reworked 0.6.0): Quick Settings (a visible pull-down HANDLE at the top of every non-ride
 * screen — tap it or swipe down from it / the top 48 px; on ride screens the ride's own handle opens the ride controls,
 * which carry the Quick Settings button, so ride controls always come first), the screen-off / touch-lock shield,
 * low-battery toasts, the Power settings page and the "Deep sleep (connectivity off)" explanation.
 * Everything lives on lv_layer_top() so it works over any screen without touching the screens themselves.
 */
#include "ui.h"
#include "app_power.h"
#include <stdio.h>
#include <string.h>

#define QS_TIMEOUT_MS 20000
#define TOAST_MS 4000
#define TOP_EDGE_Y 48
#define QS_ANIM_MS 150
#define HANDLE_W 60
#define HANDLE_H 28

static lv_obj_t *s_shield, *s_lock_btn, *s_lock_hint, *s_toast, *s_toast_lbl, *s_qs, *s_handle;
static bool s_qs_closing, s_handle_blocked;   /* blocked: the current screen owns the top of the glass (ring keyboards) */
static uint32_t s_qs_opened_ms, s_toast_until_ms;
static lv_point_t s_press;
static bool s_inited;
static int s_qs_page;      /* 0 list, 1 power options */
static bool s_qs_dirty;    /* rebuild requested from inside an event (never delete widgets while their event runs) */

/* ---------------- touch bookkeeping: press start point (for the top-edge swipe) and last-touch time */
static void indev_cb(lv_event_t *e)
{
    lv_event_code_t c = lv_event_get_code(e);
    lv_indev_t *i = lv_indev_active();
    if (c == LV_EVENT_PRESSED) { if (i) lv_indev_get_point(i, &s_press); app_power_touch(true, plat_ms()); if (s_qs) s_qs_opened_ms = plat_ms(); /* any touch keeps Quick Settings open */ }
    else if (c == LV_EVENT_RELEASED || c == LV_EVENT_PRESS_LOST) app_power_touch(false, plat_ms());
}

/* ---------------- shield: swallows touches while the screen is off or locked */
static void shield_cb(lv_event_t *e)
{
    (void)e;   /* presses are already counted by the indev callback; the shield only has to exist to catch them */
}
static void unlock_cb(lv_event_t *e) { (void)e; app_power_unlock(); }

static void shield_refresh(void)
{
    const app_power_t *P = app_power();
    bool off = !P->screen_on, locked = P->locked;
    if (!off && !locked) { lv_obj_add_flag(s_shield, LV_OBJ_FLAG_HIDDEN); return; }
    lv_obj_remove_flag(s_shield, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_foreground(s_shield);
    lv_obj_set_style_bg_opa(s_shield, off ? LV_OPA_COVER : LV_OPA_80, 0);   /* locked: dimmed, the lock button readable */
    if (locked && !off) { lv_obj_remove_flag(s_lock_btn, LV_OBJ_FLAG_HIDDEN); lv_obj_remove_flag(s_lock_hint, LV_OBJ_FLAG_HIDDEN); }
    else { lv_obj_add_flag(s_lock_btn, LV_OBJ_FLAG_HIDDEN); lv_obj_add_flag(s_lock_hint, LV_OBJ_FLAG_HIDDEN); }
}

/* ---------------- toast */
static void toast(const char *txt)
{
    lv_label_set_text(s_toast_lbl, txt);
    lv_obj_remove_flag(s_toast, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_foreground(s_toast);
    s_toast_until_ms = plat_ms() + TOAST_MS;
}

/* ---------------- Quick Settings */
static lv_obj_t *q_list, *q_bright_val, *q_batt_row, *q_batt_detail, *q_wifi, *q_phone, *q_sleep;
static void qs_build(void);
static void handle_refresh(void);

void ui_qs_close(void) { if (s_qs) { lv_anim_delete(s_qs, NULL); lv_obj_delete(s_qs); s_qs = NULL; q_list = NULL; } s_qs_closing = false; handle_refresh(); }

static void qs_close_anim(void);
static void qs_close_cb(lv_event_t *e) { (void)e; qs_close_anim(); }
static void qs_anim_y(void *o, int32_t v) { lv_obj_set_y((lv_obj_t *)o, v); }
static void qs_closed_cb(lv_anim_t *a) { (void)a; if (s_qs) { lv_obj_delete(s_qs); s_qs = NULL; q_list = NULL; } s_qs_closing = false; }
/* animated close (swipe up / X / timeout); ui_qs_close() stays immediate for code paths that need the panel gone now */
static void qs_close_anim(void)
{
    if (!s_qs || s_qs_closing) return;
    s_qs_closing = true;
    lv_anim_t a; lv_anim_init(&a); lv_anim_set_var(&a, s_qs); lv_anim_set_exec_cb(&a, qs_anim_y);
    lv_anim_set_values(&a, lv_obj_get_y(s_qs), -UI_W); lv_anim_set_duration(&a, QS_ANIM_MS); lv_anim_set_path_cb(&a, lv_anim_path_ease_in);
    lv_anim_set_completed_cb(&a, qs_closed_cb); lv_anim_start(&a);
}
static void qs_gesture(lv_event_t *e)
{
    (void)e;
    if (lv_indev_get_gesture_dir(lv_indev_active()) == LV_DIR_TOP) qs_close_anim();
}
/* the handle: tap = open; a swipe that starts on it = open (the gesture is consumed here, it never reaches the screen) */
static void handle_click_cb(lv_event_t *e) { (void)e; ui_qs_open(); }
static void handle_gesture_cb(lv_event_t *e) { (void)e; if (lv_indev_get_gesture_dir(lv_indev_active()) == LV_DIR_BOTTOM) ui_qs_open(); }
static void handle_refresh(void)
{
    if (!s_handle) return;
    const app_power_t *P = app_power();
    bool show = P->screen_on && !P->locked && !s_qs && !s_handle_blocked && ui_current() != UI_SCR_RIDE && ui_current() != UI_SCR_ONBOARD && !app_phone_passkey();
    if (show) { lv_obj_remove_flag(s_handle, LV_OBJ_FLAG_HIDDEN); lv_obj_move_foreground(s_handle); } else lv_obj_add_flag(s_handle, LV_OBJ_FLAG_HIDDEN);
}
void ui_qs_handle_allow(bool allow) { s_handle_blocked = !allow; handle_refresh(); }
bool ui_qs_handle_visible(void) { return s_handle && !lv_obj_has_flag(s_handle, LV_OBJ_FLAG_HIDDEN); }
void ui_qs_handle_rect(lv_area_t *a) { a->x1 = UI_R - HANDLE_W / 2; a->x2 = UI_R + HANDLE_W / 2 - 1; a->y1 = 0; a->y2 = HANDLE_H - 1; }
static void bright_cb(lv_event_t *e)
{
    lv_obj_t *sl = lv_event_get_target(e);
    int v = (int)lv_slider_get_value(sl);
    app_profile()->brightness = (uint8_t)v;
    plat_backlight(v);
    char b[12]; snprintf(b, sizeof b, "%d%%", v); lv_label_set_text(q_bright_val, b);
    if (lv_event_get_code(e) == LV_EVENT_RELEASED) app_profile_save();
    s_qs_opened_ms = plat_ms();
}
static bool s_wifi_long;   /* a long press toggled the radio: swallow the CLICKED that LVGL sends on release */
static void wifi_cb(lv_event_t *e)
{
    if (lv_event_get_code(e) == LV_EVENT_LONG_PRESSED) {
        bc_profile_t *p = app_profile(); p->wifi_on = !p->wifi_on; app_profile_save(); plat_wifi_set_enabled(p->wifi_on); s_wifi_long = true;
        /* update the row in place: rebuilding while the finger is still down would lose the release */
        lv_obj_t *r = q_wifi ? lv_obj_get_child(q_wifi, 1) : NULL;
        if (r) { lv_label_set_text(r, p->wifi_on ? "on " LV_SYMBOL_RIGHT : "off " LV_SYMBOL_RIGHT); lv_obj_set_style_text_color(r, p->wifi_on ? C_GREEN : C_MUT, 0); }
        return;
    }
    if (s_wifi_long) { s_wifi_long = false; return; }
    ui_qs_close(); ui_wifi_show();                       /* tap: the full Wi-Fi page (networks, password, forget) */
}
static void phone_cb(lv_event_t *e) { (void)e; bc_profile_t *p = app_profile(); p->phone_on = !p->phone_on; app_profile_save(); plat_phone_set_enabled(p->phone_on); s_qs_dirty = true; }
static void sensors_cb(lv_event_t *e) { (void)e; ui_qs_close(); ui_sensors_show(); }
static void lock_cb(lv_event_t *e) { (void)e; ui_qs_close(); app_power_lock(); }
static void off_cb(lv_event_t *e) { (void)e; ui_qs_close(); app_power_screen_off(); }
static void sleep_page_cb(lv_event_t *e) { (void)e; s_qs_page = 1; s_qs_dirty = true; }
static void sleep_go_cb(lv_event_t *e) { (void)e; if (app_power_can_sleep()) { ui_qs_close(); app_power_sleep(); } else toast("Sleep needs the ride ended first"); }
static void restart_cb(lv_event_t *e) { (void)e; ui_qs_close(); app_power_restart(); }
static void back_list_cb(lv_event_t *e) { (void)e; s_qs_page = 0; s_qs_dirty = true; }
static void power_settings_cb(lv_event_t *e) { (void)e; ui_qs_close(); ui_power_settings_show(); }

static lv_obj_t *row_static(lv_obj_t *list, const char *left, const char *right, lv_color_t rc)
{
    lv_obj_t *b = ui_row_btn(list, left, right, rc, NULL, NULL);
    lv_obj_remove_flag(b, LV_OBJ_FLAG_CLICKABLE);
    return b;
}

static void qs_fill_list(void)
{
    bc_profile_t *p = app_profile();
    const app_power_t *P = app_power();
    bool ride = app_ride_state() == BC_RIDE_RUNNING || app_ride_state() == BC_RIDE_PAUSED;
    /* brightness row: label + slider */
    lv_obj_t *br = lv_obj_create(q_list); lv_obj_remove_style_all(br);
    lv_obj_set_size(br, lv_pct(100), 40); lv_obj_set_style_bg_color(br, C_PANEL, 0); lv_obj_set_style_bg_opa(br, LV_OPA_COVER, 0); lv_obj_set_style_radius(br, 12, 0);
    lv_obj_remove_flag(br, LV_OBJ_FLAG_SCROLLABLE); lv_obj_remove_flag(br, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_t *bl = ui_label(br, &lv_font_montserrat_12, C_MUT, LV_SYMBOL_EYE_OPEN); lv_obj_align(bl, LV_ALIGN_LEFT_MID, 8, 0);
    lv_obj_t *sl = lv_slider_create(br);
    lv_obj_remove_style_all(sl);
    lv_obj_set_size(sl, 92, 28); lv_obj_align(sl, LV_ALIGN_LEFT_MID, 30, 0);
    lv_obj_set_style_bg_color(sl, C_TRACK, LV_PART_MAIN); lv_obj_set_style_bg_opa(sl, LV_OPA_COVER, LV_PART_MAIN); lv_obj_set_style_radius(sl, 14, LV_PART_MAIN);
    lv_obj_set_style_bg_color(sl, C_CYAN, LV_PART_INDICATOR); lv_obj_set_style_bg_opa(sl, LV_OPA_COVER, LV_PART_INDICATOR); lv_obj_set_style_radius(sl, 14, LV_PART_INDICATOR);
    lv_obj_set_style_bg_opa(sl, LV_OPA_TRANSP, LV_PART_KNOB);
    lv_slider_set_range(sl, 10, 100); lv_slider_set_value(sl, p->brightness, LV_ANIM_OFF);
    lv_obj_remove_flag(sl, LV_OBJ_FLAG_GESTURE_BUBBLE);
    lv_obj_add_event_cb(sl, bright_cb, LV_EVENT_VALUE_CHANGED, NULL);
    lv_obj_add_event_cb(sl, bright_cb, LV_EVENT_RELEASED, NULL);
    char v[24]; snprintf(v, sizeof v, "%u%%", p->brightness);
    q_bright_val = ui_label(br, &lv_font_montserrat_14, C_FG, v); lv_obj_align(q_bright_val, LV_ALIGN_RIGHT_MID, -10, 0);

    plat_wifi_status_t ws; plat_wifi_status(&ws);
    q_wifi = ui_row_btn(q_list, "Wi-Fi", !p->wifi_on ? "off " LV_SYMBOL_RIGHT : ws.state == PLAT_WIFI_CONNECTED ? "connected " LV_SYMBOL_RIGHT : "on " LV_SYMBOL_RIGHT, p->wifi_on ? C_GREEN : C_MUT, wifi_cb, NULL);
    lv_obj_add_event_cb(q_wifi, wifi_cb, LV_EVENT_LONG_PRESSED, NULL);   /* tap = Wi-Fi page, hold = on/off (the page has the switch too) */
    plat_phone_status_t ps; plat_phone_status(&ps);
    q_phone = ui_row_btn(q_list, "Phone link", !p->phone_on ? "off" : ps.state == PLAT_PHONE_READY ? "connected" : "on", p->phone_on ? C_GREEN : C_MUT, phone_cb, NULL);
    lv_obj_t *n1 = ui_label(q_list, &lv_font_montserrat_12, C_MUT, "stays on with the screen off"); lv_obj_set_width(n1, lv_pct(100)); lv_label_set_long_mode(n1, LV_LABEL_LONG_WRAP);
    ui_row_btn(q_list, "Sensors", LV_SYMBOL_RIGHT, C_CYAN, sensors_cb, NULL);
    char bs[16]; app_power_batt_short(bs, sizeof bs);
    q_batt_row = row_static(q_list, "Battery", bs, P->bat_level >= BC_BAT_VERY_LOW ? C_RED : P->bat_level == BC_BAT_LOW ? C_AMBER : C_FG);
    char bd[96]; app_power_batt_detail(bd, sizeof bd);
    q_batt_detail = ui_label(q_list, &lv_font_montserrat_12, C_MUT, bd); lv_obj_set_width(q_batt_detail, lv_pct(100)); lv_label_set_long_mode(q_batt_detail, LV_LABEL_LONG_WRAP);
    row_static(q_list, "State", app_power_state_text(), C_MUT);
    ui_row_btn(q_list, "Touch lock", LV_SYMBOL_EYE_CLOSE, C_CYAN, lock_cb, NULL);
    char wk[20]; snprintf(wk, sizeof wk, "%s = on", app_power_wake_name(app_power_wake_taps_now()));
    ui_row_btn(q_list, "Screen off", wk, C_CYAN, off_cb, NULL);
    lv_obj_t *n4 = ui_label(q_list, &lv_font_montserrat_12, C_MUT, "Bluetooth, sensors and recording\ncontinue with the screen off"); lv_obj_set_width(n4, lv_pct(100)); lv_label_set_long_mode(n4, LV_LABEL_LONG_WRAP);
    q_sleep = ui_row_btn(q_list, "Deep sleep", ride ? "riding" : "link off " LV_SYMBOL_RIGHT, ride ? C_FAINT : C_CYAN, sleep_page_cb, NULL);
    if (ride) { lv_obj_remove_flag(q_sleep, LV_OBJ_FLAG_CLICKABLE); lv_obj_set_style_text_color(lv_obj_get_child(q_sleep, 0), C_FAINT, 0); }
    lv_obj_t *rs = ui_hold_btn(q_list, "HOLD: RESTART", C_PANEL, C_AMBER, lv_pct(100), 40, 1500, restart_cb, NULL);
    lv_obj_set_style_text_font(lv_obj_get_child(rs, 0), &lv_font_montserrat_12, 0);
    if (ride) { lv_obj_t *n2 = ui_label(q_list, &lv_font_montserrat_12, C_MUT, "the ride is saved to the journal\nand recovered after a restart"); lv_obj_set_width(n2, lv_pct(100)); lv_label_set_long_mode(n2, LV_LABEL_LONG_WRAP); }
    ui_row_btn(q_list, "Power settings", LV_SYMBOL_RIGHT, C_CYAN, power_settings_cb, NULL);
}

static void qs_fill_power_page(void)
{
    char tx[360]; int taps = app_profile()->wake_taps < 2 ? 2 : app_profile()->wake_taps;
    snprintf(tx, sizeof tx, "This board has no power switch:\nthe lowest state is DEEP SLEEP.\n\nCONNECTIVITY OFF: the phone\nlink and sensors disconnect\nuntil the device wakes.\n(Screen off / standby keep\nBluetooth on instead.)\n\nWake it up: tap the screen\n%d times, press RESET, or\nplug in USB.\n\nSettings and rides are saved\nfirst. Not possible during a ride.", taps);
    lv_obj_t *t = ui_label(q_list, &lv_font_montserrat_12, C_FG, tx);
    lv_obj_set_width(t, lv_pct(100)); lv_label_set_long_mode(t, LV_LABEL_LONG_WRAP);
    if (app_power_can_sleep()) ui_hold_btn(q_list, "HOLD: DEEP SLEEP", C_PANEL, C_CYAN, lv_pct(100), 40, 1500, sleep_go_cb, NULL);
    else { lv_obj_t *n = ui_label(q_list, &lv_font_montserrat_12, C_AMBER, "end the ride first"); lv_obj_set_width(n, lv_pct(100)); }
    lv_obj_t *n3 = ui_label(q_list, &lv_font_montserrat_12, C_MUT, "touch wake: not yet verified\non this hardware - RESET always works");
    lv_obj_set_width(n3, lv_pct(100)); lv_label_set_long_mode(n3, LV_LABEL_LONG_WRAP);
    ui_pill(q_list, "BACK", C_PANEL, C_FG, 100, 34, back_list_cb, NULL);
}

static void qs_build(void)
{
    if (!s_qs) {
        s_qs = lv_obj_create(lv_layer_top());
        lv_obj_remove_style_all(s_qs);
        lv_obj_set_size(s_qs, UI_W, UI_W);
        lv_obj_set_style_bg_color(s_qs, C_BG, 0); lv_obj_set_style_bg_opa(s_qs, LV_OPA_COVER, 0);
        lv_obj_set_style_text_color(s_qs, C_FG, 0); lv_obj_set_style_text_font(s_qs, &lv_font_montserrat_14, 0);
        lv_obj_add_flag(s_qs, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_remove_flag(s_qs, LV_OBJ_FLAG_SCROLLABLE);
        lv_obj_add_event_cb(s_qs, qs_gesture, LV_EVENT_GESTURE, NULL);
    }
    lv_obj_clean(s_qs);
    { lv_obj_t *t = ui_label(s_qs, &lv_font_montserrat_14, C_CYAN, s_qs_page ? "DEEP SLEEP" : "QUICK SETTINGS"); lv_obj_align(t, LV_ALIGN_TOP_MID, 0, 31); }
    q_list = ui_scroll_area(s_qs, 50, 176);
    if (s_qs_page) qs_fill_power_page(); else qs_fill_list();
    lv_obj_t *x = ui_round_btn(s_qs, LV_SYMBOL_UP, C_PANEL, C_FG, 40, qs_close_cb, NULL);   /* "X": swipe-up symbol, closes */
    lv_obj_align(x, LV_ALIGN_TOP_MID, 0, 182);
    lv_obj_move_foreground(s_qs);
    if (s_shield && !lv_obj_has_flag(s_shield, LV_OBJ_FLAG_HIDDEN)) lv_obj_move_foreground(s_shield);
    s_qs_opened_ms = plat_ms();
    handle_refresh();
}

void ui_qs_open(void)
{
    if (app_power()->locked || !app_power()->screen_on || s_qs) return;
    s_qs_page = 0;
    qs_build();
    /* slide down from the top edge (~150 ms) so opening reads as a pull-down, not a flash */
    lv_obj_set_y(s_qs, -UI_W);
    lv_anim_t a; lv_anim_init(&a); lv_anim_set_var(&a, s_qs); lv_anim_set_exec_cb(&a, qs_anim_y);
    lv_anim_set_values(&a, -UI_W, 0); lv_anim_set_duration(&a, QS_ANIM_MS); lv_anim_set_path_cb(&a, lv_anim_path_ease_out); lv_anim_start(&a);
}
bool ui_qs_is_open(void) { return s_qs != NULL; }

static void qs_live(void)
{
    if (!s_qs || s_qs_page) return;
    const app_power_t *P = app_power();
    char bs[16]; app_power_batt_short(bs, sizeof bs);
    if (q_batt_row) { lv_obj_t *r = lv_obj_get_child(q_batt_row, 1); if (r) lv_label_set_text(r, bs); }
    char bd[96]; app_power_batt_detail(bd, sizeof bd);
    if (q_batt_detail) lv_label_set_text(q_batt_detail, bd);
    (void)P;
}

/* screens call this from their gesture handler; Quick Settings opens only for a swipe that began at the top edge */
void ui_power_gesture(lv_dir_t d)
{
    if (d == LV_DIR_BOTTOM && s_press.y < TOP_EDGE_Y && !s_qs && ui_current() != UI_SCR_RIDE) ui_qs_open();
}
static void scr_gesture_cb(lv_event_t *e) { (void)e; ui_power_gesture(lv_indev_get_gesture_dir(lv_indev_active())); }
void ui_power_attach_screen(lv_obj_t *scr, ui_scr_t kind) { if (kind != UI_SCR_RIDE) lv_obj_add_event_cb(scr, scr_gesture_cb, LV_EVENT_GESTURE, NULL); }

/* ---------------- init + periodic refresh (from ui_common's 250 ms timer) */
void ui_power_init(void)
{
    if (s_inited) { app_power_init(); ui_qs_close(); shield_refresh(); return; }
    s_inited = true;
    app_power_init();
    lv_indev_t *i = lv_indev_get_next(NULL);
    if (i) { lv_indev_add_event_cb(i, indev_cb, LV_EVENT_PRESSED, NULL); lv_indev_add_event_cb(i, indev_cb, LV_EVENT_RELEASED, NULL); lv_indev_add_event_cb(i, indev_cb, LV_EVENT_PRESS_LOST, NULL); }
    s_shield = lv_obj_create(lv_layer_top());
    lv_obj_remove_style_all(s_shield);
    lv_obj_set_size(s_shield, UI_W, UI_W);
    lv_obj_set_style_bg_color(s_shield, C_BG, 0);
    lv_obj_add_flag(s_shield, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_remove_flag(s_shield, LV_OBJ_FLAG_SCROLLABLE | LV_OBJ_FLAG_GESTURE_BUBBLE);
    lv_obj_add_event_cb(s_shield, shield_cb, LV_EVENT_CLICKED, NULL);
    s_lock_btn = ui_hold_btn(s_shield, "HOLD 3 s TO UNLOCK", C_PANEL, C_FG, 180, 44, 3000, unlock_cb, NULL);
    lv_obj_set_style_text_font(lv_obj_get_child(s_lock_btn, 0), &lv_font_montserrat_14, 0);
    lv_obj_align(s_lock_btn, LV_ALIGN_CENTER, 0, 0);
    s_lock_hint = ui_label(s_shield, &lv_font_montserrat_14, C_MUT, LV_SYMBOL_EYE_CLOSE "  touch locked");
    lv_obj_align(s_lock_hint, LV_ALIGN_CENTER, 0, -40);
    lv_obj_add_flag(s_shield, LV_OBJ_FLAG_HIDDEN);
    s_toast = lv_obj_create(lv_layer_top());
    lv_obj_remove_style_all(s_toast);
    lv_obj_set_size(s_toast, 134, 22); lv_obj_set_style_radius(s_toast, 11, 0);
    lv_obj_set_style_bg_color(s_toast, C_AMBER, 0); lv_obj_set_style_bg_opa(s_toast, LV_OPA_COVER, 0);
    lv_obj_align(s_toast, LV_ALIGN_TOP_MID, 0, 28);
    lv_obj_remove_flag(s_toast, LV_OBJ_FLAG_CLICKABLE);
    s_toast_lbl = ui_label(s_toast, &lv_font_montserrat_12, C_INK, ""); lv_obj_center(s_toast_lbl);
    lv_obj_set_size(s_toast_lbl, 124, 14); lv_label_set_long_mode(s_toast_lbl, LV_LABEL_LONG_DOT); lv_obj_center(s_toast_lbl);
    lv_obj_add_flag(s_toast, LV_OBJ_FLAG_HIDDEN);
    /* the pull-down handle: a 60 x 28 touch target holding a 44 x 6 pill, above every non-ride screen (titles start at y = 30) */
    s_handle = lv_button_create(lv_layer_top());
    lv_obj_remove_style_all(s_handle);
    lv_obj_set_size(s_handle, HANDLE_W, HANDLE_H);
    lv_obj_align(s_handle, LV_ALIGN_TOP_MID, 0, 0);
    lv_obj_remove_flag(s_handle, LV_OBJ_FLAG_GESTURE_BUBBLE | LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(s_handle, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_t *pill = lv_obj_create(s_handle); lv_obj_remove_style_all(pill);
    lv_obj_set_size(pill, 44, 6); lv_obj_set_style_radius(pill, 3, 0); lv_obj_set_style_bg_color(pill, C_MUT, 0); lv_obj_set_style_bg_opa(pill, LV_OPA_COVER, 0);
    lv_obj_align(pill, LV_ALIGN_TOP_MID, 0, 8); lv_obj_remove_flag(pill, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_style_bg_color(s_handle, C_FAINT, LV_STATE_PRESSED); lv_obj_set_style_bg_opa(s_handle, LV_OPA_50, LV_STATE_PRESSED); lv_obj_set_style_radius(s_handle, 8, 0);
    lv_obj_add_event_cb(s_handle, handle_click_cb, LV_EVENT_CLICKED, NULL);
    lv_obj_add_event_cb(s_handle, handle_gesture_cb, LV_EVENT_GESTURE, NULL);
    handle_refresh();
}

void ui_power_refresh(void)
{
    if (!s_inited) return;
    uint32_t now = plat_ms();
    app_power_tick(now);
    if (app_power()->asleep) { shield_refresh(); return; }
    /* a pairing code must be seen: wake the screen for it */
    if (app_phone_passkey() && !app_power()->screen_on) app_power_screen_wake();
    shield_refresh();
    char a[64];
    if (app_power_take_alert(a, sizeof a)) toast(a);
    if (s_toast_until_ms && (int32_t)(now - s_toast_until_ms) >= 0) { s_toast_until_ms = 0; lv_obj_add_flag(s_toast, LV_OBJ_FLAG_HIDDEN); }
    if (s_qs) {
        if (!app_power()->screen_on) ui_qs_close();
        else if ((int32_t)(now - (s_qs_opened_ms + QS_TIMEOUT_MS)) >= 0) qs_close_anim();
        else if (s_qs_dirty && !s_qs_closing) { s_qs_dirty = false; qs_build(); }
        else qs_live();
    }
    handle_refresh();
}

/* the screen itself went off/on: nothing to redraw here, the shield covers everything */
bool ui_power_screen_on(void) { return app_power()->screen_on; }

/* ---------------- Settings > Power */
static void back_settings(lv_event_t *e) { (void)e; ui_settings_show(); }
static void to_cb(lv_event_t *e) { (void)e; bc_profile_t *p = app_profile(); p->scr_timeout_s = (uint16_t)app_power_timeout_next(p->scr_timeout_s); app_profile_save(); ui_power_settings_show(); }
static void as_cb(lv_event_t *e) { (void)e; bc_profile_t *p = app_profile(); p->auto_sleep_min = (uint8_t)app_power_autosleep_next(p->auto_sleep_min); app_profile_save(); ui_power_settings_show(); }
static void cue_cb(lv_event_t *e) { (void)e; bc_profile_t *p = app_profile(); p->wake_on_cue = !p->wake_on_cue; app_profile_save(); ui_power_settings_show(); }
static void prot_cb(lv_event_t *e) { (void)e; bc_profile_t *p = app_profile(); p->bat_protect = p->bat_protect ? 0 : 1; app_profile_save(); ui_power_settings_show(); }
static void wake_cb(lv_event_t *e) { (void)e; bc_profile_t *p = app_profile(); p->wake_taps = (uint8_t)app_power_wake_next(p->wake_taps); app_profile_save(); ui_power_settings_show(); }
static void qs_from_settings(lv_event_t *e) { (void)e; ui_qs_open(); }
static void sleep_from_settings(lv_event_t *e) { (void)e; s_qs_page = 1; qs_build(); }   /* the Settings row is not inside s_qs: safe to build here */
static int s_ps_scroll; static lv_obj_t *s_ps_list;
static void ps_remember(lv_event_t *e) { (void)e; s_ps_scroll = lv_obj_get_scroll_y(s_ps_list); }

void ui_power_settings_show(void)
{
    bc_profile_t *p = app_profile();
    lv_obj_t *scr = ui_screen_new(UI_SCR_SETTINGS, NULL);
    ui_title(scr, "POWER");
    lv_obj_t *l = ui_scroll_area(scr, 50, 176); s_ps_list = l;
    char bd[96]; app_power_batt_detail(bd, sizeof bd);
    lv_obj_t *b = ui_label(l, &lv_font_montserrat_12, C_FG, bd); lv_obj_set_width(b, lv_pct(100)); lv_label_set_long_mode(b, LV_LABEL_LONG_WRAP);
    ui_row_btn(l, "Screen off after", app_power_timeout_name(p->scr_timeout_s), C_CYAN, to_cb, NULL);
    lv_obj_t *n1 = ui_label(l, &lv_font_montserrat_12, C_MUT, "outside rides only; Bluetooth\nstays on (connected standby)"); lv_obj_set_width(n1, lv_pct(100)); lv_label_set_long_mode(n1, LV_LABEL_LONG_WRAP);
    ui_row_btn(l, "Wake gesture", app_power_wake_name(p->wake_taps), C_CYAN, wake_cb, NULL);
    lv_obj_t *n6 = ui_label(l, &lv_font_montserrat_12, C_MUT, p->wake_taps == 1 ? "any touch: rides only;\notherwise 2 taps" : "taps anywhere, within 2.5 s;\nslides and holds are ignored"); lv_obj_set_width(n6, lv_pct(100)); lv_label_set_long_mode(n6, LV_LABEL_LONG_WRAP);
    ui_row_btn(l, "Auto deep sleep", app_power_autosleep_name(p->auto_sleep_min), C_CYAN, as_cb, NULL);
    lv_obj_t *n2 = ui_label(l, &lv_font_montserrat_12, C_MUT, "idle on battery, no ride, no phone\nconnected; switches Bluetooth OFF"); lv_obj_set_width(n2, lv_pct(100)); lv_label_set_long_mode(n2, LV_LABEL_LONG_WRAP);
    ui_row_btn(l, "Wake on warning", p->wake_on_cue ? "on" : "off", p->wake_on_cue ? C_GREEN : C_MUT, cue_cb, NULL);
    lv_obj_t *n3 = ui_label(l, &lv_font_montserrat_12, C_MUT, "screen off in a ride: 5 s on\nfor HR HIGH and similar"); lv_obj_set_width(n3, lv_pct(100)); lv_label_set_long_mode(n3, LV_LABEL_LONG_WRAP);
    ui_row_btn(l, "Low batt.", p->bat_protect ? "auto-save" : "alerts only", p->bat_protect ? C_AMBER : C_GREEN, prot_cb, NULL);
    lv_obj_t *n4 = ui_label(l, &lv_font_montserrat_12, p->bat_protect ? C_AMBER : C_MUT,
        p->bat_protect ? "NOT VALIDATED: at ~5% the ride is\nended, saved and the device sleeps" : "alerts at ~20%, ~10%, ~5%;\nthe ride is never ended by itself");
    lv_obj_set_width(n4, lv_pct(100)); lv_label_set_long_mode(n4, LV_LABEL_LONG_WRAP);
    ui_row_btn(l, "Quick Settings", LV_SYMBOL_DOWN " swipe", C_CYAN, qs_from_settings, NULL);
    ui_row_btn(l, "Deep sleep", "link off", C_CYAN, sleep_from_settings, NULL);
    lv_obj_t *n5 = ui_label(l, &lv_font_montserrat_12, C_MUT, "no power switch on this board;\npercentages are estimates"); lv_obj_set_width(n5, lv_pct(100)); lv_label_set_long_mode(n5, LV_LABEL_LONG_WRAP);
    lv_obj_add_event_cb(l, ps_remember, LV_EVENT_SCROLL_END, NULL);
    lv_obj_update_layout(l); lv_obj_scroll_to_y(l, s_ps_scroll, LV_ANIM_OFF);
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 44, back_settings, NULL);
    lv_obj_align(bk, LV_ALIGN_TOP_MID, 0, 182);
    ui_screen_show(scr);
}
