/*
 * bc_core — coach mirroring on the board (BLE_CONTRACT.md v1.1 §5, firmware 0.7.5). Pure C, host-tested.
 *
 * The phone (Cyclift) is the coach: it sends ONE workout definition (COACH_PLAN, multi-part, CRC-checked) and the live coach
 * state (COACH_STATE, on change + every 5 s). The board only displays it, and when the phone link drops it keeps following
 * the stored plan on its own ride timeline (coach_mode 2) or holds the last targets (coach_mode 3). No adaptation happens
 * on the board. Heart-rate honesty: when the phone's coach used Apple Watch HR (hr_src 4) and the phone is gone, the board
 * says "NO HR - RIDE BY FEEL" instead of pretending to have a heart rate.
 */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "bc_link13.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum { BC_CM_NONE = 0, BC_CM_FOLLOWING = 1, BC_CM_PLAN_OFFLINE = 2, BC_CM_LAST_TARGET = 3 } bc_cm_mode_t;
#define BC_CM_STATE_STALE_MS 12000u      /* no COACH_STATE for 12 s on a live link (keepalive is 5 s) = phone lost */

typedef struct {
    /* the stored plan (RAM only, one at a time) */
    bool plan_ok; uint32_t plan_id; char name[21]; uint16_t nseg; uint32_t total_dur_s, t0_elapsed_s;
    bc_cseg_t seg[BC_COACH_MAX_SEGMENTS];
    /* plan being received */
    bool rx_active; uint32_t rx_id; uint16_t rx_parts, rx_next_part, rx_total, rx_n; uint32_t rx_crc, rx_total_dur, rx_t0; char rx_name[21];
    bc_cseg_t rx_seg[BC_COACH_MAX_SEGMENTS];
    /* the last applied coach state */
    bool have_state; bc_coach_state_t st; uint32_t st_rx_ms;
    uint32_t ended_id; bool ended;       /* COACH_END received for this workout */
    uint32_t states_applied, states_ignored, plans_ok, plans_bad;
} bc_cmirror_t;

typedef struct {
    uint8_t mode;                        /* bc_cm_mode_t */
    uint8_t type, kind; uint16_t lo, hi; uint8_t cad_lo, cad_hi;
    uint8_t instruction; char text[25];
    bool has_remaining; uint16_t remaining_s;
    bool has_next; uint8_t next_type, next_kind; uint16_t next_lo, next_hi, next_dur_s;
    uint16_t interval_index, interval_count;
    uint8_t hr_src, session_state, zone, flags;
    bool no_hr;                          /* HR targets, watch HR gone with the phone: "NO HR - RIDE BY FEEL" */
    bool done;                           /* offline: past the end of the plan */
    uint16_t seq; uint32_t workout_id;
} bc_cm_view_t;

void bc_cm_init(bc_cmirror_t *m);
/** One COACH_PLAN part. Returns bc_plan_status_t; *next_part = the part the board expects next. */
uint8_t bc_cm_plan_part(bc_cmirror_t *m, const bc_coach_plan_msg_t *p, uint16_t *next_part);
/** A COACH_STATE: applied (true) only when it is for a new workout or its seq is strictly newer (serial order mod 2^16). */
bool bc_cm_state(bc_cmirror_t *m, const bc_coach_state_t *s, uint32_t now_ms);
/** COACH_END: the workout stops being shown (plan and state cleared when they belong to it). */
void bc_cm_end(bc_cmirror_t *m, uint32_t workout_id);
/** What the board shows now. phone_live = the phone link is up and Link 1.3 COACH is enabled on it; elapsed_s = the board's
 *  ride clock (LIVE 0A). */
void bc_cm_view(const bc_cmirror_t *m, bool phone_live, uint32_t now_ms, uint32_t elapsed_s, bc_cm_view_t *v);
/** "ON TARGET", "MORE POWER" ... (ASCII, <= 20 chars); "" for none / unknown */
const char *bc_cm_instr_text(uint8_t instruction);
/** "ENDURANCE", "SWEET SPOT" ... ("WORKOUT" for unknown) */
const char *bc_cm_type_name(uint8_t type);
/** Colour class of an instruction (bc_coach.h levels): 0 info, 1 good, 2 up, 3 down, 4 warn */
uint8_t bc_cm_instr_level(uint8_t instruction);
/** The coach card for the round screen: up to 9 short lines (ASCII, <= 27 chars each), e.g.
 *  CYCLIFT COACH / ENDURANCE / POWER 145 W / TARGET 140-155 W / CADENCE 84 / TARGET 80-90 / COACH: ON TARGET /
 *  NEXT: RECOVERY - 3 MIN / status ("PHONE LOST - 2:41 LEFT", "NO PHONE - LAST TARGET"). Live values < 0 = no data ("--"). Returns the number of lines. */
#define BC_CM_CARD_LINES 9
#define BC_CM_LINE 28
int bc_cm_card(const bc_cm_view_t *v, int power_w, int cad_rpm, int hr_bpm, char lines[BC_CM_CARD_LINES][BC_CM_LINE]);
/** CRC-32/ISO-HDLC of segments in order, 10 bytes each (COACH_PLAN 09 plan_crc32). */
uint32_t bc_cm_plan_crc(const bc_cseg_t *seg, int n);

#ifdef __cplusplus
}
#endif
