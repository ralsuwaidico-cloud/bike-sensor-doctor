/*
 * Ride-priority measurement (firmware 0.7.3, Link 1.2.3): the REAL main/ble_link.c + main/ble_central.c on the fake NimBLE
 * with a radio model (12-block msys pool, a congested link that sends ONE notification per 30 ms connection event = 33/s,
 * MTU 185 negotiated by the phone, oversized notifications are violations). The app thread does what the app task does every
 * 250 ms: publish LIVE once per second, move phone writes into the Link 1.2.3 server (bc_diag_srv), and hand diag replies to
 * the link with the SAME gating as app_diag_next (bc_diag_srv_chunk_next + plat_phone_bulk_room + bc_diag_pace_ok).
 * The phone measures the arrival time of every LIVE frame.
 *
 * Phases on one connection (virtual time):
 *   A  40 s  no transfer                                   -> LIVE cadence baseline
 *   B  40 s  Cyclift pulling a report (1 request at a time) -> gated (0.7.3 final)
 *   C  40 s  an aggressive phone (4 requests pipelined)     -> gated
 *   (argv: seconds per phase [40], connection-event interval ms [30]; make prio-run runs 30 ms and a poor-RF 150 ms link)
 *   D  40 s  the same aggressive phone, gating OFF (what 0.7.3-pre did: every reply pushed as soon as the queue took it)
 * PASS: no violation; in B and C every LIVE frame arrives, the largest LIVE gap is within 150 ms of the baseline, and the
 * transfer makes progress. D is reported for comparison only.
 */
#include "fake_nimble.h"
#include "ble_central.h"
#include "ble_link.h"
#include "plat.h"
#include "bc_link.h"
#include "bc_diag.h"
#include <unistd.h>

void app_psvc_on_disconnect(void) {}
bool plat_device_id(uint8_t out[6]) { memset(out, 0xAB, 6); return true; }
void ble_store_config_init(void) {}
__attribute__((weak)) void diag_event(int type, int a, int b, int c) { (void)type; (void)a; (void)b; (void)c; }

/* ---- a large in-memory report (the transfer restarts at 0 when it completes, so it never runs dry) */
#define RSIZE 200000u
static uint8_t s_rep[RSIZE]; static bc_diag_index_t s_idx;
static const bc_diag_index_t *st_index(void *c) { (void)c; return &s_idx; }
static long st_read(void *c, uint32_t id, uint32_t off, uint8_t *b, size_t n) { (void)c; (void)id; if (off + n > RSIZE) return -1; memcpy(b, s_rep + off, n); return (long)n; }
static bool st_mark(void *c, uint32_t id) { (void)c; (void)id; return true; }

/* ---- phone side (runs in the fake radio's delivery callback = host thread) */
enum { PH_IDLE, PH_CYCLIFT, PH_AGGRESSIVE };
static volatile int s_phase_mode; static volatile bool s_measure;
static uint16_t H_LIVE, H_CTRL;
static uint32_t s_last_live, s_max_gap, s_lives; static uint64_t s_gap_sum;
static uint32_t s_pub[4096]; static uint32_t s_max_lat; static uint64_t s_lat_sum;   /* LIVE publish time by counter -> latency */
static uint32_t s_off, s_chunks, s_bytes, s_busy; static int s_outstanding; static uint16_t s_pseq;
static pthread_mutex_t s_pm = PTHREAD_MUTEX_INITIALIZER;
static void phone_ask(void)
{
    uint8_t m[BC_LINK_MAX];
    bc_diag_chunk_req_t q = { 7, s_off + (uint32_t)s_outstanding * 155u, 155 };   /* Cyclift on MTU 185: max_len 155 */
    if (q.offset >= RSIZE) q.offset = 0;
    size_t n = bc_link_encode_diag_chunk_req(&q, m, sizeof m, ++s_pseq, 0);
    s_outstanding++;
    fake_phone_write(H_CTRL, m, (uint16_t)n);
}
static void on_rx(uint16_t h, const uint8_t *b, uint16_t n, uint32_t t)
{
    pthread_mutex_lock(&s_pm);
    if (h == H_LIVE && n && b[0] == BC_MSG_LIVE) {
        bc_live_t L; uint32_t lat = 0;
        if (bc_link_decode_live(b, n, &L) && L.elapsed_s < 4096 && s_pub[L.elapsed_s]) lat = t - s_pub[L.elapsed_s];
        if (s_measure) { if (s_last_live) { uint32_t g = t - s_last_live; s_gap_sum += g; if (g > s_max_gap) s_max_gap = g; } s_lives++; s_lat_sum += lat; if (lat > s_max_lat) s_max_lat = lat; }
        s_last_live = t;
    } else if (h == H_CTRL && n && b[0] == BC_MSG_DIAG_CHUNK) {
        bc_diag_chunk_t c;
        if (bc_link_decode_diag_chunk(b, n, &c)) {
            if (s_outstanding) s_outstanding--;
            if (c.offset == s_off) { s_off += c.len; if (c.last || s_off >= RSIZE) s_off = 0; }
            if (s_measure) { s_chunks++; s_bytes += c.len; }
            int want = s_phase_mode == PH_AGGRESSIVE ? 4 : s_phase_mode == PH_CYCLIFT ? 1 : 0;
            while (s_outstanding < want) phone_ask();
        }
    } else if (h == H_CTRL && n && b[0] == BC_MSG_DIAG_ERR) {
        if (s_outstanding) s_outstanding--;
        s_busy++;
    }
    pthread_mutex_unlock(&s_pm);
}

/* ---- app thread (the app task: 250 ms pump, LIVE once per second) */
static volatile bool s_stop, s_gated = true; static bc_diag_srv_t s_srv;
static uint32_t s_last_chunk; static bool s_chunk_sent; static uint64_t s_held, s_paced;
static void *app_thread(void *p)
{
    (void)p;
    uint32_t next_live = fake_now(), live_no = 0;
    uint8_t held[BC_LINK_MAX]; size_t held_len = 0; uint16_t seq = 0;
    while (!s_stop) {
        uint32_t now = fake_now();
        if ((int32_t)(now - next_live) >= 0) {
            next_live += 1000;
            bc_live_t L; memset(&L, 0, sizeof L); L.power_ok = true; L.power_w = 200; L.cad_ok = true; L.cadence_rpm = 90;
            live_no = (live_no + 1) % 4096; L.elapsed_s = live_no;
            pthread_mutex_lock(&s_pm); s_pub[live_no] = fake_now(); pthread_mutex_unlock(&s_pm);
            plat_phone_publish_live(&L);
        }
        uint8_t chr, b[BC_LINK_MAX]; int n;
        while ((n = plat_phone_take_svc(&chr, b, sizeof b)) > 0) if (chr == 0) bc_diag_srv_write(&s_srv, b, (size_t)n);
        plat_phone_status_t ps; plat_phone_status(&ps);
        if (!ps.svc_ready) { bc_diag_srv_reset(&s_srv); held_len = 0; fake_sleep_v(250); continue; }
        if (held_len) { if (plat_phone_notify_svc(0, held, held_len)) held_len = 0; }
        for (int i = 0; i < 8 && !held_len; i++) {          /* app_psvc: NOTIFY_PER_PUMP 8 */
            bc_diag_srv_set_link(&s_srv, ps.att_mtu, false);
            if (s_gated && bc_diag_srv_chunk_next(&s_srv)) {
                bool room = plat_phone_bulk_room();
                if (!bc_diag_pace_ok(now, s_last_chunk, s_chunk_sent, room)) { if (room) s_paced++; else s_held++; break; }
            }
            size_t m = bc_diag_srv_next(&s_srv, b, sizeof b, ++seq, now);
            if (!m) break;
            if (b[0] == BC_MSG_DIAG_CHUNK) { s_last_chunk = now; s_chunk_sent = true; }
            if (!plat_phone_notify_svc(0, b, m)) { memcpy(held, b, m); held_len = m; }
        }
        fake_sleep_v(250);
    }
    return NULL;
}

typedef struct { const char *name; uint32_t lives, max_gap, mean_gap, chunks, bytes, fails, enomem, busy; uint64_t held, paced; uint32_t mean_lat, max_lat; } res_t;
static res_t phase(const char *name, int mode, bool gated, uint32_t ms)
{
    pthread_mutex_lock(&s_pm);
    s_gated = gated; s_phase_mode = mode; s_lives = 0; s_max_gap = 0; s_gap_sum = 0; s_chunks = 0; s_bytes = 0; s_busy = 0; s_max_lat = 0; s_lat_sum = 0;
    int want = mode == PH_AGGRESSIVE ? 4 : mode == PH_CYCLIFT ? 1 : 0;
    while (s_outstanding < want) phone_ask();
    s_measure = true;
    pthread_mutex_unlock(&s_pm);
    plat_phone_status_t ps0; plat_phone_status(&ps0); uint64_t en0 = g_fstats.notify_enomem, h0 = s_held, p0 = s_paced;
    fake_sleep_v(ms);
    pthread_mutex_lock(&s_pm); s_measure = false; s_phase_mode = PH_IDLE; pthread_mutex_unlock(&s_pm);
    plat_phone_status_t ps1; plat_phone_status(&ps1);
    res_t r = { name, s_lives, s_max_gap, s_lives > 1 ? (uint32_t)(s_gap_sum / (s_lives - 1)) : 0, s_chunks, s_bytes, ps1.notify_fails - ps0.notify_fails,
                (uint32_t)(g_fstats.notify_enomem - en0), s_busy, s_held - h0, s_paced - p0, s_lives ? (uint32_t)(s_lat_sum / s_lives) : 0, s_max_lat };
    fake_sleep_v(3000);                                      /* drain outstanding requests between phases */
    pthread_mutex_lock(&s_pm); s_outstanding = 0; pthread_mutex_unlock(&s_pm);
    bc_diag_srv_reset(&s_srv);
    return r;
}

static int s_hold_ms;
static void *phone_thread(void *p) { (void)p; fake_phone_cycle(true, s_hold_ms, 0); return NULL; }

int main(int argc, char **argv)
{
    uint32_t ms = argc > 1 ? (uint32_t)atoi(argv[1]) * 1000u : 40000u;
    for (uint32_t i = 0; i < RSIZE; i++) s_rep[i] = (uint8_t)("0123456789abcdef[header]\n"[i % 25]);
    s_idx.n = 1; s_idx.r[0].id = 7; s_idx.r[0].size = RSIZE; s_idx.r[0].crc = bc_crc32(0, s_rep, RSIZE);
    bc_diag_store_t st = { NULL, st_index, st_read, st_mark }; bc_diag_srv_init(&s_srv, &st);
    int itvl = argc > 2 ? atoi(argv[2]) : 30;
    g_fake.radio = true; g_fake.radio_itvl_ms = itvl; g_fake.radio_per_event = 1; g_fake.phone_mtu = 185; g_fake.strict_mtu = true; g_fake.on_phone_rx = on_rx;
    g_fake.speed = 5;                                        /* slower virtual clock: thread jitter stays small next to 30 ms events */
    if (getenv("BLEHOST_SPEED")) g_fake.speed = atoi(getenv("BLEHOST_SPEED"));
    ble_central_start(true);
    fake_start_world();
    plat_phone_set_enabled(true);
    s_hold_ms = (int)(4 * (ms + 3000) + 20000);
    H_LIVE = fake_server_handle(1); H_CTRL = fake_server_handle(3);
    pthread_t a, ph; pthread_create(&a, NULL, app_thread, NULL); pthread_create(&ph, NULL, phone_thread, NULL);
    for (int w = 0; w < 200; w++) { plat_phone_status_t ps; plat_phone_status(&ps); if (ps.svc_ready && ps.att_mtu == 185) break; fake_sleep_v(50); }
    plat_phone_status_t ps; plat_phone_status(&ps);
    printf("phone connected: encrypted + subscribed, negotiated ATT MTU %u (board reads it from BLE_GAP_EVENT_MTU / ble_att_mtu)\n", ps.att_mtu);
    /* the INFO characteristic as the real ble_link.c serves it: Link 1.2 with cap 0x400 DIAG_XFER */
    uint8_t ib[BC_LINK_MAX]; int in = fake_server_read(0, ib, sizeof ib); bc_info_t info;
    bool info_ok = in > 0 && bc_link_decode_info(ib, (size_t)in, &info) && (info.caps & BC_CAP_DIAG_XFER) && info.max_msg == BC_LINK_MAX;
    printf("INFO read: %d bytes, link %u.%u, caps 0x%03lX (DIAG_XFER 0x400 %s), max_msg %u\n", in, info.ver_major, info.ver_minor, (unsigned long)info.caps,
           info.caps & BC_CAP_DIAG_XFER ? "advertised" : "MISSING", info.max_msg);
    if (!info_ok) fake_violation("INFO does not advertise DIAG_XFER");
    fake_sleep_v(3000);
    res_t R[4];
    R[0] = phase("A no transfer", PH_IDLE, true, ms);
    R[1] = phase("B Cyclift pull, gated", PH_CYCLIFT, true, ms);
    R[2] = phase("C 4 pipelined, gated", PH_AGGRESSIVE, true, ms);
    R[3] = phase("D 4 pipelined, NO gating", PH_AGGRESSIVE, false, ms);
    s_stop = true; pthread_join(a, NULL);
    fake_stop_world();
    printf("\nLIVE priority on a congested link (1 notification per %d ms connection event = %d/s, msys 12), %u s per phase (virtual)\n", itvl, 1000 / itvl, ms / 1000);
    printf("  %-26s %5s %9s %8s %9s %8s %7s %8s %7s %7s %6s\n", "phase", "LIVE", "interval", "max int", "latency", "max lat", "chunks", "bytes/s", "nfails", "ENOMEM", "held");
    for (int i = 0; i < 4; i++)
        printf("  %-26s %5u %7u ms %5u ms %6u ms %5u ms %7u %8u %7u %7u %6llu\n", R[i].name, R[i].lives, R[i].mean_gap, R[i].max_gap, R[i].mean_lat, R[i].max_lat,
               R[i].chunks, R[i].bytes * 1000u / ms, R[i].fails, R[i].enomem, (unsigned long long)R[i].held);
    printf("  (latency = LIVE handed to the link by the app -> received by the phone; interval = between two LIVE frames at the phone)\n");
    printf("  oversized notifications %llu, violations: %s\n", (unsigned long long)g_fstats.oversize_notifies, g_fstats.first_violation[0] ? g_fstats.first_violation : "none");
    uint32_t want = ms / 1000;
    bool ok = !g_fstats.first_violation[0] && g_fstats.oversize_notifies == 0 && R[0].lives >= want - 1;
    /* with a transfer a LIVE frame may only wait behind chunks the radio already holds (at most two connection events), and
       on average it must be as fast as without a transfer (within half an event) */
    uint32_t bound = R[0].max_lat + 2u * (uint32_t)itvl + 100, mbound = R[0].mean_lat + (uint32_t)itvl / 2 + 20;
    for (int i = 1; i <= 2; i++) ok = ok && R[i].lives + 1 >= R[0].lives && R[i].max_lat <= bound && R[i].mean_lat <= mbound && R[i].chunks > 20 && R[i].enomem == 0;
    printf("  criterion (B, C): every LIVE frame delivered, mean latency <= %u ms, max latency <= %u ms, no ENOMEM; D (no gating) for comparison: %s\n",
           mbound, bound, R[3].mean_lat <= mbound && R[3].max_lat <= bound ? "would pass" : "would FAIL");
    printf("RESULT %s\n", ok ? "PASS" : "FAIL");
    fflush(stdout);
    _exit(ok ? 0 : 1);
}
