#pragma once
#include <stdbool.h>
#include <stdint.h>
#include "lvgl.h"

/* Results of the power-on self-test; each line is shown on the SELF-TEST page and printed to the serial log. */
typedef enum { HW_UNTESTED = 0, HW_PASS, HW_FAIL, HW_INFO } hw_result_t;
typedef struct {
    hw_result_t display, touch, psram, flash, nvs, storage, imu, battery, wifi, ble;
    char display_s[48], touch_s[48], psram_s[48], flash_s[48], nvs_s[48], storage_s[48], imu_s[48], battery_s[48], wifi_s[48], ble_s[48];
    uint32_t boot_count;
} hw_selftest_t;

extern hw_selftest_t g_selftest;

lv_display_t *hw_display_init(void);     /* SPI + GC9A01 + LVGL port; returns the LVGL display */
bool hw_touch_init(lv_display_t *disp);  /* CST816S on I2C0 + LVGL input */
void hw_backlight_set(int percent);      /* 0..100 */
void hw_selftest_run(void);              /* PSRAM, flash, NVS boot counter, FAT storage R/W, IMU WHO_AM_I, battery */
float hw_battery_volts(void);            /* < 0 when unavailable */
uint32_t hw_millis(void);
