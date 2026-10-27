/* App-layer diagnostics (firmware 0.7.3). See app_diag.h, bc_diag.h, docs/FIRMWARE_0.7.3.md. */
#include "app_diag.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "app.h"
#include "app_power.h"
#include "bc_pipe.h"

/* 0.7.4: the whole diagnostic state and its work buffers are ONE allocation from PSRAM (plat_alloc_ext) made by
   app_diag_init(). 0.7.3 kept ~9.6 KB of them as statics in internal DRAM (D 2800 B, flush/index/report buffers), part of
   the 13.6 KB of internal DRAM 0.7.3 added over 0.7.2 - RAM the Bluetooth controller/HCI buffers needed
   (coord/reports/FW_STORAGE_MEMORY_REPORT.md). Only tasks touch it (never an ISR, never with the flash cache disabled). Before init, or
   if the allocation fails, every entry point is a no-op and the status says "Diagnostics unavailable". */
typedef struct {
    bool init, storage_ok, recovery, crashed;
    uint8_t storage_state, last_fail;   /* 0.7.4 bc_stor_state_t */
    bc_boot_plan_t plan;
    bc_evlog_t log; uint32_t written;
    bc_diag_index_t idx; bc_diag_srv_t srv;
    uint32_t crash_report; char summary[48]; int sent;
    /* monitors */
    bool mon_init; uint8_t stage[3]; uint32_t resub[3], reconn[3]; uint32_t below_since[3]; bool stuck_alerted[3];
    int phone_state; bool phone_ready; uint32_t phone_tx, phone_tx_ms; bool live_alerted; bool watch_hr_seen, watch_alerted;
    int wifi_state; uint32_t t_reading, t_health, t_live; uint32_t lives, lives_min, last_live_ms;
    bool heap_alerted, heapmin_alerted, stack_alerted;
    bool ready_due; uint16_t seq;
    /* Link 1.2.3 ride priority: chunk pacing + a reply the transport refused (sent again first, never lost) */
    uint32_t last_chunk_ms; bool chunk_sent; uint32_t chunks_held, chunks_paced;
    uint8_t held[BC_LINK_MAX]; size_t held_len; uint8_t held_chr;
    /* work buffers (0.7.3: function statics in internal DRAM) */
    bc_ev_t flush_e[BC_EVLOG_PEND]; uint8_t flush_buf[BC_EVLOG_PEND * BC_EV_SIZE];
    uint8_t idx_buf[16 + BC_DIAG_MAX_REPORTS * 76 + 4];
    plat_crash_t cr_report, cr_init, probe; bc_diag_report_in_t rin; bc_diag_task_t tasks[12];
} diag_t;
static diag_t *s_d;
#define D (*s_d)
#define ON (s_d != NULL && s_d->init)

static uint32_t now_ms(void) { return plat_ms(); }
void app_diag_event(uint8_t type, uint8_t x, uint16_t a, uint32_t b, uint32_t c, uint32_t d)
{
    if (!ON) return;
    bc_evlog_add(&D.log, type, x, a, b, c, d, now_ms());
}

/* ---- storage of the event ring */
void app_diag_flush(bool force)
{
    if (!ON || !D.storage_ok || !bc_evlog_flush_due(&D.log, now_ms(), force)) return;
    if (D.log.dropped) { uint32_t n = D.log.dropped; D.log.dropped = 0; bc_evlog_add(&D.log, BC_EV_NOTE, 0, 1, n, 0, 0, now_ms()); }
    bc_ev_t *e = D.flush_e; int n = bc_evlog_take(&D.log, e, BC_EVLOG_PEND, now_ms());   /* app task only, keeps stacks small */
    /* consecutive slots are written in one go (at most two runs: the ring wraps once) */
    uint8_t *buf = D.flush_buf;
    int i = 0;
    while (i < n) {
        uint32_t slot0 = e[i].seq % APP_DIAG_EV_SLOTS; int k = 0;
        while (i + k < n && e[i + k].seq % APP_DIAG_EV_SLOTS == (slot0 + (uint32_t)k) % APP_DIAG_EV_SLOTS && slot0 + (uint32_t)k < APP_DIAG_EV_SLOTS) { bc_ev_encode(&e[i + k], buf + (size_t)k * BC_EV_SIZE); k++; }
        if (k == 0) { bc_ev_encode(&e[i], buf); k = 1; }
        if (plat_file_write_at(APP_DIAG_EVENTS_FILE, (long)slot0 * BC_EV_SIZE, buf, (size_t)k * BC_EV_SIZE)) D.written += (uint32_t)k;
        i += k;
    }
}

static uint8_t *read_ring(void)
{
    size_t sz = (size_t)APP_DIAG_EV_SLOTS * BC_EV_SIZE;
    uint8_t *raw = malloc(sz); if (!raw) return NULL;
    long n = plat_file_read(APP_DIAG_EVENTS_FILE, (char *)raw, sz);
    if (n < 0) n = 0;
    if ((size_t)n < sz) memset(raw + n, 0xFF, sz - (size_t)n);
    return raw;
}

/* ---- report store */
static bool index_save(void)
{
    uint8_t *b = D.idx_buf; size_t n = bc_diag_index_encode(&D.idx, b, sizeof D.idx_buf);
    return n && plat_file_write(APP_DIAG_INDEX_FILE, (const char *)b, n);
}
static void report_path(uint32_t id, char *p, size_t cap) { snprintf(p, cap, "diag/r%06lu.txt", (unsigned long)id); }
static const bc_diag_index_t *st_index(void *ctx) { (void)ctx; return &D.idx; }
static long st_read(void *ctx, uint32_t id, uint32_t off, uint8_t *buf, size_t n) { (void)ctx; char p[32]; report_path(id, p, sizeof p); return plat_file_read_at(p, (long)off, (char *)buf, n); }
static bool st_mark_sent(void *ctx, uint32_t id)
{
    (void)ctx;
    for (int i = 0; i < D.idx.n; i++) if (D.idx.r[i].id == id) {
        D.idx.r[i].state = 1; D.sent++;
        app_diag_event(BC_EV_REPORT, D.idx.r[i].kind, (uint16_t)id, 1, 0, 0);
        return index_save();
    }
    return false;
}

static void fill_report(bc_diag_report_in_t *in, uint8_t kind, const plat_crash_t *cr, const char *note)
{
    memset(in, 0, sizeof *in);
    in->id = D.idx.next_id; in->kind = kind;
    app_live_t lv; memset(&lv, 0, sizeof lv);
    if (!D.recovery) { app_live(&lv); in->epoch_s = lv.time_known ? lv.epoch_s : 0; }
    snprintf(in->fw, sizeof in->fw, "%.16s", plat_fw_version());
    plat_build_ids(in->build, in->elf_sha);
    uint8_t id[6]; if (plat_device_id(id)) { in->board_id_tail[0] = id[4]; in->board_id_tail[1] = id[5]; }
    in->uptime_s = plat_uptime_s();
    in->reset = plat_reset_kind(); snprintf(in->reset_raw, sizeof in->reset_raw, "%s", plat_reset_reason());
    bc_boot_rtc_t *r = plat_boot_rtc();
    in->crash_streak = r->crash_streak; in->boot_count = plat_boot_count(); in->crash_total = plat_crash_total();
    in->boot_mode = (uint8_t)D.plan.mode; in->marker = D.plan.suspect; in->skip = D.plan.skip; in->staged_fails = r->staged_fails;
    if (cr && cr->have) {
        in->have_dump = true; snprintf(in->task, sizeof in->task, "%s", cr->task); in->pc = cr->pc; in->exccause = cr->exccause; in->excvaddr = cr->excvaddr;
        snprintf(in->reason, sizeof in->reason, "%s", cr->reason); memcpy(in->bt, cr->bt, sizeof in->bt); in->bt_depth = cr->bt_depth; in->bt_corrupted = cr->bt_corrupted;
    }
    in->ntasks = plat_tasks(in->tasks, 12);
    plat_heap(&in->heap_free, &in->heap_min, &in->heap_largest, &in->psram_free);
    plat_sensors_t s; plat_sensors(&s);
    static const plat_sens_kind_t K[3] = { PLAT_SENS_POWER, PLAT_SENS_HR, PLAT_SENS_CSC };
    for (int i = 0; i < 3; i++) {
        const plat_link_info_t *l = &s.link[K[i]];
        in->sens[i].paired = l->link != PLAT_LINK_NOT_PAIRED && l->link != PLAT_LINK_UNSUPPORTED; in->sens[i].disabled = l->disabled; in->sens[i].stage = l->stage;
        in->sens[i].packets = l->packets; in->sens[i].rejected = l->rejected; in->sens[i].resubs = l->resubscribes; in->sens[i].reconnects = l->auto_reconnects;
        in->sens[i].valid_age_ms = l->valid_age_ms; snprintf(in->sens[i].err, sizeof in->sens[i].err, "%s", l->err);
    }
    plat_phone_status_t ps; plat_phone_status(&ps);
    in->phone_state = (uint8_t)ps.state; in->phone_bonds = ps.bonds; in->phone_last_disc = (uint8_t)ps.last_disc; in->phone_disc_code = ps.last_disc_code;
    in->phone_connects = ps.connects; in->phone_tx = ps.tx_msgs; in->phone_rx = ps.rx_msgs; in->lives_sent = D.lives; in->phone_enabled = ps.state != PLAT_PHONE_OFF;
    plat_wifi_status_t ws; plat_wifi_status(&ws);
    in->wifi_on = ws.state != PLAT_WIFI_OFF; in->wifi_state = (uint8_t)ws.state; in->wifi_err = (uint8_t)ws.err; in->wifi_rssi = ws.rssi;
    in->recovery_note = note;
}

uint32_t app_diag_store_report(uint8_t kind, const char *note)
{
    if (!ON) return 0;
    plat_crash_t *crp = &D.cr_report; bool have_cr = kind == BC_DIAG_KIND_CRASH && plat_crash_info(crp);
    if (!have_cr) memset(crp, 0, sizeof *crp);
    char *tail = NULL;
    bc_diag_report_in_t *inp = &D.rin; fill_report(inp, kind, crp, note);
    if (kind == BC_DIAG_KIND_CRASH) { tail = malloc(2200); if (tail) { plat_log_tail(tail, 2200); inp->log_tail = tail; } }
    char sum[48]; bc_diag_summary(inp, sum, sizeof sum);
    if (!D.storage_ok) { free(tail); snprintf(D.summary, sizeof D.summary, "%s", sum); D.last_fail = D.storage_state; return 0; }
    D.last_fail = BC_STOR_DIAG_UNAVAILABLE;              /* until it is stored (out of memory if nothing below changes it) */
    app_diag_flush(true);
    bc_ev_t *ev = malloc(sizeof(bc_ev_t) * 60); int nev = 0;
    uint8_t *raw = read_ring();
    if (ev && raw) nev = bc_evlog_newest(raw, APP_DIAG_EV_SLOTS, ev, 60);
    free(raw);
    char *txt = malloc(BC_DIAG_REPORT_MAX);
    uint32_t id = 0;
    if (txt) {
        size_t n = bc_diag_report_build(inp, ev, nev, txt, BC_DIAG_REPORT_MAX);
        int room;
        while ((room = bc_diag_index_make_room(&D.idx, (uint32_t)n)) >= 0) {   /* delete the oldest SENT report(s) */
            char p[32]; report_path(D.idx.r[room].id, p, sizeof p); plat_file_remove(p);
            /* 0.7.4: its raw core dump copy goes with it (0.7.3 kept every diag/core-<id>.elf forever: ~14 KB per crash) */
            snprintf(p, sizeof p, "diag/core-%06lu.elf", (unsigned long)D.idx.r[room].id); plat_file_remove(p);
            memmove(&D.idx.r[room], &D.idx.r[room + 1], sizeof D.idx.r[0] * (size_t)(D.idx.n - room - 1)); D.idx.n--;
        }
        if (room == -2) {                                   /* never delete an unsent report to make room */
            D.idx.not_stored++; index_save(); D.last_fail = BC_STOR_DIAG_FULL;
            app_diag_event(BC_EV_REPORT, kind, 0, 2, 0, 0);
        } else {
            char p[32]; report_path(inp->id, p, sizeof p);
            if (plat_file_write(p, txt, n)) {
                bc_diag_info_t *r = &D.idx.r[D.idx.n];
                memset(r, 0, sizeof *r); r->id = inp->id; r->size = (uint32_t)n; r->crc = bc_crc32(0, txt, n); r->epoch_s = inp->epoch_s; r->kind = kind; r->state = 0;
                snprintf(r->summary, sizeof r->summary, "%.40s", sum); snprintf(r->fw, sizeof r->fw, "%s", inp->fw);
                D.idx.n++; D.idx.next_id++;
                if (index_save()) { id = inp->id; D.ready_due = true; D.last_fail = BC_STOR_OK; app_diag_event(BC_EV_REPORT, kind, (uint16_t)id, 0, 0, 0); }
                else { D.idx.n--; D.idx.next_id--; plat_file_remove(p); D.last_fail = (uint8_t)plat_storage_write_failure(); }
            } else D.last_fail = (uint8_t)plat_storage_write_failure();
        }
    }
    free(txt); free(ev); free(tail);
    if (kind == BC_DIAG_KIND_CRASH) snprintf(D.summary, sizeof D.summary, "%s", sum);
    app_diag_flush(true);
    return id;
}

/* ---- boot */
void app_diag_init(const bc_boot_plan_t *plan, bool storage_ok)
{
    if (!s_d) s_d = plat_alloc_ext(sizeof *s_d);
    if (!s_d) { plat_log("DIAG: no memory for the diagnostic state - diagnostics unavailable this boot"); return; }
    memset(&D, 0, sizeof D);
    D.init = true; D.storage_ok = storage_ok; D.plan = *plan;
    D.storage_state = (uint8_t)(storage_ok ? BC_STOR_OK : plat_storage_state()); D.recovery = plan->mode == BC_BOOT_RECOVERY; D.crashed = plan->crashed;
    bc_evlog_init(&D.log, APP_DIAG_EV_SLOTS, plat_boot_count());
    if (storage_ok) {
        long sz = plat_file_size(APP_DIAG_EVENTS_FILE);
        if (sz != (long)(APP_DIAG_EV_SLOTS * BC_EV_SIZE)) {   /* first start (or a damaged file): a fresh, erased ring */
            uint8_t ff[256]; memset(ff, 0xFF, sizeof ff); plat_file_remove(APP_DIAG_EVENTS_FILE);
            for (uint32_t off = 0; off < APP_DIAG_EV_SLOTS * BC_EV_SIZE; off += sizeof ff) plat_file_write_at(APP_DIAG_EVENTS_FILE, (long)off, ff, sizeof ff);
            if (sz >= 0) bc_evlog_add(&D.log, BC_EV_NOTE, 0, 2, (uint32_t)sz, 0, 0, now_ms());
        } else { uint8_t *raw = read_ring(); if (raw) { bc_evlog_resume(&D.log, raw, APP_DIAG_EV_SLOTS); free(raw); } }
        uint8_t *b = D.idx_buf; long n = plat_file_read(APP_DIAG_INDEX_FILE, (char *)b, sizeof D.idx_buf);
        if (n <= 0 || !bc_diag_index_decode(b, (size_t)n, &D.idx)) { memset(&D.idx, 0, sizeof D.idx); D.idx.next_id = 1; }
    } else D.idx.next_id = 1;
    bc_diag_store_t st = { .ctx = NULL, .index = st_index, .read = st_read, .mark_sent = st_mark_sent };
    bc_diag_srv_init(&D.srv, &st);
    bc_boot_rtc_t *r = plat_boot_rtc();
    app_diag_event(BC_EV_BOOT, 0, (uint16_t)plat_reset_kind(), r->crash_streak, plat_boot_count(), (uint32_t)plan->mode | ((uint32_t)plan->skip << 8));
    if (plan->newly_skipped) app_diag_event(BC_EV_RECOVERY, 4, plan->suspect, plan->skip, 0, 0);
    if (plan->crashed) {
        plat_crash_t *cr = &D.cr_init; bool have = plat_crash_info(cr);
        uint32_t id = app_diag_store_report(BC_DIAG_KIND_CRASH, plan->newly_skipped ? "staged boot: the subsystem that was starting is disabled on this boot" : NULL);
        D.crash_report = id;
        app_diag_event(BC_EV_CRASH, have ? 1 : 0, (uint16_t)id, have ? cr->pc : 0, have ? cr->exccause : 0, 0);
        if (have && id) plat_crash_consumed(id);            /* the raw dump moves to diag/core-<id>.elf; the partition is free again */
    } else if (plat_crash_info(&D.probe)) {
        /* a core dump without a crash reset (e.g. the board was power-cycled while the old dump was still there): report it once */
        uint32_t id = app_diag_store_report(BC_DIAG_KIND_CRASH, "core dump found after a normal start (earlier crash)");
        if (id) plat_crash_consumed(id);
    }
    app_diag_flush(true);
}

void app_diag_stage(bc_subsys_t s, int result) { app_diag_event(BC_EV_STAGE, (uint8_t)result, (uint16_t)s, 0, 0, 0); if (result >= 2) app_diag_flush(true); }
void app_diag_note_live(void) { if (!ON) return; D.lives++; D.lives_min++; D.last_live_ms = now_ms(); }

/* ---- the continuous monitor */
static void monitor(uint32_t now)
{
    plat_sensors_t s; plat_sensors(&s);
    static const plat_sens_kind_t K[3] = { PLAT_SENS_POWER, PLAT_SENS_HR, PLAT_SENS_CSC };
    for (int i = 0; i < 3; i++) {
        const plat_link_info_t *l = &s.link[K[i]];
        if (!D.mon_init || l->stage != D.stage[i]) {
            if (D.mon_init || l->stage != BC_STG_NOT_PAIRED) app_diag_event(BC_EV_SENSOR, l->stage, (uint16_t)(i + 1), l->packets, l->rejected, l->valid_age_ms);
            D.stage[i] = l->stage;
            D.below_since[i] = now; D.stuck_alerted[i] = false;
        }
        if (l->resubscribes > D.resub[i]) { app_diag_event(BC_EV_RECOVERY, 1, (uint16_t)(i + 1), l->resubscribes, 0, 0); D.resub[i] = l->resubscribes; }
        if (l->auto_reconnects > D.reconn[i]) { app_diag_event(BC_EV_RECOVERY, 2, (uint16_t)(i + 1), l->auto_reconnects, 0, 0); D.reconn[i] = l->auto_reconnects; }
        bool stuck_stage = l->stage == BC_STG_CONNECTED || l->stage == BC_STG_SUBSCRIBED || l->stage == BC_STG_RECEIVING || l->stage == BC_STG_STALE || l->stage == BC_STG_ERROR;
        if (stuck_stage && !D.stuck_alerted[i] && now - D.below_since[i] > BC_HEALTH_SENSOR_STUCK_MS) {
            D.stuck_alerted[i] = true; app_diag_event(BC_EV_ALERT, 0, BC_HA_SENSOR_STUCK, (uint32_t)(i + 1), BC_HEALTH_SENSOR_STUCK_MS, 0);
        }
    }
    plat_phone_status_t ps; plat_phone_status(&ps);
    if (!D.mon_init || (int)ps.state != D.phone_state) { app_diag_event(BC_EV_PHONE, (uint8_t)ps.state, ps.last_disc_code, ps.connects, ps.bonds, 0); D.phone_state = (int)ps.state; }
    if (ps.tx_msgs != D.phone_tx) { D.phone_tx = ps.tx_msgs; D.phone_tx_ms = now; D.live_alerted = false; }
    if (ps.state == PLAT_PHONE_READY && D.lives && !D.live_alerted && now - D.phone_tx_ms > BC_HEALTH_LIVE_STALL_MS && now - D.last_live_ms < 2000) {
        D.live_alerted = true; app_diag_event(BC_EV_ALERT, 0, BC_HA_LIVE_STALLED, now - D.phone_tx_ms, BC_HEALTH_LIVE_STALL_MS, 0);
    }
    plat_wifi_status_t ws; plat_wifi_status(&ws);
    if (!D.mon_init || (int)ws.state != D.wifi_state) { app_diag_event(BC_EV_WIFI, (uint8_t)ws.state, (uint16_t)ws.err, (uint32_t)ws.rssi, 0, 0); D.wifi_state = (int)ws.state; }
    if (!D.recovery) {
        app_live_t lv; app_live(&lv);
        if (lv.phone_hr) { D.watch_hr_seen = true; D.watch_alerted = false; }
        else if (D.watch_hr_seen && ps.state == PLAT_PHONE_READY && !D.watch_alerted) { D.watch_alerted = true; app_diag_event(BC_EV_ALERT, 0, BC_HA_WATCH_HR_STALE, 0, 6000, 0); }
        if (now - D.t_reading >= 30000 && (lv.power_ok || lv.cad_ok || lv.hr_ok) && !lv.demo) {
            D.t_reading = now;
            uint32_t pa = lv.link[PLAT_SENS_POWER].valid_age_ms;
            app_diag_event(BC_EV_READING, lv.hr_ok ? lv.hr_src : 0, (uint16_t)(lv.power_ok ? lv.watts : 0xFFFF),
                           (uint32_t)(lv.cad_ok ? (lv.rpm & 0xFFFF) : 0xFFFF) | ((uint32_t)(lv.hr_ok ? lv.bpm : 0xFFFF) << 16), pa, lv.hr_age_ms);
        }
    }
    if (now - D.t_live >= 60000) {
        D.t_live = now;
        if (ps.state == PLAT_PHONE_READY || D.lives_min) app_diag_event(BC_EV_LIVE, 0, (uint16_t)(D.lives_min > 0xFFFF ? 0xFFFF : D.lives_min), ps.tx_msgs, D.last_live_ms ? now - D.last_live_ms : UINT32_MAX, 0);
        D.lives_min = 0;
    }
    if (!D.mon_init || now - D.t_health >= 60000) {
        D.t_health = now;
        uint32_t fr, mn, lg, ps_free; plat_heap(&fr, &mn, &lg, &ps_free);
        bc_diag_task_t *t = D.tasks; int nt = plat_tasks(t, 12);
        uint32_t lvg = 0xFFFF, nim = 0xFFFF, mgr = 0xFFFF, tim = 0xFFFF, low = UINT32_MAX;
        for (int i = 0; i < nt; i++) {
            uint32_t v = t[i].stack_free > 0xFFFF ? 0xFFFF : t[i].stack_free;
            if (!strcmp(t[i].name, "taskLVGL")) lvg = v; else if (!strcmp(t[i].name, "nimble_host")) nim = v; else if (!strcmp(t[i].name, "ble_mgr")) mgr = v; else if (!strcmp(t[i].name, "esp_timer")) tim = v;
            if (t[i].stack_free < low) low = t[i].stack_free;
        }
        app_diag_event(BC_EV_HEALTH, 0, (uint16_t)(fr / 1024), mn, (lvg << 16) | nim, (mgr << 16) | tim);
        if (fr < BC_HEALTH_HEAP_LOW && !D.heap_alerted) { D.heap_alerted = true; app_diag_event(BC_EV_ALERT, 0, BC_HA_HEAP_LOW, fr, BC_HEALTH_HEAP_LOW, 0); }
        if (mn < BC_HEALTH_HEAP_MIN_LOW && !D.heapmin_alerted) { D.heapmin_alerted = true; app_diag_event(BC_EV_ALERT, 0, BC_HA_HEAP_MIN_LOW, mn, BC_HEALTH_HEAP_MIN_LOW, 0); }
        if (low < BC_HEALTH_STACK_LOW && !D.stack_alerted) { D.stack_alerted = true; app_diag_event(BC_EV_ALERT, 0, BC_HA_STACK_LOW, low, BC_HEALTH_STACK_LOW, 0); }
        if (!D.recovery) { const app_power_t *pw = app_power(); app_diag_event(BC_EV_TOUCH, 0, (uint16_t)pw->wakes, pw->touch_reports, pw->touch_passed, pw->screen_offs); }
    }
    D.mon_init = true;
}

void app_diag_tick(uint32_t now)
{
    if (!ON) return;
    monitor(now);
    app_diag_flush(false);
}

/* ---- phone transfer */
bool app_diag_write(const uint8_t *msg, size_t n)
{
    if (!ON || !msg || n < 1 || msg[0] < BC_MSG_DIAG_LIST_REQ || msg[0] > BC_MSG_DIAG_ERR) return false;
    bc_diag_srv_write(&D.srv, msg, n);
    return true;
}
size_t app_diag_next(uint8_t *chr, uint8_t *buf, size_t cap, uint32_t now)
{
    if (!ON) return 0;
    if (D.ready_due && D.phone_ready) {
        D.ready_due = false;
        bc_diag_ready_t r = { (uint8_t)bc_diag_index_pending(&D.idx), D.idx.n ? D.idx.r[D.idx.n - 1].id : 0 };
        *chr = 2; return bc_link_encode_diag_ready(&r, buf, cap, ++D.seq, now);
    }
    /* link facts for the server: chunk size from the NEGOTIATED ATT MTU, chunks refused (BUSY) while a ride records */
    if (D.srv.nq) { plat_phone_status_t ps; plat_phone_status(&ps); bc_diag_srv_set_link(&D.srv, ps.att_mtu, !D.recovery && app_ride_state() == BC_RIDE_RUNNING); }
    /* ride priority: a data chunk only when the link has room (LIVE first) and at most one per BC_DIAG_CHUNK_GAP_MS */
    if (bc_diag_srv_chunk_next(&D.srv)) {
        bool room = plat_phone_bulk_room();
        if (!bc_diag_pace_ok(now, D.last_chunk_ms, D.chunk_sent, room)) { if (room) D.chunks_paced++; else D.chunks_held++; return 0; }
    }
    size_t m = bc_diag_srv_next(&D.srv, buf, cap, ++D.seq, now);
    if (m) { *chr = 0; if (buf[0] == BC_MSG_DIAG_CHUNK) { D.last_chunk_ms = now; D.chunk_sent = true; } return m; }
    D.seq--;
    return 0;
}
void app_diag_phone_ready(bool ready)
{
    if (!ON) return;
    if (ready && !D.phone_ready) D.ready_due = true;          /* on every (re)connection: what is waiting */
    if (!ready) { bc_diag_srv_reset(&D.srv); D.ready_due = false; D.held_len = 0; }
    D.phone_ready = ready;
}

void app_diag_recovery_pump(uint32_t now)
{
    if (!ON) return;
    plat_phone_status_t ps; plat_phone_status(&ps);
    if (ps.svc_ready != D.phone_ready) { app_diag_phone_ready(ps.svc_ready); if (ps.svc_ready) app_diag_event(BC_EV_MODE, 3, 0, 0, 0, 0); }
    uint8_t chr, b[BC_LINK_MAX]; int n, guard = 0;
    while ((n = plat_phone_take_svc(&chr, b, sizeof b)) > 0 && guard++ < 16) if (chr == 0) app_diag_write(b, (size_t)n);
    if (D.held_len) { if (!plat_phone_notify_svc(D.held_chr, D.held, D.held_len)) return; D.held_len = 0; }
    for (int i = 0; i < 8; i++) {
        uint8_t c; size_t m = app_diag_next(&c, b, sizeof b, now);
        if (!m) break;
        if (!plat_phone_notify_svc(c, b, m)) { memcpy(D.held, b, m); D.held_len = m; D.held_chr = c; break; }   /* queue full: sent next pump */
    }
}

void app_diag_status(app_diag_status_t *o)
{
    memset(o, 0, sizeof *o);
    if (!ON) { o->storage_ok = plat_storage_ok(); o->storage_state = (uint8_t)plat_storage_state(); o->last_fail = BC_STOR_DIAG_UNAVAILABLE; return; }
    o->crashed = D.crashed; o->crash_report = D.crash_report; snprintf(o->summary, sizeof o->summary, "%s", D.summary);
    o->stored = D.idx.n; o->pending = bc_diag_index_pending(&D.idx); o->sent = D.sent; o->not_stored = D.idx.not_stored;
    o->storage_ok = D.storage_ok; o->storage_state = D.storage_state; o->last_fail = D.last_fail; o->events_written = D.written; o->events_dropped = D.log.dropped; o->phone_ready = D.phone_ready;
    o->chunks_sent = D.srv.chunks_sent; o->chunks_held = D.chunks_held; o->chunks_paced = D.chunks_paced; o->busy_ride = D.srv.busy_ride;
}

uint16_t app_diag_skip(void) { return ON ? D.plan.skip : plat_boot_rtc()->skip; }
bc_boot_mode_t app_diag_mode(void) { return ON ? D.plan.mode : (bc_boot_mode_t)plat_boot_rtc()->mode; }
void app_diag_retry(bc_subsys_t s)
{
    if (!ON) { bc_boot_unskip(plat_boot_rtc(), s); plat_boot_skip_save((uint16_t)(plat_boot_skip_load() & ~BC_SS_BIT(s))); return; }
    bc_boot_unskip(plat_boot_rtc(), s);
    plat_boot_skip_save((uint16_t)(plat_boot_skip_load() & ~BC_SS_BIT(s)));
    D.plan.skip &= (uint16_t)~BC_SS_BIT(s);
    app_diag_event(BC_EV_RECOVERY, 3, (uint16_t)s, 0, 0, 0);
    if (s == BC_SS_POWER) plat_sensor_set_disabled(PLAT_SENS_POWER, false);
    else if (s == BC_SS_HR) plat_sensor_set_disabled(PLAT_SENS_HR, false);
    else if (s == BC_SS_CSC) plat_sensor_set_disabled(PLAT_SENS_CSC, false);
    app_diag_flush(true);
}

bool app_diag_upload_hook(uint32_t report_id) { (void)report_id; return false; }   /* disabled: APP_DIAG_UPLOAD_ENABLED 0, no server */
