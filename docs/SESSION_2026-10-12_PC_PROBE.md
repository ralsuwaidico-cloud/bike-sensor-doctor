# PC Bluetooth probe findings (2026-10-12) and the connection fix

Run on the user's Windows PC with Bleak, directly against XDS-A001-9769. Raw log:
`Documents\bike_probe\xds_probe_20261012_135329.json`.

## Decisive result: the sensor is reliable; the failures were Android-side
- **8 of 8 connection attempts succeeded** (strategies A/B/C + 5 stress cycles). The one strategy with an
  error still *connected* — it hit a transient Windows "Operation aborted" during notify setup, not a sensor refusal.
- **Rapid-reconnect stress: 5 of 5 succeeded.** First ~9 s (sensor waking), then 291/295/319/313 ms. First data
  packet ~1.3 s after connect once warm.
- So the Nokia's "three failed attempts" is NOT the sensor. It is Android connection handling.

## Why the phone failed (root cause)
This meter accepts **one connection at a time**. The PC could not even see it in the first scan until the phone's
Bluetooth was turned off — the phone was holding it. The same mechanism causes the phone's own failures: if a prior
GATT client is not fully closed, or two app components both try to hold the link, the sensor is still "taken" and the
next `connectGatt` fails with the classic error-133 pattern.

## Fixes applied to the Android app (v0.3.1)
In `ble/GattManager.kt`:
1. **Full teardown before every (re)connect**: `refresh()` the GATT cache, `disconnect()`, `close()`, then a **700 ms
   settle delay** before `connectGatt`. Reconnecting too soon after close is the main error-133 trigger.
2. **Stale-callback rejection**: every GATT callback is ignored (and the old client closed) when it is not the current
   `gatt` instance, so events from a previous attempt can't corrupt a new one.
3. **autoConnect fallback**: a direct attempt first (fast); if it never reaches READY, one `autoConnect=true` attempt
   (which the Android stack retries in the background and which succeeds on many error-133-prone devices); then
   scheduled retry with exponential back-off.
4. **Decision logic extracted** to pure, unit-tested `core/ConnectionPolicy.kt` (STOP / TRY_AUTOCONNECT /
   SCHEDULE_RETRY) with regression tests for repeated failure, timeout→fallback, and drop-after-ready.
5. Single centralized owner (`SensorManager` + one `GattManager`) already prevents overlapping scans/clients.

## Decoding confirmed
- Forward pedaling → **positive** cadence (8→39→58→72→76 rpm as the user sped up). The earlier all-negative values
  were backward hand-pedaling. The app's "backwards" flag is therefore correct, not an inverted unit.
- Power stayed **0 W even at 76 rpm** — expected, because the bike was stationary (no load). Still unverified under load.
- Data flows on 0x2A63 at 1 Hz with **no start command** (CCCD subscribe only). Battery 50% (was 91% on 2026-10-11).

## Still open
- **Watts under load**: needs a real ride or a turbo trainer with resistance. 0 W unloaded is not a fault.
