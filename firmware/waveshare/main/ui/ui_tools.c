/* Settings > Display (ride-screen picker with preview, brightness), Settings > Diagnostics (Device Health, Sensor Test,
 * Self-test) and the diagnostic report export. */
#include "ui.h"
#include "app_diag.h"
#include "app_psvc.h"
#include <stdio.h>
#include <string.h>

static void back_settings(lv_event_t *e) { (void)e; ui_settings_show(); }

/* ---------------- Display */
static void picker_cb(lv_event_t *e) { (void)e; ui_style_picker_show(); }
static void bright_cb(lv_event_t *e) { (void)e; ui_edit_show(UI_EDIT_BRIGHT, false); }

void ui_display_show(void)
{
    bc_profile_t *p = app_profile();
    lv_obj_t *scr = ui_screen_new(UI_SCR_SETTINGS, NULL);
    ui_title(scr, "DISPLAY");
    lv_obj_t *l = ui_scroll_area(scr, 56, 168);
    char v[24];
    snprintf(v, sizeof v, "%c  " LV_SYMBOL_RIGHT, ui_ride_design(p->ride_style)->letter); ui_row_btn(l, "Ride screen", v, C_CYAN, picker_cb, NULL);
    snprintf(v, sizeof v, "%u%%", p->brightness); ui_row_btn(l, "Brightness", v, C_CYAN, bright_cb, NULL);
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 44, back_settings, NULL);
    lv_obj_align(bk, LV_ALIGN_TOP_MID, 0, 176);
    ui_screen_show(scr);
}

/* ---------------- Ride-screen picker: preview of each design, arrows to browse, USE to choose */
static int pk_i;
static lv_obj_t *pk_img, *pk_name, *pk_hint, *pk_use;

static void picker_draw(void)
{
    const ui_ride_design_t *d = ui_ride_design(pk_i);
    const lv_image_dsc_t *t = ui_ride_thumb(pk_i);
    if (t) { lv_image_set_src(pk_img, t); lv_obj_remove_flag(pk_img, LV_OBJ_FLAG_HIDDEN); } else lv_obj_add_flag(pk_img, LV_OBJ_FLAG_HIDDEN);
    char b[40]; snprintf(b, sizeof b, "%c  %s", d->letter, d->name); lv_label_set_text(pk_name, b);
    bool cur = pk_i == app_profile()->ride_style;
    snprintf(b, sizeof b, "%s", cur ? "in use" : d->hint);
    lv_label_set_text(pk_hint, b);
    lv_obj_set_style_text_color(pk_hint, cur ? C_GREEN : C_MUT, 0);
    snprintf(b, sizeof b, cur ? "DONE" : "USE %c", d->letter);
    lv_label_set_text(lv_obj_get_child(pk_use, 0), b);
}
static void pk_prev(lv_event_t *e) { (void)e; pk_i = (pk_i + ui_ride_design_count() - 1) % ui_ride_design_count(); picker_draw(); }
static void pk_next(lv_event_t *e) { (void)e; pk_i = (pk_i + 1) % ui_ride_design_count(); picker_draw(); }
static void pk_gesture(lv_event_t *e)
{
    (void)e;
    lv_dir_t d = lv_indev_get_gesture_dir(lv_indev_active());
    if (d == LV_DIR_LEFT) pk_next(NULL); else if (d == LV_DIR_RIGHT) pk_prev(NULL);
}
static void pk_use_cb(lv_event_t *e)
{
    (void)e;
    app_profile()->ride_style = (uint8_t)pk_i;
    app_profile_save();
    ui_display_show();
}

void ui_style_picker_show(void)
{
    pk_i = app_profile()->ride_style;
    lv_obj_t *scr = ui_screen_new(UI_SCR_SETTINGS, NULL);
    ui_title(scr, "RIDE SCREEN");
    pk_img = lv_image_create(scr);
    lv_obj_set_size(pk_img, 100, 100);
    lv_obj_align(pk_img, LV_ALIGN_TOP_MID, 0, 50);
    lv_obj_add_flag(pk_img, LV_OBJ_FLAG_GESTURE_BUBBLE);
    lv_obj_t *ring = lv_obj_create(scr);   /* thin bezel around the preview */
    lv_obj_remove_style_all(ring);
    lv_obj_set_size(ring, 104, 104); lv_obj_align(ring, LV_ALIGN_TOP_MID, 0, 48);
    lv_obj_set_style_radius(ring, LV_RADIUS_CIRCLE, 0); lv_obj_set_style_border_width(ring, 2, 0); lv_obj_set_style_border_color(ring, C_FAINT, 0);
    lv_obj_remove_flag(ring, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_t *l = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 40, pk_prev, NULL); lv_obj_align(l, LV_ALIGN_TOP_LEFT, 18, 80);
    lv_obj_t *r = ui_round_btn(scr, LV_SYMBOL_RIGHT, C_PANEL, C_FG, 40, pk_next, NULL); lv_obj_align(r, LV_ALIGN_TOP_RIGHT, -18, 80);
    pk_name = ui_label(scr, &bc_bold16, C_FG, ""); lv_obj_align(pk_name, LV_ALIGN_TOP_MID, 0, 156);
    pk_hint = ui_label(scr, &lv_font_montserrat_12, C_MUT, ""); lv_obj_align(pk_hint, LV_ALIGN_TOP_MID, 0, 176);
    pk_use = ui_pill(scr, "", C_CYAN, C_INK, 100, 32, pk_use_cb, NULL); lv_obj_align(pk_use, LV_ALIGN_TOP_MID, 0, 194);
    lv_obj_add_event_cb(scr, pk_gesture, LV_EVENT_GESTURE, NULL);
    picker_draw();
    ui_screen_show(scr);
}

/* ---------------- Sensor Test: one page to prove the meter end to end */
static lv_obj_t *st_src, *st_src_l, *st_state, *st_w, *st_wu, *st_rpm, *st_l1, *st_l2;
static bool st_from_diag;

static void age_text(char *b, size_t cap, uint32_t ms)
{
    if (ms == UINT32_MAX) snprintf(b, cap, "never");
    else if (ms < 60000) snprintf(b, cap, "%lu.%lu s ago", (unsigned long)(ms / 1000), (unsigned long)(ms % 1000 / 100));
    else snprintf(b, cap, "%lu min ago", (unsigned long)(ms / 60000));
}

static void st_update(void)
{
    app_live_t lv; app_live(&lv);
    const plat_link_info_t *l = &lv.link[PLAT_SENS_POWER];
    lv_label_set_text(st_src_l, lv.demo ? "SIMULATED" : "REAL SENSOR");
    lv_obj_set_style_bg_color(st_src, lv.demo ? C_DEMO : C_GREEN, 0);
    char b[64];
    char rs0[16] = ""; if (l->rssi && l->link == PLAT_LINK_CONNECTED) snprintf(rs0, sizeof rs0, "  %d dBm", l->rssi);
    if (lv.demo) snprintf(b, sizeof b, "%s", ui_link_text(l->link)); else snprintf(b, sizeof b, "%s%s", ui_stage_word(l), rs0);   /* 0.7.2: the real stage */
    lv_label_set_text(st_state, b);
    lv_obj_set_style_text_color(st_state, lv.demo ? ui_link_color(l->link) : l->stage == 6 ? C_GREEN : l->stage == 8 || l->unreadable ? C_RED : C_AMBER, 0);
    if (lv.power_ok) { snprintf(b, sizeof b, "%d", lv.watts); lv_label_set_text(st_w, b); lv_obj_set_style_text_color(st_w, C_FG, 0); lv_label_set_text(st_wu, "WATTS"); lv_obj_set_style_text_color(st_wu, C_MUT, 0); }
    else { lv_label_set_text(st_w, "--"); lv_obj_set_style_text_color(st_w, C_MUT, 0); lv_label_set_text(st_wu, "NO DATA"); lv_obj_set_style_text_color(st_wu, C_AMBER, 0); }
    if (lv.cad_ok) snprintf(b, sizeof b, "%d rpm%s", lv.rpm, lv.backwards ? " (back)" : ""); else snprintf(b, sizeof b, "-- rpm");
    lv_label_set_text(st_rpm, b);
    lv_obj_set_style_text_color(st_rpm, lv.cad_ok ? C_VIOLET : C_MUT, 0);
    char age[24]; age_text(age, sizeof age, l->valid_age_ms);
    snprintf(b, sizeof b, "last valid %s", age);
    lv_label_set_text(st_l1, b);
    snprintf(b, sizeof b, "reconnects %lu  gaps %lu", (unsigned long)l->reconnects, (unsigned long)l->gaps);
    lv_label_set_text(st_l2, b);
}

static void st_back(lv_event_t *e) { (void)e; if (st_from_diag) ui_diag_menu_show(); else ui_conn_detail_show(2); }

void ui_sensor_test_show(bool from_diag)
{
    st_from_diag = from_diag;
    lv_obj_t *scr = ui_screen_new(UI_SCR_SENSORS, st_update);
    ui_title(scr, "SENSOR TEST");
    st_src = lv_obj_create(scr); lv_obj_remove_style_all(st_src);
    lv_obj_set_size(st_src, LV_SIZE_CONTENT, 20); lv_obj_set_style_pad_hor(st_src, 10, 0); lv_obj_set_style_radius(st_src, 10, 0);
    lv_obj_set_style_bg_opa(st_src, LV_OPA_COVER, 0); lv_obj_align(st_src, LV_ALIGN_TOP_MID, 0, 52); lv_obj_remove_flag(st_src, LV_OBJ_FLAG_CLICKABLE);
    st_src_l = ui_label(st_src, &lv_font_montserrat_12, C_INK, ""); lv_obj_center(st_src_l);
    st_state = ui_label(scr, &lv_font_montserrat_14, C_MUT, ""); lv_obj_align(st_state, LV_ALIGN_TOP_MID, 0, 74);
    st_w = ui_label(scr, &bc_num60, C_FG, ""); lv_obj_align(st_w, LV_ALIGN_TOP_MID, 0, 90);
    st_wu = ui_label(scr, &lv_font_montserrat_12, C_MUT, ""); lv_obj_align(st_wu, LV_ALIGN_TOP_MID, 0, 146);
    st_rpm = ui_label(scr, &bc_bold22, C_VIOLET, ""); lv_obj_align(st_rpm, LV_ALIGN_TOP_MID, 0, 160);
    st_l1 = ui_label(scr, &lv_font_montserrat_12, C_FG, ""); lv_obj_align(st_l1, LV_ALIGN_TOP_MID, 0, 186);
    st_l2 = ui_label(scr, &lv_font_montserrat_12, C_MUT, ""); lv_obj_align(st_l2, LV_ALIGN_TOP_MID, 0, 202);
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 36, st_back, NULL);
    lv_obj_align(bk, LV_ALIGN_TOP_LEFT, 16, 102);
    ui_screen_show(scr);
}

/* ---------------- Device Health */
static lv_obj_t *h_txt, *h_note;

static void dur(char *b, size_t cap, uint32_t s) { snprintf(b, cap, "%luh %02lum %02lus", (unsigned long)(s / 3600), (unsigned long)(s / 60 % 60), (unsigned long)(s % 60)); }

static size_t health_text(char *b, size_t cap, bool markup)
{
    plat_health_t h; plat_health(&h);
    app_live_t lv; app_live(&lv);
    bc_profile_t *p = app_profile();
    const char *K = markup ? "#8494a0 " : "", *E = markup ? "#" : "";
    char up[24]; dur(up, sizeof up, h.uptime_s);
    const plat_link_info_t *pw = &lv.link[PLAT_SENS_POWER], *hr = &lv.link[PLAT_SENS_HR];
    plat_wifi_status_t ws; plat_wifi_status(&ws);
    char wifi_line[64];
    if (ws.state == PLAT_WIFI_OFF) snprintf(wifi_line, sizeof wifi_line, "off");
    else if (ws.state == PLAT_WIFI_CONNECTED) snprintf(wifi_line, sizeof wifi_line, "%.20s %d dBm %s", ws.ssid, ws.rssi, ws.ip);
    else snprintf(wifi_line, sizeof wifi_line, "on, not connected");
    const app_power_t *P = app_power();
    char dr[3][12], hl[32];
    for (int i = 0; i < 3; i++) { if (P->rate_mv_h[i] >= 0) snprintf(dr[i], sizeof dr[i], "%d", P->rate_mv_h[i]); else snprintf(dr[i], sizeof dr[i], "n/a"); }
    if (P->usb_likely) snprintf(hl, sizeof hl, "n/a on USB");
    else if (P->hours_left_x10 >= 0 && P->hours_left_x10 < 999) snprintf(hl, sizeof hl, "about %d.%d h (estimate)", P->hours_left_x10 / 10, P->hours_left_x10 % 10);
    else snprintf(hl, sizeof hl, "after 20 min of data");
    plat_phone_status_t ph; plat_phone_status(&ph);
    static const char *DISC[] = { "-", "phone ended", "board ended", "timeout", "KEYS MISSING", "AUTH FAILED", "not established", "other" };
    char link_line[96];
    snprintf(link_line, sizeof link_line, "%s, %u phone%s, id gen %u\n  last end %s (0x%x), enc fails %u, sync %s",
             ph.state == PLAT_PHONE_UNAVAILABLE ? "NO BLUETOOTH" : !p->phone_on ? "off" : ph.state == PLAT_PHONE_READY ? "connected" : ph.state == PLAT_PHONE_REPAIR ? "REPAIR NEEDED" : ph.state == PLAT_PHONE_ADVERTISING ? "searching" : "connecting",
             ph.bonds, ph.bonds == 1 ? "" : "s", ph.id_gen, DISC[ph.last_disc > 7 ? 7 : ph.last_disc], ph.last_disc_code, ph.enc_fails,
             (const char *[]){"device only", "synced", "pending", "FAILED"}[app_psvc_sync_state() & 3]);
    /* 0.7.4: crash-dump partition state (Crash partition missing / empty / dump stored) */
    char crash_line[48]; uint32_t cdb = 0; bc_crashpart_t cp = plat_crash_partition(&cdb);
    if (cp == BC_CRASHPART_DUMP) snprintf(crash_line, sizeof crash_line, "%s (%lu B)", bc_crashpart_name(cp), (unsigned long)cdb);
    else snprintf(crash_line, sizeof crash_line, "%s", bc_crashpart_name(cp));
    /* 0.7.2: the sensor lines first (automatic diagnosis, refreshed every 250 ms): "POWER  live 142 W" */
    char sens[320]; ui_conn_health_lines(sens, sizeof sens, markup);
    int n = snprintf(b, cap,
        "%s%sFirmware%s %s\n%sBuild%s %s\n%sUptime%s %s\n%sLast restart%s %s\n%sBoots%s %lu\n%sCrashes%s %lu total, %lu in a row\n"
        "%sSafe mode%s %lu times\n%sStorage errors%s %lu\n%sSettings save errors%s %lu\n"
        "%sRAM free%s %ldK (min %ldK)\n%sPSRAM free%s %ldK of %ldK\n%sFlash%s %ldK, app slot %ldK\n%sStorage%s %s, %ldK free of %ldK\n%sCrash record%s %s\n"
        "%sBattery%s %d mV, ~%d%% (estimate)%s\n%sPower source%s %s\n%sCharging%s not detectable (no STAT/VBUS line);\n  alerts unavailable, HW-1 open\n%sDrain%s idle %s, ride %s, ride dark %s mV/h\n%sHours left%s %s\n%sScreen%s %lu offs, %lu wakes, %lu auto\n%sTouch gate%s %s, %lu reports\n%sPower state%s %s, %lu standbys\n%sBluetooth%s %s%s, %lu seen\n%sPhone link%s %s\n%sPower meter%s %s %s\n%sHR strap%s %s %s\n%sSpeed/cad.%s %s %s\n%sWi-Fi%s %s\n"
        "%sMeter gaps / bad%s %lu / %lu\n%sDisplay%s %s\n%sTouch%s %s\n%sIMU%s %s\n%sDemo mode%s %s",
        sens, K, E, h.fw_version, K, E, h.build, K, E, up, K, E, h.reset_reason, K, E, (unsigned long)h.boot_count,
        K, E, (unsigned long)h.crash_total, (unsigned long)h.crash_consecutive, K, E, (unsigned long)h.safe_mode_entries,
        K, E, (unsigned long)h.storage_errors, K, E, (unsigned long)h.profile_save_errors,
        K, E, h.heap_free_k, h.heap_min_k, K, E, h.psram_free_k, h.psram_total_k, K, E, h.flash_total_k, h.app_slot_k,
        K, E, bc_stor_name(plat_storage_state()), h.storage_free_k, h.storage_total_k, K, E, crash_line,
        K, E, h.battery_mv, h.battery_pct, "", K, E, P->usb_likely ? "USB power likely (inferred)" : "battery", K, E,
        K, E, dr[0], dr[1], dr[2], K, E, hl, K, E, (unsigned long)P->screen_offs, (unsigned long)P->wakes, (unsigned long)P->auto_offs,
        K, E, app_power_gate_text(), (unsigned long)P->touch_reports,
        K, E, app_power_state_text(), (unsigned long)P->standbys,
        K, E, h.ble_ready ? "ready" : "NOT READY",
        h.ble_scanning ? ", scanning" : "", (unsigned long)h.ble_devices_seen,
        K, E, link_line,
        K, E, p->power.paired ? p->power.name : "not paired", p->power.paired ? ui_stage_word(pw) : "",
        K, E, p->hr.paired ? p->hr.name : "not paired", p->hr.paired ? ui_stage_word(hr) : "",
        K, E, p->csc.paired ? p->csc.name : "not paired", p->csc.paired ? ui_stage_word(&lv.link[PLAT_SENS_CSC]) : "",
        K, E, wifi_line,
        K, E, (unsigned long)pw->gaps, (unsigned long)pw->rejected,
        K, E, h.display_ok ? "OK" : "FAIL", K, E, h.touch_ok ? "OK" : "FAIL", K, E, h.imu_ok ? "OK" : "not found",
        K, E, app_demo() ? "ON" : "off");
    if (n > 0 && (size_t)n < cap) {      /* 0.7.4: boot records (NVS): Bluetooth start step by step, previous crash */
        char br[700]; plat_bootrec_text(br, sizeof br);
        if (br[0]) n += snprintf(b + n, cap - (size_t)n, "\n%sBoot records%s (newest first)\n%s", K, E, br);
    }
    return n > 0 && (size_t)n < cap ? (size_t)n : cap - 1;
}

static void health_update(void)
{
    static char *b;                              /* 0.7.4: 3.4 KB from PSRAM once (was a 2 KB static in internal RAM) */
    if (!b) b = plat_alloc_ext(3400);
    if (!b) return;
    health_text(b, 3400, true); lv_label_set_text(h_txt, b);
}

static void strip_markup(char *s)
{
    char *o = s;
    for (char *i = s; *i;) {
        if (*i == '#' && i[1] && strchr("0123456789abcdefABCDEF", i[1]) && strlen(i) > 7 && i[7] == ' ') { i += 8; continue; }
        if (*i == '#') { i++; continue; }
        *o++ = *i++;
    }
    *o = 0;
}

static void export_cb(lv_event_t *e)
{
    (void)e;
    static char rep[3400];
    size_t n = health_text(rep, 1900, false);
    char st[520]; plat_selftest_text(st, sizeof st); strip_markup(st);
    app_live_t lv; app_live(&lv);
    bc_ride_summary_t r[3]; int nr = app_history(r, 3, false);
    n += (size_t)snprintf(rep + n, sizeof rep - n, "\n--- self-test\n%s\n--- live\npower %s %d W, cadence %s %d rpm, hr %s\nsource %s\n--- rides: %d shown (newest first)\n",
                          st, lv.power_ok ? "ok" : "NO DATA", lv.power_ok ? lv.watts : 0, lv.cad_ok ? "ok" : "NO DATA", lv.cad_ok ? lv.rpm : 0,
                          lv.hr_ok ? "ok" : "none", lv.demo ? "SIMULATED (demo)" : "real sensors", nr);
    for (int i = 0; i < nr && n < sizeof rep - 80; i++) {
        char d[16]; bc_fmt_duration(r[i].duration_s, d, sizeof d);
        n += (size_t)snprintf(rep + n, sizeof rep - n, "ride #%u %s avg %d W max %d W cad %d%s\n", r[i].id, d, r[i].avg_power, r[i].max_power,
                              r[i].avg_cad, r[i].recovered ? " (recovered)" : "");
    }
    plat_export_report(rep);
    /* 0.7.3: also a manual diagnostic report (kind 3) for Cyclift (Link 1.2.3); announced to a connected phone at once */
    uint32_t id = app_diag_store_report(BC_DIAG_KIND_MANUAL, "Device Health: SEND LOG");
    /* 0.7.4: 0.7.3 said "saved on the device" even when nothing could be saved */
    static char note[64]; app_diag_status_t ds; app_diag_status(&ds);
    if (id) snprintf(note, sizeof note, "Sent to the PC log, saved,\nand ready for Cyclift.");
    else snprintf(note, sizeof note, "Sent to the PC log.\nNot saved: %s", bc_stor_name((bc_stor_state_t)ds.last_fail));
    lv_label_set_text(h_note, note);
}

static void back_diag(lv_event_t *e) { (void)e; ui_diag_menu_show(); }

void ui_health_show(void)
{
    lv_obj_t *scr = ui_screen_new(UI_SCR_DIAG, health_update);
    ui_title(scr, "DEVICE HEALTH");
    lv_obj_t *l = ui_scroll_area(scr, 50, 178);
    h_txt = ui_label(l, &lv_font_montserrat_12, C_FG, "");
    lv_obj_set_width(h_txt, lv_pct(100));
    lv_label_set_long_mode(h_txt, LV_LABEL_LONG_WRAP);
    lv_obj_set_style_text_align(h_txt, LV_TEXT_ALIGN_LEFT, 0);
    lv_label_set_recolor(h_txt, true);
    ui_pill(l, "SEND LOG TO PC", C_CYAN, C_INK, 160, 34, export_cb, NULL);
    h_note = ui_label(l, &lv_font_montserrat_12, C_MUT, "Start READ-LOG on the PC first, then tap SEND.");
    lv_obj_set_width(h_note, lv_pct(100)); lv_label_set_long_mode(h_note, LV_LABEL_LONG_WRAP);
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 44, back_diag, NULL);
    lv_obj_align(bk, LV_ALIGN_TOP_MID, 0, 182);
    ui_screen_show(scr);
}

/* ---------------- Diagnostics menu */
static void m_health(lv_event_t *e) { (void)e; ui_health_show(); }
static void m_sensor(lv_event_t *e) { (void)e; ui_sensor_test_show(true); }
static void m_self(lv_event_t *e) { (void)e; ui_diag_show(); }
/* 0.7.3: a SAFE way to create a diagnostic report for Cyclift (kind 3 "manual") without a crash — the recovery screen's
   SEND LOGS only appears after crashes. Held 1 s so a stray touch never makes one. */
static void m_save_report(lv_event_t *e)
{
    (void)e;
    uint32_t id = app_diag_store_report(BC_DIAG_KIND_MANUAL, "saved by the rider (Diagnostics > SAVE REPORT)");
    char t[48];
    app_diag_status_t st; app_diag_status(&st);   /* 0.7.4: the real reason, never a guessed "storage full" */
    if (id) snprintf(t, sizeof t, "Report %lu saved", (unsigned long)id); else snprintf(t, sizeof t, "Not saved: %s", bc_stor_short((bc_stor_state_t)st.last_fail));
    ui_toast(t);
}

void ui_diag_menu_show(void)
{
    lv_obj_t *scr = ui_screen_new(UI_SCR_DIAG, NULL);
    ui_title(scr, "DIAGNOSTICS");
    lv_obj_t *l = ui_scroll_area(scr, 50, 186);
    ui_row_btn(l, "Device Health", LV_SYMBOL_RIGHT, C_CYAN, m_health, NULL);
    ui_row_btn(l, "Sensor Test", LV_SYMBOL_RIGHT, C_CYAN, m_sensor, NULL);
    ui_row_btn(l, "Self-test", LV_SYMBOL_RIGHT, C_CYAN, m_self, NULL);
    ui_hold_btn(l, "HOLD: SAVE REPORT", C_PANEL, C_CYAN, lv_pct(100), 40, 1000, m_save_report, NULL);
    lv_obj_t *n = ui_label(l, &lv_font_montserrat_12, C_MUT, "For Cyclift: it fetches the report by itself.");
    lv_obj_set_width(n, lv_pct(100)); lv_label_set_long_mode(n, LV_LABEL_LONG_WRAP);
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 44, back_settings, NULL);
    lv_obj_align(bk, LV_ALIGN_TOP_MID, 0, 188);
    lv_obj_set_size(bk, 36, 36);
    ui_screen_show(scr);
}
