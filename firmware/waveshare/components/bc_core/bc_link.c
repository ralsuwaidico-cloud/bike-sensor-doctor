#include "bc_link.h"
#include <string.h>

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
