# 04 — UI/UX design system (approved interfaces, themes, screens, interactions)

Two devices, two very different screens with the same 240×240 round glass. The **BikeComputer** UI was designed on the
device‑first premise (touch only, no keys, handlebar at arm's length); the **Watch** UI was designed as a wrist glance
with two keys. They share the Cyclift tokens (three families × dark/light) and the **fixed grading colours**.

## Shared design tokens

| Family | Dark | Light | Watch token values (`watch/firmware/src/domain/theme_tokens.hpp`) |
|---|---|---|---|
| Cyclift | Midnight Blue | Arctic | dark: bg #0A1628 · card #122240 · card2 #1A2F55 · text #EAF2FF · mut #A7BAD6 · line #1E3357 · accent #4FD1FF · accent2 #9CE3FF · onAccent #06111A — light: bg #EEF5FB · card #FFFFFF · card2 #DCE8F3 · text #0B1A33 · mut #3F5574 · line #C9D8E8 · accent #0B6E9E · accent2 #1C8FC4 |
| Sport | Graphite | Steel | dark: bg #101214 · card #1B1F24 · text #F2F4F6 · mut #AEB6BF · accent #FF6A00 — light: bg #E9ECEF · text #111417 · accent #B84800 |
| Bloom | Plum | Rose | dark: bg #1E1024 · card #2C1838 · text #FBEFF7 · accent #FF8FB8 — light: bg #FBF0F5 · text #2A1230 · accent #A82B64 |

**Grading colours (never theme tokens, identical in all six appearances):** light canvas red #B91C1C · yellow #9A5A00
· light blue #0E6B8C · green #1B7A3E; dark canvas red #FF5A5A · yellow #FFB64D · light blue #5BD0F5 · green #56E08C.
Meaning: far off · adjust · on target · achieved; every graded value also carries a word or icon. (The iPhone's
Checkpoint H uses the same values — `ios/APPEARANCE_AND_GRADING.md`, branch `impl/checkpoint-h-appearance`.)

Note: the iPhone's own neutral palettes (Checkpoint H `CyAppearance`) differ slightly in hex from the watch tokens above;
both are "Cyclift / Sport / Bloom × dark / light" but were tuned per screen size. Reconciling them is a design task for
the new conversation — do not change the watch tokens unilaterally; the gallery's 0‑finding contrast evidence depends on them.

## A. BikeComputer screens (approved, implemented in firmware `main/ui/*.c`, rendered by `test/sim`)

Design round 1 (`design/device/device_design_r1.html`, 23 Oct) → approved decisions in `docs/DEVICE_DESIGN_DECISIONS.md`:

| Screen | Approved behaviour | File |
|---|---|---|
| Onboarding | Welcome → Name (letter ring) → Age / Weight (spinning wheel) → Experience → Main goal → Power meter → HR strap → Wi‑Fi → Ready; height in Settings only | `ui_onboard.c` |
| Home | START RIDE (hold to confirm) + Connections / History / Settings; status line meter · HR · battery; FTP with PROVISIONAL label | `ui_home.c` |
| Ride | three installed designs chosen in Settings › Display › Ride screen with preview, switchable mid‑ride: **A Power Focus** (default: big watts + power arc), **B Split** (watts top, cadence \| HR below, coach word), **C Coach First** (instruction leads, ring colour = on target / more / less); since Link 1.3 the **Cyclift coach card** on every design; pull‑down control panel: hold 1 s PAUSE · tap RESUME · hold 2 s END | `ui_ride.c` (`DESIGNS[]`), `ui_common.c` |
| Results | SAVE (tap) / discard (hold the bin 1.5 s); offline rides queue for the phone | `ui_results.c` |
| Connections (replaced "Sensors" in 0.6.0 rev 2) | phone, Wi‑Fi, power meter, HR, CSC; discovery; device sync; "Bluetooth unavailable" state with reason | `ui_conn.c`, `ui_phone.c`, `ui_wifi.c` |
| Power / Quick Settings | screen‑off (recording preserved), touch lock, deep sleep outside rides, battery estimate "≈"; charging alerts "unavailable" | `ui_power.c`, `docs/POWER_0.5.0.md`, `CHARGE_ALERTS.md` |
| Recovery mode | staged boot after crashes, subsystem disabled after two consecutive crashes, "Directory corrupted" | `ui_recovery.c`, `bc_boot.c` |
| Diagnostics / Tools | Device Health, Sensor Test (REAL/SIMULATED), Self‑test, SEND LOG TO PC, report transfer | `ui_tools.c`, `app_diag.c` |
| Demo mode | orange DEMO badge, separate history, never changes FTP, off after restart | all screens |

Typography: bitmap fonts `main/fonts/bc_num80/60/44.c` (numerals), `bc_bold22/16.c`. Touch rules (0.6.0 rev 3):
any‑touch wake with the wake gesture swallowed + 400 ms guard; hold‑to‑confirm for every ride‑changing action.
Evidence of rendering: simulator sheets (`test/sim/sheet.py`), 339 screens / 701 checks on rc5 (not hardware).

## B. Watch screens (Design v2, approved 8 Nov 16:44) — `watch/docs/*`, gallery `watch/docs/gallery-v2.html`

Geometry (`ROUND_LAYOUT.md`): usable radius 114 px; chord‑aware bands; control row fixed at y 160–204; minimum fonts
lead 20 · complication 12 · body 13 · label/unit 11 · button 12; a word wider than its box never fits; ellipsis only
with a More control; critical text never truncated (coach cue ≤ 44 chars at a word boundary).

| Screen | One question | Elements (v2) | Native PNG |
|---|---|---|---|
| Face **Orbit** | what time is it, what matters next | two arcs with tracks (load = accent, recovery = grade colour), 54 px clock, date + battery line, next activity 14 px, ONE legend line | `native/face-orbit.png`, `--arctic` |
| Face **Chrono** | analog glance | real hands 32/46 px in a 54 px hub, three dials at r 78 (next, load, recovery), tick ring, digital time + date between lower dials | `native/face-chrono.png` |
| Face **Pulse** | the one insight | 56 px digital time, one insight card (graded dot + ≤ 22 chars) + More, thin status bar | `native/face-pulse.png` |
| **Cockpit** | how am I performing now | status indicator · one dominant number (58 px) + large unit · 270° orbital gauge (zone ladder, target band, position dot, interval arc 140–220°) · ≤ 2 secondary metrics · one command ≤ 16 chars · one Pause pill (paused → Resume + End) | `native/live-ride-cockpit-*.png` (10 fixtures: full, hr‑only, power‑no‑ftp, low‑power, off‑route, gps‑stale, phone‑lost, no‑sensors, north‑up, paused) |
| **Performance** | how has my effort changed | one large chart per page (power · HR · cadence · target vs actual), value + 30 s trend, axis min/max, band + mid‑line, now marker, page dots | `native/live-ride-performance-*.png` |
| **Navigation** | where am I, where next | auto‑scaled dial (2–25 m/px), breadcrumb, route ahead, next‑turn dot, N, scale bar, one state line; states A tracking · B route · C disconnected | `native/live-ride-navigation-*.png` |
| Ride controls overlay | — | Lap · Pause/Resume · End (confirms) · Why? | `native/live-ride-controls-*.png` |
| Strength **Exercise** / **Rep counter** / **Rest timer** / **Controls** | log this set | exercise name header, set i/n, target reps × weight, dominant rep count with AUTO confidence or MANUAL, Log set / Correct, rest countdown + Skip | `native/live-lift-*.png`, `live-rep-counter.png`, `live-rest-timer.png` |
| Prepare · Confirm End · Review · Face picker · Today · Recovery · Sleep · HRV · Coach · Notifications/Timers · Quick settings · Activities | — | lifecycle and panels; quick settings = Brightness · Appearance · Do not disturb (44 pt rows) | gallery only |

Status words (never merged): PHONE LOST · NO GPS · GPS STALE n s · GPS n s; no route · on route · OFF ROUTE n m.
Commands (priority): PHONE LOST → EASE OFF / HOLD mid W / PUSH TO mid W → CADENCE UP/DOWN → HR ABOVE/BELOW TARGET / HOLD HR lo–hi → INTERVAL mm:ss.

Interactions (`BUTTONS.md`): Key 1 / Key 2 / Boot mapping per context (table in the doc); **two‑press system** — first
press shows a chip "KEY 2 · LAP · press again", second press within 2.5 s executes; a different key replaces the preview;
haptics 15/40/60 ms; touch Pause is immediate; End always confirms. Micro‑interactions: arc fill animates once on wake
(≤ 400 ms), haptic tick on gesture completion, **no looping animation**.

Text sizes measured (`TEXT_SIZES.md`): smallest label 11 px ≈ 1.5 mm, body 12–14 px, lead values 54–58 px ≈ 7.3–7.8 mm
on the 32.5 mm panel. Acceptance: 1 464 scenes (61 screens × 6 appearances × 4 text variants), **0 findings** —
overflow, overlap, contrast, truncation, touch size, grading invariance (`watch/firmware/test/host/gallery.cpp`).

Design v1 (rejected 16:07) is preserved for before/after comparison: `watch/docs/round-gallery.html`,
`round-gallery-1/2.png`, `ride-gallery-1/2.png`; the gallery‑v2 page carries the before/after section.

## Design decisions log (both devices)

- BikeComputer: `docs/DEVICE_DESIGN_DECISIONS.md` rounds 1–2 (23 Oct), `docs/FIRMWARE_0.6.0.md` (root causes of the
  owner's 0.5.0 findings and the resulting UI rules), Link 1.3 coach card (`coord/interfaces/BLE_CONTRACT.md` §5).
- Watch: owner directives of 8 Nov 15:14 (W1 strictness), 15:31 (cycling redesign, two‑press E), 16:07 (v2 directive
  — 12 points), 16:44 (v2 approved as baseline; "no more gallery cycles unless real‑device testing reveals a problem"),
  18:07 (paused), 19:04 (iPhone Cockpit hierarchy — applies to the phone; the watch Cockpit v2 is unchanged).
