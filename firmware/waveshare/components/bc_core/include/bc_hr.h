/*
 * bc_core — standard BLE Heart Rate Measurement (service 0x180D, characteristic 0x2A37). OPTIONAL sensor: power,
 * cadence and coaching never depend on it. Same freshness rule as the power meter: older than 4 s = NO DATA.
 */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "bc_xds.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Decodes 0x2A37 (flags bit0: 0 = u8 bpm, 1 = u16 bpm). Returns false for a short or implausible (<25 / >250) value. */
bool bc_hr_decode(const uint8_t *b, size_t n, int *bpm);

typedef struct {
    bool have;
    int bpm;
    uint32_t last_ms, last_packet_ms;
    uint32_t packets, rejected;
} bc_hr_live_t;

void bc_hr_live_reset(bc_hr_live_t *l);
bool bc_hr_live_feed(bc_hr_live_t *l, const uint8_t *b, size_t n, uint32_t now_ms);
bc_live_status_t bc_hr_live_bpm(const bc_hr_live_t *l, uint32_t now_ms, int *bpm);

#ifdef __cplusplus
}
#endif
