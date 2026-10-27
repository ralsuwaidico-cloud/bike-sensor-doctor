/*
 * Link 1.3 on the board (firmware 0.7.5, BLE_CONTRACT.md v1.1): APP_HELLO gate, coach mirroring, offline ride queue,
 * storage status + safe clean-up, diagnostics auto-delete. Portable (plat.h + bc_core): the device and the PC harness run
 * the same code. Called by app_psvc (Control writes, notifications, connection edges) and app.c (LIVE tags, the coach view
 * for the ride screens, ride closed).
 *
 * Rules
 *  - nothing new is sent before an APP_HELLO enabled it on this connection; a 1.3 request for a capability that is not
 *    enabled is ignored (an app without HELLO sees exactly Link 1.2.3);
 *  - the coach plan lives in RAM only (PSRAM), one plan at a time; the board never adapts targets on its own;
 *  - a ride's samples are deleted only after a RIDEQ_ACK whose two CRCs match, with delete_samples = 1, and never while
 *    a ride is recording; unsynced rides and unsent reports are never deleted by any command;
 *  - STORAGE_CLEAN is refused for a damaged or unchecked storage (v1.1: states 2/3/4/5/7);
 *  - all state is allocated once in PSRAM (plat_alloc_ext): internal RAM stays for the Bluetooth stack.
 */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "bc_link13.h"
#include "bc_cmirror.h"

#ifdef __cplusplus
extern "C" {
#endif

void app_link13_init(void);
/** A message the phone wrote on Control. True when it was a Link 1.3 message (handled or ignored by the gate). */
bool app_link13_write(const uint8_t *msg, size_t n, uint32_t now_ms);
/** Next Link 1.3 notification: *chr 0 = Control, 2 = Events. 0 = nothing due (chunks are paced: LIVE first). */
size_t app_link13_next(uint8_t *chr, uint8_t *buf, size_t cap, uint32_t now_ms);
/** Connection edge (encrypted + listening / gone): a new connection starts without any 1.3 capability until HELLO. */
void app_link13_phone_ready(bool ready);
/** A ride was closed (saved / kept in RAM / recovered): rides_pending is announced to a phone with RIDE_QUEUE. */
void app_link13_ride_closed(void);
/** LIVE tags 11..15 (coach_seq + coach_mode, storage_state, rides_unsynced, bt_flags). */
void app_link13_live(bc_live_t *l, uint32_t now_ms);
/** The coach view for the ride screens (false = no Cyclift workout to show). */
bool app_link13_coach(bc_cm_view_t *v);
/** Capabilities enabled by the current connection's APP_HELLO (0 = none / Link 1.2.3). */
uint32_t app_link13_enabled(void);

typedef struct {
    uint32_t hellos, plan_parts, plans_ok, plans_bad, states_applied, states_ignored, ends;
    uint32_t rq_lists, rq_chunks, rq_acks_ok, rq_acks_bad, rq_busy, rq_deleted, cleans, clean_refused, ignored_gate;
    uint16_t unsynced; uint32_t unsynced_bytes;
} app_link13_stats_t;
void app_link13_stats(app_link13_stats_t *out);

#ifdef __cplusplus
}
#endif
