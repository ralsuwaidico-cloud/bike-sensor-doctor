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
    /* simulated Wi-Fi world */
    struct { char ssid[33]; int rssi; bool secured; char pass[65]; bool present; } ap[6]; int n_ap;
    bool wifi_no_dhcp, wifi_no_answer; int wifi_auto_attempts, wifi_ui_ticks;
    /* simulated phone: the harness plays the phone (what the iPhone app will send) */
    struct { bool enabled, connected, bonded, pairing; uint32_t passkey; int rssi; plat_phone_in_t in;
             bc_ctrl_req_t ctrl; bool ctrl_pending; bc_ctrl_resp_t last_resp; int resps; bc_live_t last_live; int lives; int forgets; } phone;
} sim_hw_t;

extern sim_hw_t g_sim;
void sim_fs_root(const char *dir);
/* phone simulation helpers */
void sim_phone_connect(bool already_bonded);   /* connects; if not bonded, the device shows a passkey */
void sim_phone_enter_passkey(void);            /* the rider typed the code on the phone → encrypted + bonded */
void sim_phone_disconnect(void);
void sim_phone_send_gps(int32_t lat_e7, int32_t lon_e7, uint16_t speed_cms, uint16_t hacc_dm);
void sim_phone_send_hr(uint8_t bpm, uint8_t src);
void sim_phone_send_time(uint64_t epoch_ms);
void sim_phone_ctrl(uint8_t cmd, uint16_t ride_id);
