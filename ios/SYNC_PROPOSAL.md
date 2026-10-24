# Ride history sync — protocol proposal (BikeComputer Link v1.1, Phase 5)

Status: **proposal for the firmware** (24 Oct 2026). Firmware 0.4.0/0.5.0 declare the Sync characteristic
(`B1CE0006…`) but answer empty and do not set caps bit `RIDE_SYNC` (0x40). The iPhone app 0.3.1 already contains the
client side (`Shared/BCLink.swift`: `encodeSyncRequest`, `decodeSyncRide`, `decodeSyncEnd`; `DeviceLink.startSync`),
**gated on `INFO.caps & 0x40`**. Until the board advertises that bit, the app shows "sync coming" and never invents
rides. Unit tests in `BikeComputerTests/BCLinkTests.swift` (`testSyncRideRoundTrip`) are the conformance vectors.

## Goal
Pull the board's finished rides (its `history.txt` lines, `R1`/`R2`, i.e. `bc_ride_summary_t`) into the phone so
Progress shows every ride, including those recorded while the phone was away. The board stays the owner of those
rides: the phone stores them as `recorder = board`, keyed by **board id + start time**, and attaches its own 1 Hz
mirror (GPS track, samples) when it has one. A ride is never stored twice.

## Changes on the board
1. **INFO** gets tag `07 u8[6] device_id` = the board's public BLE address (`esp_read_mac` BT). Lets every phone key
   rides by board, without relying on the per-phone CoreBluetooth identifier. Set caps bit `0x40 RIDE_SYNC`.
2. **Sync characteristic** `0006` (encrypted, read/write/notify):
   - phone writes **SYNC_REQ 0x50**: `01 u16 after_ride_id` (0 = from the oldest), `02 u8 max_count` (1…50).
   - board notifies one **SYNC_RIDE 0x51** per ride with `id > after_ride_id`, oldest first, at most `max_count`,
     one notification per ride (≤ 180 bytes, fits one ATT MTU 185 packet):

     | tag | type | field (bc_ride_summary_t) | note |
     |---|---|---|---|
     | 01 | u16 | id | required |
     | 02 | u8 | flags | bit0 demo, bit1 recovered |
     | 03 | u32 | duration_s | |
     | 04 | u32 | paused_s | |
     | 05–09 | s16 | avg_power, max_power, avg_cad, avg_hr, max_hr | −1 = no data |
     | 0A–0C | u32 | power_s, cad_s, hr_s | seconds with data |
     | 0D | u32[7] (28 B) | zone_s | present only when zones_valid |
     | 0E | s16 | ftp_w | FTP in force during the ride |
     | 0F | u8 | ftp_how | |
     | 10 | s16 | kj | −1 = none |
     | 11 | s16 | best20 | −1 = none |
     | 12 | s8 | inband_pct | −1 = never judged |
     | 13 | u16 | ftp_new | 0 = none |
     | 14 | u8 | ftp_suggested_only | |
     | 15 | u32 | distance_m | |
     | 16 | u8 | dist_src | bc_src_t, 0 = none |
     | 17 | u32 | start_epoch_s | 0 = clock unknown during that ride |
     | 18 | str | coach | first 60 bytes of the coach text (UTF-8, cut at a character boundary) |

     Unknown tags are skipped by the phone as everywhere else, so fields can be added later.
   - after the batch the board notifies **SYNC_END 0x52**: `01 u16 count` (sent now), `02 u16 total` (rides on the
     board), `03 u8 more` (1 = call again with `after_ride_id` = last id sent).
   - A SYNC_REQ while a batch is in flight cancels the batch and starts the new one. A read of the characteristic
     returns the last SYNC_END (cheap "how many rides do you have").
3. **Pacing**: one notification per 20 ms is enough (NimBLE queues; iOS handles ~50 notifications/s); 100 rides ≈ 2 s.
   Firmware reads `history.txt` line by line (`bc_summary_from_line`) and encodes with the existing `bc_link` writer
   (`bc_link_w_*`), so no new storage format is needed.
4. **Events characteristic** `0007`: unchanged (still reserved). Optional later: `EVENT 0x40 01 u8 kind=1 (ride saved)
   02 u16 ride_id` so the phone requests the new ride immediately after the board saves one.

## Phone behaviour (implemented, inactive until RIDE_SYNC)
- On `ready` with `hasRideSync`: subscribe to Sync notifications, write SYNC_REQ(after = highest board id already
  stored for this board, 50). Repeat while `more`.
- Each SYNC_RIDE → `Store.importBoardRide(summary, boardId)`:
  - key = `boardId + start_epoch_s` when start_epoch_s > 0, else `boardId + ride id`;
  - a phone-mirror record for the same board ride (same `boardRideId`, start within 10 min) is **merged**: the
    board's totals win, the phone's samples/GPS stay; otherwise a new `recorder = board` record is added;
  - `demo` rides are dropped; rides with duration < 60 s are stored but hidden by default.
- Nothing from a SYNC message is ever displayed as live data.

## Open points for the firmware author
- Keep `history.txt` order (oldest first) and ids monotonic; after a factory reset ids restart at 1 — the phone keys on
  `device_id + start_epoch_s`, so duplicates are still avoided when the clock was known.
- Rides with `start_epoch_s = 0` (board never saw a phone during the ride) can only be keyed by id; the phone shows
  the date as "unknown" and sorts them by id.
