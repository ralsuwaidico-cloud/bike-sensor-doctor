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
#include "esp_ota_ops.h"
#include "esp_image_format.h"
#include "esp_flash.h"
#include "esp_vfs_fat.h"
#include "esp_timer.h"
#include "ble_central.h"
#include "hw.h"
#include "bc_power.h"

static const char *TAG = "plat";
static uint32_t s_storage_errors, s_profile_errors;
extern uint32_t g_crash_consecutive;
#define ROOT "/data/"

uint32_t plat_ms(void) { return hw_millis(); }
void plat_sensors(plat_sensors_t *o) { ble_central_snapshot(o); }
void plat_csc_wheel_mm(uint16_t mm) { ble_central_set_wheel_mm(mm); }

static int s_scan_kind = -1;
void plat_scan_begin(plat_sens_kind_t k) { s_scan_kind = (int)k; ble_central_scan_for((int)k); }
int plat_scan_results(plat_found_t *out, int max) { return s_scan_kind < 0 ? 0 : ble_central_found((plat_sens_kind_t)s_scan_kind, out, max); }
void plat_scan_end(void) { s_scan_kind = -1; ble_central_scan_for(-1); }
void plat_pair(plat_sens_kind_t k, const plat_found_t *d)
{
    if (d) ble_central_set_paired(k, d->mac, d->addr_type, d->name); else ble_central_set_paired(k, NULL, 0, NULL);
    ESP_LOGI(TAG, "%s %s", k == PLAT_SENS_POWER ? "power meter" : k == PLAT_SENS_HR ? "HR strap" : "speed/cadence sensor", d ? "paired" : "forgotten");   /* no names in logs (0.7.3) */
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
    if (e != ESP_OK) { s_profile_errors++; ESP_LOGE(TAG, "profile save failed: %s", esp_err_to_name(e)); }
    return e == ESP_OK;
}

/* ---- files on the FAT partition
   0.7.4: (1) the path helper no longer calls mkdir() for every path (0.7.3 did it even for reads and stat(): on the owner's
   board, with an erased root directory, every call made FatFs allocate, write and free a directory cluster - about 300 such
   clusters and ~1900 wear-levelling erases were measured in the backups); a directory is created only before a write.
   (2) Nothing is written, created, renamed or removed unless the boot measured the storage as OK (or FULL, where removing
   files is allowed): a damaged FAT stays exactly as found until an owner-approved repair. Reads work whenever it is mounted.
   (3) The errno of the last failed write is kept so a failure is reported as "Storage full" (ENOSPC) or "Write failed". */
static int s_last_errno;
static bool fs_mounted(void) { bc_stor_facts_t f; hw_storage_facts(&f); return f.mounted; }
static bool fs_may_write(void) { return hw_storage_state() == BC_STOR_OK; }
static bool fs_may_remove(void) { bc_stor_state_t st = hw_storage_state(); return st == BC_STOR_OK || st == BC_STOR_FULL; }
static void full(const char *rel, char *out, size_t cap) { snprintf(out, cap, ROOT "%s", rel); }
static void ensure_dir(const char *p)
{
    char dir[96]; snprintf(dir, sizeof dir, "%s", p);
    char *sl = strrchr(dir, '/');
    if (sl && sl > dir + strlen(ROOT) - 1) {
        *sl = 0;
        struct stat st;
        if (stat(dir, &st) != 0) mkdir(dir, 0775);
    }
}
static bool refuse(const char *what, const char *p)
{
    s_storage_errors++;
    static uint32_t n; if (n++ % 50 == 0) ESP_LOGW(TAG, "%s %s refused: storage %s (nothing is written to a damaged FAT)", what, p, bc_stor_name(hw_storage_state()));
    return false;
}
static void failed(const char *what, const char *p) { s_storage_errors++; s_last_errno = errno; ESP_LOGE(TAG, "%s %s: errno %d", what, p, errno); }

bool plat_file_append(const char *path, const char *data, size_t len, bool sync)
{
    char p[96]; full(path, p, sizeof p);
    if (!fs_may_write()) return refuse("append", p);
    ensure_dir(p);
    FILE *f = fopen(p, "a"); if (!f) { failed("append", p); return false; }
    size_t w = fwrite(data, 1, len, f);
    if (w != len) s_last_errno = errno;
    if (sync) { fflush(f); fsync(fileno(f)); }
    fclose(f);
    if (w != len) s_storage_errors++;
    return w == len;
}

bool plat_file_write(const char *path, const char *data, size_t len)
{
    char p[96], t[100]; full(path, p, sizeof p); snprintf(t, sizeof t, "%s.tmp", p);
    if (!fs_may_write()) return refuse("write", p);
    ensure_dir(p);
    FILE *f = fopen(t, "w"); if (!f) { failed("write", t); return false; }
    size_t w = fwrite(data, 1, len, f); if (w != len) s_last_errno = errno;
    fflush(f); fsync(fileno(f)); fclose(f);
    if (w != len) { s_storage_errors++; unlink(t); return false; }
    unlink(p);
    if (rename(t, p) != 0) { failed("rename", t); return false; }
    return true;
}

/* 0.7.3: in-place write (event-log ring). r+b keeps the rest of the file; created when missing. Flushed to the medium. */
bool plat_file_write_at(const char *path, long off, const void *data, size_t len)
{
    char p[96]; full(path, p, sizeof p);
    if (!fs_may_write()) return refuse("write_at", p);
    ensure_dir(p);
    FILE *f = fopen(p, "r+b"); if (!f) f = fopen(p, "w+b");
    if (!f) { failed("write_at", p); return false; }
    bool ok = fseek(f, off, SEEK_SET) == 0 && fwrite(data, 1, len, f) == len;
    if (!ok) s_last_errno = errno;
    fflush(f); fsync(fileno(f)); fclose(f);
    if (!ok) s_storage_errors++;
    return ok;
}

long plat_file_read_at(const char *path, long off, char *buf, size_t cap)
{
    char p[96]; full(path, p, sizeof p);
    if (!fs_mounted()) return -1;
    FILE *f = fopen(p, "r"); if (!f) return -1;
    if (off && fseek(f, off, SEEK_SET) != 0) { fclose(f); return 0; }
    long n = (long)fread(buf, 1, cap, f); fclose(f); return n;
}
long plat_file_read(const char *path, char *buf, size_t cap) { return plat_file_read_at(path, 0, buf, cap); }
bool plat_file_rename(const char *from, const char *to)
{
    char a[96], b[96]; full(from, a, sizeof a); full(to, b, sizeof b);
    if (!fs_may_write()) return refuse("rename", a);
    ensure_dir(b); unlink(b);
    if (rename(a, b) != 0) { failed("rename", a); return false; }
    return true;
}
bool plat_file_remove(const char *path)
{
    char p[96]; full(path, p, sizeof p);
    if (!fs_may_remove()) return refuse("remove", p);
    return unlink(p) == 0;
}
long plat_file_size(const char *path) { char p[96]; full(path, p, sizeof p); if (!fs_mounted()) return -1; struct stat st; return stat(p, &st) == 0 ? (long)st.st_size : -1; }
bool plat_storage_ok(void) { return hw_storage_state() == BC_STOR_OK; }
bool plat_settings_ok(void) { return hw_settings_ok(); }
bc_stor_state_t plat_storage_state(void) { return hw_storage_state(); }
void plat_storage_facts(bc_stor_facts_t *o) { hw_storage_facts(o); }
bool plat_storage_recheck(void) { return hw_storage_recheck(); }
bool plat_storage_fat_consistent(char *why, size_t cap) { return hw_storage_fat_consistent(why, cap); }
/** 0.7.4: category of the last failed write ("Storage full" for ENOSPC, else "Write failed"); the boot state if writes are refused. */
bc_stor_state_t plat_storage_write_failure(void)
{
    bc_stor_state_t st = hw_storage_state();
    if (st != BC_STOR_OK) return st;
    return s_last_errno == ENOSPC ? BC_STOR_FULL : BC_STOR_WRITE_FAILED;
}

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
int plat_battery_pct(void) { return bc_batt_pct_from_mv(plat_battery_mv()); }   /* ESTIMATE from the cell voltage */
/* The board has no charge-status or VBUS line wired to the ESP32: above 4.25 V the reading cannot be a battery at all.
   The app's inference (app_power / bc_usb_feed) is what the screens show as "USB power likely". */
bool plat_usb_power(void) { return plat_battery_mv() > 4250; }

void plat_backlight(int pct) { hw_backlight_set(pct <= 0 ? 0 : pct < 5 ? 5 : pct); }
void plat_panel_sleep(bool sleep) { hw_panel_sleep(sleep); }
void plat_deep_sleep(int wake_taps)
{
    esp_wifi_stop();                                   /* harmless when the radio was never started */
    vTaskDelay(pdMS_TO_TICKS(100));                    /* let the last log lines and NVS commits finish */
    hw_deep_sleep_touch_wake(wake_taps);               /* never returns */
}
void plat_touch_screen_off(bool off) { hw_touch_keep_awake(off); if (!off) hw_touch_wake_check(); }
void plat_touch_poll(void) { hw_touch_poll(); }
bool plat_device_id(uint8_t out[6]) { return hw_device_id(out); }
void plat_sensors_set_standby(bool standby) { ble_central_set_standby(standby); }
bool plat_woke_from_sleep(void) { return esp_reset_reason() == ESP_RST_DEEPSLEEP; }
uint32_t plat_uptime_s(void) { return (uint32_t)(esp_timer_get_time() / 1000000); }

const char *plat_fw_version(void) { return esp_app_get_description()->version; }
const char *plat_reset_reason(void)
{
    switch (esp_reset_reason()) {
    case ESP_RST_POWERON: return "power-on"; case ESP_RST_SW: return "software"; case ESP_RST_PANIC: return "crash";
    case ESP_RST_INT_WDT: case ESP_RST_TASK_WDT: case ESP_RST_WDT: return "watchdog"; case ESP_RST_BROWNOUT: return "brownout";
    case ESP_RST_USB: return "USB"; case ESP_RST_DEEPSLEEP: return "sleep wake"; default: return "other";
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

static uint32_t nvs_u32(const char *key)
{
    nvs_handle_t h; uint32_t v = 0;
    if (nvs_open("diag", NVS_READONLY, &h) == ESP_OK) { nvs_get_u32(h, key, &v); nvs_close(h); }
    return v;
}

void plat_health(plat_health_t *o)
{
    memset(o, 0, sizeof *o);
    const esp_app_desc_t *d = esp_app_get_description();
    snprintf(o->fw_version, sizeof o->fw_version, "%.23s", d->version);
    /* build stamp = compile date/time + the first 4 bytes of the ELF SHA-256: unique per build, so the physical screen can
       prove which firmware is running (Settings footer and Device Health) */
    snprintf(o->build, sizeof o->build, "%.6s %.5s id %02x%02x%02x%02x", d->date, d->time, d->app_elf_sha256[0], d->app_elf_sha256[1], d->app_elf_sha256[2], d->app_elf_sha256[3]);
    o->uptime_s = (uint32_t)(esp_timer_get_time() / 1000000);
    snprintf(o->reset_reason, sizeof o->reset_reason, "%s", plat_reset_reason());
    o->boot_count = g_selftest.boot_count;
    o->crash_total = nvs_u32("crashes"); o->safe_mode_entries = nvs_u32("safemode"); o->crash_consecutive = g_crash_consecutive;
    o->storage_errors = s_storage_errors; o->profile_save_errors = s_profile_errors;
    o->heap_free_k = (long)(heap_caps_get_free_size(MALLOC_CAP_INTERNAL) / 1024);
    o->heap_min_k = (long)(heap_caps_get_minimum_free_size(MALLOC_CAP_INTERNAL) / 1024);
    o->psram_free_k = (long)(heap_caps_get_free_size(MALLOC_CAP_SPIRAM) / 1024);
    o->psram_total_k = (long)(heap_caps_get_total_size(MALLOC_CAP_SPIRAM) / 1024);
    uint32_t fsz = 0; esp_flash_get_size(NULL, &fsz); o->flash_total_k = (long)(fsz / 1024);
    const esp_partition_t *run = esp_ota_get_running_partition();
    o->app_slot_k = run ? (long)(run->size / 1024) : -1;
    o->app_used_k = -1;
    uint64_t tot = 0, fre = 0;
    if (esp_vfs_fat_info("/data", &tot, &fre) == ESP_OK) { o->storage_total_k = (long)(tot / 1024); o->storage_free_k = (long)(fre / 1024); }
    else o->storage_total_k = o->storage_free_k = -1;
    o->battery_mv = plat_battery_mv(); o->battery_pct = plat_battery_pct(); o->usb_power = plat_usb_power();
    o->ble_ready = ble_central_ready(); o->ble_scanning = ble_central_scanning(); o->ble_devices_seen = ble_central_devices_seen();
    { plat_wifi_status_t w; plat_wifi_status(&w); o->wifi_on = w.state != PLAT_WIFI_OFF; } o->wifi_networks = plat_wifi_scan_count();
    { plat_phone_status_t ph; plat_phone_status(&ph); o->phone_state = ph.state; o->phone_bonded = ph.bonded; }
    o->display_ok = g_selftest.display == HW_PASS; o->touch_ok = g_selftest.touch == HW_PASS;
    o->imu_ok = g_selftest.imu == HW_PASS; o->storage_ok = g_selftest.storage == HW_PASS;
}

uint8_t plat_crash_run_update(bc_reset_t reset)
{
    nvs_handle_t h; uint8_t v = 0;
    if (nvs_open("bootrec", NVS_READWRITE, &h) != ESP_OK) return 0;
    nvs_get_u8(h, "crashrun", &v);
    uint8_t n = bc_boot_next_run(v, reset);
    if (n != v) { if (nvs_set_u8(h, "crashrun", n) != ESP_OK || nvs_commit(h) != ESP_OK) n = 0; }   /* one write only when it changes */
    nvs_close(h);
    return n;
}
void plat_flash_usage(uint32_t *slot_kb, uint32_t *used_kb, uint16_t *nvs_used, uint16_t *nvs_free)
{
    *slot_kb = *used_kb = 0; *nvs_used = *nvs_free = 0;
    const esp_partition_t *p = esp_ota_get_running_partition();
    if (p) {
        *slot_kb = (uint32_t)(p->size / 1024);
        static uint32_t s_img_len;                          /* the image does not change while it runs: read once */
        if (!s_img_len) {
            esp_partition_pos_t pos = { .offset = p->address, .size = p->size }; esp_image_metadata_t md;
            if (esp_image_get_metadata(&pos, &md) == ESP_OK) s_img_len = md.image_len;
        }
        *used_kb = (s_img_len + 1023) / 1024;
    }
    nvs_stats_t st;
    if (nvs_get_stats(NULL, &st) == ESP_OK) { *nvs_used = (uint16_t)(st.used_entries > 0xFFFF ? 0xFFFF : st.used_entries); *nvs_free = (uint16_t)(st.free_entries > 0xFFFF ? 0xFFFF : st.free_entries); }
}

void *plat_alloc_ext(size_t n)
{
    void *p = heap_caps_calloc(1, n, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    return p ? p : heap_caps_calloc(1, n, MALLOC_CAP_8BIT);
}

void plat_export_report(const char *text)
{
    /* plain printf (not the log macros) so long lines are never cut; the PC log reader records it */
    printf("\n===== BIKE COMPUTER DIAGNOSTIC REPORT BEGIN =====\n%s\n===== BIKE COMPUTER DIAGNOSTIC REPORT END =====\n", text);
    fflush(stdout);
    plat_file_write("diag/report.txt", text, strlen(text));
}
