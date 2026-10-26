/*
 * bc_core — PORTABLE CORE (no ESP-IDF headers). C port of the Android app's core/XdsDecoder.kt and the freshness rules
 * of core/SensorPolicy.kt / docs/PORTING_SPEC.md. Unit-tested on the host (firmware/waveshare/test/host) against the
 * 48 real packets captured from XDS-A001-9769 on 2026-10-11.
 *
 * XDS / Branta power meter: BLE service 0x1828 (repurposed), characteristic 0x2A63, notify ~1 Hz, 11 bytes LE:
 *   0..1 u16 total power W · 2..3 s16 left W · 4..5 s16 right W · 6..7 s16 cadence rpm (SIGNED) · 8..9 u16 crank angle · 10 u8 error
 * Rules: never guess; |cadence| for display, "backwards" flag when negative; implausible samples are rejected;
 * a value older than 4 s is NO DATA (never held); >6 s without any packet is a link problem.
 */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BC_XDS_PACKET_LEN 11
#define BC_STALE_MS 4000u        /* PORTING_SPEC §3: blank the live value after 4 s */
#define BC_LINK_SILENT_MS 6000u  /* PORTING_SPEC §3/§5: no packet for 6 s = Bluetooth problem */

typedef struct {
    uint16_t power_w;
    int16_t left_w, right_w;
    int16_t cadence_signed_rpm;
    uint16_t angle_deg;
    uint8_t error;
} bc_xds_sample_t;

/** Decodes a 0x2A63 packet. Returns false for a short packet (out untouched). */
bool bc_xds_decode(const uint8_t *b, size_t n, bc_xds_sample_t *out);
/** Plausibility (PORTING_SPEC §4): angle ≤ 359, |cadence| ≤ 250, power ≤ 3000. */
bool bc_xds_plausible(const bc_xds_sample_t *s);
static inline int bc_xds_cadence_rpm(const bc_xds_sample_t *s) { return s->cadence_signed_rpm < 0 ? -s->cadence_signed_rpm : s->cadence_signed_rpm; }
static inline bool bc_xds_backwards(const bc_xds_sample_t *s) { return s->cadence_signed_rpm < 0; }

/** Live state of one meter: last plausible sample + timing, fed from BLE, read by the UI. */
typedef struct {
    bool have;                 /* at least one plausible sample */
    bc_xds_sample_t last;
    uint32_t last_ms;          /* time of last plausible sample */
    uint32_t last_packet_ms;   /* time of last packet of any kind */
    uint32_t packets, rejected, short_packets;
    bool no_cad;               /* 0.7.2: the meter sends no cadence (standard Cycling Power without crank data): cadence = NO DATA */
} bc_xds_live_t;

typedef enum { BC_LIVE_NO_DATA = 0, BC_LIVE_OK } bc_live_status_t;

void bc_xds_live_reset(bc_xds_live_t *l);
/** Feed one raw packet received at now_ms. Returns true when it was decoded and plausible. */
bool bc_xds_live_feed(bc_xds_live_t *l, const uint8_t *b, size_t n, uint32_t now_ms);
/** 0.7.2: feed an already-decoded sample (standard Cycling Power meters, bc_cp). s = NULL counts a short packet,
 *  an implausible sample counts as rejected. has_cad = false: this sample carries no cadence. */
bool bc_xds_live_feed_sample(bc_xds_live_t *l, const bc_xds_sample_t *s, bool has_cad, uint32_t now_ms);
/** Live power / cadence at now_ms: BC_LIVE_NO_DATA when there is no sample younger than BC_STALE_MS. */
bc_live_status_t bc_xds_live_power(const bc_xds_live_t *l, uint32_t now_ms, int *watts);
bc_live_status_t bc_xds_live_cadence(const bc_xds_live_t *l, uint32_t now_ms, int *rpm, bool *backwards);
/** True when connected but nothing (not even an implausible packet) arrived for BC_LINK_SILENT_MS. */
bool bc_xds_link_silent(const bc_xds_live_t *l, uint32_t now_ms);

#ifdef __cplusplus
}
#endif
