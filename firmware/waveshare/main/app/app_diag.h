/*
 * Diagnostics in the app layer (firmware 0.7.3): persistent event log, continuous health monitor, crash / recovery / manual
 * reports and their transfer to the phone (Link 1.2.3). Shared by the device and the PC harness (test/sim); the pure logic
 * is bc_diag / bc_boot, the storage is plat_file_* (FAT on the device). Runs on the UI/app task only (no locking needed):
 * app_tick() -> app_diag_tick(), app_psvc -> app_diag_write / app_diag_next, and the recovery screen's own timer.
 */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "plat.h"

#ifdef __cplusplus
extern "C" {
#endif

#define APP_DIAG_EVENTS_FILE "diag/events.bin"
#define APP_DIAG_INDEX_FILE "diag/index.bin"
#define APP_DIAG_EV_SLOTS 1024u                 /* 32 KB ring */

/** At boot, after storage is mounted (storage_ok false: everything stays in RAM). Writes the BOOT event and, after a
 *  crash, the crash report (core dump summary + log tail + events) before anything else can fail. */
void app_diag_init(const bc_boot_plan_t *plan, bool storage_ok);
/** Subsystem start-up markers for the event log: result 0 starting, 1 up, 2 skipped (disabled after a crash), 3 failed. */
void app_diag_stage(bc_subsys_t s, int result);
void app_diag_event(uint8_t type, uint8_t x, uint16_t a, uint32_t b, uint32_t c, uint32_t d);
/** Monitors (sensor stages, recoveries, phone, Wi-Fi, readings, LIVE, health, touch) + batched log writes (<= 1 / 10 s). */
void app_diag_tick(uint32_t now_ms);
void app_diag_flush(bool force);
void app_diag_note_live(void);                  /* one LIVE message handed to the phone link */
/** Builds and stores a report (kind bc_diag_kind_t); returns its id, 0 when it could not be stored. */
uint32_t app_diag_store_report(uint8_t kind, const char *recovery_note);
/* phone transfer (Link 1.2.3) */
bool app_diag_write(const uint8_t *msg, size_t n);           /* a Control write; true when it was a DIAG message */
/** Next diag reply (chr 0 Control, 2 Events). Chunks are sized from the negotiated ATT MTU, refused BUSY while a ride is
 *  RUNNING, and released only when plat_phone_bulk_room() and at most one per BC_DIAG_CHUNK_GAP_MS (LIVE keeps priority). */
size_t app_diag_next(uint8_t *chr, uint8_t *buf, size_t cap, uint32_t now_ms);
void app_diag_phone_ready(bool ready);
/** Recovery mode: the phone link runs without the app task; this moves its Control messages to / from the diag server. */
void app_diag_recovery_pump(uint32_t now_ms);

/** Subsystems disabled after a crash this boot (bc_boot skip mask) and RETRY for one of them (clears RTC + NVS; a sensor
 *  link starts again at once, the others on the next start). */
uint16_t app_diag_skip(void);
void app_diag_retry(bc_subsys_t s);
bc_boot_mode_t app_diag_mode(void);

/** Optional Wi-Fi upload of a report: a DISABLED hook only. The owner has not authorized any server, so there is no endpoint
 *  and no network call; it returns false and does nothing. Enabling it needs an explicit decision (endpoint, consent, privacy). */
#define APP_DIAG_UPLOAD_ENABLED 0
bool app_diag_upload_hook(uint32_t report_id);

typedef struct {
    bool crashed;                  /* this boot follows a crash */
    uint32_t crash_report;         /* id of the crash report stored at this boot (0 = none) */
    char summary[48];              /* "panic in nimble_host" */
    int stored, pending, sent;     /* reports in the store / not yet acknowledged / acknowledged this boot */
    uint32_t not_stored;           /* reports that could not be stored (store full of unsent reports) */
    bool storage_ok;
    uint32_t events_written, events_dropped;
    bool phone_ready;
    /* Link 1.2.3 ride priority evidence: chunks sent, held back because the link had no room (LIVE first / mbufs / queue),
       delayed by the pacing gap, refused BUSY because a ride was recording */
    uint32_t chunks_sent, chunks_held, chunks_paced, busy_ride;
} app_diag_status_t;
void app_diag_status(app_diag_status_t *out);

#ifdef __cplusplus
}
#endif
