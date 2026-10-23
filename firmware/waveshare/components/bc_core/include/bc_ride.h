/*
 * bc_core — ride recorder, ride summary, history line format and automatic FTP evidence.
 *
 * Rules
 *  - one sample per ridden second; a missing sensor value is -1 and is EXCLUDED from averages (never filled in);
 *  - average power counts 0 W while coasting (standard practice); average cadence counts pedalling seconds only;
 *  - paused time is not ride time;
 *  - time in power zones is only reported when the FTP was established (automatic or entered) at the start of the ride;
 *  - demo rides carry demo=1 everywhere and never change the FTP.
 */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "bc_profile.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct { int16_t power, cad, hr; } bc_sample_t;   /* -1 = no data */

typedef enum { BC_RIDE_IDLE = 0, BC_RIDE_RUNNING, BC_RIDE_PAUSED, BC_RIDE_ENDED } bc_ride_state_t;

#define BC_ZONES 7
#define BC_WIN20 1200

typedef struct {
    uint16_t id;
    bool demo, recovered;
    uint32_t duration_s, paused_s;
    int avg_power, max_power, avg_cad, avg_hr, max_hr;   /* -1 = no data */
    uint32_t power_s, cad_s, hr_s;                       /* seconds with valid data */
    bool zones_valid;
    uint32_t zone_s[BC_ZONES];
    int ftp_w; uint8_t ftp_how;                          /* FTP in force during the ride */
    int kj;
    int best20;                                          /* best 20-min mean power, -1 if the ride had none */
    int inband_pct;                                      /* coach: % of judged time inside the target, -1 if never judged */
    int ftp_new;                                         /* FTP applied (or suggested) from this ride, 0 = none */
    bool ftp_suggested_only;                             /* the rider's entered FTP was kept; ftp_new is only a suggestion */
    char coach[120];                                     /* plain-language coaching summary */
} bc_ride_summary_t;

typedef struct {
    bc_ride_state_t state;
    bc_ride_summary_t s;                                 /* running totals live here */
    uint64_t pw_sum, cad_sum, hr_sum, energy_j;
    /* rolling 20-min window for FTP evidence */
    int16_t win[BC_WIN20];
    uint32_t win_pos;                                    /* seconds pushed so far */
    int64_t win_sum, win_sumsq; int win_valid;
    int best20_sum, best20_valid; double best20_cv;
} bc_ride_t;

void bc_ride_start(bc_ride_t *r, uint16_t id, bool demo, int ftp_w, uint8_t ftp_how, bool ftp_established);
void bc_ride_pause(bc_ride_t *r);
void bc_ride_resume(bc_ride_t *r);
/** One second of riding (call only while RUNNING; while PAUSED call bc_ride_tick_paused). */
void bc_ride_tick(bc_ride_t *r, bc_sample_t smp);
void bc_ride_tick_paused(bc_ride_t *r);
/** Ends the ride, finalises averages. The summary stays in r->s. */
void bc_ride_end(bc_ride_t *r);
/** Averages so far (also valid while running). */
void bc_ride_live_summary(const bc_ride_t *r, bc_ride_summary_t *out);

/** Power zone 1..7 (Coggan, % of FTP: 55/75/90/105/120/150), 0 for no power / coasting. */
int bc_power_zone(int watts, int ftp);
/** Lower/upper watts of a zone (hi = -1 for open-ended Z7). */
void bc_power_zone_range(int zone, int ftp, int *lo, int *hi);

/**
 * FTP evidence from a finished REAL ride: a steady (CV ≤ 15 %) 20-min effort ≥ 60 W that is ≥ 1.15 × the rest of the
 * ride (which must have ≥ 10 min of power). Estimate = 95 % of that 20-min mean. Returns 0 when the ride does not qualify.
 */
int bc_ride_ftp_estimate(const bc_ride_t *r);
/**
 * Applies the estimate to the profile following the honesty rules (demo → never; entered → suggestion only; none/assumed/
 * auto → applied when it differs by ≥ 3 % or the current value is only an assumption). Fills summary ftp_new / note.
 * Returns true when the profile changed.
 */
bool bc_ride_apply_ftp(bc_ride_t *r, bc_profile_t *p);

/** History line (one ride per line). */
size_t bc_summary_to_line(const bc_ride_summary_t *s, char *out, size_t cap);
bool bc_summary_from_line(bc_ride_summary_t *s, const char *line);

/** "1:02:03" or "12:34". */
void bc_fmt_duration(uint32_t sec, char *out, size_t cap);

#ifdef __cplusplus
}
#endif
