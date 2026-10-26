# Firmware 0.7.0 — the consolidated release (26 Oct 2026)

0.7.0 = 0.6.1 + pairing lifecycle repair + profile-sync hardening + the compact PHONE screen. Paired with iPhone app 0.8.0
(Link protocol v1.2 with the 1.2.1 additions below; both sides share docs/LINK_V1_2_SPEC.md). Nothing here is
hardware-verified until Rashed runs `pc-kit/TEST-v0.7.0.txt`; what the simulator proves is listed at the end.

## 1. Audit of everything requested so far (before writing a line)
| Requirement | State before 0.7.0 | Evidence | 0.7.0 |
|---|---|---|---|
| Power states: display off / standby keep BLE, XDS, recording, coaching; deep sleep explicit and default off | **complete** (0.6.0 rev 1, HW-6) | sim scenario 14; link enabled at boot from the profile | unchanged |
| Wake gate: any-touch wake, waking gesture swallowed, 400 ms guard, watchdog, controller check after wake, SAFE MODE | **complete** (0.6.1, HW-8) — simulator reproduces the 0.6.0 freeze and the fix | sim scenario 18 (event-mode reads, 20 cycles) | unchanged |
| Hold-to-start (1 s) + hold for end / delete / forget / restart / deep sleep; plain taps never start a ride | **complete** (0.6.0 rev 3) | sim scenario 17, host `t_gate_hold` | unchanged |
| Connections system (8 categories, badges, red ! only for configured things missing, direct / via phone / cloud tags) | **complete** (0.6.0 rev 2) | sim scenario 16, WORDS check (no "Sensors" anywhere) | Phone row gains "! repair needed" |
| Wi-Fi page + hotspot fixes + phone provisioning (cap 0x80) | **complete** in software (0.6.0); hotspot discovery hardware-only | sim scenarios 11, 15 | unchanged |
| Profile sync (cap 0x100) | **partial**: version rule and persistence worked, but out-of-range values were silently dropped, no last-sync time, no PROFILE on connect, no sync-state wording | app_psvc.c `profile_apply`, codec `decode_profile` | hardened (section 3) |
| Settings sync (cap 0x200) with supported_mask | **complete** (0.6.0) | sim scenario 15 | unchanged |
| Ride-history sync (cap 0x40) | **complete** (0.6.0), bytes match the Swift vectors | sim scenario 15, host `t_link3` | unchanged |
| Quick Settings handle (tap or swipe), PRESS_LOCK fix | **complete** (0.6.0 rev 3) | sim scenario 13 | unchanged |
| Settings layout audit (circle / overflow / overlap checks on every page) | **complete** (0.6.1) | sim sweep 7b: 80 screens, 0 issues | PHONE + Details pages added to the sweep |
| Pairing after a board data reset / forget | **broken** on the real devices (HW-9) | Rashed: "Peer removed pairing information", app stuck on Connecting | fixed (section 2) |
| PHONE screen: compact, one primary action, no scrolling | **missing** (0.6.x page was a long text + 4 buttons) | ui_phone.c | rewritten (section 4) |
| Diagnostics for disconnect reason / bonding / auth / sync | **missing** (only "phone disconnected (0x13)") | ble_link.c gap_cb | added (section 5) |
| Charging alerts, battery hardware | not feasible / deferred (HW-1, HW-7) | CHARGE_ALERTS.md | unchanged, still "not verified safe" |

## 2. Root cause of the pairing failure (HW-9) — from the code, to be confirmed by the serial log
- The board advertised with its **fixed public Bluetooth address** (`ble_hs_id_infer_auto` → public, ble_central.c `on_sync`).
- `plat_phone_forget()` (HOLD: FORGET PHONE), a restored backup or any NVS wipe removed the board's copy of the bond
  (`ble_store_clear()`), but the iPhone kept its LTK for that address.
- On the next connection iOS asked to encrypt with the old key; NimBLE, holding no key for that peer, answered
  "PIN or key missing" (HCI 0x06, NimBLE status 0x206). iOS reports exactly this as **"Peer removed pairing information"**
  and, because it still considers the device paired, it does not start a new pairing — so the app sat on "Connecting…"
  while the board's page honestly said PHONE LINK: ON (it was advertising and the phone kept connecting and failing).
- 0.6.x had no way out other than iPhone Settings › Bluetooth › Forget This Device, which nothing told the rider.

## 3. What 0.7.0 changes
### Pairing lifecycle (ble_link.c)
1. **Random static identity address**, generated on first boot and stored in NVS (`link/idaddr`, `link/idgen`); applied with
   `ble_hs_id_set_rnd` before advertising; both roles (peripheral to the phone, central to the sensors) use
   `BLE_OWN_ADDR_RANDOM`. `plat_device_id` (INFO tag 07) stays the factory BT MAC so the phone's records stay keyed to the
   same board.
2. **Every forget / repair takes a new identity** (gen + 1): the iPhone sees a brand-new device and simply pairs again with
   the 6-digit code — no stale-key dead end. Forget/repair run on the BLE task (`do_repair` from `ble_link_tick`): stop
   advertising, drop the connection, `ble_store_clear`, new address, advertise.
3. **Repeat pairing** (the phone forgot us, we remember it): the stale bond for that peer is deleted and pairing retried
   (`BLE_GAP_REPEAT_PAIRING_RETRY`), as before but now logged and counted.
4. **Encryption failure** (status ≠ 0, e.g. 0x206 key missing, 0x205 authentication failed): state **REPAIR NEEDED**
   (`PLAT_PHONE_REPAIR`), reason code kept, `enc_fails` counted; the state survives the phone dropping the link and clears
   on the next good encryption. The PHONE screen offers one action: **HOLD: REPAIR** = forget + new identity + advertise.
5. Advertising: unchanged content (Link service UUID + name), restarts after every disconnect / reset / standby change, and
   never starts while a repair is pending; the 0.6.0 rules (link enabled at boot, standby keeps advertising at ~1 s,
   deep sleep is the only state without the link) are untouched.
6. iOS background reconnection: the phone keeps a pending connect to the remembered peripheral; with 0.7.0 the identifier
   changes after a repair, so the app must re-discover by service UUID/name and accept the new identifier for the same
   `device_id` (noted in LINK_V1_2_SPEC.md 1.2.1 for the iOS side).
### Profile sync (app_psvc.c, bc_link.c)
- Whole-message validation; any out-of-range field → `PROFILE_ACK status 2` and nothing changes (the codec now flags
  out-of-range tags in `bc_profile_msg_t.invalid` instead of dropping them silently).
- `prof_sync_epoch` (new profile key) = time the last SET was applied → "synced hh:mm" in the phone's local time.
- Sync state for the UI and the diag event: device-only / synced / pending (phone connected, nothing applied yet) / failed.
- PROFILE "hello" on connect (encrypted + subscribed) so the phone can compare at once; LINK_DIAG event once per connection.
- Standalone → paired reconciliation unchanged (version 0 = device-only; the phone's first SET wins after the rider confirms
  in the app); rides, journal, sensor pairings, Wi-Fi store and phone bonds are never touched by a SET.
### PHONE screen (ui_phone.c)
Title PHONE · status line (CONNECTED iPhone / SEARCHING / CONNECTING / PAIRING / REPAIR NEEDED / LINK OFF, coloured) · ONE
primary button by state (CONNECT / TURN OFF / DISCONNECT / HOLD: REPAIR) · rows "Profile sync" (device only / pending /
synced hh:mm / failed) and "Phone link" (ON/OFF, tap toggles) · a hint line · "<". Nothing scrolls. Tapping the status,
the sync row or the hint opens **PHONE DETAILS**: diagnostics (state, phones remembered, last link end + code, encryption
fails, identity + gen, profile/settings versions, last sync, data counters), how to pair, how to repair (incl. the iPhone
Settings › Bluetooth › Forget step), HR preference, HOLD: FORGET PHONE. The passkey pop-up is unchanged.
### Diagnostics
Serial `link`: identity on boot; every connect (peer address type, bonds, interval, identity gen), disconnect (reason code
+ plain words), encryption ON/FAILED with the status and its meaning, subscribe changes, repeat pairing, repair; `PROFILE
synced from phone vN` / `PROFILE_SET vN rejected: value out of range`. Device Health: "Phone link" line with state, bonds,
identity gen, last link end + code, encryption fails, sync state. Events characteristic: LINK_DIAG once per connection.

## 4. Tests (all passing)
- Host (`test/host`): **1899 checks, 0 failures** (+ XDS 228/0; lint OK). New: codec `invalid` flags (FTP 0xFFFF, rest HR 160),
  LINK_DIAG vector.
- Simulator (`test/sim`): **251 screens, 0 issues; 418 functional checks, 0 failed**. New scenario 19: remembered phone
  reconnects → hello PROFILE + LINK_DIAG; PHONE screen states; forget → identity gen +1 → phone with old keys sees a new
  device → passkey pairing; stale keys with unchanged identity → REPAIR NEEDED (0x206) → Connections "! repair needed" →
  HOLD: REPAIR → new identity → pair again; history / meter pairing / profile untouched; PROFILE_SET with FTP 999 and with
  rest HR ≥ max HR rejected (status 2, nothing changed, row "failed"); valid SET applied with "synced hh:mm"; restart keeps
  version, values and last-sync time, PROFILE after restart reports the same version; standalone (v0) board reconciled on
  the first SET; Phone link row toggles LINK OFF / CONNECT. Scenarios 12 and 16 updated to the new page; the layout sweep
  covers the PHONE and PHONE DETAILS pages (0 issues).
- `idf.py build` OK (IDF 5.5.1): app 1 777 536 B (0x1b1f80), 58 % of the slot free.

## 5. Hardware-only (cannot be proven by the simulator)
Random-static identity on the real NimBLE controller (both roles); iOS re-pairing after an identity change; REPEAT_PAIRING
and the 0x206 path with a real iPhone; reconnect timing after app restart / board restart / out of range; LINK_DIAG and the
hello PROFILE against app 0.8.0; last-sync time display in local time; everything in 0.6.1's touch/wake list; hotspot
discovery; CSC sensors; standby / screen-off current. The combined checklist is `pc-kit/TEST-v0.7.0.txt`.

## 6. Kit
`pc-kit/fw-v0.7.0/` (app `1d4dd740d5a86516b79d16a23df1d5cb6155f3007ff71823dc928d82082a6c67`; bootloader / partitions /
otadata identical to 0.5.0–0.6.1, so only 0xf000 + 0x20000 are written), `INSTALL-v0.7.0.{ps1,bat}` (the pre-install backup
may hold 0.6.1, 0.6.0 rev 1/2/3, 0.5.0 or 0.4.0), `RESTORE-BACKUP-BEFORE-v070.{ps1,bat}`, `ROLLBACK-TO-v050` unchanged,
`TEST-v0.7.0.txt`. Not flashed. Battery: HW-1 unchanged — USB charging with the 500 mAh cell is still not verified safe.

## 0.7.1 (26 Oct 2026) — brand-neutral labels for Cyclift
Same as 0.7.0 except two on-screen labels: the unpaired power-meter row reads "Bluetooth power meter" (was "XDS / Branta
meter") and the source name of the board's power-meter link reads "POWER METER" (was "XDS"). The meter link already accepts
any standard Cycling Power (0x1818) device; the name-prefix match for meters that do not advertise the service UUID stays
as a compatibility shim, not a default. Protocol unchanged (1.2.1, source id 1 unchanged). Host 1899/0, simulator 251
screens / 0 issues, 418 checks / 0 failed, idf.py build OK. App hash 63ace07e…; bootloader/partitions/otadata unchanged →
INSTALL-v0.7.1 writes only 0xf000 + 0x20000. Not flashed.
