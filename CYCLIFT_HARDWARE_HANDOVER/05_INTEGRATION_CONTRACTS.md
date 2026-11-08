# 05 — Integration contracts (as they exist in code; nothing changed here)

Legend: **IN CODE (both sides)** · **IN CODE (one side)** · **SPEC ONLY**. Hardware‑verified: none of the device links
below has been exercised on real hardware since firmware 0.6.x (the last board‑to‑phone sessions were 0.4.0–0.6.0 rev 1,
24–25 Oct, protocol 1.0/1.2).

## 1. iPhone ↔ BikeComputer — "BikeComputer Link"

| Aspect | Value | Where |
|---|---|---|
| Transport | BLE GATT, board = peripheral, name `BikeComputer`; service **B1CE0000‑7E3A‑4C55‑9D2B‑5A0E1C7C0000**; chars Info `…0002` (read) · Live `…0003` (read/notify 1 Hz) · Input `…0004` (write) · Control `…0005` (read/write/notify) · Sync `…0006` · Events `…0007` | `firmware/waveshare/docs/BLE_LINK_PROTOCOL.md`, `main/ble_link.c`, `ios/Shared/BCLink.swift` |
| Security | LE Secure Connections + MITM passkey (board shows 6 digits), bonded; MTU ≥ 185; message ≤ 180 B | same |
| Framing | header 8 B `type u8 · flags u8 · seq u16 · sender_time_ms u32` + TLV fields `tag u8 · len u8 · value`; little‑endian; **unknown tags skipped, wrong length ignored, truncated message rejected whole** | `components/bc_core/bc_link.c`, `BCLink.parse` |
| Version / caps | INFO 0x01: ver 1.x, fw string, name, `caps u32`, max_msg, device_id (1.2). Caps: 0x01 LIVE · 0x02 GPS_IN · 0x04 HR_IN · 0x08 WEATHER_IN · 0x10 RIDE_CTRL · 0x20 TIME_SYNC · 0x40 RIDE_SYNC · 0x80 WIFI_PROV · 0x100 PROFILE_SYNC · 0x200 SETTINGS · 0x400 DIAG_XFER (1.2.3) · **0x0800 HELLO · 0x1000 COACH · 0x2000 RIDE_QUEUE · 0x4000 STORAGE · 0x8000 DIAG_AUTO (1.3)** | protocol doc; `coord/interfaces/BLE_CONTRACT.md` §4 |
| Messages ≤ 1.2.3 (**IN CODE both sides, byte‑compatible, must not change**) | LIVE 0x10 (tags present only when valid now; ride_state, ride_id, elapsed, distance, cue, battery, meter link/gaps, demo) · IN_TIME 0x20 · IN_GPS 0x21 (1 Hz, board integrates distance itself) · IN_HR 0x22 (≤ 6 s old, source labelled) · IN_WEATHER 0x23 · IN_BATTERY 0x24 · CTRL_REQ 0x30 / CTRL_RESP 0x31 (START/PAUSE/RESUME/STOP_REQUEST/STOP_CONFIRM; req_id, ride_id; NEEDS_CONFIRM two‑step stop) · SYNC_REQ 0x50 / SYNC_RIDE 0x51 / SYNC_END 0x52 · WIFI_* 0x60–0x66 · PROFILE_GET/SET/PROFILE/ACK 0x70–0x73 · SETTINGS_SET/SETTINGS/GET 0x74–0x76 · DIAG_* 0x80–0x86 · EVENT 0x40 (link_diag 0x20, sensor_diag 0x21, diag_ready 0x22) | firmware `bc_link.c` + iOS `BCLink.swift`; conformance vectors `test/host/test_bc_core.c` ↔ `BCLinkTests`, `LinkV12Tests`, `DiagTransferTests` |
| **Link 1.3** (phone‑first) | APP_HELLO 0x08 / HELLO_ACK 0x09 (enabled caps = INFO ∧ app caps; app retries once after 4 s then stays on 1.2.3); COACH_PLAN 0xB0 / PLAN_ACK 0xB1 / COACH_STATE 0xB2 / COACH_END 0xB3 (phone mirrors the plan's steps and live targets; board falls back offline, coach_mode in LIVE tag 12); RIDEQ_* 0x90–0x96 (offline ride queue, chunked, acked, deleted after ack); STORAGE_STATUS/CLEAN 0xA0–0xA3; LIVE tags 11–15 (coach_seq, coach_mode, storage_state, rides_unsynced, bt_flags — always sent by ≥ rc4); SYNC_REQ tag 03 only_ride_id; EVENT 0x23 rides_pending | **IN CODE both sides but on different branches**: firmware `fw/phonefirst` (0.7.4‑rc5, `app_link13.c`, `bc_link13` tests, fixture `gen_link13_fixture.c`); iPhone **`ios/phonefirst-dev` only** (CI run 90, 34‑vector cross‑check) — **not in the release / `impl/checkpoint-f-ride` iPhone code** |
| Ownership | board = recorder when the ride started on the board (ride clock, distance, pause/stop); phone = GPS, time, watch HR, weather, profile/plan/coach decisions (1.3), history and Health; phone imports board rides by `boardId + rideId`, never duplicates | `BLE_CONTRACT.md` §1, `ios/OWNERSHIP.md`, `ios/BikeComputer/Ride/RideControlPlan.swift` |
| Reconnect | board keeps advertising with a stable random‑static identity (renewed on Forget/repair, 0.7.0); advertising pauses while the board connects to the meter; app reconnects quietly, never starts a ride locally on loss; offline rides wait in the queue (1.3) | protocol doc rules 1–5; `DeviceLink.swift` |
| External sensors (board as central) | power meter Cycling Power 0x1818 / XDS‑named 0x1828 (char 0x2A63; CCCD taken from the data characteristic's own range since 0.7.2); HR 0x180D/0x2A37; CSC 0x1816/0x2A5B; meter first, then strap/CSC; **control point 0x2A55 never written** | `main/ble_central.c`, `bc_xds/bc_hr/bc_csc`, `bc_pipe` (pipeline stages) |

**⚠ Conflict found during this extraction (not fixed here, see 08_):** the iPhone branch `impl/checkpoint-f-ride`
(8 Nov) added a draft "Link 1.3 ride steps" (R‑020) using message types **0x90–0x94 and cap 0x0800** — both already
taken by Link 1.3 RIDEQ_* and HELLO on `fw/phonefirst`. That draft is cap‑gated and inert against every shipped board,
but it must be renumbered before any board with Link 1.3 meets that app. The firmware side of R‑020 does not exist.

## 2. iPhone ↔ Cyclift Watch (LILYGO) — "Cyclift wearable protocol v1"

| Aspect | Value | Where |
|---|---|---|
| Transport | BLE GATT, watch = peripheral (NimBLE); service **6E400001‑C1F7‑4F1A‑9C5E‑2026110800C1**, TX `…02` (notify, watch → phone), RX `…03` (write, phone → watch); frames may be split across notifications | `watch/firmware/src/hal/esp32/drivers.hpp` (Ble), `ios/BikeComputer/Watch/CyWatchWire.swift` |
| Framing | `[ver u8=1][type u8][seq u16][len u16][payload][crc16‑CCITT u16]`; another version → dropped and counted; types Hello 0x01 · TimeSync 0x02 · Status 0x03 · PlanToday 0x10 · Cached 0x11 · Live 0x20 · Gps 0x21 · Coach 0x22 · Event 0x30 · Ack 0x31 · Error 0x7F | `watch/firmware/src/domain/sync.hpp`, `CyWatchWire` |
| Payloads (little‑endian; absent = 0xFFFF / 0x7FFFFFFF, never 0) | Live: power/HR/cadence/speed×10 with ages, ftpKnown+ftpW, power/HR/cadence bands, step name/remaining/total, recording/paused, elapsed, distance · Gps: lat/lon e7, speed×10, heading, phoneUnixS, ageMs · TimeSync: unixS, ms, tzOffsetMin · Status: battery %, charging, freeHeap, phase, pendingEvents · Coach: id, priority, context, requiresAction/safety, expiresInS, instruction, reason, target · PlanToday: kind (0 none/1 ride/2 strength), workoutId, title, startMin, durationMin, exercises[id, name, sets, reps, weight×10, restS, superset] · Cached: sleepMin+source+unix, hrvMs+unix, recoveryPct (absent — no score), recoveryWord, insight, loadPct · Event: deviceId, seq, watchUnixS, kind (1 start 2 pause 3 resume 4 end 5 lap 6 set logged [a = exercise×100+set, b reps, c weight×10] 7 rep count 8 discard 9 save), workoutId, a, b, c, manual · Ack: cumulative seq | `payloads.hpp` ↔ `CyWatchWire.swift`; **byte‑for‑byte vectors generated by the firmware encoder and asserted in `CyWatchWireTests`** |
| Idempotency / reconnect | events carry (deviceId, seq); phone persists the highest acked seq per device, re‑acks duplicates without re‑applying; cumulative Ack; watch resends unacked events after reconnect; bounded queue with explicit overflow warning; phone reassembles split frames and resyncs after a corrupt frame | `EventQueue`/`DedupFilter` (sync.hpp), `CyWatchSession` (CyWatchLink.swift) |
| Ownership | phone = recorder, plan, FTP, GPS source, Health; watch start/pause/resume/lap/end are **commands** to the phone's RideRecorder (or Board through it); logged sets flow into the phone's active strength session; watch never writes Health; GPS points only while linked, duplicates rejected | `ios/OWNERSHIP.md`, `CyWatchCoordinator.swift`, `GpsMirror` |
| Status | **IN CODE both sides (same branch set), host/unit‑tested, never on hardware**; iPhone side is off by default (`cyWatchEnabled`) | — |

## 3. iPhone ↔ Apple Watch

| Aspect | Value | Where |
|---|---|---|
| Transport | WatchConnectivity; dictionary messages (`WatchMessage`), additive keys only | `ios/BikeComputerWatch/*`, `WatchLink.swift` |
| Content | phone → watch ride mirror (state, owner, elapsed, distance, power, cadence, HR + source, zone, cue); watch → phone commands start / pause / resume / end / end‑confirm, live HR; the Watch writes the Health workout it ran | `BikeComputerApp.swift` (`r.onTick`, `w.onCommand`), `WorkoutManager.swift` |
| Ownership | same one‑owner rules as the phone buttons; the phone never exports a ride the Watch recorded | `ios/OWNERSHIP.md` |
| Status | IN CODE, builds/tests in every CI run (watch job), in TestFlight builds 121 → 199; **never tested on a physical Watch** (WATCH‑001/004) | trackers |

## 4. Devices ↔ external BLE sensors

- BikeComputer (central): see §1 last row — decoders host‑tested with 25+ vectors; never run on the board with the meter.
- iPhone (central, `BLESensors`): standard HR / Cycling Power / CSC decoders; `SensorHub` picks one reading per metric
  by source priority and quality (Board when recording → direct BLE → Watch per preference); stale > window never shown.
- Watch: central role **possible but untested** (one radio shared with the phone link); planned W2 measurement.
- ANT+: none.

## 5. Boundaries that keep the iPhone free to change

1. **Adapters, not business logic**: `DeviceLink` (board), `CyWatchLink/Coordinator` (LILYGO), `WatchLink` (Apple Watch),
   `BLESensors` — they produce plain values with source + time; `SensorHub`, `RideRecorder`, `Store` decide. UI never
   reads a device.
2. **Capability‑gated features**: a board feature is used only when its INFO cap bit is set; the LILYGO link drops frames of
   another `ver`. A new feature = new cap/version + both encoders kept.
3. **Honest absence**: TLV tags only when valid (board); explicit absent values (watch) — the app never has to guess.
4. **Contract tests** on both sides (firmware vectors asserted by iOS tests) catch any byte change.
5. Plan/coach algorithms change on the phone only; devices receive results (steps, bands, commands) — see
   `ios/INTEGRATION_ARCHITECTURE.md` on the iPhone branch for the full statement.
