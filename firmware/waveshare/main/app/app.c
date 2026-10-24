#include "app.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "bc_demo.h"
#include "bc_link.h"
#include "app_psvc.h"

#define JOURNAL "rides/active.jnl"
#define HIST_REAL APP_HIST_REAL
#define HIST_DEMO "demo/history.txt"
#define FLUSH_EVERY_S 10

static bc_profile_t s_prof;
static bool s_demo;
static bc_demo_t s_demo_gen;
static bc_sample_t s_demo_last = { -1, -1, -1 };
static uint32_t s_demo_t0;

static bc_ride_t s_ride;
static bc_coach_t s_coach;
static bc_cue_t s_cue;
static uint32_t s_next_ms;
static char s_jbuf[1024]; static size_t s_jlen; static int s_since_flush;
static int s_ftp_evidence;
static bool s_have_recovered; static bc_ride_summary_t s_recovered;
static char s_io[4096 + 1];
static uint32_t s_epoch_at_ms, s_epoch_s;   /* wall clock from the phone: epoch_s was true at plat_ms() == s_epoch_at_ms */
static bool s_stop_armed; static uint32_t s_stop_armed_ms;      /* shared read buffer (history, recovery) — UI task only */

bc_profile_t *app_profile(void) { return &s_prof; }

bool app_profile_save(void)
{
    char buf[1024];
    if (!bc_profile_to_text(&s_prof, buf, sizeof buf)) return false;
    return plat_profile_save(buf);
}

void app_profile_reset(void)
{
    uint16_t next = s_prof.next_ride_id, nextd = s_prof.next_demo_id;
    bc_profile_defaults(&s_prof);
    s_prof.next_ride_id = next; s_prof.next_demo_id = nextd;
    app_profile_save();
}

bool app_demo(void) { return s_demo; }
void app_set_demo(bool on)
{
    if (s_ride.state == BC_RIDE_RUNNING || s_ride.state == BC_RIDE_PAUSED) return;   /* never switch source mid-ride */
    s_demo = on;
    bc_demo_init(&s_demo_gen, s_prof.ftp_w ? s_prof.ftp_w * 70 / 100 : 160, false);
    s_demo_last.power = s_demo_last.cad = s_demo_last.hr = -1;
    s_demo_t0 = plat_ms();
    char l[64]; snprintf(l, sizeof l, "DEMO MODE %s (simulated sensor data)", on ? "ON" : "OFF"); plat_log(l);
}

static void app_phone_fold(app_live_t *o, bool strap_ok, int strap_bpm);

void app_live(app_live_t *o)
{
    memset(o, 0, sizeof *o);
    o->demo = s_demo;
    if (s_demo) {
        uint32_t age = plat_ms() - s_demo_t0;
        o->power_ok = s_demo_last.power >= 0; o->watts = s_demo_last.power;
        o->cad_ok = s_demo_last.cad >= 0; o->rpm = s_demo_last.cad;
        o->hr_ok = s_demo_last.hr > 0; o->bpm = s_demo_last.hr; o->hr_src = BC_SRC_DEMO;
        for (int k = 0; k < PLAT_SENS_KINDS; k++) o->link[k].link = PLAT_LINK_UNSUPPORTED;
        o->link[PLAT_SENS_POWER].link = PLAT_LINK_CONNECTED;
        snprintf(o->link[PLAT_SENS_POWER].name, sizeof o->link[0].name, "DEMO METER");
        o->cad_src = BC_SRC_DEMO;
        o->link[PLAT_SENS_POWER].age_ms = o->power_ok ? 300 : 5000;
        o->link[PLAT_SENS_POWER].valid_age_ms = o->power_ok ? 300 : 5000;
        o->link[PLAT_SENS_POWER].packets = age / 1000;
        o->link[PLAT_SENS_HR].link = PLAT_LINK_NOT_PAIRED;
        return;
    }
    plat_sensors_t s; plat_sensors(&s);
    o->power_ok = s.power_ok; o->watts = s.watts; o->cad_ok = s.cad_ok; o->rpm = s.rpm; o->backwards = s.backwards; o->cad_src = BC_SRC_XDS;
    if (!o->cad_ok && s.csc_cad_ok) { o->cad_ok = true; o->rpm = s.csc_rpm; o->backwards = false; o->cad_src = BC_SRC_BLE_CSC; }
    memcpy(o->link, s.link, sizeof o->link);
    app_phone_fold(o, s.hr_ok, s.bpm);
    /* a wheel sensor paired to the board is the better speed source; the phone's GPS stays as the fallback */
    o->csc_speed = s.csc_speed_ok;
    if (s.csc_speed_ok) { o->speed_ok = true; o->speed_dmh = s.csc_speed_dmh; o->speed_src = BC_SRC_BLE_CSC; }
}

/* Phone-relayed inputs: heart rate from a watch (or a strap paired to the phone) and the phone's GPS. Every value keeps
   its source; anything older than the freshness limit is dropped, never held. */
static void app_phone_fold(app_live_t *o, bool strap_ok, int strap_bpm)
{
    uint32_t now = plat_ms();
    plat_phone_in_t in; plat_phone_inputs(&in);
    bool phone_hr = in.hr.rx_ms && now - in.hr.rx_ms <= APP_PHONE_HR_FRESH_MS;
    o->strap_hr = strap_ok; o->phone_hr = phone_hr;
    bool phone_first = s_prof.hr_pref == 1;
    if (strap_ok && !(phone_first && phone_hr)) { o->hr_ok = true; o->bpm = strap_bpm; o->hr_src = BC_SRC_BLE_STRAP; }
    else if (phone_hr) { o->hr_ok = true; o->bpm = in.hr.v.bpm; o->hr_src = in.hr.v.src; }
    bool gps_fresh = in.gps.rx_ms && now - in.gps.rx_ms <= APP_GPS_FRESH_MS;
    o->gps_age_ms = in.gps.rx_ms ? now - in.gps.rx_ms : UINT32_MAX;
    if (gps_fresh && in.gps.v.speed_ok && in.gps.v.hacc_dm <= 500) { o->speed_ok = true; o->gps_speed = true; o->speed_dmh = (int)(in.gps.v.speed_cms * 36 / 100); o->speed_src = in.gps.v.src; }
    plat_link_info_t *sp = &o->link[PLAT_SENS_SPEED];
    plat_phone_status_t ps; plat_phone_status(&ps);
    memset(sp, 0, sizeof *sp);
    snprintf(sp->name, sizeof sp->name, "%s", in.gps.rx_ms ? bc_src_name(in.gps.v.src) : "PHONE GPS");
    sp->age_ms = sp->valid_age_ms = o->gps_age_ms;
    if (gps_fresh) sp->link = PLAT_LINK_CONNECTED;
    else if (in.gps.rx_ms && ps.state == PLAT_PHONE_READY) sp->link = PLAT_LINK_STALE;
    else if (ps.state == PLAT_PHONE_READY) sp->link = PLAT_LINK_SEARCHING;   /* phone connected, no position yet */
    else sp->link = PLAT_LINK_NOT_PAIRED;
    sp->rssi = ps.rssi;
    if (s_epoch_s) { o->time_known = true; o->epoch_s = s_epoch_s + (now - s_epoch_at_ms) / 1000; }
}

/* ---- journal: header + one line per second ("p c h", "-" for a paused second), flushed every 10 s */
static void jflush(bool sync)
{
    if (!s_jlen) return;
    plat_file_append(JOURNAL, s_jbuf, s_jlen, sync);
    s_jlen = 0; s_since_flush = 0;
}
static void jput(const char *line)
{
    size_t n = strlen(line);
    if (s_jlen + n >= sizeof s_jbuf) jflush(true);
    memcpy(s_jbuf + s_jlen, line, n); s_jlen += n;
}

void app_journal_flush(void) { jflush(true); }

static void ride_second(bc_sample_t smp)
{
    char l[48];
    if (s_ride.state == BC_RIDE_RUNNING) {
        bc_ride_tick(&s_ride, smp);
        s_cue = *bc_coach_tick(&s_coach, smp, s_ride.s.duration_s);
        snprintf(l, sizeof l, "%d %d %d %lu\n", smp.power, smp.cad, smp.hr, (unsigned long)s_ride.s.distance_m);
    } else {
        bc_ride_tick_paused(&s_ride);
        snprintf(l, sizeof l, "-\n");
    }
    jput(l);
    if (++s_since_flush >= FLUSH_EVERY_S) jflush(true);
}

/* wall clock: taken from the phone whenever it sends the time (the board has no battery-backed clock) */
static void phone_time_sync(void)
{
    plat_phone_in_t in; plat_phone_inputs(&in);
    if (!in.time.rx_ms || in.time.rx_ms == s_epoch_at_ms) return;
    s_epoch_at_ms = in.time.rx_ms; s_epoch_s = (uint32_t)(in.time.v.epoch_ms / 1000);
    if ((s_ride.state == BC_RIDE_RUNNING || s_ride.state == BC_RIDE_PAUSED) && !s_ride.s.start_epoch_s && s_epoch_s > s_ride.s.duration_s + s_ride.s.paused_s)
        s_ride.s.start_epoch_s = s_epoch_s - s_ride.s.duration_s - s_ride.s.paused_s;
}

/* ride control from the phone: same rules as the touch screen; STOP needs a second confirming message within 10 s */
static void phone_control(void)
{
    bc_ctrl_req_t q;
    if (s_stop_armed && plat_ms() - s_stop_armed_ms > 10000) s_stop_armed = false;
    if (!plat_phone_take_ctrl(&q)) return;
    uint8_t status;
    bc_ctrl_action_t a = bc_link_ctrl_decide(&q, (uint8_t)s_ride.state, s_ride.s.id, s_stop_armed, &status);
    switch (a) {
    case BC_ACT_START: app_ride_start(); break;
    case BC_ACT_PAUSE: app_ride_pause(); break;
    case BC_ACT_RESUME: app_ride_resume(); break;
    case BC_ACT_ARM_STOP: s_stop_armed = true; s_stop_armed_ms = plat_ms(); break;
    case BC_ACT_STOP: s_stop_armed = false; app_ride_end(); break;
    default: break;
    }
    bc_ctrl_resp_t r = { .req_id = q.req_id, .status = status, .ride_state = (uint8_t)s_ride.state, .ride_id = s_ride.s.id };
    plat_phone_ctrl_respond(&r);
    char l[64]; snprintf(l, sizeof l, "PHONE CTRL cmd %u -> status %u state %d", q.cmd, status, s_ride.state); plat_log(l);
}

static void publish_live(const app_live_t *lv)
{
    bc_ride_summary_t t; app_ride_totals(&t);
    bc_live_t L = { 0 };
    L.power_ok = lv->power_ok; L.power_w = (uint16_t)(lv->power_ok ? lv->watts : 0); L.power_age_ms = (uint16_t)(lv->link[PLAT_SENS_POWER].valid_age_ms > 60000 ? BC_LINK_NONE16 : lv->link[PLAT_SENS_POWER].valid_age_ms);
    L.cad_ok = lv->cad_ok; L.cadence_rpm = (uint8_t)(lv->cad_ok && lv->rpm >= 0 && lv->rpm < 255 ? lv->rpm : 0); L.cad_age_ms = L.power_age_ms;
    L.hr_ok = lv->hr_ok; L.hr_bpm = (uint8_t)(lv->hr_ok ? lv->bpm : 0); L.hr_src = lv->hr_src; L.hr_age_ms = 0;
    L.ride_state = (uint8_t)s_ride.state; L.ride_id = s_ride.s.id; L.elapsed_s = t.duration_s; L.distance_m = t.distance_m;
    L.cue_id = (uint8_t)s_cue.id; int bp = plat_battery_pct(); L.battery_pct = (uint8_t)(bp < 0 ? 0xFF : bp);
    L.meter_link = (uint8_t)lv->link[PLAT_SENS_POWER].link; L.meter_gaps = (uint16_t)lv->link[PLAT_SENS_POWER].gaps;
    L.demo = lv->demo;
    plat_phone_publish_live(&L);
}

void app_tick(void)
{
    uint32_t now = plat_ms();
    if (!s_next_ms) s_next_ms = now + 1000;
    int guard = 0;
    while ((int32_t)(now - s_next_ms) >= 0 && guard++ < 3) {
        s_next_ms += 1000;
        if (s_demo) s_demo_last = bc_demo_next(&s_demo_gen);
        phone_time_sync();
        app_live_t lv; app_live(&lv);
        if (s_ride.state == BC_RIDE_RUNNING || s_ride.state == BC_RIDE_PAUSED) {
            bc_sample_t smp = { (int16_t)(lv.power_ok ? lv.watts : -1), (int16_t)(lv.cad_ok ? (lv.backwards ? 0 : lv.rpm) : -1),
                                (int16_t)(lv.hr_ok ? lv.bpm : -1) };
            if (s_ride.state == BC_RIDE_RUNNING && lv.speed_ok && !s_demo) bc_ride_add_speed(&s_ride, (uint16_t)(lv.speed_dmh * 100 / 36), lv.speed_src);
            ride_second(smp);
        }
        phone_control();
        publish_live(&lv);
    }
    if ((int32_t)(now - s_next_ms) > 3000) s_next_ms = now + 1000;   /* long stall (e.g. debugger): do not invent seconds */
    app_psvc_pump(now);                                                 /* 0.6.0 phone services: sync, Wi-Fi, profile, settings */
}

uint32_t app_phone_passkey(void) { plat_phone_status_t ps; plat_phone_status(&ps); return ps.state == PLAT_PHONE_PAIRING ? ps.passkey : 0; }

bc_ride_state_t app_ride_state(void) { return s_ride.state; }
bool app_ride_is_demo(void) { return s_ride.s.demo; }
int app_coach_inband_pct(void) { return s_coach.judged_s >= 60 ? (int)((s_coach.inband_s * 100 + s_coach.judged_s / 2) / s_coach.judged_s) : -1; }

void app_ride_start(void)
{
    if (s_ride.state == BC_RIDE_RUNNING || s_ride.state == BC_RIDE_PAUSED) return;
    uint16_t id = s_demo ? s_prof.next_demo_id : s_prof.next_ride_id;
    bc_ride_start(&s_ride, id, s_demo, s_prof.ftp_w, s_prof.ftp_how, bc_ftp_established(&s_prof));
    bc_coach_init(&s_coach, &s_prof);
    memset(&s_cue, 0, sizeof s_cue);
    s_ftp_evidence = 0;
    plat_file_remove(JOURNAL);
    char h[96]; snprintf(h, sizeof h, "J1 %u %d %d %d %d\n", id, s_demo, s_prof.ftp_w, s_prof.ftp_how, bc_ftp_established(&s_prof));
    s_jlen = 0; jput(h); jflush(true);
    s_next_ms = plat_ms() + 1000;
    if (s_epoch_s) s_ride.s.start_epoch_s = s_epoch_s + (plat_ms() - s_epoch_at_ms) / 1000;
    s_stop_armed = false;
    plat_wifi_set_quiet(true);            /* ride in progress: Wi-Fi never scans or retries on its own */
    char l[64]; snprintf(l, sizeof l, "RIDE START #%u%s", id, s_demo ? " (DEMO)" : ""); plat_log(l);
}

void app_ride_pause(void) { bc_ride_pause(&s_ride); jflush(true); plat_log("RIDE PAUSE"); }
void app_ride_resume(void) { bc_ride_resume(&s_ride); plat_log("RIDE RESUME"); }

static void finish(bc_ride_t *r, bc_coach_t *c)
{
    bc_ride_end(r);
    int pct; bc_coach_summary(c, &r->s, r->s.coach, sizeof r->s.coach, &pct);
    r->s.inband_pct = pct;
}

void app_ride_end(void)
{
    if (s_ride.state != BC_RIDE_RUNNING && s_ride.state != BC_RIDE_PAUSED) return;
    jflush(true);
    finish(&s_ride, &s_coach);
    s_ftp_evidence = s_ride.s.demo ? 0 : bc_ride_ftp_estimate(&s_ride);
    plat_wifi_set_quiet(false);
    char l[96]; snprintf(l, sizeof l, "RIDE END #%u %lus avg %dW", s_ride.s.id, (unsigned long)s_ride.s.duration_s, s_ride.s.avg_power); plat_log(l);
}

int app_ride_ftp_evidence(void) { return s_ftp_evidence; }

static bool append_history(const bc_ride_summary_t *s)
{
    char line[400];
    size_t n = bc_summary_to_line(s, line, sizeof line - 1);
    if (!n) return false;
    line[n++] = '\n';
    const char *path = s->demo ? HIST_DEMO : HIST_REAL;
    /* if a previous write was cut by a power loss (last line without newline), start on a fresh line so the torn
       record is the only one lost and this ride is stored intact */
    long sz = plat_file_size(path);
    if (sz > 0) { char last = 0; if (plat_file_read_at(path, sz - 1, &last, 1) == 1 && last != '\n') plat_file_append(path, "\n", 1, false); }
    return plat_file_append(path, line, n, true);
}

static void keep_samples(uint16_t id, bool demo)
{
    /* the per-second file is kept for real rides (future export to the phone apps); demo samples are dropped */
    if (demo) { plat_file_remove(JOURNAL); return; }
    char path[32]; snprintf(path, sizeof path, "rides/r%04u.txt", id);
    plat_file_remove(path);
    if (!plat_file_rename(JOURNAL, path)) plat_file_remove(JOURNAL);
}

bool app_ride_save(void)
{
    if (s_ride.state != BC_RIDE_ENDED) return false;
    if (!s_ride.s.demo) bc_ride_apply_ftp(&s_ride, &s_prof);
    bool ok = append_history(&s_ride.s);
    if (s_ride.s.demo) s_prof.next_demo_id++; else s_prof.next_ride_id++;
    app_profile_save();
    keep_samples(s_ride.s.id, s_ride.s.demo);
    char l[64]; snprintf(l, sizeof l, "RIDE SAVED #%u%s %s", s_ride.s.id, s_ride.s.demo ? " (DEMO)" : "", ok ? "OK" : "FAILED"); plat_log(l);
    s_ride.state = BC_RIDE_IDLE;
    return ok;
}

void app_ride_discard(void)
{
    plat_file_remove(JOURNAL);
    s_ride.state = BC_RIDE_IDLE;
    plat_log("RIDE DISCARDED");
}

void app_ride_totals(bc_ride_summary_t *out)
{
    if (s_ride.state == BC_RIDE_ENDED) *out = s_ride.s; else bc_ride_live_summary(&s_ride, out);
}

const bc_cue_t *app_cue(void) { return &s_cue; }
void app_target(int *lo, int *hi, bool *rel) { bc_coach_target(&s_coach, lo, hi, rel); }

/* ---- history */
int app_history(bc_ride_summary_t *out, int max, bool demo)
{
    /* stream the file and keep the newest `max` rides in a ring, then return them newest first */
    char *chunk = s_io;
    const char *path = demo ? HIST_DEMO : HIST_REAL;
    int total = 0; long off = 0;
    if (max <= 0) return 0;
    for (;;) {
        long n = plat_file_read_at(path, off, chunk, 4096);
        if (n <= 0) break;
        chunk[n] = 0;
        char *s = chunk, *e; long used = 0;
        while ((e = strchr(s, '\n')) != NULL) {
            *e = 0;
            if (bc_summary_from_line(&out[total % max], s)) total++;
            used = (e - chunk) + 1; s = e + 1;
        }
        if (used == 0) break;
        off += used;
    }
    int k = total < max ? total : max;
    /* out[] holds the newest k entries in ring order (oldest at total % max once wrapped): rotate, then reverse in place */
    if (total > max) {
        int start = total % max;   /* rotate left by start using three reversals */
        for (int a = 0, b = start - 1; a < b; a++, b--) { bc_ride_summary_t t = out[a]; out[a] = out[b]; out[b] = t; }
        for (int a = start, b = max - 1; a < b; a++, b--) { bc_ride_summary_t t = out[a]; out[a] = out[b]; out[b] = t; }
        for (int a = 0, b = max - 1; a < b; a++, b--) { bc_ride_summary_t t = out[a]; out[a] = out[b]; out[b] = t; }
    }
    for (int a = 0, b = k - 1; a < b; a++, b--) { bc_ride_summary_t t = out[a]; out[a] = out[b]; out[b] = t; }
    return k;
}

bool app_history_clear(bool demo) { return plat_file_remove(demo ? HIST_DEMO : HIST_REAL); }

/* ---- crash / power-loss recovery: replay the journal into a fresh recorder and coach */
static void recover(void)
{
    char *chunk = s_io; bc_ride_t *rp = &s_ride; static bc_coach_t c;
#define r (*rp)
    long n = plat_file_read_at(JOURNAL, 0, chunk, 4096);
    if (n <= 0) return;
    chunk[n] = 0;
    unsigned id = 0; int demo = 0, ftp = 0, how = 0, est = 0;
    char *nl = strchr(chunk, '\n');
    if (!nl || sscanf(chunk, "J1 %u %d %d %d %d", &id, &demo, &ftp, &how, &est) != 5) { plat_file_remove(JOURNAL); return; }
    bc_profile_t p = s_prof; p.ftp_w = (uint16_t)ftp; p.ftp_how = (uint8_t)how;
    bc_ride_start(&r, (uint16_t)id, demo, ftp, (uint8_t)how, est);
    bc_coach_init(&c, &p);
    long off = (nl - chunk) + 1;
    for (;;) {                                               /* stream line by line; a half-written last line is ignored */
        n = plat_file_read_at(JOURNAL, off, chunk, 4096);
        if (n <= 0) break;
        chunk[n] = 0;
        char *s = chunk, *e; long used = 0;
        while ((e = strchr(s, '\n')) != NULL) {
            *e = 0;
            if (s[0] == '-') { bc_ride_pause(&r); bc_ride_tick_paused(&r); }
            else { int pw, cd, hr; unsigned long dm = 0; int nf = sscanf(s, "%d %d %d %lu", &pw, &cd, &hr, &dm);
                   if (nf >= 3) { bc_ride_resume(&r);
                       bc_sample_t x = { (int16_t)pw, (int16_t)cd, (int16_t)hr }; bc_ride_tick(&r, x); bc_coach_tick(&c, x, r.s.duration_s);
                       if (nf == 4 && dm) { r.s.distance_m = (uint32_t)dm; r.s.dist_src = BC_SRC_PHONE_GPS; } } }
            used = (e - chunk) + 1; s = e + 1;
        }
        if (used == 0) break;
        off += used;
    }
    if (r.state == BC_RIDE_PAUSED) bc_ride_resume(&r);
    finish(&r, &c);
    r.s.recovered = true;
    char l[96];
    if (demo || r.s.duration_s < 10) {
        snprintf(l, sizeof l, "RECOVERY: interrupted %s ride #%u (%lus) not kept", demo ? "DEMO" : "very short", id, (unsigned long)r.s.duration_s);
        plat_log(l); plat_file_remove(JOURNAL); memset(&s_ride, 0, sizeof s_ride); return;
    }
    if (id >= s_prof.next_ride_id) s_prof.next_ride_id = (uint16_t)(id + 1);
    bc_ride_apply_ftp(&r, &s_prof);
    append_history(&r.s);
    app_profile_save();
    keep_samples(r.s.id, false);
    s_recovered = r.s; s_have_recovered = true;
    snprintf(l, sizeof l, "RECOVERY: ride #%u restored, %lus, saved to history", id, (unsigned long)r.s.duration_s); plat_log(l);
    memset(&s_ride, 0, sizeof s_ride);
#undef r
}

bool app_take_recovered(bc_ride_summary_t *out)
{
    if (!s_have_recovered) return false;
    *out = s_recovered; s_have_recovered = false; return true;
}

void app_init(void)
{
    static char buf[1024];
    bc_profile_defaults(&s_prof);
    if (plat_profile_load(buf, sizeof buf)) bc_profile_from_text(&s_prof, buf);
    memset(&s_ride, 0, sizeof s_ride);
    s_demo = false;
    app_psvc_init();
    recover();
    plat_backlight(s_prof.brightness);
    plat_csc_wheel_mm(s_prof.wheel_mm);
    /* 0.6.0 fix: the phone link's advertising was only ever switched on by the Settings/Quick Settings toggle, never at
       boot — after every restart or deep-sleep wake the board stayed invisible to the phone until the rider toggled it. */
    plat_phone_set_enabled(s_prof.phone_on);
    char l[96]; snprintf(l, sizeof l, "APP profile %s, FTP %u W (%s), next ride #%u", s_prof.onboarded ? "loaded" : "new",
                         s_prof.ftp_w, bc_ftp_label(&s_prof), s_prof.next_ride_id);
    plat_log(l);
}

void app_health_line(char *buf, size_t cap)
{
    char mem[96]; plat_mem_text(mem, sizeof mem);
    app_live_t lv; app_live(&lv);
    plat_wifi_status_t w; plat_wifi_status(&w);
    plat_phone_status_t ph; plat_phone_status(&ph);
    snprintf(buf, cap, "HEALTH up %lus %s ride=%d demo=%d pw=%s cad=%s hr=%s gaps=%lu wifi=%d rssi=%d phone=%d rx=%lu rej=%lu gps=%s",
             (unsigned long)(plat_ms() / 1000), mem, s_ride.state, s_demo, lv.power_ok ? "ok" : "--", lv.cad_ok ? "ok" : "--",
             lv.hr_ok ? bc_src_name(lv.hr_src) : "--", (unsigned long)lv.link[PLAT_SENS_POWER].gaps, (int)w.state, w.rssi,
             (int)ph.state, (unsigned long)ph.rx_msgs, (unsigned long)ph.rx_rejected, lv.speed_ok ? "ok" : "--");
}
