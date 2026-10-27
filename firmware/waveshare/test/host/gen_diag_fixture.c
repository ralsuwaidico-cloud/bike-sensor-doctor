/*
 * Link 1.2.3 cross-test fixture generator. Everything in the fixture is produced by the FIRMWARE's own code: the report by
 * bc_diag_report_build (diag_fixture.h), every board reply by the real transfer server (bc_diag_srv_*) and codec (bc_link.c),
 * at the ATT MTUs 23, 100, 185, 247 and 517. The phone requests are encoded with the firmware codec too; the iOS tests assert
 * that Cyclift's encoder produces the SAME bytes, decode every board reply, reassemble the report and verify its CRC-32.
 *
 *   gen_diag_fixture OUT.json OUT.swift          write the fixture (JSON + the same JSON embedded in a Swift file)
 *   gen_diag_fixture --check IN.json IN.swift     regenerate and compare (make: fails when the committed fixture is stale)
 */
#include "diag_fixture.h"
#include <stdlib.h>

static char *J; static size_t JN, JCAP;
static void put(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
#include <stdarg.h>
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
static size_t chunk_req(uint8_t *m, uint32_t id, uint32_t off, uint16_t maxl, uint16_t seq)
{ bc_diag_chunk_req_t q = { id, off, maxl }; return bc_link_encode_diag_chunk_req(&q, m, BC_LINK_MAX, seq, 0); }

/* one phone write -> the board's reply (exactly one is due after each request in this protocol) */
static size_t ask(bc_diag_srv_t *s, const uint8_t *req, size_t rn, uint8_t *rep, uint16_t seq)
{
    bc_diag_srv_write(s, req, rn);
    return bc_diag_srv_next(s, rep, BC_LINK_MAX, seq, 0x1000u + seq);
}
static void pair(const char *name, const uint8_t *req, size_t rn, const uint8_t *rep, size_t pn)
{
    put("\"%s\": {\"request\": ", name); b64(req, rn); put(", \"reply\": "); b64(rep, pn); put("}");
}

static void generate(void)
{
    JN = 0; if (!J) { JCAP = 1 << 18; J = malloc(JCAP); }
    fx_store_init();
    const bc_diag_info_t *R = &FX_IDX.r[0];
    uint8_t m[BC_LINK_MAX], o[BC_LINK_MAX]; size_t n, k;
    put("{\n\"generator\": \"firmware/waveshare/test/host/gen_diag_fixture.c (firmware 0.7.3 report builder + Link 1.2.3 server)\",\n");
    put("\"chunk_overhead\": %d, \"link_max\": %d, \"att_notify_overhead\": %d,\n", BC_DIAG_CHUNK_OVERHEAD, BC_LINK_MAX, BC_ATT_NOTIFY_OVERHEAD);
    put("\"report\": {\"id\": %lu, \"size\": %lu, \"crc32\": %lu, \"kind\": %u, \"summary\": \"%s\", \"firmware\": \"%s\", \"created\": %lu, \"text\": ",
        (unsigned long)R->id, (unsigned long)R->size, (unsigned long)R->crc, R->kind, R->summary, R->fw, (unsigned long)R->epoch_s);
    b64((const uint8_t *)FX_TXT, FX_LEN); put("},\n");

    /* INFO characteristic values: 0.7.3 (cap 0x400) and 0.7.2 (no cap) — capability negotiation */
    bc_info_t inf = { .ver_major = BC_LINK_VER_MAJOR, .ver_minor = BC_LINK_VER_MINOR, .max_msg = BC_LINK_MAX, .has_device_id = true,
                      .caps = BC_CAP_LIVE | BC_CAP_GPS_IN | BC_CAP_HR_IN | BC_CAP_WEATHER_IN | BC_CAP_RIDE_CTRL | BC_CAP_TIME_SYNC |
                              BC_CAP_RIDE_SYNC | BC_CAP_WIFI_PROV | BC_CAP_PROFILE_SYNC | BC_CAP_SETTINGS | BC_CAP_DIAG_XFER };
    memcpy(inf.device_id, (uint8_t[6]){ 0x9A, 0x3C, 0x11, 0x22, 0x33, 0x44 }, 6);
    snprintf(inf.fw, sizeof inf.fw, "0.7.3"); snprintf(inf.name, sizeof inf.name, "BikeComputer");
    n = bc_link_encode_info(&inf, o, sizeof o); put("\"info_073\": "); b64(o, n); put(",\n");
    inf.caps &= ~(uint32_t)BC_CAP_DIAG_XFER; snprintf(inf.fw, sizeof inf.fw, "0.7.2");
    n = bc_link_encode_info(&inf, o, sizeof o); put("\"info_072\": "); b64(o, n); put(",\n");
    bc_diag_ready_t rd = { (uint8_t)bc_diag_index_pending(&FX_IDX), FX_IDX.r[FX_IDX.n - 1].id };
    n = bc_link_encode_diag_ready(&rd, o, sizeof o, 1, 0x500); put("\"diag_ready\": "); b64(o, n); put(",\n");

    /* LIST */
    bc_diag_srv_t s; fx_srv(&s, 185, false);
    n = bc_link_encode_diag_list_req(m, sizeof m, 1, 0); bc_diag_srv_write(&s, m, n);
    put("\"list\": {\"request\": "); b64(m, n); put(", \"replies\": [");
    for (uint16_t q = 0; (k = bc_diag_srv_next(&s, o, sizeof o, (uint16_t)(2 + q), 0x1000u + q)) > 0; q++) { put(q ? ", " : ""); b64(o, k); }
    put("]},\n");

    /* phone-built vectors (the iOS encoder must produce exactly these bytes; the C test feeds them to the board parser) */
    put("\"phone_vectors\": [");
    n = bc_link_encode_diag_list_req(m, sizeof m, 1, 0); put("{\"type\": \"list\", \"seq\": 1, \"bytes\": "); b64(m, n); put("}");
    n = chunk_req(m, 7, 320, 160, 2); put(", {\"type\": \"chunk\", \"id\": 7, \"offset\": 320, \"max_len\": 160, \"seq\": 2, \"bytes\": "); b64(m, n); put("}");
    n = chunk_req(m, 7, 0, 155, 3); put(", {\"type\": \"chunk\", \"id\": 7, \"offset\": 0, \"max_len\": 155, \"seq\": 3, \"bytes\": "); b64(m, n); put("}");
    n = chunk_req(m, 7, 144, 72, 4); put(", {\"type\": \"chunk\", \"id\": 7, \"offset\": 144, \"max_len\": 72, \"seq\": 4, \"bytes\": "); b64(m, n); put("}");
    { bc_diag_ack_t a = { 7, 0xCBF43926u, 0 }; n = bc_link_encode_diag_ack(&a, m, sizeof m, 5, 0); }
    put(", {\"type\": \"ack\", \"id\": 7, \"crc32\": %lu, \"seq\": 5, \"bytes\": ", 0xCBF43926ul); b64(m, n); put("}");
    put("],\n");

    /* the whole report at each MTU: what the phone asks, what the board answers */
    static const uint16_t MTUS[] = { 23, 100, 185, 247, 517 };
    put("\"transfers\": [\n");
    for (size_t t = 0; t < sizeof MTUS / sizeof *MTUS; t++) {
        uint16_t mtu = MTUS[t], pml = fx_phone_max_len(mtu);
        fx_srv(&s, mtu, false);
        put("%s{\"att_mtu\": %u, \"phone_max_len\": %u, \"data_max\": %u", t ? ",\n" : "", mtu, pml, bc_diag_chunk_data_max(pml, mtu));
        if (!pml) {   /* Cyclift does not ask on such a link; a phone that asks anyway (max_len 160) gets DIAG_ERR 5 */
            n = chunk_req(m, R->id, 0, 160, 1); k = ask(&s, m, n, o, 1);
            put(", \"noncompliant\": {\"request\": "); b64(m, n); put(", \"reply\": "); b64(o, k); put("}}");
            continue;
        }
        put(", \"chunks\": [");
        uint32_t off = 0; uint16_t seq = 1; bool last = false;
        while (!last) {
            n = chunk_req(m, R->id, off, pml, seq); k = ask(&s, m, n, o, (uint16_t)(100 + seq));
            bc_diag_chunk_t c; if (!bc_link_decode_diag_chunk(o, k, &c)) { fprintf(stderr, "chunk did not decode at %lu\n", (unsigned long)off); exit(2); }
            if (k + BC_ATT_NOTIFY_OVERHEAD > mtu || k > BC_LINK_MAX) { fprintf(stderr, "chunk too big for MTU %u: %zu\n", mtu, k); exit(2); }
            put("%s{\"offset\": %lu, \"len\": %u, \"last\": %s, \"request\": ", seq > 1 ? ",\n  " : "\n  ", (unsigned long)off, c.len, c.last ? "true" : "false");
            b64(m, n); put(", \"reply\": "); b64(o, k); put("}");
            off += c.len; last = c.last; seq++;
        }
        put("]}");
    }
    put("\n],\n");

    /* ACK, duplicates, end-of-report, errors */
    fx_srv(&s, 185, false);
    put("\"cases\": {\n");
    { bc_diag_ack_t a = { R->id, R->crc ^ 1u, 0 }; n = bc_link_encode_diag_ack(&a, m, sizeof m, 40, 0); k = ask(&s, m, n, o, 140); pair("ack_bad_crc", m, n, o, k); put(",\n"); }
    { bc_diag_ack_t a = { R->id, R->crc, 0 }; n = bc_link_encode_diag_ack(&a, m, sizeof m, 41, 0); k = ask(&s, m, n, o, 141); pair("ack_ok", m, n, o, k); put(",\n"); }
    fx_store_init(); fx_srv(&s, 185, false);
    n = chunk_req(m, R->id, 310, 155, 42); k = ask(&s, m, n, o, 142); pair("duplicate_first", m, n, o, k); put(",\n");
    k = ask(&s, m, n, o, 143); pair("duplicate_second", m, n, o, k); put(",\n");
    n = chunk_req(m, R->id, R->size, 155, 44); k = ask(&s, m, n, o, 144); pair("offset_at_end", m, n, o, k); put(",\n");
    n = chunk_req(m, 99, 0, 155, 45); k = ask(&s, m, n, o, 145); pair("err_unknown_id", m, n, o, k); put(",\n");
    n = chunk_req(m, R->id, R->size + 1, 155, 46); k = ask(&s, m, n, o, 146); pair("err_bad_offset", m, n, o, k); put(",\n");
    FX_READ_FAIL = true; n = chunk_req(m, R->id, 0, 155, 47); k = ask(&s, m, n, o, 147); pair("err_storage", m, n, o, k); put(",\n"); FX_READ_FAIL = false;
    for (int q = 0; q < 4; q++) { n = chunk_req(m, R->id, (uint32_t)q * 155u, 155, (uint16_t)(48 + q)); bc_diag_srv_write(&s, m, n); }
    n = chunk_req(m, R->id, 4 * 155u, 155, 52); k = ask(&s, m, n, o, 152); pair("err_busy_pipeline", m, n, o, k); put(",\n");
    bc_diag_srv_reset(&s); bc_diag_srv_set_link(&s, 185, true);
    n = chunk_req(m, R->id, 0, 155, 53); k = ask(&s, m, n, o, 153); pair("err_busy_ride", m, n, o, k); put(",\n");
    bc_diag_srv_set_link(&s, 23, false);
    n = chunk_req(m, R->id, 0, 155, 54); k = ask(&s, m, n, o, 154); pair("err_mtu", m, n, o, k); put(",\n");
    { bc_diag_ack_t a = { 99, 1, 0 }; n = bc_link_encode_diag_ack(&a, m, sizeof m, 55, 0); bc_diag_srv_set_link(&s, 185, false); k = ask(&s, m, n, o, 155); pair("ack_unknown_id", m, n, o, k); }
    put("\n}\n}\n");
}

static char *slurp(const char *p, size_t *n)
{
    FILE *f = fopen(p, "rb"); if (!f) return NULL;
    fseek(f, 0, SEEK_END); long z = ftell(f); fseek(f, 0, SEEK_SET);
    char *b = malloc((size_t)z + 1); if (!b) { fclose(f); return NULL; }
    *n = fread(b, 1, (size_t)z, f); b[*n] = 0; fclose(f); return b;
}
static const char SWIFT_HEAD[] =
    "// GENERATED by firmware/waveshare/test/host/gen_diag_fixture.c from the firmware 0.7.3 report builder and Link 1.2.3\n"
    "// server. Do not edit: run `make fixture` in firmware/waveshare/test/host and copy both files. The same JSON is committed as\n"
    "// ios/BikeComputerTests/Fixtures/diag_fw_fixture.json (DiagFirmwareVectorTests checks that both copies agree).\n"
    "enum DiagFirmwareFixture {\n    static let json = #\"\"\"\n";
static const char SWIFT_TAIL[] = "\"\"\"#\n}\n";

int main(int argc, char **argv)
{
    bool check = argc == 4 && !strcmp(argv[1], "--check");
    if (argc != 3 && !check) { fprintf(stderr, "usage: %s OUT.json OUT.swift | --check IN.json IN.swift\n", argv[0]); return 2; }
    generate();
    size_t sn = strlen(SWIFT_HEAD) + JN + strlen(SWIFT_TAIL) + 1; char *sw = malloc(sn);
    snprintf(sw, sn, "%s%.*s%s", SWIFT_HEAD, (int)JN, J, SWIFT_TAIL);
    const char *pj = argv[check ? 2 : 1], *ps = argv[check ? 3 : 2];
    if (check) {
        size_t a = 0, b = 0; char *fj = slurp(pj, &a), *fs = slurp(ps, &b);
        bool ok = fj && fs && a == JN && !memcmp(fj, J, JN) && b == strlen(sw) && !memcmp(fs, sw, b);
        printf("gen_diag_fixture: committed fixture %s (%zu bytes JSON, report %lu bytes crc %08lX)\n", ok ? "matches the firmware" : "is STALE - run make fixture",
               JN, (unsigned long)FX_IDX.r[0].size, (unsigned long)FX_IDX.r[0].crc);
        free(fj); free(fs); free(sw); free(J);
        return ok ? 0 : 1;
    }
    FILE *f = fopen(pj, "wb"); if (!f) return 1;
    fwrite(J, 1, JN, f); fclose(f);
    f = fopen(ps, "wb"); if (!f) return 1;
    fputs(sw, f); fclose(f);
    printf("gen_diag_fixture: wrote %s (%zu bytes) and %s; report %lu bytes, crc32 %08lX\n", pj, JN, ps, (unsigned long)FX_IDX.r[0].size, (unsigned long)FX_IDX.r[0].crc);
    free(sw); free(J);
    return 0;
}
