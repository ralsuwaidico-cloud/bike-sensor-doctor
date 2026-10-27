#include "bc_link.h"
#include <string.h>
#include <math.h>

/* ---- writer */
void bc_lw_begin(bc_lw_t *w, uint8_t *buf, size_t cap, bc_msg_type_t type, uint16_t seq, uint32_t t_ms)
{
    w->b = buf; w->cap = cap; w->len = 0; w->ok = cap >= BC_LINK_HDR;
    if (!w->ok) return;
    buf[0] = (uint8_t)type; buf[1] = 0; buf[2] = (uint8_t)seq; buf[3] = (uint8_t)(seq >> 8);
    for (int i = 0; i < 4; i++) buf[4 + i] = (uint8_t)(t_ms >> (8 * i));
    w->len = BC_LINK_HDR;
}

static void put(bc_lw_t *w, uint8_t tag, uint64_t v, uint8_t n)
{
    if (!w->ok || w->len + 2 + n > w->cap) { w->ok = false; return; }
    w->b[w->len++] = tag; w->b[w->len++] = n;
    for (int i = 0; i < n; i++) w->b[w->len++] = (uint8_t)(v >> (8 * i));
}
void bc_lw_u8(bc_lw_t *w, uint8_t tag, uint8_t v) { put(w, tag, v, 1); }
void bc_lw_u16(bc_lw_t *w, uint8_t tag, uint16_t v) { put(w, tag, v, 2); }
void bc_lw_u32(bc_lw_t *w, uint8_t tag, uint32_t v) { put(w, tag, v, 4); }
void bc_lw_u64(bc_lw_t *w, uint8_t tag, uint64_t v) { put(w, tag, v, 8); }
void bc_lw_s16(bc_lw_t *w, uint8_t tag, int16_t v) { put(w, tag, (uint16_t)v, 2); }
void bc_lw_s32(bc_lw_t *w, uint8_t tag, int32_t v) { put(w, tag, (uint32_t)v, 4); }
size_t bc_lw_end(bc_lw_t *w) { return w->ok ? w->len : 0; }

void bc_lw_bytes(bc_lw_t *w, uint8_t tag, const void *p, size_t n)
{
    if (!w->ok || n > 255 || w->len + 2 + n > w->cap) { w->ok = false; return; }
    w->b[w->len++] = tag; w->b[w->len++] = (uint8_t)n; memcpy(w->b + w->len, p, n); w->len += n;
}

static void put_str(bc_lw_t *w, uint8_t tag, const char *s)
{
    size_t n = strlen(s); if (n > 31) n = 31;
    if (!w->ok || w->len + 2 + n > w->cap) { w->ok = false; return; }
    w->b[w->len++] = tag; w->b[w->len++] = (uint8_t)n; memcpy(w->b + w->len, s, n); w->len += n;
}

/* ---- reader */
bool bc_lr_begin(bc_lr_t *r, const uint8_t *b, size_t len, bc_link_hdr_t *h)
{
    if (!b || len < BC_LINK_HDR || len > 512) return false;
    h->type = b[0]; h->flags = b[1]; h->seq = (uint16_t)(b[2] | (b[3] << 8));
    h->t_ms = (uint32_t)b[4] | ((uint32_t)b[5] << 8) | ((uint32_t)b[6] << 16) | ((uint32_t)b[7] << 24);
    /* validate the whole field list first: a truncated message is rejected, not half-applied */
    size_t p = BC_LINK_HDR;
    while (p < len) { if (p + 2 > len || p + 2 + b[p + 1] > len) return false; p += 2 + b[p + 1]; }
    r->b = b; r->len = len; r->pos = BC_LINK_HDR;
    return true;
}

bool bc_lr_next(bc_lr_t *r, uint8_t *tag, const uint8_t **val, uint8_t *vlen)
{
    if (r->pos + 2 > r->len) return false;
    *tag = r->b[r->pos]; *vlen = r->b[r->pos + 1]; *val = r->b + r->pos + 2;
    r->pos += 2 + *vlen;
    return true;
}

uint64_t bc_lr_uint(const uint8_t *v, uint8_t n) { uint64_t x = 0; for (int i = n - 1; i >= 0; i--) x = (x << 8) | v[i]; return x; }
int64_t bc_lr_sint(const uint8_t *v, uint8_t n)
{
    uint64_t x = bc_lr_uint(v, n);
    if (n < 8 && (x >> (8 * n - 1)) & 1) x |= ~0ULL << (8 * n);
    return (int64_t)x;
}

#define FIELD(want) if (n != (want)) continue

/* ---- LIVE */
size_t bc_link_encode_live(const bc_live_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_LIVE, seq, t_ms);
    if (v->power_ok) { bc_lw_u16(&w, 0x01, v->power_w); bc_lw_u16(&w, 0x02, v->power_age_ms); }
    if (v->cad_ok) { bc_lw_u8(&w, 0x03, v->cadence_rpm); bc_lw_u16(&w, 0x04, v->cad_age_ms); }
    if (v->hr_ok) { bc_lw_u8(&w, 0x05, v->hr_bpm); bc_lw_u8(&w, 0x06, v->hr_src); bc_lw_u16(&w, 0x07, v->hr_age_ms); }
    bc_lw_u8(&w, 0x08, v->ride_state); bc_lw_u16(&w, 0x09, v->ride_id); bc_lw_u32(&w, 0x0A, v->elapsed_s); bc_lw_u32(&w, 0x0B, v->distance_m);
    bc_lw_u8(&w, 0x0C, v->cue_id); bc_lw_u8(&w, 0x0D, v->battery_pct); bc_lw_u8(&w, 0x0E, v->meter_link); bc_lw_u16(&w, 0x0F, v->meter_gaps);
    if (v->demo) bc_lw_u8(&w, 0x10, 1);
    return bc_lw_end(&w);
}

bool bc_link_decode_live(const uint8_t *buf, size_t len, bc_live_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x;
    memset(v, 0, sizeof *v);
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_LIVE) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        switch (t) {
        case 0x01: FIELD(2); v->power_ok = true; v->power_w = (uint16_t)bc_lr_uint(x, n); break;
        case 0x02: FIELD(2); v->power_age_ms = (uint16_t)bc_lr_uint(x, n); break;
        case 0x03: FIELD(1); v->cad_ok = true; v->cadence_rpm = x[0]; break;
        case 0x04: FIELD(2); v->cad_age_ms = (uint16_t)bc_lr_uint(x, n); break;
        case 0x05: FIELD(1); v->hr_ok = true; v->hr_bpm = x[0]; break;
        case 0x06: FIELD(1); v->hr_src = x[0]; break;
        case 0x07: FIELD(2); v->hr_age_ms = (uint16_t)bc_lr_uint(x, n); break;
        case 0x08: FIELD(1); v->ride_state = x[0]; break;
        case 0x09: FIELD(2); v->ride_id = (uint16_t)bc_lr_uint(x, n); break;
        case 0x0A: FIELD(4); v->elapsed_s = (uint32_t)bc_lr_uint(x, n); break;
        case 0x0B: FIELD(4); v->distance_m = (uint32_t)bc_lr_uint(x, n); break;
        case 0x0C: FIELD(1); v->cue_id = x[0]; break;
        case 0x0D: FIELD(1); v->battery_pct = x[0]; break;
        case 0x0E: FIELD(1); v->meter_link = x[0]; break;
        case 0x0F: FIELD(2); v->meter_gaps = (uint16_t)bc_lr_uint(x, n); break;
        case 0x10: FIELD(1); v->demo = x[0] != 0; break;
        default: break;                                   /* unknown tag: skipped */
        }
    }
    return true;
}

/* ---- inputs */
size_t bc_link_encode_time(const bc_in_time_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_IN_TIME, seq, t_ms);
    bc_lw_u64(&w, 0x01, v->epoch_ms); bc_lw_u16(&w, 0x02, v->uncertainty_ms); bc_lw_s16(&w, 0x03, v->tz_min);
    return bc_lw_end(&w);
}
bool bc_link_decode_time(const uint8_t *buf, size_t len, bc_in_time_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x; bool have = false;
    memset(v, 0, sizeof *v); v->uncertainty_ms = BC_LINK_NONE16;
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_IN_TIME) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 8) { v->epoch_ms = bc_lr_uint(x, n); have = true; }
        else if (t == 0x02 && n == 2) v->uncertainty_ms = (uint16_t)bc_lr_uint(x, n);
        else if (t == 0x03 && n == 2) v->tz_min = (int16_t)bc_lr_sint(x, n);
    }
    /* sanity: after 2024-01-01 and before 2100 */
    return have && v->epoch_ms > 1704067200000ULL && v->epoch_ms < 4102444800000ULL;
}

size_t bc_link_encode_gps(const bc_in_gps_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_IN_GPS, seq, t_ms);
    bc_lw_s32(&w, 0x01, v->lat_e7); bc_lw_s32(&w, 0x02, v->lon_e7);
    if (v->alt_ok) bc_lw_s32(&w, 0x03, v->alt_dm);
    bc_lw_u16(&w, 0x04, v->hacc_dm); bc_lw_u16(&w, 0x05, v->vacc_dm);
    if (v->speed_ok) bc_lw_u16(&w, 0x06, v->speed_cms);
    if (v->course_ok) bc_lw_u16(&w, 0x07, v->course_cdeg);
    bc_lw_u64(&w, 0x08, v->fix_epoch_ms); bc_lw_u8(&w, 0x09, v->src);
    return bc_lw_end(&w);
}
bool bc_link_decode_gps(const uint8_t *buf, size_t len, bc_in_gps_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x; bool la = false, lo = false;
    memset(v, 0, sizeof *v); v->hacc_dm = v->vacc_dm = BC_LINK_NONE16;
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_IN_GPS) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        switch (t) {
        case 0x01: FIELD(4); v->lat_e7 = (int32_t)bc_lr_sint(x, n); la = true; break;
        case 0x02: FIELD(4); v->lon_e7 = (int32_t)bc_lr_sint(x, n); lo = true; break;
        case 0x03: FIELD(4); v->alt_dm = (int32_t)bc_lr_sint(x, n); v->alt_ok = true; break;
        case 0x04: FIELD(2); v->hacc_dm = (uint16_t)bc_lr_uint(x, n); break;
        case 0x05: FIELD(2); v->vacc_dm = (uint16_t)bc_lr_uint(x, n); break;
        case 0x06: FIELD(2); v->speed_cms = (uint16_t)bc_lr_uint(x, n); v->speed_ok = v->speed_cms <= 3000; break;   /* <= 108 km/h */
        case 0x07: FIELD(2); v->course_cdeg = (uint16_t)bc_lr_uint(x, n); v->course_ok = v->course_cdeg < 36000; break;
        case 0x08: FIELD(8); v->fix_epoch_ms = bc_lr_uint(x, n); break;
        case 0x09: FIELD(1); v->src = x[0]; break;
        default: break;
        }
    }
    if (!la || !lo) return false;
    if (v->lat_e7 < -900000000 || v->lat_e7 > 900000000 || v->lon_e7 < -1800000000 || v->lon_e7 > 1800000000) return false;
    return v->src == BC_SRC_PHONE_GPS || v->src == BC_SRC_ONBOARD_GPS;
}

size_t bc_link_encode_hr(const bc_in_hr_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_IN_HR, seq, t_ms);
    bc_lw_u8(&w, 0x01, v->bpm); bc_lw_u8(&w, 0x02, v->src); bc_lw_u64(&w, 0x03, v->sample_epoch_ms); bc_lw_u8(&w, 0x04, v->quality);
    return bc_lw_end(&w);
}
bool bc_link_decode_hr(const uint8_t *buf, size_t len, bc_in_hr_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x; bool have = false;
    memset(v, 0, sizeof *v);
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_IN_HR) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 1) { v->bpm = x[0]; have = true; }
        else if (t == 0x02 && n == 1) v->src = x[0];
        else if (t == 0x03 && n == 8) v->sample_epoch_ms = bc_lr_uint(x, n);
        else if (t == 0x04 && n == 1) v->quality = x[0];
    }
    return have && v->bpm >= 25 && v->bpm <= 250 && v->src != BC_SRC_UNKNOWN;
}

size_t bc_link_encode_weather(const bc_in_weather_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_IN_WEATHER, seq, t_ms);
    if (v->temp_ok) bc_lw_s16(&w, 0x01, v->temp_dc);
    if (v->wind_ok) { bc_lw_u16(&w, 0x02, v->wind_cms); bc_lw_u16(&w, 0x03, v->wind_deg); }
    bc_lw_u8(&w, 0x04, v->humidity); bc_lw_u8(&w, 0x05, v->provider); bc_lw_u64(&w, 0x06, v->obs_epoch_ms);
    return bc_lw_end(&w);
}
bool bc_link_decode_weather(const uint8_t *buf, size_t len, bc_in_weather_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x;
    memset(v, 0, sizeof *v); v->humidity = 0xFF;
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_IN_WEATHER) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 2) { v->temp_dc = (int16_t)bc_lr_sint(x, n); v->temp_ok = v->temp_dc > -600 && v->temp_dc < 650; }
        else if (t == 0x02 && n == 2) { v->wind_cms = (uint16_t)bc_lr_uint(x, n); v->wind_ok = true; }
        else if (t == 0x03 && n == 2) v->wind_deg = (uint16_t)bc_lr_uint(x, n);
        else if (t == 0x04 && n == 1) v->humidity = x[0];
        else if (t == 0x05 && n == 1) v->provider = x[0];
        else if (t == 0x06 && n == 8) v->obs_epoch_ms = bc_lr_uint(x, n);
    }
    return (v->temp_ok || v->wind_ok) && v->provider != BC_SRC_UNKNOWN;     /* weather always names its provider */
}

bool bc_link_decode_battery(const uint8_t *buf, size_t len, bc_in_battery_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x;
    v->phone_pct = v->watch_pct = 0xFF;
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_IN_BATTERY) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 1 && x[0] <= 100) v->phone_pct = x[0];
        else if (t == 0x02 && n == 1 && x[0] <= 100) v->watch_pct = x[0];
    }
    return true;
}

/* ---- control */
size_t bc_link_encode_ctrl_req(const bc_ctrl_req_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_CTRL_REQ, seq, t_ms);
    bc_lw_u16(&w, 0x01, v->req_id); bc_lw_u8(&w, 0x02, v->cmd); bc_lw_u16(&w, 0x03, v->ride_id);
    return bc_lw_end(&w);
}
bool bc_link_decode_ctrl_req(const uint8_t *buf, size_t len, bc_ctrl_req_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x; bool have = false;
    memset(v, 0, sizeof *v);
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_CTRL_REQ) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 2) v->req_id = (uint16_t)bc_lr_uint(x, n);
        else if (t == 0x02 && n == 1) { v->cmd = x[0]; have = true; }
        else if (t == 0x03 && n == 2) v->ride_id = (uint16_t)bc_lr_uint(x, n);
    }
    return have;
}
size_t bc_link_encode_ctrl_resp(const bc_ctrl_resp_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_CTRL_RESP, seq, t_ms);
    bc_lw_u16(&w, 0x01, v->req_id); bc_lw_u8(&w, 0x02, v->status); bc_lw_u8(&w, 0x03, v->ride_state); bc_lw_u16(&w, 0x04, v->ride_id);
    return bc_lw_end(&w);
}
bool bc_link_decode_ctrl_resp(const uint8_t *buf, size_t len, bc_ctrl_resp_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x;
    memset(v, 0, sizeof *v);
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_CTRL_RESP) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 2) v->req_id = (uint16_t)bc_lr_uint(x, n);
        else if (t == 0x02 && n == 1) v->status = x[0];
        else if (t == 0x03 && n == 1) v->ride_state = x[0];
        else if (t == 0x04 && n == 2) v->ride_id = (uint16_t)bc_lr_uint(x, n);
    }
    return true;
}

/* ---- info */
size_t bc_link_encode_info(const bc_info_t *v, uint8_t *buf, size_t cap)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_INFO, 0, 0);
    bc_lw_u8(&w, 0x01, v->ver_major); bc_lw_u8(&w, 0x02, v->ver_minor);
    put_str(&w, 0x03, v->fw); put_str(&w, 0x04, v->name);
    bc_lw_u32(&w, 0x05, v->caps); bc_lw_u16(&w, 0x06, v->max_msg);
    if (v->has_device_id) bc_lw_bytes(&w, 0x07, v->device_id, 6);
    return bc_lw_end(&w);
}
bool bc_link_decode_info(const uint8_t *buf, size_t len, bc_info_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x;
    memset(v, 0, sizeof *v);
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_INFO) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 1) v->ver_major = x[0];
        else if (t == 0x02 && n == 1) v->ver_minor = x[0];
        else if (t == 0x03 && n < sizeof v->fw) { memcpy(v->fw, x, n); v->fw[n] = 0; }
        else if (t == 0x04 && n < sizeof v->name) { memcpy(v->name, x, n); v->name[n] = 0; }
        else if (t == 0x05 && n == 4) v->caps = (uint32_t)bc_lr_uint(x, n);
        else if (t == 0x06 && n == 2) v->max_msg = (uint16_t)bc_lr_uint(x, n);
        else if (t == 0x07 && n == 6) { memcpy(v->device_id, x, 6); v->has_device_id = true; }
    }
    return v->ver_major != 0;
}

/* ride states as in bc_ride.h: 0 idle, 1 running, 2 paused, 3 ended */
bc_ctrl_action_t bc_link_ctrl_decide(const bc_ctrl_req_t *q, uint8_t st, uint16_t ride_id, bool armed, uint8_t *status)
{
    bool active = st == 1 || st == 2;
    if (active && q->ride_id && q->ride_id != ride_id) { *status = BC_RESP_WRONG_RIDE; return BC_ACT_NONE; }
    switch (q->cmd) {
    case BC_CMD_START: if (st == 0) { *status = BC_RESP_OK; return BC_ACT_START; } break;
    case BC_CMD_PAUSE: if (st == 1) { *status = BC_RESP_OK; return BC_ACT_PAUSE; } break;
    case BC_CMD_RESUME: if (st == 2) { *status = BC_RESP_OK; return BC_ACT_RESUME; } break;
    case BC_CMD_STOP_REQUEST: if (active) { *status = BC_RESP_NEEDS_CONFIRM; return BC_ACT_ARM_STOP; } break;
    case BC_CMD_STOP_CONFIRM:
        if (active && armed) { *status = BC_RESP_OK; return BC_ACT_STOP; }
        if (active) { *status = BC_RESP_NEEDS_CONFIRM; return BC_ACT_NONE; }
        break;
    default: *status = BC_RESP_UNKNOWN; return BC_ACT_NONE;
    }
    *status = BC_RESP_BAD_STATE;
    return BC_ACT_NONE;
}

const char *bc_src_name(uint8_t src)
{
    switch (src) {
    case BC_SRC_XDS: return "POWER METER"; case BC_SRC_BLE_STRAP: return "STRAP"; case BC_SRC_PHONE_GPS: return "PHONE GPS";
    case BC_SRC_APPLE_WATCH: return "WATCH"; case BC_SRC_WEAR_OS: return "WEAR OS"; case BC_SRC_PHONE_STRAP: return "PHONE";
    case BC_SRC_ONBOARD_GPS: return "GPS"; case BC_SRC_BLE_CSC: return "CSC SENSOR"; case BC_SRC_WEATHERKIT: return "WEATHERKIT"; case BC_SRC_OPEN_METEO: return "OPEN-METEO";
    case BC_SRC_DEMO: return "DEMO"; default: return "?";
    }
}

uint32_t bc_geo_dist_m(int32_t lat1, int32_t lon1, int32_t lat2, int32_t lon2)
{
    const double R = 6371000.0, k = 3.14159265358979323846 / 180.0 / 1e7;
    double dlat = (double)(lat2 - lat1) * k, dlon = (double)(lon2 - lon1) * k;
    double mlat = ((double)lat1 + (double)lat2) * 0.5 * k;
    double x = dlon * cos(mlat), y = dlat;
    double d = R * sqrt(x * x + y * y);
    return d < 0 ? 0 : (uint32_t)(d + 0.5);
}

/* ---- 1.1 ride-history sync (layout: ios/SYNC_PROPOSAL.md; vectors: Swift BCLinkTests + test/host t_link) */
size_t bc_link_encode_sync_req(const bc_sync_req_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_SYNC_REQ, seq, t_ms);
    bc_lw_u16(&w, 0x01, v->after_ride_id); bc_lw_u8(&w, 0x02, v->max_count);
    return bc_lw_end(&w);
}
bool bc_link_decode_sync_req(const uint8_t *buf, size_t len, bc_sync_req_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x;
    memset(v, 0, sizeof *v);
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_SYNC_REQ) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 2) v->after_ride_id = (uint16_t)bc_lr_uint(x, n);
        else if (t == 0x02 && n == 1) v->max_count = x[0];
    }
    if (v->max_count == 0 || v->max_count > 50) v->max_count = 50;
    return true;
}
size_t bc_link_encode_sync_end(const bc_sync_end_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_SYNC_END, seq, t_ms);
    bc_lw_u16(&w, 0x01, v->count); bc_lw_u16(&w, 0x02, v->total); bc_lw_u8(&w, 0x03, v->more ? 1 : 0);
    return bc_lw_end(&w);
}
bool bc_link_decode_sync_end(const uint8_t *buf, size_t len, bc_sync_end_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x;
    memset(v, 0, sizeof *v);
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_SYNC_END) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 2) v->count = (uint16_t)bc_lr_uint(x, n);
        else if (t == 0x02 && n == 2) v->total = (uint16_t)bc_lr_uint(x, n);
        else if (t == 0x03 && n == 1) v->more = x[0] != 0;
    }
    return true;
}
size_t bc_link_encode_event(const bc_event_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_EVENT, seq, t_ms);
    bc_lw_u8(&w, 0x01, v->event_id); bc_lw_u8(&w, 0x02, v->pct_est); bc_lw_u16(&w, 0x03, v->mv); bc_lw_u8(&w, 0x04, v->stage);
    return bc_lw_end(&w);
}
bool bc_link_decode_event(const uint8_t *buf, size_t len, bc_event_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x;
    memset(v, 0, sizeof *v);
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_EVENT) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 1) v->event_id = x[0];
        else if (t == 0x02 && n == 1) v->pct_est = x[0];
        else if (t == 0x03 && n == 2) v->mv = (uint16_t)bc_lr_uint(x, n);
        else if (t == 0x04 && n == 1) v->stage = x[0];
    }
    return v->event_id != 0;
}
/* ---- 1.2.2 SENSOR_DIAG (EVENT 0x40, event_id 0x21) */
uint16_t bc_link_age_ds(uint32_t age_ms)
{
    if (age_ms == UINT32_MAX) return BC_LINK_NONE16;
    uint32_t ds = age_ms / 100;
    return (uint16_t)(ds > 0xFFFEu ? 0xFFFEu : ds);
}
size_t bc_link_encode_sensor_diag(const bc_sensor_diag_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_EVENT, seq, t_ms);
    bc_lw_u8(&w, 0x01, BC_EVT_SENSOR_DIAG); bc_lw_u8(&w, 0x02, v->sensor); bc_lw_u8(&w, 0x03, v->stage);
    bc_lw_u32(&w, 0x04, v->packets); bc_lw_u16(&w, 0x05, v->rejected); bc_lw_u16(&w, 0x06, v->pkt_age_ds); bc_lw_u16(&w, 0x07, v->valid_age_ds);
    size_t n = 0; while (n < 20 && v->err[n]) n++;
    if (n) bc_lw_bytes(&w, 0x08, v->err, n);
    return bc_lw_end(&w);
}
bool bc_link_decode_sensor_diag(const uint8_t *buf, size_t len, bc_sensor_diag_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x; uint8_t id = 0;
    memset(v, 0, sizeof *v); v->pkt_age_ds = v->valid_age_ds = BC_LINK_NONE16;
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_EVENT) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 1) id = x[0];
        else if (t == 0x02 && n == 1) v->sensor = x[0];
        else if (t == 0x03 && n == 1) v->stage = x[0];
        else if (t == 0x04 && n == 4) v->packets = (uint32_t)bc_lr_uint(x, n);
        else if (t == 0x05 && n == 2) v->rejected = (uint16_t)bc_lr_uint(x, n);
        else if (t == 0x06 && n == 2) v->pkt_age_ds = (uint16_t)bc_lr_uint(x, n);
        else if (t == 0x07 && n == 2) v->valid_age_ds = (uint16_t)bc_lr_uint(x, n);
        else if (t == 0x08 && n <= 20) { memcpy(v->err, x, n); v->err[n] = 0; }
    }
    return id == BC_EVT_SENSOR_DIAG;
}

static int16_t s16c(int v) { return (int16_t)(v < -32768 ? -32768 : v > 32767 ? 32767 : v); }
size_t bc_link_encode_sync_ride(const bc_ride_summary_t *s, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_SYNC_RIDE, seq, t_ms);
    bc_lw_u16(&w, 0x01, s->id); bc_lw_u8(&w, 0x02, (uint8_t)((s->demo ? 1 : 0) | (s->recovered ? 2 : 0)));
    bc_lw_u32(&w, 0x03, s->duration_s); bc_lw_u32(&w, 0x04, s->paused_s);
    bc_lw_s16(&w, 0x05, s16c(s->avg_power)); bc_lw_s16(&w, 0x06, s16c(s->max_power)); bc_lw_s16(&w, 0x07, s16c(s->avg_cad));
    bc_lw_s16(&w, 0x08, s16c(s->avg_hr)); bc_lw_s16(&w, 0x09, s16c(s->max_hr));
    bc_lw_u32(&w, 0x0A, s->power_s); bc_lw_u32(&w, 0x0B, s->cad_s); bc_lw_u32(&w, 0x0C, s->hr_s);
    if (s->zones_valid) { uint8_t z[28]; for (int i = 0; i < 7; i++) for (int k = 0; k < 4; k++) z[i * 4 + k] = (uint8_t)(s->zone_s[i] >> (8 * k)); bc_lw_bytes(&w, 0x0D, z, 28); }
    bc_lw_s16(&w, 0x0E, s16c(s->ftp_w)); bc_lw_u8(&w, 0x0F, s->ftp_how);
    bc_lw_s16(&w, 0x10, s16c(s->kj)); bc_lw_s16(&w, 0x11, s16c(s->best20));
    { int8_t ib = (int8_t)(s->inband_pct < -1 ? -1 : s->inband_pct > 100 ? 100 : s->inband_pct); bc_lw_bytes(&w, 0x12, &ib, 1); }
    bc_lw_u16(&w, 0x13, (uint16_t)(s->ftp_new < 0 ? 0 : s->ftp_new)); bc_lw_u8(&w, 0x14, s->ftp_suggested_only ? 1 : 0);
    bc_lw_u32(&w, 0x15, s->distance_m); bc_lw_u8(&w, 0x16, s->dist_src); bc_lw_u32(&w, 0x17, s->start_epoch_s);
    if (s->coach[0]) {
        size_t n = strlen(s->coach); if (n > 60) n = 60;
        while (n > 0 && (s->coach[n] & 0xC0) == 0x80) n--;             /* cut at a UTF-8 character boundary */
        if (n) bc_lw_bytes(&w, 0x18, s->coach, n);
    }
    return bc_lw_end(&w);
}
bool bc_link_decode_sync_ride(const uint8_t *buf, size_t len, bc_ride_summary_t *s)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x; bool got_id = false;
    memset(s, 0, sizeof *s);
    s->avg_power = s->max_power = s->avg_cad = s->avg_hr = s->max_hr = s->kj = s->best20 = s->inband_pct = -1;
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_SYNC_RIDE) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        switch (t) {
        case 0x01: if (n == 2) { s->id = (uint16_t)bc_lr_uint(x, n); got_id = true; } break;
        case 0x02: if (n == 1) { s->demo = (x[0] & 1) != 0; s->recovered = (x[0] & 2) != 0; } break;
        case 0x03: if (n == 4) s->duration_s = (uint32_t)bc_lr_uint(x, n); break;
        case 0x04: if (n == 4) s->paused_s = (uint32_t)bc_lr_uint(x, n); break;
        case 0x05: if (n == 2) s->avg_power = (int)bc_lr_sint(x, n); break;
        case 0x06: if (n == 2) s->max_power = (int)bc_lr_sint(x, n); break;
        case 0x07: if (n == 2) s->avg_cad = (int)bc_lr_sint(x, n); break;
        case 0x08: if (n == 2) s->avg_hr = (int)bc_lr_sint(x, n); break;
        case 0x09: if (n == 2) s->max_hr = (int)bc_lr_sint(x, n); break;
        case 0x0A: if (n == 4) s->power_s = (uint32_t)bc_lr_uint(x, n); break;
        case 0x0B: if (n == 4) s->cad_s = (uint32_t)bc_lr_uint(x, n); break;
        case 0x0C: if (n == 4) s->hr_s = (uint32_t)bc_lr_uint(x, n); break;
        case 0x0D: if (n == 28) { s->zones_valid = true; for (int i = 0; i < 7; i++) s->zone_s[i] = (uint32_t)bc_lr_uint(x + 4 * i, 4); } break;
        case 0x0E: if (n == 2) s->ftp_w = (int)bc_lr_sint(x, n); break;
        case 0x0F: if (n == 1) s->ftp_how = x[0]; break;
        case 0x10: if (n == 2) s->kj = (int)bc_lr_sint(x, n); break;
        case 0x11: if (n == 2) s->best20 = (int)bc_lr_sint(x, n); break;
        case 0x12: if (n == 1) s->inband_pct = (int)(int8_t)x[0]; break;
        case 0x13: if (n == 2) s->ftp_new = (int)bc_lr_uint(x, n); break;
        case 0x14: if (n == 1) s->ftp_suggested_only = x[0] != 0; break;
        case 0x15: if (n == 4) s->distance_m = (uint32_t)bc_lr_uint(x, n); break;
        case 0x16: if (n == 1) s->dist_src = x[0]; break;
        case 0x17: if (n == 4) s->start_epoch_s = (uint32_t)bc_lr_uint(x, n); break;
        case 0x18: if (n < sizeof s->coach) { memcpy(s->coach, x, n); s->coach[n] = 0; } break;
        default: break;
        }
    }
    return got_id;
}

/* ---- 1.2 Wi-Fi provisioning */
static size_t slen(const char *s, size_t max) { size_t n = 0; while (n < max && s[n]) n++; return n; }
static bool get_str(const uint8_t *x, uint8_t n, char *dst, size_t cap) { if (n >= cap) return false; memcpy(dst, x, n); dst[n] = 0; return true; }

size_t bc_link_encode_wifi_scan_req(const bc_wifi_scan_req_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_WIFI_SCAN_REQ, seq, t_ms);
    if (v && v->max) bc_lw_u8(&w, 0x01, v->max);
    return bc_lw_end(&w);
}
bool bc_link_decode_wifi_scan_req(const uint8_t *buf, size_t len, bc_wifi_scan_req_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x;
    memset(v, 0, sizeof *v); v->max = 16;
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_WIFI_SCAN_REQ) return false;
    while (bc_lr_next(&r, &t, &x, &n)) if (t == 0x01 && n == 1 && x[0]) v->max = x[0];
    if (v->max > 32) v->max = 32;
    return true;
}
size_t bc_link_encode_wifi_scan_result(const bc_wifi_scan_result_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_WIFI_SCAN_RESULT, seq, t_ms);
    bc_lw_bytes(&w, 0x01, v->ssid, slen(v->ssid, 32)); bc_lw_bytes(&w, 0x02, &v->rssi, 1);
    bc_lw_u8(&w, 0x03, v->secured ? 1 : 0); bc_lw_u8(&w, 0x04, v->channel); bc_lw_u8(&w, 0x05, v->saved ? 1 : 0);
    return bc_lw_end(&w);
}
bool bc_link_decode_wifi_scan_result(const uint8_t *buf, size_t len, bc_wifi_scan_result_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x; bool ssid = false;
    memset(v, 0, sizeof *v);
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_WIFI_SCAN_RESULT) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n >= 1 && n <= 32) ssid = get_str(x, n, v->ssid, sizeof v->ssid);
        else if (t == 0x02 && n == 1) v->rssi = (int8_t)x[0];
        else if (t == 0x03 && n == 1) v->secured = x[0] ? 1 : 0;
        else if (t == 0x04 && n == 1) v->channel = x[0];
        else if (t == 0x05 && n == 1) v->saved = x[0] ? 1 : 0;
    }
    return ssid;
}
size_t bc_link_encode_wifi_scan_end(const bc_wifi_scan_end_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_WIFI_SCAN_END, seq, t_ms);
    bc_lw_u8(&w, 0x01, v->count); bc_lw_u8(&w, 0x02, v->err);
    return bc_lw_end(&w);
}
bool bc_link_decode_wifi_scan_end(const uint8_t *buf, size_t len, bc_wifi_scan_end_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x;
    memset(v, 0, sizeof *v);
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_WIFI_SCAN_END) return false;
    while (bc_lr_next(&r, &t, &x, &n)) { if (t == 0x01 && n == 1) v->count = x[0]; else if (t == 0x02 && n == 1) v->err = x[0]; }
    return true;
}
size_t bc_link_encode_wifi_set(const bc_wifi_set_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_WIFI_SET, seq, t_ms);
    bc_lw_bytes(&w, 0x01, v->ssid, slen(v->ssid, 32)); bc_lw_bytes(&w, 0x02, v->pass, slen(v->pass, 63)); bc_lw_u8(&w, 0x03, v->flags);
    return bc_lw_end(&w);
}
bool bc_link_decode_wifi_set(const uint8_t *buf, size_t len, bc_wifi_set_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x; bool ssid = false;
    memset(v, 0, sizeof *v); v->flags = BC_WIFI_SET_CONNECT | BC_WIFI_SET_SAVE;
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_WIFI_SET) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01) { if (n < 1 || n > 32) return false; ssid = get_str(x, n, v->ssid, sizeof v->ssid); }
        else if (t == 0x02) { if (n > 63) return false; get_str(x, n, v->pass, sizeof v->pass); }
        else if (t == 0x03 && n == 1) v->flags = x[0];
    }
    return ssid;
}
size_t bc_link_encode_wifi_forget(const bc_wifi_forget_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_WIFI_FORGET, seq, t_ms);
    bc_lw_bytes(&w, 0x01, v->ssid, slen(v->ssid, 32));
    return bc_lw_end(&w);
}
bool bc_link_decode_wifi_forget(const uint8_t *buf, size_t len, bc_wifi_forget_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x; bool ssid = false;
    memset(v, 0, sizeof *v);
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_WIFI_FORGET) return false;
    while (bc_lr_next(&r, &t, &x, &n)) if (t == 0x01 && n >= 1 && n <= 32) ssid = get_str(x, n, v->ssid, sizeof v->ssid);
    return ssid;
}
size_t bc_link_encode_wifi_status(const bc_wifi_status_msg_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_WIFI_STATUS, seq, t_ms);
    bc_lw_u8(&w, 0x01, v->state); bc_lw_u8(&w, 0x02, v->err);
    bc_lw_bytes(&w, 0x03, v->ssid, slen(v->ssid, 32)); bc_lw_bytes(&w, 0x04, &v->rssi, 1);
    bc_lw_u8(&w, 0x05, v->saved_count); bc_lw_u8(&w, 0x06, v->radio_on ? 1 : 0);
    return bc_lw_end(&w);
}
bool bc_link_decode_wifi_status(const uint8_t *buf, size_t len, bc_wifi_status_msg_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x;
    memset(v, 0, sizeof *v);
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_WIFI_STATUS) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 1) v->state = x[0];
        else if (t == 0x02 && n == 1) v->err = x[0];
        else if (t == 0x03 && n <= 32) get_str(x, n, v->ssid, sizeof v->ssid);
        else if (t == 0x04 && n == 1) v->rssi = (int8_t)x[0];
        else if (t == 0x05 && n == 1) v->saved_count = x[0];
        else if (t == 0x06 && n == 1) v->radio_on = x[0] ? 1 : 0;
    }
    return true;
}
size_t bc_link_encode_wifi_status_req(uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_WIFI_STATUS_REQ, seq, t_ms);
    return bc_lw_end(&w);
}

/* ---- 1.2 athlete profile + device settings */
static void put_bytes_str(bc_lw_t *w, uint8_t tag, const char *s, size_t max)
{
    size_t n = slen(s, max);
    while (n > 0 && (s[n] & 0xC0) == 0x80) n--;         /* never cut inside a UTF-8 character */
    bc_lw_bytes(w, tag, s, n);
}
size_t bc_link_encode_profile_get(uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_PROFILE_GET, seq, t_ms); return bc_lw_end(&w);
}
size_t bc_link_encode_profile(uint8_t type, const bc_profile_msg_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    if (type != BC_MSG_PROFILE_SET && type != BC_MSG_PROFILE) return 0;
    bc_lw_t w; bc_lw_begin(&w, buf, cap, (bc_msg_type_t)type, seq, t_ms);
    uint32_t h = v->has;
    bc_lw_u32(&w, 0x01, v->version);                                         /* always */
    if (h & BC_PF_HAS(0x02)) bc_lw_u32(&w, 0x02, v->updated_epoch_s);
    if (h & BC_PF_HAS(0x03)) put_bytes_str(&w, 0x03, v->name, 24);
    if (h & BC_PF_HAS(0x04)) bc_lw_u16(&w, 0x04, v->ftp_w);
    if (h & BC_PF_HAS(0x05)) bc_lw_u8(&w, 0x05, v->ftp_how);
    if (h & BC_PF_HAS(0x06)) bc_lw_u16(&w, 0x06, v->weight_kg_x10);
    if (h & BC_PF_HAS(0x07)) bc_lw_u16(&w, 0x07, v->birth_year);
    if (h & BC_PF_HAS(0x08)) bc_lw_u8(&w, 0x08, v->max_hr);
    if (h & BC_PF_HAS(0x09)) bc_lw_u8(&w, 0x09, v->rest_hr);
    if (h & BC_PF_HAS(0x0A)) bc_lw_u8(&w, 0x0A, v->units);
    if (h & BC_PF_HAS(0x0B)) bc_lw_u8(&w, 0x0B, v->hours_per_week);
    if (h & BC_PF_HAS(0x0C)) bc_lw_u8(&w, 0x0C, v->level);
    if (h & BC_PF_HAS(0x0D)) bc_lw_u8(&w, 0x0D, v->goal);
    if (h & BC_PF_HAS(0x0E)) bc_lw_u8(&w, 0x0E, v->lthr);
    if (type == BC_MSG_PROFILE) { bc_lw_u8(&w, 0x0F, v->source); bc_lw_u32(&w, 0x10, v->board_saved_epoch_s); }
    return bc_lw_end(&w);
}
bool bc_link_decode_profile(const uint8_t *buf, size_t len, bc_profile_msg_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x; bool ver = false;
    memset(v, 0, sizeof *v);
    if (!bc_lr_begin(&r, buf, len, &h) || (h.type != BC_MSG_PROFILE_SET && h.type != BC_MSG_PROFILE)) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        switch (t) {
        case 0x01: if (n == 4) { v->version = (uint32_t)bc_lr_uint(x, n); ver = true; } break;
        case 0x02: if (n == 4) { v->updated_epoch_s = (uint32_t)bc_lr_uint(x, n); v->has |= BC_PF_HAS(t); } break;
        case 0x03: if (n <= 24) { memcpy(v->name, x, n); v->name[n] = 0; v->has |= BC_PF_HAS(t); } else v->invalid |= BC_PF_HAS(t); break;
        case 0x04: if (n == 2) { uint16_t f = (uint16_t)bc_lr_uint(x, n); if (f <= 2000) { v->ftp_w = f; v->has |= BC_PF_HAS(t); } else v->invalid |= BC_PF_HAS(t); } else v->invalid |= BC_PF_HAS(t); break;
        case 0x05: if (n == 1 && x[0] <= 3) { v->ftp_how = x[0]; v->has |= BC_PF_HAS(t); } else v->invalid |= BC_PF_HAS(t); break;
        case 0x06: if (n == 2) { uint16_t k = (uint16_t)bc_lr_uint(x, n); if (k == 0 || (k >= 200 && k <= 3000)) { v->weight_kg_x10 = k; v->has |= BC_PF_HAS(t); } else v->invalid |= BC_PF_HAS(t); } else v->invalid |= BC_PF_HAS(t); break;
        case 0x07: if (n == 2) { uint16_t y = (uint16_t)bc_lr_uint(x, n); if (y == 0 || (y >= 1900 && y <= 2100)) { v->birth_year = y; v->has |= BC_PF_HAS(t); } else v->invalid |= BC_PF_HAS(t); } else v->invalid |= BC_PF_HAS(t); break;
        case 0x08: if (n == 1 && (x[0] == 0 || (x[0] >= 100 && x[0] <= 230))) { v->max_hr = x[0]; v->has |= BC_PF_HAS(t); } else v->invalid |= BC_PF_HAS(t); break;
        case 0x09: if (n == 1 && (x[0] == 0 || (x[0] >= 25 && x[0] <= 120))) { v->rest_hr = x[0]; v->has |= BC_PF_HAS(t); } else v->invalid |= BC_PF_HAS(t); break;
        case 0x0A: if (n == 1 && x[0] <= 1) { v->units = x[0]; v->has |= BC_PF_HAS(t); } else v->invalid |= BC_PF_HAS(t); break;
        case 0x0B: if (n == 1 && x[0] <= 60) { v->hours_per_week = x[0]; v->has |= BC_PF_HAS(t); } else v->invalid |= BC_PF_HAS(t); break;
        case 0x0C: if (n == 1 && x[0] <= 2) { v->level = x[0]; v->has |= BC_PF_HAS(t); } else v->invalid |= BC_PF_HAS(t); break;
        case 0x0D: if (n == 1 && x[0] <= 4) { v->goal = x[0]; v->has |= BC_PF_HAS(t); } else v->invalid |= BC_PF_HAS(t); break;
        case 0x0E: if (n == 1 && (x[0] == 0 || (x[0] >= 80 && x[0] <= 220))) { v->lthr = x[0]; v->has |= BC_PF_HAS(t); } else v->invalid |= BC_PF_HAS(t); break;
        case 0x0F: if (n == 1) { v->source = x[0]; v->has |= BC_PF_HAS(t); } break;
        case 0x10: if (n == 4) { v->board_saved_epoch_s = (uint32_t)bc_lr_uint(x, n); v->has |= BC_PF_HAS(t); } break;
        default: break;
        }
    }
    return ver;
}
size_t bc_link_encode_profile_ack(const bc_profile_ack_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_PROFILE_ACK, seq, t_ms);
    bc_lw_u32(&w, 0x01, v->version); bc_lw_u8(&w, 0x02, v->status); bc_lw_u32(&w, 0x03, v->board_version);
    return bc_lw_end(&w);
}
bool bc_link_decode_profile_ack(const uint8_t *buf, size_t len, bc_profile_ack_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x;
    memset(v, 0, sizeof *v);
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_PROFILE_ACK) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 4) v->version = (uint32_t)bc_lr_uint(x, n);
        else if (t == 0x02 && n == 1) v->status = x[0];
        else if (t == 0x03 && n == 4) v->board_version = (uint32_t)bc_lr_uint(x, n);
    }
    return true;
}
size_t bc_link_encode_settings_get(uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_SETTINGS_GET, seq, t_ms); return bc_lw_end(&w);
}
size_t bc_link_encode_settings(uint8_t type, const bc_settings_msg_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    if (type != BC_MSG_SETTINGS_SET && type != BC_MSG_SETTINGS) return 0;
    bc_lw_t w; bc_lw_begin(&w, buf, cap, (bc_msg_type_t)type, seq, t_ms);
    uint32_t h = v->has;
    bc_lw_u32(&w, 0x01, v->version);
    if (h & BC_PF_HAS(0x02)) bc_lw_u8(&w, 0x02, v->brightness_pct);
    if (h & BC_PF_HAS(0x03)) bc_lw_u16(&w, 0x03, v->screen_timeout_s);
    if (h & BC_PF_HAS(0x04)) bc_lw_u8(&w, 0x04, v->wake_gesture);
    if (h & BC_PF_HAS(0x05)) bc_lw_u8(&w, 0x05, v->phone_link_enabled);
    if (h & BC_PF_HAS(0x06)) bc_lw_u8(&w, 0x06, v->hr_pref);
    if (h & BC_PF_HAS(0x07)) bc_lw_u16(&w, 0x07, v->auto_sleep_min);
    if (h & BC_PF_HAS(0x08)) bc_lw_u8(&w, 0x08, v->ride_layout);
    if (h & BC_PF_HAS(0x09)) bc_lw_u8(&w, 0x09, v->wake_on_cue);
    if (h & BC_PF_HAS(0x0A)) bc_lw_u8(&w, 0x0A, v->units);
    if (type == BC_MSG_SETTINGS) { bc_lw_u8(&w, 0x0F, v->status); bc_lw_u32(&w, 0x10, v->supported_mask); }
    return bc_lw_end(&w);
}
bool bc_link_decode_settings(const uint8_t *buf, size_t len, bc_settings_msg_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x; bool ver = false;
    memset(v, 0, sizeof *v);
    if (!bc_lr_begin(&r, buf, len, &h) || (h.type != BC_MSG_SETTINGS_SET && h.type != BC_MSG_SETTINGS)) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        switch (t) {
        case 0x01: if (n == 4) { v->version = (uint32_t)bc_lr_uint(x, n); ver = true; } break;
        case 0x02: if (n == 1 && x[0] >= 10 && x[0] <= 100) { v->brightness_pct = x[0]; v->has |= BC_PF_HAS(t); } break;
        case 0x03: if (n == 2) { uint16_t s = (uint16_t)bc_lr_uint(x, n); if (s <= 3600) { v->screen_timeout_s = s; v->has |= BC_PF_HAS(t); } } break;
        case 0x04: if (n == 1 && x[0] <= 2) { v->wake_gesture = x[0]; v->has |= BC_PF_HAS(t); } break;
        case 0x05: if (n == 1 && x[0] <= 1) { v->phone_link_enabled = x[0]; v->has |= BC_PF_HAS(t); } break;
        case 0x06: if (n == 1 && x[0] <= 1) { v->hr_pref = x[0]; v->has |= BC_PF_HAS(t); } break;
        case 0x07: if (n == 2) { uint16_t m = (uint16_t)bc_lr_uint(x, n); if (m <= 240) { v->auto_sleep_min = m; v->has |= BC_PF_HAS(t); } } break;
        case 0x08: if (n == 1 && x[0] <= 2) { v->ride_layout = x[0]; v->has |= BC_PF_HAS(t); } break;
        case 0x09: if (n == 1 && x[0] <= 1) { v->wake_on_cue = x[0]; v->has |= BC_PF_HAS(t); } break;
        case 0x0A: if (n == 1 && x[0] <= 1) { v->units = x[0]; v->has |= BC_PF_HAS(t); } break;
        case 0x0F: if (n == 1) { v->status = x[0]; v->has |= BC_PF_HAS(t); } break;
        case 0x10: if (n == 4) { v->supported_mask = (uint32_t)bc_lr_uint(x, n); v->has |= BC_PF_HAS(t); } break;
        default: break;
        }
    }
    return ver;
}

/* ---- 1.2.3 diagnostic report transfer */
static size_t utf8_cut(const char *s, size_t max)
{
    size_t n = strlen(s); if (n <= max) return n;
    n = max; while (n > 0 && ((uint8_t)s[n] & 0xC0) == 0x80) n--;   /* never split a multi-byte character */
    return n;
}
static void get_str_cut(char *dst, size_t cap, const uint8_t *x, uint8_t n)
{
    size_t k = n < cap - 1 ? n : cap - 1;
    while (k > 0 && k < n && ((uint8_t)x[k] & 0xC0) == 0x80) k--;
    memcpy(dst, x, k); dst[k] = 0;
}
uint16_t bc_diag_chunk_data_max(uint16_t max_len, uint16_t att_mtu)
{
    uint32_t n = BC_DIAG_CHUNK_MAX;
    if (max_len && max_len < n) n = max_len;
    uint32_t mtu = att_mtu ? att_mtu : BC_ATT_MTU_DEFAULT;
    uint32_t room = mtu > BC_ATT_NOTIFY_OVERHEAD + BC_DIAG_CHUNK_OVERHEAD ? mtu - BC_ATT_NOTIFY_OVERHEAD - BC_DIAG_CHUNK_OVERHEAD : 0;
    if (room < n) n = room;
    return (uint16_t)n;
}
size_t bc_link_encode_diag_list_req(uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{ bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_DIAG_LIST_REQ, seq, t_ms); return bc_lw_end(&w); }
bool bc_link_decode_diag_list_req(const uint8_t *buf, size_t len) { bc_lr_t r; bc_link_hdr_t h; return bc_lr_begin(&r, buf, len, &h) && h.type == BC_MSG_DIAG_LIST_REQ; }
size_t bc_link_encode_diag_info(const bc_diag_info_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_DIAG_INFO, seq, t_ms);
    bc_lw_u32(&w, 0x01, v->id); bc_lw_u32(&w, 0x02, v->size); bc_lw_u32(&w, 0x03, v->crc); bc_lw_u32(&w, 0x04, v->epoch_s);
    bc_lw_u8(&w, 0x05, v->kind); bc_lw_u8(&w, 0x06, v->state);
    bc_lw_bytes(&w, 0x07, v->summary, utf8_cut(v->summary, BC_DIAG_SUMMARY_MAX));
    bc_lw_bytes(&w, 0x08, v->fw, utf8_cut(v->fw, BC_DIAG_FW_MAX));
    return bc_lw_end(&w);
}
bool bc_link_decode_diag_info(const uint8_t *buf, size_t len, bc_diag_info_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x; bool id = false;
    memset(v, 0, sizeof *v);
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_DIAG_INFO) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 4) { v->id = (uint32_t)bc_lr_uint(x, n); id = true; }
        else if (t == 0x02 && n == 4) v->size = (uint32_t)bc_lr_uint(x, n);
        else if (t == 0x03 && n == 4) v->crc = (uint32_t)bc_lr_uint(x, n);
        else if (t == 0x04 && n == 4) v->epoch_s = (uint32_t)bc_lr_uint(x, n);
        else if (t == 0x05 && n == 1) v->kind = x[0];
        else if (t == 0x06 && n == 1) v->state = x[0];
        else if (t == 0x07) get_str_cut(v->summary, sizeof v->summary, x, n);
        else if (t == 0x08) get_str_cut(v->fw, sizeof v->fw, x, n);
    }
    return id;
}
size_t bc_link_encode_diag_list_end(const bc_diag_list_end_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{ bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_DIAG_LIST_END, seq, t_ms); bc_lw_u8(&w, 0x01, v->count); bc_lw_u8(&w, 0x02, v->pending); return bc_lw_end(&w); }
bool bc_link_decode_diag_list_end(const uint8_t *buf, size_t len, bc_diag_list_end_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x; memset(v, 0, sizeof *v);
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_DIAG_LIST_END) return false;
    while (bc_lr_next(&r, &t, &x, &n)) { if (t == 0x01 && n == 1) v->count = x[0]; else if (t == 0x02 && n == 1) v->pending = x[0]; }
    return true;
}
size_t bc_link_encode_diag_chunk_req(const bc_diag_chunk_req_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{ bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_DIAG_CHUNK_REQ, seq, t_ms); bc_lw_u32(&w, 0x01, v->id); bc_lw_u32(&w, 0x02, v->offset); bc_lw_u16(&w, 0x03, v->max_len); return bc_lw_end(&w); }
bool bc_link_decode_diag_chunk_req(const uint8_t *buf, size_t len, bc_diag_chunk_req_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x; bool id = false, off = false;
    memset(v, 0, sizeof *v); v->max_len = BC_DIAG_CHUNK_MAX;
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_DIAG_CHUNK_REQ) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 4) { v->id = (uint32_t)bc_lr_uint(x, n); id = true; }
        else if (t == 0x02 && n == 4) { v->offset = (uint32_t)bc_lr_uint(x, n); off = true; }
        else if (t == 0x03 && n == 2) v->max_len = (uint16_t)bc_lr_uint(x, n);
    }
    return id && off;
}
size_t bc_link_encode_diag_chunk(const bc_diag_chunk_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_DIAG_CHUNK, seq, t_ms);
    bc_lw_u32(&w, 0x01, v->id); bc_lw_u32(&w, 0x02, v->offset);
    bc_lw_bytes(&w, 0x03, v->data, v->len > BC_DIAG_CHUNK_MAX ? BC_DIAG_CHUNK_MAX : v->len);
    bc_lw_u8(&w, 0x04, v->last ? 1 : 0);
    return bc_lw_end(&w);
}
bool bc_link_decode_diag_chunk(const uint8_t *buf, size_t len, bc_diag_chunk_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x; bool id = false, off = false, data = false;
    memset(v, 0, sizeof *v);
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_DIAG_CHUNK) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 4) { v->id = (uint32_t)bc_lr_uint(x, n); id = true; }
        else if (t == 0x02 && n == 4) { v->offset = (uint32_t)bc_lr_uint(x, n); off = true; }
        else if (t == 0x03 && n <= BC_DIAG_CHUNK_MAX) { memcpy(v->data, x, n); v->len = n; data = true; }
        else if (t == 0x04 && n == 1) v->last = x[0] != 0;
    }
    return id && off && data;
}
size_t bc_link_encode_diag_ack(const bc_diag_ack_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{ bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_DIAG_ACK, seq, t_ms); bc_lw_u32(&w, 0x01, v->id); bc_lw_u32(&w, 0x02, v->crc); return bc_lw_end(&w); }
bool bc_link_decode_diag_ack(const uint8_t *buf, size_t len, bc_diag_ack_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x; bool id = false, crc = false;
    memset(v, 0, sizeof *v);
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_DIAG_ACK) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 4) { v->id = (uint32_t)bc_lr_uint(x, n); id = true; }
        else if (t == 0x02 && n == 4) { v->crc = (uint32_t)bc_lr_uint(x, n); crc = true; }
    }
    return id && crc;
}
size_t bc_link_encode_diag_err(const bc_diag_err_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{ bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_DIAG_ERR, seq, t_ms); bc_lw_u32(&w, 0x01, v->id); bc_lw_u8(&w, 0x02, v->code); return bc_lw_end(&w); }
bool bc_link_decode_diag_err(const uint8_t *buf, size_t len, bc_diag_err_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x; memset(v, 0, sizeof *v);
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_DIAG_ERR) return false;
    while (bc_lr_next(&r, &t, &x, &n)) { if (t == 0x01 && n == 4) v->id = (uint32_t)bc_lr_uint(x, n); else if (t == 0x02 && n == 1) v->code = x[0]; }
    return v->code != 0;
}
size_t bc_link_encode_diag_ready(const bc_diag_ready_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_EVENT, seq, t_ms);
    bc_lw_u8(&w, 0x01, BC_EVT_DIAG_READY); bc_lw_u8(&w, 0x02, v->pending); bc_lw_u32(&w, 0x03, v->newest_id);
    return bc_lw_end(&w);
}
bool bc_link_decode_diag_ready(const uint8_t *buf, size_t len, bc_diag_ready_t *v)
{
    bc_lr_t r; bc_link_hdr_t h; uint8_t t, n; const uint8_t *x; uint8_t id = 0; memset(v, 0, sizeof *v);
    if (!bc_lr_begin(&r, buf, len, &h) || h.type != BC_MSG_EVENT) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 1) id = x[0];
        else if (t == 0x02 && n == 1) v->pending = x[0];
        else if (t == 0x03 && n == 4) v->newest_id = (uint32_t)bc_lr_uint(x, n);
    }
    return id == BC_EVT_DIAG_READY;
}
