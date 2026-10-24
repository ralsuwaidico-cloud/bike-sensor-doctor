/*
 * bc_core — power-management logic that needs no hardware: battery estimate, USB-power inference, low-battery
 * levels with hysteresis, the triple-tap detector and the consumption (drain) tracker. Pure functions and small state
 * machines fed with milliseconds and millivolts, so test/host can prove them and the device and the simulator share them.
 *
 * Honesty rules (Rashed, 24 Oct 2026):
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

/* ---- triple tap: three presses (press→release) within BC_TAP_WINDOW_MS; single and double taps are ignored */
#define BC_TAP_WINDOW_MS 1500
#define BC_TAP_MAX_PRESS_MS 600   /* a longer press is a hold, not a tap */
typedef struct { uint32_t t[3]; int n; bool down; uint32_t down_ms; } bc_tap_t;
void bc_tap_reset(bc_tap_t *t);
/** Feed press state changes (or the current state every poll); returns true exactly once when the 3rd tap lands. */
bool bc_tap_feed(bc_tap_t *t, bool pressed, uint32_t now_ms);

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
