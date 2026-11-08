# CYCLIFT HARDWARE HANDOVER — start here

Prepared 8 Nov 2026 (Dubai) for a new conversation that will take over **design documentation** of the two Cyclift hardware
projects while the original conversation finishes the iPhone app. Read‑only extraction: no firmware, protocol, design or
iPhone code was changed to produce this package. Branch: `docs/hardware-handover` (documentation only).

## What Cyclift is

Cyclift is Rashed's training system for cycling and strength ("hybrid athlete"): an **iPhone app** (the product and the
brain: profile, plan, coach, history, Health, Apple Watch), plus two devices that extend it on the bike and on the wrist:

| Project | Device | One‑line purpose | Code state | Hardware state |
|---|---|---|---|---|
| **A — BikeComputer** | Waveshare ESP32‑S3‑Touch‑LCD‑1.28‑B (1.28" round, USB‑C) | handlebar cycling computer: live power/HR/cadence from BLE sensors, coach, ride recording; phone adds GPS, plan, history | firmware **0.7.4‑rc5** built and QA'd (branch `fw/phonefirst`), kit prepared | board has **0.7.3** installed (crashes at Bluetooth start); 0.7.4‑rc5 install **awaits owner go** |
| **B — Cyclift Watch (LILYGO)** | LILYGO T‑Watch 2021 (ESP32, 240×240 round GC9A01, 2 keys + Boot) | wrist instrument: faces, cycling cockpit/performance/navigation mirrored from the phone, strength set logging, rest timers, recovery glance | firmware **compiles** (Arduino‑ESP32 3.3.12 + LVGL 8.3.11 + NimBLE 1.4.3), 244 host checks, 1 464 gallery scenes 0 findings (branch `watch/w0-foundation`) | **never flashed**; board revision unconfirmed by the owner; no on‑device measurement exists |

Both devices speak **versioned contracts** to the iPhone (05_INTEGRATION_CONTRACTS.md). The iPhone is the recorder and
the owner of the plan, FTP, GPS and Health writes (ios/OWNERSHIP.md on the iPhone branches).

## How to use this package

1. `10_NEW_CONVERSATION_STARTER.md` — paste it into the new conversation first.
2. `01_` / `02_` master briefs — history, architecture and requirements per device (do not mix them).
3. `03_` hardware, `04_` UI/UX design system, `05_` contracts, `06_` feature status, `07_` evidence, `08_` risks,
   `09_` roadmap.
4. `ASSETS/MANIFEST.md` — where every visual and artefact lives (repo paths, branches, claude.ai artifact URLs).

Status vocabulary used everywhere (owner's categories): **Implemented and hardware‑verified · Implemented and
simulator/host‑tested · Compiles but not runtime‑tested · Design approved, implementation incomplete · Proposed only ·
Blocked or unknown.** Nothing in this package is "hardware‑verified" unless a real board log says so (07_).

## Standing rules carried over (owner, verbatim or near‑verbatim)

- "Do not flash the LILYGO without my explicit approval. Factory backup and safe recovery procedures must precede flashing."
- "Do not flash the BikeComputer without explicit authorization." Never reset/erase/repair the board without approval.
- "Do not mark anything hardware-tested until it has been tested on real hardware."
- "Do not claim ANT+." Never write XDS control point 0x2A55 (power‑meter calibration/control).
- Public repository: no names, e‑mails, keys or real device addresses in commits (tests use `02:00:00:c1:f7:01`, "Rider A").
- Watch Design v2 is the approved baseline: "Do not spend another development cycle redesigning the gallery unless
  real‑device testing reveals a significant problem."
- 8 Nov 18:07: iPhone first — **LILYGO firmware development is paused and preserved**; the new conversation's scope is
  **aesthetics, UI/UX and design documentation only** until the owner authorises more.

## Key locations

| What | Where |
|---|---|
| Repository | `github.com/ralsuwaidico-cloud/bike-sensor-doctor` |
| BikeComputer firmware | branch `fw/phonefirst` @ `c0a10fb0` → `firmware/waveshare/` (ESP‑IDF 5.5.1, portable core `components/bc_core`) |
| BikeComputer docs | `firmware/waveshare/docs/*`, `docs/DEVICE_DESIGN_DECISIONS.md`, `docs/DEVICE_ARCHITECTURE.md`, `coord/interfaces/BLE_CONTRACT.md`, `coord/handoffs/firmware.md`, `coord/reports/FW_STORAGE_MEMORY_REPORT.md` |
| Watch firmware + docs | branch `watch/w0-foundation` @ `ca2cadb6` → `watch/firmware/`, `watch/docs/` |
| iPhone side of both contracts | branch `impl/checkpoint-f-ride` → `ios/Shared/BCLink.swift`, `ios/BikeComputer/Watch/CyWatch*.swift`, `ios/OWNERSHIP.md`, `ios/INTEGRATION_ARCHITECTURE.md`, `docs/LINK_V1_2_SPEC.md` |
| Trackers (local Excel copies, not synced to Drive) | `/home/claude/cyclift-mcc/sync-2026-11-07/` — `Cyclift_BikeComputer_Tracker_UPDATES.xlsx`, `Cyclift_LilyGoWatch_Tracker_UPDATES.xlsx`, `Cyclift_Watch_Tracker_UPDATES.xlsx` (Apple Watch) |
| Blueprint (claude.ai) | https://claude.ai/artifact/WKZ5Qv3JJFWtQsqZ6iuuW4 (v6.5) |
| Watch gallery v2 (claude.ai) | https://claude.ai/artifact/TCR2NAoVkwB1UhRvbpFMGn |
| Watch faces page / doc | https://claude.ai/artifact/53hvVZuQVJJC8qiSWVSh58 · https://claude.ai/artifact/9M2kJLHRYa4oNocjtKBzVL |
| Owner's PC (BikeComputer kit, backups, board logs) | `C:\Users\PC\Documents\BikeComputer` (copies attached in this session under `Documents/BikeComputer/`) |
