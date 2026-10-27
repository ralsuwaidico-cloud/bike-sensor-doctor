/* Link 1.3 on the board (firmware 0.7.5): see app_link13.h. */
#include "app_link13.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "app.h"
#include "app_diag.h"
#include "plat.h"
#include "bc_diag.h"
#include "bc_storage.h"
#include "bc_boot.h"

#define RQ_MAX 56                 /* newest 50 saved rides + RAM-only rides + the ride being recorded */
#define RQ_HIST 50
#define SYNCED_FILE "rides/synced.txt"   /* one line per verified ride: "<id> <samples_crc> <summary_crc>" */
#define SYNCED_MAX 256

typedef struct {
    uint32_t id; uint8_t state, flags; bool crc_known, xfer, ram;
    uint32_t size, scrc, sumcrc, epoch, dur;
} rq_ent_t;

typedef struct {
    bc_cmirror_t cm;
    /* ride queue */
    rq_ent_t q[RQ_MAX]; int nq; bool built;
    bc_ride_summary_t hist[RQ_HIST], un[APP_UNSAVED_MAX];
    rq_ent_t old[RQ_MAX];
    uint32_t synced[SYNCED_MAX]; int nsynced;     /* ids verified on the phone (file + RAM-only rides) */
    int list_i; bool listing, list_end_due;
    bc_diag_chunk_req_t cq[4]; int ncq; uint32_t last_chunk_ms; bool chunk_sent;
    bool rinfo_due; uint32_t rinfo_id; rq_ent_t rinfo_ent; bool rinfo_has_ent; bool rerr_due; bc_diag_err_t rerr;
    /* replies due */
    bool hello_ack_due; bool plan_ack_due; bc_coach_plan_ack_t plan_ack;
    bool status_due; bool clean_due; bc_storage_clean_result_t clean;
    bool pending_due;
    uint16_t seq;
    uint32_t notify_fails_seen, notify_fail_ms;
    app_link13_stats_t st;
} l13_t;

static l13_t *L;
static uint32_t s_enabled;         /* caps enabled by this connection's HELLO */
static bool s_ready;

void app_link13_init(void)
{
    if (!L) L = plat_alloc_ext(sizeof *L);
    if (!L) { plat_log("LINK13: no memory for the Link 1.3 state - the board stays on Link 1.2.3"); return; }
    memset(L, 0, sizeof *L);
    bc_cm_init(&L->cm);
    s_enabled = 0; s_ready = false;
}
uint32_t app_link13_enabled(void) { return s_enabled; }
void app_link13_stats(app_link13_stats_t *o) { if (L) { *o = L->st; o->states_applied = L->cm.states_applied; o->states_ignored = L->cm.states_ignored; o->plans_ok = L->cm.plans_ok; o->plans_bad = L->cm.plans_bad; } else memset(o, 0, sizeof *o); }

static bool recording(void) { bc_ride_state_t s = app_ride_state(); return s == BC_RIDE_RUNNING || s == BC_RIDE_PAUSED; }
static uint32_t elapsed_now(void) { bc_ride_summary_t t; app_ride_totals(&t); return recording() ? t.duration_s : 0; }
static bool phone_live(void)
{
    if (!(s_enabled & BC_CAP_COACH)) return false;
    plat_phone_status_t ps; plat_phone_status(&ps); return ps.svc_ready;
}

/* ------------------------------------------------------------------ ride queue store */
static void samples_path(uint32_t id, char *p, size_t cap) { snprintf(p, cap, "rides/r%04u.txt", (unsigned)(id & 0xFFFF)); }
static bool is_synced(uint32_t id) { for (int i = 0; i < L->nsynced; i++) if (L->synced[i] == id) return true; return false; }
static void add_synced(uint32_t id) { if (!is_synced(id) && L->nsynced < SYNCED_MAX) L->synced[L->nsynced++] = id; }
static void load_synced(void)
{
    /* RAM-only acks survive a list rebuild; the file holds the rest */
    uint32_t keep[SYNCED_MAX]; int nk = 0;
    for (int i = 0; i < L->nq; i++) if (L->q[i].ram && is_synced(L->q[i].id) && nk < SYNCED_MAX) keep[nk++] = L->q[i].id;
    L->nsynced = 0;
    char b[257]; long off = 0, n;
    while ((n = plat_file_read_at(SYNCED_FILE, off, b, sizeof b - 1)) > 0) {
        b[n] = 0; char *s = b, *e; long used = 0;
        while ((e = strchr(s, '\n')) != NULL) { *e = 0; unsigned long id; if (sscanf(s, "%lu", &id) == 1) add_synced((uint32_t)id); used = (e - b) + 1; s = e + 1; }
        if (!used) break;
        off += used;
    }
    for (int i = 0; i < nk; i++) add_synced(keep[i]);
}
static uint32_t file_crc(const char *path, uint32_t size)
{
    uint8_t b[256]; uint32_t c = 0, off = 0;
    while (off < size) { long n = plat_file_read_at(path, (long)off, (char *)b, sizeof b); if (n <= 0) break; c = bc_crc32(c, b, (size_t)n); off += (uint32_t)n; }
    return c;
}
static void ent_state(rq_ent_t *e)
{
    char p[32]; samples_path(e->id, p, sizeof p);
    long sz = e->ram ? -1 : plat_file_size(p);
    if (sz >= 0) { if ((uint32_t)sz != e->size) e->crc_known = false; e->size = (uint32_t)sz; } else { e->size = 0; e->crc_known = true; e->scrc = 0; }
    e->flags &= (uint8_t)~(BC_RQF_SUMMARY_ONLY | BC_RQF_RAM_ONLY);
    if (e->ram) e->flags |= BC_RQF_RAM_ONLY;
    if (is_synced(e->id)) e->state = (sz >= 0 || e->ram) ? BC_RQ_VERIFIED : BC_RQ_SAMPLES_DELETED;   /* a RAM-only ride had no samples to delete */
    else { e->state = e->xfer ? BC_RQ_TRANSFER : BC_RQ_UNSYNCED; if (sz < 0 && !e->ram) e->flags |= BC_RQF_SUMMARY_ONLY; }
}
static void build_list(void)
{
    load_synced();
    rq_ent_t *old = L->old; int nold = L->nq; memcpy(old, L->q, sizeof L->q[0] * (size_t)nold);
    int nh = app_history(L->hist, RQ_HIST, false);          /* newest first; includes the RAM-only rides */
    bc_ride_summary_t *un = L->un; int nu = app_unsaved_rides(un, APP_UNSAVED_MAX);
    L->nq = 0;
    for (int i = nh - 1; i >= 0 && L->nq < RQ_MAX - 1; i--) {   /* oldest first */
        const bc_ride_summary_t *s = &L->hist[i];
        if (s->demo) continue;                              /* v1.1: demo rides are never in the queue */
        rq_ent_t *e = &L->q[L->nq++]; memset(e, 0, sizeof *e);
        e->id = s->id; e->epoch = s->start_epoch_s; e->dur = s->duration_s; e->sumcrc = bc_ride_summary_crc(s);
        e->flags = s->recovered ? BC_RQF_RECOVERED : 0;
        for (int k = 0; k < nu; k++) if (un[k].id == s->id) e->ram = true;
        for (int k = 0; k < nold; k++) if (old[k].id == e->id) { e->xfer = old[k].xfer; if (old[k].crc_known) { e->crc_known = true; e->scrc = old[k].scrc; e->size = old[k].size; } }
        ent_state(e);
    }
    if (recording() && !app_ride_is_demo()) {                /* the ride being recorded: state 0, nothing to pull yet */
        bc_ride_summary_t t; app_ride_totals(&t);
        rq_ent_t *e = &L->q[L->nq++]; memset(e, 0, sizeof *e);
        e->id = t.id; e->state = BC_RQ_RECORDING; e->dur = t.duration_s; e->epoch = t.start_epoch_s; e->crc_known = true;
    }
    L->built = true;
    uint16_t un_n = 0; uint32_t un_b = 0;
    for (int i = 0; i < L->nq; i++) if (L->q[i].state == BC_RQ_UNSYNCED || L->q[i].state == BC_RQ_TRANSFER) { un_n++; un_b += L->q[i].size; }
    L->st.unsynced = un_n; L->st.unsynced_bytes = un_b;
}
static rq_ent_t *find(uint32_t id)
{
    if (!L->built) build_list();
    for (int i = 0; i < L->nq; i++) if (L->q[i].id == id) return &L->q[i];
    return NULL;
}
static void ensure_crc(rq_ent_t *e)
{
    if (e->crc_known) return;
    char p[32]; samples_path(e->id, p, sizeof p);
    e->scrc = file_crc(p, e->size); e->crc_known = true;
}
static void rq_info(const rq_ent_t *e, bc_rideq_info_t *i)
{
    i->ride_id = e->id; i->state = e->state; i->samples_size = e->size; i->samples_crc = e->scrc; i->start_epoch_s = e->epoch; i->duration_s = e->dur;
    i->flags = e->flags; i->summary_crc = e->sumcrc;
}
static void rq_err(uint32_t id, uint8_t code) { L->rerr_due = true; L->rerr.id = id; L->rerr.code = code; }

static void rq_ack(const bc_rideq_ack_t *a)
{
    rq_ent_t *e = find(a->ride_id);
    if (!e) { rq_err(a->ride_id, BC_DIAG_ERR_UNKNOWN_ID); return; }
    if (e->state == BC_RQ_RECORDING) { rq_err(a->ride_id, BC_DIAG_ERR_BUSY); L->st.rq_busy++; return; }
    ensure_crc(e);
    bool samples_ok = (e->flags & (BC_RQF_SUMMARY_ONLY | BC_RQF_RAM_ONLY)) || e->state == BC_RQ_SAMPLES_DELETED || a->samples_crc == e->scrc;
    if (!samples_ok || a->summary_crc != e->sumcrc) { rq_err(a->ride_id, BC_RQ_ERR_CRC); L->st.rq_acks_bad++; return; }   /* v1.1: state unchanged */
    if (!is_synced(e->id)) {
        if (!e->ram) {
            char line[48]; int k = snprintf(line, sizeof line, "%lu %lu %lu\n", (unsigned long)e->id, (unsigned long)e->scrc, (unsigned long)e->sumcrc);
            if (!plat_file_append(SYNCED_FILE, line, (size_t)k, true)) { rq_err(a->ride_id, BC_DIAG_ERR_STORAGE); return; }   /* not persisted: not verified */
        }
        add_synced(e->id);
    }
    L->st.rq_acks_ok++;
    if (a->delete_samples && !recording() && !e->ram) {          /* never while a ride records; the phone has it verified */
        char p[32]; samples_path(e->id, p, sizeof p);
        if (plat_file_size(p) >= 0 && plat_file_remove(p)) L->st.rq_deleted++;
    }
    e->xfer = false; ent_state(e);
    L->rinfo_due = true; L->rinfo_id = e->id; L->rinfo_ent = *e; L->rinfo_has_ent = true;   /* the reply describes the ride as verified */
    if (e->ram) app_unsaved_release((uint16_t)e->id);        /* rc3 (QA QF-22 / QF-29): the phone has it - free the memory slot */
    build_list();                                              /* counters for LIVE / STORAGE_STATUS */
}

/* ------------------------------------------------------------------ storage */
static uint8_t stor_state(void)
{
    uint8_t s = (uint8_t)plat_storage_state();
    if (s == BC_STOR_OK) { app_diag_status_t d; app_diag_status(&d); if (d.last_fail == BC_STOR_DIAG_FULL) s = BC_STOR_DIAG_FULL; }
    return s;
}
static void storage_status(bc_storage_status_t *o)
{
    memset(o, 0, sizeof *o);
    o->state = stor_state(); snprintf(o->code, sizeof o->code, "%s", bc_stor_code((bc_stor_state_t)o->state));
    bc_stor_facts_t f; plat_storage_facts(&f);
    o->fs_total_kb = (uint32_t)(f.total_bytes / 1024); o->fs_free_kb = (uint32_t)(f.free_bytes / 1024);
    uint32_t dump = 0; o->crash_partition = (uint8_t)plat_crash_partition(&dump); o->crash_dump_bytes = dump;
    app_diag_status_t d; app_diag_status(&d);
    o->reports_stored = (uint16_t)d.stored; o->reports_unsent = (uint16_t)d.pending; o->diag_bytes = app_diag_store_bytes();
    if (!L->built) build_list();
    uint32_t synced_b = 0; for (int i = 0; i < L->nq; i++) if (L->q[i].state == BC_RQ_VERIFIED) synced_b += L->q[i].size;
    o->rides_unsynced = L->st.unsynced; o->ride_bytes_unsynced = L->st.unsynced_bytes; o->ride_bytes_synced = synced_b;
    plat_flash_usage(&o->app_slot_kb, &o->app_used_kb, &o->nvs_used_entries, &o->nvs_free_entries);
    if (f.root_scanned) { o->root_free_slots = f.root.free_slots; o->root_bad_entries = (uint16_t)(f.root.erased + f.root.garbage); }
    o->health = bc_storage_health(o->state);
}
static void storage_clean(uint8_t what)
{
    bc_storage_clean_result_t *r = &L->clean; memset(r, 0, sizeof *r);
    L->st.cleans++;
    uint8_t s = stor_state();
    if (recording()) r->status = BC_CLEAN_BUSY;
    else if (!bc_storage_clean_allowed(s)) { r->status = BC_CLEAN_REFUSED; L->st.clean_refused++; }
    else if (!plat_storage_fat_consistent(NULL, 0)) {          /* rc3 (QA QF-28): never delete on a damaged allocation table */
        r->status = BC_CLEAN_REFUSED; L->st.clean_refused++; plat_log("LINK13: storage clean-up refused - the FAT is not consistent");
    }
    else {
        uint32_t freed = 0; int items = 0;
        if (what & BC_CLEAN_REPORTS) { uint32_t b = 0; items += app_diag_clean_sent(&b); freed += b; }
        if (what & BC_CLEAN_SAMPLES) {
            build_list();
            for (int i = 0; i < L->nq; i++) if (L->q[i].state == BC_RQ_VERIFIED && !L->q[i].ram) {   /* only rides verified on the phone */
                char p[32]; samples_path(L->q[i].id, p, sizeof p); long sz = plat_file_size(p);
                if (sz >= 0 && plat_file_remove(p)) { freed += (uint32_t)sz; items++; }
            }
        }
        if (what & BC_CLEAN_CACHES) {
            static const char *C[] = { "diag/report.txt", "diag/probe.txt" };
            for (size_t i = 0; i < sizeof C / sizeof *C; i++) { long sz = plat_file_size(C[i]); if (sz >= 0 && plat_file_remove(C[i])) { freed += (uint32_t)sz; items++; } }
            long dz = plat_file_size("demo/history.txt"); if (dz > 0 && app_history_clear(true)) { freed += (uint32_t)dz; items++; }
        }
        r->status = items ? BC_CLEAN_DONE : BC_CLEAN_NOTHING; r->bytes_freed = freed; r->items = (uint16_t)(items > 0xFFFF ? 0xFFFF : items);
        if (items) plat_storage_recheck();                     /* a FULL storage may be usable again */
        build_list();
        char l[80]; snprintf(l, sizeof l, "LINK13: storage clean-up 0x%x: %d items, %lu bytes", what, items, (unsigned long)freed); plat_log(l);
    }
    L->clean_due = true; L->status_due = true;                 /* v1.1: STORAGE_STATUS after every CLEAN_RESULT */
}

/* ------------------------------------------------------------------ phone writes */
static bool gate(uint32_t cap) { if (s_enabled & cap) return true; L->st.ignored_gate++; return false; }

bool app_link13_write(const uint8_t *msg, size_t n, uint32_t now)
{
    if (!msg || n < BC_LINK_HDR) return false;
    uint8_t t = msg[0];
    bool l13 = t == BC_MSG_APP_HELLO || (t >= BC_MSG_RIDEQ_LIST_REQ && t <= BC_MSG_RIDEQ_ERR) || (t >= BC_MSG_STORAGE_STATUS_REQ && t <= BC_MSG_STORAGE_CLEAN_RESULT)
               || (t >= BC_MSG_COACH_PLAN && t <= BC_MSG_COACH_END);
    if (!l13) return false;
    if (!L) return true;
    switch (t) {
    case BC_MSG_APP_HELLO: {
        bc_hello_t h; if (!bc_link_decode_hello(msg, n, &h)) return true;
        s_enabled = BC_CAPS_BOARD & h.app_caps; L->st.hellos++;   /* contract §4: enabled_caps = INFO caps AND app_caps */
        L->hello_ack_due = true;
        app_diag_set_auto_delete((s_enabled & BC_CAP_DIAG_AUTO) != 0);
        if (s_enabled & BC_CAP_STORAGE) L->status_due = true;
        if (s_enabled & BC_CAP_RIDE_QUEUE) { L->built = false; build_list(); L->pending_due = true; }
        char l[80]; snprintf(l, sizeof l, "LINK13: HELLO from app %.16s caps 0x%lx -> enabled 0x%lx", h.app_version, (unsigned long)h.app_caps, (unsigned long)s_enabled); plat_log(l);
        return true; }
    case BC_MSG_COACH_PLAN: {
        if (!gate(BC_CAP_COACH)) return true;
        bc_coach_plan_msg_t p; L->st.plan_parts++;
        if (!bc_link_decode_coach_plan(msg, n, &p)) { L->plan_ack.workout_id = 0; L->plan_ack.status = BC_PLAN_CRC; L->plan_ack.next_part = 0; L->plan_ack_due = true; return true; }
        uint16_t next = 0; uint8_t s = bc_cm_plan_part(&L->cm, &p, &next);
        L->plan_ack.workout_id = p.workout_id; L->plan_ack.status = s; L->plan_ack.next_part = next; L->plan_ack_due = true;
        if (s == BC_PLAN_COMPLETE) { char l[80]; snprintf(l, sizeof l, "LINK13: coach plan %lu stored (%u segments)", (unsigned long)p.workout_id, L->cm.nseg); plat_log(l); }
        return true; }
    case BC_MSG_COACH_STATE: {
        if (!gate(BC_CAP_COACH)) return true;
        bc_coach_state_t s; if (bc_link_decode_coach_state(msg, n, &s)) bc_cm_state(&L->cm, &s, now);
        return true; }
    case BC_MSG_COACH_END: {
        if (!gate(BC_CAP_COACH)) return true;
        bc_coach_end_t e; if (bc_link_decode_coach_end(msg, n, &e)) { bc_cm_end(&L->cm, e.workout_id); L->st.ends++; }
        return true; }
    case BC_MSG_RIDEQ_LIST_REQ:
        if (!gate(BC_CAP_RIDE_QUEUE) || !bc_link_decode_rideq_list_req(msg, n)) return true;
        build_list(); L->listing = true; L->list_i = 0; L->st.rq_lists++;
        return true;
    case BC_MSG_RIDEQ_CHUNK_REQ: {
        if (!gate(BC_CAP_RIDE_QUEUE)) return true;
        bc_diag_chunk_req_t q; if (!bc_link_decode_rideq_chunk_req(msg, n, &q)) return true;
        if (recording()) { rq_err(q.id, BC_DIAG_ERR_BUSY); L->st.rq_busy++; return true; }   /* the ride owns the link: retry later */
        if (L->ncq >= 4) { rq_err(q.id, BC_DIAG_ERR_BUSY); return true; }
        L->cq[L->ncq++] = q;
        return true; }
    case BC_MSG_RIDEQ_ACK: {
        if (!gate(BC_CAP_RIDE_QUEUE)) return true;
        bc_rideq_ack_t a; if (bc_link_decode_rideq_ack(msg, n, &a)) rq_ack(&a);
        return true; }
    case BC_MSG_STORAGE_STATUS_REQ:
        if (gate(BC_CAP_STORAGE) && bc_link_decode_storage_status_req(msg, n)) L->status_due = true;
        return true;
    case BC_MSG_STORAGE_CLEAN_REQ: {
        if (!gate(BC_CAP_STORAGE)) return true;
        bc_storage_clean_req_t c; if (bc_link_decode_storage_clean_req(msg, n, &c)) storage_clean(c.what);
        return true; }
    default:
        return true;                                           /* board -> phone types written by a phone: ignored */
    }
}

/* ------------------------------------------------------------------ notifications */
size_t app_link13_next(uint8_t *chr, uint8_t *buf, size_t cap, uint32_t now)
{
    if (!L || !s_ready) return 0;
    *chr = 0;
    if (L->hello_ack_due) { L->hello_ack_due = false; bc_hello_ack_t a = { s_enabled }; return bc_link_encode_hello_ack(&a, buf, cap, ++L->seq, now); }
    if (!s_enabled) return 0;
    if (L->plan_ack_due) { L->plan_ack_due = false; return bc_link_encode_coach_plan_ack(&L->plan_ack, buf, cap, ++L->seq, now); }
    if (L->clean_due) { L->clean_due = false; return bc_link_encode_storage_clean_result(&L->clean, buf, cap, ++L->seq, now); }
    if (L->status_due) { L->status_due = false; bc_storage_status_t s; storage_status(&s); return bc_link_encode_storage_status(&s, buf, cap, ++L->seq, now); }
    if (L->rerr_due) { L->rerr_due = false; return bc_link_encode_rideq_err(&L->rerr, buf, cap, ++L->seq, now); }
    if (L->rinfo_due) {
        L->rinfo_due = false; rq_ent_t *e = L->rinfo_has_ent && L->rinfo_ent.id == L->rinfo_id ? &L->rinfo_ent : find(L->rinfo_id);
        L->rinfo_has_ent = false;
        if (e) { bc_rideq_info_t i; rq_info(e, &i); return bc_link_encode_rideq_info(&i, buf, cap, ++L->seq, now); }
    }
    if (L->pending_due && (s_enabled & BC_CAP_RIDE_QUEUE)) {
        L->pending_due = false;
        uint32_t newest = 0; for (int i = 0; i < L->nq; i++) if (L->q[i].state != BC_RQ_RECORDING && L->q[i].id > newest) newest = L->q[i].id;
        bc_rides_pending_t p = { (uint8_t)(L->st.unsynced > 255 ? 255 : L->st.unsynced), newest };
        *chr = 2; return bc_link_encode_rides_pending(&p, buf, cap, ++L->seq, now);
    }
    if (L->ncq) {
        bc_diag_chunk_req_t q = L->cq[0];
        rq_ent_t *e = find(q.id);
        plat_phone_status_t ps; plat_phone_status(&ps);
        uint16_t room = bc_diag_chunk_data_max(q.max_len, ps.att_mtu);
        uint8_t code = 0;
        if (!e || e->state == BC_RQ_RECORDING || (e->flags & (BC_RQF_SUMMARY_ONLY | BC_RQF_RAM_ONLY)) || e->state == BC_RQ_SAMPLES_DELETED) code = BC_DIAG_ERR_UNKNOWN_ID;
        else if (recording()) code = BC_DIAG_ERR_BUSY;
        else if (q.offset > e->size) code = BC_DIAG_ERR_BAD_OFFSET;
        else if (!room && q.offset < e->size) code = BC_DIAG_ERR_MTU;
        if (!code) {   /* ride priority: a data chunk only when the link has room (LIVE first), at most one per 200 ms */
            if (!bc_diag_pace_ok(now, L->last_chunk_ms, L->chunk_sent, plat_phone_bulk_room())) return 0;
        }
        memmove(&L->cq[0], &L->cq[1], sizeof L->cq[0] * (size_t)(L->ncq - 1)); L->ncq--;
        bc_diag_err_t er = { q.id, code };
        if (code) return bc_link_encode_rideq_err(&er, buf, cap, ++L->seq, now);
        bc_diag_chunk_t c; memset(&c, 0, sizeof c); c.id = q.id; c.offset = q.offset;
        uint32_t want = room, left = e->size - q.offset; if (want > left) want = left;
        if (want) {
            char p[32]; samples_path(e->id, p, sizeof p);
            long got = plat_file_read_at(p, (long)q.offset, (char *)c.data, want);
            if (got != (long)want) { er.code = BC_DIAG_ERR_STORAGE; return bc_link_encode_rideq_err(&er, buf, cap, ++L->seq, now); }
        }
        c.len = (uint8_t)want; c.last = q.offset + want >= e->size;
        e->xfer = true; if (e->state == BC_RQ_UNSYNCED) e->state = BC_RQ_TRANSFER;
        L->last_chunk_ms = now; L->chunk_sent = true; L->st.rq_chunks++;
        return bc_link_encode_rideq_chunk(&c, buf, cap, ++L->seq, now);
    }
    if (L->listing) {
        if (L->list_i < L->nq) {
            rq_ent_t *e = &L->q[L->list_i++]; ensure_crc(e);
            bc_rideq_info_t i; rq_info(e, &i); return bc_link_encode_rideq_info(&i, buf, cap, ++L->seq, now);
        }
        L->listing = false;
        bc_rideq_list_end_t le = { (uint16_t)L->nq, L->st.unsynced, L->st.unsynced_bytes };
        return bc_link_encode_rideq_list_end(&le, buf, cap, ++L->seq, now);
    }
    return 0;
}

void app_link13_phone_ready(bool ready)
{
    if (ready == s_ready) return;
    s_ready = ready;
    s_enabled = 0;                                     /* every connection starts on 1.2.3 until its HELLO */
    if (!L) return;
    L->hello_ack_due = L->plan_ack_due = L->status_due = L->clean_due = L->pending_due = false;
    L->listing = false; L->ncq = 0; L->rinfo_due = L->rerr_due = false;
    for (int i = 0; i < L->nq; i++) L->q[i].xfer = false;
    /* the coach plan and the last state stay: the board follows the plan while the phone is gone */
}

void app_link13_ride_closed(void)
{
    if (!L) return;
    L->built = false; build_list();
    if (s_enabled & BC_CAP_RIDE_QUEUE) L->pending_due = true;
}

void app_link13_live(bc_live_t *l, uint32_t now)
{
    if (!L) return;
    bc_cm_view_t v; bc_cm_view(&L->cm, phone_live(), now, elapsed_now(), &v);
    if (v.mode != BC_CM_NONE) { l->has_coach = true; l->coach_seq = L->cm.have_state ? L->cm.st.seq : 0; l->coach_mode = v.mode; }
    uint8_t s = (uint8_t)plat_storage_state(); l->storage_state = s;
    l->rides_unsynced = (uint8_t)(L->st.unsynced > 255 ? 255 : L->st.unsynced);
    uint8_t f = 0;
    uint16_t skip = app_diag_skip();
    if (skip & (BC_SS_BIT(BC_SS_CENTRAL) | BC_SS_BIT(BC_SS_POWER) | BC_SS_BIT(BC_SS_HR) | BC_SS_BIT(BC_SS_CSC) | BC_SS_BIT(BC_SS_BTSTACK))) f |= 1;
    plat_phone_status_t ps; plat_phone_status(&ps);
    if (ps.notify_fails != L->notify_fails_seen) { L->notify_fails_seen = ps.notify_fails; L->notify_fail_ms = now ? now : 1; }
    if (L->notify_fail_ms && now - L->notify_fail_ms < 10000) f |= 2;
    l->bt_flags = f;
}

bool app_link13_coach(bc_cm_view_t *v)
{
    if (!L) { memset(v, 0, sizeof *v); return false; }
    bc_cm_view(&L->cm, phone_live(), plat_ms(), elapsed_now(), v);
    return v->mode != BC_CM_NONE;
}
