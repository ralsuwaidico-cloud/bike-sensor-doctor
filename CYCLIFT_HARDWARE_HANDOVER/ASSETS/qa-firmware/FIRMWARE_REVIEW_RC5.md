# Independent QA final review: BikeComputer 0.7.4-rc5 and Link 1.3 (both sides)

Reviewer: QA agent (independent, read-only). Date: 28 Oct 2026.

**What was reviewed:**
- **Firmware:** `fw/phonefirst` @ `0d88933`. It contains the rc4 fixes (`dac2f8c`), contract v1.3 (`0ee42ab`), the rc4 kit (`4d28d00`), next_type 0xFF (`b18baa5`), contract v1.4 (`2591a22`) and the rc5 kit (`0d88933`).
- **iOS:** `ios/phonefirst-dev` @ `37cdca9`, read-only. Its code is the same as `dd227cb`, which CI run 90 built.
- **Kit:** `/home/claude/coord/deliver/fw-v0.7.4/`.

The finding table is `FIRMWARE_FINDINGS_RC5.csv`. Nothing was run on hardware.

## 1. Verdicts

**(a) Offering rc5 to the owner for installation and the physical test: GO.**
- No P0 and no open P1.
- All 8 rc3 findings are fixed. RC3-05 is fixed in part (RC5-01).
- The kit is verified (§4).
- **Conditions** (already written in the rc5 README and TEST):
  - Today's Cyclift on the owner's phone frees a board memory place only at the next connection, and never for a ride it watched live. The README explains this, along with how to free places by connecting twice.
  - TEST D4 is "sync at connection".
  - If the board runs on USB and crashes once in each of 4 long rides in a row, it shows RECOVERY at the next start (RC5-01). RESET clears it.

**(b) Link 1.3 / contract v1.4 as implemented by both sides: GO**, with two follow-ups that do not block (RC5-02, RC5-01):
- **RC3-01 is fixed on both sides:**
  - The board answers SYNC_REQ tag 03 by id, and a by-id request releases nothing.
  - Cyclift asks for a held ride by id, after its connect-time sync.
- **CI evidence:** run 90 (`ios/run-90/test.txt`) shows 362 tests and 0 failures. They include the 7 `RideQueueEndToEndTests`: a ride watched live is verified and ACKed, a queue-imported ride is ACKed, a RAM slot is freed, several rides are all ACKed, by-id never verifies another ride, an older board that ignores tag 03 still works, and a mismatching summary is never ACKed.
- **Firmware evidence:** simulator section 29 checks the board side (by id for a file ride and a RAM ride, nothing released, the 1.2 release rule unchanged).
- **Follow-up:** iOS should merge `0d88933` so its fixture copy gains the 34th vector `coach_state_no_next`. Its encoder already produces those bytes.
- **Not tested together:** the two implementations have not run against each other. Each side tests against fixtures in the other's bytes. Only the physical test (TEST F3/F5) joins them over real BLE.

## 2. Tests I re-ran (copy at `/home/claude/qa-fw/build-rc5`, under `heavy.lock`)

| Suite | Result |
|---|---|
| host: xds / core / pipe / diag / storage / bootrec / fixture / partitions / link13 | 228 / 1901 / 89 / 195 / 82 / 21 / 10 / 65 / 147, **0 failed**; fixtures up to date |
| blehost: stress with Link 1.3 traffic, prio ×2, initfail 0/1/2 | PASS; PASS; 15 / 11 / 9 checks, 0 failed |
| TSan (300 cycles) | 8 reports, **0 with a firmware racing access** |
| simulator, normal and ASan | 339 screens, 701 checks, 0 failed; 0 sanitizer errors (section 29 = the RC3 fixes) |
| `idf.py build` / `size` | app 1,877,632 B, identical to `BC074RC5-app.bin` except build time and hashes (69 bytes); DIRAM free **44,625 B** (README "44.6 KB") |
| My boot probe (`probes/boot_probe_rc5.c`, real `bc_boot.c` / `bc_bootrec.c`) | S1–S11 as in rc3 (bounded; residual S4b/S7d documented). S12 (sporadic crashes, deep sleep between): **never forced**. S12c (crash more than 10 min into every start, no deep sleep): forced at start #5 (RC5-01) |
| My worst-case coach probe (RACE / EVENT, 1100–1250 W, HR HIGH, 62/64, next 120 min) | **0 layout issues** in A/B/C, ride page and card (RC3-02 fixed); the content checks fail only because I changed the content |
| iOS CI 90 (`gh` and branch `ci-logs`) | build, tests (362, 0 failures), Release launch smoke, layout audit and archive: all ok |

## 3. RC3 findings

| Finding | Status | Evidence |
|---|---|---|
| RC3-01 summary deadlock (P1) | **Fixed, both sides** | Board `app_psvc.c:246-247,405,416,428`; Cyclift `RideQueueTransfer.swift` by-id request; sim 29c; iOS end-to-end tests |
| RC3-02 page-1 cue fit | Fixed | Short instruction form; my worst-case probe and sim 29a show 0 issues |
| RC3-03 coach seq after relaunch | Fixed, both sides | Board reopens the seq window at HELLO; Cyclift persists its seq (`testSeqStaysNewerAfterARelaunch` passed) |
| RC3-04 keepalive / merge | Fixed, both sides | Merge with countdown kept; Cyclift sends full states (tag 13 always, 0D = 0xFF when there is no next interval) |
| RC3-05 crash limiter | **Partly** | The RTC and NVS run counters clear after 10 min and on a deep-sleep wake. The older NVS boot-record rule (`main.c:193`) does not clear after 10 min (RC5-01) |
| RC3-06 verified-ride key | Fixed | id + summary CRC + start time |
| RC3-07 README/TEST | Fixed | The 4 memory places are explained; D4 = sync at connection |
| RC3-08 LIVE 13–15 | Fixed, both sides | Always sent by the board; absent = unknown in Cyclift |

## 4. Kit (rc5)

- **Checksums:** all 29 entries in KIT-SHA256SUMS.txt match, and every file is byte-identical to `pc-kit/`.
- **App:** SHA-256 `8ccc4d89…cedae4`. The installer's and the restore script's "known" tables list it, and `PROJECT_VER` is `0.7.4-rc5`.
- **Installer** (identical to the rc3 script I reviewed apart from version, file names, hashes and the added rc4 hash):
  - Backup: `read-flash 0x0 0x1000000 --after no-reset`, verified before the YES prompt.
  - Write: `write-flash --after no-reset [0x8000 only on an old table] 0xf000 otadata 0x20000 app`. Erasing ends at 0x1EAFFF, inside ota_0.
  - **NVS 0x9000–0xEFFF and storage 0x820000 onward are never written or erased.**
  - No firmware runs between the backup and the write.
  - The new firmware's first start is recorded for 90 s by the installer, which starts the board itself.
- **Rollback and restore:** unchanged and correct. ROLLBACK-073 still warns that 0.7.3 crashes on this board.

## 5. New findings (all P2)

- **RC5-01, crash limiter residual:** the older rule that forces RECOVERY after 4 crash resets in a row in the boot records is not cleared by 10 min of running. If the board never deep-sleeps (USB power and a connected phone block auto-sleep) and crashes once per long ride, it starts in RECOVERY at the 5th start. RESET clears it.
- **RC5-02, iOS copy behind:** the iOS branch still has contract v1.3 and the 33-vector fixture. The firmware's 34th vector `coach_state_no_next` is missing there. The wire bytes agree.
- **RC5-03, repo hygiene:** commit `b18baa5` added 39 simulator output files under `firmware/waveshare/test/simfs/`. The `.gitignore` covers only `test/sim/simfs/`. They contain no personal data (a made-up rider, zero MACs, made-up Wi-Fi credentials).

## 6. What only the board can confirm

- The per-step Bluetooth start figures.
- That no write is made to the damaged FAT.
- Real BLE Link 1.3 between this Cyclift and the board: HELLO, coach card, by-id summary and ACK, memory places freed.
- That the round display matches the simulator.
- How the crash counters behave across real resets.
