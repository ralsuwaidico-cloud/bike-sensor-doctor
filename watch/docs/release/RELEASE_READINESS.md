# Cyclift Watch — release readiness, Stage 1.3 RC1 (11 Nov 2026)

## Verdict
**OFFLINE READY — not HARDWARE VERIFIED.** RC1 is built, reproducible, computer-tested and has a simulated install and
rollback. Nothing has been installed. Stage 1.1 (3274b887…) remains on the watch. Installing RC1 needs the owner's
approval naming the file and fingerprint below.

## The release candidate

| Item | Value |
|---|---|
| File | `cyclift-stage1.3-rc1-v3poc-T-Watch-2021-V1_1.bin` (board revision V1.1, as the installed Stage 1.1) |
| SHA-256 | `4ea0ea90da5061859019c7b6f94c1eaea409c362d94a07e058d7755feda50c19` |
| Size | 1,194,112 B; header DIO / 40 MHz / 8 MB |
| Source | branch `watch/v3-poc`, commit 6854b9b; CI run 42916312090 |
| Reproducible | two clean CI builds and the published file byte-identical (1,194,112 B each) |
| Where | branch `firmware/stage1-candidates` (with SHA256SUMS); pin in `watch/firmware/releases/stage1.3-rc1.sha256`, `cy_update_s13.py`, `cy_recover_b.py` |
| Boot banner | `Cyclift v3 proof of concept · Stage 1.3 RC1 (local screens; IRAM rendering off) …` |
| Preserved | Stage 1 `faa2828f…`, Stage 1.1 `3274b887…`, Stage 1.2 `2760f5a7…` in `watch/firmware/releases/`, each CI-guarded |

Other board revisions (not for this watch): V1_0 `f4cb8d2b…`, V2 `85d0e873…`.

## What RC1 contains
Milestone A (Stage 1.2 foundation) + Milestone B (Today, Week, Quick Settings, three widgets, screen lock, "Not in this
release" pages, Bike cockpit layout, honest data defaults, Simulated-ride banner) + Milestone C (clock validity, date
EN/AR, time hook) — details in RELEASE_PLAN.md and FEATURE_MATRIX.md. Milestone D is a document only
(BLE_ARCHITECTURE_RC1.md). No Bluetooth, no flash storage writes, no settings saved.

Defects from the audit: D1 date with an invalid clock — fixed; D2 invented synced data by default — fixed (demo data only via
serial `E`); D3 silent menu rows — fixed ("Not in this release" page); D4 LVGL peak under-read — fixed in 1.2 (sampled
peak); D5 no simulated marker — fixed (banner). One new defect found and fixed by the date sweep (Arabic Today header
overlapped its date by 1 px for some months).

## Evidence (details: TEST_COVERAGE.md, MEMORY_AND_PERFORMANCE.md)
Model 1,720 · navigation 353 + 200,000-input soak · time 31 (all 27,759 days 2024–2099) · rendering 811 states / 279,605
checks / 0 findings · UI soak 30,000 inputs, no LVGL growth · 132 Stage 1 pictures byte-identical · performance budgets
0 failures · install simulation 52+1 checks, 0 failures · CI 42916312090: all 6 jobs green, incl. the boot emulator (0 failures; S10: RC1 write cut at 25–99 %, last sector missing, one bit flipped, header erased → factory app starts; complete RC1 starts once).

## Owner decisions needed (RC1 contains a proposal for each; none is final)
1. New wording not in the prototype: "No plan on the watch yet / Today's plan comes from iPhone", "Not in this release /
   Arrives in a later update", "Simulated ride / No sensors · demo values" (EN + AR).
2. Health, Coach, History, Utilities, Settings show a "Not in this release" page instead of their approved pages.
3. Geometry deviations from prototype v3.3 (round-glass and 44 px rules): the "Locked · hold Key 1" chip at y 178 instead
   of y 200; the Today "⌄ Week" link is tappable only when there is no Start button (otherwise swipe up); the Arabic Today
   header 1 px higher.
4. Demo-data mode: the watch starts "not synced"; serial `E` turns labelled demo data on (for testing without an iPhone).
5. LVGL pool stays 64 KB in RC1; 32 KB proposed for RC2 after `M` on the watch.
6. 24-hour time only (no 12-hour setting is specified in the approved design).

## Install instructions (NOT approved — for the record)
1. Copy the file to `Documents\Cyclift_Stage2a\stage1_3_firmware\` on the PC and confirm SHA-256 `4ea0ea90…`.
2. Copy `pc_update_s13_runner.py` as `tools\cy_update_s13.py` (keep `cy_update_s11.py`), and the updated
   `pc_recovery_b_runner.py` as `tools\cy_recover_b.py` (old copy kept); verify each copy by SHA-256.
3. In Python IDLE: `exec(open(r'…\tools\cy_update_s13.py').read())`, then `phase('s13_pre')`, `phase('s13_write')`,
   `phase('s13_post')` — one at a time, stop at the first failure.
4. One write only: 0x400000–0x523FFF (1,196,032 B = RC1 padded to whole 4 KB sectors; inside app1, which ends 0x6FFFFF).
5. Then HARDWARE_ACCEPTANCE.md. Rollback: ROLLBACK_AND_RECOVERY.md (`s13_rollback` → Stage 1.1).

## Definition of done
- OFFLINE READY (now): every item above, CI green, docs current.
- HARDWARE VERIFIED (later): HARDWARE_ACCEPTANCE H1–H14 pass on the watch with recorded evidence; anything that fails or
  cannot be tested (battery, real sensors, Bluetooth) stays unverified and is named.
