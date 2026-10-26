/*
 * Host tests for firmware 0.7.3 diagnostics (bc_diag.c, bc_boot.c, the Link 1.2.3 codec in bc_link.c). Built with
 * AddressSanitizer + UndefinedBehaviorSanitizer (Makefile). The byte vectors printed by test_vectors() are the ones in
 * docs/BLE_LINK_PROTOCOL.md "1.2.3" — the iOS receiver is checked against the same bytes.
 */
#include "bc_diag.h"
#include "bc_boot.h"
#include "bc_link.h"
#include "bc_pipe.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int fails, checks;
#include "diag_fixture.h"
#define CHECK(c, ...) do { checks++; if (!(c)) { fails++; printf("FAIL %s:%d %s  ", __FILE__, __LINE__, #c); printf(__VA_ARGS__); printf("\n"); } } while (0)

static void hex(const uint8_t *b, size_t n, char *out) { for (size_t i = 0; i < n; i++) sprintf(out + 3 * i, "%02X%s", b[i], i + 1 < n ? " " : ""); if (!n) out[0] = 0; }
static void expect_hex(const char *name, const uint8_t *b, size_t n, const char *want)
{
    char h[1200]; hex(b, n, h);
    printf("  %-22s %s\n", name, h);
    CHECK(!strcmp(h, want), "%s vector differs:\n   got  %s\n   want %s", name, h, want);
}

/* ------------------------------------------------------------------ CRC + event records */
static void test_crc_and_records(void)
{
    CHECK(bc_crc32(0, "123456789", 9) == 0xCBF43926u, "crc32 check value %08X", bc_crc32(0, "123456789", 9));
    CHECK(bc_crc32(bc_crc32(0, "1234", 4), "56789", 5) == 0xCBF43926u, "crc32 chaining");
    bc_ev_t e = { .seq = 77, .boot = 5, .t_ms = 12345, .type = BC_EV_SENSOR, .x = BC_STG_VALID, .a = 1, .b = 812, .c = 3, .d = 400 }, d;
    uint8_t r[BC_EV_SIZE]; bc_ev_encode(&e, r);
    CHECK(bc_ev_decode(r, &d) && d.seq == 77 && d.boot == 5 && d.type == BC_EV_SENSOR && d.x == BC_STG_VALID && d.b == 812 && d.d == 400, "record round trip");
    r[17] ^= 0x40; CHECK(!bc_ev_decode(r, &d), "a flipped bit fails the record CRC");
    memset(r, 0xFF, sizeof r); CHECK(!bc_ev_decode(r, &d), "erased slot is not a record");
    memset(r, 0, sizeof r); CHECK(!bc_ev_decode(r, &d), "zeroed slot is not a record");
    char t[160]; bc_ev_text(&e, t, sizeof t);
    CHECK(strstr(t, "SENSOR power -> VALID") && strstr(t, "pkts 812"), "event text: %s", t);
    for (int ty = 1; ty <= 15; ty++) { bc_ev_t x = e; x.type = (uint8_t)ty; x.d = UINT32_MAX; size_t n = bc_ev_text(&x, t, 24); CHECK(n < 24 && strlen(t) == n, "short buffer type %d", ty); }
}

/* ------------------------------------------------------------------ event ring: wrap, power loss, resume, batching */
#define SLOTS 64u
static uint8_t ring[SLOTS * BC_EV_SIZE];
static int flush_to_ring(bc_evlog_t *l, uint32_t now)
{
    bc_ev_t e[BC_EVLOG_PEND]; int n = bc_evlog_take(l, e, BC_EVLOG_PEND, now);
    for (int i = 0; i < n; i++) bc_ev_encode(&e[i], ring + (size_t)(e[i].seq % SLOTS) * BC_EV_SIZE);
    return n;
}
static void test_ring(void)
{
    memset(ring, 0xFF, sizeof ring);
    bc_evlog_t l; bc_evlog_init(&l, SLOTS, 1);
    uint32_t now = 0; int writes = 0;
    for (int i = 0; i < 200; i++) {
        now += 700;
        bc_evlog_add(&l, BC_EV_SENSOR, (uint8_t)(i % 9), 1, (uint32_t)i, 0, 0, now);
        if (bc_evlog_flush_due(&l, now, false)) { flush_to_ring(&l, now); writes++; }
    }
    flush_to_ring(&l, now);
    CHECK(writes <= 200 * 700 / 10000 + 2, "batched writes: %d writes for 200 events in 140 s (<= 1 per 10 s)", writes);
    bc_ev_t out[10]; int n = bc_evlog_newest(ring, SLOTS, out, 10);
    CHECK(n == 10 && out[9].b == 199 && out[0].b == 190, "newest 10 after wrap, oldest first (%d, %lu..%lu)", n, (unsigned long)out[0].b, (unsigned long)out[9].b);
    /* power loss in the middle of a write: one slot torn */
    uint32_t torn = (out[5].seq % SLOTS) * BC_EV_SIZE; ring[torn + 3] ^= 0xFF; ring[torn + 20] = 0x00;
    n = bc_evlog_newest(ring, SLOTS, out, 10);
    bool has195 = false; for (int i = 0; i < n; i++) if (out[i].b == 195) has195 = true;
    CHECK(n == 10 && !has195 && out[9].b == 199, "a torn record is skipped, every other record survives");
    bc_evlog_t l2; bc_evlog_init(&l2, SLOTS, 2); bc_evlog_resume(&l2, ring, SLOTS);
    CHECK(l2.next_seq == 201, "after restart the log continues at seq 201 (%lu)", (unsigned long)l2.next_seq);
    /* queue overflow drops low-priority records first */
    bc_evlog_t q; bc_evlog_init(&q, SLOTS, 3);
    for (int i = 0; i < BC_EVLOG_PEND; i++) bc_evlog_add(&q, i % 2 ? BC_EV_READING : BC_EV_PHONE, 0, 0, (uint32_t)i, 0, 0, 1);
    bc_evlog_add(&q, BC_EV_CRASH, 0, 0, 999, 0, 0, 2);
    int phones = 0; bool crash = false; for (int i = 0; i < q.npend; i++) { if (q.pend[i].type == BC_EV_PHONE) phones++; if (q.pend[i].type == BC_EV_CRASH) crash = true; }
    CHECK(q.dropped == 1 && crash && phones == BC_EVLOG_PEND / 2, "overflow: one READING dropped, PHONE + CRASH kept (dropped %lu)", (unsigned long)q.dropped);
    CHECK(bc_evlog_flush_due(&q, 2, true), "force flush");
}

/* ------------------------------------------------------------------ report index */
static void test_index(void)
{
    bc_diag_index_t x; memset(&x, 0, sizeof x); x.next_id = 1;
    for (int i = 0; i < BC_DIAG_MAX_REPORTS; i++) { bc_diag_info_t *r = &x.r[x.n++]; r->id = x.next_id++; r->size = 3000; r->crc = (uint32_t)i * 77; r->kind = 1; snprintf(r->summary, sizeof r->summary, "panic in task%d", i); snprintf(r->fw, sizeof r->fw, "0.7.3"); }
    uint8_t b[1200]; size_t n = bc_diag_index_encode(&x, b, sizeof b);
    bc_diag_index_t y; CHECK(n && bc_diag_index_decode(b, n, &y) && y.n == 12 && y.next_id == 13 && y.r[11].crc == 11 * 77 && !strcmp(y.r[3].summary, "panic in task3"), "index round trip");
    b[40] ^= 1; CHECK(!bc_diag_index_decode(b, n, &y), "a damaged index is rejected (CRC)");
    CHECK(bc_diag_index_make_room(&x, 1000) == -2, "store full of UNSENT reports: nothing is deleted, the new one is not stored");
    x.r[4].state = 1; x.r[7].state = 1;
    CHECK(bc_diag_index_make_room(&x, 1000) == 4, "the OLDEST SENT report is the one to delete");
    x.n = 3; CHECK(bc_diag_index_make_room(&x, 1000) == -1, "room left: nothing deleted");
    x.r[0].size = BC_DIAG_STORE_BYTES - 7000; x.r[0].state = 0; x.r[1].state = 0; x.r[2].state = 0;
    CHECK(bc_diag_index_make_room(&x, 5000) == -2, "byte limit also protects unsent reports");
    CHECK(bc_diag_index_pending(&x) == 3, "pending count");
}

/* ------------------------------------------------------------------ report builder + privacy */
static void test_report(void)
{
    bc_diag_report_in_t in; memset(&in, 0, sizeof in);
    in.id = 7; in.kind = BC_DIAG_KIND_CRASH; snprintf(in.fw, sizeof in.fw, "0.7.3"); snprintf(in.build, sizeof in.build, "Oct 26 2026 21:43:00");
    memset(in.elf_sha, 'a', 64); in.board_id_tail[0] = 0x3C; in.board_id_tail[1] = 0x9A;
    in.reset = BC_RST_PANIC; snprintf(in.reset_raw, sizeof in.reset_raw, "crash"); in.crash_streak = 3; in.boot_count = 41; in.marker = BC_SS_POWER;
    in.have_dump = true; snprintf(in.task, sizeof in.task, "nimble_host"); in.pc = 0x4200F4BC; in.exccause = 28; in.excvaddr = 0x17C;
    in.bt_depth = 3; in.bt[0] = 0x4200F4BC; in.bt[1] = 0x4202D8D4; in.bt[2] = 0x40385099;
    char tail[300]; snprintf(tail, sizeof tail, "I (12) link: identity random-static C1:22:33:44:55:66 gen 2\nI (900) wifi: connected, IP 192.168.1.23\nW (950) pipe: power: CCCD 0x0023\n");
    bc_diag_redact(tail); in.log_tail = tail;
    CHECK(strstr(tail, "..:..:..:..:55:66") && !strstr(tail, "C1:22") && strstr(tail, "x.x.x.x") && !strstr(tail, "192.168") && strstr(tail, "0x0023"),
          "privacy filter: MAC cut to the last 2 bytes, IPv4 masked, handles untouched:\n%s", tail);
    in.ntasks = 2; snprintf(in.tasks[0].name, 16, "nimble_host"); in.tasks[0].stack_free = 412; snprintf(in.tasks[1].name, 16, "taskLVGL"); in.tasks[1].stack_free = 6100;
    in.sens[0].paired = true; in.sens[0].stage = BC_STG_SUBSCRIBED; in.sens[0].valid_age_ms = UINT32_MAX; snprintf(in.sens[0].err, sizeof in.sens[0].err, "no data");
    bc_ev_t ev[2] = { { .seq = 1, .boot = 41, .t_ms = 100, .type = BC_EV_BOOT, .a = BC_RST_PANIC, .b = 3 }, { .seq = 2, .boot = 41, .t_ms = 900, .type = BC_EV_PHONE, .x = 4 } };
    static char out[BC_DIAG_REPORT_MAX]; size_t n = bc_diag_report_build(&in, ev, 2, out, sizeof out);
    static const char *const SEC[] = { "[header]", "[reset]", "[panic]", "[backtrace]", "[tasks]", "[heap]", "[events]", "[sensors]", "[phone]", "[wifi]", "[recovery]" };
    const char *p = out; bool order = true; for (int i = 0; i < 11; i++) { const char *q = strstr(p, SEC[i]); if (!q) { order = false; break; } p = q; }
    CHECK(n == strlen(out) && order, "all 11 sections present, in the 1.2.3 order");
    CHECK(strstr(out, "summary panic in nimble_host") && strstr(out, "0x4200F4BC 0x4202D8D4 0x40385099") && strstr(out, "app_elf_sha256 aaaa") && strstr(out, "board ..:3C:9A"), "crash facts + offline-decode data");
    CHECK(strstr(out, "power stage SUBSCRIBED") && strstr(out, "err no data") && strstr(out, "nimble_host stack_free 412"), "sensors + tasks");
    char sum[48]; bc_diag_summary(&in, sum, sizeof sum); CHECK(!strcmp(sum, "panic in nimble_host"), "summary %s", sum);
    in.have_dump = false; bc_diag_summary(&in, sum, sizeof sum); CHECK(!strcmp(sum, "panic (no core dump)"), "summary without a dump: %s", sum);
    char small[300]; n = bc_diag_report_build(&in, ev, 2, small, sizeof small);
    CHECK(n < sizeof small && strstr(small, "[truncated]"), "tiny buffer: cut at a line and marked");
}

/* ------------------------------------------------------------------ Link 1.2.3 vectors (docs/BLE_LINK_PROTOCOL.md) */
static void test_vectors(void)
{
    printf("  Link 1.2.3 vectors (seq / t_ms as listed in BLE_LINK_PROTOCOL.md):\n");
    uint8_t b[BC_LINK_MAX]; size_t n;
    n = bc_link_encode_diag_list_req(b, sizeof b, 1, 0x01020304);
    expect_hex("DIAG_LIST_REQ", b, n, "80 00 01 00 04 03 02 01");
    CHECK(bc_link_decode_diag_list_req(b, n), "list req decodes");
    bc_diag_info_t inf = { .id = 7, .size = 4321, .crc = 0xCBF43926u, .epoch_s = 1761480000u, .kind = 1, .state = 0 };
    snprintf(inf.summary, sizeof inf.summary, "panic in nimble_host"); snprintf(inf.fw, sizeof inf.fw, "0.7.3");
    n = bc_link_encode_diag_info(&inf, b, sizeof b, 2, 0x10);
    expect_hex("DIAG_INFO", b, n, "81 00 02 00 10 00 00 00 01 04 07 00 00 00 02 04 E1 10 00 00 03 04 26 39 F4 CB 04 04 40 0D FE 68 05 01 01 06 01 00 07 14 70 61 6E 69 63 20 69 6E 20 6E 69 6D 62 6C 65 5F 68 6F 73 74 08 05 30 2E 37 2E 33");
    bc_diag_info_t d; CHECK(bc_link_decode_diag_info(b, n, &d) && d.id == 7 && d.size == 4321 && d.crc == 0xCBF43926u && d.epoch_s == 1761480000u && d.kind == 1 && !strcmp(d.summary, inf.summary) && !strcmp(d.fw, "0.7.3"), "info round trip");
    bc_diag_list_end_t le = { 1, 1 }; n = bc_link_encode_diag_list_end(&le, b, sizeof b, 3, 0x10);
    expect_hex("DIAG_LIST_END", b, n, "82 00 03 00 10 00 00 00 01 01 01 02 01 01");
    bc_diag_chunk_req_t cq = { 7, 0, 160 }; n = bc_link_encode_diag_chunk_req(&cq, b, sizeof b, 4, 0x20);
    expect_hex("DIAG_CHUNK_REQ", b, n, "83 00 04 00 20 00 00 00 01 04 07 00 00 00 02 04 00 00 00 00 03 02 A0 00");
    bc_diag_chunk_req_t cq2; CHECK(bc_link_decode_diag_chunk_req(b, n, &cq2) && cq2.id == 7 && cq2.offset == 0 && cq2.max_len == 160, "chunk req round trip");
    bc_diag_chunk_t ch; memset(&ch, 0, sizeof ch); ch.id = 7; ch.offset = 0; ch.len = 9; memcpy(ch.data, "[header]\n", 9); ch.last = false;
    n = bc_link_encode_diag_chunk(&ch, b, sizeof b, 5, 0x21);
    expect_hex("DIAG_CHUNK", b, n, "84 00 05 00 21 00 00 00 01 04 07 00 00 00 02 04 00 00 00 00 03 09 5B 68 65 61 64 65 72 5D 0A 04 01 00");
    bc_diag_ack_t ak = { 7, 0xCBF43926u }; n = bc_link_encode_diag_ack(&ak, b, sizeof b, 6, 0x30);
    expect_hex("DIAG_ACK", b, n, "85 00 06 00 30 00 00 00 01 04 07 00 00 00 02 04 26 39 F4 CB");
    bc_diag_err_t er = { 9, BC_DIAG_ERR_UNKNOWN_ID }; n = bc_link_encode_diag_err(&er, b, sizeof b, 7, 0x31);
    expect_hex("DIAG_ERR", b, n, "86 00 07 00 31 00 00 00 01 04 09 00 00 00 02 01 01");
    bc_diag_ready_t rd = { 1, 7 }; n = bc_link_encode_diag_ready(&rd, b, sizeof b, 8, 0x40);
    expect_hex("EVENT diag_ready", b, n, "40 00 08 00 40 00 00 00 01 01 22 02 01 01 03 04 07 00 00 00");
    bc_diag_ready_t rd2; CHECK(bc_link_decode_diag_ready(b, n, &rd2) && rd2.pending == 1 && rd2.newest_id == 7, "diag_ready round trip");
    bc_sensor_diag_t sd; CHECK(!bc_link_decode_sensor_diag(b, n, &sd), "diag_ready is not a SENSOR_DIAG (event ids differ)");
    /* full-size chunk fits one notification */
    memset(&ch, 'x', sizeof ch); ch.id = 0xFFFFFFFF; ch.offset = 0xFFFFFFFF; ch.len = BC_DIAG_CHUNK_MAX; ch.last = true;
    n = bc_link_encode_diag_chunk(&ch, b, sizeof b, 9, 0); CHECK(n == BC_LINK_MAX, "a %u-byte chunk is exactly %u bytes on the wire (%zu)", BC_DIAG_CHUNK_MAX, BC_LINK_MAX, n);
    /* UTF-8: a summary is never cut inside a character */
    inf.summary[0] = 0; for (int i = 0; i < 20; i++) strcat(inf.summary, "\xC3\xA9");   /* exactly 40 bytes of "é" */
    n = bc_link_encode_diag_info(&inf, b, sizeof b, 2, 0); CHECK(bc_link_decode_diag_info(b, n, &d) && strlen(d.summary) == 40, "40-byte UTF-8 summary kept whole");
    {   /* a sender that puts 41 bytes ("x" + 20 x "é") in the summary: the board keeps whole characters only (39 bytes) */
        uint8_t w[80] = { 0x81, 0, 0, 0, 0, 0, 0, 0, 0x01, 0x04, 7, 0, 0, 0, 0x07, 41, 'x' }; for (int i = 0; i < 20; i++) { w[17 + 2 * i] = 0xC3; w[18 + 2 * i] = 0xA9; }
        CHECK(bc_link_decode_diag_info(w, 16 + 41, &d) && strlen(d.summary) == 39 && (uint8_t)d.summary[38] == 0xA9, "over-long summary cut at a character boundary (%zu)", strlen(d.summary)); }
    /* malformed input */
    uint8_t bad[12] = { 0x83, 0, 0, 0, 0, 0, 0, 0, 0x01, 0x04, 0x07, 0x00 };
    CHECK(!bc_link_decode_diag_chunk_req(bad, sizeof bad, &cq2), "a field running past the end is rejected");
    uint8_t noid[] = { 0x85, 0, 0, 0, 0, 0, 0, 0, 0x02, 0x04, 1, 2, 3, 4 };
    CHECK(!bc_link_decode_diag_ack(noid, sizeof noid, &ak), "ACK without a report id is rejected");
}

/* ------------------------------------------------------------------ the 1.2.3 server */
static bc_diag_index_t S_IDX; static char S_TXT[2][5000]; static bool S_FAIL_READ; static int S_MARKS;
static const bc_diag_index_t *s_index(void *c) { (void)c; return &S_IDX; }
static long s_read(void *c, uint32_t id, uint32_t off, uint8_t *buf, size_t n)
{ (void)c; if (S_FAIL_READ) return -1; for (int i = 0; i < S_IDX.n; i++) if (S_IDX.r[i].id == id) { memcpy(buf, S_TXT[i] + off, n); return (long)n; } return -1; }
static bool s_mark(void *c, uint32_t id) { (void)c; for (int i = 0; i < S_IDX.n; i++) if (S_IDX.r[i].id == id) { S_IDX.r[i].state = 1; S_MARKS++; return true; } return false; }
static size_t req(bc_diag_srv_t *s, uint8_t type, uint32_t id, uint32_t off, uint16_t maxl, uint32_t crc, uint8_t *out)
{
    uint8_t m[BC_LINK_MAX]; size_t n = 0;
    if (type == BC_MSG_DIAG_LIST_REQ) n = bc_link_encode_diag_list_req(m, sizeof m, 1, 0);
    else if (type == BC_MSG_DIAG_CHUNK_REQ) { bc_diag_chunk_req_t q = { id, off, maxl }; n = bc_link_encode_diag_chunk_req(&q, m, sizeof m, 1, 0); }
    else { bc_diag_ack_t a = { id, crc }; n = bc_link_encode_diag_ack(&a, m, sizeof m, 1, 0); }
    bc_diag_srv_write(s, m, n);
    return bc_diag_srv_next(s, out, BC_LINK_MAX, 2, 0);
}
static void test_server(void)
{
    memset(&S_IDX, 0, sizeof S_IDX);
    for (int i = 0; i < 2; i++) {
        size_t len = i ? 300 : 4321; for (size_t k = 0; k < len; k++) S_TXT[i][k] = (char)('a' + (k * 7 + i) % 26);
        bc_diag_info_t *r = &S_IDX.r[S_IDX.n++]; r->id = (uint32_t)(10 + i); r->size = (uint32_t)len; r->crc = bc_crc32(0, S_TXT[i], len); r->kind = (uint8_t)(i ? 3 : 1);
    }
    bc_diag_store_t st = { NULL, s_index, s_read, s_mark }; bc_diag_srv_t s; bc_diag_srv_init(&s, &st);
    bc_diag_srv_set_link(&s, 185, false);                 /* iOS negotiates ATT MTU 185 */
    uint8_t o[BC_LINK_MAX]; size_t n;
    uint8_t notdiag[8] = { BC_MSG_PROFILE_GET }; CHECK(!bc_diag_srv_write(&s, notdiag, 8), "other messages are left to app_psvc");
    n = req(&s, BC_MSG_DIAG_LIST_REQ, 0, 0, 0, 0, o);
    bc_diag_info_t i0, i1; bc_diag_list_end_t le;
    CHECK(n && bc_link_decode_diag_info(o, n, &i0) && i0.id == 10, "LIST: first DIAG_INFO");
    n = bc_diag_srv_next(&s, o, sizeof o, 3, 0); CHECK(n && bc_link_decode_diag_info(o, n, &i1) && i1.id == 11, "LIST: second DIAG_INFO");
    n = bc_diag_srv_next(&s, o, sizeof o, 4, 0); CHECK(n && bc_link_decode_diag_list_end(o, n, &le) && le.count == 2 && le.pending == 2, "LIST_END count 2 pending 2");
    CHECK(bc_diag_srv_next(&s, o, sizeof o, 5, 0) == 0, "nothing more due");
    /* pull report 10 with max_len 160: the board clamps to 155; interrupt after 9 chunks, resume at the offset reached */
    static uint8_t got[5000]; uint32_t off = 0; int chunks = 0; bool last = false;
    while (!last && chunks < 100) {
        if (chunks == 9) { bc_diag_srv_reset(&s); bc_diag_srv_set_link(&s, 185, false); }   /* the phone disconnected; on reconnect it asks again from `off` */
        n = req(&s, BC_MSG_DIAG_CHUNK_REQ, 10, off, 160, 0, o);
        bc_diag_chunk_t c; if (!(n && bc_link_decode_diag_chunk(o, n, &c))) { CHECK(0, "chunk %d did not decode", chunks); break; }
        CHECK(c.offset == off && c.len <= BC_DIAG_CHUNK_MAX && n <= BC_LINK_MAX, "chunk at %lu len %u", (unsigned long)c.offset, c.len);
        memcpy(got + off, c.data, c.len); off += c.len; last = c.last; chunks++;
    }
    CHECK(last && off == 4321 && !memcmp(got, S_TXT[0], 4321) && chunks == (4321 + 154) / 155, "interrupted transfer resumed: %lu bytes in %d chunks, identical", (unsigned long)off, chunks);
    /* pipelined requests: 4 queued, the 5th is refused BUSY */
    uint8_t m[BC_LINK_MAX];
    for (int k = 0; k < 5; k++) { bc_diag_chunk_req_t q = { 11, (uint32_t)(k * 50), 50 }; size_t mn = bc_link_encode_diag_chunk_req(&q, m, sizeof m, 1, 0); bc_diag_srv_write(&s, m, mn); }
    bc_diag_err_t e; n = bc_diag_srv_next(&s, o, sizeof o, 1, 0); CHECK(bc_link_decode_diag_err(o, n, &e) && e.code == BC_DIAG_ERR_BUSY, "5th pipelined request: BUSY");
    for (int k = 0; k < 4; k++) { bc_diag_chunk_t c; n = bc_diag_srv_next(&s, o, sizeof o, 1, 0); CHECK(bc_link_decode_diag_chunk(o, n, &c) && c.offset == (uint32_t)k * 50 && c.len == 50, "pipelined chunk %d in order", k); }
    /* errors */
    n = req(&s, BC_MSG_DIAG_CHUNK_REQ, 99, 0, 100, 0, o); CHECK(bc_link_decode_diag_err(o, n, &e) && e.code == BC_DIAG_ERR_UNKNOWN_ID && e.id == 99, "unknown id -> ERR 1");
    n = req(&s, BC_MSG_DIAG_CHUNK_REQ, 11, 301, 100, 0, o); CHECK(bc_link_decode_diag_err(o, n, &e) && e.code == BC_DIAG_ERR_BAD_OFFSET, "offset past the end -> ERR 2");
    bc_diag_chunk_t c0; n = req(&s, BC_MSG_DIAG_CHUNK_REQ, 11, 300, 100, 0, o); CHECK(bc_link_decode_diag_chunk(o, n, &c0) && c0.len == 0 && c0.last, "offset == size: empty last chunk");
    S_FAIL_READ = true; n = req(&s, BC_MSG_DIAG_CHUNK_REQ, 11, 0, 100, 0, o); CHECK(bc_link_decode_diag_err(o, n, &e) && e.code == BC_DIAG_ERR_STORAGE, "read failure -> ERR 3"); S_FAIL_READ = false;
    /* ACK */
    n = req(&s, BC_MSG_DIAG_ACK, 10, 0, 0, 0x12345678, o); CHECK(bc_link_decode_diag_info(o, n, &i0) && i0.state == 0 && S_MARKS == 0 && s.acks_bad == 1, "wrong crc: DIAG_INFO state 0, not marked");
    n = req(&s, BC_MSG_DIAG_ACK, 10, 0, 0, bc_crc32(0, got, 4321), o); CHECK(bc_link_decode_diag_info(o, n, &i0) && i0.state == 1 && S_MARKS == 1, "matching crc: marked sent, DIAG_INFO state 1");
    n = req(&s, BC_MSG_DIAG_ACK, 10, 0, 0, bc_crc32(0, got, 4321), o); CHECK(bc_link_decode_diag_info(o, n, &i0) && i0.state == 1 && S_MARKS == 1, "repeated ACK is harmless");
    n = req(&s, BC_MSG_DIAG_ACK, 55, 0, 0, 1, o); CHECK(bc_link_decode_diag_err(o, n, &e) && e.code == BC_DIAG_ERR_UNKNOWN_ID, "ACK of an unknown id -> ERR 1");
    /* fuzz: random bytes never crash the server and never produce an oversized reply */
    srand(7); int replies = 0;
    for (int k = 0; k < 20000; k++) {
        size_t len = (size_t)(rand() % 40); for (size_t j = 0; j < len; j++) m[j] = (uint8_t)rand();
        if (len) m[0] = (uint8_t)(0x80 + rand() % 7);
        bc_diag_srv_write(&s, m, len);
        while ((n = bc_diag_srv_next(&s, o, sizeof o, 1, 0)) > 0) { replies++; if (n > BC_LINK_MAX) { CHECK(0, "oversized reply"); break; } }
    }
    CHECK(replies > 0, "fuzzed 20000 random DIAG messages (%d replies, all <= 180 bytes)", replies);
}


/* ------------------------------------------------------------------ 0.7.3 final: chunk size from the NEGOTIATED ATT MTU */
static void test_chunk_size_contract(void)
{
    /* overhead is exact: an n-byte chunk is n + 25 bytes on the wire, for every n */
    for (unsigned d = 0; d <= BC_DIAG_CHUNK_MAX; d++) {
        bc_diag_chunk_t c; memset(&c, 0, sizeof c); c.id = 0xFFFFFFFF; c.offset = 0xFFFFFFFF; c.len = (uint8_t)d; c.last = true;
        uint8_t b[BC_LINK_MAX]; size_t n = bc_link_encode_diag_chunk(&c, b, sizeof b, 1, 0);
        if (n != d + BC_DIAG_CHUNK_OVERHEAD) { CHECK(0, "chunk of %u data bytes is %zu bytes (want %u)", d, n, d + BC_DIAG_CHUNK_OVERHEAD); break; }
    }
    CHECK(BC_DIAG_CHUNK_OVERHEAD == 25 && BC_DIAG_CHUNK_MAX == 155, "overhead 25 = 8 + 6 + 6 + 2 + 3; max data 155 = 180 - 25 (data 0..155 checked)");
    /* the formula: min(max_len, 155, ATT_MTU - 3 - 25) */
    static const struct { uint16_t max_len, mtu, want; } T[] = {
        { 160, 23, 0 }, { 155, 23, 0 }, { 0, 0, 0 }, { 155, 28, 0 }, { 155, 29, 1 }, { 155, 100, 72 }, { 160, 185, 155 }, { 155, 185, 155 },
        { 0, 185, 155 }, { 160, 247, 155 }, { 160, 517, 155 }, { 50, 517, 50 }, { 157, 185, 155 }, { 72, 100, 72 }, { 73, 100, 72 } };
    for (size_t i = 0; i < sizeof T / sizeof *T; i++)
        CHECK(bc_diag_chunk_data_max(T[i].max_len, T[i].mtu) == T[i].want, "data_max(max_len %u, MTU %u) = %u (want %u)", T[i].max_len, T[i].mtu,
              bc_diag_chunk_data_max(T[i].max_len, T[i].mtu), T[i].want);
    printf("  chunk data: MTU 23 -> %u (ERR 5), 100 -> %u, 185 -> %u, 247 -> %u, 517 -> %u\n", bc_diag_chunk_data_max(155, 23), bc_diag_chunk_data_max(155, 100),
           bc_diag_chunk_data_max(155, 185), bc_diag_chunk_data_max(155, 247), bc_diag_chunk_data_max(155, 517));
    /* the old phone request (max_len 160, a 185-byte message) never produces an oversized notification at any MTU */
    for (unsigned mtu = 23; mtu <= 517; mtu++) {
        unsigned d = bc_diag_chunk_data_max(160, (uint16_t)mtu);
        if (d && (d + BC_DIAG_CHUNK_OVERHEAD > mtu - 3 || d + BC_DIAG_CHUNK_OVERHEAD > BC_LINK_MAX)) { CHECK(0, "MTU %u: %u data bytes do not fit", mtu, d); break; }
    }
    CHECK(1, "every MTU 23..517: chunk + 25 <= min(MTU - 3, 180)");
}

/* the firmware's real report, pulled at each MTU with the request Cyclift sends on that link; CRC over the reassembled bytes */
static void test_fixture_transfers(void)
{
    fx_store_init();
    const bc_diag_info_t *R = &FX_IDX.r[0];
    CHECK(R->size > 3000 && R->size == FX_LEN && strstr(FX_TXT, "[backtrace]") && strstr(FX_TXT, "..:..:..:..:55:4") && !strstr(FX_TXT, "C1:22"),
          "fixture report from the real builder: %lu bytes, crc %08lX, redacted", (unsigned long)R->size, (unsigned long)R->crc);
    static const uint16_t MTUS[] = { 23, 100, 185, 247, 517 };
    for (size_t t = 0; t < sizeof MTUS / sizeof *MTUS; t++) {
        uint16_t mtu = MTUS[t], pml = fx_phone_max_len(mtu);
        bc_diag_srv_t s; fx_srv(&s, mtu, false);
        uint8_t o[BC_LINK_MAX]; size_t n;
        if (!pml) {
            n = req(&s, BC_MSG_DIAG_CHUNK_REQ, R->id, 0, 160, 0, o); bc_diag_err_t e;
            CHECK(bc_link_decode_diag_err(o, n, &e) && e.code == BC_DIAG_ERR_MTU && s.mtu_errs == 1, "MTU %u: Cyclift does not ask; a request anyway -> DIAG_ERR 5", mtu);
            continue;
        }
        static uint8_t got[BC_DIAG_REPORT_MAX]; uint32_t off = 0; int chunks = 0; bool last = false, sizes_ok = true;
        while (!last && chunks < 1000) {
            n = req(&s, BC_MSG_DIAG_CHUNK_REQ, R->id, off, pml, 0, o);
            bc_diag_chunk_t c; if (!bc_link_decode_diag_chunk(o, n, &c)) { CHECK(0, "MTU %u chunk %d", mtu, chunks); break; }
            if (n + 3 > mtu || n > BC_LINK_MAX || c.offset != off || (!c.last && c.len != bc_diag_chunk_data_max(pml, mtu))) sizes_ok = false;
            memcpy(got + off, c.data, c.len); off += c.len; last = c.last; chunks++;
        }
        uint32_t want_chunks = (R->size + bc_diag_chunk_data_max(pml, mtu) - 1) / bc_diag_chunk_data_max(pml, mtu);
        CHECK(sizes_ok && off == R->size && (uint32_t)chunks == want_chunks && bc_crc32(0, got, off) == R->crc,
              "MTU %u: max_len %u, %d chunks of %u, every notification <= MTU-3, crc32 %08lX ok", mtu, pml, chunks, bc_diag_chunk_data_max(pml, mtu), (unsigned long)bc_crc32(0, got, off));
    }
    /* ride priority in the server: chunks BUSY while a ride records, LIST + ACK still answered, chunks again after the ride */
    bc_diag_srv_t s; fx_srv(&s, 185, true); uint8_t o[BC_LINK_MAX]; size_t n; bc_diag_err_t e; bc_diag_info_t i;
    CHECK(!bc_diag_srv_chunk_next(&s), "nothing due");
    n = req(&s, BC_MSG_DIAG_CHUNK_REQ, R->id, 0, 155, 0, o); CHECK(bc_link_decode_diag_err(o, n, &e) && e.code == BC_DIAG_ERR_BUSY && s.busy_ride == 1, "ride recording: CHUNK_REQ -> BUSY");
    n = req(&s, BC_MSG_DIAG_LIST_REQ, 0, 0, 0, 0, o); CHECK(bc_link_decode_diag_info(o, n, &i) && i.id == R->id, "ride recording: LIST still answered");
    while (bc_diag_srv_next(&s, o, sizeof o, 1, 0)) {}
    bc_diag_srv_set_link(&s, 185, false);
    bc_diag_chunk_req_t q = { R->id, 0, 155 }; uint8_t m[BC_LINK_MAX]; n = bc_link_encode_diag_chunk_req(&q, m, sizeof m, 1, 0); bc_diag_srv_write(&s, m, n);
    CHECK(bc_diag_srv_chunk_next(&s), "after the ride: a chunk is due (the app layer paces it)");
    bc_diag_chunk_t c; n = bc_diag_srv_next(&s, o, sizeof o, 1, 0); CHECK(bc_link_decode_diag_chunk(o, n, &c) && c.len == 155, "after the ride: chunk sent");
    CHECK(!bc_diag_pace_ok(1000, 900, true, true) && bc_diag_pace_ok(1100, 900, true, true) && !bc_diag_pace_ok(5000, 0, true, false) && bc_diag_pace_ok(5, 0, false, true),
          "pacing: >= %u ms between chunks and only with link room", BC_DIAG_CHUNK_GAP_MS);
}

/* iOS -> firmware: the exact bytes Cyclift's encoder produces (DiagTransferTests / DiagFirmwareVectorTests assert the Swift
   encoder emits these) go through the firmware parser and server */
static size_t unhex(const char *h, uint8_t *b) { size_t n = 0; while (*h) { while (*h == ' ') h++; if (!*h) break; unsigned v; sscanf(h, "%2x", &v); b[n++] = (uint8_t)v; h += 2; } return n; }
static void test_ios_requests(void)
{
    uint8_t b[64]; size_t n;
    n = unhex("80 00 01 00 00 00 00 00", b); CHECK(bc_link_decode_diag_list_req(b, n), "iOS DIAG_LIST_REQ parses");
    bc_diag_chunk_req_t q;
    n = unhex("83 00 02 00 00 00 00 00 01 04 07 00 00 00 02 04 40 01 00 00 03 02 A0 00", b);
    CHECK(bc_link_decode_diag_chunk_req(b, n, &q) && q.id == 7 && q.offset == 320 && q.max_len == 160, "iOS (old) CHUNK_REQ id 7 off 320 max 160 parses");
    n = unhex("83 00 03 00 00 00 00 00 01 04 07 00 00 00 02 04 00 00 00 00 03 02 9B 00", b);
    CHECK(bc_link_decode_diag_chunk_req(b, n, &q) && q.id == 7 && q.offset == 0 && q.max_len == 155, "iOS CHUNK_REQ at MTU 185 (max_len 155) parses");
    n = unhex("83 00 04 00 00 00 00 00 01 04 07 00 00 00 02 04 90 00 00 00 03 02 48 00", b);
    CHECK(bc_link_decode_diag_chunk_req(b, n, &q) && q.offset == 144 && q.max_len == 72, "iOS CHUNK_REQ at MTU 100 (max_len 72) parses");
    bc_diag_ack_t a; n = unhex("85 00 05 00 00 00 00 00 01 04 07 00 00 00 02 04 26 39 F4 CB", b);
    CHECK(bc_link_decode_diag_ack(b, n, &a) && a.id == 7 && a.crc == 0xCBF43926u, "iOS DIAG_ACK parses");
    /* end to end through the server with the fixture store: the iOS ACK of the real report marks it sent only on a crc match */
    fx_store_init(); bc_diag_srv_t s; fx_srv(&s, 185, false); uint8_t o[BC_LINK_MAX]; bc_diag_info_t i;
    n = unhex("83 00 03 00 00 00 00 00 01 04 07 00 00 00 02 04 00 00 00 00 03 02 9B 00", b); bc_diag_srv_write(&s, b, n);
    bc_diag_chunk_t c; size_t k = bc_diag_srv_next(&s, o, sizeof o, 1, 0);
    CHECK(bc_link_decode_diag_chunk(o, k, &c) && c.len == 155 && k == 180 && !memcmp(c.data, FX_TXT, 155), "iOS request at MTU 185 -> a full 180-byte chunk");
    bc_diag_ack_t ack = { 7, FX_IDX.r[0].crc ^ 0x10 }; n = bc_link_encode_diag_ack(&ack, b, sizeof b, 9, 0); bc_diag_srv_write(&s, b, n);
    k = bc_diag_srv_next(&s, o, sizeof o, 1, 0); CHECK(bc_link_decode_diag_info(o, k, &i) && i.state == 0 && FX_IDX.r[0].state == 0, "ACK with a wrong crc: report stays pending");
    ack.crc = FX_IDX.r[0].crc; n = bc_link_encode_diag_ack(&ack, b, sizeof b, 10, 0); bc_diag_srv_write(&s, b, n);
    k = bc_diag_srv_next(&s, o, sizeof o, 1, 0); CHECK(bc_link_decode_diag_info(o, k, &i) && i.state == 1 && FX_IDX.r[0].state == 1, "ACK with the matching crc: marked sent");
}

/* firmware with the cap + an app that never speaks DIAG (older Cyclift): the board keeps every report, across restarts, and
   never deletes an unsent one to make room */
static void test_old_app_keeps_reports(void)
{
    bc_diag_index_t x; memset(&x, 0, sizeof x); x.next_id = 1;
    for (int i = 0; i < 5; i++) { bc_diag_info_t *r = &x.r[x.n++]; r->id = x.next_id++; r->size = 6000; r->crc = (uint32_t)i; r->kind = 1; }
    uint8_t b[1200]; bc_diag_index_t y;
    for (int boot = 0; boot < 20; boot++) {   /* 20 restarts with phone connections that send only LIVE/profile traffic */
        size_t n = bc_diag_index_encode(&x, b, sizeof b); if (!bc_diag_index_decode(b, n, &y)) { CHECK(0, "index decode at boot %d", boot); break; }
        x = y;
        int room = bc_diag_index_make_room(&x, 6000);
        if (room >= 0) { CHECK(0, "an unsent report would be deleted"); break; }
        if (room == -1) { bc_diag_info_t *r = &x.r[x.n++]; r->id = x.next_id++; r->size = 6000; r->kind = 4; } else x.not_stored++;
    }
    CHECK(bc_diag_index_pending(&x) == x.n && x.r[0].id == 1 && x.not_stored > 0, "old app: %d reports kept pending after 20 boots, oldest id 1 still there, %lu not stored", x.n, (unsigned long)x.not_stored);
}

/* ------------------------------------------------------------------ boot modes */
static void test_boot(void)
{
    bc_boot_rtc_t r; memset(&r, 0xA5, sizeof r); bc_boot_plan_t p;
    bc_boot_plan(&r, BC_RST_POWERON, 0, &p); CHECK(!p.rtc_was_valid && p.mode == BC_BOOT_NORMAL && r.crash_streak == 0, "power-on with garbage RTC: normal");
    bc_boot_mark(&r, BC_SS_POWER); bc_boot_plan(&r, BC_RST_PANIC, 0, &p); CHECK(p.crashed && p.mode == BC_BOOT_NORMAL && p.suspect == BC_SS_POWER && r.crash_streak == 1 && !p.skip, "crash 1: normal, suspect power meter (not skipped in a normal boot)");
    bc_boot_mark(&r, BC_SS_RUNNING); bc_boot_plan(&r, BC_RST_PANIC, 0, &p); CHECK(p.mode == BC_BOOT_NORMAL && r.crash_streak == 2 && p.suspect == BC_SS_NONE, "crash 2 after start-up: normal, no suspect");
    bc_boot_plan(&r, BC_RST_WDT, 0, &p); CHECK(p.mode == BC_BOOT_RECOVERY && r.crash_streak == 3, "crash 3 (watchdog): RECOVERY");
    bc_boot_plan(&r, BC_RST_SW, 0, &p); CHECK(p.mode == BC_BOOT_NORMAL, "software restart without a request: normal start again");
    for (int k = 0; k < 3; k++) bc_boot_plan(&r, BC_RST_PANIC, 0, &p);
    CHECK(p.mode == BC_BOOT_RECOVERY, "three more crashes: recovery");
    bc_boot_request_staged(&r); bc_boot_plan(&r, BC_RST_SW, 0, &p); CHECK(p.mode == BC_BOOT_STAGED && p.skip == 0 && r.staged_fails == 0 && r.request == 0, "RESTART & DIAGNOSE: staged boot, nothing skipped yet");
    bc_boot_mark(&r, BC_SS_PHONE); bc_boot_mark(&r, BC_SS_WIFI); bc_boot_mark(&r, BC_SS_CENTRAL); bc_boot_mark(&r, BC_SS_POWER);
    bc_boot_plan(&r, BC_RST_PANIC, 0, &p); CHECK(p.mode == BC_BOOT_STAGED && p.newly_skipped && p.skip == BC_SS_BIT(BC_SS_POWER) && r.staged_fails == 1, "staged: crash while the power meter starts -> next boot skips it");
    bc_boot_mark(&r, BC_SS_PHONE); bc_boot_plan(&r, BC_RST_PANIC, 0, &p); CHECK(p.mode == BC_BOOT_STAGED && p.skip == (BC_SS_BIT(BC_SS_POWER) | BC_SS_BIT(BC_SS_PHONE)) && r.staged_fails == 2, "staged: then the phone link -> both skipped");
    bc_boot_mark(&r, BC_SS_DISPLAY); bc_boot_plan(&r, BC_RST_PANIC, 0, &p); CHECK(p.mode == BC_BOOT_RECOVERY && !(p.skip & BC_SS_BIT(BC_SS_DISPLAY)), "third staged failure -> RECOVERY (display is never skipped)");
    bc_boot_request_staged(&r); bc_boot_plan(&r, BC_RST_SW, 0, &p); bc_boot_mark(&r, BC_SS_HR);
    bc_boot_plan(&r, BC_RST_PANIC, 0, &p); bc_boot_mark(&r, BC_SS_RUNNING); bc_boot_stable(&r);
    CHECK(r.mode == BC_BOOT_NORMAL && r.crash_streak == 0 && (r.skip & BC_SS_BIT(BC_SS_HR)), "staged boot completes: normal next time, HR strap stays disabled this power cycle");
    bc_boot_plan(&r, BC_RST_SW, BC_SS_BIT(BC_SS_CSC) | BC_SS_BIT(BC_SS_DISPLAY), &p); CHECK(p.mode == BC_BOOT_NORMAL && p.skip == (BC_SS_BIT(BC_SS_HR) | BC_SS_BIT(BC_SS_CSC)), "NVS skip merged, never the display (0x%03X)", p.skip);
    bc_boot_unskip(&r, BC_SS_HR); bc_boot_plan(&r, BC_RST_SW, 0, &p); CHECK(p.skip == 0, "RETRY clears it");
    r.crash_streak = 99; CHECK(!bc_boot_rtc_valid(&r), "a changed field without a new CRC is invalid");
    bc_boot_plan(&r, BC_RST_PANIC, 0, &p); CHECK(p.crashed && !p.rtc_was_valid && p.mode == BC_BOOT_NORMAL && r.crash_streak == 1, "corrupted RTC + crash: counted as the first crash");
    CHECK(!strcmp(bc_subsys_name(BC_SS_POWER), "power meter") && !strcmp(bc_boot_mode_name(BC_BOOT_STAGED), "staged"), "names");
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    test_crc_and_records();
    test_ring();
    test_index();
    test_report();
    test_vectors();
    test_server();
    test_chunk_size_contract();
    test_fixture_transfers();
    test_ios_requests();
    test_old_app_keeps_reports();
    test_boot();
    printf("test_bc_diag: %d checks, %d failed\n", checks, fails);
    return fails ? 1 : 0;
}
