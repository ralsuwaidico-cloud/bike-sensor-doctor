#include "bc_hr.h"
#include <string.h>

bool bc_hr_decode(const uint8_t *b, size_t n, int *bpm)
{
    if (!b || n < 2) return false;
    int v;
    if (b[0] & 0x01) { if (n < 3) return false; v = b[1] | (b[2] << 8); }
    else v = b[1];
    if (v < 25 || v > 250) return false;
    *bpm = v;
    return true;
}

void bc_hr_live_reset(bc_hr_live_t *l) { memset(l, 0, sizeof *l); }

bool bc_hr_live_feed(bc_hr_live_t *l, const uint8_t *b, size_t n, uint32_t now_ms)
{
    l->packets++; l->last_packet_ms = now_ms;
    int v;
    if (!bc_hr_decode(b, n, &v)) { l->rejected++; return false; }
    l->have = true; l->bpm = v; l->last_ms = now_ms;
    return true;
}

bc_live_status_t bc_hr_live_bpm(const bc_hr_live_t *l, uint32_t now_ms, int *bpm)
{
    if (!l->have || now_ms - l->last_ms > BC_STALE_MS) return BC_LIVE_NO_DATA;
    *bpm = l->bpm;
    return BC_LIVE_OK;
}
