/* Link 1.3 (BLE_CONTRACT.md v1.1) codec + coach mirroring: every new message, byte vectors, rejection rules, plan
 * reassembly, seq rule, offline follow, HR honesty, coach card, storage clean rule. Host test (ASan + UBSan). */
#include "bc_link13.h"
#include "bc_cmirror.h"
#include "bc_diag.h"
#include <stdio.h>
#include <string.h>

static int checks, fails;
#define CHECK(c, ...) do { checks++; if (!(c)) { fails++; printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static void hello_tests(void)
{
    uint8_t b[BC_LINK_MAX]; size_t n;
    bc_hello_t h = { .major = 1, .minor = 3, .app_caps = BC_CAPS_LINK13 }; snprintf(h.app_version, sizeof h.app_version, "1.0 (42)");
    n = bc_link_encode_hello(&h, b, sizeof b, 1, 0);
    const uint8_t want[] = { 0x08, 0, 1, 0, 0, 0, 0, 0, 0x01, 1, 1, 0x02, 1, 3, 0x03, 4, 0x00, 0xF8, 0, 0, 0x04, 8, '1', '.', '0', ' ', '(', '4', '2', ')' };
    CHECK(n == sizeof want && !memcmp(b, want, n), "APP_HELLO vector (%zu B)", n);
    bc_hello_t d; CHECK(bc_link_decode_hello(b, n, &d) && d.major == 1 && d.minor == 3 && d.app_caps == BC_CAPS_LINK13 && !strcmp(d.app_version, "1.0 (42)"), "APP_HELLO round trip");
    CHECK(!bc_link_decode_hello(b, 11, &d), "truncated HELLO rejected");
    { uint8_t m[] = { 0x08, 0, 1, 0, 0, 0, 0, 0, 0x01, 1, 1 }; CHECK(!bc_link_decode_hello(m, sizeof m, &d), "HELLO without app_caps rejected"); }
    bc_hello_ack_t a = { BC_CAPS_BOARD & BC_CAP_COACH }; n = bc_link_encode_hello_ack(&a, b, sizeof b, 2, 0);
    const uint8_t wa[] = { 0x09, 0, 2, 0, 0, 0, 0, 0, 0x01, 4, 0x00, 0x10, 0, 0 };
    CHECK(n == sizeof wa && !memcmp(b, wa, n), "HELLO_ACK vector");
    bc_hello_ack_t da; CHECK(bc_link_decode_hello_ack(b, n, &da) && da.enabled_caps == BC_CAP_COACH, "HELLO_ACK round trip");
    CHECK((BC_CAPS_BOARD & 0x07FF) == 0x07FF && (BC_CAPS_BOARD & BC_CAPS_LINK13) == 0xF800, "INFO caps: 1.2.3 caps unchanged + 0xF800");
}

static bc_cseg_t seg(uint16_t d, uint8_t t, uint8_t k, uint16_t lo, uint16_t hi, uint8_t cl, uint8_t ch) { bc_cseg_t s = { d, t, k, lo, hi, cl, ch }; return s; }

static void plan_tests(void)
{
    uint8_t b[BC_LINK_MAX]; size_t n;
    /* a 20-segment plan: part 0 (9 segments) + part 1 (11 segments) */
    bc_cseg_t all[20];
    all[0] = seg(600, BC_WT_WARMUP, BC_TK_POWER, 100, 140, 80, 90);
    for (int i = 1; i < 19; i++) all[i] = (i % 2) ? seg(300, BC_WT_THRESHOLD, BC_TK_POWER, 230, 250, 85, 95) : seg(180, BC_WT_RECOVERY, BC_TK_POWER, 100, 130, 0, 0);
    all[19] = seg(BC_COACH_OPEN_ENDED, BC_WT_COOLDOWN, BC_TK_HR, 100, 125, 0, 0);
    uint32_t crc = bc_cm_plan_crc(all, 20);
    bc_coach_plan_msg_t p0 = { .workout_id = 77, .part = 0, .parts = 2, .first_segment = 0, .nseg = 9, .head = true, .total_segments = 20,
                               .total_duration_s = 600 + 9 * 300 + 9 * 180 + 65535, .plan_crc32 = crc, .t0_elapsed_s = BC_COACH_T0_RIDE_START };
    memcpy(p0.name, "Threshold 9x5 longnm", 21);      /* 20 B: the maximum */
    memcpy(p0.seg, all, sizeof all[0] * 9);
    n = bc_link_encode_coach_plan(&p0, b, sizeof b, 3, 0);
    CHECK(n > 0 && n <= BC_LINK_MAX, "COACH_PLAN part 0 with 9 segments + 20-byte name fits (%zu B)", n);
    CHECK(n == 162, "part 0 size = 162 B as in the iOS review (%zu)", n);
    bc_coach_plan_msg_t d; CHECK(bc_link_decode_coach_plan(b, n, &d) && d.workout_id == 77 && d.nseg == 9 && d.head && strlen(d.name) == 20 && d.plan_crc32 == crc
                                 && d.seg[0].dur_s == 600 && d.seg[0].cad_hi == 90 && d.seg[8].lo == 100 && d.seg[1].lo == 230, "COACH_PLAN round trip");
    { uint8_t bad[BC_LINK_MAX]; memcpy(bad, b, n); /* segment bytes 9 x 10 -> length 89: not a multiple of 10 */
      for (size_t i = 8; i < n; i += 2 + bad[i + 1]) if (bad[i] == 0x05) { bad[i + 1] = 89; break; }
      bc_coach_plan_msg_t x; CHECK(!bc_link_decode_coach_plan(bad, n - 1, &x), "segment list not n x 10 bytes rejected"); }
    bc_coach_plan_msg_t p1 = { .workout_id = 77, .part = 1, .parts = 2, .first_segment = 9, .nseg = 11 };
    memcpy(p1.seg, all + 9, sizeof all[0] * 11);
    uint8_t b1[BC_LINK_MAX]; size_t n1 = bc_link_encode_coach_plan(&p1, b1, sizeof b1, 4, 0);
    CHECK(n1 > 0 && n1 <= BC_LINK_MAX, "part 1 with 11 segments fits (%zu B)", n1);
    { bc_coach_plan_msg_t p15 = p1; p15.nseg = 15; CHECK(bc_link_encode_coach_plan(&p15, b, sizeof b, 1, 0) > 0, "encoder caps a part at 14 segments"); }
    bc_coach_plan_ack_t a = { 77, BC_PLAN_COMPLETE, 2 }; n = bc_link_encode_coach_plan_ack(&a, b, sizeof b, 5, 0);
    bc_coach_plan_ack_t da; CHECK(bc_link_decode_coach_plan_ack(b, n, &da) && da.workout_id == 77 && da.status == 0 && da.next_part == 2 && n == 8 + 6 + 3 + 4, "PLAN_ACK");

    /* reassembly */
    static bc_cmirror_t m; bc_cm_init(&m); uint16_t next = 0;
    bc_coach_plan_msg_t q0, q1; bc_link_decode_coach_plan(b1, n1, &q1);
    n = bc_link_encode_coach_plan(&p0, b, sizeof b, 3, 0); bc_link_decode_coach_plan(b, n, &q0);
    CHECK(bc_cm_plan_part(&m, &q1, &next) == BC_PLAN_CRC && next == 0, "part 1 before part 0: send again from 0");
    CHECK(bc_cm_plan_part(&m, &q0, &next) == BC_PLAN_PART_OK && next == 1 && !m.plan_ok, "part 0: waiting for part 1");
    CHECK(bc_cm_plan_part(&m, &q0, &next) == BC_PLAN_PART_OK && next == 1, "part 0 again restarts cleanly");
    CHECK(bc_cm_plan_part(&m, &q1, &next) == BC_PLAN_COMPLETE && next == 2 && m.plan_ok && m.nseg == 20 && m.plan_id == 77, "part 1: complete, CRC OK, stored");
    /* CRC mismatch */
    bc_coach_plan_msg_t w0 = q0; w0.workout_id = 78; w0.plan_crc32 ^= 1; bc_coach_plan_msg_t w1 = q1; w1.workout_id = 78;
    bc_cm_plan_part(&m, &w0, &next);
    CHECK(bc_cm_plan_part(&m, &w1, &next) == BC_PLAN_CRC && m.plan_ok && m.plan_id == 77, "CRC mismatch: status 3, the stored plan is kept");
    /* too many */
    bc_coach_plan_msg_t big = q0; big.total_segments = 65; CHECK(bc_cm_plan_part(&m, &big, &next) == BC_PLAN_TOO_MANY, "65 segments: status 2");
    /* open-ended in the middle */
    { bc_cseg_t s2[2] = { seg(BC_COACH_OPEN_ENDED, 2, 1, 1, 2, 0, 0), seg(60, 2, 1, 1, 2, 0, 0) };
      bc_coach_plan_msg_t o = { .workout_id = 90, .parts = 1, .nseg = 2, .head = true, .total_segments = 2, .plan_crc32 = bc_cm_plan_crc(s2, 2) }; memcpy(o.seg, s2, sizeof s2);
      CHECK(bc_cm_plan_part(&m, &o, &next) == BC_PLAN_CRC && m.plan_id == 77, "0xFFFF not in the last segment: status 3"); }

    /* offline follow on the board's ride clock (t0 = ride start) */
    bc_cm_view_t v;
    bc_cm_view(&m, false, 1000, 0, &v);
    CHECK(v.mode == BC_CM_PLAN_OFFLINE && v.type == BC_WT_WARMUP && v.lo == 100 && v.has_remaining && v.remaining_s == 600 && v.has_next && v.next_type == BC_WT_THRESHOLD, "offline: warm-up first");
    bc_cm_view(&m, false, 1000, 595, &v);
    CHECK(v.remaining_s == 5 && v.instruction == BC_CI_GET_READY, "5 s before the interval: GET READY");
    bc_cm_view(&m, false, 1000, 600 + 300 + 10, &v);
    CHECK(v.type == BC_WT_RECOVERY && v.interval_index == 2 && v.remaining_s == 170, "third segment by the ride clock (%u, %u)", v.interval_index, v.remaining_s);
    bc_cm_view(&m, false, 1000, 600 + 9 * 300 + 9 * 180 + 5000, &v);
    CHECK(v.type == BC_WT_COOLDOWN && !v.has_remaining && !v.done && v.interval_index == 19, "open-ended last segment: no countdown");
    char L[BC_CM_CARD_LINES][BC_CM_LINE];
    bc_cm_card(&v, 120, 85, -1, L);
    CHECK(!strcmp(L[0], "CYCLIFT COACH") && !strcmp(L[1], "COOL-DOWN 20/20") && !strcmp(L[2], "HR --") && !strcmp(L[3], "TARGET 100-125 BPM") && !strcmp(L[8], "PHONE LOST - PLAN"),
          "card offline HR segment: %s | %s | %s | %s | %s", L[0], L[1], L[2], L[3], L[8]);
    /* t0 later than now */
    m.t0_elapsed_s = 100; bc_cm_view(&m, false, 1000, 40, &v);
    CHECK(v.instruction == BC_CI_GET_READY && v.remaining_s == 60 && v.interval_index == 0, "plan starts at elapsed 100: get ready, 60 s");
    m.t0_elapsed_s = BC_COACH_T0_RIDE_START;
}

static void state_tests(void)
{
    uint8_t b[BC_LINK_MAX]; size_t n;
    bc_coach_state_t s; memset(&s, 0, sizeof s);
    s.workout_id = 77; s.seq = 10; s.type = BC_WT_ENDURANCE; s.kind = BC_TK_POWER; s.lo = 140; s.hi = 155; s.cad_lo = 80; s.cad_hi = 90;
    s.interval_index = 1; s.interval_count = 3; s.remaining_s = 1200; s.interval_dur_s = 2400;
    s.next_type = BC_WT_RECOVERY; s.next_kind = BC_TK_POWER; s.next_lo = 100; s.next_hi = 120; s.next_dur_s = 180;
    s.instruction = BC_CI_ON_TARGET; memcpy(s.text, "Smooth \xC3\xA9tape r\xC3\xA9guli\xC3\xA8r", 24); s.text[24] = 0;   /* 24 B, UTF-8 */
    s.session_state = BC_SESS_RUNNING; s.hr_src = 4; s.zone = 2; s.flags = BC_CSF_WATCH_HR;
    s.has = 0x7FFFFF;
    n = bc_link_encode_coach_state(&s, b, sizeof b, 9, 0);
    CHECK(n > 0 && n <= 120, "COACH_STATE with every field and a 24-byte text <= 120 B (%zu)", n);
    bc_coach_state_t d; CHECK(bc_link_decode_coach_state(b, n, &d) && d.workout_id == 77 && d.seq == 10 && d.lo == 140 && d.hi == 155 && d.remaining_s == 1200
                              && d.next_dur_s == 180 && d.instruction == 1 && d.hr_src == 4 && d.flags == 4 && d.has == 0x7FFFFF, "COACH_STATE round trip");
    CHECK(!strcmp(d.text, s.text), "24-byte UTF-8 text kept");
    { /* a phone that sends 26 bytes: cut to <= 24 at a character boundary */
      bc_coach_state_t mn; memset(&mn, 0, sizeof mn); mn.workout_id = 5; mn.seq = 1; size_t k = bc_link_encode_coach_state(&mn, b, sizeof b, 1, 0);
      const char *t26 = "aaaaaaaaaaaaaaaaaaaaaaa\xC3\xA9" "b"; b[k] = 0x13; b[k + 1] = 26; memcpy(b + k + 2, t26, 26); k += 28;
      bc_coach_state_t x; CHECK(bc_link_decode_coach_state(b, k, &x) && strlen(x.text) == 23, "26-byte text cut at the UTF-8 boundary (%zu B)", strlen(x.text)); }
    { bc_coach_state_t mn; memset(&mn, 0, sizeof mn); mn.workout_id = 5; mn.seq = 1; n = bc_link_encode_coach_state(&mn, b, sizeof b, 1, 0);
      CHECK(n == 8 + 6 + 4, "minimal COACH_STATE = workout_id + seq (%zu)", n);
      bc_coach_state_t x; CHECK(bc_link_decode_coach_state(b, n, &x) && x.has == 3, "decoded has bits"); }
    { uint8_t m[] = { 0xB2, 0, 1, 0, 0, 0, 0, 0, 0x01, 4, 5, 0, 0, 0 }; bc_coach_state_t x; CHECK(!bc_link_decode_coach_state(m, sizeof m, &x), "no seq: rejected"); }
    bc_coach_end_t e = { 77, 1 }; n = bc_link_encode_coach_end(&e, b, sizeof b, 2, 0);
    bc_coach_end_t de; CHECK(bc_link_decode_coach_end(b, n, &de) && de.workout_id == 77 && de.reason == 1, "COACH_END");

    /* seq rule + view */
    static bc_cmirror_t m; bc_cm_init(&m); bc_cm_view_t v;
    CHECK(bc_cm_state(&m, &s, 1000), "first state applied");
    bc_coach_state_t old = s; old.seq = 9; CHECK(!bc_cm_state(&m, &old, 1100), "older seq ignored");
    bc_coach_state_t same = s; CHECK(!bc_cm_state(&m, &same, 1100), "equal seq ignored (strictly newer only)");
    bc_coach_state_t wrap = s; m.st.seq = 65530; wrap.seq = 3; CHECK(bc_cm_state(&m, &wrap, 1200), "seq wraps: 3 is newer than 65530");
    s.seq = 11; CHECK(bc_cm_state(&m, &s, 2000), "newer seq applied");
    bc_cm_view(&m, true, 7000, 50, &v);
    CHECK(v.mode == BC_CM_FOLLOWING && v.remaining_s == 1195 && v.lo == 140 && v.instruction == BC_CI_ON_TARGET && v.has_next, "following: remaining counts from the receive time (%u)", v.remaining_s);
    char L[BC_CM_CARD_LINES][BC_CM_LINE];
    s.kind = BC_TK_POWER; s.hr_src = 2; s.seq = 12; s.interval_count = 1; s.remaining_s = 0; s.has &= ~BC_CS_HAS(0x0B); bc_cm_state(&m, &s, 8000);
    bc_cm_view(&m, true, 8000, 50, &v); bc_cm_card(&v, 145, 84, 130, L);
    CHECK(!strcmp(L[0], "CYCLIFT COACH") && !strcmp(L[1], "ENDURANCE") && !strcmp(L[2], "POWER 145 W") && !strcmp(L[3], "TARGET 140-155 W") && !strcmp(L[4], "CADENCE 84")
          && !strcmp(L[5], "TARGET 80-90") && !strcmp(L[6], "COACH: ON TARGET") && !strcmp(L[7], "NEXT: RECOVERY - 3 MIN"),
          "the owner's example card: %s / %s / %s / %s / %s / %s / %s / %s", L[0], L[1], L[2], L[3], L[4], L[5], L[6], L[7]);
    for (int i = 0; i < BC_CM_CARD_LINES; i++) CHECK(strlen(L[i]) < BC_CM_LINE, "card line %d fits", i);
    /* the phone drops, no plan stored -> last targets; HR from the watch -> no HR */
    s.kind = BC_TK_HR; s.lo = 120; s.hi = 135; s.hr_src = 4; s.seq = 13; bc_cm_state(&m, &s, 9000);
    bc_cm_view(&m, false, 9500, 60, &v); bc_cm_card(&v, 150, -1, -1, L);
    CHECK(v.mode == BC_CM_LAST_TARGET && v.no_hr && !strcmp(L[6], "NO HR - RIDE BY FEEL") && !strcmp(L[8], "NO PHONE - LAST TARGET") && !strcmp(L[4], "CADENCE --"),
          "phone lost, watch HR: %s / %s", L[6], L[8]);
    /* phone connected but silent for 12 s = lost */
    bc_cm_view(&m, true, 9000 + BC_CM_STATE_STALE_MS + 1, 60, &v); CHECK(v.mode == BC_CM_LAST_TARGET, "connected but no state for 12 s: not 'following'");
    /* COACH_END */
    bc_cm_end(&m, 77); bc_cm_view(&m, true, 9600, 60, &v); CHECK(v.mode == BC_CM_NONE && !bc_cm_state(&m, &s, 9700), "COACH_END: nothing shown, later states of that workout ignored");
    s.workout_id = 78; s.seq = 1; CHECK(bc_cm_state(&m, &s, 9800), "a new workout id is accepted");
    for (int i = 0; i < 20; i++) CHECK(bc_cm_instr_text((uint8_t)i) != NULL && strlen(bc_cm_instr_text((uint8_t)i)) <= 20, "instr text %d", i);
    for (int i = 0; i < 20; i++) CHECK(strlen(bc_cm_instr_short((uint8_t)i)) <= 10 && (i >= BC_CI_COUNT || !i || bc_cm_instr_short((uint8_t)i)[0]), "rc4: short instruction %d '%s' <= 10 chars", i, bc_cm_instr_short((uint8_t)i));

    /* v1.3 (QA RC3-04): a COACH_STATE that omits fields keeps the previous values (merge); a keepalive refreshes only */
    { static bc_cmirror_t k; bc_cm_init(&k); bc_coach_state_t f; memset(&f, 0, sizeof f);
      f.workout_id = 300; f.seq = 5; f.type = BC_WT_THRESHOLD; f.kind = BC_TK_POWER; f.lo = 250; f.hi = 265; f.cad_lo = 85; f.cad_hi = 95; f.instruction = BC_CI_ON_TARGET;
      f.remaining_s = 400; snprintf(f.text, sizeof f.text, "steady"); f.session_state = BC_SESS_RUNNING; f.hr_src = 2; f.has = 0x7FFFFF;
      CHECK(bc_cm_state(&k, &f, 1000), "full state applied");
      bc_coach_state_t ka; memset(&ka, 0, sizeof ka); ka.workout_id = 300; ka.seq = 6; ka.has = BC_CS_HAS(1) | BC_CS_HAS(2);
      CHECK(bc_cm_state(&k, &ka, 11000), "keepalive (workout_id + seq) applied");
      bc_cm_view_t kv; bc_cm_view(&k, true, 20000, 0, &kv);
      CHECK(kv.mode == BC_CM_FOLLOWING && kv.lo == 250 && kv.hi == 265 && kv.cad_lo == 85 && kv.instruction == BC_CI_ON_TARGET && !strcmp(kv.text, "steady") && kv.type == BC_WT_THRESHOLD,
            "keepalive: targets, instruction, text kept; still fresh 9 s later (mode %u lo %u)", kv.mode, kv.lo);
      CHECK(kv.has_remaining && kv.remaining_s == 400 - 19, "keepalive: the countdown runs from the last state that carried it (%u)", kv.remaining_s);
      bc_coach_state_t pi; memset(&pi, 0, sizeof pi); pi.workout_id = 300; pi.seq = 7; pi.instruction = BC_CI_MORE_POWER; pi.has = BC_CS_HAS(1) | BC_CS_HAS(2) | BC_CS_HAS(0x12);
      bc_cm_state(&k, &pi, 21000); bc_cm_view(&k, true, 21000, 0, &kv);
      CHECK(kv.instruction == BC_CI_MORE_POWER && kv.lo == 250 && kv.hi == 265, "instruction-only state: merged, targets kept");
      bc_coach_state_t nw; memset(&nw, 0, sizeof nw); nw.workout_id = 301; nw.seq = 1; nw.kind = BC_TK_POWER; nw.lo = 100; nw.hi = 120; nw.has = BC_CS_HAS(1) | BC_CS_HAS(2) | BC_CS_HAS(4) | BC_CS_HAS(5) | BC_CS_HAS(6);
      bc_cm_state(&k, &nw, 22000); bc_cm_view(&k, true, 22000, 0, &kv);
      CHECK(kv.workout_id == 301 && kv.lo == 100 && kv.instruction == 0 && !kv.text[0] && kv.cad_lo == 0, "a new workout replaces (no values carried over from the old one)");
      bc_cm_view(&k, true, 22000 + BC_CM_STATE_STALE_MS + 1, 0, &kv); CHECK(kv.mode != BC_CM_FOLLOWING, "no state or keepalive for 12 s: not following");
    /* v1.3 (QA RC3-03): each APP_HELLO opens a new seq window */
      bc_coach_state_t lo = nw; lo.seq = 9000; bc_cm_state(&k, &lo, 23000);
      bc_coach_state_t rs = nw; rs.seq = 1; rs.lo = 140; CHECK(!bc_cm_state(&k, &rs, 23100), "without a new HELLO a restarted phone's seq 1 is old: ignored");
      bc_cm_new_session(&k); CHECK(bc_cm_state(&k, &rs, 23200) && k.st.lo == 140, "after APP_HELLO: the first state is accepted whatever its seq");
      bc_coach_state_t rs2 = rs; rs2.lo = 99; CHECK(!bc_cm_state(&k, &rs2, 23300), "then strictly newer again (an equal seq is ignored)");
      rs2.seq = 2; CHECK(bc_cm_state(&k, &rs2, 23400), "seq 2 applied");
    /* rc4: a stored plan only stands in for its own workout */
      k.plan_ok = true; k.plan_id = 999; k.nseg = 1; bc_cm_view(&k, false, 23500, 10, &kv);
      CHECK(kv.mode == BC_CM_LAST_TARGET && kv.lo == 99, "phone lost, plan for another workout: last target of the current one (mode %u)", kv.mode);
      k.plan_ok = false; }
    CHECK(!strcmp(bc_cm_instr_text(99), "") && !strcmp(bc_cm_type_name(99), "WORKOUT"), "unknown codes");
}

static void rideq_tests(void)
{
    uint8_t b[BC_LINK_MAX]; size_t n;
    n = bc_link_encode_rideq_list_req(b, sizeof b, 1, 0); CHECK(n == 8 && b[0] == 0x90 && bc_link_decode_rideq_list_req(b, n), "RIDEQ_LIST_REQ");
    bc_rideq_info_t i = { 1234, BC_RQ_UNSYNCED, 40960, 0xDEADBEEF, 1792850100u, 3600, BC_RQF_RECOVERED | BC_RQF_RAM_ONLY, 0x12345678 };
    n = bc_link_encode_rideq_info(&i, b, sizeof b, 2, 0);
    bc_rideq_info_t di; CHECK(n == 50 && bc_link_decode_rideq_info(b, n, &di) && di.ride_id == i.ride_id && di.state == i.state && di.samples_size == i.samples_size && di.samples_crc == i.samples_crc && di.start_epoch_s == i.start_epoch_s && di.duration_s == i.duration_s && di.flags == i.flags && di.summary_crc == i.summary_crc, "RIDEQ_INFO round trip (%zu B)", n);
    bc_rideq_list_end_t e = { 3, 2, 81920 }; n = bc_link_encode_rideq_list_end(&e, b, sizeof b, 3, 0);
    bc_rideq_list_end_t de; CHECK(bc_link_decode_rideq_list_end(b, n, &de) && de.count == 3 && de.unsynced == 2 && de.unsynced_bytes == 81920, "RIDEQ_LIST_END");
    bc_diag_chunk_req_t q = { 1234, 310, 155 }; n = bc_link_encode_rideq_chunk_req(&q, b, sizeof b, 4, 0);
    uint8_t dq[BC_LINK_MAX]; size_t dn = bc_link_encode_diag_chunk_req(&q, dq, sizeof dq, 4, 0);
    CHECK(n == dn && b[0] == 0x93 && !memcmp(b + 1, dq + 1, n - 1), "RIDEQ_CHUNK_REQ = DIAG_CHUNK_REQ layout");
    bc_diag_chunk_req_t dqq; CHECK(bc_link_decode_rideq_chunk_req(b, n, &dqq) && dqq.id == 1234 && dqq.offset == 310 && !bc_link_decode_diag_chunk_req(b, n, &dqq), "type byte checked");
    bc_diag_chunk_t c; memset(&c, 0, sizeof c); c.id = 1234; c.offset = 310; c.len = 155; for (int k = 0; k < 155; k++) c.data[k] = (uint8_t)('0' + k % 10); c.last = true;
    n = bc_link_encode_rideq_chunk(&c, b, sizeof b, 5, 0);
    bc_diag_chunk_t dc; CHECK(n == BC_DIAG_CHUNK_OVERHEAD + 155 && n == BC_LINK_MAX && bc_link_decode_rideq_chunk(b, n, &dc) && dc.len == 155 && dc.last && !memcmp(dc.data, c.data, 155), "RIDEQ_CHUNK full size 180 B");
    bc_rideq_ack_t a = { 1234, 0xDEADBEEF, 0x12345678, 1 }; n = bc_link_encode_rideq_ack(&a, b, sizeof b, 6, 0);
    bc_rideq_ack_t da; CHECK(bc_link_decode_rideq_ack(b, n, &da) && da.ride_id == a.ride_id && da.samples_crc == a.samples_crc && da.summary_crc == a.summary_crc && da.delete_samples == 1, "RIDEQ_ACK");
    { uint8_t m[] = { 0x95, 0, 1, 0, 0, 0, 0, 0, 0x01, 4, 1, 0, 0, 0, 0x02, 4, 1, 2, 3, 4 }; CHECK(!bc_link_decode_rideq_ack(m, sizeof m, &da), "ACK without summary_crc rejected"); }
    bc_diag_err_t er = { 1234, BC_RQ_ERR_CRC }; n = bc_link_encode_rideq_err(&er, b, sizeof b, 7, 0);
    bc_diag_err_t der; CHECK(b[0] == 0x96 && bc_link_decode_rideq_err(b, n, &der) && der.code == 6 && der.id == 1234, "RIDEQ_ERR 6");
    bc_rides_pending_t p = { 2, 1234 }; n = bc_link_encode_rides_pending(&p, b, sizeof b, 8, 0);
    bc_rides_pending_t dp; bc_diag_ready_t dr; CHECK(bc_link_decode_rides_pending(b, n, &dp) && dp.unsynced == 2 && dp.newest_id == 1234 && !bc_link_decode_diag_ready(b, n, &dr), "EVENT 0x23 rides_pending (not diag_ready)");
    /* summary crc = CRC over the SYNC_RIDE fields */
    bc_ride_summary_t s; memset(&s, 0, sizeof s); s.id = 12; s.duration_s = 3600; s.avg_power = 180; s.max_power = 420; s.avg_cad = 85; s.avg_hr = -1; s.max_hr = -1; s.kj = 650; s.best20 = -1; s.inband_pct = -1; s.ftp_new = -1;
    uint8_t sb[BC_LINK_MAX]; size_t sn = bc_link_encode_sync_ride(&s, sb, sizeof sb, 77, 123456);
    CHECK(sn > 8 && bc_ride_summary_crc(&s) == bc_crc32(0, sb + 8, sn - 8), "summary_crc32 = CRC of the SYNC_RIDE bytes after the header (seq/time excluded)");
}

static void storage_tests(void)
{
    uint8_t b[BC_LINK_MAX]; size_t n;
    n = bc_link_encode_storage_status_req(b, sizeof b, 1, 0); CHECK(n == 8 && bc_link_decode_storage_status_req(b, n), "STORAGE_STATUS_REQ");
    bc_storage_status_t s = { .state = 3, .fs_total_kb = 7964, .fs_free_kb = 5096, .crash_partition = 1, .crash_dump_bytes = 0, .reports_stored = 2, .reports_unsent = 1,
                              .diag_bytes = 15000, .rides_unsynced = 4, .ride_bytes_unsynced = 160000, .ride_bytes_synced = 0, .app_slot_kb = 4032, .app_used_kb = 1804,
                              .nvs_used_entries = 300, .nvs_free_entries = 330, .root_free_slots = 0, .root_bad_entries = 512, .health = 2 };
    snprintf(s.code, sizeof s.code, "dir_corrupted");
    n = bc_link_encode_storage_status(&s, b, sizeof b, 2, 0);
    bc_storage_status_t d; CHECK(bc_link_decode_storage_status(b, n, &d) && !memcmp(&d, &s, sizeof s), "STORAGE_STATUS round trip");
    { bc_storage_status_t l = s; snprintf(l.code, sizeof l.code, "diag_unavailable"); size_t m = bc_link_encode_storage_status(&l, b, sizeof b, 2, 0);
      CHECK(m == 95 + strlen(l.code) && m <= BC_LINK_MAX, "STORAGE_STATUS with every field = 95 B + code (%zu)", m); }
    bc_storage_clean_req_t c = { 0xFF }; n = bc_link_encode_storage_clean_req(&c, b, sizeof b, 3, 0);
    bc_storage_clean_req_t dc; CHECK(bc_link_decode_storage_clean_req(b, n, &dc) && dc.what == 0x07, "CLEAN_REQ: only bits 0-2");
    bc_storage_clean_result_t r = { BC_CLEAN_DONE, 40960, 3 }; n = bc_link_encode_storage_clean_result(&r, b, sizeof b, 4, 0);
    bc_storage_clean_result_t dr; CHECK(bc_link_decode_storage_clean_result(b, n, &dr) && dr.status == 0 && dr.bytes_freed == 40960 && dr.items == 3, "CLEAN_RESULT");
    const bool allow[8] = { true, true, false, false, false, false, true, false };
    for (int st = 0; st < 8; st++) CHECK(bc_storage_clean_allowed((uint8_t)st) == allow[st], "clean-up rule for state %d (v1.1: refuse 2/3/4/5/7)", st);
    CHECK(bc_storage_health(0) == 0 && bc_storage_health(1) == 1 && bc_storage_health(3) == 2 && bc_storage_health(7) == 1, "health byte");
}

static void live_diag_tests(void)
{
    uint8_t b[BC_LINK_MAX]; size_t n;
    bc_live_t l; memset(&l, 0, sizeof l); l.ride_state = 1; l.ride_id = 9; l.elapsed_s = 10;
    size_t n0 = bc_link_encode_live(&l, b, sizeof b, 1, 0);
    l.has_coach = true; l.coach_seq = 12; l.coach_mode = 2; l.storage_state = 3; l.rides_unsynced = 4; l.bt_flags = 1;
    n = bc_link_encode_live(&l, b, sizeof b, 1, 0);
    bc_live_t d; CHECK(n == n0 + 4 + 3 + 3 + 3 + 3 && bc_link_decode_live(b, n, &d) && d.has_coach && d.coach_seq == 12 && d.coach_mode == 2 && d.storage_state == 3 && d.rides_unsynced == 4 && d.bt_flags == 1, "LIVE 1.3 tags 11..15");
    memset(&l, 0, sizeof l); l.ride_state = 1; CHECK(bc_link_encode_live(&l, b, sizeof b, 1, 0) == n0, "encoder: no 1.3 tag when has_l13 is unset and all are 0");
    l.has_l13 = true; n = bc_link_encode_live(&l, b, sizeof b, 1, 0);
    CHECK(n == n0 + 9 && bc_link_decode_live(b, n, &d) && d.has_l13 && d.storage_state == 0 && d.rides_unsynced == 0 && d.bt_flags == 0 && !d.has_coach,
          "v1.3 (RC3-08): firmware sets has_l13 -> 13/14/15 always sent, also as 0 (queue count 0 is a real 0)");
    { bc_live_t o; memset(&o, 0, sizeof o); o.ride_state = 1; size_t m = bc_link_encode_live(&o, b, sizeof b, 1, 0); bc_live_t od; bc_link_decode_live(b, m, &od);
      CHECK(!od.has_l13, "decoder: no tag 13-15 -> has_l13 false (older board: unknown, not 0)"); }
    { bc_sync_req_t q = { .after_ride_id = 41, .max_count = 1, .only_ride_id = 42 }; n = bc_link_encode_sync_req(&q, b, sizeof b, 1, 0);
      bc_sync_req_t dq; CHECK(bc_link_decode_sync_req(b, n, &dq) && dq.after_ride_id == 41 && dq.max_count == 1 && dq.only_ride_id == 42, "v1.3 (RC3-01): SYNC_REQ tag 03 only_ride_id round trip");
      bc_sync_req_t q0 = { .after_ride_id = 41, .max_count = 1 }; size_t m = bc_link_encode_sync_req(&q0, b, sizeof b, 1, 0);
      CHECK(m + 4 == n && bc_link_decode_sync_req(b, m, &dq) && dq.only_ride_id == 0, "without it: the 1.2.3 bytes (%zu B)", m); }
    bc_diag_ack_t a = { 5, 0xABCD, 0 }; n = bc_link_encode_diag_ack(&a, b, sizeof b, 1, 0);
    CHECK(n == 8 + 12, "DIAG_ACK without delete = the 1.2.3 bytes");
    a.del = 1; n = bc_link_encode_diag_ack(&a, b, sizeof b, 1, 0);
    bc_diag_ack_t da; CHECK(n == 8 + 15 && bc_link_decode_diag_ack(b, n, &da) && da.del == 1 && da.id == 5, "DIAG_ACK 03 delete");
}

int main(void)
{
    hello_tests(); plan_tests(); state_tests(); rideq_tests(); storage_tests(); live_diag_tests();
    printf("test_bc_link13: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
