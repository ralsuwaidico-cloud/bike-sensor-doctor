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
#include "bc_link.h"

#ifdef __cplusplus
extern "C" {
#endif

/* PLAT_SENS_SPEED = the phone's GPS as seen by the app (never a radio of this board). PLAT_SENS_CSC (0.6.0) = an optional
 * BLE speed/cadence sensor (service 0x1816) paired to the board directly. */
typedef enum { PLAT_SENS_POWER = 0, PLAT_SENS_HR, PLAT_SENS_SPEED, PLAT_SENS_CSC, PLAT_SENS_KINDS } plat_sens_kind_t;
#define PLAT_SENS_ANY PLAT_SENS_KINDS   /* plat_scan_begin(PLAT_SENS_ANY): list every nearby BLE device (Connections > Other Bluetooth) */
typedef enum { PLAT_LINK_OFF = 0, PLAT_LINK_NOT_PAIRED, PLAT_LINK_SEARCHING, PLAT_LINK_CONNECTING, PLAT_LINK_CONNECTED,
               PLAT_LINK_RETRY, PLAT_LINK_UNSUPPORTED, PLAT_LINK_STALE /* source connected but its last value is too old to show */ } plat_link_t;

typedef struct {
    plat_link_t link;
    char name[20];
    int rssi;              /* dBm, 0 = unknown */
    uint32_t packets;
    uint32_t age_ms;       /* since the last packet of any kind; UINT32_MAX = never */
    uint32_t valid_age_ms; /* since the last VALID (decoded + plausible) packet; UINT32_MAX = never */
    uint32_t rejected;     /* packets rejected as short or implausible (never shown as data) */
    uint32_t reconnects;
    uint32_t gaps;         /* times valid data paused > 2.5 s while connected (to spot radio interference) */
} plat_link_info_t;

/** Raw live values from the real sensors (already freshness-checked: stale = absent). */
typedef struct {
    bool power_ok; int watts;
    bool cad_ok; int rpm; bool backwards;
    bool hr_ok; int bpm;
    /* 0.6.0 CSC sensor: cadence (crank) and speed (wheel x circumference set with plat_csc_wheel_mm); 0 = coasting */
    bool csc_cad_ok; int csc_rpm; bool csc_speed_ok; int csc_speed_dmh; bool csc_has_wheel, csc_has_crank;
    plat_link_info_t link[PLAT_SENS_KINDS];
} plat_sensors_t;
void plat_csc_wheel_mm(uint16_t mm);

uint32_t plat_ms(void);
void plat_sensors(plat_sensors_t *out);

/* pairing: scan for devices of one kind; results while scanning */
#define PLAT_SVC_HR 0x01       /* 0x180D heart rate */
#define PLAT_SVC_POWER 0x02    /* 0x1818 cycling power (and the XDS name) */
#define PLAT_SVC_CSC 0x04      /* 0x1816 speed / cadence */
#define PLAT_SVC_BATTERY 0x08  /* 0x180F battery */
#define PLAT_SVC_FTMS 0x10     /* 0x1826 fitness machine (trainer): recognised, not supported */
typedef struct { uint8_t mac[6]; uint8_t addr_type; char name[20]; int rssi; uint16_t svcs; /* PLAT_SVC_* seen in the advertisement */ } plat_found_t;
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
long plat_file_size(const char *path);                                  /* -1 if missing */
bool plat_storage_ok(void);

/* device */
int plat_battery_pct(void);            /* -1 unknown; an ESTIMATE from the cell voltage (bc_batt_pct_from_mv) */
int plat_battery_mv(void);             /* filtered measurement, -1 unknown */
bool plat_usb_power(void);             /* raw hint only: voltage above any battery level (> 4.25 V). The app's inference (app_power) is what screens show */
void plat_backlight(int pct);          /* 0 = off (screen-off mode), 5..100 = brightness */
/* ---- power (firmware 0.5.0). The board has no power switch, no charge-status line and no VBUS sense; see docs/POWER_FEASIBILITY.md. */
void plat_panel_sleep(bool sleep);     /* display controller sleep-in / wake (backlight is separate) */
/** 0.6.0: the screen is off and the touch layer must catch every quick tap: the touch controller is kept awake (no first-touch
 *  loss after its auto-sleep) and polled faster. Called with false when the screen is back on. Harness: bookkeeping only. */
void plat_touch_screen_off(bool off);
/** Deep sleep with touch wake (TP_INT, GPIO5) + RESET + USB. Does not return on the device; the host harness records it
 *  and the next sim boot() plays the wake. NOT hardware-verified until the 0.5.0 device tests. */
void plat_deep_sleep(int wake_taps);   /* wake_taps 1..3: the waking touch counts as tap 1 (1 = any touch wakes) */
bool plat_woke_from_sleep(void);       /* this boot is a wake from deep sleep (the chip, not necessarily a confirmed triple tap) */
uint32_t plat_uptime_s(void);
/* ---- Wi-Fi manager (optional; the device is fully usable offline). Every call returns at once: the work happens in
 * a background task, the UI polls plat_wifi_status(). During a ride the manager never scans or retries on its own. */
typedef enum { PLAT_WIFI_OFF = 0, PLAT_WIFI_IDLE, PLAT_WIFI_SCANNING, PLAT_WIFI_CONNECTING, PLAT_WIFI_CONNECTED, PLAT_WIFI_FAILED } plat_wifi_state_t;
typedef enum { PLAT_WIFI_ERR_NONE = 0, PLAT_WIFI_ERR_WRONG_PASSWORD, PLAT_WIFI_ERR_NOT_FOUND, PLAT_WIFI_ERR_TIMEOUT, PLAT_WIFI_ERR_NO_IP,
               PLAT_WIFI_ERR_LOST, PLAT_WIFI_ERR_OTHER } plat_wifi_err_t;
#define PLAT_WIFI_MAX_SAVED 5
typedef struct { char ssid[33]; int rssi; bool secured; bool saved; uint8_t channel; } plat_wifi_ap_t;
typedef struct {
    plat_wifi_state_t state;
    plat_wifi_err_t err;           /* why the last attempt failed (kept until the next attempt) */
    char ssid[33];                 /* network connected to / being joined / that failed */
    int rssi;                      /* dBm while connected, 0 otherwise */
    char ip[16];                   /* "" until an address was obtained */
    bool scan_done;                /* results available from the last scan */
    uint8_t internet;              /* while CONNECTED: 0 not checked yet, 1 DNS lookup succeeded, 2 failed ("no internet") */
    uint32_t scans, connects, failures;
} plat_wifi_status_t;
void plat_wifi_set_enabled(bool on);                 /* radio on/off; on = reconnect to saved networks automatically */
void plat_wifi_scan(void);
int plat_wifi_results(plat_wifi_ap_t *out, int max); /* strongest first, one entry per name */
void plat_wifi_connect(const char *ssid, const char *password, bool save);  /* password NULL = use the saved one */
void plat_wifi_disconnect(void);                     /* stays on, no automatic reconnect until the next connect / restart */
void plat_wifi_forget(const char *ssid);
void plat_wifi_save(const char *ssid, const char *password);   /* store without connecting (phone provisioning, "save only") */
int plat_wifi_saved(char ssids[][33], int max);
void plat_wifi_status(plat_wifi_status_t *out);
void plat_wifi_set_quiet(bool riding);               /* ride in progress: no scans or retries */
int plat_wifi_scan_count(void);                      /* networks seen by the last scan, -1 if never scanned */
/* ---- phone link: BLE peripheral "BikeComputer Link" (protocol in bc_link.h / docs/BLE_LINK_PROTOCOL.md). Optional: the
 * device is fully usable without a phone. Pairing = LE Secure Connections with a 6-digit code shown on this screen; the
 * phone is remembered (bonded) so later connections need no code. A phone disconnect never touches the ride recording. */
typedef enum { PLAT_PHONE_OFF = 0, PLAT_PHONE_ADVERTISING, PLAT_PHONE_CONNECTED /* link up, not yet authenticated */,
               PLAT_PHONE_PAIRING /* passkey on screen */, PLAT_PHONE_READY /* encrypted with a remembered phone */ } plat_phone_state_t;
typedef struct {
    plat_phone_state_t state;
    bool bonded;                      /* a phone is remembered */
    int rssi;                         /* dBm while connected, 0 otherwise */
    uint32_t passkey;                 /* code to show while PAIRING, 0 otherwise */
    uint32_t connects, rx_msgs, rx_rejected, tx_msgs;
    uint32_t last_rx_age_ms;          /* UINT32_MAX = never */
    uint8_t phone_batt, watch_batt;   /* 0xFF unknown */
} plat_phone_status_t;
void plat_phone_set_enabled(bool on);
void plat_phone_status(plat_phone_status_t *out);
void plat_phone_forget(void);         /* forget every remembered phone and drop the connection */
void plat_phone_disconnect(void);
/** Latest inputs received from the phone (validated by bc_link). rx_ms = plat_ms() at reception, 0 = never received. */
typedef struct {
    struct { bc_in_gps_t v; uint32_t rx_ms; } gps;
    struct { bc_in_hr_t v; uint32_t rx_ms; } hr;
    struct { bc_in_time_t v; uint32_t rx_ms; } time;
    struct { bc_in_weather_t v; uint32_t rx_ms; } weather;
} plat_phone_in_t;
void plat_phone_inputs(plat_phone_in_t *out);
bool plat_phone_take_ctrl(bc_ctrl_req_t *out);               /* pending ride-control request from the phone */
void plat_phone_ctrl_respond(const bc_ctrl_resp_t *resp);
void plat_phone_publish_live(const bc_live_t *live);         /* once per second from the app; sent when the phone listens */
/* 0.6.0 phone services (ride-history sync, Wi-Fi provisioning, profile + settings sync — app_psvc). The transport only
 * queues bytes: every write the phone made on Control (other than CTRL_REQ) or Sync is handed to the app task here,
 * and the app's replies go back as notifications on the same characteristic. chr: 0 = Control, 1 = Sync, 2 = Events (notify only). */
int plat_phone_take_svc(uint8_t *chr, uint8_t *buf, size_t cap);   /* bytes copied, 0 = nothing pending */
bool plat_phone_notify_svc(uint8_t chr, const uint8_t *buf, size_t n);   /* false = transport queue full, try again next tick */
/** Connected standby (screen off, no ride): keep the link, advertise slowly (~1 s) when no phone is connected. */
void plat_phone_set_standby(bool standby);
/** Connected standby for the sensor side: no scanning for paired sensors; existing connections are kept. */
void plat_sensors_set_standby(bool standby);

const char *plat_fw_version(void);
bool plat_device_id(uint8_t out[6]);   /* the board's Bluetooth address (INFO tag 07); false when unknown */
const char *plat_reset_reason(void);
uint32_t plat_boot_count(void);
void plat_restart(void);
/** Multi-line self-test text for the Diagnostics screen (LVGL recolor syntax allowed). */
void plat_selftest_text(char *buf, size_t cap);
void plat_mem_text(char *buf, size_t cap);
/** Device health for Settings > Diagnostics > Device Health. Numbers the platform cannot know are -1 / empty. */
typedef struct {
    char fw_version[24], build[32];
    uint32_t uptime_s;
    char reset_reason[24];
    uint32_t boot_count, crash_total, crash_consecutive, safe_mode_entries, storage_errors, profile_save_errors;
    long heap_free_k, heap_min_k, psram_free_k, psram_total_k;
    long flash_total_k, app_used_k, app_slot_k, storage_free_k, storage_total_k;
    int battery_mv, battery_pct; bool usb_power;
    bool ble_ready, ble_scanning; uint32_t ble_devices_seen;
    bool wifi_on; int wifi_networks;
    int phone_state; bool phone_bonded;
    bool display_ok, touch_ok, imu_ok, storage_ok;
} plat_health_t;
void plat_health(plat_health_t *out);
/** Send a multi-line diagnostic report to the PC (serial) and keep a copy on the device (diag/report.txt). */
void plat_export_report(const char *text);
/** One line for the serial log. */
void plat_log(const char *line);

#ifdef __cplusplus
}
#endif
