# Pipeline health, automatic diagnostics and the diagnostic report (Cyclift 1.0, build 65+)

Rule: **Bluetooth connected is never success.** A path is LIVE only when a valid measurement younger than its freshness
limit (power and cadence 3 s, heart rate 6 s) is actually displayed. Code: `ios/BikeComputer/Pipeline/` (pure rules in
`PipelineHealth.swift`, unit tests in `BikeComputerTests/PipelineTests.swift`).

## Paths and stages
Every path has the stages Discovered · Connected · Subscribed · Receiving packets · Valid measurement · Forwarded ·
Displayed. Each stage is ok / pending / failed / n/a / unknown, with a short detail.

| Path | Discovered … Valid | Forwarded | Displayed |
|---|---|---|---|
| Power meter (strap, CSC) → BikeComputer → iPhone | Board SENSOR_DIAG (spec 1.2.2) stage per sensor. Older firmware: LIVE `meter_link` plus whether LIVE carries the value, with the note "board firmware too old for detailed diagnostics". | LIVE fresh (< 3 s) **and** it carries the metric. | Hub shows the value from the board. |
| Apple Watch → iPhone → BikeComputer | Paired + app installed; link = workout mirroring / Watch Connectivity / messages arriving; workout running; readings arriving; reading < 6 s. | Confirmed only by the board's LIVE echo (hr source = Apple Watch). n/a without a board or when the board uses its own strap. | Hub shows a heart rate. |
| Direct BLE sensor → iPhone | Paired; CoreBluetooth link; iOS-confirmed notification (`didUpdateNotificationStateFor`); packets < freshness; decoded measurement < freshness. | n/a | Hub shows its metric. |

Health per path, from least to most severe: not set up · ready (idle) · live · waiting for data (connected, within 10 s
grace) · reconnecting · data stale · no data · failed. A paired direct sensor that is asleep outside a ride is "ready",
not a problem.

## One message
`PipelineRules.topMessage` picks the most severe path that needs attention (ties: power, watch, then direct sensors).
The watch-update notice appears only when nothing worse than "waiting" is going on. If every set-up path is live or
idle, nothing is shown. The message appears at the top of the Ride screen (header) and of Connections. Examples:
"Power meter connected — waiting for data", "Power meter connected — no readings received", "Watch connected — heart
rate unavailable", "Phone connected — watch heart rate not reaching the BikeComputer", "BikeComputer not connected —
reconnecting automatically", "Update the Watch app: Watch app on iPhone › Cyclift › Update/Install".

Per metric, a missing value says why ("Connected — waiting for data", "No power data", "Data stale", "Reconnecting
automatically") instead of the bare "No power source". The Ride header says "LIVE" only while a board metric is on
screen; otherwise it says "BOARD CONNECTED · NO SENSOR DATA" or "… NO LIVE DATA" in amber.

## Automatic diagnostics and recovery (`PipelineMonitor`)
The monitor runs every second, on a run-loop timer that keeps running while a ride keeps the app alive. Runs are logged
explicitly on app start, BikeComputer connected, sensor connected, Apple Watch available, ride start, and when a shown
metric goes stale. Safe, rate-limited recovery:

| Condition | Action |
|---|---|
| Board remembered, auto-connect on, the rider did not disconnect, not connected, no attempt running, no Repair needed | `DeviceLink.connect()` (at most every 30 s) |
| Board link up > 6 s without LIVE | Re-subscribe Live/Control/Events (3× per connection, every 10 s), then drop the link and reconnect (at most every 2 min) |
| Profile sync failed on this connection | `retryProfile()` once |
| Ride running 15 s, watch set up, no workout / heart rate | `startWatchApp` once per ride |
| Direct sensor connected but silent > 15 s, or subscription refused | Reconnect that sensor (at most every 30 s) |

Each action, each health change and each SENSOR_DIAG goes into ring buffers (last 50 each), persisted in UserDefaults.

## Exportable report (Connections › Diagnostics › Export diagnostic report)
JSON file (`cyclift-diagnostics/1`) containing:
- app, iOS, watch builds and the version check;
- firmware, protocol and caps;
- each path's stages and message;
- Link characteristics seen, notification status and errors, max notify bytes (MTU − 3);
- counters (connects, drops, LIVE, events, SENSOR_DIAG, rejected, sent GPS / HR / time) and the last 20 parse errors (length + first 12 bytes);
- watch channel counters (mirrored / messages / duplicates / dropped);
- direct sensors: kind, services, measurement characteristics, packets, rejected, ages;
- last 50 events, the SENSOR_DIAG history and the board stage log.

It never contains names, e-mail addresses, locations, board hardware addresses or health history beyond counts. The
finished text is scrubbed again: e-mail and MAC patterns, the rider's name and the advertised names of paired sensors.
A unit test asserts this, using the seed rider name.

## SENSOR_DIAG (docs/LINK_V1_2_SPEC.md "1.2.2")
`BCLink.decodeSensorDiag`: EVENT 0x40 with `01 = 0x21`. Tags: 02 u8 sensor (1 power, 2 strap, 3 CSC); 03 u8 stage (0–8);
04 u32 packets; 05 u16 rejected; 06 / 07 u16 ages in deciseconds (0xFFFF = none); 08 utf8 ≤ 20 last error. Unknown tags
and wrong-length fields are skipped. A truncated TLV or a missing sensor / stage rejects the message. Stage words match
the board: Not paired · Searching · Connecting · Connected — waiting for data · Receiving — no valid readings · Live ·
Data stale · Error.

The test vectors in `SensorDiagTests` were built by hand from the spec table, because the firmware workstream's vectors
in `firmware/waveshare/docs/BLE_LINK_PROTOCOL.md` were not visible from this branch. **Integrator: diff the two vector
sets byte for byte.**

## C. "Board → iPhone connects but no live readings": what the code shows
- On firmware 0.7.x, `DeviceLink` sets `.ready` when INFO is read over the encrypted link. Live/Control/Events
  notifications are enabled right after that, and the firmware notifies LIVE only when `s_encrypted && s_live_sub`, so
  the order is correct.
- The firmware **omits** the power fields from LIVE while its meter link has no fresh value (`power_ok`). In that state
  the old app showed a green "LIVE" header and a "connected to the board" meter row with no number. That is the bare
  "connected" the owner saw. Now the stages show it ("Power meter connected — no readings received") and the header is
  amber.
- Not provable from code alone: whether iOS confirms the Live subscription on the owner's phone, and whether LIVE
  messages are rejected by length (MTU). Both are now recorded (`notifying`, `parseErrors`, `maxNotifyBytes`) and appear
  in the exported report.
- The hub now uses the board's per-metric age (LIVE tags 02/04), so a board value turns stale on time.

## CI-verified vs needs hardware
- **CI:** decoder vectors, stage derivation (connected-but-no-data ≠ OK, stale after 3 s / 6 s, old-firmware fallback),
  message selection, per-metric labels, watch dedupe and staleness, version mismatch, report privacy, and that both
  targets compile and the app launches (Release launch smoke).
- **Hardware only:**
  - real SENSOR_DIAG from firmware 0.7.2;
  - power meter → board → phone with the owner's meter;
  - iOS subscription confirmation and MTU;
  - the recovery actions against a real board (re-subscribe / reconnect);
  - the watch items listed in WATCH_PIPELINE.md.
