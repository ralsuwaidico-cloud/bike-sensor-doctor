/* Fake NimBLE world for test/blehost: see fake_nimble.h for the semantics that are modelled. */

#include "fake_nimble.h"
#include <stdarg.h>
#include <time.h>
#include <unistd.h>
#include <errno.h>

fake_cfg_t g_fake = { .speed = 20, .meter_in_range = true, .meter_streams = true };
fake_stats_t g_fstats;
struct ble_hs_cfg ble_hs_cfg;

/* ------------------------------------------------------------------ clock, logging, misc */
static struct timespec t0;
static uint64_t real_us(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (uint64_t)(t.tv_sec - t0.tv_sec) * 1000000u + (uint64_t)((t.tv_nsec - t0.tv_nsec) / 1000); }
uint32_t fake_now(void) { return (uint32_t)(real_us() * (uint64_t)g_fake.speed / 1000u); }
uint32_t hw_millis(void) { return fake_now(); }
int64_t esp_timer_get_time(void) { return (int64_t)fake_now() * 1000; }
void fake_sleep_v(uint32_t vms) { usleep((useconds_t)((uint64_t)vms * 1000u / (uint64_t)g_fake.speed) + 1); }
void vTaskDelay(TickType_t t) { fake_sleep_v(t); }
static bool s_verbose;
static pthread_mutex_t s_logm = PTHREAD_MUTEX_INITIALIZER;
static uint64_t s_loglines;
void fake_log(char lvl, const char *tag, const char *fmt, ...)
{
    char b[400]; va_list ap; va_start(ap, fmt); vsnprintf(b, sizeof b, fmt, ap); va_end(ap);
    pthread_mutex_lock(&s_logm); s_loglines++;
    if (s_verbose || getenv("BLEHOST_LOG")) printf("%c %6u %s: %s\n", lvl, fake_now(), tag, b);
    pthread_mutex_unlock(&s_logm);
}
static unsigned s_seed = 1;
static pthread_mutex_t s_rm = PTHREAD_MUTEX_INITIALIZER;
static uint32_t rnd(void) { pthread_mutex_lock(&s_rm); s_seed = s_seed * 1103515245u + 12345u; uint32_t r = s_seed >> 8; pthread_mutex_unlock(&s_rm); return r; }
static bool chance(int per_mille) { return per_mille > 0 && (int)(rnd() % 1000) < per_mille; }
uint32_t esp_random(void) { return rnd() ^ (rnd() << 16); }
void esp_fill_random(void *b, size_t n) { for (size_t i = 0; i < n; i++) ((uint8_t *)b)[i] = (uint8_t)rnd(); }
static esp_app_desc_t s_desc = { .version = "host" };
const esp_app_desc_t *esp_app_get_description(void) { return &s_desc; }
static pthread_mutex_t s_vm = PTHREAD_MUTEX_INITIALIZER;
void fake_violation(const char *fmt, ...)
{
    char b[200]; va_list ap; va_start(ap, fmt); vsnprintf(b, sizeof b, fmt, ap); va_end(ap);
    pthread_mutex_lock(&s_vm);
    if (!g_fstats.first_violation[0]) snprintf(g_fstats.first_violation, sizeof g_fstats.first_violation, "%s", b);
    pthread_mutex_unlock(&s_vm);
    if (getenv("BLEHOST_LOG")) printf("VIOLATION %s\n", b);
}

/* ------------------------------------------------------------------ locks */
static __thread int t_crit;
static __thread const char *t_name = "?";
static pthread_mutex_t s_hs = PTHREAD_RECURSIVE_MUTEX_INITIALIZER_NP;
static void hs_lock(void)
{
    if (t_crit > 0) { g_fstats.crit_lock_violations++; fake_violation("host lock taken inside portENTER_CRITICAL on thread %s", t_name); }
    pthread_mutex_lock(&s_hs);
}
static void hs_unlock(void) { pthread_mutex_unlock(&s_hs); }
void fake_crit_enter(portMUX_TYPE *m) { pthread_mutex_lock(&m->m); t_crit++; }
void fake_crit_exit(portMUX_TYPE *m) { t_crit--; pthread_mutex_unlock(&m->m); }

/* ------------------------------------------------------------------ tasks */
typedef struct { void (*fn)(void *); void *arg; char name[16]; pthread_t th; } task_t;
static task_t s_tasks[16]; static int s_ntasks;
static void *task_main(void *p) { task_t *t = p; t_name = t->name; t->fn(t->arg); return NULL; }
BaseType_t xTaskCreatePinnedToCore(void (*fn)(void *), const char *name, uint32_t stack, void *arg, UBaseType_t prio, TaskHandle_t *h, BaseType_t core)
{
    (void)stack; (void)prio; (void)core;
    task_t *t = &s_tasks[s_ntasks++]; t->fn = fn; t->arg = arg; snprintf(t->name, sizeof t->name, "%s", name);
    pthread_create(&t->th, NULL, task_main, t); pthread_detach(t->th);
    if (h) *h = t;
    return pdPASS;
}
TaskHandle_t xTaskGetHandle(const char *name) { for (int i = 0; i < s_ntasks; i++) if (!strcmp(s_tasks[i].name, name)) return &s_tasks[i]; return NULL; }
UBaseType_t uxTaskGetStackHighWaterMark(TaskHandle_t t) { (void)t; return 1000; }

/* ------------------------------------------------------------------ NVS (in memory) */
typedef struct { char ns[16], key[16]; uint8_t v[64]; size_t n; } nvs_item_t;
static nvs_item_t s_nvs[64]; static int s_nnvs; static char s_nvs_ns[8][16]; static int s_nns;
esp_err_t nvs_open(const char *ns, nvs_open_mode_t m, nvs_handle_t *h)
{
    (void)m; for (int i = 0; i < s_nns; i++) if (!strcmp(s_nvs_ns[i], ns)) { *h = (nvs_handle_t)i; return ESP_OK; }
    if (s_nns >= 8) return ESP_FAIL;
    snprintf(s_nvs_ns[s_nns], 16, "%s", ns); *h = (nvs_handle_t)s_nns++; return ESP_OK;
}
static nvs_item_t *nvs_find(nvs_handle_t h, const char *k, bool make)
{
    for (int i = 0; i < s_nnvs; i++) if (!strcmp(s_nvs[i].ns, s_nvs_ns[h]) && !strcmp(s_nvs[i].key, k)) return &s_nvs[i];
    if (!make || s_nnvs >= 64) return NULL;
    nvs_item_t *it = &s_nvs[s_nnvs++]; snprintf(it->ns, 16, "%s", s_nvs_ns[h]); snprintf(it->key, 16, "%s", k); it->n = 0; return it;
}
esp_err_t nvs_get_blob(nvs_handle_t h, const char *k, void *v, size_t *n) { nvs_item_t *it = nvs_find(h, k, false); if (!it) return ESP_ERR_NVS_NOT_FOUND; if (v) { if (*n < it->n) return ESP_FAIL; memcpy(v, it->v, it->n); } *n = it->n; return ESP_OK; }
esp_err_t nvs_set_blob(nvs_handle_t h, const char *k, const void *v, size_t n) { nvs_item_t *it = nvs_find(h, k, true); if (!it || n > sizeof it->v) return ESP_FAIL; memcpy(it->v, v, n); it->n = n; return ESP_OK; }
esp_err_t nvs_get_u8(nvs_handle_t h, const char *k, uint8_t *v) { size_t n = 1; return nvs_get_blob(h, k, v, &n); }
esp_err_t nvs_set_u8(nvs_handle_t h, const char *k, uint8_t v) { return nvs_set_blob(h, k, &v, 1); }
esp_err_t nvs_get_u32(nvs_handle_t h, const char *k, uint32_t *v) { size_t n = 4; return nvs_get_blob(h, k, v, &n); }
esp_err_t nvs_set_u32(nvs_handle_t h, const char *k, uint32_t v) { return nvs_set_blob(h, k, &v, 4); }
esp_err_t nvs_commit(nvs_handle_t h) { (void)h; return ESP_OK; }
void nvs_close(nvs_handle_t h) { (void)h; }

/* ------------------------------------------------------------------ UUIDs, mbufs */
uint16_t ble_uuid_u16(const ble_uuid_t *u) { return u->type == BLE_UUID_TYPE_16 ? ((const ble_uuid16_t *)u)->value : 0; }
int ble_uuid_cmp(const ble_uuid_t *a, const ble_uuid_t *b)
{
    if (a->type != b->type) return a->type - b->type;
    if (a->type == BLE_UUID_TYPE_16) return (int)((const ble_uuid16_t *)a)->value - (int)((const ble_uuid16_t *)b)->value;
    return memcmp(((const ble_uuid128_t *)a)->value, ((const ble_uuid128_t *)b)->value, 16);
}
static int s_mbufs_live;
struct os_mbuf *ble_hs_mbuf_from_flat(const void *buf, uint16_t len)
{
    if (len > 512) return NULL;
    struct os_mbuf *om = calloc(1, sizeof *om); om->len = len; if (len) memcpy(om->data, buf, len);
    __atomic_add_fetch(&s_mbufs_live, 1, __ATOMIC_SEQ_CST); return om;
}
void fake_mbuf_free(struct os_mbuf *om) { if (om) { __atomic_sub_fetch(&s_mbufs_live, 1, __ATOMIC_SEQ_CST); free(om); } }
int os_mbuf_copydata(const struct os_mbuf *om, int off, int len, void *dst) { if (off < 0 || len < 0 || off + len > om->len) return -1; memcpy(dst, om->data + off, (size_t)len); return 0; }
int os_mbuf_append(struct os_mbuf *om, const void *d, uint16_t len) { if (om->len + len > 512) return BLE_HS_ENOMEM; memcpy(om->data + om->len, d, len); om->len += len; return 0; }

/* ------------------------------------------------------------------ the meter's GATT table (XDS-A001 layout + 4 other services) */
typedef struct { uint16_t h, type, props; } attr_t;   /* type: 0x2800 svc, 0x2803 chr decl (props), value uuid, 0x2902 CCCD */
static const attr_t DB[] = {
    { 0x01, 0x2800, 0x1800 }, { 0x02, 0x2803, 0x02 }, { 0x03, 0x2A00, 0 }, { 0x04, 0x2803, 0x02 }, { 0x05, 0x2A01, 0 },
    { 0x06, 0x2800, 0x1801 }, { 0x07, 0x2803, 0x20 }, { 0x08, 0x2A05, 0 }, { 0x09, 0x2902, 0 },
    { 0x0A, 0x2800, 0x180A }, { 0x0B, 0x2803, 0x02 }, { 0x0C, 0x2A29, 0 }, { 0x0D, 0x2803, 0x02 }, { 0x0E, 0x2A24, 0 },
    { 0x20, 0x2800, 0x1828 }, { 0x21, 0x2803, 0x10 }, { 0x22, 0x2A63, 0 }, { 0x23, 0x2902, 0 },
    { 0x24, 0x2803, 0x02 }, { 0x25, 0x2A65, 0 }, { 0x26, 0x2803, 0x02 }, { 0x27, 0x2A5D, 0 },
    { 0x28, 0x2803, 0x28 }, { 0x29, 0x2A55, 0 }, { 0x2A, 0x2902, 0 },
    { 0x30, 0x2800, 0x180F }, { 0x31, 0x2803, 0x12 }, { 0x32, 0x2A19, 0 }, { 0x33, 0x2902, 0 },
};
#define NDB ((int)(sizeof DB / sizeof *DB))
static const attr_t *db_find(uint16_t h) { for (int i = 0; i < NDB; i++) if (DB[i].h == h) return &DB[i]; return NULL; }
static uint16_t svc_end(int i) { for (int j = i + 1; j < NDB; j++) if (DB[j].type == 0x2800) return (uint16_t)(DB[j].h - 1); return 0x3F; }

/* ------------------------------------------------------------------ connections, procedures, the host event queue */
enum { ROLE_NONE = 0, ROLE_METER, ROLE_PHONE };
typedef struct { int role; ble_gap_event_fn *cb; void *arg; uint16_t cccd[64]; bool enc; uint32_t gen; } conn_t;
#define NCONN 4
static conn_t s_conn[NCONN];
static uint32_t s_gen;
enum { P_MTU = 1, P_SVCS, P_SVC_UUID, P_CHRS, P_CHRS_UUID, P_DSCS, P_WRITE, P_READ };
typedef struct { bool used; int type; uint16_t conn; uint32_t gen; void *cb, *arg; uint16_t s, e, h, uuid; uint8_t v[4]; uint16_t n; } proc_t;
#define NPROC 4
static proc_t s_proc[NPROC];

typedef void (*ev_fn)(void *p);
typedef struct qev { uint32_t due; ev_fn fn; void *p; struct ble_npl_event *npl; struct qev *next; } qev_t;
static qev_t *s_q; static pthread_mutex_t s_qm = PTHREAD_MUTEX_INITIALIZER; static pthread_cond_t s_qc = PTHREAD_COND_INITIALIZER;
static volatile bool s_run = true;
static void q_push(uint32_t delay, ev_fn fn, void *p, struct ble_npl_event *npl)
{
    qev_t *e = calloc(1, sizeof *e); e->due = fake_now() + delay; e->fn = fn; e->p = p; e->npl = npl;
    pthread_mutex_lock(&s_qm);
    qev_t **pp = &s_q; while (*pp && (*pp)->due <= e->due) pp = &(*pp)->next;
    e->next = *pp; *pp = e;
    pthread_cond_signal(&s_qc); pthread_mutex_unlock(&s_qm);
}
static int conn_alive(uint16_t c) { return c < NCONN && s_conn[c].role != ROLE_NONE; }

/* ---- the host's own work: break a connection (procs fail first, then the GAP event) */
typedef struct { uint16_t conn; int reason; } brk_t;
static void ev_break(void *p)
{
    brk_t *b = p; uint16_t c = b->conn; int reason = b->reason; free(b);
    hs_lock();
    if (!conn_alive(c)) { hs_unlock(); return; }
    conn_t cc = s_conn[c]; s_conn[c].role = ROLE_NONE;
    proc_t failed[NPROC]; int nf = 0;
    for (int i = 0; i < NPROC; i++) if (s_proc[i].used && s_proc[i].conn == c) { failed[nf++] = s_proc[i]; s_proc[i].used = false; }
    hs_unlock();
    struct ble_gatt_error e = { .status = BLE_HS_ENOTCONN };
    for (int i = 0; i < nf; i++) {
        proc_t *p2 = &failed[i];
        switch (p2->type) {
        case P_MTU: ((ble_gatt_mtu_fn *)p2->cb)(c, &e, 0, p2->arg); break;
        case P_SVCS: case P_SVC_UUID: ((ble_gatt_disc_svc_fn *)p2->cb)(c, &e, NULL, p2->arg); break;
        case P_CHRS: case P_CHRS_UUID: ((ble_gatt_chr_fn *)p2->cb)(c, &e, NULL, p2->arg); break;
        case P_DSCS: ((ble_gatt_dsc_fn *)p2->cb)(c, &e, 0, NULL, p2->arg); break;
        case P_WRITE: case P_READ: if (p2->cb) ((ble_gatt_attr_fn *)p2->cb)(c, &e, NULL, p2->arg); break;
        }
    }
    if (cc.role == ROLE_PHONE) g_fstats.phone_disconnects++; else g_fstats.disconnects++;
    struct ble_gap_event ev; memset(&ev, 0, sizeof ev); ev.type = BLE_GAP_EVENT_DISCONNECT; ev.disconnect.reason = reason; ev.disconnect.conn.conn_handle = c;
    cc.cb(&ev, cc.arg);
}
static void break_conn(uint16_t c, int reason, uint32_t delay) { brk_t *b = malloc(sizeof *b); b->conn = c; b->reason = reason; q_push(delay, ev_break, b, NULL); }

/* ---- GATT client procedures */
static int proc_new(int type, uint16_t conn, void *cb, void *arg, proc_t **out)
{
    if (!conn_alive(conn)) { g_fstats.stale_conn_ops++; return BLE_HS_ENOTCONN; }
    if (s_conn[conn].role == ROLE_PHONE) { g_fstats.foreign_gatt_ops++; fake_violation("sensor GATT procedure %d issued on the PHONE's connection %u", type, conn); }
    if (chance(g_fake.p_enomem)) { g_fstats.proc_enomem++; return BLE_HS_ENOMEM; }
    for (int i = 0; i < NPROC; i++) if (!s_proc[i].used) {
        memset(&s_proc[i], 0, sizeof s_proc[i]); s_proc[i].used = true; s_proc[i].type = type; s_proc[i].conn = conn; s_proc[i].gen = s_conn[conn].gen;
        s_proc[i].cb = cb; s_proc[i].arg = arg; *out = &s_proc[i]; g_fstats.procs++; return 0;
    }
    g_fstats.proc_enomem++; return BLE_HS_ENOMEM;
}
static void ev_proc(void *pp)
{
    proc_t *slot = pp;
    hs_lock();
    if (!slot->used) { hs_unlock(); return; }
    proc_t p = *slot; uint16_t c = p.conn;
    if (!conn_alive(c) || s_conn[c].gen != p.gen) { slot->used = false; hs_unlock(); return; }
    if (s_conn[c].role == ROLE_METER && chance(g_fake.p_disconnect_per_proc)) { hs_unlock(); break_conn(c, 0x08, 0); return; }
    if (p.type == P_MTU && chance(g_fake.p_no_mtu)) { hs_unlock(); g_fstats.mtu_timeouts++; return; }   /* stays in flight: the board's 2 s fallback must cope */
    slot->used = false;
    bool att_err = chance(g_fake.p_att_error);
    hs_unlock();
    struct ble_gatt_error ok = { 0 }, done = { .status = BLE_HS_EDONE }, bad = { .status = BLE_HS_ERR_ATT_BASE + 0x0A };
    switch (p.type) {
    case P_MTU: ((ble_gatt_mtu_fn *)p.cb)(c, &ok, 185, p.arg); break;
    case P_SVCS: case P_SVC_UUID:
        for (int i = 0; i < NDB && !att_err; i++) if (DB[i].type == 0x2800 && (p.type == P_SVCS || DB[i].props == p.uuid)) {
            struct ble_gatt_svc s = { .start_handle = DB[i].h, .end_handle = svc_end(i) }; s.uuid.u16.u.type = BLE_UUID_TYPE_16; s.uuid.u16.value = DB[i].props;
            ((ble_gatt_disc_svc_fn *)p.cb)(c, &ok, &s, p.arg);
        }
        ((ble_gatt_disc_svc_fn *)p.cb)(c, att_err ? &bad : &done, NULL, p.arg); break;
    case P_CHRS: case P_CHRS_UUID:
        for (int i = 0; i < NDB - 1 && !att_err; i++) if (DB[i].type == 0x2803 && DB[i].h >= p.s && DB[i].h <= p.e && (p.type == P_CHRS || DB[i + 1].type == p.uuid)) {
            struct ble_gatt_chr ch = { .def_handle = DB[i].h, .val_handle = DB[i + 1].h, .properties = (uint8_t)DB[i].props }; ch.uuid.u16.u.type = BLE_UUID_TYPE_16; ch.uuid.u16.value = DB[i + 1].type;
            ((ble_gatt_chr_fn *)p.cb)(c, &ok, &ch, p.arg);
        }
        ((ble_gatt_chr_fn *)p.cb)(c, att_err ? &bad : &done, NULL, p.arg); break;
    case P_DSCS:
        for (int i = 0; i < NDB && !att_err; i++) if (DB[i].h > p.s && DB[i].h <= p.e) {
            struct ble_gatt_dsc d = { .handle = DB[i].h }; d.uuid.u16.u.type = BLE_UUID_TYPE_16; d.uuid.u16.value = DB[i].type;
            ((ble_gatt_dsc_fn *)p.cb)(c, &ok, p.s, &d, p.arg);
        }
        ((ble_gatt_dsc_fn *)p.cb)(c, att_err ? &bad : &done, p.s, NULL, p.arg); break;
    case P_WRITE: {
        const attr_t *a = db_find(p.h); uint16_t v = (uint16_t)(p.v[0] | (p.v[1] << 8));
        if (!a || a->type != 0x2902 || p.n != 2 || (v != 1 && v != 2)) { g_fstats.bad_writes++; fake_violation("write to the sensor that is not a CCCD subscription: handle 0x%04X len %u", p.h, p.n); }
        else { hs_lock(); if (conn_alive(c)) s_conn[c].cccd[p.h & 63] = v; hs_unlock(); g_fstats.cccd_writes++; }
        struct ble_gatt_attr at = { .handle = p.h };
        if (p.cb) ((ble_gatt_attr_fn *)p.cb)(c, att_err ? &bad : &ok, &at, p.arg);
        break; }
    case P_READ: {
        hs_lock(); uint16_t v = conn_alive(c) ? s_conn[c].cccd[p.h & 63] : 0; hs_unlock();
        if (chance(g_fake.p_cccd_read_mismatch)) v = 0;
        struct os_mbuf *om = ble_hs_mbuf_from_flat((uint8_t[2]){ (uint8_t)v, (uint8_t)(v >> 8) }, 2);
        struct ble_gatt_attr at = { .handle = p.h, .om = om };
        bool fail = att_err || chance(g_fake.p_cccd_read_fail);
        ((ble_gatt_attr_fn *)p.cb)(c, fail ? &bad : &ok, fail ? NULL : &at, p.arg);
        fake_mbuf_free(om); break; }
    }
}
static int submit(int type, uint16_t conn, void *cb, void *arg, uint16_t s, uint16_t e, uint16_t h, uint16_t uuid, const void *v, uint16_t n)
{
    hs_lock();
    proc_t *p; int rc = proc_new(type, conn, cb, arg, &p);
    if (rc == 0) { p->s = s; p->e = e; p->h = h; p->uuid = uuid; p->n = n; if (v && n <= 4) memcpy(p->v, v, n); q_push(5 + rnd() % 40, ev_proc, p, NULL); }
    hs_unlock();
    return rc;
}
int ble_gattc_exchange_mtu(uint16_t c, ble_gatt_mtu_fn *cb, void *arg) { return submit(P_MTU, c, (void *)cb, arg, 0, 0, 0, 0, NULL, 0); }
int ble_gattc_disc_all_svcs(uint16_t c, ble_gatt_disc_svc_fn *cb, void *arg) { return submit(P_SVCS, c, (void *)cb, arg, 1, 0xFFFF, 0, 0, NULL, 0); }
int ble_gattc_disc_svc_by_uuid(uint16_t c, const ble_uuid_t *u, ble_gatt_disc_svc_fn *cb, void *arg) { return submit(P_SVC_UUID, c, (void *)cb, arg, 1, 0xFFFF, 0, ble_uuid_u16(u), NULL, 0); }
int ble_gattc_disc_all_chrs(uint16_t c, uint16_t s, uint16_t e, ble_gatt_chr_fn *cb, void *arg) { return submit(P_CHRS, c, (void *)cb, arg, s, e, 0, 0, NULL, 0); }
int ble_gattc_disc_chrs_by_uuid(uint16_t c, uint16_t s, uint16_t e, const ble_uuid_t *u, ble_gatt_chr_fn *cb, void *arg) { return submit(P_CHRS_UUID, c, (void *)cb, arg, s, e, 0, ble_uuid_u16(u), NULL, 0); }
int ble_gattc_disc_all_dscs(uint16_t c, uint16_t s, uint16_t e, ble_gatt_dsc_fn *cb, void *arg) { return submit(P_DSCS, c, (void *)cb, arg, s, e, 0, 0, NULL, 0); }
int ble_gattc_write_flat(uint16_t c, uint16_t h, const void *v, uint16_t n, ble_gatt_attr_fn *cb, void *arg) { return submit(P_WRITE, c, (void *)cb, arg, 0, 0, h, 0, v, n); }
int ble_gattc_read(uint16_t c, uint16_t h, ble_gatt_attr_fn *cb, void *arg) { return submit(P_READ, c, (void *)cb, arg, 0, 0, h, 0, NULL, 0); }
void ble_att_set_preferred_mtu(uint16_t mtu) { (void)mtu; }

/* ------------------------------------------------------------------ GAP central: scan + connect to the meter */
static const uint8_t METER_MAC[6] = { 0x11, 0x22, 0x33, 0x44, 0x55, 0x66 };
static bool s_scan; static ble_gap_event_fn *s_scan_cb; static void *s_scan_arg;
static struct { bool pending; ble_gap_event_fn *cb; void *arg; uint32_t gen; } s_pc;
int ble_gap_disc(uint8_t own, int32_t ms, const struct ble_gap_disc_params *p, ble_gap_event_fn *cb, void *arg)
{ (void)own; (void)ms; (void)p; hs_lock(); int rc = s_scan ? BLE_HS_EALREADY : 0; s_scan = true; s_scan_cb = cb; s_scan_arg = arg; hs_unlock(); return rc; }
int ble_gap_disc_cancel(void) { hs_lock(); int rc = s_scan ? 0 : BLE_HS_EALREADY; s_scan = false; hs_unlock(); return rc; }
static int meter_conn(void) { for (int i = 0; i < NCONN; i++) if (s_conn[i].role == ROLE_METER) return i; return -1; }
static int alloc_conn(void) { for (int i = 0; i < NCONN; i++) if (s_conn[i].role == ROLE_NONE) return i; return -1; }
typedef struct { uint32_t gen; } pc_t;
static void ev_connect_done(void *p)
{
    pc_t *x = p; uint32_t gen = x->gen; free(x);
    hs_lock();
    if (!s_pc.pending || s_pc.gen != gen) { hs_unlock(); return; }
    s_pc.pending = false;
    ble_gap_event_fn *cb = s_pc.cb; void *arg = s_pc.arg;
    struct ble_gap_event ev; memset(&ev, 0, sizeof ev); ev.type = BLE_GAP_EVENT_CONNECT;
    int c = -1;
    if (g_fake.meter_in_range && !chance(g_fake.p_conn_fail) && meter_conn() < 0 && (c = alloc_conn()) >= 0) {
        memset(&s_conn[c], 0, sizeof s_conn[c]); s_conn[c].role = ROLE_METER; s_conn[c].cb = cb; s_conn[c].arg = arg; s_conn[c].gen = ++s_gen;
        ev.connect.status = 0; ev.connect.conn_handle = (uint16_t)c; g_fstats.connects++;
    } else { ev.connect.status = BLE_HS_ETIMEOUT; ev.connect.conn_handle = BLE_HS_CONN_HANDLE_NONE; }
    hs_unlock();
    cb(&ev, arg);
}
int ble_gap_connect(uint8_t own, const ble_addr_t *peer, int32_t ms, const struct ble_gap_conn_params *p, ble_gap_event_fn *cb, void *arg)
{
    (void)own; (void)peer; (void)ms; (void)p;
    hs_lock();
    if (s_pc.pending) { hs_unlock(); return BLE_HS_EALREADY; }
    if (s_scan) { hs_unlock(); return BLE_HS_EBUSY; }
    s_pc.pending = true; s_pc.cb = cb; s_pc.arg = arg; s_pc.gen++;
    pc_t *x = malloc(sizeof *x); x->gen = s_pc.gen; q_push(20 + rnd() % 200, ev_connect_done, x, NULL);
    hs_unlock(); return 0;
}
static void ev_cancelled(void *p)
{
    pc_t *x = p; free(x);
    hs_lock(); ble_gap_event_fn *cb = s_pc.cb; void *arg = s_pc.arg; hs_unlock();
    struct ble_gap_event ev; memset(&ev, 0, sizeof ev); ev.type = BLE_GAP_EVENT_CONNECT; ev.connect.status = BLE_HS_EAPP; ev.connect.conn_handle = BLE_HS_CONN_HANDLE_NONE;
    cb(&ev, arg);
}
int ble_gap_conn_cancel(void)
{
    hs_lock();
    if (!s_pc.pending) { hs_unlock(); return BLE_HS_EALREADY; }
    s_pc.pending = false; pc_t *x = malloc(sizeof *x); q_push(1, ev_cancelled, x, NULL);
    hs_unlock(); return 0;
}
static uint16_t s_phone_conn = BLE_HS_CONN_HANDLE_NONE;
int ble_gap_terminate(uint16_t c, uint8_t reason)
{
    (void)reason;
    hs_lock();
    if (!conn_alive(c)) { hs_unlock(); g_fstats.stale_conn_ops++; return BLE_HS_ENOTCONN; }
    hs_unlock();
    break_conn(c, 0x16, 5);
    return 0;
}
int ble_gap_conn_rssi(uint16_t c, int8_t *r) { hs_lock(); int ok = conn_alive(c); hs_unlock(); if (!ok) return BLE_HS_ENOTCONN; *r = -60; return 0; }
int ble_gap_conn_find(uint16_t c, struct ble_gap_conn_desc *d)
{
    hs_lock(); int ok = conn_alive(c);
    if (ok) { memset(d, 0, sizeof *d); d->conn_handle = c; d->conn_itvl = 24; d->sec_state.encrypted = s_conn[c].enc; d->sec_state.authenticated = s_conn[c].enc; d->peer_id_addr.type = 1; }
    hs_unlock(); return ok ? 0 : BLE_HS_ENOTCONN;
}
int ble_hs_adv_parse_fields(struct ble_hs_adv_fields *f, const uint8_t *d, uint8_t len)
{
    static __thread ble_uuid16_t u16s[8];
    memset(f, 0, sizeof *f);
    for (int i = 0; i + 1 < len;) {
        int l = d[i]; if (l == 0 || i + 1 + l > len) return BLE_HS_EBADDATA;
        uint8_t t = d[i + 1]; const uint8_t *v = d + i + 2; int n = l - 1;
        if (t == 0x01 && n >= 1) f->flags = v[0];
        else if ((t == 0x02 || t == 0x03) && n % 2 == 0) { for (int k = 0; k < n / 2 && f->num_uuids16 < 8; k++) { u16s[f->num_uuids16].u.type = BLE_UUID_TYPE_16; u16s[f->num_uuids16].value = (uint16_t)(v[2 * k] | (v[2 * k + 1] << 8)); f->num_uuids16++; } f->uuids16 = u16s; }
        else if (t == 0x08 || t == 0x09) { f->name = v; f->name_len = (uint8_t)n; f->name_is_complete = t == 0x09; }
        i += 1 + l;
    }
    return 0;
}
static void ev_scan(void *p)
{
    (void)p;
    hs_lock(); bool go = s_scan && g_fake.meter_in_range && meter_conn() < 0; ble_gap_event_fn *cb = s_scan_cb; void *arg = s_scan_arg; hs_unlock();
    if (go && cb) {
        static const uint8_t ADV[] = { 2, 0x01, 0x06, 3, 0x03, 0x18, 0x18, 9, 0x09, 'X', 'D', 'S', '-', 'A', '0', '0', '1' };
        uint8_t junk[31]; uint8_t jl = (uint8_t)(rnd() % 31); for (int i = 0; i < jl; i++) junk[i] = (uint8_t)rnd();
        struct ble_gap_event ev; memset(&ev, 0, sizeof ev); ev.type = BLE_GAP_EVENT_DISC; ev.disc.rssi = -55;
        bool other = rnd() % 4 == 0;
        if (other) { ev.disc.addr.val[0] = (uint8_t)rnd(); ev.disc.addr.val[5] = 0xC0; ev.disc.data = junk; ev.disc.length_data = jl; }
        else { memcpy(ev.disc.addr.val, METER_MAC, 6); ev.disc.data = ADV; ev.disc.length_data = sizeof ADV; }
        cb(&ev, arg);
    }
    if (s_run) q_push(60 + rnd() % 80, ev_scan, NULL, NULL);
}

/* ------------------------------------------------------------------ notifications from the meter */
static const uint8_t XDS_OK[11] = { 0x8E, 0x00, 0x47, 0x00, 0x47, 0x00, 0x52, 0x00, 0x5A, 0x00, 0x00 };   /* 142 W, 82 rpm, angle 90 */
static void ev_notify(void *p)
{
    (void)p;
    hs_lock();
    int c = meter_conn(); bool on = c >= 0 && s_conn[c].cccd[0x23] && g_fake.meter_streams;
    ble_gap_event_fn *cb = c >= 0 ? s_conn[c].cb : NULL; void *arg = c >= 0 ? s_conn[c].arg : NULL;
    bool other = c >= 0 && s_conn[c].cccd[0x2A] && chance(g_fake.p_other_handle * 5);
    hs_unlock();
    if ((on || other) && cb) {
        uint8_t b[40]; uint16_t n = 11; memcpy(b, XDS_OK, 11);
        if (chance(g_fake.p_bad_packet)) { n = (uint16_t)(rnd() % 40); for (int i = 0; i < n; i++) b[i] = (uint8_t)rnd(); g_fstats.bad_packets++; }
        struct os_mbuf *om = ble_hs_mbuf_from_flat(b, n);
        struct ble_gap_event ev; memset(&ev, 0, sizeof ev); ev.type = BLE_GAP_EVENT_NOTIFY_RX; ev.notify_rx.conn_handle = (uint16_t)c;
        ev.notify_rx.attr_handle = other || chance(g_fake.p_other_handle) ? 0x2A : 0x22; ev.notify_rx.om = om;
        cb(&ev, arg); fake_mbuf_free(om); g_fstats.notifies_rx++;
    }
    if (s_run) q_push(200 + rnd() % 100, ev_notify, NULL, NULL);
}

/* ------------------------------------------------------------------ GATT server (the phone link service) + the fake phone */
typedef struct { uint16_t h; ble_gatt_access_fn *cb; void *arg; uint16_t flags; } schr_t;
static schr_t s_schr[16]; static int s_nschr; static uint16_t s_next_h = 0x40;
int ble_gatts_count_cfg(const struct ble_gatt_svc_def *d) { (void)d; return 0; }
int ble_gatts_add_svcs(const struct ble_gatt_svc_def *d)
{
    for (; d->type; d++) for (const struct ble_gatt_chr_def *c = d->characteristics; c && c->uuid; c++) {
        s_next_h += 2; if (c->val_handle) *c->val_handle = s_next_h;
        s_schr[s_nschr].h = s_next_h; s_schr[s_nschr].cb = c->access_cb; s_schr[s_nschr].arg = c->arg; s_schr[s_nschr].flags = c->flags; s_nschr++;
    }
    return 0;
}
void ble_svc_gap_init(void) {}
void ble_svc_gatt_init(void) {}
static char s_name[32] = "BikeComputer";
const char *ble_svc_gap_device_name(void) { return s_name; }
int ble_svc_gap_device_name_set(const char *n) { snprintf(s_name, sizeof s_name, "%s", n); return 0; }
int ble_gatts_notify_custom(uint16_t c, uint16_t h, struct os_mbuf *om)
{
    (void)h;
    hs_lock(); int ok = conn_alive(c) && s_conn[c].role == ROLE_PHONE; hs_unlock();
    fake_mbuf_free(om);
    if (!ok) return BLE_HS_ENOTCONN;
    __atomic_add_fetch(&g_fstats.phone_notifies, 1, __ATOMIC_SEQ_CST); return 0;
}
static bool s_adv; static ble_gap_event_fn *s_adv_cb; static void *s_adv_arg;
int ble_gap_adv_set_fields(const struct ble_hs_adv_fields *f) { (void)f; hs_lock(); hs_unlock(); return 0; }
int ble_gap_adv_rsp_set_fields(const struct ble_hs_adv_fields *f) { (void)f; hs_lock(); hs_unlock(); return 0; }
int ble_gap_adv_start(uint8_t own, const ble_addr_t *dir, int32_t ms, const struct ble_gap_adv_params *p, ble_gap_event_fn *cb, void *arg)
{ (void)own; (void)dir; (void)ms; (void)p; hs_lock(); int rc = s_adv ? BLE_HS_EALREADY : 0; s_adv = true; s_adv_cb = cb; s_adv_arg = arg; hs_unlock(); return rc; }
int ble_gap_adv_stop(void) { hs_lock(); int rc = s_adv ? 0 : BLE_HS_EALREADY; s_adv = false; hs_unlock(); return rc; }
int ble_sm_inject_io(uint16_t c, struct ble_sm_io *io) { (void)c; (void)io; hs_lock(); hs_unlock(); return 0; }
static int s_bonds = 1;
int ble_store_util_count(int type, int *out) { (void)type; hs_lock(); *out = s_bonds; hs_unlock(); return 0; }
int ble_store_util_delete_peer(const ble_addr_t *a) { (void)a; hs_lock(); hs_unlock(); return 0; }
int ble_store_clear(void) { hs_lock(); s_bonds = 0; hs_unlock(); return 0; }
int ble_hs_util_ensure_addr(int r) { (void)r; return 0; }
int ble_hs_id_infer_auto(int pr, uint8_t *own) { (void)pr; *own = 0; return 0; }
int ble_hs_id_gen_rnd(int nrpa, ble_addr_t *o) { (void)nrpa; esp_fill_random(o->val, 6); o->val[5] |= 0xC0; o->type = 1; return 0; }
int ble_hs_id_set_rnd(const uint8_t *a) { (void)a; return 0; }

/* phone: every step is a host-thread event, like the radio would deliver it */
typedef struct { int step; bool enc_ok; int hold_ms, writes; volatile int *done; } ph_t;
static void ev_phone(void *pp)
{
    ph_t *p = pp;
    if (p->step == 0) {                                     /* connect */
        hs_lock();
        int c = s_adv ? alloc_conn() : -1;
        if (c < 0) { hs_unlock(); *p->done = 2; free(p); return; }
        memset(&s_conn[c], 0, sizeof s_conn[c]); s_conn[c].role = ROLE_PHONE; s_conn[c].cb = s_adv_cb; s_conn[c].arg = s_adv_arg; s_conn[c].gen = ++s_gen; s_adv = false;
        s_phone_conn = (uint16_t)c; g_fstats.phone_connects++;
        ble_gap_event_fn *cb = s_adv_cb; void *arg = s_adv_arg; hs_unlock();
        struct ble_gap_event ev; memset(&ev, 0, sizeof ev); ev.type = BLE_GAP_EVENT_CONNECT; ev.connect.status = 0; ev.connect.conn_handle = (uint16_t)c;
        cb(&ev, arg);
        p->step = 1; q_push(10 + rnd() % 50, ev_phone, p, NULL); return;
    }
    uint16_t c = s_phone_conn;
    hs_lock(); bool alive = conn_alive(c) && s_conn[c].role == ROLE_PHONE; ble_gap_event_fn *cb = alive ? s_conn[c].cb : NULL; void *arg = alive ? s_conn[c].arg : NULL; hs_unlock();
    if (!alive) { *p->done = 1; free(p); return; }
    struct ble_gap_event ev; memset(&ev, 0, sizeof ev);
    if (p->step == 1) {                                     /* encryption */
        hs_lock(); s_conn[c].enc = p->enc_ok; hs_unlock();
        ev.type = BLE_GAP_EVENT_ENC_CHANGE; ev.enc_change.status = p->enc_ok ? 0 : 0x206; ev.enc_change.conn_handle = c; cb(&ev, arg);
        if (!p->enc_ok) { break_conn(c, 0x13, 20); p->step = 9; q_push(60, ev_phone, p, NULL); return; }
        p->step = 2; q_push(5 + rnd() % 20, ev_phone, p, NULL); return;
    }
    if (p->step == 2) {                                     /* subscribe to every notify characteristic */
        for (int i = 0; i < s_nschr; i++) if (s_schr[i].flags & BLE_GATT_CHR_F_NOTIFY) {
            memset(&ev, 0, sizeof ev); ev.type = BLE_GAP_EVENT_SUBSCRIBE; ev.subscribe.conn_handle = c; ev.subscribe.attr_handle = s_schr[i].h; ev.subscribe.cur_notify = 1; cb(&ev, arg);
        }
        p->step = 3; q_push(5, ev_phone, p, NULL); return;
    }
    if (p->step == 3 && p->writes > 0) {                    /* one write or read per step */
        p->writes--;
        int k = (int)(rnd() % (uint32_t)s_nschr); schr_t *s = &s_schr[k];
        struct os_mbuf *om = ble_hs_mbuf_from_flat(NULL, 0);
        struct ble_gatt_access_ctxt ctx = { .om = om };
        if (rnd() % 3 == 0) { ctx.op = BLE_GATT_ACCESS_OP_READ_CHR; }
        else {
            ctx.op = BLE_GATT_ACCESS_OP_WRITE_CHR;
            uint8_t b[200]; uint16_t n = (uint16_t)(rnd() % 200); for (int i = 0; i < n; i++) b[i] = (uint8_t)rnd();
            static const uint8_t TYPES[] = { 0x20, 0x21, 0x22, 0x24, 0x30, 0x50, 0x60, 0x66, 0x70, 0x76, 0x80, 0x83, 0x85 };
            if (n >= 8 && rnd() % 2) { b[0] = TYPES[rnd() % sizeof TYPES]; uint16_t p2 = 8; while (p2 + 2 < n) { uint8_t l = (uint8_t)(rnd() % 6); if (p2 + 2 + l > n) break; b[p2 + 1] = l; p2 += 2 + l; } n = p2; }
            os_mbuf_append(om, b, n);
        }
        s->cb(c, s->h, &ctx, s->arg);
        fake_mbuf_free(om);
        q_push(5 + rnd() % 30, ev_phone, p, NULL); return;
    }
    if (p->step == 3) { p->step = 4; q_push((uint32_t)p->hold_ms, ev_phone, p, NULL); return; }
    if (p->step == 4) { break_conn(c, rnd() % 4 ? 0x13 : 0x08, 0); p->step = 9; q_push(30, ev_phone, p, NULL); return; }
    *p->done = 1; free(p);
}
void fake_phone_cycle(bool enc_ok, int hold_ms, int writes)
{
    volatile int done = 0;
    for (int w = 0; w < 400; w++) { hs_lock(); bool a = s_adv; hs_unlock(); if (a) break; fake_sleep_v(10); }   /* the board advertises again */
    ph_t *p = calloc(1, sizeof *p); p->enc_ok = enc_ok; p->hold_ms = hold_ms; p->writes = writes; p->done = &done;
    q_push(1, ev_phone, p, NULL);
    while (!done) fake_sleep_v(5);
}

/* ------------------------------------------------------------------ timers (the esp_timer task) */
struct fake_timer { esp_timer_create_args_t a; bool armed; uint32_t due; };
static struct fake_timer s_timers[8]; static int s_ntimers; static pthread_mutex_t s_tm = PTHREAD_MUTEX_INITIALIZER;
esp_err_t esp_timer_create(const esp_timer_create_args_t *a, esp_timer_handle_t *out) { pthread_mutex_lock(&s_tm); s_timers[s_ntimers].a = *a; *out = &s_timers[s_ntimers++]; pthread_mutex_unlock(&s_tm); return ESP_OK; }
esp_err_t esp_timer_start_once(esp_timer_handle_t t, uint64_t us) { pthread_mutex_lock(&s_tm); esp_err_t r = t->armed ? ESP_FAIL : ESP_OK; t->armed = true; t->due = fake_now() + (uint32_t)(us / 1000); pthread_mutex_unlock(&s_tm); return r; }
esp_err_t esp_timer_stop(esp_timer_handle_t t) { pthread_mutex_lock(&s_tm); esp_err_t r = t->armed ? ESP_OK : ESP_FAIL; t->armed = false; pthread_mutex_unlock(&s_tm); return r; }
static void timer_task(void *p)
{
    (void)p;
    while (s_run) {
        for (int i = 0; i < s_ntimers; i++) {
            pthread_mutex_lock(&s_tm); bool fire = s_timers[i].armed && (int32_t)(fake_now() - s_timers[i].due) >= 0; if (fire) s_timers[i].armed = false; pthread_mutex_unlock(&s_tm);
            if (fire) s_timers[i].a.callback(s_timers[i].a.arg);
        }
        fake_sleep_v(2);
    }
}

/* ------------------------------------------------------------------ the host task */
static struct ble_npl_eventq s_dq;
struct ble_npl_eventq *nimble_port_get_dflt_eventq(void) { return &s_dq; }
void ble_npl_event_init(struct ble_npl_event *ev, ble_npl_event_fn *fn, void *arg) { memset(ev, 0, sizeof *ev); ev->fn = fn; ev->arg = arg; }
void *ble_npl_event_get_arg(struct ble_npl_event *ev) { return ev->arg; }
void ble_npl_eventq_put(struct ble_npl_eventq *q, struct ble_npl_event *ev)
{
    (void)q;
    if (__atomic_exchange_n(&ev->queued, true, __ATOMIC_SEQ_CST)) return;      /* already queued: like NimBLE's FreeRTOS port */
    q_push(0, NULL, NULL, ev);
}
esp_err_t nimble_port_init(void) { clock_gettime(CLOCK_MONOTONIC, &t0); return ESP_OK; }
void nimble_port_run(void)
{
    if (ble_hs_cfg.sync_cb) ble_hs_cfg.sync_cb();
    q_push(50, ev_scan, NULL, NULL); q_push(100, ev_notify, NULL, NULL);
    while (s_run) {
        pthread_mutex_lock(&s_qm);
        qev_t *e = s_q;
        if (!e || (int32_t)(fake_now() - e->due) < 0) {
            struct timespec ts; clock_gettime(CLOCK_REALTIME, &ts); ts.tv_nsec += 300000; if (ts.tv_nsec >= 1000000000) { ts.tv_sec++; ts.tv_nsec -= 1000000000; }
            pthread_cond_timedwait(&s_qc, &s_qm, &ts); pthread_mutex_unlock(&s_qm); continue;
        }
        s_q = e->next; pthread_mutex_unlock(&s_qm);
        if (e->npl) { __atomic_store_n(&e->npl->queued, false, __ATOMIC_SEQ_CST); g_fstats.npl_events++; e->npl->fn(e->npl); }
        else e->fn(e->p);
        free(e);
    }
}
void nimble_port_freertos_init(void (*fn)(void *)) { xTaskCreatePinnedToCore(fn, "nimble_host", 4096, NULL, 21, NULL, 0); }
void nimble_port_freertos_deinit(void) {}
void fake_start_world(void) { s_seed = (unsigned)(getenv("BLEHOST_SEED") ? atoi(getenv("BLEHOST_SEED")) : 12345); xTaskCreatePinnedToCore(timer_task, "esp_timer", 3584, NULL, 22, NULL, 0); }
void fake_stop_world(void) { s_run = false; usleep(200000); }
int fake_mbufs_live(void) { return s_mbufs_live; }
