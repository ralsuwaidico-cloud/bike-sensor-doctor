/* bc_core — BikeComputer Link 1.3 codec (BLE_CONTRACT.md v1.1). Host-tested in test/host/test_bc_link13.c. */
#include "bc_link13.h"
#include <string.h>
#include "bc_diag.h"

#define FIELD(want) if (n != (want)) break

/* UTF-8 string, cut to max bytes at a character boundary */
static void put_utf8(bc_lw_t *w, uint8_t tag, const char *s, size_t max)
{
    size_t n = strlen(s); if (n > max) n = max;
    while (n > 0 && n < strlen(s) && ((uint8_t)s[n] & 0xC0) == 0x80) n--;
    if (n) bc_lw_bytes(w, tag, s, n);
}
static void get_utf8(char *out, size_t cap, const uint8_t *x, uint8_t n)
{
    size_t k = n < cap - 1 ? n : cap - 1;
    while (k > 0 && k < n && (x[k] & 0xC0) == 0x80) k--;
    memcpy(out, x, k); out[k] = 0;
}
static bool begin(bc_lr_t *r, const uint8_t *buf, size_t len, uint8_t type)
{
    bc_link_hdr_t h;
    return bc_lr_begin(r, buf, len, &h) && h.type == type;
}

/* ---------------------------------------------------------------- HELLO */
size_t bc_link_encode_hello(const bc_hello_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_APP_HELLO, seq, t_ms);
    bc_lw_u8(&w, 0x01, v->major); bc_lw_u8(&w, 0x02, v->minor); bc_lw_u32(&w, 0x03, v->app_caps);
    put_utf8(&w, 0x04, v->app_version, 16);
    return bc_lw_end(&w);
}
bool bc_link_decode_hello(const uint8_t *buf, size_t len, bc_hello_t *v)
{
    bc_lr_t r; uint8_t t, n; const uint8_t *x; bool caps = false;
    memset(v, 0, sizeof *v);
    if (!begin(&r, buf, len, BC_MSG_APP_HELLO)) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        switch (t) {
        case 0x01: FIELD(1); v->major = x[0]; break;
        case 0x02: FIELD(1); v->minor = x[0]; break;
        case 0x03: FIELD(4); v->app_caps = (uint32_t)bc_lr_uint(x, n); caps = true; break;
        case 0x04: get_utf8(v->app_version, sizeof v->app_version, x, n); break;
        default: break;
        }
    }
    return caps;
}
size_t bc_link_encode_hello_ack(const bc_hello_ack_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{ bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_HELLO_ACK, seq, t_ms); bc_lw_u32(&w, 0x01, v->enabled_caps); return bc_lw_end(&w); }
bool bc_link_decode_hello_ack(const uint8_t *buf, size_t len, bc_hello_ack_t *v)
{
    bc_lr_t r; uint8_t t, n; const uint8_t *x; bool got = false; memset(v, 0, sizeof *v);
    if (!begin(&r, buf, len, BC_MSG_HELLO_ACK)) return false;
    while (bc_lr_next(&r, &t, &x, &n)) if (t == 0x01 && n == 4) { v->enabled_caps = (uint32_t)bc_lr_uint(x, n); got = true; }
    return got;
}

/* ---------------------------------------------------------------- coach */
size_t bc_cseg_put(const bc_cseg_t *s, uint8_t o[BC_COACH_SEG_BYTES])
{
    o[0] = (uint8_t)s->dur_s; o[1] = (uint8_t)(s->dur_s >> 8); o[2] = s->type; o[3] = s->kind;
    o[4] = (uint8_t)s->lo; o[5] = (uint8_t)(s->lo >> 8); o[6] = (uint8_t)s->hi; o[7] = (uint8_t)(s->hi >> 8); o[8] = s->cad_lo; o[9] = s->cad_hi;
    return BC_COACH_SEG_BYTES;
}
void bc_cseg_get(const uint8_t i[BC_COACH_SEG_BYTES], bc_cseg_t *s)
{
    s->dur_s = (uint16_t)(i[0] | (i[1] << 8)); s->type = i[2]; s->kind = i[3];
    s->lo = (uint16_t)(i[4] | (i[5] << 8)); s->hi = (uint16_t)(i[6] | (i[7] << 8)); s->cad_lo = i[8]; s->cad_hi = i[9];
}
size_t bc_link_encode_coach_plan(const bc_coach_plan_msg_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_COACH_PLAN, seq, t_ms);
    bc_lw_u32(&w, 0x01, v->workout_id); bc_lw_u16(&w, 0x02, v->part); bc_lw_u16(&w, 0x03, v->parts); bc_lw_u16(&w, 0x04, v->first_segment);
    uint8_t sb[BC_COACH_SEGS_PART * BC_COACH_SEG_BYTES]; int ns = v->nseg > BC_COACH_SEGS_PART ? BC_COACH_SEGS_PART : v->nseg;
    for (int i = 0; i < ns; i++) bc_cseg_put(&v->seg[i], sb + i * BC_COACH_SEG_BYTES);
    bc_lw_bytes(&w, 0x05, sb, (size_t)ns * BC_COACH_SEG_BYTES);
    if (v->head) {
        put_utf8(&w, 0x06, v->name, 20); bc_lw_u16(&w, 0x07, v->total_segments); bc_lw_u32(&w, 0x08, v->total_duration_s);
        bc_lw_u32(&w, 0x09, v->plan_crc32); bc_lw_u32(&w, 0x0A, v->t0_elapsed_s);
    }
    return bc_lw_end(&w);
}
bool bc_link_decode_coach_plan(const uint8_t *buf, size_t len, bc_coach_plan_msg_t *v)
{
    bc_lr_t r; uint8_t t, n; const uint8_t *x; unsigned got = 0;
    memset(v, 0, sizeof *v); v->t0_elapsed_s = BC_COACH_T0_RIDE_START;
    if (!begin(&r, buf, len, BC_MSG_COACH_PLAN)) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        switch (t) {
        case 0x01: FIELD(4); v->workout_id = (uint32_t)bc_lr_uint(x, n); got |= 1; break;
        case 0x02: FIELD(2); v->part = (uint16_t)bc_lr_uint(x, n); got |= 2; break;
        case 0x03: FIELD(2); v->parts = (uint16_t)bc_lr_uint(x, n); got |= 4; break;
        case 0x04: FIELD(2); v->first_segment = (uint16_t)bc_lr_uint(x, n); got |= 8; break;
        case 0x05:
            if (n % BC_COACH_SEG_BYTES || n / BC_COACH_SEG_BYTES > BC_COACH_SEGS_PART) return false;
            v->nseg = (uint8_t)(n / BC_COACH_SEG_BYTES);
            for (int i = 0; i < v->nseg; i++) bc_cseg_get(x + i * BC_COACH_SEG_BYTES, &v->seg[i]);
            got |= 16; break;
        case 0x06: get_utf8(v->name, sizeof v->name, x, n); v->head = true; break;
        case 0x07: FIELD(2); v->total_segments = (uint16_t)bc_lr_uint(x, n); v->head = true; break;
        case 0x08: FIELD(4); v->total_duration_s = (uint32_t)bc_lr_uint(x, n); v->head = true; break;
        case 0x09: FIELD(4); v->plan_crc32 = (uint32_t)bc_lr_uint(x, n); v->head = true; break;
        case 0x0A: FIELD(4); v->t0_elapsed_s = (uint32_t)bc_lr_uint(x, n); v->head = true; break;
        default: break;
        }
    }
    return got == 31 && v->parts >= 1 && v->part < v->parts;
}
size_t bc_link_encode_coach_plan_ack(const bc_coach_plan_ack_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_COACH_PLAN_ACK, seq, t_ms);
    bc_lw_u32(&w, 0x01, v->workout_id); bc_lw_u8(&w, 0x02, v->status); bc_lw_u16(&w, 0x03, v->next_part);
    return bc_lw_end(&w);
}
bool bc_link_decode_coach_plan_ack(const uint8_t *buf, size_t len, bc_coach_plan_ack_t *v)
{
    bc_lr_t r; uint8_t t, n; const uint8_t *x; bool id = false, st = false; memset(v, 0, sizeof *v);
    if (!begin(&r, buf, len, BC_MSG_COACH_PLAN_ACK)) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 4) { v->workout_id = (uint32_t)bc_lr_uint(x, n); id = true; }
        else if (t == 0x02 && n == 1) { v->status = x[0]; st = true; }
        else if (t == 0x03 && n == 2) v->next_part = (uint16_t)bc_lr_uint(x, n);
    }
    return id && st;
}
size_t bc_link_encode_coach_state(const bc_coach_state_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_COACH_STATE, seq, t_ms);
    uint32_t h = v->has | BC_CS_HAS(1) | BC_CS_HAS(2);
#define H(tag) (h & BC_CS_HAS(tag))
    bc_lw_u32(&w, 0x01, v->workout_id); bc_lw_u16(&w, 0x02, v->seq);
    if (H(0x03)) bc_lw_u8(&w, 0x03, v->type);
    if (H(0x04)) bc_lw_u8(&w, 0x04, v->kind);
    if (H(0x05)) bc_lw_u16(&w, 0x05, v->lo);
    if (H(0x06)) bc_lw_u16(&w, 0x06, v->hi);
    if (H(0x07)) bc_lw_u8(&w, 0x07, v->cad_lo);
    if (H(0x08)) bc_lw_u8(&w, 0x08, v->cad_hi);
    if (H(0x09)) bc_lw_u16(&w, 0x09, v->interval_index);
    if (H(0x0A)) bc_lw_u16(&w, 0x0A, v->interval_count);
    if (H(0x0B)) bc_lw_u16(&w, 0x0B, v->remaining_s);
    if (H(0x0C)) bc_lw_u16(&w, 0x0C, v->interval_dur_s);
    if (H(0x0D)) bc_lw_u8(&w, 0x0D, v->next_type);
    if (H(0x0E)) bc_lw_u8(&w, 0x0E, v->next_kind);
    if (H(0x0F)) bc_lw_u16(&w, 0x0F, v->next_lo);
    if (H(0x10)) bc_lw_u16(&w, 0x10, v->next_hi);
    if (H(0x11)) bc_lw_u16(&w, 0x11, v->next_dur_s);
    if (H(0x12)) bc_lw_u8(&w, 0x12, v->instruction);
    if (H(0x13)) put_utf8(&w, 0x13, v->text, 24);
    if (H(0x14)) bc_lw_u8(&w, 0x14, v->session_state);
    if (H(0x15)) bc_lw_u8(&w, 0x15, v->hr_src);
    if (H(0x16)) bc_lw_u8(&w, 0x16, v->zone);
    if (H(0x17)) bc_lw_u8(&w, 0x17, v->flags);
#undef H
    return bc_lw_end(&w);
}
bool bc_link_decode_coach_state(const uint8_t *buf, size_t len, bc_coach_state_t *v)
{
    bc_lr_t r; uint8_t t, n; const uint8_t *x;
    memset(v, 0, sizeof *v);
    if (!begin(&r, buf, len, BC_MSG_COACH_STATE)) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        uint32_t bit = (t >= 1 && t <= 0x17) ? BC_CS_HAS(t) : 0;
        switch (t) {
        case 0x01: FIELD(4); v->workout_id = (uint32_t)bc_lr_uint(x, n); v->has |= bit; break;
        case 0x02: FIELD(2); v->seq = (uint16_t)bc_lr_uint(x, n); v->has |= bit; break;
        case 0x03: FIELD(1); v->type = x[0]; v->has |= bit; break;
        case 0x04: FIELD(1); v->kind = x[0]; v->has |= bit; break;
        case 0x05: FIELD(2); v->lo = (uint16_t)bc_lr_uint(x, n); v->has |= bit; break;
        case 0x06: FIELD(2); v->hi = (uint16_t)bc_lr_uint(x, n); v->has |= bit; break;
        case 0x07: FIELD(1); v->cad_lo = x[0]; v->has |= bit; break;
        case 0x08: FIELD(1); v->cad_hi = x[0]; v->has |= bit; break;
        case 0x09: FIELD(2); v->interval_index = (uint16_t)bc_lr_uint(x, n); v->has |= bit; break;
        case 0x0A: FIELD(2); v->interval_count = (uint16_t)bc_lr_uint(x, n); v->has |= bit; break;
        case 0x0B: FIELD(2); v->remaining_s = (uint16_t)bc_lr_uint(x, n); v->has |= bit; break;
        case 0x0C: FIELD(2); v->interval_dur_s = (uint16_t)bc_lr_uint(x, n); v->has |= bit; break;
        case 0x0D: FIELD(1); v->next_type = x[0]; v->has |= bit; break;
        case 0x0E: FIELD(1); v->next_kind = x[0]; v->has |= bit; break;
        case 0x0F: FIELD(2); v->next_lo = (uint16_t)bc_lr_uint(x, n); v->has |= bit; break;
        case 0x10: FIELD(2); v->next_hi = (uint16_t)bc_lr_uint(x, n); v->has |= bit; break;
        case 0x11: FIELD(2); v->next_dur_s = (uint16_t)bc_lr_uint(x, n); v->has |= bit; break;
        case 0x12: FIELD(1); v->instruction = x[0]; v->has |= bit; break;
        case 0x13: get_utf8(v->text, sizeof v->text, x, n); v->has |= bit; break;
        case 0x14: FIELD(1); v->session_state = x[0]; v->has |= bit; break;
        case 0x15: FIELD(1); v->hr_src = x[0]; v->has |= bit; break;
        case 0x16: FIELD(1); v->zone = x[0]; v->has |= bit; break;
        case 0x17: FIELD(1); v->flags = x[0]; v->has |= bit; break;
        default: break;
        }
    }
    return (v->has & (BC_CS_HAS(1) | BC_CS_HAS(2))) == (BC_CS_HAS(1) | BC_CS_HAS(2));
}
size_t bc_link_encode_coach_end(const bc_coach_end_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{ bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_COACH_END, seq, t_ms); bc_lw_u32(&w, 0x01, v->workout_id); bc_lw_u8(&w, 0x02, v->reason); return bc_lw_end(&w); }
bool bc_link_decode_coach_end(const uint8_t *buf, size_t len, bc_coach_end_t *v)
{
    bc_lr_t r; uint8_t t, n; const uint8_t *x; bool id = false; memset(v, 0, sizeof *v);
    if (!begin(&r, buf, len, BC_MSG_COACH_END)) return false;
    while (bc_lr_next(&r, &t, &x, &n)) { if (t == 0x01 && n == 4) { v->workout_id = (uint32_t)bc_lr_uint(x, n); id = true; } else if (t == 0x02 && n == 1) v->reason = x[0]; }
    return id;
}

/* ---------------------------------------------------------------- ride queue */
static size_t empty_msg(uint8_t type, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{ bc_lw_t w; bc_lw_begin(&w, buf, cap, (bc_msg_type_t)type, seq, t_ms); return bc_lw_end(&w); }
static bool empty_ok(const uint8_t *buf, size_t len, uint8_t type) { bc_lr_t r; return begin(&r, buf, len, type); }
size_t bc_link_encode_rideq_list_req(uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms) { return empty_msg(BC_MSG_RIDEQ_LIST_REQ, buf, cap, seq, t_ms); }
bool bc_link_decode_rideq_list_req(const uint8_t *buf, size_t len) { return empty_ok(buf, len, BC_MSG_RIDEQ_LIST_REQ); }
size_t bc_link_encode_rideq_info(const bc_rideq_info_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_RIDEQ_INFO, seq, t_ms);
    bc_lw_u32(&w, 0x01, v->ride_id); bc_lw_u8(&w, 0x02, v->state); bc_lw_u32(&w, 0x03, v->samples_size); bc_lw_u32(&w, 0x04, v->samples_crc);
    bc_lw_u32(&w, 0x05, v->start_epoch_s); bc_lw_u32(&w, 0x06, v->duration_s); bc_lw_u8(&w, 0x07, v->flags); bc_lw_u32(&w, 0x08, v->summary_crc);
    return bc_lw_end(&w);
}
bool bc_link_decode_rideq_info(const uint8_t *buf, size_t len, bc_rideq_info_t *v)
{
    bc_lr_t r; uint8_t t, n; const uint8_t *x; bool id = false; memset(v, 0, sizeof *v);
    if (!begin(&r, buf, len, BC_MSG_RIDEQ_INFO)) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        switch (t) {
        case 0x01: FIELD(4); v->ride_id = (uint32_t)bc_lr_uint(x, n); id = true; break;
        case 0x02: FIELD(1); v->state = x[0]; break;
        case 0x03: FIELD(4); v->samples_size = (uint32_t)bc_lr_uint(x, n); break;
        case 0x04: FIELD(4); v->samples_crc = (uint32_t)bc_lr_uint(x, n); break;
        case 0x05: FIELD(4); v->start_epoch_s = (uint32_t)bc_lr_uint(x, n); break;
        case 0x06: FIELD(4); v->duration_s = (uint32_t)bc_lr_uint(x, n); break;
        case 0x07: FIELD(1); v->flags = x[0]; break;
        case 0x08: FIELD(4); v->summary_crc = (uint32_t)bc_lr_uint(x, n); break;
        default: break;
        }
    }
    return id;
}
size_t bc_link_encode_rideq_list_end(const bc_rideq_list_end_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_RIDEQ_LIST_END, seq, t_ms);
    bc_lw_u16(&w, 0x01, v->count); bc_lw_u16(&w, 0x02, v->unsynced); bc_lw_u32(&w, 0x03, v->unsynced_bytes);
    return bc_lw_end(&w);
}
bool bc_link_decode_rideq_list_end(const uint8_t *buf, size_t len, bc_rideq_list_end_t *v)
{
    bc_lr_t r; uint8_t t, n; const uint8_t *x; memset(v, 0, sizeof *v);
    if (!begin(&r, buf, len, BC_MSG_RIDEQ_LIST_END)) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 2) v->count = (uint16_t)bc_lr_uint(x, n);
        else if (t == 0x02 && n == 2) v->unsynced = (uint16_t)bc_lr_uint(x, n);
        else if (t == 0x03 && n == 4) v->unsynced_bytes = (uint32_t)bc_lr_uint(x, n);
    }
    return true;
}
/* RIDEQ_CHUNK_REQ / CHUNK / ERR: the DIAG layout under another type byte */
static size_t retype(size_t n, uint8_t *buf, uint8_t type) { if (n) buf[0] = type; return n; }
static bool as_type(const uint8_t *buf, size_t len, uint8_t want, uint8_t diag_type, uint8_t tmp[BC_LINK_MAX])
{
    if (!buf || len < BC_LINK_HDR || len > BC_LINK_MAX || buf[0] != want) return false;
    memcpy(tmp, buf, len); tmp[0] = diag_type; return true;
}
size_t bc_link_encode_rideq_chunk_req(const bc_diag_chunk_req_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{ return retype(bc_link_encode_diag_chunk_req(v, buf, cap, seq, t_ms), buf, BC_MSG_RIDEQ_CHUNK_REQ); }
bool bc_link_decode_rideq_chunk_req(const uint8_t *buf, size_t len, bc_diag_chunk_req_t *v)
{ uint8_t tmp[BC_LINK_MAX]; return as_type(buf, len, BC_MSG_RIDEQ_CHUNK_REQ, BC_MSG_DIAG_CHUNK_REQ, tmp) && bc_link_decode_diag_chunk_req(tmp, len, v); }
size_t bc_link_encode_rideq_chunk(const bc_diag_chunk_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{ return retype(bc_link_encode_diag_chunk(v, buf, cap, seq, t_ms), buf, BC_MSG_RIDEQ_CHUNK); }
bool bc_link_decode_rideq_chunk(const uint8_t *buf, size_t len, bc_diag_chunk_t *v)
{ uint8_t tmp[BC_LINK_MAX]; return as_type(buf, len, BC_MSG_RIDEQ_CHUNK, BC_MSG_DIAG_CHUNK, tmp) && bc_link_decode_diag_chunk(tmp, len, v); }
size_t bc_link_encode_rideq_err(const bc_diag_err_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{ return retype(bc_link_encode_diag_err(v, buf, cap, seq, t_ms), buf, BC_MSG_RIDEQ_ERR); }
bool bc_link_decode_rideq_err(const uint8_t *buf, size_t len, bc_diag_err_t *v)
{ uint8_t tmp[BC_LINK_MAX]; return as_type(buf, len, BC_MSG_RIDEQ_ERR, BC_MSG_DIAG_ERR, tmp) && bc_link_decode_diag_err(tmp, len, v); }
size_t bc_link_encode_rideq_ack(const bc_rideq_ack_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_RIDEQ_ACK, seq, t_ms);
    bc_lw_u32(&w, 0x01, v->ride_id); bc_lw_u32(&w, 0x02, v->samples_crc); bc_lw_u32(&w, 0x03, v->summary_crc); bc_lw_u8(&w, 0x04, v->delete_samples ? 1 : 0);
    return bc_lw_end(&w);
}
bool bc_link_decode_rideq_ack(const uint8_t *buf, size_t len, bc_rideq_ack_t *v)
{
    bc_lr_t r; uint8_t t, n; const uint8_t *x; unsigned got = 0; memset(v, 0, sizeof *v);
    if (!begin(&r, buf, len, BC_MSG_RIDEQ_ACK)) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 4) { v->ride_id = (uint32_t)bc_lr_uint(x, n); got |= 1; }
        else if (t == 0x02 && n == 4) { v->samples_crc = (uint32_t)bc_lr_uint(x, n); got |= 2; }
        else if (t == 0x03 && n == 4) { v->summary_crc = (uint32_t)bc_lr_uint(x, n); got |= 4; }
        else if (t == 0x04 && n == 1) v->delete_samples = x[0] ? 1 : 0;
    }
    return got == 7;
}
size_t bc_link_encode_rides_pending(const bc_rides_pending_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_EVENT, seq, t_ms);
    bc_lw_u8(&w, 0x01, BC_EVT_RIDES_PENDING); bc_lw_u8(&w, 0x02, v->unsynced); bc_lw_u32(&w, 0x03, v->newest_id);
    return bc_lw_end(&w);
}
bool bc_link_decode_rides_pending(const uint8_t *buf, size_t len, bc_rides_pending_t *v)
{
    bc_lr_t r; uint8_t t, n; const uint8_t *x; bool ev = false; memset(v, 0, sizeof *v);
    if (!begin(&r, buf, len, BC_MSG_EVENT)) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 1) ev = x[0] == BC_EVT_RIDES_PENDING;
        else if (t == 0x02 && n == 1) v->unsynced = x[0];
        else if (t == 0x03 && n == 4) v->newest_id = (uint32_t)bc_lr_uint(x, n);
    }
    return ev;
}
uint32_t bc_ride_summary_crc(const bc_ride_summary_t *s)
{
    uint8_t b[BC_LINK_MAX];
    size_t n = bc_link_encode_sync_ride(s, b, sizeof b, 0, 0);
    return n > BC_LINK_HDR ? bc_crc32(0, b + BC_LINK_HDR, n - BC_LINK_HDR) : 0;
}

/* ---------------------------------------------------------------- storage */
size_t bc_link_encode_storage_status_req(uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms) { return empty_msg(BC_MSG_STORAGE_STATUS_REQ, buf, cap, seq, t_ms); }
bool bc_link_decode_storage_status_req(const uint8_t *buf, size_t len) { return empty_ok(buf, len, BC_MSG_STORAGE_STATUS_REQ); }
size_t bc_link_encode_storage_status(const bc_storage_status_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_STORAGE_STATUS, seq, t_ms);
    bc_lw_u8(&w, 0x01, v->state); put_utf8(&w, 0x02, v->code, 19);
    bc_lw_u32(&w, 0x03, v->fs_total_kb); bc_lw_u32(&w, 0x04, v->fs_free_kb); bc_lw_u8(&w, 0x05, v->crash_partition); bc_lw_u32(&w, 0x06, v->crash_dump_bytes);
    bc_lw_u16(&w, 0x07, v->reports_stored); bc_lw_u16(&w, 0x08, v->reports_unsent); bc_lw_u32(&w, 0x09, v->diag_bytes);
    bc_lw_u16(&w, 0x0A, v->rides_unsynced); bc_lw_u32(&w, 0x0B, v->ride_bytes_unsynced); bc_lw_u32(&w, 0x0C, v->ride_bytes_synced);
    bc_lw_u32(&w, 0x0D, v->app_slot_kb); bc_lw_u32(&w, 0x0E, v->app_used_kb); bc_lw_u16(&w, 0x0F, v->nvs_used_entries); bc_lw_u16(&w, 0x10, v->nvs_free_entries);
    bc_lw_u16(&w, 0x11, v->root_free_slots); bc_lw_u16(&w, 0x12, v->root_bad_entries); bc_lw_u8(&w, 0x13, v->health);
    return bc_lw_end(&w);
}
bool bc_link_decode_storage_status(const uint8_t *buf, size_t len, bc_storage_status_t *v)
{
    bc_lr_t r; uint8_t t, n; const uint8_t *x; bool st = false; memset(v, 0, sizeof *v);
    if (!begin(&r, buf, len, BC_MSG_STORAGE_STATUS)) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        switch (t) {
        case 0x01: FIELD(1); v->state = x[0]; st = true; break;
        case 0x02: get_utf8(v->code, sizeof v->code, x, n); break;
        case 0x03: FIELD(4); v->fs_total_kb = (uint32_t)bc_lr_uint(x, n); break;
        case 0x04: FIELD(4); v->fs_free_kb = (uint32_t)bc_lr_uint(x, n); break;
        case 0x05: FIELD(1); v->crash_partition = x[0]; break;
        case 0x06: FIELD(4); v->crash_dump_bytes = (uint32_t)bc_lr_uint(x, n); break;
        case 0x07: FIELD(2); v->reports_stored = (uint16_t)bc_lr_uint(x, n); break;
        case 0x08: FIELD(2); v->reports_unsent = (uint16_t)bc_lr_uint(x, n); break;
        case 0x09: FIELD(4); v->diag_bytes = (uint32_t)bc_lr_uint(x, n); break;
        case 0x0A: FIELD(2); v->rides_unsynced = (uint16_t)bc_lr_uint(x, n); break;
        case 0x0B: FIELD(4); v->ride_bytes_unsynced = (uint32_t)bc_lr_uint(x, n); break;
        case 0x0C: FIELD(4); v->ride_bytes_synced = (uint32_t)bc_lr_uint(x, n); break;
        case 0x0D: FIELD(4); v->app_slot_kb = (uint32_t)bc_lr_uint(x, n); break;
        case 0x0E: FIELD(4); v->app_used_kb = (uint32_t)bc_lr_uint(x, n); break;
        case 0x0F: FIELD(2); v->nvs_used_entries = (uint16_t)bc_lr_uint(x, n); break;
        case 0x10: FIELD(2); v->nvs_free_entries = (uint16_t)bc_lr_uint(x, n); break;
        case 0x11: FIELD(2); v->root_free_slots = (uint16_t)bc_lr_uint(x, n); break;
        case 0x12: FIELD(2); v->root_bad_entries = (uint16_t)bc_lr_uint(x, n); break;
        case 0x13: FIELD(1); v->health = x[0]; break;
        default: break;
        }
    }
    return st;
}
size_t bc_link_encode_storage_clean_req(const bc_storage_clean_req_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{ bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_STORAGE_CLEAN_REQ, seq, t_ms); bc_lw_u8(&w, 0x01, v->what); return bc_lw_end(&w); }
bool bc_link_decode_storage_clean_req(const uint8_t *buf, size_t len, bc_storage_clean_req_t *v)
{
    bc_lr_t r; uint8_t t, n; const uint8_t *x; bool got = false; memset(v, 0, sizeof *v);
    if (!begin(&r, buf, len, BC_MSG_STORAGE_CLEAN_REQ)) return false;
    while (bc_lr_next(&r, &t, &x, &n)) if (t == 0x01 && n == 1) { v->what = x[0] & 0x07; got = true; }   /* only bits 0-2 exist */
    return got;
}
size_t bc_link_encode_storage_clean_result(const bc_storage_clean_result_t *v, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    bc_lw_t w; bc_lw_begin(&w, buf, cap, BC_MSG_STORAGE_CLEAN_RESULT, seq, t_ms);
    bc_lw_u8(&w, 0x01, v->status); bc_lw_u32(&w, 0x02, v->bytes_freed); bc_lw_u16(&w, 0x03, v->items);
    return bc_lw_end(&w);
}
bool bc_link_decode_storage_clean_result(const uint8_t *buf, size_t len, bc_storage_clean_result_t *v)
{
    bc_lr_t r; uint8_t t, n; const uint8_t *x; bool st = false; memset(v, 0, sizeof *v);
    if (!begin(&r, buf, len, BC_MSG_STORAGE_CLEAN_RESULT)) return false;
    while (bc_lr_next(&r, &t, &x, &n)) {
        if (t == 0x01 && n == 1) { v->status = x[0]; st = true; }
        else if (t == 0x02 && n == 4) v->bytes_freed = (uint32_t)bc_lr_uint(x, n);
        else if (t == 0x03 && n == 2) v->items = (uint16_t)bc_lr_uint(x, n);
    }
    return st;
}
bool bc_storage_clean_allowed(uint8_t s) { return s == 0 || s == 1 || s == 6; }
uint8_t bc_storage_health(uint8_t s) { return s == 0 ? 0 : (s == 1 || s == 6 || s == 7) ? 1 : 2; }
