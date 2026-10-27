/* bc_core — PORTABLE CORE. See bc_boot.h. */
#include "bc_boot.h"
#include <stddef.h>
#include <string.h>

#define BOOT_MAGIC 0xB0075EC3u

static uint32_t crc_of(const bc_boot_rtc_t *r) { return bc_crc32(0, r, offsetof(bc_boot_rtc_t, crc)); }
static void seal(bc_boot_rtc_t *r) { r->crc = crc_of(r); }
bool bc_boot_rtc_valid(const bc_boot_rtc_t *r) { return r->magic == BOOT_MAGIC && r->crc == crc_of(r) && r->mode <= BC_BOOT_RECOVERY; }

static bool is_crash(bc_reset_t t) { return t == BC_RST_PANIC || t == BC_RST_WDT || t == BC_RST_BROWNOUT; }
static bool subsys_known(uint8_t m) { return m >= BC_SS_DISPLAY && m <= BC_SS_BTSTACK; }

void bc_boot_plan(bc_boot_rtc_t *r, bc_reset_t reset, uint16_t nvs_skip, bc_boot_plan_t *o)
{
    memset(o, 0, sizeof *o);
    o->rtc_was_valid = bc_boot_rtc_valid(r);
    if (!o->rtc_was_valid) { memset(r, 0, sizeof *r); r->magic = BOOT_MAGIC; r->mode = BC_BOOT_NORMAL; }
    r->boots++;
    bc_boot_mode_t prev = (bc_boot_mode_t)r->mode;
    uint8_t marker = r->marker;
    o->crashed = is_crash(reset) && o->rtc_was_valid;
    if (is_crash(reset) && !o->rtc_was_valid) o->crashed = true;   /* crash after a power loss of RTC: still a crash (no marker) */
    r->crashed_last = o->crashed;
    if (o->crashed) {
        r->crash_streak++;
        o->suspect = (o->rtc_was_valid && subsys_known(marker)) ? marker : BC_SS_NONE;
        /* 0.7.4: last_failed = the subsystem of the PREVIOUS crash in this streak (NONE when that crash had no marker), so
           "the same subsystem crashed twice in a row" is exact */
        bool same_again = o->suspect && r->crash_streak >= BC_BOOT_SAME_SUSPECT_TO_SKIP && r->last_failed == o->suspect;
        r->last_failed = o->suspect;
        if (prev == BC_BOOT_STAGED) {
            r->staged_fails++;
            if (o->suspect && (BC_SS_BIT(o->suspect) & BC_SS_SKIPPABLE) && !(r->skip & BC_SS_BIT(o->suspect))) { r->skip |= BC_SS_BIT(o->suspect); o->newly_skipped = true; }
            r->mode = r->staged_fails >= BC_BOOT_STAGED_FAILS_FOR_RECOVERY ? BC_BOOT_RECOVERY : BC_BOOT_STAGED;
        } else if (prev == BC_BOOT_RECOVERY) {
            r->mode = BC_BOOT_RECOVERY;                       /* the minimal mode itself crashed: stay minimal */
        } else {
            /* 0.7.4: a NORMAL boot disables a subsystem that crashed twice in a row while starting (0.7.3 looped into RECOVERY
               with "disabled 0x000"). The boot that has just disabled it gets its chance even at the 3rd crash in a row. */
            bool newly = false;
            if (same_again && (BC_SS_BIT(o->suspect) & BC_SS_SKIPPABLE) && !(r->skip & BC_SS_BIT(o->suspect))) { r->skip |= BC_SS_BIT(o->suspect); o->newly_skipped = newly = true; }
            r->mode = r->crash_streak >= BC_BOOT_CRASHES_FOR_RECOVERY && !newly ? BC_BOOT_RECOVERY : BC_BOOT_NORMAL;
        }
    } else {
        r->crash_streak = 0;
        if (r->request == 1) { r->mode = BC_BOOT_STAGED; r->staged_fails = 0; r->skip = 0; }
        else r->mode = BC_BOOT_NORMAL;                        /* RESET pressed / power cycle / software restart: normal start */
        r->request = 0;
    }
    r->marker = BC_SS_NONE;
    o->mode = (bc_boot_mode_t)r->mode;
    o->skip = (uint16_t)((r->skip | nvs_skip) & BC_SS_SKIPPABLE);
    seal(r);
}

void bc_boot_mark(bc_boot_rtc_t *r, bc_subsys_t s) { r->marker = (uint8_t)s; seal(r); }

void bc_boot_stable(bc_boot_rtc_t *r)
{
    r->crash_streak = 0; r->marker = BC_SS_STABLE;
    if (r->mode == BC_BOOT_STAGED) { r->mode = BC_BOOT_NORMAL; r->staged_fails = 0; }   /* skip stays for this power cycle */
    seal(r);
}

void bc_boot_request_staged(bc_boot_rtc_t *r) { r->request = 1; seal(r); }
void bc_boot_unskip(bc_boot_rtc_t *r, bc_subsys_t s) { r->skip &= (uint16_t)~BC_SS_BIT(s); seal(r); }

const char *bc_subsys_name(bc_subsys_t s)
{
    switch (s) {
    case BC_SS_DISPLAY: return "display"; case BC_SS_STORAGE: return "storage"; case BC_SS_PHONE: return "phone link";
    case BC_SS_WIFI: return "Wi-Fi"; case BC_SS_CENTRAL: return "sensor Bluetooth"; case BC_SS_POWER: return "power meter";
    case BC_SS_HR: return "HR strap"; case BC_SS_CSC: return "speed/cadence sensor"; case BC_SS_BTSTACK: return "Bluetooth stack";
    case BC_SS_RUNNING: return "running";
    case BC_SS_STABLE: return "stable"; default: return "none";
    }
}
const char *bc_boot_mode_name(bc_boot_mode_t m) { return m == BC_BOOT_STAGED ? "staged" : m == BC_BOOT_RECOVERY ? "recovery" : "normal"; }
