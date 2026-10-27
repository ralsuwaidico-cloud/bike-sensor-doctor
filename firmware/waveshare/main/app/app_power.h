/*
 * Power management (0.5.0, reworked 0.6.0): battery estimate + USB inference, screen off / any-touch wake (gesture swallowed + guard), touch lock,
 * automatic screen timeout, deep sleep (no ride active), low-battery alerts, safe restart. Shared by the device and
 * the PC harness; the hardware side is behind plat.h (plat_backlight, plat_panel_sleep, plat_deep_sleep).
 *
 * Safety invariants (owner, 24 Oct 2026):
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
    uint32_t taps_rejected;      /* presses on the dark screen that were not accepted as taps (slides, holds, bursts) */
    bc_gate_t gate;              /* rev 3: swallows the waking gesture + a guard so a wake never presses a control */
    uint32_t wake_at_ms;         /* when the display last woke (0 = never) */
    bool woke_from_sleep;        /* this boot was a wake from deep sleep */
    bool standby;                /* 0.6.0 connected standby: screen off, no ride, Bluetooth link kept, sensor scanning paused */
    uint32_t standbys;
    char sleep_block[40];        /* why auto deep sleep is not happening right now ("" = nothing blocks it) */
    bool safe_mode;              /* 0.6.1: BOOT held at reset — touch gate forced open, defaults for display settings */
    uint32_t touch_reports;      /* 0.6.1 diagnostics: raw reports from the touch driver since boot */
    uint32_t touch_passed;       /* ... of which reached LVGL as a press */
} app_power_t;

void app_power_init(void);                       /* after app_init(); reads the profile settings */
void app_power_tick(uint32_t now_ms);            /* every 250 ms from the UI timer */
void app_power_touch(bool pressed, uint32_t now_ms);   /* every press/release seen by the touch layer */
void app_power_touch_xy(bool pressed, int x, int y, uint32_t now_ms);   /* same, with the position (slide rejection) */
void app_power_settle(uint32_t now_ms);                 /* screen off, finger up: lets a completed gesture fire (call every <= 50 ms) */
/** THE touch gate (rev 3). Called by the input driver's read callback on every poll with the raw press state and position.
 *  Returns true when the press may be handed to LVGL; false = report "released" (screen off, waking gesture, guard period).
 *  Wake detection happens here: any touch (default) wakes on the first contact; 2/3 taps use the tap detector. */
bool app_power_touch_filter(bool pressed, int x, int y, uint32_t now_ms);
/** Taps needed to wake the dark screen right now: the profile's wake_taps (1 = any touch, default). */
int app_power_wake_taps_now(void);
const char *app_power_wake_name(int taps);              /* "any touch" / "2 taps" / "3 taps" */
int app_power_wake_next(int taps);                      /* Settings cycle 1 -> 2 -> 3 -> 1 */
/** UI hook run right after the display wakes (backlight fade-in); may be NULL. */
void app_power_set_wake_hook(void (*hook)(void));
bool app_power_gate_blocking(void);                     /* true while touches are being swallowed / guarded */
/** 0.6.1 SAFE MODE (BOOT held during RESET): the gate never swallows (a touch on a dark screen wakes it and is passed through),
 *  wake gesture = any touch, touch lock off, brightness 80 %, screen timeout 5 min — in memory only, nothing saved. */
void app_power_set_safe_mode(bool on);
bool app_power_safe_mode(void);
const char *app_power_gate_text(void);                  /* "pass" / "off" / "swallow" / "guard" (diagnostics) */
/** A hold-to-confirm just fired and the screen is about to change: swallow the rest of this touch + guard, so the
 *  finger still on the glass cannot press whatever appears underneath (results screen, Home...). */
void app_power_swallow_rest(void);
const app_power_t *app_power(void);

void app_power_screen_off(void);                 /* allowed any time, also during a ride (recording continues) */
void app_power_screen_wake(void);
void app_power_lock(void);
void app_power_unlock(void);
bool app_power_can_sleep(void);                  /* false while a ride runs or is paused */
bool app_power_sleep(void);
/** Settings from the phone switched the phone link off: apply it after the reply has been sent (~1 s). */
void app_power_phone_link_deferred_off(void);
/** Human text for the three power states (Quick Settings / Device Health). */
const char *app_power_state_text(void);                      /* journal + profile saved, radios off, deep sleep; false if refused */
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
