# Test results — Bike Computer v0.9.0 (build 61), 2026-10-14

Release APK: `BikeComputer-build61.apk` · versionCode 12 · versionName 0.9.0 · package `com.rashed.bikesensordoctor.debug`
SHA-256 `a3f1cf4a9116c7b199ef395fa19c9ca9f4def38746368779e7f0146d75584385` — the identical file that passed every check below
(CI run 61: build → Android 12 emulator test → release, all green). Signed with the same committed key as builds 51–60, so it
installs over them with riders, rides and settings kept.

## What is new in v0.9
- **Live screen is one fixed Nokia screen, no scrolling**: speed · distance · time on top; power / HR / cadence gauges with LIVE
  dot, TGT band and status pill; one line of active targets; the coach panel takes the remaining height; PAUSE / FINISH / COOL
  (or COACH) and Home · Details · ⚙ at the bottom. Zone bands, power trend, statistics and link quality moved to **Details**.
- **Ride Results** — one scrolling page: summary (duration, moving time, distance, avg/max speed, elevation, max HR, avg/max power,
  cadence, calories ESTIMATE with method, effort, cues) + GPS track; heart-rate graph with zone shading and the target band, avg/max,
  1-minute recovery, time in **your** zones with bpm bounds and %, optional **Apple Fitness reference zones** (labelled, never used
  for coaching); power graph with FTP line, NP, time in power zones, cadence graph; speed and elevation graphs; **AI coach review**
  (objective, in-band %, longest block, consistency, drift with validity note, what went well / could improve); calibration cards;
  the two questions → next workout with the reason.
- **Coach v3**: practical instructions chosen by one priority ladder (sensor validity → effort vs targets → cadence → gear →
  encouragement): *Shift to an easier / harder gear · Reduce pressure on the pedals · Increase your effort slightly · Pedal a little
  faster · Slow your pedalling · Keep your cadence steady · Hold this pace · Your effort is stable, maintain this rhythm · Your heart
  rate is rising, ease off · Start your cooldown*. Gear is inferred from cadence + power (never measured). Coasting/stopped → no
  pedalling or gear instruction. Per-instruction spacing (no ping-pong), back-off after 3 unheeded repeats, quiet/normal/often
  presets. The panel shows the action icon, one explanation, the live numbers it used, which signals decided, and the 60-second
  assessment with an "analysed N s ago" indicator.
- **Calibration with evidence rules**: FTP = 95 % of best 20-min power, only from a verified meter and only when two rides agree
  within 5 % (one ride = "1 of 2 collected"); threshold HR only from the guided 20-minute test (one test → PROVISIONAL, two within
  3 bpm → CONFIRMED); measured values are never overwritten; "zones may be too low" flag after three easy rides mostly above band.
- **Learning**: natural cadence (median), sustainable power, HR at usual effort, endurance, in-band trend, recovery — shown in the
  ME tab, and the learned cadence feeds the coach after three real rides when none was entered.

## Automated checks (all pass)
| Layer | Count | What |
|---|---|---|
| Core unit tests (JVM, CI + local) | 117 | coach vectors (16 files, 1,502 assertions); §9 scenarios: low cadence + high power, high cadence + low power, HR rising at steady power, HR above + cadence below, power below + HR above, coasting, stopped, missing HR, missing power, sensor drop-out, different profiles, phase transitions, non-contradiction, repetition limit, 60-s assessment, frequency presets; ride analysis (zones, NP, moving time, calories, drift validity, elevation, recovery, CSV round-trip); calibration evidence rules; leaderboard; profile rules |
| Emulator (API 31, 720×1520, 320 dpi) — `AppFlowTest` | 6/6 | sign-in → onboarding → home → club/board/member/ME → rider switch (Omar, Layla) → simulated 60-min ride at 30× (warm-up, MAIN, cool-down; pause/resume; background/foreground) → results page → questions → next workout → history → restart; **extremes** 999 W · 199 bpm · 120 rpm; **system font 1.3×**; 35 screenshots |
| Layout assertions (every live-screen visit) | 4 | no scrollable container on the live screen; speed/distance/time, all three gauges, target line, coach box and headline visible without any gesture; coach box sits above the controls, controls inside the screen |
| Stress / crash | — | 1,500 monkey events clean; no FATAL in the app process; crash recorder empty |
| APK | — | installs on API 31; version/package confirmed; SHA-256 matches the tested artifact; signed with the committed key |

## Apple Fitness comparison (12 Oct ride fixture)
Reference values you gave: 1:05:05, 21.46 km, 19.7 km/h, 150 bpm avg, 91 ft, 509/617 kcal, effort 6/10; Apple zones 26:46 / 21:02 /
15:56 / 01:20 / 00:00 with bands <150, 151–160, 161–169, 170–178, 179+.
- The app reproduces Apple's **zone boundaries and labelling** exactly (reference set `APPLE_12_OCT`, shown separately from your own
  coaching zones and never used for coaching).
- Our heart-rate trace of that ride is read from your chart (26 key points, interpolated), not from the watch's second-by-second
  data. Zone totals from that trace: 29:47 / 23:40 / 8:37 / 3:01 / 0:00 — same ordering, same total, but Z3 is under-read by about
  7 minutes because short excursions above 161 bpm are smoothed out by the interpolation. On the phone the app uses the strap's
  real 1 Hz data, so this difference does not apply to real rides; it is a fixture-quality limit, documented in `RideAnalysisTest`.
- Calories are **estimates** either way: from measured power (kJ ≈ kcal) once the meter is verified, else Keytel from heart rate
  (needs weight and age in the profile). Apple's active/total split uses its own models; equality is not claimed.
- Elevation: GPS altitude with a 3 m threshold vs Apple's barometer — expect differences on flat routes.

## Visual review of the real build (screenshots in docs/evidence)
Fixed before release: gauge sub-labels overflowing the small rings (now ≤ 8 characters), coach panel clipped at 1.3× font (headline
steps down, assessment line yields), average speed above max speed in accelerated simulation (series now records every riding second).
Remaining nit: at 1.3× system font the EASE · ON TARGET · FASTER scale row touches the bottom of the coach panel.

## Untested — needs your phone or hardware
- Nokia 5.3 itself (emulator matches resolution/density/Android 12, not the chip, fonts or Bluetooth stack).
- XDS/Branta meter: pairing, 5-min reconnect, Verify Power under load (and therefore all power-based coaching, calories from power,
  FTP evidence — the app keeps these off until the meter passes verification).
- Heart-rate strap, HR recovery after FINISH (needs the strap to keep reporting for a minute), the guided threshold test.
- Outdoor GPS: speed/distance/elevation and the route drawing (emulator GPS is a fixed point).
- Voice: TTS on the phone.
- Landscape: the app is locked to portrait (as before).

## Assumptions (your earlier "adaptive coach" message arrived after this build was designed)
- "Every 60 seconds" = a display assessment (progress, trends, in-band share) once a minute; instructions themselves still use 5-s
  smoothing and 8-s holds so a sustained excess or a phase change is answered within seconds, as you asked.
- Zones never change automatically; the app only *suggests* a provisional FTP / threshold with the evidence shown, and you confirm.
- Gear instructions use cadence + power only; the app does not know the selected gear.
