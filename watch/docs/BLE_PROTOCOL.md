# Cyclift wearable protocol v1 (watch ⇄ iPhone; BikeComputer where appropriate)

Transport: BLE GATT, watch = peripheral. Service `CYW` (128-bit UUID to be assigned in W2), characteristics `TX`
(notify, watch → phone), `RX` (write-without-response, phone → watch). MTU 247 → payload ≤ 240 B per frame; larger
messages (today's plan) are chunked with a sequence.

Frame (`firmware/src/domain/sync.hpp`): `[ver u8][type u8][seq u16][len u16][payload][crc16-CCITT u16]`. A frame with
another version is refused (never half-read). Types: Hello 0x01 · TimeSync 0x02 · Status 0x03 · PlanToday 0x10 · Cached
0x11 · Live 0x20 · Gps 0x21 · Coach 0x22 · Event 0x30 · Ack 0x31 · Error 0x7F.

Identity and idempotency: the watch has a `deviceId` (chip MAC) and a monotonic `seq` persisted in LittleFS; every
Event carries `(deviceId, seq, watchUnixS, kind, workoutId, a, b, c, manual)`. The phone's filter processes each
`(deviceId, seq)` once (out-of-order safe), and acknowledges cumulatively; the watch resends everything unacknowledged
after a reconnect. Ownership: the phone owns workouts, the plan and Apple Health (one workout per ride/session, written
once — the existing iPhone rule); the watch owns its events until acknowledged and preserves them offline (bounded
queue with an explicit overflow warning).

Clock: TimeSync carries unix seconds + ms and the time-zone offset; the watch records drift between syncs and shows the
age of the last sync on the face. Live and Gps carry the measurement age; the watch shows "GPS 12 s" and greys stale
values; it never interpolates recorded data (display smoothing only).

Coach messages: id, instruction, reason, priority (info / advice / action / urgent), context, target, expiry, requires
action, confidence, safety. The watch shows one primary message (priority → safety → recency), urgent/safety cues
vibrate; offline rules are marked `local` and never presented as AI.

BikeComputer: the same frame format is intended for the board's ride-step/target protocol (separate branch, approved
for development, flashing not approved); the board remains the ride recorder when it is connected — one recorder per
ride.
