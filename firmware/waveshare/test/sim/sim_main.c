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

static void run(int ms) { for (int t = 0; t < ms; t += 5) { g_sim.now_ms += 5; lv_timer_handler(); } }
static void run_s(int s) { for (int i = 0; i < s; i++) run(1000); }
static void tap(int x, int y) { ptr.x = x; ptr.y = y; ptr.down = true; run(80); ptr.down = false; run(150); }
static void hold(int x, int y, int ms) { ptr.x = x; ptr.y = y; ptr.down = true; run(ms); ptr.down = false; run(150); }
static void drag(int x0, int y0, int x1, int y1)
{
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
    lv_obj_t *l = find_text(txt);
    if (!l) { n_checks++; n_fail++; printf("  FAIL could not find '%s' to tap\n", txt); return false; }
    lv_obj_t *c = l; while (c && !lv_obj_has_flag(c, LV_OBJ_FLAG_CLICKABLE)) c = lv_obj_get_parent(c);
    if (!c) c = l;
    lv_area_t a; lv_obj_get_coords(c, &a);
    tap((a.x1 + a.x2) / 2, (a.y1 + a.y2) / 2);
    return true;
}

static bool hold_text(const char *txt, int ms)
{
    lv_obj_t *l = find_text(txt);
    if (!l) { n_checks++; n_fail++; printf("  FAIL could not find '%s' to hold\n", txt); return false; }
    lv_obj_t *c = l; while (c && !lv_obj_has_flag(c, LV_OBJ_FLAG_CLICKABLE)) c = lv_obj_get_parent(c);
    lv_area_t a; lv_obj_get_coords(c ? c : l, &a);
    hold((a.x1 + a.x2) / 2, (a.y1 + a.y2) / 2, ms);
    return true;
}

static bool on_screen(const char *txt) { return find_text(txt) != NULL; }

/* scroll the screen's scroll area until txt is visible (tries both directions) */
static bool scroll_to(const char *txt)
{
    for (int k = 0; k < 12 && !on_screen(txt); k++) drag(120, 90, 120, 170);   /* towards the top */
    for (int k = 0; k < 14 && !on_screen(txt); k++) drag(120, 160, 120, 90);   /* towards the bottom */
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
    app_init();
    ui_start();
    run(500);
}

static int count_lines(const char *path)
{
    char p[512]; snprintf(p, sizeof p, "simfs/%s", path);
    FILE *f = fopen(p, "r"); if (!f) return 0; int n = 0, c; while ((c = fgetc(f)) != EOF) if (c == '\n') n++; fclose(f); return n;
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
