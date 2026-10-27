# Firmware 0.7.3 — stability + diagnostics (26 Oct 2026, not flashed)

0.7.3 answers the 0.7.2 crash loop (SAFE MODE, "3 crashes in a row, crash (panic)"). The crash itself has **not** been
reproduced without the board (docs/CRASH_0.7.2.md); 0.7.3 fixes every defect the investigation found and makes the next crash
— if there is one — leave its own evidence. No unrelated features.

Status words: **host/simulator-tested** = proven by the PC tests below; **needs hardware** = only the board can confirm it.

## 1. Fixes (docs/CRASH_0.7.2.md §8)

* **One task owns the Bluetooth links** (`main/ble_central.c`). The sensor manager (scan decisions, re-subscribe, reconnect,
  stuck-connect handling), the phone-link tick, the MTU fallback and pairing changes run on the NimBLE host task, in order with
  the GATT/GAP callbacks; the `ble_mgr` task, the esp_timer and the UI only post NimBLE events or set flags. GATT callbacks carry
  the link slot + a discovery generation, so answers to a replaced discovery or a previous connection are ignored; a
  re-subscribe never starts while a discovery is in flight; 20 s set-up timeout. *Host-tested (fake NimBLE, ASan/UBSan/TSan).*
* **No NimBLE call inside a spinlock**: `count_bonds()` (it takes the NimBLE host lock) was called with interrupts masked at
  every phone connect/disconnect since 0.7.0. *Host-tested (invariant counter 2000 → 0).*
* **Stacks**: NimBLE host task 4096 → 7168 B, esp_timer 3584 → 4608 B, `ble_mgr` 4096 → 3072 B (it only paces now). Log calls
  cost 1.5 KB instead of 2.1 KB of stack (new log hook). Stack high-water marks of taskLVGL, nimble_host, ble_mgr, esp_timer and
  main are in the 60 s health line and the event log (alert below 512 B).
* `app_psvc_on_disconnect` and the UI's phone on/off/disconnect/standby requests are applied on their owning task; the 60 s
  health line reads app state under the LVGL lock.
* Logs no longer contain the board's full Bluetooth identity, IP addresses or sensor names (they now end up in reports).
* Kept and re-verified: the 0.7.2 power-meter CCCD fix (own descriptor range, `01 00` only, read back) and the real LIVE ages.

## 2. Crash evidence that survives the reset

* **Core dump to flash** (ESP-IDF ELF format, CRC32) in a new 64 KB `coredump` partition taken from the unused second app slot —
  proof in docs/PARTITIONS_0.7.3.md. At the next start the summary (task, PC, exception cause/address, panic reason, 16
  backtrace addresses) goes into a crash report; the raw dump is kept as `diag/core-<id>.elf` on the FAT for offline decoding
  (`espcoredump.py` / `addr2line` with the 0.7.3 ELF, matched by the ELF SHA-256 printed in the report); the partition is then
  erased for the next crash.
* **Last 2 KB of log lines in RTC memory** (survives a panic/watchdog reset), privacy-filtered, copied into the crash report.
* **Persistent event log** `diag/events.bin`: 1024 × 32-byte records, each with its own CRC-32, written at most once per 10 s in
  batches (at once for a crash or report), torn records are skipped after a power loss. Records: reset reason + crash streak +
  boot mode, crashes, start-up stages, sensor pipeline stages, automatic recoveries (re-subscribe / reconnect / RETRY /
  disabled), phone states, Wi-Fi states, heap (free + minimum ever) and stack head-room every minute, last valid readings every
  30 s with their ages (power, cadence, HR + source), LIVE forwarding per minute, touch/screen counters, threshold alerts.
  (FAT, not NVS: NVS is 24 KB and also holds the profile, Wi-Fi networks and phone bonds.)
* **Reports** (`diag/r<id>.txt`, immutable, CRC-32): crash (kind 1) at the start after a crash, recovery session (2) after a
  staged boot, manual (3) on SEND LOGS. Sections `[header] [reset] [panic] [backtrace] [tasks] [heap] [events] [sensors]
  [phone] [wifi] [recovery]`; no names, no e-mail, no Wi-Fi names or passwords, no locations, Bluetooth addresses as last 2
  bytes. Max 12 reports / 96 KB; an unsent report is never deleted to make room.
* **Transfer to Cyclift**: Link 1.2.3 exactly as `docs/LINK_V1_2_SPEC.md` "1.2.3" (cap 0x400, messages 0x80–0x86, EVENT
  0x22 diag_ready); byte vectors and board behaviour in `docs/BLE_LINK_PROTOCOL.md`. Note for the phone: chunks carry at most
  **155** data bytes (the message must fit 180 bytes); continue at `offset + len` of the received chunk.
* Wi-Fi upload: only a **disabled hook** (`app_diag_upload_hook`, `APP_DIAG_UPLOAD_ENABLED 0`) — it returns false and does
  nothing. The owner has not authorized any server: no endpoint, no network call.

## 3. RECOVERY MODE and the staged boot (replaces SAFE MODE)

`bc_boot` (pure, host-tested) decides each start from RTC memory: 3 crash resets in a row → **RECOVERY MODE**: only display,
touch, NVS and storage run (no Bluetooth, no Wi-Fi, no sensors), the round screen shows *RECOVERY MODE / Crash detected /
"panic - nimble_host"*, **RESTART & DIAGNOSE** (hold 1 s) and **SEND LOGS**, and a status line (*Logs saved / Waiting for
Cyclift / Sent to Cyclift*). SEND LOGS starts only the phone link. RESTART & DIAGNOSE makes the next start a **staged boot**:
display → storage → phone link → Wi-Fi → sensor central → each sensor link, one at a time, with a marker in RTC memory before
each and time to run (phone 10 s, Wi-Fi 8 s, central 3 s, power meter 25 s, strap/CSC 15 s). If a crash recurs, the marker
names the subsystem and the next start skips it ("Power meter disabled after a crash - RETRY"; Connections row DISABLED, its
page offers RETRY) instead of looping; three crashed staged boots → back to RECOVERY MODE. A disabled subsystem stays
disabled across power cycles (NVS) until RETRY or a different firmware. Nothing erases rides, profile, bonds or logs.
*Simulator-tested (scenario 21); needs hardware for the real screens and timings.*

## 4. Health monitoring

Continuous (app task, every 250 ms; written ≤ 1 / 10 s): sensor link stages and automatic recoveries, a paired sensor stuck
below VALID > 60 s (alert), valid power/cadence/HR readings with ages, phone state and LIVE forwarding (alert when the phone
listens but nothing is sent for 5 s), Apple-Watch HR via the phone going stale (alert), free/minimum heap (alerts < 24 KB /
< 12 KB) and stack head-room (alert < 512 B), touch/screen counters, resets and crashes. The automatic recoveries that already
existed (pipeline re-subscribe/reconnect, Wi-Fi off on low RAM) are recorded.

## 5. Tests (all automated, results of this build)

| Test | Result |
|---|---|
| Host unit tests, ASan + UBSan (`test/host`, `make`) | (27 Oct final: **diag 162**, total **2441 checks, 0 failed**, + fixture check) — 26 Oct: xds 228, core 1899, pipe 89, **diag 124** (CRC, record/ring incl. torn record + wrap + resume + batching, index + never-delete-unsent, report sections + privacy, 1.2.3 vectors, server incl. interrupted transfer resume + pipelining + all errors + 20 000-message fuzz, boot modes), **partitions 63** — **2403 checks, 0 failed**; `make lint` OK |
| PC harness `test/sim` (`make run`) and the same with ASan + UBSan (`make run-asan`) | (27 Oct final: **291 screens 0 issues, 509 checks 0 failed**, both, incl. scenario 23) — 26 Oct: **289 screens 0 issues, 489 checks 0 failed** (both). New scenario 21: three crashes → RECOVERY screen (layout + circle checks), report contents + privacy, SEND LOGS (phone link only), diag_ready, LIST, pull interrupted after 5 chunks and resumed, crc ACK → "Sent to Cyclift", RESTART & DIAGNOSE (1 s hold) → staged boot → power meter disabled → DISABLED row + RETRY → enabled, event log kept across 6 boots, 3 crashed staged boots → RECOVERY, no phone → waiting, store full of unsent reports → none deleted, new firmware → clean normal start, torn event record skipped. Scenario 22 stress: **1000 rapid phone connect/disconnect cycles (735 s simulated)** with 1125 SENSOR_DIAG events, 425 report requests, 1004 meter changes (silent / stalled / garbage / variants), 252 Wi-Fi toggles, 248 malformed writes, 29 reports — clean under ASan/UBSan (also 5000 cycles) |
| BLE glue stress `test/blehost` (real `ble_central.c` + `ble_link.c` on a fake NimBLE, device task layout, fault injection) | ASan/UBSan **1000 phone cycles PASS** (118 meter connections, 662 GATT procedures, 3759 notifications of which 210 malformed, 17 500 host-task events, 0 invariant violations, 0 leaked mbufs). TSan: only single-byte request flags remain. Same harness on the exact 0.7.2 source: 2000 "host lock inside critical section" violations, 41 TSan reports |
| cppcheck, gcc -fanalyzer | 0 real findings (one harmless format fixed); -fanalyzer 0 warnings on 34 files |
| `idf.py build` | OK. **27 Oct final: app 1 830 352 bytes (44 % of the smaller slot), SHA-256 `181b2e5c751108679a2101bfb1c1942b0302fe537527ceaeba207c5256ea4da5`** (26 Oct draft `735c2699…`, never released) |
| Partition change | `test_partitions` (above) |

## 6. What needs the hardware

The original 0.7.2 crash (only a crash log or a 0.7.3 report can identify it), the real stack high-water marks under a
connecting meter and phone, core dump write/read on the real flash, the RECOVERY screen touch and the staged-boot timings,
the Link 1.2.3 transfer with the real Cyclift build, and everything in pc-kit/TEST-v0.7.3.txt.

## 7. Kit

`pc-kit/fw-v0.7.3/` (+ `SHA256SUMS.txt`), `INSTALL-v0.7.3.bat/.ps1` (full backup + verification incl. the partition table,
one-line explanation, YES, writes app + OTA selector + table if needed, then records and judges the first 60 s),
`RESTORE-CHOSEN-BACKUP.bat/.ps1` (lists every backup with the firmware inside, you pick the number — replaces the "newest
backup" restore, which would now pick the crashing 0.7.2), `ROLLBACK-TO-v071` (unchanged; valid with the new table),
`TEST-v0.7.3.txt`.

## 8. 27 Oct final: Link 1.2.3 integration with Cyclift

* **Chunk size contract** (`bc_diag_chunk_data_max`, docs/LINK_V1_2_SPEC.md 1.2.3): DIAG_CHUNK = 25 + data bytes;
  data = min(phone max_len, 180 − 25 = 155, (ATT_MTU − 3) − 25), ATT_MTU = the phone connection's negotiated MTU
  (`BLE_GAP_EVENT_MTU`, `ble_att_mtu(conn)` every link tick; `plat_phone_status().att_mtu`). MTU < 29 → DIAG_ERR 5. Cyclift
  asks for min(155, maximumWriteValueLength(.withoutResponse) − 25); its 128-byte timeout fallback is gone.
* **Ride priority**: chunks only when `plat_phone_bulk_room()` (LIVE gone, queue empty, ≥ 4 free msys blocks, no refused
  notify in 500 ms) and ≤ 1 per 200 ms; BUSY while a ride is RUNNING; diag replies after every other phone-service reply;
  a notification NimBLE refuses is retried (LIVE, control reply, service queue) instead of dropped.
* **Safe report**: Settings › Diagnostics › **HOLD: SAVE REPORT** (1 s) stores a kind-3 report and announces it (diag_ready).
* **Cross-tests**: `test/host/gen_diag_fixture` exports the real report + server replies at MTU 23/100/185/247/517 for the iOS
  tests (`make` fails on a stale fixture); `test_bc_diag` `test_chunk_size_contract`, `test_fixture_transfers`,
  `test_ios_requests`, `test_old_app_keeps_reports`; simulator scenario 23; `test/blehost/prio` measures LIVE latency with and
  without a transfer (30 ms and 150 ms connection events).
* Kit: fw-v0.7.3 refreshed (app `181b2e5c…`), INSTALL / RESTORE-CHOSEN-BACKUP know the new hash, README-v0.7.3.txt,
  DIAG-TEST-v0.7.3.txt.
