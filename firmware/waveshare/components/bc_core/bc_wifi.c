#include "bc_wifi.h"
#include <string.h>

bool bc_wifi_ssid_valid(const char *s) { size_t n = s ? strlen(s) : 0; return n >= 1 && n <= 32; }

bool bc_wifi_pass_valid(const char *p)
{
    if (!p) return false;
    size_t n = strlen(p);
    if (n == 0) return true;
    if (n < 8 || n > 63) return false;
    for (size_t i = 0; i < n; i++) if ((unsigned char)p[i] < 0x20 || (unsigned char)p[i] > 0x7E) return false;
    return true;
}

void bc_wifi_store_init(bc_wifi_store_t *st) { memset(st, 0, sizeof *st); }

static int idx(const bc_wifi_store_t *st, const char *ssid)
{
    for (int i = 0; i < st->n; i++) if (!strcmp(st->c[i].ssid, ssid)) return i;
    return -1;
}

const bc_wifi_cred_t *bc_wifi_store_find(const bc_wifi_store_t *st, const char *ssid) { int i = idx(st, ssid); return i < 0 ? NULL : &st->c[i]; }

static void to_front(bc_wifi_store_t *st, int i)
{
    bc_wifi_cred_t t = st->c[i];
    memmove(&st->c[1], &st->c[0], sizeof(bc_wifi_cred_t) * (size_t)i);
    st->c[0] = t;
}

void bc_wifi_store_touch(bc_wifi_store_t *st, const char *ssid) { int i = idx(st, ssid); if (i > 0) to_front(st, i); }

bool bc_wifi_store_put(bc_wifi_store_t *st, const char *ssid, const char *pass)
{
    if (!bc_wifi_ssid_valid(ssid) || !bc_wifi_pass_valid(pass)) return false;
    int i = idx(st, ssid);
    if (i < 0) {
        if (st->n < BC_WIFI_MAX_SAVED) st->n++;
        i = st->n - 1;                     /* full: the least recently used (last) is replaced */
    }
    memset(&st->c[i], 0, sizeof st->c[i]);
    strncpy(st->c[i].ssid, ssid, 32);
    strncpy(st->c[i].pass, pass, 64);
    to_front(st, i);
    return true;
}

bool bc_wifi_store_remove(bc_wifi_store_t *st, const char *ssid)
{
    int i = idx(st, ssid);
    if (i < 0) return false;
    memmove(&st->c[i], &st->c[i + 1], sizeof(bc_wifi_cred_t) * (size_t)(st->n - i - 1));
    st->n--;
    memset(&st->c[st->n], 0, sizeof st->c[st->n]);   /* wipe the freed slot */
    return true;
}

size_t bc_wifi_store_pack(const bc_wifi_store_t *st, unsigned char *out, size_t cap)
{
    size_t o = 0;
    if (cap < 2) return 0;
    out[o++] = 1;                          /* format version */
    out[o++] = (unsigned char)st->n;
    for (int i = 0; i < st->n; i++) {
        size_t ls = strlen(st->c[i].ssid), lp = strlen(st->c[i].pass);
        if (o + 2 + ls + lp > cap) return 0;
        out[o++] = (unsigned char)ls; memcpy(out + o, st->c[i].ssid, ls); o += ls;
        out[o++] = (unsigned char)lp; memcpy(out + o, st->c[i].pass, lp); o += lp;
    }
    return o;
}

bool bc_wifi_store_unpack(bc_wifi_store_t *st, const unsigned char *in, size_t len)
{
    bc_wifi_store_init(st);
    if (!in || len < 2 || in[0] != 1 || in[1] > BC_WIFI_MAX_SAVED) return false;
    size_t o = 2; int n = in[1];
    for (int i = 0; i < n; i++) {
        if (o >= len) { bc_wifi_store_init(st); return false; }
        size_t ls = in[o++]; if (ls < 1 || ls > 32 || o + ls >= len) { bc_wifi_store_init(st); return false; }
        memcpy(st->c[i].ssid, in + o, ls); o += ls;
        size_t lp = in[o++]; if (lp > 64 || o + lp > len) { bc_wifi_store_init(st); return false; }
        memcpy(st->c[i].pass, in + o, lp); o += lp;
        st->n++;
    }
    return true;
}

int bc_wifi_pick(const bc_wifi_store_t *st, const char (*ssids)[33], const int *rssi, int n)
{
    int best = -1, best_rssi = -1000;
    for (int s = 0; s < st->n; s++)
        for (int k = 0; k < n; k++)
            if (!strcmp(st->c[s].ssid, ssids[k]) && rssi[k] > best_rssi + (best < 0 ? 0 : 3)) { best = s; best_rssi = rssi[k]; }
    /* the "+3 dB" margin keeps the more recently used network unless another saved one is clearly stronger */
    return best;
}

bc_wifi_err_t bc_wifi_map_reason(int reason, bool had_password, bool associated)
{
    switch (reason) {
    case 201: case 210: case 211: case 212: return BC_WIFI_ERR_NOT_FOUND;    /* no AP / incompatible security / too weak */
    case 15: case 204: case 14:                                              /* 4-way handshake: the classic wrong key */
        return had_password ? BC_WIFI_ERR_WRONG_PASSWORD : BC_WIFI_ERR_OTHER;
    case 202: case 2:                                                        /* authentication failed / expired */
        return had_password ? BC_WIFI_ERR_WRONG_PASSWORD : BC_WIFI_ERR_OTHER;
    case 200: return associated ? BC_WIFI_ERR_LOST : BC_WIFI_ERR_TIMEOUT;    /* beacon timeout: out of range */
    default: return associated ? BC_WIFI_ERR_LOST : BC_WIFI_ERR_OTHER;
    }
}

const char *bc_wifi_err_text(bc_wifi_err_t e)
{
    switch (e) {
    case BC_WIFI_ERR_WRONG_PASSWORD: return "Wrong password. Check it and try again.";
    case BC_WIFI_ERR_NOT_FOUND: return "Network not found. Is it on and 2.4 GHz?";
    case BC_WIFI_ERR_TIMEOUT: return "No answer from the network (timeout).";
    case BC_WIFI_ERR_NO_IP: return "Joined, but got no address. Try again.";
    case BC_WIFI_ERR_LOST: return "Connection lost.";
    case BC_WIFI_ERR_OTHER: return "Could not connect. Try again.";
    default: return "";
    }
}

unsigned bc_wifi_backoff_s(unsigned attempt) { static const unsigned T[] = { 5, 10, 30, 60 }; return T[attempt < 3 ? attempt : 3]; }
