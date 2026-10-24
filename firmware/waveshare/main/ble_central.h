/*
 * Bluetooth LE central for the cycling computer (NimBLE). Three links:
 *   POWER  the paired XDS / Branta meter — service 0x1828, characteristic 0x2A63 (11-byte packet, bc_xds decoder)
 *   HR     an optional standard heart-rate strap — service 0x180D, characteristic 0x2A37 (bc_hr decoder)
 *   CSC    an optional speed/cadence sensor (0.6.0) — service 0x1816, characteristic 0x2A5B (bc_csc decoder)
 * Plus a pairing scan that lists nearby meters / straps for the Sensors and onboarding screens.
 *
 * SAFETY: the only write ever sent to any device is the standard CCCD subscription (01 00). No control point
 * (0x2A55), no vendor characteristics, no bonding. Reconnect automatically with back-off 1, 2, 4, 8, 16 s.
 */
#pragma once
#include <stdbool.h>
#include <stdint.h>
#include "plat.h"

void ble_central_start(void);
/* configure the device to use for a kind (NULL = none). Safe to call from the UI task. */
void ble_central_set_paired(plat_sens_kind_t kind, const uint8_t mac[6], uint8_t addr_type, const char *name);
void ble_central_scan_for(int kind);      /* pairing list for a kind; -1 = stop the pairing list */
void ble_central_set_standby(bool standby);
void ble_central_set_wheel_mm(uint16_t mm);   /* wheel circumference for the CSC speed (profile.wheel_mm) */   /* 0.6.0 connected standby: pause scanning for paired sensors */
int ble_central_found(plat_sens_kind_t kind, plat_found_t *out, int max);
/* thread-safe snapshot for the UI */
void ble_central_snapshot(plat_sensors_t *out);
uint32_t ble_central_devices_seen(void);
bool ble_central_ready(void);
bool ble_central_scanning(void);
