/*
 * "BikeComputer Link": the BLE peripheral side for the phone (NimBLE GATT server), running next to the central in
 * ble_central.c on the same host. Protocol: components/bc_core/include/bc_link.h, docs/BLE_LINK_PROTOCOL.md.
 *
 * Rules
 *  - the phone is a guest: a phone connecting, disconnecting or misbehaving never touches the meter link or the ride;
 *  - every characteristic needs an encrypted + authenticated link (LE Secure Connections, 6-digit code on this screen);
 *  - no Bluetooth call from the UI task: the app publishes values, the BLE manager task sends them.
 */
#pragma once
#include <stdbool.h>
#include <stdint.h>
#include "host/ble_gap.h"

void ble_link_register_gatt(void);           /* before the host starts */
void ble_link_configure_security(void);      /* ble_hs_cfg.sm_* for passkey display + bonding */
/** Host synced: applies the stored random-static identity (0.7.0) and starts advertising. Returns the own-address type the
 *  central must use too (BLE_OWN_ADDR_RANDOM when the identity could be set, else the one passed in). */
uint8_t ble_link_on_sync(uint8_t own_addr_type);
void ble_link_tick(void);                    /* from the BLE manager task (~500 ms): pending notifications, RSSI */
/** The central is about to initiate a connection: pause advertising so the controller is free (resume = false). */
void ble_link_central_busy(bool busy);
