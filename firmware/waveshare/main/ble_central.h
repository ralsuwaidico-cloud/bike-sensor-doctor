/*
 * Bluetooth LE central for the cycling computer (NimBLE). Three links:
 *   POWER  the paired XDS / Branta meter — service 0x1828, characteristic 0x2A63 (11-byte packet, bc_xds decoder)
 *   HR     an optional standard heart-rate strap — service 0x180D, characteristic 0x2A37 (bc_hr decoder)
 *   CSC    an optional speed/cadence sensor (0.6.0) — service 0x1816, characteristic 0x2A5B (bc_csc decoder)
 * Plus a pairing scan that lists nearby meters / straps for the Sensors and onboarding screens.
 *
 * SAFETY: the only write ever sent to any device is the standard CCCD subscription (01 00; 02 00 for an indicate-only data
 * characteristic) on the data characteristic's OWN CCCD (0.7.2: bc_gatt_pick_cccd — never a CCCD of a later
 * characteristic such as the 0x2A55 control point). No control point writes, no vendor characteristics, no bonding.
 * The CCCD is read back to confirm. Reconnect automatically with back-off 1, 2, 4, 8, 16 s (reset only when valid data
 * flows). 0.7.2: every link has a pipeline stage (bc_pipe.h, serial tag "pipe") and automatic recovery.
 *
 * THREADING (0.7.3): every Bluetooth call and every change of a link's state happens on the NimBLE host task. The manager
 * task, the MTU fallback timer and the UI only post NimBLE events (ble_npl_eventq_put) or set request flags; the host task
 * does the work in order with the GATT/GAP callbacks. The UI reads copies through ble_central_snapshot (spinlock, no
 * Bluetooth call inside). 0.7.2 ran the recovery actions on the manager task in parallel with the host callbacks.
 */
#pragma once
#include <stdbool.h>
#include <stdint.h>
#include "plat.h"

/* 0.7.4: two steps, neither aborts.
   ble_central_stack_init(): BT controller + NimBLE port (HCI transport buffers from INTERNAL RAM). Called early in the start-up
   (before touch, profile and screens take their internal RAM, as in 0.7.2). false = Bluetooth unavailable for this boot; the
   reason and the heap figures are in ble_central_init_info() and in the serial log.
   ble_central_start(sensors): the stack if not up yet, then the phone-link GATT service, host task and manager task. false =
   Bluetooth unavailable (nothing else is affected). sensors = false: the sensor central stays off (no scan, no sensor link)
   until ble_central_enable_sensors(true) — recovery mode "SEND LOGS" and the staged boot use that. */
typedef struct {
    bool attempted, stack_ok, host_started, failed;
    int err;                                          /* esp_err_t of the failed step */
    char reason[56];                                  /* short, for the screen: "HCI init failed", "no RAM for host task" (err: field) */
    uint32_t pre_free, pre_largest, pre_dma;          /* internal heap just before nimble_port_init() */
    uint32_t post_free, post_largest, post_dma;       /* after a successful init */
    uint32_t fail_free, fail_largest, fail_dma;       /* after the failure (the controller has released its memory again) */
} ble_central_init_t;
bool ble_central_stack_init(void);
bool ble_central_start(bool sensors);
const ble_central_init_t *ble_central_init_info(void);
bool ble_central_unavailable(void);       /* the stack or the host failed to start this boot */
void ble_central_enable_sensors(bool on);
/* configure the device to use for a kind (NULL = none). Safe to call from the UI task (applied on the host task). */
void ble_central_set_paired(plat_sens_kind_t kind, const uint8_t mac[6], uint8_t addr_type, const char *name);
/* 0.7.3 staged boot: a sensor link disabled after a crash keeps its pairing but is not connected until enabled again */
void ble_central_set_disabled(plat_sens_kind_t kind, bool disabled);
void ble_central_scan_for(int kind);      /* pairing list for a kind; -1 = stop the pairing list */
void ble_central_set_standby(bool standby);
void ble_central_set_wheel_mm(uint16_t mm);   /* wheel circumference for the CSC speed (profile.wheel_mm) */   /* 0.6.0 connected standby: pause scanning for paired sensors */
int ble_central_found(plat_sens_kind_t kind, plat_found_t *out, int max);
/* thread-safe snapshot for the UI */
void ble_central_snapshot(plat_sensors_t *out);
uint32_t ble_central_devices_seen(void);
bool ble_central_ready(void);
bool ble_central_scanning(void);
