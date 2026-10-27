#include "app_psvc.h"
#include <stdio.h>
#include <string.h>
#include "app.h"
#include "app_power.h"
#include "bc_link.h"
#include "bc_ride.h"
#include "bc_pipe.h"
#include "app_diag.h"
#include "app_link13.h"

#define SCAN_TIMEOUT_MS 25000       /* a connect attempt in flight (<= 20 s) delays the scan */
#define STATUS_MIN_GAP_MS 500
#define STATUS_PERIOD_MS 15000      /* while connected: refresh the signal strength for the phone */
#define NOTIFY_PER_PUMP 8

/* 0.7.5: the service state (~2.7 KB) lives in PSRAM (plat_alloc_ext in app_psvc_init): internal RAM is kept for the
   Bluetooth stack; every entry point returns early until it exists */
typedef struct {
    /* Wi-Fi scan in flight */
    bool scan_pending, scan_issued; uint8_t scan_max; uint32_t scan_t0, scans_before; int scan_sent; int scan_total; bool scan_ending; uint8_t scan_err;
    plat_wifi_ap_t aps[32]; int naps;
    /* status watch */
    bool status_watch, status_now; bc_wifi_status_msg_t last_status; uint32_t last_status_ms; bool have_last;
    /* profile / settings replies due */
    bool profile_due, profile_ack_due, settings_due; bc_profile_ack_t ack; uint8_t settings_status;
    /* sync */
    bool sync_active; int ram_i; uint16_t after_id; uint8_t max_count; uint16_t sent, total; long off; bool eof;
    char line[320]; int line_len; char chunk[512]; int chunk_pos, chunk_len;
    uint8_t last_end[32]; size_t last_end_len;
    uint8_t held[BC_LINK_MAX]; size_t held_len; uint8_t held_chr;   /* a notification the transport could not take yet */
    uint16_t seq;
    app_psvc_stats_t st;
    /* 0.7.0 */
    bool was_ready, hello_due, diag_due; uint8_t last_set_status; bool set_seen; uint16_t last_disc_code; uint8_t last_disc;
    /* 0.7.2 SENSOR_DIAG (Link 1.2.2): per sensor (0 power, 1 HR strap, 2 CSC) the last stage seen and what is due */
    uint8_t sd_stage[3]; bool sd_known[3]; uint8_t sd_due; uint32_t sd_period_ms;
} psvc_t;
static psvc_t *s_ps;
#define S (*s_ps)

static const plat_sens_kind_t SD_KIND[3] = { PLAT_SENS_POWER, PLAT_SENS_HR, PLAT_SENS_CSC };
static void apply_disconnect(void);
static volatile bool s_disc_pending;

/* which SENSOR_DIAG events are due: stage changes, every 5 s for a paired link below VALID, all paired ones on connect */
static void sd_scan(uint32_t now, bool phone_connected_now)
{
    plat_sensors_t s; plat_sensors(&s);
    bool below = false; uint8_t below_mask = 0;
    for (int i = 0; i < 3; i++) {
        const plat_link_info_t *li = &s.link[SD_KIND[i]];
        bool paired = li->link != PLAT_LINK_NOT_PAIRED && li->link != PLAT_LINK_UNSUPPORTED && li->link != PLAT_LINK_OFF;
        if (S.sd_known[i] && li->stage != S.sd_stage[i]) S.sd_due |= (uint8_t)(1u << i);
        S.sd_stage[i] = li->stage; S.sd_known[i] = true;
        if (phone_connected_now && paired) S.sd_due |= (uint8_t)(1u << i);
        if (paired && li->stage != BC_STG_VALID) { below = true; below_mask |= (uint8_t)(1u << i); }
    }
    if (!below) S.sd_period_ms = now;
    else if (now - S.sd_period_ms >= 5000) { S.sd_period_ms = now; S.sd_due |= below_mask; }
}

void app_psvc_init(void)
{
    if (!s_ps) s_ps = plat_alloc_ext(sizeof *s_ps);
    if (s_ps) memset(s_ps, 0, sizeof *s_ps); else plat_log("PSVC: no memory for the phone services");
    app_link13_init();
}
void app_psvc_stats(app_psvc_stats_t *o) { if (!s_ps) { memset(o, 0, sizeof *o); return; } *o = S.st; o->sync_active = S.sync_active; o->status_watch = S.status_watch; }

static bool riding(void) { bc_ride_state_t s = app_ride_state(); return s == BC_RIDE_RUNNING || s == BC_RIDE_PAUSED; }

/* ---- Wi-Fi status snapshot → protocol message */
static void status_msg(bc_wifi_status_msg_t *m)
{
    plat_wifi_status_t w; plat_wifi_status(&w);
    memset(m, 0, sizeof *m);
    switch (w.state) {
    case PLAT_WIFI_OFF: m->state = BC_WIFI_ST_OFF; break;
    case PLAT_WIFI_IDLE: case PLAT_WIFI_FAILED: m->state = BC_WIFI_ST_DISCONNECTED; break;
    case PLAT_WIFI_SCANNING: m->state = BC_WIFI_ST_SCANNING; break;
    case PLAT_WIFI_CONNECTING: m->state = BC_WIFI_ST_CONNECTING; break;
    case PLAT_WIFI_CONNECTED: m->state = w.internet == 2 ? BC_WIFI_ST_CONNECTED_NO_INTERNET : BC_WIFI_ST_CONNECTED; break;
    }
    if (w.state == PLAT_WIFI_FAILED || (w.state == PLAT_WIFI_IDLE && w.err != PLAT_WIFI_ERR_NONE)) {
        switch (w.err) {
        case PLAT_WIFI_ERR_WRONG_PASSWORD: m->err = BC_WIFI_E_WRONG_PASSWORD; break;
        case PLAT_WIFI_ERR_NOT_FOUND: m->err = BC_WIFI_E_NOT_FOUND; break;
        case PLAT_WIFI_ERR_TIMEOUT: m->err = BC_WIFI_E_TIMEOUT; break;
        case PLAT_WIFI_ERR_NONE: m->err = BC_WIFI_E_NONE; break;
        default: m->err = BC_WIFI_E_OTHER; break;
        }
    }
    snprintf(m->ssid, sizeof m->ssid, "%s", w.ssid);
    m->rssi = (int8_t)(w.rssi < -127 ? -127 : w.rssi > 0 ? 0 : w.rssi);
    char saved[PLAT_WIFI_MAX_SAVED][33]; m->saved_count = (uint8_t)plat_wifi_saved(saved, PLAT_WIFI_MAX_SAVED);
    m->radio_on = w.state != PLAT_WIFI_OFF;
}

static bool status_changed(const bc_wifi_status_msg_t *a, const bc_wifi_status_msg_t *b)
{
    return a->state != b->state || a->err != b->err || a->saved_count != b->saved_count || a->radio_on != b->radio_on || strcmp(a->ssid, b->ssid) != 0;
}

/* ---- athlete profile <-> protocol (mapping documented in docs/LINK_V1_2_SPEC.md) */
static uint8_t ftp_how_out(uint8_t h) { return h == BC_FTP_ENTERED ? 1 : h == BC_FTP_AUTO ? 2 : 0; }
static uint8_t ftp_how_in(uint8_t v) { return v == 1 || v == 3 ? BC_FTP_ENTERED : v == 2 ? BC_FTP_AUTO : BC_FTP_ASSUMED; }
static uint8_t level_out(uint8_t e) { return e <= BC_EXP_NOVICE ? 0 : e == BC_EXP_INTERMEDIATE ? 1 : 2; }
static uint8_t level_in(uint8_t l) { return l == 0 ? BC_EXP_BEGINNER : l == 1 ? BC_EXP_INTERMEDIATE : BC_EXP_ADVANCED; }
static uint8_t goal_out(uint8_t g)
{
    switch (g) { case BC_GOAL_FITNESS: return 0; case BC_GOAL_ENDURANCE: return 1; case BC_GOAL_CLIMB: return 2; case BC_GOAL_EVENT: return 3; case BC_GOAL_WEIGHT: return 4; default: return 0; /* FTP goal: nearest = fitness */ }
}
static uint8_t goal_in(uint8_t g)
{
    switch (g) { case 0: return BC_GOAL_FITNESS; case 1: return BC_GOAL_ENDURANCE; case 2: return BC_GOAL_CLIMB; case 3: return BC_GOAL_EVENT; default: return BC_GOAL_WEIGHT; }
}
static uint32_t epoch_now(void) { app_live_t lv; app_live(&lv); return lv.time_known ? lv.epoch_s : 0; }
static uint16_t year_of(uint32_t epoch) { return epoch ? (uint16_t)(1970 + epoch / 31556952u) : 0; }

void app_psvc_profile_msg(bc_profile_msg_t *m)
{
    const bc_profile_t *p = app_profile();
    memset(m, 0, sizeof *m);
    m->version = p->phone_prof_ver; m->updated_epoch_s = p->phone_prof_epoch;
    snprintf(m->name, sizeof m->name, "%s", p->name);
    m->ftp_w = p->ftp_w; m->ftp_how = ftp_how_out(p->ftp_how);
    m->weight_kg_x10 = p->weight_dg;
    m->birth_year = p->birth_year; if (!m->birth_year && p->age && year_of(epoch_now())) m->birth_year = (uint16_t)(year_of(epoch_now()) - p->age);
    m->max_hr = p->max_hr; m->rest_hr = p->rest_hr; m->units = p->units; m->hours_per_week = p->hours_wk;
    m->level = level_out(p->exp); m->goal = goal_out(p->goal); m->lthr = p->lthr;
    m->source = p->prof_src; m->board_saved_epoch_s = p->phone_prof_epoch;
    m->has = 0; for (int t = 2; t <= 0x10; t++) m->has |= BC_PF_HAS(t);
}

/* applies a PROFILE_SET; returns the ack status. Only shared athlete fields change; everything device-specific is kept. */
/* 0.7.0: every field the phone sends is range-checked before anything changes; one bad value rejects the whole message */
static bool profile_valid(const bc_profile_msg_t *m)
{
    if (m->invalid) return false;                 /* the codec saw a tag whose value is outside its range */
    if ((m->has & BC_PF_HAS(0x03)) && (m->name[0] == 0 || strlen(m->name) > 24)) return false;
    if ((m->has & BC_PF_HAS(0x04)) && m->ftp_w && (m->ftp_w < 50 || m->ftp_w > 600)) return false;
    if ((m->has & BC_PF_HAS(0x05)) && m->ftp_how > 3) return false;
    if ((m->has & BC_PF_HAS(0x06)) && (m->weight_kg_x10 < 300 || m->weight_kg_x10 > 2000)) return false;
    if ((m->has & BC_PF_HAS(0x07)) && m->birth_year && (m->birth_year < 1900 || m->birth_year > 2030)) return false;
    if ((m->has & BC_PF_HAS(0x08)) && m->max_hr && (m->max_hr < 100 || m->max_hr > 230)) return false;
    if ((m->has & BC_PF_HAS(0x09)) && m->rest_hr && (m->rest_hr < 25 || m->rest_hr > 120)) return false;
    if ((m->has & BC_PF_HAS(0x0A)) && m->units > 1) return false;
    if ((m->has & BC_PF_HAS(0x0B)) && m->hours_per_week > 40) return false;
    if ((m->has & BC_PF_HAS(0x0C)) && m->level > 2) return false;
    if ((m->has & BC_PF_HAS(0x0D)) && m->goal > 4) return false;
    if ((m->has & BC_PF_HAS(0x0E)) && m->lthr && (m->lthr < 80 || m->lthr > 220)) return false;
    if ((m->has & BC_PF_HAS(0x08)) && (m->has & BC_PF_HAS(0x09)) && m->max_hr && m->rest_hr && m->rest_hr >= m->max_hr) return false;
    return true;
}

static uint8_t profile_apply(const bc_profile_msg_t *m)
{
    bc_profile_t *p = app_profile();
    if (m->version == 0 || m->version <= p->phone_prof_ver) return BC_PF_OLDER;
    if (!profile_valid(m)) { char l[64]; snprintf(l, sizeof l, "PROFILE_SET v%lu rejected: value out of range", (unsigned long)m->version); plat_log(l); return BC_PF_BAD; }
    bool ftp_changed = false;
    if (m->has & BC_PF_HAS(0x03)) { snprintf(p->name, sizeof p->name, "%.16s", m->name); size_t n = strlen(p->name); while (n && (p->name[n - 1] & 0xC0) == 0x80 && (p->name[n - 1] & 0xC0) != 0xC0) { /* trailing partial UTF-8 */ p->name[--n] = 0; if (n && (p->name[n - 1] & 0xC0) == 0xC0) { p->name[--n] = 0; break; } } }
    if (m->has & BC_PF_HAS(0x06)) p->weight_dg = m->weight_kg_x10;
    if (m->has & BC_PF_HAS(0x07)) { p->birth_year = m->birth_year; uint16_t y = year_of(epoch_now()); if (m->birth_year && y > m->birth_year) p->age = (uint8_t)(y - m->birth_year); }
    if (m->has & BC_PF_HAS(0x08)) p->max_hr = m->max_hr;
    if (m->has & BC_PF_HAS(0x09)) p->rest_hr = m->rest_hr;
    if (m->has & BC_PF_HAS(0x0A)) p->units = m->units;
    if (m->has & BC_PF_HAS(0x0B)) p->hours_wk = m->hours_per_week;
    if (m->has & BC_PF_HAS(0x0C)) p->exp = level_in(m->level);
    if (m->has & BC_PF_HAS(0x0D)) p->goal = goal_in(m->goal);
    if (m->has & BC_PF_HAS(0x0E)) p->lthr = m->lthr;
    if ((m->has & BC_PF_HAS(0x04)) && m->ftp_w) {
        p->ftp_w = m->ftp_w; p->ftp_how = (m->has & BC_PF_HAS(0x05)) ? ftp_how_in(m->ftp_how) : BC_FTP_ENTERED; ftp_changed = true;
        snprintf(p->ftp_note, sizeof p->ftp_note, "FTP %u W from the phone (%s)", p->ftp_w, p->ftp_how == BC_FTP_ENTERED ? "entered/tested" : p->ftp_how == BC_FTP_AUTO ? "estimated from rides" : "assumed");
    } else if (!ftp_changed) bc_profile_refresh_assumption(p);   /* weight/level may have changed an assumed FTP */
    p->phone_prof_ver = m->version; p->phone_prof_epoch = (m->has & BC_PF_HAS(0x02)) ? m->updated_epoch_s : epoch_now(); p->prof_src = 1;
    p->prof_sync_epoch = epoch_now();
    app_profile_save();
    char l[96]; snprintf(l, sizeof l, "PROFILE synced from phone v%lu (ftp %u W %s)", (unsigned long)m->version, p->ftp_w, bc_ftp_label(p)); plat_log(l);
    return BC_PF_APPLIED;
}

void app_psvc_settings_msg(bc_settings_msg_t *m)
{
    const bc_profile_t *p = app_profile();
    memset(m, 0, sizeof *m);
    m->version = p->sett_ver;
    m->brightness_pct = p->brightness < 10 ? 10 : p->brightness; m->screen_timeout_s = p->scr_timeout_s;
    m->wake_gesture = p->wake_taps == 3 ? 0 : p->wake_taps == 2 ? 1 : 2;
    m->phone_link_enabled = p->phone_on; m->hr_pref = p->hr_pref; m->auto_sleep_min = p->auto_sleep_min;
    m->ride_layout = p->ride_style; m->wake_on_cue = p->wake_on_cue; m->units = p->units;
    m->status = S.settings_status; m->supported_mask = BC_SETTINGS_SUPPORTED_ALL;
    m->has = 0; for (int t = 2; t <= 0x10; t++) m->has |= BC_PF_HAS(t);
}

static uint8_t settings_apply(const bc_settings_msg_t *m)
{
    bc_profile_t *p = app_profile();
    if (m->version == 0 || m->version <= p->sett_ver) return BC_ST_OLDER;
    if (m->has & ~BC_SETTINGS_SUPPORTED_ALL & 0x3FFFu) return BC_ST_UNSUPPORTED;
    if (m->has & BC_PF_HAS(0x02)) { p->brightness = m->brightness_pct; plat_backlight(app_power()->screen_on ? p->brightness : 0); }
    if (m->has & BC_PF_HAS(0x03)) p->scr_timeout_s = m->screen_timeout_s;
    if (m->has & BC_PF_HAS(0x04)) p->wake_taps = m->wake_gesture == 0 ? 3 : m->wake_gesture == 1 ? 2 : 1;
    if (m->has & BC_PF_HAS(0x05)) { if (p->phone_on != (m->phone_link_enabled != 0)) { p->phone_on = m->phone_link_enabled != 0; if (!p->phone_on) plat_log("SETTINGS phone link switched off by the phone"); } }
    if (m->has & BC_PF_HAS(0x06)) p->hr_pref = m->hr_pref;
    if (m->has & BC_PF_HAS(0x07)) p->auto_sleep_min = (uint8_t)(m->auto_sleep_min > 240 ? 240 : m->auto_sleep_min);
    if (m->has & BC_PF_HAS(0x08)) p->ride_style = m->ride_layout;
    if (m->has & BC_PF_HAS(0x09)) p->wake_on_cue = m->wake_on_cue != 0;
    if (m->has & BC_PF_HAS(0x0A)) p->units = m->units;
    p->sett_ver = m->version;
    app_profile_save();
    /* the phone switching its own link off: honour it after the reply has gone out (app_power picks phone_on up) */
    if ((m->has & BC_PF_HAS(0x05)) && !p->phone_on) app_power_phone_link_deferred_off();
    char l[64]; snprintf(l, sizeof l, "SETTINGS synced from phone v%lu", (unsigned long)m->version); plat_log(l);
    return BC_ST_APPLIED;
}

/* ---- sync: history streamed line by line */
static bool sync_next_line(void)
{
    S.line_len = 0;
    for (;;) {
        if (S.chunk_pos >= S.chunk_len) {
            if (S.eof) return false;
            long n = plat_file_read_at(APP_HIST_REAL, S.off, S.chunk, sizeof S.chunk);
            if (n <= 0) { S.eof = true; return S.line_len > 0; }
            S.off += n; S.chunk_len = (int)n; S.chunk_pos = 0;
        }
        char c = S.chunk[S.chunk_pos++];
        if (c == '\n') { S.line[S.line_len] = 0; return true; }
        if (S.line_len < (int)sizeof S.line - 1) S.line[S.line_len++] = c;
    }
}

static void sync_rewind(void) { S.off = 0; S.eof = false; S.chunk_pos = S.chunk_len = 0; S.line_len = 0; }

static void sync_start(const bc_sync_req_t *q)
{
    S.sync_active = true; S.after_id = q->after_ride_id; S.max_count = q->max_count; S.sent = 0; S.total = 0;
    /* counting pass: how many rides the board holds */
    sync_rewind(); bc_ride_summary_t s;
    while (sync_next_line()) if (S.line_len && bc_summary_from_line(&s, S.line)) S.total++;
    sync_rewind();
    S.ram_i = 0; { bc_ride_summary_t u[APP_UNSAVED_MAX]; S.total += app_unsaved_rides(u, APP_UNSAVED_MAX); }   /* 0.7.4: RAM-only rides */
    S.st.sync_reqs++;
}

/* ---- writes from the phone */
bool app_psvc_write(app_psvc_chr_t chr, const uint8_t *msg, size_t n, uint32_t now)
{
    if (!s_ps || !msg || n < BC_LINK_HDR) return false;
    uint8_t type = msg[0];
    if (chr == APP_PSVC_CTRL && app_diag_write(msg, n)) return true;   /* 0.7.3 Link 1.2.3 DIAG_* (0x80..0x86) */
    if (chr == APP_PSVC_CTRL && app_link13_write(msg, n, now)) return true;   /* 0.7.5 Link 1.3 (HELLO-gated) */
    if (chr == APP_PSVC_SYNC) {
        bc_sync_req_t q;
        if (type != BC_MSG_SYNC_REQ || !bc_link_decode_sync_req(msg, n, &q)) return false;
        sync_start(&q);                                  /* a new request cancels a batch in flight */
        return true;
    }
    switch (type) {
    case BC_MSG_WIFI_SCAN_REQ: {
        bc_wifi_scan_req_t q; if (!bc_link_decode_wifi_scan_req(msg, n, &q)) { S.st.wifi_rejected++; return false; }
        S.st.wifi_msgs++; S.st.scans++;
        plat_wifi_status_t w; plat_wifi_status(&w);
        S.scan_pending = true; S.scan_issued = false; S.scan_max = q.max; S.scan_t0 = now; S.scan_sent = 0; S.scan_total = 0; S.scan_ending = false; S.scan_err = BC_WIFI_SCAN_OK; S.naps = 0;
        if (w.state == PLAT_WIFI_OFF) { S.scan_ending = true; S.scan_err = BC_WIFI_SCAN_RADIO_OFF; }
        else if (riding()) { S.scan_ending = true; S.scan_err = BC_WIFI_SCAN_BUSY; }
        /* else: issued from app_psvc_next once no connect attempt is in flight (a scan during CONNECTING would be dropped) */
        return true; }
    case BC_MSG_WIFI_SET: {
        bc_wifi_set_t v; if (!bc_link_decode_wifi_set(msg, n, &v)) { S.st.wifi_rejected++; return false; }
        S.st.wifi_msgs++; S.st.sets++;
        if (v.flags & BC_WIFI_SET_CONNECT) plat_wifi_connect(v.ssid, v.pass, (v.flags & BC_WIFI_SET_SAVE) != 0);
        else if (v.flags & BC_WIFI_SET_SAVE) plat_wifi_save(v.ssid, v.pass);
        memset(&v, 0, sizeof v);                          /* no password left in RAM */
        S.status_watch = true; S.status_now = true;
        return true; }
    case BC_MSG_WIFI_FORGET: {
        bc_wifi_forget_t v; if (!bc_link_decode_wifi_forget(msg, n, &v)) { S.st.wifi_rejected++; return false; }
        S.st.wifi_msgs++; S.st.forgets++;
        plat_wifi_forget(v.ssid);
        S.status_watch = true; S.status_now = true;
        return true; }
    case BC_MSG_WIFI_STATUS_REQ:
        S.st.wifi_msgs++; S.status_watch = true; S.status_now = true;
        return true;
    case BC_MSG_PROFILE_GET:
        S.st.profile_gets++; S.profile_due = true;
        return true;
    case BC_MSG_PROFILE_SET: {
        bc_profile_msg_t m; if (!bc_link_decode_profile(msg, n, &m)) { S.st.profile_rejected++; return false; }
        S.st.profile_sets++;
        uint8_t st = profile_apply(&m);
        if (st == BC_PF_APPLIED) S.st.profile_applied++, S.st.last_profile_ms = (now ? now : 1); else S.st.profile_rejected++;
        S.ack.version = m.version; S.ack.status = st; S.ack.board_version = app_profile()->phone_prof_ver;
        S.profile_ack_due = true; S.set_seen = true; S.last_set_status = st;
        return true; }
    case BC_MSG_SETTINGS_GET:
        S.st.settings_gets++; S.settings_status = BC_ST_APPLIED; S.settings_due = true;
        return true;
    case BC_MSG_SETTINGS_SET: {
        bc_settings_msg_t m; if (!bc_link_decode_settings(msg, n, &m)) { S.st.settings_rejected++; return false; }
        S.st.settings_sets++;
        uint8_t st = settings_apply(&m);
        if (st == BC_ST_APPLIED) S.st.settings_applied++, S.st.last_settings_ms = (now ? now : 1); else S.st.settings_rejected++;
        S.settings_status = st; S.settings_due = true;
        return true; }
    default:
        return false;
    }
}

/* ---- notifications */
size_t app_psvc_next(app_psvc_chr_t *chr, uint8_t *buf, size_t cap, uint32_t now)
{
    if (!s_ps) return 0;
    /* 0.7.0 link diagnostics: one EVENT per connection (Events characteristic) — why the previous link ended, bonds, sync state */
    if (S.diag_due && !S.profile_due && !S.profile_ack_due) {
        S.diag_due = false;
        plat_phone_status_t ps; plat_phone_status(&ps);
        bc_event_t ev = { .event_id = BC_EVT_LINK_DIAG, .pct_est = (uint8_t)S.last_disc, .mv = ps.bonds, .stage = (uint8_t)app_psvc_sync_state() };
        *chr = APP_PSVC_EVENTS;
        return bc_link_encode_event(&ev, buf, cap, ++S.seq, now);
    }
    /* 0. profile / settings replies first (small, the phone is waiting) */
    if (S.profile_ack_due) { S.profile_ack_due = false; *chr = APP_PSVC_CTRL; return bc_link_encode_profile_ack(&S.ack, buf, cap, ++S.seq, now); }
    if (S.profile_due) { S.profile_due = false; bc_profile_msg_t m; app_psvc_profile_msg(&m); *chr = APP_PSVC_CTRL; return bc_link_encode_profile(BC_MSG_PROFILE, &m, buf, cap, ++S.seq, now); }
    if (S.settings_due) { S.settings_due = false; bc_settings_msg_t m; app_psvc_settings_msg(&m); *chr = APP_PSVC_CTRL; return bc_link_encode_settings(BC_MSG_SETTINGS, &m, buf, cap, ++S.seq, now); }
    /* 0.7.2 sensor pipeline diagnostics (Events characteristic), one sensor per message */
    if (S.sd_due) {
        plat_sensors_t s; plat_sensors(&s);
        for (int i = 0; i < 3; i++) if (S.sd_due & (1u << i)) {
            S.sd_due &= (uint8_t)~(1u << i);
            const plat_link_info_t *li = &s.link[SD_KIND[i]];
            bc_sensor_diag_t d; memset(&d, 0, sizeof d);
            d.sensor = (uint8_t)(i + 1); d.stage = li->stage; d.packets = li->packets; d.rejected = (uint16_t)(li->rejected > 0xFFFF ? 0xFFFF : li->rejected);
            d.pkt_age_ds = bc_link_age_ds(li->age_ms); d.valid_age_ds = bc_link_age_ds(li->valid_age_ms);
            snprintf(d.err, sizeof d.err, "%s", li->err);
            S.st.sensor_diags++;
            *chr = APP_PSVC_EVENTS;
            return bc_link_encode_sensor_diag(&d, buf, cap, ++S.seq, now);
        }
    }
    /* 0.7.5 Link 1.3 replies (HELLO_ACK, PLAN_ACK, storage, ride queue; queue chunks paced like diag chunks) */
    { uint8_t c; size_t m = app_link13_next(&c, buf, cap, now); if (m) { *chr = c == 2 ? APP_PSVC_EVENTS : APP_PSVC_CTRL; return m; } }
    /* 0.7.3 diagnostic reports (Link 1.2.3): diag_ready event, then the replies the phone pulled. Lower priority than every
       reply above; its data chunks are additionally held back while LIVE / the transport need the link (app_diag_next). */
    { uint8_t c; size_t m = app_diag_next(&c, buf, cap, now); if (m) { *chr = c == 2 ? APP_PSVC_EVENTS : APP_PSVC_CTRL; return m; } }
    /* 1. scan results, then the end marker */
    if (S.scan_pending) {
        if (!S.scan_ending) {
            plat_wifi_status_t w; plat_wifi_status(&w);
            if (!S.scan_issued) {
                if (w.state != PLAT_WIFI_CONNECTING) { S.scans_before = w.scans; plat_wifi_scan(); S.scan_issued = true; }
                else if (now - S.scan_t0 > SCAN_TIMEOUT_MS) { S.scan_ending = true; S.scan_err = BC_WIFI_SCAN_FAILED; S.scan_total = 0; }
                else return 0;
            }
            if (w.scans > S.scans_before) {                       /* results are published together with the counter */
                S.naps = plat_wifi_results(S.aps, 32);
                S.scan_total = S.naps < S.scan_max ? S.naps : S.scan_max;
                S.scan_ending = true;
            } else if (now - S.scan_t0 > SCAN_TIMEOUT_MS) { S.scan_ending = true; S.scan_err = BC_WIFI_SCAN_FAILED; S.scan_total = 0; }
            else return 0;
        }
        if (S.scan_sent < S.scan_total) {
            const plat_wifi_ap_t *a = &S.aps[S.scan_sent++];
            bc_wifi_scan_result_t r = { .rssi = (int8_t)(a->rssi < -127 ? -127 : a->rssi), .secured = a->secured, .channel = a->channel, .saved = a->saved };
            snprintf(r.ssid, sizeof r.ssid, "%s", a->ssid);
            *chr = APP_PSVC_CTRL;
            return bc_link_encode_wifi_scan_result(&r, buf, cap, ++S.seq, now);
        }
        bc_wifi_scan_end_t e = { .count = (uint8_t)S.scan_sent, .err = S.scan_err };
        S.scan_pending = false; *chr = APP_PSVC_CTRL;
        return bc_link_encode_wifi_scan_end(&e, buf, cap, ++S.seq, now);
    }
    /* 2. status: at once when asked, then on every change (and a periodic refresh while connected) */
    if (S.status_watch) {
        bc_wifi_status_msg_t m; status_msg(&m);
        bool due = S.status_now || !S.have_last || status_changed(&m, &S.last_status) ||
                   ((m.state == BC_WIFI_ST_CONNECTED || m.state == BC_WIFI_ST_CONNECTED_NO_INTERNET) && now - S.last_status_ms >= STATUS_PERIOD_MS);
        if (due && (S.status_now || !S.have_last || now - S.last_status_ms >= STATUS_MIN_GAP_MS)) {
            S.status_now = false; S.have_last = true; S.last_status = m; S.last_status_ms = now; S.st.status_sent++;
            *chr = APP_PSVC_CTRL;
            return bc_link_encode_wifi_status(&m, buf, cap, ++S.seq, now);
        }
    }
    /* 3. ride history, oldest first, ids above after_ride_id */
    if (S.sync_active) {
        bc_ride_summary_t s;
        while (S.sent < S.max_count && sync_next_line()) {
            if (!S.line_len || !bc_summary_from_line(&s, S.line) || s.id <= S.after_id) continue;
            size_t n = bc_link_encode_sync_ride(&s, buf, cap, ++S.seq, now);
            if (!n) continue;                                 /* cannot happen with BC_LINK_MAX; skip rather than stall */
            S.sent++; S.after_id = s.id; S.st.rides_sent++;
            *chr = APP_PSVC_SYNC;
            return n;
        }
        /* 0.7.4: then the rides kept only in RAM (storage damaged), oldest first - the shipped Cyclift imports them like any ride */
        { bc_ride_summary_t u[APP_UNSAVED_MAX]; int nu = app_unsaved_rides(u, APP_UNSAVED_MAX);
          while (S.sent < S.max_count && S.ram_i < nu) {
              bc_ride_summary_t *r = &u[S.ram_i++];
              if (r->id <= S.after_id) continue;
              size_t n = bc_link_encode_sync_ride(r, buf, cap, ++S.seq, now);
              if (!n) continue;
              S.sent++; S.after_id = r->id; S.st.rides_sent++;
              *chr = APP_PSVC_SYNC;
              return n;
          } }
        /* batch complete (max reached or end of file): is there more? peek ahead, then restore the reader completely */
        bool more = false;
        { bc_ride_summary_t u[APP_UNSAVED_MAX]; int nu = app_unsaved_rides(u, APP_UNSAVED_MAX);
          for (int i = S.ram_i; i < nu; i++) if (u[i].id > S.after_id) more = true; }
        if (S.sent >= S.max_count) {
            long off = S.off; bool eof = S.eof; int cp = S.chunk_pos, cl = S.chunk_len; char chunk[512]; memcpy(chunk, S.chunk, sizeof chunk);
            while (sync_next_line()) if (S.line_len && bc_summary_from_line(&s, S.line) && s.id > S.after_id) { more = true; break; }
            S.off = off; S.eof = eof; S.chunk_pos = cp; S.chunk_len = cl; memcpy(S.chunk, chunk, sizeof chunk);
        }
        bc_sync_end_t e = { .count = S.sent, .total = S.total, .more = more };
        S.sync_active = false;
        S.st.last_sync_ms = now ? now : 1; if (S.after_id > S.st.last_synced_id) S.st.last_synced_id = S.after_id; S.st.synced_all = !more;
        size_t n = bc_link_encode_sync_end(&e, buf, cap, ++S.seq, now);
        if (n && n <= sizeof S.last_end) { memcpy(S.last_end, buf, n); S.last_end_len = n; }
        *chr = APP_PSVC_SYNC;
        return n;
    }
    return 0;
}

app_psync_state_t app_psvc_sync_state(void)
{
    const bc_profile_t *p = app_profile();
    plat_phone_status_t ps; plat_phone_status(&ps);
    if (s_ps && S.set_seen && S.last_set_status == BC_PF_BAD) return APP_PSYNC_FAILED;
    if (ps.state == PLAT_PHONE_READY && !(s_ps && S.set_seen) && !p->prof_src) return APP_PSYNC_PENDING;   /* connected, phone has not sent its profile yet */
    return p->prof_src ? APP_PSYNC_SYNCED : APP_PSYNC_DEVICE_ONLY;
}

void app_psvc_pump(uint32_t now)
{
    if (!s_ps) return;
    if (s_disc_pending) { s_disc_pending = false; apply_disconnect(); }
    /* 0.7.0: when the phone is encrypted and listening, send PROFILE (so it can compare) and one LINK_DIAG event */
    { plat_phone_status_t ps; plat_phone_status(&ps);
      bool rising = ps.svc_ready && !S.was_ready;
      if (rising) { S.was_ready = true; S.hello_due = true; S.diag_due = true; S.set_seen = false; S.last_disc_code = ps.last_disc_code; S.last_disc = (uint8_t)ps.last_disc; }
      if (!ps.svc_ready) { S.was_ready = false; S.sd_due = 0; }
      app_diag_phone_ready(ps.svc_ready);                  /* 0.7.3: diag_ready on every new connection */
      app_link13_phone_ready(ps.svc_ready);                /* 0.7.5: a new connection is 1.2.3 until its APP_HELLO */
      sd_scan(now, rising);                                /* 0.7.2 SENSOR_DIAG bookkeeping (sent only while the phone listens) */
      if (!ps.svc_ready) S.sd_due = 0; }
    if (S.hello_due) { S.hello_due = false; S.profile_due = true; }
    uint8_t chr, b[BC_LINK_MAX]; int n, guard = 0;
    while ((n = plat_phone_take_svc(&chr, b, sizeof b)) > 0 && guard++ < 16) app_psvc_write(chr ? APP_PSVC_SYNC : APP_PSVC_CTRL, b, (size_t)n, now);
    if (S.held_len) { if (!plat_phone_notify_svc(S.held_chr, S.held, S.held_len)) return; S.held_len = 0; }
    for (int i = 0; i < NOTIFY_PER_PUMP; i++) {
        app_psvc_chr_t c; size_t m = app_psvc_next(&c, b, sizeof b, now);
        if (!m) break;
        if (!plat_phone_notify_svc((uint8_t)c, b, m)) { memcpy(S.held, b, m); S.held_len = m; S.held_chr = (uint8_t)c; break; }   /* transport full: keep it for the next pump */
    }
}

/* 0.7.3: called by the phone link on the NimBLE host task — only a flag here; the app task applies it in app_psvc_pump
   (0.7.0-0.7.2 reset these fields from the host task while the app task was using them) */
void app_psvc_on_disconnect(void) { s_disc_pending = true; }
static void apply_disconnect(void)
{
    if (!s_ps) return;
    S.sync_active = false; S.scan_pending = false; S.status_watch = false; S.have_last = false; S.status_now = false;
    S.profile_due = S.profile_ack_due = S.settings_due = false; S.held_len = 0; S.hello_due = S.diag_due = false; S.was_ready = false; S.sd_due = 0;
    app_diag_phone_ready(false);
    app_link13_phone_ready(false);
}

size_t app_psvc_last_sync_end(uint8_t *buf, size_t cap)
{
    if (!s_ps) return 0;
    if (!S.last_end_len || S.last_end_len > cap) return 0;
    memcpy(buf, S.last_end, S.last_end_len); return S.last_end_len;
}
