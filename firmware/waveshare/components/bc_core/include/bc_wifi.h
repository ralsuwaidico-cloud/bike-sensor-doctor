/*
 * bc_core — portable Wi-Fi manager rules (no ESP-IDF): the saved-network list, which saved network to join, and how a
 * disconnect reason becomes a plain error. Host-tested; used by main/net_wifi.c on the device.
 */
#pragma once
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BC_WIFI_MAX_SAVED 5

typedef struct { char ssid[33]; char pass[65]; } bc_wifi_cred_t;
typedef struct { int n; bc_wifi_cred_t c[BC_WIFI_MAX_SAVED]; } bc_wifi_store_t;   /* c[0] = most recently used */

typedef enum { BC_WIFI_ERR_NONE = 0, BC_WIFI_ERR_WRONG_PASSWORD, BC_WIFI_ERR_NOT_FOUND, BC_WIFI_ERR_TIMEOUT, BC_WIFI_ERR_NO_IP,
               BC_WIFI_ERR_LOST, BC_WIFI_ERR_OTHER } bc_wifi_err_t;

/** Valid WPA passphrase: empty (open network) or 8..63 printable ASCII characters. */
bool bc_wifi_pass_valid(const char *p);
/** SSID: 1..32 bytes. */
bool bc_wifi_ssid_valid(const char *s);

void bc_wifi_store_init(bc_wifi_store_t *st);
/** Adds or updates a network and makes it the most recent; the oldest is dropped when full. */
bool bc_wifi_store_put(bc_wifi_store_t *st, const char *ssid, const char *pass);
bool bc_wifi_store_remove(bc_wifi_store_t *st, const char *ssid);
const bc_wifi_cred_t *bc_wifi_store_find(const bc_wifi_store_t *st, const char *ssid);
void bc_wifi_store_touch(bc_wifi_store_t *st, const char *ssid);        /* mark as most recently used */

/** Serialised form for flash: length-prefixed fields, so any SSID / password byte is safe. Returns bytes, 0 if too small. */
size_t bc_wifi_store_pack(const bc_wifi_store_t *st, unsigned char *out, size_t cap);
bool bc_wifi_store_unpack(bc_wifi_store_t *st, const unsigned char *in, size_t len);

/**
 * Which saved network to join from a scan (parallel arrays): the strongest saved network in range, ties to the most
 * recently used. Returns the index into the store, -1 when none is in range.
 */
int bc_wifi_pick(const bc_wifi_store_t *st, const char (*ssids)[33], const int *rssi, int n);

/**
 * Turns a station disconnect reason (802.11 / ESP-IDF code) into an error the rider can act on.
 * had_password: a password was used; associated: the link had been up (then it is a LOST connection).
 */
bc_wifi_err_t bc_wifi_map_reason(int reason, bool had_password, bool associated);
const char *bc_wifi_err_text(bc_wifi_err_t e);

/** Retry delay for automatic reconnection: 5, 10, 30, then 60 s. */
unsigned bc_wifi_backoff_s(unsigned attempt);

#ifdef __cplusplus
}
#endif
