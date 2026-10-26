/*
 * bc_core — PORTABLE GATT DECISIONS for the sensor links (firmware 0.7.2). Pure functions, host-tested, used by the NimBLE
 * central (main/ble_central.c) and by the PC harness's fake GATT server (test/sim) so both make the same choices.
 *
 * Why this exists (0.7.2 root cause): up to 0.7.1 the central took the CCCD from a descriptor discovery that ran from the
 * 0x2A63 value handle to the END OF THE SERVICE and kept the LAST 0x2902 it saw. Descriptor discovery (ATT Find
 * Information) returns every attribute in that range — including the declarations, values and CCCDs of the characteristics
 * that FOLLOW 0x2A63. On the XDS meter 0x2A63 is followed in service 0x1828 by 0x2A65, 0x2A5D and 0x2A55 (control point,
 * write + indicate, so it has its own CCCD): the board therefore wrote 01 00 to the control point's CCCD, reported
 * "connected", and never received a power packet. bc_gatt_pick_cccd() only accepts a CCCD inside the characteristic's own
 * descriptor range and stops at the next declaration.
 */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define BC_UUID_PRIMARY_SVC 0x2800
#define BC_UUID_SECONDARY_SVC 0x2801
#define BC_UUID_INCLUDE 0x2802
#define BC_UUID_CHR_DECL 0x2803
#define BC_UUID_CCCD 0x2902
#define BC_GATT_PROP_NOTIFY 0x10
#define BC_GATT_PROP_INDICATE 0x20

/* one attribute as descriptor discovery reports it (uuid16 = 0 for a 128-bit UUID) */
typedef struct { uint16_t handle, uuid16; } bc_gatt_attr_t;
/* one characteristic as characteristic discovery reports it */
typedef struct { uint16_t def_handle, val_handle, uuid16; uint8_t props; } bc_gatt_chr_t;

/** Index of the first characteristic with this 16-bit UUID, -1 if none. */
int bc_gatt_find_chr(const bc_gatt_chr_t *chrs, int n, uint16_t uuid16);
/** Last handle that can belong to chrs[i]: one before the next characteristic's declaration, else the service end.
 *  chrs must be in handle order (discovery order). */
uint16_t bc_gatt_chr_end(const bc_gatt_chr_t *chrs, int n, int i, uint16_t svc_end);
/** The CCCD (0x2902) of the characteristic whose value handle is val_handle. a[] = descriptor discovery results in handle
 *  order. Only handles in (val_handle, end] count, and the scan stops at the first declaration (characteristic, service,
 *  include) so a later characteristic's CCCD is never taken, even when end was too generous. 0 = none. */
uint16_t bc_gatt_pick_cccd(const bc_gatt_attr_t *a, int n, uint16_t val_handle, uint16_t end);
/** The value to write to the CCCD: 0x0001 (notify) when the characteristic notifies, else 0x0002 (indicate), 0 = neither. */
uint16_t bc_gatt_cccd_value(uint8_t props);

/** Power-meter service search order. XDS-named meters: 0x1828 first (the proprietary 11-byte 0x2A63), then 0x1818.
 *  Any other meter: 0x1818 (standard Cycling Power) first, then 0x1828. Returns the count (2). */
int bc_gatt_power_services(const char *name, uint16_t out[2]);
typedef enum { BC_PFMT_NONE = 0, BC_PFMT_XDS = 1 /* 11-byte XDS packet, bc_xds */, BC_PFMT_CPS = 2 /* SIG Cycling Power Measurement, bc_cp */ } bc_pfmt_t;
/** Decoder for a 0x2A63 found under this service: 0x1828 -> XDS, 0x1818 -> standard Cycling Power. */
bc_pfmt_t bc_gatt_power_format(uint16_t svc_uuid16);

#ifdef __cplusplus
}
#endif
