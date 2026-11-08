# Cyclift Watch OS — architecture, screen map, protocol, rep counting, milestones (W0 output)

## 1. Recommended development framework

**PlatformIO + Arduino-ESP32 2.x + LVGL 8.3 + NimBLE-Arduino**, structured as modules (not one sketch):

- Arduino-ESP32 gives the manufacturer-tested drivers (TFT_eSPI GC9A01 profile, BMA4 API, PCF8563, CST816S, QMC5883)
  and a huge example base; ESP-IDF underneath provides OTA rollback, LittleFS, light/deep sleep and NimBLE.
- **LVGL 8** evaluated against the constraints: 240 × 240 × 2 B = 115 KB per frame; internal RAM on the ESP32 is
  ~320 KB with ~200 KB usable for us after Wi-Fi/BLE stacks. A **half-screen draw buffer (57.6 KB) in internal RAM**
  with partial redraws gives smooth arcs and text; PSRAM (2 MB) holds fonts, images, the event queue and caches
  (PSRAM is slower, so no draw buffers there — the manufacturer's config has the same conclusion). Alternatives
  considered: TFT_eSPI-only (fast, but every widget hand-made), u8g2 (monochrome-oriented), a custom renderer
  (months). LVGL wins on widgets (arcs, meters, labels, animations), theming and input handling.
- Host build (`platform = native`) compiles the whole `domain/` on a PC; the tests run there in milliseconds
  (66 checks today, see `firmware/test/host`).

## 2. Module layout (firmware/src)

| Layer | Module | Owns | Hardware-free |
|---|---|---|---|
| hal | `board_pins.hpp`, `hal.hpp` (+ `hal/esp32/*` in W1) | display, touch, IMU, RTC, power, haptics, BLE, storage drivers | interfaces yes, drivers no |
| domain | `activity.hpp` | activity registry · lifecycle · honest timers · metric-source rules | ✓ tested |
| domain | `strength.hpp` | exercise order, supersets, set logging, corrections, undo, rest timer | ✓ tested |
| domain | `rep_detector.hpp` | experimental wrist-motion rep counting with confidence | ✓ tested (synthetic) |
| domain | `coach.hpp` | coaching message protocol, one-primary selection, offline rules | ✓ tested |
| domain | `sync.hpp` | versioned frames (CRC), offline event queue, idempotent dedup, clock sync | ✓ tested |
| domain | `grading.hpp` | fixed four-colour grading (shared rules with the iPhone) | ✓ tested |
| domain | `navigation.hpp` | orbital navigation state machine, live-activity gesture rules | ✓ tested |
| ui | `tokens.hpp` (W1), faces, screens, `lv_conf.h` | LVGL rendering, themes (3 families × 2), micro-interactions | no |
| app | `main.cpp` | boot, module wiring, schedulers, power states, diagnostics | no |
| planned | `power.hpp`, `persist.hpp`, `ota.hpp`, `diag.hpp` | power management, LittleFS persistence, update/rollback, self-test | partly |

Rule: `domain/` includes nothing from Arduino or LVGL; `ui/` reads domain state and sends `Gesture`s; `hal/` is the only
place with register addresses. Tokens are shared with the iPhone's design system (Cyclift / Sport / Bloom × dark /
light; grading colours fixed).

## 3. Screen and navigation map

```
                    QuickSettings  (swipe ↓)        brightness · DND · display mode · battery · link
                          ▲
 Notifications ◄ Progress ◄ [ WATCH FACE ] ► Today ► Recovery          swipe ◄ ►  (major panels)
                          ▼ (swipe ↑)
                      Activities  ─► Prepare ─► [ live activity ] ─► Review ─► Save / Discard ─► Face
                                                   │
                        cycling:  Cockpit ⇄ Navigation ⇄ Performance   (swipe ◄ ►, a ring)
                        strength: Exercise ⇄ Rest                        (swipe ◄ ►)
 Face: tap = complication detail · long press = choose face / complications · BTN3 = Activities · BTN1 = back
```

Live-activity rules (tested): swipe ↑/↓ never leave an activity; Pause / Resume / End (cycling) and Log set / Undo /
Skip rest / End (strength) are drawn on every live view; End opens Review; Review is left only by Save or Discard.
Faces: **Orbit**, **Chrono**, **Pulse** — see `WATCH_FACES.md` and the published face previews.

Adaptive face hierarchy by time and context (directive §3C): morning → sleep + today's session; during an activity the
face is replaced by the live view; after an activity → recovery + results card for 2 h; evening → tomorrow's plan +
bedtime. The hierarchy changes which complications are large, never the face's layout.

## 4. BLE integration design (shared protocol, v1)

One GATT service `CYW` on the watch (peripheral) with two characteristics: `TX` (notify, watch → phone) and `RX` (write
without response, phone → watch), MTU negotiated to 247. Frames: `[ver][type][seq][len][payload][crc16]`
(`sync.hpp`), payload = compact binary fields; message types: Hello (identity, capabilities, protocol version),
TimeSync, Status (battery / phase), PlanToday, Cached (sleep / recovery / HRV summaries with source + timestamp), Live
(power / HR / cadence / speed with age), Gps (timestamped position / speed / heading / distance — mirror only), Coach,
Event (watch → phone with stable `(deviceId, seq, timestamp)`), Ack (cumulative), Error.

Ownership: the **iPhone owns workouts and the plan**; the **watch owns its events until acknowledged** and keeps them in
LittleFS across power loss; the phone's `DedupFilter` makes re-sends idempotent, so a reconnect can never duplicate a
set, a lap or a HealthKit workout (the phone writes Health, once, as today). The iPhone's existing one-recorder-per-ride
rule stays: a ride is recorded by **either** the BikeComputer **or** the phone **or** the watch, never two.

BLE roles to measure in W2: the ESP32 as peripheral to the iPhone while also central to one HR strap / the BikeComputer
(shared radio, connection intervals 30–50 ms). If that proves unreliable, sensors stay on the phone and the watch
receives their values through `Live` — which is the default design anyway.

## 5. Automatic rep counting — realistic strategy

Implemented experimental engine: `rep_detector.hpp` (gravity removal → signed principal-axis signal → smoothing →
hysteresis cycle detection with tempo floor and minimum half-cycle time → plausibility against the running tempo →
confidence). Host results on synthetic wrist motion today: 10 curls → 9 (conf 0.98); 8 fast → 7; 6 slow → 6; two sets
of 8 with a 45 s rest → 15; walking 20 s → 0; five knocks → 0. **Known characteristic: the first rep of a set is
confirmed one cycle late**, so manual +1 / confirm is always offered. Real-world accuracy is unknown until W4.

Where wrist sensing is expected to work: biceps curl, hammer curl, shoulder press, lateral / front raise, upright row,
dumbbell row (one-arm), triceps extension, kettlebell swing. Expected unreliable → offered as manual only: squat, leg
press, deadlift (small wrist cycle), bench press (tested in W4 — the bar path is small but regular), planks / holds,
cable machines with fixed handles.

W4 validation dataset: ≥ 8 exercises × 3 tempos (1.2 / 2 / 4 s) × 3 wrist positions × 2 loads, plus false-movement
recordings (walking, adjusting the watch, re-racking, drinking), recorded on the watch with ground truth typed on the
phone. Acceptance: per exercise ≥ 90 % of sets within ±1 rep **or** the exercise is marked manual-only. Learning from
corrections (§6.9) only as explicit per-exercise parameter updates reviewed with the owner — no on-device learning.

External Polar sensors: their BLE HR profile exposes heart rate and RR intervals; Polar Verity/OH1/H10 expose raw
accelerometer **only through Polar's proprietary PMD service** (documented in Polar's SDK), which an ESP32 central could
subscribe to in principle — treated as an investigation item, not a dependency.

## 6. Milestones, dependencies, acceptance

| Milestone | Scope | Depends on | Acceptance (actual outcomes, not assumptions) |
|---|---|---|---|
| **W0** Hardware audit & recovery plan (this output) | identification, capability matrix, pin maps, programming method, backup/restore, diagnostics, architecture, screen map, faces, rep strategy, BLE design, codebase + host tests | owner identifies revision / compass / T-U2T | owner confirms revision; `backup_factory_firmware.sh` dump + SHA-256 stored (needs T-U2T); host tests green (66/66 today) |
| **W1** Watch OS foundation | boot, display, touch, clock (RTC + sync), navigation, battery, theme system, diagnostics, power states | W0 backup done; **owner authorises flashing** | boots to Orbit face; touch gestures verified on device; RTC drift measured vs phone; 3 faces × 6 appearances render with no clipping; battery voltage read; serial diagnostics; host tests green |
| **W2** iPhone connection | NimBLE service, pairing/reconnect, time sync, status, notifications, today's training, cached recovery data | W1; iPhone companion module (new, on an ios/ branch) | reconnect within 10 s after airplane mode; time within 1 s after sync; today's plan shown with its timestamp; disconnect banner; 48 h soak with no duplicate events |
| **W3** Strength training | exercise display, manual logging, sets, weights, rest timers, supersets, sync to the plan | W2; iPhone plan-event path (same rules as the Watch mirror) | a seeded 3-exercise session logged from the watch appears on the phone with every set once; undo/correct propagate; rest timer haptic |
| **W4** Rep detection | on-device 50 Hz sampling, detector, confirm / correct / undo UI, validation dataset | W3 | per-exercise accuracy table from the dataset; manual-only list; never blocks manual logging |
| **W5** Cycling computer | Cockpit / Navigation / Performance, GPS mirror with age, zones, targets, coach cues, ride controls, post-ride summary | W2; iPhone Ride engine (Checkpoint F) sends steps/targets | one recorder per ride enforced; End always available; GPS age shown; disconnect → recording continues; results match the phone's |
| **W6** Recovery & daily intelligence | sleep / HRV / recovery cards with source + age, schedule, coaching messages | W2; iPhone Checkpoint E (recovery, after Health duplicate/permission fixes) | every card shows source and timestamp; stale > 24 h warns; no invented readiness score |
| **W7** Integrated hybrid athlete | unified history, recommendations, cross-device sync, adaptive faces | W3–W6 | a hybrid day (ride + lift) recorded across phone + watch with no duplicates anywhere incl. Health |
| **W8** Optimisation | battery measurements, low-power modes, reliability, accessibility, hardware validation checklist | W1–W7 | measured battery table; crash-free 7-day soak; device checklist signed by the owner |

Nothing destabilises the iPhone release: the watch workstream lives in `watch/` and on `watch/**` branches, with its own
CI (host tests on Linux; firmware compile check on the PlatformIO ESP32 toolchain — no flashing).

## 7. Tracking

Dedicated **Cyclift Watch tracker** (new workbook, `Cyclift_Watch_Tracker_UPDATES.xlsx`) with one row per capability
and the columns Specified · Designed · Implemented · Unit-tested · Host-tested · Hardware-tested · Integrated ·
Released · Blocked · Deferred, plus dependency columns (iPhone app, Apple Watch, BikeComputer, Apple Health, external
sensors). Blueprint: new lane "LILYGO Watch" with milestones W0–W8. Google Drive: NOT SYNCED until an actual update and
read-back are verified.
