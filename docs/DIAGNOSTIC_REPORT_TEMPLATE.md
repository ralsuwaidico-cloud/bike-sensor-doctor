# Bike Sensor Doctor — Diagnostic Report

| Field | Value |
|---|---|
| Date / time | |
| Phone | Nokia 5.3, Android 12, Bike Sensor Doctor v0.1.0 |
| Sensor | XDS-A001-9769, MAC C0:A1:25:07:97:69, model csc_sensor_01, HW V1.0, FW 1.0 |
| Bike / crank | |
| Session duration | |

## 1. Scan
- Devices seen: __
- XDS-like candidates (name / MAC / avg RSSI / advertised services): __
- Near/far RSSI test: at crank __ dBm, at 3 m __ dBm → identification: confirmed / not confirmed
- Does the device advertise 0x1818 or 0x1816? yes / no

## 2. Connection
- Connect result: READY / failed (error: __), attempts __, drops __, MTU __
- Battery: __ %   Device Information: __
- Services and characteristics (paste from Device tab or report):
  - 0x1828 contains 0x2A63? yes / no   contains 0x2A55? yes / no
  - a6ed0401 characteristics: __
  - a6ed0201 characteristics: __
- Characteristics successfully subscribed (✓sub): __
- Errors in log (INSUFFICIENT_AUTHENTICATION / 133 / timeouts): __

## 3. Data
- Total notifications in session: __
- Per characteristic (count / distinct payloads / 3 sample hex strings): __
- Verified standard metrics decoded: yes / no (power __ W, cadence __ rpm)
- Candidate (community layout) metrics: __

## 4. Guided test
- Stationary 30 s: __ notifications   Pedaling 30 s: __ notifications
- App verdict: __

## 5. Official app cross-check
- X-LAB Bikes installed: yes / no   Shows live power while pedaling: yes / no / not tried
- Any firmware/update/binding prompt shown by the app: __

## 6. Phase 2 experiment (only if attempted)
- "Community start command" sent: yes / no   Write result: success / 0x81 / other __
- Data after write: __

## 7. Conclusions
**Confirmed findings**
-

**Likely causes**
-

**Unresolved questions**
-

**Verified software-based fix available?** yes (describe) / no / unknown

## Attachments
- JSON log export: __
- CSV log export: __
- App-generated report text: __
- (Optional) HCI snoop log captured while X-LAB Bikes connected: __
