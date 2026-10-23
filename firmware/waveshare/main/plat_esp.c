/* plat.h on the Waveshare ESP32-S3-Touch-LCD-1.28-B: NimBLE sensors, NVS profile, FAT ride storage, battery ADC. */
#include "plat.h"
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include "esp_app_desc.h"
#include "esp_heap_caps.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_wifi.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs.h"
#include "ble_central.h"
#include "hw.h"

static const char *TAG = "plat";
#define ROOT "/data/"

uint32_t plat_ms(void) { return hw_millis(); }
void plat_sensors(plat_sensors_t *o) { ble_central_snapshot(o); }

static int s_scan_kind = -1;
void plat_scan_begin(plat_sens_kind_t k) { s_scan_kind = (int)k; ble_central_scan_for((int)k); }
int plat_scan_results(plat_found_t *out, int max) { return s_scan_kind < 0 ? 0 : ble_central_found((plat_sens_kind_t)s_scan_kind, out, max); }
void plat_scan_end(void) { s_scan_kind = -1; ble_central_scan_for(-1); }
void plat_pair(plat_sens_kind_t k, const plat_found_t *d)
{
    if (d) ble_central_set_paired(k, d->mac, d->addr_type, d->name); else ble_central_set_paired(k, NULL, 0, NULL);
    ESP_LOGI(TAG, "%s %s %s", k == PLAT_SENS_POWER ? "power meter" : "HR strap", d ? "paired:" : "forgotten", d ? d->name : "");
}

/* ---- profile in NVS (power-loss safe) */
bool plat_profile_load(char *buf, size_t cap)
{
    nvs_handle_t h; size_t n = cap;
    if (nvs_open("bc", NVS_READONLY, &h) != ESP_OK) return false;
    esp_err_t e = nvs_get_str(h, "profile", buf, &n);
    nvs_close(h);
    return e == ESP_OK;
}

bool plat_profile_save(const char *txt)
{
    nvs_handle_t h;
    if (nvs_open("bc", NVS_READWRITE, &h) != ESP_OK) return false;
    esp_err_t e = nvs_set_str(h, "profile", txt);
    if (e == ESP_OK) e = nvs_commit(h);
    nvs_close(h);
    if (e != ESP_OK) ESP_LOGE(TAG, "profile save failed: %s", esp_err_to_name(e));
    return e == ESP_OK;
}

/* ---- files on the FAT partition */
static void full(const char *rel, char *out, size_t cap)
{
    snprintf(out, cap, ROOT "%s", rel);
    char dir[96]; snprintf(dir, sizeof dir, "%s", out);
    char *sl = strrchr(dir, '/');
    if (sl && sl > dir + strlen(ROOT) - 1) { *sl = 0; mkdir(dir, 0775); }
}

bool plat_file_append(const char *path, const char *data, size_t len, bool sync)
{
    char p[96]; full(path, p, sizeof p);
    FILE *f = fopen(p, "a"); if (!f) { ESP_LOGE(TAG, "append %s: errno %d", p, errno); return false; }
    size_t w = fwrite(data, 1, len, f);
    if (sync) { fflush(f); fsync(fileno(f)); }
    fclose(f);
    return w == len;
}

bool plat_file_write(const char *path, const char *data, size_t len)
{
    char p[96], t[100]; full(path, p, sizeof p); snprintf(t, sizeof t, "%s.tmp", p);
    FILE *f = fopen(t, "w"); if (!f) return false;
    size_t w = fwrite(data, 1, len, f); fflush(f); fsync(fileno(f)); fclose(f);
    if (w != len) { unlink(t); return false; }
    unlink(p);
    return rename(t, p) == 0;
}

long plat_file_read_at(const char *path, long off, char *buf, size_t cap)
{
    char p[96]; full(path, p, sizeof p);
    FILE *f = fopen(p, "r"); if (!f) return -1;
    if (off && fseek(f, off, SEEK_SET) != 0) { fclose(f); return 0; }
    long n = (long)fread(buf, 1, cap, f); fclose(f); return n;
}
long plat_file_read(const char *path, char *buf, size_t cap) { return plat_file_read_at(path, 0, buf, cap); }
bool plat_file_rename(const char *from, const char *to) { char a[96], b[96]; full(from, a, sizeof a); full(to, b, sizeof b); unlink(b); return rename(a, b) == 0; }
bool plat_file_remove(const char *path) { char p[96]; full(path, p, sizeof p); return unlink(p) == 0; }
bool plat_storage_ok(void) { return g_selftest.storage == HW_PASS; }

/* ---- battery: averaged, read at most every 5 s */
static int s_mv = -1; static uint32_t s_bat_t;
int plat_battery_mv(void)
{
    uint32_t now = hw_millis();
    if (s_mv < 0 || now - s_bat_t > 5000) {
        float v = hw_battery_volts(); s_bat_t = now;
        if (v > 0) { int mv = (int)(v * 1000.0f); s_mv = s_mv < 0 ? mv : (s_mv * 3 + mv) / 4; }
    }
    return s_mv;
}
int plat_battery_pct(void)
{
    static const int MV[] = { 3300, 3500, 3600, 3700, 3800, 3900, 4000, 4100, 4200 }, PCT[] = { 0, 5, 15, 30, 50, 65, 80, 90, 100 };
    int mv = plat_battery_mv(); if (mv < 0) return -1;
    if (mv <= MV[0]) return 0;
    for (int i = 1; i < 9; i++) if (mv <= MV[i]) return PCT[i - 1] + (PCT[i] - PCT[i - 1]) * (mv - MV[i - 1]) / (MV[i] - MV[i - 1]);
    return 100;
}
/* The board has no charge-status line wired to the ESP32: above 4.25 V we assume USB power without a (full) battery. */
bool plat_usb_power(void) { return plat_battery_mv() > 4250; }

void plat_backlight(int pct) { hw_backlight_set(pct < 5 ? 5 : pct); }

/* ---- Wi-Fi: optional; one scan when switched on, radio off otherwise */
void net_wifi_scan_once(void);
int net_wifi_count(void);
void net_wifi_off(void);
static void wifi_task(void *a) { net_wifi_scan_once(); vTaskDelete(NULL); }
void plat_wifi_enable(bool on)
{
    if (on) xTaskCreatePinnedToCore(wifi_task, "wifi_scan", 4096, NULL, 3, NULL, 0);
    else net_wifi_off();
}
int plat_wifi_scan_count(void) { return net_wifi_count(); }

const char *plat_fw_version(void) { return esp_app_get_description()->version; }
const char *plat_reset_reason(void)
{
    switch (esp_reset_reason()) {
    case ESP_RST_POWERON: return "power-on"; case ESP_RST_SW: return "software"; case ESP_RST_PANIC: return "crash";
    case ESP_RST_INT_WDT: case ESP_RST_TASK_WDT: case ESP_RST_WDT: return "watchdog"; case ESP_RST_BROWNOUT: return "brownout";
    case ESP_RST_USB: return "USB"; default: return "other";
    }
}
uint32_t plat_boot_count(void) { return g_selftest.boot_count; }
void plat_restart(void) { esp_restart(); }

static const char *word(hw_result_t r) { return r == HW_PASS ? "#56E08C PASS#" : r == HW_FAIL ? "#FF5A5A FAIL#" : r == HW_INFO ? "#FFB64D INFO#" : "#7D8B93 ...#"; }
void plat_selftest_text(char *b, size_t cap)
{
    snprintf(b, cap, "Display %s\nTouch %s\nPSRAM %s\nFlash %s\nNVS %s\nStorage %s\n%s\nIMU %s\nBattery %s %d mV\nWi-Fi %s %s\nBLE %s %lu seen",
             word(g_selftest.display), word(g_selftest.touch), word(g_selftest.psram), word(g_selftest.flash), word(g_selftest.nvs),
             word(g_selftest.storage), g_selftest.storage_s, word(g_selftest.imu), word(g_selftest.battery), plat_battery_mv(),
             word(g_selftest.wifi), g_selftest.wifi_s, ble_central_devices_seen() ? "#56E08C PASS#" : "#7D8B93 ...#", (unsigned long)ble_central_devices_seen());
}
void plat_mem_text(char *b, size_t cap)
{
    snprintf(b, cap, "heap %uK min %uK psram %uK", (unsigned)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024),
             (unsigned)(heap_caps_get_minimum_free_size(MALLOC_CAP_INTERNAL) / 1024), (unsigned)(heap_caps_get_free_size(MALLOC_CAP_SPIRAM) / 1024));
}
void plat_log(const char *line) { ESP_LOGI("app", "%s", line); }
