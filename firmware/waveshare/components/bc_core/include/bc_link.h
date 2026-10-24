/*
 * bc_core — "BikeComputer Link" protocol v1 codec (ESP32 <-> companion phone app). Spec: docs/BLE_LINK_PROTOCOL.md.
 *
 * Every message = 8-byte header (type u8, flags u8, seq u16, sender time ms u32) + tagged fields
 * (tag u8, len u8, value, little-endian). Unknown tags are skipped (forward compatible); a field whose length does not
 * match its type is ignored; a message whose fields run past its end is rejected. Pure C, host-tested; the iOS /
 * Android apps implement the same rules (shared Kotlin Multiplatform module) and are checked against the same vectors.
 */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BC_LINK_VER_MAJOR 1
#define BC_LINK_VER_MINOR 0
#define BC_LINK_HDR 8
#define BC_LINK_MAX 180            /* fits one notification at the MTU 185 iOS negotiates; clients must request >= 185 */
#define BC_LINK_NONE16 0xFFFFu     /* "no value / no data" for u16 ages and readings */

typedef enum {
    BC_MSG_INFO = 0x01,
    BC_MSG_LIVE = 0x10,
    BC_MSG_IN_TIME = 0x20, BC_MSG_IN_GPS = 0x21, BC_MSG_IN_HR = 0x22, BC_MSG_IN_WEATHER = 0x23, BC_MSG_IN_BATTERY = 0x24,
    BC_MSG_CTRL_REQ = 0x30, BC_MSG_CTRL_RESP = 0x31,
    BC_MSG_EVENT = 0x40,
} bc_msg_type_t;

/* sources of a reading (who measured it) */
typedef enum { BC_SRC_UNKNOWN = 0, BC_SRC_XDS = 1, BC_SRC_BLE_STRAP = 2, BC_SRC_PHONE_GPS = 3, BC_SRC_APPLE_WATCH = 4,
               BC_SRC_WEAR_OS = 5, BC_SRC_PHONE_STRAP = 6, BC_SRC_ONBOARD_GPS = 7, BC_SRC_WEATHERKIT = 8, BC_SRC_OPEN_METEO = 9,
               BC_SRC_DEMO = 0x7F } bc_src_t;

typedef enum { BC_CMD_START = 1, BC_CMD_PAUSE = 2, BC_CMD_RESUME = 3, BC_CMD_STOP_REQUEST = 4, BC_CMD_STOP_CONFIRM = 5 } bc_cmd_t;
typedef enum { BC_RESP_OK = 0, BC_RESP_BAD_STATE = 1, BC_RESP_NEEDS_CONFIRM = 2, BC_RESP_UNKNOWN = 3, BC_RESP_WRONG_RIDE = 4 } bc_resp_t;

typedef struct { uint8_t type, flags; uint16_t seq; uint32_t t_ms; } bc_link_hdr_t;

/* ---- generic writer / reader */
typedef struct { uint8_t *b; size_t cap, len; bool ok; } bc_lw_t;
void bc_lw_begin(bc_lw_t *w, uint8_t *buf, size_t cap, bc_msg_type_t type, uint16_t seq, uint32_t t_ms);
void bc_lw_u8(bc_lw_t *w, uint8_t tag, uint8_t v);
void bc_lw_u16(bc_lw_t *w, uint8_t tag, uint16_t v);
void bc_lw_u32(bc_lw_t *w, uint8_t tag, uint32_t v);
void bc_lw_u64(bc_lw_t *w, uint8_t tag, uint64_t v);
void bc_lw_s16(bc_lw_t *w, uint8_t tag, int16_t v);
void bc_lw_s32(bc_lw_t *w, uint8_t tag, int32_t v);
size_t bc_lw_end(bc_lw_t *w);                            /* 0 when it did not fit */

typedef struct { const uint8_t *b; size_t len, pos; } bc_lr_t;
/** Parses the header; false for a short message or a field list that runs past the end. */
bool bc_lr_begin(bc_lr_t *r, const uint8_t *buf, size_t len, bc_link_hdr_t *h);
/** Next field: false at the end. *val points into the message, *vlen is its length. */
bool bc_lr_next(bc_lr_t *r, uint8_t *tag, const uint8_t **val, uint8_t *vlen);
uint64_t bc_lr_uint(const uint8_t *v, uint8_t n);       /* little-endian, n = 1..8 */
int64_t bc_lr_sint(const uint8_t *v, uint8_t n);

/* ---- LIVE (ESP32 -> phone, 1 Hz). Ages in ms, BC_LINK_NONE16 = no value. */
typedef struct {
    bool power_ok; uint16_t power_w, power_age_ms;
    bool cad_ok; uint8_t cadence_rpm; uint16_t cad_age_ms;
    bool hr_ok; uint8_t hr_bpm; uint8_t hr_src; uint16_t hr_age_ms;
    uint8_t ride_state; uint16_t ride_id; uint32_t elapsed_s; uint32_t distance_m;
    uint8_t cue_id; uint8_t battery_pct; uint8_t meter_link; uint16_t meter_gaps;
    bool demo;                                           /* values are SIMULATED (demo mode) */
} bc_live_t;
size_t bc_link_encode_live(const bc_live_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
bool bc_link_decode_live(const uint8_t *buf, size_t len, bc_live_t *v);

/* ---- phone inputs */
typedef struct { uint64_t epoch_ms; uint16_t uncertainty_ms; int16_t tz_min; } bc_in_time_t;
typedef struct {
    int32_t lat_e7, lon_e7; bool alt_ok; int32_t alt_dm; uint16_t hacc_dm, vacc_dm;    /* accuracy in decimetres, 0xFFFF unknown */
    bool speed_ok; uint16_t speed_cms; bool course_ok; uint16_t course_cdeg; uint64_t fix_epoch_ms; uint8_t src;
} bc_in_gps_t;
typedef struct { uint8_t bpm; uint8_t src; uint64_t sample_epoch_ms; uint8_t quality; } bc_in_hr_t;
typedef struct { bool temp_ok; int16_t temp_dc; bool wind_ok; uint16_t wind_cms; uint16_t wind_deg; uint8_t humidity; uint8_t provider; uint64_t obs_epoch_ms; } bc_in_weather_t;
typedef struct { uint8_t phone_pct, watch_pct; } bc_in_battery_t;          /* 0xFF unknown */

size_t bc_link_encode_time(const bc_in_time_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
size_t bc_link_encode_gps(const bc_in_gps_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
size_t bc_link_encode_hr(const bc_in_hr_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
size_t bc_link_encode_weather(const bc_in_weather_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
bool bc_link_decode_time(const uint8_t *buf, size_t len, bc_in_time_t *v);
/** GPS is rejected (false) when latitude/longitude are missing or out of range, or the source is not a GPS. */
bool bc_link_decode_gps(const uint8_t *buf, size_t len, bc_in_gps_t *v);
/** Heart rate is rejected outside 25..250 bpm or without a source (never shown as a real value). */
bool bc_link_decode_hr(const uint8_t *buf, size_t len, bc_in_hr_t *v);
bool bc_link_decode_weather(const uint8_t *buf, size_t len, bc_in_weather_t *v);
bool bc_link_decode_battery(const uint8_t *buf, size_t len, bc_in_battery_t *v);

/* ---- ride control */
typedef struct { uint16_t req_id; uint8_t cmd; uint16_t ride_id; } bc_ctrl_req_t;
typedef struct { uint16_t req_id; uint8_t status; uint8_t ride_state; uint16_t ride_id; } bc_ctrl_resp_t;
size_t bc_link_encode_ctrl_req(const bc_ctrl_req_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
bool bc_link_decode_ctrl_req(const uint8_t *buf, size_t len, bc_ctrl_req_t *v);
size_t bc_link_encode_ctrl_resp(const bc_ctrl_resp_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
bool bc_link_decode_ctrl_resp(const uint8_t *buf, size_t len, bc_ctrl_resp_t *v);

/* ---- INFO characteristic value */
typedef struct { uint8_t ver_major, ver_minor; char fw[24]; char name[24]; uint32_t caps; uint16_t max_msg; } bc_info_t;
#define BC_CAP_LIVE 0x01
#define BC_CAP_GPS_IN 0x02
#define BC_CAP_HR_IN 0x04
#define BC_CAP_WEATHER_IN 0x08
#define BC_CAP_RIDE_CTRL 0x10
#define BC_CAP_TIME_SYNC 0x20
#define BC_CAP_RIDE_SYNC 0x40      /* Phase 5 */
size_t bc_link_encode_info(const bc_info_t *v, uint8_t *buf, size_t cap);
bool bc_link_decode_info(const uint8_t *buf, size_t len, bc_info_t *v);

/** Ride-control rules on the ESP32 side: what a request does to the ride given its current state (pure decision). */
typedef enum { BC_ACT_NONE = 0, BC_ACT_START, BC_ACT_PAUSE, BC_ACT_RESUME, BC_ACT_ARM_STOP, BC_ACT_STOP } bc_ctrl_action_t;
bc_ctrl_action_t bc_link_ctrl_decide(const bc_ctrl_req_t *q, uint8_t ride_state, uint16_t ride_id, bool stop_armed, uint8_t *status);

/** Short display name of a source: "XDS", "STRAP", "PHONE GPS", "WATCH", "WEAR OS", "PHONE", "GPS", "DEMO", "?" */
const char *bc_src_name(uint8_t src);
/** Distance in metres between two positions (lat/lon × 1e7). Equirectangular: exact enough for 1–60 s GPS steps. */
uint32_t bc_geo_dist_m(int32_t lat1_e7, int32_t lon1_e7, int32_t lat2_e7, int32_t lon2_e7);

#ifdef __cplusplus
}
#endif
