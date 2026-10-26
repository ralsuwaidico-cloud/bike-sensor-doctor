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
typedef bool (*hw_touch_filter_t)(bool pressed, int x, int y, uint32_t now_ms);
void hw_touch_set_filter(hw_touch_filter_t f);   /* veto presses before LVGL (wake gesture swallow + guard) */
void hw_touch_diag_log(const char *when);        /* 0.6.1: chip id / fw / DisAutoSleep / INT level / indev mode to the serial log */
void hw_touch_counters(uint32_t *reads, uint32_t *presses);   /* raw driver reads and reads with a finger down since boot */
bool hw_boot_button_held(void);
void hw_touch_poll(void);                        /* 0.6.1: read the controller now (event-mode indev reads only on interrupt) */
void hw_touch_wake_check(void);                  /* 0.6.1: after a screen wake: is the controller answering? else TP_RST pulse */                  /* 0.6.1: BOOT (GPIO0) low at start-up -> SAFE MODE */
void hw_backlight_set(int percent);      /* 0..100 */
void hw_selftest_run(void);              /* PSRAM, flash, NVS boot counter, FAT storage R/W, IMU WHO_AM_I, battery */
void hw_selftest_nvs(void);              /* 0.7.3: PSRAM, flash, NVS + boot counter */
bool hw_selftest_storage(void);          /* 0.7.3: FAT mount + R/W check, IMU, battery; true = storage usable */
float hw_battery_volts(void);            /* < 0 when unavailable */
uint32_t hw_millis(void);
/* power (0.5.0 / 0.6.0) — NOT hardware-verified until the device tests in pc-kit/TEST-v0.6.0.txt */
void hw_panel_sleep(bool sleep);         /* GC9A01 display off + sleep-in (0x10) / sleep-out (0x11) + display on */
/** Screen-off mode: keep the CST816S awake (DisAutoSleep) so the first quick tap is reported instead of only waking the
 *  controller, and poll it faster. keep=false restores auto-sleep (needed before deep sleep so a touch wakes the chip). */
void hw_touch_keep_awake(bool keep);
void hw_deep_sleep_touch_wake(int taps); /* backlight held off, TP_RST held high, ext0 wake on TP_INT (GPIO5, low); never returns. taps 1..3 (1 = the waking touch alone) */
bool hw_wake_tap_check(void);            /* after an ext0 wake: the waking touch is tap 1; wait <= 2.5 s for the rest (profile setting kept in RTC memory) */
int hw_wake_taps_needed(void);           /* what the last deep sleep asked for (diagnostics) */
bool hw_device_id(uint8_t out[6]);       /* Bluetooth MAC */
