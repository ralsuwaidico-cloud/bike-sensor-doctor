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
    /* power (0.5.0): scripted cell voltage (0 = derive from battery_pct), panel/backlight state, deep-sleep bookkeeping */
    int battery_mv; bool panel_asleep; bool asleep; int deep_sleeps; bool woke_from_sleep;
    int pair_calls, profile_saves, exports; bool verbose; char last_log[160];
    /* simulated Wi-Fi world */
    struct { char ssid[33]; int rssi; bool secured; char pass[65]; bool present; bool ghz5_only; uint8_t channel; } ap[6]; int n_ap;
    bool wifi_no_dhcp, wifi_no_answer, wifi_no_internet; int wifi_auto_attempts, wifi_ui_ticks;
    bool touch_fast_poll; int touch_screen_offs; int sleep_wake_taps; bool sensor_standby; int sensor_standbys;
    /* simulated phone: the harness plays the phone (what the iPhone app will send) */
    struct { bool enabled, connected, bonded, pairing; uint32_t passkey; int rssi; plat_phone_in_t in;
             bc_ctrl_req_t ctrl; bool ctrl_pending; bc_ctrl_resp_t last_resp; int resps; bc_live_t last_live; int lives; int forgets;
             /* 0.6.0 phone services: what the board notified */
             int notifies, unknown_notifies; bc_wifi_scan_result_t scan[32]; int n_scan; bc_wifi_scan_end_t scan_end; int scan_ends;
             bc_wifi_status_msg_t wifi_status; int statuses; bc_ride_summary_t rides[64]; int n_rides; bc_sync_end_t sync_end; int sync_ends;
             bc_profile_msg_t profile; int profiles; bc_profile_ack_t profile_ack; int profile_acks; bc_settings_msg_t settings; int settings_msgs;
             struct { uint8_t chr; size_t len; uint8_t b[BC_LINK_MAX]; } svc_in[8]; int svc_in_n; bool notify_full; uint8_t last_notify_chr;
             bool standby; int standbys; } phone;
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
bool sim_phone_write(int chr, const uint8_t *msg, size_t n);   /* chr 0 = Control, 1 = Sync; returns the board's accept/reject */
