# iOS review of BLE_CONTRACT.md v1 (draft, "Link 1.3")

Reviewer: iOS agent, 27 Oct 2026. Contract author: firmware agent (owns the file; this review does not edit it).
Reviewed against: `ios/Shared/BCLink.swift`, `ios/BikeComputer/DeviceLink.swift`, `ios/BikeComputer/Diagnostics/*`
(Link 1.2.3 as shipped in the Cyclift release candidate) and `firmware/waveshare/components/bc_core/bc_link.c` @ a0af3d2.
Implementation on the iOS side: `ios/BikeComputer/Link13/` (branch `ios/phonefirst-dev`). No Link 1.3 encoder exists in the
firmware yet, so every iOS vector is a **contract vector** built by hand from this document, not a firmware vector.

## 1. What matches the shipped iOS code (verified, no change needed)

- §2 framing, TLV rules (unknown tags skipped, overrun rejects the whole message), 180-byte cap: identical to `BCLink.parse` / `Writer`.
- §3 shipped behaviour statements are correct: the RC app counts unknown Control types in `stats.rejected` and ignores them,
  ignores unknown LIVE tags, decodes Events by `event_id` (EVENT 0x23 with a 4-byte tag 03 is harmlessly skipped by the
  generic decoder: `w3` expects 2 bytes).
- §4 gating is implemented exactly as written: no APP_HELLO without INFO cap 0x0800; nothing new before HELLO_ACK; a
  feature is used only when its bit is in `enabled_caps` (masked again by what the app implements). A second, independent
  gate in `DeviceLink.sendLink13` refuses any Link 1.3 byte to a board without cap 0x0800.
- §6 RIDEQ_CHUNK_REQ / RIDEQ_CHUNK reuse DIAG_CHUNK's layout and 25-byte overhead: confirmed byte-for-byte (test
  `Link13CodecTests.testRideQueueVectors`).
- §7 STORAGE_STATUS with every field is 109 bytes; COACH_STATE with every field and a 24-byte text is ≤ 120 bytes; the
  largest COACH_PLAN part (part 0, 9 segments, 20-byte name) is 162 bytes: all inside 180.
- §8 DIAG_ACK `03 delete` as an optional trailing tag is compatible with 0.7.3 (unknown tag skipped). Without DIAG_AUTO
  enabled Cyclift sends the exact 1.2.3 bytes.

## 2. Changes / definitions needed (please decide and update the contract)

| # | Section | Issue | iOS proposal (what Cyclift implements today) |
|---|---|---|---|
| Q-iOS-1 | §6 RIDEQ_INFO `08 summary_crc32`, RIDEQ_ACK `03` | Not defined over which bytes. The phone cannot verify the summary otherwise. | CRC-32/ISO-HDLC over the **SYNC_RIDE TLV fields exactly as the board sends them** (every byte after the 8-byte header) for that ride. Cyclift stores this CRC for every SYNC_RIDE it receives and sends RIDEQ_ACK only when it equals `summary_crc32`. If the firmware chooses another definition, no ride is ever ACKed (safe, but storage never frees) — please confirm. |
| Q-iOS-2 | §6 samples file | Grammar is incomplete: per-field missing value, header line, line ending, what `-` means for the time axis. | Cyclift parses tolerantly: lines split on `\n` (`\r` ignored), blank and `#` lines skipped, a line `-` = one paused second (kept on the time axis, no values), a single field `-` = no value, out-of-range values dropped (never clamped). Please specify: is `distance_m` cumulative (Cyclift assumes yes); does the file include paused seconds (assumed yes); is there a header line. |
| Q-iOS-3 | §5.2 segment `u16 duration_s` | A free ride (coach on, no planned duration) has an open-ended main part; u16 has no "until the ride ends" value. | `0xFFFF` = open-ended (only ever the last segment). `total_duration_s` then counts it as 65535. Please adopt or define another marker. |
| Q-iOS-4 | §6 RIDEQ ids | RIDEQ uses `u32 ride_id`, SYNC_RIDE and LIVE use `u16`. | Confirm they are the same counter (Cyclift keys history by board id + ride id and merges RIDEQ samples with the SYNC_RIDE summary of the same id). |
| Q-iOS-5 | §6 RIDEQ_ACK reply | Only "RIDEQ_INFO with the new state" is defined. On a CRC mismatch the phone cannot tell "mismatch" from "lost reply". | Board answers a mismatching ACK with RIDEQ_ERR code 6 `crc mismatch` (new) and leaves the state unchanged. Cyclift treats a missing answer as "not confirmed" and asks again on the next list. |
| Q-iOS-6 | §6 demo rides | Demo rides are in the queue; Cyclift never imports demo data into the history, so it never ACKs them. | Who frees them? Proposal: the board's own retention, or STORAGE_CLEAN bit2 may remove demo rides. Cyclift shows them as "Demo ride — not imported". |
| Q-iOS-7 | §7 STORAGE_CLEAN_RESULT `2 refused: storage not OK` | "Not OK" would include state 1 `storage full` and 6 `reports full`, exactly when cleanup is needed. | Refuse only for 2/3/4/5 (filesystem unavailable, directory corrupted, write failed, diagnostics unavailable). Cyclift enables the button for OK / full / reports full and disables it (with the PC-procedure note) for the damaged states. |
| Q-iOS-8 | §7 status after cleanup | STORAGE_STATUS is pushed "on every change of `01`", not after bytes were freed. | Send STORAGE_STATUS after every STORAGE_CLEAN_RESULT. (Cyclift also requests it after the result.) |
| Q-iOS-9 | §8 DIAG_ACK `delete = 1` | Does the board still answer with DIAG_INFO state 1 before deleting? Cyclift uses that reply to mark "board acknowledged". | Yes: DIAG_INFO state 1, then delete. A later list simply no longer contains the report. |
| Q-iOS-10 | §5.3 `0B remaining_s` "at sender_time_ms" | The board cannot relate the phone's ms clock to its own. | Board uses the receive time; or drop the field (the board derives it from the plan + its own `elapsed_s`). Cyclift sends it from the same timeline. |
| Q-iOS-11 | §5.3 `09 interval_index` | Not stated whether it is the plan's segment index. | Cyclift sends the plan segment index (warm-up = 0) and `interval_count` = number of plan segments, so the board can cross-check with its stored plan. |
| Q-iOS-12 | §5.3 seq | "Ignores older" — is an equal seq a duplicate? | Cyclift increments seq on every send (also keepalives and echo-lag resends), so the question never arises; please state "seq strictly greater is applied". |
| Q-iOS-13 | §5.4 / §4 | A ride recorded by the **phone alone** (phone-only mode) runs on the phone clock, not the board's. | Cyclift does not mirror the coach then (no plan, COACH_END if one was sent). Please confirm the board shows nothing / its own screens. |
| Q-iOS-14 | §4 HELLO timing | No timeout defined. | Cyclift waits 4 s, sends one more APP_HELLO, then stays on Link 1.2.3 behaviour for that connection. |

## 3. Answers to §10

1. **Coach state cadence** — on change + 5 s keepalive is enough. The AdaptationEngine works between sessions (check-ins,
   completed rides), not live. The live ride coach runs on the phone at 1 Hz and its cue gate holds a cue ≥ 15 s, so changes
   are rare. Cyclift additionally resends when LIVE `11 coach_seq` lags > 3 s.
2. **%FTP vs absolute watts** — absolute watts, as drafted. Cyclift sends power targets only when the FTP is the rider's own
   (entered / tested / from rides) and sets flag bit1; with the onboarding FTP assumption it sends the rider's heart-rate
   zone in bpm (`target_kind 2`), and with neither it sends `target_kind 0` (ride by feel). Note for the lead: the phone
   coach itself treats all power as unverified (`PowerTrust.meterVerified = false`) and coaches on heart rate when there is
   a strap; the board will still show the watts range of the same zone. Decide whether the board should show HR targets
   whenever the phone coach uses HR.
3. **Samples format** — text is fine for the phone (CRC-verified, ~40 KB/h). Please complete the grammar (Q-iOS-2).
4. **Strength never goes to the board** — confirmed. Cyclift mirrors only cycling sessions (and a free Zone-2 ride on
   other days when the coach is on); strength, mobility and rest days send no plan.

## 4. Behaviour Cyclift guarantees (for the firmware's test plan)

- With a board without cap 0x0800 (0.7.3 / RC pairing): no APP_HELLO, no 0x08/0x90–0x96/0xA0–0xA3/0xB0–0xB3 byte, DIAG_ACK
  without tag 03. Unit-tested (`Link13CodecTests.testSessionGate`, `DiagTransferTests.testAckCarriesDeleteOnlyWithDiagAuto`).
- RIDEQ_ACK only after: samples size + CRC verified on the stored file, the ride saved in Cyclift's history (store written to
  disk without error), and `summary_crc32` verified. `delete_samples = 1` then. Demo, recording (state 0), and conflicting
  rides (same id, other CRC already on the phone) are never ACKed. A ride already on the phone is never pulled twice.
- STORAGE_CLEAN_REQ carries only bits 0–2 and is sent only after the rider confirms a dialog that lists what stays.
- COACH_PLAN is resent on every new connection (the board keeps it in RAM only); a new `workout_id` is used whenever the
  segments change; COACH_END once per workout.

## 5. Round 2 — contract v1.1/v1.2 and the firmware fixture (27 Oct 2026)

All 14 answers adopted in Cyclift (`ios/phonefirst-dev`): summary CRC over SYNC_RIDE bytes 8…end, 0xFFFF open-ended last
segment, RIDEQ_ERR 6 (ACK not confirmed → ride kept, shown), cleanup allowed for 0/1/6 only, samples grammar (`J1` header
skipped, `-1` = no data, `-` = paused second, cumulative distance, torn last line ignored), RAM-only rides (bit4) imported
first and shown as at risk, duplicate check also on `start_epoch_s` (v1.2 residual). Lead decision: when the phone coach
coaches on heart rate (power unverified) the board gets the same heart-rate targets.

Firmware fixture `link13_fw_fixture.json` (30 entries) cross-checked in `Link13FirmwareFixtureTests`: every board → phone
vector decodes and re-encodes byte-identically, every phone → board vector is produced byte-identically by Cyclift, the
SYNC_RIDE of ride 23 re-encodes byte-identically and its CRC equals `summary_crc32`, and the ride-queue engine fed the
firmware's bytes sends exactly the firmware's RIDEQ_ACK. Notes for the firmware agent:
- `coach_state_keepalive` (id + seq only): `bc_cm_state` replaces the whole stored state, so applying it would blank the
  board's targets. Cyclift never sends that form; its keepalive is the full state with a newer seq. Suggest the contract
  says so (or the board merges only the tags present).
- LIVE `15 bt_flags` is left out when 0 — fine ("absent = none"), noted only because §4 lists it as always sent.
