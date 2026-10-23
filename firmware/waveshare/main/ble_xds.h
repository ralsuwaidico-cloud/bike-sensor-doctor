#pragma once
#include <stdbool.h>
#include <stdint.h>
#include "bc_xds.h"

typedef enum { XDS_OFF = 0, XDS_SCANNING, XDS_CONNECTING, XDS_DISCOVERING, XDS_SUBSCRIBED, XDS_WAIT_RETRY } xds_state_t;

typedef struct {
    xds_state_t state;
    char name[24];
    uint8_t mac[6];
    bool have_mac;
    int8_t rssi;
    uint32_t devices_seen;     /* distinct advertisers seen while scanning — proves the radio works */
    uint32_t connects, disconnects;
    int last_disconnect_reason;
    bc_xds_live_t live;        /* decoded data, see bc_core */
} xds_status_t;

void ble_xds_start(void);                 /* NimBLE host + scan for the XDS meter (service 0x1828 or name "XDS…") */
void ble_xds_snapshot(xds_status_t *out); /* thread-safe copy for the UI */
const char *ble_xds_state_name(xds_state_t s);
