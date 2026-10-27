/*
 * bc_core — BikeComputer Link 1.3 codec (coord/interfaces/BLE_CONTRACT.md v1.1, firmware 0.7.5). Same framing and TLV rules
 * as bc_link.h (unknown tags skipped, a field running past the end rejects the message, <= BC_LINK_MAX bytes).
 *
 *   0x08 APP_HELLO / 0x09 HELLO_ACK                       capability negotiation (cap 0x0800)
 *   0x90..0x96 RIDEQ_*                                    offline ride queue (cap 0x2000)
 *   0xA0..0xA3 STORAGE_*                                  storage status + safe clean-up (cap 0x4000)
 *   0xB0..0xB3 COACH_PLAN / PLAN_ACK / STATE / END        coach mirroring (cap 0x1000)
 *   EVENT 0x23 rides_pending                              (after HELLO)
 *   LIVE tags 11..15, DIAG_ACK tag 03 delete             (bc_link.h)
 * Pure C, host-tested; test/host/gen_link13_fixture.c writes the shared fixture for the iOS tests.
 */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "bc_link.h"

#ifdef __cplusplus
extern "C" {
#endif

#define BC_LINK13_MINOR 3
#define BC_CAP_HELLO 0x0800u
#define BC_CAP_COACH 0x1000u
#define BC_CAP_RIDE_QUEUE 0x2000u
#define BC_CAP_STORAGE 0x4000u
#define BC_CAP_DIAG_AUTO 0x8000u
#define BC_CAPS_LINK13 (BC_CAP_HELLO | BC_CAP_COACH | BC_CAP_RIDE_QUEUE | BC_CAP_STORAGE | BC_CAP_DIAG_AUTO)
/* every capability firmware >= 0.7.5 announces in INFO */
#define BC_CAPS_BOARD (BC_CAP_LIVE | BC_CAP_GPS_IN | BC_CAP_HR_IN | BC_CAP_WEATHER_IN | BC_CAP_RIDE_CTRL | BC_CAP_TIME_SYNC | \
                       BC_CAP_RIDE_SYNC | BC_CAP_WIFI_PROV | BC_CAP_PROFILE_SYNC | BC_CAP_SETTINGS | BC_CAP_DIAG_XFER | BC_CAPS_LINK13)

/* ---- HELLO */
typedef struct { uint8_t major, minor; uint32_t app_caps; char app_version[17]; } bc_hello_t;
typedef struct { uint32_t enabled_caps; } bc_hello_ack_t;
size_t bc_link_encode_hello(const bc_hello_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
/** False unless APP_HELLO with 03 app_caps. */
bool bc_link_decode_hello(const uint8_t *buf, size_t len, bc_hello_t *v);
size_t bc_link_encode_hello_ack(const bc_hello_ack_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
bool bc_link_decode_hello_ack(const uint8_t *buf, size_t len, bc_hello_ack_t *v);

/* ---- coach mirroring (§5) */
#define BC_COACH_MAX_SEGMENTS 64
#define BC_COACH_SEGS_PART0 9            /* part 0 also carries name / totals / crc: <= 9 segments keep it <= 180 B */
#define BC_COACH_SEGS_PART 14
#define BC_COACH_SEG_BYTES 10
#define BC_COACH_OPEN_ENDED 0xFFFFu      /* v1.1: segment duration "until the ride ends" (last segment only) */
#define BC_COACH_T0_RIDE_START 0xFFFFFFFFu
typedef enum { BC_TK_NONE = 0, BC_TK_POWER = 1, BC_TK_HR = 2, BC_TK_CADENCE = 3, BC_TK_RPE = 4 } bc_target_kind_t;
typedef enum { BC_WT_FREE = 0, BC_WT_RECOVERY, BC_WT_ENDURANCE, BC_WT_TEMPO, BC_WT_SWEET_SPOT, BC_WT_THRESHOLD, BC_WT_VO2MAX,
               BC_WT_ANAEROBIC, BC_WT_SPRINT, BC_WT_FTP_TEST, BC_WT_RACE, BC_WT_WARMUP, BC_WT_COOLDOWN, BC_WT_CUSTOM, BC_WT_COUNT } bc_workout_type_t;
typedef enum { BC_CI_NONE = 0, BC_CI_ON_TARGET, BC_CI_MORE_POWER, BC_CI_LESS_POWER, BC_CI_CADENCE_UP, BC_CI_CADENCE_DOWN,
               BC_CI_HOLD_STEADY, BC_CI_GET_READY, BC_CI_EASY, BC_CI_GO, BC_CI_COOL_DOWN, BC_CI_HR_HIGH, BC_CI_DRINK,
               BC_CI_PAUSED, BC_CI_DONE, BC_CI_NO_DATA, BC_CI_TARGET_CHANGED, BC_CI_COUNT } bc_coach_instr_t;
typedef struct { uint16_t dur_s; uint8_t type, kind; uint16_t lo, hi; uint8_t cad_lo, cad_hi; } bc_cseg_t;
typedef struct {
    uint32_t workout_id; uint16_t part, parts, first_segment;
    uint8_t nseg; bc_cseg_t seg[BC_COACH_SEGS_PART];
    bool head;                           /* part 0 fields present */
    char name[21]; uint16_t total_segments; uint32_t total_duration_s, plan_crc32, t0_elapsed_s;
} bc_coach_plan_msg_t;
typedef enum { BC_PLAN_COMPLETE = 0, BC_PLAN_PART_OK = 1, BC_PLAN_TOO_MANY = 2, BC_PLAN_CRC = 3, BC_PLAN_BUSY = 4 } bc_plan_status_t;
typedef struct { uint32_t workout_id; uint8_t status; uint16_t next_part; } bc_coach_plan_ack_t;
#define BC_CS_HAS(tag) (1u << ((tag) - 1))
typedef struct {
    uint32_t has;                        /* bit (tag-1) per field present */
    uint32_t workout_id; uint16_t seq;                                   /* 01 02 (required) */
    uint8_t type, kind; uint16_t lo, hi; uint8_t cad_lo, cad_hi;         /* 03..08 */
    uint16_t interval_index, interval_count, remaining_s, interval_dur_s; /* 09..0C */
    uint8_t next_type, next_kind; uint16_t next_lo, next_hi, next_dur_s;  /* 0D..11 */
    uint8_t instruction; char text[25];                                  /* 12 13 */
    uint8_t session_state, hr_src, zone, flags;                          /* 14..17 */
} bc_coach_state_t;
typedef enum { BC_SESS_NOT_STARTED = 0, BC_SESS_RUNNING = 1, BC_SESS_PAUSED = 2, BC_SESS_FINISHED = 3, BC_SESS_ABANDONED = 4 } bc_session_state_t;
#define BC_CSF_ADAPTED 0x01
#define BC_CSF_FTP_DERIVED 0x02
#define BC_CSF_WATCH_HR 0x04
typedef struct { uint32_t workout_id; uint8_t reason; } bc_coach_end_t;
size_t bc_cseg_put(const bc_cseg_t *s, uint8_t out[BC_COACH_SEG_BYTES]);
void bc_cseg_get(const uint8_t in[BC_COACH_SEG_BYTES], bc_cseg_t *s);
size_t bc_link_encode_coach_plan(const bc_coach_plan_msg_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
/** False unless COACH_PLAN with workout_id, part, parts, first_segment and a segment list of n x 10 bytes (n <= 14). */
bool bc_link_decode_coach_plan(const uint8_t *buf, size_t len, bc_coach_plan_msg_t *v);
size_t bc_link_encode_coach_plan_ack(const bc_coach_plan_ack_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
bool bc_link_decode_coach_plan_ack(const uint8_t *buf, size_t len, bc_coach_plan_ack_t *v);
size_t bc_link_encode_coach_state(const bc_coach_state_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
/** False unless COACH_STATE with workout_id and seq. The text is cut at a UTF-8 character boundary (<= 24 B). */
bool bc_link_decode_coach_state(const uint8_t *buf, size_t len, bc_coach_state_t *v);
size_t bc_link_encode_coach_end(const bc_coach_end_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
bool bc_link_decode_coach_end(const uint8_t *buf, size_t len, bc_coach_end_t *v);

/* ---- offline ride queue (§6) */
typedef enum { BC_RQ_RECORDING = 0, BC_RQ_UNSYNCED = 1, BC_RQ_TRANSFER = 2, BC_RQ_VERIFIED = 3, BC_RQ_SAMPLES_DELETED = 4 } bc_rideq_state_t;
#define BC_RQF_RECOVERED 0x02
#define BC_RQF_TRUNCATED 0x04
#define BC_RQF_SUMMARY_ONLY 0x08
#define BC_RQF_RAM_ONLY 0x10
typedef struct { uint32_t ride_id; uint8_t state; uint32_t samples_size, samples_crc, start_epoch_s, duration_s; uint8_t flags; uint32_t summary_crc; } bc_rideq_info_t;
typedef struct { uint16_t count, unsynced; uint32_t unsynced_bytes; } bc_rideq_list_end_t;
typedef struct { uint32_t ride_id, samples_crc, summary_crc; uint8_t delete_samples; } bc_rideq_ack_t;
#define BC_RQ_ERR_CRC 6                  /* v1.1: RIDEQ_ACK with a CRC that does not match (state unchanged) */
typedef struct { uint8_t unsynced; uint32_t newest_id; } bc_rides_pending_t;
#define BC_EVT_RIDES_PENDING 0x23
size_t bc_link_encode_rideq_list_req(uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
bool bc_link_decode_rideq_list_req(const uint8_t *buf, size_t len);
size_t bc_link_encode_rideq_info(const bc_rideq_info_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
bool bc_link_decode_rideq_info(const uint8_t *buf, size_t len, bc_rideq_info_t *v);
size_t bc_link_encode_rideq_list_end(const bc_rideq_list_end_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
bool bc_link_decode_rideq_list_end(const uint8_t *buf, size_t len, bc_rideq_list_end_t *v);
/* chunk request / chunk / error: byte-identical layout to DIAG_CHUNK_REQ / DIAG_CHUNK / DIAG_ERR, other type bytes */
size_t bc_link_encode_rideq_chunk_req(const bc_diag_chunk_req_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
bool bc_link_decode_rideq_chunk_req(const uint8_t *buf, size_t len, bc_diag_chunk_req_t *v);
size_t bc_link_encode_rideq_chunk(const bc_diag_chunk_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
bool bc_link_decode_rideq_chunk(const uint8_t *buf, size_t len, bc_diag_chunk_t *v);
size_t bc_link_encode_rideq_ack(const bc_rideq_ack_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
/** False unless RIDEQ_ACK with ride_id, samples_crc32 and summary_crc32. */
bool bc_link_decode_rideq_ack(const uint8_t *buf, size_t len, bc_rideq_ack_t *v);
size_t bc_link_encode_rideq_err(const bc_diag_err_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
bool bc_link_decode_rideq_err(const uint8_t *buf, size_t len, bc_diag_err_t *v);
size_t bc_link_encode_rides_pending(const bc_rides_pending_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
bool bc_link_decode_rides_pending(const uint8_t *buf, size_t len, bc_rides_pending_t *v);
/** summary_crc32 of a ride: CRC-32/ISO-HDLC over its SYNC_RIDE fields (every byte after the 8-byte header). 0 if it does not encode. */
uint32_t bc_ride_summary_crc(const bc_ride_summary_t *s);

/* ---- storage (§7) */
typedef struct {
    uint8_t state; char code[20];
    uint32_t fs_total_kb, fs_free_kb; uint8_t crash_partition; uint32_t crash_dump_bytes;
    uint16_t reports_stored, reports_unsent; uint32_t diag_bytes;
    uint16_t rides_unsynced; uint32_t ride_bytes_unsynced, ride_bytes_synced;
    uint32_t app_slot_kb, app_used_kb; uint16_t nvs_used_entries, nvs_free_entries, root_free_slots, root_bad_entries;
    uint8_t health;                      /* 0 good, 1 degraded, 2 failed */
} bc_storage_status_t;
#define BC_CLEAN_REPORTS 0x01
#define BC_CLEAN_SAMPLES 0x02
#define BC_CLEAN_CACHES 0x04
typedef enum { BC_CLEAN_DONE = 0, BC_CLEAN_NOTHING = 1, BC_CLEAN_REFUSED = 2, BC_CLEAN_BUSY = 3 } bc_clean_status_t;
typedef struct { uint8_t what; } bc_storage_clean_req_t;
typedef struct { uint8_t status; uint32_t bytes_freed; uint16_t items; } bc_storage_clean_result_t;
size_t bc_link_encode_storage_status_req(uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
bool bc_link_decode_storage_status_req(const uint8_t *buf, size_t len);
size_t bc_link_encode_storage_status(const bc_storage_status_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
bool bc_link_decode_storage_status(const uint8_t *buf, size_t len, bc_storage_status_t *v);
size_t bc_link_encode_storage_clean_req(const bc_storage_clean_req_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
bool bc_link_decode_storage_clean_req(const uint8_t *buf, size_t len, bc_storage_clean_req_t *v);
size_t bc_link_encode_storage_clean_result(const bc_storage_clean_result_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
bool bc_link_decode_storage_clean_result(const uint8_t *buf, size_t len, bc_storage_clean_result_t *v);
/** v1.1 rule: clean-up is allowed for storage state 0 OK, 1 full, 6 reports full; refused for 2/3/4/5/7 (damaged / not checked). */
bool bc_storage_clean_allowed(uint8_t stor_state);
/** Storage health byte from the state: 0 good (OK), 1 degraded (full / reports full / not checked), 2 failed (damaged). */
uint8_t bc_storage_health(uint8_t stor_state);

#ifdef __cplusplus
}
#endif
