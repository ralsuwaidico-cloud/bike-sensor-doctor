/*
 * Phone link: Settings > Phone (status, battery, HR source preference, forget / off) and the pairing-code pop-up that
 * appears on ANY screen while a phone is pairing. The phone is optional: everything else works without it.
 */
#include "ui.h"
#include <stdio.h>
#include <string.h>

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

/* ---------------- Settings > Phone */
static lv_obj_t *ph_txt, *ph_toggle, *ph_pref, *ph_forget;

static const char *state_text(plat_phone_state_t s)
{
    switch (s) {
    case PLAT_PHONE_OFF: return "OFF";
    case PLAT_PHONE_ADVERTISING: return "WAITING FOR PHONE";
    case PLAT_PHONE_CONNECTED: return "CONNECTED (not paired)";
    case PLAT_PHONE_PAIRING: return "PAIRING";
    case PLAT_PHONE_READY: return "CONNECTED";
    default: return "?";
    }
}
static lv_color_t state_color(plat_phone_state_t s) { return s == PLAT_PHONE_READY ? C_GREEN : s == PLAT_PHONE_OFF ? C_MUT : C_AMBER; }

static void phone_update(void)
{
    plat_phone_status_t ps; plat_phone_status(&ps);
    app_live_t lv; app_live(&lv);
    bc_profile_t *p = app_profile();
    char b[400], sig[20] = "", bat[40] = "", rx[40], gps[48], hr[48];
    if (ps.rssi) snprintf(sig, sizeof sig, "  %d dBm", ps.rssi);
    if (ps.phone_batt != 0xFF) snprintf(bat, sizeof bat, "\n#8494a0 PHONE BATTERY# %u%%%s", ps.phone_batt, ps.watch_batt != 0xFF ? "" : "");
    if (ps.watch_batt != 0xFF) { size_t n = strlen(bat); snprintf(bat + n, sizeof bat - n, "  #8494a0 WATCH# %u%%", ps.watch_batt); }
    if (ps.last_rx_age_ms == UINT32_MAX) snprintf(rx, sizeof rx, "no data received yet");
    else snprintf(rx, sizeof rx, "last data %lu s ago", (unsigned long)(ps.last_rx_age_ms / 1000));
    const plat_link_info_t *sp = &lv.link[PLAT_SENS_SPEED];
    if (lv.speed_ok) snprintf(gps, sizeof gps, "#56e08c %s# %d.%d km/h", bc_src_name(lv.speed_src), lv.speed_dmh / 10, lv.speed_dmh % 10);
    else snprintf(gps, sizeof gps, "#%06x %s#", ui_hex(ui_link_color(sp->link)), sp->link == PLAT_LINK_NOT_PAIRED ? "none" : ui_link_text(sp->link));
    if (lv.phone_hr) snprintf(hr, sizeof hr, "#56e08c %s# %d bpm%s", bc_src_name(lv.hr_ok ? (lv.hr_src == BC_SRC_BLE_STRAP ? BC_SRC_PHONE_STRAP : lv.hr_src) : BC_SRC_PHONE_STRAP), lv.hr_ok && lv.hr_src != BC_SRC_BLE_STRAP ? lv.bpm : 0, lv.hr_ok && lv.hr_src == BC_SRC_BLE_STRAP ? " (backup)" : "");
    else snprintf(hr, sizeof hr, "#8494a0 none#");
    char sync[64];
    if (p->prof_src) snprintf(sync, sizeof sync, "#8494a0 PROFILE# phone v%lu (shared settings)", (unsigned long)p->phone_prof_ver);
    else snprintf(sync, sizeof sync, "#8494a0 PROFILE# this device only");
    snprintf(b, sizeof b, "#%06x %s#%s\n%s%s\n#8494a0 GPS# %s\n#8494a0 HR VIA PHONE# %s\n%s\n%s",
             ui_hex(state_color(ps.state)), state_text(ps.state), sig, rx, bat, gps, hr, sync,
             ps.bonded ? "a phone is remembered" : "no phone remembered yet:\npair from the BikeComputer app");
    lv_label_set_text(ph_txt, b);
    lv_label_set_text(lv_obj_get_child(ph_toggle, 0), p->phone_on ? "PHONE LINK: ON" : "PHONE LINK: OFF");
    lv_label_set_text(lv_obj_get_child(ph_pref, 0), p->hr_pref ? "HR: WATCH FIRST" : "HR: STRAP FIRST");
    if (ps.bonded) lv_obj_remove_flag(ph_forget, LV_OBJ_FLAG_HIDDEN); else lv_obj_add_flag(ph_forget, LV_OBJ_FLAG_HIDDEN);
}

static void toggle_cb(lv_event_t *e) { (void)e; bc_profile_t *p = app_profile(); p->phone_on = !p->phone_on; app_profile_save(); plat_phone_set_enabled(p->phone_on); }
static void pref_cb(lv_event_t *e) { (void)e; bc_profile_t *p = app_profile(); p->hr_pref = p->hr_pref ? 0 : 1; app_profile_save(); }
static void forget_cb(lv_event_t *e) { (void)e; plat_phone_forget(); }
static void back_cb(lv_event_t *e) { (void)e; ui_return(); }
static void reconnect_cb(lv_event_t *e) { (void)e; bc_profile_t *p = app_profile(); if (!p->phone_on) { p->phone_on = true; app_profile_save(); } plat_phone_set_enabled(false); plat_phone_set_enabled(true); }

void ui_phone_show(void)
{
    lv_obj_t *scr = ui_screen_new(UI_SCR_SETTINGS, phone_update);
    ui_title(scr, "PHONE");
    lv_obj_t *l = ui_scroll_area(scr, 50, 178);
    ph_txt = ui_label(l, &lv_font_montserrat_12, C_FG, "");
    lv_obj_set_width(ph_txt, lv_pct(100)); lv_label_set_long_mode(ph_txt, LV_LABEL_LONG_WRAP); lv_label_set_recolor(ph_txt, true);
    ph_toggle = ui_pill(l, "", C_PANEL, C_CYAN, 160, 32, toggle_cb, NULL);
    lv_obj_set_style_text_font(lv_obj_get_child(ph_toggle, 0), &lv_font_montserrat_12, 0);
    ph_pref = ui_pill(l, "", C_PANEL, C_CYAN, 160, 32, pref_cb, NULL);
    lv_obj_set_style_text_font(lv_obj_get_child(ph_pref, 0), &lv_font_montserrat_12, 0);
    lv_obj_t *hint = ui_label(l, &lv_font_montserrat_12, C_MUT, "the other source is the\nautomatic backup");
    (void)hint;
    { lv_obj_t *rc = ui_pill(l, "RECONNECT", C_PANEL, C_CYAN, 160, 32, reconnect_cb, NULL); lv_obj_set_style_text_font(lv_obj_get_child(rc, 0), &lv_font_montserrat_12, 0); }
    lv_obj_t *tr = ui_label(l, &lv_font_montserrat_12, C_MUT, "RELAYS: GPS speed, time, watch HR\nTROUBLE? open the BikeComputer app,\nBluetooth on, within 5 m; forget on\nboth sides and pair again if the\ncode never appears");
    lv_obj_set_width(tr, lv_pct(100)); lv_label_set_long_mode(tr, LV_LABEL_LONG_WRAP);
    ph_forget = ui_hold_btn(l, "HOLD: FORGET PHONE", C_PANEL, C_RED, 160, 34, 1500, forget_cb, NULL);
    lv_obj_set_style_text_font(lv_obj_get_child(ph_forget, 0), &lv_font_montserrat_12, 0);
    lv_obj_t *bk = ui_round_btn(scr, LV_SYMBOL_LEFT, C_PANEL, C_FG, 40, back_cb, NULL);
    lv_obj_align(bk, LV_ALIGN_TOP_MID, 0, 184);
    ui_screen_show(scr);
}
