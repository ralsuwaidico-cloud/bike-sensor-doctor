/*
 * bc_core — BOOT MODES: crash streak, RECOVERY MODE and the STAGED BOOT (firmware 0.7.3). Pure C, host-tested.
 *
 * State that must survive a crash lives in RTC memory that is not initialised at start (bc_boot_rtc_t, RTC_NOINIT on the
 * device): it survives panics, watchdog and software resets, not a power loss (then it is re-initialised: magic + CRC).
 *
 *   NORMAL     everything starts at once. A subsystem marker is still written before each one (the crash report shows
 *              which subsystem was starting). 3 crash resets in a row, each within 20 s of the previous start
 *              (bc_boot_stable clears the streak) -> RECOVERY.
 *   RECOVERY   only display + touch + NVS + storage start (no Bluetooth, no Wi-Fi, no sensors): the recovery screen.
 *              RESTART & DIAGNOSE -> bc_boot_request_staged + software restart. SEND LOGS starts only the phone link.
 *              Pressing RESET (a non-crash reset) tries a NORMAL start again.
 *   STAGED     subsystems start one at a time in this order: display, storage, phone link, Wi-Fi, sensor central, power
 *              meter, HR strap, speed/cadence sensor; the marker is written before each and each gets time to run. A crash
 *              whose marker names a subsystem disables that subsystem on the next boot ("Power meter disabled after a crash
 *              - RETRY") instead of looping; the caller also stores the skip in NVS so it survives a power cycle until the
 *              rider taps RETRY or a different firmware is installed. Three crashed staged boots -> RECOVERY.
 * Display and storage cannot be skipped (without them there is no recovery screen); a crash there counts as a failure.
 * Nothing here erases rides, the profile, bonds or logs.
 */
#pragma once
#include <stdbool.h>
#include <stdint.h>
#include "bc_diag.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef enum { BC_SS_NONE = 0, BC_SS_DISPLAY = 1, BC_SS_STORAGE = 2, BC_SS_PHONE = 3, BC_SS_WIFI = 4, BC_SS_CENTRAL = 5,
               BC_SS_POWER = 6, BC_SS_HR = 7, BC_SS_CSC = 8, BC_SS_RUNNING = 14, BC_SS_STABLE = 15 } bc_subsys_t;
#define BC_SS_BIT(s) ((uint16_t)(1u << (s)))
#define BC_SS_SKIPPABLE (BC_SS_BIT(BC_SS_PHONE) | BC_SS_BIT(BC_SS_WIFI) | BC_SS_BIT(BC_SS_CENTRAL) | BC_SS_BIT(BC_SS_POWER) | BC_SS_BIT(BC_SS_HR) | BC_SS_BIT(BC_SS_CSC))
typedef enum { BC_BOOT_NORMAL = 0, BC_BOOT_STAGED = 1, BC_BOOT_RECOVERY = 2 } bc_boot_mode_t;
#define BC_BOOT_CRASHES_FOR_RECOVERY 3
#define BC_BOOT_STAGED_FAILS_FOR_RECOVERY 3
#define BC_BOOT_STABLE_MS 20000u

typedef struct {
    uint32_t magic;
    uint32_t crash_streak;     /* crash resets in a row (cleared after 20 s stable) */
    uint8_t mode;              /* bc_boot_mode_t of the current boot */
    uint8_t marker;            /* bc_subsys_t being started (or RUNNING / STABLE) */
    uint16_t skip;             /* subsystems disabled after a crash (this power cycle; the caller mirrors it in NVS) */
    uint8_t staged_fails;      /* crashed staged boots in a row */
    uint8_t last_failed;       /* bc_subsys_t of the last crash with a subsystem marker */
    uint8_t request;           /* 1 = the rider asked for a staged boot (applied on the next start) */
    uint8_t crashed_last;      /* this boot follows a crash */
    uint32_t boots;            /* starts since the RTC state was created */
    uint32_t crc;
} bc_boot_rtc_t;

typedef struct {
    bc_boot_mode_t mode;
    uint16_t skip;             /* subsystems NOT to start this boot */
    bool crashed;              /* the previous run ended in a crash (report due) */
    uint8_t suspect;           /* bc_subsys_t that was starting when it crashed (NONE if unknown) */
    bool newly_skipped;        /* suspect was added to skip on this boot */
    bool rtc_was_valid;
} bc_boot_plan_t;

bool bc_boot_rtc_valid(const bc_boot_rtc_t *r);
/** Decide this boot. reset = bc_reset_t of esp_reset_reason(); nvs_skip = subsystems disabled in NVS for this firmware. */
void bc_boot_plan(bc_boot_rtc_t *r, bc_reset_t reset, uint16_t nvs_skip, bc_boot_plan_t *out);
/** Before starting a subsystem (and RUNNING when all are up). */
void bc_boot_mark(bc_boot_rtc_t *r, bc_subsys_t s);
/** 20 s after the last subsystem came up: crash streak cleared; a staged boot is complete (mode NORMAL next time). */
void bc_boot_stable(bc_boot_rtc_t *r);
/** RESTART & DIAGNOSE: the next start is a staged boot. */
void bc_boot_request_staged(bc_boot_rtc_t *r);
/** RETRY for a disabled subsystem: removed from skip (the caller clears NVS too). */
void bc_boot_unskip(bc_boot_rtc_t *r, bc_subsys_t s);
const char *bc_subsys_name(bc_subsys_t s);     /* "power meter", "phone link", ... */
const char *bc_boot_mode_name(bc_boot_mode_t m);

#ifdef __cplusplus
}
#endif
