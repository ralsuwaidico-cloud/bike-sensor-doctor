/*
 * Bike Computer — Waveshare ESP32-S3-Touch-LCD-1.28-B firmware 0.7.4-dev (0.7.3 + crash fix: Bluetooth never aborts the start).
 * Standalone cycling computer: onboarding, home, ride (4 pages + controls), coach, results, history, settings, sensors,
 * DEMO MODE. App/UI code is shared with the PC test harness (test/sim); hardware lives in hw.c, ble_central.c, plat_esp.c.
 *
 * Start-up (0.7.3, bc_boot.h + docs/FIRMWARE_0.7.3.md):
 *  - the previous run's last log lines (RTC memory) are kept and the log is mirrored into RTC memory again;
 *  - NVS, then the boot plan: NORMAL, STAGED (one subsystem at a time; the one that crashed is disabled instead of looping)
 *    or RECOVERY (3 crash resets in a row or 3 crashed staged boots: only display + touch + storage, the RECOVERY screen);
 *  - a subsystem marker is written to RTC memory before every subsystem: display, storage, phone link, Wi-Fi, sensor
 *    central, power meter, HR strap, speed/cadence sensor;
 *  - after a crash the report (core dump summary + log tail + events) is stored before anything else runs;
 *  - health line every 60 s (now under the LVGL lock: the app state belongs to the UI task) + the event-log health monitor.
 * 0.7.4 (coord/reports/FW_STORAGE_MEMORY_REPORT.md): the 0.7.3 board aborted in app_main on every start - ESP_ERROR_CHECK(nimble_port_init())
 * after "BLE_INIT: hci inits failed" (decoded with the matching ELF fa0edc5ac). Now:
 *  - the Bluetooth stack (controller + NimBLE port, internal-RAM buffers) is its own stage, started right after storage and
 *    BEFORE touch, profile and screens take internal RAM (0.7.2 order, where it worked); heap figures are logged around it;
 *  - a failure never aborts: "Bluetooth unavailable" + reason on Connections / Phone / Device Health, everything else runs;
 *  - a subsystem that crashes twice in a row while starting is disabled on the next boot even in a NORMAL boot (bc_boot), and a
 *    disabled phone link / Bluetooth stack is really not started (0.7.3 still called ble_central_start() when it was "skipped");
 *  - storage reports its real category (bc_storage.h) and is never formatted or written when damaged.
 * Never pass %f to lv_*_fmt (LVGL printf has no float support) — test/host `make lint` enforces it.
 */
#include <stdio.h>
#include "esp_log.h"
#include "esp_app_desc.h"
#include "esp_system.h"
#include "esp_attr.h"
#include "esp_timer.h"
#include "esp_heap_caps.h"
#include "esp_sleep.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_lvgl_port.h"
#include "nvs.h"
#include "hw.h"
#include "ble_central.h"
#include "app.h"
#include "app_power.h"
#include "app_diag.h"
#include "ui.h"
#include "diag_esp.h"
void net_wifi_init(void);

static const char *TAG = "main";
uint32_t g_crash_consecutive;

static const char *reason_name(esp_reset_reason_t r)
{
    switch (r) {
    case ESP_RST_POWERON: return "power-on / RESET button";
    case ESP_RST_SW: return "software restart";
    case ESP_RST_PANIC: return "crash (panic)";
    case ESP_RST_INT_WDT: return "interrupt watchdog";
    case ESP_RST_TASK_WDT: return "task watchdog";
    case ESP_RST_WDT: return "watchdog";
    case ESP_RST_BROWNOUT: return "brownout (low voltage)";
    case ESP_RST_DEEPSLEEP: return "wake from deep sleep";
    case ESP_RST_USB: return "USB reset";
    case ESP_RST_JTAG: return "JTAG";
    default: return "other";
    }
}

/* persistent counters for Device Health (NVS namespace "diag", next to the boot counter) */
static void bump(const char *key)
{
    nvs_handle_t h; uint32_t v = 0;
    if (nvs_open("diag", NVS_READWRITE, &h) != ESP_OK) return;
    nvs_get_u32(h, key, &v); nvs_set_u32(h, key, v + 1); nvs_commit(h); nvs_close(h);
}

static void health(void)
{
    static char line[320];
    lv_mem_monitor_t m;
    lvgl_port_lock(0); app_health_line(line, sizeof line); lv_mem_monitor(&m); lvgl_port_unlock();   /* 0.7.3: app state under the UI lock */
    TaskHandle_t lv = xTaskGetHandle("taskLVGL"), nb = xTaskGetHandle("nimble_host"), mg = xTaskGetHandle("ble_mgr"), tm = xTaskGetHandle("esp_timer");
    ESP_LOGI(TAG, "%s lvgl %u%% (max %uB) stack-free lvgl %u nimble %u ble_mgr %u esp_timer %u main %u", line, m.used_pct, (unsigned)m.max_used,
             lv ? (unsigned)uxTaskGetStackHighWaterMark(lv) : 0, nb ? (unsigned)uxTaskGetStackHighWaterMark(nb) : 0,
             mg ? (unsigned)uxTaskGetStackHighWaterMark(mg) : 0, tm ? (unsigned)uxTaskGetStackHighWaterMark(tm) : 0, (unsigned)uxTaskGetStackHighWaterMark(NULL));
}

/* 0.6.1: ten seconds after boot, say over serial whether the touch controller has reported anything at all */
static void touch_check_cb(void *arg)
{
    (void)arg;
    uint32_t reads = 0, presses = 0; hw_touch_counters(&reads, &presses);
    lvgl_port_lock(0);
    hw_touch_diag_log("10 s self-check");
    const app_power_t *pw = app_power();
    uint32_t tr = pw->touch_reports, tp = pw->touch_passed; bool on = pw->screen_on; const char *gate = app_power_gate_text();
    lvgl_port_unlock();
    ESP_LOGI(TAG, "touch 10 s self-check: driver reads %u (finger down %u), gate reports %u passed %u, gate=%s, screen %s%s",
             (unsigned)reads, (unsigned)presses, (unsigned)tr, (unsigned)tp, gate, on ? "on" : "off", reads == 0 ? " - NO TOUCH REPORT YET (normal if the glass was not touched)" : "");
}

static bc_boot_plan_t s_plan;
static bc_boot_rtc_t *R;

/* marker before a subsystem; in a staged boot it is announced and given time to run before the next one */
static void stage(bc_subsys_t s, const char *announce)
{
    bc_boot_mark(R, s);
    ESP_LOGI(TAG, "STAGE %s starting%s", bc_subsys_name(s), s_plan.mode == BC_BOOT_STAGED ? " (staged boot)" : "");
    lvgl_port_lock(0); app_diag_stage(s, 0);
    if (s_plan.mode == BC_BOOT_STAGED && announce) ui_toast(announce);
    lvgl_port_unlock();
}
static void stage_done(bc_subsys_t s, int result, uint32_t staged_dwell_ms)
{
    lvgl_port_lock(0); app_diag_stage(s, result); lvgl_port_unlock();
    ESP_LOGI(TAG, "STAGE %s %s", bc_subsys_name(s), result == 1 ? "up" : result == 2 ? "SKIPPED (disabled after a crash)" : "failed");
    if (s_plan.mode == BC_BOOT_STAGED && result == 1 && staged_dwell_ms) vTaskDelay(pdMS_TO_TICKS(staged_dwell_ms));
}
static bool skipped(bc_subsys_t s) { return (s_plan.skip & BC_SS_BIT(s)) != 0; }

/* rc3 (QA QF-25): the recovery screen crashed last time - a static text, nothing else. Its own marker (RECMIN): if even this
   crashes, the next start halts (bc_boot_plan). */
static void minimal_mode(void)
{
    ESP_LOGW(TAG, "RECOVERY (MINIMAL): the recovery screen crashed on the previous start - static text only (no touch, no Bluetooth)");
    bc_boot_mark(R, BC_SS_RECMIN);
    lvgl_port_lock(0);
    hw_backlight_set(80);
    ui_recovery_minimal_show();
    lvgl_port_unlock();
    for (;;) { vTaskDelay(pdMS_TO_TICKS(60000)); ESP_LOGW(TAG, "recovery (minimal): waiting - unplug to restart"); }
}
static void recovery_mode(lv_display_t *disp)
{
    ESP_LOGW(TAG, "RECOVERY MODE: %u crash resets in a row / %u crashed staged boots - display, touch and storage only", (unsigned)R->crash_streak, (unsigned)R->staged_fails);
    bump("safemode");
    bc_boot_mark(R, BC_SS_RECUI);                            /* rc3 (QF-25): a crash from here on is the recovery screen's */
    hw_touch_init(disp);                                     /* no wake gesture filter: the screen stays on */
    lvgl_port_lock(0);
    hw_backlight_set(80);
    ui_recovery_show();
    lvgl_port_unlock();
    for (;;) { vTaskDelay(pdMS_TO_TICKS(60000)); ESP_LOGI(TAG, "recovery mode, waiting for the rider (RESTART & DIAGNOSE / SEND LOGS)"); }
}

void app_main(void)
{
    diag_esp_early_init();                                   /* before the first log line: keeps the previous run's tail */
    const esp_app_desc_t *d = esp_app_get_description();
    esp_reset_reason_t why = esp_reset_reason();
    ESP_LOGI(TAG, "Bike Computer firmware %s (%s %s)", d->version, d->date, d->time);

    /* 0.6.0: woken from deep sleep by a touch — the waking touch is tap 1; the remaining taps (rider's setting, 2 or 3 in
       total) must follow within 2.5 s or the device goes straight back to sleep. RESET and USB wakes skip the check. */
    if (why == ESP_RST_DEEPSLEEP && esp_sleep_get_wakeup_cause() == ESP_SLEEP_WAKEUP_EXT0) {
        ESP_LOGI(TAG, "STAGE 0 touch wake: waiting for %d taps", hw_wake_taps_needed());
        if (!hw_wake_tap_check()) hw_deep_sleep_touch_wake(hw_wake_taps_needed());   /* never returns */
    }

    hw_selftest_nvs();                                       /* NVS before the plan (disabled subsystems live there) */
    R = plat_boot_rtc();
    /* rc3 (QA QF-26): the crash-run counter in NVS is updated BEFORE storage starts (so a crash in storage with RTC memory lost
       is still counted), then the limiter combines it with the RTC run streak */
    uint8_t nvs_run = plat_crash_run_update(plat_reset_kind());
    bc_boot_plan(R, plat_reset_kind(), plat_boot_skip_load(), &s_plan);
    bc_boot_limit(R, &s_plan, nvs_run);
    if (s_plan.newly_skipped) plat_boot_skip_save(s_plan.skip);
    if (s_plan.halt) {   /* rc3 (QF-25): even the minimal recovery text crashed: start nothing, never loop */
        ESP_LOGE(TAG, "HALT: the minimal recovery screen crashed on the previous start. Nothing is started. Unplug the board and tell Claude (READ-BOARD-STATE).");
        for (;;) { vTaskDelay(pdMS_TO_TICKS(60000)); ESP_LOGE(TAG, "halted after repeated recovery crashes - unplug to restart"); }
    }
    if (s_plan.brownout) ESP_LOGW(TAG, "brownout reset (%u in a row): power dip - not counted as a crash", (unsigned)s_plan.brown_streak);
    if (s_plan.limited) ESP_LOGW(TAG, "crash-loop limiter: %u crash resets in a row (NVS %u) -> RECOVERY%s%s%s", (unsigned)s_plan.run_streak, (unsigned)nvs_run,
                                 s_plan.no_storage ? ", no storage" : "", s_plan.no_diag ? ", no diagnostics" : "", s_plan.minimal ? ", minimal" : "");
    g_crash_consecutive = R->crash_streak;
    if (s_plan.crashed) bump("crashes");
    ESP_LOGI(TAG, "reset reason: %s, consecutive crash resets: %u, boot mode %s, crashed subsystem %s, disabled 0x%03X",
             reason_name(why), (unsigned)R->crash_streak, bc_boot_mode_name(s_plan.mode), bc_subsys_name((bc_subsys_t)s_plan.suspect), s_plan.skip);

    bc_boot_mark(R, BC_SS_DISPLAY);
    lv_display_t *disp = hw_display_init();
    ESP_LOGI(TAG, "STAGE display OK");
    /* 0.7.4 (QA QF-03): a RECOVERY boot does not start again the stage the last crash happened in (storage, or the boot
       record + diagnostics init), so a crash there cannot loop even in RECOVERY. */
    bc_boot_mark(R, BC_SS_STORAGE);
    bool storage_ok = false;
    if (s_plan.no_storage) { hw_storage_skip(); ESP_LOGW(TAG, "STAGE storage NOT started: the last crash happened while it started (recovery)"); }
    else storage_ok = hw_selftest_storage();
    ESP_LOGI(TAG, "STAGE storage %s", storage_ok ? "OK" : "FAILED (logs stay in RAM)");
    bc_boot_mark(R, BC_SS_DIAG);
    if (!s_plan.no_diag) {
        /* boot record FIRST: it reads the core-dump summary before app_diag copies + erases the dump (QA QF-04) */
        diag_esp_bootrec_begin(&s_plan, hw_storage_state());
        /* QA QF-09: the NVS records show 4 crash resets in a row that the RTC state missed (RTC lost, or each crash came
           more than 20 s after the start) -> RECOVERY */
        if (s_plan.mode == BC_BOOT_NORMAL && diag_esp_crash_streak() >= 4) {
            bc_boot_force_recovery(R, &s_plan);
            ESP_LOGW(TAG, "boot records: %d crash resets in a row -> RECOVERY", diag_esp_crash_streak());
        }
        /* two boots in a row whose Bluetooth start FAILED (no crash, e.g. no internal RAM) -> Bluetooth disabled until RETRY.
           Decided BEFORE app_diag_init, so the Phone screen offers RETRY on this very boot (QA QF-07). */
        if (s_plan.mode != BC_BOOT_RECOVERY && !skipped(BC_SS_BTSTACK) && diag_esp_bt_fail_streak() >= 2) {
            bc_boot_disable(R, BC_SS_BTSTACK); s_plan.skip |= BC_SS_BIT(BC_SS_BTSTACK); plat_boot_skip_save(s_plan.skip);
            ESP_LOGW(TAG, "Bluetooth start failed on %d boots in a row: disabled until RETRY (Phone screen)", diag_esp_bt_fail_streak());
        }
        lvgl_port_lock(0);
        app_diag_init(&s_plan, storage_ok);                  /* BOOT event; after a crash the report is stored now */
        app_diag_stage(BC_SS_DISPLAY, 1); app_diag_stage(BC_SS_STORAGE, s_plan.no_storage ? 2 : storage_ok ? 1 : 3);
        lvgl_port_unlock();
    } else ESP_LOGW(TAG, "STAGE diagnostics NOT started: the last crash happened there (recovery; the core dump stays in its partition)");
    if (s_plan.mode == BC_BOOT_RECOVERY) { if (s_plan.minimal) minimal_mode(); else recovery_mode(disp); return; }

    /* 0.7.4: Bluetooth stack first (its HCI buffers must come from internal RAM; see the header comment) */
    bool bt_stack = false;
    stage(BC_SS_BTSTACK, NULL);
    if (skipped(BC_SS_BTSTACK)) { diag_esp_bt_disabled("off after 2 failures"); stage_done(BC_SS_BTSTACK, 2, 0); }
    else { bt_stack = ble_central_stack_init(); stage_done(BC_SS_BTSTACK, bt_stack ? 1 : 3, 0); }
    diag_esp_bootrec_bt(ble_central_init_info(), skipped(BC_SS_BTSTACK), s_plan.skip);

    /* 0.6.1 SAFE MODE (touch): BOOT held while RESET is pressed -> the wake gate is forced open and the display settings run on
       defaults for this boot only (nothing saved). Recovery path that does not depend on the touch gate or on saved settings. */
    bool touch_safe = hw_boot_button_held();
    hw_touch_init(disp);
    hw_touch_set_filter(app_power_touch_filter);   /* wake gesture swallowed + guard: a wake can never press a control */
    app_power_set_safe_mode(touch_safe);
    if (touch_safe) { ESP_LOGW(TAG, "SAFE MODE (touch gate off): BOOT was held at reset. Settings and rides untouched."); bump("touchsafe"); }
    { esp_timer_handle_t t10; esp_timer_create_args_t a10 = { .callback = touch_check_cb, .name = "touch10s" };
      if (esp_timer_create(&a10, &t10) == ESP_OK) esp_timer_start_once(t10, 10 * 1000 * 1000); }

    lvgl_port_lock(0);
    app_init();                           /* profile from NVS; an interrupted ride is recovered here */
    bc_profile_t *p = app_profile();
    if (touch_safe) { p->brightness = 80; p->scr_timeout_s = 300; p->wake_taps = 1; }   /* this boot only; app_profile_save() is not called here */
    ui_start();
    if (s_plan.mode == BC_BOOT_STAGED) ui_toast("Diagnosing: starting one part at a time");
    if (!hw_settings_ok()) ui_toast("Settings memory needs repair");   /* QA QF-02: NVS not erased, nothing saved this boot */
    else if (s_plan.brown_streak >= 2) { char b[56]; snprintf(b, sizeof b, "Power dips: %u restarts - check battery", (unsigned)s_plan.brown_streak); ui_toast(b); }   /* rc3 QF-26 */
    else if (!bt_stack) ui_toast("Bluetooth unavailable - see Connections");
    else if (s_plan.newly_skipped && s_plan.suspect != BC_SS_POWER && s_plan.suspect != BC_SS_HR && s_plan.suspect != BC_SS_CSC) { char b[56];   /* sensors: own toast below */ snprintf(b, sizeof b, "%s disabled after a crash", bc_subsys_name((bc_subsys_t)s_plan.suspect)); ui_toast(b); }
    lvgl_port_unlock();
    ESP_LOGI(TAG, "STAGE app + screens OK");

    /* phone link (NimBLE host + the BikeComputer Link service). The sensor central starts later, on its own stage. The host
       serves both, so a phone link disabled after crashes means no Bluetooth host this boot (sensors included). */
    stage(BC_SS_PHONE, "Starting the phone link");
    bool bt_up = false;
    if (!bt_stack) stage_done(BC_SS_PHONE, skipped(BC_SS_BTSTACK) ? 2 : 3, 0);
    else if (skipped(BC_SS_PHONE)) { diag_esp_bt_disabled("phone link off: crashes"); stage_done(BC_SS_PHONE, 2, 0); }   /* this power cycle */
    else { bt_up = ble_central_start(false); diag_esp_ble_started(); diag_esp_bootrec_bt(ble_central_init_info(), false, s_plan.skip); stage_done(BC_SS_PHONE, bt_up ? 1 : 3, 10000); }

    stage(BC_SS_WIFI, p->wifi_on ? "Starting Wi-Fi" : NULL);
    net_wifi_init();                      /* background manager; radio stays off unless the rider switched Wi-Fi on */
    g_selftest.wifi = HW_INFO; snprintf(g_selftest.wifi_s, sizeof g_selftest.wifi_s, p->wifi_on ? "on" : "off (optional)");
    if (skipped(BC_SS_WIFI)) stage_done(BC_SS_WIFI, 2, 0);
    else { if (p->wifi_on) plat_wifi_set_enabled(true); stage_done(BC_SS_WIFI, 1, p->wifi_on ? 8000 : 0); }

    stage(BC_SS_CENTRAL, bt_up ? "Starting sensor Bluetooth" : NULL);
    bool central = bt_up && !skipped(BC_SS_CENTRAL);
    if (central) { ble_central_enable_sensors(true); stage_done(BC_SS_CENTRAL, 1, 3000); } else stage_done(BC_SS_CENTRAL, bt_up ? 2 : 3, 0);

    static const struct { bc_subsys_t ss; plat_sens_kind_t k; const char *msg; uint32_t dwell; } SENS[3] = {
        { BC_SS_POWER, PLAT_SENS_POWER, "Connecting the power meter", 25000 },
        { BC_SS_HR, PLAT_SENS_HR, "Connecting the HR strap", 15000 },
        { BC_SS_CSC, PLAT_SENS_CSC, "Connecting the speed/cadence sensor", 15000 } };
    for (int i = 0; i < 3; i++) {
        const bc_sensor_pair_t *sp = SENS[i].k == PLAT_SENS_POWER ? &p->power : SENS[i].k == PLAT_SENS_HR ? &p->hr : &p->csc;
        if (!sp->paired) continue;
        stage(SENS[i].ss, central ? SENS[i].msg : NULL);
        bool off = !central || skipped(SENS[i].ss);
        if (off) ble_central_set_disabled(SENS[i].k, true);
        ble_central_set_paired(SENS[i].k, sp->mac, sp->addr_type, sp->name);
        stage_done(SENS[i].ss, off ? 2 : 1, SENS[i].dwell);
        if (off && skipped(SENS[i].ss)) { lvgl_port_lock(0); char b[48]; snprintf(b, sizeof b, "%s disabled after a crash - RETRY", SENS[i].ss == BC_SS_POWER ? "Power meter" : SENS[i].ss == BC_SS_HR ? "HR strap" : "Sensor"); ui_toast(b); lvgl_port_unlock(); }
    }
    bc_boot_mark(R, BC_SS_RUNNING);   /* (QA QF-20: no NVS write here - the record is written at start, after Bluetooth, at STABLE) */
    ESP_LOGI(TAG, "STAGE all subsystems started (power meter %s, HR %s)", p->power.paired ? "paired" : "not paired", p->hr.paired ? "paired" : "not paired");

    /* stable: 20 s after everything is up (a staged boot also stores a "recovery session" report with what happened) */
    bool was_staged = s_plan.mode == BC_BOOT_STAGED;
    vTaskDelay(pdMS_TO_TICKS(BC_BOOT_STABLE_MS));
    bc_boot_stable(R);
    ESP_LOGI(TAG, "STAGE stable for 20 s - crash counter cleared"); diag_esp_bootrec_reached(BC_SS_STABLE);
    lvgl_port_lock(0);
    if (was_staged) {
        char note[160]; int n = snprintf(note, sizeof note, "staged boot completed without a crash");
        if (s_plan.skip && n > 0 && (size_t)n < sizeof note) {
            snprintf(note + n, sizeof note - (size_t)n, "; disabled after a crash:%s%s%s%s%s%s%s", s_plan.skip & BC_SS_BIT(BC_SS_BTSTACK) ? " Bluetooth-stack" : "", s_plan.skip & BC_SS_BIT(BC_SS_PHONE) ? " phone link" : "",
                     s_plan.skip & BC_SS_BIT(BC_SS_WIFI) ? " Wi-Fi" : "", s_plan.skip & BC_SS_BIT(BC_SS_CENTRAL) ? " sensor-Bluetooth" : "",
                     s_plan.skip & BC_SS_BIT(BC_SS_POWER) ? " power-meter" : "", s_plan.skip & BC_SS_BIT(BC_SS_HR) ? " HR-strap" : "", s_plan.skip & BC_SS_BIT(BC_SS_CSC) ? " CSC" : "");
        }
        app_diag_store_report(BC_DIAG_KIND_RECOVERY, note);
        ui_toast(s_plan.skip ? "Diagnosis done - see Connections" : "Diagnosis done - all parts OK");
    }
    app_diag_stage(BC_SS_STABLE, 1);
    lvgl_port_unlock();

    /* rc4 (QA RC3-05): the crash-loop counters count crashes that come close together. After 10 minutes of normal running
       they are cleared (RTC + NVS), so sporadic crashes days apart never add up to a forced RECOVERY in the middle of a ride. */
    int run_min = 0; bool run_cleared = false;
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(60000));
        health();
        if (!run_cleared && ++run_min * 60000u >= BC_BOOT_RUN_CLEAR_MS) {
            run_cleared = true; bc_boot_long_stable(R); plat_crash_run_clear();
            ESP_LOGI(TAG, "running %d min without a crash: crash-loop counters cleared", run_min);
        }
    }
}
