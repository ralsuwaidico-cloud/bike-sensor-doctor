# BikeComputer Link protocol v1.2 — additions for firmware 0.6.0 / iOS 0.4.0 (24 Oct 2026)

Both sides implement EXACTLY this. Header + TLV as in v1 (bc_link / BCLink.swift). Unknown tags are skipped.
All messages below travel on the **Control** characteristic 0005 (encrypted write + notify) unless stated.
Caps (INFO tag 05, u32): 0x40 RIDE_SYNC (Sync char 0006, see ios/SYNC_PROPOSAL.md), 0x80 WIFI_PROV, 0x100 PROFILE_SYNC,
0x200 SETTINGS. INFO tag 07 = u8[6] device_id (board BT MAC — stays the same across pairing repairs; the Bluetooth identity
address the phone sees is a random static one that CHANGES on every forget/repair, see 1.2.1 below).

## Wi-Fi provisioning (cap 0x80) — the board rejects these when the link is not encrypted
| msg | dir | fields |
|---|---|---|
| WIFI_SCAN_REQ 0x60 | phone→board | 01 u8 max (optional, default 16) |
| WIFI_SCAN_RESULT 0x61 | board→phone, one per AP, strongest first, deduped by SSID | 01 utf8 ssid · 02 s8 rssi · 03 u8 secured (0 open, 1 secured) · 04 u8 channel · 05 u8 saved (0/1) |
| WIFI_SCAN_END 0x62 | board→phone | 01 u8 count · 02 u8 err (0 ok, 1 radio off, 2 busy/ride, 3 failed) |
| WIFI_SET 0x63 | phone→board | 01 utf8 ssid (≤32 B) · 02 utf8 password (0–63 B, empty = open) · 03 u8 flags (bit0 connect now, bit1 save) |
| WIFI_FORGET 0x64 | phone→board | 01 utf8 ssid |
| WIFI_STATUS 0x65 | board→phone, on 0x66 and on every change | 01 u8 state (0 off, 1 disconnected, 2 scanning, 3 connecting, 4 connected, 5 connected_no_internet) · 02 u8 err (0 none, 1 wrong_password, 2 not_found, 3 timeout, 4 other) · 03 utf8 ssid (current/target) · 04 s8 rssi · 05 u8 saved_count · 06 u8 radio_on |
| WIFI_STATUS_REQ 0x66 | phone→board | — |
Passwords: never logged, never echoed, stored only in the board's existing NVS store.

## Athlete profile sync (cap 0x100) — phone is authoritative once paired; board works alone otherwise
| msg | dir | fields |
|---|---|---|
| PROFILE_GET 0x70 | phone→board | — → board answers PROFILE 0x72 |
| PROFILE_SET 0x71 | phone→board | 01 u32 version (monotonic, phone-owned) · 02 u32 updated_epoch_s · 03 utf8 name (≤24 B) · 04 u16 ftp_w · 05 u8 ftp_how (0 assumed, 1 entered, 2 estimated from rides, 3 tested) · 06 u16 weight_kg_x10 · 07 u16 birth_year (0 unknown) · 08 u8 max_hr (0 unknown) · 09 u8 rest_hr (0 unknown) · 0A u8 units (0 metric, 1 imperial) · 0B u8 hours_per_week · 0C u8 level (0 new, 1 regular, 2 experienced) · 0D u8 goal (0 fitness, 1 endurance, 2 climbing, 3 event, 4 weight) · 0E u8 lthr (0 unknown) |
| PROFILE 0x72 | board→phone | same tags as 0x71 as the board holds them + 0F u8 source (0 device-only, 1 phone-synced) + 10 u32 board_saved_epoch_s |
| PROFILE_ACK 0x73 | board→phone after 0x71 | 01 u32 version · 02 u8 status (0 applied, 1 rejected_older_version, 2 bad_value) · 03 u32 board_version (version now in force) |
Rules: the board applies a SET only when version > its stored phone-version; version 0 on the board = device-only profile.
Never touched by profile sync: ride history, journal, XDS/strap pairing, phone bonds, calibration, Wi-Fi store.
First pairing: phone sends PROFILE_GET, compares, shows the user the differences, and sends PROFILE_SET only after the user confirms.

## Device settings (cap 0x200)
| msg | dir | fields |
|---|---|---|
| SETTINGS_GET 0x76 | phone→board | — → board answers SETTINGS 0x75 |
| SETTINGS_SET 0x74 | phone→board | 01 u32 version · 02 u8 brightness_pct (10–100) · 03 u16 screen_timeout_s (0 never) · 04 u8 wake_gesture (0 triple tap, 1 double tap, 2 any touch) · 05 u8 phone_link_enabled · 06 u8 hr_pref (0 strap first, 1 watch first) · 07 u16 auto_sleep_min (0 off) · 08 u8 ride_layout (0 A, 1 B, 2 C) · 09 u8 wake_on_coach_cue (0/1) · 0A u8 units (0/1) |
| SETTINGS 0x75 | board→phone, after SET and on request | same tags with current values + 0F u8 status (0 applied, 1 rejected_older_version, 2 bad_value, 3 unsupported_tag) + 10 u32 supported_mask (bit n = tag n+1 supported) |
A phone shows a control only when `supported_mask` has its bit; every change waits for 0x75 and shows "synced" / "failed".

## Power states (board) — behaviour the phone may rely on
| state | display | BLE phone link | XDS / strap | recording | how to leave |
|---|---|---|---|---|---|
| Active | on | on | on | yes | — |
| Display off | off | **on, unchanged** | on | continues | wake gesture, coach cue (ride), phone command |
| Connected standby (no ride, idle) | off | on (slow advertising when not connected) | off | — | wake gesture, phone connect |
| Deep sleep (explicit, or auto-sleep setting) | off | **off** | off | never while a ride is active | wake gesture / RESET / USB |

## 1.2.1 additions (firmware 0.7.0 / iOS 0.8.0) — no new tags on existing messages
- Board identity: random static address persisted on the board; a new one after every Forget / Repair / data reset. The phone
  must therefore NOT key the board by its CoreBluetooth peripheral identifier alone: re-discover by the Link service UUID +
  name and accept a new identifier for the same `device_id` (INFO tag 07).
- EVENT `event_id 0x20 link_diag` (tags 02 reason, 03 u16 bonds, 04 sync state) once per connection; PROFILE hello on connect;
  PROFILE_SET whole-message validation with `status 2` — details and vectors in firmware/waveshare/docs/BLE_LINK_PROTOCOL.md.
- Stale-key failure on the board side is `encryption status 0x206 (key missing)` → board state REPAIR NEEDED; the phone side
  sees "Peer removed pairing information" / ATT insufficient authentication. Recovery = board REPAIR (new identity) +
  iPhone Settings › Bluetooth › Forget, then pair again from the app.
