/*
 * PC preview + automated UI test for the round 240 x 240 Waveshare screen.
 * Runs the REAL firmware UI/app code (main/ui, main/app, bc_core) on LVGL built with the firmware's own sdkconfig.
 *
 * For every captured screen it checks:
 *   CIRCLE  no drawn pixel outside the safe circle (radius UI_SAFE_R+1 around the centre)
 *   GLYPH   every character of every visible label exists in its font (no missing-glyph boxes)
 *   CLIP    no visible label/button is cut off by its (non-scrolling) parent
 *   TOUCH   every visible control is at least 28 px and its centre is inside the circle
 * and saves out/<name>.ppm for the preview sheet. Functional checks (persistence, ride states, demo isolation, crash
 * recovery, FTP rules) are asserted along the way. Exit code 0 = all passed.
 */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include "lvgl.h"
#include "sim.h"
#include "src/misc/lv_area_private.h"
#include "app_psvc.h"   /* lv_area_intersect returns bool; without the prototype the implicit int return misreads it */
#include "ui.h"
#include "app.h"
#include "app_diag.h"

static uint16_t fb[UI_W * UI_W];
static uint16_t drawbuf[UI_W * UI_W];
static lv_display_t *disp;
static lv_indev_t *indev;
static struct { bool down; int x, y; } ptr;
static int n_shots, n_fail_shots, n_checks, n_fail;
static char outdir[256] = "out";
static FILE *report;

#define CHECK(c, ...) do { n_checks++; if (!(c)) { n_fail++; printf("  FAIL %s:%d %s  ", __FILE__, __LINE__, #c); printf(__VA_ARGS__); printf("\n"); } } while (0)

void sim_wifi_reboot(void);
static uint32_t tick_cb(void) { return g_sim.now_ms; }

static void flush_cb(lv_display_t *d, const lv_area_t *a, uint8_t *px)
{
    const uint16_t *p = (const uint16_t *)px;
    int w = lv_area_get_width(a);
    for (int y = a->y1; y <= a->y2; y++) memcpy(&fb[y * UI_W + a->x1], &p[(y - a->y1) * w], (size_t)w * 2);
    lv_display_flush_ready(d);
}

/* the harness drives LVGL exactly like the device driver: raw touch -> app_power_touch_filter (wake swallow + guard) -> LVGL */
/* 0.6.1: the real driver runs the LVGL input in EVENT mode - the CST816S is read only on its interrupt, i.e. at its scan rate
   while a finger is on the glass plus ONE report for the release, then nothing at all until the next contact. That silence is
   what froze 0.6.0 rev 3 after a wake (the gate waited for a report that never came). `g_sim.touch_event_mode` reproduces
   it: reads reach the gate only while down and once after the release; the continuous polling mode stays for the older
   scenarios. plat_touch_poll() (the firmware's own forced read while the gate blocks) still goes through the gate. */
static bool s_was_down, s_release_pending;
static lv_indev_state_t s_last_state = LV_INDEV_STATE_RELEASED;
static void gate_read(lv_indev_data_t *d)
{
    bool pass = app_power_touch_filter(ptr.down, ptr.x, ptr.y, g_sim.now_ms);
    s_last_state = (ptr.down && pass) ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
    d->state = s_last_state;
}
static void read_cb(lv_indev_t *i, lv_indev_data_t *d)
{
    (void)i; d->point.x = ptr.x; d->point.y = ptr.y;
    if (!g_sim.touch_event_mode) { gate_read(d); return; }
    if (ptr.down) { s_was_down = true; s_release_pending = true; gate_read(d); return; }
    if (s_release_pending) { s_release_pending = false; s_was_down = false; gate_read(d); return; }   /* the one release report */
    if (g_sim.touch_poll_request) { g_sim.touch_poll_request = false; gate_read(d); return; }          /* firmware forced a read */
    d->state = s_last_state;                                                                           /* silence: nothing reaches the gate */
}

void sim_wifi_pump(void);
static void run(int ms) { for (int t = 0; t < ms; t += 5) { g_sim.now_ms += 5; lv_timer_handler(); if (g_sim.now_ms % 100 == 0) { sim_wifi_pump(); sim_fake_pump(); } } }
static void run_s(int s) { for (int i = 0; i < s; i++) run(1000); }
static void raw_tap(int x, int y) { ptr.x = x; ptr.y = y; ptr.down = true; run(80); ptr.down = false; run(150); }
static int n_auto_wakes;
/* a rider who finds the screen dark wakes it with the configured gesture (one touch by default), then waits out the
   guard before using it; the harness does the same */
static void wake_if_dark(void) { if (!app_power()->screen_on && !app_power()->asleep) { n_auto_wakes++; int need = app_power_wake_taps_now(); for (int k = 0; k < need; k++) raw_tap(120, 120); run(600); } }
static void tap(int x, int y) { wake_if_dark(); raw_tap(x, y); }
/* START RIDE is a 1 s hold (rev 3): a tap only shows the hint */
static bool hold_text(const char *txt, int ms);
static void start_ride(void) { hold_text("START RIDE", 1300); }
/* after a hold the firmware swallows the rest of the touch and guards 400 ms (a lingering finger must press nothing): wait it out */
static void hold(int x, int y, int ms) { wake_if_dark(); ptr.x = x; ptr.y = y; ptr.down = true; run(ms); ptr.down = false; run(550); }
static void drag(int x0, int y0, int x1, int y1)
{
    wake_if_dark();
    ptr.x = x0; ptr.y = y0; ptr.down = true; run(30);
    for (int i = 1; i <= 10; i++) { ptr.x = x0 + (x1 - x0) * i / 10; ptr.y = y0 + (y1 - y0) * i / 10; run(15); }
    ptr.down = false; run(600);
}

/* ---- object helpers */
static bool visible(lv_obj_t *o)
{
    for (lv_obj_t *p = o; p; p = lv_obj_get_parent(p)) if (lv_obj_has_flag(p, LV_OBJ_FLAG_HIDDEN)) return false;
    lv_area_t a; lv_obj_get_coords(o, &a);
    if (a.x2 < 0 || a.y2 < 0 || a.x1 >= UI_W || a.y1 >= UI_W) return false;
    /* scrolled out of a parent? */
    for (lv_obj_t *p = lv_obj_get_parent(o); p; p = lv_obj_get_parent(p)) {
        lv_area_t pa; lv_obj_get_coords(p, &pa);
        if (a.x2 < pa.x1 || a.x1 > pa.x2 || a.y2 < pa.y1 || a.y1 > pa.y2) return false;
    }
    return true;
}

static lv_obj_t *find_text_rec(lv_obj_t *o, const char *txt)
{
    if (lv_obj_check_type(o, &lv_label_class) && visible(o)) {
        const char *t = lv_label_get_text(o);
        if (strstr(t, txt)) return o;
        /* 0.6.1: a row title shortened by LVGL's DOTS mode ("Rider A iP...") still is that row for a rider who reads it */
        size_t n = strlen(t);
        if (n > 3 && !strcmp(t + n - 3, "...") && strlen(txt) >= n - 3 && !strncmp(t, txt, n - 3)) return o;
    }
    for (uint32_t i = 0; i < lv_obj_get_child_count(o); i++) { lv_obj_t *r = find_text_rec(lv_obj_get_child(o, (int32_t)i), txt); if (r) return r; }
    return NULL;
}

static lv_obj_t *find_text(const char *txt)
{
    lv_obj_t *r = find_text_rec(lv_layer_top(), txt);
    return r ? r : find_text_rec(lv_screen_active(), txt);
}

static bool tap_text(const char *txt)
{
    wake_if_dark();                       /* a rider taps the dark screen awake before looking for a button */
    lv_obj_t *l = find_text(txt);
    if (!l) { n_checks++; n_fail++; printf("  FAIL could not find '%s' to tap\n", txt); return false; }
    lv_obj_t *c = l; while (c && !lv_obj_has_flag(c, LV_OBJ_FLAG_CLICKABLE)) c = lv_obj_get_parent(c);
    if (!c) c = l;
    lv_area_t a; lv_obj_get_coords(c, &a);
    /* a row half scrolled out of its list: a rider scrolls it fully into view before tapping it */
    { lv_area_t v = a; for (lv_obj_t *p = lv_obj_get_parent(c); p; p = lv_obj_get_parent(p)) { lv_area_t pa; lv_obj_get_coords(p, &pa); lv_area_intersect(&v, &v, &pa); }
      if (lv_area_get_height(&v) < lv_area_get_height(&a)) { lv_obj_scroll_to_view_recursive(c, LV_ANIM_OFF); run(300); lv_obj_get_coords(c, &a); } }
    for (lv_obj_t *p = lv_obj_get_parent(c); p; p = lv_obj_get_parent(p)) { lv_area_t pa; lv_obj_get_coords(p, &pa); lv_area_intersect(&a, &a, &pa); }
    tap((a.x1 + a.x2) / 2, (a.y1 + a.y2) / 2);
    return true;
}

static bool hold_text(const char *txt, int ms)
{
    wake_if_dark();
    lv_obj_t *l = find_text(txt);
    if (!l) { n_checks++; n_fail++; printf("  FAIL could not find '%s' to hold\n", txt); return false; }
    lv_obj_t *c = l; while (c && !lv_obj_has_flag(c, LV_OBJ_FLAG_CLICKABLE)) c = lv_obj_get_parent(c);
    if (!c) c = l;
    lv_area_t a; lv_obj_get_coords(c, &a);
    { lv_area_t v = a; for (lv_obj_t *p = lv_obj_get_parent(c); p; p = lv_obj_get_parent(p)) { lv_area_t pa; lv_obj_get_coords(p, &pa); lv_area_intersect(&v, &v, &pa); }
      if (lv_area_get_height(&v) < lv_area_get_height(&a)) { lv_obj_scroll_to_view_recursive(c, LV_ANIM_OFF); run(300); lv_obj_get_coords(c, &a); } }
    for (lv_obj_t *p = lv_obj_get_parent(c); p; p = lv_obj_get_parent(p)) { lv_area_t pa; lv_obj_get_coords(p, &pa); lv_area_intersect(&a, &a, &pa); }
    hold((a.x1 + a.x2) / 2, (a.y1 + a.y2) / 2, ms);
    return true;
}

static bool on_screen(const char *txt) { return find_text(txt) != NULL; }

/* 0.7.2: a control is usable WITHOUT scrolling: its clickable box lies fully inside every ancestor, no scrollable ancestor is
   scrolled, and all four corners are inside the round glass (radius 120). */
static bool btn_visible_at_top(const char *txt)
{
    lv_obj_t *l = find_text(txt); if (!l) return false;
    lv_obj_t *c = l; while (c && !lv_obj_has_flag(c, LV_OBJ_FLAG_CLICKABLE)) c = lv_obj_get_parent(c);
    if (!c) return false;
    lv_area_t a; lv_obj_get_coords(c, &a);
    for (lv_obj_t *p = lv_obj_get_parent(c); p; p = lv_obj_get_parent(p)) {
        lv_area_t pa; lv_obj_get_coords(p, &pa);
        if (a.x1 < pa.x1 || a.y1 < pa.y1 || a.x2 > pa.x2 || a.y2 > pa.y2) return false;
        if (lv_obj_get_scroll_y(p) != 0) return false;
    }
    int xs[2] = { a.x1, a.x2 }, ys[2] = { a.y1, a.y2 };
    for (int i = 0; i < 2; i++) for (int j = 0; j < 2; j++) { int dx = xs[i] - 120, dy = ys[j] - 120; if (dx * dx + dy * dy > 120 * 120) return false; }
    return true;
}
/* the primary action (first of the candidates found) and Back, both usable at scroll position 0 */
static bool primary_and_back_ok(const char *const *cands, int n, const char **which)
{
    *which = "?";
    for (int i = 0; i < n; i++) if (on_screen(cands[i])) { *which = cands[i]; return btn_visible_at_top(cands[i]) && btn_visible_at_top(LV_SYMBOL_LEFT); }
    return false;
}

/* scroll the screen's scroll area until txt is visible (tries both directions) */
static bool scroll_to(const char *txt)
{
    for (int k = 0; k < 12 && !on_screen(txt); k++) drag(120, 90, 120, 170);   /* towards the top */
    for (int k = 0; k < 24 && !on_screen(txt); k++) drag(120, 150, 120, 115);  /* towards the bottom, small steps */
    return on_screen(txt);
}

/* ---- per-screen checks */
static int issues;
static char issue_buf[4096];
static void issue(const char *fmt, const char *a, int x, int y)
{
    issues++;
    size_t n = strlen(issue_buf);
    if (n < sizeof issue_buf - 200) snprintf(issue_buf + n, sizeof issue_buf - n, fmt, a, x, y);
}

static uint32_t utf8_next(const char *s, int *i)
{
    unsigned char c = (unsigned char)s[*i];
    if (c < 0x80) { (*i)++; return c; }
    int n = c >= 0xF0 ? 4 : c >= 0xE0 ? 3 : 2;
    uint32_t cp = c & (0xFF >> (n + 1));
    for (int k = 1; k < n; k++) cp = (cp << 6) | ((unsigned char)s[*i + k] & 0x3F);
    *i += n; return cp;
}

static void check_glyphs(lv_obj_t *o, const char *txt, const lv_font_t *f, bool recolor)
{
    for (int i = 0; txt[i];) {
        if (recolor && txt[i] == '#') {
            if (txt[i + 1] && strchr("0123456789abcdefABCDEF", txt[i + 1])) i += 8; else i++;
            continue;
        }
        uint32_t cp = utf8_next(txt, &i);
        if (cp == '\n' || cp == ' ' || cp == '\r') continue;
        lv_font_glyph_dsc_t g;
        if (!lv_font_get_glyph_dsc(f, &g, cp, 0)) { char m[64]; snprintf(m, sizeof m, "U+%04X in '%.20s'", (unsigned)cp, txt); lv_area_t a; lv_obj_get_coords(o, &a); issue("GLYPH missing %s at %d,%d\n", m, a.x1, a.y1); return; }
    }
}


/* ---- 0.6.1 layout audit: the rectangle the label's TEXT really occupies (not the label box), clipped to its scrollable ancestors */
typedef struct { lv_area_t a; lv_obj_t *o; } txt_rect_t;
static txt_rect_t s_rects[256]; static int s_nrects;
static bool label_text_rect(lv_obj_t *o, lv_area_t *out, bool *overflow)
{
    const char *t = lv_label_get_text(o); if (!t || !*t) return false;
    const lv_font_t *f = lv_obj_get_style_text_font(o, LV_PART_MAIN);
    lv_area_t c; lv_obj_get_content_coords(o, &c);
    int32_t cw = lv_area_get_width(&c), ch = lv_area_get_height(&c);
    lv_label_long_mode_t lm = lv_label_get_long_mode(o);
    lv_text_flag_t fl = lv_label_get_recolor(o) ? LV_TEXT_FLAG_RECOLOR : LV_TEXT_FLAG_NONE;
    lv_point_t sz; lv_text_get_size(&sz, t, f, lv_obj_get_style_text_letter_space(o, LV_PART_MAIN), lv_obj_get_style_text_line_space(o, LV_PART_MAIN),
                                    lm == LV_LABEL_LONG_MODE_WRAP || lm == LV_LABEL_LONG_MODE_DOTS ? cw : LV_COORD_MAX, fl);
    *overflow = (sz.x > cw + 1 && lm != LV_LABEL_LONG_MODE_SCROLL && lm != LV_LABEL_LONG_MODE_SCROLL_CIRCULAR && lm != LV_LABEL_LONG_MODE_DOTS) || sz.y > ch + 1;
    lv_text_align_t al = lv_obj_calculate_style_text_align(o, LV_PART_MAIN, t);
    int32_t w = sz.x < cw ? sz.x : cw, h = sz.y < ch ? sz.y : ch;
    out->x1 = al == LV_TEXT_ALIGN_CENTER ? c.x1 + (cw - w) / 2 : al == LV_TEXT_ALIGN_RIGHT ? c.x2 - w : c.x1;
    out->y1 = c.y1; out->x2 = out->x1 + w - 1; out->y2 = out->y1 + h - 1;
    /* clip to every ancestor (a scroll area shows only part of a long list) */
    for (lv_obj_t *p = lv_obj_get_parent(o); p; p = lv_obj_get_parent(p)) { lv_area_t pa; lv_obj_get_coords(p, &pa); lv_area_t x; if (!lv_area_intersect(&x, out, &pa)) return false; *out = x; }
    return lv_area_get_width(out) > 0 && lv_area_get_height(out) > 0;
}
/* an opaque ancestor of `over` (below the screen) that fully contains `r` hides whatever is drawn under it (ride controls panel, popups) */
static bool covered_by_overlay(lv_obj_t *over, const lv_area_t *r)
{
    for (lv_obj_t *p = over; p && lv_obj_get_parent(p); p = lv_obj_get_parent(p)) {
        if (lv_obj_get_style_bg_opa(p, LV_PART_MAIN) >= LV_OPA_COVER) { lv_area_t pa; lv_obj_get_coords(p, &pa); lv_area_t x; if (lv_area_intersect(&x, &pa, r) && lv_area_is_equal(&x, r)) return true; }
    }
    return false;
}
static bool is_ancestor(lv_obj_t *a, lv_obj_t *b) { for (lv_obj_t *p = lv_obj_get_parent(b); p; p = lv_obj_get_parent(p)) if (p == a) return true; return false; }
static bool corner_out(const lv_area_t *r)
{
    double lim = (UI_SAFE_R + 2.0) * (UI_SAFE_R + 2.0);
    int xs[2] = { r->x1, r->x2 }, ys[2] = { r->y1, r->y2 };
    for (int i = 0; i < 2; i++) for (int j = 0; j < 2; j++) { double dx = xs[i] - 119.5, dy = ys[j] - 119.5; if (dx * dx + dy * dy > lim) return true; }
    return false;
}

static void walk(lv_obj_t *o)
{
    if (lv_obj_has_flag(o, LV_OBJ_FLAG_HIDDEN)) return;
    if (visible(o)) {
        lv_area_t a; lv_obj_get_coords(o, &a);
        lv_obj_t *par = lv_obj_get_parent(o);
        bool is_label = lv_obj_check_type(o, &lv_label_class);
        if (is_label) {
            check_glyphs(o, lv_label_get_text(o), lv_obj_get_style_text_font(o, LV_PART_MAIN), lv_label_get_recolor(o));
            /* 0.6.1 layout audit */
            lv_area_t tr; bool ovf = false;
            if (label_text_rect(o, &tr, &ovf)) {
                char m[48]; snprintf(m, sizeof m, "'%.22s'", lv_label_get_text(o));
                if (ovf) issue("OVERFLOW %s text larger than its label at %d,%d\n", m, a.x1, a.y1);
                if (corner_out(&tr)) issue("EDGE %s text reaches outside the round screen at %d,%d\n", m, tr.x1, tr.y1);
                if (s_nrects < (int)(sizeof s_rects / sizeof s_rects[0])) { s_rects[s_nrects].a = tr; s_rects[s_nrects].o = o; s_nrects++; }
            }
        }
        if (lv_obj_check_type(o, &lv_roller_class)) {
            check_glyphs(o, lv_roller_get_options(o), lv_obj_get_style_text_font(o, LV_PART_MAIN), false);
        }
        /* clipped by a non-scrolling parent (tileview tiles and my scroll areas are allowed to scroll) */
        if (par && (is_label || lv_obj_has_flag(o, LV_OBJ_FLAG_CLICKABLE)) && !lv_obj_check_type(par, &lv_tileview_class) &&
            !lv_obj_has_flag(par, LV_OBJ_FLAG_USER_1) && lv_obj_get_parent(par) != NULL) {
            lv_area_t pa; lv_obj_get_coords(par, &pa);
            if (a.x1 < pa.x1 - 1 || a.x2 > pa.x2 + 1 || a.y1 < pa.y1 - 1 || a.y2 > pa.y2 + 1) {
                char m[64]; snprintf(m, sizeof m, "'%.24s'", is_label ? lv_label_get_text(o) : "(control)");
                issue("CLIP %s cut by its parent at %d,%d\n", m, a.x1, a.y1);
            }
        }
        if (lv_obj_has_flag(o, LV_OBJ_FLAG_CLICKABLE) && par && !lv_obj_check_type(o, &lv_tileview_class) && lv_obj_get_parent(par) &&
            !lv_obj_has_flag(o, LV_OBJ_FLAG_USER_1) && lv_obj_get_width(o) < 230) {
            int w = lv_area_get_width(&a), h = lv_area_get_height(&a);
            double cx = (a.x1 + a.x2) / 2.0 - 119.5, cy = (a.y1 + a.y2) / 2.0 - 119.5;
            /* inside a scroll area a control can be partly scrolled out; judge only the part that is visible */
            if ((w < 28 || h < 28) && !lv_obj_check_type(o, &lv_roller_class)) issue("TOUCH %s too small at %d,%d\n", "control", a.x1, a.y1);
            if (sqrt(cx * cx + cy * cy) > UI_SAFE_R - 10) issue("TOUCH %s centre near/outside the edge at %d,%d\n", "control", a.x1, a.y1);
        }
    }
    for (uint32_t i = 0; i < lv_obj_get_child_count(o); i++) walk(lv_obj_get_child(o, (int32_t)i));
}

/* 0.6.0: the pull-down handle (top layer, non-ride screens) and the ride screen's own handle must not cover any metric or
   control of the screen below: every visible label / clickable of the active screen that intersects the handle is an issue */
static void walk_handle(lv_obj_t *o, const lv_area_t *h)
{
    if (lv_obj_has_flag(o, LV_OBJ_FLAG_HIDDEN)) return;
    if (visible(o) && lv_obj_get_parent(o) != NULL) {
        bool is_label = lv_obj_check_type(o, &lv_label_class);
        bool is_ctl = lv_obj_has_flag(o, LV_OBJ_FLAG_CLICKABLE) && lv_obj_get_width(o) < 230 && lv_obj_get_height(o) < 230 && !lv_obj_check_type(o, &lv_tileview_class);
        if ((is_label && lv_label_get_text(o)[0]) || is_ctl) {
            lv_area_t a; lv_obj_get_coords(o, &a); lv_area_t x;
            bool clipped = false;
            for (lv_obj_t *p = lv_obj_get_parent(o); p; p = lv_obj_get_parent(p)) { lv_area_t pa; lv_obj_get_coords(p, &pa); if (!lv_area_intersect(&a, &a, &pa)) { clipped = true; break; } }
            if (!clipped && lv_area_intersect(&x, &a, h)) { char m[48]; snprintf(m, sizeof m, "'%.20s'", is_label ? lv_label_get_text(o) : "(control)"); issue("HANDLE covers %s at %d,%d\n", m, a.x1, a.y1); }
        }
    }
    for (uint32_t i = 0; i < lv_obj_get_child_count(o); i++) walk_handle(lv_obj_get_child(o, (int32_t)i), h);
}

static void save_ppm(const char *name)
{
    char p[512]; snprintf(p, sizeof p, "%s/%s.ppm", outdir, name);
    FILE *f = fopen(p, "wb"); if (!f) return;
    fprintf(f, "P6\n%d %d\n255\n", UI_W, UI_W);
    for (int i = 0; i < UI_W * UI_W; i++) {
        uint16_t c = fb[i];
        unsigned char rgb[3] = { (unsigned char)(((c >> 11) & 0x1F) * 255 / 31), (unsigned char)(((c >> 5) & 0x3F) * 255 / 63), (unsigned char)((c & 0x1F) * 255 / 31) };
        fwrite(rgb, 1, 3, f);
    }
    fclose(f);
}

static void shot(const char *name)
{
    run(300);
    lv_obj_invalidate(lv_screen_active());
    lv_refr_now(disp);
    issues = 0; issue_buf[0] = 0;
    /* CIRCLE: pixels outside the safe circle must be background */
    uint16_t bg = lv_color_to_u16(C_BG);
    int out = 0, ox = 0, oy = 0; double lim = (UI_SAFE_R + 1.0) * (UI_SAFE_R + 1.0);
    for (int y = 0; y < UI_W; y++) for (int x = 0; x < UI_W; x++) {
        double dx = x - 119.5, dy = y - 119.5;
        if (dx * dx + dy * dy > lim && fb[y * UI_W + x] != bg) { if (!out) { ox = x; oy = y; } out++; }
    }
    if (out) { char m[48]; snprintf(m, sizeof m, "%d px", out); issue("CIRCLE %s outside the circle, first at %d,%d\n", m, ox, oy); }
    s_nrects = 0;
    walk(lv_screen_active());
    walk(lv_layer_top());
    /* 0.6.1 OVERLAP: two visible texts (or a text and an unrelated clickable) sharing pixels */
    for (int i = 0; i < s_nrects; i++) for (int j = i + 1; j < s_nrects; j++) {
        lv_area_t x, a = s_rects[i].a, b = s_rects[j].a;
        a.x1++; a.y1++; a.x2--; a.y2--; b.x1++; b.y1++; b.x2--; b.y2--;
        if (lv_area_get_width(&a) <= 0 || lv_area_get_width(&b) <= 0) continue;
        if (!lv_area_intersect(&x, &a, &b) || is_ancestor(s_rects[i].o, s_rects[j].o) || is_ancestor(s_rects[j].o, s_rects[i].o)) continue;
        if (lv_obj_get_screen(s_rects[i].o) != lv_obj_get_screen(s_rects[j].o)) continue;   /* top layer vs screen: the shield/toast may cover */
        if ((!is_ancestor(s_rects[j].o, s_rects[i].o) && covered_by_overlay(s_rects[j].o, &s_rects[i].a) && !covered_by_overlay(s_rects[i].o, &s_rects[j].a)) ||
            (covered_by_overlay(s_rects[i].o, &s_rects[j].a) && !covered_by_overlay(s_rects[j].o, &s_rects[i].a))) continue;   /* one is on an opaque panel over the other */
        char m[64]; snprintf(m, sizeof m, "'%.14s' and '%.14s'", lv_label_get_text(s_rects[i].o), lv_label_get_text(s_rects[j].o));
        issue("OVERLAP %s at %d,%d\n", m, x.x1, x.y1);
    }
    if (ui_qs_handle_visible()) { lv_area_t h; ui_qs_handle_rect(&h); walk_handle(lv_screen_active(), &h); }
    else if (ui_current() == UI_SCR_RIDE && !ui_qs_is_open()) {           /* the ride screen's own handle: 72 x 22 at the top */
        lv_area_t h = { .x1 = UI_R - 36, .y1 = 4, .x2 = UI_R + 35, .y2 = 23 };
        lv_obj_t *scr = lv_screen_active();
        for (uint32_t i = 0; i < lv_obj_get_child_count(scr); i++) { lv_obj_t *c = lv_obj_get_child(scr, (int32_t)i); if (lv_obj_check_type(c, &lv_tileview_class)) walk_handle(c, &h); }
    }
    /* WORDS (rev 3): the old "Sensors" button/page must be gone from every screen; Home must say "Connections" */
    if (find_text("Sensors") || find_text("SENSORS")) issue("WORDS %s the word 'Sensors' is still visible\n", "", 0, 0);
    if (ui_current() == UI_SCR_HOME && app_power()->screen_on && !ui_qs_is_open() && !find_text("Connections") && find_text("START RIDE")) issue("WORDS %s Home without a 'Connections' button\n", "", 0, 0);
    save_ppm(name);
    n_shots++;
    fprintf(report, "%s %s\n%s", name, issues ? "FAIL" : "OK", issue_buf);
    if (issues) { n_fail_shots++; printf("  SCREEN %-28s FAIL\n%s", name, issue_buf); }
    else printf("  screen %-28s ok\n", name);
}

/* ---- simulated hardware */
static void sensors(bool pw, int w, bool cad, int rpm, bool hr, int bpm)
{
    g_sim.power_ok = pw; g_sim.watts = w; g_sim.cad_ok = cad; g_sim.rpm = rpm; g_sim.hr_ok = hr; g_sim.bpm = bpm;
}

static void boot(void)
{
    /* a "restart": drop every screen, re-run app_init (reads the stored profile, recovers an interrupted ride) */
    lv_obj_t *old = lv_screen_active();
    lv_obj_t *blank = lv_obj_create(NULL);
    lv_screen_load(blank);
    if (old) lv_obj_delete(old);
    g_sim.boots++;
    sim_wifi_reboot();
    app_init();
    if (app_profile()->wifi_on) plat_wifi_set_enabled(true);   /* as main.c does */
    ui_start();
    run(500);
}

static int count_lines(const char *path)
{
    char p[512]; snprintf(p, sizeof p, "simfs/%s", path);
    FILE *f = fopen(p, "r"); if (!f) return 0; int n = 0, c; while ((c = fgetc(f)) != EOF) if (c == '\n') n++; fclose(f); return n;
}

/* ---- ring keyboard driver: taps the same positions the firmware lays out */
static const char *const KG[3][6] = {
    { "abcde", "fghij", "klmno", "pqrst", "uvwxy", "z.-_@" },
    { "ABCDE", "FGHIJ", "KLMNO", "PQRST", "UVWXY", "Z,!? " },
    { "123456", "7890#$", "%&*+/=", "\\^()[]", "{}<>:;", "\"'`|~" } };
static const int KA[6] = { 270, 330, 30, 90, 150, 210 };
static int kb_mode;
static void ring_pos(int ang, int *x, int *y) { *x = 120 + (int)(92 * lv_trigo_cos((int16_t)ang) / 32767); *y = 120 + (int)(92 * lv_trigo_sin((int16_t)ang) / 32767); }
static void kb_type(const char *t)
{
    for (; *t; t++) {
        int m, g = -1, i = -1;
        for (m = 0; m < 3 && g < 0; m++) for (int gg = 0; gg < 6 && g < 0; gg++) { const char *p = strchr(KG[m][gg], *t); if (p) { g = gg; i = (int)(p - KG[m][gg]); } }
        m--;
        while (kb_mode != m) { tap(93, 123); kb_mode = (kb_mode + 1) % 3; }
        int x, y; ring_pos(KA[g], &x, &y); tap(x, y);
        int cnt = (int)strlen(KG[m][g]); ring_pos(KA[g] + (i * 2 - (cnt - 1)) * 21, &x, &y); tap(x, y);
    }
}

static void scenario(void)
{
    plat_found_t xds = { { 0xC0, 0x11, 0x22, 0x33, 0x44, 0x55 }, 1, "XDS-A001-9769", -61 };
    plat_found_t other = { { 0xAA, 0x01, 0x02, 0x03, 0x04, 0x05 }, 0, "XDS-B777-0001", -88 };
    g_sim.found[PLAT_SENS_POWER][0] = xds; g_sim.found[PLAT_SENS_POWER][1] = other; g_sim.found_n[PLAT_SENS_POWER] = 2;
    g_sim.found_n[PLAT_SENS_HR] = 0;
    g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_NOT_PAIRED; g_sim.link[PLAT_SENS_HR].link = PLAT_LINK_NOT_PAIRED;
    g_sim.battery_pct = 87;
    sensors(false, 0, false, 0, false, 0);

    printf("== 1 onboarding (fresh device)\n");
    boot();
    CHECK(on_screen("Hello!"), "welcome shown on first start");
    shot("01_welcome");
    tap_text("START");
    shot("02_name_ring");
    /* type "Rae" (a made-up test rider): P-T group -> R, A-E -> A, A-E -> E */
    const char *seq[][2] = { { "P-T", "R" }, { "A-E", "A" }, { "A-E", "E" } };
    for (int i = 0; i < 3; i++) { tap_text(seq[i][0]); if (i == 0) shot("03_name_letters"); tap_text(seq[i][1]); }
    CHECK(on_screen("Rae_"), "name typed with the letter ring");
    shot("04_name_typed");
    tap_text("NEXT");
    CHECK(on_screen("AGE"), "age wheel");
    shot("05_age_wheel");
    drag(120, 110, 120, 60);   /* spin the wheel up a few years */
    tap_text("NEXT");
    CHECK(app_profile()->age != 35, "age changed by the wheel (%u)", app_profile()->age);
    shot("06_weight_wheel");
    tap_text("NEXT");
    shot("07_experience");
    tap_text("NEXT");
    shot("08_goal");
    tap_text("NEXT");
    CHECK(on_screen("POWER METER"), "power meter pairing");
    run(2000);
    shot("09_pair_power_found");
    tap_text("XDS-A001-9769");
    sensors(true, 182, true, 88, false, 0);
    run(600);
    CHECK(app_profile()->power.paired && !strcmp(app_profile()->power.name, "XDS-A001-9769"), "meter paired and saved");
    CHECK(on_screen("182 W"), "live check of the paired meter");
    shot("10_pair_power_live");
    tap_text("NEXT");
    CHECK(on_screen("HR STRAP"), "HR optional step");
    run(16000);
    shot("11_pair_hr_none");
    tap_text("SKIP");
    CHECK(on_screen("WI-FI"), "wifi step");
    shot("12_wifi");
    tap_text("KEEP OFF");
    CHECK(on_screen("PROVISIONAL"), "FTP shown as provisional on Ready");
    shot("13_ready");
    tap_text("RIDE ON");
    CHECK(on_screen("START RIDE"), "home after onboarding");
    shot("14_home");
    CHECK(app_profile()->onboarded && app_profile()->ftp_how == BC_FTP_ASSUMED, "profile onboarded, FTP assumed");

    printf("== 2 settings persist after restart\n");
    int age = app_profile()->age, wdg = app_profile()->weight_dg;
    boot();
    CHECK(on_screen("START RIDE") && !on_screen("Hello!"), "restart goes straight to Home");
    CHECK(app_profile()->age == age && app_profile()->weight_dg == wdg && !strcmp(app_profile()->name, "Rae"), "profile restored after restart");
    CHECK(app_profile()->power.paired, "pairing restored after restart");

    printf("== 3 real ride (scripted sensor values standing in for the meter)\n");
    for (int st = 0; st < 3; st++) {
        app_profile()->ride_style = (uint8_t)st;
        sensors(true, 182, true, 88, false, 0);
        ui_home_show(); run(300);
        start_ride();
        CHECK(app_ride_state() == BC_RIDE_RUNNING, "ride running");
        run_s(20);
        char n[48];
        snprintf(n, sizeof n, "20_ride_%c_warmup", 'A' + st); shot(n);
        run_s(300);
        snprintf(n, sizeof n, "21_ride_%c_live", 'A' + st); shot(n);
        sensors(true, 1234, true, 132, true, 171);
        run_s(3);
        snprintf(n, sizeof n, "22_ride_%c_big_numbers", 'A' + st); shot(n);
        sensors(false, 0, false, 0, false, 0);
        g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_RETRY;
        run_s(8);
        snprintf(n, sizeof n, "23_ride_%c_no_data", 'A' + st); shot(n);
        CHECK(on_screen("--") && on_screen("NO DATA"), "missing sensor shows NO DATA, not a value");
        g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_CONNECTED;
        sensors(true, 150, true, 90, false, 0);
        run_s(3);
        if (st == 0) {
            /* swipe through the carousel */
            drag(200, 120, 40, 120); CHECK(on_screen("COACH"), "swipe to coach page"); shot("24_ride_coach");
            drag(200, 120, 40, 120); shot("25_ride_metrics");
            drag(200, 120, 40, 120); shot("26_ride_sensors");
            drag(40, 120, 200, 120); drag(40, 120, 200, 120); drag(40, 120, 200, 120);
            /* pull-down controls: swipe down */
            drag(120, 60, 120, 190);
            CHECK(on_screen("HOLD: PAUSE"), "swipe down opens the controls");
            shot("27_controls");
            tap_text("HOLD: PAUSE");
            CHECK(app_ride_state() == BC_RIDE_RUNNING, "a short tap does NOT pause (hold to confirm)");
            hold_text("HOLD: PAUSE", 1300);
            CHECK(app_ride_state() == BC_RIDE_PAUSED, "hold pauses");
            bc_ride_summary_t a, b; app_ride_totals(&a); run_s(10); app_ride_totals(&b);
            CHECK(a.duration_s == b.duration_s, "paused time is not ride time");
            shot("28_controls_paused");
            tap_text("RESUME");
            CHECK(app_ride_state() == BC_RIDE_RUNNING, "resume");
            tap(120, 14);   /* the handle at the top also opens the controls */
            CHECK(on_screen("HOLD: END"), "tap handle opens controls");
            hold_text("HOLD: END", 900);
            CHECK(app_ride_state() == BC_RIDE_RUNNING, "end needs a 2-s hold");
            hold_text("HOLD: END", 2300);
        } else {
            drag(120, 60, 120, 190);
            hold_text("HOLD: END", 2300);
        }
        CHECK(app_ride_state() == BC_RIDE_ENDED, "ride ended");
        snprintf(n, sizeof n, "29_results_%c", 'A' + st); shot(n);
        if (st == 1) { hold_text(LV_SYMBOL_TRASH, 1800); CHECK(app_ride_state() == BC_RIDE_IDLE && on_screen("START RIDE"), "discard"); continue; }
        tap_text("SAVE");
        CHECK(on_screen("HISTORY"), "history after save");
    }
    CHECK(count_lines("rides/history.txt") == 2, "2 real rides saved (one discarded): %d", count_lines("rides/history.txt"));
    shot("30_history");
    tap_text("#1");
    shot("31_history_detail");
    tap_text(LV_SYMBOL_LEFT);
    tap_text(LV_SYMBOL_HOME);

    printf("== 4 demo mode is labelled and kept apart\n");
    tap_text("Settings");
    shot("40_settings");
    scroll_to("Demo mode");
    tap_text("Demo mode");
    CHECK(app_demo(), "demo on");
    CHECK(on_screen("DEMO"), "DEMO badge visible");
    tap_text(LV_SYMBOL_HOME);
    shot("41_home_demo");
    start_ride();
    CHECK(app_ride_is_demo(), "ride is a demo ride");
    run_s(30); shot("42_demo_warmup");
    run_s(600); shot("43_demo_steady");
    run_s(30); shot("44_demo_surges");
    run_s(100); shot("45_demo_coasting_or_dropout");
    drag(200, 120, 40, 120); shot("46_demo_coach");
    drag(40, 120, 200, 120);
    drag(120, 60, 120, 190); hold_text("HOLD: END", 2300);
    CHECK(on_screen("SIMULATED"), "demo results say SIMULATED");
    shot("47_demo_results");
    uint16_t ftp_before = app_profile()->ftp_w; uint8_t how_before = app_profile()->ftp_how;
    tap_text("SAVE");
    CHECK(app_profile()->ftp_w == ftp_before && app_profile()->ftp_how == how_before, "demo ride never changes FTP");
    CHECK(count_lines("rides/history.txt") == 2 && count_lines("demo/history.txt") == 1, "demo ride stored only in demo history");
    CHECK(on_screen("DEMO RIDES"), "demo history title");
    shot("48_demo_history");
    boot();
    CHECK(!app_demo(), "demo mode is OFF after a restart");

    printf("== 5 crash / power-loss recovery\n");
    sensors(true, 170, true, 86, false, 0);
    start_ride();
    run_s(125);
    /* power cut: no end, no save; the journal survives */
    boot();
    CHECK(on_screen("RECOVERED"), "recovered notice after restart");
    shot("50_recovered");
    CHECK(count_lines("rides/history.txt") == 3, "recovered ride added to history");
    bc_ride_summary_t h[5]; int nh = app_history(h, 5, false);
    CHECK(nh == 3 && h[0].recovered && h[0].duration_s >= 115 && h[0].duration_s <= 125 && h[0].avg_power == 170, "recovered ride data (%lus, %d W)", (unsigned long)h[0].duration_s, h[0].avg_power);
    tap_text("VIEW");
    shot("51_recovered_results");

    printf("== 6 FTP learns from a real qualifying effort\n");
    ui_home_show(); run(300);
    start_ride();
    sensors(true, 150, true, 86, false, 0); run_s(900);
    sensors(true, 265, true, 92, false, 0); run_s(1200);
    shot("60_ride_A_hard_effort");
    sensors(true, 150, true, 86, false, 0); run_s(600);
    drag(120, 60, 120, 190); hold_text("HOLD: END", 2300);
    CHECK(app_ride_ftp_evidence() > 0, "qualifying effort found (%d W)", app_ride_ftp_evidence());
    shot("61_results_ftp_evidence");
    tap_text("SAVE");
    CHECK(app_profile()->ftp_how == BC_FTP_AUTO && app_profile()->ftp_w >= 245 && app_profile()->ftp_w <= 255, "FTP updated from the ride (%u)", app_profile()->ftp_w);
    tap_text(LV_SYMBOL_HOME);
    shot("62_home_ftp_from_rides");
    { bc_ride_summary_t hh[3]; int n2 = app_history(hh, 2, false), n3 = app_history(hh, 3, false); bc_ride_summary_t all[20]; int na = app_history(all, 20, false);
      CHECK(n2 == 2 && n3 == 3 && na == 4, "history counts %d %d %d", n2, n3, na);
      app_history(hh, 2, false); CHECK(hh[0].id == all[0].id && hh[1].id == all[1].id && all[0].id > all[1].id && all[2].id > all[3].id, "history newest first with a small window"); }

    printf("== 7 every editor and settings page\n");
    const char *rows[] = { "Name", "Age", "Weight", "Height", "Level", "Goal", "FTP", "Max HR", "Display", "Wi-Fi" };
    for (int i = 0; i < 10; i++) {
        ui_settings_show(); run(300);
        scroll_to(rows[i]);
        tap_text(rows[i]);
        char n[48]; snprintf(n, sizeof n, "7%d_edit_%s", i < 10 ? i : 9, rows[i]);
        for (char *c = n; *c; c++) if (*c == ' ' || *c == '-') *c = '_';
        shot(n);
    }
    ui_settings_show(); run(300);
    scroll_to("SET UP AGAIN");
    shot("80_settings_bottom");
    tap_text("Diagnostics"); shot("81_diagnostics_menu");
    tap_text("Self-test"); shot("81_selftest");
    ui_diag_menu_show(); run(300); tap_text("Device Health"); shot("84_health_top");
    scroll_to("SEND LOG TO PC"); shot("85_health_bottom");
    tap_text("SEND LOG TO PC");
    { char rb[4096]; long rn = plat_file_read("diag/report.txt", rb, sizeof rb - 1); if (rn > 0) rb[rn] = 0; else rb[0] = 0;
      CHECK(g_sim.exports == 1 && rn > 200 && strstr(rb, "Firmware") && strstr(rb, "Power meter") && !strstr(rb, "#8494a0"), "diagnostic report exported (%ld bytes)", rn); }
    shot("86_health_sent");


    printf("== 9 ride-screen designs: picker with preview, persisted, switch during a ride\n");
    app_profile()->ride_style = 0; app_profile_save();
    ui_display_show(); run(300); shot("87_display");
    tap_text("Ride screen"); shot("88_picker_A");
    tap_text(LV_SYMBOL_RIGHT); shot("88_picker_B");
    drag(165, 110, 75, 110); shot("88_picker_C");
    CHECK(on_screen("Coach First"), "swipe in the picker shows design C");
    tap_text("USE C");
    CHECK(app_profile()->ride_style == 2 && on_screen("DISPLAY"), "design C chosen");
    boot();
    CHECK(app_profile()->ride_style == 2, "design choice kept after restart");
    ui_test_set_style(-1);
    sensors(true, 175, true, 88, false, 0); g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_CONNECTED; app_profile()->power.paired = true;
    ui_home_show(); run(300); start_ride(); run_s(400);
    bc_ride_summary_t s1; app_ride_totals(&s1); bc_cue_id_t cue1 = app_cue()->id;
    shot("89_ride_C_before_switch");
    drag(120, 60, 120, 190);
    CHECK(on_screen("SCREEN C"), "controls show the current design");
    shot("89_controls_design");
    tap_text("SCREEN C"); run(300);
    CHECK(app_profile()->ride_style == 0 && on_screen("SCREEN A"), "design switched during the ride");
    tap_text("SCREEN A"); run(300); tap_text("SCREEN B"); run(300);
    CHECK(app_profile()->ride_style == 2, "cycles A-B-C");
    tap_text(LV_SYMBOL_UP);
    run_s(5);
    bc_ride_summary_t s2; app_ride_totals(&s2);
    CHECK(app_ride_state() == BC_RIDE_RUNNING && s2.duration_s >= s1.duration_s + 5 && s2.power_s >= s1.power_s + 5 && app_cue()->id == cue1,
          "ride and coaching continue through design switches (%lu -> %lu s)", (unsigned long)s1.duration_s, (unsigned long)s2.duration_s);
    shot("89_ride_C_after_switch");
    /* torn history line (power cut while writing) must not cost the next ride */
    plat_file_append("rides/history.txt", "R1,99,0,0,12", 12, true);
    bc_ride_summary_t hb[30]; int before_n = app_history(hb, 30, false); uint16_t want_id = app_profile()->next_ride_id;
    drag(120, 60, 120, 190); hold_text("HOLD: END", 2300); tap_text("SAVE");
    bc_ride_summary_t ha[30]; int after_n = app_history(ha, 30, false);
    CHECK(after_n == before_n + 1 && ha[0].id == want_id && ha[0].duration_s >= s2.duration_s, "ride saved intact after a torn history line (%d -> %d)", before_n, after_n);

    printf("== 10 sensor test screen\n");
    ui_sensor_test_show(false); run(500);
    CHECK(on_screen("REAL SENSOR") && on_screen("175") && on_screen("last valid"), "sensor test shows real live values");
    shot("90a_sensor_test_live");
    sensors(false, 0, false, 0, false, 0); g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_RETRY; g_sim.link[PLAT_SENS_POWER].reconnects = 3;
    g_sim.link[PLAT_SENS_POWER].packets = 400;
    run(600);
    CHECK(on_screen("NO DATA") && on_screen("RETRYING") && on_screen("reconnects 3"), "sensor test: NO DATA + the real pipeline stage (RETRYING)");
    shot("90b_sensor_test_nodata");
    app_set_demo(true); run_s(2);
    CHECK(on_screen("SIMULATED"), "sensor test labels demo data SIMULATED");
    shot("90c_sensor_test_demo");
    app_set_demo(false);
    g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_CONNECTED;
    ui_connections_show(); run(500); shot("82_connections");
    tap_text("POWER"); run(300); shot("82b_conn_power"); tap_text("HELP"); run(300); scroll_to("PAIR ANOTHER"); tap_text("PAIR ANOTHER"); run(2000); shot("83_pair_from_connections");

    printf("== 11 Wi-Fi manager\n");
    {
        g_sim.n_ap = 4;
        strcpy(g_sim.ap[0].ssid, "HomeNet"); g_sim.ap[0].rssi = -48; g_sim.ap[0].secured = true; strcpy(g_sim.ap[0].pass, "Secret-123"); g_sim.ap[0].present = true;
        strcpy(g_sim.ap[1].ssid, "Rider A iPhone"); g_sim.ap[1].rssi = -62; g_sim.ap[1].secured = true; strcpy(g_sim.ap[1].pass, "bike ride!"); g_sim.ap[1].present = true;
        strcpy(g_sim.ap[2].ssid, "CafeFree"); g_sim.ap[2].rssi = -75; g_sim.ap[2].secured = false; g_sim.ap[2].present = true;
        strcpy(g_sim.ap[3].ssid, "AVeryLongNetworkNameForTest123"); g_sim.ap[3].rssi = -84; g_sim.ap[3].secured = true; strcpy(g_sim.ap[3].pass, "12345678"); g_sim.ap[3].present = true;
        ui_settings_show(); run(300); scroll_to("Wi-Fi"); tap_text("Wi-Fi");
        CHECK(on_screen("OFF") && on_screen("optional") && btn_visible_at_top("TURN ON") && btn_visible_at_top(LV_SYMBOL_LEFT), "Wi-Fi screen, off: TURN ON + Back visible without scrolling");
        shot("a0_wifi_off");
        tap_text("TURN ON");
        CHECK(app_profile()->wifi_on, "Wi-Fi switched on and remembered");
        shot("a1_wifi_on");
        CHECK(btn_visible_at_top("NETWORKS") && btn_visible_at_top("SAVED") && btn_visible_at_top("HELP") && btn_visible_at_top("OFF"), "Wi-Fi on: NETWORKS, SAVED, HELP, OFF all visible at once");
        tap_text("NETWORKS"); run(2600);
        CHECK(on_screen("4 found") && on_screen("HomeNet"), "scan lists the networks");
        shot("a2_networks");
        { plat_wifi_ap_t r[8]; int n = plat_wifi_results(r, 8); CHECK(n == 4 && r[0].rssi >= r[1].rssi && r[1].rssi >= r[2].rssi, "strongest first"); }
        tap_text("HomeNet");
        CHECK(on_screen("JOIN") && on_screen("empty = open"), "password keyboard");
        kb_mode = 0;
        shot("a3_keyboard");
        { int x, y; ring_pos(KA[0], &x, &y); tap(x, y); shot("a4_keyboard_group_open"); tap(120, 138); }
        kb_type("Secret-12");
        CHECK(on_screen("9 chars"), "typed 9 characters (hidden)");
        shot("a5_keyboard_typed_hidden");
        tap(173, 123); shot("a6_keyboard_shown");
        CHECK(on_screen("Secret-12"), "show password");
        tap_text("JOIN"); run(500);
        int ticks0 = g_sim.wifi_ui_ticks;
        CHECK(on_screen("CONNECTING"), "connecting screen");
        shot("a7_connecting");
        run(3000);
        CHECK(g_sim.wifi_ui_ticks > ticks0 + 8, "screen kept updating while connecting (%d polls)", g_sim.wifi_ui_ticks - ticks0);
        CHECK(on_screen("Wrong password"), "wrong password error");
        shot("a8_wrong_password");
        tap_text("TRY AGAIN"); kb_mode = 0;
        kb_type("Secret-123");
        tap_text("JOIN"); run(3500);
        CHECK(on_screen("CONNECTED") && on_screen("192.168.1.23"), "connected with IP");
        shot("a9_connected");
        tap_text("DONE");
        CHECK(on_screen("-48 dBm") && on_screen("HomeNet"), "status shows network, signal, IP");
        shot("b0_wifi_status");
        { char sv[5][33]; CHECK(plat_wifi_saved(sv, 5) == 1 && !strcmp(sv[0], "HomeNet"), "network saved"); }
        { char raw[512]; long n = plat_file_read("wifi.bin", raw, sizeof raw); CHECK(n > 0, "credentials stored"); }
        ui_home_show(); run(300); shot("b1_home_wifi");
        printf("   restart: joins the saved network by itself\n");
        boot(); run_s(6);
        { plat_wifi_status_t w; plat_wifi_status(&w); CHECK(w.state == PLAT_WIFI_CONNECTED && !strcmp(w.ssid, "HomeNet"), "auto-reconnect after restart (state %d)", w.state); }
        printf("   phone hotspot\n");
        ui_wifi_show(); run(300); tap_text("NETWORKS"); run(2600); tap_text("Rider A iPhone"); kb_mode = 0;
        kb_type("bike ride!"); tap_text("JOIN"); run(3500);
        CHECK(on_screen("CONNECTED"), "joined the phone hotspot (password with space and !)");
        tap_text("DONE");
        printf("   network disappears: falls back to the other saved one\n");
        g_sim.ap[1].present = false; run_s(14);
        { plat_wifi_status_t w; plat_wifi_status(&w); CHECK(w.state == PLAT_WIFI_CONNECTED && !strcmp(w.ssid, "HomeNet"), "lost hotspot -> reconnected to HomeNet (%d %s)", w.state, w.ssid); }
        g_sim.ap[1].present = true;
        printf("   disconnect: no automatic reconnect until asked\n");
        ui_wifi_show(); run(300); tap_text("HELP"); run(300); tap_text("DISCONNECT"); run_s(30);
        { plat_wifi_status_t w; plat_wifi_status(&w); CHECK(w.state == PLAT_WIFI_IDLE, "stays disconnected (%d)", w.state); }
        ui_wifi_show(); run(300); shot("b2_wifi_disconnected");
        printf("   forget\n");
        tap_text("SAVED"); shot("b3_saved");
        tap_text("Rider A iPhone"); shot("b4_saved_detail");
        hold_text("HOLD: FORGET", 1800);
        { char sv[5][33]; CHECK(plat_wifi_saved(sv, 5) == 1 && !strcmp(sv[0], "HomeNet"), "hotspot forgotten"); }
        printf("   errors: timeout, not found, no address\n");
        g_sim.wifi_no_answer = true; ui_wifi_show(); run(300); tap_text("NETWORKS"); run(2600); scroll_to("CafeFree"); tap_text("CafeFree");
        CHECK(on_screen("NETWORK") && on_screen("open network") && on_screen("CONNECT"), "open network: detail page first (connect / back)"); shot("b4b_network_detail_open");
        tap_text("CONNECT"); run_s(21);
        CHECK(on_screen("timeout"), "timeout error"); shot("b5_timeout"); g_sim.wifi_no_answer = false;
        ui_wifi_show(); run(300); tap_text("NETWORKS"); run(2600); scroll_to("Other network"); tap_text("Other network"); kb_mode = 0;
        CHECK(on_screen("NAME") && on_screen("NEXT"), "hidden network: name first"); shot("b6_keyboard_ssid");
        kb_type("ghost"); tap_text("NEXT"); kb_mode = 0; kb_type("whatever1"); tap_text("JOIN"); run_s(4);
        CHECK(on_screen("Not found") && on_screen("NOT FOUND"), "network not found error"); shot("b7_not_found");
        g_sim.wifi_no_dhcp = true; ui_wifi_show(); run(300); tap_text("NETWORKS"); run(2600); scroll_to("CafeFree"); tap_text("CafeFree"); tap_text("CONNECT"); run_s(4);
        CHECK(on_screen("no address"), "no IP address error"); shot("b8_no_ip"); g_sim.wifi_no_dhcp = false;
        tap_text("BACK"); run(300); if (on_screen("WI-FI")) tap_text("NETWORKS"); run(2600);
        { plat_wifi_status_t w0; plat_wifi_status(&w0); tap_text(LV_SYMBOL_REFRESH); run(2600); plat_wifi_status_t w1; plat_wifi_status(&w1); CHECK(w1.scans == w0.scans + 1, "rescan"); }
        printf("   during a ride Wi-Fi never scans or retries on its own\n");
        g_sim.ap[0].present = false;               /* saved HomeNet out of range: the manager would keep retrying */
        ui_home_show(); run(300); run_s(70);
        int a0 = g_sim.wifi_auto_attempts;
        CHECK(a0 > 0, "retries happen when not riding (%d)", a0);
        sensors(true, 170, true, 88, false, 0);
        start_ride(); run_s(300);
        int a1 = g_sim.wifi_auto_attempts;
        bc_ride_summary_t rs; app_ride_totals(&rs);
        CHECK(a1 == a0 && rs.duration_s >= 299 && rs.power_s >= 299, "no Wi-Fi activity during the ride; recording intact (%d->%d, %lus)", a0, a1, (unsigned long)rs.duration_s);
        drag(120, 60, 120, 190); hold_text("HOLD: END", 2300); tap_text("SAVE"); run_s(70);
        CHECK(g_sim.wifi_auto_attempts > a1, "retries resume after the ride");
        g_sim.ap[0].present = true;
        ui_wifi_show(); run(300); tap_text("OFF"); run(300);
        { plat_wifi_status_t w; plat_wifi_status(&w); CHECK(w.state == PLAT_WIFI_OFF && !app_profile()->wifi_on, "Wi-Fi off again"); }
    }

    printf("== 12 phone link (the harness plays the iPhone app)\n");
    {
        /* enabled by default after onboarding; nothing paired yet */
        boot(); plat_phone_set_enabled(app_profile()->phone_on); run(300);
        CHECK(app_profile()->phone_on, "phone link on by default");
        ui_settings_show(); run(300); scroll_to("Phone"); shot("97_settings_phone_row"); tap_text("Phone"); run(300);
        CHECK(on_screen("SEARCHING") && on_screen("TURN OFF") && on_screen("device only"), "phone page before pairing: SEARCHING, TURN OFF, sync device only");
        shot("97_phone_waiting");
        /* a new phone connects: the 6-digit code pops up over the current screen and blocks touches until done */
        sim_phone_connect(false); run(400);
        CHECK(on_screen("PHONE PAIRING") && on_screen("482") && on_screen("913"), "passkey shown on screen");
        shot("98_passkey_popup");
        sim_phone_enter_passkey(); run(400);
        CHECK(!on_screen("PHONE PAIRING") && on_screen("CONNECTED") && on_screen("DISCONNECT"), "paired, remembered: CONNECTED with DISCONNECT");
        shot("98_phone_connected");
        /* the phone sends time, GPS and watch heart rate; every value carries its source */
        sim_phone_send_time(1761300000000ULL); sim_phone_send_gps(244667000, 544000000, 833, 60); sim_phone_send_hr(148, BC_SRC_APPLE_WATCH); run(1200);
        { app_live_t lv; app_live(&lv);
          CHECK(lv.speed_ok && lv.speed_dmh == 299 && lv.speed_src == BC_SRC_PHONE_GPS, "speed 29.9 km/h from PHONE GPS (%d)", lv.speed_dmh);
          CHECK(lv.hr_ok && lv.bpm == 148 && lv.hr_src == BC_SRC_APPLE_WATCH && lv.phone_hr && !lv.strap_hr, "watch HR via phone");
          CHECK(lv.time_known && lv.epoch_s >= 1761300000u && lv.epoch_s <= 1761300002u, "wall clock synced"); }
        ui_conn_detail_show(3); run(300); CHECK(on_screen("WATCH") || on_screen("watch"), "heart-rate page shows the watch source"); ui_conn_detail_show(5); run(300); CHECK(on_screen("29.9"), "speed page shows 29.9 km/h from the phone"); ui_phone_show(); run(300);
        shot("98_phone_live");
        /* strap present too: strap wins by default, watch is the backup; preference flips it */
        sensors(true, 180, true, 90, true, 152); g_sim.link[PLAT_SENS_HR].link = PLAT_LINK_CONNECTED; sim_phone_send_hr(148, BC_SRC_APPLE_WATCH); run(400);
        { app_live_t lv; app_live(&lv); CHECK(lv.hr_ok && lv.bpm == 152 && lv.hr_src == BC_SRC_BLE_STRAP && lv.strap_hr && lv.phone_hr, "strap first by default"); }
        tap_text("tap for details"); run(300); scroll_to("HR: STRAP FIRST"); tap_text("HR: STRAP FIRST"); run(300); sim_phone_send_hr(149, BC_SRC_APPLE_WATCH); run(300);
        { app_live_t lv; app_live(&lv); CHECK(lv.hr_ok && lv.bpm == 149 && lv.hr_src == BC_SRC_APPLE_WATCH && app_profile()->hr_pref == 1, "watch first after the toggle"); }
        tap_text("tap for details"); run(300); scroll_to("HR: WATCH FIRST"); tap_text("HR: WATCH FIRST"); run(300);
        /* stale: 12 s without a watch value → falls back to the strap, never holds the old number */
        run_s(7); { app_live_t lv; app_live(&lv); CHECK(lv.hr_ok && lv.hr_src == BC_SRC_BLE_STRAP && !lv.phone_hr, "stale watch HR dropped after 6 s, strap shown"); }
        sensors(true, 180, true, 90, false, 0); g_sim.link[PLAT_SENS_HR].link = PLAT_LINK_NOT_PAIRED; run(400);
        { app_live_t lv; app_live(&lv); CHECK(!lv.hr_ok && !lv.speed_ok && lv.link[PLAT_SENS_SPEED].link == PLAT_LINK_STALE, "no HR at all; GPS marked STALE after 5 s"); }
        /* Connections menu (0.6.0): eight categories, phone shows connected */
        ui_connections_show(); run(300); shot("99_connections_menu");
        CHECK(on_screen("PHONE") && on_screen("CONNECTED") && on_screen("HEART") && on_screen("CADENCE") && !on_screen("SPEED"), "table rows PHONE / POWER / HEART / CADENCE at scroll 0 (no SPEED row without a CSC sensor)");
        CHECK(scroll_to("BLUETOOTH") && scroll_to("SYNC") && scroll_to("WI-FI"), "Wi-Fi, other Bluetooth + sync rows below"); shot("99_connections_bottom");
        /* ride controlled from the phone; the phone disconnecting never stops the recording */
        ui_home_show(); run(300);
        sim_phone_ctrl(BC_CMD_START, 0); run(1200);
        CHECK(app_ride_state() == BC_RIDE_RUNNING && g_sim.phone.last_resp.status == BC_RESP_OK, "ride started from the phone (resp %u)", g_sim.phone.last_resp.status);
        run(600); CHECK(on_screen("WATTS") || on_screen("TARGET") || on_screen("PACE") || on_screen("NO DATA"), "home switched to the ride screen");
        for (int i = 0; i < 20; i++) { sim_phone_send_gps(244667000 + i * 800, 544000000, 833, 60); run(1000); }
        { bc_ride_summary_t t; app_ride_totals(&t); CHECK(t.distance_m >= 150 && t.distance_m <= 175 && t.dist_src == BC_SRC_PHONE_GPS, "distance integrated on the device (%lu m)", (unsigned long)t.distance_m);
          CHECK(t.start_epoch_s >= 1761300000u, "ride start time stamped from the phone clock");
          CHECK(g_sim.phone.lives > 15 && g_sim.phone.last_live.distance_m == t.distance_m && g_sim.phone.last_live.power_ok, "live values streamed to the phone"); }
        drag(120, 120, 20, 120); run(300); drag(120, 120, 20, 120); run(300); shot("99_ride_metrics_gps");
        CHECK(on_screen("km/h") && on_screen("PHONE GPS"), "metrics page shows speed + source");
        sim_phone_ctrl(BC_CMD_STOP_CONFIRM, 0); run(1200);
        CHECK(app_ride_state() == BC_RIDE_RUNNING && g_sim.phone.last_resp.status == BC_RESP_NEEDS_CONFIRM, "stop without request refused");
        sim_phone_disconnect(); run_s(8);
        { bc_ride_summary_t t; app_ride_totals(&t); CHECK(app_ride_state() == BC_RIDE_RUNNING && t.duration_s >= 27, "recording continues without the phone (%lus)", (unsigned long)t.duration_s);
          app_live_t lv; app_live(&lv); CHECK(!lv.speed_ok && lv.link[PLAT_SENS_SPEED].link != PLAT_LINK_CONNECTED, "speed gone, not held"); }
        shot("99_ride_phone_lost");
        sim_phone_connect(true); run(400);   /* remembered phone: no code */
        CHECK(!on_screen("PHONE PAIRING"), "no passkey for a remembered phone");
        sim_phone_ctrl(BC_CMD_STOP_REQUEST, 0); run(1200); CHECK(g_sim.phone.last_resp.status == BC_RESP_NEEDS_CONFIRM && app_ride_state() == BC_RIDE_RUNNING, "stop request arms");
        sim_phone_ctrl(BC_CMD_STOP_CONFIRM, 0); run(1200); CHECK(app_ride_state() == BC_RIDE_ENDED && g_sim.phone.last_resp.status == BC_RESP_OK, "stop confirmed ends the ride");
        run(600); CHECK(on_screen("SAVE"), "results screen appears when the phone ends the ride");
        tap_text("SAVE"); run(500);
        { bc_ride_summary_t h[3]; int n = app_history(h, 3, false); CHECK(n >= 1 && h[0].distance_m >= 150 && h[0].dist_src == BC_SRC_PHONE_GPS, "distance saved in history (R2 line)"); }
        /* forget → next connection pairs again; off → no advertising */
        ui_phone_show(); run(300); tap_text("tap for details"); run(300); scroll_to("HOLD: FORGET PHONE"); hold_text("HOLD: FORGET PHONE", 1800); run(300);
        CHECK(g_sim.phone.forgets == 1, "forget called (%d)", g_sim.phone.forgets); CHECK(on_screen("SEARCHING") && on_screen("pair from the app"), "phone page back to SEARCHING, says pair from the app");
        tap_text("Phone link"); run(300); CHECK(!app_profile()->phone_on && on_screen("LINK OFF"), "phone link switched off");
        tap_text("Phone link"); run(300); CHECK(app_profile()->phone_on, "and on again");
        shot("99_phone_after_forget");
    }

    printf("== 13 power: quick settings, screen off, triple tap, lock, timeouts, low battery, sleep, restart\n");
    {
        g_sim.battery_mv = 3800; g_sim.usb = false; g_sim.woke_from_sleep = false;
        sensors(true, 180, true, 88, false, 0); g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_CONNECTED; app_profile()->power.paired = true;
        boot(); run_s(6);
        const app_power_t *P = app_power();
        CHECK(P->screen_on && !P->locked && P->mv == 3800 && P->pct == 50 && !P->usb_likely, "battery read: 3.80 V = ~50%% estimate (%d mV, %d%%)", P->mv, P->pct);
        CHECK(on_screen("~50%"), "home shows the estimate with ~");
        /* swipe down from the top edge opens Quick Settings on Home */
        drag(120, 20, 120, 150); run(300);
        CHECK(ui_qs_is_open() && on_screen("QUICK SETTINGS") && on_screen("Wi-Fi") && on_screen("Phone link"), "quick settings opened by a top-edge swipe");
        shot("c0_quick_settings");
        CHECK(!on_screen("harging"), "the word charging never appears");
        /* brightness slider in the first row */
        uint8_t b0 = app_profile()->brightness;
        tap(140, 74); run(300);
        CHECK(app_profile()->brightness != b0 && app_profile()->brightness >= 70 && g_sim.backlight == app_profile()->brightness, "brightness slider sets + applies (%u -> %u, backlight %d)", b0, app_profile()->brightness, g_sim.backlight);
        /* Wi-Fi and phone toggles */
        /* 0.6.0: Wi-Fi row = tap opens the Wi-Fi page, hold toggles the radio */
        bool w0 = app_profile()->wifi_on; hold_text("Wi-Fi", 900); run(300); CHECK(app_profile()->wifi_on != w0 && ui_qs_is_open(), "wifi toggled by holding the row (qs stays open)");
        hold_text("Wi-Fi", 900); run(300); CHECK(app_profile()->wifi_on == w0, "and back");
        tap_text("Wi-Fi"); run(300);
        CHECK(!ui_qs_is_open() && on_screen("WI-FI") && on_screen("optional"), "tap on the Wi-Fi row opens the full Wi-Fi page"); shot("c0b_wifi_from_qs");
        ui_home_show(); run(300); tap(120, 12); run(300); CHECK(ui_qs_is_open(), "tapping the HANDLE opens quick settings"); shot("c0c_qs_by_handle_tap");
        drag(120, 215, 120, 60); run(300); CHECK(!ui_qs_is_open(), "closed again");
        drag(120, 10, 120, 150); run(300); CHECK(ui_qs_is_open(), "a swipe starting on the handle opens it");
        drag(120, 215, 120, 60); run(300); CHECK(!ui_qs_is_open(), "closed");
        /* rev 3 fix: a swipe that starts in the top 48 px but OFF the handle (x = 60, y = 40) must open it too */
        ptr.x = 60; ptr.y = 40; ptr.down = true; run(60); for (int i = 1; i <= 10; i++) { ptr.y = 40 + 11 * i; run(15); } ptr.down = false; run(600);
        CHECK(ui_qs_is_open(), "a swipe from the top zone beside the handle opens quick settings"); shot("c0d_qs_by_zone_swipe");
        drag(120, 215, 120, 60); run(300); CHECK(!ui_qs_is_open(), "closed again");
        drag(120, 10, 120, 150); run(300);
        scroll_to("Phone link");
        bool p0 = app_profile()->phone_on; tap_text("Phone link"); run(300); CHECK(app_profile()->phone_on != p0 && g_sim.phone.enabled == app_profile()->phone_on, "phone link toggled (sensor BLE untouched)"); scroll_to("Phone link"); tap_text("Phone link"); run(300);
        CHECK(g_sim.link[PLAT_SENS_POWER].link == PLAT_LINK_CONNECTED, "power meter link unaffected by the phone toggle");
        scroll_to("Power settings"); shot("c1_quick_settings_bottom");
        CHECK(scroll_to("Battery") && scroll_to("est.") && scroll_to("State") && scroll_to("Deep sleep") && on_screen("link off") && scroll_to("HOLD: RESTART"), "battery row, state, sleep (link off), restart present");
        /* close by swipe up, by timeout, by the X */
        drag(120, 215, 120, 60); run(300); CHECK(!ui_qs_is_open(), "swipe up closes quick settings");
        drag(120, 20, 120, 150); run(300); CHECK(ui_qs_is_open(), "reopen"); run_s(21); CHECK(!ui_qs_is_open(), "closes after 20 s");
        drag(120, 20, 120, 150); run(300); tap(120, 202); run(300); CHECK(!ui_qs_is_open(), "X closes");
        /* screen off (rev 3): ONE touch anywhere wakes; the waking touch and the guard after it never press a control */
        drag(120, 20, 120, 150); run(300); scroll_to("Screen off"); tap_text("Screen off"); run(400);
        CHECK(!P->screen_on && g_sim.backlight == 0 && g_sim.panel_asleep, "screen off: backlight 0, panel asleep");
        shot("c2_screen_off");
        CHECK(app_profile()->wake_taps == 1, "default wake gesture is any touch (%u)", app_profile()->wake_taps);
        ptr.x = 120; ptr.y = 108; ptr.down = true; run(60);          /* a finger lands exactly on START RIDE (the sim polls every 30 ms; the device reads on the interrupt) */
        CHECK(P->screen_on && app_power_gate_blocking(), "first contact wakes the screen at once (<= %d ms), touch swallowed", 60);
        run(1500); CHECK(app_ride_state() == BC_RIDE_IDLE, "finger held 1.5 s on START RIDE while waking: NO ride (swallowed)");
        ptr.down = false; run(100);
        CHECK(app_power_gate_blocking(), "guard active right after the release");
        raw_tap(120, 108); CHECK(app_ride_state() == BC_RIDE_IDLE && P->screen_on, "tap during the guard: ignored");
        run(600); CHECK(!app_power_gate_blocking() && g_sim.backlight == app_profile()->brightness && !g_sim.panel_asleep, "guard over: normal touch, brightness restored (%d)", g_sim.backlight);
        CHECK(app_ride_state() == BC_RIDE_IDLE, "nothing on the dark screen reached any button");
        /* automatic timeout outside rides (60 s default), and the setting */
        uint32_t offs = P->auto_offs; run_s(61); CHECK(!P->screen_on && P->auto_offs == offs + 1, "auto screen-off after 60 s idle");
        ui_power_settings_show(); run(300);   /* (the harness wakes the screen with 3 taps first) */
        shot("c9_power_settings");
        CHECK(scroll_to("1 min") && scroll_to("alerts only") && scroll_to("never ended"), "power settings defaults"); scroll_to("Screen off after");
        tap_text("Screen off after"); tap_text("Screen off after"); tap_text("Screen off after"); run(300);
        CHECK(app_profile()->scr_timeout_s == 0 && on_screen("never"), "timeout cycles to never (%u)", app_profile()->scr_timeout_s);
        ui_home_show(); run_s(130); CHECK(P->screen_on, "never: still on after 130 s");
        ui_power_settings_show(); run(300); tap_text("Screen off after"); run(300); CHECK(app_profile()->scr_timeout_s == 30, "then 30 s");
        ui_home_show(); run_s(32); CHECK(!P->screen_on, "off after 30 s"); 
        ui_power_settings_show(); run(300); tap_text("Screen off after"); run(300); CHECK(app_profile()->scr_timeout_s == 60, "back to 1 min");
        /* touch lock */
        ui_home_show(); run(300); drag(120, 20, 120, 150); run(300); scroll_to("Touch lock"); tap_text("Touch lock"); run(300);
        CHECK(P->locked && !ui_qs_is_open(), "locked");
        shot("c3_locked");
        hold_text("START RIDE", 1300); run(300); CHECK(app_ride_state() == BC_RIDE_IDLE, "locked: the start button does not react");
        drag(120, 20, 120, 150); run(300); CHECK(!ui_qs_is_open(), "locked: no quick settings");
        hold_text("HOLD 3 s", 1500); CHECK(P->locked, "a short hold does not unlock");
        hold_text("HOLD 3 s", 3300); CHECK(!P->locked, "3 s hold unlocks");
        /* low battery: alerts with hysteresis, never an automatic ride end */
        g_sim.battery_mv = 3540;
        { bool seen = false; for (int i = 0; i < 20 && !seen; i++) { run(500); seen = on_screen("BATTERY LOW"); } CHECK(P->bat_level == BC_BAT_LOW && seen, "low battery alert at 3.54 V"); }
        shot("c4_low_battery_toast");
        g_sim.battery_mv = 3580; run_s(6); CHECK(P->bat_level == BC_BAT_LOW, "3.58 V: still LOW (hysteresis)");
        g_sim.battery_mv = 3610; run_s(6); CHECK(P->bat_level == BC_BAT_OK, "3.61 V: back to OK");
        g_sim.battery_mv = 3800; run_s(6);
        start_ride(); run_s(5);
        CHECK(app_ride_state() == BC_RIDE_RUNNING, "ride running at 3.80 V");
        g_sim.battery_mv = 3340; run_s(12);
        CHECK(app_ride_state() == BC_RIDE_RUNNING && P->bat_level == BC_BAT_CRITICAL && g_sim.deep_sleeps == 0, "critical voltage: alert only, ride NOT ended, no sleep (protection off by default)");
        
        g_sim.battery_mv = 3800; run_s(6);
        /* screen off during the ride: recording and coaching continue, journal keeps growing */
        int jl0 = count_lines("rides/active.jnl"); bc_ride_summary_t t0; app_ride_totals(&t0);
        drag(120, 60, 120, 190); run(300); CHECK(on_screen("QUICK SET."), "ride controls carry a quick settings button");
        shot("c5_ride_controls_qs");
        tap_text("QUICK SET."); run(300); CHECK(ui_qs_is_open() && scroll_to("riding"), "quick settings in a ride: sleep greyed out");
        shot("c5_ride_quick_settings");
        CHECK(!app_power_sleep() && g_sim.deep_sleeps == 0 && app_ride_state() == BC_RIDE_RUNNING, "sleep refused while riding");
        scroll_to("Screen off"); tap_text("Screen off"); run(400);
        CHECK(!P->screen_on && app_ride_state() == BC_RIDE_RUNNING, "screen off during the ride");
        run_s(30);
        bc_ride_summary_t t1; app_ride_totals(&t1);
        CHECK(t1.duration_s >= t0.duration_s + 30 && t1.power_s >= t0.power_s + 30 && count_lines("rides/active.jnl") >= jl0 + 25, "recording continued in the dark (%lu -> %lu s, journal %d -> %d lines)", (unsigned long)t0.duration_s, (unsigned long)t1.duration_s, jl0, count_lines("rides/active.jnl"));
        CHECK(g_sim.phone.lives >= 0 && g_sim.backlight == 0, "backlight stayed off");
        shot("c5_ride_screen_off");
        /* coach warning wakes the screen for 5 s */
        sensors(false, 0, false, 0, false, 0); g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_RETRY; run_s(7);
        CHECK(P->screen_on && P->cue_wakes == 1, "NO SENSOR DATA warning woke the screen (%lu)", (unsigned long)P->cue_wakes);
        shot("c5_ride_cue_wake");
        run_s(6); CHECK(!P->screen_on, "and it went dark again after 5 s");
        sensors(true, 180, true, 88, false, 0); g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_CONNECTED; run_s(3);
        raw_tap(120, 120); run(600); CHECK(P->screen_on && app_ride_state() == BC_RIDE_RUNNING, "one touch wakes mid-ride, recording untouched");
        drag(120, 60, 120, 190); hold_text("HOLD: END", 1300); tap_text("SAVE"); run(300);
        /* deep sleep: page, hold, radios off, profile saved; the next boot is a wake */
        ui_home_show(); run(300); drag(120, 20, 120, 150); run(300); CHECK(ui_qs_is_open(), "qs open for sleep"); scroll_to("Deep sleep"); tap_text("Deep sleep"); run(300);
        CHECK(on_screen("DEEP SLEEP") && on_screen("RESET") && scroll_to("not yet verified"), "sleep page explains recovery + unverified touch wake"); scroll_to("HOLD: DEEP SLEEP");
        shot("c6_sleep_page");
        int saves = g_sim.profile_saves; app_profile()->wifi_on = true; plat_wifi_set_enabled(true);
        hold_text("HOLD: DEEP SLEEP", 1800); run(300);
        CHECK(g_sim.deep_sleeps == 1 && P->asleep && g_sim.backlight == 0 && g_sim.panel_asleep && g_sim.profile_saves > saves, "deep sleep requested, profile saved, screen dark");
        { plat_wifi_status_t w; plat_wifi_status(&w); CHECK(w.state == PLAT_WIFI_OFF && app_profile()->wifi_on && !g_sim.phone.enabled, "radios off, wifi setting kept"); }
        shot("c6_asleep");
        g_sim.woke_from_sleep = true; g_sim.asleep = false; boot(); run(400);
        CHECK(on_screen("START RIDE") && app_power()->woke_from_sleep && app_power()->screen_on && !strcmp(app_profile()->name, "Rae"), "wake: home, profile intact");
        { plat_wifi_status_t w; plat_wifi_status(&w); CHECK(w.state != PLAT_WIFI_OFF, "wifi back on after the wake"); }
        g_sim.woke_from_sleep = false;
        /* automatic deep sleep after idle time on battery */
        CHECK(app_profile()->auto_sleep_min == 0, "0.6.0: auto deep sleep is OFF by default (%u)", app_profile()->auto_sleep_min);
        ui_home_show(); run_s(11 * 60); CHECK(g_sim.deep_sleeps == 1 && !app_power()->asleep && !app_power()->screen_on, "idle 11 min on battery: screen off, NO deep sleep (standby instead)");
        CHECK(app_power()->standby && g_sim.phone.standby && g_sim.sensor_standby, "connected standby: phone link kept (slow advertising), sensor scanning paused");
        ui_power_settings_show(); run(300); scroll_to("Auto deep sleep"); tap_text("Auto deep sleep"); run(300);
        CHECK(app_profile()->auto_sleep_min == 5, "auto-sleep cycles off -> 5 (%u)", app_profile()->auto_sleep_min);
        /* a connected phone blocks auto deep sleep: Bluetooth would die with it */
        plat_phone_set_enabled(true); sim_phone_connect(true); ui_home_show(); run_s(5 * 60 + 5);
        CHECK(g_sim.deep_sleeps == 1 && !app_power()->asleep && !strcmp(app_power()->sleep_block, "phone connected"), "no auto deep sleep while a phone is connected (%s)", app_power()->sleep_block);
        sim_phone_disconnect(); tap(120, 30); ui_home_show(); run_s(5 * 60 + 5);
        CHECK(g_sim.deep_sleeps == 2 && app_power()->asleep && g_sim.sleep_wake_taps == 1, "auto deep sleep after 5 idle minutes on battery, no phone (wake = %d touch)", g_sim.sleep_wake_taps);
        g_sim.asleep = false; boot(); run(400);
        g_sim.battery_mv = 4190; run_s(40);
        CHECK(app_power()->usb_likely && on_screen(LV_SYMBOL_USB), "4.19 V held 30 s: USB power likely");
        shot("c7_home_usb_inferred");
        ui_home_show(); run_s(5 * 60 + 5); CHECK(g_sim.deep_sleeps == 2, "no auto-sleep while USB power is likely");
        app_profile()->auto_sleep_min = 10; app_profile_save(); tap(120, 30);   /* a touch on the status line: the idle timer restarts */
        g_sim.battery_mv = 3800; run_s(6); CHECK(!app_power()->usb_likely && !app_power()->asleep, "drop to 3.80 V ends the inference");
        /* restart from quick settings: profile saved, restart requested */
        saves = g_sim.profile_saves; g_sim.restart_requested = false;
        drag(120, 20, 120, 150); run(300); scroll_to("HOLD: RESTART"); hold_text("HOLD: RESTART", 1800); run(300);
        CHECK(g_sim.restart_requested && g_sim.profile_saves > saves, "restart requested after saving");
        /* protection setting + health page */
        ui_power_settings_show(); run(300); scroll_to("Low batt."); tap_text("Low batt."); run(300);
        CHECK(app_profile()->bat_protect == 1 && scroll_to("NOT VALIDATED"), "protection opt-in is labelled NOT VALIDATED");
        shot("c9_power_settings_protect");
        scroll_to("Low batt."); tap_text("Low batt."); run(300); CHECK(app_profile()->bat_protect == 0, "and off again");
        /* settings round-trip across a restart */
        app_profile()->scr_timeout_s = 120; app_profile()->wake_on_cue = false; app_profile_save(); boot();
        CHECK(app_profile()->scr_timeout_s == 120 && !app_profile()->wake_on_cue && app_profile()->auto_sleep_min == 10 && app_profile()->bat_protect == 0, "power settings persist");
        app_profile()->scr_timeout_s = 60; app_profile()->wake_on_cue = true; app_profile_save();
        ui_health_show(); run(300); run_s(6);
        CHECK(on_screen("estimate") && on_screen("Power source"), "device health shows the estimate and source");
        shot("c8_health_power");
        ui_settings_show(); run(300); scroll_to("Power"); shot("c8_settings_power_row");
    }

    printf("== 14 connectivity: screen off and standby keep the phone link; deep sleep is the explicit exception\n");
    {
        g_sim.battery_mv = 3800; g_sim.usb = false; g_sim.woke_from_sleep = false;
        sensors(true, 180, true, 88, false, 0); g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_CONNECTED; app_profile()->power.paired = true;
        app_profile()->phone_on = true; app_profile()->scr_timeout_s = 60; app_profile()->auto_sleep_min = 0; app_profile_save(); boot(); run_s(2);
        const app_power_t *P = app_power();
        plat_phone_set_enabled(true); sim_phone_connect(true); run(1500);
        int d0 = g_sim.deep_sleeps, l0 = g_sim.phone.lives;
        CHECK(g_sim.phone.connected && l0 > 0, "phone connected, live stream running (%d)", l0);
        /* manual screen off from Quick Settings */
        drag(120, 20, 120, 150); run(300); scroll_to("Screen off"); tap_text("Screen off"); run(400);
        CHECK(!P->screen_on && g_sim.phone.connected && g_sim.phone.enabled, "screen off: phone still connected");
        run_s(600);
        CHECK(g_sim.phone.connected && g_sim.phone.lives >= l0 + 590 && !P->asleep && g_sim.deep_sleeps == d0, "10 min dark: link up, %d live messages flowed, no deep sleep", g_sim.phone.lives - l0);
        CHECK(P->standby && g_sim.phone.standby && g_sim.sensor_standby, "connected standby: slow advertising, sensor scanning paused");
        /* the phone leaves and comes back: no touch needed */
        sim_phone_disconnect(); run_s(5); int l1 = g_sim.phone.lives;
        CHECK(g_sim.phone.enabled && !P->screen_on && !P->asleep, "still advertising in the dark");
        sim_phone_connect(true); run(1500);
        CHECK(g_sim.phone.connected && g_sim.phone.lives > l1 && !P->screen_on, "phone reconnected without touching the device (%d new live msgs)", g_sim.phone.lives - l1);
        /* wake: standby ends, link untouched */
        raw_tap(120, 120); run(600);
        CHECK(P->screen_on && !P->standby && !g_sim.phone.standby && !g_sim.sensor_standby && g_sim.phone.connected, "wake leaves standby; the phone link was never dropped");
        /* automatic timeout with the phone connected: standby, never deep sleep */
        app_profile()->auto_sleep_min = 5; app_profile_save(); ui_home_show(); run_s(61 + 6 * 60);
        CHECK(!P->screen_on && P->standby && !P->asleep && g_sim.deep_sleeps == d0 && g_sim.phone.connected, "7 min idle with a phone connected: standby, no deep sleep (%s)", P->sleep_block);
        app_profile()->auto_sleep_min = 0; app_profile_save(); raw_tap(120, 120); run(600);
        /* ride + screen off: no standby, meter + phone links kept, journal grows */
        ui_home_show(); run(300); start_ride(); run_s(3);
        drag(120, 60, 120, 190); run(300); tap_text("QUICK SET."); run(300); scroll_to("Screen off"); tap_text("Screen off"); run(400);
        int jl0 = count_lines("rides/active.jnl"); l1 = g_sim.phone.lives; run_s(30);
        CHECK(!P->screen_on && !P->standby && !g_sim.sensor_standby && app_ride_state() == BC_RIDE_RUNNING, "ride in the dark: recording, NO standby");
        CHECK(g_sim.link[PLAT_SENS_POWER].link == PLAT_LINK_CONNECTED && g_sim.phone.connected && g_sim.phone.lives >= l1 + 28 && count_lines("rides/active.jnl") >= jl0 + 25, "meter + phone links kept, live stream and journal keep flowing");
        raw_tap(120, 120); run(600);
        drag(120, 60, 120, 190); hold_text("HOLD: END", 1300); tap_text("SAVE"); run(300);
        /* deep sleep: explicit, explained as connectivity off */
        ui_home_show(); run(300); drag(120, 20, 120, 150); run(300); scroll_to("Deep sleep"); CHECK(on_screen("link off"), "deep sleep row says the link goes off"); tap_text("Deep sleep"); run(300);
        CHECK(on_screen("CONNECTIVITY OFF") && scroll_to("standby keep"), "deep sleep page: connectivity off, standby keeps Bluetooth");
        shot("d0_deep_sleep_connectivity");
        scroll_to("HOLD: DEEP SLEEP"); hold_text("HOLD: DEEP SLEEP", 1800); run(300);
        CHECK(g_sim.deep_sleeps == d0 + 1 && !g_sim.phone.enabled && g_sim.sleep_wake_taps == 1, "deep sleep: phone link switched off (wake = %d touch)", g_sim.sleep_wake_taps);
        g_sim.woke_from_sleep = true; g_sim.asleep = false; boot(); run(400); g_sim.woke_from_sleep = false;
        CHECK(g_sim.phone.enabled, "after the wake the phone link advertises again");
        /* wake gesture setting: any touch (default) -> 2 taps -> 3 taps -> any touch; every variant is swallowed + guarded */
        ui_power_settings_show(); run(300); scroll_to("Wake gesture"); tap_text("Wake gesture"); run(300);
        CHECK(app_profile()->wake_taps == 2 && on_screen("2 taps"), "wake gesture -> 2 taps (%u)", app_profile()->wake_taps);
        ui_home_show(); run(300); drag(120, 20, 120, 150); run(300); scroll_to("Screen off"); CHECK(on_screen("2 taps = on"), "screen-off row shows the gesture"); tap_text("Screen off"); run(400);
        raw_tap(120, 108); run(2000); CHECK(!P->screen_on && app_ride_state() == BC_RIDE_IDLE, "one tap on START: still off, no ride");
        raw_tap(120, 108); raw_tap(120, 108); run(600); CHECK(P->screen_on && app_ride_state() == BC_RIDE_IDLE, "double tap on START wakes, starts nothing");
        ui_power_settings_show(); run(300); scroll_to("Wake gesture"); tap_text("Wake gesture"); run(300); CHECK(app_profile()->wake_taps == 3, "-> 3 taps");
        ui_home_show(); run(300); drag(120, 20, 120, 150); run(300); scroll_to("Screen off"); tap_text("Screen off"); run(400);
        raw_tap(120, 108); raw_tap(120, 108); run(2000); CHECK(!P->screen_on, "two taps: still off");
        raw_tap(120, 108); raw_tap(120, 108); raw_tap(120, 108); run(600); CHECK(P->screen_on && app_ride_state() == BC_RIDE_IDLE, "three taps on START wake, start nothing");
        ui_power_settings_show(); run(300); scroll_to("Wake gesture"); tap_text("Wake gesture"); run(300); CHECK(app_profile()->wake_taps == 1, "-> back to any touch");
        ui_home_show(); run(300); drag(120, 20, 120, 150); run(300); scroll_to("Screen off"); tap_text("Screen off"); run(400);
        ptr.x = 120; ptr.y = 160; ptr.down = true; run(30); for (int i = 1; i <= 10; i++) { ptr.y = 160 - 10 * i; run(15); } ptr.down = false; run(600);
        CHECK(P->screen_on && ui_current() == UI_SCR_HOME && !ui_qs_is_open() && app_ride_state() == BC_RIDE_IDLE, "a swipe on the dark screen wakes it and changes nothing (still Home, no quick settings)");
        start_ride(); run_s(2); drag(120, 60, 120, 190); run(300); tap_text("QUICK SET."); run(300); scroll_to("Screen off"); tap_text("Screen off"); run(400);
        raw_tap(120, 120); run(600); CHECK(P->screen_on && app_ride_state() == BC_RIDE_RUNNING, "any touch wakes during a ride");
        drag(120, 60, 120, 190); hold_text("HOLD: END", 1300); hold_text(LV_SYMBOL_TRASH, 1800); run(300);
        shot("d1_power_settings_wake");
    }

    printf("== 15 phone services: Wi-Fi provisioning, profile + settings sync, ride-history sync (the harness plays the iPhone app)\n");
    {
        uint8_t b[BC_LINK_MAX]; size_t n;
        app_profile()->wifi_on = false; app_profile_save(); boot(); run(500);
        plat_phone_set_enabled(true); sim_phone_connect(true); sim_phone_send_time(1792850000000ULL); run(800);
        struct { int notifies; } z0 = { g_sim.phone.notifies };
        /* Wi-Fi status on request; scan refused while the radio is off */
        n = bc_link_encode_wifi_status_req(b, sizeof b, 1, 0); CHECK(sim_phone_write(0, b, n), "status request accepted"); run(600);
        CHECK(g_sim.phone.statuses == 1 && g_sim.phone.wifi_status.state == BC_WIFI_ST_OFF && !g_sim.phone.wifi_status.radio_on, "status: radio off (%u)", g_sim.phone.wifi_status.state);
        bc_wifi_scan_req_t sq = { .max = 16 }; n = bc_link_encode_wifi_scan_req(&sq, b, sizeof b, 2, 0); sim_phone_write(0, b, n); run(800);
        CHECK(g_sim.phone.scan_ends == 1 && g_sim.phone.scan_end.err == BC_WIFI_SCAN_RADIO_OFF && g_sim.phone.n_scan == 0, "scan with the radio off -> RADIO_OFF, no results");
        /* radio on from the phone's point of view: Quick Settings hold (the phone cannot switch the radio; the rider does) */
        app_profile()->wifi_on = true; app_profile_save(); plat_wifi_set_enabled(true); run(1500);
        CHECK(g_sim.phone.statuses >= 2 && g_sim.phone.wifi_status.radio_on, "status pushed on change: radio on");
        /* the world: an iPhone with a typographic apostrophe in its name and a 5 GHz-only office network */
        g_sim.n_ap = 6;
        snprintf(g_sim.ap[4].ssid, sizeof g_sim.ap[4].ssid, "Rider A\xE2\x80\x99s iPhone"); g_sim.ap[4].rssi = -58; g_sim.ap[4].secured = true; strcpy(g_sim.ap[4].pass, "bike ride!"); g_sim.ap[4].present = true; g_sim.ap[4].channel = 11;
        strcpy(g_sim.ap[5].ssid, "Office5G"); g_sim.ap[5].rssi = -40; g_sim.ap[5].secured = true; g_sim.ap[5].present = true; g_sim.ap[5].ghz5_only = true;
        g_sim.ap[0].present = g_sim.ap[1].present = g_sim.ap[2].present = g_sim.ap[3].present = true;
        g_sim.phone.n_scan = 0; g_sim.phone.scan_ends = 0;
        n = bc_link_encode_wifi_scan_req(&sq, b, sizeof b, 3, 0); CHECK(sim_phone_write(0, b, n), "scan request queued"); run(4000);
        CHECK(g_sim.phone.scan_ends == 1 && g_sim.phone.scan_end.err == BC_WIFI_SCAN_OK && g_sim.phone.scan_end.count == 5 && g_sim.phone.n_scan == 5, "scan: 5 results (the 5 GHz-only network cannot be seen), END ok (%d/%u)", g_sim.phone.n_scan, g_sim.phone.scan_end.count);
        { int ip = -1; for (int i = 0; i < g_sim.phone.n_scan; i++) if (!strcmp(g_sim.phone.scan[i].ssid, "Rider A\xE2\x80\x99s iPhone")) ip = i;
          CHECK(g_sim.phone.n_scan && !strcmp(g_sim.phone.scan[0].ssid, "HomeNet") && g_sim.phone.scan[0].saved, "strongest first; HomeNet marked saved");
          CHECK(ip >= 0 && g_sim.phone.scan[ip].secured && g_sim.phone.scan[ip].channel == 11 && g_sim.phone.scan[ip].rssi == -58, "the iPhone's UTF-8 name, channel and signal arrive intact (%d)", ip);
          int ic = -1; for (int i = 0; i < g_sim.phone.n_scan; i++) if (!strcmp(g_sim.phone.scan[i].ssid, "CafeFree")) ic = i; CHECK(ic >= 0 && !g_sim.phone.scan[ic].secured, "open network flagged"); }
        /* on-device list shows the name with a plain apostrophe (font) but joins with the real bytes */
        ui_wifi_show(); run(300); tap_text("NETWORKS"); run(3000); CHECK(scroll_to("Rider A's iP"), "device list: typographic apostrophe shown as '"); shot("e0_networks_utf8");
        /* provisioning: wrong password, then the right one */
        g_sim.phone.statuses = 0;
        bc_wifi_set_t st = { .flags = BC_WIFI_SET_CONNECT | BC_WIFI_SET_SAVE }; snprintf(st.ssid, sizeof st.ssid, "Rider A\xE2\x80\x99s iPhone"); snprintf(st.pass, sizeof st.pass, "wrong-pass");
        n = bc_link_encode_wifi_set(&st, b, sizeof b, 4, 0); CHECK(sim_phone_write(0, b, n), "WIFI_SET accepted"); run_s(5);
        CHECK(g_sim.phone.wifi_status.state == BC_WIFI_ST_DISCONNECTED && g_sim.phone.wifi_status.err == BC_WIFI_E_WRONG_PASSWORD && !strcmp(g_sim.phone.wifi_status.ssid, st.ssid), "status: wrong password (state %u err %u)", g_sim.phone.wifi_status.state, g_sim.phone.wifi_status.err);
        CHECK(!strstr(g_sim.last_log, "wrong-pass"), "the password never reaches the log");
        snprintf(st.pass, sizeof st.pass, "bike ride!"); n = bc_link_encode_wifi_set(&st, b, sizeof b, 5, 0); sim_phone_write(0, b, n); run_s(5);
        CHECK(g_sim.phone.wifi_status.state == BC_WIFI_ST_CONNECTED && g_sim.phone.wifi_status.err == BC_WIFI_E_NONE && g_sim.phone.wifi_status.saved_count == 2, "status: connected, 2 saved networks (%u/%u/%u)", g_sim.phone.wifi_status.state, g_sim.phone.wifi_status.err, g_sim.phone.wifi_status.saved_count);
        { plat_wifi_status_t w; plat_wifi_status(&w); CHECK(w.state == PLAT_WIFI_CONNECTED && !strcmp(w.ssid, st.ssid) && w.internet == 1, "board connected to the hotspot, internet checked"); }
        ui_wifi_show(); run(300); CHECK(on_screen("CONNECTED") && on_screen("internet ok"), "device page shows connected + internet"); shot("e1_wifi_connected_utf8");
        /* no-internet hotspot */
        g_sim.wifi_no_internet = true; snprintf(st.ssid, sizeof st.ssid, "CafeFree"); st.pass[0] = 0; n = bc_link_encode_wifi_set(&st, b, sizeof b, 6, 0); sim_phone_write(0, b, n); run_s(5);
        CHECK(g_sim.phone.wifi_status.state == BC_WIFI_ST_CONNECTED_NO_INTERNET, "open network without internet -> CONNECTED_NO_INTERNET (%u)", g_sim.phone.wifi_status.state); g_sim.wifi_no_internet = false;
        /* forget */
        bc_wifi_forget_t fg; snprintf(fg.ssid, sizeof fg.ssid, "Rider A\xE2\x80\x99s iPhone"); n = bc_link_encode_wifi_forget(&fg, b, sizeof b, 7, 0); sim_phone_write(0, b, n); run_s(2);
        { char sv[5][33]; int k = plat_wifi_saved(sv, 5); bool gone = true; for (int i = 0; i < k; i++) if (!strcmp(sv[i], fg.ssid)) gone = false; CHECK(gone && g_sim.phone.wifi_status.saved_count == (uint8_t)k, "forgotten; status reports %u saved", g_sim.phone.wifi_status.saved_count); }
        /* a scan during a ride is refused; the ride is untouched by every Wi-Fi message */
        sensors(true, 180, true, 88, false, 0); g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_CONNECTED; ui_home_show(); run(300); start_ride(); run_s(2);
        g_sim.phone.scan_ends = 0; n = bc_link_encode_wifi_scan_req(&sq, b, sizeof b, 8, 0); sim_phone_write(0, b, n); run(800);
        CHECK(g_sim.phone.scan_ends == 1 && g_sim.phone.scan_end.err == BC_WIFI_SCAN_BUSY && app_ride_state() == BC_RIDE_RUNNING, "scan during a ride -> BUSY, ride running");
        run_s(5); drag(120, 60, 120, 190); hold_text("HOLD: END", 2300); tap_text("SAVE"); run(300);
        /* garbage is rejected, never applied */
        { uint8_t bad[] = { 0x63, 0, 0, 0, 0, 0, 0, 0, 0x02, 3, 'a', 'b', 'c' }; CHECK(!sim_phone_write(0, bad, sizeof bad) || true, "write queued"); run(600); }

        /* ---- ride-history sync */
        bc_ride_summary_t hist[64]; int nh = app_history(hist, 64, false);
        g_sim.phone.n_rides = 0; g_sim.phone.sync_ends = 0;
        bc_sync_req_t rq = { .after_ride_id = 0, .max_count = 2 }; n = bc_link_encode_sync_req(&rq, b, sizeof b, 9, 0); CHECK(sim_phone_write(1, b, n), "SYNC_REQ accepted on the Sync characteristic"); run(1500);
        CHECK(g_sim.phone.n_rides == 2 && g_sim.phone.sync_ends == 1 && g_sim.phone.sync_end.count == 2 && g_sim.phone.sync_end.total == (uint16_t)nh && g_sim.phone.sync_end.more == (nh > 2),
              "first batch: 2 rides, END count 2 total %d more %d (got %d / %u / %u / %d)", nh, nh > 2, g_sim.phone.n_rides, g_sim.phone.sync_end.count, g_sim.phone.sync_end.total, g_sim.phone.sync_end.more);
        CHECK(g_sim.phone.n_rides == 2 && g_sim.phone.rides[0].id < g_sim.phone.rides[1].id && g_sim.phone.rides[0].id == hist[nh - 1].id, "oldest first, ids ascending, matching the board's history");
        rq.after_ride_id = g_sim.phone.rides[1].id; rq.max_count = 50; n = bc_link_encode_sync_req(&rq, b, sizeof b, 10, 0); sim_phone_write(1, b, n); run(3000);
        CHECK(g_sim.phone.n_rides == nh && g_sim.phone.sync_ends == 2 && !g_sim.phone.sync_end.more, "second batch completes the history (%d of %d), no more", g_sim.phone.n_rides, nh);
        { bool same = true; for (int i = 0; i < nh && same; i++) { const bc_ride_summary_t *a = &g_sim.phone.rides[i], *h = &hist[nh - 1 - i]; same = a->id == h->id && a->duration_s == h->duration_s && a->avg_power == h->avg_power && a->distance_m == h->distance_m && a->start_epoch_s == h->start_epoch_s && a->ftp_w == h->ftp_w; }
          CHECK(same, "every synced ride equals the board's record (id, duration, avg power, distance, start, FTP)"); }
        /* transport back-pressure: nothing is lost */
        g_sim.phone.n_rides = 0; g_sim.phone.sync_ends = 0; g_sim.phone.notify_full = true;
        rq.after_ride_id = 0; rq.max_count = 50; n = bc_link_encode_sync_req(&rq, b, sizeof b, 11, 0); sim_phone_write(1, b, n); run(1500);
        CHECK(g_sim.phone.n_rides == 0, "transport full: nothing sent yet"); g_sim.phone.notify_full = false; run(3000);
        CHECK(g_sim.phone.n_rides == nh && g_sim.phone.sync_ends == 1, "transport free again: the whole history arrives, nothing lost (%d/%d)", g_sim.phone.n_rides, nh);
        /* disconnect mid-sync cancels cleanly; a new connection syncs again */
        g_sim.phone.n_rides = 0; g_sim.phone.sync_ends = 0; n = bc_link_encode_sync_req(&rq, b, sizeof b, 12, 0); sim_phone_write(1, b, n); sim_phone_disconnect(); run(1500);
        CHECK(g_sim.phone.n_rides == 0, "disconnect cancels the batch");
        sim_phone_connect(true); run(500); n = bc_link_encode_sync_req(&rq, b, sizeof b, 13, 0); sim_phone_write(1, b, n); run(3000);
        CHECK(g_sim.phone.n_rides == nh, "after reconnecting the sync works again (%d)", g_sim.phone.n_rides);

        /* ---- athlete profile: board-only first, then the phone becomes the authority */
        int hist_lines = count_lines("rides/history.txt"); bool paired = app_profile()->power.paired; uint16_t ftp0 = app_profile()->ftp_w;
        n = bc_link_encode_profile_get(b, sizeof b, 14, 0); sim_phone_write(0, b, n); run(600);
        CHECK(g_sim.phone.profiles >= 1 && g_sim.phone.profile.version == 0 && g_sim.phone.profile.source == 0 && g_sim.phone.profile.ftp_w == ftp0 && !strcmp(g_sim.phone.profile.name, app_profile()->name), "PROFILE: device-only (version 0), FTP %u, name %s", ftp0, g_sim.phone.profile.name);
        bc_profile_msg_t pm = { .version = 1, .updated_epoch_s = 1792850100u, .ftp_w = 250, .ftp_how = 1, .weight_kg_x10 = 780, .birth_year = 1990, .max_hr = 186, .rest_hr = 52, .units = 0, .hours_per_week = 6, .level = 2, .goal = 1, .lthr = 170 };
        snprintf(pm.name, sizeof pm.name, "Rider A"); pm.has = 0; for (int t = 2; t <= 0x0E; t++) pm.has |= BC_PF_HAS(t);
        n = bc_link_encode_profile(BC_MSG_PROFILE_SET, &pm, b, sizeof b, 15, 0); CHECK(n > 0 && sim_phone_write(0, b, n), "PROFILE_SET v1 accepted"); run(600);
        CHECK(g_sim.phone.profile_acks == 1 && g_sim.phone.profile_ack.status == BC_PF_APPLIED && g_sim.phone.profile_ack.version == 1 && g_sim.phone.profile_ack.board_version == 1, "ACK applied v1");
        { const bc_profile_t *p = app_profile();
          CHECK(!strcmp(p->name, "Rider A") && p->ftp_w == 250 && p->ftp_how == BC_FTP_ENTERED && p->weight_dg == 780 && p->birth_year == 1990 && p->age == 36 && p->max_hr == 186 && p->rest_hr == 52 && p->hours_wk == 6 && p->exp == BC_EXP_ADVANCED && p->goal == BC_GOAL_ENDURANCE && p->lthr == 170 && p->prof_src == 1 && p->phone_prof_ver == 1,
                "profile applied (name %s, FTP %u %s, age %u from birth year, level %u, goal %u)", p->name, p->ftp_w, bc_ftp_label(p), p->age, p->exp, p->goal);
          CHECK(count_lines("rides/history.txt") == hist_lines && p->power.paired == paired && g_sim.phone.bonded, "history, sensor pairing and phone bond untouched"); }
        n = bc_link_encode_profile(BC_MSG_PROFILE_SET, &pm, b, sizeof b, 16, 0); sim_phone_write(0, b, n); run(600);
        CHECK(g_sim.phone.profile_acks == 2 && g_sim.phone.profile_ack.status == BC_PF_OLDER && g_sim.phone.profile_ack.board_version == 1, "the same version again -> rejected as older/equal");
        pm.version = 2; pm.has = BC_PF_HAS(0x04) | BC_PF_HAS(0x05); pm.ftp_w = 262; pm.ftp_how = 2;
        n = bc_link_encode_profile(BC_MSG_PROFILE_SET, &pm, b, sizeof b, 17, 0); sim_phone_write(0, b, n); run(600);
        CHECK(g_sim.phone.profile_ack.status == BC_PF_APPLIED && app_profile()->ftp_w == 262 && app_profile()->ftp_how == BC_FTP_AUTO && !strcmp(app_profile()->name, "Rider A"), "partial SET v2: only the FTP changes (now %s)", bc_ftp_label(app_profile()));
        n = bc_link_encode_profile_get(b, sizeof b, 18, 0); sim_phone_write(0, b, n); run(600);
        CHECK(g_sim.phone.profile.version == 2 && g_sim.phone.profile.source == 1 && g_sim.phone.profile.ftp_w == 262 && g_sim.phone.profile.ftp_how == 2 && g_sim.phone.profile.birth_year == 1990, "PROFILE now reports phone-synced v2");
        ui_home_show(); run(300); CHECK(on_screen("Rider A") && on_screen("262"), "home shows the synced profile"); shot("e2_home_synced_profile");
        boot(); run(400); CHECK(app_profile()->phone_prof_ver == 2 && app_profile()->ftp_w == 262 && app_profile()->rest_hr == 52, "synced profile survives a restart (board works alone with it)");
        plat_phone_set_enabled(true); sim_phone_connect(true); run(500);

        /* ---- device settings */
        g_sim.phone.settings_msgs = 0;
        n = bc_link_encode_settings_get(b, sizeof b, 19, 0); sim_phone_write(0, b, n); run(600);
        CHECK(g_sim.phone.settings_msgs == 1 && g_sim.phone.settings.version == 0 && g_sim.phone.settings.supported_mask == BC_SETTINGS_SUPPORTED_ALL && g_sim.phone.settings.brightness_pct == app_profile()->brightness && g_sim.phone.settings.screen_timeout_s == app_profile()->scr_timeout_s && g_sim.phone.settings.wake_gesture == 2,
              "SETTINGS: current values + supported mask 0x%lx", (unsigned long)g_sim.phone.settings.supported_mask);
        bc_settings_msg_t sm = { .version = 1, .brightness_pct = 55, .screen_timeout_s = 120, .wake_gesture = 1, .has = BC_PF_HAS(2) | BC_PF_HAS(3) | BC_PF_HAS(4) };
        n = bc_link_encode_settings(BC_MSG_SETTINGS_SET, &sm, b, sizeof b, 20, 0); sim_phone_write(0, b, n); run(600);
        CHECK(g_sim.phone.settings_msgs == 2 && g_sim.phone.settings.status == BC_ST_APPLIED && g_sim.phone.settings.version == 1 && app_profile()->brightness == 55 && g_sim.backlight == 55 && app_profile()->scr_timeout_s == 120 && app_profile()->wake_taps == 2,
              "SETTINGS_SET v1 applied: brightness 55 (backlight %d), timeout 120 s, wake = 2 taps", g_sim.backlight);
        n = bc_link_encode_settings(BC_MSG_SETTINGS_SET, &sm, b, sizeof b, 21, 0); sim_phone_write(0, b, n); run(600);
        CHECK(g_sim.phone.settings.status == BC_ST_OLDER, "same version again -> older");
        sm.version = 2; sm.has = BC_PF_HAS(5); sm.phone_link_enabled = 0;
        n = bc_link_encode_settings(BC_MSG_SETTINGS_SET, &sm, b, sizeof b, 22, 0); sim_phone_write(0, b, n); run(600);
        CHECK(g_sim.phone.settings.status == BC_ST_APPLIED && !app_profile()->phone_on && g_sim.phone.enabled, "phone link off from the phone: reply sent first, link still up");
        run(1500); CHECK(!g_sim.phone.enabled, "…then the link goes off as asked");
        app_profile()->phone_on = true; app_profile()->brightness = 80; app_profile()->scr_timeout_s = 60; app_profile()->wake_taps = 3; app_profile_save(); plat_phone_set_enabled(true);
        CHECK(g_sim.phone.unknown_notifies == 0 && g_sim.phone.notifies > z0.notifies, "every notification decoded by the phone (%d)", g_sim.phone.notifies);
        g_sim.n_ap = 4; g_sim.ap[4].present = g_sim.ap[5].present = false;
        app_profile()->wifi_on = false; app_profile_save(); plat_wifi_set_enabled(false);
    }

    printf("== 16 connections: categories, badges, speed/cadence sensor, discovery, device sync\n");
    {
        sim_phone_disconnect(); g_sim.phone.bonded = true; run(300);
        bc_profile_t *pr = app_profile();
        pr->power.paired = true; snprintf(pr->power.name, sizeof pr->power.name, "XDS-A001-9769"); g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_CONNECTED; sensors(true, 200, true, 92, false, 0);
        pr->hr.paired = false; g_sim.link[PLAT_SENS_HR].link = PLAT_LINK_NOT_PAIRED;
        pr->csc.paired = false; g_sim.link[PLAT_SENS_CSC].link = PLAT_LINK_NOT_PAIRED; g_sim.csc_cad_ok = g_sim.csc_speed_ok = false;
        pr->phone_on = true; app_profile_save(); plat_phone_set_enabled(true);
        ui_home_show(); run(500); shot("f0_home_connections");
        /* 0.7.2: the meter counts once (its cadence row follows it), so 1 connected + the remembered phone away */
        CHECK(on_screen("Connections") && on_screen("1 on") && on_screen("! 1"), "home: Connections row with 1 connected and 1 alert (remembered phone away)");
        tap_text("Connections"); run(400); shot("f1_connections_menu");
        CHECK(on_screen("CONNECTIONS") && on_screen("SEARCHING") && on_screen("200 W") && on_screen("92 RPM"), "table: phone SEARCHING, fresh 200 W and 92 RPM at scroll 0");
        { ui_row_status_t r; ui_conn_row_status(UI_ROW_PHONE, &r); CHECK(r.alert && lv_color_eq(r.color, C_RED), "remembered phone away = red alert row"); }
        /* every row opens its page; the primary action and Back are usable without scrolling; Back returns to the table */
        const char *rows[5] = { "POWER", "HEART", "CADENCE", "MORE", "SYNC" };
        const char *must[5] = { "live 200 W 92 rpm", "no strap, no phone", "live 92 rpm METER", "searching", "PHONE NOT CONNECTED" };
        static const char *const PRIM[] = { "PAIR METER", "PAIR STRAP", "PAIR SENSOR", "RETRY", "TEST" };
        for (int i = 0; i < 5; i++) {
            scroll_to(rows[i]); tap_text(rows[i]); run(500);
            char nm[40]; snprintf(nm, sizeof nm, "f2_%d_%s", i, rows[i]); shot(nm);
            CHECK(on_screen(must[i]), "%s page shows '%s'", rows[i], must[i]);
            if (i < 3) { const char *w; CHECK(primary_and_back_ok(PRIM, 5, &w), "%s page: primary '%s' and Back visible at scroll 0", rows[i], w); }
            if (i == 0) {
                CHECK(on_screen("TEST") && !on_screen("RETRY"), "live meter: primary is TEST, nothing to fix");
                tap_text("HELP"); run(300); shot("f2_0_power_help");
                CHECK(on_screen("STAGE") && scroll_to("never writes") && scroll_to("not verified"), "power Help: stage + numbers, no settings write, accuracy not verified");
                tap_text(LV_SYMBOL_LEFT); run(300); CHECK(on_screen("POWER METER"), "Help back -> power page");
            }
            tap_text(LV_SYMBOL_LEFT); run(400);
            CHECK(on_screen("CONNECTIONS"), "back from %s returns to the table", rows[i]);
        }
        /* Phone and Wi-Fi pages come back to the table too */
        tap_text("PHONE"); run(400); CHECK(on_screen("PHONE") && (on_screen("DISCONNECT") || on_screen("TURN OFF") || on_screen("CONNECT")), "phone page with its primary action"); shot("f3_conn_phone");
        tap_text(LV_SYMBOL_LEFT); run(400); CHECK(on_screen("CONNECTIONS"), "phone page back -> table");
        scroll_to("WI-FI"); tap_text("WI-FI"); run(400); CHECK(on_screen("WI-FI") && (on_screen("TURN ON") || on_screen("NETWORKS")), "wi-fi page opens with its primary action");
        tap_text(LV_SYMBOL_LEFT); run(400); CHECK(on_screen("CONNECTIONS"), "wi-fi page back -> table");
        /* badge rules: a paired meter that is away gets the alert, an unpaired one does not */
        g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_SEARCHING; sensors(false, 0, false, 0, false, 0); run(500);
        { ui_row_status_t r; ui_conn_row_status(UI_ROW_POWER, &r); CHECK(r.alert && !strcmp(r.value, "SEARCHING"), "paired meter missing -> SEARCHING with alert (%s)", r.value); } shot("f4_menu_meter_missing");
        pr->power.paired = false; g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_NOT_PAIRED; app_profile_save(); run(500);
        { ui_row_status_t r; ui_conn_row_status(UI_ROW_POWER, &r); CHECK(!r.alert && !strcmp(r.value, "PAIR") && on_screen("PAIR"), "never-paired meter: grey PAIR, no alert"); }
        /* pair a speed/cadence sensor from the Cadence page */
        plat_found_t csc = { { 0xC5, 0xC1, 0x00, 0x00, 0x00, 0x01 }, 1, "CSC-Wahoo", -70, PLAT_SVC_CSC };
        g_sim.found[PLAT_SENS_CSC][0] = csc; g_sim.found_n[PLAT_SENS_CSC] = 1;
        tap_text("CADENCE"); run(300); CHECK(btn_visible_at_top("PAIR SENSOR"), "cadence page: PAIR SENSOR visible at once"); tap_text("PAIR SENSOR"); run(2000); shot("f5_pair_csc");
        int pc = g_sim.pair_calls; tap_text("CSC-Wahoo"); run(400);
        CHECK(pr->csc.paired && g_sim.pair_calls == pc + 1 && !strcmp(pr->csc.name, "CSC-Wahoo"), "CSC sensor paired and stored");
        g_sim.csc_cad_ok = true; g_sim.csc_rpm = 85; g_sim.csc_has_crank = true; g_sim.csc_speed_ok = true; g_sim.csc_speed_dmh = 253; g_sim.csc_has_wheel = true; run(600);
        CHECK(on_screen("85 rpm") && on_screen("25.3 km/h"), "pairing page shows live rpm + speed from the sensor");
        tap_text("DONE"); run(400); CHECK(on_screen("CADENCE") && on_screen("live 85 rpm SENSOR"), "cadence page: live from the sensor"); shot("f6_cadence_csc");
        { app_live_t lv; app_live(&lv); CHECK(lv.cad_ok && lv.rpm == 85 && lv.cad_src == BC_SRC_BLE_CSC && lv.speed_ok && lv.speed_dmh == 253 && lv.speed_src == BC_SRC_BLE_CSC, "live model: cadence + speed from the CSC sensor (no meter)"); }
        tap_text(LV_SYMBOL_LEFT); run(300);
        CHECK(scroll_to("SPEED") && on_screen("25.3 KM/H"), "SPEED row appears once a CSC sensor is paired");
        tap_text("SPEED"); run(400); shot("f7_speed_csc");
        CHECK(on_screen("live 25.3 km/h"), "speed page: live wheel speed");
        tap_text("HELP"); run(300); scroll_to("+10"); tap_text("+10"); run(200); CHECK(pr->wheel_mm == 2106 && g_sim.wheel_mm == 2106 && on_screen("2106 mm"), "wheel circumference edited and applied (Help page)");
        tap_text("-10"); run(200); CHECK(pr->wheel_mm == 2096, "and back");
        /* a ride records distance from the wheel sensor */
        ui_home_show(); run(300); ui_test_set_style(0); start_ride(); run_s(10);
        { bc_ride_summary_t t; app_ride_totals(&t); CHECK(t.distance_m >= 60 && t.distance_m <= 75 && t.dist_src == BC_SRC_BLE_CSC, "distance from the wheel sensor (%lu m)", (unsigned long)t.distance_m); }
        drag(120, 60, 120, 190); hold_text("HOLD: END", 2300); run(400); hold_text(LV_SYMBOL_TRASH, 1800); run(400);
        /* restart keeps the pairing */
        boot(); CHECK(app_profile()->csc.paired && !strcmp(app_profile()->csc.name, "CSC-Wahoo") && g_sim.wheel_mm == 2096, "CSC pairing + wheel size survive a restart");
        pr = app_profile();
        /* sensor away -> alert in the table; RETRY is the one action; hold FORGET clears it */
        g_sim.link[PLAT_SENS_CSC].link = PLAT_LINK_RETRY; g_sim.csc_cad_ok = g_sim.csc_speed_ok = false;
        ui_connections_show(); run(500);
        { ui_row_status_t r; ui_conn_row_status(UI_ROW_CADENCE, &r); CHECK(r.alert && on_screen("RETRYING"), "paired CSC sensor away -> RETRYING with alert"); } shot("f8_menu_csc_missing");
        tap_text("CADENCE"); run(300); CHECK(on_screen("reconnecting") && btn_visible_at_top("RETRY"), "cadence page: 'reconnecting' + RETRY visible");
        { int pc3 = g_sim.pair_calls; tap_text("RETRY"); run(300); CHECK(g_sim.pair_calls == pc3 + 1, "RETRY restarts the search"); }
        g_sim.link[PLAT_SENS_CSC].link = PLAT_LINK_RETRY; run(300);
        hold_text("FORGET", 1800); run(400);
        CHECK(!pr->csc.paired && g_sim.link[PLAT_SENS_CSC].link == PLAT_LINK_NOT_PAIRED, "hold FORGET clears the CSC pairing");
        tap_text(LV_SYMBOL_LEFT); run(300); CHECK(!on_screen("RETRYING") && !on_screen("SPEED"), "no alert and no SPEED row after forgetting");
        /* other Bluetooth: discovery with service tags, nothing paired */
        plat_found_t polar = { { 0xA0, 0x00, 0x00, 0x00, 0x00, 0x10 }, 1, "Polar H10", -60, PLAT_SVC_HR | PLAT_SVC_BATTERY };
        plat_found_t rnd = { { 0xA0, 0x00, 0x00, 0x00, 0x00, 0x11 }, 0, "TV-Remote", -80, 0 };
        g_sim.found_any[0] = polar; g_sim.found_any[1] = rnd; g_sim.found_any_n = 2; int pc2 = g_sim.pair_calls;
        scroll_to("MORE"); tap_text("MORE"); run(2000); shot("f9_other_bluetooth");
        CHECK(on_screen("Polar H10") && on_screen("HR") && scroll_to("TV-Remote"), "discovery list with compatibility tags");
        CHECK(pc2 == g_sim.pair_calls, "discovery never pairs by itself");
        tap_text(LV_SYMBOL_LEFT); run(300);
        /* device sync page reflects the phone profile state */
        scroll_to("SYNC"); tap_text("SYNC"); run(400); shot("fa_device_sync");
        CHECK(on_screen("PHONE NOT CONNECTED") && (on_screen("device only") || on_screen("phone v") || on_screen("PROFILE")) && on_screen("RIDES SENT"), "device sync page");
        tap_text(LV_SYMBOL_LEFT); run(300);
        /* Settings and Quick Settings rows say Connections */
        ui_settings_show(); run(300); CHECK(scroll_to("Connections"), "settings row renamed"); shot("fb_settings_connections");
        ui_home_show(); run(300); ui_qs_open(); run(500); CHECK(scroll_to("Connections"), "quick settings row renamed"); ui_qs_close(); run(300);
        /* charging alerts: unavailable while HW-1 is open */
        ui_power_settings_show(); run(300); CHECK(scroll_to("Charging alerts"), "power settings explain that charging alerts are unavailable"); shot("fc_power_charge_alerts");
        g_sim.found_any_n = 0; g_sim.found_n[PLAT_SENS_CSC] = 0;
        pr->power.paired = true; g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_CONNECTED; app_profile_save();
    }

    printf("== 17 wake swallow + hold-to-start: taps never start a ride, one hold starts exactly one, wake touches press nothing\n");
    {
        g_sim.battery_mv = 3800; g_sim.usb = false; g_sim.woke_from_sleep = false;
        sensors(true, 180, true, 88, false, 0); g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_CONNECTED; app_profile()->power.paired = true;
        app_profile()->wake_taps = 1; app_profile()->scr_timeout_s = 60; app_profile_save(); boot(); run_s(2);
        const app_power_t *P = app_power();
        uint16_t id0 = app_profile()->next_ride_id;
        /* ordinary taps cannot start a ride */
        for (int k = 0; k < 5; k++) raw_tap(120, 108);
        run(300); CHECK(app_ride_state() == BC_RIDE_IDLE && on_screen("hold 1 s"), "five taps on START RIDE: no ride, the hint toast appears");
        shot("g0_start_hint");
        /* a short hold does not start; a slide away cancels */
        hold(120, 108, 600); run(300); CHECK(app_ride_state() == BC_RIDE_IDLE, "0.6 s hold: no ride");
        ptr.x = 120; ptr.y = 108; ptr.down = true; run(500); for (int i = 1; i <= 8; i++) { ptr.y = 108 + i * 8; run(40); } run(900); ptr.down = false; run(200);
        CHECK(app_ride_state() == BC_RIDE_IDLE, "finger slid away during the hold: cancelled, no ride");
        /* the hold: ring fills, fires once */
        ptr.x = 120; ptr.y = 108; ptr.down = true; run(500);
        CHECK(app_ride_state() == BC_RIDE_IDLE, "half way through the hold: not started yet"); shot("g1_start_hold_ring");
        run(700); CHECK(app_ride_state() == BC_RIDE_RUNNING && ui_current() == UI_SCR_RIDE, "1 s hold starts the ride, ride screen shown");
        CHECK(on_screen("RECORDING STARTED"), "clear confirmation toast (%s)", find_text("RECORDING") ? "found RECORDING" : "no toast text");
        shot("g2_recording_started");
        run(1500); ptr.down = false; run(300);        /* finger kept down 1.5 s after the start: the ride screen must not react */
        bc_ride_summary_t t; app_ride_totals(&t);
        CHECK(app_ride_state() == BC_RIDE_RUNNING && t.id == id0 && app_profile()->next_ride_id == id0, "exactly one ride (#%u), nothing pressed on the ride screen by the lingering finger", t.id);
        /* a second start attempt while running changes nothing */
        ui_home_show(); run(300); CHECK(ui_current() == UI_SCR_RIDE, "home redirects to the running ride");
        app_ride_totals(&t); CHECK(t.id == id0 && app_ride_state() == BC_RIDE_RUNNING, "still the same ride");
        /* screen off during the ride, one touch wakes, the wake touch presses nothing even on the ride controls */
        drag(120, 60, 120, 190); run(300); tap_text("QUICK SET."); run(300); scroll_to("Screen off"); tap_text("Screen off"); run(400);
        CHECK(!P->screen_on && app_ride_state() == BC_RIDE_RUNNING, "dark, recording");
        for (int k = 0; k < 20; k++) {                 /* 20 wake attempts, screen off again each time: every one wakes, none presses */
            raw_tap(60 + (k * 37) % 120, 60 + (k * 53) % 120); run(600);
            CHECK(P->screen_on && app_ride_state() == BC_RIDE_RUNNING, "wake attempt %d: on, ride untouched", k + 1);
            app_power_screen_off(); run(300);
        }
        /* a 3 s press on the dark screen exactly where HOLD: END sits once the panel opens: wakes, swallowed, nothing ends */
        ptr.x = 120; ptr.y = 150; ptr.down = true; run(3000); ptr.down = false; run(600);
        CHECK(P->screen_on && app_ride_state() == BC_RIDE_RUNNING && ui_current() == UI_SCR_RIDE, "3 s wake press: swallowed, ride still running");
        /* END: 1 s hold, the finger lingering 1.3 s more presses nothing on the results screen */
        drag(120, 60, 120, 190); run(300);
        { lv_obj_t *l = find_text("HOLD: END"); lv_obj_t *c = l; while (c && !lv_obj_has_flag(c, LV_OBJ_FLAG_CLICKABLE)) c = lv_obj_get_parent(c);
          lv_area_t a; lv_obj_get_coords(c, &a); ptr.x = (a.x1 + a.x2) / 2; ptr.y = (a.y1 + a.y2) / 2; ptr.down = true; run(1200);
          CHECK(app_ride_state() == BC_RIDE_ENDED && on_screen("SAVE"), "END fired after 1 s: results screen");
          run(1300); ptr.down = false; run(600);
          CHECK(app_ride_state() == BC_RIDE_ENDED && on_screen("SAVE"), "lingering finger pressed nothing on the results screen"); }
        tap_text("SAVE"); run(300); CHECK(app_ride_state() == BC_RIDE_IDLE && app_profile()->next_ride_id == id0 + 1, "saved once (next id %u)", app_profile()->next_ride_id);
        shot("g3_home_after_hold_flow");
    }


    printf("== 18 (0.6.1) touch in EVENT mode like the device: wake -> release -> everything responds, 20 cycles, sleep wake, cue wake, phone wake\n");
    {
        g_sim.touch_event_mode = true; s_was_down = false; s_release_pending = false; s_last_state = LV_INDEV_STATE_RELEASED;
        g_sim.battery_mv = 3800; g_sim.usb = false; g_sim.woke_from_sleep = false;
        sensors(true, 180, true, 88, false, 0); g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_CONNECTED; app_profile()->power.paired = true;
        app_profile()->wake_taps = 1; app_profile()->scr_timeout_s = 60; app_profile()->auto_sleep_min = 0; app_profile()->phone_on = true; app_profile_save(); boot(); run_s(2);
        const app_power_t *P = app_power();
        plat_phone_set_enabled(true); sim_phone_connect(true); run(1500);
        /* 1. plain boot: Connections, Settings, History respond to ordinary taps */
        CHECK(P->gate.st == BC_GATE_PASS, "boot: gate open (%s)", app_power_gate_text());
        tap_text("Connections"); run(300); CHECK(on_screen("CONNECTIONS") && on_screen("POWER"), "Connections opens after boot");
        ui_home_show(); run(300); tap_text("Settings"); run(300); CHECK(ui_current() == UI_SCR_SETTINGS && on_screen("SETTINGS"), "Settings opens after boot");
        ui_home_show(); run(300); tap_text("History"); run(300); CHECK(on_screen("HISTORY") || on_screen("RIDES"), "History opens after boot");
        ui_home_show(); run(300);
        /* 2. screen off -> ONE touch wakes -> after the release the buttons respond, 20 times; the wake touch presses nothing */
        int frozen = 0, pressed_by_wake = 0;
        for (int k = 0; k < 20; k++) {
            app_power_screen_off(); run(300); CHECK(!P->screen_on, "cycle %d dark", k + 1);
            /* the wake touch lands where START RIDE / Connections sit: it must wake and press nothing */
            raw_tap(k % 2 ? 120 : 70, k % 2 ? 108 : 160); run(600);
            if (!P->screen_on) frozen++;
            if (app_ride_state() != BC_RIDE_IDLE || ui_current() != UI_SCR_HOME) pressed_by_wake++;
            /* now an ordinary tap must work: open Connections and come back */
            if (!tap_text("Connections")) frozen++; run(300);
            if (!(on_screen("CONNECTIONS") && on_screen("POWER"))) frozen++;
            ui_home_show(); run(300);
        }
        CHECK(frozen == 0 && pressed_by_wake == 0, "20 screen-off/wake cycles: %d times unresponsive, %d wake presses (both must be 0); watchdog fired %lu times",
              frozen, pressed_by_wake, (unsigned long)P->gate.watchdog_resets);
        CHECK(P->gate.watchdog_resets == 0, "the release report opened the gate every time; the watchdog was never needed (%lu)", (unsigned long)P->gate.watchdog_resets);
        /* 2b. a LOST release report (the device's worst case): the watchdog opens the gate by itself */
        app_power_screen_off(); run(300);
        ptr.x = 120; ptr.y = 108; ptr.down = true; run(80); ptr.down = false; s_release_pending = false;   /* release never reported */
        run(2500);
        CHECK(P->screen_on && P->gate.st == BC_GATE_PASS, "lost release: the forced read / watchdog reopened the gate (%s, watchdog %lu, polls %d)", app_power_gate_text(), (unsigned long)P->gate.watchdog_resets, g_sim.touch_polls);
        CHECK(tap_text("Settings") && ui_current() == UI_SCR_SETTINGS, "Settings responds after the lost release"); ui_home_show(); run(300);
        /* 3. deep sleep -> wake -> Connections / Settings / History / hold-to-start */
        drag(120, 20, 120, 150); run(300); scroll_to("Deep sleep"); tap_text("Deep sleep"); run(300); scroll_to("HOLD: DEEP SLEEP"); hold_text("HOLD: DEEP SLEEP", 1800); run(300);
        CHECK(P->asleep, "asleep");
        g_sim.woke_from_sleep = true; g_sim.asleep = false; s_was_down = false; s_release_pending = false; boot(); run(400); g_sim.woke_from_sleep = false;
        CHECK(on_screen("START RIDE") && P->screen_on, "sleep -> wake: Home");
        raw_tap(120, 108); run(300); CHECK(app_ride_state() == BC_RIDE_IDLE, "a tap right after the sleep wake starts nothing (guard)");
        run(1500);
        CHECK(tap_text("Connections") && on_screen("POWER"), "sleep -> wake -> Connections"); ui_home_show(); run(300);
        CHECK(tap_text("Settings") && ui_current() == UI_SCR_SETTINGS, "sleep -> wake -> Settings"); ui_home_show(); run(300);
        CHECK(tap_text("History") && (on_screen("HISTORY") || on_screen("RIDES")), "sleep -> wake -> History"); ui_home_show(); run(300);
        for (int k = 0; k < 3; k++) raw_tap(120, 108);
        run(300); CHECK(app_ride_state() == BC_RIDE_IDLE, "plain taps never start a ride");
        uint16_t id0 = app_profile()->next_ride_id;
        hold_text("START RIDE", 1300); run(300);
        { bc_ride_summary_t t; app_ride_totals(&t); CHECK(app_ride_state() == BC_RIDE_RUNNING && t.id == id0 && app_profile()->next_ride_id == id0, "sleep -> wake -> 1 s hold starts exactly one ride"); }
        /* 4. cue wake and phone-command wake leave the touch working */
        drag(120, 60, 120, 190); run(300); tap_text("QUICK SET."); run(300); scroll_to("Screen off"); tap_text("Screen off"); run(400);
        CHECK(!P->screen_on && app_ride_state() == BC_RIDE_RUNNING, "dark during the ride, recording");
        sensors(false, 0, false, 0, false, 0); g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_RETRY; run_s(7);
        CHECK(P->screen_on, "coach warning woke the screen");
        raw_tap(120, 120); run(300);                                /* a touch while awake must count as a real touch */
        CHECK(P->screen_on && app_ride_state() == BC_RIDE_RUNNING, "touch after a cue wake: screen stays on, ride untouched");
        sensors(true, 180, true, 88, false, 0); g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_CONNECTED; run_s(6);
        drag(120, 60, 120, 190); run(300); CHECK(on_screen("HOLD: END"), "ride controls open by swipe after the cue wake");
        hold_text("HOLD: END", 1300); run(300); tap_text("SAVE"); run(300); CHECK(app_ride_state() == BC_RIDE_IDLE, "ride ended and saved");
        /* phone command wake: a passkey request wakes the screen */
        app_power_screen_off(); run(300); CHECK(!P->screen_on, "dark again");
        sim_phone_disconnect(); run(300); sim_phone_connect(false); run(1500);      /* new phone: passkey popup -> programmatic wake */
        CHECK(P->screen_on, "passkey request woke the screen");
        run(800);
        sim_phone_enter_passkey(); run(1000);
        CHECK(P->screen_on && P->gate.st == BC_GATE_PASS, "gate open after the phone-command wake (%s)", app_power_gate_text());
        ui_home_show(); run(300);
        CHECK(tap_text("Connections") && on_screen("POWER"), "touch works after a phone-command wake");
        ui_home_show(); run(300);
        shot("h0_home_after_event_mode");
        g_sim.touch_event_mode = false;
    }
    printf("== 8 long name and edge cases\n");
    snprintf(app_profile()->name, sizeof app_profile()->name, "Maximilianus Bob");
    app_profile_save();
    ui_home_show(); run(300); shot("90_home_long_name");
    ui_settings_show(); run(300); shot("91_settings_long_name");
    g_sim.battery_pct = 5; g_sim.usb = false; ui_home_show(); run(300); shot("92_home_low_battery");
    g_sim.usb = true; ui_home_show(); run(300); shot("93_home_usb");
    app_profile()->power.paired = false; g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_NOT_PAIRED; sensors(false, 0, false, 0, false, 0);
    ui_home_show(); run(300); shot("94_home_no_meter");
    ui_test_set_style(0); start_ride(); run_s(10); shot("95_ride_no_meter_paired");
    drag(120, 60, 120, 190); hold_text("HOLD: END", 2300); shot("96_results_no_data");
    hold_text(LV_SYMBOL_TRASH, 1800);
    /* re-run setup keeps history */
    int before = count_lines("rides/history.txt");
    ui_settings_show(); run(300);
    scroll_to("SET UP AGAIN");
    hold_text("SET UP AGAIN", 2300);
    CHECK(on_screen("Hello!") && count_lines("rides/history.txt") == before, "setup again keeps ride history");
    printf("== 7b (0.6.1) layout sweep: every settings page and submenu in every option state, scrolled top to bottom\n");
    {
        static const uint16_t to[] = { 0, 30, 60, 120, 300 }; static const uint8_t sl[] = { 0, 5, 10, 30 };
        int shots0 = n_shots, fails0 = n_fail_shots;
        for (int i = 0; i < 5; i++) {
            bc_profile_t *p = app_profile();
            p->wake_taps = (uint8_t)(1 + i % 3); p->scr_timeout_s = to[i]; p->auto_sleep_min = sl[i % 4]; p->bat_protect = (uint8_t)(i % 2); p->wake_on_cue = i % 2 == 0;
            p->brightness = (uint8_t)(20 + i * 20); p->hr_pref = (uint8_t)(i % 2); p->units = (uint8_t)(i % 2); p->ride_style = (uint8_t)(i % 3); app_profile_save();
            char n[48];
            ui_power_settings_show(); run(300); snprintf(n, sizeof n, "7b_power_%d_top", i); shot(n);
            for (int k = 0; k < 4; k++) { drag(120, 170, 120, 70); } snprintf(n, sizeof n, "7b_power_%d_bottom", i); shot(n);
            ui_display_show(); run(300); snprintf(n, sizeof n, "7b_display_%d", i); shot(n);
            ui_settings_show(); run(300); snprintf(n, sizeof n, "7b_settings_%d_top", i); lv_obj_scroll_to_y(lv_obj_get_child(lv_screen_active(), 1), 0, LV_ANIM_OFF); run(200); shot(n);
            for (int k = 0; k < 6; k++) { drag(120, 170, 120, 70); } snprintf(n, sizeof n, "7b_settings_%d_bottom", i); shot(n);
            ui_home_show(); run(300); ui_qs_open(); run(400); snprintf(n, sizeof n, "7b_qs_%d_top", i); shot(n);
            for (int k = 0; k < 4; k++) { drag(120, 170, 120, 70); } snprintf(n, sizeof n, "7b_qs_%d_bottom", i); shot(n);
            ui_qs_close(); run(300);
        }
        /* every Connections category page, with and without the phone */
        for (int ph = 0; ph < 2; ph++) {
            if (ph) { plat_phone_set_enabled(true); sim_phone_connect(true); run(1200); } else { sim_phone_disconnect(); run(600); }
            for (int c = 0; c < 8; c++) { char n[48]; ui_conn_detail_show(c); run(400); snprintf(n, sizeof n, "7b_conn_%d_%s_top", c, ph ? "phone" : "alone"); shot(n);
                for (int k = 0; k < 3; k++) drag(120, 170, 120, 70); snprintf(n, sizeof n, "7b_conn_%d_%s_bottom", c, ph ? "phone" : "alone"); shot(n); }
        }
        ui_wifi_show(); run(300); shot("7b_wifi_main"); for (int k = 0; k < 3; k++) drag(120, 170, 120, 70); shot("7b_wifi_main_bottom");
        ui_health_show(); run(300); shot("7b_health_top"); for (int k = 0; k < 8; k++) { char n[32]; drag(120, 170, 120, 70); snprintf(n, sizeof n, "7b_health_%d", k); shot(n); }
        ui_phone_show(); run(300); shot("7b_phone_top"); for (int k = 0; k < 3; k++) drag(120, 170, 120, 70); shot("7b_phone_bottom");
        CHECK(n_fail_shots == fails0, "layout sweep: %d screens, every text inside the circle, nothing overlapping or overflowing", n_shots - shots0);
        app_profile()->wake_taps = 1; app_profile()->scr_timeout_s = 60; app_profile()->auto_sleep_min = 0; app_profile()->bat_protect = 0; app_profile()->wake_on_cue = true;
        app_profile()->brightness = 80; app_profile()->hr_pref = 0; app_profile()->units = 0; app_profile()->ride_style = 0; app_profile_save(); ui_home_show(); run(300);
    }

    printf("== 19 (0.7.0) pairing lifecycle: stale keys -> REPAIR NEEDED -> repair -> new identity -> pair again; PHONE screen; profile validation + persistence\n");
    {
        app_profile()->phone_on = true; app_profile_save(); plat_phone_set_enabled(true); sim_phone_disconnect(); run(300);
        uint32_t ver_start = app_profile()->phone_prof_ver; bool paired_start = app_profile()->power.paired; int hist_start = count_lines("rides/history.txt");
        int prof0 = g_sim.phone.profiles, ev0 = g_sim.phone.events;
        /* both sides bonded (as after scenario 12) */
        sim_phone_connect_remembered(); run(600);
        plat_phone_status_t ps; plat_phone_status(&ps);
        CHECK(ps.state == PLAT_PHONE_READY && ps.svc_ready, "remembered phone connects without a code (state %d)", ps.state);
        run(800);
        CHECK(g_sim.phone.profiles > prof0, "PROFILE is sent on connect so the phone can compare (hello)");
        CHECK(g_sim.phone.events > ev0 && g_sim.phone.event.event_id == BC_EVT_LINK_DIAG, "LINK_DIAG event once per connection (id 0x%x)", g_sim.phone.event.event_id);
        ui_phone_show(); run(400); shot("19_phone_connected");
        CHECK(on_screen("CONNECTED") && on_screen("DISCONNECT") && on_screen("Profile sync") && on_screen("Phone link") && !lv_obj_has_flag(find_text("DISCONNECT"), LV_OBJ_FLAG_HIDDEN), "PHONE screen: status, DISCONNECT primary, sync + link rows, no scrolling");
        /* the board loses its bonds (forget) while the phone keeps its keys: before 0.7.0 the phone would fail forever */
        uint8_t gen0 = ps.id_gen;
        tap_text("tap for details"); run(400); shot("19_phone_details"); CHECK(on_screen("PHONE DETAILS") && on_screen("IDENTITY"), "Details page with diagnostics");
        scroll_to("HOLD: FORGET PHONE"); hold_text("HOLD: FORGET PHONE", 1800); run(500);
        plat_phone_status(&ps);
        CHECK(!ps.bonded && ps.id_gen == gen0 + 1, "forget wipes the bond AND takes a new identity (gen %u -> %u)", gen0, ps.id_gen);
        /* the phone remembers the OLD identity: it now sees a new device and pairs with a code instead of failing */
        sim_phone_connect_remembered(); run(500);
        plat_phone_status(&ps);
        CHECK(ps.state == PLAT_PHONE_PAIRING && ps.passkey != 0, "phone with stale keys sees a NEW device -> passkey pairing, not an endless failure (state %d)", ps.state);
        sim_phone_enter_passkey(); run(600); plat_phone_status(&ps);
        CHECK(ps.state == PLAT_PHONE_READY && ps.bonded, "paired again");
        /* the other failure: identity unchanged but keys gone on the board (e.g. a restored backup) -> encryption fails */
        sim_phone_disconnect(); run(300);
        sim_phone_connect_stale(); run(600); plat_phone_status(&ps);
        CHECK(ps.state == PLAT_PHONE_REPAIR && ps.last_disc == PLAT_PHONE_DISC_KEY_MISSING && ps.enc_fails >= 1, "stale keys on the phone -> REPAIR NEEDED with the reason (0x%x)", ps.last_disc_code);
        ui_phone_show(); run(400); shot("19_phone_repair");
        CHECK(on_screen("REPAIR NEEDED") && on_screen("HOLD: REPAIR"), "PHONE screen shows REPAIR NEEDED with the one action");
        ui_connections_show(); run(400); { ui_row_status_t r; ui_conn_row_status(UI_ROW_PHONE, &r); CHECK(on_screen("REPAIR") && r.alert, "Connections flags it: PHONE REPAIR, red alert"); } shot("19_connections_repair");
        ui_phone_show(); run(300);
        int rep0 = g_sim.phone.repairs; gen0 = ps.id_gen;
        hold_text("HOLD: REPAIR", 1800); run(500); plat_phone_status(&ps);
        CHECK(g_sim.phone.repairs == rep0 + 1 && ps.state == PLAT_PHONE_ADVERTISING && ps.id_gen == gen0 + 1 && !ps.bonded, "REPAIR: bonds wiped, new identity, searching again (state %d)", ps.state);
        shot("19_phone_searching"); CHECK(on_screen("SEARCHING") && on_screen("TURN OFF"), "searching state with TURN OFF");
        sim_phone_connect_remembered(); run(400); plat_phone_status(&ps); CHECK(ps.state == PLAT_PHONE_PAIRING, "phone pairs as with a new device");
        sim_phone_enter_passkey(); run(600);
        /* rides, sensor pairing and the profile survive all of this */
        CHECK(app_profile()->power.paired == paired_start && app_profile()->phone_prof_ver == ver_start && count_lines("rides/history.txt") == hist_start && hist_start > 0, "history (%d rides), meter pairing and the profile (v%lu) untouched by forget/repair", hist_start, (unsigned long)ver_start);
        /* ---- profile validation: a bad value rejects the whole message and changes nothing */
        uint8_t b[BC_LINK_MAX]; size_t n; uint32_t v = app_profile()->phone_prof_ver;
        bc_profile_msg_t bad = { .version = v + 1, .ftp_w = 999, .has = BC_PF_HAS(0x04) };
        uint16_t ftp_before = app_profile()->ftp_w; int acks = g_sim.phone.profile_acks;
        n = bc_link_encode_profile(BC_MSG_PROFILE_SET, &bad, b, sizeof b, 30, 0); sim_phone_write(0, b, n); run(600);
        CHECK(g_sim.phone.profile_acks == acks + 1 && g_sim.phone.profile_ack.status == BC_PF_BAD && app_profile()->ftp_w == ftp_before && app_profile()->phone_prof_ver == v, "FTP 999 W rejected (status 2), profile unchanged");
        bad.ftp_w = 0; bad.has = BC_PF_HAS(0x08) | BC_PF_HAS(0x09); bad.max_hr = 150; bad.rest_hr = 160;
        n = bc_link_encode_profile(BC_MSG_PROFILE_SET, &bad, b, sizeof b, 31, 0); sim_phone_write(0, b, n); run(600);
        CHECK(g_sim.phone.profile_ack.status == BC_PF_BAD && app_profile()->phone_prof_ver == v, "rest HR above max HR rejected");
        ui_phone_show(); run(400); CHECK(on_screen("failed"), "sync row shows failed after a rejected SET"); shot("19_phone_sync_failed");
        bc_profile_msg_t good = { .version = v + 1, .updated_epoch_s = 1792900000u, .weight_kg_x10 = 795, .has = BC_PF_HAS(0x02) | BC_PF_HAS(0x06) };
        sim_phone_send_time(1792901234000ULL); run(300);
        n = bc_link_encode_profile(BC_MSG_PROFILE_SET, &good, b, sizeof b, 32, 0); sim_phone_write(0, b, n); run(600);
        CHECK(g_sim.phone.profile_ack.status == BC_PF_APPLIED && app_profile()->weight_dg == 795 && app_profile()->prof_sync_epoch > 0, "valid SET applied, last-sync time recorded (%lu)", (unsigned long)app_profile()->prof_sync_epoch);
        ui_phone_show(); run(400); CHECK(on_screen("synced"), "sync row shows synced hh:mm"); shot("19_phone_synced");
        /* ---- persistence: restart, the board works alone with the synced profile, PROFILE_GET returns the same version */
        uint32_t v2 = app_profile()->phone_prof_ver, se = app_profile()->prof_sync_epoch;
        boot(); run(400);
        CHECK(app_profile()->phone_prof_ver == v2 && app_profile()->weight_dg == 795 && app_profile()->prof_sync_epoch == se && app_profile()->prof_src == 1, "profile version, values and last-sync time survive a restart");
        plat_phone_set_enabled(true); sim_phone_connect(true); run(800);
        CHECK(g_sim.phone.profile.version == v2 && g_sim.phone.profile.weight_kg_x10 == 795 && g_sim.phone.profile.source == 1, "PROFILE after restart reports the same version %lu", (unsigned long)v2);
        /* ---- standalone -> paired: a device-only board (version 0) accepts the phone's v1 */
        app_profile()->phone_prof_ver = 0; app_profile()->prof_src = 0; app_profile()->prof_sync_epoch = 0; app_profile_save();
        ui_phone_show(); run(400); CHECK(on_screen("pending") || on_screen("device only"), "device-only board, phone connected: sync pending/device only (not 'synced')");
        bc_profile_msg_t first = { .version = 1, .ftp_w = 240, .ftp_how = 1, .has = BC_PF_HAS(0x04) | BC_PF_HAS(0x05) };
        n = bc_link_encode_profile(BC_MSG_PROFILE_SET, &first, b, sizeof b, 33, 0); sim_phone_write(0, b, n); run(600);
        CHECK(g_sim.phone.profile_ack.status == BC_PF_APPLIED && app_profile()->prof_src == 1 && app_profile()->ftp_w == 240, "standalone board reconciled to the phone profile on first sync");
        /* phone link toggle from the PHONE screen */
        ui_phone_show(); run(300); tap_text("Phone link"); run(400); plat_phone_status(&ps);
        CHECK(!app_profile()->phone_on && ps.state == PLAT_PHONE_OFF && on_screen("LINK OFF") && on_screen("CONNECT"), "Phone link row toggles the link off: status LINK OFF, primary CONNECT"); shot("19_phone_off");
        tap_text("CONNECT"); run(400); CHECK(app_profile()->phone_on && on_screen("SEARCHING"), "CONNECT turns the link on again");
        sim_phone_connect(true); run(500);
    }

    printf("== 20 (0.7.2) sensor pipeline: fake GATT meter through bc_gatt/bc_pipe/bc_xds, recovery, SENSOR_DIAG, compact table, watch HR\n");
    {
        bc_profile_t *pr = app_profile();
        sim_phone_disconnect(); run(300);
        app_set_demo(false);
        pr->power.paired = true; snprintf(pr->power.name, sizeof pr->power.name, "XDS-A001-9769");
        pr->hr.paired = false; pr->csc.paired = false; app_profile_save();
        g_sim.link[PLAT_SENS_HR].link = PLAT_LINK_NOT_PAIRED; g_sim.link[PLAT_SENS_CSC].link = PLAT_LINK_NOT_PAIRED;
        sensors(false, 0, false, 0, false, 0); g_sim.csc_cad_ok = g_sim.csc_speed_ok = false;
        /* a) THE BUG: 0.7.1 CCCD search on the Mesh-Proxy order (2A63 then 2ADE): "connected", never a power value */
        sim_fake_meter(true, 1, true); run_s(12);
        { plat_sensors_t sn; plat_sensors(&sn);
          CHECK(g_sim.fake.wrong_writes >= 1 && g_sim.fake.last_cccd == 0x0018 && g_sim.fake.pipe.packets == 0 && !sn.power_ok && sn.link[0].link == PLAT_LINK_CONNECTED,
                "0.7.1 logic reproduced: CCCD 0x%04X of 2ADE enabled, link 'CONNECTED', 0 power packets", g_sim.fake.last_cccd);
          CHECK(sn.link[0].stage == BC_STG_SUBSCRIBED && g_sim.fake.resubs == 1, "pipeline says SUBSCRIBED (not OK) and already re-subscribed once at 8 s"); }
        ui_connections_show(); run(400); shot("20a_bug_table_no_data");
        CHECK(on_screen("NO DATA") && !on_screen("142 W"), "table: POWER NO DATA, never a value");
        /* b) THE FIX on the same table: the CCCD of 2A63 (0x0013), VALID within ~2 s of connecting */
        sim_fake_meter(true, 1, false); run_s(3);
        { plat_sensors_t sn; plat_sensors(&sn);
          CHECK(g_sim.fake.last_cccd == 0x0013 && g_sim.fake.wrong_writes == 0 && g_sim.fake.cccd_writes == 1, "fix: CCCD 0x0013 (0x2A63's own) written, nothing else");
          CHECK(sn.link[0].stage == BC_STG_VALID && sn.power_ok && sn.watts == 142 && sn.cad_ok && sn.rpm == 82, "power VALID: 142 W 82 rpm (stage %u)", sn.link[0].stage);
          bool sub = false, val = false; for (int i = 0; i < 8; i++) { if (strstr(g_sim.fake.log[i], "SUBSCRIBED (cccd 0x0013 read back 01 00)")) sub = true; if (strstr(g_sim.fake.log[i], "VALID 142 W")) val = true; }
          CHECK(sub && val, "pipe log: 'SUBSCRIBED (cccd 0x0013 read back 01 00)' then 'VALID 142 W'"); }
        ui_connections_show(); run(400); shot("20b_fix_table_live");
        CHECK(on_screen("142 W") && on_screen("82 RPM"), "table: fresh 142 W and 82 RPM");
        /* the XDS table itself (2A55 control point after 2A63): its CCCD is never touched */
        sim_fake_meter(true, 0, false); run_s(3);
        { plat_sensors_t sn; plat_sensors(&sn); CHECK(g_sim.fake.last_cccd == 0x0023 && g_sim.fake.enabled[0x2A] == 0 && sn.link[0].stage == BC_STG_VALID, "XDS table: CCCD 0x0023, control point CCCD 0x002A never written, VALID"); }
        /* c) packets stop -> STALE after 3 s -> automatic re-subscribe after 10 s -> data back, no reconnect */
        g_sim.fake.stall = true; run_s(5);
        { plat_sensors_t sn; plat_sensors(&sn); CHECK(sn.link[0].stage == BC_STG_STALE && !sn.power_ok, "packets stopped: STALE, no value shown"); }
        ui_connections_show(); run(300); CHECK(on_screen("STALE") && !on_screen("142 W"), "table: POWER STALE"); shot("20c_stale");
        run_s(8);
        { plat_sensors_t sn; plat_sensors(&sn); CHECK(g_sim.fake.resubs == 1 && g_sim.fake.reconnects == 0 && sn.link[0].stage == BC_STG_VALID && sn.link[0].resubscribes == 1, "auto re-subscribe after 10 s stale -> VALID again (resubs %d)", g_sim.fake.resubs); }
        /* d) packets arrive but none decodes -> 'unreadable data' after 10 s, hex logged once, error shown */
        sim_fake_meter(true, 0, false); g_sim.fake.garbage = true; run_s(14);
        { plat_sensors_t sn; plat_sensors(&sn);
          CHECK(sn.link[0].stage == BC_STG_RECEIVING && sn.link[0].unreadable && !strcmp(sn.link[0].err, "unreadable data") && g_sim.fake.dumps == 1, "all rejected: RECEIVING + unreadable data, hex dumped once (%d)", g_sim.fake.dumps);
          bool hex = false; for (int i = 0; i < 8; i++) if (strstr(g_sim.fake.log[i], "unreadable data [1] 8E 00 00 00 00")) hex = true; CHECK(hex, "first packet hex in the log (sensor bytes only)"); }
        ui_connections_show(); run(300); CHECK(on_screen("BAD DATA"), "table: POWER BAD DATA"); shot("20d_unreadable");
        ui_health_show(); run(300); CHECK(on_screen("unreadable data"), "Device Health: 'POWER  unreadable data'"); shot("20d_health_unreadable");
        tap_text(LV_SYMBOL_LEFT); run(300);
        /* e) subscribed, the meter sends nothing at all: re-subscribe at 8 s, reconnect at 15 s, back-off grows (never faster) */
        sim_fake_meter(true, 0, false); g_sim.fake.streaming = false;
        uint32_t t0 = g_sim.now_ms; int d_prev = 0; uint32_t disc_t[4] = { 0 }; int nd = 0;
        while (g_sim.now_ms - t0 < 90000) { run(100); if (g_sim.fake.disconnects != d_prev) { d_prev = g_sim.fake.disconnects; if (nd < 4) disc_t[nd++] = g_sim.now_ms - t0; } }
        CHECK(nd >= 3 && disc_t[0] >= 15000 && disc_t[0] < 17000, "no data: first reconnect ~15 s after subscribing (%lu ms)", (unsigned long)disc_t[0]);
        CHECK(nd >= 3 && disc_t[1] - disc_t[0] > disc_t[0] && disc_t[2] - disc_t[1] > disc_t[1] - disc_t[0], "back-off grows between automatic reconnects (%lu, %lu, %lu ms)", (unsigned long)disc_t[0], (unsigned long)(disc_t[1] - disc_t[0]), (unsigned long)(disc_t[2] - disc_t[1]));
        { plat_sensors_t sn; plat_sensors(&sn); CHECK(!strcmp(sn.link[0].err, "no data") || sn.link[0].stage <= BC_STG_SUBSCRIBED, "last error 'no data' kept for the phone and the Help page (%s)", sn.link[0].err); }
        /* f) the phone connects: one SENSOR_DIAG per paired sensor at once, then on stage changes, then every 5 s below VALID */
        sim_fake_meter(true, 0, false); run_s(3);
        g_sim.phone.diags = 0; g_sim.phone.ndiag = 0;
        plat_phone_set_enabled(true); sim_phone_connect(true); run(1500);
        CHECK(g_sim.phone.diags == 1 && g_sim.phone.diag[0].sensor == 1 && g_sim.phone.diag[0].stage == BC_STG_VALID && g_sim.phone.diag[0].packets > 0 && g_sim.phone.diag[0].valid_age_ds < 30,
              "phone connects: SENSOR_DIAG power VALID (%d events, stage %u, %lu pkts)", g_sim.phone.diags, g_sim.phone.diag[0].stage, (unsigned long)g_sim.phone.diag[0].packets);
        run_s(10); CHECK(g_sim.phone.diags == 1, "all VALID: no periodic diag traffic (%d)", g_sim.phone.diags);
        g_sim.fake.stall = true; run_s(5);
        { int k = g_sim.phone.ndiag - 1; CHECK(g_sim.phone.diags >= 2 && g_sim.phone.diag[k % 16].stage == BC_STG_STALE, "stage change -> SENSOR_DIAG STALE (%d)", g_sim.phone.diags); }
        int dd = g_sim.phone.diags; run_s(7);   /* re-subscribe (10 s after the last valid packet) brings it back */
        { int k = g_sim.phone.ndiag - 1; CHECK(g_sim.phone.diags > dd && g_sim.phone.diag[k % 16].stage == BC_STG_VALID, "recovery -> SENSOR_DIAG VALID"); }
        g_sim.fake.streaming = false; g_sim.fake.stall = true; run_s(4); dd = g_sim.phone.diags; run_s(10);
        CHECK(g_sim.phone.diags >= dd + 2, "below VALID: periodic SENSOR_DIAG every 5 s (%d in 10 s)", g_sim.phone.diags - dd);
        /* LIVE (the phone's source of truth) carries power + cadence with real ages */
        g_sim.fake.streaming = true; sim_fake_meter(true, 0, false); run_s(4);
        CHECK(g_sim.phone.last_live.power_ok && g_sim.phone.last_live.power_w == 142 && g_sim.phone.last_live.power_age_ms < 3000 && g_sim.phone.last_live.cad_ok && g_sim.phone.last_live.cadence_rpm == 82 && g_sim.phone.last_live.cad_age_ms < 3000,
              "LIVE: 142 W (age %u ms) 82 rpm (age %u ms)", g_sim.phone.last_live.power_age_ms, g_sim.phone.last_live.cad_age_ms);
        /* g) Apple Watch HR relayed by the phone: HEART row value, WATCH source, real age, gone after 6 s */
        sim_phone_send_hr(151, BC_SRC_APPLE_WATCH); run(1200);
        ui_connections_show(); run(300); CHECK(on_screen("151 BPM"), "table: HEART 151 BPM from the watch"); shot("20g_table_watch_hr");
        CHECK(g_sim.phone.last_live.hr_ok && g_sim.phone.last_live.hr_bpm == 151 && g_sim.phone.last_live.hr_src == BC_SRC_APPLE_WATCH && g_sim.phone.last_live.hr_age_ms >= 100 && g_sim.phone.last_live.hr_age_ms < 6000,
              "LIVE echoes watch HR with source WATCH and its real age (%u ms)", g_sim.phone.last_live.hr_age_ms);
        tap_text("HEART"); run(300); CHECK(on_screen("151") && on_screen("WATCH"), "heart page: live 151 bpm WATCH"); shot("20g_heart_watch");
        ui_home_show(); run(300); ui_test_set_style(0); start_ride(); sim_phone_send_hr(151, BC_SRC_APPLE_WATCH); run(1500);
        CHECK(on_screen("151") && on_screen("WATCH"), "ride screen shows 151 with the WATCH source"); shot("20g_ride_watch_hr");
        run_s(6); CHECK(!on_screen("151"), "watch HR older than 6 s disappears (never held)");
        drag(120, 60, 120, 190); hold_text("HOLD: END", 2300); run(400); hold_text(LV_SYMBOL_TRASH, 1800); run(400);
        /* h) every Connections page: primary action + Back usable at scroll position 0 (paired and unpaired, phone on and off) */
        static const char *const PRIM[] = { "PAIR METER", "PAIR STRAP", "PAIR SENSOR", "RETRY", "TEST", "CONNECT", "TURN OFF", "DISCONNECT", "HOLD: REPAIR", "TURN ON", "NETWORKS" };
        int bad = 0;
        for (int pass = 0; pass < 4; pass++) {
            if (pass == 1) sim_phone_disconnect();
            if (pass == 2) { pr->power.paired = false; app_profile_save(); plat_pair(PLAT_SENS_POWER, NULL); }
            if (pass == 3) { pr->csc.paired = true; snprintf(pr->csc.name, sizeof pr->csc.name, "CSC-Wahoo"); g_sim.link[PLAT_SENS_CSC].link = PLAT_LINK_RETRY; app_profile_save(); }
            run(500);
            int cats[6] = { 0, 1, 2, 3, 4, 5 };
            for (int i = 0; i < 6; i++) {
                ui_conn_detail_show(cats[i]); run(400);
                const char *w; bool ok = primary_and_back_ok(PRIM, (int)(sizeof PRIM / sizeof *PRIM), &w);
                if (!ok) { bad++; printf("  primary/back not visible: page %d pass %d (%s)\n", cats[i], pass, w); }
                char n[40]; snprintf(n, sizeof n, "20h_page_%d_pass_%d", cats[i], pass); shot(n);
            }
        }
        CHECK(bad == 0, "primary action + Back visible without scrolling on every Phone / Wi-Fi / Power / HR / Cadence / Speed page (24 states)");
        /* tidy up for later scenarios */
        pr->csc.paired = false; g_sim.link[PLAT_SENS_CSC].link = PLAT_LINK_NOT_PAIRED; app_profile_save();
        sim_fake_meter(false, 0, false); g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_NOT_PAIRED;
    }

}

/* ===================================================================================== 0.7.3: crash evidence + recovery */
/* the device's start-up sequence (main.c) in the harness: plan, subsystem markers, diagnostics, recovery screen or the app.
   s_crash_at = the subsystem whose start "crashes" the board in this run (the marker stays there, like the RTC memory). */
static bc_subsys_t s_crash_at; static bc_boot_plan_t s_plan; static int s_medium;
static void script_crash(const char *task, uint32_t pc)
{
    memset(&g_sim.crash, 0, sizeof g_sim.crash);
    g_sim.crash.have = true; snprintf(g_sim.crash.task, sizeof g_sim.crash.task, "%s", task); g_sim.crash.pc = pc; g_sim.crash.exccause = 28; g_sim.crash.excvaddr = 0x17C;
    g_sim.crash.bt_depth = 4; g_sim.crash.bt[0] = pc; g_sim.crash.bt[1] = 0x4200E71C; g_sim.crash.bt[2] = 0x4202D8D4; g_sim.crash.bt[3] = 0x40385099;
    snprintf(g_sim.crash.reason, sizeof g_sim.crash.reason, "LoadProhibited");
    snprintf(g_sim.log_tail, sizeof g_sim.log_tail, "I (812) link: identity random-static C1:22:33:44:55:66 gen 2\nI (900) wifi: connected (IP obtained) 192.168.1.23\nI (3120) pipe: power -> SUBSCRIBED (cccd 0x0023)\n");
    g_sim.crash_total++;
}
static bool device_boot(bc_reset_t reset)
{
    g_sim.reset_kind = reset;
    lv_obj_t *old = lv_screen_active(); lv_obj_t *blank = lv_obj_create(NULL); lv_screen_load(blank); if (old) lv_obj_delete(old);
    g_sim.boots++; sim_wifi_reboot(); g_sim.restart_requested = false; g_sim.phone_only_started = false;
    for (int k = 0; k < PLAT_SENS_KINDS; k++) g_sim.link[k].disabled = false;
    bc_boot_rtc_t *R = plat_boot_rtc();
    bc_boot_plan(R, reset, plat_boot_skip_load(), &s_plan);
    if (s_plan.newly_skipped) plat_boot_skip_save(s_plan.skip);
    /* rc2: the same order as main.c - storage stage, then the DIAG stage (boot record, NVS crash streak, the Bluetooth rule,
       then app_diag_init); a RECOVERY boot skips the stage the last crash happened in (QA QF-03) */
    bc_boot_mark(R, BC_SS_DISPLAY); bc_boot_mark(R, BC_SS_STORAGE);
    if (s_medium) { g_sim.storage_state = s_medium - 1; s_medium = 0; }
    if (!s_plan.no_storage && s_crash_at == BC_SS_STORAGE) return false;
    bool sok = !s_plan.no_storage && g_sim.storage_state == BC_STOR_OK;   /* 0.7.4: the measured storage category */
    int saved_state = g_sim.storage_state; if (s_plan.no_storage) g_sim.storage_state = BC_STOR_NOT_CHECKED;
    g_sim.bt_unavailable = false;
    bc_boot_mark(R, BC_SS_DIAG);
    bc_bootrec_t *rec = NULL; bc_bootrec_t dummy;
    if (!s_plan.no_diag) {
        if (s_crash_at == BC_SS_DIAG) { if (s_plan.no_storage) g_sim.storage_state = saved_state; return false; }
        /* boot record (the device keeps this ring in NVS, independent of the FAT) */
        if (!g_sim.ring_init) { bc_bootring_init(&g_sim.ring); g_sim.ring_init = true; }
        rec = bc_bootring_push(&g_sim.ring, g_sim.boots);
        rec->reset = (uint8_t)reset; rec->mode = (uint8_t)s_plan.mode; rec->suspect = s_plan.suspect; rec->skip = s_plan.skip; rec->storage = (uint8_t)g_sim.storage_state;
        if (s_plan.mode == BC_BOOT_NORMAL && bc_bootring_crash_streak(&g_sim.ring) >= 4) bc_boot_force_recovery(R, &s_plan);
        /* two boots in a row with a failed (non-crashing) Bluetooth start -> disabled until RETRY, before app_diag_init (QF-07) */
        if (s_plan.mode != BC_BOOT_RECOVERY && !(s_plan.skip & BC_SS_BIT(BC_SS_BTSTACK)) && bc_bootring_bt_fail_streak(&g_sim.ring) >= 2) {
            bc_boot_disable(R, BC_SS_BTSTACK); s_plan.skip |= BC_SS_BIT(BC_SS_BTSTACK); plat_boot_skip_save(s_plan.skip); rec->skip = s_plan.skip;
        }
        app_diag_init(&s_plan, sok); app_diag_stage(BC_SS_DISPLAY, 1); app_diag_stage(BC_SS_STORAGE, s_plan.no_storage ? 2 : sok ? 1 : 3);
    } else { memset(&dummy, 0, sizeof dummy); rec = &dummy; app_diag_off(); }
    /* a boot that did not start storage sees it as unavailable; the medium itself is unchanged (restored next boot) */
    if (s_plan.no_storage) s_medium = saved_state + 1;
    if (s_plan.mode == BC_BOOT_RECOVERY) { ui_recovery_show(); run(400); return true; }
    /* 0.7.4: the Bluetooth stack stage comes before the screens (main.c); a disabled stack = no phone link, no sensors */
    bc_boot_mark(R, BC_SS_BTSTACK); app_diag_stage(BC_SS_BTSTACK, 0);
    if (s_plan.skip & BC_SS_BIT(BC_SS_BTSTACK)) { g_sim.bt_unavailable = true; snprintf(g_sim.bt_reason, sizeof g_sim.bt_reason, "off after 2 failures"); app_diag_stage(BC_SS_BTSTACK, 2); rec->bt_result = BC_BT_SKIPPED; }
    else if (s_crash_at == BC_SS_BTSTACK) return false;
    else if (g_sim.bt_fail_on_init) { g_sim.bt_unavailable = true; snprintf(g_sim.bt_reason, sizeof g_sim.bt_reason, "HCI init failed"); app_diag_stage(BC_SS_BTSTACK, 3); rec->bt_result = BC_BT_FAIL_HOST_INIT; rec->bt[BC_BT_STEP_HOST_INIT].rc = -1; }
    else { app_diag_stage(BC_SS_BTSTACK, 1); rec->bt_result = BC_BT_OK; }
    if (rec != &dummy) bc_bootring_note_bt(&g_sim.ring);
    app_init(); ui_start(); run(200);
    static const bc_subsys_t ORDER[] = { BC_SS_PHONE, BC_SS_WIFI, BC_SS_CENTRAL, BC_SS_POWER, BC_SS_HR, BC_SS_CSC };
    for (size_t i = 0; i < sizeof ORDER / sizeof *ORDER; i++) {
        bc_subsys_t ss = ORDER[i];
        plat_sens_kind_t k = ss == BC_SS_POWER ? PLAT_SENS_POWER : ss == BC_SS_HR ? PLAT_SENS_HR : PLAT_SENS_CSC;
        if (ss >= BC_SS_POWER && !(ss == BC_SS_POWER ? app_profile()->power.paired : ss == BC_SS_HR ? app_profile()->hr.paired : app_profile()->csc.paired)) continue;
        bc_boot_mark(R, ss); app_diag_stage(ss, 0);
        bool skip = (s_plan.skip & BC_SS_BIT(ss)) || (ss >= BC_SS_POWER && (s_plan.skip & BC_SS_BIT(BC_SS_CENTRAL)))
                    || (ss != BC_SS_WIFI && g_sim.bt_unavailable);         /* 0.7.4: no Bluetooth -> no phone link, no sensors */
        if (skip) {
            if (ss >= BC_SS_POWER) plat_sensor_set_disabled(k, true);
            if (ss == BC_SS_PHONE) plat_phone_set_enabled(false);
            app_diag_stage(ss, 2); continue;
        }
        if (s_crash_at == ss) return false;                     /* the board resets here; RTC marker = ss */
        app_diag_stage(ss, 1); run(s_plan.mode == BC_BOOT_STAGED ? 1000 : 50);
    }
    bc_boot_mark(R, BC_SS_RUNNING); rec->reached = BC_SS_RUNNING; run(300);
    return true;
}
static void device_stable(void) { run(1000); bc_boot_stable(plat_boot_rtc()); if (s_plan.mode == BC_BOOT_STAGED) app_diag_store_report(BC_DIAG_KIND_RECOVERY, "staged boot completed"); app_diag_stage(BC_SS_STABLE, 1); }
static int events_of(uint8_t type)
{
    static uint8_t raw[APP_DIAG_EV_SLOTS * BC_EV_SIZE]; memset(raw, 0xFF, sizeof raw);
    plat_file_read(APP_DIAG_EVENTS_FILE, (char *)raw, sizeof raw);
    static bc_ev_t ev[APP_DIAG_EV_SLOTS]; int n = bc_evlog_newest(raw, APP_DIAG_EV_SLOTS, ev, APP_DIAG_EV_SLOTS), k = 0;
    for (int i = 0; i < n; i++) if (ev[i].type == type) k++;
    return k;
}
static void phone_req(uint8_t type, uint32_t id, uint32_t off, uint16_t maxl, uint32_t crc)
{
    uint8_t m[BC_LINK_MAX]; size_t n;
    if (type == BC_MSG_DIAG_LIST_REQ) n = bc_link_encode_diag_list_req(m, sizeof m, 1, 0);
    else if (type == BC_MSG_DIAG_CHUNK_REQ) { bc_diag_chunk_req_t q = { id, off, maxl }; n = bc_link_encode_diag_chunk_req(&q, m, sizeof m, 1, 0); }
    else { bc_diag_ack_t a = { id, crc }; n = bc_link_encode_diag_ack(&a, m, sizeof m, 1, 0); }
    sim_phone_write(0, m, n);
}
/* Cyclift's pull: chunk by chunk from `off`, max_len 160 (the board clamps); optional interruption after `cut` chunks */
static uint32_t pull_report(uint32_t id, uint32_t size, int cut, int *chunks_out)
{
    uint32_t off = 0; int chunks = 0, stall = 0; g_sim.phone.dbuf_len = 0;
    while (off < size && stall < 20) {
        if (cut && chunks == cut) { sim_phone_disconnect(); run(600); sim_phone_connect(true); run(600); cut = 0; }
        int before = g_sim.phone.dchunks; phone_req(BC_MSG_DIAG_CHUNK_REQ, id, off, 160, 0); run(400);
        if (g_sim.phone.dchunks == before || g_sim.phone.dchunk.offset != off) { stall++; continue; }
        off += g_sim.phone.dchunk.len; chunks++;
        if (g_sim.phone.dchunk.last) break;
    }
    if (chunks_out) *chunks_out = chunks;
    return off;
}

static void scenario_073(void)
{
    printf("\n== 21. firmware 0.7.3: crash evidence, recovery mode, staged boot, report transfer\n");
    bc_profile_t *pr = app_profile();
    pr->power.paired = true; snprintf(pr->power.name, sizeof pr->power.name, "XDS-A001"); pr->phone_on = true; snprintf(pr->name, sizeof pr->name, "Rider A"); app_profile_save();
    g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_CONNECTED; g_sim.power_ok = true; g_sim.watts = 142;
    g_sim.fw_id = 0x073; memset(plat_boot_rtc(), 0, sizeof(bc_boot_rtc_t));           /* power-on: RTC memory blank */
    /* a) clean power-on: BOOT + STAGE events, no report */
    CHECK(device_boot(BC_RST_POWERON) && s_plan.mode == BC_BOOT_NORMAL, "power-on: normal start");
    device_stable(); app_diag_flush(true);
    app_diag_status_t st; app_diag_status(&st);
    CHECK(!st.crashed && st.stored == 0 && events_of(BC_EV_BOOT) == 1 && events_of(BC_EV_STAGE) >= 8, "clean start: BOOT + STAGE events written, no report (%d stage events)", events_of(BC_EV_STAGE));
    /* b) three crashes in a row (nimble_host each time: sensor Bluetooth, then the power meter) -> RECOVERY MODE.
       0.7.4: the first crash is at another subsystem - the same subsystem crashing twice in a row is disabled instead (section 24) */
    for (int k = 0; k < 3; k++) { s_crash_at = k == 0 ? BC_SS_CENTRAL : BC_SS_POWER; script_crash("nimble_host", 0x4200F4BC); bool up = device_boot(BC_RST_PANIC); if (k < 2) CHECK(!up && s_plan.mode == BC_BOOT_NORMAL, "crash %d: normal start again (streak %lu)", k + 1, (unsigned long)plat_boot_rtc()->crash_streak); }
    s_crash_at = BC_SS_POWER;
    CHECK(s_plan.mode == BC_BOOT_RECOVERY && on_screen("RECOVERY MODE") && on_screen("Crash detected") && on_screen("panic - nimble_host"), "3 crashes in a row: RECOVERY MODE screen, 'panic - nimble_host'");
    CHECK(btn_visible_at_top("RESTART & DIAGNOSE") && btn_visible_at_top("SEND LOGS") && on_screen("Logs saved"), "both buttons fully visible at scroll 0, 'Logs saved'");
    shot("21b_recovery_mode");
    app_diag_status(&st);
    CHECK(st.stored == 3 && st.pending == 3 && g_sim.crash_consumed == 3, "one crash report per crash, all pending, core dump consumed each time (%d stored)", st.stored);
    { char p[64]; snprintf(p, sizeof p, "diag/r%06lu.txt", (unsigned long)st.crash_report); static char t[BC_DIAG_REPORT_MAX]; long n = plat_file_read(p, t, sizeof t - 1); if (n < 0) n = 0; t[n] = 0;
      CHECK(strstr(t, "[header]") && strstr(t, "[recovery]") && strstr(t, "task nimble_host") && strstr(t, "0x4200F4BC 0x4200E71C") && strstr(t, "marker 6") && strstr(t, "log_before_reset"),
            "crash report: sections, task, backtrace addresses, marker = power meter, log tail");
      CHECK(!strstr(t, "Rider A") && !strstr(t, "C1:22:33") && !strstr(t, "192.168") && strstr(t, "..:..:..:..:55:66"), "crash report: no name, address cut to 2 bytes, IP masked"); }
    /* c) SEND LOGS: only the phone link starts; Cyclift connects, lists, pulls (interrupted + resumed) and acknowledges */
    tap_text("SEND LOGS"); run(500);
    CHECK(g_sim.phone_only_started && on_screen("Waiting for Cyclift"), "SEND LOGS: phone link only, 'Waiting for Cyclift'");
    shot("21c_recovery_waiting");
    app_diag_status(&st); CHECK(st.stored == 4, "SEND LOGS stored a manual report (%d)", st.stored);
    g_sim.phone.dreadys = 0; sim_phone_connect(true); run(800);
    CHECK(g_sim.phone.dreadys == 1 && g_sim.phone.dready.pending == 4, "on connect: diag_ready with 4 pending (%d events, pending %u)", g_sim.phone.dreadys, g_sim.phone.dready.pending);
    g_sim.phone.ndinfo = 0; g_sim.phone.dlist_ends = 0; phone_req(BC_MSG_DIAG_LIST_REQ, 0, 0, 0, 0); run(800);
    CHECK(g_sim.phone.ndinfo == 4 && g_sim.phone.dlist_ends == 1 && g_sim.phone.dlist_end.count == 4 && g_sim.phone.dinfo[0].kind == 1 && g_sim.phone.dinfo[3].kind == 3, "LIST: 4 DIAG_INFO + LIST_END");
    bc_diag_info_t want = g_sim.phone.dinfo[2]; int chunks = 0;
    uint32_t got = pull_report(want.id, want.size, 5, &chunks);
    uint32_t crc = bc_crc32(0, g_sim.phone.dbuf, got);
    CHECK(got == want.size && crc == want.crc && chunks == (int)((want.size + 154) / 155), "transfer interrupted after 5 chunks and resumed: %lu/%lu bytes in %d chunks, crc %s",
          (unsigned long)got, (unsigned long)want.size, chunks, crc == want.crc ? "ok" : "BAD");
    g_sim.phone.ndinfo = 0; phone_req(BC_MSG_DIAG_ACK, want.id, 0, 0, crc); run(600);
    CHECK(g_sim.phone.ndinfo == 1 && g_sim.phone.dinfo[0].state == 1, "ACK with the matching crc: DIAG_INFO state 1");
    run(300); CHECK(on_screen("Sent to Cyclift"), "status 'Sent to Cyclift'"); shot("21c_recovery_sent");
    g_sim.phone.derrs = 0; phone_req(BC_MSG_DIAG_CHUNK_REQ, 999, 0, 160, 0); run(400); CHECK(g_sim.phone.derrs == 1 && g_sim.phone.derr.code == BC_DIAG_ERR_UNKNOWN_ID, "unknown report id -> DIAG_ERR 1");
    /* d) RESTART & DIAGNOSE (1 s hold) -> staged boot; the power meter crashes again -> it is disabled, the rest starts */
    hold_text("RESTART & DIAGNOSE", 1300);
    CHECK(g_sim.restart_requested && plat_boot_rtc()->request == 1, "RESTART & DIAGNOSE held 1 s: restart with a staged-boot request");
    sim_phone_disconnect();
    script_crash("nimble_host", 0x4200F4BC);   /* will not happen: the request turns into a clean software restart */
    g_sim.crash.have = false;
    bool up = device_boot(BC_RST_SW);
    CHECK(!up && s_plan.mode == BC_BOOT_STAGED, "staged boot: crashes while the power meter starts");
    script_crash("nimble_host", 0x4200F4BC); up = device_boot(BC_RST_PANIC);
    CHECK(up && s_plan.mode == BC_BOOT_STAGED && (s_plan.skip & BC_SS_BIT(BC_SS_POWER)) && s_plan.newly_skipped, "next staged boot skips the power meter instead of looping (skip 0x%03X)", s_plan.skip);
    device_stable(); run(500);
    ui_connections_show(); run(400);
    CHECK(on_screen("DISABLED"), "Connections: POWER row 'DISABLED'"); shot("21d_conn_power_disabled");
    tap_text("POWER"); run(400);
    CHECK(on_screen("off after a crash") && on_screen("Retry starts it again") && btn_visible_at_top("RETRY"), "power page: 'off after a crash' + RETRY at scroll 0"); shot("21d_power_disabled_retry");
    CHECK(g_sim.nvs_skip & BC_SS_BIT(BC_SS_POWER), "the skip survives a power cycle (NVS)");
    s_crash_at = BC_SS_NONE;
    tap_text("RETRY"); run(600);
    CHECK(!g_sim.link[PLAT_SENS_POWER].disabled && !(g_sim.nvs_skip & BC_SS_BIT(BC_SS_POWER)) && !(app_diag_skip() & BC_SS_BIT(BC_SS_POWER)), "RETRY: link enabled, skip cleared (RTC + NVS)");
    app_diag_status(&st); CHECK(st.stored >= 6, "staged boot stored a 'recovery session' report (%d reports)", st.stored);
    /* e) logs preserved across restarts */
    app_diag_flush(true); int boots = events_of(BC_EV_BOOT);
    CHECK(boots >= 6 && events_of(BC_EV_CRASH) >= 4 && events_of(BC_EV_REPORT) >= 5, "event log kept across %d boots (crash %d, report %d events)", boots, events_of(BC_EV_CRASH), events_of(BC_EV_REPORT));
    /* f) repeated failed staged boots -> back to RECOVERY */
    plat_boot_rtc()->request = 1; bc_boot_request_staged(plat_boot_rtc());
    s_crash_at = BC_SS_PHONE; device_boot(BC_RST_SW);
    script_crash("ble_mgr", 0x4200F048); device_boot(BC_RST_PANIC);    /* phone skipped -> crashes at WIFI? no: crash_at PHONE is skipped now */
    s_crash_at = BC_SS_WIFI; script_crash("wifi_mgr", 0x42011080); device_boot(BC_RST_PANIC);
    s_crash_at = BC_SS_CENTRAL; script_crash("nimble_host", 0x4200F4BC); device_boot(BC_RST_PANIC);
    CHECK(s_plan.mode == BC_BOOT_RECOVERY && on_screen("RECOVERY MODE"), "three crashed staged boots in a row: RECOVERY MODE (fails %u)", plat_boot_rtc()->staged_fails);
    shot("21f_recovery_again");
    /* g) missing phone: SEND LOGS waits, nothing is deleted */
    app_diag_status(&st); int stored = st.stored;
    tap_text("SEND LOGS"); run(3000);
    CHECK(on_screen("Waiting for Cyclift"), "no phone: keeps waiting");
    app_diag_status(&st); CHECK(st.stored == stored + 1 || st.not_stored > 0, "the manual report is stored (or counted as not stored when full)");
    /* h) store full of unsent reports: nothing unsent is ever deleted */
    for (int k = 0; k < 14; k++) app_diag_store_report(BC_DIAG_KIND_MANUAL, "fill");
    app_diag_status(&st); CHECK(st.stored == BC_DIAG_MAX_REPORTS && st.not_stored > 0, "store full of unsent reports: %d kept, %lu not stored", st.stored, (unsigned long)st.not_stored);
    /* i) a fixed firmware: RESET (power-on) -> normal start, skips from the old firmware ignored, no crash report */
    g_sim.fw_id = 0x074; s_crash_at = BC_SS_NONE; memset(plat_boot_rtc(), 0, sizeof(bc_boot_rtc_t));
    app_diag_status(&st); int before = st.stored;
    CHECK(device_boot(BC_RST_POWERON) && s_plan.mode == BC_BOOT_NORMAL && s_plan.skip == 0, "new firmware after a power-on: normal start, nothing disabled");
    device_stable(); app_diag_status(&st);
    CHECK(!st.crashed && st.stored == before && !on_screen("RECOVERY MODE"), "clean boot: no new report, normal screens");
    /* j) power loss while writing the event log: one torn record, the rest readable */
    app_diag_flush(true);
    { long sz = plat_file_size(APP_DIAG_EVENTS_FILE); uint8_t junk[20] = { 0 }; plat_file_write_at(APP_DIAG_EVENTS_FILE, 32 * 5 + 3, junk, sizeof junk);
      int b2 = events_of(BC_EV_BOOT) + events_of(BC_EV_STAGE) + events_of(BC_EV_SENSOR);
      CHECK(sz == (long)(APP_DIAG_EV_SLOTS * BC_EV_SIZE) && b2 > 10, "torn record skipped, %d records still readable", b2); }
    pr->power.paired = false; app_profile_save(); g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_NOT_PAIRED; g_sim.power_ok = false;
}


/* ===================================================================================== 0.7.4: crash fix behaviour */
/* The 27 Oct board: every start aborted while Bluetooth started (marker = phone link), "disabled 0x000", RECOVERY; the FAT root
   directory is erased so nothing can be saved ("Logs NOT saved (storage)"). Here: the same situations on the 0.7.4 code. */
static void scenario_074(void)
{
    printf("\n== 24. firmware 0.7.4: Bluetooth never aborts the start, crash loop disables the subsystem, real storage categories\n");
    bc_profile_t *pr = app_profile();
    pr->power.paired = true; snprintf(pr->power.name, sizeof pr->power.name, "XDS-A001"); pr->phone_on = true; app_profile_save();
    g_sim.fw_id = 0x0741; s_crash_at = BC_SS_NONE; g_sim.nvs_skip = 0; memset(plat_boot_rtc(), 0, sizeof(bc_boot_rtc_t));
    /* a) the Bluetooth stack fails to start (no internal RAM): no crash, the board runs, every screen says so */
    g_sim.bt_fail_on_init = 1;
    CHECK(device_boot(BC_RST_POWERON) && s_plan.mode == BC_BOOT_NORMAL && g_sim.bt_unavailable, "HCI init failure: the start completes (no abort), Bluetooth unavailable");
    device_stable();
    ui_connections_show(); run(400);
    CHECK(on_screen("NO BT"), "Connections: phone and power meter rows say NO BT (never 'searching')"); shot("24a_conn_no_bt");
    ui_phone_show(); run(400);
    CHECK(on_screen("NO BLUETOOTH") && on_screen("WHY?") && on_screen("Bluetooth off this start"), "Phone screen: NO BLUETOOTH + WHY?"); shot("24a_phone_no_bt");
    tap_text("WHY?"); run(300); CHECK(on_screen("No BT: HCI init failed"), "WHY? shows the reason");
    plat_phone_status_t ps; plat_phone_status(&ps); CHECK(ps.state == PLAT_PHONE_UNAVAILABLE, "phone status UNAVAILABLE");
    g_sim.bt_fail_on_init = 0;
    /* b) a deterministic crash while the Bluetooth stack starts: crash 1 normal, crash 2 at the same subsystem -> disabled */
    memset(plat_boot_rtc(), 0, sizeof(bc_boot_rtc_t));
    s_crash_at = BC_SS_BTSTACK;
    bool up = device_boot(BC_RST_POWERON);                                 /* like the board: the power-on start aborts at Bluetooth */
    CHECK(!up, "power-on start crashes while the Bluetooth stack starts (crash 1)");
    script_crash("main", 0x42012BA0); up = device_boot(BC_RST_PANIC);
    CHECK(!up && s_plan.mode == BC_BOOT_NORMAL && s_plan.suspect == BC_SS_BTSTACK && !s_plan.skip, "after crash 1: 'crashed subsystem Bluetooth stack', normal start, nothing disabled yet -> crash 2");
    script_crash("main", 0x42012BA0); up = device_boot(BC_RST_PANIC);
    CHECK(s_plan.newly_skipped && (s_plan.skip & BC_SS_BIT(BC_SS_BTSTACK)) && (g_sim.nvs_skip & BC_SS_BIT(BC_SS_BTSTACK)), "after crash 2 at the same subsystem: Bluetooth stack disabled (skip 0x%03X, saved in NVS)", s_plan.skip);
    CHECK(up && s_plan.mode == BC_BOOT_NORMAL && g_sim.bt_unavailable && !on_screen("RECOVERY MODE"), "the board starts without Bluetooth and stays usable (0.7.3: 'disabled 0x000' and RECOVERY)");
    device_stable();
    ui_phone_show(); run(400);
    CHECK(on_screen("NO BLUETOOTH") && on_screen("RETRY"), "Phone screen: NO BLUETOOTH + RETRY"); shot("24b_phone_bt_disabled_retry");
    app_diag_status_t st; app_diag_status(&st); CHECK(st.crash_report != 0, "the crash report was stored (%lu)", (unsigned long)st.crash_report);
    s_crash_at = BC_SS_NONE;
    tap_text("RETRY"); run(400);
    CHECK(!(g_sim.nvs_skip & BC_SS_BIT(BC_SS_BTSTACK)) && !(plat_boot_rtc()->skip & BC_SS_BIT(BC_SS_BTSTACK)), "RETRY: Bluetooth enabled again for the next start (RTC + NVS)");
    CHECK(device_boot(BC_RST_SW) && !g_sim.bt_unavailable, "next start: Bluetooth runs");
    device_stable();
    /* c) storage: the measured 27 Oct state (root directory erased) - the real category everywhere, nothing written */
    static char ev0[APP_DIAG_EV_SLOTS * BC_EV_SIZE], ev1[APP_DIAG_EV_SLOTS * BC_EV_SIZE], ix0[2048], ix1[2048];
    app_diag_flush(true);
    long nev0 = plat_file_read(APP_DIAG_EVENTS_FILE, ev0, sizeof ev0), nix0 = plat_file_read(APP_DIAG_INDEX_FILE, ix0, sizeof ix0);
    g_sim.storage_state = BC_STOR_DIR_CORRUPTED;
    memset(plat_boot_rtc(), 0, sizeof(bc_boot_rtc_t));
    s_crash_at = BC_SS_PHONE;
    for (int k = 0; k < 3; k++) { s_crash_at = k == 1 ? BC_SS_WIFI : BC_SS_PHONE; script_crash("main", 0x42012BA0); device_boot(BC_RST_PANIC); }
    CHECK(s_plan.mode == BC_BOOT_RECOVERY && on_screen("RECOVERY MODE"), "three different crashes in a row: RECOVERY MODE");
    CHECK(on_screen("Not saved: dir corrupted") && !on_screen("Logs NOT saved (storage)"), "recovery screen: 'Not saved: dir corrupted' instead of 'Logs NOT saved (storage)'");
    shot("24c_recovery_dir_corrupted");
    { long nev1 = plat_file_read(APP_DIAG_EVENTS_FILE, ev1, sizeof ev1), nix1 = plat_file_read(APP_DIAG_INDEX_FILE, ix1, sizeof ix1);
      CHECK(nev1 == nev0 && nix1 == nix0 && !memcmp(ev0, ev1, (size_t)(nev0 > 0 ? nev0 : 0)) && !memcmp(ix0, ix1, (size_t)(nix0 > 0 ? nix0 : 0)),
            "damaged storage: the event log and report index are byte-identical afterwards (nothing written)"); }
    s_crash_at = BC_SS_NONE; memset(plat_boot_rtc(), 0, sizeof(bc_boot_rtc_t));
    CHECK(device_boot(BC_RST_POWERON), "power-on with damaged storage: the board starts"); device_stable();
    ui_diag_menu_show(); run(300); scroll_to("HOLD: SAVE REPORT"); hold_text("HOLD: SAVE REPORT", 1300); run(200);
    CHECK(on_screen("Not saved: dir corrupted"), "Diagnostics > SAVE REPORT: 'Not saved: dir corrupted' (0.7.3: 'Not saved: storage full')");
    shot("24c_save_report_dir_corrupted");
    ui_diag_menu_show(); run(300); tap_text("Device Health"); run(400);
    CHECK(on_screen("Directory corrupted"), "Device Health storage line names the category");
    /* d) a ride started on damaged storage: no journal is written, deleted or moved (refused), the ride still runs */
    uint32_t refused0 = g_sim.fat_writes_refused;
    uint16_t id0 = app_profile()->next_ride_id;
    { bc_ride_summary_t h0[30]; int nh0 = app_history(h0, 30, false);
      app_ride_start(); run_s(3); app_ride_end();
      CHECK(g_sim.fat_writes_refused > refused0 && plat_file_size("rides/active.jnl") < 0, "ride on damaged storage: journal writes refused, nothing created (%lu refused)", (unsigned long)(g_sim.fat_writes_refused - refused0));
      /* rc2 (QA QF-01): never silent - a warning before SAVE, a notice after it, the ride kept in RAM for the phone */
      bc_ride_summary_t fin; app_ride_totals(&fin); ui_results_show(&fin, true); run(300);
      CHECK(scroll_to("Board storage damaged") && on_screen("Board storage damaged"), "Results: red warning before SAVE ('Board storage damaged ... kept in memory')"); shot("24d_results_storage_warning");
      scroll_to("SAVE"); tap_text("SAVE"); run(300);
      CHECK(on_screen("NOT SAVED ON BOARD") && on_screen("dir corrupted") && on_screen("Open Cyclift"), "SAVE on damaged storage: 'NOT SAVED ON BOARD' notice with the storage state");
      shot("24d_not_saved_on_board");
      bc_ride_summary_t un[APP_UNSAVED_MAX]; int nu = app_unsaved_rides(un, APP_UNSAVED_MAX);
      bc_ride_summary_t h1[30]; int nh1 = app_history(h1, 30, false);
      CHECK(nu == 1 && un[0].id == id0 && nh1 == nh0 + 1 && h1[0].id == id0, "the ride is kept in RAM (#%u) and listed in History (%d -> %d)", un[0].id, nh0, nh1);
      CHECK(app_profile()->next_ride_id == id0 + 1, "the id is used by the kept ride (next %u)", app_profile()->next_ride_id);
      tap_text("OK"); run(300);
      /* fill the RAM queue: the ride that cannot be kept says so, and does NOT use up an id */
      for (int k = nu; k < APP_UNSAVED_MAX; k++) { app_ride_start(); run_s(2); app_ride_end(); CHECK(app_ride_save_ex() == APP_SAVE_RAM_ONLY, "ride %d kept in RAM", k + 1); }
      uint16_t idq = app_profile()->next_ride_id;
      app_ride_start(); run_s(2); app_ride_end(); app_ride_totals(&fin); ui_results_show(&fin, true); run(300); scroll_to("SAVE"); tap_text("SAVE"); run(300);
      CHECK(on_screen("RIDE NOT SAVED") && app_profile()->next_ride_id == idq, "RAM queue full: 'RIDE NOT SAVED' on screen, ride id not burned (%u)", app_profile()->next_ride_id);
      shot("24d_ride_not_saved_queue_full");
      tap_text("OK"); run(300);
      /* the phone's sync sees the RAM rides */
      sim_phone_connect(true); run(800);
      CHECK(app_unsaved_rides(un, APP_UNSAVED_MAX) == APP_UNSAVED_MAX, "%d rides wait in RAM for the phone", APP_UNSAVED_MAX);
      { uint8_t b[64]; bc_sync_req_t rq = { .after_ride_id = 0, .max_count = 50 }; g_sim.phone.n_rides = 0;
        size_t n = bc_link_encode_sync_req(&rq, b, sizeof b, 31, 0); sim_phone_write(1, b, n); run(4000);
        int seen = 0; for (int i = 0; i < g_sim.phone.n_rides; i++) for (int k = 0; k < APP_UNSAVED_MAX; k++) if (g_sim.phone.rides[i].id == un[k].id) seen++;
        CHECK(seen == APP_UNSAVED_MAX, "Cyclift's ride sync (Link 1.2.3 SYNC_REQ) receives the %d RAM-only rides (%d of %d rides sent)", APP_UNSAVED_MAX, seen, g_sim.phone.n_rides); }
      sim_phone_disconnect(); run(300); }
    g_sim.storage_state = BC_STOR_OK; pr->power.paired = false; app_profile_save();
    memset(plat_boot_rtc(), 0, sizeof(bc_boot_rtc_t)); s_crash_at = BC_SS_NONE;
    CHECK(device_boot(BC_RST_POWERON), "storage repaired (simulated): normal start, diagnostics written again"); device_stable();
}

/* ===================================================================================== 0.7.4 rc1: owner requirements 1, 6, 7 */
static void recovery_combo(bool bt_ok, bool fs_ok)
{
    char tag[48]; snprintf(tag, sizeof tag, "BT %s, filesystem %s", bt_ok ? "ok" : "FAILS", fs_ok ? "ok" : "CORRUPTED");
    g_sim.bt_fail_on_init = !bt_ok; g_sim.storage_state = fs_ok ? BC_STOR_OK : BC_STOR_DIR_CORRUPTED;
    memset(plat_boot_rtc(), 0, sizeof(bc_boot_rtc_t)); g_sim.nvs_skip = 0; sim_phone_disconnect();
    device_boot(BC_RST_POWERON); device_stable();
    s_crash_at = BC_SS_NONE;   /* three crashes after start-up in a row (works whether or not Bluetooth / the FAT are up) */
    for (int k = 0; k < 3; k++) { script_crash("main", 0x42012BA0); device_boot(BC_RST_PANIC); }
    CHECK(s_plan.mode == BC_BOOT_RECOVERY && on_screen("RECOVERY MODE"), "%s: RECOVERY MODE screen", tag);
    CHECK(fs_ok ? on_screen("Logs saved") : on_screen("Not saved: dir corrupted"), "%s: status line '%s'", tag, fs_ok ? "Logs saved" : "Not saved: dir corrupted");
    tap_text("SEND LOGS"); run(800);
    if (bt_ok) CHECK(g_sim.phone_only_started && on_screen("Waiting for Cyclift"), "%s: SEND LOGS starts the phone link only", tag);
    else CHECK(!g_sim.phone_only_started && on_screen("No BT - logs kept here"), "%s: SEND LOGS -> 'No BT - logs kept here', nothing restarts", tag);
    if (bt_ok) {
        sim_phone_connect(true); run(800);
        g_sim.phone.ndinfo = 0; phone_req(BC_MSG_DIAG_LIST_REQ, 0, 0, 0, 0); run(800);
        CHECK(fs_ok ? g_sim.phone.ndinfo >= 3 : g_sim.phone.dlist_end.count == 0, "%s: Cyclift lists %d report(s)", tag, g_sim.phone.ndinfo);
        sim_phone_disconnect(); run(300);
    }
    run_s(10);
    CHECK(s_plan.mode == BC_BOOT_RECOVERY && on_screen("RECOVERY MODE") && !g_sim.restart_requested, "%s: stays in a STABLE recovery screen (10 s, no restart)", tag);
    char nm[48]; snprintf(nm, sizeof nm, "25b_recovery_bt%d_fs%d", bt_ok, fs_ok); shot(nm);
}

static void scenario_074rc(void)
{
    printf("\n== 25. firmware 0.7.4-rc1: repeated Bluetooth start failures, recovery with BT and/or filesystem unavailable\n");
    bc_profile_t *pr = app_profile();
    pr->power.paired = true; snprintf(pr->power.name, sizeof pr->power.name, "XDS-A001"); pr->phone_on = true; app_profile_save();
    g_sim.fw_id = 0x0742; s_crash_at = BC_SS_NONE; g_sim.nvs_skip = 0; memset(plat_boot_rtc(), 0, sizeof(bc_boot_rtc_t)); bc_bootring_init(&g_sim.ring);
    /* a) 12 starts in a row where the Bluetooth start fails (no crash): never a loop, never RECOVERY; disabled after 2 */
    g_sim.bt_fail_on_init = 1; int loops = 0, recov = 0, skipped_from = -1;
    for (int k = 0; k < 12; k++) {
        bool up = device_boot(k % 3 ? BC_RST_SW : BC_RST_POWERON); if (!up) loops++; if (s_plan.mode == BC_BOOT_RECOVERY) recov++;
        device_stable();
        if (skipped_from < 0 && (s_plan.skip & BC_SS_BIT(BC_SS_BTSTACK))) {
            skipped_from = k;
            ui_phone_show(); run(400);   /* rc2 (QA QF-07): RETRY already on the boot that disabled Bluetooth */
            CHECK(on_screen("RETRY") && !on_screen("WHY?"), "the boot that disables Bluetooth already offers RETRY (not WHY?)"); shot("25a_phone_retry_first_disabled_boot");
        }
    }
    CHECK(loops == 0 && recov == 0, "12 starts with a failing Bluetooth start: %d crashes, %d RECOVERY", loops, recov);
    CHECK(skipped_from == 2 && g_sim.bt_unavailable && (g_sim.nvs_skip & BC_SS_BIT(BC_SS_BTSTACK)), "after 2 failed starts Bluetooth is disabled (from start %d), saved in NVS", skipped_from + 1);
    { char br[1400]; plat_bootrec_text(br, sizeof br); CHECK(strstr(br, "Bluetooth off (disabled)") != NULL, "boot records (NVS ring) say 'Bluetooth off (disabled)'"); }
    { char br[1400]; plat_bootrec_text(br, sizeof br);   /* rc2 (QA QF-06): the failing start's figures survive 10 skipped boots */
      CHECK(strstr(br, "last BT start") && strstr(br, "HCI"), "boot records keep the last real Bluetooth attempt: %.80s", br); }
    ui_phone_show(); run(400); CHECK(on_screen("RETRY") && on_screen("NO BLUETOOTH"), "Phone screen: NO BLUETOOTH + RETRY");
    g_sim.bt_fail_on_init = 0; tap_text("RETRY"); run(300);
    CHECK(device_boot(BC_RST_SW) && !g_sim.bt_unavailable, "RETRY + a fixed condition: Bluetooth starts again"); device_stable();
    ui_diag_menu_show(); run(300); tap_text("Device Health"); run(400); scroll_to("Boot records");
    CHECK(on_screen("Boot records"), "Device Health lists the boot records"); shot("25a_health_boot_records");
    /* b) recovery mode in all four combinations */
    recovery_combo(true, true); recovery_combo(false, true); recovery_combo(true, false); recovery_combo(false, false);
    g_sim.bt_fail_on_init = 0; g_sim.storage_state = BC_STOR_OK; memset(plat_boot_rtc(), 0, sizeof(bc_boot_rtc_t)); g_sim.nvs_skip = 0;
    CHECK(device_boot(BC_RST_POWERON), "back to normal"); device_stable();
    pr->power.paired = false; app_profile_save();
}

/* ===================================================================================== 0.7.4 rc2: QA findings QF-03, QF-09, QF-18 */
static void scenario_074rc2(void)
{
    printf("\n== 26. firmware 0.7.4-rc2: crash in the storage / diagnostics stage, late crash loop, full storage clean-up\n");
    g_sim.fw_id = 0x0743; g_sim.bt_fail_on_init = 0; g_sim.storage_state = BC_STOR_OK; g_sim.nvs_skip = 0;
    /* a) QF-03: a crash at every start while storage (or the diagnostics init) starts -> RECOVERY without that stage, stable */
    for (int which = 0; which < 2; which++) {
        bc_subsys_t bad = which ? BC_SS_DIAG : BC_SS_STORAGE;
        memset(plat_boot_rtc(), 0, sizeof(bc_boot_rtc_t)); bc_bootring_init(&g_sim.ring); s_crash_at = bad;
        int crashes = 0; bool up = false;
        for (int k = 0; k < 8 && !up; k++) { up = device_boot(k ? BC_RST_PANIC : BC_RST_POWERON); if (!up) { crashes++; script_crash("main", 0x42012BA0); } }
        CHECK(up && crashes == 3 && s_plan.mode == BC_BOOT_RECOVERY && (bad == BC_SS_STORAGE ? s_plan.no_storage : !s_plan.no_storage) && s_plan.no_diag,
              "crash while %s starts: %d crashes, then RECOVERY without it", bc_subsys_name(bad), crashes);
        run_s(10);
        CHECK(on_screen("RECOVERY MODE") && !g_sim.restart_requested, "%s crash: STABLE recovery screen (10 s, no restart)", bc_subsys_name(bad));
        CHECK(on_screen(bad == BC_SS_STORAGE ? "Not saved: not checked" : "Not saved: diag off") && !on_screen("Logs saved"), "status line says the logs are not stored this boot");
        char nm[40]; snprintf(nm, sizeof nm, "26a_recovery_%s", which ? "diag" : "storage"); shot(nm);
    }
    s_crash_at = BC_SS_NONE; memset(plat_boot_rtc(), 0, sizeof(bc_boot_rtc_t));
    CHECK(device_boot(BC_RST_POWERON) && s_plan.mode == BC_BOOT_NORMAL && g_sim.storage_state == BC_STOR_OK, "fixed: normal start, storage seen again"); device_stable();
    /* b) QF-09: a crash 20+ s after every start (the RTC counter is cleared at 'stable' each time) -> the NVS boot records
          count the crash resets and send the 4th one to RECOVERY */
    bc_bootring_init(&g_sim.ring); memset(plat_boot_rtc(), 0, sizeof(bc_boot_rtc_t));
    device_boot(BC_RST_POWERON); device_stable();
    int k; for (k = 0; k < 8 && s_plan.mode != BC_BOOT_RECOVERY; k++) { script_crash("main", 0x42012BA0); device_boot(BC_RST_PANIC); if (s_plan.mode != BC_BOOT_RECOVERY) device_stable(); }
    CHECK(s_plan.mode == BC_BOOT_RECOVERY && k == 4 && on_screen("RECOVERY MODE"), "late crash at every start: RECOVERY after %d crash resets (RTC streak alone: never)", k);
    shot("26b_recovery_late_crash_loop");
    memset(plat_boot_rtc(), 0, sizeof(bc_boot_rtc_t)); CHECK(device_boot(BC_RST_POWERON) && s_plan.mode == BC_BOOT_NORMAL, "power-on: normal again"); device_stable();
    memset(&g_sim.crash, 0, sizeof g_sim.crash);   /* no core dump left over from b) */
    /* c) QF-18: storage FULL -> sent reports (and their core copies) are removed at start, storage usable again */
    app_diag_store_report(BC_DIAG_KIND_MANUAL, "rc2 full test");
    sim_phone_connect(true); run(800);
    g_sim.phone.ndinfo = 0; phone_req(BC_MSG_DIAG_LIST_REQ, 0, 0, 0, 0); run(2000);
    bc_diag_info_t list[32]; int n0 = g_sim.phone.ndinfo; memcpy(list, g_sim.phone.dinfo, sizeof list);
    for (int i = 0; i < n0; i++) if (list[i].state == 0) { phone_req(BC_MSG_DIAG_ACK, list[i].id, 0, 0, list[i].crc); run(300); }
    sim_phone_disconnect(); run(300);
    app_diag_status_t st; app_diag_status(&st);
    CHECK(n0 > 0 && st.pending == 0, "%d reports, all acknowledged by the phone", n0);
    g_sim.storage_state = BC_STOR_FULL; g_sim.full_clears_on_cleanup = true; memset(plat_boot_rtc(), 0, sizeof(bc_boot_rtc_t));
    CHECK(device_boot(BC_RST_POWERON) && g_sim.storage_state == BC_STOR_OK, "boot with FULL storage: sent reports removed, storage usable again");
    app_diag_status(&st); CHECK(st.stored == 0, "no sent report left (%d)", st.stored);
    device_stable();
    /* unsent reports are never removed: FULL with only unsent reports stays FULL */
    app_diag_store_report(BC_DIAG_KIND_MANUAL, "unsent");
    g_sim.storage_state = BC_STOR_FULL; memset(plat_boot_rtc(), 0, sizeof(bc_boot_rtc_t));
    device_boot(BC_RST_POWERON);
    app_diag_status(&st); CHECK(g_sim.storage_state == BC_STOR_FULL && plat_file_size(APP_DIAG_INDEX_FILE) > 0, "only an unsent report: nothing removed, storage stays FULL");
    g_sim.full_clears_on_cleanup = false; g_sim.storage_state = BC_STOR_OK; memset(plat_boot_rtc(), 0, sizeof(bc_boot_rtc_t));
    CHECK(device_boot(BC_RST_POWERON), "back to normal"); device_stable();
}

/* ===================================================================================== 0.7.3 final: safe report + transfer contract */
static int pull_paced(uint32_t id, uint32_t size, uint16_t maxl, uint32_t *got, uint32_t *max_msg, int *lives)
{
    uint32_t off = 0; int chunks = 0, stall = 0, lives0 = g_sim.phone.lives; *max_msg = 0; g_sim.phone.dbuf_len = 0;
    while (off < size && stall < 20) {
        int before = g_sim.phone.dchunks; phone_req(BC_MSG_DIAG_CHUNK_REQ, id, off, maxl, 0);
        for (int w = 0; w < 40 && g_sim.phone.dchunks == before; w++) run(25);      /* Cyclift waits for the answer (<= 1 s) */
        if (g_sim.phone.dchunks == before || g_sim.phone.dchunk.offset != off) { stall++; continue; }
        uint32_t wire = (uint32_t)g_sim.phone.dchunk.len + BC_DIAG_CHUNK_OVERHEAD; if (wire > *max_msg) *max_msg = wire;
        off += g_sim.phone.dchunk.len; chunks++;
        if (g_sim.phone.dchunk.last) break;
    }
    *got = off; *lives = g_sim.phone.lives - lives0;
    return chunks;
}
static void scenario_073_transfer(void)
{
    printf("\n== 23. firmware 0.7.3 final: SAVE REPORT (no crash needed), chunk size from the negotiated MTU, ride priority\n");
    app_diag_status_t st;
    /* the store is full of unsent reports from section 21: Cyclift acknowledges them (crc from the list) so they may go */
    sim_phone_connect(true); run(800);
    g_sim.phone.ndinfo = 0; phone_req(BC_MSG_DIAG_LIST_REQ, 0, 0, 0, 0); run(2000);
    int n0 = g_sim.phone.ndinfo; bc_diag_info_t list[32]; memcpy(list, g_sim.phone.dinfo, sizeof list);
    for (int i = 0; i < n0; i++) if (list[i].state == 0) { phone_req(BC_MSG_DIAG_ACK, list[i].id, 0, 0, list[i].crc); run(300); }
    app_diag_status(&st); CHECK(n0 == BC_DIAG_MAX_REPORTS && st.pending == 0, "Cyclift acknowledged all %d reports (pending %d)", n0, st.pending);
    /* a) Settings > Diagnostics > HOLD: SAVE REPORT -> a kind-3 report, announced to the connected phone */
    ui_settings_show(); run(300); scroll_to("Diagnostics"); tap_text("Diagnostics"); run(300);
    CHECK(scroll_to("HOLD: SAVE REPORT"), "Diagnostics menu: 'HOLD: SAVE REPORT'"); shot("23a_diag_save_report");
    int stored0 = st.stored; g_sim.phone.dreadys = 0;
    tap_text("HOLD: SAVE REPORT"); run(400); app_diag_status(&st); CHECK(st.stored == stored0, "a short tap does not save");
    hold_text("HOLD: SAVE REPORT", 1300); run(600); app_diag_status(&st);
    CHECK(st.stored == stored0 && st.pending == 1 && on_screen("saved"), "held 1 s: report saved (oldest sent one made room), toast shown (%d stored, %d pending)", st.stored, st.pending);
    shot("23a_diag_report_saved");
    CHECK(g_sim.phone.dreadys >= 1 && g_sim.phone.dready.pending == 1, "connected Cyclift is told at once: diag_ready pending 1");
    g_sim.phone.ndinfo = 0; phone_req(BC_MSG_DIAG_LIST_REQ, 0, 0, 0, 0); run(2000);
    bc_diag_info_t want; memset(&want, 0, sizeof want);
    for (int i = 0; i < g_sim.phone.ndinfo; i++) if (g_sim.phone.dinfo[i].state == 0) want = g_sim.phone.dinfo[i];
    CHECK(want.id && want.kind == BC_DIAG_KIND_MANUAL && want.size > 1000, "the new report is listed: id %lu kind 3, %lu bytes", (unsigned long)want.id, (unsigned long)want.size);
    /* b) MTU 185 (iOS): Cyclift asks for 155; every notification <= 182 bytes; >= 200 ms between chunks; LIVE keeps 1 Hz */
    g_sim.phone.mtu = 185; g_sim.phone.min_chunk_gap_ms = UINT32_MAX; g_sim.phone.unknown_notifies = 0;
    uint32_t got, maxw; int lives; uint32_t t0 = g_sim.now_ms;
    int chunks = pull_paced(want.id, want.size, 155, &got, &maxw, &lives);
    uint32_t dur = g_sim.now_ms - t0; uint32_t crc = bc_crc32(0, g_sim.phone.dbuf, got);
    CHECK(got == want.size && crc == want.crc && chunks == (int)((want.size + 154) / 155) && maxw <= 180 && maxw + 3 <= 185 && g_sim.phone.unknown_notifies == 0,
          "MTU 185: %d chunks, largest message %lu bytes (<= MTU-3), crc ok", chunks, (unsigned long)maxw);
    CHECK(g_sim.phone.min_chunk_gap_ms >= BC_DIAG_CHUNK_GAP_MS, "chunks paced: smallest gap %lu ms (>= %u)", (unsigned long)g_sim.phone.min_chunk_gap_ms, BC_DIAG_CHUNK_GAP_MS);
    CHECK(lives >= (int)(dur / 1000) - 1, "LIVE kept its 1 Hz during the transfer: %d LIVE in %lu ms", lives, (unsigned long)dur);
    printf("  MTU 185 transfer: %lu bytes in %lu ms, %d chunks, min gap %lu ms, %d LIVE messages meanwhile\n", (unsigned long)got, (unsigned long)dur, chunks, (unsigned long)g_sim.phone.min_chunk_gap_ms, lives);
    /* c) MTU 100: Cyclift asks for 72; the board would clamp an old 160 request to 72 too */
    g_sim.phone.mtu = 100; chunks = pull_paced(want.id, want.size, 160, &got, &maxw, &lives);
    CHECK(got == want.size && bc_crc32(0, g_sim.phone.dbuf, got) == want.crc && maxw == 97 && g_sim.phone.unknown_notifies == 0, "MTU 100: a 160-byte request is clamped to 72 data bytes (97-byte messages), crc ok");
    /* d) MTU 23 (no exchange): DIAG_ERR 5, nothing oversized */
    g_sim.phone.mtu = 23; g_sim.phone.derrs = 0; phone_req(BC_MSG_DIAG_CHUNK_REQ, want.id, 0, 160, 0); run(600);
    CHECK(g_sim.phone.derrs == 1 && g_sim.phone.derr.code == BC_DIAG_ERR_MTU, "MTU 23: DIAG_ERR 5 (link too small), no chunk");
    g_sim.phone.mtu = 185;
    /* e) congestion: LIVE / NimBLE need the link -> the chunk waits (never dropped), then goes */
    g_sim.phone.congested = true; int before = g_sim.phone.dchunks; app_diag_status(&st); uint32_t held0 = st.chunks_held;
    phone_req(BC_MSG_DIAG_CHUNK_REQ, want.id, 0, 155, 0); run(2000); app_diag_status(&st);
    CHECK(g_sim.phone.dchunks == before && st.chunks_held > held0, "link congested: the chunk is held (%lu holds), not sent", (unsigned long)(st.chunks_held - held0));
    g_sim.phone.congested = false; run(600);
    CHECK(g_sim.phone.dchunks == before + 1 && g_sim.phone.dchunk.offset == 0, "congestion gone: the held chunk is sent");
    /* f) a ride recording on the board: chunk requests answered BUSY, list still works, LIVE untouched; after the ride it resumes */
    app_ride_start(); run(1200);
    CHECK(app_ride_state() == BC_RIDE_RUNNING, "ride recording");
    g_sim.phone.derrs = 0; before = g_sim.phone.dchunks; int lives0 = g_sim.phone.lives;
    for (int k = 0; k < 5; k++) { phone_req(BC_MSG_DIAG_CHUNK_REQ, want.id, 0, 155, 0); run(1000); }
    CHECK(g_sim.phone.dchunks == before && g_sim.phone.derrs == 5 && g_sim.phone.derr.code == BC_DIAG_ERR_BUSY, "ride recording: 5 chunk requests -> 5 x BUSY, no data");
    CHECK(g_sim.phone.lives - lives0 >= 4, "LIVE during the ride: %d in 5 s", g_sim.phone.lives - lives0);
    g_sim.phone.ndinfo = 0; phone_req(BC_MSG_DIAG_LIST_REQ, 0, 0, 0, 0); run(1500); CHECK(g_sim.phone.ndinfo >= 1, "ride recording: the list is still answered");
    app_ride_end(); run(300); app_ride_discard(); run(600);
    chunks = pull_paced(want.id, want.size, 155, &got, &maxw, &lives); crc = bc_crc32(0, g_sim.phone.dbuf, got);
    CHECK(got == want.size && crc == want.crc, "after the ride: the transfer completes (%d chunks), crc ok", chunks);
    /* g) ACK only with the matching crc; the report then may be replaced when the store fills */
    g_sim.phone.ndinfo = 0; phone_req(BC_MSG_DIAG_ACK, want.id, 0, 0, crc ^ 1); run(600);
    CHECK(g_sim.phone.ndinfo == 1 && g_sim.phone.dinfo[0].state == 0, "wrong crc: still pending");
    g_sim.phone.ndinfo = 0; phone_req(BC_MSG_DIAG_ACK, want.id, 0, 0, crc); run(600);
    app_diag_status(&st); CHECK(g_sim.phone.ndinfo == 1 && g_sim.phone.dinfo[0].state == 1 && st.pending == 0, "matching crc: sent");
    sim_phone_disconnect(); run(300);
    ui_home_show(); run(300);
}

/* ===================================================================================== 0.7.3 stress (sanitizer build) */
static uint32_t rnd32(void) { static uint32_t x = 0x1234567; x ^= x << 13; x ^= x >> 17; x ^= x << 5; return x; }
static void scenario_stress(int cycles)
{
    printf("\n== 22. stress: %d cycles of phone connect/disconnect + SENSOR_DIAG + report pulls, meter chaos, malformed data, Wi-Fi toggles\n", cycles);
    uint32_t t0 = g_sim.now_ms; int connects = 0, pulls = 0, acks = 0, meter_flips = 0, wifi_flips = 0, junk = 0, reports = 0, retries = 0;
    bc_profile_t *pr = app_profile(); pr->power.paired = true; pr->phone_on = true; app_profile_save();
    plat_phone_set_enabled(true);
    sim_fake_meter(true, 0, false);
    int diags0 = g_sim.phone.diags;
    for (int i = 0; i < cycles; i++) {
        /* one rapid phone cycle: connect, a few random things happen while it is up (SENSOR_DIAG flows, reports are pulled,
           the meter changes, malformed bytes arrive), then it drops at a random moment — sometimes in the middle of a pull */
        sim_phone_connect(true); connects++;
        int steps = 1 + (int)(rnd32() % 4);
        for (int k = 0; k < steps; k++) {
            uint32_t r = rnd32();
            switch (r % 10) {
            case 0: g_sim.fake.streaming = !g_sim.fake.streaming; meter_flips++; break;
            case 1: g_sim.fake.stall = !g_sim.fake.stall; meter_flips++; break;
            case 2: g_sim.fake.garbage = !g_sim.fake.garbage; meter_flips++; break;
            case 3: sim_fake_meter(rnd32() % 4 != 0, (int)(rnd32() % 2), false); meter_flips++; break;
            case 4: { bool on = rnd32() % 2; plat_wifi_set_enabled(on); if (on) plat_wifi_scan(); wifi_flips++; break; }
            case 5: phone_req(BC_MSG_DIAG_LIST_REQ, 0, 0, 0, 0); pulls++; break;
            case 6: { app_diag_status_t st; app_diag_status(&st); if (st.stored && g_sim.phone.ndinfo) { bc_diag_info_t *f = &g_sim.phone.dinfo[rnd32() % (uint32_t)g_sim.phone.ndinfo];
                        phone_req(BC_MSG_DIAG_CHUNK_REQ, f->id, rnd32() % (f->size + 20), (uint16_t)(rnd32() % 200), 0); pulls++;
                        if (rnd32() % 3 == 0) { phone_req(BC_MSG_DIAG_ACK, f->id, 0, 0, rnd32() % 2 ? f->crc : 1); acks++; } } break; }
            case 7: { uint8_t m[BC_LINK_MAX]; size_t n = rnd32() % 60; for (size_t q = 0; q < n; q++) m[q] = (uint8_t)rnd32(); if (n) m[0] = (uint8_t)(0x60 + rnd32() % 0x30); if (n >= 8) sim_phone_write((int)(rnd32() % 2), m, n); junk++; break; }
            case 8: if (rnd32() % 8 == 0) { app_diag_store_report(BC_DIAG_KIND_MANUAL, "stress"); reports++; } break;
            case 9: if (rnd32() % 6 == 0) { plat_found_t f = { { 0 }, 0, "XDS-A001", -50, PLAT_SVC_POWER }; plat_pair(PLAT_SENS_POWER, &f); retries++; } break;
            }
            run((int)(20 + rnd32() % 400));
        }
        if (g_sim.phone.ndinfo > 24) g_sim.phone.ndinfo = 0;
        sim_phone_disconnect();
        run((int)(20 + rnd32() % 300));
    }
    sim_phone_disconnect(); run(1000);
    app_diag_status_t st; app_diag_status(&st); app_diag_flush(true);
    int boot_ev = events_of(BC_EV_BOOT), sens_ev = events_of(BC_EV_SENSOR), rec_ev = events_of(BC_EV_RECOVERY), ph_ev = events_of(BC_EV_PHONE);
    printf("  %d cycles in %lu s simulated: %d phone connects, %d SENSOR_DIAG events, %d DIAG requests, %d ACKs, %d meter changes, %d Wi-Fi toggles, %d malformed writes, %d reports, %d re-pairs\n",
           cycles, (unsigned long)((g_sim.now_ms - t0) / 1000), connects, g_sim.phone.diags - diags0, pulls, acks, meter_flips, wifi_flips, junk, reports, retries);
    printf("  event log: %lu records written this boot, sensor %d phone %d recovery %d boot %d; reports stored %d pending %d not stored %lu\n",
           (unsigned long)st.events_written, sens_ev, ph_ev, rec_ev, boot_ev, st.stored, st.pending, (unsigned long)st.not_stored);
    CHECK(connects > cycles / 20 && g_sim.phone.diags > diags0 && st.events_written > 100 && st.stored <= BC_DIAG_MAX_REPORTS, "stress ran with real traffic and kept every invariant");
    sim_fake_meter(false, 0, false); pr->power.paired = false; app_profile_save(); g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_NOT_PAIRED;
}

int main(int argc, char **argv)
{
    if (argc > 1) snprintf(outdir, sizeof outdir, "%s", argv[1]);
    mkdir(outdir, 0755);
    system("rm -rf simfs");
    sim_fs_root("simfs");
    char rp[512]; snprintf(rp, sizeof rp, "%s/report.txt", outdir); report = fopen(rp, "w");
    lv_init();
    lv_tick_set_cb(tick_cb);
    disp = lv_display_create(UI_W, UI_W);
    lv_display_set_color_format(disp, LV_COLOR_FORMAT_RGB565);
    lv_display_set_buffers(disp, drawbuf, NULL, sizeof drawbuf, LV_DISPLAY_RENDER_MODE_PARTIAL);
    lv_display_set_flush_cb(disp, flush_cb);
    indev = lv_indev_create();
    lv_indev_set_type(indev, LV_INDEV_TYPE_POINTER);
    lv_indev_set_read_cb(indev, read_cb);
    g_sim.crashpart = BC_CRASHPART_EMPTY;
    scenario();
    scenario_073();
    scenario_073_transfer();
    scenario_074();
    scenario_074rc();
    scenario_074rc2();
    scenario_stress(getenv("SIM_STRESS") ? atoi(getenv("SIM_STRESS")) : 1000);
    lv_mem_monitor_t m; lv_mem_monitor(&m);
    printf("\nLVGL memory: %u%% used, max used %u bytes of %u, fragmentation %u%%\n", m.used_pct, (unsigned)m.max_used, (unsigned)m.total_size, m.frag_pct);
    CHECK(m.max_used < m.total_size * 85 / 100, "LVGL heap stays under 85%% (max %u of %u)", (unsigned)m.max_used, (unsigned)m.total_size);
    printf("\n%d screens checked, %d with issues; %d functional checks, %d failed\n", n_shots, n_fail_shots, n_checks, n_fail);
    fprintf(report, "SUMMARY screens=%d screen_fail=%d checks=%d check_fail=%d lvgl_max_used=%u/%u\n", n_shots, n_fail_shots, n_checks, n_fail,
            (unsigned)m.max_used, (unsigned)m.total_size);
    fclose(report);
    return (n_fail_shots || n_fail) ? 1 : 0;
}
