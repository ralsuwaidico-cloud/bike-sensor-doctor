#include "app_power.h"
#include <stdio.h>
#include <string.h>
#include "app.h"

#define SAMPLE_MS 5000
#define CUE_WAKE_MS 5000

static app_power_t P;
static bc_usb_t s_usb; static bc_lowbat_t s_low; static bc_tap_t s_tap; static bc_drain_t s_drain;
static uint32_t s_last_sample_ms, s_last_log_ms;
static char s_alert[64]; static bool s_alert_pending;
static int s_last_cue_id = -1;
static uint32_t s_sleep_at_ms;          /* opt-in critical action pending (bat_protect == 1) */
static bool s_inited;

const app_power_t *app_power(void) { return &P; }

static bool riding(void) { bc_ride_state_t s = app_ride_state(); return s == BC_RIDE_RUNNING || s == BC_RIDE_PAUSED; }

static void alert(const char *txt) { snprintf(s_alert, sizeof s_alert, "%s", txt); s_alert_pending = true; plat_log(txt); }

/* every power action: ride journal flushed first (nothing recorded is lost), then one log line */
static void before_action(const char *what)
{
    app_journal_flush();
    char l[64]; snprintf(l, sizeof l, "POWER %s (ride %d, %d mV)", what, (int)app_ride_state(), P.mv); plat_log(l);
}

void app_power_init(void)
{
    memset(&P, 0, sizeof P);
    P.screen_on = true; P.mv = -1; P.pct = -1; P.hours_left_x10 = -1;
    for (int i = 0; i < BC_MODE_COUNT; i++) P.rate_mv_h[i] = -1;
    bc_usb_reset(&s_usb); bc_lowbat_reset(&s_low); bc_tap_reset(&s_tap); bc_drain_reset(&s_drain);
    s_last_sample_ms = 0; s_last_log_ms = 0; s_alert_pending = false; s_last_cue_id = -1; s_sleep_at_ms = 0;
    P.last_touch_ms = plat_ms();
    P.woke_from_sleep = plat_woke_from_sleep();
    if (P.woke_from_sleep) plat_log("POWER wake from deep sleep (touch / RESET / USB)");
    plat_backlight(app_profile()->brightness);
    plat_panel_sleep(false);
    s_inited = true;
}

static void sample(uint32_t now)
{
    int mv = plat_battery_mv();
    P.mv = mv; P.pct = bc_batt_pct_from_mv(mv);
    P.usb_likely = bc_usb_feed(&s_usb, mv, now) || plat_usb_power();
    bc_bat_level_t before = s_low.level, lv = bc_lowbat_feed(&s_low, P.usb_likely ? 0 : mv);
    P.bat_level = lv;
    /* drain attribution */
    bool ride = riding();
    bc_power_mode_t mode = ride ? (P.screen_on ? BC_MODE_RIDE_ON : BC_MODE_RIDE_OFF) : BC_MODE_IDLE_ON;
    bool untracked = !ride && !P.screen_on;                 /* idle with the screen off: not one of the three logged modes */
    bc_drain_feed(&s_drain, mode, mv, now, P.usb_likely || untracked);
    P.mode = mode;
    for (int i = 0; i < BC_MODE_COUNT; i++) P.rate_mv_h[i] = bc_drain_rate_mv_h(&s_drain, (bc_power_mode_t)i);
    P.hours_left_x10 = P.usb_likely ? -1 : bc_drain_hours_left_x10(&s_drain, mode, mv);
    if (now - s_last_log_ms >= 600000) {                     /* every 10 min: one line for the PC log */
        s_last_log_ms = now;
        char l[128]; snprintf(l, sizeof l, "POWER %d mV ~%d%% %s mode=%s drain idle/ride/ride-off %d/%d/%d mV/h", mv, P.pct, P.usb_likely ? "usb-likely" : "battery",
                              bc_power_mode_name(mode), P.rate_mv_h[0], P.rate_mv_h[1], P.rate_mv_h[2]);
        plat_log(l);
    }
    /* alerts on level changes (worse only) */
    if (lv > before) {
        char b[64];
        if (lv == BC_BAT_LOW) snprintf(b, sizeof b, "BATTERY LOW ~%d%%", P.pct);
        else if (lv == BC_BAT_VERY_LOW) snprintf(b, sizeof b, "BATTERY ~%d%% VERY LOW", P.pct);
        else snprintf(b, sizeof b, "BATTERY ~%d%% CRITICAL", P.pct);
        alert(b);
        app_journal_flush();                                  /* a low battery is a power-loss risk: get the ride on flash now */
        if (lv == BC_BAT_CRITICAL && app_profile()->bat_protect == 1) {
            /* OPT-IN, NOT VALIDATED: end + save the ride, then deep sleep a few seconds later */
            before_action("critical: protection ON -> auto-save");
            if (riding()) { app_ride_end(); app_ride_save(); alert("RIDE SAVED - battery empty"); }
            s_sleep_at_ms = now + 4000;
        }
    }
    if (!ride && app_profile()->bat_protect == 1 && !P.usb_likely && mv > 0 && mv <= BC_BAT_EMPTY_MV && !s_sleep_at_ms) {
        before_action("empty: protection ON -> sleep"); s_sleep_at_ms = now + 2000;
    }
}

void app_power_tick(uint32_t now)
{
    if (!s_inited || P.asleep) return;
    if (!s_last_sample_ms || now - s_last_sample_ms >= SAMPLE_MS) { s_last_sample_ms = now; sample(now); }
    const bc_profile_t *p = app_profile();
    bool ride = riding();
    /* automatic screen timeout: outside rides only, never on the onboarding screens, never while USB power is likely? (yes: still off — saves the panel) */
    if (P.screen_on && !ride && p->onboarded && p->scr_timeout_s && now - P.last_touch_ms >= (uint32_t)p->scr_timeout_s * 1000u && !P.wake_until_ms) {
        P.auto_offs++; app_power_screen_off();
    }
    /* short wake after a coach warning ends */
    if (P.wake_until_ms && (int32_t)(now - P.wake_until_ms) >= 0) { P.wake_until_ms = 0; if (P.screen_on && now - P.last_touch_ms >= CUE_WAKE_MS) app_power_screen_off(); }
    /* coach warning while the screen is off during a ride: wake for 5 s (optional) */
    if (ride && !P.screen_on && p->wake_on_cue) {
        const bc_cue_t *c = app_cue();
        if (c->level == BC_LVL_WARN && (int)c->id != s_last_cue_id) { s_last_cue_id = (int)c->id; P.cue_wakes++; P.wake_until_ms = now + CUE_WAKE_MS; app_power_screen_wake(); P.wake_until_ms = now + CUE_WAKE_MS; }
    }
    if (ride) { const bc_cue_t *c = app_cue(); if (c->level != BC_LVL_WARN) s_last_cue_id = -1; }
    /* auto-sleep: idle N minutes on battery, no ride */
    if (!ride && p->onboarded && p->auto_sleep_min && !P.usb_likely && now - P.last_touch_ms >= (uint32_t)p->auto_sleep_min * 60000u) {
        plat_log("POWER auto-sleep after idle time"); app_power_sleep();
        return;
    }
    if (s_sleep_at_ms && (int32_t)(now - s_sleep_at_ms) >= 0) { s_sleep_at_ms = 0; if (!riding()) app_power_sleep(); }
}

void app_power_touch(bool pressed, uint32_t now)
{
    if (pressed) P.last_touch_ms = now;
    if (!P.screen_on) {
        if (bc_tap_feed(&s_tap, pressed, now)) { P.wakes++; app_power_screen_wake(); }
    } else bc_tap_reset(&s_tap);
}

void app_power_screen_off(void)
{
    if (!P.screen_on) return;
    before_action("screen off");
    P.screen_on = false; P.screen_off_ms = plat_ms(); P.screen_offs++;
    bc_tap_reset(&s_tap);
    plat_backlight(0);
    plat_panel_sleep(true);
}

void app_power_screen_wake(void)
{
    if (P.screen_on) return;
    plat_panel_sleep(false);
    plat_backlight(app_profile()->brightness);
    P.screen_on = true; P.last_touch_ms = plat_ms();
    plat_log("POWER screen on");
}

void app_power_lock(void) { if (P.locked) return; before_action("touch lock"); P.locked = true; P.lock_count++; }
void app_power_unlock(void) { if (!P.locked) return; P.locked = false; plat_log("POWER touch unlocked"); }

bool app_power_can_sleep(void) { return !riding(); }

bool app_power_sleep(void)
{
    if (!app_power_can_sleep()) { plat_log("POWER sleep refused: ride active"); return false; }
    before_action("deep sleep");
    app_profile_save();
    plat_wifi_set_enabled(false);          /* radio only; the profile keeps wifi_on so it returns after the wake */
    plat_phone_set_enabled(false);
    plat_backlight(0);
    plat_panel_sleep(true);
    P.sleeps_requested++; P.asleep = true; P.screen_on = false;
    plat_deep_sleep();                     /* device: never returns. harness: boot() plays the wake */
    return true;
}

void app_power_restart(void)
{
    before_action("restart");
    app_profile_save();
    P.restarts_requested++;
    plat_restart();
}

bool app_power_take_alert(char *buf, uint32_t cap)
{
    if (!s_alert_pending) return false;
    snprintf(buf, cap, "%s", s_alert); s_alert_pending = false; return true;
}

void app_power_batt_short(char *buf, uint32_t cap)
{
    if (P.usb_likely) snprintf(buf, cap, "USB");
    else if (P.pct < 0) snprintf(buf, cap, "?");
    else snprintf(buf, cap, "~%d%%", P.pct);
}

void app_power_batt_detail(char *buf, uint32_t cap)
{
    if (P.mv <= 0) { snprintf(buf, cap, "no battery reading"); return; }
    char hl[40];
    if (P.usb_likely) snprintf(hl, sizeof hl, "USB power likely (inferred)");
    else if (P.hours_left_x10 >= 0 && P.hours_left_x10 < 999) snprintf(hl, sizeof hl, "about %d.%d h left (est.)", P.hours_left_x10 / 10, P.hours_left_x10 % 10);
    else snprintf(hl, sizeof hl, "hours left: after 20 min");
    snprintf(buf, cap, "%d.%02d V  ~%d%% est.\n%s", P.mv / 1000, P.mv % 1000 / 10, P.pct, hl);
}

static const int TO[] = { 30, 60, 120, 300, 0 };
int app_power_timeout_next(int cur) { for (int i = 0; i < 5; i++) if (TO[i] == cur) return TO[(i + 1) % 5]; return 60; }
const char *app_power_timeout_name(int s)
{
    switch (s) { case 30: return "30 s"; case 60: return "1 min"; case 120: return "2 min"; case 300: return "5 min"; case 0: return "never"; }
    return "1 min";
}
static const int AS[] = { 0, 5, 10, 30 };
int app_power_autosleep_next(int cur) { for (int i = 0; i < 4; i++) if (AS[i] == cur) return AS[(i + 1) % 4]; return 10; }
const char *app_power_autosleep_name(int m)
{
    switch (m) { case 0: return "off"; case 5: return "5 min"; case 10: return "10 min"; case 30: return "30 min"; }
    return "10 min";
}
