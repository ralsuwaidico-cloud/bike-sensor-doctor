/*
 * Phone services (firmware 0.6.0): the board-side logic of BikeComputer Link 1.1 ride-history sync (Sync characteristic
 * 0006) and 1.2 Wi-Fi provisioning, athlete-profile sync and device settings (Control characteristic 0005).
 * Portable: uses only plat.h and bc_core, so the device (ble_link.c queues the bytes) and the PC harness run the same code.
 *
 * Model: the transport queues every message the phone wrote; app_psvc_pump() (app task, every 250 ms) takes them with
 * plat_phone_take_svc(), applies them, and sends the replies with plat_phone_notify_svc(), a few per pump so a 50-ride
 * sync takes about two seconds without starving the live stream.
 *
 * Rules
 *  - nothing here touches the ride, the sensors or the screen; Wi-Fi work is posted to the background manager;
 *  - Wi-Fi passwords are copied straight into plat_wifi_connect/save and wiped; never logged, never echoed back;
 *  - a scan request during a ride is refused (BUSY) so the power meter and the recording keep the radio;
 *  - history is streamed line by line (bc_summary_from_line) with its own buffer: the UI's history reader is untouched;
 *  - PROFILE_SET is applied only with a version above the stored one and never touches ride history, journal, sensor
 *    pairings, phone bonds, calibration or the Wi-Fi store; the board keeps working alone with the last synced profile.
 */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "bc_link.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum { APP_PSVC_CTRL = 0, APP_PSVC_SYNC = 1, APP_PSVC_EVENTS = 2 } app_psvc_chr_t;

void app_psvc_init(void);
/** Take queued phone writes, apply them, send what is due. Call every ~250 ms from the app task. */
void app_psvc_pump(uint32_t now_ms);
/** A message written by an encrypted phone (also usable directly by tests). False = not a service message or malformed. */
bool app_psvc_write(app_psvc_chr_t chr, const uint8_t *msg, size_t n, uint32_t now_ms);
/** Next notification to send (0 = nothing right now). *chr says on which characteristic. */
size_t app_psvc_next(app_psvc_chr_t *chr, uint8_t *buf, size_t cap, uint32_t now_ms);
/** The phone left: cancel a running sync and the status watch. */
void app_psvc_on_disconnect(void);
/** 0.7.0: profile-sync state for the PHONE screen and the LINK_DIAG event. */
typedef enum { APP_PSYNC_DEVICE_ONLY = 0, APP_PSYNC_SYNCED = 1, APP_PSYNC_PENDING = 2 /* phone connected, nothing applied yet this connection */, APP_PSYNC_FAILED = 3 /* last PROFILE_SET rejected */ } app_psync_state_t;
app_psync_state_t app_psvc_sync_state(void);
/** Last SYNC_END (for a read of the Sync characteristic): 0 when none was sent yet. */
size_t app_psvc_last_sync_end(uint8_t *buf, size_t cap);
/** The board's current athlete profile / settings as the protocol carries them (also used by the UI "Sync status" text). */
void app_psvc_profile_msg(bc_profile_msg_t *out);
void app_psvc_settings_msg(bc_settings_msg_t *out);
/** Counters for Device Health / tests. */
typedef struct { uint32_t wifi_msgs, wifi_rejected, scans, sets, forgets, status_sent, sync_reqs, rides_sent,
                 profile_gets, profile_sets, profile_applied, profile_rejected, settings_gets, settings_sets, settings_applied, settings_rejected;
                 /* 0.6.0 Connections > Device sync: plat_ms() of the last completed action (0 = never this boot), last ride id streamed */
                 uint32_t last_sync_ms, last_profile_ms, last_settings_ms; uint16_t last_synced_id; bool synced_all;
                 bool sync_active, status_watch;
                 uint32_t sensor_diags;   /* 0.7.2 SENSOR_DIAG events sent */ } app_psvc_stats_t;
void app_psvc_stats(app_psvc_stats_t *out);

#ifdef __cplusplus
}
#endif
