/*
 * bc_core — standard BLE Cycling Speed and Cadence (service 0x1816, characteristic 0x2A5B "CSC Measurement").
 * OPTIONAL sensor (firmware 0.6.0): a crank sensor gives cadence when there is no power meter, a wheel sensor gives
 * speed/distance without the phone. Power and coaching never depend on it.
 *
 *  flags bit0: wheel data present  -> u32 cumulative wheel revolutions, u16 last wheel event time (1/1024 s)
 *  flags bit1: crank data present  -> u16 cumulative crank revolutions, u16 last crank event time (1/1024 s)
 *
 * Rates come from the difference between two packets with DIFFERENT event times (a repeated event time means the
 * wheel/crank stood still). No new event for BC_CSC_ZERO_MS = 0 rpm / 0 km/h (coasting); no packet at all for
 * BC_STALE_MS = NO DATA. Nothing is ever extrapolated.
 */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "bc_xds.h"

#ifdef __cplusplus
extern "C" {
#endif

#define BC_CSC_ZERO_MS 3000

typedef struct {
    bool wheel_ok, crank_ok;
    uint32_t wheel_revs; uint16_t wheel_t;   /* raw cumulative values and 1/1024 s event times */
    uint16_t crank_revs, crank_t;
} bc_csc_meas_t;

/** Decodes 0x2A5B. False for a short packet or a flags/length mismatch. */
bool bc_csc_decode(const uint8_t *b, size_t n, bc_csc_meas_t *m);

typedef struct {
    bool have_wheel, have_crank;              /* a rate has been computed at least once */
    bool has_wheel, has_crank;                /* the sensor reports this kind of data at all */
    int rpm;                                  /* crank cadence */
    uint32_t wheel_mrph;                      /* wheel revolutions per hour (milli-revs/h not needed: revs/h fits) */
    uint32_t wheel_total;                     /* wheel revolutions counted since reset (for distance) */
    uint32_t last_crank_event_ms, last_wheel_event_ms, last_ms, last_packet_ms, first_ms;
    uint32_t packets, rejected;
    bc_csc_meas_t prev; bool have_prev;
} bc_csc_live_t;

void bc_csc_live_reset(bc_csc_live_t *l);
bool bc_csc_live_feed(bc_csc_live_t *l, const uint8_t *b, size_t n, uint32_t now_ms);
/** Cadence: OK with rpm (0 while coasting after BC_CSC_ZERO_MS), NO_DATA when the sensor has no crank data or is stale. */
bc_live_status_t bc_csc_live_cadence(const bc_csc_live_t *l, uint32_t now_ms, int *rpm);
/** Speed in km/h x 10 from the wheel rate and the wheel circumference in mm. */
bc_live_status_t bc_csc_live_speed(const bc_csc_live_t *l, uint32_t now_ms, uint16_t wheel_mm, int *speed_dmh);

#ifdef __cplusplus
}
#endif
