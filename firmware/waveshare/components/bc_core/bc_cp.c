/* bc_core — PORTABLE CORE. See bc_cp.h. */
#include "bc_cp.h"
#include <string.h>

static uint16_t u16(const uint8_t *b, size_t i) { return (uint16_t)(b[i] | (b[i + 1] << 8)); }

bool bc_cp_decode(const uint8_t *b, size_t n, bc_cp_meas_t *m)
{
    if (!b || !m || n < 4) return false;
    memset(m, 0, sizeof *m);
    uint16_t f = u16(b, 0);
    m->power_w = (int16_t)u16(b, 2);
    size_t p = 4;
    if (f & 0x0001) p += 1;          /* pedal power balance */
    if (f & 0x0004) p += 2;          /* accumulated torque */
    if (f & 0x0010) p += 6;          /* wheel revolution data */
    if (f & 0x0020) {
        if (n < p + 4) return false;
        m->crank_ok = true; m->crank_revs = u16(b, p); m->crank_t = u16(b, p + 2);
        p += 4;
    }
    return n >= p;
}

void bc_cp_cad_reset(bc_cp_cad_t *c) { memset(c, 0, sizeof *c); }

bool bc_cp_live_feed(bc_xds_live_t *l, bc_cp_cad_t *c, const uint8_t *b, size_t n, uint32_t now_ms)
{
    bc_cp_meas_t m;
    if (!bc_cp_decode(b, n, &m)) return bc_xds_live_feed_sample(l, NULL, false, now_ms);
    bc_xds_sample_t s; memset(&s, 0, sizeof s);
    if (m.power_w < 0) { l->packets++; l->last_packet_ms = now_ms; l->rejected++; return false; }
    s.power_w = (uint16_t)m.power_w;
    bool has_cad = false;
    if (m.crank_ok) {
        if (!c->first_ms) c->first_ms = now_ms ? now_ms : 1;
        if (c->have_prev) {
            uint16_t d = (uint16_t)(m.crank_revs - c->prev_revs), dt = (uint16_t)(m.crank_t - c->prev_t);
            if (d && dt && d < 50) {
                uint32_t r = ((uint32_t)d * 60u * 1024u + dt / 2) / dt;
                if (r <= 250) { c->rpm = (int)r; c->have_rpm = true; c->last_event_ms = now_ms; }
            }
        }
        c->prev_revs = m.crank_revs; c->prev_t = m.crank_t; c->have_prev = true;
        if (c->have_rpm && now_ms - c->last_event_ms <= BC_CP_ZERO_MS) { s.cadence_signed_rpm = (int16_t)c->rpm; has_cad = true; }
        else if (now_ms - (c->have_rpm ? c->last_event_ms : c->first_ms) > BC_CP_ZERO_MS) { s.cadence_signed_rpm = 0; has_cad = true; }   /* coasting */
    }
    return bc_xds_live_feed_sample(l, &s, has_cad, now_ms);
}
