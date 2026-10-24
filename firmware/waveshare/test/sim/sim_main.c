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

static void read_cb(lv_indev_t *i, lv_indev_data_t *d)
{
    (void)i; d->point.x = ptr.x; d->point.y = ptr.y; d->state = ptr.down ? LV_INDEV_STATE_PRESSED : LV_INDEV_STATE_RELEASED;
}

void sim_wifi_pump(void);
static void run(int ms) { for (int t = 0; t < ms; t += 5) { g_sim.now_ms += 5; lv_timer_handler(); if (g_sim.now_ms % 100 == 0) sim_wifi_pump(); } }
static void run_s(int s) { for (int i = 0; i < s; i++) run(1000); }
static void raw_tap(int x, int y) { ptr.x = x; ptr.y = y; ptr.down = true; run(80); ptr.down = false; run(150); }
static int n_auto_wakes;
/* a rider who finds the screen dark taps it three times before using it (0.5.0 screen-off); the harness does the same */
static void wake_if_dark(void) { if (!app_power()->screen_on && !app_power()->asleep) { n_auto_wakes++; raw_tap(120, 120); raw_tap(120, 120); raw_tap(120, 120); run(300); } }
static void tap(int x, int y) { wake_if_dark(); raw_tap(x, y); }
static void hold(int x, int y, int ms) { wake_if_dark(); ptr.x = x; ptr.y = y; ptr.down = true; run(ms); ptr.down = false; run(150); }
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
    if (lv_obj_check_type(o, &lv_label_class) && visible(o) && strstr(lv_label_get_text(o), txt)) return o;
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

static void walk(lv_obj_t *o)
{
    if (lv_obj_has_flag(o, LV_OBJ_FLAG_HIDDEN)) return;
    if (visible(o)) {
        lv_area_t a; lv_obj_get_coords(o, &a);
        lv_obj_t *par = lv_obj_get_parent(o);
        bool is_label = lv_obj_check_type(o, &lv_label_class);
        if (is_label) {
            check_glyphs(o, lv_label_get_text(o), lv_obj_get_style_text_font(o, LV_PART_MAIN), lv_label_get_recolor(o));
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
    walk(lv_screen_active());
    walk(lv_layer_top());
    if (ui_qs_handle_visible()) { lv_area_t h; ui_qs_handle_rect(&h); walk_handle(lv_screen_active(), &h); }
    else if (ui_current() == UI_SCR_RIDE && !ui_qs_is_open()) {           /* the ride screen's own handle: 72 x 22 at the top */
        lv_area_t h = { .x1 = UI_R - 36, .y1 = 4, .x2 = UI_R + 35, .y2 = 23 };
        lv_obj_t *scr = lv_screen_active();
        for (uint32_t i = 0; i < lv_obj_get_child_count(scr); i++) { lv_obj_t *c = lv_obj_get_child(scr, (int32_t)i); if (lv_obj_check_type(c, &lv_tileview_class)) walk_handle(c, &h); }
    }
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
    /* type "Rashed": P-T group -> R, A-E -> A, P-T -> S, F-J -> H, A-E -> E, A-E -> D */
    const char *seq[][2] = { { "P-T", "R" }, { "A-E", "A" }, { "P-T", "S" }, { "F-J", "H" }, { "A-E", "E" }, { "A-E", "D" } };
    for (int i = 0; i < 6; i++) { tap_text(seq[i][0]); if (i == 0) shot("03_name_letters"); tap_text(seq[i][1]); }
    CHECK(on_screen("Rashed_"), "name typed with the letter ring");
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
    CHECK(app_profile()->age == age && app_profile()->weight_dg == wdg && !strcmp(app_profile()->name, "Rashed"), "profile restored after restart");
    CHECK(app_profile()->power.paired, "pairing restored after restart");

    printf("== 3 real ride (scripted sensor values standing in for the meter)\n");
    for (int st = 0; st < 3; st++) {
        app_profile()->ride_style = (uint8_t)st;
        sensors(true, 182, true, 88, false, 0);
        ui_home_show(); run(300);
        tap_text("START RIDE");
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
    tap_text("START RIDE");
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
    tap_text("START RIDE");
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
    tap_text("START RIDE");
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
    ui_home_show(); run(300); tap_text("START RIDE"); run_s(400);
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
    CHECK(on_screen("NO DATA") && on_screen("RECONNECTING") && on_screen("reconnects 3"), "sensor test: NO DATA + reconnecting");
    shot("90b_sensor_test_nodata");
    app_set_demo(true); run_s(2);
    CHECK(on_screen("SIMULATED"), "sensor test labels demo data SIMULATED");
    shot("90c_sensor_test_demo");
    app_set_demo(false);
    g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_CONNECTED;
    ui_sensors_show(); run(500); shot("82_sensors");
    tap_text("PAIR POWER"); run(2000); shot("83_pair_from_settings");

    printf("== 11 Wi-Fi manager\n");
    {
        g_sim.n_ap = 4;
        strcpy(g_sim.ap[0].ssid, "HomeNet"); g_sim.ap[0].rssi = -48; g_sim.ap[0].secured = true; strcpy(g_sim.ap[0].pass, "Secret-123"); g_sim.ap[0].present = true;
        strcpy(g_sim.ap[1].ssid, "Rashed iPhone"); g_sim.ap[1].rssi = -62; g_sim.ap[1].secured = true; strcpy(g_sim.ap[1].pass, "bike ride!"); g_sim.ap[1].present = true;
        strcpy(g_sim.ap[2].ssid, "CafeFree"); g_sim.ap[2].rssi = -75; g_sim.ap[2].secured = false; g_sim.ap[2].present = true;
        strcpy(g_sim.ap[3].ssid, "AVeryLongNetworkNameForTest123"); g_sim.ap[3].rssi = -84; g_sim.ap[3].secured = true; strcpy(g_sim.ap[3].pass, "12345678"); g_sim.ap[3].present = true;
        ui_settings_show(); run(300); scroll_to("Wi-Fi"); tap_text("Wi-Fi");
        CHECK(on_screen("OFF") && on_screen("Optional"), "Wi-Fi screen, off");
        shot("a0_wifi_off");
        tap_text("Wi-Fi");
        CHECK(app_profile()->wifi_on, "Wi-Fi switched on and remembered");
        shot("a1_wifi_on");
        tap_text("Networks"); run(2600);
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
        ui_wifi_show(); run(300); tap_text("Networks"); run(2600); tap_text("Rashed iPhone"); kb_mode = 0;
        kb_type("bike ride!"); tap_text("JOIN"); run(3500);
        CHECK(on_screen("CONNECTED"), "joined the phone hotspot (password with space and !)");
        tap_text("DONE");
        printf("   network disappears: falls back to the other saved one\n");
        g_sim.ap[1].present = false; run_s(14);
        { plat_wifi_status_t w; plat_wifi_status(&w); CHECK(w.state == PLAT_WIFI_CONNECTED && !strcmp(w.ssid, "HomeNet"), "lost hotspot -> reconnected to HomeNet (%d %s)", w.state, w.ssid); }
        g_sim.ap[1].present = true;
        printf("   disconnect: no automatic reconnect until asked\n");
        ui_wifi_show(); run(300); scroll_to("Disconnect"); tap_text("Disconnect"); run_s(30);
        { plat_wifi_status_t w; plat_wifi_status(&w); CHECK(w.state == PLAT_WIFI_IDLE, "stays disconnected (%d)", w.state); }
        ui_wifi_show(); run(300); shot("b2_wifi_disconnected");
        printf("   forget\n");
        scroll_to("Saved"); tap_text("Saved"); shot("b3_saved");
        tap_text("Rashed iPhone"); shot("b4_saved_detail");
        hold_text("HOLD: FORGET", 1800);
        { char sv[5][33]; CHECK(plat_wifi_saved(sv, 5) == 1 && !strcmp(sv[0], "HomeNet"), "hotspot forgotten"); }
        printf("   errors: timeout, not found, no address\n");
        g_sim.wifi_no_answer = true; ui_wifi_show(); run(300); scroll_to("Networks"); tap_text("Networks"); run(2600); scroll_to("CafeFree"); tap_text("CafeFree");
        CHECK(on_screen("NETWORK") && on_screen("open network") && on_screen("CONNECT"), "open network: detail page first (connect / back)"); shot("b4b_network_detail_open");
        tap_text("CONNECT"); run_s(21);
        CHECK(on_screen("timeout"), "timeout error"); shot("b5_timeout"); g_sim.wifi_no_answer = false;
        ui_wifi_show(); run(300); scroll_to("Networks"); tap_text("Networks"); run(2600); scroll_to("Other network"); tap_text("Other network"); kb_mode = 0;
        CHECK(on_screen("NAME") && on_screen("NEXT"), "hidden network: name first"); shot("b6_keyboard_ssid");
        kb_type("ghost"); tap_text("NEXT"); kb_mode = 0; kb_type("whatever1"); tap_text("JOIN"); run_s(4);
        CHECK(on_screen("not found"), "network not found error"); shot("b7_not_found");
        g_sim.wifi_no_dhcp = true; ui_wifi_show(); run(300); scroll_to("Networks"); tap_text("Networks"); run(2600); scroll_to("CafeFree"); tap_text("CafeFree"); tap_text("CONNECT"); run_s(4);
        CHECK(on_screen("no address"), "no IP address error"); shot("b8_no_ip"); g_sim.wifi_no_dhcp = false;
        tap_text("BACK"); scroll_to("Networks"); tap_text("Networks"); run(2600);
        { plat_wifi_status_t w0; plat_wifi_status(&w0); tap_text(LV_SYMBOL_REFRESH); run(2600); plat_wifi_status_t w1; plat_wifi_status(&w1); CHECK(w1.scans == w0.scans + 1, "rescan"); }
        printf("   during a ride Wi-Fi never scans or retries on its own\n");
        g_sim.ap[0].present = false;               /* saved HomeNet out of range: the manager would keep retrying */
        ui_home_show(); run(300); run_s(70);
        int a0 = g_sim.wifi_auto_attempts;
        CHECK(a0 > 0, "retries happen when not riding (%d)", a0);
        sensors(true, 170, true, 88, false, 0);
        tap_text("START RIDE"); run_s(300);
        int a1 = g_sim.wifi_auto_attempts;
        bc_ride_summary_t rs; app_ride_totals(&rs);
        CHECK(a1 == a0 && rs.duration_s >= 299 && rs.power_s >= 299, "no Wi-Fi activity during the ride; recording intact (%d->%d, %lus)", a0, a1, (unsigned long)rs.duration_s);
        drag(120, 60, 120, 190); hold_text("HOLD: END", 2300); tap_text("SAVE"); run_s(70);
        CHECK(g_sim.wifi_auto_attempts > a1, "retries resume after the ride");
        g_sim.ap[0].present = true;
        ui_wifi_show(); run(300); tap_text("Wi-Fi"); 
        { plat_wifi_status_t w; plat_wifi_status(&w); CHECK(w.state == PLAT_WIFI_OFF && !app_profile()->wifi_on, "Wi-Fi off again"); }
    }

    printf("== 12 phone link (the harness plays the iPhone app)\n");
    {
        /* enabled by default after onboarding; nothing paired yet */
        boot(); plat_phone_set_enabled(app_profile()->phone_on); run(300);
        CHECK(app_profile()->phone_on, "phone link on by default");
        ui_settings_show(); run(300); scroll_to("Phone"); shot("97_settings_phone_row"); tap_text("Phone"); run(300);
        CHECK(on_screen("WAITING FOR PHONE") && on_screen("no phone remembered"), "phone page before pairing");
        shot("97_phone_waiting");
        /* a new phone connects: the 6-digit code pops up over the current screen and blocks touches until done */
        sim_phone_connect(false); run(400);
        CHECK(on_screen("PHONE PAIRING") && on_screen("482") && on_screen("913"), "passkey shown on screen");
        shot("98_passkey_popup");
        sim_phone_enter_passkey(); run(400);
        CHECK(!on_screen("PHONE PAIRING") && on_screen("CONNECTED") && on_screen("a phone is remembered"), "paired, remembered");
        shot("98_phone_connected");
        /* the phone sends time, GPS and watch heart rate; every value carries its source */
        sim_phone_send_time(1761300000000ULL); sim_phone_send_gps(244667000, 544000000, 833, 60); sim_phone_send_hr(148, BC_SRC_APPLE_WATCH); run(1200);
        { app_live_t lv; app_live(&lv);
          CHECK(lv.speed_ok && lv.speed_dmh == 299 && lv.speed_src == BC_SRC_PHONE_GPS, "speed 29.9 km/h from PHONE GPS (%d)", lv.speed_dmh);
          CHECK(lv.hr_ok && lv.bpm == 148 && lv.hr_src == BC_SRC_APPLE_WATCH && lv.phone_hr && !lv.strap_hr, "watch HR via phone");
          CHECK(lv.time_known && lv.epoch_s >= 1761300000u && lv.epoch_s <= 1761300002u, "wall clock synced"); }
        CHECK(on_screen("WATCH") && on_screen("29.9 km/h"), "phone page shows sources");
        shot("98_phone_live");
        /* strap present too: strap wins by default, watch is the backup; preference flips it */
        sensors(true, 180, true, 90, true, 152); g_sim.link[PLAT_SENS_HR].link = PLAT_LINK_CONNECTED; sim_phone_send_hr(148, BC_SRC_APPLE_WATCH); run(400);
        { app_live_t lv; app_live(&lv); CHECK(lv.hr_ok && lv.bpm == 152 && lv.hr_src == BC_SRC_BLE_STRAP && lv.strap_hr && lv.phone_hr, "strap first by default"); }
        scroll_to("HR: STRAP FIRST"); tap_text("HR: STRAP FIRST"); run(300); sim_phone_send_hr(149, BC_SRC_APPLE_WATCH); run(300);
        { app_live_t lv; app_live(&lv); CHECK(lv.hr_ok && lv.bpm == 149 && lv.hr_src == BC_SRC_APPLE_WATCH && app_profile()->hr_pref == 1, "watch first after the toggle"); }
        scroll_to("HR: WATCH FIRST"); tap_text("HR: WATCH FIRST"); run(300);
        /* stale: 12 s without a watch value → falls back to the strap, never holds the old number */
        run_s(7); { app_live_t lv; app_live(&lv); CHECK(lv.hr_ok && lv.hr_src == BC_SRC_BLE_STRAP && !lv.phone_hr, "stale watch HR dropped after 6 s, strap shown"); }
        sensors(true, 180, true, 90, false, 0); g_sim.link[PLAT_SENS_HR].link = PLAT_LINK_NOT_PAIRED; run(400);
        { app_live_t lv; app_live(&lv); CHECK(!lv.hr_ok && !lv.speed_ok && lv.link[PLAT_SENS_SPEED].link == PLAT_LINK_STALE, "no HR at all; GPS marked STALE after 5 s"); }
        /* Sensors page: five groups */
        ui_sensors_show(); run(300); shot("99_sensors_groups");
        CHECK(on_screen("POWER METER") && scroll_to("HEART RATE") && scroll_to("SPEED / CADENCE"), "sensor groups");
        CHECK(scroll_to("WEARABLES") && scroll_to("PHONE SETTINGS") && on_screen("CONNECTED"), "wearables + phone rows"); shot("99_sensors_phone");
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
        ui_phone_show(); run(300); scroll_to("FORGET PHONE"); hold_text("FORGET PHONE", 1800); run(300);
        CHECK(g_sim.phone.forgets == 1, "forget called (%d)", g_sim.phone.forgets); CHECK(scroll_to("no phone remembered"), "phone page says not remembered");
        scroll_to("PHONE LINK: ON"); tap_text("PHONE LINK: ON"); run(300); CHECK(!app_profile()->phone_on && scroll_to("OFF"), "phone link switched off");
        scroll_to("PHONE LINK: OFF"); tap_text("PHONE LINK: OFF"); run(300); CHECK(app_profile()->phone_on, "and on again");
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
        CHECK(!ui_qs_is_open() && on_screen("WI-FI") && on_screen("Optional"), "tap on the Wi-Fi row opens the full Wi-Fi page"); shot("c0b_wifi_from_qs");
        ui_home_show(); run(300); tap(120, 12); run(300); CHECK(ui_qs_is_open(), "tapping the HANDLE opens quick settings"); shot("c0c_qs_by_handle_tap");
        drag(120, 215, 120, 60); run(300); CHECK(!ui_qs_is_open(), "closed again");
        drag(120, 10, 120, 150); run(300); CHECK(ui_qs_is_open(), "a swipe starting on the handle opens it");
        scroll_to("Phone link");
        bool p0 = app_profile()->phone_on; tap_text("Phone link"); run(300); CHECK(app_profile()->phone_on != p0 && g_sim.phone.enabled == app_profile()->phone_on, "phone link toggled (sensor BLE untouched)"); scroll_to("Phone link"); tap_text("Phone link"); run(300);
        CHECK(g_sim.link[PLAT_SENS_POWER].link == PLAT_LINK_CONNECTED, "power meter link unaffected by the phone toggle");
        scroll_to("Power settings"); shot("c1_quick_settings_bottom");
        CHECK(scroll_to("Battery") && scroll_to("est.") && scroll_to("State") && scroll_to("Deep sleep") && on_screen("link off") && scroll_to("HOLD: RESTART"), "battery row, state, sleep (link off), restart present");
        /* close by swipe up, by timeout, by the X */
        drag(120, 215, 120, 60); run(300); CHECK(!ui_qs_is_open(), "swipe up closes quick settings");
        drag(120, 20, 120, 150); run(300); CHECK(ui_qs_is_open(), "reopen"); run_s(21); CHECK(!ui_qs_is_open(), "closes after 20 s");
        drag(120, 20, 120, 150); run(300); tap(120, 202); run(300); CHECK(!ui_qs_is_open(), "X closes");
        /* screen off: single and double taps do nothing, a triple tap wakes */
        drag(120, 20, 120, 150); run(300); scroll_to("Screen off"); tap_text("Screen off"); run(400);
        CHECK(!P->screen_on && g_sim.backlight == 0 && g_sim.panel_asleep, "screen off: backlight 0, panel asleep");
        shot("c2_screen_off");
        raw_tap(120, 120); run(2000); CHECK(!P->screen_on, "one tap: still off");
        raw_tap(120, 120); raw_tap(120, 120); run(2000); CHECK(!P->screen_on, "two taps: still off");
        raw_tap(120, 120); raw_tap(120, 120); raw_tap(120, 120); run(300);
        CHECK(P->screen_on && g_sim.backlight == app_profile()->brightness && !g_sim.panel_asleep, "three taps: screen on, brightness restored");
        CHECK(app_ride_state() == BC_RIDE_IDLE, "taps on the dark screen did not reach any button");
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
        tap_text("START RIDE"); run(300); CHECK(app_ride_state() == BC_RIDE_IDLE, "locked: the start button does not react");
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
        tap_text("START RIDE"); run_s(5);
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
        raw_tap(120, 120); raw_tap(120, 120); raw_tap(120, 120); run(400); CHECK(P->screen_on && app_ride_state() == BC_RIDE_RUNNING, "triple tap wakes mid-ride");
        drag(120, 60, 120, 190); hold_text("HOLD: END", 2300); tap_text("SAVE"); run(300);
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
        CHECK(on_screen("START RIDE") && app_power()->woke_from_sleep && app_power()->screen_on && !strcmp(app_profile()->name, "Rashed"), "wake: home, profile intact");
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
        CHECK(g_sim.deep_sleeps == 2 && app_power()->asleep && g_sim.sleep_wake_taps == 3, "auto deep sleep after 5 idle minutes on battery, no phone (wake needs %d taps)", g_sim.sleep_wake_taps);
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
        raw_tap(120, 120); raw_tap(120, 120); raw_tap(120, 120); run(400);
        CHECK(P->screen_on && !P->standby && !g_sim.phone.standby && !g_sim.sensor_standby && g_sim.phone.connected, "wake leaves standby; the phone link was never dropped");
        /* automatic timeout with the phone connected: standby, never deep sleep */
        app_profile()->auto_sleep_min = 5; app_profile_save(); ui_home_show(); run_s(61 + 6 * 60);
        CHECK(!P->screen_on && P->standby && !P->asleep && g_sim.deep_sleeps == d0 && g_sim.phone.connected, "7 min idle with a phone connected: standby, no deep sleep (%s)", P->sleep_block);
        app_profile()->auto_sleep_min = 0; app_profile_save(); raw_tap(120, 120); raw_tap(120, 120); raw_tap(120, 120); run(400);
        /* ride + screen off: no standby, meter + phone links kept, journal grows */
        ui_home_show(); run(300); tap_text("START RIDE"); run_s(3);
        drag(120, 60, 120, 190); run(300); tap_text("QUICK SET."); run(300); scroll_to("Screen off"); tap_text("Screen off"); run(400);
        int jl0 = count_lines("rides/active.jnl"); l1 = g_sim.phone.lives; run_s(30);
        CHECK(!P->screen_on && !P->standby && !g_sim.sensor_standby && app_ride_state() == BC_RIDE_RUNNING, "ride in the dark: recording, NO standby");
        CHECK(g_sim.link[PLAT_SENS_POWER].link == PLAT_LINK_CONNECTED && g_sim.phone.connected && g_sim.phone.lives >= l1 + 28 && count_lines("rides/active.jnl") >= jl0 + 25, "meter + phone links kept, live stream and journal keep flowing");
        raw_tap(120, 120); raw_tap(120, 120); raw_tap(120, 120); run(400);
        drag(120, 60, 120, 190); hold_text("HOLD: END", 2300); tap_text("SAVE"); run(300);
        /* deep sleep: explicit, explained as connectivity off */
        ui_home_show(); run(300); drag(120, 20, 120, 150); run(300); scroll_to("Deep sleep"); CHECK(on_screen("link off"), "deep sleep row says the link goes off"); tap_text("Deep sleep"); run(300);
        CHECK(on_screen("CONNECTIVITY OFF") && scroll_to("standby keep"), "deep sleep page: connectivity off, standby keeps Bluetooth");
        shot("d0_deep_sleep_connectivity");
        scroll_to("HOLD: DEEP SLEEP"); hold_text("HOLD: DEEP SLEEP", 1800); run(300);
        CHECK(g_sim.deep_sleeps == d0 + 1 && !g_sim.phone.enabled && g_sim.sleep_wake_taps == 3, "deep sleep: phone link switched off (wake needs %d taps)", g_sim.sleep_wake_taps);
        g_sim.woke_from_sleep = true; g_sim.asleep = false; boot(); run(400); g_sim.woke_from_sleep = false;
        CHECK(g_sim.phone.enabled, "after the wake the phone link advertises again");
        /* wake gesture setting: double tap */
        ui_power_settings_show(); run(300); scroll_to("Wake gesture"); tap_text("Wake gesture"); run(300);
        CHECK(app_profile()->wake_taps == 2 && on_screen("2 taps"), "wake gesture -> 2 taps (%u)", app_profile()->wake_taps);
        ui_home_show(); run(300); drag(120, 20, 120, 150); run(300); scroll_to("Screen off"); CHECK(on_screen("2 taps = on"), "screen-off row shows the gesture"); tap_text("Screen off"); run(400);
        raw_tap(120, 120); run(2000); CHECK(!P->screen_on, "one tap: still off");
        raw_tap(120, 120); raw_tap(120, 120); run(400); CHECK(P->screen_on, "double tap wakes");
        ui_power_settings_show(); run(300); scroll_to("Wake gesture"); tap_text("Wake gesture"); run(300); CHECK(app_profile()->wake_taps == 1, "-> any touch");
        ui_home_show(); run(300); drag(120, 20, 120, 150); run(300); scroll_to("Screen off"); tap_text("Screen off"); run(400);
        raw_tap(120, 120); run(1200); CHECK(!P->screen_on, "any touch applies to rides only: idle still needs 2 taps");
        raw_tap(120, 120); raw_tap(120, 120); run(400); CHECK(P->screen_on && app_ride_state() == BC_RIDE_IDLE, "2 taps wake when idle (and reach no button)");
        tap_text("START RIDE"); run_s(2); drag(120, 60, 120, 190); run(300); tap_text("QUICK SET."); run(300); scroll_to("Screen off"); tap_text("Screen off"); run(400);
        raw_tap(120, 120); run(400); CHECK(P->screen_on && app_ride_state() == BC_RIDE_RUNNING, "any touch wakes during a ride");
        drag(120, 60, 120, 190); hold_text("HOLD: END", 2300); hold_text(LV_SYMBOL_TRASH, 1800); run(300);
        ui_power_settings_show(); run(300); scroll_to("Wake gesture"); tap_text("Wake gesture"); run(300); CHECK(app_profile()->wake_taps == 3, "-> back to 3 taps");
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
        snprintf(g_sim.ap[4].ssid, sizeof g_sim.ap[4].ssid, "Rashed\xE2\x80\x99s iPhone"); g_sim.ap[4].rssi = -58; g_sim.ap[4].secured = true; strcpy(g_sim.ap[4].pass, "bike ride!"); g_sim.ap[4].present = true; g_sim.ap[4].channel = 11;
        strcpy(g_sim.ap[5].ssid, "Office5G"); g_sim.ap[5].rssi = -40; g_sim.ap[5].secured = true; g_sim.ap[5].present = true; g_sim.ap[5].ghz5_only = true;
        g_sim.ap[0].present = g_sim.ap[1].present = g_sim.ap[2].present = g_sim.ap[3].present = true;
        g_sim.phone.n_scan = 0; g_sim.phone.scan_ends = 0;
        n = bc_link_encode_wifi_scan_req(&sq, b, sizeof b, 3, 0); CHECK(sim_phone_write(0, b, n), "scan request queued"); run(4000);
        CHECK(g_sim.phone.scan_ends == 1 && g_sim.phone.scan_end.err == BC_WIFI_SCAN_OK && g_sim.phone.scan_end.count == 5 && g_sim.phone.n_scan == 5, "scan: 5 results (the 5 GHz-only network cannot be seen), END ok (%d/%u)", g_sim.phone.n_scan, g_sim.phone.scan_end.count);
        { int ip = -1; for (int i = 0; i < g_sim.phone.n_scan; i++) if (!strcmp(g_sim.phone.scan[i].ssid, "Rashed\xE2\x80\x99s iPhone")) ip = i;
          CHECK(g_sim.phone.n_scan && !strcmp(g_sim.phone.scan[0].ssid, "HomeNet") && g_sim.phone.scan[0].saved, "strongest first; HomeNet marked saved");
          CHECK(ip >= 0 && g_sim.phone.scan[ip].secured && g_sim.phone.scan[ip].channel == 11 && g_sim.phone.scan[ip].rssi == -58, "the iPhone's UTF-8 name, channel and signal arrive intact (%d)", ip);
          int ic = -1; for (int i = 0; i < g_sim.phone.n_scan; i++) if (!strcmp(g_sim.phone.scan[i].ssid, "CafeFree")) ic = i; CHECK(ic >= 0 && !g_sim.phone.scan[ic].secured, "open network flagged"); }
        /* on-device list shows the name with a plain apostrophe (font) but joins with the real bytes */
        ui_wifi_show(); run(300); scroll_to("Networks"); tap_text("Networks"); run(3000); CHECK(scroll_to("Rashed's iPho"), "device list: typographic apostrophe shown as '"); shot("e0_networks_utf8");
        /* provisioning: wrong password, then the right one */
        g_sim.phone.statuses = 0;
        bc_wifi_set_t st = { .flags = BC_WIFI_SET_CONNECT | BC_WIFI_SET_SAVE }; snprintf(st.ssid, sizeof st.ssid, "Rashed\xE2\x80\x99s iPhone"); snprintf(st.pass, sizeof st.pass, "wrong-pass");
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
        bc_wifi_forget_t fg; snprintf(fg.ssid, sizeof fg.ssid, "Rashed\xE2\x80\x99s iPhone"); n = bc_link_encode_wifi_forget(&fg, b, sizeof b, 7, 0); sim_phone_write(0, b, n); run_s(2);
        { char sv[5][33]; int k = plat_wifi_saved(sv, 5); bool gone = true; for (int i = 0; i < k; i++) if (!strcmp(sv[i], fg.ssid)) gone = false; CHECK(gone && g_sim.phone.wifi_status.saved_count == (uint8_t)k, "forgotten; status reports %u saved", g_sim.phone.wifi_status.saved_count); }
        /* a scan during a ride is refused; the ride is untouched by every Wi-Fi message */
        sensors(true, 180, true, 88, false, 0); g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_CONNECTED; ui_home_show(); run(300); tap_text("START RIDE"); run_s(2);
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
        CHECK(g_sim.phone.profiles == 1 && g_sim.phone.profile.version == 0 && g_sim.phone.profile.source == 0 && g_sim.phone.profile.ftp_w == ftp0 && !strcmp(g_sim.phone.profile.name, app_profile()->name), "PROFILE: device-only (version 0), FTP %u, name %s", ftp0, g_sim.phone.profile.name);
        bc_profile_msg_t pm = { .version = 1, .updated_epoch_s = 1792850100u, .ftp_w = 250, .ftp_how = 1, .weight_kg_x10 = 780, .birth_year = 1990, .max_hr = 186, .rest_hr = 52, .units = 0, .hours_per_week = 6, .level = 2, .goal = 1, .lthr = 170 };
        snprintf(pm.name, sizeof pm.name, "Rashed"); pm.has = 0; for (int t = 2; t <= 0x0E; t++) pm.has |= BC_PF_HAS(t);
        n = bc_link_encode_profile(BC_MSG_PROFILE_SET, &pm, b, sizeof b, 15, 0); CHECK(n > 0 && sim_phone_write(0, b, n), "PROFILE_SET v1 accepted"); run(600);
        CHECK(g_sim.phone.profile_acks == 1 && g_sim.phone.profile_ack.status == BC_PF_APPLIED && g_sim.phone.profile_ack.version == 1 && g_sim.phone.profile_ack.board_version == 1, "ACK applied v1");
        { const bc_profile_t *p = app_profile();
          CHECK(!strcmp(p->name, "Rashed") && p->ftp_w == 250 && p->ftp_how == BC_FTP_ENTERED && p->weight_dg == 780 && p->birth_year == 1990 && p->age == 36 && p->max_hr == 186 && p->rest_hr == 52 && p->hours_wk == 6 && p->exp == BC_EXP_ADVANCED && p->goal == BC_GOAL_ENDURANCE && p->lthr == 170 && p->prof_src == 1 && p->phone_prof_ver == 1,
                "profile applied (name %s, FTP %u %s, age %u from birth year, level %u, goal %u)", p->name, p->ftp_w, bc_ftp_label(p), p->age, p->exp, p->goal);
          CHECK(count_lines("rides/history.txt") == hist_lines && p->power.paired == paired && g_sim.phone.bonded, "history, sensor pairing and phone bond untouched"); }
        n = bc_link_encode_profile(BC_MSG_PROFILE_SET, &pm, b, sizeof b, 16, 0); sim_phone_write(0, b, n); run(600);
        CHECK(g_sim.phone.profile_acks == 2 && g_sim.phone.profile_ack.status == BC_PF_OLDER && g_sim.phone.profile_ack.board_version == 1, "the same version again -> rejected as older/equal");
        pm.version = 2; pm.has = BC_PF_HAS(0x04) | BC_PF_HAS(0x05); pm.ftp_w = 262; pm.ftp_how = 2;
        n = bc_link_encode_profile(BC_MSG_PROFILE_SET, &pm, b, sizeof b, 17, 0); sim_phone_write(0, b, n); run(600);
        CHECK(g_sim.phone.profile_ack.status == BC_PF_APPLIED && app_profile()->ftp_w == 262 && app_profile()->ftp_how == BC_FTP_AUTO && !strcmp(app_profile()->name, "Rashed"), "partial SET v2: only the FTP changes (now %s)", bc_ftp_label(app_profile()));
        n = bc_link_encode_profile_get(b, sizeof b, 18, 0); sim_phone_write(0, b, n); run(600);
        CHECK(g_sim.phone.profile.version == 2 && g_sim.phone.profile.source == 1 && g_sim.phone.profile.ftp_w == 262 && g_sim.phone.profile.ftp_how == 2 && g_sim.phone.profile.birth_year == 1990, "PROFILE now reports phone-synced v2");
        ui_home_show(); run(300); CHECK(on_screen("Rashed") && on_screen("262"), "home shows the synced profile"); shot("e2_home_synced_profile");
        boot(); run(400); CHECK(app_profile()->phone_prof_ver == 2 && app_profile()->ftp_w == 262 && app_profile()->rest_hr == 52, "synced profile survives a restart (board works alone with it)");
        plat_phone_set_enabled(true); sim_phone_connect(true); run(500);

        /* ---- device settings */
        g_sim.phone.settings_msgs = 0;
        n = bc_link_encode_settings_get(b, sizeof b, 19, 0); sim_phone_write(0, b, n); run(600);
        CHECK(g_sim.phone.settings_msgs == 1 && g_sim.phone.settings.version == 0 && g_sim.phone.settings.supported_mask == BC_SETTINGS_SUPPORTED_ALL && g_sim.phone.settings.brightness_pct == app_profile()->brightness && g_sim.phone.settings.screen_timeout_s == app_profile()->scr_timeout_s && g_sim.phone.settings.wake_gesture == 0,
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

    printf("== 8 long name and edge cases\n");
    snprintf(app_profile()->name, sizeof app_profile()->name, "Maximilianus Bob");
    app_profile_save();
    ui_home_show(); run(300); shot("90_home_long_name");
    ui_settings_show(); run(300); shot("91_settings_long_name");
    g_sim.battery_pct = 5; g_sim.usb = false; ui_home_show(); run(300); shot("92_home_low_battery");
    g_sim.usb = true; ui_home_show(); run(300); shot("93_home_usb");
    app_profile()->power.paired = false; g_sim.link[PLAT_SENS_POWER].link = PLAT_LINK_NOT_PAIRED; sensors(false, 0, false, 0, false, 0);
    ui_home_show(); run(300); shot("94_home_no_meter");
    ui_test_set_style(0); tap_text("START RIDE"); run_s(10); shot("95_ride_no_meter_paired");
    drag(120, 60, 120, 190); hold_text("HOLD: END", 2300); shot("96_results_no_data");
    hold_text(LV_SYMBOL_TRASH, 1800);
    /* re-run setup keeps history */
    int before = count_lines("rides/history.txt");
    ui_settings_show(); run(300);
    scroll_to("SET UP AGAIN");
    hold_text("SET UP AGAIN", 2300);
    CHECK(on_screen("Hello!") && count_lines("rides/history.txt") == before, "setup again keeps ride history");
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
    scenario();
    lv_mem_monitor_t m; lv_mem_monitor(&m);
    printf("\nLVGL memory: %u%% used, max used %u bytes of %u, fragmentation %u%%\n", m.used_pct, (unsigned)m.max_used, (unsigned)m.total_size, m.frag_pct);
    CHECK(m.max_used < m.total_size * 85 / 100, "LVGL heap stays under 85%% (max %u of %u)", (unsigned)m.max_used, (unsigned)m.total_size);
    printf("\n%d screens checked, %d with issues; %d functional checks, %d failed\n", n_shots, n_fail_shots, n_checks, n_fail);
    fprintf(report, "SUMMARY screens=%d screen_fail=%d checks=%d check_fail=%d lvgl_max_used=%u/%u\n", n_shots, n_fail_shots, n_checks, n_fail,
            (unsigned)m.max_used, (unsigned)m.total_size);
    fclose(report);
    return (n_fail_shots || n_fail) ? 1 : 0;
}
