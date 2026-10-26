# BikeComputer Link — BLE protocol v1.2 (firmware 0.6.0; v1.0 = 0.4.0/0.5.0)

The phone talks to the Waveshare cycling computer over one GATT service. The ESP32 is the **hub**: it owns the ride
(start/pause/stop, the recording, distance integration, the coach); the phone adds what the board lacks (GPS, a watch's
heart rate, the wall clock, weather, a big screen). The ESP32 keeps working if the phone leaves.

Reference implementation: `components/bc_core/bc_link.{h,c}` (portable C, host-tested), GATT server `main/ble_link.c`.
The apps implement the same message rules; the host tests in `test/host/test_bc_core.c` (t_link) are the conformance vectors.

## Discovery and pairing
- Advertised name `BikeComputer`; advertisement carries the 128-bit service UUID; scan response carries the name.
- Service **B1CE0000-7E3A-4C55-9D2B-5A0E1C7C0000**. Characteristics replace the `00xx` group:

| Char | UUID suffix | Properties | Content |
|---|---|---|---|
| Info | `0002` | read | INFO message (protocol version, firmware, capabilities, max message size) |
| Live | `0003` | read, notify | LIVE message, 1 Hz while the phone is subscribed |
| Input | `0004` | write, write-no-response | IN_* messages from the phone (time, GPS, HR, weather, battery) |
| Control | `0005` | read, write, notify | CTRL_REQ written by the phone; CTRL_RESP notified back. **1.2:** WIFI_*, PROFILE_*, SETTINGS_* written here, replies notified here |
| Sync | `0006` | read, write, notify | **1.1:** SYNC_REQ written; SYNC_RIDE / SYNC_END notified; a read returns the last SYNC_END |
| Events | `0007` | read, notify | reserved (coach cues, errors) |

- Every characteristic requires an **encrypted + authenticated** link (LE Secure Connections, MITM). The first access from
  a new phone triggers pairing: the board shows a 6-digit code, the phone types it. The bond is stored on both sides, so
  later connections encrypt silently (no code). "Forget phone" on the board deletes all bonds.
- The client must negotiate an ATT MTU of at least **185** (iOS does this by default; Android: `requestMtu(247)`).
  Messages are at most `BC_LINK_MAX` = 180 bytes.
- Advertising pauses for a few seconds while the board initiates a connection to the power meter (meter first, always).

## Message framing
Header, 8 bytes, little-endian: `type u8 | flags u8 (0) | seq u16 | sender_time_ms u32`, followed by fields
`tag u8 | len u8 | value[len]`. Integers are little-endian. **Unknown tags are skipped**; a known tag with the wrong
length is ignored; a message whose fields run past the end is **rejected whole** (never half-applied).

### INFO 0x01 (board → phone, read)
`01 u8 ver_major (1)` `02 u8 ver_minor (2)` `03 str fw` `04 str name` `05 u32 caps` `06 u16 max_msg` `07 u8[6] device_id` (1.2: the board's Bluetooth address; key rides and profiles per board)
caps: 0x01 LIVE, 0x02 GPS_IN, 0x04 HR_IN, 0x08 WEATHER_IN, 0x10 RIDE_CTRL, 0x20 TIME_SYNC, 0x40 RIDE_SYNC, 0x80 WIFI_PROV, 0x100 PROFILE_SYNC, 0x200 SETTINGS.
Firmware 0.6.0 sets all ten. Firmware 0.4.0/0.5.0 set only the first six (no device_id), so a phone must gate every 1.1/1.2 feature on these bits.

### LIVE 0x10 (board → phone, 1 Hz)
Present only when the value is valid *now* (a missing tag means "no data", never "last value"):
`01 u16 power_w` `02 u16 power_age_ms` `03 u8 cadence_rpm` `04 u16 cad_age_ms` `05 u8 hr_bpm` `06 u8 hr_src` `07 u16 hr_age_ms`
Always: `08 u8 ride_state (0 idle,1 running,2 paused,3 ended)` `09 u16 ride_id` `0A u32 elapsed_s` `0B u32 distance_m`
`0C u8 cue_id` `0D u8 battery_pct (0xFF unknown)` `0E u8 meter_link` `0F u16 meter_gaps` `10 u8 demo (present = SIMULATED values)`.

### Inputs (phone → board, Input characteristic)
- **IN_TIME 0x20**: `01 u64 epoch_ms` `02 u16 uncertainty_ms` `03 s16 tz_min`. Rejected outside 2024…2099.
- **IN_GPS 0x21**: `01 s32 lat_e7` `02 s32 lon_e7` `03 s32 alt_dm` `04 u16 hacc_dm` `05 u16 vacc_dm` `06 u16 speed_cms`
  `07 u16 course_cdeg` `08 u64 fix_epoch_ms` `09 u8 src` (3 PHONE_GPS, 7 ONBOARD_GPS). Rejected without lat/lon, out of
  range, or without a GPS source. Speed above 108 km/h is not trusted. Send at 1 Hz while riding.
  The board integrates distance from speed itself (ignores fixes with hacc > 50 m; ignores speed < 1.8 km/h); the phone must
  **not** send a distance total.
- **IN_HR 0x22**: `01 u8 bpm` `02 u8 src` `03 u64 sample_epoch_ms` `04 u8 quality`. Rejected outside 25–250 or without a
  source. The board shows it only if it is ≤ 6 s old (watches deliver about every 5 s); a directly connected strap wins unless the rider chose "watch first".
- **IN_WEATHER 0x23**: `01 s16 temp_dc` `02 u16 wind_cms` `03 u16 wind_deg` `04 u8 humidity` `05 u8 provider` `06 u64 obs_epoch_ms`.
  Rejected without a provider.
- **IN_BATTERY 0x24**: `01 u8 phone_pct` `02 u8 watch_pct` (0xFF unknown).

Sources (`bc_src_t`): 1 XDS, 2 BLE_STRAP, 3 PHONE_GPS, 4 APPLE_WATCH, 5 WEAR_OS, 6 PHONE_STRAP, 7 ONBOARD_GPS, 8 WEATHERKIT,
9 OPEN_METEO, 10 BLE_CSC (0.6.0: a speed/cadence sensor paired to the board; appears as `dist_src` and as the cadence source),
0x7F DEMO.

### Ride control (Control characteristic)
- **CTRL_REQ 0x30**: `01 u16 req_id` `02 u8 cmd` `03 u16 ride_id` (0 = any). cmd: 1 START, 2 PAUSE, 3 RESUME,
  4 STOP_REQUEST, 5 STOP_CONFIRM.
- **CTRL_RESP 0x31** (notify): `01 u16 req_id` `02 u8 status` `03 u8 ride_state` `04 u16 ride_id`. status: 0 OK,
  1 BAD_STATE, 2 NEEDS_CONFIRM, 3 UNKNOWN, 4 WRONG_RIDE.
- Stopping is two steps: STOP_REQUEST → NEEDS_CONFIRM (board arms for 10 s) → STOP_CONFIRM → OK. A confirm without a
  request is refused. A request naming another ride id is refused (WRONG_RIDE).

## Rules the apps must follow
1. Never show a LIVE value whose tag is absent, and show the board's age fields when they exceed 3 s.
2. Label the heart-rate source from `hr_src`; never present relayed watch HR as a strap.
3. Distance and elapsed time come from the board (`0A`, `0B`); the phone does not keep its own ride clock.
4. If the connection drops, keep showing "disconnected"; reconnect quietly; do not start a ride locally.
5. Treat `10 demo` as a red label on every screen; never store a demo ride as a real one.

## 1.1 Ride-history sync (Sync characteristic `0006`, cap 0x40) — firmware 0.6.0
Layout exactly as proposed by the phone app in `ios/SYNC_PROPOSAL.md`; the board streams `rides/history.txt` (R1/R2 lines) oldest first.
- **SYNC_REQ 0x50** (phone → board, write): `01 u16 after_ride_id` (0 = from the oldest) `02 u8 max_count` (1…50, 0 → 50).
  A new request cancels a batch in flight; a disconnect cancels it too.
- **SYNC_RIDE 0x51** (board → phone, one notify per ride, ≤ 180 B): `01 u16 id` `02 u8 flags (bit0 demo, bit1 recovered)` `03 u32 duration_s`
  `04 u32 paused_s` `05–09 s16 avg_power, max_power, avg_cad, avg_hr, max_hr (−1 = none)` `0A–0C u32 power_s, cad_s, hr_s` `0D u32[7] zone_s (only when valid)`
  `0E s16 ftp_w` `0F u8 ftp_how` `10 s16 kj` `11 s16 best20` `12 s8 inband_pct` `13 u16 ftp_new` `14 u8 ftp_suggested_only` `15 u32 distance_m`
  `16 u8 dist_src` `17 u32 start_epoch_s (0 = clock unknown)` `18 str coach (≤ 60 B, cut at a UTF-8 boundary)`.
- **SYNC_END 0x52**: `01 u16 count (sent now)` `02 u16 total (rides on the board)` `03 u8 more`.
- Pacing: the board queues up to 8 notifications per 250 ms (≈ 32/s); 50 rides take about 2 s.

Vectors (also asserted by `test/host` t_link2 and the Swift BCLinkTests): SYNC_REQ(after 7, max 50, seq 3, t 1000) =
`50 00 03 00 E8 03 00 00 01 02 07 00 02 01 32`; SYNC_END(50, 123, more) seq 1 = `52 00 01 00 00 00 00 00 01 02 32 00 02 02 7B 00 03 01 01`;
SYNC_RIDE header + first fields for id 12 recovered, seq 9, t 55 = `51 00 09 00 37 00 00 00 01 02 0C 00 02 01 02 03 …`.

## 1.2 Wi-Fi provisioning (Control characteristic `0005`, cap 0x80) — firmware 0.6.0
The board rejects these with ATT "insufficient authentication" when the link is not encrypted. Passwords are copied into the Wi-Fi
manager and wiped; they are never logged or echoed back.
- **WIFI_SCAN_REQ 0x60**: optional `01 u8 max` (default 16, cap 32). During a ride the board answers END with err 2 (busy)
  without scanning; with the radio off, err 1. A connect attempt in flight delays the scan (up to 25 s) instead of dropping it.
- **WIFI_SCAN_RESULT 0x61**, one per network, strongest first, one entry per SSID: `01 str ssid (UTF-8, 1–32 B)` `02 s8 rssi` `03 u8 secured`
  `04 u8 channel` `05 u8 saved`.
- **WIFI_SCAN_END 0x62**: `01 u8 count` `02 u8 err (0 ok, 1 radio off, 2 busy/ride, 3 failed)`.
- **WIFI_SET 0x63**: `01 str ssid (1–32 B, required)` `02 str password (0–63 B; empty = open)` `03 u8 flags (bit0 connect now, bit1 save; default 3)`.
  Rejected (nothing applied) without an SSID or with a longer password.
- **WIFI_FORGET 0x64**: `01 str ssid`.
- **WIFI_STATUS 0x65** (sent on 0x66, after every SET/FORGET, on every change, and every 15 s while connected):
  `01 u8 state (0 off, 1 disconnected, 2 scanning, 3 connecting, 4 connected, 5 connected_no_internet)` `02 u8 err (0 none, 1 wrong password,
  2 not found, 3 timeout, 4 other)` `03 str ssid (current / target)` `04 s8 rssi` `05 u8 saved_count` `06 u8 radio_on`.
- **WIFI_STATUS_REQ 0x66**: no fields.

Vectors (t_link2): STATUS_REQ seq 10 = `66 00 0A 00 00 00 00 00`; SCAN_REQ default = `60 00 01 00 00 00 00 00`; SCAN_REQ max 8 =
`60 00 02 00 00 00 00 00 01 01 08`; SCAN_RESULT "Rashed’s iPhone" −62 dBm secured ch 6 not saved, seq 5 =
`61 00 05 00 00 00 00 00 01 11 52 61 73 68 65 64 E2 80 99 73 20 69 50 68 6F 6E 65 02 01 C2 03 01 01 04 01 06 05 01 00`;
SCAN_END(3, ok) seq 6 = `62 00 06 00 00 00 00 00 01 01 03 02 01 00`; SET("HomeNet", "Secret-123", 3) seq 7 =
`63 00 07 00 00 00 00 00 01 07 48 6F 6D 65 4E 65 74 02 0A 53 65 63 72 65 74 2D 31 32 33 03 01 03`; FORGET("HomeNet") seq 8 =
`64 00 08 00 00 00 00 00 01 07 48 6F 6D 65 4E 65 74`; STATUS(connected, HomeNet, −48, 2 saved, on) seq 9 =
`65 00 09 00 00 00 00 00 01 01 04 02 01 00 03 07 48 6F 6D 65 4E 65 74 04 01 D0 05 01 02 06 01 01`.

## 1.2 Athlete profile sync (Control, cap 0x100) — firmware 0.6.0
Phone-authoritative once the rider confirmed on the phone; the board works alone with the last synced profile. `has`-style:
a SET carries any subset of tags 02–0E; the board reports everything.
- **PROFILE_GET 0x70**: no fields → board answers PROFILE.
- **PROFILE_SET 0x71**: `01 u32 version (required, > stored)` `02 u32 updated_epoch_s` `03 str name (≤ 24 B)` `04 u16 ftp_w (≤ 2000)` `05 u8 ftp_how (0 assumed, 1 entered,
  2 estimated from rides, 3 tested)` `06 u16 weight_kg_x10 (200–3000 or 0)` `07 u16 birth_year (1900–2100 or 0)` `08 u8 max_hr (100–230 or 0)` `09 u8 rest_hr (25–120 or 0)`
  `0A u8 units (0 metric, 1 imperial)` `0B u8 hours_per_week (≤ 60)` `0C u8 level (0 new, 1 regular, 2 experienced)` `0D u8 goal (0 fitness, 1 endurance, 2 climbing, 3 event, 4 weight)`
  `0E u8 lthr (80–220 or 0)`. An out-of-range value is dropped (its tag treated as absent); a message without tag 01 is rejected.
- **PROFILE 0x72** (board → phone): the same tags with the board's values + `0F u8 source (0 device-only, 1 phone-synced)` `10 u32 board_saved_epoch_s`.
  Mapping on the board: ftp_how entered/tested ↔ ENTERED, estimated ↔ AUTO; level ↔ experience beginner/novice → 0, intermediate → 1, advanced/competitive → 2;
  goal FTP (board-only) is reported as 0 fitness; birth_year ↔ age via the phone-synced clock; name cut to 16 bytes on the board.
- **PROFILE_ACK 0x73**: `01 u32 version` `02 u8 status (0 applied, 1 rejected_older_version, 2 bad_value)` `03 u32 board_version`.
- Never touched by a SET: ride history, journal, sensor pairings, phone bonds, Wi-Fi store, device settings.

Vectors (t_link3): PROFILE_GET seq 1 = `70 00 01 00 00 00 00 00`; PROFILE_ACK(v1 applied, board v1) seq 2 =
`73 00 02 00 00 00 00 00 01 04 01 00 00 00 02 01 00 03 04 01 00 00 00`; full PROFILE_SET v1 "Rashed" FTP 250 entered, 78.0 kg, born 1990,
max 186, rest 52, metric, 6 h, experienced, endurance, LTHR 170, updated 1792850100, seq 2 =
`71 00 02 00 00 00 00 00 01 04 01 00 00 00 02 04 B4 B8 DC 6A 03 06 52 61 73 68 65 64 04 02 FA 00 05 01 01 06 02 0C 03 07 02 C6 07 08 01 BA 09 01 34 0A 01 00 0B 01 06 0C 01 02 0D 01 01 0E 01 AA`.

## 1.2 Device settings (Control, cap 0x200) — firmware 0.6.0
- **SETTINGS_GET 0x76**: no fields → SETTINGS.
- **SETTINGS_SET 0x74**: `01 u32 version (required, > stored)` `02 u8 brightness_pct (10–100)` `03 u16 screen_timeout_s (0 never, ≤ 3600)` `04 u8 wake_gesture (0 triple, 1 double, 2 any touch)`
  `05 u8 phone_link_enabled` `06 u8 hr_pref (0 strap first, 1 watch first)` `07 u16 auto_sleep_min (0 off, ≤ 240)` `08 u8 ride_layout (0 A, 1 B, 2 C)` `09 u8 wake_on_cue` `0A u8 units`.
  Out-of-range values are dropped. Switching the phone link off is applied about 1.5 s after the reply has been sent.
- **SETTINGS 0x75** (board → phone, after a SET and on request): the same tags with current values + `0F u8 status (0 applied, 1 rejected_older_version, 2 bad_value, 3 unsupported_tag)`
  `10 u32 supported_mask (bit n = tag n+1 supported; 0.6.0 = 0x3FF)`.

Vectors (t_link3): SETTINGS_GET seq 3 = `76 00 03 00 00 00 00 00`; SETTINGS_SET v1 brightness 55, timeout 120 s, double tap, seq 4 =
`74 00 04 00 00 00 00 00 01 04 01 00 00 00 02 01 37 03 02 78 00 04 01 01`; SETTINGS reply v2 (80 %, 60 s, triple, link on, strap first, no auto sleep,
layout A, cue wake on, metric, applied, mask 0x3FF) seq 5 = `75 00 05 00 00 00 00 00 01 04 02 00 00 00 02 01 50 03 02 3C 00 04 01 00 05 01 01 06 01 00 07 02 00 00 08 01 00 09 01 01 0A 01 00 0F 01 00 10 04 FF 03 00 00`.

## EVENT (Events characteristic `0007`, notify) — firmware 0.6.0, emission OFF by default
`EVENT 0x40`: `01 u8 event_id` `02 u8 level_pct_est` `03 u16 mv` `04 u8 stage`. One event defined: `event_id 0x10 battery_notice`
(stage 1 ≈ 80 %, 2 ≈ 90 %, 3 ≈ 98 % — voltage-band ESTIMATES, see `CHARGE_ALERTS.md`). Not sent unless the board's `chg_notice`
flag is on, which has no menu while HW-1 is open. Vector (seq 7, t 123456, 81 %, 3990 mV, stage 1):
`40 00 07 00 40 E2 01 00 01 01 10 02 01 51 03 02 96 0F 04 01 01`. A phone that subscribes to Events should show it as a local
notification labelled as an estimate and must not present it as a charger state.

### 1.2.1 (firmware 0.7.0): `event_id 0x20 link_diag` — sent ONCE per connection, right after the board's PROFILE "hello"
Same four tags, reinterpreted: `02 u8 last_disconnect_reason` (0 none, 1 phone ended it, 2 board ended it, 3 timeout / out of
range, 4 keys missing (stale pairing), 5 authentication failed, 6 failed to establish, 7 other), `03 u16 bonded_phones`,
`04 u8 profile_sync_state` (0 device-only, 1 synced, 2 pending, 3 failed). Informational: the app shows it on the Connection
diagnostics page. Vector (seq 3, t 500, reason 3, 1 bond, synced): `40 00 03 00 F4 01 00 00 01 01 20 02 01 03 03 02 01 00 04 01 01`.

### 1.2.2 (firmware 0.7.2): `event_id 0x21 sensor_diag` — the real pipeline stage of each board sensor link
Spec: `docs/LINK_V1_2_SPEC.md` section "1.2.2". Encoder/decoder: `bc_link_encode_sensor_diag` / `bc_link_decode_sensor_diag`
(bc_core), host-tested in `test/host/test_bc_pipe.c` against the exact bytes below.
`EVENT 0x40`: `01 u8 event_id = 0x21` `02 u8 sensor` (1 power meter, 2 HR strap, 3 CSC) `03 u8 stage` (0 not paired, 1 searching,
2 connecting, 3 connected, 4 subscribed, 5 receiving, 6 valid, 7 stale, 8 error) `04 u32 packets since connect` `05 u16 rejected`
`06 u16 last packet age (ds)` `07 u16 last valid age (ds)` (0xFFFF = none; ages are capped at 0xFFFE) `08 utf8 <= 20 last error` —
**tag 08 is omitted when there is no error**. Only stage 6 means the sensor works.
When the board sends it: on every stage change of a paired link; every 5 s for each paired link below VALID; and once per paired
sensor right after the phone becomes ready (encrypted + subscribed to Control). Nothing for unpaired sensors except the change to
"not paired". Board-side last-error strings: `no service 0x1828`, `no 0x2A63`, `not notifiable`, `no CCCD`, `CCCD write failed`,
`CCCD reads XX XX`, `service discovery`, `characteristic discovery`, `descriptor discovery`, `connect failed`, `connect timeout`,
`no data` (subscribed, nothing for 15 s → reconnected), `data stopped` (stale 25 s → reconnected), `unreadable data`,
`link lost 0x..` (HCI disconnect reason). The error is cleared by the next valid measurement.

Vectors (header seq / t_ms = 100000 = `A0 86 01 00`):
| case | bytes |
|---|---|
| V1 power VALID, 142 packets, 0 rejected, ages 0.4 s, seq 5 | `40 00 05 00 A0 86 01 00 01 01 21 02 01 01 03 01 06 04 04 8E 00 00 00 05 02 00 00 06 02 04 00 07 02 04 00` |
| V2 power SUBSCRIBED, nothing yet, seq 6 | `40 00 06 00 A0 86 01 00 01 01 21 02 01 01 03 01 04 04 04 00 00 00 00 05 02 00 00 06 02 FF FF 07 02 FF FF` |
| V3 power ERROR "no CCCD", seq 7 | `40 00 07 00 A0 86 01 00 01 01 21 02 01 01 03 01 08 04 04 00 00 00 00 05 02 00 00 06 02 FF FF 07 02 FF FF 08 07 6E 6F 20 43 43 43 44` |
| V4 HR strap RECEIVING, 12 packets all rejected, last 0.8 s ago, "unreadable data", seq 8 | `40 00 08 00 A0 86 01 00 01 01 21 02 01 02 03 01 05 04 04 0C 00 00 00 05 02 0C 00 06 02 08 00 07 02 FF FF 08 0F 75 6E 72 65 61 64 61 62 6C 65 20 64 61 74 61` |
| V5 CSC STALE, 300 packets, 2 rejected, ages 5.2 s, seq 9 | `40 00 09 00 A0 86 01 00 01 01 21 02 01 03 03 01 07 04 04 2C 01 00 00 05 02 02 00 06 02 34 00 07 02 34 00` |

A phone that decodes EVENT with the 0x10/0x20 layout must check `event_id` first: tags 02..04 mean different things in 0x21.
LIVE (0x10) is unchanged; from 0.7.2 its `cad_age_ms` is the age of the cadence actually shown (meter or CSC sensor) and
`hr_age_ms` the age of the heart rate shown (strap, or the phone-relayed watch value counted from when the board received it) —
before 0.7.2 `hr_age_ms` was always 0 and `cad_age_ms` copied the power age.

### 1.2.1 (firmware 0.7.0): PROFILE hello and field validation
- As soon as the link is encrypted and the phone subscribed to Control, the board sends one unsolicited `PROFILE 0x72` so the
  phone can compare without asking (a PROFILE_GET still works).
- `PROFILE_SET` is range-checked as a whole: name 1–24 bytes, FTP 50–600 W (0 = unchanged), weight 30.0–200.0 kg, birth year
  1900–2030, max HR 100–230, rest HR 25–120 and below max HR, LTHR 80–220, units 0/1, hours ≤ 40, level ≤ 2, goal ≤ 4. Any
  violation → `PROFILE_ACK status 2 (bad_value)` and NOTHING changes (before 0.7.0 an out-of-range tag was silently dropped
  and the rest applied). The board stores the time it applied the last SET (`prof_sync_epoch`) and shows it as "synced hh:mm".

## Power states and the link (firmware 0.6.0)
| state | display | phone link | XDS / strap | recording |
|---|---|---|---|---|
| Active | on | on | on | yes |
| Display off (manual or timeout) | off | **on, unchanged** | on | continues |
| Connected standby (screen off, no ride) | off | on; advertising every ~1 s when no phone is connected | no scanning for sensors (connections kept) | — |
| Deep sleep (explicit, or the auto-sleep setting — off by default, never with a ride or a connected phone) | off | **off** | off | never while a ride is active |
