# BikeComputer iPhone + Apple Watch — changelog

## 0.5.1 (build 30) — 25 Oct 2026 — TestFlight, internal testers only — HOTFIX

**Fixes the launch crash of build 27** (black screen, app killed immediately) on phones that already had data from
build 24. Nothing else changes; profile, plan, rides and settings are untouched.

- **Cause**: the Ride dashboard's gauge-layout fitting loop. At launch all five tabs are laid out at once and SwiftUI's
  GeometryReader reports a 0 × 0 size on its first pass for the hidden Ride tab; the dashboard subtracted its padding
  (−28 pt), the loop's square root became NaN, every comparison was false and the loop never ended — the main thread
  hung and iOS's watchdog killed the app before the first screen appeared. A fresh install never showed the Ride tab
  (onboarding comes first), which is why it only hit updated phones.
- **Fix**: degenerate or non-finite sizes return a safe fallback layout at once, both loops are bounded, and the Ride
  tab draws nothing until it has a real size. Regression test with widths −28 … 159, NaN and ∞ must finish in < 0.5 s.
- **Pipeline**: a new launch smoke test runs the **Release** build on the simulator before every archive — fresh
  install (Welcome must appear) and an upgrade from a build-24-shaped store (Home must appear, then all five tabs are
  opened). Any launch crash or hang now fails CI instead of reaching TestFlight. Run 29 reproduced the hang with it.

### Known limitations
Unchanged from 0.5.0 (below).

## 0.5.0 (build 27) — 25 Oct 2026 — TestFlight, internal testers only

Everything below is **simulator-tested** (62 XCTest cases in GitHub Actions, 0 failures — including the 16 shared coach
vector files from the Nokia app, which the Swift coach engine now passes byte for byte). **Nothing new in this build is
real-device-tested** until Rashed runs `BUILD27-TEST.txt`. The board runs firmware 0.5.0; firmware 0.6.0 (prepared, not
flashed) is still needed for everything marked **(needs 0.6.0)**.

### Implemented (Rashed's real-device findings on build 24, items 3–7)
- **Profile is a category menu**: Rider information (name, birth year, optional gender, weight, height, units), Training
  profile (goals, level, sports, weekly limit, training days → the availability editor, training history), Heart rate
  (resting / max / LTHR, zone method % max HR or % LTHR, zones, sources), Power & cycling (FTP with its method, power
  zones, meter status with "power unverified", cadence preference, bike name, wheel circumference), Connections & devices
  (the dashboard), App & device settings (appearance, keep screen on, coach on/off and frequency, background-recording
  notice, privacy + delete, phone-only mode, auto-connect, sync status, firmware, board settings). Every page saves into
  the same store; no saved value is dropped (older `store.json` files load with defaults for the new fields).
- **Plan rebuilt around your availability**: Profile › Training profile › "Training days" (also the calendar icon on
  Plan) sets, per weekday, cycle / lift / other / rest and the preferred duration. The engine never schedules on a rest
  day, puts strength on lift days, rides only on cycling days at the chosen duration, the longest cycling day is the long
  ride, one quality session per week (tempo for beginners, threshold for strength/climbing goals), a recovery spin after
  it. If riding time exceeds the weekly limit the summary shows concrete suggestions (shorten X, skip Y, raise the
  limit) instead of silently cutting sessions.
- **Plan page redesign**: readable day strip (icon + duration + zone bars, "+N" when a day has several activities),
  weekly summary with a time-budget bar (riding / all training / done / budget), separate cards for workouts and for
  rest/recovery days, tap a day to view / edit / move / replace / skip / remove / add. Hand-edited sessions are
  flagged "edited" and never regenerated without confirmation ("Rebuild this week" asks first; completed sessions and
  past days are never touched).
- **Durations** everywhere through one formatter: "1 h 40 min", "45 min", "2 h" — never "1.66667 h".
- **Historical timeline** under the plan: rides and past sessions, newest first, with duration, distance, avg / max HR,
  avg power + NP, cadence, time-in-zone strip, training load (TSS only when NP and FTP both exist — otherwise blank),
  completed / skipped / missed status; tap a ride for the full report with graphs and route. Sparkline trends (duration,
  avg power, avg HR, load) once 5+ points exist. Duplicates across board sync and phone recordings are removed
  (same board ride id, or same recorder within 5 minutes); Apple Health import is not connected and says so.
- **Ride dashboard = the Nokia "Power Focus" design**, ported from `app/src/main/java/.../ui/{Design7,Dashboard}.kt`
  and `core/DashLayout.kt`: a large power gauge on top with zone ticks, target band and the live dot; cadence and heart
  rate gauges tucked below (computed, non-overlapping geometry for every iPhone width and the available height);
  BELOW TGT / ON TARGET / ABOVE TGT / COASTING / NOT TURNING / NO SENSOR / NO HR SOURCE pills; the coach box with the
  shape badge (▲ ✓ ▼) and the lit EASE · ON TARGET · FASTER scale; a combined live graph of power, HR and cadence each
  normalised against its own target band (last 5 minutes); distance, speed, normalized power and lap; START / PAUSE /
  LAP / END and "Start cool-down". No scrolling on the main screen; the route map, sensors and classic tiles are behind
  "DETAILS ›". Header tags: POWER UNVERIFIED (always, until the XDS is validated), FTP ASSUMED, DEMO.
- **Coach engine** (`Shared/CoachCore.swift`): line-by-line port of the Nokia `CoachEngine` v3 — HR is the authority
  when present, power confirms or pre-empts, cadence only when effort is in order; gear intelligence (easier / harder
  gear vs reduce pressure / increase effort); warm-up / main / cool-down phases from ride time (5 min each, cool-down
  on request); smoothing, hold times, hysteresis, spacing and back-off; sensor-loss notices; relative-effort coaching
  when the FTP is only an assumption; sensor-poor mode (cadence + pace only) when no effort sensor is live. The target
  zone is today's planned session (free ride = Z2). Coach on/off and frequency in App settings.
- **Source id 10 (BLE cadence/speed sensor on the board)** is named in live data and history; Connections wording aligned
  with the board's Connections menu (Phone, Wi-Fi, Power meter, Heart rate, Cadence, Speed, Other Bluetooth, Device sync).

### Known limitations
- Nothing in the Nokia source was missing: the dashboard, gauge, coach, graph scaling and layout code were all present
  and ported. Two things are intentionally different: the bundled Rajdhani / IBM Plex Mono fonts are replaced by the
  system rounded / monospaced fonts (no font files are shipped), and the Nokia "Classic" and "Compact" layouts are not
  offered — Power Focus is the only ride layout (the classic tiles remain under Details).
- The XDS power stays labelled **unverified**; the Nokia 60-second "verify power" test is not ported yet.
- Wheel circumference is stored on the phone; the Link v1.2 settings message has no wheel field, so it is entered on the
  board as well (Connections › Speed) until a later protocol revision.
- Coach cues are shown, not spoken (no audio in this build).
- Google and e-mail sign-in still wait for Supabase + Google configuration; board history sync, Wi-Fi setup, profile and
  device settings still need firmware 0.6.0 on the board.
- Dynamic Type: the dashboard keeps its own sizes (it is a cockpit, not text); every other page follows the system size.

## 0.4.0 (build 24) — 25 Oct 2026 — TestFlight, internal testers only

Everything below is **simulator-tested** (43 XCTest cases in GitHub Actions, 0 failures). **Nothing new in this build is
real-device-tested** until Rashed runs `BUILD24-TEST.txt`. Pairing, live data, GPS to the board and watch heart rate were
device-tested in builds 14–21 and are unchanged in code. The board runs firmware 0.5.0; firmware 0.6.0 (prepared, not
flashed) is needed for everything marked **(needs 0.6.0)** — the app checks the board's capability bits and says so.

### Implemented
- **Connections replaces Sensors.** Home shows a Connections card (BikeComputer, power meter, Apple Watch, phone GPS);
  it opens a dashboard with BikeComputer (link, firmware, battery estimate), Phone (Bluetooth, GPS, Internet), Apple
  Watch, Bluetooth sensors via the board (power meter, strap, speed/cadence = not supported yet) and other integrations
  (Apple Health; WHOOP and Garmin listed as not connected). Colours: green connected and working · red "!" only for
  connections you enabled or the ride setup requires · amber connecting / stale / limited · gray optional / off. Every
  row opens status, pairing steps, measurements, reconnect and troubleshooting. Pairing the board: Connect → tap the
  board → type the 6-digit code once.
- **Reconnection without touching the board.** The phone keeps a pending Bluetooth connection open (state restoration,
  `bluetooth-central` background mode, no polling) and attaches as soon as the board advertises. "Connect automatically"
  (Profile › Settings and the BikeComputer page) switches that off locally; the board's own phone-link switch is a
  device setting (needs 0.6.0). The screen-off BLE drop itself was a firmware defect, fixed in 0.6.0 (see
  `firmware/waveshare/docs/FIRMWARE_0.6.0.md`); on 0.5.0 the board still has to be woken.
- **Two-stage onboarding.** Stage A: Continue as guest (name only) · Sign in with Apple · Google / e-mail shown disabled
  with the reason (account service not configured). Stage B, one question per screen, every screen skippable: name ·
  birth year · weight + units · sports and activities · goal · experience and hours · max / resting heart rate and FTP
  (tested value, or "estimate for me" labelled provisional) · devices you own (board, watch, strap, power meter) ·
  Apple Health (save workouts / read workouts / read heart rate explained separately; marked connected only after iOS
  confirms the permission) · summary. Skipped values stay "not set"; nothing is invented.
- **Profile sync (needs 0.6.0).** Ownership: board alone, phone alone, or connected with the phone authoritative. At
  first pairing the app reads the board's profile, lists the differences and asks: use the phone's profile on the board,
  or keep the board's values (copied to the phone). After that every change on the phone (also through sliders and
  text fields) bumps a version and is pushed with acknowledgement and three retries; an older version never overwrites
  a newer one. Ride history, sensor pairings, calibration, Wi-Fi and the phone pairing on the board are never touched.
  Sync status page under Profile › Devices and Connections › BikeComputer.
- **Device settings from the phone (needs 0.6.0).** Brightness, screen timeout, wake gesture, ride layout, wake on
  coach cue, phone link, deep sleep after idle, heart-rate source, board units, diagnostics. Only controls the connected
  firmware reports as supported are shown; each change waits for the board's reply and shows synced / failed.
- **Wi-Fi setup from the phone (needs 0.6.0).** Scan list with signal bars, lock and "saved", password entry (sent once
  over the encrypted link, kept nowhere on the phone), connect progress, states Connected / Connecting / Wrong password /
  Not found / Connected, no internet, Forget, Rescan, "Other network", 2.4 GHz note and the iPhone-hotspot
  "Maximize Compatibility" hint.
- **Home coach redesigned.** One line at the top ("Today: 45-minute endurance ride (Zone 2) to improve aerobic
  fitness."), a compact table (workout, duration, target zone with watts, benefit, structure, status), "Why this
  workout?" in plain words using only data the app has (last ride, this week, goal, level, FTP label — and it says that
  no sleep/HRV/recovery source is connected), and Start / Adjust / Alternative (easier, shorter, off the bike, skip).
- **Ride tab button.** Five tabs kept; the middle one is a raised circular "Ride now" button (turns green while
  recording). Tapping it opens the Ride screen only; recording starts from Start ride there.
- **Layout audit.** Plan week strip: several activities on one day are stacked (first shown + "+N" badge that opens the
  day list; "Add another activity on this day"), cells have a minimum height and scale text instead of overlapping;
  Home coach text wraps (no truncation); Connections rows are two-line with a status badge; tab bar labels scale with
  Dynamic Type; all screens use system grouped backgrounds in light and dark.
- **Profile tab.** Birth year, max / resting / threshold heart rate (entered values replace estimates and are labelled),
  sports picker, FTP entry marked "tested", Devices section → Connections, BikeComputer settings and Wi-Fi, Sync status.
- **Protocol.** `Shared/BCLink.swift` implements Link v1.2 (Wi-Fi 0x60–0x66, profile 0x70–0x73, settings 0x74–0x76,
  INFO tag 07 device id, caps 0x80/0x100/0x200); `LinkV12Tests` reproduces the firmware's byte vectors from
  `firmware/waveshare/docs/BLE_LINK_PROTOCOL.md` exactly.
- **Store.** Schema stays 1; new fields are optional with defaults (tolerant decoding tested against a build-21 file).
  Profiles and rides survive the update.

### Known limitations
- Google and e-mail sign-in remain disabled until Supabase + Google OAuth + Sign in with Apple service id are configured.
- Everything marked (needs 0.6.0) shows "needs firmware 0.6.0" on the current 0.5.0 board; history sync too.
- Board power state (display off / standby / deep sleep) is not reported over the link yet; the app shows link state only.
- Apple Health: permission flow and status are real; saving rides as workouts is prepared but not active in this build.
- Speed/cadence BLE sensors (0x1816) are listed as not supported (firmware).
- WHOOP / Garmin: listed, not connected. Android skeleton unchanged.
- Long locked-screen phone-only rides and background reconnection are untested on devices.

### Testing checklist (short) — see BUILD24-TEST.txt
1. Update; existing profile, plan and rides are intact; Home shows the coach line + table and the Connections card.
2. Delete all data → onboarding: guest with a name only, skip screens, finish; Profile shows "not set" where skipped.
3. Connections: board paired → green; switch Bluetooth off → red "!" on Bluetooth and BikeComputer; back on → reconnects
   without touching the board.
4. Watch toggle off → watch row gray, never red; on → status follows the workout.
5. Plan: add a second activity on a day → stacked cell with "+1"; tap → day list.
6. Ride now button opens Ride; nothing records until Start ride.
7. With firmware 0.6.0 later: sync differences dialog, device settings synced/failed, Wi-Fi scan + connect.

## 0.3.1 (build 21) — 24 Oct 2026 — TestFlight, internal testers only

Everything below is **simulator-tested** (27 XCTest cases in GitHub Actions, 0 failures). **Nothing is real-device-tested**
until Rashed runs `BUILD21-TEST.txt`. The board is on firmware 0.5.0; the phone-link protocol is unchanged, so the
build-17 board tests still apply.

### Implemented
- **Ride-history sync, client side** (`SYNC_PROPOSAL.md`): the app subscribes to the board's Sync characteristic and
  requests finished rides — **only when the board's INFO advertises the RIDE_SYNC capability (bit 0x40)**. Firmware
  0.4.0/0.5.0 do not, so the app shows "not supported by firmware 0.5.0 — sync coming" in Progress and never invents
  rides. Imported board rides are owned by the board, keyed by board id + start time, merged with the phone's live
  mirror of the same ride (board totals win, phone GPS track kept); demo rides are dropped. Conformance vectors for the
  firmware author are in `BCLinkTests` (SYNC_REQ bytes, SYNC_RIDE round trip, SYNC_END).
- **FTP from rides**: best 20-minute (and 60-minute) mean power from a ride's 1 Hz samples (needs power on ≥ 95 % of
  the window). When 95 % of the best 20 min differs ≥ 2 % from the current FTP, a **"Suggested FTP" card** appears on
  Home and in Progress: "95 % of the best 20-minute power (N W) from <date> ride", with Accept / Not now. Nothing
  changes until Accept; an entered (tested) FTP is never replaced automatically. After Accept the label reads
  "estimated from <date> ride". Best 20 / 60 min are shown in each ride's detail.
- **Background phone-only recording**: the recorder now runs on its own 1 Hz timer (not the screen refresh), the
  location background mode keeps GPS flowing with the screen locked, and watch heart rate keeps arriving over the
  existing WatchConnectivity path. If iOS suspends the app, the unobserved seconds are stored as **marked gaps**
  (time stays correct, no values are interpolated) and the ride detail says how many. A local notification
  ("Recording in the background") appears when the app leaves the foreground during a ride; asked once, no new
  entitlements.
- **Apple Watch ride mirror and controls**: the watch shows the phone's ride (state, recorder, time, distance, W with
  zone, rpm, bpm with source) at 1 Hz while reachable, and offers Start / Pause / Resume / End (End asks first). Commands
  go to the phone, which applies the same one-owner rules as its own buttons (board records when connected with live
  data, otherwise the phone), so the wrist can never create a second ride. The HealthKit workout flow is unchanged.
- Store schema stays 1; new fields (`boardId`, `gapSeconds`, `ftpSuggestion`, `ftpFromDate`, sample `gap`) are optional,
  so build-17 data loads unchanged.

### Known limitations
- Board rides recorded while the phone was away still stay on the board: the firmware side of the sync proposal is not
  implemented yet (planned for firmware 0.6.0).
- Google and e-mail sign-in remain disabled until Supabase + Google OAuth are configured (needs Rashed).
- Watch controls need the phone app running (foreground or background); with the phone unreachable the watch says so.
- Background recording depends on iOS keeping the app alive with the location background mode; a long locked-screen
  ride is untested on a real phone.
- Training load / form still "not enough data"; cloud integrations still "not connected"; Android unchanged (skeleton).
- Build number is the GitHub run number (21); version 0.3.1.

## 0.3.0 (build 17) — 24 Oct 2026 — TestFlight, internal testers only

The five-tab app from Prototype v3. Everything below is **simulator-tested** (XCTest in GitHub Actions: Link codec
vectors, plan engine, store persistence and migration, ride ownership, zones). **Nothing in this build is
real-device-tested** until Rashed runs the checklist in `BUILD17-TEST.txt`; build-14 features that were device-tested
(pairing, live data, GPS to board, Watch HR relay) are carried over unchanged in code but must be re-confirmed.

### Implemented
- **Onboarding** (first run): Sign in with Apple or guest → goal → hours, weight, level → connect the BikeComputer or
  continue phone-only. Starting FTP is an assumption from weight × level and is labelled "provisional" everywhere.
- **Home**: today's workout card, Start ride (says which recorder it will use), Coach (rules) note, next days,
  recovery placeholder (no source → says so), device status, FTP label.
- **Plan**: this/next week from the deterministic plan engine (hours and level decide the mix; never over the weekly
  limit), workout detail with power steps from FTP, move / edit / skip, regenerate, strength / mobility / other /
  recovery-day / rest activities.
- **Ride**: three status chips (Recording · Devices · Heart rate), six configurable tiles (power, cadence, HR, speed,
  time, distance, lap, zone, normalized power, board battery ≈ estimate), zone bar, MapKit route from the phone's
  GPS, sensors list, pause / lap / end with confirmation, save / discard sheet.
  - **One recorder per ride, fixed at start**: a connected BikeComputer with live data is the recorder (the phone
    mirrors it and adds GPS); otherwise this phone records (GPS speed/distance, watch HR; no power is ever invented).
    A board that connects mid-ride does not take over; a phone ride cannot start while the board has a ride running.
    "Phone-only mode" (Profile › Settings) forces phone recording even with a board connected.
  - Phone link lost during a board ride → banner; the board keeps recording; nothing is recorded on the phone.
- **Progress**: weekly riding-time chart with the hours limit, FTP card with its label (provisional / entered /
  from rides), ride list, ride detail with interactive Swift Charts graph (power / HR / cadence / speed, touch to read
  values), time in zones, route map, Coach (rules) summary, delete. Rides stored on the BikeComputer while the phone
  was away are **not** shown (note says "sync coming"); nothing is fabricated.
- **Profile**: rider details, FTP entry, power + HR zones, Devices (BikeComputer with the full build-14 Devices
  screen, XDS via board, Apple Watch, strap via board, phone GPS) with LIVE / CLOUD capability pills, cloud
  integrations listed as "not connected", Settings (units, phone-only mode, HR preference, keep screen on), Account
  (guest → Create account; Sign in with Apple; sign out; **delete account and all data on this phone**), About with
  version and the simulator-vs-device note.
- **Persistence**: one `store.json` (schema 1) in Application Support; build-14 per-file data is imported once;
  missing keys take defaults so future builds never drop profile or rides.
- **Offline**: no network calls in this build.
- **Watch app**: unchanged from build 14 (HealthKit cycling workout, 1 Hz heart rate to the phone, no duplicate
  Fitness workouts).
- **Android foundation** (`android/`): Kotlin Link codec with the same conformance vectors as Swift and the firmware,
  minimal Compose app skeleton with the five tabs as empty states, CI workflow building a debug APK. Not a usable
  app yet.

### Known limitations
- Google and e-mail sign-in buttons are disabled ("coming with the sync service"): Supabase + Google configuration
  needed (Rashed). Sign in with Apple only identifies the rider on this phone; nothing is synced anywhere.
- Board ride history is not pulled from the BikeComputer (Sync characteristic not implemented in the app yet).
- The board's own ride totals are the authority; the phone's copy of a board ride is built from the 1 Hz mirror and
  may have gaps if the app was in the background. Avg/NP/kJ on the phone can therefore differ slightly from the
  board's results screen.
- FTP is never estimated from rides yet ("from rides" label exists but no detector runs).
- Training load / form intentionally shows "not enough data yet".
- Cloud integrations (WHOOP, Garmin, Apple Health) are listed but not connected.
- Units setting affects the Ride and results tiles; the Plan and Progress texts stay metric in this build.
- Imperial speed/distance conversions are display-only; stored data is always metric.
- Background recording on the phone depends on iOS keeping the app alive with the location background mode; a long
  phone-only ride with the screen locked is untested.
- Build number is the GitHub run number (17); the version is 0.3.0.

### Testing checklist (short) — see BUILD17-TEST.txt for the step-by-step version
1. Install 0.3.0 (17) from TestFlight; first run shows onboarding; choose guest.
2. Profile → data from onboarding present; set a tested FTP; zones update.
3. Board off: Ride → "Start ride · phone only" → walk 2 min → End → Save; Progress shows the ride with a map.
4. Board on (0.4.0), paired: Ride shows "board ready"; Start → board starts; tiles show XDS power/cadence; End from
   phone → results on both; Save; Progress lists it as "BikeComputer".
5. During a board ride, switch Bluetooth off on the phone for 30 s → banner; back on → values return.
6. Watch workout running → HR tile shows "Apple Watch"; strap paired on the board → HR source "via board".
7. Kill and relaunch the app → profile, plan, rides intact.
8. Profile → Delete account and all data → onboarding again; board remembered state cleared.
