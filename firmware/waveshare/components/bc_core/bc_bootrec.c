/* bc_core — PORTABLE CORE. See bc_bootrec.h. */
#include "bc_bootrec.h"
#include <stdio.h>
#include <string.h>
#include "bc_diag.h"   /* bc_crc32 */

#define VER 2

void bc_bootring_init(bc_bootring_t *g) { memset(g, 0, sizeof *g); g->magic = BC_BOOTREC_MAGIC; g->version = VER; g->head = BC_BOOTREC_N - 1; }

bc_bootrec_t *bc_bootring_push(bc_bootring_t *g, uint32_t boot)
{
    g->head = (uint16_t)((g->head + 1) % BC_BOOTREC_N);
    if (g->count < BC_BOOTREC_N) g->count++;
    bc_bootrec_t *r = &g->r[g->head];
    memset(r, 0, sizeof *r);
    r->boot = boot;
    return r;
}

const bc_bootrec_t *bc_bootring_get(const bc_bootring_t *g, int i)
{
    if (i < 0 || i >= g->count || g->head >= BC_BOOTREC_N) return NULL;
    return &g->r[(g->head + BC_BOOTREC_N - (unsigned)i) % BC_BOOTREC_N];
}
bc_bootrec_t *bc_bootring_newest(bc_bootring_t *g) { return g->count ? &g->r[g->head % BC_BOOTREC_N] : NULL; }

static uint32_t crc_of(const bc_bootring_t *g) { return bc_crc32(0, g, offsetof(bc_bootring_t, crc)); }
void bc_bootring_seal(bc_bootring_t *g) { g->crc = crc_of(g); }
bool bc_bootring_valid(const bc_bootring_t *g, size_t blob_len)
{
    return blob_len == sizeof *g && g->magic == BC_BOOTREC_MAGIC && g->version == VER && g->count <= BC_BOOTREC_N && g->head < BC_BOOTREC_N && g->crc == crc_of(g);
}

static bool failed(uint8_t r) { return r >= BC_BT_FAIL_CTRL_INIT && r <= BC_BT_FAIL_HOST_TASK; }
int bc_bootring_bt_fail_streak(const bc_bootring_t *g)
{
    int n = 0;
    for (int i = 1; i < g->count; i++) {
        const bc_bootrec_t *r = bc_bootring_get(g, i);
        if (!r || !failed(r->bt_result)) break;
        n++;
    }
    return n;
}

void bc_bootring_note_bt(bc_bootring_t *g)
{
    bc_bootrec_t *r = bc_bootring_newest(g);
    if (r && r->bt_result != BC_BT_NOT_TRIED && r->bt_result != BC_BT_SKIPPED) g->last_bt_try = *r;
}
int bc_bootring_crash_streak(const bc_bootring_t *g)
{
    int n = 0;
    for (int i = 0; i < g->count; i++) {
        const bc_bootrec_t *r = bc_bootring_get(g, i);
        if (!r || !(r->reset == BC_RST_PANIC || r->reset == BC_RST_WDT || r->reset == BC_RST_BROWNOUT)) break;
        n++;
    }
    return n;
}

const char *bc_bt_result_name(bc_bt_result_t r)
{
    switch (r) {
    case BC_BT_OK: return "Bluetooth OK";
    case BC_BT_FAIL_CTRL_INIT: return "controller init failed";
    case BC_BT_FAIL_CTRL_ENABLE: return "controller enable failed";
    case BC_BT_FAIL_HOST_INIT: return "HCI init failed";
    case BC_BT_FAIL_HOST_TASK: return "no RAM for host task";
    case BC_BT_SKIPPED: return "Bluetooth off (disabled)";
    case BC_BT_NOT_TRIED: default: return "Bluetooth not started";
    }
}

size_t bc_bootrec_describe(const bc_bootrec_t *r, char *out, size_t cap)
{
    if (!out || !cap) return 0;
    if (!r) { out[0] = 0; return 0; }
    int n = snprintf(out, cap, "boot #%lu reset %u mode %u crashed-subsys %u skip 0x%03X storage %u reached %u; BT: %s",
                     (unsigned long)r->boot, r->reset, r->mode, r->suspect, r->skip, r->storage, r->reached, bc_bt_result_name((bc_bt_result_t)r->bt_result));
    if (n > 0 && (size_t)n < cap && r->bt_result != BC_BT_NOT_TRIED && r->bt_result != BC_BT_SKIPPED) {
        int last = r->bt_result == BC_BT_OK ? BC_BT_STEP_HOST_TASK : r->bt_result - 1;   /* step that failed (2->1 ... 5->4) */
        for (int s = 0; s <= last && s < BC_BT_STEPS && n > 0 && (size_t)n < cap; s++)
            n += snprintf(out + n, cap - (size_t)n, " [%d rc %ld int %lu/%lu dma %lu/%lu]", s, (long)r->bt[s].rc, (unsigned long)r->bt[s].free_int,
                          (unsigned long)r->bt[s].largest_int, (unsigned long)r->bt[s].free_dma, (unsigned long)r->bt[s].largest_dma);
        if (n > 0 && (size_t)n < cap && r->fail_allocs)
            n += snprintf(out + n, cap - (size_t)n, " failed alloc %lu B caps 0x%lx (x%u)", (unsigned long)r->fail_alloc_size, (unsigned long)r->fail_alloc_caps, r->fail_allocs);
    }
    if (n > 0 && (size_t)n < cap && r->crash_pc)
        n += snprintf(out + n, cap - (size_t)n, "; previous crash pc 0x%08lX in %.12s", (unsigned long)r->crash_pc, r->crash_task);
    if (n < 0) { out[0] = 0; return 0; }
    return (size_t)n < cap ? (size_t)n : cap - 1;
}
