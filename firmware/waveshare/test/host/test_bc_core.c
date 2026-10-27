/* Host unit tests for the portable cycling-computer core (profile, FTP rules, ride recorder, history, coach, demo). */
#include <stdio.h>
#include <string.h>
#include "bc_hr.h"
#include "bc_profile.h"
#include "bc_ride.h"
#include "bc_coach.h"
#include "bc_demo.h"
#include "bc_wifi.h"
#include "bc_link.h"
#include "bc_power.h"

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

static void t_link(void)
{
    {   /* 0.2.x history lines (R1) still parse; R2 round-trips distance */
        bc_ride_summary_t s1;
        CHECK(bc_summary_from_line(&s1, "R1,3,0,0,3600,0,200,400,85,150,170,3600,3000,3600,1,0,0,1800,1800,0,0,0,225,1,720,210,80,0,0,ok ride") && s1.id == 3 && s1.distance_m == 0 && s1.coach[0] == 'o');
        bc_ride_t r; bc_ride_start(&r, 4, false, 225, 1, true);
        bc_sample_t smp = { 200, 90, 150 };
        for (int i = 0; i < 10; i++) { bc_ride_tick(&r, smp); bc_ride_add_speed(&r, 833, BC_SRC_PHONE_GPS); }   /* 30 km/h */
        bc_ride_add_speed(&r, 30, BC_SRC_PHONE_GPS);        /* standing-still noise is ignored */
        CHECK(r.s.distance_m == 83 && r.s.dist_src == BC_SRC_PHONE_GPS);
        bc_ride_pause(&r); bc_ride_add_speed(&r, 833, BC_SRC_PHONE_GPS); CHECK(r.s.distance_m == 83);   /* paused: no distance */
        bc_ride_resume(&r); bc_ride_end(&r); r.s.start_epoch_s = 1761300000u;
        char line[400]; CHECK(bc_summary_to_line(&r.s, line, sizeof line) > 0 && !strncmp(line, "R2,", 3));
        bc_ride_summary_t s2; CHECK(bc_summary_from_line(&s2, line) && s2.distance_m == 83 && s2.dist_src == BC_SRC_PHONE_GPS && s2.start_epoch_s == 1761300000u && s2.id == 4);
    }
    uint8_t buf[BC_LINK_MAX];
    /* LIVE round trip, including "no data" fields left out */
    bc_live_t a = { .power_ok = true, .power_w = 231, .power_age_ms = 400, .cad_ok = true, .cadence_rpm = 88, .cad_age_ms = 500,
                    .hr_ok = false, .ride_state = 1, .ride_id = 12, .elapsed_s = 3600, .distance_m = 25000, .cue_id = 3,
                    .battery_pct = 77, .meter_link = 4, .meter_gaps = 2, .demo = false };
    size_t n = bc_link_encode_live(&a, buf, sizeof buf, 7, 123456);
    CHECK(n > BC_LINK_HDR && n <= BC_LINK_MAX);
    bc_live_t b; CHECK(bc_link_decode_live(buf, n, &b));
    CHECK(b.power_ok && b.power_w == 231 && b.power_age_ms == 400 && b.cad_ok && b.cadence_rpm == 88 && !b.hr_ok);
    CHECK(b.ride_state == 1 && b.ride_id == 12 && b.elapsed_s == 3600 && b.distance_m == 25000 && b.battery_pct == 77 && b.meter_gaps == 2 && !b.demo);
    bc_link_hdr_t h; bc_lr_t r; CHECK(bc_lr_begin(&r, buf, n, &h) && h.type == BC_MSG_LIVE && h.seq == 7 && h.t_ms == 123456);
    /* demo flag survives */
    a.demo = true; n = bc_link_encode_live(&a, buf, sizeof buf, 8, 0); CHECK(bc_link_decode_live(buf, n, &b) && b.demo);
    /* truncated field list → rejected whole */
    CHECK(!bc_link_decode_live(buf, n - 1, &b));
    CHECK(!bc_link_decode_live(buf, 5, &b));
    /* unknown tag is skipped, wrong-length known tag is ignored */
    uint8_t m[] = { BC_MSG_LIVE, 0, 1, 0, 0, 0, 0, 0, 0x7E, 3, 1, 2, 3, 0x01, 1, 9, 0x08, 1, 2 };
    CHECK(bc_link_decode_live(m, sizeof m, &b) && !b.power_ok && b.ride_state == 2);
    /* wrong type */
    m[0] = BC_MSG_IN_GPS; CHECK(!bc_link_decode_live(m, sizeof m, &b));
    /* too small buffer */
    CHECK(bc_link_encode_live(&a, buf, 20, 1, 0) == 0);

    /* time: sane range */
    bc_in_time_t t = { .epoch_ms = 1761300000000ULL, .uncertainty_ms = 50, .tz_min = 240 }, t2;
    n = bc_link_encode_time(&t, buf, sizeof buf, 1, 0); CHECK(bc_link_decode_time(buf, n, &t2) && t2.epoch_ms == t.epoch_ms && t2.tz_min == 240);
    t.epoch_ms = 1000; n = bc_link_encode_time(&t, buf, sizeof buf, 1, 0); CHECK(!bc_link_decode_time(buf, n, &t2));

    /* GPS: needs lat/lon in range and a GPS source; speed > 108 km/h not trusted */
    bc_in_gps_t g = { .lat_e7 = 244667000, .lon_e7 = 544000000, .alt_ok = true, .alt_dm = 120, .hacc_dm = 50, .vacc_dm = 80,
                      .speed_ok = true, .speed_cms = 833, .course_ok = true, .course_cdeg = 9000, .fix_epoch_ms = 1761300000000ULL, .src = BC_SRC_PHONE_GPS }, g2;
    n = bc_link_encode_gps(&g, buf, sizeof buf, 2, 0); CHECK(n <= BC_LINK_MAX && bc_link_decode_gps(buf, n, &g2));
    CHECK(g2.lat_e7 == g.lat_e7 && g2.lon_e7 == g.lon_e7 && g2.alt_ok && g2.alt_dm == 120 && g2.speed_ok && g2.speed_cms == 833 && g2.src == BC_SRC_PHONE_GPS);
    g.src = BC_SRC_APPLE_WATCH; n = bc_link_encode_gps(&g, buf, sizeof buf, 2, 0); CHECK(!bc_link_decode_gps(buf, n, &g2));
    g.src = BC_SRC_PHONE_GPS; g.lat_e7 = 950000000; n = bc_link_encode_gps(&g, buf, sizeof buf, 2, 0); CHECK(!bc_link_decode_gps(buf, n, &g2));
    g.lat_e7 = 0; g.speed_cms = 5000; n = bc_link_encode_gps(&g, buf, sizeof buf, 2, 0); CHECK(bc_link_decode_gps(buf, n, &g2) && !g2.speed_ok);

    /* HR: 25..250 with a source */
    bc_in_hr_t hr = { .bpm = 152, .src = BC_SRC_APPLE_WATCH, .sample_epoch_ms = 1761300000000ULL, .quality = 2 }, hr2;
    n = bc_link_encode_hr(&hr, buf, sizeof buf, 3, 0); CHECK(bc_link_decode_hr(buf, n, &hr2) && hr2.bpm == 152 && hr2.src == BC_SRC_APPLE_WATCH);
    hr.bpm = 20; n = bc_link_encode_hr(&hr, buf, sizeof buf, 3, 0); CHECK(!bc_link_decode_hr(buf, n, &hr2));
    hr.bpm = 150; hr.src = BC_SRC_UNKNOWN; n = bc_link_encode_hr(&hr, buf, sizeof buf, 3, 0); CHECK(!bc_link_decode_hr(buf, n, &hr2));

    /* weather names its provider */
    bc_in_weather_t w = { .temp_ok = true, .temp_dc = 345, .wind_ok = true, .wind_cms = 400, .wind_deg = 270, .humidity = 60, .provider = BC_SRC_OPEN_METEO }, w2;
    n = bc_link_encode_weather(&w, buf, sizeof buf, 4, 0); CHECK(bc_link_decode_weather(buf, n, &w2) && w2.temp_dc == 345 && w2.provider == BC_SRC_OPEN_METEO);
    w.provider = 0; n = bc_link_encode_weather(&w, buf, sizeof buf, 4, 0); CHECK(!bc_link_decode_weather(buf, n, &w2));

    /* control: stop needs a confirmation, wrong ride id refused */
    bc_ctrl_req_t q = { .req_id = 9, .cmd = BC_CMD_STOP_REQUEST, .ride_id = 12 }, q2; uint8_t st;
    n = bc_link_encode_ctrl_req(&q, buf, sizeof buf, 5, 0); CHECK(bc_link_decode_ctrl_req(buf, n, &q2) && q2.cmd == BC_CMD_STOP_REQUEST && q2.req_id == 9);
    CHECK(bc_link_ctrl_decide(&q2, 1, 12, false, &st) == BC_ACT_ARM_STOP && st == BC_RESP_NEEDS_CONFIRM);
    q2.cmd = BC_CMD_STOP_CONFIRM; CHECK(bc_link_ctrl_decide(&q2, 1, 12, false, &st) == BC_ACT_NONE && st == BC_RESP_NEEDS_CONFIRM);
    CHECK(bc_link_ctrl_decide(&q2, 1, 12, true, &st) == BC_ACT_STOP && st == BC_RESP_OK);
    q2.ride_id = 13; CHECK(bc_link_ctrl_decide(&q2, 1, 12, true, &st) == BC_ACT_NONE && st == BC_RESP_WRONG_RIDE);
    q2.ride_id = 0; q2.cmd = BC_CMD_START; CHECK(bc_link_ctrl_decide(&q2, 0, 0, false, &st) == BC_ACT_START);
    CHECK(bc_link_ctrl_decide(&q2, 1, 12, false, &st) == BC_ACT_NONE && st == BC_RESP_BAD_STATE);
    q2.cmd = BC_CMD_PAUSE; CHECK(bc_link_ctrl_decide(&q2, 1, 12, false, &st) == BC_ACT_PAUSE);
    q2.cmd = BC_CMD_RESUME; CHECK(bc_link_ctrl_decide(&q2, 2, 12, false, &st) == BC_ACT_RESUME);
    q2.cmd = 99; CHECK(bc_link_ctrl_decide(&q2, 2, 12, false, &st) == BC_ACT_NONE && st == BC_RESP_UNKNOWN);
    bc_ctrl_resp_t rs = { .req_id = 9, .status = BC_RESP_OK, .ride_state = 1, .ride_id = 12 }, rs2;
    n = bc_link_encode_ctrl_resp(&rs, buf, sizeof buf, 6, 0); CHECK(bc_link_decode_ctrl_resp(buf, n, &rs2) && rs2.req_id == 9 && rs2.ride_id == 12);

    /* info */
    bc_info_t inf = { .ver_major = 1, .ver_minor = 0, .fw = "0.4.0", .name = "BikeComputer", .caps = BC_CAP_LIVE | BC_CAP_GPS_IN, .max_msg = BC_LINK_MAX }, inf2;
    n = bc_link_encode_info(&inf, buf, sizeof buf); CHECK(bc_link_decode_info(buf, n, &inf2) && inf2.ver_major == 1 && !strcmp(inf2.fw, "0.4.0") && !strcmp(inf2.name, "BikeComputer") && inf2.caps == (BC_CAP_LIVE | BC_CAP_GPS_IN));

    /* geo: 100 m north at Abu Dhabi latitude; identical points = 0 */
    uint32_t d = bc_geo_dist_m(244667000, 544000000, 244667000 + 8993, 544000000); CHECK(d >= 99 && d <= 101);
    CHECK(bc_geo_dist_m(244667000, 544000000, 244667000, 544000000) == 0);
    CHECK(!strcmp(bc_src_name(BC_SRC_APPLE_WATCH), "WATCH") && !strcmp(bc_src_name(0x55), "?"));
}


static void t_power(void)
{
    /* battery curve: estimate, monotonic, clamped */
    CHECK(bc_batt_pct_from_mv(0) == -1 && bc_batt_pct_from_mv(3200) == 0 && bc_batt_pct_from_mv(3300) == 0 && bc_batt_pct_from_mv(4200) == 100 && bc_batt_pct_from_mv(4300) == 100);
    CHECK(bc_batt_pct_from_mv(3800) == 50 && bc_batt_pct_from_mv(3700) == 30 && bc_batt_pct_from_mv(4100) == 90);
    for (int mv = 3300; mv < 4200; mv += 10) CHECK(bc_batt_pct_from_mv(mv + 10) >= bc_batt_pct_from_mv(mv));

    /* USB inference: 4.19 V for 30 s → likely; a drop back to 3.9 V ends it; +30 mV rise in 5 min → likely */
    bc_usb_t u; bc_usb_reset(&u);
    CHECK(!bc_usb_feed(&u, 4190, 1000));
    CHECK(!bc_usb_feed(&u, 4190, 20000));
    CHECK(bc_usb_feed(&u, 4190, 31500));
    CHECK(!bc_usb_feed(&u, 3900, 40000));                        /* clear drop: no longer likely */
    bc_usb_reset(&u);
    CHECK(!bc_usb_feed(&u, 3800, 5000)); CHECK(!bc_usb_feed(&u, 3815, 60000)); CHECK(bc_usb_feed(&u, 3835, 120000));   /* rising on the bench */
    bc_usb_reset(&u);
    for (uint32_t t = 0; t < 600000; t += 5000) CHECK(!bc_usb_feed(&u, 3800 - (int)(t / 60000), t));   /* slow discharge never looks like USB */

    /* low battery: levels rise at once, fall back only past 50 mV hysteresis */
    bc_lowbat_t l; bc_lowbat_reset(&l);
    CHECK(bc_lowbat_feed(&l, 3800) == BC_BAT_OK);
    CHECK(bc_lowbat_feed(&l, 3550) == BC_BAT_LOW);
    CHECK(bc_lowbat_feed(&l, 3580) == BC_BAT_LOW);               /* inside the band: stays */
    CHECK(bc_lowbat_feed(&l, 3601) == BC_BAT_OK);                /* above threshold + 50: clears */
    CHECK(bc_lowbat_feed(&l, 3340) == BC_BAT_CRITICAL);          /* jump straight to critical */
    CHECK(bc_lowbat_feed(&l, 3390) == BC_BAT_CRITICAL);          /* sag recovery inside the band */
    CHECK(bc_lowbat_feed(&l, 3401) == BC_BAT_VERY_LOW);
    CHECK(bc_lowbat_feed(&l, 3700) == BC_BAT_OK);
    CHECK(bc_lowbat_feed(&l, 0) == BC_BAT_OK);                   /* no reading: unchanged */
    CHECK(!strcmp(bc_bat_level_name(BC_BAT_CRITICAL), "CRITICAL"));

    /* wake taps (default 3): 3 quick taps fire once; 2 taps + late tap do not; a hold is not a tap */
    bc_tap_t t; bc_tap_reset(&t); bool fired = false;
    uint32_t ms = 1000;
    for (int i = 0; i < 3; i++) { fired |= bc_tap_feed(&t, true, ms); ms += 80; bool f = bc_tap_feed(&t, false, ms); CHECK(!f); ms += 200; f = bc_tap_feed(&t, false, ms); if (i < 2) CHECK(!f); else CHECK(f); }
    CHECK(!bc_tap_feed(&t, false, ms + 100));                    /* no second firing */
    bc_tap_reset(&t); ms = 5000;
    bc_tap_feed(&t, true, ms); bc_tap_feed(&t, false, ms + 80); bc_tap_feed(&t, true, ms + 300); bc_tap_feed(&t, false, ms + 380);
    bc_tap_feed(&t, true, ms + 1700); CHECK(!bc_tap_feed(&t, false, ms + 1780));   /* third tap too late: window restarts */
    bc_tap_feed(&t, true, ms + 1900); CHECK(!bc_tap_feed(&t, false, ms + 1980));
    bc_tap_feed(&t, true, ms + 2100); bc_tap_feed(&t, false, ms + 2180); CHECK(bc_tap_feed(&t, false, ms + 2300));    /* ...and completes with two more */
    bc_tap_reset(&t); ms = 9000;
    bc_tap_feed(&t, true, ms); bc_tap_feed(&t, false, ms + 80); bc_tap_feed(&t, true, ms + 200); bc_tap_feed(&t, false, ms + 280);
    bc_tap_feed(&t, true, ms + 400); CHECK(!bc_tap_feed(&t, false, ms + 1200));    /* long press cancels */
    CHECK(t.n == 0);
    /* single taps every 2 s for a minute: never fires */
    bc_tap_reset(&t); fired = false; for (int i = 0; i < 30; i++) { fired |= bc_tap_feed(&t, true, 20000 + i * 2000); fired |= bc_tap_feed(&t, false, 20080 + i * 2000); } CHECK(!fired);

    /* drain: 60 mV over 30 min riding, screen on → 120 mV/h; hours left from 3.80 V to 3.35 V = 3.75 h; nothing before 20 min */
    bc_drain_t d; bc_drain_reset(&d);
    int mv = 3800; uint32_t now = 0;
    for (int i = 0; i <= 360; i++) { bc_drain_feed(&d, BC_MODE_RIDE_ON, mv, now, false); if (i == 120) CHECK(bc_drain_rate_mv_h(&d, BC_MODE_RIDE_ON) == -1); now += 5000; if (i % 30 == 29) mv -= 5; }
    int r = bc_drain_rate_mv_h(&d, BC_MODE_RIDE_ON); CHECK(r >= 110 && r <= 130);
    int hl = bc_drain_hours_left_x10(&d, BC_MODE_RIDE_ON, 3800); CHECK(hl >= 34 && hl <= 41);
    CHECK(bc_drain_rate_mv_h(&d, BC_MODE_IDLE_ON) == -1 && bc_drain_hours_left_x10(&d, BC_MODE_IDLE_ON, 3800) == -1);
    /* USB samples are ignored, voltage rising never counts as drain */
    bc_drain_feed(&d, BC_MODE_RIDE_ON, 4190, now, true); now += 5000; bc_drain_feed(&d, BC_MODE_RIDE_ON, 4195, now, true);
    CHECK(bc_drain_rate_mv_h(&d, BC_MODE_RIDE_ON) == r);
    CHECK(!strcmp(bc_power_mode_name(BC_MODE_RIDE_OFF), "riding, screen off"));

    /* profile: new power keys round-trip; an old 0.4.0 profile without them takes the defaults */
    bc_profile_t p, q; bc_profile_defaults(&p);
    CHECK(p.scr_timeout_s == 60 && p.auto_sleep_min == 0 && p.bat_protect == 0 && p.wake_on_cue && p.pwr_v == 3 && p.wake_taps == 1);   /* 0.6.0: auto deep sleep off, any touch wakes */
    p.scr_timeout_s = 300; p.auto_sleep_min = 0; p.bat_protect = 1; p.wake_on_cue = false;
    char txt[1024]; CHECK(bc_profile_to_text(&p, txt, sizeof txt) > 0);
    CHECK(bc_profile_from_text(&q, txt) && q.scr_timeout_s == 300 && q.auto_sleep_min == 0 && q.bat_protect == 1 && !q.wake_on_cue);
    CHECK(bc_profile_from_text(&q, "format=bc-profile-1\nonboarded=1\nname=Rashed\nbrightness=70\n") && q.scr_timeout_s == 60 && q.auto_sleep_min == 0 && q.bat_protect == 0 && q.wake_on_cue && q.brightness == 70 && !strcmp(q.name, "Rashed"));
    /* a 0.5.0 profile (no pwr_v) carried auto_sleep_min=10: migrated to off once; a 0.6.0 profile keeps what it says */
    CHECK(bc_profile_from_text(&q, "scr_timeout_s=99999\nauto_sleep_min=999\nbat_protect=7\n") && q.scr_timeout_s == 3600 && q.auto_sleep_min == 0 && q.pwr_v == 3 && q.bat_protect == 1);
    CHECK(bc_profile_from_text(&q, "auto_sleep_min=30\npwr_v=2\n") && q.auto_sleep_min == 30);
    /* rev 3: a 0.6.0 rev-1/2 profile (pwr_v=2) with triple tap is migrated once to any touch; a rev-3 profile keeps its choice */
    CHECK(bc_profile_from_text(&q, "wake_taps=3\npwr_v=2\n") && q.wake_taps == 1 && q.pwr_v == 3);
    CHECK(bc_profile_from_text(&q, "wake_taps=3\npwr_v=3\n") && q.wake_taps == 3);
    CHECK(bc_profile_from_text(&q, "auto_sleep_min=10\n") && q.auto_sleep_min == 0);
    /* 0.6.0 shared athlete fields round-trip */
    bc_profile_defaults(&p); p.birth_year = 1990; p.rest_hr = 52; p.lthr = 170; p.units = 1; p.hours_wk = 6; p.phone_prof_ver = 7; p.phone_prof_epoch = 1792850100u; p.prof_src = 1; p.sett_ver = 3;
    CHECK(bc_profile_to_text(&p, txt, sizeof txt) > 0 && bc_profile_from_text(&q, txt) && q.birth_year == 1990 && q.rest_hr == 52 && q.lthr == 170 && q.units == 1 && q.hours_wk == 6 && q.phone_prof_ver == 7 && q.phone_prof_epoch == 1792850100u && q.prof_src == 1 && q.sett_ver == 3);
}


static void t_tap2(void)
{
    bc_tap_t t; memset(&t, 0, sizeof t); bc_tap_reset(&t); CHECK(t.need == 3);
    /* slow but valid: 300 ms presses, 800 ms gaps → 3 taps in 2.3 s fire */
    uint32_t ms = 1000; bool f = false;
    for (int i = 0; i < 3; i++) { bc_tap_feed(&t, true, ms); ms += 300; f = bc_tap_feed(&t, false, ms); ms += 800; f |= bc_tap_feed(&t, false, ms - 600); }
    CHECK(f);
    /* gaps over 900 ms never complete */
    bc_tap_reset(&t); ms = 10000; f = false;
    for (int i = 0; i < 6; i++) { bc_tap_feed(&t, true, ms); ms += 100; f |= bc_tap_feed(&t, false, ms); ms += 950; f |= bc_tap_feed(&t, false, ms - 500); }
    CHECK(!f);
    /* a slide is not a tap */
    bc_tap_reset(&t); ms = 20000;
    bc_tap_feed_xy(&t, true, 100, 100, ms); bc_tap_feed_xy(&t, true, 130, 100, ms + 40); CHECK(!bc_tap_feed_xy(&t, false, 130, 100, ms + 80));
    bc_tap_feed_xy(&t, true, 100, 100, ms + 300); bc_tap_feed_xy(&t, false, 102, 101, ms + 380);
    bc_tap_feed_xy(&t, true, 100, 100, ms + 600); CHECK(!bc_tap_feed_xy(&t, false, 100, 100, ms + 680) && t.rejected_slides == 1);
    bc_tap_feed_xy(&t, true, 100, 100, ms + 900); bc_tap_feed_xy(&t, false, 100, 100, ms + 980); CHECK(bc_tap_feed_xy(&t, false, 100, 100, ms + 1100));   /* 3 clean taps after the slide */
    /* glitches under 20 ms are ignored without breaking the sequence */
    bc_tap_reset(&t); ms = 30000;
    bc_tap_feed(&t, true, ms); bc_tap_feed(&t, false, ms + 80); bc_tap_feed(&t, true, ms + 300); bc_tap_feed(&t, false, ms + 310);   /* glitch */
    bc_tap_feed(&t, true, ms + 500); bc_tap_feed(&t, false, ms + 580); bc_tap_feed(&t, true, ms + 800); bc_tap_feed(&t, false, ms + 880); CHECK(bc_tap_feed(&t, false, ms + 1000));
    /* vibration: 10 presses in a second → nothing fires and the detector locks for a second */
    bc_tap_reset(&t); ms = 40000; f = false;
    for (int i = 0; i < 10; i++) { f |= bc_tap_feed(&t, true, ms + i * 90); f |= bc_tap_feed(&t, false, ms + i * 90 + 40); }
    f |= bc_tap_feed(&t, false, ms + 1000);
    CHECK(!f && t.rejected_bursts >= 1 && t.lockout_until_ms);
    bc_tap_feed(&t, true, ms + 1100); f = bc_tap_feed(&t, false, ms + 1180); f |= bc_tap_feed(&t, false, ms + 1300); CHECK(!f);          /* still locked */
    /* double tap mode */
    bc_tap_reset(&t); bc_tap_set_count(&t, 2); ms = 50000;
    bc_tap_feed(&t, true, ms); bc_tap_feed(&t, false, ms + 80); CHECK(!bc_tap_feed(&t, false, ms + 200)); bc_tap_feed(&t, true, ms + 300); bc_tap_feed(&t, false, ms + 380); CHECK(bc_tap_feed(&t, false, ms + 500));
    /* three human taps when two are needed: the third press fires the gesture at once (not a cancel) */
    bc_tap_reset(&t); bc_tap_set_count(&t, 2); ms = 55000;
    bc_tap_feed(&t, true, ms); bc_tap_feed(&t, false, ms + 80); bc_tap_feed(&t, true, ms + 300); bc_tap_feed(&t, false, ms + 380);
    CHECK(bc_tap_feed(&t, true, ms + 530)); bc_tap_feed(&t, false, ms + 610); CHECK(!bc_tap_feed(&t, false, ms + 800));
    /* ...but a press 40 ms after the completed gesture is bounce/vibration and cancels it */
    bc_tap_reset(&t); ms = 56000;
    bc_tap_feed(&t, true, ms); bc_tap_feed(&t, false, ms + 80); bc_tap_feed(&t, true, ms + 300); bc_tap_feed(&t, false, ms + 380);
    CHECK(!bc_tap_feed(&t, true, ms + 420)); bc_tap_feed(&t, false, ms + 460); CHECK(!bc_tap_feed(&t, false, ms + 700) && t.rejected_bursts >= 1);
    /* any touch */
    bc_tap_set_count(&t, 1); bc_tap_feed(&t, true, ms + 2000); bc_tap_feed(&t, false, ms + 2080); CHECK(bc_tap_feed(&t, false, ms + 2200));
    bc_tap_feed(&t, true, ms + 3000); bc_tap_feed(&t, false, ms + 3600); CHECK(!bc_tap_feed(&t, false, ms + 3800));   /* but a hold is still not a tap */
    bc_tap_reset(&t); CHECK(t.need == 1);                                             /* reset keeps the setting */
}

static void t_link2(void)
{
    uint8_t b[BC_LINK_MAX]; size_t n;
    /* INFO with device id (tag 07) + new caps; old decoders skip the tag */
    bc_info_t i = { .ver_major = 1, .ver_minor = 2, .fw = "0.6.0", .name = "BikeComputer", .caps = 0xFF, .max_msg = 180, .has_device_id = true, .device_id = { 0x02, 0x00, 0x00, 0xc1, 0xf7, 0x01 } };
    n = bc_link_encode_info(&i, b, sizeof b); bc_info_t j; CHECK(n && bc_link_decode_info(b, n, &j) && j.has_device_id && j.device_id[5] == 0x01 && (j.caps & BC_CAP_WIFI_PROV) && (j.caps & BC_CAP_RIDE_SYNC));
    /* SYNC_REQ: bytes identical to the Swift vector (BCLinkTests.testSyncRequestBytes) */
    bc_sync_req_t q = { .after_ride_id = 7, .max_count = 50 };
    n = bc_link_encode_sync_req(&q, b, sizeof b, 3, 1000);
    const uint8_t want_req[] = { 0x50, 0x00, 0x03, 0x00, 0xE8, 0x03, 0x00, 0x00, 0x01, 0x02, 0x07, 0x00, 0x02, 0x01, 0x32 };
    CHECK(n == sizeof want_req && !memcmp(b, want_req, n));
    bc_sync_req_t q2; CHECK(bc_link_decode_sync_req(b, n, &q2) && q2.after_ride_id == 7 && q2.max_count == 50);
    uint8_t req0[] = { 0x50, 0, 0, 0, 0, 0, 0, 0, 0x01, 0x02, 0, 0 }; CHECK(bc_link_decode_sync_req(req0, sizeof req0, &q2) && q2.after_ride_id == 0 && q2.max_count == 50);
    /* SYNC_RIDE: the Swift testSyncRideRoundTrip ride, same header + first fields byte for byte, <= 180 bytes, round trip */
    bc_ride_summary_t r; memset(&r, 0, sizeof r);
    r.id = 12; r.recovered = true; r.duration_s = 3725; r.paused_s = 60; r.avg_power = 187; r.max_power = 612; r.avg_cad = 88; r.avg_hr = -1; r.max_hr = -1;
    r.power_s = 3600; r.cad_s = 3500; r.hr_s = 0; r.zones_valid = true; uint32_t z[7] = { 600, 1800, 900, 300, 100, 20, 5 }; memcpy(r.zone_s, z, sizeof z);
    r.ftp_w = 240; r.ftp_how = 2; r.kj = 673; r.best20 = 251; r.inband_pct = 72; r.ftp_new = 238; r.ftp_suggested_only = true;
    r.distance_m = 31250; r.dist_src = 3; r.start_epoch_s = 1792850000u; snprintf(r.coach, sizeof r.coach, "Steady Z2 ride");
    n = bc_link_encode_sync_ride(&r, b, sizeof b, 9, 55);
    const uint8_t want_hdr[] = { 0x51, 0x00, 0x09, 0x00, 0x37, 0x00, 0x00, 0x00, 0x01, 0x02, 0x0C, 0x00, 0x02, 0x01, 0x02, 0x03 };
    CHECK(n > 0 && n <= 180 && !memcmp(b, want_hdr, sizeof want_hdr));
    bc_ride_summary_t d; CHECK(bc_link_decode_sync_ride(b, n, &d));
    CHECK(d.id == 12 && d.recovered && !d.demo && d.duration_s == 3725 && d.paused_s == 60 && d.avg_power == 187 && d.max_power == 612 && d.avg_cad == 88 && d.avg_hr == -1 && d.max_hr == -1);
    CHECK(d.power_s == 3600 && d.cad_s == 3500 && d.hr_s == 0 && d.zones_valid && !memcmp(d.zone_s, z, sizeof z) && d.ftp_w == 240 && d.ftp_how == 2 && d.kj == 673 && d.best20 == 251);
    CHECK(d.inband_pct == 72 && d.ftp_new == 238 && d.ftp_suggested_only && d.distance_m == 31250 && d.dist_src == 3 && d.start_epoch_s == 1792850000u && !strcmp(d.coach, "Steady Z2 ride"));
    { uint8_t ext[BC_LINK_MAX + 4]; memcpy(ext, b, n); ext[n] = 0x7E; ext[n + 1] = 1; ext[n + 2] = 0xFF; CHECK(bc_link_decode_sync_ride(ext, n + 3, &d) && d.id == 12); }   /* unknown tag skipped */
    CHECK(!bc_link_decode_sync_ride(b, n - 1, &d));                                                                                               /* truncated rejected */
    /* a ride with a 120-byte coach text and no zones still fits */
    r.zones_valid = false; memset(r.coach, 'x', 119); r.coach[119] = 0; n = bc_link_encode_sync_ride(&r, b, sizeof b, 1, 1); CHECK(n > 0 && n <= 180 && bc_link_decode_sync_ride(b, n, &d) && strlen(d.coach) == 60);
    /* 0.7.4-rc2: zones + a long coaching text used to exceed 180 B -> encoder returned 0 -> the ride was never synced */
    { bc_ride_summary_t z = r; z.zones_valid = true; for (int i = 0; i < 7; i++) z.zone_s[i] = 100u * (uint32_t)i;
      memset(z.coach, 'y', 119); z.coach[119] = 0; z.coach[40] = (char)0xC3; z.coach[41] = (char)0xA9;   /* a 2-byte UTF-8 char near the cut */
      uint8_t bb[400]; size_t m = bc_link_encode_sync_ride(&z, bb, sizeof bb, 1, 1); bc_ride_summary_t dz;
      CHECK(m > 0 && m <= BC_LINK_MAX && bc_link_decode_sync_ride(bb, m, &dz) && dz.zones_valid && strlen(dz.coach) > 0 && strlen(dz.coach) < 60);
      size_t m2 = bc_link_encode_sync_ride(&z, b, BC_LINK_MAX, 1, 1); CHECK(m2 == m && !memcmp(b, bb, m)); }
    /* SYNC_END: Swift testSyncEnd */
    bc_sync_end_t e = { .count = 50, .total = 123, .more = true }; n = bc_link_encode_sync_end(&e, b, sizeof b, 1, 0);
    const uint8_t want_end[] = { 0x52, 0, 1, 0, 0, 0, 0, 0, 0x01, 0x02, 0x32, 0x00, 0x02, 0x02, 0x7B, 0x00, 0x03, 0x01, 0x01 };
    CHECK(n == sizeof want_end && !memcmp(b, want_end, n)); bc_sync_end_t e2; CHECK(bc_link_decode_sync_end(b, n, &e2) && e2.count == 50 && e2.total == 123 && e2.more);
    CHECK(!bc_link_decode_sync_ride(b, n, &d));

    /* Wi-Fi provisioning vectors (documented in docs/BLE_LINK_PROTOCOL.md) */
    bc_wifi_scan_req_t sq = { .max = 0 }; n = bc_link_encode_wifi_scan_req(&sq, b, sizeof b, 1, 0);
    const uint8_t want_sq[] = { 0x60, 0, 1, 0, 0, 0, 0, 0 }; CHECK(n == sizeof want_sq && !memcmp(b, want_sq, n));
    bc_wifi_scan_req_t sq2; CHECK(bc_link_decode_wifi_scan_req(b, n, &sq2) && sq2.max == 16);
    sq.max = 8; n = bc_link_encode_wifi_scan_req(&sq, b, sizeof b, 2, 0); CHECK(n == 11 && b[8] == 1 && b[9] == 1 && b[10] == 8 && bc_link_decode_wifi_scan_req(b, n, &sq2) && sq2.max == 8);
    bc_wifi_scan_result_t sr = { .ssid = "Rashed\xE2\x80\x99s iPhone", .rssi = -62, .secured = 1, .channel = 6, .saved = 0 };
    n = bc_link_encode_wifi_scan_result(&sr, b, sizeof b, 5, 0);
    const uint8_t want_sr[] = { 0x61, 0, 5, 0, 0, 0, 0, 0, 0x01, 17, 'R','a','s','h','e','d',0xE2,0x80,0x99,'s',' ','i','P','h','o','n','e', 0x02, 1, 0xC2, 0x03, 1, 1, 0x04, 1, 6, 0x05, 1, 0 };
    CHECK(n == sizeof want_sr && !memcmp(b, want_sr, n));
    bc_wifi_scan_result_t sr2; CHECK(bc_link_decode_wifi_scan_result(b, n, &sr2) && !strcmp(sr2.ssid, sr.ssid) && sr2.rssi == -62 && sr2.secured && sr2.channel == 6 && !sr2.saved);
    bc_wifi_scan_end_t se = { .count = 3, .err = 0 }; n = bc_link_encode_wifi_scan_end(&se, b, sizeof b, 6, 0);
    const uint8_t want_se[] = { 0x62, 0, 6, 0, 0, 0, 0, 0, 0x01, 1, 3, 0x02, 1, 0 }; CHECK(n == sizeof want_se && !memcmp(b, want_se, n));
    bc_wifi_set_t st = { .ssid = "HomeNet", .pass = "Secret-123", .flags = 3 }; n = bc_link_encode_wifi_set(&st, b, sizeof b, 7, 0);
    const uint8_t want_set[] = { 0x63, 0, 7, 0, 0, 0, 0, 0, 0x01, 7, 'H','o','m','e','N','e','t', 0x02, 10, 'S','e','c','r','e','t','-','1','2','3', 0x03, 1, 3 };
    CHECK(n == sizeof want_set && !memcmp(b, want_set, n));
    bc_wifi_set_t st2; CHECK(bc_link_decode_wifi_set(b, n, &st2) && !strcmp(st2.ssid, "HomeNet") && !strcmp(st2.pass, "Secret-123") && st2.flags == 3);
    { uint8_t open_[] = { 0x63, 0, 0, 0, 0, 0, 0, 0, 0x01, 4, 'C','a','f','e', 0x02, 0 }; CHECK(bc_link_decode_wifi_set(open_, sizeof open_, &st2) && st2.pass[0] == 0 && st2.flags == 3); }
    { uint8_t nossid[] = { 0x63, 0, 0, 0, 0, 0, 0, 0, 0x02, 3, 'a','b','c' }; CHECK(!bc_link_decode_wifi_set(nossid, sizeof nossid, &st2)); }
    bc_wifi_forget_t fg = { .ssid = "HomeNet" }; n = bc_link_encode_wifi_forget(&fg, b, sizeof b, 8, 0);
    const uint8_t want_fg[] = { 0x64, 0, 8, 0, 0, 0, 0, 0, 0x01, 7, 'H','o','m','e','N','e','t' }; CHECK(n == sizeof want_fg && !memcmp(b, want_fg, n));
    bc_wifi_forget_t fg2; CHECK(bc_link_decode_wifi_forget(b, n, &fg2) && !strcmp(fg2.ssid, "HomeNet"));
    bc_wifi_status_msg_t ws = { .state = 4, .err = 0, .ssid = "HomeNet", .rssi = -48, .saved_count = 2, .radio_on = 1 }; n = bc_link_encode_wifi_status(&ws, b, sizeof b, 9, 0);
    const uint8_t want_ws[] = { 0x65, 0, 9, 0, 0, 0, 0, 0, 0x01, 1, 4, 0x02, 1, 0, 0x03, 7, 'H','o','m','e','N','e','t', 0x04, 1, 0xD0, 0x05, 1, 2, 0x06, 1, 1 };
    CHECK(n == sizeof want_ws && !memcmp(b, want_ws, n));
    bc_wifi_status_msg_t ws2; CHECK(bc_link_decode_wifi_status(b, n, &ws2) && ws2.state == 4 && ws2.rssi == -48 && ws2.saved_count == 2 && ws2.radio_on && !strcmp(ws2.ssid, "HomeNet"));
    n = bc_link_encode_wifi_status_req(b, sizeof b, 10, 0); const uint8_t want_wr[] = { 0x66, 0, 10, 0, 0, 0, 0, 0 }; CHECK(n == 8 && !memcmp(b, want_wr, 8));
}

static void t_link3(void)
{
    uint8_t b[BC_LINK_MAX]; size_t n;
    /* PROFILE_GET / SETTINGS_GET: header only */
    n = bc_link_encode_profile_get(b, sizeof b, 1, 0); const uint8_t want_pg[] = { 0x70, 0, 1, 0, 0, 0, 0, 0 }; CHECK(n == 8 && !memcmp(b, want_pg, 8));
    n = bc_link_encode_settings_get(b, sizeof b, 3, 0); const uint8_t want_sg[] = { 0x76, 0, 3, 0, 0, 0, 0, 0 }; CHECK(n == 8 && !memcmp(b, want_sg, 8));
    /* PROFILE_SET: full set, byte vector (docs/BLE_LINK_PROTOCOL.md) */
    bc_profile_msg_t pm = { .version = 1, .updated_epoch_s = 1792850100u, .ftp_w = 250, .ftp_how = 1, .weight_kg_x10 = 780, .birth_year = 1990, .max_hr = 186, .rest_hr = 52, .units = 0, .hours_per_week = 6, .level = 2, .goal = 1, .lthr = 170 };
    snprintf(pm.name, sizeof pm.name, "Rashed"); pm.has = 0; for (int t = 2; t <= 0x0E; t++) pm.has |= BC_PF_HAS(t);
    n = bc_link_encode_profile(BC_MSG_PROFILE_SET, &pm, b, sizeof b, 2, 0);
    const uint8_t want_ps[] = { 0x71, 0, 2, 0, 0, 0, 0, 0,  0x01, 4, 1, 0, 0, 0,  0x02, 4, 0xB4, 0xB8, 0xDC, 0x6A,  0x03, 6, 'R','a','s','h','e','d',
                                0x04, 2, 0xFA, 0x00,  0x05, 1, 1,  0x06, 2, 0x0C, 0x03,  0x07, 2, 0xC6, 0x07,  0x08, 1, 186,  0x09, 1, 52,  0x0A, 1, 0,  0x0B, 1, 6,  0x0C, 1, 2,  0x0D, 1, 1,  0x0E, 1, 170 };
    CHECK(n == sizeof want_ps && !memcmp(b, want_ps, n));
    bc_profile_msg_t d; CHECK(bc_link_decode_profile(b, n, &d) && d.version == 1 && d.updated_epoch_s == 1792850100u && !strcmp(d.name, "Rashed") && d.ftp_w == 250 && d.ftp_how == 1 && d.weight_kg_x10 == 780 && d.birth_year == 1990 && d.max_hr == 186 && d.rest_hr == 52 && d.units == 0 && d.hours_per_week == 6 && d.level == 2 && d.goal == 1 && d.lthr == 170 && d.has == pm.has);
    /* partial SET: only the fields sent are flagged; 0.7.0: an out-of-range value is not applied AND is flagged in `invalid`
       (the board then answers status 2 and changes nothing) */
    uint8_t part[] = { 0x71, 0, 0, 0, 0, 0, 0, 0,  0x01, 4, 5, 0, 0, 0,  0x04, 2, 0xFF, 0xFF,  0x08, 1, 186 };
    CHECK(bc_link_decode_profile(part, sizeof part, &d) && d.version == 5 && d.has == BC_PF_HAS(0x08) && d.max_hr == 186 && !(d.has & BC_PF_HAS(0x04)) && d.invalid == BC_PF_HAS(0x04));
    uint8_t bad_rest[] = { 0x71, 0, 0, 0, 0, 0, 0, 0,  0x01, 4, 6, 0, 0, 0,  0x08, 1, 150,  0x09, 1, 160 };
    CHECK(bc_link_decode_profile(bad_rest, sizeof bad_rest, &d) && d.has == BC_PF_HAS(0x08) && d.invalid == BC_PF_HAS(0x09));
    CHECK(bc_link_decode_profile(b, n, &d) && d.invalid == 0);   /* the full valid set: nothing invalid */
    /* 0.7.0 LINK_DIAG event vector (docs/BLE_LINK_PROTOCOL.md 1.2.1) */
    { bc_event_t ev = { .event_id = BC_EVT_LINK_DIAG, .pct_est = 3, .mv = 1, .stage = 1 };
      static const uint8_t want_ld[] = { 0x40, 0x00, 0x03, 0x00, 0xF4, 0x01, 0x00, 0x00, 0x01, 0x01, 0x20, 0x02, 0x01, 0x03, 0x03, 0x02, 0x01, 0x00, 0x04, 0x01, 0x01 };
      size_t ln = bc_link_encode_event(&ev, b, sizeof b, 3, 500); bc_event_t ed;
      CHECK(ln == sizeof want_ld && memcmp(b, want_ld, ln) == 0 && bc_link_decode_event(b, ln, &ed) && ed.event_id == 0x20 && ed.pct_est == 3 && ed.mv == 1 && ed.stage == 1); }
    uint8_t nover[] = { 0x71, 0, 0, 0, 0, 0, 0, 0, 0x08, 1, 186 }; CHECK(!bc_link_decode_profile(nover, sizeof nover, &d));
    /* PROFILE (board -> phone) carries 0F source and 10 board_saved_epoch_s */
    pm.source = 1; pm.board_saved_epoch_s = 1792850100u; n = bc_link_encode_profile(BC_MSG_PROFILE, &pm, b, sizeof b, 2, 0);
    CHECK(n == sizeof want_ps + 9 && b[0] == 0x72 && b[n - 9] == 0x0F && b[n - 8] == 1 && b[n - 7] == 1 && b[n - 6] == 0x10 && b[n - 5] == 4 && bc_link_decode_profile(b, n, &d) && d.source == 1 && d.board_saved_epoch_s == 1792850100u);
    CHECK(bc_link_encode_profile(BC_MSG_PROFILE_ACK, &pm, b, sizeof b, 1, 0) == 0);
    /* PROFILE_ACK */
    bc_profile_ack_t a = { .version = 1, .status = 0, .board_version = 1 }; n = bc_link_encode_profile_ack(&a, b, sizeof b, 2, 0);
    const uint8_t want_pa[] = { 0x73, 0, 2, 0, 0, 0, 0, 0,  0x01, 4, 1, 0, 0, 0,  0x02, 1, 0,  0x03, 4, 1, 0, 0, 0 }; CHECK(n == sizeof want_pa && !memcmp(b, want_pa, n));
    bc_profile_ack_t a2; CHECK(bc_link_decode_profile_ack(b, n, &a2) && a2.version == 1 && a2.status == 0 && a2.board_version == 1);
    /* SETTINGS_SET vector */
    bc_settings_msg_t sm = { .version = 1, .brightness_pct = 55, .screen_timeout_s = 120, .wake_gesture = 1, .has = BC_PF_HAS(2) | BC_PF_HAS(3) | BC_PF_HAS(4) };
    n = bc_link_encode_settings(BC_MSG_SETTINGS_SET, &sm, b, sizeof b, 4, 0);
    const uint8_t want_ss[] = { 0x74, 0, 4, 0, 0, 0, 0, 0,  0x01, 4, 1, 0, 0, 0,  0x02, 1, 55,  0x03, 2, 120, 0,  0x04, 1, 1 }; CHECK(n == sizeof want_ss && !memcmp(b, want_ss, n));
    bc_settings_msg_t s2; CHECK(bc_link_decode_settings(b, n, &s2) && s2.version == 1 && s2.has == sm.has && s2.brightness_pct == 55 && s2.screen_timeout_s == 120 && s2.wake_gesture == 1);
    /* SETTINGS reply: all tags + 0F status + 10 supported mask */
    bc_settings_msg_t full = { .version = 2, .brightness_pct = 80, .screen_timeout_s = 60, .wake_gesture = 0, .phone_link_enabled = 1, .hr_pref = 0, .auto_sleep_min = 0, .ride_layout = 0, .wake_on_cue = 1, .units = 0, .status = 0, .supported_mask = BC_SETTINGS_SUPPORTED_ALL };
    full.has = 0; for (int t = 2; t <= 0x10; t++) full.has |= BC_PF_HAS(t);
    n = bc_link_encode_settings(BC_MSG_SETTINGS, &full, b, sizeof b, 5, 0);
    const uint8_t want_sr[] = { 0x75, 0, 5, 0, 0, 0, 0, 0,  0x01, 4, 2, 0, 0, 0,  0x02, 1, 80,  0x03, 2, 60, 0,  0x04, 1, 0,  0x05, 1, 1,  0x06, 1, 0,  0x07, 2, 0, 0,  0x08, 1, 0,  0x09, 1, 1,  0x0A, 1, 0,  0x0F, 1, 0,  0x10, 4, 0xFF, 0x03, 0, 0 };
    CHECK(n == sizeof want_sr && !memcmp(b, want_sr, n));
    CHECK(bc_link_decode_settings(b, n, &s2) && s2.supported_mask == BC_SETTINGS_SUPPORTED_ALL && s2.status == 0 && s2.phone_link_enabled == 1);
    /* bad values are dropped, not applied: brightness 5 (< 10), gesture 7 */
    uint8_t bad[] = { 0x74, 0, 0, 0, 0, 0, 0, 0,  0x01, 4, 9, 0, 0, 0,  0x02, 1, 5,  0x04, 1, 7,  0x06, 1, 1 };
    CHECK(bc_link_decode_settings(bad, sizeof bad, &s2) && s2.version == 9 && s2.has == BC_PF_HAS(6) && s2.hr_pref == 1);
}


/* 0.6.0: BLE speed/cadence sensor (CSC 0x2A5B) and the battery-notice EVENT codec */
#include "bc_csc.h"
static void csc_pkt(uint8_t *b, bool wheel, uint32_t wr, uint16_t wt, bool crank, uint16_t cr, uint16_t ct, size_t *n)
{
    size_t i = 0; b[i++] = (uint8_t)((wheel ? 1 : 0) | (crank ? 2 : 0));
    if (wheel) { b[i++] = (uint8_t)wr; b[i++] = (uint8_t)(wr >> 8); b[i++] = (uint8_t)(wr >> 16); b[i++] = (uint8_t)(wr >> 24); b[i++] = (uint8_t)wt; b[i++] = (uint8_t)(wt >> 8); }
    if (crank) { b[i++] = (uint8_t)cr; b[i++] = (uint8_t)(cr >> 8); b[i++] = (uint8_t)ct; b[i++] = (uint8_t)(ct >> 8); }
    *n = i;
}
static void t_csc(void)
{
    bc_csc_meas_t m; uint8_t b[16]; size_t n;
    csc_pkt(b, true, 1000, 2048, true, 50, 1024, &n); CHECK(n == 11 && bc_csc_decode(b, n, &m) && m.wheel_ok && m.crank_ok && m.wheel_revs == 1000 && m.wheel_t == 2048 && m.crank_revs == 50 && m.crank_t == 1024);
    CHECK(!bc_csc_decode(b, 5, &m));                                 /* truncated wheel block */
    uint8_t none[1] = { 0 }; CHECK(!bc_csc_decode(none, 1, &m));     /* flags without data */
    bc_csc_live_t l; bc_csc_live_reset(&l);
    int rpm = -1, sp = -1;
    /* crank: 1 rev per 0.667 s (683/1024 s) = 90 rpm */
    csc_pkt(b, false, 0, 0, true, 100, 10000, &n); CHECK(bc_csc_live_feed(&l, b, n, 1000));
    CHECK(bc_csc_live_cadence(&l, 1000, &rpm) == BC_LIVE_NO_DATA);   /* one packet: no rate yet (nothing extrapolated) */
    csc_pkt(b, false, 0, 0, true, 101, 10683, &n); CHECK(bc_csc_live_feed(&l, b, n, 1700));
    CHECK(bc_csc_live_cadence(&l, 1800, &rpm) == BC_LIVE_OK && rpm == 90);
    CHECK(bc_csc_live_speed(&l, 1800, 2096, &sp) == BC_LIVE_NO_DATA);   /* crank-only sensor: no speed */
    /* same event time repeated = stopped pedalling: after 3 s the cadence reads 0, after 4 s without packets NO DATA */
    csc_pkt(b, false, 0, 0, true, 101, 10683, &n); bc_csc_live_feed(&l, b, n, 2700);
    CHECK(bc_csc_live_cadence(&l, 2800, &rpm) == BC_LIVE_OK && rpm == 90);
    csc_pkt(b, false, 0, 0, true, 101, 10683, &n); bc_csc_live_feed(&l, b, n, 4900);
    CHECK(bc_csc_live_cadence(&l, 5000, &rpm) == BC_LIVE_OK && rpm == 0);
    CHECK(bc_csc_live_cadence(&l, 9500, &rpm) == BC_LIVE_NO_DATA);
    /* wheel: 4 revs in 1.0 s (1024 ticks), 2096 mm -> 8.384 m/s = 30.18 km/h; 16-bit event time wraps */
    bc_csc_live_reset(&l);
    csc_pkt(b, true, 5000, 65000, false, 0, 0, &n); bc_csc_live_feed(&l, b, n, 1000);
    csc_pkt(b, true, 5004, (uint16_t)(65000 + 1024), false, 0, 0, &n); bc_csc_live_feed(&l, b, n, 2000);
    CHECK(bc_csc_live_speed(&l, 2100, 2096, &sp) == BC_LIVE_OK && sp >= 300 && sp <= 303);
    CHECK(bc_csc_live_speed(&l, 2100, 100, &sp) == BC_LIVE_NO_DATA);     /* absurd circumference refused */
    CHECK(bc_csc_live_cadence(&l, 2100, &rpm) == BC_LIVE_NO_DATA);        /* wheel-only: no cadence */
    CHECK(l.wheel_total == 4);
    /* event codec */
    bc_event_t e = { .event_id = BC_EVT_BATTERY_NOTICE, .pct_est = 81, .mv = 3990, .stage = 1 }, d;
    uint8_t eb[32]; size_t en = bc_link_encode_event(&e, eb, sizeof eb, 7, 123456);
    static const uint8_t want[] = { 0x40, 0x00, 0x07, 0x00, 0x40, 0xE2, 0x01, 0x00, 0x01, 0x01, 0x10, 0x02, 0x01, 0x51, 0x03, 0x02, 0x96, 0x0F, 0x04, 0x01, 0x01 };
    CHECK(en == sizeof want && !memcmp(eb, want, en));
    CHECK(bc_link_decode_event(eb, en, &d) && d.event_id == BC_EVT_BATTERY_NOTICE && d.pct_est == 81 && d.mv == 3990 && d.stage == 1);
    /* a profile with the new keys round-trips and old profiles take the defaults */
    bc_profile_t p; bc_profile_defaults(&p); CHECK(p.wheel_mm == 2096 && p.chg_notice == 0 && !p.csc.paired);
    p.csc.paired = true; memcpy(p.csc.mac, "\x01\x02\x03\x04\x05\x06", 6); p.csc.addr_type = 1; snprintf(p.csc.name, sizeof p.csc.name, "CSC-Wahoo"); p.wheel_mm = 2136;
    char txt[1024]; CHECK(bc_profile_to_text(&p, txt, sizeof txt) > 0);
    bc_profile_t q; bc_profile_defaults(&q); CHECK(bc_profile_from_text(&q, txt) && q.csc.paired && q.csc.mac[5] == 6 && !strcmp(q.csc.name, "CSC-Wahoo") && q.wheel_mm == 2136);
    bc_profile_t r; bc_profile_defaults(&r); CHECK(bc_profile_from_text(&r, "format=bc-profile-1\nname=Old\n") && r.wheel_mm == 2096 && !r.csc.paired);
}


/* rev 3: wake gate (swallow + guard) and hold-to-confirm, with timing vectors */
static void t_gate_hold(void)
{
    bc_gate_t g; bc_gate_reset(&g);
    CHECK(bc_gate_feed(&g, true, 100) && bc_gate_feed(&g, false, 200));          /* screen on: everything passes */
    bc_gate_screen_off(&g);
    CHECK(!bc_gate_feed(&g, true, 1000) && !bc_gate_feed(&g, true, 1050) && !bc_gate_feed(&g, false, 1100) && g.swallowed == 1);   /* dark: nothing passes */
    /* any-touch wake: finger lands at 2000, wake decided, swallowed until the release at 3500 (even a long press) */
    bc_gate_wake(&g, true, 2000);
    for (uint32_t t = 2000; t < 3500; t += 15) CHECK(!bc_gate_feed(&g, true, t));
    CHECK(!bc_gate_feed(&g, false, 3500) && g.st == BC_GATE_GUARD && g.guard_until_ms == 3500 + BC_GATE_GUARD_MS);
    /* guard: a tap inside it is dropped */
    CHECK(!bc_gate_feed(&g, true, 3600) && !bc_gate_feed(&g, false, 3700) && g.guarded == 1);
    /* a finger that lands in the guard and stays past its end keeps being swallowed until it lifts */
    CHECK(!bc_gate_feed(&g, true, 3850) && !bc_gate_feed(&g, true, 3950) && g.st == BC_GATE_SWALLOW && !bc_gate_feed(&g, true, 4100));
    CHECK(!bc_gate_feed(&g, false, 4200) && g.st == BC_GATE_GUARD);
    CHECK(!bc_gate_feed(&g, false, 4300));
    CHECK(bc_gate_feed(&g, false, 4200 + BC_GATE_GUARD_MS) && g.st == BC_GATE_PASS);  /* quiet guard over: open */
    CHECK(bc_gate_feed(&g, true, 4700) && bc_gate_feed(&g, false, 4800));               /* normal touches pass again */
    /* wake decided on a release (2/3 taps): straight to the guard */
    bc_gate_screen_off(&g); bc_gate_wake(&g, false, 9000);
    CHECK(g.st == BC_GATE_GUARD && !bc_gate_feed(&g, true, 9100) && !bc_gate_feed(&g, false, 9200) && bc_gate_feed(&g, false, 9400));

    /* 0.6.1 regression (the "Home frozen" bug): on the device the controller is read ONLY on its interrupt, i.e. while a finger
       is down plus one release report. No idle "released" feeds exist, so the guard must open by itself (tick) and a NEW press
       seen after an expired guard must pass. Replay exactly the device sequence of 0.6.0 rev 3: screen off -> wake touch ->
       release -> (silence) -> next tap. */
    bc_gate_t e; bc_gate_reset(&e);
    bc_gate_screen_off(&e);
    CHECK(!bc_gate_feed(&e, true, 10000)); bc_gate_wake(&e, true, 10000);                 /* wake touch, swallowed */
    CHECK(!bc_gate_feed(&e, true, 10030) && !bc_gate_feed(&e, false, 10200) && e.st == BC_GATE_GUARD);   /* release -> guard */
    CHECK(bc_gate_feed(&e, true, 11000) && e.st == BC_GATE_PASS);                          /* first read after a quiet guard IS the next press: must pass */
    CHECK(bc_gate_feed(&e, false, 11100) && bc_gate_feed(&e, true, 11200));
    /* same, but the periodic tick opens the guard before the next press */
    bc_gate_screen_off(&e); bc_gate_wake(&e, true, 20000); CHECK(!bc_gate_feed(&e, false, 20100) && e.st == BC_GATE_GUARD);
    CHECK(!bc_gate_tick(&e, 20300) && e.st == BC_GATE_GUARD);
    CHECK(bc_gate_tick(&e, 20600) && e.st == BC_GATE_PASS && bc_gate_feed(&e, true, 20700));
    /* a finger that landed during the guard and is still down at its end is swallowed to its release (unchanged rule) */
    bc_gate_screen_off(&e); bc_gate_wake(&e, false, 30000);
    CHECK(!bc_gate_feed(&e, true, 30100) && e.guarded == 1 && !bc_gate_feed(&e, true, 30500) && e.st == BC_GATE_SWALLOW);
    CHECK(!bc_gate_feed(&e, false, 30600) && e.st == BC_GATE_GUARD && !bc_gate_tick(&e, 30700) && bc_gate_tick(&e, 31000) && e.st == BC_GATE_PASS);
    /* watchdog: a swallow whose release is never reported is abandoned after BC_GATE_WATCHDOG_MS (tick or next feed) */
    bc_gate_screen_off(&e); bc_gate_wake(&e, true, 40000);
    CHECK(!bc_gate_tick(&e, 41000) && e.st == BC_GATE_SWALLOW);
    CHECK(bc_gate_tick(&e, 40000 + BC_GATE_WATCHDOG_MS) && e.st == BC_GATE_GUARD && e.watchdog_resets == 1 && !e.down);
    CHECK(bc_gate_tick(&e, 40000 + BC_GATE_WATCHDOG_MS + BC_GATE_GUARD_MS) && e.st == BC_GATE_PASS);
    bc_gate_screen_off(&e); bc_gate_wake(&e, true, 50000);
    CHECK(!bc_gate_feed(&e, true, 50000 + BC_GATE_WATCHDOG_MS) && e.st == BC_GATE_GUARD && e.watchdog_resets == 2);   /* long press: swallow ends, guard, release opens */
    CHECK(!bc_gate_feed(&e, false, 50000 + BC_GATE_WATCHDOG_MS + 100) && bc_gate_tick(&e, 50000 + BC_GATE_WATCHDOG_MS + BC_GATE_GUARD_MS + 1) && e.st == BC_GATE_PASS);
    CHECK(!strcmp(bc_gate_state_name(BC_GATE_SWALLOW), "swallow"));
    /* a finger the driver keeps reporting (active polling while the gate blocks) is swallowed for as long as it stays, with no
       watchdog: resting a finger on START RIDE through the wake must never turn into a hold-to-start */
    bc_gate_screen_off(&e); bc_gate_wake(&e, true, 60000);
    for (uint32_t t = 60050; t <= 64000; t += 50) CHECK(!bc_gate_feed(&e, true, t) && e.st == BC_GATE_SWALLOW);
    CHECK(e.watchdog_resets == 2 && !bc_gate_tick(&e, 64020));
    CHECK(!bc_gate_feed(&e, false, 64100) && e.st == BC_GATE_GUARD && bc_gate_tick(&e, 64600) && e.st == BC_GATE_PASS);

    /* hold-to-confirm: 1000 ms */
    bc_hold_t h; bc_hold_init(&h, 1000);
    CHECK(bc_hold_feed(&h, true, 100, 100, 0) == BC_HOLD_HOLDING);
    CHECK(bc_hold_feed(&h, true, 100, 100, 500) == BC_HOLD_HOLDING && h.progress == 50);
    CHECK(bc_hold_feed(&h, false, 100, 100, 600) == BC_HOLD_CANCELLED && h.cancels_release == 1 && h.progress == 0);   /* early release */
    CHECK(bc_hold_feed(&h, true, 100, 100, 1000) == BC_HOLD_HOLDING);
    CHECK(bc_hold_feed(&h, true, 100, 125, 1300) == BC_HOLD_CANCELLED && h.cancels_slide == 1);                      /* slid 25 px */
    CHECK(bc_hold_feed(&h, true, 100, 130, 1400) == BC_HOLD_IDLE);                                                   /* stays cancelled while down */
    CHECK(bc_hold_feed(&h, false, 100, 130, 1500) == BC_HOLD_IDLE);
    CHECK(bc_hold_feed(&h, true, 50, 50, 2000) == BC_HOLD_HOLDING);
    CHECK(bc_hold_feed(&h, true, 60, 55, 2990) == BC_HOLD_HOLDING && h.progress == 99);                               /* 10/5 px jitter is fine */
    CHECK(bc_hold_feed(&h, true, 60, 55, 3000) == BC_HOLD_FIRED && h.fires == 1 && h.progress == 100);
    CHECK(bc_hold_feed(&h, true, 60, 55, 3500) == BC_HOLD_IDLE);                                                      /* never fires twice while held */
    CHECK(bc_hold_feed(&h, false, 60, 55, 3600) == BC_HOLD_IDLE);
    CHECK(bc_hold_feed(&h, true, 60, 55, 3700) == BC_HOLD_IDLE && h.ignored_cooldown == 1);                          /* bounce / duplicate inside the cool-down */
    CHECK(bc_hold_feed(&h, true, 60, 55, 4900) == BC_HOLD_IDLE && bc_hold_feed(&h, false, 60, 55, 5000) == BC_HOLD_IDLE && h.fires == 1);
    CHECK(bc_hold_feed(&h, true, 60, 55, 5200) == BC_HOLD_HOLDING);                                                   /* after the cool-down: a new hold */
    CHECK(bc_hold_feed(&h, true, 60, 55, 6200) == BC_HOLD_FIRED && h.fires == 2);
    /* a position-less feed (-1) never counts as a slide */
    bc_hold_init(&h, 1000); CHECK(bc_hold_feed(&h, true, -1, -1, 0) == BC_HOLD_HOLDING && bc_hold_feed(&h, true, -1, -1, 1000) == BC_HOLD_FIRED);
}

int main(void)
{
    t_gate_hold(); t_csc(); t_tap2(); t_link2(); t_link3(); t_hr(); t_profile(); t_ride(); t_auto_ftp(); t_coach(); t_demo(); t_wifi(); t_link(); t_power();
    printf("%d checks, %d failures\n", checks, fails);
    return fails ? 1 : 0;
}
