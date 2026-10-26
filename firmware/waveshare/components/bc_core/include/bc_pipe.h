/*
 * bc_core — SENSOR PIPELINE STAGES + AUTOMATIC RECOVERY (firmware 0.7.2). One bc_pipe_t per sensor link (power meter,
 * heart-rate strap, speed/cadence sensor). Pure C with an explicit clock, host-tested with a fake clock; driven by the
 * NimBLE central on the device and by the fake GATT server in the PC harness.
 *
 * "Bluetooth connected" is never success. The stages, in order:
 *   NOT PAIRED · SEARCHING · CONNECTING · CONNECTED (GATT link up) · SUBSCRIBED (CCCD written and read back)
 *   · RECEIVING (packets arrive, none valid yet) · VALID (a decoded, plausible measurement <= 3 s old)
 *   · STALE (no valid measurement for > 3 s after having one) · ERROR (the last attempt failed; see err)
 * A link is OK only at VALID. Numbers on the wire / LINK spec 1.2.2: 0..8 in this order.
 *
 * Recovery (returned by bc_pipe_tick, at most one action per call, the caller performs it):
 *   subscribed, 0 packets for 8 s       -> RESUBSCRIBE (rediscover + subscribe again), once per connection
 *   subscribed, still 0 packets at 15 s -> RECONNECT (the caller disconnects; the normal back-off applies)
 *   packets, but ALL rejected for 10 s  -> DUMP_HEX once (first 3 packets, sensor data only) + err "unreadable data"
 *   stale > 10 s while connected        -> RESUBSCRIBE once; still stale at 25 s -> RECONNECT
 * The caller resets its back-off only at VALID, so a meter that connects but never sends data is retried at 1, 2, 4, 8, 16 s
 * spacing, never faster.
 */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum { BC_STG_NOT_PAIRED = 0, BC_STG_SEARCHING = 1, BC_STG_CONNECTING = 2, BC_STG_CONNECTED = 3, BC_STG_SUBSCRIBED = 4,
               BC_STG_RECEIVING = 5, BC_STG_VALID = 6, BC_STG_STALE = 7, BC_STG_ERROR = 8 } bc_stage_t;
typedef enum { BC_PIPE_NONE = 0, BC_PIPE_RESUBSCRIBE, BC_PIPE_RECONNECT, BC_PIPE_DUMP_HEX } bc_pipe_act_t;

#define BC_PIPE_VALID_MS 3000u
#define BC_PIPE_NODATA_RESUB_MS 8000u
#define BC_PIPE_NODATA_RECONNECT_MS 15000u
#define BC_PIPE_REJECT_MS 10000u
#define BC_PIPE_STALE_RESUB_MS 10000u
#define BC_PIPE_STALE_RECONNECT_MS 25000u
#define BC_PIPE_HEX_N 3
#define BC_PIPE_HEX_LEN 20

typedef struct {
    bc_stage_t stage; uint32_t stage_ms;            /* current stage and since when */
    bool changed;                                   /* stage changed since bc_pipe_take_change */
    uint32_t packets, rejected;                     /* since the current connection */
    bool have_packet, have_valid; uint32_t last_packet_ms, last_valid_ms, first_packet_ms;
    uint32_t sub_ms;                                /* first subscription of this connection (0 = not subscribed) */
    uint16_t cccd, cccd_readback;                   /* handle written and the value read back from it */
    bool resub_done, stale_resub_done, reconnect_pending, hex_dumped, unreadable;
    uint8_t hex[BC_PIPE_HEX_N][BC_PIPE_HEX_LEN]; uint8_t hex_n[BC_PIPE_HEX_N]; int nhex;
    char err[21];                                   /* last error, short, kept until the next valid data */
    uint32_t transitions, resubscribes, reconnects;
} bc_pipe_t;

const char *bc_stage_name(bc_stage_t s);           /* "NOT PAIRED", "SEARCHING", ... "VALID", "STALE", "ERROR" */
void bc_pipe_init(bc_pipe_t *p);
/** Radio-side stages: NOT_PAIRED, SEARCHING, CONNECTING. An ERROR stays visible while the link waits to retry
 *  (SEARCHING does not overwrite ERROR; CONNECTING does). */
void bc_pipe_set_link(bc_pipe_t *p, bc_stage_t s, uint32_t now);
/** GATT link up: per-connection counters reset, stage CONNECTED. */
void bc_pipe_connected(bc_pipe_t *p, uint32_t now);
/** CCCD written; readback = the 16-bit value read back from it (the caller passes it only when it matched). */
void bc_pipe_subscribed(bc_pipe_t *p, uint16_t cccd, uint16_t readback, uint32_t now);
/** A step failed: stage ERROR with a short reason ("no CCCD", "CCCD write failed", "no 0x2A63", ...). */
void bc_pipe_error(bc_pipe_t *p, const char *why, uint32_t now);
/** A packet arrived on the data characteristic; valid = decoded and plausible. Keeps the first 3 packets for DUMP_HEX. */
void bc_pipe_packet(bc_pipe_t *p, const uint8_t *b, size_t n, bool valid, uint32_t now);
/** Updates SUBSCRIBED / RECEIVING / VALID / STALE from the clock and returns the recovery action due now (or NONE). */
bc_pipe_act_t bc_pipe_tick(bc_pipe_t *p, uint32_t now);
/** True once per stage change (for the serial log and the SENSOR_DIAG event). */
bool bc_pipe_take_change(bc_pipe_t *p);
/** "00 00 5A 01 ..." of kept packet i (sensor data only, nothing personal). */
void bc_pipe_hex(const bc_pipe_t *p, int i, char *out, size_t cap);
/** Milliseconds since the last packet / last valid measurement, UINT32_MAX = none. */
uint32_t bc_pipe_packet_age(const bc_pipe_t *p, uint32_t now);
uint32_t bc_pipe_valid_age(const bc_pipe_t *p, uint32_t now);

#ifdef __cplusplus
}
#endif
