# 09 — Future roadmap (remaining work, priorities, dependencies)

Order set by the owner on 8 Nov 2026: **iPhone app first** (Phases 1–4 of the 18:07 directive, then a frozen
integration contract) → **only then** device development resumes. Until then the new conversation works on
**design documentation and aesthetics only**; firmware, flashing, BLE changes and integration stay paused.

## Phase 0 — now (design‑only, no firmware)

| # | Work | Device | Depends on |
|---|---|---|---|
| 0.1 | Keep Design v2 as the watch baseline; produce polished design documentation from the existing gallery/native PNGs (no new gallery cycles) | Watch | — |
| 0.2 | Reconcile the watch tokens with the iPhone's Checkpoint H palettes (same six names; slightly different hex) — a documented decision, not a code change | both | iPhone Checkpoint H review |
| 0.3 | BikeComputer ride‑design documentation for Link 1.3 (coach card on A/B/C) and the phone‑first Home/Connections states ("Bluetooth unavailable", storage state) — design record of what rc5 draws | BikeComputer | — |
| 0.4 | Physical‑test checklists ready for the owner: BikeComputer rc5 (`pc-kit/TEST-v0.7.4-rc5.txt` exists), Watch M0/M1 (`HARDWARE_READINESS.md` §4) | both | — |

## Phase 1 — BikeComputer hardware (owner approvals, one at a time)

1. `READ-BOARD-STATE` (read‑only dump: core dump, NVS, storage, full backup) → confirms A1 cause and A2 state.
2. Install **0.7.4‑rc5** with the kit (full backup first; rollback to 0.7.3/0.7.2 kept) → physical test sheet.
3. Storage repair (PC‑side, storage region only) if the FAT root is still erased.
4. **First‑milestone proof**: XDS meter live on the board (power + cadence) — the project's original goal, still unproven.
5. Decide the battery/charging question (A4) before unattended charging.
6. Link 1.3 end to end: needs the iPhone Link 1.3 code (`ios/phonefirst-dev`) brought into the release line **after**
   the R‑020 renumbering (A9) — or R‑020 folded into COACH_PLAN, which already carries steps and targets (design decision).
7. Coach audit items M‑07…M‑11; align board/phone auto‑FTP rules (A8).

## Phase 2 — Watch hardware (owner approvals per M‑step)

| Step | Flashes? | Gate |
|---|---|---|
| **M0** identify (silkscreen revision, compass probe, T‑U2T) + factory backup with SHA‑256 (`watch/tools/backup_factory_firmware.sh`) | no (read‑only) | owner reads the silkscreen; dongle present |
| **M1** diagnostics image (`T-Watch-2021-V1_1-diag`): chip/flash/PSRAM print, I2C scan, keys, battery ADC, motor, display pattern, touch echo | yes | M0 backup verified; owner approves the exact procedure |
| **M2** faces + clock (RTC + TimeSync), device‑measured fonts → repeat the 0‑finding layout pass on device | yes | M1 |
| **M3** BLE + cockpit (phone link, telemetry mirror, Cockpit/Performance/Navigation live), latency, reconnect, frame rate, RAM/PSRAM measured | yes | M2; iPhone companion enabled |
| **M4** strength + measurements (set logging, rest timers, two‑press keys, battery/perf table) | yes | M3 |
| W4 rep‑detection dataset and accuracy table; W6 recovery cards from the iPhone's Checkpoint E; W7 hybrid day without duplicates; W8 7‑day soak | — | M4 |

## Phase 3 — integration contract freeze (iPhone conversation leads)

- Freeze Link 1.x + wearable v1 as the versioned baseline; add firmware‑generated vectors for every message to both test
  suites (Link 1.3 fixture already exists; R‑020 does not).
- Adapter boundary and ownership rules as written in `ios/INTEGRATION_ARCHITECTURE.md` and `ios/OWNERSHIP.md`.
- Migration rule for any incompatible change: new version/cap, both encoders kept, "update required" shown, never silent.

## Explicitly not planned

ANT+ (no radio on either device); GPS or barometer on the V1.x watch; charge alerts on the BikeComputer; a LILYGO Health
writer; replacing the approved Watch v2 design or the approved BikeComputer navigation/dashboard decisions without
device evidence.
