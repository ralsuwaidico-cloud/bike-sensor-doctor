# Cyclift ride layouts — what existed before and what each restored layout comes from

Cyclift 1.0 (workstream A4, branch `ios/cyclift-ride`). The live ride screen offers five layouts, chosen in
**Ride › ⚙ Ride settings › Ride layout** or with the quick switch (the layout name at the top of the ride screen).
The choice is stored in `AppSettings.rideLayout` (default `coach`; older stores without the key decode to `coach`).
Switching only writes that setting — the recorder, the SensorHub and Bluetooth are never touched, so a layout can be
changed in the middle of a ride without interrupting recording or sensors (`RideLayoutTests`).

Every layout embeds the same **CoachPanel** (rule-based "Coach", optional *Why?*), the same header (link state, ride
time, workout target, POWER UNVERIFIED / FTP PROVISIONAL tags, Details ›) and the same controls, and fits one screen
without scrolling from iPhone SE (375 × 667 pt) to Pro Max at the default text size. Live metrics come only from
`SensorHub.reading(_:)`; a missing metric reads "No power source" / "No heart-rate source" / …; labels name the metric
("POWER · W") and the source is printed separately from `reading.sourceLabel`.

## 1. Audit: ride dashboards that existed

### Nokia Android app (`app/src/main/java/com/rashed/bikesensordoctor/`)
| When | Commit(s) | Files | Dashboard |
|---|---|---|---|
| v0.6.0 | `83cd451` "Design 7 — AI Scientific Coach dashboard" | `ui/Design7.kt`, `ui/Dashboard.kt` (`DashboardScreen`, `Gauges()`) | Large power gauge (62 % width) on top, RPM and BPM gauges side by side below, big coach box with EASE · ON TARGET · FASTER, power/HR zone bars, power trend, stats. Mock-up `v3_phone.png` (+ `v3_cue_a.png`, `v3_cue_b.png` for the coach box); design #7 "AI Scientific Coach" in `design/bike_designs.html`. |
| v0.7–0.9 | `cddd7a4`, `c51a420`, `09d2dbe`, `daccdcf` "fixed no-scroll live screen" | same + `ui/CoachWidgets.kt` | Same gauges; coach v3 with gear intelligence; v0.9 made the live screen one screen without scrolling and moved the rest to Details. |
| v0.10.0 | `127142c`, `d78145c` "four-section live dashboard with combined normalised graph, metric cards, compact coach" | `ui/LiveScreen.kt`, `ui/LiveGraph.kt` (`CombinedGraph`), `core/LiveGraph.kt` | Top stats, three **metric cards** (number + target bar), the **combined live graph** of W / BPM / RPM normalised to each target band, compact coach line. |
| v0.10–0.11 | `9337d94` "hybrid live dashboard: compact Design-7 circular gauges replace the metric cards", `04fed0c`, `92f03f8` "width-sized gauges, graph takes the remaining height", `f98baf8` | `ui/LiveScreen.kt`, `ui/D7Widgets.kt` (`CompactGauge`) | **Three compact rings in one row** (power, heart rate, cadence) with LIVE dot and target band, combined graph filling the rest, compact coach. |
| v0.12 | `ded8e28` "Power Focus gauge layout …, per-rider Dashboard Layout setting (Power Focus / Classic / Compact)", `5132c1a`, `e607bb5` | `core/DashLayout.kt` (`DashLayout`, `PowerFocus`), `ui/LiveScreen.kt`, test `app/src/test/.../core/DashLayoutTest.kt` | Selectable: **POWER_FOCUS** (large power ring top, cadence + HR tucked below, computed non-overlapping geometry), **CLASSIC** "Classic Three Gauges" (the v0.11 three-ring row), **COMPACT** "Compact Metrics" (the v0.10 number cards). Mid-ride switching + persistence tests. |

### iOS app (`ios/BikeComputer/RideView.swift`, `RideDashboard.swift`)
| Build | Commit | Dashboard |
|---|---|---|
| 0.3.0 (build 17) | `6efd177`, `ca51f1b` | **Classic tile grid**: three status chips, six `MetricTile`s (first one large) chosen in `TilePicker`, zone bar, controls, map and sensors (scrolling). |
| 0.3.1 (build 21) | `968d263` | Same tile grid. |
| 0.4.0 (build 24) | `5264a2f` | Same tile grid + coach line and table. |
| 0.5.0 (build 27) / 0.5.1 (build 30) | `084d1c6`, `8d65916` | **Power-Focus port** of Nokia v0.12 (three `TargetGauge`s, `CoachBox`, `LiveGraphView`, stats, controls, no scrolling); tiles/map/sensors moved behind Details. 0.5.1 fixed the geometry hang (0-size first layout pass): bounded loops, safe fallback, no dashboard before a real size. Unchanged through builds 33/36/40. |

The ESP32 board has its own on-device ride layouts A/B/C (`BCLink.SettingsMessage.rideLayout`, Device settings);
those are the board's screen and are unrelated to the phone layouts below.

## 2. Restored layouts and where each comes from

| `RideLayout` | Name in the app | Restored from | Implementation (reused components) |
|---|---|---|---|
| `coach` | Ride Coach | iOS 0.5.x Power-Focus dashboard = Nokia v0.12 `POWER_FOCUS` | `PowerFocus.compute` geometry, `TargetGauge` ×3, `LiveGraphView`, `RideStatsRow` (`DashStat`). The coach box is now the shared `CoachPanel`. |
| `gauges` | Large gauges | Nokia Design 7 `DashboardScreen` gauges (v0.6–0.9, `v3_phone.png`) | Big power `TargetGauge` on its own row, heart-rate and cadence gauges side by side, one-line stats; sizes from `RideFit.largeGauges`. |
| `classic` | Classic | iOS builds 17–24 tile grid (and Nokia `COMPACT` number cards) | `MetricTile` grid, six tiles from `store.tiles` (`TilePicker`, reachable from Ride settings and Details); tiles built by `RideTiles.tile`, shared with the Details sheet. |
| `rings` | Rings | Nokia v0.11–0.12 compact three-ring hybrid dashboard (`DashLayout.CLASSIC` "Classic Three Gauges") | Three equal `TargetGauge`s in one row, power and HR `ZoneBandView`s (dropped first on short screens), small `LiveGraphView`, stats; `RideFit.rings`. |
| `analytics` | Analytics | Nokia v0.10 combined normalised live graph (`CombinedGraph`) | `LiveGraphView` (W / BPM / RPM against their own target bands) as the main element, three big numbers with their sources, power zone band, stats. |

All five read the same `RideLive` snapshot (built from the hub), the same `RideCoach` (engine `CoachEngine` from
`Shared/CoachCore.swift`, unchanged; vectors pass) and the same `RideRecorder`. Nothing is drawn before the screen
has a real size and every fitting computation is bounded (`RideFit`, `PowerFocus`).

## 3. Coach panel (all layouts)
- Instruction from the existing engine, worded for the panel (`CoachWording`): *Maintain current effort*, *Increase
  cadence slightly*, *Shift to an easier gear*, *Reduce intensity to return to Zone N*, *Recover for the next interval* …
- Follows today's ride: target zone from the workout kind; threshold and VO2 sessions run the engine's interval mode
  (work / recovery blocks); strength or rest days coach a free Zone 2 ride.
- Uses only live hub readings (stale readings ignored). Unverified power → advice marked PROVISIONAL; assumed FTP →
  FTP PROVISIONAL. Heart rate only, cadence only, speed only or nothing → matching guidance (perceived exertion, which
  sensors would help).
- *Why?* shows the rule with the values the engine used. Rate limit (`CueGate`): a cue stays on screen ≥ 15 s; only a
  safety ease-off, a lost sensor or a phase change cuts in. No notifications or speech are added.
