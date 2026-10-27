/*
 * RECOVERY MODE screen (firmware 0.7.3, replaces the 0.6.x SAFE MODE text screen). Shown after 3 crash resets in a row or 3
 * crashed staged boots. Only display + touch + NVS + storage run (no Bluetooth, no Wi-Fi, no sensors), so it works even when
 * Bluetooth or a sensor is what crashes.
 *
 *   RECOVERY MODE / Crash detected / "panic - nimble_host"
 *   [ RESTART & DIAGNOSE ]  hold 1 s: the next start is a STAGED boot (one subsystem at a time; the one that crashes is
 *                           disabled instead of looping; bc_boot.h)
 *   [ SEND LOGS ]           stores a manual report and starts ONLY the phone link so Cyclift can pull the reports
 *   status line             "Logs saved" / "Waiting for Cyclift" / "Sent to Cyclift"
 *                           0.7.4: "Not saved: dir corrupted" (the measured category, bc_storage.h; <= 24 characters at
 *                           this height of the round screen) instead of "Logs NOT saved (storage)"; "No BT - logs kept here"
 * Never erases rides, profile, bonds or logs. Not built with ui_screen_new (that timer runs the app and the power manager,
 * which do not run in recovery mode); this screen has its own 100 ms timer.
 */
#include "ui.h"
#include "app_diag.h"
#include <stdio.h>
#include <string.h>

static lv_obj_t *r_status, *r_send, *r_scr;
static lv_timer_t *r_timer;
static bool r_send_pressed, r_phone_started;
static uint32_t r_sent_at_press;

static void restart_cb(lv_event_t *e)
{
    (void)e;
    app_diag_event(BC_EV_MODE, 1, 0, 0, 0, 0);
    app_diag_flush(true);
    bc_boot_request_staged(plat_boot_rtc());
    lv_label_set_text(r_status, "Restarting...");
    plat_restart();
}

static void send_cb(lv_event_t *e)
{
    (void)e;
    if (r_send_pressed) return;
    r_send_pressed = true;
    app_diag_event(BC_EV_MODE, 2, 0, 0, 0, 0);
    app_diag_status_t st; app_diag_status(&st); r_sent_at_press = (uint32_t)st.sent;
    app_diag_store_report(BC_DIAG_KIND_MANUAL, "recovery screen: SEND LOGS");
    plat_phone_only_start();                         /* the phone link only: no sensor central, no Wi-Fi */
    r_phone_started = true;
}

static void recovery_tick(lv_timer_t *t)
{
    (void)t;
    if (!r_status) return;
    uint32_t now = plat_ms();
    if (r_phone_started) app_diag_recovery_pump(now);
    app_diag_tick(now);
    app_diag_status_t st; app_diag_status(&st);
    const char *txt; lv_color_t c; static char why[40];
    if (r_send_pressed && plat_bt_unavailable(NULL, 0)) { txt = "No BT - logs kept here"; c = C_RED; }
    else if (r_send_pressed && (uint32_t)st.sent > r_sent_at_press) { txt = "Sent to Cyclift"; c = C_GREEN; }
    else if (r_send_pressed) { txt = st.phone_ready ? "Sending to Cyclift..." : "Waiting for Cyclift"; c = C_AMBER; }
    else if (!st.storage_ok) { snprintf(why, sizeof why, "Not saved: %s", bc_stor_short((bc_stor_state_t)st.storage_state)); txt = why; c = C_RED; }
    else if (st.crash_report || st.stored) { txt = "Logs saved"; c = C_GREEN; }
    else { txt = "No crash log stored"; c = C_MUT; }
    if (strcmp(lv_label_get_text(r_status), txt)) lv_label_set_text(r_status, txt);
    lv_obj_set_style_text_color(r_status, c, 0);
    if (r_send_pressed) lv_obj_add_state(r_send, LV_STATE_DISABLED);
}

static void scr_deleted(lv_event_t *e)
{
    if (lv_event_get_target(e) != r_scr) return;    /* the screen is gone (only in the PC harness: the device restarts) */
    r_scr = NULL;
    if (r_timer) { lv_timer_delete(r_timer); r_timer = NULL; }
    r_status = r_send = NULL;
}

/* rc3 (QA QF-25): the recovery screen itself crashed on the previous start - a static text only: no touch, no timer, no
   Bluetooth, nothing that can crash the same way again. The boot record and crash report were already written. */
void ui_recovery_minimal_show(void)
{
    lv_obj_t *scr = lv_obj_create(NULL);
    lv_obj_set_style_bg_color(scr, C_BG, 0); lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, 0);
    lv_obj_remove_flag(scr, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_t *t = ui_label(scr, &bc_bold16, C_AMBER, "RECOVERY (MINIMAL)");
    lv_obj_align(t, LV_ALIGN_TOP_MID, 0, 50);
    lv_obj_t *m = ui_label(scr, &lv_font_montserrat_14, C_FG, "The recovery screen\ncrashed. Settings and\nrides are untouched.\nUnplug, then tell Claude:\nrun READ-BOARD-STATE.");
    lv_obj_set_style_text_align(m, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(m, LV_ALIGN_TOP_MID, 0, 80);
    lv_obj_t *old = lv_screen_active();
    lv_screen_load(scr);
    if (old && old != scr) lv_obj_delete_async(old);
}

void ui_recovery_show(void)
{
    lv_obj_t *scr = lv_obj_create(NULL);
    lv_obj_set_style_bg_color(scr, C_BG, 0); lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, 0);
    lv_obj_set_style_text_color(scr, C_FG, 0); lv_obj_set_style_pad_all(scr, 0, 0);
    lv_obj_remove_flag(scr, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_add_event_cb(scr, scr_deleted, LV_EVENT_DELETE, NULL); r_scr = scr;
    lv_obj_t *t = ui_label(scr, &bc_bold16, C_AMBER, "RECOVERY MODE");
    lv_obj_align(t, LV_ALIGN_TOP_MID, 0, 36);
    app_diag_status_t st; app_diag_status(&st);
    lv_obj_t *c = ui_label(scr, &lv_font_montserrat_14, C_FG, st.crashed ? "Crash detected" : "Restarted in recovery");
    lv_obj_align(c, LV_ALIGN_TOP_MID, 0, 60);
    char sum[56];
    if (st.summary[0]) { snprintf(sum, sizeof sum, "%s", st.summary); char *in = strstr(sum, " in "); if (in) { memmove(in + 3, in + 4, strlen(in + 4) + 1); in[0] = ' '; in[1] = '-'; in[2] = ' '; } }
    else snprintf(sum, sizeof sum, "3 restarts in a row");
    lv_obj_t *s = ui_label(scr, &lv_font_montserrat_12, C_MUT, sum);
    lv_obj_set_width(s, 2 * ui_chord(84) - 24); lv_label_set_long_mode(s, LV_LABEL_LONG_MODE_DOTS); lv_obj_set_style_text_align(s, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(s, LV_ALIGN_TOP_MID, 0, 82);
    lv_obj_t *r = ui_hold_btn(scr, "RESTART & DIAGNOSE", C_CYAN, C_INK, 204, 44, 1000, restart_cb, NULL);   /* hold 1 s: never by accident */
    lv_obj_set_style_text_font(ui_hold_label(r), &bc_bold16, 0);
    lv_obj_align(r, LV_ALIGN_TOP_MID, 0, 104);
    r_send = ui_pill(scr, "SEND LOGS", C_PANEL, C_CYAN, 128, 34, send_cb, NULL);
    lv_obj_align(r_send, LV_ALIGN_TOP_MID, 0, 156);
    r_status = ui_label(scr, &lv_font_montserrat_12, C_MUT, "");
    lv_obj_set_width(r_status, 2 * ui_chord(204) - 16); lv_label_set_long_mode(r_status, LV_LABEL_LONG_MODE_DOTS); lv_obj_set_style_text_align(r_status, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(r_status, LV_ALIGN_TOP_MID, 0, 196);
    r_send_pressed = r_phone_started = false;
    lv_obj_t *old = lv_screen_active();
    lv_screen_load(scr);
    if (old && old != scr) lv_obj_delete_async(old);
    if (!r_timer) r_timer = lv_timer_create(recovery_tick, 100, NULL);
    recovery_tick(NULL);
}
