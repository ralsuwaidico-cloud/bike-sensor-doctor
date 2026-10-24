/*
 * Bike Computer — Waveshare ESP32-S3-Touch-LCD-1.28-B firmware 0.5.0 (0.4.0 + power management).
 * Standalone cycling computer: onboarding, home, ride (4 pages + controls), coach, results, history, settings, sensors,
 * DEMO MODE. App/UI code is shared with the PC test harness (test/sim); hardware lives in hw.c, ble_central.c, plat_esp.c.
 *
 * Kept from 0.1.1-diag (reboot-loop fix):
 *  - staged start-up: each subsystem logs "STAGE n <name> OK", so a fault is pinned to one stage;
 *  - crash-loop guard: after 3 consecutive crash resets the device stops restarting and shows a SAFE MODE screen;
 *  - health line every 60 s: free/min heap, LVGL memory, task stack head-room, sensor state;
 *  - never pass %f to lv_*_fmt (LVGL printf has no float support) — test/host `make lint` enforces it.
 */
#include <stdio.h>
#include "esp_log.h"
#include "esp_app_desc.h"
#include "esp_system.h"
#include "esp_attr.h"
#include "esp_timer.h"
#include "esp_heap_caps.h"
#include "esp_sleep.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_lvgl_port.h"
#include "nvs.h"
#include "hw.h"
#include "ble_central.h"
#include "app.h"
#include "ui.h"
void net_wifi_init(void);

static const char *TAG = "main";
#define GUARD_MAGIC 0xB1C0FFEEu
#define CRASHES_FOR_SAFE_MODE 3
RTC_NOINIT_ATTR static uint32_t s_guard_magic;
RTC_NOINIT_ATTR static uint32_t s_crash_count;
uint32_t g_crash_consecutive;

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

static void safe_mode_screen(esp_reset_reason_t r)
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

/* persistent counters for Device Health (NVS namespace "diag", next to the boot counter) */
static void bump(const char *key)
{
    nvs_handle_t h; uint32_t v = 0;
    if (nvs_open("diag", NVS_READWRITE, &h) != ESP_OK) return;
    nvs_get_u32(h, key, &v); nvs_set_u32(h, key, v + 1); nvs_commit(h); nvs_close(h);
}

static void health(void)
{
    char line[200]; app_health_line(line, sizeof line);
    lv_mem_monitor_t m; lvgl_port_lock(0); lv_mem_monitor(&m); lvgl_port_unlock();
    TaskHandle_t lv = xTaskGetHandle("taskLVGL"), nb = xTaskGetHandle("nimble_host");
    ESP_LOGI(TAG, "%s lvgl %u%% (max %uB) stack-free lvgl %u nimble %u main %u", line, m.used_pct, (unsigned)m.max_used,
             lv ? (unsigned)uxTaskGetStackHighWaterMark(lv) : 0, nb ? (unsigned)uxTaskGetStackHighWaterMark(nb) : 0,
             (unsigned)uxTaskGetStackHighWaterMark(NULL));
}

void app_main(void)
{
    const esp_app_desc_t *d = esp_app_get_description();
    esp_reset_reason_t why = esp_reset_reason();
    if (s_guard_magic != GUARD_MAGIC) { s_guard_magic = GUARD_MAGIC; s_crash_count = 0; }
    if (is_crash(why)) s_crash_count++; else s_crash_count = 0;
    ESP_LOGI(TAG, "Bike Computer firmware %s (%s %s)", d->version, d->date, d->time);
    ESP_LOGI(TAG, "reset reason: %s, consecutive crash resets: %u", reason_name(why), (unsigned)s_crash_count);

    /* 0.5.0: woken from deep sleep by a touch — a single accidental touch goes straight back to sleep (< 2 s awake); three
       taps within 1.5 s start the device. RESET and USB wakes skip the check. NOT hardware-verified yet. */
    if (why == ESP_RST_DEEPSLEEP && esp_sleep_get_wakeup_cause() == ESP_SLEEP_WAKEUP_EXT0) {
        ESP_LOGI(TAG, "STAGE 0 touch wake: waiting for three taps");
        if (!hw_wake_tap_check()) hw_deep_sleep_touch_wake();   /* never returns */
    }

    hw_selftest_run();                    /* NVS must be up before BLE and the profile */
    ESP_LOGI(TAG, "STAGE 1 self-test OK");
    g_crash_consecutive = s_crash_count;
    if (is_crash(why)) bump("crashes");
    lv_display_t *disp = hw_display_init();
    ESP_LOGI(TAG, "STAGE 2 display OK");

    if (s_crash_count >= CRASHES_FOR_SAFE_MODE) {
        ESP_LOGW(TAG, "SAFE MODE: %u crash resets in a row - only the display runs", (unsigned)s_crash_count);
        bump("safemode");
        safe_mode_screen(why);
        return;                           /* no touch, no UI, no Bluetooth, no Wi-Fi */
    }

    esp_timer_handle_t t;
    esp_timer_create_args_t ta = { .callback = stable_cb, .name = "stable" };
    if (esp_timer_create(&ta, &t) == ESP_OK) esp_timer_start_once(t, 20 * 1000 * 1000);

    hw_touch_init(disp);
    ESP_LOGI(TAG, "STAGE 3 touch OK");
    ble_central_start();
    ESP_LOGI(TAG, "STAGE 4 Bluetooth OK");

    lvgl_port_lock(0);
    app_init();                           /* profile from NVS; an interrupted ride is recovered here */
    bc_profile_t *p = app_profile();
    if (p->power.paired) ble_central_set_paired(PLAT_SENS_POWER, p->power.mac, p->power.addr_type, p->power.name);
    if (p->hr.paired) ble_central_set_paired(PLAT_SENS_HR, p->hr.mac, p->hr.addr_type, p->hr.name);
    ui_start();
    lvgl_port_unlock();
    ESP_LOGI(TAG, "STAGE 5 app + screens OK (power meter %s, HR %s)", p->power.paired ? p->power.name : "not paired",
             p->hr.paired ? p->hr.name : "not paired");
    net_wifi_init();                      /* background manager; radio stays off unless the rider switched Wi-Fi on */
    g_selftest.wifi = HW_INFO; snprintf(g_selftest.wifi_s, sizeof g_selftest.wifi_s, p->wifi_on ? "on" : "off (optional)");
    if (p->wifi_on) { plat_wifi_set_enabled(true); ESP_LOGI(TAG, "STAGE 6 Wi-Fi on (joins saved networks in the background)"); }

    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(60000));
        health();
    }
}
