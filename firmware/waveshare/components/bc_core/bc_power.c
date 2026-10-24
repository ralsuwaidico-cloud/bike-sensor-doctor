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

/* ---- wake taps */
void bc_tap_reset(bc_tap_t *t)
{
    int need = t->need; uint32_t rb = t->rejected_bursts, rs = t->rejected_slides, rl = t->rejected_long;
    memset(t, 0, sizeof *t);
    t->need = (need >= 1 && need <= 3) ? need : 3;
    t->rejected_bursts = rb; t->rejected_slides = rs; t->rejected_long = rl;
}
void bc_tap_set_count(bc_tap_t *t, int need)
{
    int nn = (need >= 1 && need <= 3) ? need : 3;
    if (nn != t->need) { t->need = nn; t->n = 0; t->pending_ms = 0; }   /* only a CHANGE restarts a sequence in progress */
}

static void clear_taps(bc_tap_t *t) { t->n = 0; t->first_ms = 0; t->last_release_ms = 0; t->pending_ms = 0; }

bool bc_tap_feed_xy(bc_tap_t *t, bool pressed, int x, int y, uint32_t now_ms)
{
    if (t->need < 1 || t->need > 3) t->need = 3;
    if (t->lockout_until_ms && (int32_t)(now_ms - t->lockout_until_ms) < 0) { t->down = pressed; t->down_ms = now_ms; return false; }
    t->lockout_until_ms = 0;
    if (pressed && !t->down) {                                   /* press begins */
        t->down = true; t->down_ms = now_ms; t->x0 = x; t->y0 = y; t->slid = false;
        /* burst detection: more than BC_TAP_BURST_N presses inside one second is not a hand */
        t->press_ms[t->ph & 7] = now_ms; t->ph++;
        int recent = 0; for (int i = 0; i < 8 && i < t->ph; i++) if (now_ms - t->press_ms[i] <= 1000) recent++;
        if (recent > BC_TAP_BURST_N) { t->rejected_bursts++; clear_taps(t); t->lockout_until_ms = now_ms + BC_TAP_LOCKOUT_MS; return false; }
        if (t->pending_ms) {
            /* a press right after the completed gesture: within the bounce gap it is vibration/bounce (cancel), later it is a
               human extra tap (3 taps when 2 are needed must still wake): fire now */
            bool bounce = now_ms - t->last_release_ms < BC_TAP_MIN_GAP_MS;
            clear_taps(t); t->down = true; t->down_ms = now_ms;
            if (bounce) { t->rejected_bursts++; return false; }
            return true;
        }
        /* a long pause since the previous tap: start a fresh sequence */
        if (t->n && now_ms - t->last_release_ms > BC_TAP_MAX_GAP_MS) clear_taps(t);
        return false;
    }
    if (pressed && t->down) {                                    /* finger moving? */
        if (x >= 0 && t->x0 >= 0) { int dx = x - t->x0, dy = y - t->y0; if (dx < 0) dx = -dx; if (dy < 0) dy = -dy; if (dx > BC_TAP_SLIDE_PX || dy > BC_TAP_SLIDE_PX) t->slid = true; }
        return false;
    }
    if (!pressed && t->down) {                                   /* release */
        t->down = false;
        uint32_t d = now_ms - t->down_ms;
        if (d < BC_TAP_MIN_PRESS_MS) return false;                       /* glitch: ignore, keep the sequence */
        if (d > BC_TAP_MAX_PRESS_MS) { t->rejected_long++; clear_taps(t); return false; }   /* a hold is not a tap */
        if (t->slid) { t->rejected_slides++; clear_taps(t); return false; }
        if (t->n && t->down_ms - t->last_release_ms < BC_TAP_MIN_GAP_MS) return false;     /* contact bounce */
        if (t->n == 0) t->first_ms = t->down_ms;
        t->n++; t->last_release_ms = now_ms;
        if (now_ms - t->first_ms > BC_TAP_WINDOW_MS) { t->n = 1; t->first_ms = t->down_ms; }  /* too slow: this tap starts over */
        if (t->n >= t->need) t->pending_ms = now_ms ? now_ms : 1;           /* complete: fire after the settle time */
        return false;
    }
    /* idle */
    if (t->pending_ms && now_ms - t->pending_ms >= BC_TAP_SETTLE_MS) { clear_taps(t); return true; }
    if (!t->pending_ms && t->n && now_ms - t->last_release_ms > BC_TAP_MAX_GAP_MS) clear_taps(t);   /* cannot complete any more */
    return false;
}
bool bc_tap_feed(bc_tap_t *t, bool pressed, uint32_t now_ms) { return bc_tap_feed_xy(t, pressed, -1, -1, now_ms); }

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
