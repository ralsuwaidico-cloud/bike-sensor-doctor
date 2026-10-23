/* PC implementation of plat.h for the preview/test harness. Sensor values here are the harness's scripted stand-in for
 * the Bluetooth hardware (set by the scenario), so screens can be tested in every state. Files live in SIM_FS. */
#include "plat.h"
#include "sim.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

sim_hw_t g_sim;
static char s_root[256] = "simfs";

void sim_fs_root(const char *dir) { snprintf(s_root, sizeof s_root, "%s", dir); mkdir(s_root, 0755); }

static void full(const char *rel, char *out, size_t cap)
{
    snprintf(out, cap, "%s/%s", s_root, rel);
    char dir[512]; snprintf(dir, sizeof dir, "%s", out);
    char *sl = strrchr(dir, '/'); if (sl) { *sl = 0; mkdir(dir, 0755); }
}

uint32_t plat_ms(void) { return g_sim.now_ms; }

void plat_sensors(plat_sensors_t *o)
{
    memset(o, 0, sizeof *o);
    o->power_ok = g_sim.power_ok; o->watts = g_sim.watts; o->cad_ok = g_sim.cad_ok; o->rpm = g_sim.rpm;
    o->hr_ok = g_sim.hr_ok; o->bpm = g_sim.bpm;
    for (int k = 0; k < PLAT_SENS_KINDS; k++) { o->link[k] = g_sim.link[k]; }
    o->link[PLAT_SENS_SPEED].link = PLAT_LINK_UNSUPPORTED;
}

static plat_sens_kind_t s_scan_kind; static bool s_scanning; static uint32_t s_scan_t0;
void plat_scan_begin(plat_sens_kind_t k) { s_scan_kind = k; s_scanning = true; s_scan_t0 = g_sim.now_ms; }
void plat_scan_end(void) { s_scanning = false; }
int plat_scan_results(plat_found_t *out, int max)
{
    if (!s_scanning || g_sim.now_ms - s_scan_t0 < 1500) return 0;
    int n = 0;
    for (int i = 0; i < g_sim.found_n[s_scan_kind] && n < max; i++) out[n++] = g_sim.found[s_scan_kind][i];
    return n;
}
void plat_pair(plat_sens_kind_t k, const plat_found_t *d)
{
    g_sim.link[k].link = d ? PLAT_LINK_CONNECTED : PLAT_LINK_NOT_PAIRED;
    if (d) snprintf(g_sim.link[k].name, sizeof g_sim.link[k].name, "%s", d->name);
    g_sim.pair_calls++;
}

bool plat_profile_load(char *buf, size_t cap) { long n = plat_file_read("profile.txt", buf, cap - 1); if (n <= 0) return false; buf[n] = 0; return true; }
bool plat_profile_save(const char *txt) { g_sim.profile_saves++; return plat_file_write("profile.txt", txt, strlen(txt)); }

bool plat_file_append(const char *path, const char *data, size_t len, bool sync)
{
    (void)sync; char p[512]; full(path, p, sizeof p);
    FILE *f = fopen(p, "ab"); if (!f) return false;
    size_t w = fwrite(data, 1, len, f); fclose(f); return w == len;
}
bool plat_file_write(const char *path, const char *data, size_t len)
{
    char p[512], t[520]; full(path, p, sizeof p); snprintf(t, sizeof t, "%s.tmp", p);
    FILE *f = fopen(t, "wb"); if (!f) return false;
    size_t w = fwrite(data, 1, len, f); fclose(f);
    return w == len && rename(t, p) == 0;
}
long plat_file_read(const char *path, char *buf, size_t cap) { return plat_file_read_at(path, 0, buf, cap); }
long plat_file_read_at(const char *path, long off, char *buf, size_t cap)
{
    char p[512]; full(path, p, sizeof p);
    FILE *f = fopen(p, "rb"); if (!f) return -1;
    fseek(f, off, SEEK_SET); long n = (long)fread(buf, 1, cap, f); fclose(f); return n;
}
bool plat_file_rename(const char *from, const char *to)
{
    char a[512], b[512]; full(from, a, sizeof a); full(to, b, sizeof b); return rename(a, b) == 0;
}
bool plat_file_remove(const char *path) { char p[512]; full(path, p, sizeof p); return unlink(p) == 0; }
bool plat_storage_ok(void) { return true; }

int plat_battery_pct(void) { return g_sim.battery_pct; }
int plat_battery_mv(void) { return 3600 + g_sim.battery_pct * 6; }
bool plat_usb_power(void) { return g_sim.usb; }
void plat_backlight(int pct) { g_sim.backlight = pct; }
void plat_wifi_enable(bool on) { g_sim.wifi_on = on; }
int plat_wifi_scan_count(void) { return g_sim.wifi_on ? 4 : -1; }
const char *plat_fw_version(void) { return "0.2.0-sim"; }
const char *plat_reset_reason(void) { return "power-on"; }
uint32_t plat_boot_count(void) { return g_sim.boots; }
void plat_restart(void) { g_sim.restart_requested = true; }
void plat_selftest_text(char *b, size_t cap)
{
    snprintf(b, cap, "Display  #56E08C PASS#\nTouch    #56E08C PASS#\nPSRAM    #56E08C PASS#\nFlash    #56E08C PASS#\nNVS      #56E08C PASS#\n"
                     "Storage  #56E08C PASS#\nIMU      #56E08C PASS#\nBattery  #56E08C PASS# 4.11V\nWi-Fi    #FFB64D INFO# off\nBLE      #56E08C PASS#");
}
void plat_mem_text(char *b, size_t cap) { snprintf(b, cap, "heap 180K min 150K psram 1900K"); }
void plat_log(const char *line) { if (g_sim.verbose) printf("  [log] %s\n", line); snprintf(g_sim.last_log, sizeof g_sim.last_log, "%s", line); }
