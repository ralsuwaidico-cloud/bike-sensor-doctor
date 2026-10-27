/*
 * bc_core — power-management logic that needs no hardware: battery estimate, USB-power inference, low-battery
 * levels with hysteresis, the triple-tap detector and the consumption (drain) tracker. Pure functions and small state
 * machines fed with milliseconds and millivolts, so test/host can prove them and the device and the simulator share them.
 *
 * Honesty rules (owner, 24 Oct 2026):
 *  - the percentage is an ESTIMATE from the cell voltage under load; every display adds "~" or "est.";
 *  - the board cannot see the charger: "USB power likely" is an inference from the voltage, never "charging";
 *  - low-battery thresholds are alerts only until validated on hardware; any automatic action is opt-in.
 */
#pragma once
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- battery estimate: 1-cell LiPo curve, 3300 mV = 0 %, 4200 mV = 100 % */
int bc_batt_pct_from_mv(int mv);          /* -1 when mv <= 0 (no reading) */

/* ---- USB-power inference: voltage held >= 4180 mV for 30 s, or rising >= 30 mV within 5 min */
#define BC_USB_HOLD_MV 4180
#define BC_USB_HOLD_MS 30000
#define BC_USB_RISE_MV 30
#define BC_USB_RISE_MS 300000
typedef struct {
    bool likely;
    uint32_t high_since_ms;      /* 0 = not currently above the hold level */
    int ref_mv; uint32_t ref_ms; /* reference sample for the rise test */
    uint32_t last_ms; int last_mv;
} bc_usb_t;
void bc_usb_reset(bc_usb_t *u);
/** Feed a (filtered) battery reading; returns the current verdict. Call about every 5 s. */
bool bc_usb_feed(bc_usb_t *u, int mv, uint32_t now_ms);

/* ---- low-battery levels with 50 mV hysteresis (thresholds for a lightly loaded cell) */
typedef enum { BC_BAT_OK = 0, BC_BAT_LOW = 1 /* ~20 % */, BC_BAT_VERY_LOW = 2 /* ~10 % */, BC_BAT_CRITICAL = 3 /* ~5 % */ } bc_bat_level_t;
#define BC_BAT_LOW_MV 3550
#define BC_BAT_VERY_LOW_MV 3450
#define BC_BAT_CRIT_MV 3350
#define BC_BAT_EMPTY_MV 3300        /* outside a ride: deep sleep allowed here (only when the protection setting is on) */
#define BC_BAT_HYST_MV 50
typedef struct { bc_bat_level_t level; } bc_lowbat_t;
void bc_lowbat_reset(bc_lowbat_t *l);
/** Returns the new level; a level only rises when the voltage is below its threshold and only falls back when the
 *  voltage is above threshold + hysteresis, so vibration or a short sag never toggles alerts twice. */
bc_bat_level_t bc_lowbat_feed(bc_lowbat_t *l, int mv);
const char *bc_bat_level_name(bc_bat_level_t l);

/* ---- wake taps (0.6.0): N presses (press -> release) within BC_TAP_WINDOW_MS, any position. Used for the 2- and 3-tap
 * wake options; the default since rev 3 is any touch (bc_gate_t below handles the swallow + guard for every variant).
 * A tap is a press of 20..400 ms without sliding; the gap release -> next press is 60..900 ms. Longer presses, slides and
 * bursts (> 6 presses in a second: vibration, rain) reset the counter; a burst also locks the detector for a second.
 * Hardware notes: the first touch after the controller slept must be delivered too — see hw.c (auto-sleep disabled while
 * the screen is off); the window is measured from the FIRST press, so a slow rider has 2.5 s for all taps. */
#define BC_TAP_WINDOW_MS 2500
#define BC_TAP_MIN_PRESS_MS 20
#define BC_TAP_MAX_PRESS_MS 400
#define BC_TAP_MIN_GAP_MS 60
#define BC_TAP_MAX_GAP_MS 900
#define BC_TAP_SLIDE_PX 15
#define BC_TAP_BURST_N 6
#define BC_TAP_LOCKOUT_MS 1000
#define BC_TAP_SETTLE_MS 100      /* the gesture fires only when no further press follows the last tap within this time (vibration guard) */
typedef struct {
    int need;                    /* taps required (1..3) */
    int n; uint32_t first_ms, last_release_ms;
    bool down; uint32_t down_ms; int x0, y0; bool slid;
    uint32_t press_ms[8]; int ph; uint32_t lockout_until_ms, pending_ms;
    uint32_t rejected_bursts, rejected_slides, rejected_long;
} bc_tap_t;
void bc_tap_reset(bc_tap_t *t);                 /* keeps `need` (3 after a zeroed struct) */
void bc_tap_set_count(bc_tap_t *t, int need);   /* 1..3 */
/** Feed press state (every poll or on change) with the touch position (-1 = unknown); true exactly once when the gesture completes
 *  (BC_TAP_SETTLE_MS after the last release, so keep feeding the released state). */
bool bc_tap_feed_xy(bc_tap_t *t, bool pressed, int x, int y, uint32_t now_ms);
bool bc_tap_feed(bc_tap_t *t, bool pressed, uint32_t now_ms);

/* ---- wake gate (0.6.0 rev 3): what reaches the UI while the screen is off / just woke.
 * Default wake = ANY touch (profile wake_taps = 1): the first contact wakes the display at once. The whole waking gesture is
 * SWALLOWED (no press reaches LVGL until every finger is lifted), then a GUARD of BC_GATE_GUARD_MS ignores touches too; a
 * finger still down when the guard ends keeps being swallowed until it lifts. So a wake can never press START RIDE or any
 * other control underneath. 2- and 3-tap wakes use bc_tap_t and get the same swallow + guard. */
#define BC_GATE_GUARD_MS 400
#define BC_GATE_WATCHDOG_MS 1500  /* 0.6.1: a swallow with NO touch report for this long is abandoned (event-driven touch reads
                                     only arrive while a finger is on the glass; a missed release must never lock the UI) */
typedef enum { BC_GATE_PASS = 0, BC_GATE_OFF, BC_GATE_SWALLOW, BC_GATE_GUARD } bc_gate_state_t;
typedef struct {
    bc_gate_state_t st;
    uint32_t guard_until_ms;
    uint32_t since_ms;           /* when the current state was entered */
    uint32_t last_feed_ms;       /* 0.6.1: last touch report seen (any state); silence while swallowing trips the watchdog */
    bool down;                   /* finger currently down as seen by the gate */
    uint32_t swallowed, guarded; /* presses dropped (diagnostics) */
    uint32_t watchdog_resets;    /* 0.6.1: SWALLOW abandoned because no release arrived in BC_GATE_WATCHDOG_MS */
} bc_gate_t;
void bc_gate_reset(bc_gate_t *g);
void bc_gate_screen_off(bc_gate_t *g);                       /* screen went dark: nothing passes */
void bc_gate_wake(bc_gate_t *g, bool finger_down, uint32_t now_ms);   /* display woke: swallow the rest of the gesture, then guard */
/** Every touch poll: returns true when the press state may be handed to the UI, false when it must read as "released". */
bool bc_gate_feed(bc_gate_t *g, bool pressed, uint32_t now_ms);
/** 0.6.1: call periodically (every <= 250 ms) even when the touch driver reports nothing: ends an expired guard and abandons
 *  a swallow that never saw its release (watchdog). Returns true when the state changed. */
bool bc_gate_tick(bc_gate_t *g, uint32_t now_ms);
bool bc_gate_blocking(const bc_gate_t *g);
const char *bc_gate_state_name(bc_gate_state_t st);

/* ---- hold-to-confirm (0.6.0 rev 3): START RIDE, END, delete, forget, restart, deep sleep.
 * Press and keep still for `hold_ms`: progress 0..100 for the ring; FIRE exactly once; release early or a slide of more than
 * BC_HOLD_SLIDE_PX cancels; after a fire the next press is ignored for BC_HOLD_COOLDOWN_MS (bounce / duplicate start). */
#define BC_HOLD_SLIDE_PX 20
#define BC_HOLD_COOLDOWN_MS 1500
typedef enum { BC_HOLD_IDLE = 0, BC_HOLD_HOLDING, BC_HOLD_FIRED, BC_HOLD_CANCELLED } bc_hold_ev_t;
typedef struct {
    uint32_t hold_ms;
    bool down, fired, slid; uint32_t t0; int x0, y0;
    uint32_t cooldown_until_ms;
    int progress;                /* 0..100 while holding */
    uint32_t fires, cancels_release, cancels_slide, ignored_cooldown;
} bc_hold_t;
void bc_hold_init(bc_hold_t *h, uint32_t hold_ms);
/** Feed press state + position on every event/poll. Returns FIRED exactly once per completed hold. */
bc_hold_ev_t bc_hold_feed(bc_hold_t *h, bool pressed, int x, int y, uint32_t now_ms);

/* ---- consumption tracker: millivolts lost per hour in each operating mode */
typedef enum { BC_MODE_IDLE_ON = 0, BC_MODE_RIDE_ON, BC_MODE_RIDE_OFF, BC_MODE_COUNT } bc_power_mode_t;
#define BC_DRAIN_MIN_S 1200       /* 20 min of data before any "hours left" is shown */
typedef struct {
    struct { uint32_t secs; int32_t drop_mv; int start_mv; bool open; } m[BC_MODE_COUNT];
    int cur; uint32_t cur_since_ms; int cur_start_mv;
} bc_drain_t;
void bc_drain_reset(bc_drain_t *d);
/** Mode switch or periodic sample (every 5 s). While USB power is likely the sample is ignored (voltage is not the cell's). */
void bc_drain_feed(bc_drain_t *d, bc_power_mode_t mode, int mv, uint32_t now_ms, bool usb_likely);
/** mV per hour for a mode; -1 until BC_DRAIN_MIN_S of data exist for it. */
int bc_drain_rate_mv_h(const bc_drain_t *d, bc_power_mode_t mode);
/** Hours left (x10) from the current voltage down to BC_BAT_CRIT_MV at that mode's rate; -1 when unknown. */
int bc_drain_hours_left_x10(const bc_drain_t *d, bc_power_mode_t mode, int mv);
const char *bc_power_mode_name(bc_power_mode_t m);

#ifdef __cplusplus
}
#endif
