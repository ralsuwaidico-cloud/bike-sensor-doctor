#include "bc_ride.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const int ZONE_PCT[6] = { 55, 75, 90, 105, 120, 150 };

int bc_power_zone(int w, int ftp)
{
    if (w <= 0 || ftp <= 0) return 0;
    for (int i = 0; i < 6; i++) if (w * 100 <= ZONE_PCT[i] * ftp) return i + 1;
    return 7;
}

void bc_power_zone_range(int z, int ftp, int *lo, int *hi)
{
    *lo = z <= 1 ? 0 : (ZONE_PCT[z - 2] * ftp + 50) / 100 + 1;
    *hi = z >= 7 ? -1 : (ZONE_PCT[z - 1] * ftp + 50) / 100;
}

void bc_ride_start(bc_ride_t *r, uint16_t id, bool demo, int ftp_w, uint8_t ftp_how, bool established)
{
    memset(r, 0, sizeof *r);
    r->state = BC_RIDE_RUNNING;
    r->s.id = id; r->s.demo = demo; r->s.ftp_w = ftp_w; r->s.ftp_how = ftp_how;
    r->s.zones_valid = established && ftp_w > 0;
    r->s.max_power = -1; r->s.max_hr = -1; r->s.best20 = -1; r->s.inband_pct = -1;
    r->best20_sum = -1;
}

void bc_ride_pause(bc_ride_t *r) { if (r->state == BC_RIDE_RUNNING) r->state = BC_RIDE_PAUSED; }
void bc_ride_resume(bc_ride_t *r) { if (r->state == BC_RIDE_PAUSED) r->state = BC_RIDE_RUNNING; }
void bc_ride_tick_paused(bc_ride_t *r) { if (r->state == BC_RIDE_PAUSED) r->s.paused_s++; }

static void win_push(bc_ride_t *r, int v)
{
    uint32_t i = r->win_pos % BC_WIN20;
    if (r->win_pos >= BC_WIN20) {               /* drop the oldest second */
        int o = r->win[i];
        if (o >= 0) { r->win_sum -= o; r->win_sumsq -= (int64_t)o * o; r->win_valid--; }
    }
    r->win[i] = (int16_t)v;
    if (v >= 0) { r->win_sum += v; r->win_sumsq += (int64_t)v * v; r->win_valid++; }
    r->win_pos++;
    if (r->win_pos >= BC_WIN20 && r->win_valid >= (BC_WIN20 * 95) / 100) {
        /* compare means: sum/valid > best_sum/best_valid */
        if (r->best20_sum < 0 || (int64_t)r->win_sum * r->best20_valid > (int64_t)r->best20_sum * r->win_valid) {
            r->best20_sum = (int)r->win_sum; r->best20_valid = r->win_valid;
            double m = (double)r->win_sum / r->win_valid, var = (double)r->win_sumsq / r->win_valid - m * m;
            r->best20_cv = m > 0 ? sqrt(var > 0 ? var : 0) / m : 0;
        }
    }
}

void bc_ride_tick(bc_ride_t *r, bc_sample_t x)
{
    if (r->state != BC_RIDE_RUNNING) return;
    bc_ride_summary_t *s = &r->s;
    s->duration_s++;
    if (x.power >= 0) {
        s->power_s++; r->pw_sum += (uint64_t)x.power; r->energy_j += (uint64_t)x.power;
        if (x.power > s->max_power) s->max_power = x.power;
        if (s->zones_valid) { int z = bc_power_zone(x.power, s->ftp_w); if (z >= 1) s->zone_s[z - 1]++; }
    }
    if (x.cad > 0) { s->cad_s++; r->cad_sum += (uint64_t)x.cad; }
    if (x.hr > 0) { s->hr_s++; r->hr_sum += (uint64_t)x.hr; if (x.hr > s->max_hr) s->max_hr = x.hr; }
    win_push(r, x.power);
}

void bc_ride_live_summary(const bc_ride_t *r, bc_ride_summary_t *o)
{
    *o = r->s;
    o->avg_power = r->s.power_s ? (int)((r->pw_sum + r->s.power_s / 2) / r->s.power_s) : -1;
    o->avg_cad = r->s.cad_s ? (int)((r->cad_sum + r->s.cad_s / 2) / r->s.cad_s) : -1;
    o->avg_hr = r->s.hr_s ? (int)((r->hr_sum + r->s.hr_s / 2) / r->s.hr_s) : -1;
    o->kj = (int)((r->energy_j + 500) / 1000);
    o->best20 = r->best20_sum >= 0 && r->best20_valid > 0 ? (r->best20_sum + r->best20_valid / 2) / r->best20_valid : -1;
}

void bc_ride_end(bc_ride_t *r)
{
    if (r->state == BC_RIDE_IDLE || r->state == BC_RIDE_ENDED) return;
    bc_ride_live_summary(r, &r->s);
    r->state = BC_RIDE_ENDED;
}

int bc_ride_ftp_estimate(const bc_ride_t *r)
{
    if (r->best20_sum < 0 || r->best20_valid <= 0) return 0;
    double best = (double)r->best20_sum / r->best20_valid;
    if (best < 60 || r->best20_cv > 0.15) return 0;
    int64_t rest_n = (int64_t)r->s.power_s - r->best20_valid;
    if (rest_n < 600) return 0;
    double rest = (double)((int64_t)r->pw_sum - r->best20_sum) / (double)rest_n;
    if (rest <= 0 || best < rest * 1.15) return 0;
    return (int)(best * 0.95 + 0.5);
}

bool bc_ride_apply_ftp(bc_ride_t *r, bc_profile_t *p)
{
    r->s.ftp_new = 0; r->s.ftp_suggested_only = false;
    if (r->s.demo) return false;                         /* simulated data never changes the FTP */
    int est = bc_ride_ftp_estimate(r);
    if (est <= 0) return false;
    if (p->ftp_how == BC_FTP_ENTERED) {
        if (abs(est - p->ftp_w) * 100 >= 3 * p->ftp_w) { r->s.ftp_new = est; r->s.ftp_suggested_only = true; }
        return false;
    }
    if (p->ftp_how == BC_FTP_AUTO && abs(est - p->ftp_w) * 100 < 3 * p->ftp_w) return false;
    int prev = p->ftp_w; uint8_t prev_how = p->ftp_how;
    p->ftp_w = (uint16_t)est; p->ftp_how = BC_FTP_AUTO; p->ftp_from_ride = r->s.id;
    snprintf(p->ftp_note, sizeof p->ftp_note, "Ride #%u: 95%% of a steady 20-min %d W effort. Was %d W (%s).", r->s.id,
             (r->best20_sum + r->best20_valid / 2) / r->best20_valid, prev, prev_how == BC_FTP_ASSUMED ? "provisional" : "from rides");
    r->s.ftp_new = est;
    return true;
}

void bc_ride_add_speed(bc_ride_t *r, uint16_t speed_cms, uint8_t src)
{
    if (r->state != BC_RIDE_RUNNING || speed_cms < 50) return;
    r->dist_cm_rem += speed_cms;
    r->s.distance_m += r->dist_cm_rem / 100; r->dist_cm_rem %= 100;
    r->s.dist_src = src;
}

/* ---- history line: comma-separated, coach text last (it may contain commas) */
size_t bc_summary_to_line(const bc_ride_summary_t *s, char *out, size_t cap)
{
    char coach[sizeof s->coach]; size_t j = 0;
    for (size_t i = 0; s->coach[i] && j + 1 < sizeof coach; i++) coach[j++] = (s->coach[i] == '\n' || s->coach[i] == '\r') ? ' ' : s->coach[i];
    coach[j] = 0;
    int n = snprintf(out, cap, "R2,%u,%d,%d,%lu,%lu,%d,%d,%d,%d,%d,%lu,%lu,%lu,%d,%lu,%lu,%lu,%lu,%lu,%lu,%lu,%d,%u,%d,%d,%d,%d,%d,%lu,%u,%lu,%s",
        s->id, s->demo, s->recovered, (unsigned long)s->duration_s, (unsigned long)s->paused_s, s->avg_power, s->max_power, s->avg_cad,
        s->avg_hr, s->max_hr, (unsigned long)s->power_s, (unsigned long)s->cad_s, (unsigned long)s->hr_s, s->zones_valid,
        (unsigned long)s->zone_s[0], (unsigned long)s->zone_s[1], (unsigned long)s->zone_s[2], (unsigned long)s->zone_s[3],
        (unsigned long)s->zone_s[4], (unsigned long)s->zone_s[5], (unsigned long)s->zone_s[6], s->ftp_w, s->ftp_how, s->kj, s->best20,
        s->inband_pct, s->ftp_new, s->ftp_suggested_only, (unsigned long)s->distance_m, s->dist_src, (unsigned long)s->start_epoch_s, coach);
    if (n < 0 || (size_t)n >= cap) return 0;
    return (size_t)n;
}

bool bc_summary_from_line(bc_ride_summary_t *s, const char *line)
{
    memset(s, 0, sizeof *s);
    if (!line || (strncmp(line, "R1,", 3) != 0 && strncmp(line, "R2,", 3) != 0)) return false;
    int nf = line[1] == '2' ? 31 : 28;                   /* R1 = 0.2.x rides (no position data), R2 adds distance, source, start time */
    long v[31] = { 0 }; const char *p = line + 3;
    for (int i = 0; i < nf; i++) {
        char *e; v[i] = strtol(p, &e, 10);
        if (e == p || *e != ',') return false;
        p = e + 1;
    }
    s->id = (uint16_t)v[0]; s->demo = v[1]; s->recovered = v[2]; s->duration_s = v[3]; s->paused_s = v[4]; s->avg_power = v[5];
    s->max_power = v[6]; s->avg_cad = v[7]; s->avg_hr = v[8]; s->max_hr = v[9]; s->power_s = v[10]; s->cad_s = v[11]; s->hr_s = v[12];
    s->zones_valid = v[13]; for (int z = 0; z < 7; z++) s->zone_s[z] = v[14 + z];
    s->ftp_w = v[21]; s->ftp_how = (uint8_t)v[22]; s->kj = v[23]; s->best20 = v[24]; s->inband_pct = v[25]; s->ftp_new = v[26];
    s->ftp_suggested_only = v[27];
    s->distance_m = (uint32_t)v[28]; s->dist_src = (uint8_t)v[29]; s->start_epoch_s = (uint32_t)v[30];
    size_t i = 0; for (; p[i] && p[i] != '\n' && p[i] != '\r' && i + 1 < sizeof s->coach; i++) s->coach[i] = p[i];
    s->coach[i] = 0;
    return true;
}

void bc_fmt_duration(uint32_t t, char *o, size_t cap)
{
    unsigned h = t / 3600, m = (t / 60) % 60, sec = t % 60;
    if (h) snprintf(o, cap, "%u:%02u:%02u", h, m, sec); else snprintf(o, cap, "%u:%02u", m, sec);
}
