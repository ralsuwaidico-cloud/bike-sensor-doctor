/*
 * Crash evidence on the Waveshare (firmware 0.7.3): RTC-memory state for the boot modes, a 2 KB RTC ring of the last log
 * lines (survives the panic reset, read at the next boot), the core dump summary from the flash 'coredump' partition
 * (ESP-IDF ELF core dump with CRC32, docs/PARTITIONS_0.7.3.md), task stack head-room and heap numbers for the health monitor.
 * Platform side of plat.h "0.7.3 crash evidence"; the reports themselves are built in app_diag.c.
 */
#include "plat.h"
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "esp_attr.h"
#include "esp_log.h"
#include "esp_system.h"
#include "esp_app_desc.h"
#include "esp_heap_caps.h"
#include "esp_partition.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "nvs.h"
#include "sdkconfig.h"
#if CONFIG_ESP_COREDUMP_ENABLE_TO_FLASH
#include "esp_core_dump.h"
#endif
#include "ble_central.h"
#include "diag_esp.h"

static const char *TAG = "diag";

/* ---- boot-mode state (bc_boot.h) */
RTC_NOINIT_ATTR static bc_boot_rtc_t s_boot;
bc_boot_rtc_t *plat_boot_rtc(void) { return &s_boot; }

/* ---- RTC log ring: every log line is also appended here; the previous boot's ring is saved before the first new line */
#define RING 2048
typedef struct { uint32_t magic, head, used; char b[RING]; } logring_t;
RTC_NOINIT_ATTR static logring_t s_ring;
#define RING_MAGIC 0x10C0FFEEu
static char *s_prev; static size_t s_prev_n;          /* the tail of the run that ended with the last reset */
static portMUX_TYPE s_rmux = portMUX_INITIALIZER_UNLOCKED;
static vprintf_like_t s_orig;

static int log_hook(const char *fmt, va_list ap)
{
    char line[192];
    int n = vsnprintf(line, sizeof line, fmt, ap);   /* one formatting pass (the default vprintf would format again) */
    if (n < 0) return n;
    size_t len = (size_t)n < sizeof line ? (size_t)n : sizeof line - 1;
    portENTER_CRITICAL(&s_rmux);
    for (size_t i = 0; i < len; i++) { s_ring.b[s_ring.head] = line[i]; s_ring.head = (s_ring.head + 1) % RING; }
    s_ring.used = s_ring.used + len > RING ? RING : s_ring.used + (uint32_t)len;
    portEXIT_CRITICAL(&s_rmux);
    fwrite(line, 1, len, stdout);
    return n;
}

void diag_esp_early_init(void)
{
    if (s_ring.magic == RING_MAGIC && s_ring.head < RING && s_ring.used <= RING) {
        s_prev = malloc(RING + 1);
        if (s_prev) {
            size_t start = (s_ring.head + RING - s_ring.used) % RING;
            for (size_t i = 0; i < s_ring.used; i++) s_prev[i] = s_ring.b[(start + i) % RING];
            s_prev_n = s_ring.used; s_prev[s_prev_n] = 0;
            /* start at a line boundary (the oldest line may be cut by the ring) */
            char *nl = memchr(s_prev, '\n', s_prev_n);
            if (nl && s_ring.used == RING) { size_t cut = (size_t)(nl + 1 - s_prev); memmove(s_prev, nl + 1, s_prev_n - cut + 1); s_prev_n -= cut; }
            for (size_t i = 0; i < s_prev_n; i++) if ((unsigned char)s_prev[i] == 0x1B) s_prev[i] = ' ';   /* ANSI colour codes */
        }
    }
    memset(&s_ring, 0, sizeof s_ring); s_ring.magic = RING_MAGIC;
    s_orig = esp_log_set_vprintf(log_hook);
}

size_t plat_log_tail(char *buf, size_t cap)
{
    if (!cap) return 0;
    buf[0] = 0;
    if (!s_prev) return 0;
    size_t n = s_prev_n < cap - 1 ? s_prev_n : cap - 1;
    const char *src = s_prev + (s_prev_n - n);               /* the newest part if it does not fit */
    memcpy(buf, src, n); buf[n] = 0;
    /* colour sequences "[0;32m" left after the ESC byte was blanked */
    for (char *p = buf; (p = strstr(p, " [0")) != NULL;) { char *m = strchr(p, 'm'); if (m && m - p < 8) memmove(p, m + 1, strlen(m + 1) + 1); else p++; }
    bc_diag_redact(buf);
    return strlen(buf);
}

/* ---- reset reason */
bc_reset_t plat_reset_kind(void)
{
    switch (esp_reset_reason()) {
    case ESP_RST_POWERON: return BC_RST_POWERON; case ESP_RST_SW: return BC_RST_SW; case ESP_RST_PANIC: return BC_RST_PANIC;
    case ESP_RST_INT_WDT: case ESP_RST_TASK_WDT: case ESP_RST_WDT: return BC_RST_WDT; case ESP_RST_BROWNOUT: return BC_RST_BROWNOUT;
    case ESP_RST_DEEPSLEEP: return BC_RST_DEEPSLEEP; default: return BC_RST_OTHER;
    }
}

/* ---- core dump (flash partition 'coredump', ELF + CRC32) */
bool plat_crash_info(plat_crash_t *o)
{
    memset(o, 0, sizeof *o);
#if CONFIG_ESP_COREDUMP_ENABLE_TO_FLASH && CONFIG_ESP_COREDUMP_DATA_FORMAT_ELF
    if (esp_core_dump_image_check() != ESP_OK) return false;
    esp_core_dump_summary_t *s = malloc(sizeof *s);
    if (!s) return false;
    if (esp_core_dump_get_summary(s) == ESP_OK) {
        o->have = true;
        snprintf(o->task, sizeof o->task, "%.15s", s->exc_task);
        o->pc = s->exc_pc; o->exccause = s->ex_info.exc_cause; o->excvaddr = s->ex_info.exc_vaddr;
        o->bt_depth = (uint8_t)(s->exc_bt_info.depth > 16 ? 16 : s->exc_bt_info.depth); o->bt_corrupted = s->exc_bt_info.corrupted;
        memcpy(o->bt, s->exc_bt_info.bt, sizeof o->bt);
        if (esp_core_dump_get_panic_reason(o->reason, sizeof o->reason) != ESP_OK) o->reason[0] = 0;
        bc_diag_redact(o->reason);
    }
    free(s);
#endif
    return o->have;
}

void plat_crash_consumed(uint32_t report_id)
{
#if CONFIG_ESP_COREDUMP_ENABLE_TO_FLASH
    size_t addr = 0, size = 0; bool copied = false;
    if (esp_core_dump_image_get(&addr, &size) == ESP_OK && size > 0 && size <= 64 * 1024) {
        const esp_partition_t *p = esp_partition_find_first(ESP_PARTITION_TYPE_DATA, ESP_PARTITION_SUBTYPE_DATA_COREDUMP, NULL);
        uint8_t *buf = malloc(4096);
        if (p && buf) {
            char path[32]; snprintf(path, sizeof path, "diag/core-%06lu.elf", (unsigned long)report_id);
            bool ok = true;
            for (size_t off = 0; off < size && ok; off += 4096) {
                size_t n = size - off < 4096 ? size - off : 4096;
                ok = esp_partition_read(p, addr - p->address + off, buf, n) == ESP_OK && plat_file_write_at(path, (long)off, buf, n);
            }
            ESP_LOGI(TAG, "core dump (%u bytes) %s diag/core-%06lu.elf", (unsigned)size, ok ? "kept as" : "could NOT be copied to", (unsigned long)report_id);
            copied = ok;
        }
        free(buf);
    }
    /* 0.7.4: the partition is freed ONLY when the raw dump is safely on the FAT (0.7.3 erased it even when the copy failed,
       losing the only full crash evidence). Kept, it is still read by READ-BOARD-STATE and by the next boot's report. */
    if (copied) esp_core_dump_image_erase();
    else ESP_LOGW(TAG, "core dump kept in the 'coredump' partition (copy to the FAT failed or no dump size)");
#else
    (void)report_id;
#endif
}

/* ---- subsystems disabled after a crash: NVS "boot", valid only for the firmware that recorded them */
static uint32_t fw_id(void) { const uint8_t *s = esp_app_get_description()->app_elf_sha256; return (uint32_t)s[0] | ((uint32_t)s[1] << 8) | ((uint32_t)s[2] << 16) | ((uint32_t)s[3] << 24); }
uint16_t plat_boot_skip_load(void)
{
    nvs_handle_t h; uint16_t v = 0; uint32_t f = 0;
    if (nvs_open("boot", NVS_READONLY, &h) != ESP_OK) return 0;
    if (nvs_get_u16(h, "skip", &v) != ESP_OK || nvs_get_u32(h, "skipfw", &f) != ESP_OK || f != fw_id()) v = 0;   /* new firmware: start clean */
    nvs_close(h);
    return v;
}
void plat_boot_skip_save(uint16_t skip)
{
    nvs_handle_t h;
    if (nvs_open("boot", NVS_READWRITE, &h) != ESP_OK) return;
    nvs_set_u16(h, "skip", skip); nvs_set_u32(h, "skipfw", fw_id()); nvs_commit(h); nvs_close(h);
}
uint32_t plat_crash_total(void) { nvs_handle_t h; uint32_t v = 0; if (nvs_open("diag", NVS_READONLY, &h) == ESP_OK) { nvs_get_u32(h, "crashes", &v); nvs_close(h); } return v; }

/* ---- tasks and heap */
int plat_tasks(bc_diag_task_t *out, int max)
{
    static const char *const N[] = { "taskLVGL", "nimble_host", "ble_mgr", "esp_timer", "main", "wifi_mgr", "btController", "tiT", "IDLE0", "IDLE1", "ipc0", "ipc1" };
    int n = 0;
    for (size_t i = 0; i < sizeof N / sizeof *N && n < max; i++) {
        TaskHandle_t t = xTaskGetHandle(N[i]); if (!t) continue;
        snprintf(out[n].name, sizeof out[n].name, "%s", N[i]); out[n].stack_free = (uint32_t)uxTaskGetStackHighWaterMark(t); n++;
    }
    return n;
}
void plat_heap(uint32_t *fr, uint32_t *mn, uint32_t *lg, uint32_t *ps)
{
    *fr = (uint32_t)heap_caps_get_free_size(MALLOC_CAP_INTERNAL); *mn = (uint32_t)heap_caps_get_minimum_free_size(MALLOC_CAP_INTERNAL);
    *lg = (uint32_t)heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL); *ps = (uint32_t)heap_caps_get_free_size(MALLOC_CAP_SPIRAM);
}
void plat_build_ids(char build[32], char sha[65])
{
    const esp_app_desc_t *d = esp_app_get_description();
    snprintf(build, 32, "%.11s %.8s", d->date, d->time);
    for (int i = 0; i < 32; i++) snprintf(sha + 2 * i, 3, "%02x", d->app_elf_sha256[i]);
}

/* ---- 0.7.4 crash partition status (Device Health, reports, BLE storage status) */
bc_crashpart_t plat_crash_partition(uint32_t *dump_bytes)
{
    if (dump_bytes) *dump_bytes = 0;
    const esp_partition_t *p = esp_partition_find_first(ESP_PARTITION_TYPE_DATA, ESP_PARTITION_SUBTYPE_DATA_COREDUMP, NULL);
    if (!p) return BC_CRASHPART_MISSING;
#if CONFIG_ESP_COREDUMP_ENABLE_TO_FLASH
    size_t addr = 0, size = 0;
    if (esp_core_dump_image_get(&addr, &size) != ESP_OK || size == 0 || size > p->size) return BC_CRASHPART_EMPTY;
    if (dump_bytes) *dump_bytes = (uint32_t)size;
    return esp_core_dump_image_check() == ESP_OK ? BC_CRASHPART_DUMP : BC_CRASHPART_BAD;
#else
    return BC_CRASHPART_EMPTY;
#endif
}

/* ---- phone link alone (recovery SEND LOGS) and per-sensor disable */
static bool s_ble_started;
static bool s_bt_disabled; static char s_bt_disabled_why[40];
void diag_esp_ble_started(void) { s_ble_started = true; }
void diag_esp_bt_disabled(const char *why) { s_bt_disabled = true; snprintf(s_bt_disabled_why, sizeof s_bt_disabled_why, "%s", why ? why : "disabled"); }
bool plat_bt_unavailable(char *reason, size_t cap)
{
    const char *r = NULL;
    if (s_bt_disabled) r = s_bt_disabled_why;
    else if (ble_central_unavailable()) r = ble_central_init_info()->reason;
    if (r && reason && cap) snprintf(reason, cap, "%s", r);
    return r != NULL;
}
void plat_phone_only_start(void)
{
    /* 0.7.4: never restart what crashed - the Bluetooth stack / phone link disabled after crashes stays off for SEND LOGS too */
    uint16_t sk = (uint16_t)(plat_boot_rtc()->skip | plat_boot_skip_load());
    if (!s_ble_started && (sk & (BC_SS_BIT(BC_SS_BTSTACK) | BC_SS_BIT(BC_SS_PHONE)))) { diag_esp_bt_disabled("off after crashes"); ESP_LOGW(TAG, "recovery: SEND LOGS - Bluetooth stays off (disabled after crashes)"); return; }
    if (!s_ble_started) {
        s_ble_started = true;
        if (!ble_central_start(false)) { ESP_LOGE(TAG, "recovery: phone link could not start - Bluetooth unavailable (%s)", ble_central_init_info()->reason); return; }
        ESP_LOGI(TAG, "recovery: phone link started alone (no sensors, no Wi-Fi)");
    }
    if (plat_bt_unavailable(NULL, 0)) return;
    plat_phone_set_enabled(true);                    /* this boot only: the profile is not changed */
}
void plat_sensor_set_disabled(plat_sens_kind_t k, bool disabled) { ble_central_set_disabled(k, disabled); }
