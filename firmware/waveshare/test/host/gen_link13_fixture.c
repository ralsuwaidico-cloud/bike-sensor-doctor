/*
 * Link 1.3 (BLE_CONTRACT.md v1.1) cross-test fixture. Every byte vector is produced by the FIRMWARE's own encoder
 * (bc_link13.c / bc_link.c); the expected decoded fields are listed next to it. The iOS tests (Cyclift Link13 code) assert
 * that its encoder produces the same bytes for the phone -> board messages and that its decoder yields the listed fields
 * for the board -> phone messages; plus the summary_crc32 / samples CRC definitions and the coach plan CRC.
 *
 *   gen_link13_fixture OUT.json OUT.swift          write the fixture (JSON + the same JSON embedded in a Swift file)
 *   gen_link13_fixture --check IN.json IN.swift     regenerate and compare (make fails when the committed fixture is stale)
 */
#define _POSIX_C_SOURCE 200809L
#include "bc_link13.h"
#include "bc_cmirror.h"
#include "bc_diag.h"
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char *J; static size_t JN, JCAP;
static void put(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
static void put(const char *fmt, ...)
{
    va_list ap;
    for (;;) {
        va_start(ap, fmt); int n = vsnprintf(J + JN, JCAP - JN, fmt, ap); va_end(ap);
        if (n >= 0 && JN + (size_t)n < JCAP) { JN += (size_t)n; return; }
        JCAP = JCAP * 2 + 4096; J = realloc(J, JCAP); if (!J) abort();
    }
}
static void b64(const uint8_t *b, size_t n)
{
    static const char A[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    put("\"");
    for (size_t i = 0; i < n; i += 3) {
        uint32_t v = (uint32_t)b[i] << 16 | (i + 1 < n ? (uint32_t)b[i + 1] << 8 : 0) | (i + 2 < n ? b[i + 2] : 0);
        put("%c%c%c%c", A[v >> 18 & 63], A[v >> 12 & 63], i + 1 < n ? A[v >> 6 & 63] : '=', i + 2 < n ? A[v & 63] : '=');
    }
    put("\"");
}
static bool first;
static void vec(const char *name, const char *dir, const uint8_t *b, size_t n, const char *fields_fmt, ...) __attribute__((format(printf, 5, 6)));
static void vec(const char *name, const char *dir, const uint8_t *b, size_t n, const char *fields_fmt, ...)
{
    if (!n) { fprintf(stderr, "vector %s did not encode\n", name); exit(3); }
    put("%s\n  {\"name\": \"%s\", \"dir\": \"%s\", \"type\": %u, \"len\": %zu, \"bytes\": ", first ? "" : ",", name, dir, b[0], n); b64(b, n);
    char f[1024]; va_list ap; va_start(ap, fields_fmt); vsnprintf(f, sizeof f, fields_fmt, ap); va_end(ap);
    put(", \"fields\": {%s}}", f);
    first = false;
}

static void generate(void)
{
    JN = 0; if (!J) { JCAP = 1 << 16; J = malloc(JCAP); }
    uint8_t b[BC_LINK_MAX]; size_t n;
    put("{\n\"generator\": \"firmware/waveshare/test/host/gen_link13_fixture.c (firmware 0.7.5 Link 1.3 codec, BLE_CONTRACT.md v1.1)\",\n");
    put("\"link_max\": %d, \"caps\": {\"hello\": %u, \"coach\": %u, \"ride_queue\": %u, \"storage\": %u, \"diag_auto\": %u, \"board\": %u},\n",
        BC_LINK_MAX, BC_CAP_HELLO, BC_CAP_COACH, BC_CAP_RIDE_QUEUE, BC_CAP_STORAGE, BC_CAP_DIAG_AUTO, BC_CAPS_BOARD);
    put("\"vectors\": [");
    first = true;

    /* HELLO */
    bc_hello_t h = { 1, 3, BC_CAPS_LINK13, "" }; snprintf(h.app_version, sizeof h.app_version, "1.0 (42)");
    n = bc_link_encode_hello(&h, b, sizeof b, 1, 0);
    vec("app_hello", "phone_to_board", b, n, "\"seq\": 1, \"link_major\": 1, \"link_minor\": 3, \"app_caps\": %u, \"app_version\": \"1.0 (42)\"", h.app_caps);
    bc_hello_ack_t ha = { BC_CAPS_BOARD & h.app_caps }; n = bc_link_encode_hello_ack(&ha, b, sizeof b, 1, 0x1000);
    vec("hello_ack", "board_to_phone", b, n, "\"seq\": 1, \"enabled_caps\": %u", ha.enabled_caps);

    /* COACH_PLAN: 12 segments in 2 parts (9 + 3), open-ended cool-down */
    bc_cseg_t s[12];
    s[0] = (bc_cseg_t){ 600, BC_WT_WARMUP, BC_TK_POWER, 100, 140, 80, 90 };
    for (int i = 1; i < 11; i++) s[i] = (i % 2) ? (bc_cseg_t){ 480, BC_WT_SWEET_SPOT, BC_TK_POWER, 210, 225, 85, 95 } : (bc_cseg_t){ 180, BC_WT_RECOVERY, BC_TK_POWER, 100, 130, 0, 0 };
    s[11] = (bc_cseg_t){ BC_COACH_OPEN_ENDED, BC_WT_COOLDOWN, BC_TK_HR, 100, 125, 0, 0 };
    uint32_t pcrc = bc_cm_plan_crc(s, 12);
    bc_coach_plan_msg_t p0 = { .workout_id = 0x0A0B0C0Du, .part = 0, .parts = 2, .first_segment = 0, .nseg = 9, .head = true, .total_segments = 12,
                               .total_duration_s = 600 + 5 * 480 + 5 * 180 + 65535, .plan_crc32 = pcrc, .t0_elapsed_s = BC_COACH_T0_RIDE_START };
    snprintf(p0.name, sizeof p0.name, "Sweet spot 5x8");
    memcpy(p0.seg, s, sizeof s[0] * 9);
    n = bc_link_encode_coach_plan(&p0, b, sizeof b, 2, 0);
    vec("coach_plan_part0", "phone_to_board", b, n, "\"seq\": 2, \"workout_id\": %u, \"part\": 0, \"parts\": 2, \"first_segment\": 0, \"segments\": 9, \"name\": \"Sweet spot 5x8\", "
        "\"total_segments\": 12, \"total_duration_s\": %u, \"plan_crc32\": %u, \"t0_elapsed_s\": %u", p0.workout_id, p0.total_duration_s, pcrc, p0.t0_elapsed_s);
    bc_coach_plan_msg_t p1 = { .workout_id = p0.workout_id, .part = 1, .parts = 2, .first_segment = 9, .nseg = 3 };
    memcpy(p1.seg, s + 9, sizeof s[0] * 3);
    n = bc_link_encode_coach_plan(&p1, b, sizeof b, 3, 0);
    vec("coach_plan_part1", "phone_to_board", b, n, "\"seq\": 3, \"workout_id\": %u, \"part\": 1, \"parts\": 2, \"first_segment\": 9, \"segments\": 3, \"last_duration_s\": 65535", p1.workout_id);
    bc_coach_plan_ack_t pa1 = { p0.workout_id, BC_PLAN_PART_OK, 1 }; n = bc_link_encode_coach_plan_ack(&pa1, b, sizeof b, 2, 0x1001);
    vec("coach_plan_ack_part", "board_to_phone", b, n, "\"seq\": 2, \"workout_id\": %u, \"status\": 1, \"next_part\": 1", p0.workout_id);
    bc_coach_plan_ack_t pa2 = { p0.workout_id, BC_PLAN_COMPLETE, 2 }; n = bc_link_encode_coach_plan_ack(&pa2, b, sizeof b, 3, 0x1002);
    vec("coach_plan_ack_complete", "board_to_phone", b, n, "\"seq\": 3, \"workout_id\": %u, \"status\": 0, \"next_part\": 2", p0.workout_id);

    /* COACH_STATE: the owner's example (ENDURANCE 140-155 W, cadence 80-90, ON TARGET, next RECOVERY 3 min) + a minimal keepalive */
    bc_coach_state_t cs; memset(&cs, 0, sizeof cs);
    cs.workout_id = p0.workout_id; cs.seq = 41; cs.type = BC_WT_ENDURANCE; cs.kind = BC_TK_POWER; cs.lo = 140; cs.hi = 155; cs.cad_lo = 80; cs.cad_hi = 90;
    cs.interval_index = 3; cs.interval_count = 12; cs.remaining_s = 161; cs.interval_dur_s = 480;
    cs.next_type = BC_WT_RECOVERY; cs.next_kind = BC_TK_POWER; cs.next_lo = 100; cs.next_hi = 130; cs.next_dur_s = 180;
    cs.instruction = BC_CI_ON_TARGET; snprintf(cs.text, sizeof cs.text, "Smooth and steady");
    cs.session_state = BC_SESS_RUNNING; cs.hr_src = 4; cs.zone = 2; cs.flags = BC_CSF_FTP_DERIVED | BC_CSF_WATCH_HR; cs.has = 0x7FFFFF;
    n = bc_link_encode_coach_state(&cs, b, sizeof b, 4, 0);
    vec("coach_state_full", "phone_to_board", b, n, "\"seq\": 4, \"workout_id\": %u, \"state_seq\": 41, \"workout_type\": 2, \"target_kind\": 1, \"target_lo\": 140, \"target_hi\": 155, "
        "\"cad_lo\": 80, \"cad_hi\": 90, \"interval_index\": 3, \"interval_count\": 12, \"remaining_s\": 161, \"interval_duration_s\": 480, \"next_type\": 1, \"next_target_kind\": 1, "
        "\"next_lo\": 100, \"next_hi\": 130, \"next_duration_s\": 180, \"instruction\": 1, \"text\": \"Smooth and steady\", \"session_state\": 1, \"hr_src\": 4, \"zone\": 2, \"flags\": 6", cs.workout_id);
    { bc_cmirror_t *m = calloc(1, sizeof *m); bc_cm_init(m); bc_cm_state(m, &cs, 1000); bc_cm_view_t v; bc_cm_view(m, true, 1000, 0, &v);
      char L[BC_CM_CARD_LINES][BC_CM_LINE]; bc_cm_card(&v, 145, 84, 132, L);
      put(",\n  {\"name\": \"coach_card_example\", \"dir\": \"board_screen\", \"live\": {\"power_w\": 145, \"cadence_rpm\": 84, \"hr_bpm\": 132}, \"lines\": [");
      for (int i = 0; i < BC_CM_CARD_LINES; i++) put("%s\"%s\"", i ? ", " : "", L[i]);
      put("]}"); free(m); }
    bc_coach_state_t ka; memset(&ka, 0, sizeof ka); ka.workout_id = p0.workout_id; ka.seq = 42;
    n = bc_link_encode_coach_state(&ka, b, sizeof b, 5, 0);
    vec("coach_state_keepalive", "phone_to_board", b, n, "\"seq\": 5, \"workout_id\": %u, \"state_seq\": 42", ka.workout_id);
    bc_coach_end_t ce = { p0.workout_id, 0 }; n = bc_link_encode_coach_end(&ce, b, sizeof b, 6, 0);
    vec("coach_end", "phone_to_board", b, n, "\"seq\": 6, \"workout_id\": %u, \"reason\": 0", ce.workout_id);

    /* ride queue */
    n = bc_link_encode_rideq_list_req(b, sizeof b, 7, 0); vec("rideq_list_req", "phone_to_board", b, n, "\"seq\": 7");
    /* a ride, its SYNC_RIDE and samples file, with both CRCs */
    bc_ride_summary_t r; memset(&r, 0, sizeof r);
    r.id = 23; r.duration_s = 5; r.paused_s = 1; r.avg_power = 181; r.max_power = 190; r.avg_cad = 86; r.avg_hr = -1; r.max_hr = -1; r.power_s = 5; r.cad_s = 5;
    r.ftp_w = 250; r.kj = 1; r.best20 = -1; r.inband_pct = -1; r.ftp_new = -1; r.distance_m = 52; r.dist_src = BC_SRC_PHONE_GPS; r.start_epoch_s = 1792850100u;
    uint8_t sr[BC_LINK_MAX]; size_t srn = bc_link_encode_sync_ride(&r, sr, sizeof sr, 9, 0x2000);
    const char *samples = "J1 23 0 250 1 1\n175 85 -1 10\n180 86 -1 21\n-\n185 86 -1 31\n190 87 -1 42\n175 86 -1 52\n";
    uint32_t scrc = bc_crc32(0, samples, strlen(samples)), sumcrc = bc_ride_summary_crc(&r);
    put(",\n  {\"name\": \"ride_23\", \"dir\": \"definition\", \"sync_ride\": "); b64(sr, srn);
    put(", \"summary_crc32\": %u, \"summary_crc32_over\": \"sync_ride bytes 8..end\", \"samples\": ", sumcrc); b64((const uint8_t *)samples, strlen(samples));
    put(", \"samples_size\": %zu, \"samples_crc32\": %u, \"samples_lines\": {\"header\": \"J1 23 0 250 1 1\", \"seconds\": 6, \"paused_seconds\": 1, \"missing\": -1, \"distance_cumulative\": true}}",
        strlen(samples), scrc);
    first = false;
    bc_rideq_info_t qi = { 23, BC_RQ_UNSYNCED, (uint32_t)strlen(samples), scrc, r.start_epoch_s, r.duration_s, 0, sumcrc };
    n = bc_link_encode_rideq_info(&qi, b, sizeof b, 8, 0x1003);
    vec("rideq_info", "board_to_phone", b, n, "\"seq\": 8, \"ride_id\": 23, \"state\": 1, \"samples_size\": %u, \"samples_crc32\": %u, \"start_epoch_s\": %u, \"duration_s\": 5, \"flags\": 0, \"summary_crc32\": %u",
        qi.samples_size, scrc, qi.start_epoch_s, sumcrc);
    bc_rideq_info_t qr = { 24, BC_RQ_UNSYNCED, 0, 0, 0, 1800, BC_RQF_RAM_ONLY, 0x11223344u };
    n = bc_link_encode_rideq_info(&qr, b, sizeof b, 9, 0x1004);
    vec("rideq_info_ram_only", "board_to_phone", b, n, "\"seq\": 9, \"ride_id\": 24, \"state\": 1, \"samples_size\": 0, \"samples_crc32\": 0, \"start_epoch_s\": 0, \"duration_s\": 1800, \"flags\": 16, \"summary_crc32\": %u", qr.summary_crc);
    bc_rideq_list_end_t le = { 2, 2, qi.samples_size }; n = bc_link_encode_rideq_list_end(&le, b, sizeof b, 10, 0x1005);
    vec("rideq_list_end", "board_to_phone", b, n, "\"seq\": 10, \"count\": 2, \"unsynced\": 2, \"unsynced_bytes\": %u", le.unsynced_bytes);
    bc_diag_chunk_req_t cq = { 23, 0, 155 }; n = bc_link_encode_rideq_chunk_req(&cq, b, sizeof b, 11, 0);
    vec("rideq_chunk_req", "phone_to_board", b, n, "\"seq\": 11, \"ride_id\": 23, \"offset\": 0, \"max_len\": 155");
    bc_diag_chunk_t ck; memset(&ck, 0, sizeof ck); ck.id = 23; ck.offset = 0; ck.len = (uint8_t)strlen(samples); memcpy(ck.data, samples, ck.len); ck.last = true;
    n = bc_link_encode_rideq_chunk(&ck, b, sizeof b, 11, 0x1006);
    vec("rideq_chunk", "board_to_phone", b, n, "\"seq\": 11, \"ride_id\": 23, \"offset\": 0, \"len\": %u, \"last\": true", ck.len);
    bc_rideq_ack_t ra = { 23, scrc, sumcrc, 1 }; n = bc_link_encode_rideq_ack(&ra, b, sizeof b, 12, 0);
    vec("rideq_ack", "phone_to_board", b, n, "\"seq\": 12, \"ride_id\": 23, \"samples_crc32\": %u, \"summary_crc32\": %u, \"delete_samples\": 1", scrc, sumcrc);
    bc_rideq_info_t qd = qi; qd.state = BC_RQ_SAMPLES_DELETED; n = bc_link_encode_rideq_info(&qd, b, sizeof b, 12, 0x1007);
    vec("rideq_info_after_ack", "board_to_phone", b, n, "\"seq\": 12, \"ride_id\": 23, \"state\": 4");
    bc_diag_err_t re = { 23, BC_RQ_ERR_CRC }; n = bc_link_encode_rideq_err(&re, b, sizeof b, 13, 0x1008);
    vec("rideq_err_crc", "board_to_phone", b, n, "\"seq\": 13, \"ride_id\": 23, \"code\": 6");
    bc_diag_err_t rb = { 23, BC_DIAG_ERR_BUSY }; n = bc_link_encode_rideq_err(&rb, b, sizeof b, 14, 0x1009);
    vec("rideq_err_busy_recording", "board_to_phone", b, n, "\"seq\": 14, \"ride_id\": 23, \"code\": 4");
    bc_rides_pending_t rp = { 2, 24 }; n = bc_link_encode_rides_pending(&rp, b, sizeof b, 15, 0x100A);
    vec("event_rides_pending", "board_to_phone", b, n, "\"seq\": 15, \"event_id\": 35, \"unsynced\": 2, \"newest_ride_id\": 24");

    /* storage */
    n = bc_link_encode_storage_status_req(b, sizeof b, 16, 0); vec("storage_status_req", "phone_to_board", b, n, "\"seq\": 16");
    bc_storage_status_t st = { .state = 3, .fs_total_kb = 7964, .fs_free_kb = 5096, .crash_partition = 1, .reports_stored = 0, .reports_unsent = 0, .rides_unsynced = 1,
                               .app_slot_kb = 4032, .app_used_kb = 1804, .nvs_used_entries = 310, .nvs_free_entries = 320, .root_free_slots = 0, .root_bad_entries = 512, .health = 2 };
    snprintf(st.code, sizeof st.code, "dir_corrupted");
    n = bc_link_encode_storage_status(&st, b, sizeof b, 16, 0x100B);
    vec("storage_status_dir_corrupted", "board_to_phone", b, n, "\"seq\": 16, \"state\": 3, \"code\": \"dir_corrupted\", \"fs_total_kb\": 7964, \"fs_free_kb\": 5096, \"crash_partition\": 1, "
        "\"crash_dump_bytes\": 0, \"reports_stored\": 0, \"reports_unsent\": 0, \"diag_bytes\": 0, \"rides_unsynced\": 1, \"ride_bytes_unsynced\": 0, \"ride_bytes_synced\": 0, "
        "\"app_slot_kb\": 4032, \"app_used_kb\": 1804, \"nvs_used_entries\": 310, \"nvs_free_entries\": 320, \"root_free_slots\": 0, \"root_bad_entries\": 512, \"health\": 2");
    bc_storage_clean_req_t cr = { BC_CLEAN_REPORTS | BC_CLEAN_SAMPLES | BC_CLEAN_CACHES }; n = bc_link_encode_storage_clean_req(&cr, b, sizeof b, 17, 0);
    vec("storage_clean_req", "phone_to_board", b, n, "\"seq\": 17, \"what\": 7");
    bc_storage_clean_result_t rr = { BC_CLEAN_REFUSED, 0, 0 }; n = bc_link_encode_storage_clean_result(&rr, b, sizeof b, 17, 0x100C);
    vec("storage_clean_refused", "board_to_phone", b, n, "\"seq\": 17, \"status\": 2, \"bytes_freed\": 0, \"items\": 0");
    bc_storage_clean_result_t rd = { BC_CLEAN_DONE, 40960, 3 }; n = bc_link_encode_storage_clean_result(&rd, b, sizeof b, 18, 0x100D);
    vec("storage_clean_done", "board_to_phone", b, n, "\"seq\": 18, \"status\": 0, \"bytes_freed\": 40960, \"items\": 3");
    put(",\n  {\"name\": \"storage_clean_rule\", \"dir\": \"definition\", \"allowed_states\": [0, 1, 6], \"refused_states\": [2, 3, 4, 5, 7]}");

    /* LIVE with the 1.3 tags, DIAG_ACK with delete */
    bc_live_t lv; memset(&lv, 0, sizeof lv);
    lv.power_ok = true; lv.power_w = 145; lv.power_age_ms = 400; lv.cad_ok = true; lv.cadence_rpm = 84; lv.cad_age_ms = 400; lv.ride_state = 1; lv.ride_id = 23; lv.elapsed_s = 1830;
    lv.distance_m = 12000; lv.cue_id = 0; lv.battery_pct = 80; lv.meter_link = 2; lv.has_coach = true; lv.coach_seq = 41; lv.coach_mode = 2; lv.storage_state = 3; lv.rides_unsynced = 1; lv.bt_flags = 0;
    n = bc_link_encode_live(&lv, b, sizeof b, 19, 0x100E);
    vec("live_with_link13_tags", "board_to_phone", b, n, "\"seq\": 19, \"power_w\": 145, \"cadence_rpm\": 84, \"ride_id\": 23, \"elapsed_s\": 1830, \"coach_seq\": 41, \"coach_mode\": 2, \"storage_state\": 3, \"rides_unsynced\": 1, \"bt_flags\": 0");
    bc_diag_ack_t da = { 7, 0xCBF43926u, 1 }; n = bc_link_encode_diag_ack(&da, b, sizeof b, 20, 0);
    vec("diag_ack_delete", "phone_to_board", b, n, "\"seq\": 20, \"report_id\": 7, \"crc32\": %u, \"delete\": 1", da.crc);
    put("\n]\n}\n");
}

static char *slurp(const char *p, size_t *n)
{
    FILE *f = fopen(p, "rb"); if (!f) return NULL;
    fseek(f, 0, SEEK_END); long z = ftell(f); fseek(f, 0, SEEK_SET);
    char *b = malloc((size_t)z + 1); if (!b) { fclose(f); return NULL; }
    *n = fread(b, 1, (size_t)z, f); b[*n] = 0; fclose(f); return b;
}
static void swift(FILE *f)
{
    fprintf(f, "// GENERATED by firmware/waveshare/test/host/gen_link13_fixture.c from the firmware 0.7.5 Link 1.3 codec (BLE_CONTRACT.md\n"
               "// v1.1). Do not edit: run `make fixture13` in firmware/waveshare/test/host and copy both files. The same JSON is meant\n"
               "// for ios/BikeComputerTests/Fixtures/link13_fw_fixture.json.\n"
               "enum Link13FirmwareFixture {\n    static let json = #\"\"\"\n%.*s\"\"\"#\n}\n", (int)JN, J);
}
int main(int argc, char **argv)
{
    bool check = argc == 4 && !strcmp(argv[1], "--check");
    if (argc != 3 && !check) { fprintf(stderr, "usage: %s OUT.json OUT.swift | --check IN.json IN.swift\n", argv[0]); return 2; }
    generate();
    const char *pj = argv[check ? 2 : 1], *ps = argv[check ? 3 : 2];
    char *sw = NULL; size_t swn = 0;
    { FILE *m = open_memstream(&sw, &swn); swift(m); fclose(m); }
    if (check) {
        size_t a, c; char *x = slurp(pj, &a), *y = slurp(ps, &c);
        bool ok = x && y && a == JN && !memcmp(x, J, JN) && c == swn && !memcmp(y, sw, swn);
        printf("gen_link13_fixture: %s\n", ok ? "fixture up to date" : "FIXTURE STALE - run make fixture13");
        free(x); free(y); free(sw); free(J);
        return ok ? 0 : 1;
    }
    FILE *f = fopen(pj, "wb"); if (!f) return 1; fwrite(J, 1, JN, f); fclose(f);
    f = fopen(ps, "wb"); if (!f) return 1; fwrite(sw, 1, swn, f); fclose(f);
    printf("gen_link13_fixture: wrote %s (%zu bytes) and %s\n", pj, JN, ps);
    free(sw); free(J);
    return 0;
}
