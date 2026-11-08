# ASSETS — manifest

Everything here is a **copy of an existing file** (nothing redrawn). The source path is the authoritative one.
Branch for watch files: `watch/w0-foundation` @ ca2cadb6; for BikeComputer files: `fw/phonefirst` @ c0a10fb0
(also present on `ios/dev`). Artifact URLs are claude.ai pages the owner can open.

## Published artefacts (not files — URLs)

| Artefact | URL | Content |
|---|---|---|
| Cyclift Watch Gallery v2 | https://claude.ai/artifact/TCR2NAoVkwB1UhRvbpFMGn | every v2 screen in six appearances, before/after v1→v2, text sizes, memory estimates (labelled estimates), limitations |
| Cyclift Watch Faces (page) | https://claude.ai/artifact/53hvVZuQVJJC8qiSWVSh58 | Orbit · Chrono · Pulse concepts and complication rules |
| Cyclift Watch Faces (doc) | https://claude.ai/artifact/9M2kJLHRYa4oNocjtKBzVL | same, as a document (also exported as `Cyclift_Watch_Faces_for_ChatGPT.md`) |
| Cyclift Blueprint v6.5 | https://claude.ai/artifact/WKZ5Qv3JJFWtQsqZ6iuuW4 | programme‑level status incl. CP‑W (watch) and BikeComputer rows |
| Ride · clickable prototype / Ride flow revised design (iPhone, 7 Nov) | canvases referenced in the trackers (APP‑028 notes) — **URLs not recorded in the repo**; the implementation on `impl/checkpoint-f-ride` is the surviving reference | iPhone, not a device asset |

## Watch (LILYGO)

| Copy in this package | Source |
|---|---|
| `ASSETS/watch/gallery-v2.html` | `watch/docs/gallery-v2.html` (Design v2 gallery, approved baseline) |
| `ASSETS/watch/round-gallery.html`, `round-gallery-1/2.png`, `ride-gallery-1/2.png` | `watch/docs/…` — **Design v1 (rejected 8 Nov 16:07), kept for before/after** |
| `ASSETS/watch/watch-faces.html` | `watch/docs/watch-faces.html` (W0 face concepts) |
| `ASSETS/watch/TEXT_SIZES.md` | `watch/docs/TEXT_SIZES.md` (measured text sizes per screen) |
| 59 native 240×240 PNGs below | `watch/docs/native/*.png` (rendered from the gallery SVGs at native resolution) |
| not copied (6.1 MB, 1 464 files) | `watch/firmware/gallery-out/{short,long,german,extreme}/<Appearance>/*.svg` + `REPORT.md` — per‑scene SVG evidence of the 0‑finding run |
| design tokens | `watch/firmware/src/domain/theme_tokens.hpp` (six appearances + fixed grading colours) |
| navigation / button diagrams | text diagrams in `watch/docs/ARCHITECTURE.md` §3 and `watch/docs/BUTTONS.md` (no separate image files exist) |
| animation specification | `watch/docs/WATCH_FACES.md` "Micro‑interactions" and `CYCLING_INSTRUMENT.md` (arc fill ≤ 400 ms on wake, haptic tick, no looping animation) — text only |

| Native PNG | Source |
|---|---|
| `ASSETS/watch/native/face-chrono--arctic.png` | `watch/docs/native/face-chrono--arctic.png` |
| `ASSETS/watch/native/face-chrono.png` | `watch/docs/native/face-chrono.png` |
| `ASSETS/watch/native/face-orbit--arctic.png` | `watch/docs/native/face-orbit--arctic.png` |
| `ASSETS/watch/native/face-orbit.png` | `watch/docs/native/face-orbit.png` |
| `ASSETS/watch/native/face-pulse--arctic.png` | `watch/docs/native/face-pulse--arctic.png` |
| `ASSETS/watch/native/face-pulse.png` | `watch/docs/native/face-pulse.png` |
| `ASSETS/watch/native/live-lift-controls.png` | `watch/docs/native/live-lift-controls.png` |
| `ASSETS/watch/native/live-lift-exercise--arctic.png` | `watch/docs/native/live-lift-exercise--arctic.png` |
| `ASSETS/watch/native/live-lift-exercise-key2.png` | `watch/docs/native/live-lift-exercise-key2.png` |
| `ASSETS/watch/native/live-lift-exercise.png` | `watch/docs/native/live-lift-exercise.png` |
| `ASSETS/watch/native/live-rep-counter.png` | `watch/docs/native/live-rep-counter.png` |
| `ASSETS/watch/native/live-rest-timer.png` | `watch/docs/native/live-rest-timer.png` |
| `ASSETS/watch/native/live-ride-cockpit-full--arctic.png` | `watch/docs/native/live-ride-cockpit-full--arctic.png` |
| `ASSETS/watch/native/live-ride-cockpit-full.png` | `watch/docs/native/live-ride-cockpit-full.png` |
| `ASSETS/watch/native/live-ride-cockpit-gps-stale.png` | `watch/docs/native/live-ride-cockpit-gps-stale.png` |
| `ASSETS/watch/native/live-ride-cockpit-hr-only.png` | `watch/docs/native/live-ride-cockpit-hr-only.png` |
| `ASSETS/watch/native/live-ride-cockpit-key1hold-full.png` | `watch/docs/native/live-ride-cockpit-key1hold-full.png` |
| `ASSETS/watch/native/live-ride-cockpit-key2-full.png` | `watch/docs/native/live-ride-cockpit-key2-full.png` |
| `ASSETS/watch/native/live-ride-cockpit-low-power.png` | `watch/docs/native/live-ride-cockpit-low-power.png` |
| `ASSETS/watch/native/live-ride-cockpit-no-sensors.png` | `watch/docs/native/live-ride-cockpit-no-sensors.png` |
| `ASSETS/watch/native/live-ride-cockpit-north-up.png` | `watch/docs/native/live-ride-cockpit-north-up.png` |
| `ASSETS/watch/native/live-ride-cockpit-off-route.png` | `watch/docs/native/live-ride-cockpit-off-route.png` |
| `ASSETS/watch/native/live-ride-cockpit-paused.png` | `watch/docs/native/live-ride-cockpit-paused.png` |
| `ASSETS/watch/native/live-ride-cockpit-phone-lost.png` | `watch/docs/native/live-ride-cockpit-phone-lost.png` |
| `ASSETS/watch/native/live-ride-cockpit-power-no-ftp.png` | `watch/docs/native/live-ride-cockpit-power-no-ftp.png` |
| `ASSETS/watch/native/live-ride-controls-full.png` | `watch/docs/native/live-ride-controls-full.png` |
| `ASSETS/watch/native/live-ride-controls-paused.png` | `watch/docs/native/live-ride-controls-paused.png` |
| `ASSETS/watch/native/live-ride-navigation-full--arctic.png` | `watch/docs/native/live-ride-navigation-full--arctic.png` |
| `ASSETS/watch/native/live-ride-navigation-full.png` | `watch/docs/native/live-ride-navigation-full.png` |
| `ASSETS/watch/native/live-ride-navigation-gps-stale.png` | `watch/docs/native/live-ride-navigation-gps-stale.png` |
| `ASSETS/watch/native/live-ride-navigation-hr-only.png` | `watch/docs/native/live-ride-navigation-hr-only.png` |
| `ASSETS/watch/native/live-ride-navigation-low-power.png` | `watch/docs/native/live-ride-navigation-low-power.png` |
| `ASSETS/watch/native/live-ride-navigation-no-sensors.png` | `watch/docs/native/live-ride-navigation-no-sensors.png` |
| `ASSETS/watch/native/live-ride-navigation-north-up.png` | `watch/docs/native/live-ride-navigation-north-up.png` |
| `ASSETS/watch/native/live-ride-navigation-off-route.png` | `watch/docs/native/live-ride-navigation-off-route.png` |
| `ASSETS/watch/native/live-ride-navigation-paused.png` | `watch/docs/native/live-ride-navigation-paused.png` |
| `ASSETS/watch/native/live-ride-navigation-phone-lost.png` | `watch/docs/native/live-ride-navigation-phone-lost.png` |
| `ASSETS/watch/native/live-ride-navigation-power-no-ftp.png` | `watch/docs/native/live-ride-navigation-power-no-ftp.png` |
| `ASSETS/watch/native/live-ride-performance-cadence-full.png` | `watch/docs/native/live-ride-performance-cadence-full.png` |
| `ASSETS/watch/native/live-ride-performance-hr-full.png` | `watch/docs/native/live-ride-performance-hr-full.png` |
| `ASSETS/watch/native/live-ride-performance-hr-hr-only.png` | `watch/docs/native/live-ride-performance-hr-hr-only.png` |
| `ASSETS/watch/native/live-ride-performance-power-full--arctic.png` | `watch/docs/native/live-ride-performance-power-full--arctic.png` |
| `ASSETS/watch/native/live-ride-performance-power-full.png` | `watch/docs/native/live-ride-performance-power-full.png` |
| `ASSETS/watch/native/live-ride-performance-power-gps-stale.png` | `watch/docs/native/live-ride-performance-power-gps-stale.png` |
| `ASSETS/watch/native/live-ride-performance-power-low-power.png` | `watch/docs/native/live-ride-performance-power-low-power.png` |
| `ASSETS/watch/native/live-ride-performance-power-no-sensors.png` | `watch/docs/native/live-ride-performance-power-no-sensors.png` |
| `ASSETS/watch/native/live-ride-performance-power-north-up.png` | `watch/docs/native/live-ride-performance-power-north-up.png` |
| `ASSETS/watch/native/live-ride-performance-power-off-route.png` | `watch/docs/native/live-ride-performance-power-off-route.png` |
| `ASSETS/watch/native/live-ride-performance-power-paused.png` | `watch/docs/native/live-ride-performance-power-paused.png` |
| `ASSETS/watch/native/live-ride-performance-power-phone-lost.png` | `watch/docs/native/live-ride-performance-power-phone-lost.png` |
| `ASSETS/watch/native/live-ride-performance-power-power-no-ftp.png` | `watch/docs/native/live-ride-performance-power-power-no-ftp.png` |
| `ASSETS/watch/native/live-ride-performance-target-full.png` | `watch/docs/native/live-ride-performance-target-full.png` |
| `ASSETS/watch/native/menu-activities.png` | `watch/docs/native/menu-activities.png` |
| `ASSETS/watch/native/menu-settings.png` | `watch/docs/native/menu-settings.png` |
| `ASSETS/watch/native/panel-coach.png` | `watch/docs/native/panel-coach.png` |
| `ASSETS/watch/native/panel-hrv.png` | `watch/docs/native/panel-hrv.png` |
| `ASSETS/watch/native/panel-notifications.png` | `watch/docs/native/panel-notifications.png` |
| `ASSETS/watch/native/panel-recovery.png` | `watch/docs/native/panel-recovery.png` |
| `ASSETS/watch/native/panel-sleep.png` | `watch/docs/native/panel-sleep.png` |

## BikeComputer (Waveshare)

| Copy in this package | Source | What it is |
|---|---|---|
| `ASSETS/bikecomputer/device_design_r1.html` | `design/device/device_design_r1.html` | design round 1 (23 Oct): onboarding, navigation A/B/C, number/name entry, ride dashboards A/B/C — the approved options are recorded in `docs/DEVICE_DESIGN_DECISIONS.md` |
| `ASSETS/bikecomputer/bike_designs.html`, `coach_demo.html` | `design/` | Android‑era (Nokia app) dashboard and coach demos that preceded the device |
| `ASSETS/bikecomputer/v3_phone.png`, `v3_cue_a/b.png` | repo root | Nokia Design 7 reference renders (three‑gauge dashboard, coach cues) |
| `ASSETS/bikecomputer/build51…run94 PNGs` | `docs/evidence/*.png` | Android app screenshots by build (history of the dashboards that the Waveshare designs inherited) |
| **not recoverable as files** | firmware LVGL simulator renders (`test/sim`, `python3 sheet.py out`) are **regenerated on demand**, not committed; CI job summaries list screens/checks; the owner's real‑device photos (e.g. the "Sensors" photo of 0.6.0 rev 1) were shared in chat and are not in the repo |
| fonts | `firmware/waveshare/main/fonts/bc_num80/60/44.c`, `bc_bold22/16.c` (bitmap C arrays) |

## Trackers and QA (local files, copied)

| Copy | Source |
|---|---|
| `ASSETS/trackers/Cyclift_BikeComputer_Tracker_UPDATES.xlsx` | `/home/claude/cyclift-mcc/sync-2026-11-07/` (built by `content.py`/`build_sync.py`; "NOT SYNCED" to Drive) |
| `ASSETS/trackers/Cyclift_LilyGoWatch_Tracker_UPDATES.xlsx` | same folder (`build_lilygo_tracker.py`, 40 capabilities CW‑001…CW‑040) |
| `ASSETS/qa-firmware/FIRMWARE_REVIEW_RC1/2/3/5.md`, `FIRMWARE_FINDINGS*.csv` | `/home/claude/qa-fw/` (independent QA of 0.7.4 rc1–rc5, host/simulator only) |

Not in this package: the owner's PC folder `Documents/BikeComputer` (kits, 16 MB backups, board logs) — too large and
personal; it stays on the owner's PC, with copies attached to the original session.
