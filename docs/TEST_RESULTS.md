# Test results — Bike Computer v0.8.0 (build 51), 2026-10-14

Release APK: `BikeComputer-build51.apk` · versionCode 11 · versionName 0.8.0 · package `com.rashed.bikesensordoctor.debug`
SHA-256 `de370e2ad51d581d2334e9b5f1cf55c446100d7ef63dfcc98f930efcc58fd180` — the identical file that passed every check below
(CI run 51: build → emulator test → release, all green; run 50 passed the same tests one commit earlier).

## How it was tested

| Layer | Where | What |
|---|---|---|
| Portable core (coach, profile rules, targets, leaderboard, reliability) | GitHub Actions JVM + local JVM | 88 JUnit tests incl. 16 coach test vectors (1,502 assertions) |
| Whole app on a device | GitHub Actions **Android 12 (API 31) emulator**, 720×1520 @ 320 dpi (Nokia 5.3 geometry) | Installed the release APK, drove it through the accessibility tree like a finger (UiAutomator), 31 screenshots, logcat crash scan, 1,500-event monkey stress |
| Nokia 5.3 hardware, XDS meter, HR strap | **not possible from here** | see "Untested" |

## Passed (emulator, automated — `AppFlowTest`, 5/5 OK)

| # | Check | Evidence |
|---|---|---|
| 1 | First launch → sign-in screen with 4 SAMPLE riders, create account "Rashed" | 01_sign_in, 02_welcome |
| 2 | All 6 onboarding pages (chips, numbers, sliders, "Tested" tags), summary with CONFIRMED zones (threshold 168 → Z2 139–151) | 03–08 |
| 3 | Personal home: goal, today's workout, why/how/measure, START RIDE pinned | 09_home |
| 4 | Club: not a member → join with invite code → member list, challenges, Leave | 10, 11 |
| 5 | Leaderboard: Weekly km / Monthly km / Time / Climb / Rides / Z2★ tabs, reset date, DEMO banner, own row highlighted | 12–14 |
| 6 | Rider profile of another member (zones hidden, their coach's recommendation shown) | 15 |
| 7 | ME tab = editable profile summary, redo onboarding, sign out | 16 |
| 8 | Switch rider: Omar's home (Zone 2 endurance 90 min) and Layla's home (Sweet-spot intervals) differ from Rashed's; switch back | 17–19 |
| 9 | Back button from Club/Board/ME returns Home; Back on Home leaves the app | t02 |
| 10 | Simulated 60-min ride at 30×: START, PAUSE, RESUME, WARM-UP ramp → MAIN → COOL-DOWN ramp, gauges update, LIVE dots and TGT bands move, cues (WARM UP, KEEP IT UP, EASE OFF, WIND DOWN, COACH QUIET after 3 repeats), link 100 % no gaps, backgrounded + reopened without losing the ride | 20–27 |
| 11 | FINISH → post-ride results (92 % in band, drift, cues, SIMULATED label) → questions → next recommendation ("Legs limited you last time → cadence hints prioritised") → Home | 28, 29 |
| 12 | History lists the ride tagged SIMULATED with % in band; CSV/GPX present | 30 |
| 13 | App restart keeps rider, profile, feedback; Settings screen renders; dashboard without simulation stays alive | 31, 32 |
| 14 | Logcat: no crash in the app process during the whole run; crash recorder file empty | crashes.txt, last-crash.txt empty |
| 15 | Monkey 1,500 random taps/swipes: app still running, no crash file | monkey.txt |
| 16 | APK installs on API 31; version/package confirmed by `dumpsys package` | install.txt |

## Visual problems found by the screenshots and fixed before release
- Header "SCIENTIFIC COACH" wrapped letter-by-letter when phase + tags shared the row → tags moved to their own line.
- "COACH" button wrapped to "COA / CH" → wider button, smaller font, single line.
- "SHOWN · NOT COACHED" overflowed the power gauge → "NOT COACHED".
- "Tested" chips wrapped to "Teste / d" on the zones page → narrower label/number columns, tighter chip padding.
- START RIDE on Home was below the fold → pinned above the tab bar.
- After SAVE on the post-ride screen the app skipped the "recommendation changed" view → fixed.
- Previous ride's last cue ("COACH QUIET") stayed on the dashboard after finishing → cue reset at start/finish.
- Simulator script was out of step with the ride clock (coasting at minute 50) → script restarts with the ride.

## Coaching engine (unit tests, all pass)
HR below/inside/above band · power below/inside/above · cadence below/inside/above · HR–power conflict (HR authority, HR-lag hold,
surge pre-empt) · stale/absent signals · warm-up → MAIN with 90 s transition grace · MAIN → cool-down with falling ceiling (WIND DOWN) ·
back-off (3 unheeded repeats → QUIET, speaks again after 5 min; 12+ repeats without it) · power never coached when FTP unknown ·
four rider profiles give different bands/recommendations (CONFIRMED / PROVISIONAL / GENERIC derivations) · leaderboard excludes
SIMULATED/SAMPLE rides from a real board.

## Untested — needs your phone or your hardware
- Nokia 5.3 itself (the emulator matches its resolution/density and Android version, not its chip, fonts or Bluetooth stack).
- XDS/Branta power meter: pairing, 5-min reconnect, power under load (Verify Power screen), battery read.
- Heart-rate strap over Bluetooth (code unchanged from v0.7; HR address is now stored per rider).
- Real GPS distance/elevation outdoors (emulator GPS gives a fixed point → 0.0 km).
- Text-to-speech voice on the phone.
- Landscape: the activity is locked to portrait (as before), so the landscape layout code is unused.
- Bluetooth off / permission denied mid-ride: the gates no longer block the app and the dashboard shows a tappable notice, but
  this was only exercised with the emulator's Bluetooth state, not a real adapter being switched off.
- Battery/background behaviour over a real 60-minute ride (the foreground service and wake lock are unchanged from v0.7).

## Known limitations
- Accounts, club, invite code and leaderboard are **local to the phone** and labelled DEMO; no cloud, no real friends yet.
- Sample riders (Omar, Layla, Sami, Noor) are fictional; their rides are tagged SAMPLE and cannot reach a real board.
- Rides recorded with the simulation tool are tagged SIMULATED everywhere (history, board) and carry virtual timestamps.
- Power targets switch on only after the meter passes "Verify power under load" **and** the profile has an FTP; until then power
  is shown, not coached (by design: no invented watts).
- Switching rider is refused while a ride is running or paused.

## Installing
- Previous builds (21–24) were signed with throw-away keys generated per build; from build 51 the key is fixed and committed,
  so **future** updates install over this one with data kept. **This one time** Android will refuse to update over an older
  build ("App not installed"): uninstall the old Bike Computer first, then install build 51. Old test rides are lost; the new
  app starts with the sign-in screen.
