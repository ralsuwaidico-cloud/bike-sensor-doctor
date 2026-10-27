/*
 * bc_core — BOOT RECORDS (firmware 0.7.4). Pure C, host-tested (test/host/test_bc_bootrec.c).
 *
 * Crash / start-up evidence that does NOT depend on the FAT filesystem: a ring of the last BC_BOOTREC_N boot records, one
 * fixed-size blob (576 B) in a reserved NVS namespace ("bootrec"), CRC-protected. Written only from normal task context
 * (after the boot plan, after the Bluetooth stage, when the start-up is complete / stable) - never from a panic handler.
 * Each record says how that boot went: reset reason, boot mode, which subsystem crashed before it, the storage category, the
 * Bluetooth start-up result step by step (return codes + internal-heap figures before/after each step + the failed
 * allocation, if any) and the crash PC/task read from the core-dump partition.
 * The next boot prints the previous records in its serial log and Device Health shows them.
 */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BC_BOOTREC_N 4
#define BC_BOOTREC_MAGIC 0xB007EC04u

/* Bluetooth start-up steps (the order of nimble_port_init in ESP-IDF 5.5.1) */
typedef enum { BC_BT_STEP_PRE = 0, BC_BT_STEP_CTRL_INIT = 1, BC_BT_STEP_CTRL_ENABLE = 2, BC_BT_STEP_HOST_INIT = 3, BC_BT_STEP_HOST_TASK = 4,
               BC_BT_STEPS = 5 } bc_bt_step_t;
/* overall result */
typedef enum { BC_BT_NOT_TRIED = 0, BC_BT_OK = 1, BC_BT_FAIL_CTRL_INIT = 2, BC_BT_FAIL_CTRL_ENABLE = 3, BC_BT_FAIL_HOST_INIT = 4,
               BC_BT_FAIL_HOST_TASK = 5, BC_BT_SKIPPED = 6 } bc_bt_result_t;

typedef struct {
    uint32_t free_int, largest_int;     /* heap_caps INTERNAL|8BIT after the step */
    uint32_t free_dma, largest_dma;     /* heap_caps DMA */
    int32_t rc;                          /* esp_err_t of the step (0 OK) */
} bc_bt_snap_t;

typedef struct {
    uint32_t boot;                       /* boot counter (NVS diag/boots) */
    uint8_t reset;                       /* bc_reset_t of this start */
    uint8_t mode;                        /* bc_boot_mode_t */
    uint8_t suspect;                     /* bc_subsys_t that was starting when the previous run crashed (0 none) */
    uint8_t storage;                     /* bc_stor_state_t measured by this boot */
    uint16_t skip;                       /* subsystems disabled this boot */
    uint8_t bt_result;                   /* bc_bt_result_t */
    uint8_t reached;                     /* last stage reached: bc_subsys_t (RUNNING 14 / STABLE 15 ...) */
    bc_bt_snap_t bt[BC_BT_STEPS];        /* per step; rc meaningful up to the failed step */
    uint32_t fail_alloc_size, fail_alloc_caps;   /* first allocation that failed during the Bluetooth start (0 none) */
    uint16_t fail_allocs;                /* failed allocations counted during the Bluetooth start */
    uint8_t crashpart;                   /* bc_crashpart_t seen by this boot */
    uint8_t pad;
    uint32_t crash_pc;                   /* previous run's crash PC from the core dump (0 none) */
    char crash_task[12];
} bc_bootrec_t;

typedef struct {
    uint32_t magic;
    uint16_t version, count;             /* count = records filled (<= N) */
    uint16_t head, pad;                  /* index of the NEWEST record */
    bc_bootrec_t r[BC_BOOTREC_N];
    uint32_t crc;
} bc_bootring_t;

void bc_bootring_init(bc_bootring_t *g);
/** Start a new record (oldest overwritten); returns it, zeroed except boot. */
bc_bootrec_t *bc_bootring_push(bc_bootring_t *g, uint32_t boot);
/** i = 0 newest, 1 the one before ...; NULL past count. */
const bc_bootrec_t *bc_bootring_get(const bc_bootring_t *g, int i);
bc_bootrec_t *bc_bootring_newest(bc_bootring_t *g);
/** Seal (CRC) before storing; valid() checks magic, version, bounds and CRC. A torn / foreign blob is invalid -> init. */
void bc_bootring_seal(bc_bootring_t *g);
bool bc_bootring_valid(const bc_bootring_t *g, size_t blob_len);
/** Consecutive most recent records (excluding the newest one, i.e. previous boots) whose Bluetooth start FAILED.
 *  A record with SKIPPED, OK or NOT_TRIED ends the streak (so RETRY after a skip starts counting again). */
int bc_bootring_bt_fail_streak(const bc_bootring_t *g);
const char *bc_bt_result_name(bc_bt_result_t r);   /* "HCI/host init failed" ... (<= 24 chars) */
/** One line for the serial log / Device Health / reports. */
size_t bc_bootrec_describe(const bc_bootrec_t *r, char *out, size_t cap);

#ifdef __cplusplus
}
#endif
