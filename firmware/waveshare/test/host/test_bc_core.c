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

    /* triple tap: 3 quick taps fire once; 2 taps + late tap do not; a hold is not a tap */
    bc_tap_t t; bc_tap_reset(&t); bool fired = false;
    uint32_t ms = 1000;
    for (int i = 0; i < 3; i++) { fired |= bc_tap_feed(&t, true, ms); ms += 80; bool f = bc_tap_feed(&t, false, ms); ms += 200; if (i < 2) CHECK(!f); else CHECK(f); }
    CHECK(!bc_tap_feed(&t, false, ms + 100));                    /* no second firing */
    bc_tap_reset(&t); ms = 5000;
    bc_tap_feed(&t, true, ms); bc_tap_feed(&t, false, ms + 80); bc_tap_feed(&t, true, ms + 300); bc_tap_feed(&t, false, ms + 380);
    bc_tap_feed(&t, true, ms + 1700); CHECK(!bc_tap_feed(&t, false, ms + 1780));   /* third tap too late: window restarts */
    bc_tap_feed(&t, true, ms + 1900); CHECK(!bc_tap_feed(&t, false, ms + 1980));
    bc_tap_feed(&t, true, ms + 2100); CHECK(bc_tap_feed(&t, false, ms + 2180));    /* ...and completes with two more */
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
    CHECK(p.scr_timeout_s == 60 && p.auto_sleep_min == 10 && p.bat_protect == 0 && p.wake_on_cue);
    p.scr_timeout_s = 300; p.auto_sleep_min = 0; p.bat_protect = 1; p.wake_on_cue = false;
    char txt[1024]; CHECK(bc_profile_to_text(&p, txt, sizeof txt) > 0);
    CHECK(bc_profile_from_text(&q, txt) && q.scr_timeout_s == 300 && q.auto_sleep_min == 0 && q.bat_protect == 1 && !q.wake_on_cue);
    CHECK(bc_profile_from_text(&q, "format=bc-profile-1\nonboarded=1\nname=Rashed\nbrightness=70\n") && q.scr_timeout_s == 60 && q.auto_sleep_min == 10 && q.bat_protect == 0 && q.wake_on_cue && q.brightness == 70 && !strcmp(q.name, "Rashed"));
    CHECK(bc_profile_from_text(&q, "scr_timeout_s=99999\nauto_sleep_min=999\nbat_protect=7\n") && q.scr_timeout_s == 3600 && q.auto_sleep_min == 240 && q.bat_protect == 1);
}

int main(void)
{
    t_hr(); t_profile(); t_ride(); t_auto_ftp(); t_coach(); t_demo(); t_wifi(); t_link(); t_power();
    printf("%d checks, %d failures\n", checks, fails);
    return fails ? 1 : 0;
}
