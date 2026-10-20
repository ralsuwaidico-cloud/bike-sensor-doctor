# Test results — Bike Computer v0.11.0, 2026-10-19

versionCode 14 · versionName 0.11.0 · package `com.rashed.bikesensordoctor.debug`, signed with the same committed key as every build
since 51. Review runs on `design/v0.11-auto-coach`: run 83 (commit 0f011cd, approved) and run 85 (new onboarding Step 4): build +
161 unit tests ✓, Android 12 emulator (720 × 1520, 320 dpi — Nokia 5.3 geometry) 9 of 9 flow tests ✓, 1 500-event monkey ✓, no
crash. The release build on main is recorded at the end of this file. Previous report: `TEST_RESULTS_v0.10.md`.

## Onboarding Step 4 replaced (requested from the Nokia, 19 Oct)
"Fitness & zones" (I know my numbers / Estimate for now / Set up later · I know my FTP / Don't know yet) is gone. Step 4 is now
**"Your starting fitness profile"**: Starting FTP from weight × experience with an ESTIMATED FROM EXPERIENCE tag and a one-line
explanation; "Heart-rate zones — We'll learn these when you connect your HR strap" with the note that the age-based estimate is
GENERIC, not a measured threshold; "Your coach will automatically improve these estimates as you ride."; CONTINUE enabled with nothing
entered; "Enter my own FTP (optional)" and "I know my heart-rate numbers (optional)" folded away. An existing tested/estimated FTP is
shown and kept (never replaced by the assumption). No other onboarding page asks fitness questions; the interactive artifact
(version 14) shows the same page. Evidence: docs/evidence/v011-run85-onboarding.png.

## What is new in v0.11 (implemented as approved in artifact version 13)
- **Layout**: three 84 dp gauges in one row (76 dp at large font), value in the centre, TARGET band inside the ring on the same scale;
  graph at half height (118 dp / 96 dp) with a **5-minute averages row** above it (AVG 5 MIN · PWR · HR · CAD); Details view has a
  **window / ride** switch for the averages. Power average counts a real 0 W while coasting and excludes missing seconds ("gaps" note);
  cadence shows the elapsed average and, when different, the pedalling-only average ("86 pedal"); HR only while the strap reported.
- **Starting FTP = weight × W/kg by experience** (Beginner 1.75 · Novice 2.25 · Intermediate 3.00 · Advanced 4.00 · Competitive 5.00),
  shown as **STARTING ASSUMPTION** on onboarding page 4, the summary page, the ME tab and the results, never as a measurement. Applied
  only when no credible FTP exists; a tested or app-estimated value is preserved. Riders never share it (Rashed 300 W, Nora 105 → 180 W
  when her experience changed). With only an assumption the coach never recommends sweet-spot or threshold work.
- **Automatic FTP learning** (per rider): every real ride's 1 Hz power is scanned for the best 1/3/5/8/12/20/30/60-minute efforts
  (no interpolation across gaps). A 20-minute block counts as evidence only if it is steady (CV ≤ 15 %) and clearly harder than the rest
  of the ride (≥ 1.15×). Ordinary endurance rides therefore give **no** FTP evidence. Estimates carry method + confidence
  (ceilings: passive best effort 0.65, 20-min test 0.80, lab 0.95). When the current FTP is an assumption or an earlier automatic
  value, an estimate of at least PROVISIONAL confidence that differs by ≥ 3 % replaces it automatically — up or down — and the ME tab
  explains it in one line ("Your starting FTP 225 W (assumption) → estimated FTP is now 195 W (lower) …"). Over a tested value the app
  only proposes. Simulated rides never enter this path.
- **Meter verification is separate from FTP**: a real meter becomes VERIFIED automatically after ≥ 10 min of plausible pedalling
  packets, ≥ 3 clean coasts (0 W + 0 rpm after pedalling), power present on ≥ 95 % of pedalling seconds, link ≥ 90 %, ≤ 3
  disconnections and no impossible values. This is data consistency, not accuracy; FTP may stay UNKNOWN while the meter is VERIFIED.
  Simulated packets never verify a meter. Zero-offset/calibration remain the XDS app's job.
- **Coach without a strap**: with power only it coaches **relative effort** — your own 10-minute output is the reference; a minute
  < 85 % of it → "Power dropping — keep a steady rhythm", > 1.6× → "Smooth out the surges", within ±10 % → "Good pace — hold this
  effort", every 10 steady minutes a check-in. With cadence only: "No effort sensors" once, cadence cues, "Try to hold a steadier pace"
  on erratic speed, and a time check-in every 10 minutes. No zone claims are made without a strap, and the post-ride message says so
  ("188 W average for 33 min — judged against your own output, not a heart-rate zone").
- **Provenance labels**: MEASURED · CALCULATED · ESTIMATED · SIMULATED · UNVERIFIED · UNAVAILABLE, shown once per screen.
- **Learning stages** on the ME tab: Learning (0–2 real rides) → Understanding (3–7) → Personalised (8+).

## Automated checks (all pass, CI run 83)
Unit (pure Kotlin, 160 tests): starting-FTP table and preservation rules · MMP windows break on gaps · endurance ride ≠ evidence, sustained
effort = evidence, surging block ≠ evidence · policy NONE / AUTO_APPLY (down and up) / PROPOSE, 3 % threshold, history line · meter
verification needs pedalling + coasts + clean values and ignores simulation · relative-effort and sensor-poor coaching vectors ·
coach invariants (nothing while stopped, no gear wording while coasting, no zone wording without HR) · graph scaling, decimation,
breaches, window averages · post-ride ladder incl. the new no-strap messages · performance-engine ceilings and status bands.

Emulator (AppFlowTest, 9 tests, 48 screenshots in docs/evidence/v011-run83-*.png):
t01 onboarding Rashed 75 kg / 3+ yrs → "Starting FTP 300 W" · t01b Nora 60 kg New → 105 W, 1–3 yrs → 180 W, summary shows
STARTING ASSUMPTION, back to Rashed → ME still 300 W (per-rider isolation) · t02 club/board/profile tabs · t03 rider switch isolates
profiles; Omar live screen · t04 full simulated ride: no-scroll live layout, Details graphs + tap readout, results one-message +
expanders, heap growth < 24 MB (13.5 → 16.6 MB) · t04b 999 W / 199 bpm / 120 rpm at 1.0× and 1.3× font: no overlap, no scroll ·
t04c meter silent → "— NO DATA" with no value drawn; strap silent → "— NO STRAP"; gaps visible in graph and Details · t04d power
only: "Good pace — hold this effort", "Power dropping — keep a steady rhythm", no zone wording, results SIMULATED with no estimates
section; cadence only: "No effort sensors", "Pedal a little faster", "You have been riding for 10 minutes" · t05 restart keeps data.

## Bugs found and fixed by these runs (runs 75–82)
compile error in meter verification (run 75) · onboarding summary ignored the starting assumption (76) · **5-minute graph and
averages carried over from the previous ride** (77 — 999 W from the extremes ride showed as a 489 W average; buffer now cleared at
ride start) · cadence-only simulation stood still so the coach stayed silent (80) · 10-minute check-in lost when another cue spoke
(82) · a stray emulator "launcher isn't responding" pop-up (79, test now dismisses it).

## Untested — needs your phone or hardware
- Automatic meter verification and automatic FTP learning with the **real XDS meter** (only unit-tested and emulator-tested with
  real-data rules; the simulator is deliberately excluded from both).
- Real HR strap, GPS pace, voice output; Nokia 5.3 rendering of the 84 dp gauges (emulator geometry only).
- Battery/thermal behaviour over a 2-hour ride.

## Not in this release (unchanged scope)
Cloud-backed rider accounts and sync (design in ARCHITECTURE_V2.md §6) · critical-power / LTHR auto-estimation beyond the engine's
existing methods · any layout change beyond the approved artifact version 13.

## Release build — CI run 86 on main (commit fbb608f), 19 Oct 2026
`BikeComputer-build86.apk` · 17.97 MB · SHA-256 `f80d0e979394a1a8f6e12e94020b52c85238d18f6f60e0816f2a06bb941b2262` (matches the published
apk.sha256) · package `com.rashed.bikesensordoctor.debug` · versionCode 14 · versionName 0.11.0 · minSdk 26 / targetSdk 34.
Pre-publish checks requested on 19 Oct:
1. Complete suite on main: build + 161 unit tests ✓ · Android 12 emulator 9/9 flow tests ✓ · 1 500-event monkey ✓ · no app crash (the one
   FATAL in logcat is the emulator's own System UI at boot, process com.android.systemui).
2. Signing: APK v2 signing certificate SHA-256 `E2:51:4D:05:46:C2:55:A6:DA:1A:6F:AA:28:69:7A:01:2A:A1:F9:DD:FE:CD:80:EF:84:41:C9:74:C9:76:1E:4F`
   = the committed `keystore/debug.keystore` (androiddebugkey) used by every build since 51, including the installed v0.10.0 build 74 → in-place update.
3. Data preserved: same package id + same key, versionCode 13 → 14; riders, settings, FTP values and ride history live in the app's own
   storage, which Android keeps on an in-place update; t05 (restart keeps data and settings) passes; no store migration changes in v0.11.
4. Starting-FTP assumptions are tagged STARTING ASSUMPTION / ESTIMATED FROM EXPERIENCE everywhere they appear and are applied only when the
   profile has no FTP or an earlier assumption (`StartingFtp.applyIfMissing`; unit-tested with tested/estimated values preserved; t01b).
5. Simulated rides: FTP evidence, MMP, qualifying efforts, automatic FTP policy and meter verification all require `RideSource.DEVICE` /
   a real sensor; leaderboards count DEVICE rides only; results show SIMULATED and no estimates section (t04d, unit tests).
6. Coaching without a strap: power-only and cadence-only profiles coached on the emulator (t04d) with no zone wording; missing sensors
   show "— NO DATA" / "— NO STRAP" with no value drawn (t04c); averages exclude missing seconds; 0 W counts only as a real coasting zero.
APK built from commit fbb608f = the commit the emulator job tested in the same run.

## v0.11.1 — full-screen live dashboard (CI run 90 on main, commit 02a160e, 20 Oct 2026)
Requested from the Nokia photo: gauges too small, graph too short, empty band above the coach. Root cause in `LiveScreen.kt`: fixed 118 dp
graph + `Spacer(weight 1f)` + hard-coded 84 dp rings + a 51 dp link row (Material 48 dp touch target). Now: ring = (screen width − 28 dp) / 3
− 6 dp (104 dp on 360 dp; 92 dp at 1.3× font), value text scales with the ring, the graph takes all remaining height (167 dp on the
emulator at 1.0×, 132 dp at 1.3×; more on the phone, whose status bar is smaller than the emulator's 68 dp), coach 2 dp below the graph,
link row 32 dp. The flow test now fails if graph→coach > 12 dp or coach→controls > 16 dp and logs the geometry (docs/evidence/
v0111-run89-layout.txt). Evidence: docs/evidence/v0111-run89-live-before-after.png. Nothing outside the live layout changed.
Release: `BikeComputer-build90.apk` · 17.97 MB · SHA-256 `e75a99cad6543a2cf3f9b91d60656a2094f9038d430143ee9312181a8d208596` · versionCode 15 ·
versionName 0.11.1 · same signing certificate `E2:51:4D:…:1E:4F` · build + 161 unit tests ✓ · emulator 9/9 ✓ · monkey ✓ · no app crash ·
APK from the commit the emulator tested.

## v0.12.0 — real riders, dashboard layouts (CI run 95 on main, commit 9068b4f, 20 Oct 2026)
Approved from run 94 (docs/evidence/v012-run94-*.png, geometry in v012-run94-layout.txt).
- **Riders**: no sample riders on a real install (none created; folders from older installs hidden); "Welcome to Bike Computer → Create
  rider profile" on first run; "Who's riding today?" with large cards and a fixed "+ ADD NEW RIDER"; optional PIN asked only when set;
  Developer / Test mode switch in Settings (off by default) shows the fictional riders and demo club.
- **Dashboard Layout** (Settings, per rider, presentation only): Power Focus (default for new riders; existing riders keep Classic),
  Classic Three Gauges, Compact Metrics. Power-Focus geometry is computed in the portable core (`DashLayout.kt`, unit-tested for no
  overlap on 300–480 dp widths); the live block height is measured, not estimated. Emulator at 360 × 760 dp: Power Focus 147 / 100 dp
  rings + 104 dp graph (1.3×: 132 / 92 + 93 dp), Classic 104 dp rings + 170 dp graph, Compact 224 dp graph.
Release: `BikeComputer-build95.apk` · 18.0 MB · SHA-256 `05b2fa85e985ad0d2308c1655967527308d6d1c5eb6e3543fd39eed4589fcdb7` · versionCode 16 ·
versionName 0.12.0 · signing certificate `E2:51:4D:…:1E:4F` (unchanged since build 51) · build + 165 unit tests ✓ · emulator 9/9 ✓
(fresh install, three real riders, PIN, per-rider FTP and layout, layout switch mid-ride, samples hidden/shown, restart persistence) ·
1 500-event monkey ✓ · no app crash · APK from the commit the emulator tested. Rider storage format unchanged (meta.txt/answers.txt);
the layout choice is an extra key in each rider's own answers file, so profiles, FTP history, rides and settings carry over untouched.
