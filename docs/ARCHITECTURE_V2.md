# Bike Computer — Architecture v2 and acceptance tests (P0–P5)

Revised 2026-10-12 after the v0.6.0 coaching assessment. Objective: a **reliable, scientifically sensible** cycling
coach that improves endurance and measures genuine progress. Nothing is called "AI" until an adaptive or AI component
actually exists.

## 1. Module map

```
┌───────────────────────────── Android app (Kotlin / Compose) ──────────────────────────────┐
│  ui/        Dashboard (Design 7), Coach, History, Report, Settings, Verify-power screen   │
│  ride/      RideEngine (orchestrator), SensorManager, RideService, RideHistory, Prefs,    │
│             GpsTracker, Checkpoint (ride survives app restart)                            │
│  ble/       GattManager (XDS link), HrSensor (standard HR strap), scanner, parsers        │
├─────────────────────────────── core/ — PORTABLE, no Android imports ──────────────────────┤
│  XdsDecoder      packet → sample (+ plausibility)                                         │
│  RideStats       ride state machine, 3 s/10 s power, NP/VI, SIGNAL STATE (fresh/stale/0)  │
│  LinkMonitor     packet rate, gaps (start/end/reason/activity-before-drop), quality %     │
│  LoadVerifier    "power under load" test logic (pass/fail criteria, no guessing)          │
│  Zones, Targets  zone maths, below/on/above target, gauge positions                       │
│  Session         phase model: WARMUP → MAIN (/ RECOVERY intervals) → COOLDOWN             │
│  CoachEngine     P1 multi-signal, deterministic decision engine (replaces v0.6 engine)    │
│  HealthClassifier, ConnectionPolicy, BleStandard                                          │
└───────────────────────────────────────────────────────────────────────────────────────────┘
                                   ▲ same inputs / same outputs ▲
┌──────────────────────── ESP32-S3 firmware (C++, later) ────────────────────────────────────┐
│  core re-implemented 1:1 in C++; verified against the SAME test vectors (testvectors/)     │
└───────────────────────────────────────────────────────────────────────────────────────────┘
```

**Rule:** anything that *decides* lives in `core/` and is deterministic (same inputs → same outputs, no clocks, no
randomness, no I/O). Android code only collects inputs and draws outputs. This is what makes the ESP32 port a
re-implementation rather than a redesign — Kotlin will not run on the ESP32, so the contract is the test vectors,
not the source.

### Data flow (1 Hz)
```
XDS packet ──► XdsDecoder ──► RideStats.onSample ──┐
                              LinkMonitor.onPacket │
HR strap ───► BleStandard.heartRate ───────────────┤
GPS ─────────────────────────────────────────────── ┼──► RideEngine.refresh()
                                                   │      ├─ Session.phaseAt(elapsed)
                                                   │      ├─ CoachEngine.update(CoachInput)  → cue (or none)
                                                   │      └─ Dashboard snapshot → UI / TTS
                                                   └──► Checkpoint (every 10 s) + CSV append
```

### Shared test vectors (`testvectors/`)
Plain text, one file per scenario, trivially parsed in Kotlin and C:
```
# name: hr-above-target-eases-off
# config: mode=ZONE2 ftp=200 maxHr=185 cadence=on cadLow=85 cadHigh=95 hrHoldMs=8000 powerHoldMs=2000
# t_ms,phase,cad,hr,pw,expect          (blank = no value; expect blank = not asserted; "NONE" = must be silent)
0,MAIN,90,150,140,NONE
9000,MAIN,90,150,140,EASE_OFF
```
`CoachVectorTest` (JUnit) runs every file; the ESP32 build will run the same files through its C++ engine.
A vector only passes if the cue type matches on every asserted tick. Adding a vector = adding a requirement.

## 2. Phase plan and acceptance tests

Each test is tagged **[SIM]** (runs in CI/JUnit, simulated inputs) or **[DEVICE]** (needs Rashed on the bike;
never claimed done until observed). A phase is complete only when all its [SIM] tests pass *and* its [DEVICE]
tests have been performed and recorded in `docs/TEST_RESULTS.md`.

### P0 — Reliability
| ID | Test | Type |
|---|---|---|
| P0-1 | **5-minute drop:** the next ride log records, for every disconnect, the GATT status, the gap length, and whether the cranks were turning / power > 0 in the 15 s before the drop. This decides between "sensor sleeps on pedaling pause" (expected) and "sensor sleeps under zero load even while spinning" (needs a different mitigation). | [DEVICE] |
| P0-2 | Mid-ride disconnect → app re-latches with `autoConnect=true`; data resumes ≤ 10 s after the cranks turn again, no 20 s stalls. | [DEVICE] |
| P0-3 | **Ride survives:** RideStats snapshot/restore round-trip is lossless (elapsed, sums, max, NP accumulator, zone time). | [SIM] |
| P0-4 | Kill the app mid-ride → reopen → ride is restored PAUSED with its elapsed time, averages and CSV samples intact; one tap resumes. | [DEVICE] |
| P0-5 | **Zero vs missing:** signal state is `FRESH` (packet ≤ 4 s old, power > 0 or cranks turning), `COASTING` (fresh packet, 0 W, cranks still), `STALE` (> 4 s), `NONE` (never). Coasting never counts as "below target"; stale never counts as any value. | [SIM] |
| P0-6 | LinkMonitor: 60 packets in 60 s = 100 %; a 20 s hole = one gap of 20 s, quality 67 %; gap records activity-before-drop correctly. | [SIM] |
| P0-7 | Ride report shows link quality %, number of gaps, seconds lost, and each gap's "pedaling before drop: yes/no". | [SIM]+[DEVICE] |
| P0-8 | **Power under load:** LoadVerifier passes only with ≥ 10 plausible packets where cadence > 30 rpm **and** power ≥ 40 W within a 60 s window; passes never on spinning with 0 W. | [SIM] |
| P0-9 | On the bike, under real resistance, the Verify screen reports PASS with a credible max watts; the dashboard "POWER UNVERIFIED" tag disappears. | [DEVICE] |

### P1 — Intelligent real-time coaching
| ID | Test | Type |
|---|---|---|
| P1-1 | HR above target (held 8 s) → EASE OFF, regardless of what power or cadence say. | [SIM] |
| P1-2 | HR below target but power already at/above target → **no PUSH** (HR lag); engine stays silent. | [SIM] |
| P1-3 | HR below target and power below target → PUSH after 8 s hold. | [SIM] |
| P1-4 | HR on target, power surging ≥ 1 zone above for 6 s → EASE OFF ("power surging"). | [SIM] |
| P1-5 | No HR strap → power-only logic with 2 s holds; coasting (0 W) → silent, never "push". | [SIM] |
| P1-6 | Cadence low while HR above target → EASE OFF wins, no PEDAL FASTER; cadence low while effort is on target → PEDAL FASTER. | [SIM] |
| P1-7 | Cadence disabled → never a cadence cue. Cadence range is editable. | [SIM] |
| P1-8 | Stale signals are treated as absent (a 20 s hole in HR does not freeze the last value). | [SIM] |
| P1-9 | WARMUP phase → no PUSH; a WARM UP cue once; EASE OFF only if HR ≥ 2 zones above target. COOLDOWN → COOL DOWN once; no PUSH. | [SIM] |
| P1-10 | Hysteresis: HR oscillating ±1 bpm across a zone boundary produces at most one cue change, not flapping. | [SIM] |
| P1-11 | Anti-repeat: same cue ≥ 45 s apart; KEEP IT UP ≥ 90 s apart; a changed cue ≥ 10 s after the previous. | [SIM] |
| P1-12 | 60-min Zone 2 scenario vector (warm-up, Z2, cadence drop, hill, recovery, finish) produces exactly the expected cue sequence. | [SIM] |
| P1-13 | On a real ride the cues match what the gauges show and no instruction contradicts the previous one within 10 s. | [DEVICE] |

### P2 — Training personalisation
| ID | Test | Type |
|---|---|---|
| P2-1 | HR zone boundaries editable (5 bands) and FTP editable; defaults are visibly flagged **UNVERIFIED DEFAULT** until the user changes them. | [SIM]+[DEVICE] |
| P2-2 | Session phases (warm-up / main / recovery / cool-down) configurable; phase shown on the dashboard. | [SIM] |
| P2-3 | The app never changes FTP or max HR on its own from ordinary rides (no auto-detection code path exists). | [SIM] |
| P2-4 | Guided tests (20-min FTP, HR ramp) — only after P0-9 passes. | later |

### P3 — Performance analysis
| ID | Test | Type |
|---|---|---|
| P3-1 | Watts at similar HR: given two rides with ≥ 20 min in HR Z2, report the mean power in Z2 for each and the delta; refuse (flag) when either ride has < 10 min in zone or link quality < 90 %. | [SIM] |
| P3-2 | Aerobic decoupling (Pw:Hr first half vs second half) computed only when the main phase is ≥ 40 min, steady (VI ≤ 1.06), with < 5 % data loss; otherwise "not comparable" with the reason. | [SIM] |
| P3-3 | Time in target zone, longest continuous Z2 block, consistency (CV of 5-min power) in every summary. | [SIM] |
| P3-4 | Post-ride summary in plain English lists what was done, what it means, and any reliability caveats. | [SIM]+[DEVICE] |

### P4 — Adaptive training (transparent rules)
| ID | Test | Type |
|---|---|---|
| P4-1 | Suggestion rules are readable in one file and every suggestion states its rule ("3 Z2 rides ≥ 60 min this week with decoupling < 5 % → extend next ride by 10 min"). | [SIM] |
| P4-2 | Training-load model enabled only when ≥ 14 days of rides with link quality ≥ 90 % exist. | [SIM] |

### P5 — Optional AI
| ID | Test | Type |
|---|---|---|
| P5-1 | With the network off, every real-time cue still works identically (vectors pass with the LLM layer disabled). | [SIM] |
| P5-2 | LLM output is labelled as such and never changes a target, zone or cue. | [SIM] |

## 3. P1 decision engine — specification

Inputs per tick: `nowMs`, `phase`, cadence / HR / power each as `(value, fresh)`; config: mode, target zone,
zone tables, cadence on/off + range, hold times, hysteresis.

```
1. Smooth: 5 s rolling mean per fresh signal. Stale (> 4 s) or absent ⇒ unavailable (window cleared).
2. Band state per effort signal with hysteresis (±2 % of max HR / FTP): BELOW · ON · ABOVE.
3. Phase gate:
     WARMUP  → PUSH forbidden. WARM UP cue once. EASE OFF only if HR ≥ target+2 zones (held 5 s).
     COOLDOWN→ PUSH forbidden. COOL DOWN cue once. EASE OFF if HR ABOVE (held).
     RECOVERY→ RECOVER once; EASE OFF if power ABOVE target (held).
     MAIN    → steps 4–6.
4. Effort (safety first, HR is the authority when present):
     HR ABOVE (held 8 s)                                  → EASE OFF
     HR ON  & power ABOVE by ≥ 1 zone (held 6 s)          → EASE OFF  "power surging — HR will follow"
     HR BELOW & power ON/ABOVE                            → silent    (HR lag; never push)
     HR BELOW & (power BELOW or unavailable) (held 8 s)   → PUSH
     no HR: power ABOVE (2 s) → EASE OFF; power BELOW (2 s) → PUSH; 0 W → silent
     neither → NO SIGNAL (info, 30 s)
5. Cadence (only if enabled, cranks turning, and step 4 chose nothing and HR not ABOVE):
     < low−3 held 5 s → PEDAL FASTER;  > high+3 held 5 s → PEDAL SLOWER   (±3 rpm hysteresis)
6. Otherwise KEEP IT UP — once on entering "all good", then at most every 90 s.
7. Emission: changed cue ≥ 10 s after last; same cue ≥ 45 s; KEEP IT UP ≥ 90 s; info ≥ 30 s.
```
Every cue carries a `reason` code (e.g. `HR_ABOVE`, `HR_LAG_HOLD`) so a log or a test can explain *why*.

## 4. What is simulated vs. verified on the device
- All [SIM] tests run in CI on every build (JUnit) and locally before each release.
- [DEVICE] tests are performed by Rashed; results are written to `docs/TEST_RESULTS.md` with the log file name.
- A feature's status in release notes is one of: **simulated-only**, **device-verified**, **not implemented**.

## 5. Findings from the ride-replay demonstration (2026-10-13, design/coach_demo.html)
Three real Apple Fitness rides (30 Sep, 5 Oct, 12 Oct) were replayed through the v0.7 engine with simulated power/cadence.
- **Repeat policy is too aggressive.** With HR above target for 45 min, the engine repeats EASE OFF every 45 s (~60 cues).
  P1 follow-up for v0.8: after 3 unheeded repeats of the same cue, go quiet (gauges keep showing the state) and speak again
  only on a state change or every 5 min. Add a vector for it.
- **Default zones would make every real ride "above target".** Max-HR-185 zones give Z2 = 111–129 bpm; Rashed's rides
  average 150–156 bpm. P2 calibration (editable zones, LTHR-based option) is required before HR coaching is useful.
- **Power cannot be inferred from speed/HR.** The physics model gave ~80 W average at 19.7 km/h; a coherent demo needed a
  140 W "demo FTP". Only the XDS verified under load (P0-9) resolves this.

## 6. Multi-rider accounts, clubs and leaderboards — production proposal (2026-10-13)

Prototyped in `design/coach_demo.html` (sign-in / create account with optional PIN, switch rider, four SAMPLE riders,
club with invite code and challenges, leaderboard with six metrics, per-rider coaching from the same replay). The APK is
unchanged.

### 6.1 Principles
- **One rider, one record.** Profile, answers, zones, FTP, coach config, sensor pairing, rides and feedback live under a
  rider id. The active rider id is stamped on a ride at start and never changes. No code path reads another rider's
  private data.
- **Fair boards only.** Ranked: weekly/monthly distance, riding time, elevation, ride count, optional Zone 2 discipline
  (each rider judged against their own band). Never ranked: power, speed, heart rate. Simulated or replayed values are
  flagged (`source != "device"`, `verified=false`) and excluded from any real board.
- **Private by default.** HR, zones, FTP, weight are not shared; a per-field share flag opens them to a club.
- **Offline first.** The Nokia records and coaches with no network; sync is a background job that can fail silently.

### 6.2 Simplest practical architecture
| Layer | Choice | Notes |
|---|---|---|
| Device store | Room/SQLite on Android; LittleFS records on ESP32 | Tables: riders, profiles, rides (immutable, UUID), samples (optional), feedback, sync_queue |
| Auth | Managed provider (Supabase Auth or Firebase Auth): e-mail/password + Google | Tokens cached; app works signed-in-offline indefinitely |
| Backend | Supabase (Postgres + row-level security + edge functions) — or Firebase equivalent | RLS: a rider reads own rows plus club members' *shared* columns via a view |
| Tables | riders, profiles, rides, clubs, memberships, invites, challenges, board_snapshots | `rides.source ∈ {device, import}`, `verified` set by server from sensor provenance |
| Leaderboards | Server-computed per club/period from verified rides only; scheduled job rolls week (Mon) and month | Device caches the last snapshot |
| ESP32-S3 | BLE relay through the phone app: rides up, profile/zones/config down; optional Wi-Fi later | Same ride-record format as Android (portable core) |

### 6.3 Conflict-free sync
- Rides: append-only, idempotent upload keyed by UUID. Re-sending is harmless; nothing edits a ride after upload.
- Profile fields: last-writer-wins per field with timestamps; fields flagged `verified` (tested LTHR, verified FTP) are
  never overwritten by estimates (existing rule "never overwrite verified values with simulated estimates").
- Feedback/answers: append-only log folded into the profile on the device.
- Club membership, invites, challenges: server-authoritative; device keeps a read-only cache.

### 6.4 Development stages and acceptance
1. **Local accounts in the APK** — rider list, switch before ride, per-rider prefs/ride files. *Accept:* two riders ride
   back-to-back; each ride file, prefs and zones belong to the right rider; switching mid-ride is blocked.
2. **Onboarding + personal coach** — port the six-page onboarding and `deriveConfig` rules; profile drives `CoachEngine`
   config. *Accept:* test vectors per rider config; same replay → different cue counts as in the prototype.
3. **Cloud sign-in + sync** — profiles and rides; offline queue; conflict rules above. *Accept:* airplane-mode ride syncs
   later exactly once; verified fields survive a stale-estimate upload.
4. **Clubs + leaderboard** — invites, membership, server boards, verified-only rule. *Accept:* a replay/simulated ride
   never appears on a board; week/month rollover tested with a fixed clock.
5. **ESP32 relay** — BLE sync via phone. *Accept:* ride recorded on ESP32 appears under the correct rider on the phone
   and in the cloud.
6. **Verified challenges** — only after the power meter is verified under load and an FTP-test protocol is fixed.
