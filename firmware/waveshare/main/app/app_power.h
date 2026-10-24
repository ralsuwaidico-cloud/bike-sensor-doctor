/*
 * Power management (firmware 0.5.0): battery estimate + USB inference, screen off / triple-tap wake, touch lock,
 * automatic screen timeout, deep sleep (no ride active), low-battery alerts, safe restart. Shared by the device and
 * the PC harness; the hardware side is behind plat.h (plat_backlight, plat_panel_sleep, plat_deep_sleep).
 *
 * Safety invariants (Rashed, 24 Oct 2026):
 *  - nothing here ever pauses or ends a ride by itself unless bc_profile.bat_protect == 1, which is OFF by default and
 *    labelled NOT VALIDATED in every menu; by default a low battery only alerts;
 *  - Sleep is refused while a ride is running or paused;
 *  - every power action flushes the ride journal first and writes one line to the device log;
 *  - the percentage is an estimate ("~"), "USB power likely" is an inference, the word "charging" is never used.
 */
#pragma once
#include <stdbool.h>
#include <stdint.h>
#include "bc_power.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    bool screen_on;
    bool locked;
    bool asleep;                 /* deep sleep requested (host harness only: the device never returns from it) */
    int mv, pct;                 /* latest filtered reading and its ESTIMATED percentage (-1 unknown) */
    bool usb_likely;             /* inference, see bc_usb_feed */
    bc_bat_level_t bat_level;
    bc_power_mode_t mode;        /* what the drain tracker is currently attributing consumption to */
    int rate_mv_h[BC_MODE_COUNT];      /* -1 until 20 min of data */
    int hours_left_x10;          /* for the current mode, -1 unknown */
    uint32_t last_touch_ms, screen_off_ms, wake_until_ms;
    uint32_t screen_offs, wakes, lock_count, sleeps_requested, restarts_requested, auto_offs, cue_wakes;
    bool woke_from_sleep;        /* this boot was a wake from deep sleep */
} app_power_t;

void app_power_init(void);                       /* after app_init(); reads the profile settings */
void app_power_tick(uint32_t now_ms);            /* every 250 ms from the UI timer */
void app_power_touch(bool pressed, uint32_t now_ms);   /* every press/release seen by the touch layer */
const app_power_t *app_power(void);

void app_power_screen_off(void);                 /* allowed any time, also during a ride (recording continues) */
void app_power_screen_wake(void);
void app_power_lock(void);
void app_power_unlock(void);
bool app_power_can_sleep(void);                  /* false while a ride runs or is paused */
bool app_power_sleep(void);                      /* journal + profile saved, radios off, deep sleep; false if refused */
void app_power_restart(void);                    /* journal + profile saved, then restart */
/** Pending one-line alert for a toast (low battery etc.); returns false when none. */
bool app_power_take_alert(char *buf, uint32_t cap);
/** "~63%" style text and a longer status line for Quick Settings / Device Health. */
void app_power_batt_short(char *buf, uint32_t cap);
void app_power_batt_detail(char *buf, uint32_t cap);
/** Screen-timeout option helpers for the Settings rows (seconds; 0 = never). */
int app_power_timeout_next(int cur_s);
const char *app_power_timeout_name(int s);
int app_power_autosleep_next(int cur_min);
const char *app_power_autosleep_name(int m);

#ifdef __cplusplus
}
#endif
