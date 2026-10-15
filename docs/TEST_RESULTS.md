# Test results — Bike Computer v0.10.0, 2026-10-14

Candidate: `BikeComputer-build69.apk` · versionCode 13 · versionName 0.10.0 · package `com.rashed.bikesensordoctor.debug`
SHA-256 `4dd3bb38b618533d7cdc8e46cae3f05cf16f0648077908d7e56eadbb3766dd11` — the identical file that passed every check below
(CI run 69: build → Android 12 emulator test → release, all green). Signed with the same committed key as builds 51–61, so it
installs over them with riders, rides and settings kept. **Held for design approval — not yet delivered.**

## What is new in v0.10
- **Live dashboard redesigned** (hybrid of Design 7 and the compact layout, approved 15 Oct) into four sections on one fixed Nokia 5.3 screen (no scrolling):
  A ride info (speed · distance · time · phase chip) · B three compact Design-7 circular gauges (power cyan / heart rate green / cadence violet) — LIVE dot and TARGET band on one numerical scale, value in the centre, unit in the dial opening — and a
  status word (▲ ABOVE · ● ON TARGET · ▼ BELOW · ○ COASTING · — NO DATA — never colour alone) · C the combined graph (power cyan,
  HR green, cadence violet; last 5 minutes) · D a compact coach line (icon · short instruction · short reason · "analysed N s ago").
  PAUSE / FINISH / COOL stay at the bottom; Details · Home · ⚙ beneath.
- **Combined graph with scientific scaling** (see below), a fixed 600-sample ring buffer, peak-preserving min/max decimation,
  gaps for missing data, 0 W kept as a real zero, ≥ 20-s breaches shaded, phase changes marked, missing-signal legend.
- **Details view**: three separate traces in real units with the target band as it was at each second, 1 / 5 / 10-minute windows,
  tap or drag for the exact readings at that second, and the full coach reasoning (the live screen shows the short form).
- **Coach communication**: one message first — headline (the achievement or the gap), verdict, one next step, a progress bar against
  the 80 % goal — with "Why?", "Detailed analysis" and "How was this calculated?" folded away. One recommendation at a time, picked
  by a ladder (no HR → free ride → time in target → drift → pacing → cadence → recovery → praise). Beginner wording by default;
  riders who said "experienced" (or choose technical detail) get the numbers added to the details. MEASURED / ESTIMATE / SIMULATED /
  UNVERIFIED tags once at the top of the results, not repeated. Ride details, heart rate, power & cadence, speed & elevation and
  fitness estimates are expanders. ME tab: today's workout first, targets with one tag, progress card, profile and "still to learn"
  behind expanders. Home: the workout with one sentence, "Why this workout?" and "How the coach will guide it" behind expanders.
- **Coach v3.1**: sudden power spike (> 1.5× the band top for 3 s) → "Smooth out the surges"; a minute of power swinging ±20 % around an
  on-target average → "Hold a steadier effort"; the first "all good" after an ease-off → "Good — back on target"; "Settle into your
  target" when the main block starts; "Power sensor disconnected — coaching from heart rate" / "Heart-rate sensor disconnected —
  coaching from power" said once; nothing at all while stopped; no gear wording while coasting. Short live-screen wording for every
  instruction ("Ease off — HR above target" / "HR 158 vs 139–151 bpm").
- **Performance engine (threshold-engine 2.1)**: FTP, critical power and threshold HR are separate metrics; each estimate carries its
  method, evidence, a confidence capped by the method's ceiling (FTP20 0.80, passive best-20-min 0.65, 30-min HR field test 0.70,
  age-based 0.20, laboratory 0.95 …) and a status (UNKNOWN / GENERIC / PROVISIONAL / HIGH / VERIFIED — only a laboratory source can be
  VERIFIED). Simulated, unverified or poor-quality data is inadmissible. One field test is PROVISIONAL; two agreeing tests HIGH; a weak
  method repeated 100× stays PROVISIONAL. Proposals read "FTP estimate may have increased · Current 205 W · Candidate 214 W ·
  Confidence High · Evidence …", never "your FTP is now 214 W"; a tested profile value is never overwritten by a weaker estimate;
  estimates change only between rides. CP is fitted from ≥ 3 maximal efforts (P = CP + W′/t) and never relabelled FTP.
- **Sensor policy** in one place: power/cadence stale after 4 s (one missed XDS packet tolerated), HR after 6 s, GPS 10 s.

## How the combined graph is scaled
Watts, bpm and rpm never share an axis. Each line is scaled by its **own** function against **its own target band at the time of
the sample** (0 = lower edge, 1 = upper edge):
- power ÷ the current power target (or, when the meter is unverified / no workout power target, a labelled *reference* band —
  "PWR 3s ref 111–150 W" — so the trace is still shown but never called a target);
- heart rate ÷ the current HR target (warm-up and cool-down ramps included, so old points are not bent by a later band);
- cadence ÷ the rider's preferred range.
The grey TARGET strip is the same height (28 % of the plot) for all three: inside it = on target. One strip height equals the
width of that signal's band (the legend prints the numbers, e.g. 34 W · 12 bpm · 15 rpm). The scale stays linear for one more
band height above and below, then compresses toward the edge, so 999 W still sits visibly above 300 W without flattening the
normal range. Missing readings are gaps (never joined, never filled); a true 0 W while coasting is drawn as a value. Shaded areas
mark ≥ 20 s outside the band for HR and power. Dashed verticals mark phase changes. Exact values are on the cards above the
graph and in Details. Power on the live graph is the 3-second mean (gaps are not bridged); Details draws the raw 1 Hz series.

Performance: the graph reads the engine's ring buffer directly (no copies), redraws once per new sample, reuses its Paths, and
when samples outnumber pixel columns each column keeps its minimum and maximum. The recorded ride is a separate 1 Hz series that
display downsampling never touches. Sensor acquisition and recording run in the engine, independent of drawing.

## Automated checks (all pass, CI run 69)
| Layer | Count | What |
|---|---|---|
| Core unit tests (JVM, CI + local) | 149 | coach vectors (16 files, 1,502 assertions); coach patterns (spike, unsteady, recovery wording, short wording); **property tests** over 90,000 random ticks: HR over the ceiling never yields increase-effort / harder-gear, power above target never a harder gear, stopped or coasting never a pedalling or gear cue, power never cited alone without a loaded reading, replay deterministic; live-graph core (per-signal scaling, band mapping, status incl. zero-as-value, ring buffer, 3-s mean not bridging gaps, band-at-the-time, decimation keeping peaks and gaps, sustained breaches, fallback bands); coach summary (example wording, too easy, praise + progression by feel, detail levels, no-HR / free ride, provenance); performance engine (FTP20 protocol, inadmissible evidence, one test provisional, two tests high but capped, weak method ×100 stays provisional, strongest method wins, lab-only VERIFIED, CP recovers synthetic CP/W′ and stays separate from FTP, threshold-HR plateau rules, meaningful-change rule); ride analysis, calibration, leaderboard, profile |
| Emulator (API 31, 720×1520, 320 dpi) — `AppFlowTest` | 7/7 | sign-in → onboarding → home → club/board/member/ME → rider switch (Omar's live screen, Layla) → simulated 60-min ride at 30× (warm-up, MAIN, cool-down, pause/resume, background/foreground) → Details graphs (1/5/10-min, tap readout) → results (coach message, Why?, heart-rate and power expanders) → questions → next workout → history → restart; **extremes** 999 W · 199 bpm · 120 rpm; **system font 1.3×**; **sensor drop-outs** (meter silent → "— NO DATA" on power and cadence, strap silent → "— NO STRAP", gaps in the graph, app alive); settings; no-Bluetooth live screen; 42 screenshots |
| Layout assertions (every live-screen visit, 8 visits) | 11 tags + 3 geometry | no scrollable container; speed/distance/time/phase, all three cards, legend, graph, coach box and headline visible without a gesture; graph above the coach box, ≥ 1/7 of the screen high; coach box above the controls, controls inside the screen; no section overlaps the one above |
| Memory (hour-long ride at 30×) | heap KB start 12,374 · main 15,180 · cool-down 14,888 | −292 KB over the ride after GC (limit 24 MB): the ring buffer is fixed, drawing allocates nothing per frame |
| Stress / crash | — | 1,500 monkey events clean; no FATAL in the app process; crash recorder empty |
| APK | — | installs on API 31; version/package confirmed; SHA-256 matches the tested artifact; signed with the committed key; new classes present in the dex |

## Visual review of the real build (docs/evidence/build68-*.png)
Fixed before this candidate: the power trace was missing whenever the meter was unverified (now a labelled reference band); axis
labels at the right edge collided with the newest points (moved left); the zone-table time column wrapped ("1:02:58"); the
accessibility tree used by the test harness went stale on the continuously updating live screen (Compose only announces changes
when it believes an accessibility service is enabled — the test switches that on; the app itself is unchanged for real users).
Remaining nits: at 1.3× system font the legend truncates ("PWR 3s ref 111–1…") and the status line ellipsises "PWR UNVERI…".

## Untested — needs your phone or hardware
- Nokia 5.3 itself (the emulator matches resolution/density/Android 12, not the chip, fonts or Bluetooth stack).
- XDS/Branta meter: pairing, 5-min reconnect, Verify Power under load (and therefore all power-based coaching, calories from power,
  FTP evidence — the app keeps these off until the meter passes verification); a real meter drop-out and reconnect.
- Heart-rate strap, HR recovery after FINISH, the guided threshold test (the 30-minute field assessment is implemented in the engine
  but the guided workout in the app is still the 20-minute test, labelled FIELD_20MIN_HR with a 0.65 ceiling).
- Outdoor GPS: speed/distance/elevation and the route drawing. Voice (TTS). Landscape (locked to portrait).

## From the specification — done now / not in this release
Done on the phone: sensor provenance and quality flags (SIMULATED / UNVERIFIED / stale limits); SIM/unverified data impossible to
use for FTP/LTHR; FTP, CP and threshold HR as separate metric types with method, evidence, confidence ceiling and status;
confidence/provenance visible; deterministic, replayable real-time coach with one primary instruction per tick; 60-second
assessment; event-driven corrections within seconds; HR ceiling vetoes increase-effort (property-tested); cadence learned from
steady on-target riding (median) with the profile range as the provisional band; gear direction only from valid power + cadence,
never while coasting or stopped; zones never move during a ride; rider switching blocked during an active ride; rides fully
offline; Nokia layout tests; hardware limits reported separately.
Not in this release (server work, designed in docs/ARCHITECTURE_V2.md §6): cloud accounts and authentication, the sync outbox and
idempotent upload, the REST API, cross-account tests, server-computed leaderboards, the AI explanation service. Also not yet: the
guided 30-minute HR assessment as an in-app workout, maximal-effort tracking to feed the CP model, and cue-success learning.
