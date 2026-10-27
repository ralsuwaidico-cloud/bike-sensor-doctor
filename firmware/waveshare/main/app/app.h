/*
 * App logic shared by the device and the PC test harness: profile, demo mode, live values, ride session (recorder +
 * coach + crash-safe journal), history. Runs in the UI task: call app_tick() often (it processes whole seconds).
 */
#pragma once
#include <stdbool.h>
#include "plat.h"
#include "bc_profile.h"
#include "bc_ride.h"
#include "bc_coach.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    bool demo;                         /* values are SIMULATED (demo mode) */
    bool power_ok; int watts;
    bool cad_ok; int rpm; bool backwards; uint8_t cad_src;   /* bc_src_t: XDS (meter) or BLE_CSC (0.6.0 crank sensor, used when the meter gives none) */
    bool hr_ok; int bpm; uint8_t hr_src;           /* bc_src_t: STRAP (direct BLE) or the phone-relayed source (WATCH, ...) */
    uint32_t hr_age_ms, cad_age_ms;                /* 0.7.2: age of the shown HR / cadence value (UINT32_MAX = none) — the LIVE message carries them */
    bool strap_hr, phone_hr;                       /* which HR sources have a fresh value right now (for "backup" labels) */
    bool speed_ok; int speed_dmh; uint8_t speed_src;   /* km/h × 10: a wheel sensor (BLE_CSC) first, else the phone's GPS (fresh ≤ 5 s) */
    bool csc_speed, gps_speed;                     /* which speed sources are fresh right now */
    uint32_t gps_age_ms;                           /* since the last accepted position, UINT32_MAX = never */
    bool time_known; uint32_t epoch_s;             /* wall clock when a phone synced the time */
    plat_link_info_t link[PLAT_SENS_KINDS];        /* SPEED = phone GPS: CONNECTED fresh, STALE old, NOT_PAIRED never; CSC = the paired speed/cadence sensor */
} app_live_t;
#define APP_GPS_FRESH_MS 5000
#define APP_PHONE_HR_FRESH_MS 6000                /* Apple Watch delivers about every 5 s: one missed sample = NO DATA, never a held value */

void app_init(void);
bc_profile_t *app_profile(void);
bool app_profile_save(void);
void app_profile_reset(void);                    /* "start setup again" — keeps ride history */

bool app_demo(void);
void app_set_demo(bool on);                      /* demo mode is never stored: every restart begins in real mode */

void app_live(app_live_t *out);
void app_tick(void);

/* ride session */
bc_ride_state_t app_ride_state(void);           /* IDLE when no ride */
void app_ride_start(void);
void app_ride_pause(void);
void app_ride_resume(void);
void app_ride_end(void);                         /* → ENDED, summary ready, waiting for save / discard */
bool app_ride_save(void);                        /* writes history, applies FTP evidence (real rides only) */
/* 0.7.4: what happened to the ride at SAVE. On damaged storage a real ride is never lost silently: its summary is kept in RAM
   (up to APP_UNSAVED_MAX, until power-off), shown in History and sent to Cyclift by the normal ride sync (SYNC_RIDE); the
   ride id advances only when the ride is kept somewhere (file or RAM). */
typedef enum { APP_SAVE_OK = 0, APP_SAVE_RAM_ONLY = 1, APP_SAVE_LOST = 2, APP_SAVE_NOTHING = 3 } app_save_result_t;
#define APP_UNSAVED_MAX 4
app_save_result_t app_ride_save_ex(void);
int app_unsaved_rides(bc_ride_summary_t *out, int max);   /* RAM-only rides, oldest first */
void app_ride_discard(void);
void app_ride_totals(bc_ride_summary_t *out);    /* live totals while riding; final summary after end */
int app_ride_ftp_evidence(void);                 /* FTP estimate from the ended ride, 0 = none */
const bc_cue_t *app_cue(void);
void app_target(int *lo, int *hi, bool *relative);
bool app_ride_is_demo(void);
int app_coach_inband_pct(void);                  /* -1 until a minute has been judged */

/* history (newest first). demo=true reads the separate demo history. */
#define APP_HIST_REAL "rides/history.txt"       /* one line per saved real ride (bc_summary_to_line); streamed by app_psvc for the phone */
int app_history(bc_ride_summary_t *out, int max, bool demo);
bool app_history_clear(bool demo);

/* a ride interrupted by a crash or power loss is recovered at start-up */
bool app_take_recovered(bc_ride_summary_t *out);

/* phone link: pending pairing code (0 = none) for the pop-up, and the current phone status */
uint32_t app_phone_passkey(void);

/* write any buffered journal seconds to flash now (power actions, low battery) */
void app_journal_flush(void);

/* health line for the serial log (memory etc. come from the platform) */
void app_health_line(char *buf, size_t cap);

#ifdef __cplusplus
}
#endif
