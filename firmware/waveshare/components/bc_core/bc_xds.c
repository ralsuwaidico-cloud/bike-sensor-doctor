/* bc_core — PORTABLE CORE. See bc_xds.h. */
#include "bc_xds.h"
#include <string.h>

static uint16_t u16(const uint8_t *b, size_t i) { return (uint16_t)(b[i] | (b[i + 1] << 8)); }

bool bc_xds_decode(const uint8_t *b, size_t n, bc_xds_sample_t *out)
{
    if (b == NULL || out == NULL || n < BC_XDS_PACKET_LEN) return false;
    out->power_w = u16(b, 0);
    out->left_w = (int16_t)u16(b, 2);
    out->right_w = (int16_t)u16(b, 4);
    out->cadence_signed_rpm = (int16_t)u16(b, 6);
    out->angle_deg = u16(b, 8);
    out->error = b[10];
    return true;
}

bool bc_xds_plausible(const bc_xds_sample_t *s)
{
    int cad = bc_xds_cadence_rpm(s);
    return s->angle_deg <= 359 && cad <= 250 && s->power_w <= 3000;
}

void bc_xds_live_reset(bc_xds_live_t *l) { memset(l, 0, sizeof(*l)); }

bool bc_xds_live_feed(bc_xds_live_t *l, const uint8_t *b, size_t n, uint32_t now_ms)
{
    l->packets++;
    l->last_packet_ms = now_ms;
    bc_xds_sample_t s;
    if (!bc_xds_decode(b, n, &s)) { l->short_packets++; return false; }
    if (!bc_xds_plausible(&s)) { l->rejected++; return false; }
    l->last = s;
    l->last_ms = now_ms;
    l->have = true;
    return true;
}

bool bc_xds_live_feed_sample(bc_xds_live_t *l, const bc_xds_sample_t *s, bool has_cad, uint32_t now_ms)
{
    l->packets++;
    l->last_packet_ms = now_ms;
    if (!s) { l->short_packets++; return false; }
    if (!bc_xds_plausible(s)) { l->rejected++; return false; }
    l->last = *s; l->no_cad = !has_cad;
    l->last_ms = now_ms;
    l->have = true;
    return true;
}

static bool fresh(const bc_xds_live_t *l, uint32_t now_ms) { return l->have && (uint32_t)(now_ms - l->last_ms) <= BC_STALE_MS; }

bc_live_status_t bc_xds_live_power(const bc_xds_live_t *l, uint32_t now_ms, int *watts)
{
    if (!fresh(l, now_ms)) return BC_LIVE_NO_DATA;
    if (watts) *watts = l->last.power_w;
    return BC_LIVE_OK;
}

bc_live_status_t bc_xds_live_cadence(const bc_xds_live_t *l, uint32_t now_ms, int *rpm, bool *backwards)
{
    if (!fresh(l, now_ms) || l->no_cad) return BC_LIVE_NO_DATA;
    if (rpm) *rpm = bc_xds_cadence_rpm(&l->last);
    if (backwards) *backwards = bc_xds_backwards(&l->last);
    return BC_LIVE_OK;
}

bool bc_xds_link_silent(const bc_xds_live_t *l, uint32_t now_ms)
{
    return l->packets > 0 && (uint32_t)(now_ms - l->last_packet_ms) > BC_LINK_SILENT_MS;
}
