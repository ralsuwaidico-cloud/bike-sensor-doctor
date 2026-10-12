# PC Bluetooth probe for the XDS / Branta power meter

`xds_probe.py` connects to `XDS-A001-9769` directly from a PC (Windows/mac/Linux) using
[Bleak](https://github.com/hbldh/bleak). It is **read-only and safe** — it scans, connects,
discovers services, subscribes to notifications and logs raw bytes; it never writes to the sensor.

It exists to find the reliable connection sequence (free of Android's reconnect quirks) and to
confirm power/cadence decoding, then feed verified improvements back into the Android app.

## Run
```
python xds_probe.py
```
It self-installs `bleak` if needed, scans, runs a connection-strategy investigation and a
rapid-reconnect stress test, then captures a stationary phase and a pedaling phase (it prompts you).
Results are written to `Documents\bike_probe\xds_probe_<timestamp>.json` (Windows) or
`~/bike_probe/…` (mac/Linux) for exact analysis.

## What it tells us
- Whether the PC's Bluetooth connects first-try where the phone needed retries.
- The first-packet latency per strategy and whether rapid reconnects fail (the Android "error 133" pattern).
- Live cadence sign (forward vs backward) and whether watts rise under load.
