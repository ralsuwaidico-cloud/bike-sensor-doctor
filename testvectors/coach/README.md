# Coach test vectors (shared Android ↔ ESP32)

One file per scenario. Lines starting with `#` are metadata; the rest are ticks.

```
# name: <scenario id>
# config: key=value ...     keys: mode ftp maxHr cadence(on|off) cadLow cadHigh source(AUTO|HR|POWER)
#                           hrHoldMs powerHoldMs surgeHoldMs cadHoldMs minAlertMs sameRepeatMs keepRepeatMs smoothingMs
# t_ms,phase,cad,hr,pw,expect
```
- `phase`: WARMUP | MAIN | RECOVERY | COOLDOWN (what the Session model reports for that tick).
- `cad`, `hr`, `pw`: integer or blank (= unavailable/stale). `pw=0` is a valid coasting reading.
- `expect`: a CueType (`EASE_OFF`, `PUSH_HARDER`, `PEDAL_FASTER`, `PEDAL_SLOWER`, `KEEP_IT_UP`, `RECOVER`,
  `WARMUP`, `COOLDOWN`, `NO_HR`, `NO_POWER`), `NONE` (engine must be silent on this tick), or blank (not asserted).
- Ticks must be in increasing time. The engine is fed every listed tick in order; it is NOT fed intermediate
  seconds, so write a tick for every second where the smoothing window matters.

A port passes when every asserted tick in every file matches. Defaults (if a key is absent): mode=ZONE2 ftp=200
maxHr=185 cadence=on cadLow=85 cadHigh=95 source=AUTO hrHoldMs=8000 powerHoldMs=2000 surgeHoldMs=6000
cadHoldMs=5000 minAlertMs=10000 sameRepeatMs=45000 keepRepeatMs=90000 keepHoldMs=5000 smoothingMs=5000.
