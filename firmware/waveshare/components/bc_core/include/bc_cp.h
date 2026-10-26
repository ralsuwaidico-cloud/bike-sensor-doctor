/*
 * bc_core — standard Bluetooth SIG Cycling Power Measurement (service 0x1818, characteristic 0x2A63), firmware 0.7.2.
 * Used for any power meter that is NOT an XDS (the XDS sends its own 11-byte format on 0x2A63 under 0x1828, see bc_xds.h).
 *
 *  u16 flags · s16 instantaneous power (W) · then, in this order, only when its flag bit is set:
 *    bit0 u8 pedal power balance · bit2 u16 accumulated torque · bit4 u32 wheel revs + u16 last wheel event (1/2048 s)
 *    bit5 u16 crank revs + u16 last crank event (1/1024 s) · (bit6.. extreme forces/torques/angles/dead spots/energy: ignored)
 * Cadence = crank revolutions / time between two DIFFERENT crank events; no new crank event for BC_CP_ZERO_MS = 0 rpm
 * (coasting); a meter without crank data has NO cadence (never guessed). Negative or > 3000 W is rejected.
 */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "bc_xds.h"

#ifdef __cplusplus
extern "C" {
#endif

#define BC_CP_ZERO_MS 3000u

typedef struct { int16_t power_w; bool crank_ok; uint16_t crank_revs, crank_t; } bc_cp_meas_t;
/** False for a packet shorter than its flags announce (fields up to the crank data are checked). */
bool bc_cp_decode(const uint8_t *b, size_t n, bc_cp_meas_t *m);

typedef struct { bool have_prev, have_rpm; uint16_t prev_revs, prev_t; int rpm; uint32_t last_event_ms, first_ms; } bc_cp_cad_t;
void bc_cp_cad_reset(bc_cp_cad_t *c);
/** Feeds one standard 0x2A63 packet into the meter's live state (the same bc_xds_live_t the screens read): power and,
 *  when the meter sends crank data, cadence. True when decoded and plausible. */
bool bc_cp_live_feed(bc_xds_live_t *l, bc_cp_cad_t *c, const uint8_t *b, size_t n, uint32_t now_ms);

#ifdef __cplusplus
}
#endif
