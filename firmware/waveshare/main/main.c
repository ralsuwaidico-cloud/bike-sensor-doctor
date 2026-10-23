/*
 * Bike Computer — Waveshare ESP32-S3-Touch-LCD-1.28-B firmware.
 * Phase A: hardware foundation + diagnostic screens, incl. live XDS power/cadence (milestone 1: real watts and cadence
 * on the Waveshare without the Nokia, HR strap or phone).
 *
 * 0.1.1-diag (2026-10-23) after the 0.1.0 reboot loop:
 *  - staged start-up: each subsystem starts in turn and logs "STAGE n <name> OK", so a fault is pinned to one stage;
 *  - crash-loop guard: after 3 consecutive crash resets the device stops restarting and shows a stable SAFE MODE screen
 *    with the reset reason (display only — no touch, Bluetooth or Wi-Fi). Press RESET to try a normal start again.
 */
#include <stdio.h>
#include "esp_log.h"
#include "esp_app_desc.h"
#include "esp_system.h"
#include "esp_attr.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_lvgl_port.h"
#include "hw.h"
#include "ble_xds.h"

void ui_diag_create(void);
void net_wifi_scan_once(void);

static const char *TAG = "main";
#define GUARD_MAGIC 0xB1C0FFEEu
#define CRASHES_FOR_SAFE_MODE 3
RTC_NOINIT_ATTR static uint32_t s_guard_magic;
RTC_NOINIT_ATTR static uint32_t s_crash_count;

static const char *reason_name(esp_reset_reason_t r)
{
    switch (r) {
    case ESP_RST_POWERON: return "power-on / RESET button";
    case ESP_RST_SW: return "software restart";
    case ESP_RST_PANIC: return "crash (panic)";
    case ESP_RST_INT_WDT: return "interrupt watchdog";
    case ESP_RST_TASK_WDT: return "task watchdog";
    case ESP_RST_WDT: return "watchdog";
    case ESP_RST_BROWNOUT: return "brownout (low voltage)";
    case ESP_RST_DEEPSLEEP: return "wake from deep sleep";
    case ESP_RST_USB: return "USB reset";
    case ESP_RST_JTAG: return "JTAG";
    default: return "other";
    }
}

static bool is_crash(esp_reset_reason_t r)
{
    return r == ESP_RST_PANIC || r == ESP_RST_INT_WDT || r == ESP_RST_TASK_WDT || r == ESP_RST_WDT || r == ESP_RST_BROWNOUT;
}

static void stable_cb(void *arg)
{
    s_crash_count = 0;   /* 20 s without a crash: the start-up is considered good */
    ESP_LOGI(TAG, "STAGE 9 stable for 20 s - crash counter cleared");
}

static void safe_mode_screen(lv_display_t *disp, esp_reset_reason_t r)
{
    lvgl_port_lock(0);
    lv_obj_t *scr = lv_screen_active();
    lv_obj_set_style_bg_color(scr, lv_color_hex(0x080B0E), 0);
    lv_obj_t *t = lv_label_create(scr);
    lv_obj_set_style_text_color(t, lv_color_hex(0xFFB64D), 0);
    lv_obj_set_style_text_font(t, &lv_font_montserrat_20, 0);
    lv_label_set_text(t, "SAFE MODE");
    lv_obj_align(t, LV_ALIGN_TOP_MID, 0, 46);
    lv_obj_t *b = lv_label_create(scr);
    lv_obj_set_style_text_color(b, lv_color_hex(0xEAF2F4), 0);
    lv_obj_set_style_text_font(b, &lv_font_montserrat_14, 0);
    lv_obj_set_style_text_align(b, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_set_width(b, 180);
    lv_label_set_long_mode(b, LV_LABEL_LONG_WRAP);
    char msg[160];
    snprintf(msg, sizeof msg, "Stopped after %u crashes in a row.\nLast reset: %s\n\nPress RESET to retry.\nSend the device log to Claude.",
             (unsigned)s_crash_count, reason_name(r));
    lv_label_set_text(b, msg);
    lv_obj_align(b, LV_ALIGN_CENTER, 0, 14);
    lvgl_port_unlock();
}

void app_main(void)
{
    const esp_app_desc_t *d = esp_app_get_description();
    esp_reset_reason_t why = esp_reset_reason();
    if (s_guard_magic != GUARD_MAGIC) { s_guard_magic = GUARD_MAGIC; s_crash_count = 0; }
    if (is_crash(why)) s_crash_count++; else s_crash_count = 0;
    ESP_LOGI(TAG, "Bike Computer firmware %s (%s %s) - Phase A diagnostic", d->version, d->date, d->time);
    ESP_LOGI(TAG, "reset reason: %s, consecutive crash resets: %u", reason_name(why), (unsigned)s_crash_count);

    hw_selftest_run();                    /* NVS must be up before BLE */
    ESP_LOGI(TAG, "STAGE 1 self-test OK");
    lv_display_t *disp = hw_display_init();
    ESP_LOGI(TAG, "STAGE 2 display OK");

    if (s_crash_count >= CRASHES_FOR_SAFE_MODE) {
        ESP_LOGW(TAG, "SAFE MODE: %u crash resets in a row - only the display runs", (unsigned)s_crash_count);
        safe_mode_screen(disp, why);
        return;                           /* no touch, no UI timer, no Bluetooth, no Wi-Fi */
    }

    esp_timer_handle_t t;
    esp_timer_create_args_t ta = { .callback = stable_cb, .name = "stable" };
    if (esp_timer_create(&ta, &t) == ESP_OK) esp_timer_start_once(t, 20 * 1000 * 1000);

    ui_diag_create();
    ESP_LOGI(TAG, "STAGE 3 diagnostic screens OK");
    vTaskDelay(pdMS_TO_TICKS(1500));      /* the screen updates on its own before anything else starts */
    hw_touch_init(disp);
    ESP_LOGI(TAG, "STAGE 4 touch OK");
#ifndef BC_QEMU_TEST                     /* the QEMU emulator has no Bluetooth or Wi-Fi radio */
    ble_xds_start();                      /* searches for the XDS meter immediately */
    ESP_LOGI(TAG, "STAGE 5 Bluetooth OK");
    vTaskDelay(pdMS_TO_TICKS(1000));
    net_wifi_scan_once();                 /* one scan, then the Wi-Fi radio is switched off again */
    ESP_LOGI(TAG, "STAGE 6 Wi-Fi scan OK");
#else
    ESP_LOGW(TAG, "QEMU test build: Bluetooth and Wi-Fi skipped");
#endif
}
