# Porting spec — XDS/Branta power meter on a microcontroller (ESP32-S3 or similar)

This document describes exactly what the Android app does with the sensor so the same behaviour can be implemented
in C/C++ on a dedicated cycling computer. The reference implementation is the **portable core** in
`app/src/main/java/com/rashed/bikesensordoctor/core/` (`XdsDecoder.kt`, `RideStats.kt`, `HealthClassifier.kt`) —
pure Kotlin with no Android imports — and its tests in `app/src/test/.../core/`, which replay 48 real packets
captured from Rashed's sensor (`Fixtures.kt`). Port the tests too.

## 1. Finding the sensor (BLE central role)

- Scan for advertisements containing **16-bit service UUID 0x1828**. Also accept a remembered MAC
  (`C0:A1:25:07:97:69`) or a device name beginning `XDS`.
- The sensor advertises only while awake; it wakes when the cranks move. Expect to wait up to ~30 s after a long idle.
- Observed RSSI at ~1 m: −60 to −75 dBm.

## 2. Connecting

1. Connect (LE, public address). Observed: connection completes in ~300 ms.
2. Request MTU 247 (optional; the only large payload is the 36-byte telemetry stream). **Wait for the MTU exchange to
   finish before starting service discovery** — starting discovery while the exchange is in flight hung the Android
   stack for 30 s on the Nokia (log 2026-10-11 13:59:34 → 14:00:02). If no MTU response within 2 s, discover anyway.
3. Discover services. Expected GATT table:

| Service | Characteristic | Props | Meaning |
|---|---|---|---|
| 0x180A Device Information | 0x2A24 | R | Model: `csc_sensor_01` |
| | 0x2A25 | R | Serial: `886A001257P9769` |
| | 0x2A26 / 0x2A27 / 0x2A28 | R | FW `1.0`, HW `V1.0`, SW `V1.7` |
| 0x180F Battery | 0x2A19 | R, N | Battery %, first byte (observed `5B` = 91 %; two trailing bytes `01 10` are vendor extras — ignore) |
| **0x1828** (labelled Mesh Proxy by the SIG, repurposed by XDS) | **0x2A63** | **N** | **11-byte power/cadence packet, ~1 Hz — THE data channel** |
| | 0x2A65 | R | 26 bytes, vendor "feature" blob (undocumented) |
| | 0x2A5D | R | 15 bytes, vendor blob (undocumented) |
| | 0x2A55 | W, I | Control point. Not required: this unit streams without any write. Do not write to it. |
| a6ed0401-d344-460a-8075-b9e8ec90d71b | a6ed0402 (N), a6ed0403 (W), a6ed0404 (W,I) | | Undocumented vendor service (probably OTA/config). **Never write.** |
| a6ed0201-d344-460a-8075-b9e8ec90d71b | a6ed0202 (N), a6ed0203 (W), a6ed0204 (W,N) | | Undocumented. a6ed0202 notifies a 36-byte telemetry frame at ~7.5 Hz: header `AA BB 24 0F`, trailing checksum byte; bytes 19–20 appear to mirror cadence (big-endian signed). Not needed; subscribing is harmless. |

4. Subscribe to notifications on **0x2A63** (write `01 00` to its CCCD 0x2902). Optionally 0x2A19 for battery.
5. Read 0x2A19 once for the battery level.

**No start command, no authentication, no pairing/bonding is needed.** The sensor began notifying 0x2A63 ~1 s after
the CCCD write, with no writes to any control point. (A community bridge sends `02 16 AA 10` to 0x2A55; another unit
rejected it with ATT error 0x81; ours was never sent it. Leave it out.)

## 3. Packet format — 0x2A63 under 0x1828

11 bytes, little-endian:

```
offset  type  field
0..1    u16   total power, W
2..3    s16   left power, W
4..5    s16   right power, W
6..7    s16   cadence, rpm, SIGNED (see below)
8..9    u16   crank angle, degrees 0..359
10      u8    error code (0 observed)
```

Example C:
```c
typedef struct { uint16_t power_w; int16_t left_w, right_w, cadence_rpm; uint16_t angle_deg; uint8_t error; } xds_sample_t;
bool xds_decode(const uint8_t *b, size_t n, xds_sample_t *out) {
    if (n < 11) return false;
    out->power_w     = b[0] | (b[1] << 8);
    out->left_w      = (int16_t)(b[2] | (b[3] << 8));
    out->right_w     = (int16_t)(b[4] | (b[5] << 8));
    out->cadence_rpm = (int16_t)(b[6] | (b[7] << 8));
    out->angle_deg   = b[8] | (b[9] << 8);
    out->error       = b[10];
    return out->angle_deg <= 359 && abs(out->cadence_rpm) <= 250 && out->power_w <= 3000;  // plausibility
}
```

Observed packets (real):
- Idle: `00 00 00 00 00 00 00 00 5A 01 00` → 0 W, 0 rpm, angle 346°, frozen for 32 s.
- Turning unloaded cranks: `00 00 00 00 00 00 A8 FF F1 00 00` → 0 W, cadence **−88**, angle 241°; angle advanced every
  packet (140, 10, 42, 144, 266, 49, 241, 37, 225, 339, 139, 283, 46, 134, 293, 79 …).
- Community bridge samples (light forward pedaling): `03 00 03 00 00 00 07 00 …` → 3 W total = 3 L + 0 R, 7 rpm.

**Cadence sign.** On Rashed's unit the value was negative throughout a stationary pedaling test. Two open-source
bridges clamp negatives to 0 and one README calls negative "reverse pedaling". Either the rider turned the cranks
backwards or the unit's sign convention is inverted. Rule: **use |cadence| for display and statistics; show a
"backwards" flag when negative; never discard the sample.** The ride test in v0.3 (pedal forwards under load) will
settle the convention — update this section with the result.

**Power.** 0 W whenever there is no load, regardless of cadence. Power is only meaningful while riding.

**Rate.** 1.00 Hz (median interval 1020 ms on both our unit and the community one). Treat >6 s without a packet as a
link problem (not a sensor problem); treat >4 s as "no live value" and blank the display.

## 4. Ride statistics (RideStats.kt)

- States: IDLE → RUNNING ⇄ PAUSED → FINISHED. Samples count only in RUNNING. Riding time accumulates only in RUNNING.
- Live power/cadence: last plausible sample, blanked ("—") when older than 4 s. Never hold a stale value.
- 3-s power: mean of samples received in the last 3000 ms (count varies with packet loss).
- Average power: Σpower / samples (zeros included — matches Garmin/Wahoo).
- Average cadence: over samples with cadence ≠ 0 only. Max cadence: max |cadence|.
- Energy (kJ) ≈ avgPower × seconds / 1000.
- Reject (don't count) implausible samples: angle > 359, |cadence| > 250, power > 3000.
- L/R balance % = left/(left+right) when the sum > 0.

## 5. Link health classification (HealthClassifier.kt)

Priority order: no permission → Bluetooth off → (not connected & recovering) RECONNECTING → (not connected) SEARCHING
→ (connected, no packet for 6 s) LINK_SILENT = Bluetooth problem → (packets but ≥3 undecodable and none decodable)
DECODE_ERROR = software problem → (error byte ≠ 0) SENSOR_FAULT → rotating ? CONNECTED_LIVE : CONNECTED_IDLE.

Recovery actions, all reversible: reconnect with exponential back-off 1 → 2 → 4 → 8 → 16 s; after a silent link,
disconnect/reconnect, at most 3 cycles then fall back to scanning. Never write to any characteristic other than
CCCDs.

## 6. Hardware notes for the ESP32-S3 build

- NimBLE central, one connection, MTU ≥ 23 is enough for 0x2A63 (11 bytes) — MTU 247 only matters for a6ed0202.
- Store last MAC in NVS; try direct connect first, scan as fallback (same as the Android SensorManager).
- Round display: the dashboard layout already puts power in the dominant arc gauge (270° sweep starting at 135°)
  with cadence in a second arc; the four small fields map to a ring of tiles on a circular screen.
- Sample rate is low (1 Hz), so a 1 s UI tick plus a 500 ms blink for stale is sufficient.
