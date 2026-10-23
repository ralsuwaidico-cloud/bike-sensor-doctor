#include "bc_coach.h"
#include <stdio.h>
#include <string.h>

#define RING 60
#define LOADED_W 30          /* below this the rider is coasting / soft-pedalling */
#define REF_TAU 300.0        /* relative reference: ~5-min exponential average of loaded power */
#define REF_MIN_S 180        /* learning time before the reference is trusted */

void bc_coach_init(bc_coach_t *c, const bc_profile_t *p)
{
    memset(c, 0, sizeof *c);
    c->ftp = p->ftp_w; c->ftp_established = bc_ftp_established(p); c->goal = p->goal;
    c->max_hr = bc_profile_max_hr(p);
    c->hr_guidance = true;
    c->warmup_s = (p->age >= 50 ? 10 : 5) * 60 + (p->exp <= BC_EXP_NOVICE ? 180 : 0);
    c->cad_lo = 80; c->cad_hi = 95;
    for (int i = 0; i < RING; i++) c->pw[i] = c->cad[i] = c->hr[i] = -1;
}

static void band(const bc_coach_t *c, int *lo, int *hi)
{
    bool tempo = c->goal == BC_GOAL_FTP || c->goal == BC_GOAL_CLIMB;
    *lo = (c->ftp * (tempo ? 76 : 56) + 50) / 100;
    *hi = (c->ftp * (tempo ? 90 : 75) + 50) / 100;
}

void bc_coach_target(const bc_coach_t *c, int *lo, int *hi, bool *relative)
{
    *relative = !c->ftp_established;
    if (c->ftp_established && c->ftp > 0) { band(c, lo, hi); return; }
    if (c->ref_n >= REF_MIN_S) { *lo = (int)(c->ref * 0.90 + 0.5); *hi = (int)(c->ref * 1.10 + 0.5); return; }
    *lo = *hi = 0;
}

/* mean of the last k seconds of a ring; needs at least min_valid valid values */
static int mean_last(const int16_t *a, uint32_t n, int k, int min_valid, bool positive_only)
{
    long sum = 0; int v = 0;
    for (int i = 1; i <= k && (uint32_t)i <= n; i++) {
        int x = a[(n - i) % RING];
        if (x < 0 || (positive_only && x == 0)) continue;
        sum += x; v++;
    }
    return v >= min_valid ? (int)((sum + v / 2) / v) : -1;
}

static const bc_cue_t *set(bc_coach_t *c, bc_cue_id_t id, bc_cue_level_t lvl, const char *head, const char *why, uint32_t now)
{
    if (c->cue.id != id) c->cue_since = now;
    c->cue.id = id; c->cue.level = lvl;
    snprintf(c->cue.head, sizeof c->cue.head, "%s", head);
    snprintf(c->cue.why, sizeof c->cue.why, "%s", why);
    return &c->cue;
}

const bc_cue_t *bc_coach_tick(bc_coach_t *c, bc_sample_t s, uint32_t t)
{
    uint32_t i = c->n % RING;
    c->pw[i] = s.power; c->cad[i] = s.cad; c->hr[i] = s.hr; c->n++;
    if (s.cad > 0) { c->cad_sum += (uint64_t)s.cad; c->cad_n++; }

    int p10 = mean_last(c->pw, c->n, 10, 6, false), p3 = mean_last(c->pw, c->n, 3, 2, false), p60 = mean_last(c->pw, c->n, 60, 40, false);
    int c15 = mean_last(c->cad, c->n, 15, 8, false), hr = s.hr > 0 ? s.hr : -1;
    char why[48];

    /* 1. no data: neither power nor cadence for 5 s */
    bool any = s.power >= 0 || s.cad >= 0;
    c->nodata_s = any ? 0 : c->nodata_s + 1;
    if (!any) c->nodata_total++;
    if (c->nodata_s >= 5 || (c->n <= 5 && !any)) {
        snprintf(why, sizeof why, "meter silent %lus", (unsigned long)c->nodata_s);
        return set(c, BC_CUE_NO_DATA, BC_LVL_WARN, "NO SENSOR DATA", why, t);
    }

    /* relative reference: learns from loaded seconds only */
    if (s.power >= LOADED_W) {
        c->ref_n++;
        double a = c->ref_n < REF_TAU ? 1.0 / c->ref_n : 1.0 / REF_TAU;
        c->ref += (s.power - c->ref) * a;
    }

    /* 2. heart-rate safety, only when a strap is connected (never required) */
    int hr_cap = (c->max_hr * (c->goal == BC_GOAL_FTP || c->goal == BC_GOAL_CLIMB ? 90 : 80) + 50) / 100;
    c->hr_s = (hr > 0 && hr > hr_cap) ? c->hr_s + 1 : 0;
    if (c->hr_guidance && c->hr_s >= 10) {
        if (c->hr_s == 10) { c->hr_alerts++; c->ease++; }
        snprintf(why, sizeof why, "HR %d > %d bpm", hr, hr_cap);
        return set(c, BC_CUE_HR_HIGH, BC_LVL_WARN, "EASE OFF - HR HIGH", why, t);
    }

    /* 3. coasting */
    bool coasting = (c15 >= 0 && c15 < 20) && (p10 < 0 || p10 < 20);
    if (coasting) return set(c, BC_CUE_COASTING, BC_LVL_INFO, "COASTING", "no cues while freewheeling", t);

    /* cadence bookkeeping (hysteresis: start below lo-5 / above hi+10, clear back inside the range) */
    if (c15 >= 30 && c15 < c->cad_lo - 5) c->cadlo_s++; else if (c15 < 0 || c15 >= c->cad_lo) c->cadlo_s = 0;
    if (c15 > c->cad_hi + 10) c->cadhi_s++; else if (c15 <= c->cad_hi) c->cadhi_s = 0;

    int lo = 0, hi = 0; bool rel; bc_coach_target(c, &lo, &hi, &rel);

    /* 4. warm-up */
    if (t < (uint32_t)c->warmup_s) {
        int cap = c->ftp > 0 ? (c->ftp * 75 + 50) / 100 : 0;
        c->warm_hi_s = (cap > 0 && p10 > cap) ? c->warm_hi_s + 1 : 0;
        uint32_t left = c->warmup_s - t;
        if (c->warm_hi_s >= 10) {
            snprintf(why, sizeof why, "%d W > %d W%s", p10, cap, c->ftp_established ? "" : " (prov.)");
            return set(c, BC_CUE_WARMUP_EASY, BC_LVL_DOWN, "EASIER - WARM-UP", why, t);
        }
        snprintf(why, sizeof why, "%lu:%02lu left, keep it easy", (unsigned long)(left / 60), (unsigned long)(left % 60));
        return set(c, BC_CUE_WARMUP, BC_LVL_INFO, "WARM UP", why, t);
    }

    if (p10 < 0) {   /* cadence but no power: cadence-only coaching */
        c->drop_s = c->above_s = c->below_s = 0;
    } else if (c->ftp_established && c->ftp > 0) {
        /* 5a. established FTP: power band */
        c->judged_s++;
        bool surge = p3 > 0 && hi > 0 && p3 * 2 > hi * 3;
        c->surge_s = surge ? c->surge_s + 1 : 0;
        c->above_s = p10 * 100 > hi * 103 ? c->above_s + 1 : 0;
        c->below_s = p10 * 100 < lo * 97 ? c->below_s + 1 : 0;
        bool in = p10 >= lo && p10 <= hi;
        if (in) c->inband_s++;
        if (c->surge_s >= 3) {
            if (c->surge_s == 3) c->surges++;
            snprintf(why, sizeof why, "%d W, target up to %d W", p3, hi);
            return set(c, BC_CUE_SURGE, BC_LVL_DOWN, "SMOOTH IT OUT", why, t);
        }
        if (c->above_s >= 5) {
            if (c->above_s == 5) c->ease++;
            snprintf(why, sizeof why, "%d W > %d W target", p10, hi);
            return set(c, BC_CUE_EASE_OFF, BC_LVL_DOWN, "EASE OFF", why, t);
        }
        bool hr_rising = hr > 0 && hr > (c->max_hr * 75) / 100;   /* never ask for more when HR is already up (HR lags) */
        if (c->below_s >= 8 && !hr_rising) {
            if (c->below_s == 8) c->more++;
            snprintf(why, sizeof why, "%d W < %d W target", p10, lo);
            return set(c, BC_CUE_MORE, BC_LVL_UP, "A LITTLE MORE", why, t);
        }
    } else {
        /* 5b. provisional FTP: the rider's own steady output is the yardstick */
        if (c->ref_n < REF_MIN_S) {
            snprintf(why, sizeof why, "steady riding %lu:%02lu more", (unsigned long)((REF_MIN_S - c->ref_n) / 60),
                     (unsigned long)((REF_MIN_S - c->ref_n) % 60));
            /* cadence hints still allowed below */
            if (c->cadlo_s < 10 && c->cadhi_s < 10) return set(c, BC_CUE_LEARNING, BC_LVL_INFO, "LEARNING YOUR PACE", why, t);
        } else {
            c->judged_s++;
            int ref = (int)(c->ref + 0.5);
            if (p10 * 10 >= ref * 9 && p10 * 10 <= ref * 11) c->inband_s++;
            c->surge_s = (p3 > 0 && p3 * 2 > ref * 3) ? c->surge_s + 1 : 0;
            c->drop_s = (p60 >= LOADED_W && p60 * 100 < ref * 85) ? c->drop_s + 1 : 0;
            int soft = c->ftp > 0 ? (c->ftp * 90 + 50) / 100 : 0;
            bool endurance = c->goal != BC_GOAL_FTP && c->goal != BC_GOAL_CLIMB;
            c->prov_hi_s = (endurance && soft > 0 && p60 > soft) ? c->prov_hi_s + 1 : 0;
            if (c->surge_s >= 3) {
                if (c->surge_s == 3) c->surges++;
                snprintf(why, sizeof why, "%d W vs your steady %d W", p3, ref);
                return set(c, BC_CUE_SURGE, BC_LVL_DOWN, "SMOOTH IT OUT", why, t);
            }
            if (c->prov_hi_s >= 60) {
                if (c->prov_hi_s == 60) c->ease++;
                snprintf(why, sizeof why, "1-min %d W > %d W (prov.)", p60, soft);
                return set(c, BC_CUE_EASE_OFF, BC_LVL_DOWN, "EASE OFF", why, t);
            }
            if (c->drop_s >= 60) {
                if (c->drop_s == 60) c->drops++;
                snprintf(why, sizeof why, "1-min %d W vs steady %d W", p60, ref);
                return set(c, BC_CUE_DROPPING, BC_LVL_UP, "POWER DROPPING", why, t);
            }
        }
    }

    /* 6. cadence, only once effort is in order */
    if (c->cadlo_s >= 10) {
        if (c->cadlo_s == 10) c->cad_hints++;
        snprintf(why, sizeof why, "%d rpm, aim %d-%d", c15, c->cad_lo, c->cad_hi);
        return set(c, BC_CUE_CAD_LOW, BC_LVL_UP, "SPIN FASTER", why, t);
    }
    if (c->cadhi_s >= 10) {
        if (c->cadhi_s == 10) c->cad_hints++;
        snprintf(why, sizeof why, "%d rpm, aim %d-%d", c15, c->cad_lo, c->cad_hi);
        return set(c, BC_CUE_CAD_HIGH, BC_LVL_DOWN, "SLOWER CADENCE", why, t);
    }

    /* 7. all good */
    if (p10 < 0) return set(c, BC_CUE_HOLD, BC_LVL_GOOD, "CADENCE ONLY", "no power data, cadence OK", t);
    if (c->ftp_established) snprintf(why, sizeof why, "%d W in %d-%d W", p10, lo, hi);
    else snprintf(why, sizeof why, "%d W, steady near %d W", p10, (int)(c->ref + 0.5));
    return set(c, BC_CUE_HOLD, BC_LVL_GOOD, c->ftp_established ? "HOLD THIS" : "GOOD PACE - HOLD", why, t);
}

void bc_coach_summary(const bc_coach_t *c, const bc_ride_summary_t *r, char *out, size_t cap, int *inband_pct)
{
    *inband_pct = c->judged_s >= 60 ? (int)((c->inband_s * 100 + c->judged_s / 2) / c->judged_s) : -1;
    if (r->power_s == 0 && r->cad_s == 0) { snprintf(out, cap, "No power or cadence data was received. Check the meter is paired and awake."); return; }
    if (r->power_s == 0) { snprintf(out, cap, "Cadence only - no power data. Avg cadence %d rpm.", r->avg_cad); return; }
    int n = 0;
    if (*inband_pct >= 0) {
        if (c->ftp_established) n = snprintf(out, cap, "In target %d%% of the time.", *inband_pct);
        else n = snprintf(out, cap, "Steady near your own pace %d%% of the time.", *inband_pct);
    } else n = snprintf(out, cap, "Too short to judge pacing.");
    if (n < 0 || (size_t)n >= cap) return;
    if (c->surges) n += snprintf(out + n, cap - n, " %lu surge%s.", (unsigned long)c->surges, c->surges == 1 ? "" : "s");
    if ((size_t)n >= cap) return;
    if (r->avg_cad > 0 && (r->avg_cad < c->cad_lo || r->avg_cad > c->cad_hi))
        n += snprintf(out + n, cap - n, " Cadence %d rpm: aim %d-%d.", r->avg_cad, c->cad_lo, c->cad_hi);
    if ((size_t)n >= cap) return;
    if (!c->ftp_established) snprintf(out + n, cap - n, " FTP still provisional.");
    else if (*inband_pct >= 0 && *inband_pct < 60) snprintf(out + n, cap - n, " Next time hold the band longer.");
}
