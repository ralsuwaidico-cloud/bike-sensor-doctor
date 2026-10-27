/* bc_core — coach mirroring (BLE_CONTRACT.md v1.1 §5). Host-tested in test/host/test_bc_link13.c. */
#include "bc_cmirror.h"
#include <stdio.h>
#include <string.h>
#include "bc_diag.h"

void bc_cm_init(bc_cmirror_t *m) { memset(m, 0, sizeof *m); }

uint32_t bc_cm_plan_crc(const bc_cseg_t *seg, int n)
{
    uint32_t c = 0; uint8_t b[BC_COACH_SEG_BYTES];
    for (int i = 0; i < n; i++) { bc_cseg_put(&seg[i], b); c = bc_crc32(c, b, sizeof b); }
    return c;
}

static uint8_t rx_fail(bc_cmirror_t *m, uint8_t status, uint16_t *next_part)
{
    m->rx_active = false; m->plans_bad++;
    *next_part = 0;
    return status;
}

uint8_t bc_cm_plan_part(bc_cmirror_t *m, const bc_coach_plan_msg_t *p, uint16_t *next_part)
{
    if (p->part == 0) {
        if (!p->head || p->first_segment != 0) return rx_fail(m, BC_PLAN_CRC, next_part);
        if (p->total_segments == 0 || p->total_segments > BC_COACH_MAX_SEGMENTS) return rx_fail(m, BC_PLAN_TOO_MANY, next_part);
        m->rx_active = true; m->rx_id = p->workout_id; m->rx_parts = p->parts; m->rx_next_part = 0; m->rx_total = p->total_segments;
        m->rx_n = 0; m->rx_crc = p->plan_crc32; m->rx_total_dur = p->total_duration_s; m->rx_t0 = p->t0_elapsed_s;
        snprintf(m->rx_name, sizeof m->rx_name, "%s", p->name);
    } else {
        if (!m->rx_active || p->workout_id != m->rx_id || p->parts != m->rx_parts) return rx_fail(m, BC_PLAN_CRC, next_part);
        if (p->part != m->rx_next_part) { *next_part = m->rx_next_part; return BC_PLAN_PART_OK; }   /* a repeat or a gap: ask for the expected part */
    }
    if (p->first_segment != m->rx_n) return rx_fail(m, BC_PLAN_CRC, next_part);
    if (m->rx_n + p->nseg > m->rx_total) return rx_fail(m, BC_PLAN_TOO_MANY, next_part);
    memcpy(&m->rx_seg[m->rx_n], p->seg, sizeof p->seg[0] * p->nseg);
    m->rx_n = (uint16_t)(m->rx_n + p->nseg);
    m->rx_next_part++;
    if (m->rx_next_part < m->rx_parts) { *next_part = m->rx_next_part; return BC_PLAN_PART_OK; }
    /* last part: complete, CRC, open-ended only as the last segment */
    if (m->rx_n != m->rx_total || bc_cm_plan_crc(m->rx_seg, m->rx_n) != m->rx_crc) return rx_fail(m, BC_PLAN_CRC, next_part);
    for (int i = 0; i + 1 < m->rx_n; i++) if (m->rx_seg[i].dur_s == BC_COACH_OPEN_ENDED) return rx_fail(m, BC_PLAN_CRC, next_part);
    m->plan_ok = true; m->plan_id = m->rx_id; m->nseg = m->rx_n; m->total_dur_s = m->rx_total_dur; m->t0_elapsed_s = m->rx_t0;
    memcpy(m->seg, m->rx_seg, sizeof m->seg[0] * m->rx_n);
    snprintf(m->name, sizeof m->name, "%s", m->rx_name);
    if (m->have_state && m->st.workout_id != m->plan_id) m->have_state = false;   /* a new workout replaces the old one */
    if (m->ended && m->ended_id == m->plan_id) m->ended = false;
    m->rx_active = false; m->plans_ok++;
    *next_part = m->rx_parts;
    return BC_PLAN_COMPLETE;
}

void bc_cm_new_session(bc_cmirror_t *m) { m->seq_open = true; }

/* contract v1.3 (QA RC3-04): fields a COACH_STATE omits keep their previous values for the same workout (merge); a
   keepalive = workout_id + seq only refreshes the link. A new workout id starts from an empty state. */
static void merge(bc_coach_state_t *d, const bc_coach_state_t *s)
{
#define M(tag, f) if (s->has & BC_CS_HAS(tag)) d->f = s->f
    M(0x03, type); M(0x04, kind); M(0x05, lo); M(0x06, hi); M(0x07, cad_lo); M(0x08, cad_hi);
    M(0x09, interval_index); M(0x0A, interval_count); M(0x0B, remaining_s); M(0x0C, interval_dur_s);
    M(0x0D, next_type); M(0x0E, next_kind); M(0x0F, next_lo); M(0x10, next_hi); M(0x11, next_dur_s);
    M(0x12, instruction); M(0x14, session_state); M(0x15, hr_src); M(0x16, zone); M(0x17, flags);
#undef M
    if (s->has & BC_CS_HAS(0x13)) memcpy(d->text, s->text, sizeof d->text);
    d->has |= s->has; d->seq = s->seq; d->workout_id = s->workout_id;
}

bool bc_cm_state(bc_cmirror_t *m, const bc_coach_state_t *s, uint32_t now_ms)
{
    if (m->ended && s->workout_id == m->ended_id) { m->states_ignored++; return false; }
    bool same = m->have_state && s->workout_id == m->st.workout_id;
    /* contract v1.3 (QA RC3-03): the seq window restarts with every APP_HELLO (an app relaunch restarts its seq) */
    if (same && !m->seq_open && (int16_t)(uint16_t)(s->seq - m->st.seq) <= 0) { m->states_ignored++; return false; }
    m->seq_open = false;
    if (same) merge(&m->st, s); else m->st = *s;
    if (!same || (s->has & BC_CS_HAS(0x0B))) m->rem_rx_ms = now_ms;    /* a keepalive must not restart the countdown */
    m->have_state = true; m->st_rx_ms = now_ms; m->states_applied++;
    return true;
}

void bc_cm_end(bc_cmirror_t *m, uint32_t id)
{
    if (m->plan_ok && m->plan_id == id) m->plan_ok = false;
    if (m->have_state && m->st.workout_id == id) m->have_state = false;
    if (m->rx_active && m->rx_id == id) m->rx_active = false;
    m->ended = true; m->ended_id = id;
}

static void from_seg(bc_cm_view_t *v, const bc_cseg_t *s)
{
    v->type = s->type; v->kind = s->kind; v->lo = s->lo; v->hi = s->hi; v->cad_lo = s->cad_lo; v->cad_hi = s->cad_hi;
}
/* the stored plan on the board's ride clock */
static void plan_view(const bc_cmirror_t *m, uint32_t elapsed, bc_cm_view_t *v)
{
    uint32_t t0 = m->t0_elapsed_s == BC_COACH_T0_RIDE_START ? 0 : m->t0_elapsed_s;
    int idx = 0; v->interval_count = m->nseg; v->workout_id = m->plan_id;
    if (elapsed < t0) {
        idx = 0; v->has_remaining = true; v->remaining_s = (uint16_t)((t0 - elapsed) > 0xFFFE ? 0xFFFE : t0 - elapsed);
        from_seg(v, &m->seg[0]); v->instruction = BC_CI_GET_READY;
        v->has_next = false; v->interval_index = 0;
        return;
    }
    uint32_t rel = elapsed - t0; bool found = false;
    for (idx = 0; idx < m->nseg; idx++) {
        uint16_t d = m->seg[idx].dur_s;
        if (d == BC_COACH_OPEN_ENDED) { found = true; v->has_remaining = false; break; }
        if (rel < d) { found = true; v->has_remaining = true; v->remaining_s = (uint16_t)(d - rel); break; }
        rel -= d;
    }
    if (!found) { idx = m->nseg - 1; v->done = true; v->has_remaining = false; v->instruction = BC_CI_DONE; }
    from_seg(v, &m->seg[idx]); v->interval_index = (uint16_t)idx;
    if (!v->done && idx + 1 < m->nseg) {
        const bc_cseg_t *n = &m->seg[idx + 1];
        v->has_next = true; v->next_type = n->type; v->next_kind = n->kind; v->next_lo = n->lo; v->next_hi = n->hi; v->next_dur_s = n->dur_s;
        if (v->has_remaining && v->remaining_s <= 10) v->instruction = BC_CI_GET_READY;
    }
}

void bc_cm_view(const bc_cmirror_t *m, bool phone_live, uint32_t now_ms, uint32_t elapsed_s, bc_cm_view_t *v)
{
    memset(v, 0, sizeof *v);
    bool fresh = m->have_state && now_ms - m->st_rx_ms < BC_CM_STATE_STALE_MS;
    bool coach_live = phone_live && (m->have_state ? fresh : m->plan_ok);
    const bc_coach_state_t *s = &m->st;
    if (coach_live && m->have_state) {
        v->mode = BC_CM_FOLLOWING;
        v->workout_id = s->workout_id; v->seq = s->seq;
        v->type = s->type; v->kind = s->kind; v->lo = s->lo; v->hi = s->hi; v->cad_lo = s->cad_lo; v->cad_hi = s->cad_hi;
        v->instruction = s->instruction; snprintf(v->text, sizeof v->text, "%s", s->text);
        if (s->has & BC_CS_HAS(0x0B)) {
            uint32_t gone = (now_ms - m->rem_rx_ms) / 1000u;
            v->has_remaining = true; v->remaining_s = (uint16_t)(s->remaining_s > gone ? s->remaining_s - gone : 0);
            if (s->session_state == BC_SESS_PAUSED) v->remaining_s = s->remaining_s;   /* the phone's countdown is paused too */
        }
        if ((s->has & BC_CS_HAS(0x0D)) && s->next_type != BC_COACH_NO_NEXT) {   /* v1.4: 0xFF clears "next" under the merge */
            v->has_next = true; v->next_type = s->next_type; v->next_kind = s->next_kind; v->next_lo = s->next_lo; v->next_hi = s->next_hi;
            v->next_dur_s = (s->has & BC_CS_HAS(0x11)) ? s->next_dur_s : 0;
        }
        v->interval_index = s->interval_index; v->interval_count = s->interval_count;
        v->hr_src = s->hr_src; v->session_state = s->session_state; v->zone = s->zone; v->flags = s->flags;
        if (s->session_state == BC_SESS_FINISHED) { v->done = true; if (!v->instruction) v->instruction = BC_CI_DONE; }
        return;
    }
    /* rc4: a stored plan only stands in for the workout it belongs to (a newer workout without a plan -> its last target) */
    bool plan = m->plan_ok && (!m->have_state || m->st.workout_id == m->plan_id);
    if (coach_live && plan) { v->mode = BC_CM_FOLLOWING; plan_view(m, elapsed_s, v); return; }
    if (plan) {
        v->mode = BC_CM_PLAN_OFFLINE; plan_view(m, elapsed_s, v);
        if (m->have_state) { v->hr_src = s->hr_src; v->seq = s->seq; }
    } else if (m->have_state && s->session_state != BC_SESS_FINISHED && s->session_state != BC_SESS_ABANDONED) {
        v->mode = BC_CM_LAST_TARGET;
        v->workout_id = s->workout_id; v->seq = s->seq;
        v->type = s->type; v->kind = s->kind; v->lo = s->lo; v->hi = s->hi; v->cad_lo = s->cad_lo; v->cad_hi = s->cad_hi;
        v->interval_index = s->interval_index; v->interval_count = s->interval_count; v->hr_src = s->hr_src; v->zone = s->zone;
    } else return;
    /* the watch heart rate came through the phone: without the phone there is none */
    if (v->kind == BC_TK_HR && v->hr_src == 4 /* BC_SRC_APPLE_WATCH */) v->no_hr = true;
}

const char *bc_cm_instr_text(uint8_t i)
{
    static const char *T[BC_CI_COUNT] = { "", "ON TARGET", "MORE POWER", "LESS POWER", "CADENCE UP", "CADENCE DOWN", "HOLD STEADY",
        "GET READY", "EASY / RECOVER", "GO!", "COOL DOWN", "HR HIGH - EASE OFF", "DRINK / FUEL", "PAUSED", "WORKOUT DONE", "NO DATA",
        "TARGET CHANGED" };
    return i < BC_CI_COUNT ? T[i] : "";
}
const char *bc_cm_instr_short(uint8_t i)
{
    static const char *T[BC_CI_COUNT] = { "", "ON TARGET", "MORE POWER", "LESS POWER", "RPM UP", "RPM DOWN", "HOLD", "GET READY", "EASY",
        "GO!", "COOL DOWN", "HR HIGH", "DRINK", "PAUSED", "DONE", "NO DATA", "NEW TARGET" };
    return i < BC_CI_COUNT ? T[i] : "";
}
const char *bc_cm_type_name(uint8_t t)
{
    static const char *N[BC_WT_COUNT] = { "FREE RIDE", "RECOVERY", "ENDURANCE", "TEMPO", "SWEET SPOT", "THRESHOLD", "VO2MAX", "ANAEROBIC",
        "SPRINT", "FTP TEST", "RACE / EVENT", "WARM-UP", "COOL-DOWN", "CUSTOM" };
    return t < BC_WT_COUNT ? N[t] : "WORKOUT";
}
uint8_t bc_cm_instr_level(uint8_t i)
{
    switch (i) {
    case BC_CI_ON_TARGET: case BC_CI_HOLD_STEADY: case BC_CI_GO: case BC_CI_DONE: return 1;
    case BC_CI_MORE_POWER: case BC_CI_CADENCE_UP: return 2;
    case BC_CI_LESS_POWER: case BC_CI_CADENCE_DOWN: case BC_CI_EASY: case BC_CI_COOL_DOWN: case BC_CI_PAUSED: return 3;
    case BC_CI_HR_HIGH: case BC_CI_NO_DATA: return 4;
    default: return 0;
    }
}

static void fmt_dur(char *o, size_t cap, uint16_t d)
{
    if (d >= 60) snprintf(o, cap, "%u MIN", (unsigned)((d + 30) / 60)); else snprintf(o, cap, "%u S", (unsigned)d);
}
static void fmt_target(char *o, size_t cap, uint8_t kind, uint16_t lo, uint16_t hi)
{
    const char *u = kind == BC_TK_POWER ? " W" : kind == BC_TK_HR ? " BPM" : "";
    if (kind == BC_TK_POWER || kind == BC_TK_HR) {
        if (lo == hi || !hi) snprintf(o, cap, "TARGET %u%s", (unsigned)lo, u); else snprintf(o, cap, "TARGET %u-%u%s", (unsigned)lo, (unsigned)hi, u);
    } else if (kind == BC_TK_RPE) snprintf(o, cap, "RPE %u-%u", (unsigned)lo, (unsigned)hi);
    else if (kind == BC_TK_CADENCE) snprintf(o, cap, "RIDE BY CADENCE");
    else snprintf(o, cap, "RIDE BY FEEL");
}

int bc_cm_card(const bc_cm_view_t *v, int power_w, int cad_rpm, int hr_bpm, char L[BC_CM_CARD_LINES][BC_CM_LINE])
{
    for (int i = 0; i < BC_CM_CARD_LINES; i++) L[i][0] = 0;
    if (v->mode == BC_CM_NONE) return 0;
    snprintf(L[0], BC_CM_LINE, "CYCLIFT COACH");
    if (v->interval_count > 1) snprintf(L[1], BC_CM_LINE, "%.12s %u/%u", bc_cm_type_name(v->type), (unsigned)(v->interval_index + 1), (unsigned)v->interval_count);
    else snprintf(L[1], BC_CM_LINE, "%s", bc_cm_type_name(v->type));
    if (v->kind == BC_TK_HR) { if (hr_bpm > 0) snprintf(L[2], BC_CM_LINE, "HR %d BPM", hr_bpm); else snprintf(L[2], BC_CM_LINE, "HR --"); }
    else { if (power_w >= 0) snprintf(L[2], BC_CM_LINE, "POWER %d W", power_w); else snprintf(L[2], BC_CM_LINE, "POWER --"); }
    fmt_target(L[3], BC_CM_LINE, v->kind, v->lo, v->hi);
    if (cad_rpm >= 0) snprintf(L[4], BC_CM_LINE, "CADENCE %d", cad_rpm); else snprintf(L[4], BC_CM_LINE, "CADENCE --");
    if (v->cad_lo || v->cad_hi) snprintf(L[5], BC_CM_LINE, "TARGET %u-%u", (unsigned)v->cad_lo, (unsigned)v->cad_hi);
    const char *it = bc_cm_instr_text(v->instruction);
    if (v->no_hr) snprintf(L[6], BC_CM_LINE, "NO HR - RIDE BY FEEL");
    else if (it[0]) snprintf(L[6], BC_CM_LINE, "COACH: %s", it);
    else if (v->text[0]) snprintf(L[6], BC_CM_LINE, "COACH: %.20s", v->text);
    if (v->has_next && v->next_type != BC_COACH_NO_NEXT) {
        if (v->next_dur_s && v->next_dur_s != BC_COACH_OPEN_ENDED) { char d[12]; fmt_dur(d, sizeof d, v->next_dur_s); snprintf(L[7], BC_CM_LINE, "NEXT: %.12s - %.6s", bc_cm_type_name(v->next_type), d); }
        else snprintf(L[7], BC_CM_LINE, "NEXT: %s", bc_cm_type_name(v->next_type));
    }
    char rem[16] = ""; if (v->has_remaining) snprintf(rem, sizeof rem, "%u:%02u", (unsigned)(v->remaining_s / 60) % 1000u, (unsigned)(v->remaining_s % 60));
    if (v->mode == BC_CM_FOLLOWING) { if (rem[0]) snprintf(L[8], BC_CM_LINE, "%.7s LEFT", rem); }
    else if (v->mode == BC_CM_PLAN_OFFLINE) { if (rem[0]) snprintf(L[8], BC_CM_LINE, "PHONE LOST - %.7s LEFT", rem); else snprintf(L[8], BC_CM_LINE, "PHONE LOST - PLAN"); }
    else snprintf(L[8], BC_CM_LINE, "NO PHONE - LAST TARGET");   /* <= 22 chars: the bottom line of the round screen */
    return BC_CM_CARD_LINES;
}
