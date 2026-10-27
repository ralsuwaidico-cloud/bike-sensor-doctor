/* bc_core — PORTABLE CORE. See bc_diag.h. */
#include "bc_diag.h"
#include "bc_pipe.h"
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

/* ------------------------------------------------------------------ CRC-32 */
uint32_t bc_crc32(uint32_t crc, const void *data, size_t n)
{
    const uint8_t *p = data; crc = ~crc;
    while (n--) { crc ^= *p++; for (int k = 0; k < 8; k++) crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1u))); }
    return ~crc;
}

/* ------------------------------------------------------------------ event records */
static void w32(uint8_t *b, uint32_t v) { b[0] = (uint8_t)v; b[1] = (uint8_t)(v >> 8); b[2] = (uint8_t)(v >> 16); b[3] = (uint8_t)(v >> 24); }
static uint32_t r32(const uint8_t *b) { return (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24); }
void bc_ev_encode(const bc_ev_t *e, uint8_t o[BC_EV_SIZE])
{
    w32(o, e->seq); w32(o + 4, e->boot); w32(o + 8, e->t_ms); o[12] = e->type; o[13] = e->x; o[14] = (uint8_t)e->a; o[15] = (uint8_t)(e->a >> 8);
    w32(o + 16, e->b); w32(o + 20, e->c); w32(o + 24, e->d); w32(o + 28, bc_crc32(0, o, 28));
}
bool bc_ev_decode(const uint8_t in[BC_EV_SIZE], bc_ev_t *e)
{
    bool ff = true, zz = true; for (int i = 0; i < BC_EV_SIZE; i++) { if (in[i] != 0xFF) ff = false; if (in[i]) zz = false; }
    if (ff || zz || r32(in + 28) != bc_crc32(0, in, 28) || in[12] == 0) return false;
    e->seq = r32(in); e->boot = r32(in + 4); e->t_ms = r32(in + 8); e->type = in[12]; e->x = in[13]; e->a = (uint16_t)(in[14] | (in[15] << 8));
    e->b = r32(in + 16); e->c = r32(in + 20); e->d = r32(in + 24);
    return true;
}
static const char *sens_name(unsigned s) { return s == 1 ? "power" : s == 2 ? "hr" : s == 3 ? "csc" : "?"; }
static const char *phone_state(unsigned s)
{ static const char *const N[] = { "off", "advertising", "connected", "pairing", "ready", "repair", "bt_unavailable" }; return s < 7 ? N[s] : "?"; }
static const char *wifi_state(unsigned s)
{ static const char *const N[] = { "off", "idle", "scanning", "connecting", "connected", "failed" }; return s < 6 ? N[s] : "?"; }
size_t bc_ev_text(const bc_ev_t *e, char *b, size_t cap)
{
    if (!cap) return 0;
    int n = snprintf(b, cap, "#%lu b%lu +%lu.%lus ", (unsigned long)e->seq, (unsigned long)e->boot, (unsigned long)(e->t_ms / 1000), (unsigned long)(e->t_ms % 1000 / 100));
    if (n < 0 || (size_t)n >= cap) return cap - 1;
    char *p = b + n; size_t r = cap - (size_t)n; int k = 0;
    switch (e->type) {
    case BC_EV_BOOT: k = snprintf(p, r, "BOOT reset %s, crash streak %lu, boot #%lu, mode %s, skip 0x%03lX", bc_reset_name((bc_reset_t)e->a), (unsigned long)e->b, (unsigned long)e->c,
                                  (e->d & 0xFF) == 1 ? "staged" : (e->d & 0xFF) == 2 ? "recovery" : "normal", (unsigned long)(e->d >> 8)); break;
    case BC_EV_CRASH: k = snprintf(p, r, "CRASH report %u pc 0x%08lX cause %lu%s", e->a, (unsigned long)e->b, (unsigned long)e->c, e->x ? " (core dump)" : " (no core dump)"); break;
    case BC_EV_STAGE: k = snprintf(p, r, "STAGE subsystem %u %s", e->a, e->x == 0 ? "starting" : e->x == 1 ? "up" : e->x == 2 ? "SKIPPED (disabled after a crash)" : "FAILED"); break;
    case BC_EV_SENSOR: { char age[16]; if (e->d == UINT32_MAX) snprintf(age, sizeof age, "none"); else snprintf(age, sizeof age, "%lums", (unsigned long)e->d);
        k = snprintf(p, r, "SENSOR %s -> %s pkts %lu rej %lu valid age %s", sens_name(e->a), bc_stage_name((bc_stage_t)e->x), (unsigned long)e->b, (unsigned long)e->c, age); break; }
    case BC_EV_RECOVERY: k = snprintf(p, r, "RECOVERY %s %s (#%lu)", sens_name(e->a), e->x == 1 ? "re-subscribe" : e->x == 2 ? "reconnect" : e->x == 3 ? "RETRY by rider" : e->x == 4 ? "link disabled after a crash" : "?", (unsigned long)e->b); break;
    case BC_EV_PHONE: k = snprintf(p, r, "PHONE %s (last disconnect 0x%x, connects %lu, bonds %lu)", phone_state(e->x), e->a, (unsigned long)e->b, (unsigned long)e->c); break;
    case BC_EV_WIFI: k = snprintf(p, r, "WIFI %s err %u rssi %ld", wifi_state(e->x), e->a, (long)(int32_t)e->b); break;
    case BC_EV_HEALTH: k = snprintf(p, r, "HEALTH heap %uK min %luB stack free lvgl %lu nimble %lu mgr %lu timer %lu", e->a, (unsigned long)e->b, (unsigned long)(e->c >> 16), (unsigned long)(e->c & 0xFFFF),
                                    (unsigned long)(e->d >> 16), (unsigned long)(e->d & 0xFFFF)); break;
    case BC_EV_READING: {
        char w[12], c[12], h[12];
        if (e->a == 0xFFFF) snprintf(w, sizeof w, "--"); else snprintf(w, sizeof w, "%u W", e->a);
        if ((e->b & 0xFFFF) == 0xFFFF) snprintf(c, sizeof c, "--"); else snprintf(c, sizeof c, "%lu rpm", (unsigned long)(e->b & 0xFFFF));
        if ((e->b >> 16) == 0xFFFF) snprintf(h, sizeof h, "--"); else snprintf(h, sizeof h, "%lu bpm", (unsigned long)(e->b >> 16));
        k = snprintf(p, r, "READING %s %s %s (power age %lums, hr age %lums, hr src %u)", w, c, h, (unsigned long)e->c, (unsigned long)e->d, e->x); break; }
    case BC_EV_LIVE: k = snprintf(p, r, "LIVE %u sent in the last minute, %lu notifications total, last %lums ago", e->a, (unsigned long)e->b, (unsigned long)e->c); break;
    case BC_EV_ALERT: k = snprintf(p, r, "ALERT %s value %lu threshold %lu", bc_health_alert_name((bc_health_alert_t)e->a), (unsigned long)e->b, (unsigned long)e->c); break;
    case BC_EV_REPORT: k = snprintf(p, r, "REPORT %u kind %u %s", e->a, e->x, e->b == 0 ? "stored" : e->b == 1 ? "sent (crc ok)" : e->b == 2 ? "NOT stored (store full of unsent reports)" : "ack crc mismatch"); break;
    case BC_EV_TOUCH: k = snprintf(p, r, "TOUCH wakes %u reports %lu passed %lu controller resets %lu", e->a, (unsigned long)e->b, (unsigned long)e->c, (unsigned long)e->d); break;
    case BC_EV_NOTE: k = snprintf(p, r, "NOTE %s %lu", e->a == 1 ? "events dropped from the RAM queue:" : e->a == 2 ? "event log file reset, size" : "?", (unsigned long)e->b); break;
    case BC_EV_MODE: k = snprintf(p, r, "RECOVERY SCREEN %s", e->x == 1 ? "RESTART & DIAGNOSE" : e->x == 2 ? "SEND LOGS" : e->x == 3 ? "phone connected" : e->x == 4 ? "report sent" : "?"); break;
    default: k = snprintf(p, r, "type %u", e->type); break;
    }
    if (k < 0) k = 0;
    size_t t = (size_t)n + (size_t)k;
    return t < cap ? t : cap - 1;
}

/* ------------------------------------------------------------------ event log ring */
void bc_evlog_init(bc_evlog_t *l, uint32_t nslots, uint32_t boot) { memset(l, 0, sizeof *l); l->nslots = nslots ? nslots : 1; l->next_seq = 1; l->boot = boot; }
void bc_evlog_resume(bc_evlog_t *l, const uint8_t *raw, uint32_t nslots)
{
    uint32_t best = 0; bc_ev_t e;
    for (uint32_t i = 0; raw && i < nslots; i++) if (bc_ev_decode(raw + (size_t)i * BC_EV_SIZE, &e) && e.seq > best) best = e.seq;
    l->next_seq = best + 1;
}
static bool low_prio(uint8_t t) { return t == BC_EV_READING || t == BC_EV_HEALTH || t == BC_EV_LIVE || t == BC_EV_TOUCH; }
void bc_evlog_add(bc_evlog_t *l, uint8_t type, uint8_t x, uint16_t a, uint32_t b, uint32_t c, uint32_t d, uint32_t now_ms)
{
    if (l->npend >= BC_EVLOG_PEND) {
        int drop = 0;
        for (int i = 0; i < l->npend; i++) if (low_prio(l->pend[i].type)) { drop = i; break; }
        memmove(&l->pend[drop], &l->pend[drop + 1], sizeof l->pend[0] * (size_t)(l->npend - drop - 1));
        l->npend--; l->dropped++;
        /* sequence numbers stay unique; the dropped one simply never reaches the file */
    }
    bc_ev_t *e = &l->pend[l->npend++];
    e->seq = l->next_seq++; e->boot = l->boot; e->t_ms = now_ms; e->type = type; e->x = x; e->a = a; e->b = b; e->c = c; e->d = d;
}
bool bc_evlog_flush_due(const bc_evlog_t *l, uint32_t now_ms, bool force)
{
    if (!l->npend) return false;
    if (force || !l->flushed_once) return true;
    return now_ms - l->last_flush_ms >= BC_EVLOG_FLUSH_MS;
}
int bc_evlog_take(bc_evlog_t *l, bc_ev_t *out, int max, uint32_t now_ms)
{
    int n = l->npend < max ? l->npend : max;
    memcpy(out, l->pend, sizeof *out * (size_t)n);
    memmove(l->pend, l->pend + n, sizeof *out * (size_t)(l->npend - n)); l->npend -= n;
    l->last_flush_ms = now_ms; l->flushed_once = true;
    return n;
}
int bc_evlog_newest(const uint8_t *raw, uint32_t nslots, bc_ev_t *out, int n)
{
    /* keep the n records with the largest seq (insertion into a sorted window), then oldest first */
    int k = 0; bc_ev_t e;
    for (uint32_t i = 0; raw && i < nslots && n > 0; i++) {
        if (!bc_ev_decode(raw + (size_t)i * BC_EV_SIZE, &e)) continue;
        if (k < n) { int j = k++; while (j > 0 && out[j - 1].seq > e.seq) { out[j] = out[j - 1]; j--; } out[j] = e; }
        else if (e.seq > out[0].seq) { int j = 0; while (j + 1 < n && out[j + 1].seq < e.seq) { out[j] = out[j + 1]; j++; } out[j] = e; }
    }
    return k;
}

/* ------------------------------------------------------------------ report index */
#define IDX_ENTRY 76
size_t bc_diag_index_encode(const bc_diag_index_t *x, uint8_t *b, size_t cap)
{
    int n = x->n < 0 ? 0 : x->n > BC_DIAG_MAX_REPORTS ? BC_DIAG_MAX_REPORTS : x->n;
    size_t need = 16 + (size_t)n * IDX_ENTRY + 4;
    if (cap < need) return 0;
    memset(b, 0, need);
    memcpy(b, "BCDX", 4); b[4] = 1; b[5] = (uint8_t)n; w32(b + 8, x->next_id); w32(b + 12, x->not_stored);
    for (int i = 0; i < n; i++) {
        uint8_t *e = b + 16 + (size_t)i * IDX_ENTRY; const bc_diag_info_t *r = &x->r[i];
        w32(e, r->id); w32(e + 4, r->size); w32(e + 8, r->crc); w32(e + 12, r->epoch_s); e[16] = r->kind; e[17] = r->state;
        memcpy(e + 18, r->summary, sizeof r->summary - 1); memcpy(e + 58, r->fw, sizeof r->fw - 1);
    }
    w32(b + need - 4, bc_crc32(0, b, need - 4));
    return need;
}
bool bc_diag_index_decode(const uint8_t *b, size_t n, bc_diag_index_t *x)
{
    memset(x, 0, sizeof *x); x->next_id = 1;
    if (n < 20 || memcmp(b, "BCDX", 4) || b[4] != 1 || b[5] > BC_DIAG_MAX_REPORTS) return false;
    size_t need = 16 + (size_t)b[5] * IDX_ENTRY + 4;
    if (n < need || r32(b + need - 4) != bc_crc32(0, b, need - 4)) return false;
    x->n = b[5]; x->next_id = r32(b + 8); x->not_stored = r32(b + 12);
    for (int i = 0; i < x->n; i++) {
        const uint8_t *e = b + 16 + (size_t)i * IDX_ENTRY; bc_diag_info_t *r = &x->r[i];
        r->id = r32(e); r->size = r32(e + 4); r->crc = r32(e + 8); r->epoch_s = r32(e + 12); r->kind = e[16]; r->state = e[17];
        memcpy(r->summary, e + 18, sizeof r->summary - 1); r->summary[sizeof r->summary - 1] = 0;
        memcpy(r->fw, e + 58, sizeof r->fw - 1); r->fw[sizeof r->fw - 1] = 0;
    }
    if (x->next_id == 0) x->next_id = 1;
    return true;
}
int bc_diag_index_make_room(const bc_diag_index_t *x, uint32_t size)
{
    uint32_t total = 0; for (int i = 0; i < x->n; i++) total += x->r[i].size;
    if (x->n < BC_DIAG_MAX_REPORTS && total + size <= BC_DIAG_STORE_BYTES) return -1;
    for (int i = 0; i < x->n; i++) if (x->r[i].state == 1) return i;      /* oldest SENT report first */
    return -2;                                                            /* only unsent reports: never deleted */
}
int bc_diag_index_pending(const bc_diag_index_t *x) { int k = 0; for (int i = 0; i < x->n; i++) if (x->r[i].state == 0) k++; return k; }
const bc_diag_info_t *bc_diag_index_find(const bc_diag_index_t *x, uint32_t id) { for (int i = 0; i < x->n; i++) if (x->r[i].id == id) return &x->r[i]; return NULL; }

/* ------------------------------------------------------------------ report builder */
const char *bc_reset_name(bc_reset_t r)
{
    switch (r) { case BC_RST_POWERON: return "power-on / RESET button"; case BC_RST_SW: return "software restart"; case BC_RST_PANIC: return "crash (panic)";
                 case BC_RST_WDT: return "watchdog"; case BC_RST_BROWNOUT: return "brownout (low voltage)"; case BC_RST_DEEPSLEEP: return "wake from deep sleep"; default: return "other"; }
}
typedef struct { char *b; size_t cap, n; bool full; } wb_t;
static void ap(wb_t *w, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
static void ap(wb_t *w, const char *fmt, ...)
{
    if (w->full) return;
    va_list a; va_start(a, fmt); int k = vsnprintf(w->b + w->n, w->cap - w->n, fmt, a); va_end(a);
    if (k < 0 || (size_t)k >= w->cap - w->n) { w->full = true; w->n = w->cap - 1; w->b[w->n] = 0; return; }
    w->n += (size_t)k;
}
static const char *kind_word(uint8_t k) { return k == 1 ? "crash" : k == 2 ? "recovery session" : k == 3 ? "manual (send logs)" : k == 4 ? "periodic health" : "?"; }
void bc_diag_summary(const bc_diag_report_in_t *in, char *out, size_t cap)
{
    if (in->kind == BC_DIAG_KIND_CRASH) {
        const char *what = in->reset == BC_RST_WDT ? "watchdog" : in->reset == BC_RST_BROWNOUT ? "brownout" : "panic";
        if (in->have_dump && in->task[0]) snprintf(out, cap, "%s in %s", what, in->task); else snprintf(out, cap, "%s (no core dump)", what);
    } else if (in->kind == BC_DIAG_KIND_RECOVERY) snprintf(out, cap, "recovery session");
    else if (in->kind == BC_DIAG_KIND_MANUAL) snprintf(out, cap, "manual report");
    else snprintf(out, cap, "health report");
    if (cap > BC_DIAG_SUMMARY_MAX + 1) out[BC_DIAG_SUMMARY_MAX] = 0;
}
size_t bc_diag_report_build(const bc_diag_report_in_t *in, const bc_ev_t *ev, int nev, char *out, size_t cap)
{
    if (cap < 64) { if (cap) out[0] = 0; return 0; }
    wb_t w = { out, cap - 16, 0, false };            /* room kept for the truncation marker */
    char sum[48]; bc_diag_summary(in, sum, sizeof sum);
    ap(&w, "[header]\nformat bikecomputer-diag 1\nreport %lu\nkind %u %s\nsummary %s\nfirmware %s\nbuild %s\napp_elf_sha256 %s\nboard ..:%02X:%02X\ncreated_epoch %lu\nuptime_s %lu\n",
       (unsigned long)in->id, in->kind, kind_word(in->kind), sum, in->fw, in->build, in->elf_sha[0] ? in->elf_sha : "unknown", in->board_id_tail[0], in->board_id_tail[1],
       (unsigned long)in->epoch_s, (unsigned long)in->uptime_s);
    ap(&w, "\n[reset]\nreason %s (%s)\ncrash_streak %lu\nboot_count %lu\ncrashes_total %lu\nboot_mode %s\nmarker %u\nskip 0x%03X\nstaged_fails %u\n",
       bc_reset_name(in->reset), in->reset_raw, (unsigned long)in->crash_streak, (unsigned long)in->boot_count, (unsigned long)in->crash_total,
       in->boot_mode == 1 ? "staged" : in->boot_mode == 2 ? "recovery" : "normal", in->marker, in->skip, in->staged_fails);
    ap(&w, "\n[panic]\n");
    if (in->have_dump) ap(&w, "core_dump yes\ntask %s\npc 0x%08lX\nexccause %lu\nexcvaddr 0x%08lX\nreason %s\n", in->task, (unsigned long)in->pc, (unsigned long)in->exccause, (unsigned long)in->excvaddr, in->reason[0] ? in->reason : "-");
    else ap(&w, "core_dump none%s\n", in->kind == BC_DIAG_KIND_CRASH ? " (the crash happened before core dumps were enabled, or the dump could not be read)" : "");
    if (in->log_tail && in->log_tail[0]) {
        ap(&w, "log_before_reset:\n");
        const char *p = in->log_tail;
        while (*p && !w.full) { const char *e = strchr(p, '\n'); size_t l = e ? (size_t)(e - p) : strlen(p); ap(&w, "  %.*s\n", (int)(l > 200 ? 200 : l), p); p += l + (e ? 1 : 0); }
    }
    ap(&w, "\n[backtrace]\n");
    if (in->have_dump && in->bt_depth) {
        for (int i = 0; i < in->bt_depth && i < 16; i++) ap(&w, "%s0x%08lX", i ? " " : "", (unsigned long)in->bt[i]);
        ap(&w, "%s\ndecode: xtensa-esp32s3-elf-addr2line -pfiaC -e bike_computer.elf <addresses> (ELF with the sha256 above)\n", in->bt_corrupted ? " |CORRUPTED" : "");
    } else ap(&w, "none\n");
    ap(&w, "\n[tasks]\n");
    for (int i = 0; i < in->ntasks && i < 12; i++) ap(&w, "%s stack_free %lu\n", in->tasks[i].name, (unsigned long)in->tasks[i].stack_free);
    if (!in->ntasks) ap(&w, "not running (recovery mode / before start)\n");
    ap(&w, "\n[heap]\nfree %lu\nmin_free_ever %lu\nlargest_block %lu\npsram_free %lu\n", (unsigned long)in->heap_free, (unsigned long)in->heap_min, (unsigned long)in->heap_largest, (unsigned long)in->psram_free);
    ap(&w, "\n[events]\n");
    for (int i = 0; i < nev && !w.full; i++) { char l[160]; bc_ev_text(&ev[i], l, sizeof l); ap(&w, "%s\n", l); }
    if (!nev) ap(&w, "none\n");
    ap(&w, "\n[sensors]\n");
    static const char *const SN[3] = { "power", "hr", "csc" };
    for (int i = 0; i < 3; i++) {
        if (!in->sens[i].paired) { ap(&w, "%s not paired\n", SN[i]); continue; }
        char age[16]; if (in->sens[i].valid_age_ms == UINT32_MAX) snprintf(age, sizeof age, "none"); else snprintf(age, sizeof age, "%lums", (unsigned long)in->sens[i].valid_age_ms);
        ap(&w, "%s stage %s%s pkts %lu rej %lu resub %lu reconn %lu valid_age %s%s%s\n", SN[i], bc_stage_name((bc_stage_t)in->sens[i].stage), in->sens[i].disabled ? " DISABLED-after-crash" : "",
           (unsigned long)in->sens[i].packets, (unsigned long)in->sens[i].rejected, (unsigned long)in->sens[i].resubs, (unsigned long)in->sens[i].reconnects,
           age, in->sens[i].err[0] ? " err " : "", in->sens[i].err);
    }
    ap(&w, "\n[phone]\nenabled %d\nstate %s\nbonds %u\nlast_disconnect %u (0x%x)\nconnects %lu\ntx %lu rx %lu\nlive_sent %lu\n", in->phone_enabled, phone_state(in->phone_state), in->phone_bonds,
       in->phone_last_disc, in->phone_disc_code, (unsigned long)in->phone_connects, (unsigned long)in->phone_tx, (unsigned long)in->phone_rx, (unsigned long)in->lives_sent);
    ap(&w, "\n[wifi]\non %d\nstate %s\nerror %u\nrssi %d\n", in->wifi_on, wifi_state(in->wifi_state), in->wifi_err, in->wifi_rssi);
    ap(&w, "\n[recovery]\n%s\n", in->recovery_note && in->recovery_note[0] ? in->recovery_note : "none");
    if (w.full) { size_t n = strlen(out); while (n && out[n - 1] != '\n') n--; snprintf(out + n, cap - n, "[truncated]\n"); return strlen(out); }
    return w.n;
}
static bool hexd(char c) { return (c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f'); }
static bool decd(char c) { return c >= '0' && c <= '9'; }
void bc_diag_redact(char *s)
{
    for (size_t i = 0; s[i]; i++) {
        /* XX:XX:XX:XX:XX:XX (17 chars) -> ..:..:..:..:XX:XX */
        bool mac = true;
        for (int k = 0; k < 17 && mac; k++) { char c = s[i + k]; if (!c) { mac = false; break; } mac = (k % 3 == 2) ? c == ':' : hexd(c); }
        if (mac && (i == 0 || !hexd(s[i - 1])) && !hexd(s[i + 17])) { for (int k = 0; k < 12; k++) if (k % 3 != 2) s[i + k] = '.'; i += 16; continue; }
        /* a.b.c.d -> x.x.x.x */
        if (decd(s[i]) && (i == 0 || (!decd(s[i - 1]) && s[i - 1] != '.'))) {
            size_t j = i; int dots = 0, digits = 0; bool ok = true;
            while (s[j] && (decd(s[j]) || s[j] == '.')) { if (s[j] == '.') { if (!digits) { ok = false; break; } dots++; digits = 0; } else if (++digits > 3) { ok = false; break; } j++; }
            if (ok && dots == 3 && digits) { memcpy(s + i, "x.x.x.x", 7); memmove(s + i + 7, s + j, strlen(s + j) + 1); i += 6; }
        }
    }
}

/* ------------------------------------------------------------------ Link 1.2.3 server */
void bc_diag_srv_init(bc_diag_srv_t *s, const bc_diag_store_t *st) { memset(s, 0, sizeof *s); s->st = *st; }
void bc_diag_srv_reset(bc_diag_srv_t *s) { s->listing = false; s->nq = 0; s->info_due = s->err_due = false; s->att_mtu = 0; s->delete_due = false; s->auto_delete = false; }
void bc_diag_srv_set_link(bc_diag_srv_t *s, uint16_t att_mtu, bool ride_recording) { s->att_mtu = att_mtu; s->paused = ride_recording; }
bool bc_diag_srv_chunk_next(const bc_diag_srv_t *s)
{
    if (s->err_due || s->info_due || !s->nq || s->paused) return false;
    const bc_diag_info_t *r = bc_diag_index_find(s->st.index(s->st.ctx), s->q[0].id);
    return r && s->q[0].offset < r->size && bc_diag_chunk_data_max(s->q[0].max_len, s->att_mtu) > 0;
}
bool bc_diag_pace_ok(uint32_t now_ms, uint32_t last_chunk_ms, bool have_sent, bool link_room)
{
    return link_room && (!have_sent || now_ms - last_chunk_ms >= BC_DIAG_CHUNK_GAP_MS);
}
static void err(bc_diag_srv_t *s, uint32_t id, uint8_t code) { s->err_due = true; s->err.id = id; s->err.code = code; }
bool bc_diag_srv_write(bc_diag_srv_t *s, const uint8_t *msg, size_t n)
{
    if (!msg || n < BC_LINK_HDR) return false;
    switch (msg[0]) {
    case BC_MSG_DIAG_LIST_REQ: if (!bc_link_decode_diag_list_req(msg, n)) return true; s->listing = true; s->list_i = 0; s->reqs++; return true;
    case BC_MSG_DIAG_CHUNK_REQ: {
        bc_diag_chunk_req_t q; if (!bc_link_decode_diag_chunk_req(msg, n, &q)) return true;
        if (s->nq >= 4) { err(s, q.id, BC_DIAG_ERR_BUSY); return true; }   /* more than 4 outstanding: the phone retries */
        s->q[s->nq++] = q; s->reqs++; return true; }
    case BC_MSG_DIAG_ACK: {
        bc_diag_ack_t a; if (!bc_link_decode_diag_ack(msg, n, &a)) return true;
        s->reqs++;
        const bc_diag_info_t *r = bc_diag_index_find(s->st.index(s->st.ctx), a.id);
        if (!r) { err(s, a.id, BC_DIAG_ERR_UNKNOWN_ID); return true; }
        if (a.crc == r->crc) {
            if (r->state != 1 && !s->st.mark_sent(s->st.ctx, a.id)) { err(s, a.id, BC_DIAG_ERR_STORAGE); return true; }
            s->acks_ok++;
            if (a.del && s->auto_delete && s->st.remove) { s->delete_due = true; s->delete_id = a.id; }   /* after the DIAG_INFO below */
        }
        else s->acks_bad++;
        s->info_due = true; s->info_id = a.id;
        return true; }
    default: return false;
    }
}
size_t bc_diag_srv_next(bc_diag_srv_t *s, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms)
{
    const bc_diag_index_t *x = s->st.index(s->st.ctx);
    if (s->err_due) { s->err_due = false; return bc_link_encode_diag_err(&s->err, buf, cap, seq, t_ms); }
    if (s->info_due) {
        s->info_due = false;
        const bc_diag_info_t *r = bc_diag_index_find(x, s->info_id);
        if (r) {
            size_t n = bc_link_encode_diag_info(r, buf, cap, seq, t_ms);
            if (s->delete_due && s->delete_id == s->info_id) { s->delete_due = false; if (s->st.remove(s->st.ctx, s->delete_id)) s->deleted++; }
            return n;
        }
    }
    if (s->nq) {
        bc_diag_chunk_req_t qq = s->q[0]; memmove(&s->q[0], &s->q[1], sizeof s->q[0] * (size_t)(s->nq - 1)); s->nq--;
        const bc_diag_chunk_req_t *q = &qq;
        const bc_diag_info_t *r = bc_diag_index_find(x, q->id);
        bc_diag_err_t e = { q->id, 0 };
        uint16_t room = bc_diag_chunk_data_max(q->max_len, s->att_mtu);
        if (!r) e.code = BC_DIAG_ERR_UNKNOWN_ID;
        else if (q->offset > r->size) e.code = BC_DIAG_ERR_BAD_OFFSET;
        else if (s->paused && q->offset < r->size) { e.code = BC_DIAG_ERR_BUSY; s->busy_ride++; }     /* a ride is recording */
        else if (!room && q->offset < r->size) { e.code = BC_DIAG_ERR_MTU; s->mtu_errs++; }           /* MTU leaves no room */
        if (e.code) return bc_link_encode_diag_err(&e, buf, cap, seq, t_ms);
        bc_diag_chunk_t c; memset(&c, 0, sizeof c); c.id = q->id; c.offset = q->offset;
        uint32_t want = room;
        uint32_t left = r->size - q->offset; if (want > left) want = left;
        if (want) { long got = s->st.read(s->st.ctx, q->id, q->offset, c.data, want); if (got != (long)want) { e.code = BC_DIAG_ERR_STORAGE; return bc_link_encode_diag_err(&e, buf, cap, seq, t_ms); } }
        c.len = (uint8_t)want; c.last = q->offset + want == r->size;
        s->chunks_sent++;
        return bc_link_encode_diag_chunk(&c, buf, cap, seq, t_ms);
    }
    if (s->listing) {
        if (s->list_i < x->n) return bc_link_encode_diag_info(&x->r[s->list_i++], buf, cap, seq, t_ms);
        s->listing = false;
        bc_diag_list_end_t e = { (uint8_t)x->n, (uint8_t)bc_diag_index_pending(x) };
        return bc_link_encode_diag_list_end(&e, buf, cap, seq, t_ms);
    }
    return 0;
}

const char *bc_health_alert_name(bc_health_alert_t a)
{
    switch (a) {
    case BC_HA_HEAP_LOW: return "heap low"; case BC_HA_HEAP_MIN_LOW: return "heap minimum low"; case BC_HA_STACK_LOW: return "task stack low";
    case BC_HA_LIVE_STALLED: return "LIVE to phone stalled"; case BC_HA_WATCH_HR_STALE: return "watch HR via phone stale"; case BC_HA_SENSOR_STUCK: return "sensor stuck below VALID";
    case BC_HA_TOUCH_SILENT: return "touch silent"; case BC_HA_LVGL_MEM: return "UI memory high"; default: return "none";
    }
}
