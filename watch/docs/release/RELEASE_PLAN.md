# Cyclift Watch — audit summary, gap analysis and release plan (11 Nov 2026)

Owner brief 11 Nov 02:10 ("Autonomous development, validation and release readiness"). Offline work only; nothing is
installed on the watch without a separate approval. Stage 1.1 (3274b887…) stays installed.

## 1. What actually exists (audit, from the code — not from designs)

Two firmware lines live in `watch/firmware` on branch `watch/v3-poc`:

| Line | Build | What is in it | Evidence |
|---|---|---|---|
| **v2 application** (`src/app/main.cpp`, `src/domain/*`) | `T-Watch-2021-V1_1` | v2 design: Orbit/Chrono/Pulse faces, timers, ride screens, strength, rep-detector (experimental), BLE wearable protocol v1 (NimBLE), event queue | computer tests (244 domain checks, 1,464-scene gallery); **never run on the watch** |
| **v3 proof of concept** (`src/app/v3poc_main.cpp`, `src/ui/v3/*`) | `…-v3poc` | approved Hybrid UI/UX v3: Orbit face, app menu (8 destinations listed, 2 wired), cycling cockpit (simulated ride + simulated iPhone), 6 theme palettes, Standard / Focused / Large Text, English / Arabic | computer tests + **hardware**: B2 13/13 (Stage 1), C1 install + C2 partial (Stage 1.1) |

The approved direction is v3 (decision V1: "v3 is the direction; preserve v2 functionality, layouts may improve").
So every v2 function counts as **not yet in the v3 firmware** until it is ported; nothing is lost from the repository.

Approved design: prototype v3.3 (Deliverable D) has ~95 screens: 3 faces + picker + complications, 3 glance widgets,
Quick Settings, app menu with 8 destinations (Watch Face, Today, Activities, Health, Coach, History, Utilities,
Settings), ride/run/walk/strength workouts, health, coach, history, utilities and settings pages. 102-feature placement:
74 shown, 15 shown as unavailable with a reason, 13 hidden (listed in Settings → Feature availability).

## 2. Gap analysis (v3 firmware vs approved v3 design)

| Area | Approved | v3 firmware today | Gap |
|---|---|---|---|
| Faces | Orbit, Chrono, Pulse + picker + 3 complication slots | Orbit only | Chrono, Pulse, picker, complications |
| Face neighbourhood | swipe up Today · down Quick Settings · left/right 3 widgets (Health, Coach, Activity) | **nothing** (owner found this on 10 Nov) | all of it |
| Menu destinations | 8 | Watch Face, Activities (starts simulated ride), Return to workout | Today, Health, Coach, History, Utilities, Settings |
| Cycling | cockpit + 5 ride pages + controls + end/summary | cockpit (Wrist mode), pause/resume/lap | ride pages, controls page, End, summary, Bike mode layout |
| Strength / run / walk | full flows | none | all |
| Themes | 6 | 6 palettes compiled, only Obsidian reachable/tested | switching + verification of 5 themes |
| Time | from iPhone (TimeSync), date + weekday EN/AR | RTC read; **date shown even when the clock is invalid** (defect); serial set in Stage 1.2 | invalid-date defect; iPhone sync interface |
| Data honesty | empty / unavailable states with reasons | face shows **invented "synced" values** (Move 72 %, Next · Ride 18:30) by default | default must be "not synced"; demo data only on request and labelled |
| Bluetooth | iPhone-centred, protocol v1 (+ proposed additions) | v3 build has none (v2 build has NimBLE) | Stage 2b/4 — architecture only now |
| Tests | — | model + 132-state render + perf + install simulations | gesture matrix for every screen, theme matrix, clock rollovers, soak, performance budgets per screen |

Defects found in this audit: **D1** date shown with an invalid clock; **D2** invented synced data on the face by default;
**D3** unwired menu rows do nothing when tapped (silent); **D4** LVGL peak counter under-reads (fixed in 1.2);
**D5** no visible marker that ride values are simulated.

## 3. Release scope — "Stage 1.3 / RC1: local watch experience" (no Bluetooth)

Milestone A — foundation = Stage 1.2 (done offline 10 Nov): IRAM speed-up off, smaller recorder, `M` memory/stack
report, RTC integrity check, `T`/`R` serial time. LVGL pool stays 64 KB (32 KB proven safe on the computer; adopted only
after `M` measurements on the watch).

Milestone B — local experience (this release):
1. Face swipes exactly as approved: up → Today, down → Quick Settings, left/right → widget carousel
   (face ↔ Health ↔ Coach ↔ Activity ↔ face, page dots), back gestures as in the prototype.
2. Today (planned session, Start, "Week" strip) and Week strip; honest empty state without an iPhone plan.
3. Quick Settings: Brightness (real backlight), Theme (all 6), Do not disturb (state), Mode (Wrist / Bike / Gym;
   Bike changes the cockpit to the approved Bike layout), Screen lock (hold Key 1 to unlock).
4. Widgets Health / Coach / Activity with the approved empty / unavailable states (no data source yet).
5. Menu: Today wired; Health, Coach, History, Utilities, Settings open an explicit "Not in this release" page
   (approved empty-state pattern; wording is an owner decision — listed in RELEASE_READINESS).
6. Six themes, Standard / Focused / Large Text, English / Arabic on every screen in scope.
7. Data honesty: default "not synced" everywhere; demo data (simulated iPhone) only via serial `E`; a started ride
   shows "Simulated ride" so values are never mistaken for sensor data.

Milestone C — time: invalid clock hides time **and date**; valid clock shows date/weekday EN/AR; `T`/`R` serial
commands; rollover/leap tests; model interface `Model::setClock()` = the hook the Bluetooth TimeSync will call.
24-hour format only (the approved design shows 24 h; no 12 h setting is specified).

Milestone D — Bluetooth architecture document only (no code, no radio).

Deferred to RC2+ (documented, not silently dropped): Chrono/Pulse faces and picker, complications, Health/Coach/History/
Utilities/Settings pages, ride pages/controls/End/summary, strength/run/walk, notifications, alarms/timers, haptics.

## 4. Process
Everything is built and tested on the computer and in CI; one release candidate with its own file name, SHA-256,
reproducible-build evidence and install/rollback tool is prepared; then one guided hardware acceptance session
(HARDWARE_ACCEPTANCE.md) is proposed for approval. OFFLINE READY ≠ HARDWARE VERIFIED.
