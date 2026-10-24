#include "bc_csc.h"
#include <string.h>

bool bc_csc_decode(const uint8_t *b, size_t n, bc_csc_meas_t *m)
{
    if (!b || n < 1) return false;
    memset(m, 0, sizeof *m);
    uint8_t f = b[0]; size_t p = 1;
    if (f & 0x01) { if (n < p + 6) return false; m->wheel_ok = true; m->wheel_revs = (uint32_t)b[p] | ((uint32_t)b[p + 1] << 8) | ((uint32_t)b[p + 2] << 16) | ((uint32_t)b[p + 3] << 24); m->wheel_t = (uint16_t)(b[p + 4] | (b[p + 5] << 8)); p += 6; }
    if (f & 0x02) { if (n < p + 4) return false; m->crank_ok = true; m->crank_revs = (uint16_t)(b[p] | (b[p + 1] << 8)); m->crank_t = (uint16_t)(b[p + 2] | (b[p + 3] << 8)); p += 4; }
    return m->wheel_ok || m->crank_ok;
}

void bc_csc_live_reset(bc_csc_live_t *l) { memset(l, 0, sizeof *l); }

/* revolutions per minute from two cumulative counts and two 1/1024 s timestamps (16-bit wrap-safe) */
static bool rate_rpm(uint32_t d_revs, uint16_t t_new, uint16_t t_old, int *rpm)
{
    uint16_t dt = (uint16_t)(t_new - t_old);
    if (dt == 0) return false;                    /* same event: no movement since the last packet */
    uint32_t r = (d_revs * 60u * 1024u + dt / 2) / dt;
    if (r > 400) return false;                    /* implausible (sensor glitch) */
    *rpm = (int)r; return true;
}

bool bc_csc_live_feed(bc_csc_live_t *l, const uint8_t *b, size_t n, uint32_t now_ms)
{
    l->packets++; l->last_packet_ms = now_ms;
    bc_csc_meas_t m;
    if (!bc_csc_decode(b, n, &m)) { l->rejected++; return false; }
    l->last_ms = now_ms; if (!l->have_prev) l->first_ms = now_ms;
    if (m.wheel_ok) l->has_wheel = true;
    if (m.crank_ok) l->has_crank = true;
    if (l->have_prev) {
        if (m.crank_ok && l->prev.crank_ok) {
            uint16_t d = (uint16_t)(m.crank_revs - l->prev.crank_revs);
            if (d && d < 50) { int r; if (rate_rpm(d, m.crank_t, l->prev.crank_t, &r)) { l->rpm = r; l->have_crank = true; l->last_crank_event_ms = now_ms; } }
        }
        if (m.wheel_ok && l->prev.wheel_ok) {
            uint32_t d = m.wheel_revs - l->prev.wheel_revs;
            if (d && d < 200) { int r; if (rate_rpm(d, m.wheel_t, l->prev.wheel_t, &r)) { l->wheel_mrph = (uint32_t)r * 60u; l->wheel_total += d; l->have_wheel = true; l->last_wheel_event_ms = now_ms; } }
        }
    } else {
        if (m.crank_ok) l->have_crank = false;
        if (m.wheel_ok) l->have_wheel = false;
    }
    l->prev = m; l->have_prev = true;
    return true;
}

bc_live_status_t bc_csc_live_cadence(const bc_csc_live_t *l, uint32_t now_ms, int *rpm)
{
    if (!l->has_crank || !l->have_prev || now_ms - l->last_ms > BC_STALE_MS) return BC_LIVE_NO_DATA;
    if (!l->have_crank) { if (now_ms - l->first_ms > BC_CSC_ZERO_MS) { *rpm = 0; return BC_LIVE_OK; } return BC_LIVE_NO_DATA; }   /* one packet only: not yet a rate */
    if (now_ms - l->last_crank_event_ms > BC_CSC_ZERO_MS) { *rpm = 0; return BC_LIVE_OK; }
    *rpm = l->rpm; return BC_LIVE_OK;
}

bc_live_status_t bc_csc_live_speed(const bc_csc_live_t *l, uint32_t now_ms, uint16_t wheel_mm, int *speed_dmh)
{
    if (!l->has_wheel || !l->have_prev || now_ms - l->last_ms > BC_STALE_MS || wheel_mm < 500) return BC_LIVE_NO_DATA;
    if (!l->have_wheel) { if (now_ms - l->first_ms > BC_CSC_ZERO_MS) { *speed_dmh = 0; return BC_LIVE_OK; } return BC_LIVE_NO_DATA; }
    if (now_ms - l->last_wheel_event_ms > BC_CSC_ZERO_MS) { *speed_dmh = 0; return BC_LIVE_OK; }
    /* revs/h x mm = mm/h; km/h x 10 = mm/h / 100000 */
    uint64_t mmph = (uint64_t)l->wheel_mrph * wheel_mm;
    *speed_dmh = (int)((mmph + 50000) / 100000);
    return BC_LIVE_OK;
}
