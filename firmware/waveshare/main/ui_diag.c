/*
 * Phase A DIAGNOSTIC screens — engineering only, not the final interface (that is designed with Rashed).
 * Swipe left/right between three pages:
 *   1  XDS LIVE   — real watts and cadence from the meter, or NO DATA (never a simulated or held value)
 *   2  SELF-TEST  — PASS/FAIL per subsystem (display, touch, PSRAM, flash, NVS, storage, IMU, battery, Wi-Fi, BLE)
 *   3  TOUCH      — every tap draws a dot with its coordinates; slider sets the backlight
 */
#include <stdio.h>
#include "lvgl.h"
#include "esp_lvgl_port.h"
#include "esp_heap_caps.h"
#include "hw.h"
#include "ble_xds.h"

int ble_xds_link_rssi(void);

#define C_BG    lv_color_hex(0x080B0E)
#define C_FG    lv_color_hex(0xEAF2F4)
#define C_MUT   lv_color_hex(0x7D8B93)
#define C_CYAN  lv_color_hex(0x34E7E4)
#define C_GREEN lv_color_hex(0x56E08C)
#define C_AMBER lv_color_hex(0xFFB64D)
#define C_RED   lv_color_hex(0xFF5A5A)

static lv_obj_t *l_state, *l_watts, *l_wunit, *l_cad, *l_info, *l_test, *l_touch, *l_heap;
static lv_obj_t *dots[12]; static int dot_i;

static lv_obj_t *label(lv_obj_t *p, const lv_font_t *f, lv_color_t c, lv_align_t a, int x, int y)
{
    lv_obj_t *l = lv_label_create(p);
    lv_obj_set_style_text_font(l, f, 0); lv_obj_set_style_text_color(l, c, 0);
    lv_obj_set_style_text_align(l, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(l, a, x, y); lv_label_set_text(l, "");
    return l;
}

static void touch_cb(lv_event_t *e)
{
    lv_indev_t *in = lv_indev_active(); if (!in) return;
    lv_point_t p; lv_indev_get_point(in, &p);
    lv_obj_t *d = dots[dot_i++ % 12];
    lv_obj_set_pos(d, p.x - 6, p.y - 6); lv_obj_remove_flag(d, LV_OBJ_FLAG_HIDDEN);
    lv_label_set_text_fmt(l_touch, "tap %d, %d", (int)p.x, (int)p.y);
    if (g_selftest.touch != HW_PASS) { g_selftest.touch = HW_PASS; snprintf(g_selftest.touch_s, sizeof g_selftest.touch_s, "CST816S taps registered"); }
}

static void bl_cb(lv_event_t *e) { hw_backlight_set(lv_slider_get_value(lv_event_get_target(e))); }

static const char *word(hw_result_t r) { return r == HW_PASS ? "#56E08C PASS#" : r == HW_FAIL ? "#FF5A5A FAIL#" : r == HW_INFO ? "#FFB64D INFO#" : "#7D8B93 ...#"; }

static void tick(lv_timer_t *t)
{
    xds_status_t s; ble_xds_snapshot(&s);
    uint32_t now = hw_millis();
    int w = 0, rpm = 0; bool back = false;
    bool pw = bc_xds_live_power(&s.live, now, &w) == BC_LIVE_OK;
    bool cd = bc_xds_live_cadence(&s.live, now, &rpm, &back) == BC_LIVE_OK;
    bool silent = s.state == XDS_SUBSCRIBED && bc_xds_link_silent(&s.live, now);

    const char *st = silent ? "LINK SILENT" : (s.state == XDS_SUBSCRIBED && !pw) ? "CONNECTED - NO DATA" : ble_xds_state_name(s.state);
    lv_color_t sc = silent ? C_RED : s.state == XDS_SUBSCRIBED ? (pw ? C_GREEN : C_AMBER) : C_AMBER;
    lv_label_set_text(l_state, st); lv_obj_set_style_text_color(l_state, sc, 0);

    if (pw) { lv_label_set_text_fmt(l_watts, "%d", w); lv_obj_set_style_text_color(l_watts, C_FG, 0); lv_label_set_text(l_wunit, "WATTS"); }
    else { lv_label_set_text(l_watts, "--"); lv_obj_set_style_text_color(l_watts, C_MUT, 0); lv_label_set_text(l_wunit, "NO DATA"); }
    if (cd) lv_label_set_text_fmt(l_cad, "%d rpm%s", rpm, back ? "  (reverse)" : "");
    else lv_label_set_text(l_cad, "-- rpm");

    if (s.state == XDS_SUBSCRIBED) ble_xds_link_rssi();
    if (s.have_mac) lv_label_set_text_fmt(l_info, "%s\npkts %u  rej %u  rssi %d", s.name[0] ? s.name : "XDS meter",
                                          (unsigned)s.live.packets, (unsigned)(s.live.rejected + s.live.short_packets), s.rssi);
    else lv_label_set_text_fmt(l_info, "pedal to wake the meter\n%u BLE devices seen", (unsigned)s.devices_seen);

    if (s.devices_seen > 0 && g_selftest.ble != HW_PASS) { g_selftest.ble = HW_PASS; snprintf(g_selftest.ble_s, sizeof g_selftest.ble_s, "scan OK, %u devices", (unsigned)s.devices_seen); }
    if (s.state == XDS_SUBSCRIBED && pw) snprintf(g_selftest.ble_s, sizeof g_selftest.ble_s, "XDS live, %u pkts", (unsigned)s.live.packets);

    float v = hw_battery_volts();
    lv_label_set_text_fmt(l_test,
        "Display  %s\nTouch    %s\nPSRAM    %s\nFlash    %s\nNVS      %s\nStorage  %s\nIMU      %s\nBattery  %s %.2fV\nWi-Fi    %s\nBLE      %s\nboot #%u",
        word(g_selftest.display), word(g_selftest.touch), word(g_selftest.psram), word(g_selftest.flash), word(g_selftest.nvs),
        word(g_selftest.storage), word(g_selftest.imu), word(g_selftest.battery), v, word(g_selftest.wifi), word(g_selftest.ble),
        (unsigned)g_selftest.boot_count);
    lv_label_set_text_fmt(l_heap, "heap %uK  psram %uK  up %us", (unsigned)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024),
                          (unsigned)(heap_caps_get_free_size(MALLOC_CAP_SPIRAM) / 1024), (unsigned)(now / 1000));
}

void ui_diag_create(void)
{
    lvgl_port_lock(0);
    lv_obj_t *scr = lv_screen_active();
    lv_obj_set_style_bg_color(scr, C_BG, 0);
    lv_obj_t *tv = lv_tileview_create(scr);
    lv_obj_set_style_bg_color(tv, C_BG, 0);
    lv_obj_set_scrollbar_mode(tv, LV_SCROLLBAR_MODE_OFF);

    /* 1 — XDS LIVE */
    lv_obj_t *t1 = lv_tileview_add_tile(tv, 0, 0, LV_DIR_RIGHT);
    label(t1, &lv_font_montserrat_14, C_CYAN, LV_ALIGN_TOP_MID, 0, 28); lv_label_set_text(lv_obj_get_child(t1, 0), "DIAGNOSTIC 1/3  XDS");
    l_state = label(t1, &lv_font_montserrat_14, C_AMBER, LV_ALIGN_TOP_MID, 0, 50);
    l_watts = label(t1, &lv_font_montserrat_48, C_FG, LV_ALIGN_CENTER, 0, -14);
    l_wunit = label(t1, &lv_font_montserrat_14, C_MUT, LV_ALIGN_CENTER, 0, 22);
    l_cad = label(t1, &lv_font_montserrat_28, C_FG, LV_ALIGN_CENTER, 0, 52);
    l_info = label(t1, &lv_font_montserrat_12, C_MUT, LV_ALIGN_BOTTOM_MID, 0, -26);

    /* 2 — SELF-TEST */
    lv_obj_t *t2 = lv_tileview_add_tile(tv, 1, 0, LV_DIR_LEFT | LV_DIR_RIGHT);
    lv_obj_t *h2 = label(t2, &lv_font_montserrat_14, C_CYAN, LV_ALIGN_TOP_MID, 0, 22); lv_label_set_text(h2, "2/3  SELF-TEST");
    l_test = label(t2, &lv_font_montserrat_14, C_FG, LV_ALIGN_CENTER, 0, 4);
    lv_label_set_recolor(l_test, true);
    lv_obj_set_style_text_align(l_test, LV_TEXT_ALIGN_LEFT, 0);
    l_heap = label(t2, &lv_font_montserrat_12, C_MUT, LV_ALIGN_BOTTOM_MID, 0, -18);

    /* 3 — TOUCH + backlight */
    lv_obj_t *t3 = lv_tileview_add_tile(tv, 2, 0, LV_DIR_LEFT);
    lv_obj_t *h3 = label(t3, &lv_font_montserrat_14, C_CYAN, LV_ALIGN_TOP_MID, 0, 28); lv_label_set_text(h3, "3/3  TOUCH  (tap anywhere)");
    l_touch = label(t3, &lv_font_montserrat_20, C_FG, LV_ALIGN_CENTER, 0, -10); lv_label_set_text(l_touch, "tap the screen");
    for (int i = 0; i < 12; i++) { dots[i] = lv_obj_create(t3); lv_obj_set_size(dots[i], 12, 12); lv_obj_set_style_radius(dots[i], 6, 0);
        lv_obj_set_style_bg_color(dots[i], C_CYAN, 0); lv_obj_set_style_border_width(dots[i], 0, 0); lv_obj_add_flag(dots[i], LV_OBJ_FLAG_HIDDEN);
        lv_obj_remove_flag(dots[i], LV_OBJ_FLAG_CLICKABLE); }
    lv_obj_add_event_cb(t3, touch_cb, LV_EVENT_PRESSED, NULL);
    lv_obj_t *sl = lv_slider_create(t3); lv_obj_set_width(sl, 140); lv_obj_align(sl, LV_ALIGN_BOTTOM_MID, 0, -48);
    lv_slider_set_range(sl, 5, 100); lv_slider_set_value(sl, 80, LV_ANIM_OFF);
    lv_obj_add_event_cb(sl, bl_cb, LV_EVENT_VALUE_CHANGED, NULL);
    lv_obj_t *h4 = label(t3, &lv_font_montserrat_12, C_MUT, LV_ALIGN_BOTTOM_MID, 0, -26); lv_label_set_text(h4, "brightness");

    lv_timer_create(tick, 250, NULL);
    lvgl_port_unlock();
}
