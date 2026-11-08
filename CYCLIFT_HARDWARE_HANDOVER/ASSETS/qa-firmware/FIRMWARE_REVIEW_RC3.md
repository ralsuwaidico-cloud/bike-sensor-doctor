# Independent QA review: BikeComputer 0.7.4-rc3 and Link 1.3 (both sides)

Reviewer: QA agent (independent, read-only). Date: 27 Oct 2026.

**What was reviewed:**
- **Firmware:** `fw/phonefirst` @ `08b639e`. This holds the Link 1.3 commits `8251e7b`, `3d721b6`, `6a2f57c`, `031e430` and `c7f33f9`, the fixes for QF-21..29 in `040e6cb`, and the kit in `08b639e`.
- **iOS:** `ios/phonefirst-dev` @ `3e54803`, read from `/home/claude/ws-ios2` without editing.
- **Contract:** `coord/interfaces/BLE_CONTRACT.md` v1.2.

The finding table is `FIRMWARE_FINDINGS_RC3.csv`: the status of QF-21..29 and the new findings RC3-01..08. Nothing was run on hardware.

## 1. Verdicts

**(a) Offering rc3 to the owner for installation and the physical test: GO, with conditions.**
- **No P0.** The kit only writes the app and OTA selector, and keeps the backup before it writes.
- **Rebuild:** the app I built from `08b639e` differs from `BC074RC3-app.bin` only in the build time and hashes (70 bytes).
- **Checksums:** all 29 entries in KIT-SHA256SUMS.txt match.
- **Fixes:** all nine rc2 findings are fixed. One of them, QF-22, works only partly because of RC3-01.
- **Conditions:**
  1. Tell the owner that on his board (damaged storage, so every ride is RAM-only), a ride's memory place is **not** freed when Cyclift was connected during the ride, or when the phone imports it before the connect-time sync (RC3-01). After 4 rides in one power cycle the next ride is "RIDE NOT SAVED", although the phone normally holds the earlier ones.
  2. Fix or annotate TEST step D4. It asks for a "pull to refresh" ride sync that no Cyclift version has (RC3-07).
  3. Expect the ride page-1 cue to run past the round edge in designs A and B for long cues such as "HR HIGH - EASE OFF" (RC3-02, cosmetic).

**(b) Contract v1.2 as implemented by both sides: NO-GO** until RC3-01 (P1) is fixed.
- **RC3-01:** Cyclift can never get the summary CRC of a ride it has already put in its history, so it never sends RIDEQ_ACK. The ride stays "unsynced" on the board for good. Its samples are never freed, and its RAM slot is never released.
- **Also fix or define:**
  - RC3-03: COACH_STATE seq after a Cyclift relaunch.
  - RC3-04: every COACH_STATE must be a complete state.
  - RC3-06: `synced.txt` must also be matched by CRC.

Everything else in Link 1.3 checked out: the HELLO gate in both directions, delete only after a verified ACK, nothing while recording, replays, the clean-refusal rules, DIAG auto-delete, and HR honesty.

## 2. Tests I re-ran (copy at `/home/claude/qa-fw/build-rc3`, under `heavy.lock`)

| Suite | Mine | Claimed |
|---|---|---|
| host: xds / core / pipe / diag / storage / bootrec / fixture / partitions / link13 | 228 / 1901 / 89 / 194 / 82 / 21 / 10 / 65 / 105, **0 failed**; diag and link13 fixtures up to date | same |
| blehost: stress (with Link 1.3 phone traffic and 180-B RIDEQ chunks), prio ×2, initfail 0/1/2 | PASS; PASS; 15 / 11 / 9 checks, 0 failed | same |
| TSan (300 cycles) | 7 reports, every racing access in the fake or harness | — |
| simulator, normal and ASan | 321 screens, 656 checks, 0 failed; 0 sanitizer errors | same |
| `idf.py build` / `idf.py size` | OK / **DIRAM free 44,673 B (claim confirmed)** | 44,673 |
| iOS fixture cross-test | `ios/BikeComputerTests/Fixtures/link13_fw_fixture.json` and `Link13FirmwareFixture.swift` are byte-identical to the firmware's (30 vectors) | — |
| iOS CI | `gh`: run 86 (`06bb718`) succeeded, jobs build and apple. `3e54803` is a [skip ci] handoff commit on top. | green |

**Own probes:**
- `probes/boot_probe_rc3.c`, using the real `bc_boot.c` and `bc_bootrec.c` with rc3's `main.c` order, including the NVS crash-run counter, the limiter, RECUI/RECMIN and brownouts.
- `probes/fat/fatcheck_probe.c`, running the real `bc_fat_check` on the owner's damaged image and on fatfsgen images with 9 kinds of corruption.
- Two simulator copies with worst-case COACH_STATE content.

All output is in `/home/claude/qa-fw/logs-rc3/`.

## 3. QF-21..29: tried to break them

- **QF-22, RAM slot release.** Firmware: a verified RIDEQ_ACK releases the slot (`app_link13.c:182`), and so does a later 1.2 SYNC_REQ whose `after_ride_id` covers a RAM ride already streamed (`app_psvc.c:243`). `ram_sent` survives a disconnect.
  - **The shipped Cyclift** sends SYNC_REQ only at connect (+2 s) and when SYNC_END says "more", with `after = highestBoardRideId` (`DeviceLink.swift:282-288,559,580`). So a RAM ride is released only at the second reconnection after the phone received it.
  - **It is never released** when the phone recorded its own live mirror of the ride. `RideRecorder.swift:145` sets `boardRideId`, the first sync then starts above the ride, and the ride is never streamed. That is the normal case when Cyclift is connected during a ride.
  - **The new Cyclift** has the same gap through RC3-01.
- **QF-24, ride ids and FAT move-aside.** The id floor comes from the history and the RAM queue, and an existing samples file is renamed to `r####-oldNNNNN.txt`, never overwritten. The residual (NVS and FAT both unusable) is documented in the contract.
- **QF-25, recovery-screen crash marker and halt path.** Probe S9: the recovery screen crashes, and the next start shows the minimal text. S9b: the minimal text crashes too, and the next start halts. Bounded either way.
- **QF-26, brownout counting.** Brownouts are no longer crashes. Two brownouts at the same skippable stage disable it: S11 shows Bluetooth off after 2 brownouts, a power toast, and the board stable.
- **QF-26, RTC and NVS counters.** The NVS crash-run counter is written before storage starts. RTC lost plus a crash in storage now reaches RECOVERY at boot 5 (S7b; rc2 never did). Late crashes with NVS failing are bounded too (S6b).
  - Residual, documented: RTC lost **and** NVS failing is unbounded (S4b, S7d).
  - **New (RC3-05):** the counters survive deep sleep and are not cleared by stable running. Four sporadic crashes days apart force RECOVERY on the fourth, mid-ride (S12).
- **QF-28, FAT consistency checker.**
  - The real damaged owner image is **inconsistent**: 512 erased entries and 717 lost clusters.
  - A healthy image with 8.3 names is consistent.
  - Every synthetic corruption is caught: cross-link, loop, lost cluster, the owner-like 713 phantom clusters, size mismatch, free cluster in a chain, chain out of range, erased sub-directory entry.
  - A bad-cluster mark outside any chain is accepted.
  - FAT2 is not compared with FAT1. That is harmless, because FatFs uses FAT1.
  - **A strict SFN check means a non-FatFs tool's odd short name counts as damage, and the check then refuses to clean** (fatfsgen writes a 0x01 numeric tail). This is a safe-side false positive; FatFs's own names pass.
  - Every delete path is gated: the boot-time FULL clean-up and STORAGE_CLEAN.
- **QF-27, internal RAM.** Static DIRAM free is **44,673 B**, measured.
- **QF-21, QF-23, QF-29.** Honest texts without Bluetooth; restart and sleep need a 3 s hold; automatic sleep is blocked; short interrupted rides are kept. Simulator section 28.

## 4. Link 1.3 end to end

- **HELLO gate, both directions:**
  - **rc3 board with the shipped Cyclift:** no HELLO is sent. Every 1.3 Control type is consumed and ignored, and nothing new is sent (sim 27a). The extra LIVE tags are skipped by the shipped decoder, and INFO caps (u32) decode fine.
  - **New Cyclift with old boards:** `Link13Session` sends nothing without INFO cap 0x0800, and `sendLink13` checks again.
  - **Timing:** HELLO is written after the Control CCCD write in the same GATT queue, and the board marks the phone ready before it processes queued writes. Even a lost HELLO is recovered by Cyclift's one retry after 4 s.
- **Coach:**
  - Plan CRC, the 0xFFFF open-ended rule, seq in serial-number order, phone lost after 12 s, the stored plan running on the ride clock, last target otherwise. With watch HR gone the board shows "NO HR - BY FEEL" (sim 27d).
  - **Keepalive (RC3-04):** the board replaces its whole state with every COACH_STATE, and Cyclift sends the full state, so the two interoperate. The contract and the fixture's minimal-keepalive vector still allow a form that blanks the board's targets.
  - **Seq after a relaunch (RC3-03):** Cyclift's seq restarts while the workout_id stays the same, so the board ignores its states for minutes.
- **Offline queue:**
  - Samples are deleted only after a RIDEQ_ACK with both CRCs matching and `delete_samples`, and never while a ride records.
  - Chunk requests while recording get BUSY. At most 4 are outstanding, and the offset is checked.
  - A replayed ACK is idempotent; a mismatching one gets ERR 6 and the state is unchanged.
  - A disconnect clears pending requests, and Cyclift resumes from its partial file.
  - COACH_STATE seq wrap is handled.
  - **RC3-01 (P1):** the summary-CRC deadlock. **RC3-06:** `synced.txt` is matched by id only.
- **Storage clean:**
  - Refused for states 2, 3, 4, 5 and 7, and refused if the FAT is inconsistent. The owner's board (state 3, "Directory corrupted") is refused.
  - BUSY while a ride records. STORAGE_STATUS follows every result.
- **DIAG auto-delete:** only when HELLO enabled DIAG_AUTO, only after a CRC-matching DIAG_ACK with `delete=1`, after DIAG_INFO state 1, and never an unsent report.
- **HR honesty:** phone-relayed HR is used only if it is ≤ 6 s old (`app.c` `APP_PHONE_HR_FRESH_MS`). The coach view drops watch-based HR targets without the phone. The board never shows Apple Watch HR without the link.
- **Coach card on 240×240:**
  - The card page fits in designs A, B and C, including my worst-case content: RACE / EVENT type, 1100–1250 W targets, 100–120 rpm, interval 62/64, next SWEET SPOT 120 min.
  - **The ride page-1 cue line does not fit in designs A and B** for "HR HIGH - EASE OFF" and long targets: CIRCLE and EDGE failures (RC3-02).

## 5. Installer, rollback, restore (kit `fw-v0.7.4/`)

The rc3 installer is identical to the rc2 script I reviewed apart from the version, file names and hashes.

- **Backup:** `read-flash 0x0 0x1000000 --after no-reset`, then verified (16 MB, a known app hash, a known table).
- **Write, only after the owner types YES:** `write-flash --after no-reset [0x8000 only if the board has the old table] 0xf000 otadata 0x20000 app (1,875,840 B; erase ends at 0x1E9FFF, inside ota_0)`.
- **NVS (0x9000–0xEFFF) and storage (0x820000 onward) are never written or erased.**
- No firmware runs between the backup and the write.
- **First-boot capture:** the script opens the port first and pulses RTS to start the board, then records 90 s. A crash loop is reported as CRASHED. The script expects the version string `0.7.4-rc3`, which matches `PROJECT_VER`.
- **Rollback and restore:** ROLLBACK-073/072 write only 0xf000 and 0x20000, with checksums checked (073 warns). RESTORE knows the rc3 hash. READ-BOARD-STATE is read-only.

## 6. What only the board can confirm

- The per-step Bluetooth start figures, and whether 44.7 KB of free static DIRAM is enough.
- That the 15 s watchdog guard never fires.
- That the owner's damaged FAT is never written.
- That the real round display renders the cards as the simulator does.
- That Cyclift ↔ board Link 1.3 works over real BLE (HELLO, plan, queue, storage screen).
- That RAM-only rides reach Cyclift when Bluetooth works.
