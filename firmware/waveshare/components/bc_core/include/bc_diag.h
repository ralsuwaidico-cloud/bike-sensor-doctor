/*
 * bc_core — DIAGNOSTICS (firmware 0.7.3). Pure C, host-tested (test/host/test_bc_diag.c), used by the app layer on the device
 * and in the PC harness. Four parts:
 *
 * 1. Persistent event log. Fixed 32-byte records, each with its own CRC-32, written into a ring file (diag/events.bin on the
 *    FAT partition, which is wear-levelled) at slot seq % nslots. Records are batched in RAM and written at most once per
 *    10 s (bc_evlog_flush_due), or at once for a crash / report. A record torn by a power loss fails its CRC and is skipped;
 *    every other record survives. Old records are overwritten by new ones (it is a log). NVS was not used: its 24 KB also
 *    hold the profile, the Wi-Fi networks and the phone bonds, and a full NVS would put those at risk.
 * 2. Report store index. Reports are immutable text files (diag/r<id>.txt) with a CRC-32 over the whole text, listed in
 *    diag/index.bin. A report that was not sent (acknowledged by the phone with the matching CRC) is never deleted to make
 *    room: when the store is full of unsent reports a new low-priority report is not stored and that is counted instead.
 * 3. Report builder: UTF-8 text with the sections of docs/LINK_V1_2_SPEC.md 1.2.3 — [header] [reset] [panic] [backtrace]
 *    [tasks] [heap] [events] [sensors] [phone] [wifi] [recovery]. No names, no e-mail, no Wi-Fi passwords or network names,
 *    no locations; Bluetooth addresses only as their last 2 bytes. Backtraces are raw addresses + the app ELF SHA-256 so they
 *    can be decoded offline (xtensa addr2line with the matching ELF).
 * 4. The Link 1.2.3 transfer server (bc_diag_srv_*): phone-driven pull over the bc_link DIAG_* messages.
 * Plus health thresholds (bc_health_check) for the continuous monitor.
 */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "bc_link.h"

#ifdef __cplusplus
extern "C" {
#endif

/** CRC-32/ISO-HDLC (IEEE 802.3, zlib): reflected 0xEDB88320, init and xorout 0xFFFFFFFF. bc_crc32(0, "123456789", 9) =
 *  0xCBF43926. Chain calls by passing the previous result. */
uint32_t bc_crc32(uint32_t crc, const void *data, size_t n);

/* ------------------------------------------------------------------ 1. event log */
typedef enum {
    BC_EV_BOOT = 1,      /* a = reset kind (bc_reset_t), b = crash streak, c = boot count, d = boot mode | skip mask << 8 */
    BC_EV_CRASH = 2,     /* a = report id (low 16), b = PC, c = exception cause, d = task name hash; x = 1 when a core dump exists */
    BC_EV_STAGE = 3,     /* a = subsystem (bc_subsys_t), x = 0 starting, 1 up, 2 skipped (disabled after a crash), 3 failed */
    BC_EV_SENSOR = 4,    /* a = sensor (1 power, 2 HR, 3 CSC), x = pipeline stage, b = packets, c = rejected, d = valid age ms */
    BC_EV_RECOVERY = 5,  /* a = sensor, x = 1 re-subscribe, 2 reconnect, 3 RETRY by the rider, 4 link disabled after a crash; b = count */
    BC_EV_PHONE = 6,     /* x = plat_phone_state_t, a = last disconnect code, b = connects, c = bonds */
    BC_EV_WIFI = 7,      /* x = plat_wifi_state_t, a = error, b = rssi (signed) */
    BC_EV_HEALTH = 8,    /* a = free internal heap K, b = minimum free heap ever (bytes), c = stack free lvgl << 16 | nimble, d = ble_mgr << 16 | esp_timer */
    BC_EV_READING = 9,   /* a = watts (0xFFFF none), b = rpm | bpm << 16 (0xFFFF none), c = power age ms, d = HR age ms; x = HR source */
    BC_EV_LIVE = 10,     /* a = LIVE messages sent in the last minute, b = phone notifications total, c = last LIVE age ms */
    BC_EV_ALERT = 11,    /* a = bc_health_alert_t, b = value, c = threshold */
    BC_EV_REPORT = 12,   /* a = report id (low 16), x = kind, b = 0 stored, 1 sent (crc ok), 2 not stored (store full of unsent), 3 ack crc mismatch */
    BC_EV_TOUCH = 13,    /* a = screen wakes, b = touch reports, c = touch passed, d = touch controller resets */
    BC_EV_NOTE = 14,     /* a = what (1 events dropped from RAM queue, 2 log file reset), b = count */
    BC_EV_MODE = 15,     /* x = recovery screen action (1 restart & diagnose, 2 send logs, 3 phone connected, 4 report sent) */
} bc_ev_type_t;
typedef struct { uint32_t seq, boot, t_ms; uint8_t type, x; uint16_t a; uint32_t b, c, d; } bc_ev_t;
#define BC_EV_SIZE 32
void bc_ev_encode(const bc_ev_t *e, uint8_t out[BC_EV_SIZE]);   /* little-endian, CRC-32 of bytes 0..27 at 28..31 */
bool bc_ev_decode(const uint8_t in[BC_EV_SIZE], bc_ev_t *e);    /* false: CRC mismatch, erased (all FF / all 00), type 0 */
/** One readable line: "#1234 boot 7 +12.3s SENSOR power -> VALID pkts 812 rej 0". */
size_t bc_ev_text(const bc_ev_t *e, char *buf, size_t cap);

#define BC_EVLOG_PEND 48
#define BC_EVLOG_FLUSH_MS 10000u
typedef struct {
    uint32_t nslots, next_seq, boot;
    bc_ev_t pend[BC_EVLOG_PEND]; int npend; uint32_t dropped;
    uint32_t last_flush_ms; bool flushed_once;
} bc_evlog_t;
void bc_evlog_init(bc_evlog_t *l, uint32_t nslots, uint32_t boot);
/** Continue after the newest valid record of a ring file read back into raw (nslots * 32 bytes; missing = erased). */
void bc_evlog_resume(bc_evlog_t *l, const uint8_t *raw, uint32_t nslots);
/** Queue a record (seq, boot assigned here). When the RAM queue is full the oldest low-priority record (READING, HEALTH,
 *  LIVE, TOUCH) is dropped first, else the oldest; dropped records are counted (and reported with a NOTE). */
void bc_evlog_add(bc_evlog_t *l, uint8_t type, uint8_t x, uint16_t a, uint32_t b, uint32_t c, uint32_t d, uint32_t now_ms);
/** True when queued records should be written now: force (crash / report), or >= 10 s since the last write. */
bool bc_evlog_flush_due(const bc_evlog_t *l, uint32_t now_ms, bool force);
/** Takes up to max queued records in order for writing; the caller writes record i at slot (seq % nslots). */
int bc_evlog_take(bc_evlog_t *l, bc_ev_t *out, int max, uint32_t now_ms);
/** The newest n valid records of a ring file, oldest first. */
int bc_evlog_newest(const uint8_t *raw, uint32_t nslots, bc_ev_t *out, int n);

/* ------------------------------------------------------------------ 2. report store index */
#define BC_DIAG_MAX_REPORTS 12
#define BC_DIAG_STORE_BYTES (96u * 1024u)
#define BC_DIAG_REPORT_MAX 8192u
typedef struct { bc_diag_info_t r[BC_DIAG_MAX_REPORTS]; int n; uint32_t next_id; uint32_t not_stored; } bc_diag_index_t;
/** Serialised index (diag/index.bin): magic "BCDX", version, count, next id, not_stored, entries, CRC-32. */
size_t bc_diag_index_encode(const bc_diag_index_t *x, uint8_t *buf, size_t cap);
bool bc_diag_index_decode(const uint8_t *buf, size_t n, bc_diag_index_t *x);
/** Room for a new report of `size` bytes: returns the index of a SENT report to delete first (oldest first) when needed,
 *  -1 when there is room already, -2 when there is no room without deleting an unsent report (do not store). */
int bc_diag_index_make_room(const bc_diag_index_t *x, uint32_t size);
int bc_diag_index_pending(const bc_diag_index_t *x);
const bc_diag_info_t *bc_diag_index_find(const bc_diag_index_t *x, uint32_t id);

/* ------------------------------------------------------------------ 3. report builder */
typedef enum { BC_RST_POWERON = 0, BC_RST_SW = 1, BC_RST_PANIC = 2, BC_RST_WDT = 3, BC_RST_BROWNOUT = 4, BC_RST_DEEPSLEEP = 5, BC_RST_OTHER = 6 } bc_reset_t;
const char *bc_reset_name(bc_reset_t r);
typedef struct { char name[16]; uint32_t stack_free; } bc_diag_task_t;
typedef struct {
    /* header */
    uint32_t id; uint8_t kind; uint32_t epoch_s; char fw[17]; char build[32]; char elf_sha[65]; uint8_t board_id_tail[2]; uint32_t uptime_s;
    /* reset */
    bc_reset_t reset; char reset_raw[24]; uint32_t crash_streak, boot_count, crash_total; uint8_t boot_mode, marker; uint16_t skip; uint8_t staged_fails;
    /* panic + backtrace (core dump summary; have_dump = false when none was stored) */
    bool have_dump; char task[16]; uint32_t pc, exccause, excvaddr; char reason[64]; uint32_t bt[16]; uint8_t bt_depth; bool bt_corrupted;
    const char *log_tail;                            /* last log lines before the reset (RTC memory), already privacy-filtered */
    /* tasks, heap */
    bc_diag_task_t tasks[12]; int ntasks; uint32_t heap_free, heap_min, heap_largest, psram_free;
    /* sensors: 0 power, 1 HR strap, 2 CSC */
    struct { bool paired, disabled; uint8_t stage; uint32_t packets, rejected, resubs, reconnects, valid_age_ms; char err[21]; } sens[3];
    /* phone, wifi */
    uint8_t phone_state, phone_bonds, phone_last_disc; uint16_t phone_disc_code; uint32_t phone_connects, phone_tx, phone_rx, lives_sent; bool phone_enabled;
    uint8_t wifi_state, wifi_err; int wifi_rssi; bool wifi_on;
    /* recovery */
    const char *recovery_note;                       /* e.g. "staged boot: power meter disabled after a crash" */
} bc_diag_report_in_t;
/** Builds the report text; returns its length (truncated cleanly to cap - 1 with a "[truncated]" line). */
size_t bc_diag_report_build(const bc_diag_report_in_t *in, const bc_ev_t *ev, int nev, char *out, size_t cap);
/** "panic in nimble_host", "watchdog", "manual report", "recovery session" (<= 40 bytes) */
void bc_diag_summary(const bc_diag_report_in_t *in, char *out, size_t cap);
/** Privacy filter for log lines: Bluetooth / MAC addresses -> "..:XX:XX", IPv4 addresses -> "x.x.x.x". In place. */
void bc_diag_redact(char *s);

/* ------------------------------------------------------------------ 4. Link 1.2.3 server */
typedef struct {
    void *ctx;
    const bc_diag_index_t *(*index)(void *ctx);                        /* current list, oldest first */
    long (*read)(void *ctx, uint32_t id, uint32_t off, uint8_t *buf, size_t n);   /* bytes read, -1 storage error */
    bool (*mark_sent)(void *ctx, uint32_t id);                         /* persist state 1 */
    bool (*remove)(void *ctx, uint32_t id);                            /* 1.3 DIAG_AUTO: delete an ACKed report (NULL = never) */
} bc_diag_store_t;
typedef struct {
    bc_diag_store_t st;
    int list_i; bool listing;                        /* sending DIAG_INFO list_i.. then LIST_END */
    bc_diag_chunk_req_t q[4]; int nq;                /* CHUNK_REQs answered in order (a phone may pipeline up to 4) */
    bool info_due; uint32_t info_id;                 /* DIAG_INFO after an ACK */
    bool err_due; bc_diag_err_t err;
    uint16_t att_mtu;                                /* negotiated ATT MTU of the phone connection (0 = not known = 23) */
    bool paused;                                     /* a ride is recording: CHUNK_REQs are answered BUSY (LIST / ACK still work) */
    uint32_t chunks_sent, acks_ok, acks_bad, reqs, busy_ride, mtu_errs;
    /* Link 1.3 DIAG_AUTO (enabled by APP_HELLO on this connection): DIAG_ACK with 03 delete = 1 and a matching CRC ->
       DIAG_INFO state 1 is sent first, then the report is deleted (store.remove) */
    bool auto_delete; uint32_t delete_id; bool delete_due; uint32_t deleted;
} bc_diag_srv_t;
void bc_diag_srv_init(bc_diag_srv_t *s, const bc_diag_store_t *st);
/** Link facts for the next replies: the phone connection's negotiated ATT MTU and whether a ride is recording. */
void bc_diag_srv_set_link(bc_diag_srv_t *s, uint16_t att_mtu, bool ride_recording);
/** True when the next reply bc_diag_srv_next would produce is a DIAG_CHUNK with data (the bulk traffic that is paced). */
bool bc_diag_srv_chunk_next(const bc_diag_srv_t *s);
/* Ride priority (the app layer, app_diag_next): a DIAG_CHUNK is handed to the phone link only when
 *  - the link has room (plat_phone_bulk_room: LIVE already sent, the notify queue empty, NimBLE mbufs free, no recent notify
 *    failure), and
 *  - at least BC_DIAG_CHUNK_GAP_MS passed since the previous chunk (<= 5 chunks/s, <= ~0.8 KB/s);
 * while a ride is RECORDING the server answers chunk requests BUSY instead (the phone retries after 10 s). */
#define BC_DIAG_CHUNK_GAP_MS 200u
bool bc_diag_pace_ok(uint32_t now_ms, uint32_t last_chunk_ms, bool have_sent, bool link_room);
/** A message the phone wrote on Control. False when it is not a DIAG request (the caller handles it). */
bool bc_diag_srv_write(bc_diag_srv_t *s, const uint8_t *msg, size_t n);
/** The next reply to notify on Control (0 = nothing due). */
size_t bc_diag_srv_next(bc_diag_srv_t *s, uint8_t *buf, size_t cap, uint16_t seq, uint32_t t_ms);
void bc_diag_srv_reset(bc_diag_srv_t *s);           /* the phone disconnected: drop what was due (the phone pulls again) */

/* ------------------------------------------------------------------ health thresholds (continuous monitor) */
typedef enum { BC_HA_NONE = 0, BC_HA_HEAP_LOW = 1, BC_HA_HEAP_MIN_LOW = 2, BC_HA_STACK_LOW = 3, BC_HA_LIVE_STALLED = 4, BC_HA_WATCH_HR_STALE = 5,
               BC_HA_SENSOR_STUCK = 6, BC_HA_TOUCH_SILENT = 7, BC_HA_LVGL_MEM = 8 } bc_health_alert_t;
#define BC_HEALTH_HEAP_LOW 24576u        /* free internal heap below 24 KB */
#define BC_HEALTH_HEAP_MIN_LOW 12288u    /* lowest free internal heap ever below 12 KB */
#define BC_HEALTH_STACK_LOW 512u         /* any monitored task with less than 512 bytes of stack never used */
#define BC_HEALTH_LIVE_STALL_MS 5000u    /* phone subscribed to LIVE, nothing sent for 5 s */
#define BC_HEALTH_SENSOR_STUCK_MS 60000u /* a paired sensor below VALID (and not searching) for 60 s */
#define BC_HEALTH_LVGL_PCT 85u
const char *bc_health_alert_name(bc_health_alert_t a);

#ifdef __cplusplus
}
#endif
