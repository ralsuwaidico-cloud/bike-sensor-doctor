# BikeComputer diagnostic report transfer — iPhone side (Link 1.2.3)

Spec: `docs/LINK_V1_2_SPEC.md` § "1.2.3 — diagnostic report transfer" (firmware 0.7.3, cap `0x400 DIAG_XFER`).
The phone pulls; the board never pushes report data. Older firmware (no cap) never receives a request and the app shows
nothing for it.

## Files

| file | what |
|---|---|
| `BikeComputer/Diagnostics/BCLinkDiag.swift` | codec: encode `DIAG_LIST_REQ 0x80`, `DIAG_CHUNK_REQ 0x83`, `DIAG_ACK 0x85`; decode `DIAG_INFO 0x81`, `DIAG_LIST_END 0x82`, `DIAG_CHUNK 0x84`, `DIAG_ERR 0x86`, `EVENT 0x40 / 0x22 diag_ready`; test encoders for the board side; `CRC32` (IEEE) |
| `BikeComputer/Diagnostics/DiagTransfer.swift` | the transfer engine — pure, synchronous, clock and transport injected |
| `BikeComputer/Diagnostics/DiagStore.swift` | files on disk, partials, dedupe, rider deletion |
| `BikeComputer/Diagnostics/DiagReportCenter.swift` | app glue (DeviceLink ↔ engine, 4 Hz clock only while working), export entries, the disabled upload hook |
| `BikeComputer/Diagnostics/DiagReportViews.swift` | Connections section, report list, text viewer with Share / Delete, Home crash banner |
| `DeviceLink.swift` | routes 0x81/0x82/0x84/0x86 from Control and diag_ready (Events **or** Control) to `onDiagMessage`; `sendDiag` (only with the cap); `onLinkDown` |
| `BikeComputerTests/DiagTransferTests.swift` | codec vectors + engine tests against a fake board |

## Engine rules

1. **Start**: 3 s after the link is Ready with cap 0x400 (connect-time traffic goes first), and on every `diag_ready`.
   A `diag_ready` during a transfer lists again when the current one ends.
2. **List**: `DIAG_LIST_REQ` → collect `DIAG_INFO` until `DIAG_LIST_END`.
3. **Queue**: reports with `state 0` (pending), oldest `report_id` first, that are not on this phone. Dedupe key =
   (board id from INFO tag 07, report_id). A report already saved here (or deleted here by the rider — a tombstone
   meta stays) is never pulled again; if the board still lists it as pending, the phone sends `DIAG_ACK` again with the
   stored crc. Reports with `state 1` that are not on this phone are not pulled.
4. **Pull**: `DIAG_CHUNK_REQ(report_id, offset, max_len 160)` one at a time. Each chunk is appended to
   `<id>.part` on disk immediately, so the resume point after a disconnect, a board restart or an app restart is the
   partial's length. A partial whose size/crc differ from the current DIAG_INFO is discarded (restart at 0).
   Late or duplicate chunks (offset ≠ expected) are ignored.
5. **Verify**: when `offset == size`, crc32 (IEEE) of the whole file. Match → move to `<id>.txt`, write meta, then
   `DIAG_ACK(report_id, crc)`. **The ACK is sent only after the crc matched.** The board's `DIAG_INFO state 1` reply marks
   the meta `boardAcknowledged`; if it is lost, the next list re-acknowledges.
6. **Mismatch** (also: more data than `size`, `last` before `size`, `DIAG_ERR 2`): delete the partial, restart from 0,
   up to 3 times; after that the report is left on the board for this app session (`lastError` explains).
7. **DIAG_ERR**: 1 unknown id → drop partial, next report · 2 bad offset → as 6 · 3 storage read error → same offset
   again after 2 s, up to 3 times, then keep the partial and move on (resumes next connection) · 4 busy → same request
   after 10 s, no limit · other codes → as 3. During listing: busy → list again after 10 s; others → after 2 s, 3 times.
8. **Timeouts**: 5 s per request, 3 retries of the same request; after a chunk timeout the phone asks for 128-byte
   chunks for the rest of that connection (see integrator note 1). After the 3rd retry the session pauses; the partial
   stays and the next connect / `diag_ready` resumes it.
9. **Rides**: never blocks recording. While a ride is active, at most one `DIAG_CHUNK_REQ` per second (throttled
   requests are scheduled, not dropped); without a ride, back-to-back.
10. **Disconnect**: `linkDown()` clears the in-memory session only.

## Storage

`Application Support/Diagnostics/<board-id>/` with the board id's `:` replaced by `-`:
`<report_id>.txt` (verified report), `<report_id>.json` (meta: size, crc, created, kind, summary, firmware, received,
acknowledged, seen, deletedByUser), `<report_id>.part` + `.part.json` while transferring. Default backup behaviour.
Nothing is deleted automatically. The rider deletes a report from the list (swipe) or the viewer; the text goes, the
meta stays as a tombstone so it is never downloaded again.

## UI

- Connections › BikeComputer and Connections › Diagnostics: section "BikeComputer diagnostic reports" — only when
  the board has the cap or reports are saved. While transferring: **Diagnostic report ready** + progress. After a
  save in this session: **Report saved** + "Kind · firmware · created · size" and the board's summary line. Link to
  the report list.
- Report list (newest first, "new" dot, swipe to delete) → full text viewer (monospaced, selectable) with **Share**
  (system share sheet with the `.txt` file — to Claude, mail, Files, …) and **Delete** (confirmation).
- Home: ONE banner "BikeComputer crashed earlier — report saved" while a crash report (kind 1) is unseen; opening it
  or the ✕ clears it. Nothing on the Ride screen.
- "Export diagnostic report" JSON: new `boardReports` list — id, kind, firmware, created, received, size, crc32,
  summary, acknowledged. Never the text, never the board address; the export is scrubbed as before.
- Upload: `DiagUploadHook` exists only as a hook — `ReleaseFlags.diagUploadEnabled = false` hides the consent toggle,
  consent defaults to off, and `upload` returns false without any network call in this build.

## Notes for the integrator (cross-check with firmware/waveshare/docs/BLE_LINK_PROTOCOL.md)

1. **Size conflict in the spec**: a full DIAG_CHUNK with 160 data bytes is 8 + 6 + 6 + 162 + 3 = **185 bytes**, above
   `BCLink.maxMessage` 180 and above the 182-byte notify payload of the usual iOS MTU 185. The spec also says
   `max_len ≤ 180 − overhead` (= 155). The phone sends `max_len 160` as instructed, accepts any shorter chunk, and its
   parser takes messages up to 512 bytes. The firmware should clamp the data to what fits (≤ 155 at MTU 185); if
   it does not and a notify is dropped, the phone's timeout fallback asks for 128 bytes.
2. Phone-built vectors (seq as shown, t_ms 0) in `DiagTransferTests.swift`:
   - `DIAG_LIST_REQ` seq 1: `80 00 01 00 00 00 00 00`
   - `DIAG_CHUNK_REQ` id 7, offset 320, max_len 160, seq 2: `83 00 02 00 00 00 00 00 01 04 07 00 00 00 02 04 40 01 00 00 03 02 A0 00`
   - `DIAG_ACK` id 7, crc 0xCBF43926, seq 3: `85 00 03 00 00 00 00 00 01 04 07 00 00 00 02 04 26 39 F4 CB`
   - `DIAG_INFO` id 7, size 4096, crc 0xCBF43926, created 1792850100, kind 1, state 0, "panic in nimble_host", "0.7.3", seq 10:
     `81 00 0A 00 00 00 00 00 01 04 07 00 00 00 02 04 00 10 00 00 03 04 26 39 F4 CB 04 04 B4 B8 DC 6A 05 01 01 06 01 00 07 14 70 61 6E 69 63 20 69 6E 20 6E 69 6D 62 6C 65 5F 68 6F 73 74 08 05 30 2E 37 2E 33`
   - `DIAG_LIST_END` count 2, pending 1: `82 00 0B 00 00 00 00 00 01 01 02 02 01 01`
   - `DIAG_CHUNK` id 7, offset 0, "[header]\n", last 0: `84 00 0C 00 00 00 00 00 01 04 07 00 00 00 02 04 00 00 00 00 03 09 5B 68 65 61 64 65 72 5D 0A 04 01 00`
   - `DIAG_ERR` id 7, code 4: `86 00 0E 00 00 00 00 00 01 04 07 00 00 00 02 01 04`
   - `diag_ready` pending 1, newest 7, seq 15: `40 00 0F 00 00 00 00 00 01 01 22 02 01 01 03 04 07 00 00 00`
   - crc32("123456789") = `0xCBF43926` (zlib / IEEE 802.3).
   The firmware's own vectors should be added as a `DiagFirmwareVectorTests` like `SensorDiagFirmwareVectorTests`.
3. The phone accepts `diag_ready` on the Events characteristic (like SENSOR_DIAG) **and** on Control (the 1.2.3 table
   says all messages travel on Control).
4. Required fields: DIAG_INFO needs tags 01/02/03, DIAG_CHUNK 01/02/03, DIAG_ERR 02; otherwise the message is ignored.
   summary ≤ 40 B and firmware ≤ 16 B — longer values are skipped (not truncated).
5. The phone sends `DIAG_ACK` again for a report it already holds whenever a list shows it pending.
