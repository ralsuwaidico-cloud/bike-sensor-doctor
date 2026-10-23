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
    bool cad_ok; int rpm; bool backwards;
    bool hr_ok; int bpm;
    plat_link_info_t link[PLAT_SENS_KINDS];
} app_live_t;

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
void app_ride_discard(void);
void app_ride_totals(bc_ride_summary_t *out);    /* live totals while riding; final summary after end */
int app_ride_ftp_evidence(void);                 /* FTP estimate from the ended ride, 0 = none */
const bc_cue_t *app_cue(void);
void app_target(int *lo, int *hi, bool *relative);
bool app_ride_is_demo(void);
int app_coach_inband_pct(void);                  /* -1 until a minute has been judged */

/* history (newest first). demo=true reads the separate demo history. */
int app_history(bc_ride_summary_t *out, int max, bool demo);
bool app_history_clear(bool demo);

/* a ride interrupted by a crash or power loss is recovered at start-up */
bool app_take_recovered(bc_ride_summary_t *out);

/* health line for the serial log (memory etc. come from the platform) */
void app_health_line(char *buf, size_t cap);

#ifdef __cplusplus
}
#endif
