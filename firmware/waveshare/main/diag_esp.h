#pragma once
/* diag_esp.c: device side of the 0.7.3 crash evidence (see plat.h). */
void diag_esp_early_init(void);   /* first thing in app_main: keep the previous run's log tail, hook the log output */
void diag_esp_ble_started(void);  /* NimBLE was started by the normal boot (recovery SEND LOGS must not start it again) */
/* 0.7.4: the boot plan disabled the Bluetooth stack (crashed twice in a row while starting): reported as unavailable */
void diag_esp_bt_disabled(const char *why);
/* 0.7.4 boot records in NVS (bc_bootrec.h): begin after the boot plan + storage stage, then Bluetooth result, stage reached */
#include "bc_boot.h"
#include "bc_storage.h"
#include "ble_central.h"
void diag_esp_bootrec_begin(const bc_boot_plan_t *plan, bc_stor_state_t storage);
void diag_esp_bootrec_bt(const ble_central_init_t *bi, bool skipped);
void diag_esp_bootrec_reached(uint8_t subsys);
int diag_esp_bt_fail_streak(void);   /* previous boots in a row whose Bluetooth start failed (no crash) */
