#include "app.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "bc_demo.h"

#define JOURNAL "rides/active.jnl"
#define HIST_REAL "rides/history.txt"
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
static char s_io[4096 + 1];      /* shared read buffer (history, recovery) — UI task only */

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

void app_live(app_live_t *o)
{
    memset(o, 0, sizeof *o);
    o->demo = s_demo;
    if (s_demo) {
        uint32_t age = plat_ms() - s_demo_t0;
        o->power_ok = s_demo_last.power >= 0; o->watts = s_demo_last.power;
        o->cad_ok = s_demo_last.cad >= 0; o->rpm = s_demo_last.cad;
        o->hr_ok = s_demo_last.hr > 0; o->bpm = s_demo_last.hr;
        for (int k = 0; k < PLAT_SENS_KINDS; k++) o->link[k].link = PLAT_LINK_UNSUPPORTED;
        o->link[PLAT_SENS_POWER].link = PLAT_LINK_CONNECTED;
        snprintf(o->link[PLAT_SENS_POWER].name, sizeof o->link[0].name, "DEMO METER");
        o->link[PLAT_SENS_POWER].age_ms = o->power_ok ? 300 : 5000;
        o->link[PLAT_SENS_POWER].packets = age / 1000;
        o->link[PLAT_SENS_HR].link = PLAT_LINK_NOT_PAIRED;
        return;
    }
    plat_sensors_t s; plat_sensors(&s);
    o->power_ok = s.power_ok; o->watts = s.watts; o->cad_ok = s.cad_ok; o->rpm = s.rpm; o->backwards = s.backwards;
    o->hr_ok = s.hr_ok; o->bpm = s.bpm;
    memcpy(o->link, s.link, sizeof o->link);
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

static void ride_second(bc_sample_t smp)
{
    char l[32];
    if (s_ride.state == BC_RIDE_RUNNING) {
        bc_ride_tick(&s_ride, smp);
        s_cue = *bc_coach_tick(&s_coach, smp, s_ride.s.duration_s);
        snprintf(l, sizeof l, "%d %d %d\n", smp.power, smp.cad, smp.hr);
    } else {
        bc_ride_tick_paused(&s_ride);
        snprintf(l, sizeof l, "-\n");
    }
    jput(l);
    if (++s_since_flush >= FLUSH_EVERY_S) jflush(true);
}

void app_tick(void)
{
    uint32_t now = plat_ms();
    if (!s_next_ms) s_next_ms = now + 1000;
    int guard = 0;
    while ((int32_t)(now - s_next_ms) >= 0 && guard++ < 3) {
        s_next_ms += 1000;
        if (s_demo) s_demo_last = bc_demo_next(&s_demo_gen);
        if (s_ride.state == BC_RIDE_RUNNING || s_ride.state == BC_RIDE_PAUSED) {
            app_live_t lv; app_live(&lv);
            bc_sample_t smp = { (int16_t)(lv.power_ok ? lv.watts : -1), (int16_t)(lv.cad_ok ? (lv.backwards ? 0 : lv.rpm) : -1),
                                (int16_t)(lv.hr_ok ? lv.bpm : -1) };
            ride_second(smp);
        }
    }
    if ((int32_t)(now - s_next_ms) > 3000) s_next_ms = now + 1000;   /* long stall (e.g. debugger): do not invent seconds */
}

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
    char l[96]; snprintf(l, sizeof l, "RIDE END #%u %lus avg %dW", s_ride.s.id, (unsigned long)s_ride.s.duration_s, s_ride.s.avg_power); plat_log(l);
}

int app_ride_ftp_evidence(void) { return s_ftp_evidence; }

static bool append_history(const bc_ride_summary_t *s)
{
    char line[400];
    size_t n = bc_summary_to_line(s, line, sizeof line - 1);
    if (!n) return false;
    line[n++] = '\n';
    return plat_file_append(s->demo ? HIST_DEMO : HIST_REAL, line, n, true);
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
            else { int pw, cd, hr; if (sscanf(s, "%d %d %d", &pw, &cd, &hr) == 3) { bc_ride_resume(&r);
                       bc_sample_t x = { (int16_t)pw, (int16_t)cd, (int16_t)hr }; bc_ride_tick(&r, x); bc_coach_tick(&c, x, r.s.duration_s); } }
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
    recover();
    plat_backlight(s_prof.brightness);
    char l[96]; snprintf(l, sizeof l, "APP profile %s, FTP %u W (%s), next ride #%u", s_prof.onboarded ? "loaded" : "new",
                         s_prof.ftp_w, bc_ftp_label(&s_prof), s_prof.next_ride_id);
    plat_log(l);
}

void app_health_line(char *buf, size_t cap)
{
    char mem[96]; plat_mem_text(mem, sizeof mem);
    app_live_t lv; app_live(&lv);
    snprintf(buf, cap, "HEALTH up %lus %s ride=%d demo=%d pw=%s cad=%s hr=%s", (unsigned long)(plat_ms() / 1000), mem, s_ride.state, s_demo,
             lv.power_ok ? "ok" : "--", lv.cad_ok ? "ok" : "--", lv.hr_ok ? "ok" : "--");
}
