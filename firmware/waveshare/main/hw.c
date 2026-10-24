/* Phase A hardware layer: display, touch, backlight, battery ADC, IMU presence, PSRAM/flash, NVS, FAT storage. */
#include "hw.h"
#include "board.h"
#include <stdio.h>
#include <string.h>
#include "esp_log.h"
#include "esp_timer.h"
#include "esp_heap_caps.h"
#include "esp_flash.h"
#include "esp_psram.h"
#include "nvs_flash.h"
#include "nvs.h"
#include "esp_vfs_fat.h"
#include "wear_levelling.h"
#include "driver/spi_master.h"
#include "driver/ledc.h"
#include "driver/i2c_master.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_adc/adc_cali.h"
#include "esp_adc/adc_cali_scheme.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_gc9a01.h"
#include "esp_lcd_touch_cst816s.h"
#include "esp_lvgl_port.h"
#include "esp_sleep.h"
#include "esp_attr.h"
#include "esp_mac.h"
#include "driver/gpio.h"
#include "driver/rtc_io.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "hw";
hw_selftest_t g_selftest;
static i2c_master_bus_handle_t s_i2c;
static esp_lcd_panel_handle_t s_panel;
static esp_lcd_panel_io_handle_t s_panel_io;
static esp_lcd_touch_handle_t s_tp;
static esp_lcd_panel_io_handle_t s_tp_io;
static lv_indev_t *s_indev;
RTC_NOINIT_ATTR static int s_rtc_wake_taps;     /* survives deep sleep: taps the rider's setting asks for */
#define WAKE_WINDOW_MS 2500
#define WAKE_MAX_PRESS_MS 450

uint32_t hw_millis(void) { return (uint32_t)(esp_timer_get_time() / 1000); }

#define SET(f, r, ...) do { g_selftest.f = (r); snprintf(g_selftest.f##_s, sizeof g_selftest.f##_s, __VA_ARGS__); \
    ESP_LOGI("selftest", "%-8s %s  %s", #f, (r) == HW_PASS ? "PASS" : (r) == HW_FAIL ? "FAIL" : "INFO", g_selftest.f##_s); } while (0)

/* ------------------------------------------------------------------ backlight */
void hw_backlight_set(int percent)
{
    if (percent < 0) percent = 0;
    if (percent > 100) percent = 100;
    ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_0, (uint32_t)(percent * 1023 / 100));
    ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_0);
}

static void backlight_init(void)
{
    ledc_timer_config_t t = { .speed_mode = LEDC_LOW_SPEED_MODE, .duty_resolution = LEDC_TIMER_10_BIT, .timer_num = LEDC_TIMER_0,
                              .freq_hz = 5000, .clk_cfg = LEDC_AUTO_CLK };
    ESP_ERROR_CHECK(ledc_timer_config(&t));
    ledc_channel_config_t c = { .gpio_num = BOARD_LCD_BL, .speed_mode = LEDC_LOW_SPEED_MODE, .channel = LEDC_CHANNEL_0,
                                .timer_sel = LEDC_TIMER_0, .duty = 0, .hpoint = 0 };
    ESP_ERROR_CHECK(ledc_channel_config(&c));
}

/* ------------------------------------------------------------------ display */
lv_display_t *hw_display_init(void)
{
    backlight_init();
    spi_bus_config_t bus = { .sclk_io_num = BOARD_LCD_SCLK, .mosi_io_num = BOARD_LCD_MOSI, .miso_io_num = BOARD_LCD_MISO,
                             .quadwp_io_num = -1, .quadhd_io_num = -1, .max_transfer_sz = BOARD_LCD_W * 40 * 2 };
    ESP_ERROR_CHECK(spi_bus_initialize(BOARD_LCD_HOST, &bus, SPI_DMA_CH_AUTO));

    esp_lcd_panel_io_handle_t io = NULL;
    esp_lcd_panel_io_spi_config_t io_cfg = { .dc_gpio_num = BOARD_LCD_DC, .cs_gpio_num = BOARD_LCD_CS, .pclk_hz = BOARD_LCD_PCLK_HZ,
                                             .lcd_cmd_bits = 8, .lcd_param_bits = 8, .spi_mode = 0, .trans_queue_depth = 10 };
    ESP_ERROR_CHECK(esp_lcd_new_panel_io_spi((esp_lcd_spi_bus_handle_t)BOARD_LCD_HOST, &io_cfg, &io));

    esp_lcd_panel_handle_t panel = NULL;
    esp_lcd_panel_dev_config_t pcfg = { .reset_gpio_num = BOARD_LCD_RST, .rgb_ele_order = LCD_RGB_ELEMENT_ORDER_BGR, .bits_per_pixel = 16 };
    ESP_ERROR_CHECK(esp_lcd_new_panel_gc9a01(io, &pcfg, &panel));
    ESP_ERROR_CHECK(esp_lcd_panel_reset(panel));
    ESP_ERROR_CHECK(esp_lcd_panel_init(panel));
    ESP_ERROR_CHECK(esp_lcd_panel_invert_color(panel, true));
    ESP_ERROR_CHECK(esp_lcd_panel_mirror(panel, true, false));
    ESP_ERROR_CHECK(esp_lcd_panel_disp_on_off(panel, true));

    lvgl_port_cfg_t lcfg = ESP_LVGL_PORT_INIT_CONFIG();
    lcfg.task_affinity = 1;            /* UI on core 1; BLE/Wi-Fi run on core 0 */
    lcfg.task_stack = 12288;           /* the UI builds screens with formatted text; head-room is logged every 60 s */
    ESP_ERROR_CHECK(lvgl_port_init(&lcfg));
    lvgl_port_display_cfg_t dcfg = {
        .io_handle = io, .panel_handle = panel, .buffer_size = BOARD_LCD_W * 40, .double_buffer = true,
        .hres = BOARD_LCD_W, .vres = BOARD_LCD_H, .monochrome = false,
        .rotation = { .swap_xy = false, .mirror_x = true, .mirror_y = false },
        .color_format = LV_COLOR_FORMAT_RGB565,
        .flags = { .buff_dma = true, .swap_bytes = true },
    };
    lv_display_t *disp = lvgl_port_add_disp(&dcfg);
    s_panel = panel; s_panel_io = io;
    hw_backlight_set(80);
    SET(display, disp ? HW_PASS : HW_FAIL, disp ? "GC9A01 240x240 @ %d MHz" : "init failed (%d MHz)", BOARD_LCD_PCLK_HZ / 1000000);
    return disp;
}

/* ------------------------------------------------------------------ I2C, touch, IMU */
static void i2c_init(void)
{
    if (s_i2c) return;
    i2c_master_bus_config_t b = { .i2c_port = I2C_NUM_0, .sda_io_num = BOARD_I2C_SDA, .scl_io_num = BOARD_I2C_SCL,
                                  .clk_source = I2C_CLK_SRC_DEFAULT, .glitch_ignore_cnt = 7, .flags.enable_internal_pullup = true };
    ESP_ERROR_CHECK(i2c_new_master_bus(&b, &s_i2c));
}

static esp_err_t touch_create(bool reset)
{
    i2c_init();
    esp_lcd_panel_io_handle_t tio = NULL;
    esp_lcd_panel_io_i2c_config_t tcfg = ESP_LCD_TOUCH_IO_I2C_CST816S_CONFIG();
    tcfg.scl_speed_hz = 400000;
    esp_err_t e = esp_lcd_new_panel_io_i2c(s_i2c, &tcfg, &tio);
    if (e != ESP_OK) return e;
    s_tp_io = tio;
    esp_lcd_touch_config_t cfg = { .x_max = BOARD_LCD_W, .y_max = BOARD_LCD_H, .rst_gpio_num = reset ? BOARD_TP_RST : -1, .int_gpio_num = BOARD_TP_INT,
                                   .levels = { .reset = 0, .interrupt = 0 }, .flags = { .swap_xy = 0, .mirror_x = 0, .mirror_y = 0 } };
    return esp_lcd_touch_new_i2c_cst816s(tio, &cfg, &s_tp);
}

bool hw_touch_init(lv_display_t *disp)
{
    if (!s_tp) {                                       /* after a wake the check below may already have created it */
        esp_err_t e = touch_create(true);
        if (e != ESP_OK || !s_tp) { SET(touch, HW_FAIL, "CST816S not found (%s)", esp_err_to_name(e)); return false; }
    }
    esp_lcd_touch_handle_t tp = s_tp;
    lvgl_port_touch_cfg_t lt = { .disp = disp, .handle = tp };
    s_indev = lvgl_port_add_touch(&lt);
    hw_touch_keep_awake(false);                        /* normal operation: controller auto-sleep (a wake check may have disabled it) */
    SET(touch, HW_PASS, "CST816S ready");
    return true;
}

static void imu_check(void)
{
    i2c_init();
    const uint8_t addrs[2] = { BOARD_IMU_ADDR_A, BOARD_IMU_ADDR_B };
    for (int i = 0; i < 2; i++) {
        i2c_master_dev_handle_t d;
        i2c_device_config_t dc = { .dev_addr_length = I2C_ADDR_BIT_LEN_7, .device_address = addrs[i], .scl_speed_hz = 400000 };
        if (i2c_master_bus_add_device(s_i2c, &dc, &d) != ESP_OK) continue;
        uint8_t reg = 0x00, who = 0;
        esp_err_t e = i2c_master_transmit_receive(d, &reg, 1, &who, 1, 50);
        i2c_master_bus_rm_device(d);
        if (e == ESP_OK) { SET(imu, who == 0x05 ? HW_PASS : HW_INFO, "QMI8658 @0x%02X WHO_AM_I=0x%02X", addrs[i], who); return; }
    }
    SET(imu, HW_FAIL, "QMI8658 not answering at 0x6B/0x6A");
}

/* ------------------------------------------------------------------ power (0.5.0) — not yet verified on the device */
void hw_panel_sleep(bool sleep)
{
    if (!s_panel || !s_panel_io) return;
    if (sleep) {
        esp_lcd_panel_disp_on_off(s_panel, false);
        esp_lcd_panel_io_tx_param(s_panel_io, 0x10, NULL, 0);          /* SLPIN */
    } else {
        esp_lcd_panel_io_tx_param(s_panel_io, 0x11, NULL, 0);          /* SLPOUT: the controller needs 120 ms before display-on */
        vTaskDelay(pdMS_TO_TICKS(120));
        esp_lcd_panel_disp_on_off(s_panel, true);
    }
}

/* CST816S registers (register map in docs/POWER_FEASIBILITY.md sources): 0xFE DisAutoSleep (non-zero = never sleep),
   0xF9 AutoSleepTime (s), 0xFA IrqCtl, 0xEC MotionMask. Written through the touch panel's own I2C io (8-bit register). */
static void tp_write(uint8_t reg, uint8_t val) { if (s_tp_io) esp_lcd_panel_io_tx_param(s_tp_io, reg, &val, 1); }

void hw_touch_keep_awake(bool keep)
{
    /* Root cause of the 0.5.0 "many taps needed": the controller auto-sleeps 2 s after the last touch; the first touch then
       only wakes it (tens of ms) and is never reported, so the rider's first tap was lost every time. Keeping it awake while
       the screen is off costs roughly 1.5 mA extra (datasheet active current) — accepted for screen-off, not for deep sleep. */
    tp_write(0xFE, keep ? 0x01 : 0x00);
    if (!keep) tp_write(0xF9, 2);                                   /* back to the 2 s auto-sleep */
    if (s_indev) { lv_timer_t *t = lv_indev_get_read_timer(s_indev); if (t) lv_timer_set_period(t, keep ? 15 : 30); }   /* 15 ms polling: a 40 ms tap gets 2 samples */
}

int hw_wake_taps_needed(void) { return (s_rtc_wake_taps >= 2 && s_rtc_wake_taps <= 3) ? s_rtc_wake_taps : 3; }
bool hw_device_id(uint8_t out[6]) { return esp_read_mac(out, ESP_MAC_BT) == ESP_OK; }

void hw_deep_sleep_touch_wake(int taps)
{
    s_rtc_wake_taps = (taps >= 2 && taps <= 3) ? taps : 3;
    ESP_LOGI(TAG, "deep sleep: wake on touch (GPIO%d low, then %d taps), RESET or USB", BOARD_TP_INT, s_rtc_wake_taps);
    hw_touch_keep_awake(false);                                       /* the controller must sleep so a touch raises INT and wakes us */
    /* backlight hard off and held through sleep (the FET gate must not float high) */
    ledc_stop(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_0, 0);
    gpio_reset_pin(BOARD_LCD_BL); gpio_set_direction(BOARD_LCD_BL, GPIO_MODE_OUTPUT); gpio_set_level(BOARD_LCD_BL, 0);
    gpio_hold_en(BOARD_LCD_BL);
    /* touch controller stays powered and out of reset so a finger pulls TP_INT low */
    gpio_reset_pin(BOARD_TP_RST); gpio_set_direction(BOARD_TP_RST, GPIO_MODE_OUTPUT); gpio_set_level(BOARD_TP_RST, 1);
    gpio_hold_en(BOARD_TP_RST);
    gpio_deep_sleep_hold_en();
    rtc_gpio_init(BOARD_TP_INT); rtc_gpio_set_direction(BOARD_TP_INT, RTC_GPIO_MODE_INPUT_ONLY);
    rtc_gpio_pullup_en(BOARD_TP_INT); rtc_gpio_pulldown_dis(BOARD_TP_INT);
    esp_sleep_enable_ext0_wakeup(BOARD_TP_INT, 0);
    vTaskDelay(pdMS_TO_TICKS(20));
    esp_deep_sleep_start();
}

/* After an ext0 wake the chip needs ~200-300 ms to get here; the touch that woke it is tap 1 (a finger still down at this
   point is that same touch and is counted when it lifts). Then press->release pairs of <= 450 ms count, anywhere on the
   glass, until the stored number of taps is reached within 2.5 s of the wake. A hold (> 450 ms) or the window running out
   puts the device back to sleep in < 200 ms. NOT hardware-verified: see pc-kit/TEST-v0.6.0.txt (20 trials). */
bool hw_wake_tap_check(void)
{
    gpio_deep_sleep_hold_dis(); gpio_hold_dis(BOARD_LCD_BL); gpio_hold_dis(BOARD_TP_RST);
    rtc_gpio_deinit(BOARD_TP_INT);
    if (touch_create(false) != ESP_OK || !s_tp) { ESP_LOGW(TAG, "wake check: touch not reachable, staying awake"); return true; }
    tp_write(0xFE, 0x01);                                             /* stay awake for the whole check: every tap must be reported */
    int need = hw_wake_taps_needed();
    int taps = 1, presses = 0; bool down = false; uint32_t t0 = hw_millis(), down_ms = 0;
    /* is the waking finger still on the glass? then its release does not count as a new tap */
    esp_lcd_touch_read_data(s_tp);
    { uint16_t x, y, st; uint8_t n = 0; if (esp_lcd_touch_get_coordinates(s_tp, &x, &y, &st, &n, 1) && n > 0) { down = true; down_ms = t0; taps = 0; } }
    while (hw_millis() - t0 < WAKE_WINDOW_MS) {
        esp_lcd_touch_read_data(s_tp);
        uint16_t x, y, st; uint8_t n = 0;
        bool p = esp_lcd_touch_get_coordinates(s_tp, &x, &y, &st, &n, 1) && n > 0;
        if (p && !down) { down = true; down_ms = hw_millis(); presses++; }
        else if (!p && down) {
            down = false;
            if (hw_millis() - down_ms > WAKE_MAX_PRESS_MS) { ESP_LOGI(TAG, "wake check: a hold, not a tap - back to sleep"); break; }
            taps++;
            if (taps >= need) { ESP_LOGI(TAG, "wake check: %d taps in %lu ms", taps, (unsigned long)(hw_millis() - t0)); return true; }
        }
        vTaskDelay(pdMS_TO_TICKS(8));
    }
    ESP_LOGI(TAG, "wake check: %d tap(s) of %d (%d presses) - back to sleep", taps, need, presses);
    return false;
}

/* ------------------------------------------------------------------ battery */
static adc_oneshot_unit_handle_t s_adc;
static adc_cali_handle_t s_cali;

float hw_battery_volts(void)
{
    if (!s_adc) {
        adc_oneshot_unit_init_cfg_t u = { .unit_id = ADC_UNIT_1 };
        if (adc_oneshot_new_unit(&u, &s_adc) != ESP_OK) return -1;
        adc_oneshot_chan_cfg_t c = { .atten = ADC_ATTEN_DB_12, .bitwidth = ADC_BITWIDTH_12 };
        adc_oneshot_config_channel(s_adc, ADC_CHANNEL_0, &c);       /* GPIO1 = ADC1_CH0 on the ESP32-S3 */
        adc_cali_curve_fitting_config_t cc = { .unit_id = ADC_UNIT_1, .chan = ADC_CHANNEL_0, .atten = ADC_ATTEN_DB_12, .bitwidth = ADC_BITWIDTH_12 };
        if (adc_cali_create_scheme_curve_fitting(&cc, &s_cali) != ESP_OK) s_cali = NULL;
    }
    int sum = 0, n = 0;
    for (int i = 0; i < 16; i++) { int raw, mv; if (adc_oneshot_read(s_adc, ADC_CHANNEL_0, &raw) != ESP_OK) continue;
        if (s_cali && adc_cali_raw_to_voltage(s_cali, raw, &mv) == ESP_OK) { sum += mv; n++; } else { sum += raw * 3300 / 4095; n++; } }
    if (!n) return -1;
    return (float)sum / n / 1000.0f * BOARD_BAT_DIVIDER;
}

/* ------------------------------------------------------------------ memory, NVS, storage */
void hw_selftest_run(void)
{
#if CONFIG_SPIRAM
    size_t ps = esp_psram_is_initialized() ? esp_psram_get_size() : 0;
#else
    size_t ps = 0;   /* PSRAM disabled in this build (QEMU emulator test only) */
#endif
    SET(psram, ps >= 2 * 1024 * 1024 ? HW_PASS : HW_FAIL, "%u KB PSRAM, %u KB free internal", (unsigned)(ps / 1024),
        (unsigned)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024));

    uint32_t fsz = 0; esp_flash_get_size(NULL, &fsz);
    SET(flash, fsz == 16 * 1024 * 1024 ? HW_PASS : HW_FAIL, "%u MB flash", (unsigned)(fsz / (1024 * 1024)));

    esp_err_t e = nvs_flash_init();
    if (e == ESP_ERR_NVS_NO_FREE_PAGES || e == ESP_ERR_NVS_NEW_VERSION_FOUND) { nvs_flash_erase(); e = nvs_flash_init(); }
    nvs_handle_t h;
    if (e == ESP_OK && nvs_open("diag", NVS_READWRITE, &h) == ESP_OK) {
        uint32_t boots = 0; nvs_get_u32(h, "boots", &boots); boots++; nvs_set_u32(h, "boots", boots); nvs_commit(h); nvs_close(h);
        g_selftest.boot_count = boots;
        SET(nvs, HW_PASS, "boot #%u remembered", (unsigned)boots);
    } else SET(nvs, HW_FAIL, "%s", esp_err_to_name(e));

    /* the 'storage' FAT partition is new space created by this firmware's partition table (the factory app is backed up first) */
    static wl_handle_t wl = WL_INVALID_HANDLE;
    esp_vfs_fat_mount_config_t m = { .format_if_mount_failed = true, .max_files = 4, .allocation_unit_size = 4096 };
    e = esp_vfs_fat_spiflash_mount_rw_wl("/data", "storage", &m, &wl);
    if (e == ESP_OK) {
        FILE *f = fopen("/data/selftest.txt", "w"); bool ok = false;
        if (f) { fprintf(f, "boot %u\n", (unsigned)g_selftest.boot_count); fclose(f);
            f = fopen("/data/selftest.txt", "r"); unsigned b = 0; if (f) { ok = fscanf(f, "boot %u", &b) == 1 && b == g_selftest.boot_count; fclose(f); } }
        uint64_t tot = 0, fre = 0; esp_vfs_fat_info("/data", &tot, &fre);
        SET(storage, ok ? HW_PASS : HW_FAIL, "FAT %u KB free / %u KB", (unsigned)(fre / 1024), (unsigned)(tot / 1024));
    } else SET(storage, HW_FAIL, "mount: %s", esp_err_to_name(e));

    imu_check();
    float v = hw_battery_volts();
    if (v < 0) SET(battery, HW_FAIL, "ADC unavailable");
    else SET(battery, HW_INFO, "%.2f V %s", v, v > 4.3f ? "(USB, no battery?)" : v < 3.0f ? "(no battery / reading low)" : "");
    ESP_LOGI(TAG, "self-test done");
}
