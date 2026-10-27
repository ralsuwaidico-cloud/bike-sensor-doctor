/*
 * BLE glue stress test: the REAL main/ble_central.c + main/ble_link.c (whichever firmware tree FW= points to) on the fake
 * NimBLE world (fake/fake_nimble.c), with the same task layout as the device: NimBLE host thread (callbacks), the BLE
 * manager task (mgr_task: tick every 500 ms, link tick every 100 ms), the esp_timer task (MTU fallback), an app/UI thread
 * that reads the snapshots and queues phone messages every 250 ms like app_psvc, a phone thread doing N connect /
 * encrypt / subscribe / write / disconnect cycles, and a chaos thread that moves the meter in and out of range.
 * Fault injection: disconnects in the middle of any GATT procedure, ATT errors, ENOMEM, no MTU answer, CCCD read-back
 * mismatches and failures, malformed / short / long notifications and notifications on other handles, connect failures.
 * Built with ASan+UBSan (make) or TSan (make tsan). Exit 0 = no sanitizer error and no invariant violation.
 */

#include "fake_nimble.h"
#include "ble_central.h"
#include "ble_link.h"
#include "plat.h"
#include "bc_link.h"
#include "bc_pipe.h"
#include "bc_link13.h"
#include "bc_cmirror.h"
#include "bc_diag.h"
#include <unistd.h>

/* what ble_link.c needs from the app / platform */
void app_psvc_on_disconnect(void) {}
bool plat_device_id(uint8_t out[6]) { memset(out, 0xAB, 6); return true; }
/* 0.7.4: device side lives in diag_esp.c; here Bluetooth is unavailable only when the stack failed to start */
__attribute__((weak)) bool plat_bt_unavailable(char *reason, size_t cap) { (void)reason; (void)cap; return false; }
void ble_store_config_init(void) {}
int fake_mbufs_live(void);
/* 0.7.3 hooks (weak so the 0.7.2 tree links too) */
__attribute__((weak)) void diag_event(int type, int a, int b, int c) { (void)type; (void)a; (void)b; (void)c; }

/* 0.7.5 Link 1.3 traffic: the phone writes well-formed 1.3 messages (seq 0xBEEF) among the fuzz; the app thread decodes
   every one it takes (a valid one must decode), feeds coach messages to the real coach mirror, and pushes paced 180-byte
   RIDEQ_CHUNK notifications (bulk) while the meter streams - LIVE and sensor traffic must be unaffected */
#define VALID_SEQ 0xBEEF
size_t fake_link13_valid(uint8_t *b, size_t cap, uint32_t r)
{
    switch (r % 6) {
    case 0: { bc_hello_t h = { 1, 3, BC_CAPS_LINK13, "stress" }; return bc_link_encode_hello(&h, b, cap, VALID_SEQ, r); }
    case 1: { bc_coach_state_t s; memset(&s, 0, sizeof s); s.workout_id = 9; s.seq = (uint16_t)r; s.kind = BC_TK_POWER; s.lo = 140; s.hi = 155; s.instruction = (uint8_t)(r % 17);
              s.has = 0x3FFFF; return bc_link_encode_coach_state(&s, b, cap, VALID_SEQ, r); }
    case 2: { bc_cseg_t g[3] = { { 300, 11, 1, 100, 140, 80, 90 }, { 600, 2, 1, 140, 155, 80, 90 }, { 0xFFFF, 12, 2, 100, 125, 0, 0 } };
              bc_coach_plan_msg_t p; memset(&p, 0, sizeof p); p.workout_id = 9; p.parts = 1; p.nseg = 3; memcpy(p.seg, g, sizeof g); p.head = true; p.total_segments = 3;
              p.plan_crc32 = bc_cm_plan_crc(g, 3); p.t0_elapsed_s = BC_COACH_T0_RIDE_START; snprintf(p.name, sizeof p.name, "stress plan");
              return bc_link_encode_coach_plan(&p, b, cap, VALID_SEQ, r); }
    case 3: { bc_diag_chunk_req_t q = { 7, r % 4096, 155 }; return bc_link_encode_rideq_chunk_req(&q, b, cap, VALID_SEQ, r); }
    case 4: { bc_rideq_ack_t a = { 7, r, ~r, 1 }; return bc_link_encode_rideq_ack(&a, b, cap, VALID_SEQ, r); }
    default: { bc_storage_clean_req_t c = { (uint8_t)(r & 7) }; return bc_link_encode_storage_clean_req(&c, b, cap, VALID_SEQ, r); }
    }
}
static uint64_t s_l13_valid, s_l13_bad, s_l13_fuzz, s_bulk, s_cm_applied;
static bc_cmirror_t s_cm;
static void take_link13(const uint8_t *b, size_t n)
{
    if (n < BC_LINK_HDR) return;
    bool valid = (uint16_t)(b[2] | (b[3] << 8)) == VALID_SEQ;
    bool ok = true;
    switch (b[0]) {
    case 0x08: { bc_hello_t h; ok = bc_link_decode_hello(b, n, &h); break; }
    case 0xB0: { bc_coach_plan_msg_t p; ok = bc_link_decode_coach_plan(b, n, &p); if (ok) { uint16_t np; bc_cm_plan_part(&s_cm, &p, &np); } break; }
    case 0xB2: { bc_coach_state_t s; ok = bc_link_decode_coach_state(b, n, &s); if (ok && bc_cm_state(&s_cm, &s, hw_millis())) s_cm_applied++; break; }
    case 0xB3: { bc_coach_end_t e; ok = bc_link_decode_coach_end(b, n, &e); break; }
    case 0x93: { bc_diag_chunk_req_t q; ok = bc_link_decode_rideq_chunk_req(b, n, &q); break; }
    case 0x95: { bc_rideq_ack_t a; ok = bc_link_decode_rideq_ack(b, n, &a); break; }
    case 0xA2: { bc_storage_clean_req_t c; ok = bc_link_decode_storage_clean_req(b, n, &c); break; }
    default: return;
    }
    if (valid) { s_l13_valid++; if (!ok) { s_l13_bad++; fake_violation("well-formed Link 1.3 message type 0x%02X rejected", b[0]); } }
    else s_l13_fuzz++;
}

static volatile bool s_stop;
static const uint8_t MAC[6] = { 0x11, 0x22, 0x33, 0x44, 0x55, 0x66 };
static uint64_t s_app_loops, s_snap_valid, s_retries, s_live, s_svc;

static void *app_thread(void *p)
{
    (void)p;
    uint32_t n = 0;
    while (!s_stop) {
        plat_sensors_t s; ble_central_snapshot(&s);
        if (s.link[PLAT_SENS_POWER].stage == BC_STG_VALID) s_snap_valid++;
        if (s.link[PLAT_SENS_POWER].stage > BC_STG_ERROR) fake_violation("snapshot stage out of range %u", s.link[0].stage);
        plat_phone_status_t ps; plat_phone_status(&ps);
        uint8_t chr, b[BC_LINK_MAX]; int tn; while ((tn = plat_phone_take_svc(&chr, b, sizeof b)) > 0) { s_svc++; if (chr == 0) take_link13(b, (size_t)tn); }
        { bc_cm_view_t v; bc_cm_view(&s_cm, ps.svc_ready, hw_millis(), n, &v); (void)v; }
        static uint32_t last_bulk; static bool bulk_sent;
        if (ps.svc_ready && bc_diag_pace_ok(hw_millis(), last_bulk, bulk_sent, plat_phone_bulk_room())) {   /* 0.7.5: ride-queue chunks while the meter streams */
            bc_diag_chunk_t c; memset(&c, 0, sizeof c); c.id = 7; c.offset = n * 155u; c.len = 155; for (int i = 0; i < 155; i++) c.data[i] = (uint8_t)i;
            size_t m = bc_link_encode_rideq_chunk(&c, b, sizeof b, (uint16_t)n, hw_millis());
            if (plat_phone_notify_svc(0, b, m)) { s_bulk++; last_bulk = hw_millis(); bulk_sent = true; }
        }
        if (ps.svc_ready) {   /* like app_psvc: one SENSOR_DIAG per pump while the phone listens */
            bc_sensor_diag_t d; memset(&d, 0, sizeof d); d.sensor = 1; d.stage = s.link[0].stage; d.packets = s.link[0].packets;
            snprintf(d.err, sizeof d.err, "%s", s.link[0].err);
            size_t m = bc_link_encode_sensor_diag(&d, b, sizeof b, (uint16_t)n, hw_millis()); plat_phone_notify_svc(2, b, m);
        }
        bc_live_t L; memset(&L, 0, sizeof L); L.power_ok = s.power_ok; L.power_w = (uint16_t)s.watts; plat_phone_publish_live(&L); s_live++;
        plat_found_t f[8]; ble_central_found(PLAT_SENS_POWER, f, 8);
        /* UI actions that race the radio: RETRY (re-pair), pairing list on/off, standby on/off */
        if (n % 97 == 13) { ble_central_set_paired(PLAT_SENS_POWER, MAC, 0, "XDS-A001"); s_retries++; }
        if (n % 53 == 7) ble_central_scan_for(n % 2 ? PLAT_SENS_POWER : -1);
        if (n % 71 == 5) ble_central_set_standby(n % 3 == 0);
        if (n % 211 == 100) plat_phone_disconnect();
#ifndef BLEHOST_072
        if (n % 157 == 60) ble_central_set_disabled(PLAT_SENS_POWER, true);      /* 0.7.3 staged boot / RETRY racing the radio */
        if (n % 157 == 75) ble_central_set_disabled(PLAT_SENS_POWER, false);
        if (n % 263 == 30) plat_phone_set_enabled(false);
        if (n % 263 == 40) plat_phone_set_enabled(true);
#endif
        n++; s_app_loops++;
        fake_sleep_v(250);
    }
    return NULL;
}

static void *chaos_thread(void *p)
{
    (void)p;
    while (!s_stop) {
        fake_sleep_v(3000 + esp_random() % 9000);
        uint32_t r = esp_random() % 10;
        if (r < 2) g_fake.meter_in_range = !g_fake.meter_in_range;
        else if (r < 4) g_fake.meter_streams = !g_fake.meter_streams;     /* subscribed but silent: RESUBSCRIBE / RECONNECT paths */
        else { g_fake.meter_in_range = true; g_fake.meter_streams = true; }
    }
    return NULL;
}

int main(int argc, char **argv)
{
    int cycles = argc > 1 ? atoi(argv[1]) : 1000;
    g_fake.p_disconnect_per_proc = 25; g_fake.p_att_error = 20; g_fake.p_bad_packet = 60; g_fake.p_other_handle = 20;
    g_fake.p_cccd_read_mismatch = 15; g_fake.p_cccd_read_fail = 15; g_fake.p_no_mtu = 60; g_fake.p_conn_fail = 100; g_fake.p_enomem = 15;
    if (getenv("BLEHOST_SPEED")) g_fake.speed = atoi(getenv("BLEHOST_SPEED"));
#ifdef BLEHOST_072
    ble_central_start();                       /* 0.7.2 API */
#else
    ble_central_start(true);                   /* nimble_port_init (starts the clock), GATT registration, host + manager tasks */
#endif
    fake_start_world();
    plat_phone_set_enabled(true);
    ble_central_set_paired(PLAT_SENS_POWER, MAC, 0, "XDS-A001");
    pthread_t a, c; pthread_create(&a, NULL, app_thread, NULL); pthread_create(&c, NULL, chaos_thread, NULL);
    uint32_t t0 = fake_now();
    for (int i = 0; i < cycles; i++) {
        bool enc = esp_random() % 10 != 0;
        fake_phone_cycle(enc, (int)(200 + esp_random() % 3000), (int)(esp_random() % 6));
        if (i % 100 == 99) printf("  %d phone cycles, %u s virtual, meter connects %llu\n", i + 1, (fake_now() - t0) / 1000, (unsigned long long)g_fstats.connects);
    }
    s_stop = true; pthread_join(a, NULL); pthread_join(c, NULL);
    fake_stop_world();
    uint32_t dur = (fake_now() - t0) / 1000;
    printf("\nBLE glue stress: %d phone cycles in %u s (virtual)\n", cycles, dur);
    printf("  phone: %llu connects, %llu disconnects, %llu notifications sent by the board, %llu service msgs taken\n",
           (unsigned long long)g_fstats.phone_connects, (unsigned long long)g_fstats.phone_disconnects, (unsigned long long)g_fstats.phone_notifies, (unsigned long long)s_svc);
    printf("  meter: %llu connects, %llu disconnects, %llu GATT procedures (%llu refused ENOMEM), %llu CCCD writes, %llu notifications (%llu malformed), %llu MTU timeouts\n",
           (unsigned long long)g_fstats.connects, (unsigned long long)g_fstats.disconnects, (unsigned long long)g_fstats.procs, (unsigned long long)g_fstats.proc_enomem,
           (unsigned long long)g_fstats.cccd_writes, (unsigned long long)g_fstats.notifies_rx, (unsigned long long)g_fstats.bad_packets, (unsigned long long)g_fstats.mtu_timeouts);
    printf("  app: %llu snapshot loops (%llu with power VALID), %llu RETRY re-pairs, host-task events %llu\n",
           (unsigned long long)s_app_loops, (unsigned long long)s_snap_valid, (unsigned long long)s_retries, (unsigned long long)g_fstats.npl_events);
    printf("  Link 1.3: %llu well-formed phone messages decoded (%llu rejected), %llu fuzzed ones handled, %llu coach states applied, %llu 180-B RIDEQ_CHUNK notifications\n",
           (unsigned long long)s_l13_valid, (unsigned long long)s_l13_bad, (unsigned long long)s_l13_fuzz, (unsigned long long)s_cm_applied, (unsigned long long)s_bulk);
    printf("  stale-handle API calls %llu (refused ENOTCONN), mbufs still allocated %d\n", (unsigned long long)g_fstats.stale_conn_ops, fake_mbufs_live());
    printf("  INVARIANTS: host lock inside critical section %llu, sensor GATT ops on the phone connection %llu, non-CCCD writes to a sensor %llu\n",
           (unsigned long long)g_fstats.crit_lock_violations, (unsigned long long)g_fstats.foreign_gatt_ops, (unsigned long long)g_fstats.bad_writes);
    if (g_fstats.first_violation[0]) printf("  first violation: %s\n", g_fstats.first_violation);
    bool ok = !g_fstats.first_violation[0] && g_fstats.connects > 0 && g_fstats.phone_connects > 0;
#ifndef BLEHOST_072
    ok = ok && s_l13_valid > 0 && s_bulk > 0 && s_live > 0;
#endif
    printf("RESULT %s\n", ok ? "PASS" : "FAIL");
    fflush(stdout);
    _exit(ok ? 0 : 1);
}
