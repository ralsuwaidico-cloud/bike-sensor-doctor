#pragma once
/* diag_esp.c: device side of the 0.7.3 crash evidence (see plat.h). */
void diag_esp_early_init(void);   /* first thing in app_main: keep the previous run's log tail, hook the log output */
void diag_esp_ble_started(void);  /* NimBLE was started by the normal boot (recovery SEND LOGS must not start it again) */
/* 0.7.4: the boot plan disabled the Bluetooth stack (crashed twice in a row while starting): reported as unavailable */
void diag_esp_bt_disabled(const char *why);
