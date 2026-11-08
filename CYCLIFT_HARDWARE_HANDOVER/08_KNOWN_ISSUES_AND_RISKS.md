# 08 — Known issues, risks, limitations, unresolved decisions

## A. BikeComputer

| # | Issue | Status | Evidence | Decision needed |
|---|---|---|---|---|
| A1 | **Board crashes at Bluetooth start on 0.7.3** (`ESP_ERROR_CHECK(nimble_port_init())` abort). Cause: internal‑RAM shortage when the host starts — strongly indicated, **unconfirmed** | 0.7.4 removes the abort, logs heap, shows "Bluetooth unavailable"; **not installed** | `FW_STORAGE_MEMORY_REPORT.md`, board log 27 Oct | owner: run `READ-BOARD-STATE` (read‑only, resets to download mode) then install rc5 |
| A2 | **FAT root directory erased** (512/512 entries) → no ride, log or report can be saved; 713 clusters wrongly marked used since first format | repair plan written (PC‑side, storage region only), **not started**; mechanism that erased all four root sectors **open** | report §7 | approval after A1's read |
| A3 | 0.7.2 crash loop — D1 (NimBLE host lock inside a spinlock), D2 (recovery actions racing host callbacks) **confirmed** by harness/TSan; H1–H3 hypotheses | fixed in 0.7.3/0.7.4 with regression tests; never hardware‑verified | `CRASH_0.7.2.md` §7–8 | — |
| A4 | Charging: ETA6096 fitted for ≈ 1 A, cell is 500 mAh (0.5 A max) → **charging safety not verified** (HW‑1) | OPEN | `HW_RISK_REGISTER.md` | owner: battery choice or charging only at a low‑current port? |
| A5 | No charge/VBUS sense, no true power‑off, deep‑sleep current unknown, charge alerts infeasible (HW‑2/3/4/7) | ACCEPTED / OPEN | same | — |
| A6 | Touch wake unreliable; touch dead after sleep; link lost on screen‑off; pairing broke after a data reset (HW‑5/6/8/9) | fixed in software 0.6.x–0.7.0, **unverified on hardware** | `FIRMWARE_0.6.0/0.6.1.md` | — |
| A7 | **The first milestone — real power + cadence from the XDS meter on the Waveshare — has never been demonstrated** (decoders host‑tested only; 0.7.2 found a real CCCD bug) | OPEN | BIKE‑001 | — |
| A8 | On‑board coach uses watts from its own FTP even when the phone's FTP is unknown (audit M‑07…M‑11); board and phone auto‑FTP rules differ | OPEN (BIKE‑005, DEV‑GAP‑005) | tracker | design decision |
| A9 | **Protocol number collision (found during this extraction):** iPhone branch `impl/checkpoint-f-ride` R‑020 draft uses msg 0x90–0x94 and cap 0x0800 — already Link 1.3 RIDEQ_* and HELLO on `fw/phonefirst`. Inert today (gated on a cap no shipped board sets), but **must be renumbered before any Link‑1.3 board meets that app** | OPEN — to be fixed on the iPhone branch (not part of this read‑only task) | `docs/LINK_V1_2_SPEC.md` §1.3 vs `coord/interfaces/BLE_CONTRACT.md` §4/§9 | iPhone conversation |
| A10 | iPhone Link 1.3 implementation exists only on `ios/phonefirst-dev` (not in the release line); the firmware side is in rc5 — the two have never met | OPEN | branches | roadmap item |
| A11 | Health stop/pause to board, ANT+ sensors | PO / not possible | BIKE‑011/012 | — |
| A12 | Old design docs call Decision 4 "Power Focus approved"; Link 1.3 later made the Cyclift coach card part of every ride design — both true, read in order | note | — | — |

## B. Cyclift Watch (LILYGO)

| # | Issue | Status | Evidence | Decision needed |
|---|---|---|---|---|
| B1 | **Board revision and T‑U2T dongle unconfirmed** — pin map and the factory binary depend on it | BLOCKS every hardware step | `HARDWARE_AUDIT.md` §1 | owner reads the silkscreen |
| B2 | **Nothing has run on the device**: no frame rate, touch latency, RAM/heap at runtime, PSRAM behaviour, BLE range/stability, battery drain, RTC drift, key debounce timing | all **pending** | `HARDWARE_READINESS.md` §5 | M0 → M1 approvals |
| B3 | Fonts measured by a conservative host table; device fonts (LVGL `lv_txt_get_size`) may differ → the 0‑finding layout result must be repeated on the device | pending | `ROUND_LAYOUT.md` | — |
| B4 | Flash headroom ≈ 0.9 MB in the 3 MB OTA slot (five Montserrat sizes dominate); static RAM 34 % before any runtime allocation (LVGL draw buffer 57.6 KB planned in internal RAM, NimBLE, LittleFS) | risk of internal‑RAM pressure like the BikeComputer's | run 42487341323 figures | measure at M1/M3 |
| B5 | Rep counting is **experimental**; validation dataset and per‑exercise accuracy table do not exist (CW‑022) | DI | `REP_COUNTING.md` | hardware data |
| B6 | ESP32 as BLE central (sensors) + peripheral (phone) on one radio: plausible, **untested** (CW‑018) | needs testing | — | W2 |
| B7 | Compass variant (QMC5883L vs P) unknown until probed; compass disturbed by the bike's steel | — | audit §2 | — |
| B8 | Capacitive touch will not work with gloves → the two keys are the glove path (two‑press) | by design | `BUTTONS.md` | — |
| B9 | The watch palette hex values differ slightly from the iPhone's Checkpoint H palettes (same family names) | design reconciliation | 04_ | new conversation |
| B10 | Design v1 was rejected (16:07); v2 approved (16:44) — do not reopen the gallery without device evidence | decision | — | — |

## C. Cross‑cutting

- **No Google Drive sync** of trackers (all workbooks are local copies: "NOT SYNCED"); the handover and trackers live in the
  repo and in `/home/claude/cyclift-mcc/`.
- Public repository: no personal data, keys or real device addresses (the simulator's `plat_host.c` device id was flagged
  for neutralisation — check before publishing logs).
- Both firmware branches are frozen by the owner (18:07): BikeComputer awaits the owner's board actions; LILYGO is
  paused for the iPhone‑first phase.

## D. Local files that are not in the repository (available only in this session's workspace)

`/home/claude/qa-fw/FIRMWARE_REVIEW_RC1/2/3/5.md` + `FIRMWARE_FINDINGS*.csv` (independent QA of 0.7.4), the tracker
workbooks and `content.py`/`build_lilygo_tracker.py` in `/home/claude/cyclift-mcc/sync-2026-11-07/`, the owner's PC
folder copy under `Documents/BikeComputer/` (kits, backups, board logs). Copies of the QA reports and the two hardware
tracker workbooks are included in `ASSETS/` of this package.
