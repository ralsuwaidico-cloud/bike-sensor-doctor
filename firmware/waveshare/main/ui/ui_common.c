#include "ui.h"
#include <math.h>
#include <stdio.h>
#include <string.h>

/* ---- screen management: a tiny table maps each live screen to its kind and periodic update function */
typedef struct { lv_obj_t *scr; ui_scr_t kind; ui_update_cb_t update; } scr_entry_t;
static scr_entry_t s_tab[6];
static ui_scr_t s_kind = UI_SCR_OTHER;
static ui_update_cb_t s_update;
static lv_timer_t *s_timer;
static lv_obj_t *s_badge;
static bool s_badge_hidden;

int ui_chord(int y)
{
    int dy = y - UI_R; if (dy < 0) dy = -dy;
    if (dy >= UI_SAFE_R) return 0;
    return (int)sqrt((double)(UI_SAFE_R * UI_SAFE_R - dy * dy));
}

static void refresh_cb(lv_timer_t *t)
{
    (void)t;
    app_tick();
    if (s_update) s_update();
    ui_demo_badge_refresh();
}

static void scr_deleted(lv_event_t *e)
{
    lv_obj_t *scr = lv_event_get_target(e);
    for (int i = 0; i < 6; i++) if (s_tab[i].scr == scr) s_tab[i].scr = NULL;
}

lv_obj_t *ui_screen_new(ui_scr_t kind, ui_update_cb_t update)
{
    lv_obj_t *scr = lv_obj_create(NULL);
    lv_obj_set_style_bg_color(scr, C_BG, 0);
    lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, 0);
    lv_obj_set_style_text_color(scr, C_FG, 0);
    lv_obj_set_style_text_font(scr, &lv_font_montserrat_14, 0);
    lv_obj_set_style_pad_all(scr, 0, 0);
    lv_obj_remove_flag(scr, LV_OBJ_FLAG_SCROLLABLE);
    for (int i = 0; i < 6; i++) if (!s_tab[i].scr) { s_tab[i].scr = scr; s_tab[i].kind = kind; s_tab[i].update = update; break; }
    lv_obj_add_event_cb(scr, scr_deleted, LV_EVENT_DELETE, NULL);
    return scr;
}

ui_scr_t ui_current(void) { return s_kind; }

void ui_screen_show(lv_obj_t *scr)
{
    if (!s_timer) s_timer = lv_timer_create(refresh_cb, 250, NULL);
    s_kind = UI_SCR_OTHER; s_update = NULL;
    for (int i = 0; i < 6; i++) if (s_tab[i].scr == scr) { s_kind = s_tab[i].kind; s_update = s_tab[i].update; }
    lv_obj_t *old = lv_screen_active();
    lv_screen_load(scr);
    if (old && old != scr) lv_obj_delete_async(old);
    s_badge_hidden = false;
    if (s_update) s_update();
    ui_demo_badge_refresh();
}

/* ---- building blocks */
lv_obj_t *ui_label(lv_obj_t *p, const lv_font_t *f, lv_color_t c, const char *txt)
{
    lv_obj_t *l = lv_label_create(p);
    lv_obj_set_style_text_font(l, f, 0);
    lv_obj_set_style_text_color(l, c, 0);
    lv_obj_set_style_text_align(l, LV_TEXT_ALIGN_CENTER, 0);
    lv_label_set_text(l, txt ? txt : "");
    return l;
}

lv_obj_t *ui_title(lv_obj_t *p, const char *txt)
{
    lv_obj_t *l = ui_label(p, &bc_bold16, C_CYAN, txt);
    lv_obj_set_style_text_letter_space(l, 1, 0);
    lv_obj_align(l, LV_ALIGN_TOP_MID, 0, 30);
    return l;
}

static void style_btn(lv_obj_t *b, lv_color_t bg, int radius)
{
    lv_obj_remove_style_all(b);
    lv_obj_set_style_bg_color(b, bg, 0);
    lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(b, radius, 0);
    lv_obj_set_style_bg_color(b, lv_color_mix(bg, lv_color_white(), 200), LV_STATE_PRESSED);
    lv_obj_set_style_transform_scale(b, 245, LV_STATE_PRESSED);
    lv_obj_add_flag(b, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_remove_flag(b, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_flag(b, LV_OBJ_FLAG_GESTURE_BUBBLE);
}

lv_obj_t *ui_pill(lv_obj_t *p, const char *txt, lv_color_t bg, lv_color_t fg, int w, int h, lv_event_cb_t cb, void *ud)
{
    lv_obj_t *b = lv_button_create(p);
    style_btn(b, bg, LV_RADIUS_CIRCLE);
    lv_obj_set_size(b, w, h);
    lv_obj_t *l = ui_label(b, &bc_bold16, fg, txt);
    lv_obj_center(l);
    if (cb) lv_obj_add_event_cb(b, cb, LV_EVENT_CLICKED, ud);
    return b;
}

lv_obj_t *ui_round_btn(lv_obj_t *p, const char *sym, lv_color_t bg, lv_color_t fg, int d, lv_event_cb_t cb, void *ud)
{
    lv_obj_t *b = lv_button_create(p);
    style_btn(b, bg, LV_RADIUS_CIRCLE);
    lv_obj_set_size(b, d, d);
    lv_obj_t *l = ui_label(b, &lv_font_montserrat_20, fg, sym);
    lv_obj_center(l);
    if (cb) lv_obj_add_event_cb(b, cb, LV_EVENT_CLICKED, ud);
    return b;
}

void ui_nav(lv_obj_t *p, lv_event_cb_t back, const char *next_txt, lv_event_cb_t next, void *ud)
{
    if (back) {
        lv_obj_t *b = ui_round_btn(p, LV_SYMBOL_LEFT, C_PANEL, C_FG, 44, back, ud);
        lv_obj_align(b, LV_ALIGN_TOP_LEFT, 54, 164);
    }
    if (next_txt) {
        lv_obj_t *n = ui_pill(p, next_txt, C_CYAN, C_INK, back ? 100 : 112, 44, next, ud);
        if (back) lv_obj_align(n, LV_ALIGN_TOP_LEFT, 106, 164);
        else lv_obj_align(n, LV_ALIGN_TOP_MID, 0, 166);
    }
}

/* ---- hold-to-confirm */
typedef struct { uint32_t t0; uint32_t hold; bool fired, down; lv_obj_t *ring; } hold_t;

static void hold_cb(lv_event_t *e)
{
    lv_obj_t *b = lv_event_get_current_target(e);
    hold_t *h = (hold_t *)lv_event_get_user_data(e);
    lv_event_code_t c = lv_event_get_code(e);
    if (c == LV_EVENT_DELETE) { lv_free(h); return; }
    if (c == LV_EVENT_PRESSED) { h->t0 = lv_tick_get(); h->fired = false; h->down = true; lv_arc_set_value(h->ring, 0); lv_obj_remove_flag(h->ring, LV_OBJ_FLAG_HIDDEN); }
    else if (c == LV_EVENT_PRESSING && h->down && !h->fired) {
        uint32_t el = lv_tick_elaps(h->t0);
        lv_arc_set_value(h->ring, (int32_t)(el >= h->hold ? 100 : el * 100 / h->hold));
        if (el >= h->hold) { h->fired = true; lv_obj_send_event(b, LV_EVENT_READY, NULL); }
    } else if (c == LV_EVENT_RELEASED || c == LV_EVENT_PRESS_LOST) {
        h->down = false; lv_arc_set_value(h->ring, 0); lv_obj_add_flag(h->ring, LV_OBJ_FLAG_HIDDEN);
    }
}

lv_obj_t *ui_hold_btn(lv_obj_t *p, const char *txt, lv_color_t bg, lv_color_t fg, int w, int h, uint32_t hold_ms, lv_event_cb_t cb, void *ud)
{
    lv_obj_t *b = ui_pill(p, txt, bg, fg, w, h, NULL, NULL);
    lv_obj_remove_flag(b, LV_OBJ_FLAG_GESTURE_BUBBLE);
    hold_t *st = lv_malloc(sizeof(hold_t)); memset(st, 0, sizeof *st); st->hold = hold_ms;
    /* progress: a bar along the bottom of the pill */
    lv_obj_t *r = lv_arc_create(b);   /* arc used as a simple 0..100 progress holder drawn as a ring around the label */
    lv_obj_remove_style_all(r);
    lv_obj_set_size(r, h - 8, h - 8);
    lv_obj_align(r, LV_ALIGN_RIGHT_MID, -6, 0);
    lv_arc_set_bg_angles(r, 0, 360); lv_arc_set_rotation(r, 270); lv_arc_set_range(r, 0, 100); lv_arc_set_value(r, 0);
    lv_obj_set_style_arc_width(r, 4, LV_PART_INDICATOR);
    lv_obj_set_style_arc_color(r, fg, LV_PART_INDICATOR);
    lv_obj_set_style_arc_rounded(r, false, LV_PART_INDICATOR);
    lv_obj_remove_flag(r, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_flag(r, LV_OBJ_FLAG_HIDDEN);
    st->ring = r;
    lv_obj_add_event_cb(b, hold_cb, LV_EVENT_ALL, st);
    if (cb) lv_obj_add_event_cb(b, cb, LV_EVENT_READY, ud);
    return b;
}

/* ---- scroll area + rows */
lv_obj_t *ui_scroll_area(lv_obj_t *p, int y0, int y1)
{
    int half = ui_chord(y0); int h2 = ui_chord(y1); if (h2 < half) half = h2;
    lv_obj_t *c = lv_obj_create(p);
    lv_obj_remove_style_all(c);
    lv_obj_set_size(c, 2 * half - 4, y1 - y0);
    lv_obj_align(c, LV_ALIGN_TOP_MID, 0, y0);
    lv_obj_set_flex_flow(c, LV_FLEX_FLOW_COLUMN);
    lv_obj_set_flex_align(c, LV_FLEX_ALIGN_START, LV_FLEX_ALIGN_CENTER, LV_FLEX_ALIGN_CENTER);
    lv_obj_set_style_pad_row(c, 6, 0);
    lv_obj_set_style_pad_ver(c, 4, 0);
    lv_obj_set_scroll_dir(c, LV_DIR_VER);
    lv_obj_set_scrollbar_mode(c, LV_SCROLLBAR_MODE_ACTIVE);
    lv_obj_set_style_bg_color(c, C_CYAN, LV_PART_SCROLLBAR);
    lv_obj_set_style_width(c, 3, LV_PART_SCROLLBAR);
    lv_obj_add_flag(c, LV_OBJ_FLAG_SCROLL_MOMENTUM);
    lv_obj_add_flag(c, LV_OBJ_FLAG_USER_1);   /* marks an intended scroll area (test harness) */
    return c;
}

lv_obj_t *ui_row_btn(lv_obj_t *list, const char *left, const char *right, lv_color_t right_c, lv_event_cb_t cb, void *ud)
{
    lv_obj_t *b = lv_button_create(list);
    style_btn(b, C_PANEL, 12);
    lv_obj_set_size(b, lv_pct(100), 40);
    lv_obj_remove_flag(b, LV_OBJ_FLAG_GESTURE_BUBBLE);
    lv_obj_add_flag(b, LV_OBJ_FLAG_SCROLL_ON_FOCUS);
    lv_obj_t *l = ui_label(b, &lv_font_montserrat_14, C_FG, left);
    lv_obj_align(l, LV_ALIGN_LEFT_MID, 10, 0);
    if (right) { lv_obj_t *r = ui_label(b, &lv_font_montserrat_14, right_c, right); lv_obj_align(r, LV_ALIGN_RIGHT_MID, -10, 0); }
    if (cb) lv_obj_add_event_cb(b, cb, LV_EVENT_CLICKED, ud);
    return b;
}

lv_obj_t *ui_wheel(lv_obj_t *p, const char *options, int sel, int w, int rows, const lv_font_t *f)
{
    lv_obj_t *r = lv_roller_create(p);
    lv_roller_set_options(r, options, LV_ROLLER_MODE_NORMAL);
    lv_obj_set_width(r, w);
    lv_obj_set_style_text_font(r, f, 0);
    lv_obj_set_style_text_color(r, C_MUT, 0);
    lv_obj_set_style_text_align(r, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_style_bg_opa(r, LV_OPA_TRANSP, 0);
    lv_obj_set_style_border_width(r, 0, 0);
    lv_obj_set_style_text_line_space(r, 8, 0);
    lv_obj_set_style_bg_color(r, C_PANEL, LV_PART_SELECTED);
    lv_obj_set_style_bg_opa(r, LV_OPA_COVER, LV_PART_SELECTED);
    lv_obj_set_style_text_color(r, C_FG, LV_PART_SELECTED);
    lv_obj_set_style_radius(r, 12, LV_PART_SELECTED);
    lv_roller_set_visible_row_count(r, (uint32_t)rows);
    lv_roller_set_selected(r, (uint32_t)sel, LV_ANIM_OFF);
    lv_obj_remove_flag(r, LV_OBJ_FLAG_GESTURE_BUBBLE);
    return r;
}

void ui_page_dots(lv_obj_t *p, int n, int active, int y)
{
    int gap = 12, x0 = UI_R - (n - 1) * gap / 2;
    for (int i = 0; i < n; i++) {
        lv_obj_t *d = lv_obj_create(p);
        lv_obj_remove_style_all(d);
        lv_obj_set_size(d, 6, 6);
        lv_obj_set_style_radius(d, 3, 0);
        lv_obj_set_style_bg_opa(d, LV_OPA_COVER, 0);
        lv_obj_set_style_bg_color(d, i == active ? C_CYAN : C_FAINT, 0);
        lv_obj_set_pos(d, x0 + i * gap - 3, y);
        lv_obj_remove_flag(d, LV_OBJ_FLAG_CLICKABLE);
    }
}

/* ---- demo badge: lives on the top layer, so it shows on every screen */
void ui_demo_badge_hide_for_screen(bool hide) { s_badge_hidden = hide; ui_demo_badge_refresh(); }

void ui_demo_badge_refresh(void)
{
    if (!s_badge) {
        s_badge = lv_obj_create(lv_layer_top());
        lv_obj_remove_style_all(s_badge);
        lv_obj_set_size(s_badge, 58, 18);
        lv_obj_set_style_radius(s_badge, 9, 0);
        lv_obj_set_style_bg_color(s_badge, C_DEMO, 0);
        lv_obj_set_style_bg_opa(s_badge, LV_OPA_COVER, 0);
        lv_obj_align(s_badge, LV_ALIGN_TOP_MID, 0, 8);
        lv_obj_remove_flag(s_badge, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_t *l = ui_label(s_badge, &lv_font_montserrat_12, C_INK, "DEMO");
        lv_obj_center(l);
    }
    bool show = app_demo() && !s_badge_hidden;
    if (show) lv_obj_remove_flag(s_badge, LV_OBJ_FLAG_HIDDEN); else lv_obj_add_flag(s_badge, LV_OBJ_FLAG_HIDDEN);
}

/* ---- status helpers */
const char *ui_link_text(plat_link_t l)
{
    switch (l) {
    case PLAT_LINK_OFF: return "OFF";
    case PLAT_LINK_NOT_PAIRED: return "NOT PAIRED";
    case PLAT_LINK_SEARCHING: return "SEARCHING";
    case PLAT_LINK_CONNECTING: return "CONNECTING";
    case PLAT_LINK_CONNECTED: return "CONNECTED";
    case PLAT_LINK_RETRY: return "RECONNECTING";
    case PLAT_LINK_UNSUPPORTED: return "NO SENSOR";
    }
    return "?";
}

lv_color_t ui_link_color(plat_link_t l)
{
    switch (l) {
    case PLAT_LINK_CONNECTED: return C_GREEN;
    case PLAT_LINK_SEARCHING: case PLAT_LINK_CONNECTING: case PLAT_LINK_RETRY: return C_AMBER;
    default: return C_MUT;
    }
}

lv_color_t ui_level_color(bc_cue_level_t l)
{
    switch (l) { case BC_LVL_GOOD: return C_GREEN; case BC_LVL_UP: return C_CYAN; case BC_LVL_DOWN: return C_AMBER; case BC_LVL_WARN: return C_RED; default: return C_FAINT; }
}

const char *ui_cue_short(const bc_cue_t *c)
{
    switch (c->id) {
    case BC_CUE_NO_DATA: return "NO DATA";
    case BC_CUE_HR_HIGH: return "HR HIGH";
    case BC_CUE_COASTING: return "COASTING";
    case BC_CUE_WARMUP: return "WARM UP";
    case BC_CUE_WARMUP_EASY: return "EASIER";
    case BC_CUE_LEARNING: return "LEARNING";
    case BC_CUE_EASE_OFF: return "EASE OFF";
    case BC_CUE_MORE: return "MORE POWER";
    case BC_CUE_SURGE: return "SMOOTH IT";
    case BC_CUE_DROPPING: return "KEEP POWER";
    case BC_CUE_CAD_LOW: return "HIGHER RPM";
    case BC_CUE_CAD_HIGH: return "LOWER RPM";
    case BC_CUE_HOLD: return c->why[0] == 'n' ? "CADENCE OK" : "HOLD THIS";
    default: return "READY";
    }
}

void ui_battery_text(char *buf, size_t cap)
{
    int pct = plat_battery_pct();
    if (plat_usb_power()) snprintf(buf, cap, LV_SYMBOL_USB);
    else if (pct < 0) snprintf(buf, cap, LV_SYMBOL_BATTERY_EMPTY " ?");
    else snprintf(buf, cap, "%s %d%%", pct > 75 ? LV_SYMBOL_BATTERY_FULL : pct > 50 ? LV_SYMBOL_BATTERY_3 : pct > 25 ? LV_SYMBOL_BATTERY_2 :
                  pct > 10 ? LV_SYMBOL_BATTERY_1 : LV_SYMBOL_BATTERY_EMPTY, pct);
}

unsigned ui_hex(lv_color_t c) { return (unsigned)(lv_color_to_u32(c) & 0xFFFFFFu); }
