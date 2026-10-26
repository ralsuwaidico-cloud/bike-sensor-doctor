/* bc_core — PORTABLE CORE. See bc_pipe.h. */
#include "bc_pipe.h"
#include <stdio.h>
#include <string.h>

const char *bc_stage_name(bc_stage_t s)
{
    switch (s) {
    case BC_STG_NOT_PAIRED: return "NOT PAIRED"; case BC_STG_SEARCHING: return "SEARCHING"; case BC_STG_CONNECTING: return "CONNECTING";
    case BC_STG_CONNECTED: return "CONNECTED"; case BC_STG_SUBSCRIBED: return "SUBSCRIBED"; case BC_STG_RECEIVING: return "RECEIVING";
    case BC_STG_VALID: return "VALID"; case BC_STG_STALE: return "STALE"; case BC_STG_ERROR: return "ERROR";
    }
    return "?";
}

static void set_stage(bc_pipe_t *p, bc_stage_t s, uint32_t now)
{
    if (p->stage == s) return;
    p->stage = s; p->stage_ms = now; p->changed = true; p->transitions++;
}

void bc_pipe_init(bc_pipe_t *p) { memset(p, 0, sizeof *p); p->stage = BC_STG_NOT_PAIRED; }

static void reset_conn(bc_pipe_t *p)
{
    p->packets = p->rejected = 0; p->have_packet = p->have_valid = false; p->last_packet_ms = p->last_valid_ms = p->first_packet_ms = 0;
    p->sub_ms = 0; p->cccd = p->cccd_readback = 0;
    p->resub_done = p->stale_resub_done = p->reconnect_pending = p->hex_dumped = p->unreadable = false;
    p->nhex = 0; memset(p->hex_n, 0, sizeof p->hex_n);
}

void bc_pipe_set_link(bc_pipe_t *p, bc_stage_t s, uint32_t now)
{
    if (s == BC_STG_NOT_PAIRED) { bc_pipe_init(p); p->stage_ms = now; p->changed = true; return; }
    if (s == BC_STG_SEARCHING && p->stage == BC_STG_ERROR) return;    /* keep showing why it failed until the next attempt */
    if (s == BC_STG_SEARCHING || s == BC_STG_CONNECTING) reset_conn(p);
    set_stage(p, s, now);
}

void bc_pipe_connected(bc_pipe_t *p, uint32_t now) { reset_conn(p); set_stage(p, BC_STG_CONNECTED, now); }

void bc_pipe_subscribed(bc_pipe_t *p, uint16_t cccd, uint16_t readback, uint32_t now)
{
    p->cccd = cccd; p->cccd_readback = readback;
    if (!p->sub_ms) p->sub_ms = now ? now : 1;                         /* recovery timers count from the FIRST subscription */
    if (p->stage < BC_STG_SUBSCRIBED || p->stage == BC_STG_ERROR) set_stage(p, BC_STG_SUBSCRIBED, now);
}

void bc_pipe_error(bc_pipe_t *p, const char *why, uint32_t now)
{
    snprintf(p->err, sizeof p->err, "%s", why ? why : "error");
    set_stage(p, BC_STG_ERROR, now);
}

void bc_pipe_packet(bc_pipe_t *p, const uint8_t *b, size_t n, bool valid, uint32_t now)
{
    if (p->nhex < BC_PIPE_HEX_N) {
        size_t k = n < BC_PIPE_HEX_LEN ? n : BC_PIPE_HEX_LEN;
        if (b && k) memcpy(p->hex[p->nhex], b, k);
        p->hex_n[p->nhex++] = (uint8_t)(b ? k : 0);
    }
    p->packets++;
    if (!p->have_packet) p->first_packet_ms = now;
    p->have_packet = true; p->last_packet_ms = now;
    if (valid) {
        p->have_valid = true; p->last_valid_ms = now; p->unreadable = false;
        if (p->err[0]) p->err[0] = 0;                                  /* data flows: the last error is history */
    } else p->rejected++;
}

static bool subscribed(const bc_pipe_t *p) { return p->sub_ms && p->stage >= BC_STG_SUBSCRIBED && p->stage != BC_STG_ERROR; }

bc_pipe_act_t bc_pipe_tick(bc_pipe_t *p, uint32_t now)
{
    if (!subscribed(p)) return BC_PIPE_NONE;
    bc_stage_t s;
    if (p->have_valid && now - p->last_valid_ms <= BC_PIPE_VALID_MS) s = BC_STG_VALID;
    else if (p->have_valid) s = BC_STG_STALE;
    else if (p->packets) s = BC_STG_RECEIVING;
    else s = BC_STG_SUBSCRIBED;
    set_stage(p, s, now);
    if (p->reconnect_pending) return BC_PIPE_NONE;
    if (s == BC_STG_VALID) p->stale_resub_done = false;
    if (!p->packets) {
        uint32_t t = now - p->sub_ms;
        if (t >= BC_PIPE_NODATA_RECONNECT_MS) { p->reconnect_pending = true; p->reconnects++; snprintf(p->err, sizeof p->err, "no data"); return BC_PIPE_RECONNECT; }
        if (t >= BC_PIPE_NODATA_RESUB_MS && !p->resub_done) { p->resub_done = true; p->resubscribes++; return BC_PIPE_RESUBSCRIBE; }
        return BC_PIPE_NONE;
    }
    if (!p->have_valid && !p->hex_dumped && now - p->first_packet_ms >= BC_PIPE_REJECT_MS) {
        p->hex_dumped = p->unreadable = true; snprintf(p->err, sizeof p->err, "unreadable data");
        return BC_PIPE_DUMP_HEX;
    }
    if (s == BC_STG_STALE) {
        uint32_t t = now - p->last_valid_ms;
        if (t > BC_PIPE_STALE_RECONNECT_MS) { p->reconnect_pending = true; p->reconnects++; snprintf(p->err, sizeof p->err, "data stopped"); return BC_PIPE_RECONNECT; }
        if (t > BC_PIPE_STALE_RESUB_MS && !p->stale_resub_done) { p->stale_resub_done = true; p->resubscribes++; return BC_PIPE_RESUBSCRIBE; }
    }
    return BC_PIPE_NONE;
}

bool bc_pipe_take_change(bc_pipe_t *p) { bool c = p->changed; p->changed = false; return c; }

void bc_pipe_hex(const bc_pipe_t *p, int i, char *out, size_t cap)
{
    if (!cap) return;
    out[0] = 0;
    if (i < 0 || i >= p->nhex) return;
    size_t o = 0;
    for (int k = 0; k < p->hex_n[i] && o + 4 <= cap; k++) o += (size_t)snprintf(out + o, cap - o, k ? " %02X" : "%02X", p->hex[i][k]);
}

uint32_t bc_pipe_packet_age(const bc_pipe_t *p, uint32_t now) { return p->have_packet ? now - p->last_packet_ms : UINT32_MAX; }
uint32_t bc_pipe_valid_age(const bc_pipe_t *p, uint32_t now) { return p->have_valid ? now - p->last_valid_ms : UINT32_MAX; }
