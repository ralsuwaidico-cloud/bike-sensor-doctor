/* Host unit tests for the portable cycling-computer core (profile, FTP rules, ride recorder, history, coach, demo). */
#include <stdio.h>
#include <string.h>
#include "bc_hr.h"
#include "bc_profile.h"
#include "bc_ride.h"
#include "bc_coach.h"
#include "bc_demo.h"
#include "bc_wifi.h"

static int fails, checks;
#define CHECK(c) do { checks++; if (!(c)) { fails++; printf("FAIL %s:%d  %s\n", __FILE__, __LINE__, #c); } } while (0)

static void t_hr(void)
{
    int b = 0;
    uint8_t u8[] = { 0x00, 72 }; CHECK(bc_hr_decode(u8, 2, &b) && b == 72);
    uint8_t u16[] = { 0x01, 0x2C, 0x01 }; CHECK(!bc_hr_decode(u16, 3, &b));          /* 300 bpm is implausible */
    uint8_t u16b[] = { 0x01, 150, 0 }; CHECK(bc_hr_decode(u16b, 3, &b) && b == 150);
    uint8_t s[] = { 0x01, 150 }; CHECK(!bc_hr_decode(s, 2, &b));
    bc_hr_live_t l; bc_hr_live_reset(&l);
    CHECK(bc_hr_live_bpm(&l, 0, &b) == BC_LIVE_NO_DATA);
    bc_hr_live_feed(&l, u8, 2, 1000);
    CHECK(bc_hr_live_bpm(&l, 4000, &b) == BC_LIVE_OK && b == 72);
    CHECK(bc_hr_live_bpm(&l, 5001, &b) == BC_LIVE_NO_DATA);                           /* stale → NO DATA, never held */
}

static void t_profile(void)
{
    bc_profile_t p, q; bc_profile_defaults(&p);
    CHECK(bc_starting_ftp(750, BC_EXP_INTERMEDIATE) == 225);
    CHECK(bc_starting_ftp(800, BC_EXP_BEGINNER) == 140);
    CHECK(bc_starting_ftp(0, BC_EXP_BEGINNER) == 0);
    bc_profile_refresh_assumption(&p);
    CHECK(p.ftp_w == 225 && p.ftp_how == BC_FTP_ASSUMED && !bc_ftp_established(&p));
    CHECK(!strcmp(bc_ftp_label(&p), "PROVISIONAL"));
    p.weight_dg = 905; bc_profile_refresh_assumption(&p); CHECK(p.ftp_w == 272);  /* 90.5 × 3.0 = 271.5 → 272 */
    p.ftp_how = BC_FTP_ENTERED; p.ftp_w = 250; p.weight_dg = 600; bc_profile_refresh_assumption(&p); CHECK(p.ftp_w == 250);
    strcpy(p.name, "Rashed Al S"); p.power.paired = true; p.power.mac[0] = 0xAB; p.power.mac[5] = 0x01; p.power.addr_type = 1;
    strcpy(p.power.name, "XDS-A001-9769"); p.height_cm = 178; p.onboarded = true; p.ride_style = BC_STYLE_COACH;
    char buf[1024]; size_t n = bc_profile_to_text(&p, buf, sizeof buf); CHECK(n > 0);
    CHECK(bc_profile_from_text(&q, buf));
    CHECK(!strcmp(q.name, "Rashed Al S") && q.age == p.age && q.weight_dg == 600 && q.height_cm == 178 && q.ftp_w == 250);
    CHECK(q.ftp_how == BC_FTP_ENTERED && q.power.paired && q.power.mac[0] == 0xAB && q.power.mac[5] == 1 && q.power.addr_type == 1);
    CHECK(!strcmp(q.power.name, "XDS-A001-9769") && q.onboarded && q.ride_style == BC_STYLE_COACH && !q.hr.paired);
    CHECK(bc_profile_from_text(&q, "garbage\nage=500\nexp=99\nunknown=1\n") && q.age == 120 && q.exp == BC_EXP_COMPETITIVE && !q.onboarded);
    CHECK(bc_profile_to_text(&p, buf, 20) == 0);                                       /* too small → 0, never truncated */
    p.max_hr = 0; p.age = 40; CHECK(bc_profile_max_hr(&p) == 180);
}

static bc_sample_t S(int p, int c, int h) { bc_sample_t s = { (int16_t)p, (int16_t)c, (int16_t)h }; return s; }

static void t_ride(void)
{
    static bc_ride_t r;
    bc_ride_start(&r, 7, false, 200, BC_FTP_ASSUMED, false);
    for (int i = 0; i < 60; i++) bc_ride_tick(&r, S(200, 90, -1));
    for (int i = 0; i < 10; i++) bc_ride_tick(&r, S(-1, -1, -1));                    /* sensor gap: excluded */
    for (int i = 0; i < 30; i++) bc_ride_tick(&r, S(0, 0, -1));                      /* coasting: 0 W counts, cadence not */
    bc_ride_pause(&r); for (int i = 0; i < 20; i++) { bc_ride_tick(&r, S(500, 90, -1)); bc_ride_tick_paused(&r); }
    bc_ride_resume(&r);
    bc_ride_end(&r);
    CHECK(r.s.duration_s == 100 && r.s.paused_s == 20);
    CHECK(r.s.avg_power == 133);                                                      /* 60×200 / 90 */
    CHECK(r.s.max_power == 200 && r.s.avg_cad == 90 && r.s.avg_hr == -1 && r.s.hr_s == 0);
    CHECK(!r.s.zones_valid && r.s.zone_s[1] == 0);                                    /* provisional FTP → no zones */
    CHECK(r.s.best20 == -1 && bc_ride_ftp_estimate(&r) == 0);

    bc_ride_start(&r, 8, false, 200, BC_FTP_AUTO, true);
    for (int i = 0; i < 100; i++) bc_ride_tick(&r, S(140, 85, 130));
    bc_ride_end(&r);
    CHECK(r.s.zones_valid && r.s.zone_s[1] == 100 && r.s.avg_hr == 130 && r.s.max_hr == 130);
    CHECK(bc_power_zone(110, 200) == 1 && bc_power_zone(111, 200) == 2 && bc_power_zone(301, 200) == 7 && bc_power_zone(0, 200) == 0);

    char line[400]; bc_ride_summary_t a = r.s, b;
    strcpy(a.coach, "Line, with commas, and\nnewline"); a.recovered = true;
    CHECK(bc_summary_to_line(&a, line, sizeof line) > 0);
    CHECK(bc_summary_from_line(&b, line));
    CHECK(b.id == 8 && b.duration_s == 100 && b.zone_s[1] == 100 && b.recovered && b.avg_hr == 130 && !strcmp(b.coach, "Line, with commas, and newline"));
    CHECK(!bc_summary_from_line(&b, "R1,1,2,3"));
    char d[16]; bc_fmt_duration(3725, d, sizeof d); CHECK(!strcmp(d, "1:02:05")); bc_fmt_duration(65, d, sizeof d); CHECK(!strcmp(d, "1:05"));
}

static void ride_with_effort(bc_ride_t *r, bool demo, int effort_w, int easy_w)
{
    bc_ride_start(r, 9, demo, 225, BC_FTP_ASSUMED, false);
    for (int i = 0; i < 900; i++) bc_ride_tick(r, S(easy_w, 85, -1));
    for (int i = 0; i < 1200; i++) bc_ride_tick(r, S(effort_w + (i % 2 ? 5 : -5), 90, -1));
    for (int i = 0; i < 600; i++) bc_ride_tick(r, S(easy_w, 85, -1));
    bc_ride_end(r);
}

static void t_auto_ftp(void)
{
    static bc_ride_t r; bc_profile_t p; bc_profile_defaults(&p); bc_profile_refresh_assumption(&p);
    /* ordinary endurance ride → no evidence */
    ride_with_effort(&r, false, 150, 150);
    CHECK(bc_ride_ftp_estimate(&r) == 0 && !bc_ride_apply_ftp(&r, &p) && p.ftp_how == BC_FTP_ASSUMED);
    /* steady hard 20 min → 95 % of 260 = 247, replaces the assumption */
    ride_with_effort(&r, false, 260, 150);
    CHECK(bc_ride_ftp_estimate(&r) == 247);
    CHECK(bc_ride_apply_ftp(&r, &p) && p.ftp_w == 247 && p.ftp_how == BC_FTP_AUTO && r.s.ftp_new == 247 && p.ftp_from_ride == 9);
    CHECK(bc_ftp_established(&p) && strstr(p.ftp_note, "Ride #9") != NULL);
    /* demo ride never changes the FTP */
    bc_profile_defaults(&p); bc_profile_refresh_assumption(&p);
    ride_with_effort(&r, true, 300, 150);
    CHECK(!bc_ride_apply_ftp(&r, &p) && p.ftp_w == 225 && p.ftp_how == BC_FTP_ASSUMED && r.s.ftp_new == 0);
    /* an entered FTP is never overwritten: suggestion only */
    p.ftp_how = BC_FTP_ENTERED; p.ftp_w = 200;
    ride_with_effort(&r, false, 260, 150);
    CHECK(!bc_ride_apply_ftp(&r, &p) && p.ftp_w == 200 && r.s.ftp_new == 247 && r.s.ftp_suggested_only);
    /* unsteady effort (CV > 15 %) does not qualify */
    bc_ride_start(&r, 10, false, 225, BC_FTP_ASSUMED, false);
    for (int i = 0; i < 900; i++) bc_ride_tick(&r, S(150, 85, -1));
    for (int i = 0; i < 1200; i++) bc_ride_tick(&r, S(i % 2 ? 400 : 120, 85, -1));
    for (int i = 0; i < 600; i++) bc_ride_tick(&r, S(150, 85, -1));
    bc_ride_end(&r); CHECK(bc_ride_ftp_estimate(&r) == 0);
}

static bc_profile_t prof(bool established, int ftp)
{
    bc_profile_t p; bc_profile_defaults(&p); p.age = 35; p.exp = BC_EXP_INTERMEDIATE;
    p.ftp_w = (uint16_t)ftp; p.ftp_how = established ? BC_FTP_AUTO : BC_FTP_ASSUMED; return p;
}

static const bc_cue_t *run(bc_coach_t *c, uint32_t *t, int secs, bc_sample_t s)
{
    const bc_cue_t *q = NULL; for (int i = 0; i < secs; i++) q = bc_coach_tick(c, s, (*t)++); return q;
}

static void t_coach(void)
{
    bc_coach_t c; uint32_t t = 0; const bc_cue_t *q;
    bc_profile_t p = prof(true, 200);                                                 /* Z2 = 112..150 W */
    bc_coach_init(&c, &p);
    q = run(&c, &t, 3, S(-1, -1, -1)); CHECK(q->id == BC_CUE_NO_DATA);
    q = run(&c, &t, 60, S(130, 88, -1)); CHECK(q->id == BC_CUE_WARMUP);              /* warm-up first 5 min */
    q = run(&c, &t, 20, S(190, 88, -1)); CHECK(q->id == BC_CUE_WARMUP_EASY);
    t = 300; bc_coach_init(&c, &p);
    q = run(&c, &t, 30, S(130, 88, -1)); CHECK(q->id == BC_CUE_HOLD && q->level == BC_LVL_GOOD && strstr(q->why, "112-150"));
    q = run(&c, &t, 12, S(180, 88, -1)); CHECK(q->id == BC_CUE_EASE_OFF && strstr(q->why, "> 150"));
    q = run(&c, &t, 20, S(90, 88, -1)); CHECK(q->id == BC_CUE_MORE && q->level == BC_LVL_UP);
    q = run(&c, &t, 20, S(90, 88, 150)); CHECK(q->id != BC_CUE_MORE);                /* HR already up: never ask for more */
    q = run(&c, &t, 30, S(130, 88, 160)); CHECK(q->id == BC_CUE_HR_HIGH && strstr(q->why, "HR 160")); /* cap 80 % of 185 = 148 */
    q = run(&c, &t, 30, S(130, 88, -1)); CHECK(q->id == BC_CUE_HOLD);                /* works without a strap */
    q = run(&c, &t, 30, S(130, 62, -1)); CHECK(q->id == BC_CUE_CAD_LOW && strstr(q->why, "62 rpm"));
    q = run(&c, &t, 30, S(0, 0, -1)); CHECK(q->id == BC_CUE_COASTING);
    q = run(&c, &t, 6, S(-1, -1, -1)); CHECK(q->id == BC_CUE_NO_DATA);
    q = run(&c, &t, 20, S(-1, 88, -1)); CHECK(q->id == BC_CUE_HOLD && !strcmp(q->head, "CADENCE ONLY"));
    q = run(&c, &t, 10, S(130, 88, -1)); q = run(&c, &t, 4, S(320, 95, -1)); CHECK(q->id == BC_CUE_SURGE);

    /* provisional FTP: learns the rider's own pace, never treats the assumption as fact */
    p = prof(false, 225); bc_coach_init(&c, &p); t = 300;
    q = run(&c, &t, 60, S(170, 88, -1)); CHECK(q->id == BC_CUE_LEARNING);
    int lo, hi; bool rel; bc_coach_target(&c, &lo, &hi, &rel); CHECK(rel && lo == 0);
    q = run(&c, &t, 150, S(170, 88, -1)); CHECK(q->id == BC_CUE_HOLD && !strcmp(q->head, "GOOD PACE - HOLD"));
    bc_coach_target(&c, &lo, &hi, &rel); CHECK(rel && lo == 153 && hi == 187);
    q = run(&c, &t, 130, S(120, 88, -1)); CHECK(q->id == BC_CUE_DROPPING);
    bc_coach_init(&c, &p); t = 300;
    q = run(&c, &t, 400, S(220, 88, -1)); CHECK(q->id == BC_CUE_EASE_OFF && strstr(q->why, "(prov.)")); /* 220 > 90 % × 225 */

    char sum[120]; int pct; bc_ride_summary_t rs; memset(&rs, 0, sizeof rs); rs.power_s = 100; rs.avg_cad = 70;
    bc_coach_summary(&c, &rs, sum, sizeof sum, &pct); CHECK(strlen(sum) < 120 && strstr(sum, "provisional") && strstr(sum, "70 rpm"));
    rs.power_s = 0; rs.cad_s = 0; bc_coach_summary(&c, &rs, sum, sizeof sum, &pct); CHECK(strstr(sum, "No power") != NULL);
}

static void t_demo(void)
{
    bc_demo_t d; bc_demo_init(&d, 180, false); int gaps = 0, coast = 0, maxw = 0;
    for (int i = 0; i < 1200; i++) { bc_sample_t s = bc_demo_next(&d); if (s.power < 0) gaps++; if (s.power == 0 && s.cad == 0) coast++; if (s.power > maxw) maxw = s.power; CHECK(s.hr == -1); }
    CHECK(gaps == 8 && coast == 30 && maxw > 280);
    bc_demo_init(&d, 180, true); bc_sample_t s = { 0, 0, 0 }; for (int i = 0; i < 400; i++) s = bc_demo_next(&d); CHECK(s.hr > 100 && s.hr < 200);
}

static void t_wifi(void)
{
    CHECK(bc_wifi_pass_valid("") && bc_wifi_pass_valid("12345678") && !bc_wifi_pass_valid("1234567") && !bc_wifi_pass_valid("bad\x01pass1"));
    char p63[64]; memset(p63, 'a', 63); p63[63] = 0; CHECK(bc_wifi_pass_valid(p63));
    char p64[65]; memset(p64, 'a', 64); p64[64] = 0; CHECK(!bc_wifi_pass_valid(p64));
    CHECK(!bc_wifi_ssid_valid("") && bc_wifi_ssid_valid("Rashed's iPhone"));
    bc_wifi_store_t st; bc_wifi_store_init(&st);
    CHECK(bc_wifi_store_put(&st, "Home", "secret123") && bc_wifi_store_put(&st, "Rashed's iPhone", "p@ss w0rd!") && bc_wifi_store_put(&st, "Cafe", ""));
    CHECK(st.n == 3 && !strcmp(st.c[0].ssid, "Cafe") && !strcmp(st.c[2].ssid, "Home"));
    CHECK(!bc_wifi_store_put(&st, "X", "short"));
    bc_wifi_store_put(&st, "Home", "newpass99"); CHECK(st.n == 3 && !strcmp(st.c[0].ssid, "Home") && !strcmp(st.c[0].pass, "newpass99"));
    for (int i = 0; i < 6; i++) { char n[16]; snprintf(n, sizeof n, "N%d", i); bc_wifi_store_put(&st, n, "12345678"); }
    CHECK(st.n == BC_WIFI_MAX_SAVED && !strcmp(st.c[0].ssid, "N5") && bc_wifi_store_find(&st, "Home") == NULL);
    unsigned char buf[512]; size_t n = bc_wifi_store_pack(&st, buf, sizeof buf); CHECK(n > 10);
    bc_wifi_store_t s2; CHECK(bc_wifi_store_unpack(&s2, buf, n) && s2.n == st.n && !strcmp(s2.c[4].ssid, st.c[4].ssid) && !strcmp(s2.c[1].pass, "12345678"));
    CHECK(!bc_wifi_store_unpack(&s2, buf, n - 3) && s2.n == 0);     /* truncated flash data is rejected, not half-read */
    CHECK(bc_wifi_store_remove(&st, "N3") && st.n == 4 && !bc_wifi_store_find(&st, "N3") && !bc_wifi_store_remove(&st, "N3"));
    bc_wifi_store_init(&st); bc_wifi_store_put(&st, "Home", "12345678"); bc_wifi_store_put(&st, "Phone", "12345678");   /* Phone most recent */
    const char seen[3][33] = { "Neighbour", "Home", "Phone" }; int rs[3] = { -40, -60, -62 };
    CHECK(bc_wifi_pick(&st, seen, rs, 3) == 0);                        /* Phone (recent) kept: Home is not 3 dB stronger */
    int rs2[3] = { -40, -50, -70 }; CHECK(bc_wifi_pick(&st, seen, rs2, 3) == 1);   /* Home clearly stronger */
    const char none[1][33] = { "Other" }; int r1[1] = { -30 }; CHECK(bc_wifi_pick(&st, none, r1, 1) == -1);
    CHECK(bc_wifi_map_reason(15, true, false) == BC_WIFI_ERR_WRONG_PASSWORD && bc_wifi_map_reason(202, true, false) == BC_WIFI_ERR_WRONG_PASSWORD);
    CHECK(bc_wifi_map_reason(201, true, false) == BC_WIFI_ERR_NOT_FOUND && bc_wifi_map_reason(211, false, false) == BC_WIFI_ERR_NOT_FOUND);
    CHECK(bc_wifi_map_reason(200, true, true) == BC_WIFI_ERR_LOST && bc_wifi_map_reason(8, true, true) == BC_WIFI_ERR_LOST);
    CHECK(bc_wifi_backoff_s(0) == 5 && bc_wifi_backoff_s(2) == 30 && bc_wifi_backoff_s(9) == 60);
    CHECK(strlen(bc_wifi_err_text(BC_WIFI_ERR_WRONG_PASSWORD)) > 5);
}

int main(void)
{
    t_hr(); t_profile(); t_ride(); t_auto_ftp(); t_coach(); t_demo(); t_wifi();
    printf("%d checks, %d failures\n", checks, fails);
    return fails ? 1 : 0;
}
