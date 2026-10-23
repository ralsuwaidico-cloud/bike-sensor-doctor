/*
 * Bike Computer — Waveshare ESP32-S3-Touch-LCD-1.28-B firmware.
 * Phase A: hardware foundation + diagnostic screens, incl. live XDS power/cadence (milestone 1: real watts and cadence
 * on the Waveshare without the Nokia, HR strap or phone).
 */
#include "esp_log.h"
#include "esp_app_desc.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "hw.h"
#include "ble_xds.h"

void ui_diag_create(void);
void net_wifi_scan_once(void);

void app_main(void)
{
    const esp_app_desc_t *d = esp_app_get_description();
    ESP_LOGI("main", "Bike Computer firmware %s (%s %s) — Phase A diagnostic", d->version, d->date, d->time);

    hw_selftest_run();                    /* NVS must be up before BLE */
    lv_display_t *disp = hw_display_init();
    hw_touch_init(disp);
    ui_diag_create();
    ble_xds_start();                      /* searches for the XDS meter immediately */
    net_wifi_scan_once();                 /* one scan, then the Wi-Fi radio is switched off again */
    ESP_LOGI("main", "running");
}
