/* bc_core — PORTABLE CORE. See bc_gatt.h. */
#include "bc_gatt.h"
#include <string.h>

int bc_gatt_find_chr(const bc_gatt_chr_t *c, int n, uint16_t uuid16)
{
    for (int i = 0; c && i < n; i++) if (c[i].uuid16 == uuid16) return i;
    return -1;
}

uint16_t bc_gatt_chr_end(const bc_gatt_chr_t *c, int n, int i, uint16_t svc_end)
{
    if (!c || i < 0 || i >= n) return 0;
    /* the next declaration in handle order (discovery reports them in order; be safe if it did not) */
    uint16_t next = 0;
    for (int j = 0; j < n; j++) if (c[j].def_handle > c[i].val_handle && (!next || c[j].def_handle < next)) next = c[j].def_handle;
    uint16_t end = next ? (uint16_t)(next - 1) : svc_end;
    if (end > svc_end) end = svc_end;
    return end;
}

static bool is_decl(uint16_t u) { return u == BC_UUID_CHR_DECL || u == BC_UUID_PRIMARY_SVC || u == BC_UUID_SECONDARY_SVC || u == BC_UUID_INCLUDE; }

uint16_t bc_gatt_pick_cccd(const bc_gatt_attr_t *a, int n, uint16_t val, uint16_t end)
{
    for (int i = 0; a && i < n; i++) {
        if (a[i].handle <= val) continue;
        if (a[i].handle > end || is_decl(a[i].uuid16)) break;    /* the next characteristic starts: its CCCD is not ours */
        if (a[i].uuid16 == BC_UUID_CCCD) return a[i].handle;    /* the FIRST one in range (a characteristic has at most one) */
    }
    return 0;
}

uint16_t bc_gatt_cccd_value(uint8_t props)
{
    if (props & BC_GATT_PROP_NOTIFY) return 0x0001;
    if (props & BC_GATT_PROP_INDICATE) return 0x0002;
    return 0;
}

int bc_gatt_power_services(const char *name, uint16_t out[2])
{
    bool xds = name && !strncmp(name, "XDS", 3);
    out[0] = xds ? 0x1828 : 0x1818;
    out[1] = xds ? 0x1818 : 0x1828;
    return 2;
}

bc_pfmt_t bc_gatt_power_format(uint16_t svc) { return svc == 0x1828 ? BC_PFMT_XDS : svc == 0x1818 ? BC_PFMT_CPS : BC_PFMT_NONE; }
