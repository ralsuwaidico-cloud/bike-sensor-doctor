#include "bc_power.h"
#include <string.h>

/* ---- battery curve: open-circuit-ish LiPo points; under load the estimate reads low (safe side) */
int bc_batt_pct_from_mv(int mv)
{
    static const int MV[] = { 3300, 3500, 3600, 3700, 3800, 3900, 4000, 4100, 4200 }, PCT[] = { 0, 5, 15, 30, 50, 65, 80, 90, 100 };
    if (mv <= 0) return -1;
    if (mv <= MV[0]) return 0;
    for (int i = 1; i < 9; i++) if (mv <= MV[i]) return PCT[i - 1] + (PCT[i] - PCT[i - 1]) * (mv - MV[i - 1]) / (MV[i] - MV[i - 1]);
    return 100;
}

/* ---- USB inference */
void bc_usb_reset(bc_usb_t *u) { memset(u, 0, sizeof *u); }

bool bc_usb_feed(bc_usb_t *u, int mv, uint32_t now_ms)
{
    if (mv <= 0) return u->likely;
    if (mv >= BC_USB_HOLD_MV) { if (!u->high_since_ms) u->high_since_ms = now_ms ? now_ms : 1; }
    else u->high_since_ms = 0;
    bool held = u->high_since_ms && now_ms - u->high_since_ms >= BC_USB_HOLD_MS;
    /* rise test against a reference at most 5 min old */
    if (!u->ref_ms || now_ms - u->ref_ms > BC_USB_RISE_MS) { u->ref_mv = mv; u->ref_ms = now_ms ? now_ms : 1; }
    bool rising = mv - u->ref_mv >= BC_USB_RISE_MV;
    if (rising) { u->ref_mv = mv; u->ref_ms = now_ms ? now_ms : 1; }
    bool falling = u->last_ms && mv < u->last_mv - 40;            /* a clear drop ends the inference at once */
    if (held || rising) u->likely = true;
    else if (falling || (mv < BC_USB_HOLD_MV - 100)) u->likely = false;
    u->last_ms = now_ms ? now_ms : 1; u->last_mv = mv;
    return u->likely;
}

/* ---- low battery */
void bc_lowbat_reset(bc_lowbat_t *l) { l->level = BC_BAT_OK; }

bc_bat_level_t bc_lowbat_feed(bc_lowbat_t *l, int mv)
{
    if (mv <= 0) return l->level;
    static const int TH[4] = { 0, BC_BAT_LOW_MV, BC_BAT_VERY_LOW_MV, BC_BAT_CRIT_MV };
    bc_bat_level_t lv = BC_BAT_OK;
    for (int i = 3; i >= 1; i--) if (mv <= TH[i]) { lv = (bc_bat_level_t)i; break; }
    if (lv > l->level) l->level = lv;                                   /* worse: immediately */
    else if (lv < l->level) {                                            /* better: only past the hysteresis band */
        while (l->level > BC_BAT_OK && mv > TH[l->level] + BC_BAT_HYST_MV) l->level = (bc_bat_level_t)(l->level - 1);
    }
    return l->level;
}

const char *bc_bat_level_name(bc_bat_level_t l)
{
    switch (l) { case BC_BAT_LOW: return "LOW"; case BC_BAT_VERY_LOW: return "VERY LOW"; case BC_BAT_CRITICAL: return "CRITICAL"; default: return "OK"; }
}

/* ---- triple tap */
void bc_tap_reset(bc_tap_t *t) { memset(t, 0, sizeof *t); }

bool bc_tap_feed(bc_tap_t *t, bool pressed, uint32_t now_ms)
{
    if (pressed && !t->down) { t->down = true; t->down_ms = now_ms; return false; }
    if (!pressed && t->down) {
        t->down = false;
        if (now_ms - t->down_ms > BC_TAP_MAX_PRESS_MS) { t->n = 0; return false; }   /* a hold is not a tap */
        /* drop taps older than the window */
        int k = 0; for (int i = 0; i < t->n; i++) if (now_ms - t->t[i] <= BC_TAP_WINDOW_MS) t->t[k++] = t->t[i];
        t->n = k;
        if (t->n < 3) t->t[t->n++] = now_ms;
        if (t->n >= 3 && now_ms - t->t[0] <= BC_TAP_WINDOW_MS) { t->n = 0; return true; }
        return false;
    }
    /* idle: forget stale taps */
    if (!pressed && t->n && now_ms - t->t[0] > BC_TAP_WINDOW_MS) { int k = 0; for (int i = 0; i < t->n; i++) if (now_ms - t->t[i] <= BC_TAP_WINDOW_MS) t->t[k++] = t->t[i]; t->n = k; }
    return false;
}

/* ---- drain */
void bc_drain_reset(bc_drain_t *d) { memset(d, 0, sizeof *d); d->cur = -1; }

static void fold(bc_drain_t *d, int mv, uint32_t now_ms)
{
    if (d->cur < 0 || d->cur >= BC_MODE_COUNT) return;
    uint32_t secs = (now_ms - d->cur_since_ms) / 1000;
    int drop = d->cur_start_mv - mv;
    if (drop < -20) return;                         /* voltage rose: not the cell discharging (USB) — do not count */
    d->m[d->cur].secs += secs;
    if (drop > 0) d->m[d->cur].drop_mv += drop;
}

void bc_drain_feed(bc_drain_t *d, bc_power_mode_t mode, int mv, uint32_t now_ms, bool usb_likely)
{
    if (mv <= 0) return;
    if (usb_likely) { d->cur = -1; return; }       /* not the cell's own voltage: start fresh afterwards */
    if (d->cur == (int)mode) fold(d, mv, now_ms);  /* same mode: fold the open segment so the rate is live */
    else if (d->cur >= 0 && now_ms - d->cur_since_ms >= 30000) fold(d, mv, now_ms);   /* mode switch: keep segments >= 30 s */
    d->cur = (int)mode; d->cur_since_ms = now_ms; d->cur_start_mv = mv;
}

int bc_drain_rate_mv_h(const bc_drain_t *d, bc_power_mode_t mode)
{
    if (mode >= BC_MODE_COUNT || d->m[mode].secs < BC_DRAIN_MIN_S) return -1;
    return (int)((int64_t)d->m[mode].drop_mv * 3600 / (int64_t)d->m[mode].secs);
}

int bc_drain_hours_left_x10(const bc_drain_t *d, bc_power_mode_t mode, int mv)
{
    int r = bc_drain_rate_mv_h(d, mode);
    if (r <= 0 || mv <= BC_BAT_CRIT_MV) return r == 0 ? 999 : -1;
    return (mv - BC_BAT_CRIT_MV) * 10 / r;
}

const char *bc_power_mode_name(bc_power_mode_t m)
{
    switch (m) { case BC_MODE_IDLE_ON: return "idle, screen on"; case BC_MODE_RIDE_ON: return "riding, screen on"; case BC_MODE_RIDE_OFF: return "riding, screen off"; default: return "?"; }
}
