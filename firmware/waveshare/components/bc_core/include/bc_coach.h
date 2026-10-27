/*
 * bc_core — offline real-time coach (C, deterministic, 1 Hz). Follows the principles of the Android Coach v2/v3
 * (docs/ARCHITECTURE_V2.md §3) in a compact form for the device:
 *
 *  - ONE instruction at a time from a single priority ladder:
 *      no data → heart-rate safety (only if a strap is connected) → coasting → warm-up → effort vs target → cadence → hold;
 *  - every instruction carries its reason with the live number that triggered it ("212 W > 165 W");
 *  - smoothing (power 10 s, cadence 15 s) and hold times (5–10 s) stop flapping;
 *  - power and cadence alone are enough — heart rate is optional;
 *  - with an ESTABLISHED FTP the target is a power band (Zone 2, or tempo for FTP/climbing goals);
 *    with a PROVISIONAL FTP the coach uses the rider's own steady output as the yardstick (relative effort) and only
 *    uses the provisional FTP as a soft upper guide that is labelled as provisional;
 *  - stale or missing data is never replaced: the coach says it has no data.
 */
#pragma once
#include <stdbool.h>
#include <stdint.h>
#include "bc_ride.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    BC_CUE_NONE = 0, BC_CUE_NO_DATA, BC_CUE_HR_HIGH, BC_CUE_COASTING, BC_CUE_WARMUP, BC_CUE_WARMUP_EASY, BC_CUE_LEARNING,
    BC_CUE_EASE_OFF, BC_CUE_MORE, BC_CUE_SURGE, BC_CUE_DROPPING, BC_CUE_CAD_LOW, BC_CUE_CAD_HIGH, BC_CUE_HOLD,
    BC_CUE_PHONE /* 0.7.5: Cyclift coaches (Link 1.3 mirror); head = its instruction */, BC_CUE_COUNT
} bc_cue_id_t;

/* Colour class for the display: GOOD green, UP cyan (more), DOWN amber (less), WARN red, INFO grey */
typedef enum { BC_LVL_INFO = 0, BC_LVL_GOOD, BC_LVL_UP, BC_LVL_DOWN, BC_LVL_WARN } bc_cue_level_t;

typedef struct {
    bc_cue_id_t id;
    bc_cue_level_t level;
    char head[24];      /* glanceable instruction, e.g. "EASE OFF" */
    char why[40];       /* reason with the live number, e.g. "212 W > 165 W" */
} bc_cue_t;

typedef struct {
    /* configuration */
    int ftp; bool ftp_established; int goal; int max_hr; bool hr_guidance;
    int warmup_s; int cad_lo, cad_hi;
    /* 1 Hz history */
    int16_t pw[60], cad[60], hr[60]; uint32_t n;
    /* relative-effort reference (provisional FTP): slow average of loaded power */
    double ref; uint32_t ref_n;
    /* hold counters */
    int above_s, below_s, surge_s, drop_s, hr_s, cadlo_s, cadhi_s, nodata_s, warm_hi_s, prov_hi_s;
    bc_cue_t cue; uint32_t cue_since;
    /* statistics for the summary */
    uint32_t judged_s, inband_s, surges, drops, ease, more, cad_hints, hr_alerts, nodata_total;
    uint64_t cad_sum; uint32_t cad_n;
} bc_coach_t;

void bc_coach_init(bc_coach_t *c, const bc_profile_t *p);
/** Target band in watts for display (lo/hi = 0 while it is not known yet). Sets *relative when it is the rider's own pace. */
void bc_coach_target(const bc_coach_t *c, int *lo, int *hi, bool *relative);
/** Advance one ridden second. ride_s = ride seconds so far (excluding pauses). */
const bc_cue_t *bc_coach_tick(bc_coach_t *c, bc_sample_t s, uint32_t ride_s);
/** Plain-language summary for the results screen (≤ 119 chars). Also sets *inband_pct (-1 if never judged). */
void bc_coach_summary(const bc_coach_t *c, const bc_ride_summary_t *r, char *out, size_t cap, int *inband_pct);

#ifdef __cplusplus
}
#endif
