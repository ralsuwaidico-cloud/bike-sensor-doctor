# Firmware 0.7.2 — "the power meter connects but no power appears" (26 Oct 2026)

Owner's report on real hardware (board on 0.7.0/0.7.1): *the power meter connects to BikeComputer, but no power readings
appear*; the connection and pairing screens carry too much text and need scrolling to reach their buttons; the rider has to
troubleshoot too much himself. 0.7.2 fixes the data path, makes every sensor link report its real stage, repairs silent
links by itself, and turns the Connections pages into compact round-screen pages.

Status words used below: **simulator-verified** = proven by the PC harness or host tests; **needs hardware** = only the first
test on the board with the real XDS meter can confirm it. Nothing has been flashed.

## 1. Root cause (code evidence)

`main/ble_central.c` as of 0.7.1 (commit e728ffa):

```c
 99  if (err->status == 0 && dsc && ble_uuid_cmp(&dsc->uuid.u, BLE_UUID16_DECLARE(BLE_GATT_DSC_CLT_CFG_UUID16)) == 0) l->cccd = dsc->handle;
114  ble_gattc_disc_all_dscs(conn, l->val, l->svc_e, on_dsc, NULL);          /* from the 0x2A63 value handle to the SERVICE END */
 91  if (err->status == 0) { l->backoff_s = 1; s_connecting = NULL; set_state(l, PLAT_LINK_CONNECTED); ... }   /* "connected" */
274  if (!l || ev->notify_rx.attr_handle != l->val) return 0;                /* only 0x2A63 notifications are decoded */
```

- Descriptor discovery ran from the 0x2A63 value handle to the **end of service 0x1828**. NimBLE's
  `ble_gattc_disc_all_dscs` (ATT Find Information; `ble_gattc.c` `ble_gattc_disc_all_dscs_rx_idata`) reports **every**
  attribute in that range — the declarations, values and CCCDs of the characteristics that follow 0x2A63.
- `on_dsc` overwrote `l->cccd` for every 0x2902 it saw: **the last CCCD in the service won**.
- The XDS meter's 0x1828 table (docs/PORTING_SPEC.md §2, measured 2026-10-11/12): `0x2A63 (N)`, `0x2A65 (R)`, `0x2A5D (R)`,
  **`0x2A55 (W, I)`** — the control point is indicate-capable and therefore has its own CCCD, *after* 0x2A63. A Mesh-Proxy
  style table (`0x2A63`, then `0x2ADD`, `0x2ADE` notify + CCCD) fails the same way.
- So the board wrote `01 00` to the **control point's CCCD** (not to the control point itself — the 0x2A55 value was never
  written), got a successful write response, set the link to CONNECTED, and never received a single 0x2A63 packet. The
  Android app worked because `GattManager.enableAllNotifications()` subscribes every notify/indicate characteristic.
- The bug has been present since 0.2.0; power on the board had never been confirmed on hardware before the owner's test.

Reproduced on the host (`test/host/test_bc_pipe.c`, `test_cccd_choice`): with the XDS table the 0.7.1 logic picks CCCD
0x002A (0x2A55's), with the Mesh table 0x0018 (0x2ADE's); and in the simulator (scenario 20a): "CONNECTED", 0 power packets,
table shows NO DATA. **Simulator-verified.** Whether the real meter's handle layout matches the documented table: **needs
hardware** (the new log prints the handles, see §6).

## 2. Fixes

**Descriptor choice (bc_core `bc_gatt.c`, pure, host-tested).** The central now discovers *all characteristics* of the chosen
service, computes the data characteristic's own range (`bc_gatt_chr_end`: next characteristic declaration − 1), discovers
descriptors only in that range, and takes the CCCD with `bc_gatt_pick_cccd`, which additionally stops at the first
declaration (so even a too-wide range can never yield another characteristic's CCCD). Value written: `01 00` if the
characteristic notifies, `02 00` if it only indicates (`bc_gatt_cccd_value`). The CCCD is then **read back**
(`ble_gattc_read`); a different value is an error ("CCCD reads XX XX") and the link is retried. If the read itself fails the
write is trusted and logged as "read back n/a" — data arriving is the final proof.

**Which 0x2A63.** `bc_gatt_power_services`: XDS-named meters → 0x1828 first (proprietary 11-byte format, `bc_xds`), any
other meter → 0x1818 first (standard Cycling Power), the other one as fallback. The decoder follows the service the
characteristic was found in (`bc_gatt_power_format`). New `bc_cp.c`: SIG Cycling Power Measurement (flags, s16 power, skips
balance / torque / wheel data, crank revolutions → cadence, 0 rpm after 3 s without a crank event, no cadence at all when the
meter sends none, negative or > 3000 W rejected).

**XDS decoder re-verified byte for byte** against `app/.../core/XdsDecoder.kt`: offsets 0/2/4/6/8/10, u16 power, s16
left/right/cadence, u16 angle, u8 error; plausibility angle ≤ 359, |cadence| ≤ 250, power ≤ 3000; short = rejected
(`test_xds_reverify`, plus the 48 captured packets in `test_bc_xds.c`). Unchanged.

**HR (0x2A37) and CSC (0x2A5B) links** used the same code path and had the same bug (a strap with a later notifying
characteristic in 0x180D would have failed the same way). They now go through the same discovery → own-range CCCD →
read-back chain. Safety rule kept and tightened: the only write to any sensor is the CCCD enable on the data characteristic's
own CCCD; never 0x2A55, never a control point, no vendor characteristics, no bonding.

**Pipeline stages (`bc_pipe.c`).** Per link: NOT PAIRED · SEARCHING · CONNECTING · CONNECTED · SUBSCRIBED (CCCD written and read
back) · RECEIVING · VALID (decoded, plausible, ≤ 3 s old) · STALE · ERROR, with packets / rejected / last packet / last valid
/ last error. A link is OK only at VALID. Exposed through `plat_link_info_t` (`stage`, `err`, `unreadable`, `svc_uuid`, `cccd`,
`data_handle`, `resubscribes`, `auto_reconnects`). Serial: one `pipe` line per transition.

**Automatic recovery.** Subscribed + 0 packets for 8 s → rediscover + resubscribe (once); still nothing at 15 s → disconnect
and reconnect; all packets rejected for 10 s → hex of the first 3 packets logged once + "unreadable data"; stale > 10 s →
resubscribe; still stale at 25 s → reconnect. The reconnect back-off (1, 2, 4, 8, 16 s) is now reset only when **valid data**
flows (it used to reset on a bare subscribe), so a link that connects but never delivers backs off instead of looping.
A notification on any other handle is counted and logged once, never decoded.

**SENSOR_DIAG (Link 1.2.2, EVENT 0x40 / event_id 0x21).** `bc_link_encode_sensor_diag`; sent by `app_psvc` on every stage change,
every 5 s for a paired link below VALID, and once per paired sensor when the phone becomes ready. Vectors in
`BLE_LINK_PROTOCOL.md` (§ "1.2.2"), asserted byte for byte by the host test.

**LIVE ages.** `hr_age_ms` was always 0 and `cad_age_ms` copied the power age. Now: the real age of the HR shown (strap, or the
phone-relayed watch value since reception; watch HR older than 6 s is dropped) and of the cadence shown (meter or CSC).

**Device Health / serial HEALTH line.** Device Health starts with one line per sensor ("POWER  live 142 W 82 rpm",
"POWER  connected - no data", "POWER  reconnecting", "POWER  unreadable data", "POWER  error: no CCCD"). The 60 s serial HEALTH
line ends with `stage pw=VALID(pkts/rejected) hr=… csc=…`.

## 3. Round-screen UI, before → after

| page | 0.7.1 | 0.7.2 |
|---|---|---|
| Connections | 8 text rows + 3-line legend in a scroll list; "connected" with no data looked like success | live table: PHONE / POWER / HEART / CADENCE at scroll 0 (SPEED only with a CSC sensor), each row icon + fresh value ("142 W", "151 BPM", "82 RPM") or 1–2 words ("NO DATA", "SEARCHING", "RETRYING", "STALE", "BAD DATA", "PAIR"); Wi-Fi, Bluetooth, Sync below |
| Power meter / Heart rate / Cadence / Speed | a 12–15 line coloured paragraph; PAIR / RECONNECT / FORGET only after scrolling | one status line, one numbers line, ONE primary button (PAIR … / RETRY / TEST), HELP + HOLD: FORGET, Back — no scrolling |
| Help (new, per category) | — | the explanations, stage / packet / CCCD numbers, rare options (sensor test, pair another, HR source preference, wheel size) |
| Wi-Fi | toggle row, status, Networks / Saved rows and a 4-line note in a scroll list | status line, detail line, ONE primary (TURN ON / NETWORKS), SAVED · HELP · OFF, Back; notes and DISCONNECT on Help |
| Phone | already compact in 0.7.0 | unchanged; now covered by the visibility check |

New simulator check `btn_visible_at_top`: the primary action and Back must lie fully inside their parents, inside the round
glass, with no scrollable ancestor scrolled — asserted on Phone, Wi-Fi, Power, Heart rate, Cadence and Speed pages in four
states (phone on/off, meter paired/unpaired, CSC paired and away) — 24 states, all pass.

## 4. Tests (26 Oct 2026, this branch)

- Host: `make -C test/host` → test_bc_xds 228 checks, test_bc_core 1899, **test_bc_pipe 89** (descriptor-choice bug + fix,
  XDS re-verification, standard CP, stage machine, recovery timers on a fake clock, SENSOR_DIAG vectors) — 0 failures;
  `make lint` OK.
- Simulator: `make run` in test/sim → **283 screens, 0 issues; 455 functional checks, 0 failed**. New scenario 20 runs a fake
  GATT meter through the same bc_gatt / bc_pipe / bc_xds code as the device: (a) the 0.7.1 logic on the 2A63-then-2ADE table
  never gets a value; (b) the fix gets VALID 142 W 82 rpm and logs `SUBSCRIBED (cccd 0x0013 read back 01 00)` /
  `VALID 142 W`; XDS table: CCCD 0x0023, control-point CCCD 0x002A never written; (c) packets stop → STALE → automatic
  resubscribe → VALID, no reconnect; (d) all packets rejected → "unreadable data", hex once, table BAD DATA, Device Health
  line; (e) silent meter → resubscribe at 8 s, reconnect at ~15 s, growing back-off; (f) phone connects → SENSOR_DIAG per
  paired sensor, on changes, every 5 s below VALID; LIVE carries power/cadence with ages; (g) watch HR 151 → table, heart
  page and ride screen with WATCH, LIVE age, gone after 6 s; (h) primary + Back visibility on 24 page states.
- `idf.py build` (ESP-IDF 5.5.1) OK, PROJECT_VER 0.7.2, app 0x1b47c0 bytes (57 % of the slot free).
- Kit: `pc-kit/fw-v0.7.2/` — app SHA-256 `33b425022eb12ed7d4b55f343cb76c94ad6677864379112b08352eb36c779a60`.

## 5. What the simulator proves — and what only hardware can

Simulator-verified: the CCCD decision for the documented tables; the stage machine and every recovery timer; SENSOR_DIAG bytes
and emission rules; LIVE ages; the compact pages and their layout on the round glass; that a meter whose data arrives is shown
as live and one whose data does not is never shown as working.

Needs hardware: NimBLE's real callback order and timing; that the XDS meter's handles match PORTING_SPEC §2 (the log prints
them); that the meter streams after a CCCD write on 0x2A63's own CCCD (it did on the PC and on Android with the same write);
that the CCCD read-back returns `01 00` on this meter; behaviour of a non-XDS (standard 0x1818) meter; the HR strap / CSC sensor
paths on real devices; watts under load (accuracy is still unverified).

## 6. Reading the first hardware log (READ-LOG-v0.7.2.bat → device-log-v072-*.txt)

Good run, in order (`I (…) pipe:` lines):
```
pipe: power → SEARCHING / CONNECTING / CONNECTED
pipe: power: service 0x1828 0x0020..0x002A                    (handles will differ)
pipe: power: 0x2A63 value 0x0022, descriptors 0x0023..0x0023 (1), CCCD 0x0023
pipe: power → SUBSCRIBED (cccd 0x0023 read back 01 00; 0x2A63 in 0x1828)
pipe: power → VALID 142 W 82 rpm (pkts 2)
```
Trouble signs: `→ ERROR no CCCD` / `no 0x2A63` / `no service 0x1828` (table differs from the documented one — the log line
before shows what was found); `CCCD reads 00 00` (the meter refused the subscription); `subscribed, no packet in 8 s` then
`no data - reconnecting` (subscribed correctly but the meter is silent — pedal to wake it); `unreadable data` + three hex
lines (packets arrive but do not decode — send the hex); `notification on handle 0x…. ignored` (something else notifies).
The 60 s `HEALTH` line ends with `stage pw=VALID(120/0)` when all is well.

## 7. Compatibility

Profile text, ride history, NVS keys, phone bonds, Wi-Fi store and sensor pairings are untouched (no format change). Link
protocol: additive only (event_id 0x21; LIVE tags unchanged, ages now real). The installer accepts a board on 0.7.1, 0.7.0,
0.6.1, 0.6.0 rev 1–3, 0.5.0 or 0.4.0 and writes only the OTA selector and the app.
