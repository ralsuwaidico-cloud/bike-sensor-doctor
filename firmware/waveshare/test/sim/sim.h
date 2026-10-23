#pragma once
#include <stdbool.h>
#include <stdint.h>
#include "plat.h"

typedef struct {
    uint32_t now_ms;
    bool power_ok, cad_ok, hr_ok; int watts, rpm, bpm;
    plat_link_info_t link[PLAT_SENS_KINDS];
    plat_found_t found[PLAT_SENS_KINDS][6]; int found_n[PLAT_SENS_KINDS];
    int battery_pct; bool usb; int backlight; bool wifi_on; uint32_t boots; bool restart_requested;
    int pair_calls, profile_saves, exports; bool verbose; char last_log[160];
} sim_hw_t;

extern sim_hw_t g_sim;
void sim_fs_root(const char *dir);
