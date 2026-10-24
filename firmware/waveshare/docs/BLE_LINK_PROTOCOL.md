# BikeComputer Link — BLE protocol v1.0

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
| Control | `0005` | read, write, notify | CTRL_REQ written by the phone; CTRL_RESP notified back |
| Sync | `0006` | read, write, notify | reserved (Phase 5: ride history transfer) |
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
`01 u8 ver_major (1)` `02 u8 ver_minor (0)` `03 str fw` `04 str name` `05 u32 caps` `06 u16 max_msg`
caps: 0x01 LIVE, 0x02 GPS_IN, 0x04 HR_IN, 0x08 WEATHER_IN, 0x10 RIDE_CTRL, 0x20 TIME_SYNC, 0x40 RIDE_SYNC (Phase 5).

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
9 OPEN_METEO, 0x7F DEMO.

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
