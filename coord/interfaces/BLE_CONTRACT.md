# Cyclift ↔ BikeComputer — phone-first architecture and BLE data contract

**Version: contract v1 (draft) = BikeComputer Link 1.3.** Author: firmware agent, 27 Oct 2026. Review: iOS agent, QA.
Status: **DRAFT — nothing in section 4–8 is implemented yet** (firmware FW-4, iOS IOS-1). Sections 2–3 describe what is
shipped today (Link 1.2.3, firmware 0.7.3 / Cyclift RC1) and must keep working unchanged.
Owner's goal: *Cyclift is the brain, BikeComputer the reliable cycling companion.*

---

## 1. Who does what

| Concern | Cyclift (iPhone) — authoritative | BikeComputer (ESP32-S3) — companion |
|---|---|---|
| Athlete profile, FTP, zones | master copy, edits, history of changes | last synced copy in NVS (706 B today) for offline rides |
| Training plans, adaptive decisions, substitutions | **all** (coach engine, AdaptationEngine, CoachSafety) | none — receives the current workout as data (§5) |
| Active workout definition | owner; sends the plan + live coach state | stores the plan in RAM for this ride; follows it offline (§5.4) |
| Live sensors | Apple Watch HR, phone GPS speed/distance | power meter, cadence, HR strap, CSC (BLE central); integrates distance from phone speed |
| Live display | big-screen dashboard | 240×240 round screen, every existing layout A/B/C + coach overlay |
| Ride start / pause / end | may request (CTRL_REQ, two-step stop) | **owns the ride state machine and clock** (elapsed time = timeline for both) |
| Ride history, cycling + strength history, analytics | **all**, long-term, cloud when enabled | offline queue only until verified transfer (§6); last few summaries for the Results screen |
| Diagnostics | stores every report, shows them, (cloud only if the owner enables it) | small bounded store: core dump partition + 32 KB event ring + ≤ 12 reports; deletes only after a verified ACK |
| Storage management | storage screen + "safe cleanup" button (§7) | reports measured status; deletes only verified-synced items; never repairs/formats on its own |

Rules that do not change:
* The board must stay fully usable without the phone (sensors, recording, coach plan already received).
* Never claim a heart-rate source that is not live: Apple Watch HR exists on the board **only** as phone-relayed `IN_HR` with
  `src = 4` received ≤ 6 s ago. Phone link lost → the board shows "HR —  (watch via phone: lost)", never the last value.
* Never silently discard an unsynchronised ride or an unsent crash report (both sides).
* No large text, no AI responses to the board: structured codes + ≤ 24-byte strings only.

## 2. Transport (unchanged since Link 1.2)

Service `B1CE0000-7E3A-4C55-9D2B-5A0E1C7C0000`; characteristics `…0002` Info (read), `…0003` Live (read/notify, 1 Hz),
`…0004` Input (write / write-without-response), `…0005` Control (read/write/notify), `…0006` Sync (read/write/notify),
`…0007` Events (read/notify). Encrypted + authenticated (LE SC, passkey) for every characteristic. ATT MTU ≥ 185 requested
by the phone; a message is ≤ 180 B. Framing: `type u8 | flags u8 (0) | seq u16 | sender_time_ms u32` + TLV fields
`tag u8 | len u8 | value`. Little-endian. **Unknown tags are skipped; a field running past the end rejects the whole message.**
Full reference: `firmware/waveshare/docs/BLE_LINK_PROTOCOL.md` + `components/bc_core/bc_link.c` (host-tested vectors).

## 3. Shipped messages (Link ≤ 1.2.3) — must stay byte-compatible

| Type | Name | Dir / char | Since |
|---|---|---|---|
| 0x01 | INFO (ver, fw, caps, max_msg, device_id) | B→P read Info | 1.0 / 1.2 |
| 0x10 | LIVE (power, cadence, HR+src+age, ride state/id/elapsed/distance, cue_id, battery, meter link, demo) | B→P Live | 1.0 / 1.2.2 ages |
| 0x20–0x24 | IN_TIME, IN_GPS, IN_HR, IN_WEATHER, IN_BATTERY | P→B Input | 1.0 |
| 0x30/0x31 | CTRL_REQ / CTRL_RESP (start, pause, resume, stop request/confirm) | Control | 1.0 |
| 0x40 | EVENT: 0x10 battery_notice (off), 0x20 link_diag, 0x21 sensor_diag, 0x22 diag_ready | B→P Events | 1.2–1.2.3 |
| 0x50–0x52 | SYNC_REQ / SYNC_RIDE / SYNC_END (ride summaries) | Sync | 1.1 |
| 0x60–0x66 | WIFI_* provisioning | Control | 1.2 |
| 0x70–0x73 | PROFILE_GET/SET/PROFILE/ACK | Control | 1.2 / 1.2.1 hello |
| 0x74–0x76 | SETTINGS_SET/SETTINGS/GET | Control | 1.2 |
| 0x80–0x86 | DIAG_LIST_REQ, DIAG_INFO, DIAG_LIST_END, DIAG_CHUNK_REQ, DIAG_CHUNK, DIAG_ACK, DIAG_ERR | Control | 1.2.3 |

INFO caps today: 0x01 LIVE · 0x02 GPS_IN · 0x04 HR_IN · 0x08 WEATHER_IN · 0x10 RIDE_CTRL · 0x20 TIME_SYNC · 0x40 RIDE_SYNC ·
0x80 WIFI_PROV · 0x100 PROFILE_SYNC · 0x200 SETTINGS · 0x400 DIAG_XFER.

Observed behaviour both sides rely on (verified in code, 27 Oct): the shipped Cyclift drops unknown Control types
(`stats.rejected`), ignores unknown LIVE tags, decodes Events by `event_id`; firmware 0.7.3 ignores unknown Control types
(the ATT write still succeeds).

## 4. Versioning, negotiation, backward compatibility (Link 1.3)

New INFO caps (board → phone):

| Cap | Meaning |
|---|---|
| 0x0800 HELLO | the board understands APP_HELLO |
| 0x1000 COACH | COACH_PLAN / COACH_STATE (§5) |
| 0x2000 RIDE_QUEUE | RIDEQ_* (§6) |
| 0x4000 STORAGE | STORAGE_STATUS / STORAGE_CLEAN (§7) |
| 0x8000 DIAG_AUTO | diag retention + DIAG_ACK `03 delete` (§8) |

**APP_HELLO 0x08** (phone → board, Control, write-with-response), sent once per encrypted connection, only if INFO has 0x0800:
`01 u8 link_major (1)` `02 u8 link_minor (3)` `03 u32 app_caps` (same bit values as above, meaning "the app implements it")
`04 str app_version (≤ 16 B)`.
**HELLO_ACK 0x09** (board → phone, Control): `01 u32 enabled_caps` = INFO caps ∧ app_caps.

The board sends **no** new board-initiated message (§5–§8: COACH_PLAN_ACK, RIDEQ events, STORAGE_STATUS, new EVENT ids)
before a HELLO enabling it on the current connection. New LIVE tags (below) are always sent (old apps skip them).

| Pairing | Behaviour |
|---|---|
| Cyclift RC1 (≤ 1.2.3) + board 1.3 | exactly today's behaviour; extra LIVE tags ignored; SYNC + DIAG unchanged |
| Cyclift 1.3 + board 0.7.3 (no cap 0x0800) | app does not send HELLO / COACH / RIDEQ / STORAGE; uses SYNC_RIDE + DIAG; shows "update BikeComputer for coach mirroring" |
| Cyclift 1.3 + board 1.3 | HELLO → enabled caps → everything below |

New LIVE tags (board → phone, 1 Hz; absent = unknown/none):
`11 u16 coach_seq` (last applied COACH_STATE seq) · `12 u8 coach_mode` (0 none, 1 following phone, 2 phone lost → board follows
the stored plan, 3 phone lost → holding last targets, no plan) · `13 u8 storage_state` (bc_stor_state_t, present only when not
OK) · `14 u8 rides_unsynced` · `15 u8 bt_flags` (bit0 sensors disabled after a crash, bit1 phone link degraded).

## 5. Coach mirroring (cap COACH)

One authoritative workout **definition** (the plan) + live **state** from the phone. Segment boundaries are defined on the
board's ride timeline (LIVE `0A elapsed_s`), so both devices derive the same interval from the same numbers.

### 5.1 Enumerations
* `workout_type u8`: 0 free ride, 1 recovery, 2 endurance, 3 tempo, 4 sweet spot, 5 threshold, 6 VO2max, 7 anaerobic,
  8 sprint, 9 FTP test, 10 race/event, 11 warm-up, 12 cool-down, 13 custom.
* `target_kind u8`: 0 none (ride by feel), 1 power W range, 2 heart-rate bpm range, 3 cadence only, 4 RPE (1–10 in lo/hi).
* `instruction u8` (the board renders its own fixed text; ≤ 24 chars): 0 none, 1 ON TARGET, 2 MORE POWER, 3 LESS POWER,
  4 CADENCE UP, 5 CADENCE DOWN, 6 HOLD STEADY, 7 GET READY (interval change ≤ 10 s), 8 EASY / RECOVER, 9 GO!, 10 COOL DOWN,
  11 HR HIGH – EASE OFF, 12 DRINK / FUEL, 13 PAUSED, 14 WORKOUT DONE, 15 NO DATA (sensor lost), 16 TARGET CHANGED.
  Unknown codes → the board shows the `text` field if present, else nothing.
* `hr_src u8` = `bc_src_t` (2 board strap, 4 Apple Watch via phone, 6 phone strap): which HR the phone's coach used.

### 5.2 COACH_PLAN 0xB0 (phone → board, Control, write-with-response), multi-part
`01 u32 workout_id` · `02 u16 part` · `03 u16 parts` · `04 u16 first_segment` · `05 bytes segments` (n × 10 B; n ≤ 14,
n ≤ 9 in part 0 so the message stays ≤ 180 B) ·
part 0 only: `06 str name (≤ 20 B)` `07 u16 total_segments (≤ 64)` `08 u32 total_duration_s` `09 u32 plan_crc32`
(CRC-32/ISO-HDLC of all segment bytes in order) `0A u32 t0_elapsed_s` (board `elapsed_s` at which segment 0 starts; 0xFFFFFFFF =
"starts when the ride starts").
Segment, 10 bytes: `u16 duration_s` `u8 workout_type` `u8 target_kind` `u16 lo` `u16 hi` `u8 cad_lo` `u8 cad_hi` (0 = no cadence
target).
**COACH_PLAN_ACK 0xB1** (board → phone, Control): `01 u32 workout_id` `02 u8 status` (0 complete + CRC OK, stored · 1 part
received, waiting · 2 too many segments · 3 CRC mismatch, send again · 4 busy) `03 u16 next_part`.
A new workout_id replaces the stored plan; the board keeps one plan in RAM (≤ 640 B), never in flash.

### 5.3 COACH_STATE 0xB2 (phone → board, Control, write-with-response) — on every change + every 5 s while a workout runs
`01 u32 workout_id` · `02 u16 seq` (monotonic per workout; the board ignores older) · `03 u8 workout_type` · `04 u8 target_kind`
· `05 u16 target_lo` · `06 u16 target_hi` · `07 u8 cad_lo` · `08 u8 cad_hi` · `09 u16 interval_index` · `0A u16 interval_count`
· `0B u16 remaining_s` (at `sender_time_ms`) · `0C u16 interval_duration_s` · `0D u8 next_type` · `0E u8 next_target_kind` ·
`0F u16 next_lo` · `10 u16 next_hi` · `11 u16 next_duration_s` · `12 u8 instruction` · `13 str text (≤ 24 B UTF-8, optional,
cut at a character boundary)` · `14 u8 session_state` (0 not started, 1 running, 2 paused, 3 finished, 4 abandoned) ·
`15 u8 hr_src` · `16 u8 zone` (1–7 power / 1–5 HR, 0 none) · `17 u8 flags` (bit0 targets changed by adaptation now,
bit1 targets are %FTP-derived from the board profile FTP, bit2 Apple Watch HR live on the phone).
Size: ≤ 8 + 23 fields ≈ 110 B. The board echoes `seq` in LIVE `11`; the phone resends if the echo lags > 3 s.
Example screen (round 240×240, any layout, coach overlay): `CYCLIFT COACH / ENDURANCE / POWER 145 W / TARGET 140–155 W /
CADENCE 84 / TARGET 80–90 / ON TARGET / NEXT: RECOVERY – 3 MIN`.

**COACH_END 0xB3** (phone → board): `01 u32 workout_id` `02 u8 reason` (0 completed, 1 stopped by rider, 2 replaced).

### 5.4 Offline behaviour (board)
* Phone link lost while a plan is stored → `coach_mode 2`: the board advances through the stored segments on its own ride
  timeline, shows the targets of the current segment, "PHONE LOST", and the countdown. No adaptation happens offline.
* No plan stored → `coach_mode 3`: keep the last COACH_STATE targets, labelled "LAST TARGET", no countdown beyond the interval.
* HR-based targets: if the HR source was Apple Watch (via phone) the board has no HR → instruction "NO HR – RIDE BY FEEL"
  (power/cadence targets still shown); never shows a stale HR.
* Reconnect: the phone sends HELLO, then COACH_STATE (authoritative); the board adopts it immediately (`coach_mode 1`).
  The phone reconstructs what happened offline from LIVE elapsed time + the ride queue (§6).

## 6. Offline ride queue (cap RIDE_QUEUE)

A ride on the board = its summary (today's SYNC_RIDE content) + the per-second samples file (`rides/r####.txt`, text lines
`power cadence hr distance_m`, "-" = paused second; ~7–12 B/s → ~40 KB/hour). Queue states: 0 recording · 1 closed,
unsynced · 2 transfer in progress · 3 verified on the phone · 4 samples deleted (summary kept, ≤ 50 summaries).

* **RIDEQ_LIST_REQ 0x90** (P→B Control): no fields.
* **RIDEQ_INFO 0x91** (B→P Control, one per ride): `01 u32 ride_id` `02 u8 state` `03 u32 samples_size` `04 u32 samples_crc32`
  `05 u32 start_epoch_s (0 unknown)` `06 u32 duration_s` `07 u8 flags` (bit0 demo, bit1 recovered after a crash, bit2 samples
  truncated (storage full), bit3 summary only) `08 u32 summary_crc32`.
* **RIDEQ_LIST_END 0x92**: `01 u16 count` `02 u16 unsynced` `03 u32 unsynced_bytes`.
* **RIDEQ_CHUNK_REQ 0x93** / **RIDEQ_CHUNK 0x94**: byte-identical layout and size rule to DIAG_CHUNK_REQ / DIAG_CHUNK
  (1.2.3: `01 u32 id` `02 u32 offset` `03 u16 max_len` / `01 u32 id` `02 u32 offset` `03 data` `04 u8 last`; data =
  min(max_len, 155, (ATT_MTU − 3) − 25)); ≤ 4 outstanding; LIVE has priority; **BUSY (err 4) while a ride is recording**.
* **RIDEQ_ACK 0x95** (P→B): `01 u32 ride_id` `02 u32 samples_crc32` `03 u32 summary_crc32` `04 u8 delete_samples (0/1)`.
  The board marks state 3 only if both CRCs match its own; it deletes the samples only then and only if `delete_samples = 1`.
  Reply: RIDEQ_INFO with the new state.
* **RIDEQ_ERR 0x96**: codes as DIAG_ERR (1 unknown id, 2 bad offset, 3 storage read error, 4 busy, 5 MTU too small).
* **EVENT 0x40 / event_id 0x23 rides_pending** (B→P Events, after HELLO): `02 u8 unsynced` `03 u32 newest ride_id`; sent on every
  connection and whenever a ride closes.
* The phone stores the ride (Cyclift history, HealthKit/cloud per its own settings) **before** sending RIDEQ_ACK.
* The board never deletes a state-1/2 ride. Storage full during a ride → samples stop (flag bit2), the summary is always
  kept (NVS-sized), and the screen says "STORAGE FULL – SUMMARY ONLY".
* SYNC_REQ (1.1) keeps working for old apps (summaries only).

## 7. Storage status and safe cleanup (cap STORAGE)

* **STORAGE_STATUS_REQ 0xA0** (P→B Control): no fields.
* **STORAGE_STATUS 0xA1** (B→P Control; also after HELLO and on every change of `01`): `01 u8 state` (bc_stor_state_t:
  0 OK, 1 storage full, 2 filesystem unavailable, 3 directory corrupted, 4 write failed, 5 diagnostics unavailable,
  6 reports full (unsent), 7 not checked) `02 str code` (`ok`, `full`, `fs_unavailable`, `dir_corrupted`, `write_failed`,
  `diag_unavailable`, `diag_full`, `not_checked`) `03 u32 fs_total_kb` `04 u32 fs_free_kb` `05 u8 crash_partition`
  (0 missing, 1 empty, 2 dump stored, 3 dump unreadable) `06 u32 crash_dump_bytes` `07 u16 reports_stored`
  `08 u16 reports_unsent` `09 u32 diag_bytes` `0A u16 rides_unsynced` `0B u32 ride_bytes_unsynced` `0C u32 ride_bytes_synced`
  `0D u32 app_slot_kb` `0E u32 app_used_kb` `0F u16 nvs_used_entries` `10 u16 nvs_free_entries` `11 u16 root_free_slots`
  `12 u16 root_bad_entries` `13 u8 health` (0 good, 1 degraded, 2 failed).
  Cyclift's storage screen = firmware storage (`0D/0E`), diagnostic storage (`07–09`, `05–06`), offline rides (`0A–0C`),
  free space (`04`), health (`13` + `01/02`).
* **STORAGE_CLEAN_REQ 0xA2** (P→B): `01 u8 what` (bit0 ACKed reports + their core copies, bit1 samples of verified rides,
  bit2 caches/duplicates such as `diag/report.txt`). **STORAGE_CLEAN_RESULT 0xA3**: `01 u8 status` (0 done, 1 nothing to do,
  2 refused: storage not OK, 3 busy: ride recording) `02 u32 bytes_freed` `03 u16 items`.
  Never deletable by any command: unsynced rides, unsent reports, the crash dump partition before its report is ACKed,
  NVS (settings, pairings, bonds, ride id counter). A damaged filesystem is **not** repaired over BLE: that is an
  owner-approved PC procedure (`coord/reports/FW_STORAGE_MEMORY_REPORT.md` §7).

## 8. Diagnostics (cap DIAG_XFER unchanged; DIAG_AUTO adds retention)

* Transfer: Link 1.2.3 unchanged (phone-driven pull, CRC-verified ACK; `diag_ready` event on every connection). Cyclift with
  DIAG_AUTO pulls automatically after HELLO when `pending > 0` and no ride is recording.
* **DIAG_ACK 0x85** gains optional `03 u8 delete (0/1)` — 1: the board may delete the report (and `diag/core-<id>.elf`) now
  instead of waiting for room. Old firmware skips the tag.
* Board retention (firmware): ≤ 12 reports / 96 KB; ACKed reports are deleted oldest-first when room is needed or after
  `delete = 1`; an **unsent** report is never deleted; the crash-dump partition is erased only after its report is stored
  and the raw dump copied (0.7.4-dev). Event ring 32 KB fixed, written ≤ once per 10 s.

## 9. Message map (Link 1.3 additions)

| Type | Name | Dir | Char | Gate |
|---|---|---|---|---|
| 0x08 / 0x09 | APP_HELLO / HELLO_ACK | P→B / B→P | Control | cap 0x0800 |
| 0x90–0x96 | RIDEQ_* | both | Control | cap 0x2000 + HELLO |
| 0xA0–0xA3 | STORAGE_* | both | Control | cap 0x4000 + HELLO |
| 0xB0–0xB3 | COACH_PLAN / PLAN_ACK / STATE / END | both | Control | cap 0x1000 + HELLO |
| 0x40 / 0x23 | EVENT rides_pending | B→P | Events | HELLO |
| LIVE 11–15 | coach_seq, coach_mode, storage_state, rides_unsynced, bt_flags | B→P | Live | always (ignored by old apps) |

Test vectors: to be generated by `bc_link` encoders in firmware FW-4 and committed as a fixture shared with
`ios/BikeComputerTests` (same pattern as `diag_fw_fixture.json`). Until then this document is the reference.

## 10. Open questions for the iOS review

1. Coach state cadence: 5 s keepalive + on change — enough for the phone's AdaptationEngine, or does it need 1 Hz?
2. Should COACH_PLAN carry %FTP targets (board converts with its profile FTP) or always absolute watts? Draft: absolute,
   flag bit1 for display only.
3. Ride samples format: keep the board's text lines (simple, ~40 KB/h) or a compact binary (≈ 8 B/s)? Draft: text, CRC-verified.
4. Strength workouts never go to the board (cycling only) — confirm.
