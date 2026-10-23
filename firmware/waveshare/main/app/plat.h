/*
 * Platform interface. The app logic (app.c) and every screen (ui_*.c) use ONLY this header, bc_core and LVGL, so the
 * same code runs on the Waveshare (plat_esp.c) and on the PC preview/test harness (test/sim/plat_host.c).
 *
 * Sensor sources are kinds, not radios, so future hardware slots in without touching the screens:
 *   PLAT_SENS_POWER (BLE today; ANT+ later), PLAT_SENS_HR (BLE today; ANT+ later), PLAT_SENS_SPEED (none on this board —
 *   reserved for a GPS-equipped Waveshare model or a speed sensor). This 1.28" board has NO GPS: speed/distance are
 *   reported as unsupported, never estimated.
 */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum { PLAT_SENS_POWER = 0, PLAT_SENS_HR, PLAT_SENS_SPEED, PLAT_SENS_KINDS } plat_sens_kind_t;
typedef enum { PLAT_LINK_OFF = 0, PLAT_LINK_NOT_PAIRED, PLAT_LINK_SEARCHING, PLAT_LINK_CONNECTING, PLAT_LINK_CONNECTED,
               PLAT_LINK_RETRY, PLAT_LINK_UNSUPPORTED } plat_link_t;

typedef struct {
    plat_link_t link;
    char name[20];
    int rssi;              /* dBm, 0 = unknown */
    uint32_t packets;
    uint32_t age_ms;       /* since the last packet; UINT32_MAX = never */
    uint32_t reconnects;
} plat_link_info_t;

/** Raw live values from the real sensors (already freshness-checked: stale = absent). */
typedef struct {
    bool power_ok; int watts;
    bool cad_ok; int rpm; bool backwards;
    bool hr_ok; int bpm;
    plat_link_info_t link[PLAT_SENS_KINDS];
} plat_sensors_t;

uint32_t plat_ms(void);
void plat_sensors(plat_sensors_t *out);

/* pairing: scan for devices of one kind; results while scanning */
typedef struct { uint8_t mac[6]; uint8_t addr_type; char name[20]; int rssi; } plat_found_t;
void plat_scan_begin(plat_sens_kind_t kind);
int plat_scan_results(plat_found_t *out, int max);
void plat_scan_end(void);
/** Use this device from now on (also stored in the profile by the caller). Pass NULL to forget the pairing. */
void plat_pair(plat_sens_kind_t kind, const plat_found_t *dev);

/* storage: the profile is a small text blob kept power-loss safe (NVS on the device) */
bool plat_profile_load(char *buf, size_t cap);
bool plat_profile_save(const char *txt);
/* files on the ride storage (FAT on the device). Paths are relative, e.g. "rides/history.txt". */
bool plat_file_append(const char *path, const char *data, size_t len, bool sync);
bool plat_file_write(const char *path, const char *data, size_t len);   /* atomic: write temp + rename */
long plat_file_read(const char *path, char *buf, size_t cap);           /* bytes read, -1 if missing */
long plat_file_read_at(const char *path, long offset, char *buf, size_t cap);
bool plat_file_rename(const char *from, const char *to);
bool plat_file_remove(const char *path);
bool plat_storage_ok(void);

/* device */
int plat_battery_pct(void);            /* -1 unknown */
int plat_battery_mv(void);
bool plat_usb_power(void);             /* best guess: voltage above full-charge level */
void plat_backlight(int pct);
void plat_wifi_enable(bool on);
int plat_wifi_scan_count(void);        /* networks seen by the last scan, -1 if not scanned */
const char *plat_fw_version(void);
const char *plat_reset_reason(void);
uint32_t plat_boot_count(void);
void plat_restart(void);
/** Multi-line self-test text for the Diagnostics screen (LVGL recolor syntax allowed). */
void plat_selftest_text(char *buf, size_t cap);
void plat_mem_text(char *buf, size_t cap);
/** One line for the serial log. */
void plat_log(const char *line);

#ifdef __cplusplus
}
#endif
