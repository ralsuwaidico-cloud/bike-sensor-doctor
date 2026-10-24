#include "bc_profile.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char *EXP_NAME[BC_EXP_COUNT] = { "Beginner", "Novice", "Intermediate", "Advanced", "Competitive" };
static const char *EXP_HINT[BC_EXP_COUNT] = { "new to cycling", "riding again", "rides regularly", "trains seriously", "races" };
static const int EXP_WKG[BC_EXP_COUNT] = { 175, 225, 300, 400, 500 };
static const char *GOAL_NAME[BC_GOAL_COUNT] = { "Endurance", "Raise FTP", "Climbing", "Fitness", "Body comp.", "Race / event" };
static const char *GOAL_HINT[BC_GOAL_COUNT] = { "ride longer, Zone 2", "more sustained power", "stronger uphill", "general health",
                                                "steady fat-burning", "prepare for a date" };

const char *bc_exp_name(int e) { return e >= 0 && e < BC_EXP_COUNT ? EXP_NAME[e] : "?"; }
const char *bc_exp_hint(int e) { return e >= 0 && e < BC_EXP_COUNT ? EXP_HINT[e] : ""; }
const char *bc_goal_name(int g) { return g >= 0 && g < BC_GOAL_COUNT ? GOAL_NAME[g] : "?"; }
const char *bc_goal_hint(int g) { return g >= 0 && g < BC_GOAL_COUNT ? GOAL_HINT[g] : ""; }
int bc_exp_wkg_x100(int e) { return e >= 0 && e < BC_EXP_COUNT ? EXP_WKG[e] : 0; }

void bc_profile_defaults(bc_profile_t *p)
{
    memset(p, 0, sizeof *p);
    p->age = 35; p->weight_dg = 750; p->exp = BC_EXP_INTERMEDIATE; p->goal = BC_GOAL_ENDURANCE;
    p->brightness = 80; p->ride_style = BC_STYLE_FOCUS; p->next_ride_id = 1; p->next_demo_id = 1; p->phone_on = true;
    p->scr_timeout_s = 60; p->auto_sleep_min = 10; p->bat_protect = 0; p->wake_on_cue = true;
}

int bc_starting_ftp(int weight_dg, int exp)
{
    if (weight_dg < 300 || weight_dg > 2000) return 0;
    int k = bc_exp_wkg_x100(exp); if (!k) return 0;
    return (weight_dg * k + 500) / 1000;   /* (kg×10)(W/kg×100)/1000 = W, rounded */
}

void bc_profile_refresh_assumption(bc_profile_t *p)
{
    if (p->ftp_how != BC_FTP_NONE && p->ftp_how != BC_FTP_ASSUMED) return;
    int v = bc_starting_ftp(p->weight_dg, p->exp);
    if (v <= 0) return;
    if (p->ftp_how == BC_FTP_ASSUMED && p->ftp_w == v) return;
    p->ftp_w = (uint16_t)v; p->ftp_how = BC_FTP_ASSUMED;
    snprintf(p->ftp_note, sizeof p->ftp_note, "Starting assumption: %d.%d kg x %d.%02d W/kg (%s).", p->weight_dg / 10, p->weight_dg % 10,
             bc_exp_wkg_x100(p->exp) / 100, bc_exp_wkg_x100(p->exp) % 100, bc_exp_name(p->exp));
}

bool bc_ftp_established(const bc_profile_t *p) { return p->ftp_w > 0 && (p->ftp_how == BC_FTP_AUTO || p->ftp_how == BC_FTP_ENTERED); }

const char *bc_ftp_label(const bc_profile_t *p)
{
    switch (p->ftp_how) { case BC_FTP_ASSUMED: return "PROVISIONAL"; case BC_FTP_AUTO: return "FROM RIDES"; case BC_FTP_ENTERED: return "ENTERED"; }
    return "NOT SET";
}

int bc_profile_max_hr(const bc_profile_t *p)
{
    if (p->max_hr >= 100) return p->max_hr;
    if (p->age >= 10 && p->age <= 100) return (2080 - 7 * p->age + 5) / 10;
    return 185;
}

const char *bc_profile_display_name(const bc_profile_t *p) { return p->name[0] ? p->name : "Rider"; }

/* ---- text format */
static void hex6(char *o, const uint8_t *m) { snprintf(o, 13, "%02x%02x%02x%02x%02x%02x", m[0], m[1], m[2], m[3], m[4], m[5]); }
static bool unhex6(const char *s, uint8_t *m)
{
    if (strlen(s) < 12) return false;
    for (int i = 0; i < 6; i++) { char b[3] = { s[2 * i], s[2 * i + 1], 0 }; char *e; long v = strtol(b, &e, 16); if (*e) return false; m[i] = (uint8_t)v; }
    return true;
}

size_t bc_profile_to_text(const bc_profile_t *p, char *out, size_t cap)
{
    char pm[13], hm[13]; hex6(pm, p->power.mac); hex6(hm, p->hr.mac);
    int n = snprintf(out, cap,
        "format=bc-profile-1\nonboarded=%d\nname=%s\nage=%u\nweight_dg=%u\nheight_cm=%u\nexp=%u\ngoal=%u\nftp_w=%u\nftp_how=%u\n"
        "ftp_from_ride=%u\nmax_hr=%u\npower.paired=%d\npower.mac=%s\npower.type=%u\npower.name=%s\nhr.paired=%d\nhr.mac=%s\nhr.type=%u\n"
        "hr.name=%s\nwifi_on=%d\nphone_on=%d\nhr_pref=%u\nride_style=%u\nbrightness=%u\nscr_timeout_s=%u\nauto_sleep_min=%u\nbat_protect=%u\nwake_on_cue=%d\n"
        "next_ride_id=%u\nnext_demo_id=%u\nftp_note=%s\n",
        p->onboarded, p->name, p->age, p->weight_dg, p->height_cm, p->exp, p->goal, p->ftp_w, p->ftp_how, p->ftp_from_ride, p->max_hr,
        p->power.paired, pm, p->power.addr_type, p->power.name, p->hr.paired, hm, p->hr.addr_type, p->hr.name, p->wifi_on, p->phone_on, p->hr_pref, p->ride_style,
        p->brightness, p->scr_timeout_s, p->auto_sleep_min, p->bat_protect, p->wake_on_cue, p->next_ride_id, p->next_demo_id, p->ftp_note);
    if (n < 0 || (size_t)n >= cap) return 0;
    return (size_t)n;
}

static void cpy(char *dst, size_t cap, const char *v)
{
    size_t i = 0;
    for (; v[i] && v[i] != '\n' && v[i] != '\r' && i + 1 < cap; i++) dst[i] = v[i];
    dst[i] = 0;
}

static int clampi(long v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : (int)v; }

bool bc_profile_from_text(bc_profile_t *p, const char *txt)
{
    if (!txt) return false;
    bc_profile_defaults(p);
    const char *s = txt;
    while (*s) {
        const char *eol = strchr(s, '\n'); size_t len = eol ? (size_t)(eol - s) : strlen(s);
        char line[160]; if (len >= sizeof line) len = sizeof line - 1; memcpy(line, s, len); line[len] = 0;
        s = eol ? eol + 1 : s + len;
        char *eq = strchr(line, '='); if (!eq) continue;
        *eq = 0; const char *k = line, *v = eq + 1; long iv = strtol(v, NULL, 10);
        if (!strcmp(k, "onboarded")) p->onboarded = iv != 0;
        else if (!strcmp(k, "name")) cpy(p->name, sizeof p->name, v);
        else if (!strcmp(k, "age")) p->age = (uint8_t)clampi(iv, 0, 120);
        else if (!strcmp(k, "weight_dg")) p->weight_dg = (uint16_t)clampi(iv, 0, 3000);
        else if (!strcmp(k, "height_cm")) p->height_cm = (uint16_t)clampi(iv, 0, 250);
        else if (!strcmp(k, "exp")) p->exp = (uint8_t)clampi(iv, 0, BC_EXP_COUNT - 1);
        else if (!strcmp(k, "goal")) p->goal = (uint8_t)clampi(iv, 0, BC_GOAL_COUNT - 1);
        else if (!strcmp(k, "ftp_w")) p->ftp_w = (uint16_t)clampi(iv, 0, 2000);
        else if (!strcmp(k, "ftp_how")) p->ftp_how = (uint8_t)clampi(iv, 0, BC_FTP_ENTERED);
        else if (!strcmp(k, "ftp_from_ride")) p->ftp_from_ride = (uint16_t)clampi(iv, 0, 65535);
        else if (!strcmp(k, "max_hr")) p->max_hr = (uint8_t)clampi(iv, 0, 240);
        else if (!strcmp(k, "power.paired")) p->power.paired = iv != 0;
        else if (!strcmp(k, "power.mac")) { if (!unhex6(v, p->power.mac)) p->power.paired = false; }
        else if (!strcmp(k, "power.type")) p->power.addr_type = (uint8_t)clampi(iv, 0, 3);
        else if (!strcmp(k, "power.name")) cpy(p->power.name, sizeof p->power.name, v);
        else if (!strcmp(k, "hr.paired")) p->hr.paired = iv != 0;
        else if (!strcmp(k, "hr.mac")) { if (!unhex6(v, p->hr.mac)) p->hr.paired = false; }
        else if (!strcmp(k, "hr.type")) p->hr.addr_type = (uint8_t)clampi(iv, 0, 3);
        else if (!strcmp(k, "hr.name")) cpy(p->hr.name, sizeof p->hr.name, v);
        else if (!strcmp(k, "wifi_on")) p->wifi_on = iv != 0;
        else if (!strcmp(k, "phone_on")) p->phone_on = iv != 0;
        else if (!strcmp(k, "hr_pref")) p->hr_pref = iv ? 1 : 0;
        else if (!strcmp(k, "ride_style")) p->ride_style = (uint8_t)clampi(iv, 0, BC_STYLE_COUNT - 1);
        else if (!strcmp(k, "brightness")) p->brightness = (uint8_t)clampi(iv, 5, 100);
        else if (!strcmp(k, "scr_timeout_s")) p->scr_timeout_s = (uint16_t)clampi(iv, 0, 3600);
        else if (!strcmp(k, "auto_sleep_min")) p->auto_sleep_min = (uint8_t)clampi(iv, 0, 240);
        else if (!strcmp(k, "bat_protect")) p->bat_protect = iv ? 1 : 0;
        else if (!strcmp(k, "wake_on_cue")) p->wake_on_cue = iv != 0;
        else if (!strcmp(k, "next_ride_id")) p->next_ride_id = (uint16_t)clampi(iv, 1, 65535);
        else if (!strcmp(k, "next_demo_id")) p->next_demo_id = (uint16_t)clampi(iv, 1, 65535);
        else if (!strcmp(k, "ftp_note")) cpy(p->ftp_note, sizeof p->ftp_note, v);
    }
    if (p->ftp_w == 0) p->ftp_how = BC_FTP_NONE;
    return true;
}
