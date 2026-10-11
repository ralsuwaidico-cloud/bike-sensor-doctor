# Analysis of the first real-device session (Nokia 5.3, 2026-10-11 14:00)

Source: `report-20261011-140056.txt` and `-log.json` exported from the app (490 log events).

## What the sensor sent
- Connected, battery 91 %, model `csc_sensor_01`, FW 1.0, SW V1.7. All 8 notify channels subscribed.
- `0x2A63` under `0x1828`: **48 packets at exactly 1 Hz, no start command needed** (matches 66ccff231's observation).
- `a6ed0202`: 369 packets at ~7.5 Hz, 36 bytes, header `AA BB 24 0F`, last byte a checksum — an internal
  telemetry stream (contains a copy of cadence at bytes 19-20, big-endian). Not needed.
- `0x2A19` battery: 24 packets.

## Why the first build showed 0 W / 0 rpm
0x2A63 packets, idle (14:00:08–14:00:39): `00 00 00 00 00 00 00 00 5A 01 00` — power 0, cadence 0, angle 346°, fixed.
0x2A63 packets, rotating (from 14:00:40): e.g. `00 00 00 00 00 00 A8 FF F1 00 00` — power 0, **cadence 0xFFA8 = −88 rpm**,
angle advancing every packet (140°, 10°, 42°, 144°, 266°, 49°, 241°, 37°, 225°, 339°, 139° …).

1. **Cadence was negative** in every rotating packet (−24 → −88, settling around −80 to −88, i.e. the ~80 rpm the
   app asked for). Both open-source decoders clamp negative cadence to 0; the 66ccff231 README states negative
   means reverse pedaling ("负值（反踩）"). The app copied that clamp, hence 0 rpm. **The sensor was measuring
   cadence correctly the whole time.** Most likely the pedals were turned backwards (natural with the bike standing
   on its wheels); the other possibility is that this unit's sign convention is inverted. Either way the magnitude
   is right. v0.2 keeps the sign, shows the magnitude, and tells the rider on screen if it sees backwards pedaling.
2. **Power was 0 because there was no load.** Spinning cranks that drive nothing produce ~0 W on any power meter
   (66ccff231's samples show 2–7 W for light unloaded turning). Power cannot be verified without riding or a
   trainer. v0.2 adds a 60-second ride test for exactly this.

## Decoder validation
Layout confirmed identical in DuoDuoJuZi `xds_protocol.c` (u16 power, s16 L, s16 R, s16 cadence, u16 angle, u8 error)
and 66ccff231 README (whose samples satisfy total = left + right). Matched against the captured packets: idle = all
zero + fixed angle; rotation = non-zero signed cadence + advancing angle. Unit tests now include two captured packets.

## Other fixes from the log
- First connection attempt hung in service discovery for 30 s (discovery was started 600 ms after `requestMtu`,
  while the MTU exchange was still in flight). v0.2 starts discovery from the MTU callback, with a 2 s fallback.

## Verdict on the sensor so far
- Radio, battery, firmware, data streaming: **working**.
- Cadence measurement: **verified** (magnitude ~80–88 rpm during the pedaling phase; direction reported as reverse).
- Power measurement: **not yet verified** — needs the ride test in v0.2.
- Garmin Edge 820: cannot pair, by design. The Edge 820 pairs sensors over ANT+ only (Bluetooth is for the phone
  link): DC Rainmaker review and Garmin forum. The meter has no ANT+ and no standard BLE cycling service.
