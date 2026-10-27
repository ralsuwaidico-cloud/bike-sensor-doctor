/*
 * Phone link: Settings > Phone (status, battery, HR source preference, forget / off) and the pairing-code pop-up that
 * appears on ANY screen while a phone is pairing. The phone is optional: everything else works without it.
 */
#include "ui.h"
#include <stdio.h>
#include <string.h>
#include "app_psvc.h"
#include "app_diag.h"

/* ---------------- pairing-code pop-up (top layer, over whatever screen is showing) */
static lv_obj_t *k_box, *k_code, *k_code2;
static uint32_t k_shown;

void ui_passkey_refresh(void)
{
    uint32_t code = app_phone_passkey();
    if (!code) {
        if (k_box) { lv_obj_delete(k_box); k_box = NULL; k_shown = 0; }
        return;
    }
    if (k_box && k_shown == code) return;
    if (!k_box) {
        k_box = lv_obj_create(lv_layer_top());
        lv_obj_remove_style_all(k_box);
        lv_obj_set_size(k_box, UI_W, UI_W);
        lv_obj_set_style_bg_color(k_box, C_BG, 0);
        lv_obj_set_style_bg_opa(k_box, LV_OPA_COVER, 0);
        lv_obj_add_flag(k_box, LV_OBJ_FLAG_CLICKABLE);     /* swallows touches while pairing */
        lv_obj_remove_flag(k_box, LV_OBJ_FLAG_SCROLLABLE);
        ui_title(k_box, "PHONE PAIRING");
        lv_obj_t *t = ui_label(k_box, &lv_font_montserrat_14, C_FG, "Type this code\non your phone:");
        lv_obj_align(t, LV_ALIGN_TOP_MID, 0, 56);
        k_code = ui_label(k_box, &bc_num44, C_CYAN, ""); lv_obj_align(k_code, LV_ALIGN_TOP_MID, -46, 100);
        k_code2 = ui_label(k_box, &bc_num44, C_CYAN, ""); lv_obj_align(k_code2, LV_ALIGN_TOP_MID, 46, 100);
        lv_obj_t *h = ui_label(k_box, &lv_font_montserrat_12, C_MUT, "the phone is remembered\nafter this");
        lv_obj_align(h, LV_ALIGN_TOP_MID, 0, 160);
    }
    char b[8]; snprintf(b, sizeof b, "%03lu", (unsigned long)(code / 1000)); lv_label_set_text(k_code, b);
    snprintf(b, sizeof b, "%03lu", (unsigned long)(code % 1000)); lv_label_set_text(k_code2, b);
    k_shown = code;
}

/* ---------------- Settings > Phone (0.7.0: compact — status, ONE primary action, two rows; everything else on Details) */
static lv_obj_t *ph_status, *ph_primary, *ph_sync_row, *ph_link_row, *ph_hint;
static plat_phone_state_t ph_shown_state = (plat_phone_state_t)-1;
static bool ph_shown_on;

static const char *state_text(plat_phone_state_t s, bool link_on)
{
    if (!link_on) return "LINK OFF";
    switch (s) {
    case PLAT_PHONE_OFF: return "LINK OFF";
    case PLAT_PHONE_ADVERTISING: return "SEARCHING";
    case PLAT_PHONE_CONNECTED: return "CONNECTING";
    case PLAT_PHONE_PAIRING: return "PAIRING";
    case PLAT_PHONE_READY: return "CONNECTED";
    case PLAT_PHONE_REPAIR: return "REPAIR NEEDED";
    case PLAT_PHONE_UNAVAILABLE: return "NO BLUETOOTH";
    default: return "?";
    }
}
static lv_color_t state_color(plat_phone_state_t s, bool link_on)
{
    if (!link_on) return C_MUT;
    return s == PLAT_PHONE_READY ? C_GREEN : s == PLAT_PHONE_REPAIR || s == PLAT_PHONE_UNAVAILABLE ? C_RED : s == PLAT_PHONE_OFF ? C_MUT : C_AMBER;
}
static const char *disc_text(plat_phone_disc_t d)
{
    switch (d) {
    case PLAT_PHONE_DISC_NONE: return "-";
    case PLAT_PHONE_DISC_PHONE_ENDED: return "phone ended it";
    case PLAT_PHONE_DISC_BOARD_ENDED: return "board ended it";
    case PLAT_PHONE_DISC_TIMEOUT: return "out of range / timeout";
    case PLAT_PHONE_DISC_KEY_MISSING: return "keys missing (stale pairing)";
    case PLAT_PHONE_DISC_AUTH_FAILED: return "authentication failed";
    case PLAT_PHONE_DISC_FAILED_TO_ESTABLISH: return "failed to establish";
    default: return "other";
    }
}
static void hhmm(char *b, size_t cap, uint32_t epoch)
{
    if (!epoch) { snprintf(b, cap, "never"); return; }
    plat_phone_in_t in; plat_phone_inputs(&in);
    int32_t tz = in.time.rx_ms ? (int32_t)in.time.v.tz_min * 60 : 0;   /* local time as the phone last told us; UTC before that */
    uint32_t t = (uint32_t)((int64_t)epoch + tz); snprintf(b, cap, "%02lu:%02lu", (unsigned long)(t / 3600 % 24), (unsigned long)(t / 60 % 60));
}
static void sync_text(char *b, size_t cap, lv_color_t *c)
{
    bc_profile_t *p = app_profile();
    char when[8]; hhmm(when, sizeof when, p->prof_sync_epoch);
    switch (app_psvc_sync_state()) {
    case APP_PSYNC_SYNCED: if (p->prof_sync_epoch) snprintf(b, cap, "synced %s", when); else snprintf(b, cap, "synced v%lu", (unsigned long)p->phone_prof_ver); *c = C_GREEN; break;
    case APP_PSYNC_PENDING: snprintf(b, cap, "pending"); *c = C_AMBER; break;
    case APP_PSYNC_FAILED: snprintf(b, cap, "failed"); *c = C_RED; break;
    default: snprintf(b, cap, "device only"); *c = C_MUT; break;
    }
}

static void primary_cb(lv_event_t *e);
/* 0.7.4: Bluetooth unavailable this start. Disabled by the boot plan after crashes -> RETRY (applies at the next start);
   failed to start (e.g. no internal RAM for the controller) -> WHY? shows the reason. */
static bool bt_disabled_by_crash(void) { return (app_diag_skip() & (BC_SS_BIT(BC_SS_BTSTACK) | BC_SS_BIT(BC_SS_PHONE))) != 0; }
static void why_cb(lv_event_t *e)
{
    (void)e;
    if (bt_disabled_by_crash()) { app_diag_retry(BC_SS_BTSTACK); app_diag_retry(BC_SS_PHONE); ui_toast("Bluetooth starts again at the next restart"); return; }
    char r[56] = ""; plat_bt_unavailable(r, sizeof r); char t[72]; snprintf(t, sizeof t, "No Bluetooth: %s", r); ui_toast(t);
}
static void repair_cb(lv_event_t *e) { (void)e; plat_phone_repair(); bc_profile_t *p = app_profile(); if (!p->phone_on) { p->phone_on = true; app_profile_save(); } ui_toast("pairing reset: pair again from the app"); }
static void rebuild_primary(plat_phone_state_t st, bool on)
{
    if (ph_primary) { lv_obj_delete(ph_primary); ph_primary = NULL; }
    lv_obj_t *scr = lv_obj_get_parent(ph_status);
    if (st == PLAT_PHONE_UNAVAILABLE) ph_primary = ui_pill(scr, bt_disabled_by_crash() ? "RETRY" : "WHY?", C_PANEL, C_RED, 160, 36, why_cb, NULL);   /* 0.7.4 */
    else if (!on || st == PLAT_PHONE_OFF) ph_primary = ui_pill(scr, "CONNECT", C_CYAN, C_BG, 160, 36, primary_cb, NULL);
    else if (st == PLAT_PHONE_REPAIR) { ph_primary = ui_hold_btn(scr, "HOLD: REPAIR", C_RED, C_FG, 160, 36, 1500, repair_cb, NULL); lv_obj_set_style_text_font(ui_hold_label(ph_primary), &lv_font_montserrat_14, 0); }
    else if (st == PLAT_PHONE_ADVERTISING) ph_primary = ui_pill(scr, "TURN OFF", C_PANEL, C_FG, 160, 36, primary_cb, NULL);
    else ph_primary = ui_pill(scr, "DISCONNECT", C_PANEL, C_FG, 160, 36, primary_cb, NULL);
    lv_obj_align(ph_primary, LV_ALIGN_TOP_MID, 0, 76);
    ph_shown_state = st; ph_shown_on = on;
}

static void phone_update(void)
{
    plat_phone_status_t ps; plat_phone_status(&ps);
    bc_profile_t *p = app_profile();
    bool on = p->phone_on;
    char b[48];
    if (on && ps.state == PLAT_PHONE_READY) snprintf(b, sizeof b, "CONNECTED  iPhone%s", ps.rssi ? "" : "");
    else snprintf(b, sizeof b, "%s", state_text(ps.state, on));
    lv_label_set_text(ph_status, b); lv_obj_set_style_text_color(ph_status, state_color(ps.state, on), 0);
    if (ps.state != ph_shown_state || on != ph_shown_on) rebuild_primary(ps.state, on);
    lv_color_t c; sync_text(b, sizeof b, &c); ui_row_set_value(ph_sync_row, b, c);
    ui_row_set_value(ph_link_row, on ? "ON" : "OFF", on ? C_GREEN : C_MUT);
    lv_label_set_text(ph_hint, ps.state == PLAT_PHONE_UNAVAILABLE ? "Bluetooth off this start" : ps.state == PLAT_PHONE_REPAIR ? "keys mismatch - details" : ps.bonded ? "tap for details" : "pair from the app - details");
}

static void primary_cb(lv_event_t *e)
{
    (void)e; bc_profile_t *p = app_profile(); plat_phone_status_t ps; plat_phone_status(&ps);
    if (!p->phone_on) { p->phone_on = true; app_profile_save(); plat_phone_set_enabled(true); return; }           /* CONNECT */
    if (ps.state == PLAT_PHONE_ADVERTISING) { p->phone_on = false; app_profile_save(); plat_phone_set_enabled(false); return; }   /* TURN OFF */
    plat_phone_disconnect();                                                                                        /* DISCONNECT */
}
static void link_cb(lv_event_t *e) { (void)e; bc_profile_t *p = app_profile(); p->phone_on = !p->phone_on; app_profile_save(); plat_phone_set_enabled(p->phone_on); }
static void back_cb(lv_event_t *e) { (void)e; ui_return(); }
static void help_cb(lv_event_t *e);

void ui_phone_show(void)
{
    lv_obj_t *scr = ui_screen_new(UI_SCR_SETTINGS, phone_update);
    ui_title(scr, "PHONE");
    ph_status = ui_label(scr, &lv_font_montserrat_14, C_FG, "");
    lv_obj_set_width(ph_status, 2 * ui_chord(54) - 16); lv_label_set_long_mode(ph_status, LV_LABEL_LONG_MODE_DOTS);
    lv_obj_set_style_text_align(ph_status, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(ph_status, LV_ALIGN_TOP_MID, 0, 54);
    lv_obj_add_flag(ph_status, LV_OBJ_FLAG_CLICKABLE); lv_obj_add_event_cb(ph_status, help_cb, LV_EVENT_CLICKED, NULL);
    ph_primary = NULL; ph_shown_state = (plat_phone_state_t)-1;
    lv_obj_t *l = ui_scroll_area(scr, 114, 172);
    lv_obj_remove_flag(l, LV_OBJ_FLAG_SCROLLABLE);
    lv_obj_set_style_pad_row(l, 2, 0); lv_obj_set_style_pad_ver(l, 0, 0);
    ph_sync_row = ui_row_btn(l, "Profile sync", "", C_MUT, help_cb, NULL); lv_obj_set_height(ph_sync_row, 29);
    ph_link_row = ui_row_btn(l, "Phone link", "", C_MUT, link_cb, NULL); lv_obj_set_height(ph_link_row, 29);
    ph_hint = ui_label(scr, &lv_font_montserrat_12, C_MUT, "");
    lv_obj_set_width(ph_hint, 2 * ui_chord(188) - 24); lv_label_set_long_mode(ph_hint, LV_LABEL_LONG_MODE_DOTS);
    lv_obj_set_style_text_align(ph_hint, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(ph_hint, LV_ALIGN_TOP_MID, 0, 174);
    lv_obj_add_flag(ph_hint, LV_OBJ_FLAG_CLICKABLE); lv_obj_add_event_cb(ph_hint, help_cb, LV_EVENT_CLICKED, NULL);
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 32, back_cb, NULL);
    lv_obj_align(bk, LV_ALIGN_TOP_MID, 0, 190);
    ui_screen_show(scr);
    phone_update();
}

/* ---------------- Phone > Details (help, HR preference, forget, diagnostics) */
static lv_obj_t *hd_txt;
static void hd_update(void)
{
    plat_phone_status_t ps; plat_phone_status(&ps);
    bc_profile_t *p = app_profile();
    app_psvc_stats_t st; app_psvc_stats(&st);
    char b[900], when[8]; hhmm(when, sizeof when, p->prof_sync_epoch);
    snprintf(b, sizeof b,
             "#8494a0 STATE# %s\n#8494a0 PHONES REMEMBERED# %u\n#8494a0 LAST LINK END# %s (0x%x)\n#8494a0 ENCRYPTION FAILS# %u\n"
             "#8494a0 IDENTITY# %02X%02X..%02X gen %u\n#8494a0 PROFILE# %s v%lu, last sync %s\n#8494a0 SETTINGS# v%lu  #8494a0 RIDES SENT# %lu\n"
             "#8494a0 DATA# %lu in / %lu out / %lu bad\n\n"
             "HOW TO PAIR: open the BikeComputer app, Connections > BikeComputer > Connect; type the 6-digit code shown here.\n\n"
             "REPAIR NEEDED means the phone kept keys this board no longer has (after a forget or data reset). Hold REPAIR here, "
             "then in the iPhone: Settings > Bluetooth > BikeComputer > Forget This Device, and pair again from the app.\n\n"
             "Screen off and standby keep the link. Deep sleep switches it off until the board wakes.",
             state_text(ps.state, p->phone_on), ps.bonds, disc_text(ps.last_disc), ps.last_disc_code, ps.enc_fails,
             ps.id_addr[5], ps.id_addr[4], ps.id_addr[0], ps.id_gen, p->prof_src ? "phone" : "device only", (unsigned long)p->phone_prof_ver, when,
             (unsigned long)p->sett_ver, (unsigned long)st.rides_sent, (unsigned long)ps.rx_msgs, (unsigned long)ps.tx_msgs, (unsigned long)ps.rx_rejected);
    lv_label_set_text(hd_txt, b);
}
static void pref_cb(lv_event_t *e) { (void)e; bc_profile_t *p = app_profile(); p->hr_pref = p->hr_pref ? 0 : 1; app_profile_save(); ui_phone_show(); }
static void forget_cb(lv_event_t *e) { (void)e; plat_phone_forget(); ui_toast("phone forgotten - new identity"); ui_phone_show(); }
static void hd_back_cb(lv_event_t *e) { (void)e; ui_phone_show(); }
static void help_cb(lv_event_t *e)
{
    (void)e;
    lv_obj_t *scr = ui_screen_new(UI_SCR_SETTINGS, hd_update);
    ui_title(scr, "PHONE DETAILS");
    lv_obj_t *l = ui_scroll_area(scr, 50, 182);
    hd_txt = ui_label(l, &lv_font_montserrat_12, C_FG, "");
    lv_obj_set_width(hd_txt, lv_pct(100)); lv_label_set_long_mode(hd_txt, LV_LABEL_LONG_MODE_WRAP); lv_label_set_recolor(hd_txt, true);
    bc_profile_t *p = app_profile();
    { lv_obj_t *pr = ui_pill(l, p->hr_pref ? "HR: WATCH FIRST" : "HR: STRAP FIRST", C_PANEL, C_CYAN, 160, 32, pref_cb, NULL); lv_obj_set_style_text_font(lv_obj_get_child(pr, 0), &lv_font_montserrat_12, 0); }
    ui_note(l, "the other HR source is the automatic backup", 0);
    { lv_obj_t *fg = ui_hold_btn(l, "HOLD: FORGET PHONE", C_PANEL, C_RED, 160, 34, 1500, forget_cb, NULL); lv_obj_set_style_text_font(ui_hold_label(fg), &lv_font_montserrat_12, 0); }
    ui_note(l, "forgets every phone and gives the board a new Bluetooth identity; rides and settings are kept", 0);
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 36, hd_back_cb, NULL);
    lv_obj_align(bk, LV_ALIGN_TOP_MID, 0, 188);
    ui_screen_show(scr);
    hd_update();
}
