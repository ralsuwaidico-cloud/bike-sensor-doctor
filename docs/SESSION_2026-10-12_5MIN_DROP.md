# The "5-minute disconnect" — root cause and fix (2026-10-12 ride logs)

Source: `log-20261012-173316-ride-end.json` and the 17:59 ride-end log from the Nokia.

## What happened
- Ride streamed perfectly for ~4 minutes: 2,119 packets, 17:27:13 → 17:31:10.
- Then: `Disconnected: GATT_SUCCESS`. Status **GATT_SUCCESS (0)** = a clean close initiated by the remote device,
  not an error-133 stack failure. **The XDS meter put itself to sleep and closed the link** — expected behaviour for
  a crank power meter when pedaling pauses (it re-advertises when the cranks move again, to save coin-cell battery).
- The app then tried to reconnect **49 times with `connectGatt(autoConnect=false)`, each timing out after 20 s, for 26
  minutes, never recovering.**

## Root cause (app bug)
A direct `connectGatt(autoConnect=false)` only succeeds while the peripheral is **actively advertising**. A sleeping
XDS is not advertising, so direct connects can never catch it and always time out. v0.3.1 used Android's
`autoConnect=true` (which waits in the background and latches when the device reappears) only for *initial* connection
failures — never for a mid-ride drop, because the reconnect decision short-circuited to "scheduled retry" once the
session had ever been READY.

## Fix (v0.5.0)
Mid-ride reconnects now go straight to **`autoConnect=true` (persistent background reconnect)**. The moment the meter
wakes and re-advertises (i.e. the rider pedals again), Android latches the connection automatically — no 20-second
timeouts, no giving up. The ride keeps running throughout the gap and resumes data on reconnect; ride history is never
discarded (confirmed: the first 6-minute segment saved correctly as avg 111 W even across the drop).

## What this is NOT
- Not error 133, not the phone's Bluetooth, not a teardown race (v0.3.1 fixed those — the connection was rock-solid
  for the 4 minutes it ran). It is the sensor's normal sleep behaviour plus the app using the wrong reconnect mode.
- We do not try to stop the sensor sleeping — that would require undocumented writes. Reconnect-on-wake is the correct,
  safe approach.

## Still to confirm on hardware
- A real ride with pedaling pauses: does the app re-latch and resume watts/cadence within a few seconds of pedaling
  resuming, with no 20-second stalls? (Do not claim fixed until this is observed.)
- Power under load still unverified (every logged segment was low/zero-load spinning).
