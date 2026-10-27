/*
 * Deterministic diagnostic report for the Link 1.2.3 cross-tests (firmware <-> Cyclift). Built by the FIRMWARE's real report
 * builder (bc_diag_report_build) from a fixed crash scenario, so the bytes, size and CRC-32 are exactly what a 0.7.3 board
 * would store for that crash. Used by gen_diag_fixture.c (exports the fixture for the iOS tests) and test_bc_diag.c.
 */
#pragma once
#include "bc_diag.h"
#include "bc_link.h"
#include "bc_pipe.h"
#include <stdio.h>
#include <string.h>

#define FX_REPORT_ID 7u
#define FX_SENT_ID 8u
#define FX_EPOCH 1792850100u              /* 2026-10-25 */

static char FX_SUMMARY[48];
static size_t fx_build_report(char *out, size_t cap)
{
    static bc_diag_report_in_t in; memset(&in, 0, sizeof in);
    in.id = FX_REPORT_ID; in.kind = BC_DIAG_KIND_CRASH; in.epoch_s = FX_EPOCH;
    snprintf(in.fw, sizeof in.fw, "0.7.3"); snprintf(in.build, sizeof in.build, "Oct 27 2026 10:00:00");
    for (int i = 0; i < 64; i++) in.elf_sha[i] = "0123456789abcdef"[(i * 7) % 16];
    in.board_id_tail[0] = 0x3C; in.board_id_tail[1] = 0x9A; in.uptime_s = 4242;
    in.reset = BC_RST_PANIC; snprintf(in.reset_raw, sizeof in.reset_raw, "panic"); in.crash_streak = 1; in.boot_count = 57; in.crash_total = 3;
    in.boot_mode = 0; in.marker = 6; in.skip = 0; in.staged_fails = 0;
    in.have_dump = true; snprintf(in.task, sizeof in.task, "nimble_host"); in.pc = 0x4200F4BC; in.exccause = 28; in.excvaddr = 0x17C;
    snprintf(in.reason, sizeof in.reason, "LoadProhibited");
    static const uint32_t BT[] = { 0x4200F4BC, 0x4200E71C, 0x4202D8D4, 0x40385099, 0x4037F2A0, 0x42011080 };
    in.bt_depth = 6; memcpy(in.bt, BT, sizeof BT);
    static char tail[2200]; tail[0] = 0;
    for (int i = 0; i < 24; i++) {
        char l[96];
        snprintf(l, sizeof l, "I (%d) %s: line %02d of the log before the reset, peer C1:22:33:44:55:%02X\n", 1000 + i * 137,
                 i % 3 == 0 ? "link" : i % 3 == 1 ? "pipe" : "app", i, 0x40 + i);
        strncat(tail, l, sizeof tail - strlen(tail) - 1);
    }
    bc_diag_redact(tail); in.log_tail = tail;
    static const char *const TN[] = { "taskLVGL", "nimble_host", "ble_mgr", "esp_timer", "main", "app", "IDLE0", "IDLE1" };
    static const uint32_t TF[] = { 6100, 3300, 2100, 2900, 5200, 1800, 900, 900 };
    in.ntasks = 8; for (int i = 0; i < 8; i++) { snprintf(in.tasks[i].name, sizeof in.tasks[i].name, "%s", TN[i]); in.tasks[i].stack_free = TF[i]; }
    in.heap_free = 151234; in.heap_min = 120001; in.heap_largest = 90112; in.psram_free = 1900000;
    in.sens[0].paired = true; in.sens[0].stage = BC_STG_VALID; in.sens[0].packets = 81234; in.sens[0].rejected = 3; in.sens[0].resubs = 1; in.sens[0].valid_age_ms = 240;
    in.sens[1].paired = true; in.sens[1].stage = BC_STG_STALE; in.sens[1].packets = 512; in.sens[1].valid_age_ms = 12000; snprintf(in.sens[1].err, sizeof in.sens[1].err, "no data 12 s");
    in.phone_state = 4; in.phone_bonds = 1; in.phone_connects = 9; in.phone_tx = 31337; in.phone_rx = 2048; in.lives_sent = 4100; in.phone_enabled = true;
    in.wifi_on = false;
    in.recovery_note = NULL;
    static bc_ev_t ev[60];
    for (int i = 0; i < 60; i++) {
        bc_ev_t *e = &ev[i]; memset(e, 0, sizeof *e);
        e->seq = 1000u + (uint32_t)i; e->boot = 57; e->t_ms = 500u + (uint32_t)i * 3100u;
        e->type = (uint8_t)(1 + i % 14); e->x = (uint8_t)(i % 9); e->a = (uint16_t)(i % 3 + 1); e->b = (uint32_t)i * 97u; e->c = (uint32_t)i * 13u; e->d = (uint32_t)i * 5u;
    }
    bc_diag_summary(&in, FX_SUMMARY, sizeof FX_SUMMARY);
    return bc_diag_report_build(&in, ev, 60, out, cap);
}

/* ---- an in-memory store with the fixture report (pending) and a second, already acknowledged one */
static char FX_TXT[BC_DIAG_REPORT_MAX]; static size_t FX_LEN;
static const char FX_SENT_TXT[] = "[header]\nmanual report (already sent)\n";
static bc_diag_index_t FX_IDX; static bool FX_READ_FAIL;
static const bc_diag_index_t *fx_index(void *c) { (void)c; return &FX_IDX; }
static long fx_read(void *c, uint32_t id, uint32_t off, uint8_t *buf, size_t n)
{
    (void)c; if (FX_READ_FAIL) return -1;
    if (id == FX_REPORT_ID && off + n <= FX_LEN) { memcpy(buf, FX_TXT + off, n); return (long)n; }
    if (id == FX_SENT_ID && off + n <= sizeof FX_SENT_TXT - 1) { memcpy(buf, FX_SENT_TXT + off, n); return (long)n; }
    return -1;
}
static bool fx_mark(void *c, uint32_t id) { (void)c; for (int i = 0; i < FX_IDX.n; i++) if (FX_IDX.r[i].id == id) { FX_IDX.r[i].state = 1; return true; } return false; }
static void fx_store_init(void)
{
    FX_LEN = fx_build_report(FX_TXT, sizeof FX_TXT);
    memset(&FX_IDX, 0, sizeof FX_IDX); FX_READ_FAIL = false;
    bc_diag_info_t *r = &FX_IDX.r[FX_IDX.n++];
    r->id = FX_REPORT_ID; r->size = (uint32_t)FX_LEN; r->crc = bc_crc32(0, FX_TXT, FX_LEN); r->epoch_s = FX_EPOCH; r->kind = BC_DIAG_KIND_CRASH; r->state = 0;
    snprintf(r->summary, sizeof r->summary, "%.40s", FX_SUMMARY); snprintf(r->fw, sizeof r->fw, "0.7.3");
    r = &FX_IDX.r[FX_IDX.n++];
    r->id = FX_SENT_ID; r->size = (uint32_t)(sizeof FX_SENT_TXT - 1); r->crc = bc_crc32(0, FX_SENT_TXT, sizeof FX_SENT_TXT - 1); r->epoch_s = FX_EPOCH + 60;
    r->kind = BC_DIAG_KIND_MANUAL; r->state = 1; snprintf(r->summary, sizeof r->summary, "manual report"); snprintf(r->fw, sizeof r->fw, "0.7.3");
    FX_IDX.next_id = 9;
}
static void fx_srv(bc_diag_srv_t *s, uint16_t mtu, bool riding)
{
    bc_diag_store_t st = { NULL, fx_index, fx_read, fx_mark };
    bc_diag_srv_init(s, &st); bc_diag_srv_set_link(s, mtu, riding);
}
/* what Cyclift asks for on a link whose ATT MTU is `mtu` (ios: BCLink.diagRequestMaxLen) — 0 = it does not ask */
static uint16_t fx_phone_max_len(uint16_t mtu)
{
    int room = (int)mtu - BC_ATT_NOTIFY_OVERHEAD - BC_DIAG_CHUNK_OVERHEAD;
    if (room < 1) return 0;
    return (uint16_t)(room < BC_DIAG_CHUNK_MAX ? room : BC_DIAG_CHUNK_MAX);
}
