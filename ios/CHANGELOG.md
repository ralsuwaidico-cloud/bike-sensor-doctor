# BikeComputer iPhone + Apple Watch — changelog

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
