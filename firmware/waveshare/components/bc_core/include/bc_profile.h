/*
 * bc_core — rider profile (the on-device onboarding answers) and the FTP rules.
 *
 * Stored as plain "key=value" lines so future phone apps can read and write the same structure (shared profile format,
 * see docs/DEVICE_ARCHITECTURE.md). Unknown keys are ignored, missing keys take defaults, so old profiles never break.
 *
 * FTP honesty rules (carried over from the Android app):
 *  - the onboarding FTP is a STARTING ASSUMPTION = weight × W/kg for the experience level → always shown PROVISIONAL;
 *  - it is replaced automatically only by evidence from a REAL ride (a qualifying sustained 20-min effort, see bc_ride);
 *  - a value the rider types in from a real test elsewhere is "entered" and is never silently overwritten;
 *  - demo (simulated) rides never change the FTP.
 */
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum { BC_EXP_BEGINNER = 0, BC_EXP_NOVICE, BC_EXP_INTERMEDIATE, BC_EXP_ADVANCED, BC_EXP_COMPETITIVE, BC_EXP_COUNT } bc_exp_t;
typedef enum { BC_GOAL_ENDURANCE = 0, BC_GOAL_FTP, BC_GOAL_CLIMB, BC_GOAL_FITNESS, BC_GOAL_WEIGHT, BC_GOAL_EVENT, BC_GOAL_COUNT } bc_goal_t;
typedef enum { BC_FTP_NONE = 0, BC_FTP_ASSUMED, BC_FTP_AUTO, BC_FTP_ENTERED } bc_ftp_how_t;
typedef enum { BC_STYLE_FOCUS = 0, BC_STYLE_SPLIT, BC_STYLE_COACH, BC_STYLE_COUNT } bc_ride_style_t;

typedef struct {
    uint8_t mac[6];
    uint8_t addr_type;
    bool paired;
    char name[20];
} bc_sensor_pair_t;

typedef struct {
    bool onboarded;
    char name[17];             /* up to 16 characters */
    uint8_t age;               /* years; 0 = not set */
    uint16_t weight_dg;        /* kg × 10 (0.5 kg steps); 0 = not set */
    uint16_t height_cm;        /* optional (Settings only); 0 = not set */
    uint8_t exp;               /* bc_exp_t */
    uint8_t goal;              /* bc_goal_t */
    uint16_t ftp_w;
    uint8_t ftp_how;           /* bc_ftp_how_t */
    uint16_t ftp_from_ride;    /* ride id that produced an automatic FTP (0 = none) */
    uint8_t max_hr;            /* optional, bpm; 0 = estimate from age */
    bc_sensor_pair_t power, hr;
    bc_sensor_pair_t csc;      /* 0.6.0: optional speed/cadence sensor (BLE CSC 0x1816) */
    uint16_t wheel_mm;         /* wheel circumference for a wheel-speed sensor; default 2096 (700x25c) */
    uint8_t chg_notice;        /* 0.6.0: battery-notice events to the phone (docs/CHARGE_ALERTS.md). Default 0 = OFF, no UI toggle while HW-1 is open */
    bool wifi_on;
    bool phone_on;             /* phone link advertising (default on; pairing still needs the code on screen) */
    uint8_t hr_pref;           /* 0 = strap first, phone/watch as backup; 1 = phone/watch first */
    uint8_t ride_style;        /* bc_ride_style_t */
    uint8_t brightness;        /* 5..100 % */
    /* power (firmware 0.5.0); missing keys in an old profile take these defaults */
    uint16_t scr_timeout_s;    /* auto screen-off outside rides: 0 = never, default 60 */
    uint8_t auto_sleep_min;    /* deep sleep after N idle minutes on battery, no ride, no phone connected: 0 = off (default since 0.6.0) */
    uint8_t bat_protect;       /* 0 = alerts only (default); 1 = at the critical level also auto-save the ride and sleep (NOT validated) */
    bool wake_on_cue;          /* screen off during a ride: wake 5 s on a coach warning (default on) */
    uint8_t wake_taps;         /* wake gesture: 1 = any touch (default since 0.6.0 rev 3; the waking gesture never reaches a button), 2 = double tap, 3 = triple tap */
    /* 0.6.0 shared athlete profile (phone sync, docs/LINK_V1_2_SPEC.md); 0 = unknown */
    uint16_t birth_year; uint8_t rest_hr, lthr, units /* 0 metric, 1 imperial */, hours_wk;
    uint32_t phone_prof_ver;   /* version of the last PROFILE_SET applied; 0 = device-only profile */
    uint32_t phone_prof_epoch; /* updated_epoch_s the phone sent with it */
    uint8_t prof_src;          /* 0 device-only, 1 phone-synced */
    uint32_t sett_ver;         /* version of the last SETTINGS_SET applied */
    uint8_t pwr_v;             /* power-settings schema: 0 = written by 0.5.0 (auto_sleep_min reset once), 2 = 0.6.0 */
    uint16_t next_ride_id;     /* real rides only; demo rides are numbered separately */
    uint16_t next_demo_id;
    char ftp_note[96];         /* last FTP change in plain words */
} bc_profile_t;

void bc_profile_defaults(bc_profile_t *p);
/** Writes the profile as key=value lines. Returns bytes written (excluding NUL) or 0 if the buffer is too small. */
size_t bc_profile_to_text(const bc_profile_t *p, char *out, size_t cap);
/** Parses key=value lines on top of defaults. Returns false only for NULL input. */
bool bc_profile_from_text(bc_profile_t *p, const char *txt);

const char *bc_exp_name(int e);
const char *bc_exp_hint(int e);
const char *bc_goal_name(int g);
const char *bc_goal_hint(int g);
/** W/kg for the experience level (Android StartingFtp: 1.75 / 2.25 / 3.0 / 4.0 / 5.0). */
int bc_exp_wkg_x100(int e);

/** Starting assumption = weight × W/kg (rounded), 0 when weight is unset or out of 30..200 kg. */
int bc_starting_ftp(int weight_dg, int exp);
/** Re-applies the starting assumption when the FTP is NONE or still ASSUMED (e.g. weight/experience edited). */
void bc_profile_refresh_assumption(bc_profile_t *p);
/** True when the FTP is backed by evidence (automatic from a real ride, or entered from a real test). */
bool bc_ftp_established(const bc_profile_t *p);
/** "PROVISIONAL", "FROM RIDES", "ENTERED", "NOT SET". */
const char *bc_ftp_label(const bc_profile_t *p);
/** Max HR used for HR guidance: the rider's value or the Tanaka estimate 208 − 0.7 × age (185 if age unknown). */
int bc_profile_max_hr(const bc_profile_t *p);
/** Name for display ("Rider" when empty). */
const char *bc_profile_display_name(const bc_profile_t *p);

#ifdef __cplusplus
}
#endif
