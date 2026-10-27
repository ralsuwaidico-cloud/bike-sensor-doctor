#pragma once
#include <stdbool.h>
#include <stdint.h>
#include "plat.h"
#include "bc_pipe.h"
#include "bc_xds.h"

typedef struct {
    uint32_t now_ms;
    bool power_ok, cad_ok, hr_ok; int watts, rpm, bpm;
    plat_link_info_t link[PLAT_SENS_KINDS];
    plat_found_t found[PLAT_SENS_KINDS][6]; int found_n[PLAT_SENS_KINDS];
    plat_found_t found_any[12]; int found_any_n;                 /* Connections > Other Bluetooth discovery list */
    /* 0.6.0 CSC sensor stand-in */
    bool csc_cad_ok, csc_speed_ok, csc_has_wheel, csc_has_crank; int csc_rpm, csc_speed_dmh; uint16_t wheel_mm;
    int battery_pct; bool usb; int backlight; bool wifi_on; uint32_t boots; bool restart_requested;
    /* power (0.5.0): scripted cell voltage (0 = derive from battery_pct), panel/backlight state, deep-sleep bookkeeping */
    int battery_mv; bool panel_asleep; bool asleep; int deep_sleeps; bool woke_from_sleep;
    int pair_calls, profile_saves, exports; bool verbose; char last_log[160];
    /* simulated Wi-Fi world */
    struct { char ssid[33]; int rssi; bool secured; char pass[65]; bool present; bool ghz5_only; uint8_t channel; } ap[6]; int n_ap;
    bool wifi_no_dhcp, wifi_no_answer, wifi_no_internet; int wifi_auto_attempts, wifi_ui_ticks;
    bool touch_fast_poll; int touch_screen_offs, touch_polls; bool touch_event_mode, touch_poll_request; int sleep_wake_taps; bool sensor_standby; int sensor_standbys;
    /* simulated phone: the harness plays the phone (what the iPhone app will send) */
    struct { bool enabled, connected, bonded, pairing; uint32_t passkey; int rssi; plat_phone_in_t in;
             bc_ctrl_req_t ctrl; bool ctrl_pending; bc_ctrl_resp_t last_resp; int resps; bc_live_t last_live; int lives; int forgets;
             /* 0.6.0 phone services: what the board notified */
             int notifies, unknown_notifies; bc_wifi_scan_result_t scan[32]; int n_scan; bc_wifi_scan_end_t scan_end; int scan_ends;
             bc_wifi_status_msg_t wifi_status; int statuses; bc_ride_summary_t rides[64]; int n_rides; bc_sync_end_t sync_end; int sync_ends;
             bc_profile_msg_t profile; int profiles; bc_profile_ack_t profile_ack; int profile_acks; bc_settings_msg_t settings; int settings_msgs; bc_event_t event; int events;
             struct { uint8_t chr; size_t len; uint8_t b[BC_LINK_MAX]; } svc_in[8]; int svc_in_n; bool notify_full; uint8_t last_notify_chr;
             bool standby; int standbys;
             /* 0.7.0 pairing lifecycle: the board's identity generation (changes on forget/repair) and what the phone remembers */
             uint8_t id_gen, phone_id_gen; bool phone_has_bond; bool enc_failed; int enc_fails, repairs; uint16_t last_disc_code;
             bc_sensor_diag_t diag[16]; int ndiag; int diags;
             /* 0.7.3 Link 1.2.3: what the board answered to the phone's DIAG_* requests */
             bc_diag_info_t dinfo[32]; int ndinfo; bc_diag_list_end_t dlist_end; int dlist_ends; bc_diag_err_t derr; int derrs;
             bc_diag_ready_t dready; int dreadys; bc_diag_chunk_t dchunk; int dchunks; uint8_t dbuf[16384]; uint32_t dbuf_len;
             uint16_t mtu;            /* negotiated ATT MTU the harness reports (0 = 185 like iOS) */
             bool congested;          /* test hook: plat_phone_bulk_room() false (LIVE / mbufs need the link) */
             uint32_t last_chunk_ms; uint32_t min_chunk_gap_ms; } phone;
    /* 0.7.3 crash evidence + boot modes (plat_host.c) */
    bc_reset_t reset_kind; plat_crash_t crash; char log_tail[1024]; uint16_t nvs_skip; uint32_t nvs_skip_fw, fw_id; uint32_t crash_total;
    bool phone_only_started; int crash_consumed; uint32_t heap_free, heap_min;
    /* 0.7.4: storage category measured at boot (0 = BC_STOR_OK), Bluetooth unavailable (reason), crash partition state */
    int storage_state; bool bt_unavailable; char bt_reason[56]; int crashpart; uint32_t crashpart_bytes; uint32_t fat_writes_refused;
    /* 0.7.2 fake GATT power meter (sim_gatt.c): a real attribute table driven through bc_gatt / bc_pipe / bc_xds */
    struct { bool on, legacy_pick, paired, in_range, streaming, stall, garbage; int variant, state; uint32_t t, retry_at, next_pkt; int backoff_s;
             int watts, rpm; uint16_t angle, val, last_cccd; uint16_t enabled[64];
             bc_pipe_t pipe; bc_xds_live_t xds;
             int connects, disconnects, discoveries, cccd_writes, wrong_writes, resubs, reconnects, dumps, packets_sent, other_notifies;
             char log[8][96]; int nlog; } fake;
} sim_hw_t;

extern sim_hw_t g_sim;
void sim_fs_root(const char *dir);
/* phone simulation helpers */
void sim_phone_connect(bool already_bonded);   /* connects; if not bonded, the device shows a passkey */
void sim_phone_enter_passkey(void);            /* the rider typed the code on the phone → encrypted + bonded */
void sim_phone_disconnect(void);
/* 0.7.0: the phone connects with whatever it remembers: a bond for the board's CURRENT identity → encrypted at once; a bond
   for an identity the board has since replaced → the phone treats it as a new device → passkey; a bond the board no longer
   holds (same identity) → encryption fails → REPAIR NEEDED. */
void sim_phone_connect_remembered(void);
void sim_phone_connect_stale(void);           /* force the stale-keys case (board wiped bonds, identity unchanged) */
void sim_phone_send_gps(int32_t lat_e7, int32_t lon_e7, uint16_t speed_cms, uint16_t hacc_dm);
void sim_phone_send_hr(uint8_t bpm, uint8_t src);
void sim_phone_send_time(uint64_t epoch_ms);
void sim_phone_ctrl(uint8_t cmd, uint16_t ride_id);
bool sim_phone_write(int chr, const uint8_t *msg, size_t n);   /* chr 0 = Control, 1 = Sync; returns the board's accept/reject */
/* 0.7.2 fake GATT power meter: variant 0 = XDS table (2A55 after 2A63), 1 = Mesh order (2ADE after 2A63);
   legacy_pick = use the 0.7.1 CCCD search (reproduces "connected, no power") */
void sim_fake_meter(bool on, int variant, bool legacy_pick);
void sim_fake_pump(void);
void sim_fake_snapshot(plat_sensors_t *o);
