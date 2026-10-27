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
    ui_power_refresh();
    if (app_power()->asleep) return;                 /* harness only: the device never returns from deep sleep */
    if (s_update && app_power()->screen_on) s_update();   /* screen off: app and recording run, widgets are not redrawn */
    ui_demo_badge_refresh();
    ui_passkey_refresh();
}

static lv_obj_t *s_cur_scr;
static void scr_deleted(lv_event_t *e)
{
    lv_obj_t *scr = lv_event_get_target(e);
    if (scr == s_cur_scr) { s_cur_scr = NULL; s_update = NULL; s_kind = UI_SCR_OTHER; }   /* rc3: never refresh a deleted screen */
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
    ui_power_attach_screen(scr, kind);
    return scr;
}

ui_scr_t ui_current(void) { return s_kind; }

void ui_screen_show(lv_obj_t *scr)
{
    if (!s_timer) s_timer = lv_timer_create(refresh_cb, 250, NULL);
    s_kind = UI_SCR_OTHER; s_update = NULL; s_cur_scr = scr;
    for (int i = 0; i < 6; i++) if (s_tab[i].scr == scr) { s_kind = s_tab[i].kind; s_update = s_tab[i].update; }
    lv_obj_t *old = lv_screen_active();
    ui_qs_handle_allow(true);
    lv_screen_load(scr);
    if (old && old != scr) lv_obj_delete_async(old);
    s_badge_hidden = false;
    if (s_update) s_update();
    ui_demo_badge_refresh();
    ui_passkey_refresh();
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
    int lim = 2 * ui_chord(38) - 8;                        /* 0.6.1: never wider than the circle at that height */
    lv_point_t sz; lv_text_get_size(&sz, txt ? txt : "", &bc_bold16, 1, 0, LV_COORD_MAX, LV_TEXT_FLAG_NONE);
    lv_obj_set_style_text_letter_space(l, sz.x > lim ? 0 : 1, 0);   /* long title: drop the letter spacing before shortening */
    lv_obj_set_width(l, lim);
    lv_label_set_long_mode(l, LV_LABEL_LONG_MODE_DOTS);
    lv_obj_align(l, LV_ALIGN_TOP_MID, 0, 30);
    return l;
}

/* 0.6.1: a wrapped description for a list or page: width = the chord of the circle at the given height, never wider */
lv_obj_t *ui_note(lv_obj_t *p, const char *txt, int at_y)
{
    lv_obj_t *l = ui_label(p, &lv_font_montserrat_12, C_MUT, txt);
    if (lv_obj_has_flag(p, LV_OBJ_FLAG_USER_1)) lv_obj_set_width(l, lv_pct(100));   /* inside a list: the list's width */
    else { int w = 2 * ui_chord(at_y) - 16; if (w > 212) w = 212; if (w < 120) w = 120; lv_obj_set_width(l, w); }
    lv_label_set_long_mode(l, LV_LABEL_LONG_MODE_WRAP);
    return l;
}

static void style_btn(lv_obj_t *b, lv_color_t bg, int radius)
{
    lv_obj_remove_style_all(b);
    lv_obj_set_style_bg_color(b, bg, 0);
    lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0);
    lv_obj_set_style_radius(b, radius, 0);
    lv_obj_set_style_bg_color(b, lv_color_mix(bg, lv_color_white(), 200), LV_STATE_PRESSED);
    /* no transform on press: a scaled object makes LVGL render it through a 32-bit layer (~28 KB for a list row), which
       on top of the ride screen + Quick Settings pushed the LVGL heap past 90 % (measured in test/sim, 0.5.0) */
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

/* ---- hold-to-confirm (state machine in bc_core: bc_hold_t) */
typedef struct { bc_hold_t h; lv_obj_t *ring; } hold_t;

static void hold_apply(lv_obj_t *b, hold_t *st, bc_hold_ev_t ev)
{
    switch (ev) {
    case BC_HOLD_HOLDING: lv_obj_remove_flag(st->ring, LV_OBJ_FLAG_HIDDEN); lv_bar_set_value(st->ring, st->h.progress, LV_ANIM_OFF); break;
    case BC_HOLD_FIRED: lv_bar_set_value(st->ring, 100, LV_ANIM_OFF); app_power_swallow_rest(); lv_obj_send_event(b, LV_EVENT_READY, NULL); break;
    case BC_HOLD_CANCELLED: lv_bar_set_value(st->ring, 0, LV_ANIM_OFF); lv_obj_add_flag(st->ring, LV_OBJ_FLAG_HIDDEN); lv_obj_send_event(b, LV_EVENT_CANCEL, NULL); break;
    default: break;
    }
}

static void hold_cb(lv_event_t *e)
{
    lv_obj_t *b = lv_event_get_current_target(e);
    hold_t *st = (hold_t *)lv_event_get_user_data(e);
    lv_event_code_t c = lv_event_get_code(e);
    if (c == LV_EVENT_DELETE) { lv_free(st); return; }
    if (c != LV_EVENT_PRESSED && c != LV_EVENT_PRESSING && c != LV_EVENT_RELEASED && c != LV_EVENT_PRESS_LOST) return;
    lv_indev_t *i = lv_indev_active(); lv_point_t pt = { -1, -1 }; if (i) lv_indev_get_point(i, &pt);
    bool pressed = (c == LV_EVENT_PRESSED || c == LV_EVENT_PRESSING);
    bc_hold_ev_t ev = bc_hold_feed(&st->h, pressed, pt.x, pt.y, lv_tick_get());
    if (c == LV_EVENT_RELEASED || c == LV_EVENT_PRESS_LOST) { lv_bar_set_value(st->ring, 0, LV_ANIM_OFF); lv_obj_add_flag(st->ring, LV_OBJ_FLAG_HIDDEN); }
    hold_apply(b, st, ev);
}

lv_obj_t *ui_hold_btn(lv_obj_t *p, const char *txt, lv_color_t bg, lv_color_t fg, int w, int h, uint32_t hold_ms, lv_event_cb_t cb, void *ud)
{
    lv_obj_t *b = ui_pill(p, txt, bg, fg, w, h, NULL, NULL);
    lv_obj_remove_flag(b, LV_OBJ_FLAG_GESTURE_BUBBLE);
    hold_t *st = lv_malloc(sizeof(hold_t)); memset(st, 0, sizeof *st); bc_hold_init(&st->h, hold_ms);
    /* progress: the pill fills from the left while the finger stays still (a bar under the label, hidden when idle) */
    lv_obj_t *r = lv_bar_create(b);
    lv_obj_remove_style_all(r);
    lv_obj_set_size(r, lv_pct(100), lv_pct(100));
    lv_obj_center(r);
    lv_obj_set_style_radius(r, LV_RADIUS_CIRCLE, LV_PART_MAIN);
    lv_obj_set_style_bg_opa(r, LV_OPA_TRANSP, LV_PART_MAIN);
    lv_obj_set_style_radius(r, LV_RADIUS_CIRCLE, LV_PART_INDICATOR);
    lv_obj_set_style_bg_color(r, lv_color_mix(fg, bg, 120), LV_PART_INDICATOR);
    lv_obj_set_style_bg_opa(r, LV_OPA_70, LV_PART_INDICATOR);
    lv_bar_set_range(r, 0, 100); lv_bar_set_value(r, 0, LV_ANIM_OFF);
    lv_obj_remove_flag(r, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_flag(r, LV_OBJ_FLAG_HIDDEN);
    lv_obj_move_background(r);
    st->ring = r;
    lv_obj_add_event_cb(b, hold_cb, LV_EVENT_ALL, st);
    if (cb) lv_obj_add_event_cb(b, cb, LV_EVENT_READY, ud);
    return b;
}
lv_obj_t *ui_hold_label(lv_obj_t *hold_btn) { return lv_obj_get_child(hold_btn, 1); }   /* child 0 is the fill bar */

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
    lv_obj_set_size(b, lv_pct(100), 44);                 /* 0.6.1: finger-sized rows (was 40) */
    lv_obj_remove_flag(b, LV_OBJ_FLAG_GESTURE_BUBBLE);
    lv_obj_add_flag(b, LV_OBJ_FLAG_SCROLL_ON_FOCUS);
    lv_obj_t *l = ui_label(b, &lv_font_montserrat_14, C_FG, left);
    lv_obj_set_style_text_align(l, LV_TEXT_ALIGN_LEFT, 0);
    lv_obj_set_height(l, lv_font_get_line_height(&lv_font_montserrat_14) + 2);   /* one line: a fixed box, else a long text wraps */
    lv_label_set_long_mode(l, LV_LABEL_LONG_MODE_CLIP);
    lv_obj_align(l, LV_ALIGN_LEFT_MID, 10, 0);
    if (right) {
        lv_obj_t *r = ui_label(b, &lv_font_montserrat_14, right_c, right);
        lv_obj_set_style_text_align(r, LV_TEXT_ALIGN_RIGHT, 0);
        lv_obj_set_height(r, lv_font_get_line_height(&lv_font_montserrat_14) + 2);
        lv_label_set_long_mode(r, LV_LABEL_LONG_MODE_CLIP);
        lv_obj_align(r, LV_ALIGN_RIGHT_MID, -10, 0);
    }
    if (cb) lv_obj_add_event_cb(b, cb, LV_EVENT_CLICKED, ud);
    ui_row_fit(b);
    return b;
}

/* 0.6.1: split a row's inner width between title and value: each gets what its text needs when both fit; otherwise the
   title keeps at least 40 % and the value at least 20 %, and whichever is too long ends in "..." (DOTS). */
static void row_split(int inner, int title_w, int value_w, int *lw, int *rw)
{
    const int gap = 8;
    int r = value_w, l = title_w;
    if (l + gap + r <= inner) { *lw = l; *rw = inner - gap - l; return; }   /* both fit: the value takes the slack */
    /* too long together: the title is the row's identity and keeps its text (up to 70 %); the value gets the rest (>= 20 %) */
    int max_l = inner * 70 / 100, min_r = inner * 20 / 100;
    if (l > max_l) l = max_l;
    r = inner - gap - l;
    if (r < min_r) { r = min_r; l = inner - gap - r; }
    *lw = l; *rw = r;
}
static int text_w(lv_obj_t *label, const char *txt)
{
    lv_point_t sz; lv_text_get_size(&sz, txt ? txt : "", lv_obj_get_style_text_font(label, LV_PART_MAIN), 0, 0, LV_COORD_MAX, LV_TEXT_FLAG_NONE);
    return sz.x;
}
static int row_inner(lv_obj_t *row)
{
    lv_obj_t *par = lv_obj_get_parent(row);
    int w = par ? lv_obj_get_content_width(par) : 0; if (w <= 80) w = lv_obj_get_width(row); if (w <= 80) w = 2 * ui_chord(60) - 4;
    return w - 20;
}
/* DOTS rewrites the stored text when it does not fit; keep it for the label that really is too long, CLIP (text untouched) otherwise */
static void fit_mode(lv_obj_t *label, int need_w, int have_w) { lv_label_set_long_mode(label, need_w > have_w ? LV_LABEL_LONG_MODE_DOTS : LV_LABEL_LONG_MODE_CLIP); }

/* 0.6.1: change a row's value. The width is set from the NEW text before it is stored, because LVGL's DOTS mode rewrites a
   stored text that does not fit ("! not..."), and a fit measured afterwards would only see the shortened text. */
void ui_row_set_value(lv_obj_t *row, const char *txt, lv_color_t color)
{
    lv_obj_t *r = lv_obj_get_child_count(row) > 1 ? lv_obj_get_child(row, 1) : NULL;
    if (!r || !lv_obj_check_type(r, &lv_label_class)) return;
    lv_obj_t *l = lv_obj_get_child(row, 0);
    bool l_ok = l && lv_obj_check_type(l, &lv_label_class);
    int tw = l_ok ? text_w(l, lv_label_get_text(l)) : 0, vw = text_w(r, txt);
    int lw, rw; row_split(row_inner(row), tw, vw, &lw, &rw);
    if (l_ok) { fit_mode(l, tw, lw); lv_obj_set_width(l, lw); }
    lv_label_set_long_mode(r, LV_LABEL_LONG_MODE_CLIP);   /* set the text with the stored copy intact, then choose the mode */
    lv_obj_set_width(r, rw);
    lv_obj_set_style_text_color(r, color, 0);
    lv_label_set_text(r, txt);
    fit_mode(r, vw, rw);
}

/* 0.6.1 layout rule for a row: the value keeps up to 55 % of the row, the title gets the rest; a title or value that is
   still too long ends in "..." instead of running under the other. Call again after changing either text. */
void ui_row_fit(lv_obj_t *row)
{
    lv_obj_t *l = lv_obj_get_child(row, 0), *r = lv_obj_get_child_count(row) > 1 ? lv_obj_get_child(row, 1) : NULL;
    if (!l || !lv_obj_check_type(l, &lv_label_class)) return;
    int inner = row_inner(row);
    if (!r) { lv_obj_set_width(l, inner); return; }
    int tw = text_w(l, lv_label_get_text(l)), vw = text_w(r, lv_label_get_text(r));
    int lw, rw; row_split(inner, tw, vw, &lw, &rw);
    fit_mode(r, vw, rw); lv_obj_set_width(r, rw);
    fit_mode(l, tw, lw); lv_obj_set_width(l, lw);
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
    case PLAT_LINK_STALE: return "STALE";
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
    case PLAT_LINK_SEARCHING: case PLAT_LINK_CONNECTING: case PLAT_LINK_RETRY: case PLAT_LINK_STALE: return C_AMBER;
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
    case BC_CUE_PHONE: return c->head;
    default: return "READY";
    }
}

void ui_battery_text(char *buf, size_t cap)
{
    /* the percentage is an ESTIMATE from the voltage ("~"); "USB" is an inference, never a charging claim */
    const app_power_t *P = app_power();
    int pct = P->pct;
    if (P->usb_likely) snprintf(buf, cap, LV_SYMBOL_USB);
    else if (pct < 0) snprintf(buf, cap, LV_SYMBOL_BATTERY_EMPTY " ?");
    else snprintf(buf, cap, "%s ~%d%%", pct > 75 ? LV_SYMBOL_BATTERY_FULL : pct > 50 ? LV_SYMBOL_BATTERY_3 : pct > 25 ? LV_SYMBOL_BATTERY_2 :
                  pct > 10 ? LV_SYMBOL_BATTERY_1 : LV_SYMBOL_BATTERY_EMPTY, pct);
}

unsigned ui_hex(lv_color_t c) { return (unsigned)(lv_color_to_u32(c) & 0xFFFFFFu); }
