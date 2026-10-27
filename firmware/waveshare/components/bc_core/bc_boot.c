/* bc_core — PORTABLE CORE. See bc_boot.h. */
#include "bc_boot.h"
#include <stddef.h>
#include <string.h>

#define BOOT_MAGIC 0xB0075EC3u

static uint32_t crc_of(const bc_boot_rtc_t *r) { return bc_crc32(0, r, offsetof(bc_boot_rtc_t, crc)); }
static void seal(bc_boot_rtc_t *r) { r->crc = crc_of(r); }
bool bc_boot_rtc_valid(const bc_boot_rtc_t *r) { return r->magic == BOOT_MAGIC && r->crc == crc_of(r) && r->mode <= BC_BOOT_RECOVERY; }

/* rc3 (QA QF-26): a brownout is a power dip, not a firmware fault: counted on its own (power warning), never toward RECOVERY */
static bool is_crash(bc_reset_t t) { return t == BC_RST_PANIC || t == BC_RST_WDT; }
static bool subsys_known(uint8_t m) { return m >= BC_SS_DISPLAY && m <= BC_SS_RECMIN; }
uint8_t bc_boot_next_run(uint8_t prev, bc_reset_t reset)
{
    if (is_crash(reset)) return prev < 250 ? (uint8_t)(prev + 1) : prev;
    if (reset == BC_RST_BROWNOUT) return prev;
    return 0;                                                  /* power-on, software restart, deep-sleep wake (rc4, RC3-05) */
}

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
    r->run_streak = bc_boot_next_run(o->rtc_was_valid ? r->run_streak : 0, reset);
    o->run_streak = r->run_streak;
    if (reset == BC_RST_BROWNOUT) {
        /* a power dip: no crash streak, no RECOVERY; the same subsystem starting at two brownouts in a row (e.g. the radio's
           current peak on a weak battery) is disabled like a crash would be, so it cannot loop either */
        o->brownout = true; r->brown_streak = (uint8_t)(r->brown_streak < 250 ? r->brown_streak + 1 : r->brown_streak);
        uint8_t sus = (o->rtc_was_valid && subsys_known(marker)) ? marker : BC_SS_NONE;
        if (sus && r->brown_streak >= 2 && r->last_brown == sus && (BC_SS_BIT(sus) & BC_SS_SKIPPABLE) && !(r->skip & BC_SS_BIT(sus))) { r->skip |= BC_SS_BIT(sus); o->newly_skipped = true; o->suspect = sus; }
        r->last_brown = sus;
        if (prev != BC_BOOT_RECOVERY && prev != BC_BOOT_STAGED) r->mode = BC_BOOT_NORMAL;
    } else r->brown_streak = 0;
    o->brown_streak = r->brown_streak;
    if (o->brownout) { /* handled above */ }
    else if (o->crashed) {
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
    if (o->mode == BC_BOOT_RECOVERY && o->crashed) { o->no_storage = o->suspect == BC_SS_STORAGE; o->no_diag = o->suspect == BC_SS_DIAG || o->no_storage; }
    /* rc3 (QA QF-25): the recovery screen crashed -> a static text next time (the boot record and crash report still run,
       attributed to "recovery screen"); the static text crashed too -> nothing at all (halt) */
    if (o->crashed && o->suspect == BC_SS_RECUI) { r->mode = BC_BOOT_RECOVERY; o->mode = BC_BOOT_RECOVERY; o->minimal = true; }
    if (o->crashed && o->suspect == BC_SS_RECMIN) { r->mode = BC_BOOT_RECOVERY; o->mode = BC_BOOT_RECOVERY; o->minimal = true; o->halt = true; }
    o->skip = (uint16_t)((r->skip | nvs_skip) & BC_SS_SKIPPABLE);
    seal(r);
}

void bc_boot_mark(bc_boot_rtc_t *r, bc_subsys_t s) { r->marker = (uint8_t)s; seal(r); }
void bc_boot_long_stable(bc_boot_rtc_t *r) { r->run_streak = 0; seal(r); }

void bc_boot_limit(bc_boot_rtc_t *r, bc_boot_plan_t *p, uint8_t nvs_run)
{
    uint8_t run = r->run_streak > nvs_run ? r->run_streak : nvs_run;
    if (run < BC_BOOT_LIMIT_RUN) return;
    if (p->mode != BC_BOOT_RECOVERY) { r->mode = BC_BOOT_RECOVERY; p->mode = BC_BOOT_RECOVERY; p->limited = true; }
    /* RTC memory intact: the plan already sheds the stage the last crash happened in (and nothing after a crash past the
       start-up). RTC lost: the crash site is unknown - shed stages step by step. */
    if (p->rtc_was_valid) { seal(r); return; }
    p->no_storage = true;
    if (run >= BC_BOOT_LIMIT_RUN + 2) p->no_diag = true;
    if (run >= BC_BOOT_LIMIT_RUN + 4) p->minimal = true;
    seal(r);
}

void bc_boot_stable(bc_boot_rtc_t *r)
{
    r->crash_streak = 0; r->marker = BC_SS_STABLE;
    if (r->mode == BC_BOOT_STAGED) { r->mode = BC_BOOT_NORMAL; r->staged_fails = 0; }   /* skip stays for this power cycle */
    seal(r);
}

void bc_boot_request_staged(bc_boot_rtc_t *r) { r->request = 1; seal(r); }
void bc_boot_disable(bc_boot_rtc_t *r, bc_subsys_t s) { if (BC_SS_BIT(s) & BC_SS_SKIPPABLE) { r->skip |= BC_SS_BIT(s); seal(r); } }
void bc_boot_force_recovery(bc_boot_rtc_t *r, bc_boot_plan_t *p) { r->mode = BC_BOOT_RECOVERY; seal(r); p->mode = BC_BOOT_RECOVERY; }
void bc_boot_unskip(bc_boot_rtc_t *r, bc_subsys_t s) { r->skip &= (uint16_t)~BC_SS_BIT(s); seal(r); }

const char *bc_subsys_name(bc_subsys_t s)
{
    switch (s) {
    case BC_SS_DISPLAY: return "display"; case BC_SS_STORAGE: return "storage"; case BC_SS_PHONE: return "phone link";
    case BC_SS_WIFI: return "Wi-Fi"; case BC_SS_CENTRAL: return "sensor Bluetooth"; case BC_SS_POWER: return "power meter";
    case BC_SS_HR: return "HR strap"; case BC_SS_CSC: return "speed/cadence sensor"; case BC_SS_BTSTACK: return "Bluetooth stack"; case BC_SS_DIAG: return "diagnostics";
    case BC_SS_RECUI: return "recovery screen"; case BC_SS_RECMIN: return "minimal recovery text";
    case BC_SS_RUNNING: return "running";
    case BC_SS_STABLE: return "stable"; default: return "none";
    }
}
const char *bc_boot_mode_name(bc_boot_mode_t m) { return m == BC_BOOT_STAGED ? "staged" : m == BC_BOOT_RECOVERY ? "recovery" : "normal"; }
