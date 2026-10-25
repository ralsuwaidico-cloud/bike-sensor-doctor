/*
 * Ride screens — swipe carousel (approved navigation A) with a pull-down control panel (swipe down, or tap the handle
 * at the top). Pause and End are hold-to-confirm; Resume is a tap.
 *   1 POWER (style A Power Focus [approved] / B Split / C Coach First — chosen in Settings > Ride screen)
 *   2 COACH   3 RIDE (time and averages)   4 CONNECTIONS (sensor states)
 * Missing data is shown as "--" with NO DATA / NO STRAP — never a held or invented value.
 */
#include "ui.h"
#include <stdio.h>
#include <string.h>

static lv_obj_t *r_tv, *r_panel;
static int r_style;
/* page 1 */
static lv_obj_t *w_arc, *w_band, *w_status, *w_watts, *w_unit, *w_cad, *w_hr, *w_cue, *w_cue_lbl, *w_ring, *w_head, *w_time1;
/* page 2 */
static lv_obj_t *c_head, *c_why, *c_target, *c_inband, *c_live;
/* page 3 */
static lv_obj_t *m_time, *m_state, *m_l1, *m_l2, *m_l3;
/* page 4 */
static lv_obj_t *s_txt;
/* panel */
static lv_obj_t *p_time, *p_state, *p_pause, *p_resume;
static int s_forced_style = -1;

void ui_test_set_style(int st) { s_forced_style = st; }

static lv_obj_t *tile_label(lv_obj_t *t, const lv_font_t *f, lv_color_t c, int y)
{
    lv_obj_t *l = ui_label(t, f, c, "");
    lv_obj_align(l, LV_ALIGN_TOP_MID, 0, y);
    return l;
}

static lv_obj_t *mk_arc(lv_obj_t *p, int size, int width, int a0, int a1, lv_color_t bg, lv_color_t ind)
{
    lv_obj_t *a = lv_arc_create(p);
    lv_obj_remove_style(a, NULL, LV_PART_KNOB);
    lv_obj_remove_flag(a, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_set_size(a, size, size);
    lv_obj_center(a);
    lv_arc_set_bg_angles(a, a0, a1);
    lv_obj_set_style_arc_width(a, width, LV_PART_MAIN);
    lv_obj_set_style_arc_width(a, width, LV_PART_INDICATOR);
    lv_obj_set_style_arc_color(a, bg, LV_PART_MAIN);
    lv_obj_set_style_arc_color(a, ind, LV_PART_INDICATOR);
    lv_obj_set_style_pad_all(a, 0, 0);
    lv_obj_add_flag(a, LV_OBJ_FLAG_GESTURE_BUBBLE);
    return a;
}

/* ---- page 1 variants */
static lv_obj_t *w_cad_u, *w_hr_u;
static void reset_widgets(void)
{
    w_arc = w_band = w_ring = w_head = w_time1 = w_cad_u = w_hr_u = NULL;
    w_status = w_watts = w_unit = w_cad = w_hr = w_cue = w_cue_lbl = NULL;
}

static void build_focus(lv_obj_t *t)
{
    {
        /* A — Power Focus (approved): power arc with the target band on its outer edge, huge watts, cadence + HR, coach pill */
        w_arc = mk_arc(t, 228, 10, 135, 45, C_TRACK, C_CYAN);
        lv_arc_set_range(w_arc, 0, 1000);
        w_band = mk_arc(t, 228, 4, 135, 45, C_BG, C_FG);
        lv_obj_set_style_arc_opa(w_band, LV_OPA_TRANSP, LV_PART_MAIN);
        lv_obj_set_style_arc_rounded(w_band, false, LV_PART_INDICATOR);
        w_status = tile_label(t, &lv_font_montserrat_12, C_MUT, 30);
        w_watts = tile_label(t, &bc_num80, C_FG, 46);
        w_unit = tile_label(t, &lv_font_montserrat_12, C_MUT, 128);
        w_cad = ui_label(t, &bc_bold22, C_VIOLET, ""); lv_obj_align(w_cad, LV_ALIGN_TOP_MID, -42, 142);
        w_hr = ui_label(t, &bc_bold22, C_MUT, ""); lv_obj_align(w_hr, LV_ALIGN_TOP_MID, 42, 142);
        w_cad_u = ui_label(t, &lv_font_montserrat_12, C_MUT, "RPM"); lv_obj_align(w_cad_u, LV_ALIGN_TOP_MID, -42, 166);
        w_hr_u = ui_label(t, &lv_font_montserrat_12, C_MUT, "BPM"); lv_obj_align(w_hr_u, LV_ALIGN_TOP_MID, 42, 166);
        w_cue = lv_obj_create(t); lv_obj_remove_style_all(w_cue);
        lv_obj_set_size(w_cue, LV_SIZE_CONTENT, 26); lv_obj_set_style_radius(w_cue, 13, 0); lv_obj_set_style_bg_opa(w_cue, LV_OPA_COVER, 0);
        lv_obj_set_style_pad_hor(w_cue, 10, 0); lv_obj_align(w_cue, LV_ALIGN_TOP_MID, 0, 186);
        lv_obj_remove_flag(w_cue, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_add_flag(w_cue, LV_OBJ_FLAG_GESTURE_BUBBLE);
        w_cue_lbl = ui_label(w_cue, &bc_bold16, C_INK, ""); lv_obj_center(w_cue_lbl);
    }
}

static void build_split(lv_obj_t *t)
{
    {
        /* B — Split: watts on top, cadence | heart rate below, coach word at the bottom */
        w_status = tile_label(t, &lv_font_montserrat_12, C_MUT, 24);
        w_watts = tile_label(t, &bc_num80, C_FG, 44);
        w_unit = tile_label(t, &lv_font_montserrat_12, C_MUT, 124);
        lv_obj_t *line = lv_obj_create(t); lv_obj_remove_style_all(line);
        lv_obj_set_size(line, 196, 2); lv_obj_set_style_bg_color(line, C_FAINT, 0); lv_obj_set_style_bg_opa(line, LV_OPA_COVER, 0);
        lv_obj_align(line, LV_ALIGN_TOP_MID, 0, 140); lv_obj_remove_flag(line, LV_OBJ_FLAG_CLICKABLE);
        lv_obj_t *vl = lv_obj_create(t); lv_obj_remove_style_all(vl);
        lv_obj_set_size(vl, 2, 50); lv_obj_set_style_bg_color(vl, C_FAINT, 0); lv_obj_set_style_bg_opa(vl, LV_OPA_COVER, 0);
        lv_obj_align(vl, LV_ALIGN_TOP_MID, 0, 148); lv_obj_remove_flag(vl, LV_OBJ_FLAG_CLICKABLE);
        w_cad = ui_label(t, &bc_num44, C_VIOLET, ""); lv_obj_align(w_cad, LV_ALIGN_TOP_MID, -46, 142);
        w_hr = ui_label(t, &bc_num44, C_MUT, ""); lv_obj_align(w_hr, LV_ALIGN_TOP_MID, 46, 142);
        lv_obj_t *l1 = ui_label(t, &lv_font_montserrat_12, C_MUT, "RPM"); lv_obj_align(l1, LV_ALIGN_TOP_MID, -46, 188);
        w_hr_u = ui_label(t, &lv_font_montserrat_12, C_MUT, "BPM"); lv_obj_align(w_hr_u, LV_ALIGN_TOP_MID, 46, 188);
        w_cue = NULL; w_cue_lbl = tile_label(t, &bc_bold16, C_GREEN, 203);
    }
}

static void build_coach(lv_obj_t *t)
{
    {
        /* C — Coach First: the instruction leads, the ring colour says on target / more / less */
        w_ring = mk_arc(t, 230, 8, 0, 360, C_TRACK, C_GREEN);
        lv_arc_set_range(w_ring, 0, 100); lv_arc_set_value(w_ring, 100);
        w_head = ui_label(t, &bc_bold22, C_FG, ""); lv_obj_set_width(w_head, 150);
        lv_label_set_long_mode(w_head, LV_LABEL_LONG_WRAP); lv_obj_align(w_head, LV_ALIGN_TOP_MID, 0, 40);
        w_status = NULL;
        w_watts = tile_label(t, &bc_num80, C_FG, 90);
        w_unit = tile_label(t, &lv_font_montserrat_12, C_MUT, 170);
        w_cad = ui_label(t, &bc_bold16, C_VIOLET, ""); lv_obj_align(w_cad, LV_ALIGN_TOP_MID, -38, 186);
        w_time1 = ui_label(t, &bc_bold16, C_FG, ""); lv_obj_align(w_time1, LV_ALIGN_TOP_MID, 40, 186);
        w_hr = NULL; w_cue = NULL; w_cue_lbl = NULL;
    }
}

/*
 * Ride-screen designs. Every design is only a LAYOUT of the same widgets: ride_update() fills whatever widgets the
 * design created (all fed from the same app/coach data), so designs are visual alternatives, not separate code paths.
 * To add a design: write build_x(tile), add one line here, add its thumbnail (tools/make_thumbs.py) and raise
 * BC_STYLE_COUNT. Every design must pass the round-screen checks in test/sim.
 */
static const ui_ride_design_t DESIGNS[] = {
    { 'A', "Power Focus", "big watts + power arc", build_focus, false },
    { 'B', "Split", "cadence + HR below", build_split, false },
    { 'C', "Coach First", "instruction first", build_coach, true },
};
int ui_ride_design_count(void) { return (int)(sizeof DESIGNS / sizeof DESIGNS[0]); }
const ui_ride_design_t *ui_ride_design(int i) { return &DESIGNS[(i >= 0 && i < ui_ride_design_count()) ? i : 0]; }

static lv_obj_t *r_tile0;
static void page_power(lv_obj_t *t)
{
    reset_widgets();
    r_tile0 = t;
    ui_ride_design(r_style)->build(t);
}

static void build_pages(lv_obj_t *scr)
{
    r_tv = lv_tileview_create(scr);
    lv_obj_set_style_bg_opa(r_tv, LV_OPA_TRANSP, 0);
    lv_obj_set_scrollbar_mode(r_tv, LV_SCROLLBAR_MODE_OFF);
    lv_obj_t *t[4];
    for (int i = 0; i < 4; i++) {
        t[i] = lv_tileview_add_tile(r_tv, (uint8_t)i, 0, (i == 0 ? 0 : LV_DIR_LEFT) | (i == 3 ? 0 : LV_DIR_RIGHT));
        ui_page_dots(t[i], 4, i, 222);
    }
    page_power(t[0]);
    ui_title(t[1], "COACH");
    c_head = ui_label(t[1], &bc_bold22, C_FG, ""); lv_obj_set_width(c_head, 180); lv_label_set_long_mode(c_head, LV_LABEL_LONG_WRAP);
    lv_obj_align(c_head, LV_ALIGN_TOP_MID, 0, 58);
    c_why = tile_label(t[1], &lv_font_montserrat_14, C_FG, 116);
    c_target = tile_label(t[1], &lv_font_montserrat_12, C_MUT, 140);
    c_inband = tile_label(t[1], &lv_font_montserrat_12, C_MUT, 158);
    c_live = tile_label(t[1], &bc_bold16, C_MUT, 180);

    ui_title(t[2], "RIDE");
    m_time = tile_label(t[2], &bc_num44, C_FG, 52);
    m_state = tile_label(t[2], &bc_bold16, C_AMBER, 100);
    m_l1 = tile_label(t[2], &lv_font_montserrat_14, C_FG, 122);
    m_l2 = tile_label(t[2], &lv_font_montserrat_14, C_FG, 144);
    m_l3 = tile_label(t[2], &lv_font_montserrat_12, C_MUT, 168);
    lv_label_set_recolor(m_l1, true); lv_label_set_recolor(m_l2, true);

    ui_title(t[3], "CONNECTIONS");
    s_txt = tile_label(t[3], &lv_font_montserrat_12, C_FG, 54);
    lv_label_set_recolor(s_txt, true);
    lv_obj_t *hint = tile_label(t[3], &lv_font_montserrat_12, C_MUT, 192);
    lv_label_set_text(hint, LV_SYMBOL_DOWN " swipe down: controls");
}

/* ---- control panel */
static void panel_open(void) { lv_obj_remove_flag(r_panel, LV_OBJ_FLAG_HIDDEN); lv_obj_move_foreground(r_panel); }
static void panel_close_cb(lv_event_t *e) { (void)e; lv_obj_add_flag(r_panel, LV_OBJ_FLAG_HIDDEN); }
static void handle_cb(lv_event_t *e) { (void)e; panel_open(); }
static void qs_cb(lv_event_t *e) { (void)e; lv_obj_add_flag(r_panel, LV_OBJ_FLAG_HIDDEN); ui_qs_open(); }
static void pause_cb(lv_event_t *e) { (void)e; app_ride_pause(); }
static void resume_cb(lv_event_t *e) { (void)e; app_ride_resume(); lv_obj_add_flag(r_panel, LV_OBJ_FLAG_HIDDEN); }
static void end_cb(lv_event_t *e)
{
    (void)e;
    app_ride_end();
    bc_ride_summary_t s; app_ride_totals(&s);
    ui_results_show(&s, true);
}

static lv_obj_t *p_design;
static void ride_update(void);
/* switch design during a ride: only page 1's widgets are rebuilt; recording and coaching carry on untouched */
static void design_cb(lv_event_t *e)
{
    (void)e;
    r_style = (r_style + 1) % ui_ride_design_count();
    app_profile()->ride_style = (uint8_t)r_style;
    app_profile_save();
    lv_obj_clean(r_tile0);
    ui_page_dots(r_tile0, 4, 0, 222);
    page_power(r_tile0);
    ride_update();
}

static void gesture_cb(lv_event_t *e)
{
    (void)e;
    lv_dir_t d = lv_indev_get_gesture_dir(lv_indev_active());
    if (d == LV_DIR_BOTTOM) panel_open();
    else if (d == LV_DIR_TOP) lv_obj_add_flag(r_panel, LV_OBJ_FLAG_HIDDEN);
}

static void build_panel(lv_obj_t *scr)
{
    r_panel = lv_obj_create(scr);
    lv_obj_remove_style_all(r_panel);
    lv_obj_set_size(r_panel, UI_W, UI_W);
    lv_obj_set_style_bg_color(r_panel, C_BG, 0);
    lv_obj_set_style_bg_opa(r_panel, LV_OPA_COVER, 0);
    lv_obj_add_flag(r_panel, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_flag(r_panel, LV_OBJ_FLAG_GESTURE_BUBBLE);
    ui_title(r_panel, "CONTROLS");
    p_time = ui_label(r_panel, &bc_bold22, C_FG, ""); lv_obj_align(p_time, LV_ALIGN_TOP_MID, 0, 48);
    p_state = ui_label(r_panel, &lv_font_montserrat_12, C_MUT, ""); lv_obj_align(p_state, LV_ALIGN_TOP_MID, 0, 72);
    p_design = ui_pill(r_panel, "", C_PANEL, C_CYAN, 150, 28, design_cb, NULL);
    lv_obj_set_style_text_font(lv_obj_get_child(p_design, 0), &lv_font_montserrat_14, 0);
    lv_obj_align(p_design, LV_ALIGN_TOP_MID, 0, 76);
    /* ride controls stay first and unchanged: pause / resume / end (hold to confirm). Quick Settings is a plain button
       below them and can never pause or end the ride. */
    p_pause = ui_hold_btn(r_panel, "HOLD: PAUSE", C_AMBER, C_INK, 168, 38, 1000, pause_cb, NULL);
    lv_obj_align(p_pause, LV_ALIGN_TOP_MID, 0, 108);
    p_resume = ui_pill(r_panel, LV_SYMBOL_PLAY " RESUME", C_GREEN, C_INK, 168, 38, resume_cb, NULL);
    lv_obj_set_style_text_font(lv_obj_get_child(p_resume, 0), &lv_font_montserrat_20, 0);
    lv_obj_align(p_resume, LV_ALIGN_TOP_MID, 0, 108);
    lv_obj_t *end = ui_hold_btn(r_panel, "HOLD: END", C_RED, C_INK, 140, 36, 1000, end_cb, NULL);
    lv_obj_align(end, LV_ALIGN_TOP_MID, 0, 150);
    lv_obj_t *qs = ui_pill(r_panel, LV_SYMBOL_SETTINGS " QUICK SET.", C_PANEL, C_CYAN, 98, 28, qs_cb, NULL);
    lv_obj_set_style_text_font(lv_obj_get_child(qs, 0), &lv_font_montserrat_12, 0);
    lv_obj_align(qs, LV_ALIGN_TOP_LEFT, 52, 188);
    lv_obj_t *x = ui_round_btn(r_panel, LV_SYMBOL_UP, C_PANEL, C_FG, 30, panel_close_cb, NULL);
    lv_obj_set_style_text_font(lv_obj_get_child(x, 0), &lv_font_montserrat_14, 0);
    lv_obj_align(x, LV_ALIGN_TOP_LEFT, 156, 187);
    lv_obj_add_flag(r_panel, LV_OBJ_FLAG_HIDDEN);
}

/* ---- live update */
static void fmt_watts(lv_obj_t *l, bool ok, int w)
{
    char b[12];
    if (!ok) { lv_label_set_text(l, "--"); lv_obj_set_style_text_color(l, C_MUT, 0); lv_obj_set_style_text_font(l, &bc_num80, 0); return; }
    snprintf(b, sizeof b, "%d", w);
    lv_label_set_text(l, b);
    lv_obj_set_style_text_color(l, C_FG, 0);
    lv_obj_set_style_text_font(l, w >= 1000 ? &bc_num60 : &bc_num80, 0);
}

static void ride_update(void)
{
    if (app_ride_state() == BC_RIDE_ENDED) {        /* ended from the phone: same results screen as the END button */
        bc_ride_summary_t s; app_ride_totals(&s); ui_results_show(&s, true); return;
    }
    app_live_t lv; app_live(&lv);
    bc_ride_summary_t s; app_ride_totals(&s);
    const bc_cue_t *cue = app_cue();
    bc_ride_state_t st = app_ride_state();
    int lo, hi; bool rel; app_target(&lo, &hi, &rel);
    char b[240], tm[16]; bc_fmt_duration(s.duration_s, tm, sizeof tm);
    bool paused = st == BC_RIDE_PAUSED;
    lv_color_t cc = ui_level_color(cue->level);
    const char *cshort = paused ? "PAUSED" : ui_cue_short(cue);
    if (paused) cc = C_AMBER;

    /* page 1 */
    fmt_watts(w_watts, lv.power_ok, lv.watts);
    if (w_status) {
        char bat[24]; ui_battery_text(bat, sizeof bat);
        snprintf(b, sizeof b, "#%06x %s#  %s  %s", ui_hex(lv.demo ? C_DEMO : ui_link_color(lv.link[PLAT_SENS_POWER].link)),
                 lv.demo ? "DEMO" : "PWR", tm, bat);
        lv_label_set_recolor(w_status, true);
        lv_label_set_text(w_status, b);
    }
    if (lo > 0) snprintf(b, sizeof b, "%s %d-%d", rel ? "PACE" : "TARGET", lo, hi);
    else snprintf(b, sizeof b, "WATTS");
    if (!lv.power_ok) snprintf(b, sizeof b, "NO DATA");
    lv_label_set_text(w_unit, b);
    lv_obj_set_style_text_color(w_unit, lv.power_ok ? C_MUT : C_AMBER, 0);
    if (ui_ride_design(r_style)->cad_inline) {
        if (lv.cad_ok) snprintf(b, sizeof b, "%d rpm", lv.rpm); else snprintf(b, sizeof b, "-- rpm");
        lv_label_set_text(w_cad, b);
    } else {
        if (lv.cad_ok) snprintf(b, sizeof b, "%d", lv.rpm); else snprintf(b, sizeof b, "--");
        lv_label_set_text(w_cad, b);
        lv_obj_set_style_text_color(w_cad, lv.cad_ok ? C_VIOLET : C_MUT, 0);
        if (lv.hr_ok) snprintf(b, sizeof b, "%d", lv.bpm); else snprintf(b, sizeof b, "--");
        lv_label_set_text(w_hr, b);
        lv_obj_set_style_text_color(w_hr, lv.hr_ok ? C_RED : C_MUT, 0);
        /* the unit line names the heart-rate source (STRAP / WATCH / …) so a relayed value is never mistaken for the strap */
        lv_label_set_text(w_hr_u, lv.hr_ok ? bc_src_name(lv.hr_src) : lv.link[PLAT_SENS_HR].link == PLAT_LINK_NOT_PAIRED && !lv.phone_hr ? "NO HR" : "BPM");
    }
    if (w_arc) {
        int maxw = hi > 0 ? hi * 2 : (app_profile()->ftp_w ? app_profile()->ftp_w * 3 / 2 : 400);
        if (maxw < 200) maxw = 200;
        int v = lv.power_ok ? lv.watts * 1000 / maxw : 0; if (v > 1000) v = 1000;
        lv_arc_set_value(w_arc, v);
        if (lo > 0) {
            int a0 = 135 + lo * 270 / maxw, a1 = 135 + (hi > maxw ? maxw : hi) * 270 / maxw;
            lv_arc_set_angles(w_band, a0 % 360, a1 % 360);
            lv_obj_remove_flag(w_band, LV_OBJ_FLAG_HIDDEN);
        } else lv_obj_add_flag(w_band, LV_OBJ_FLAG_HIDDEN);
    }
    if (w_cue) { lv_obj_set_style_bg_color(w_cue, cc, 0); lv_label_set_text(w_cue_lbl, cshort); }
    else if (w_cue_lbl) { lv_obj_set_style_text_color(w_cue_lbl, cc, 0); lv_label_set_text(w_cue_lbl, cshort); }
    if (w_ring) { lv_obj_set_style_arc_color(w_ring, cc, LV_PART_INDICATOR); }
    if (w_head) { lv_label_set_text(w_head, paused ? "PAUSED" : (cue->head[0] ? cue->head : "READY")); lv_obj_set_style_text_color(w_head, cue->level == BC_LVL_INFO && !paused ? C_FG : cc, 0); }
    if (w_time1) lv_label_set_text(w_time1, tm);

    /* page 2: coach */
    lv_label_set_text(c_head, paused ? "PAUSED" : (cue->head[0] ? cue->head : "READY"));
    lv_obj_set_style_text_color(c_head, cue->level == BC_LVL_INFO && !paused ? C_FG : cc, 0);
    lv_label_set_text(c_why, paused ? "resume from the controls" : cue->why);
    if (lo > 0 && !rel) snprintf(b, sizeof b, "target %d-%d W (FTP %s)", lo, hi, bc_ftp_label(app_profile()));
    else if (lo > 0) snprintf(b, sizeof b, "your steady pace %d-%d W", lo, hi);
    else snprintf(b, sizeof b, "FTP %s: learning your pace", bc_ftp_label(app_profile()));
    lv_label_set_text(c_target, b);
    int pct = app_coach_inband_pct();
    if (pct >= 0) snprintf(b, sizeof b, "%s %d%% of the time", rel ? "steady" : "in target", pct);
    else snprintf(b, sizeof b, "%s", rel ? "judged against your own riding" : "judged after warm-up");
    lv_label_set_text(c_inband, b);
    if (lv.power_ok) snprintf(b, sizeof b, "%d W", lv.watts);
    else snprintf(b, sizeof b, "power NO DATA");
    if (lv.power_ok && lv.cad_ok) snprintf(b, sizeof b, "%d W   %d rpm", lv.watts, lv.rpm);
    lv_label_set_text(c_live, b);

    /* page 3: metrics */
    lv_label_set_text(m_time, tm);
    lv_label_set_text(m_state, paused ? "PAUSED" : "");
    char ap[12], mp[12], ac[12], ah[12];
    if (s.avg_power >= 0) snprintf(ap, sizeof ap, "%d", s.avg_power); else snprintf(ap, sizeof ap, "--");
    if (s.max_power >= 0) snprintf(mp, sizeof mp, "%d", s.max_power); else snprintf(mp, sizeof mp, "--");
    if (s.avg_cad >= 0) snprintf(ac, sizeof ac, "%d", s.avg_cad); else snprintf(ac, sizeof ac, "--");
    if (s.avg_hr >= 0) snprintf(ah, sizeof ah, "%d", s.avg_hr); else snprintf(ah, sizeof ah, "--");
    snprintf(b, sizeof b, "#8494a0 AVG# %s W  #8494a0 MAX# %s W", ap, mp); lv_label_set_text(m_l1, b);
    snprintf(b, sizeof b, "#8494a0 CAD# %s  #8494a0 HR# %s  #8494a0 kJ# %d", ac, ah, s.kj); lv_label_set_text(m_l2, b);
    {   /* speed / distance come only from a connected phone's GPS; stale or missing is said, never guessed */
        const plat_link_info_t *sp = &lv.link[PLAT_SENS_SPEED];
        char dist[20];
        if (s.dist_src) snprintf(dist, sizeof dist, "%lu.%02lu km", (unsigned long)(s.distance_m / 1000), (unsigned long)(s.distance_m % 1000 / 10)); else snprintf(dist, sizeof dist, "--");
        if (lv.speed_ok) snprintf(b, sizeof b, "%d.%d km/h  %s\n#56e08c %s#", lv.speed_dmh / 10, lv.speed_dmh % 10, dist, bc_src_name(lv.speed_src));
        else if (sp->link == PLAT_LINK_STALE) snprintf(b, sizeof b, "-- km/h  %s\n#ffb64d %s STALE# %lus", dist, sp->name, (unsigned long)(sp->age_ms / 1000));
        else if (sp->link == PLAT_LINK_SEARCHING) snprintf(b, sizeof b, "-- km/h  %s\n#ffb64d waiting for GPS#", dist);
        else snprintf(b, sizeof b, "speed / distance: %s\nphone GPS not connected", dist);
        lv_label_set_recolor(m_l3, true);
        lv_label_set_text(m_l3, b);
    }

    /* page 4: sensors */
    const plat_link_info_t *pw = &lv.link[PLAT_SENS_POWER], *hr = &lv.link[PLAT_SENS_HR];
    char age[16] = "--";
    if (pw->age_ms != UINT32_MAX && pw->link == PLAT_LINK_CONNECTED) snprintf(age, sizeof age, "%lu.%lus", (unsigned long)(pw->age_ms / 1000), (unsigned long)(pw->age_ms % 1000 / 100));
    char bat[24]; ui_battery_text(bat, sizeof bat);
    char rssi[16]; if (pw->rssi) snprintf(rssi, sizeof rssi, "%d dBm", pw->rssi); else rssi[0] = 0;
    char hrs[40];
    if (lv.hr_ok) snprintf(hrs, sizeof hrs, "#56e08c %s# %d bpm%s", bc_src_name(lv.hr_src), lv.bpm, (lv.strap_hr && lv.phone_hr) ? " +backup" : "");
    else snprintf(hrs, sizeof hrs, "#%06x %s#", ui_hex(ui_link_color(hr->link)), hr->link == PLAT_LINK_NOT_PAIRED ? "NO SOURCE" : ui_link_text(hr->link));
    const plat_link_info_t *sp = &lv.link[PLAT_SENS_SPEED];
    char gps[40];
    if (sp->link == PLAT_LINK_NOT_PAIRED) snprintf(gps, sizeof gps, "#8494a0 no phone#");
    else snprintf(gps, sizeof gps, "#%06x %s %s#", ui_hex(ui_link_color(sp->link)), sp->name, ui_link_text(sp->link));
    snprintf(b, sizeof b, "#8494a0 POWER%s#\n#%06x %s# %s\nlast data %s\n#8494a0 HEART RATE# %s\n#8494a0 GPS# %s\n#8494a0 BATTERY# %s",
             lv.demo ? " (SIMULATED)" : "", ui_hex(ui_link_color(pw->link)), ui_link_text(pw->link), rssi, age, hrs, gps, bat);
    lv_label_set_text(s_txt, b);

    /* panel */
    { char pt[32]; snprintf(pt, sizeof pt, paused ? "PAUSED %s" : "%s", tm); lv_label_set_text(p_time, pt);
      lv_obj_set_style_text_color(p_time, paused ? C_AMBER : C_FG, 0); }
    lv_obj_add_flag(p_state, LV_OBJ_FLAG_HIDDEN);   /* state is shown in the time line */
    { char d[40]; snprintf(d, sizeof d, "SCREEN %c " LV_SYMBOL_RIGHT, ui_ride_design(r_style)->letter); lv_label_set_text(lv_obj_get_child(p_design, 0), d); }
    if (paused) { lv_obj_add_flag(p_pause, LV_OBJ_FLAG_HIDDEN); lv_obj_remove_flag(p_resume, LV_OBJ_FLAG_HIDDEN); }
    else { lv_obj_remove_flag(p_pause, LV_OBJ_FLAG_HIDDEN); lv_obj_add_flag(p_resume, LV_OBJ_FLAG_HIDDEN); }
}

void ui_ride_show(void)
{
    r_style = s_forced_style >= 0 ? s_forced_style : app_profile()->ride_style;
    lv_obj_t *scr = ui_screen_new(UI_SCR_RIDE, ride_update);
    build_pages(scr);
    /* handle at the top: tap to open the controls (also: swipe down anywhere) */
    lv_obj_t *h = lv_button_create(scr);
    lv_obj_remove_style_all(h);
    lv_obj_set_size(h, 72, 20);          /* y 4..23: clear of design B's status row at y 24 */
    lv_obj_align(h, LV_ALIGN_TOP_MID, 0, 4);
    lv_obj_t *bar = lv_obj_create(h); lv_obj_remove_style_all(bar);
    lv_obj_set_size(bar, 30, 4); lv_obj_set_style_radius(bar, 2, 0); lv_obj_set_style_bg_color(bar, C_FAINT, 0); lv_obj_set_style_bg_opa(bar, LV_OPA_COVER, 0);
    lv_obj_align(bar, LV_ALIGN_TOP_MID, 0, 8); lv_obj_remove_flag(bar, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(h, handle_cb, LV_EVENT_CLICKED, NULL);
    build_panel(scr);
    lv_obj_add_event_cb(scr, gesture_cb, LV_EVENT_GESTURE, NULL);
    ui_screen_show(scr);
}
