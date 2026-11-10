# Cyclift Watch — feature matrix, Stage 1.3 RC1 (11 Nov 2026)

Sources: the 102-feature registry (unchanged; IDs as given by the owner) with its placement in the approved prototype v3.3,
and the v3 firmware on branch `watch/v3-poc` (Stage 1.3 RC1 working tree). Status words:

| Status | Meaning |
|---|---|
| IMPLEMENTED AND VERIFIED | in the firmware and checked on the physical watch (Stage 1 B2, 9 Nov, or Stage 1.1 C1/C2, 10 Nov) |
| IMPLEMENTED BUT UNVERIFIED | in the RC1 firmware and computer-tested; never run on the watch |
| PARTIALLY IMPLEMENTED | part of the approved behaviour exists; the rest is named in the row |
| NOT IMPLEMENTED | not in the v3 firmware (several exist in the older v2 line, never run on the watch) |
| BLOCKED BY HARDWARE | the screen exists, but the data needs a sensor, the battery or Bluetooth hardware work |
| BLOCKED BY APP INTEGRATION | the screen exists with an honest empty state; the data comes from the iPhone (Bluetooth, Stage 4) |

Count: **3** verified · **3** unverified · **9** partial · **6** blocked by hardware · **9** blocked by app integration ·
**72** not implemented = 102. Nothing in RC1 is "verified" until the hardware acceptance session (HARDWARE_ACCEPTANCE.md).

## A. Design elements outside the 102 IDs (Hybrid UI/UX v3)

| Element | Approved | RC1 firmware | Status |
|---|---|---|---|
| Themes | 6 (Obsidian, Arctic, Ocean, Forest, Sandstone, High contrast) | all 6 selectable in Quick Settings; every RC1 screen rendered and checked in all 6 (contrast ≥ 3:1) | IMPLEMENTED BUT UNVERIFIED (Obsidian verified Stage 1) |
| Faces | Orbit, Chrono, Pulse | Orbit | PARTIALLY IMPLEMENTED |
| Menu destinations | 8 | Watch Face, Today, Activities (simulated ride); Health, Coach, History, Utilities, Settings open "Not in this release" | PARTIALLY IMPLEMENTED |
| Face swipes | up Today · down Quick Settings · sideways widgets | as approved (prototype v3.3): the face-level carousel keeps the same physical directions in Arabic; the back swipe on other screens is mirrored in Arabic | IMPLEMENTED BUT UNVERIFIED (owner found them missing on 10 Nov in Stage 1.1) |
| Back navigation | Key 2 / swipe back, no duplicate history | history of at most 8 screens; going back to the screen already on top is not stacked; tested for every screen × input | IMPLEMENTED BUT UNVERIFIED |
| Quick Settings | Brightness, Theme, Do not disturb, Mode, Screen lock | all five; DND is a state only (nothing to silence yet); settings are RAM-only (reset at restart) | IMPLEMENTED BUT UNVERIFIED |
| Screen lock | "Locked · hold Key 1" | taps and Key 1 ignored; hold Key 1 ≥ 1 s unlocks | IMPLEMENTED BUT UNVERIFIED |
| Languages | English, Arabic (RTL) | both on every RC1 screen | IMPLEMENTED BUT UNVERIFIED (Arabic verified on Stage 1 screens) |
| Densities | Standard, Focused, Large Text | all three on every RC1 screen | IMPLEMENTED BUT UNVERIFIED (verified on Stage 1 screens) |
| Time and date | from the iPhone; weekday + date EN/AR | clock chip read every 10 s; invalid clock hides time AND date; 24-hour only (no 12-hour setting is specified) | IMPLEMENTED BUT UNVERIFIED (time display verified C2; date hiding new) |
| Data honesty | empty / unavailable states with reasons | no invented data by default; demo data only by serial `E`; "Simulated ride" banner | IMPLEMENTED BUT UNVERIFIED |
| Bike mode cockpit | large lead number, button for gloves | lead 76 px, 52 px Pause button (≥ 44 px), unit omitted (label under the number) | IMPLEMENTED BUT UNVERIFIED |

## B. The 102 registry features

| ID | Feature | Design | Approved screens | RC1 firmware | Notes |
|---|---|---|---|---|---|
| WF-01 | Digital and analog watch faces | shown | face, fpick | **PARTIALLY IMPLEMENTED** | Orbit face only (hardware-verified in Stage 1 B2). Chrono, Pulse and the face picker: RC2. |
| WF-02 | Customizable watch face complications | shown | fpick, fcomp | **NOT IMPLEMENTED** | Complication slots: RC2. |
| WF-03 | Daily activity rings and goals | shown | w-activity, face | **BLOCKED BY HARDWARE** | Activity widget built (computer-tested) with an honest empty state; step counting from the accelerometer not implemented and untested on this board. |
| WF-04 | Widgets and glance carousel | shown | w-health, w-coach, w-activity | **IMPLEMENTED BUT UNVERIFIED** | Health / Coach / Activity widgets reached by sideways swipes with page dots (computer-tested in EN/AR, 6 themes, 3 densities). Not yet seen on the watch. |
| WF-05 | Notifications from iPhone | shown | ut-notif, ut-notif-d, wk-banner | **NOT IMPLEMENTED** | Approved screen(s) ut-notif, ut-notif-d, wk-banner — not in RC1 (RC2+). |
| WF-06 | Calls and message controls | shown | ut-call | **NOT IMPLEMENTED** | Approved screen(s) ut-call — not in RC1 (RC2+). |
| WF-07 | Alarms, stopwatch and timers | shown | ut-alarm, ut-sw, ut-timer | **NOT IMPLEMENTED** | Approved screen(s) ut-alarm, ut-sw, ut-timer — not in RC1 (RC2+). |
| WF-08 | Music playback controls | shown | ut-music | **NOT IMPLEMENTED** | Approved screen(s) ut-music — not in RC1 (RC2+). |
| HH-01 | Live heart rate | shown | w-health, health, h-hr, ride-hr | **BLOCKED BY HARDWARE** | Health widget shows "Waiting HR"; needs a Bluetooth heart-rate sensor (Stage 2b/4). |
| HH-02 | Resting heart rate | shown | w-health, h-trends | **BLOCKED BY APP INTEGRATION** | Resting HR tile shows "—"; value comes from the iPhone. |
| HH-03 | Heart rate variability (HRV) | shown | h-hrv, w-health | **BLOCKED BY APP INTEGRATION** | HRV tile shows "—"; value comes from the iPhone. |
| HH-04 | High and low HR alerts | shown | alert-hr, se-work, h-hr | **NOT IMPLEMENTED** | Approved screen(s) alert-hr, se-work, h-hr — not in RC1 (RC2+). |
| HH-05 | Blood oxygen (SpO₂) | unavail | h-vitals | **NOT IMPLEMENTED** | Approved as "unavailable with reason" (No sensor on this hardware); the reason page is RC2. |
| HH-06 | Respiratory rate | unavail | h-vitals | **NOT IMPLEMENTED** | Approved as "unavailable with reason" (No sensor on this hardware); the reason page is RC2. |
| HH-07 | Skin temperature trends | unavail | h-vitals | **NOT IMPLEMENTED** | Approved as "unavailable with reason" (No sensor on this hardware); the reason page is RC2. |
| HH-08 | Blood pressure insights | unavail | h-vitals | **NOT IMPLEMENTED** | Approved as "unavailable with reason" (No sensor on this hardware); the reason page is RC2. |
| HH-09 | VO₂ max / cardio fitness | unavail | h-vitals | **NOT IMPLEMENTED** | Approved as "unavailable with reason" (Method not yet validated); the reason page is RC2. |
| HH-10 | Cardiovascular age | unavail | h-vitals | **NOT IMPLEMENTED** | Approved as "unavailable with reason" (Method not yet validated); the reason page is RC2. |
| HH-11 | Health trends and unusual vitals | unavail | h-trends | **NOT IMPLEMENTED** | Approved as "unavailable with reason" (Trends shown; unusual-vitals detection not validated); the reason page is RC2. |
| HH-12 | Stress monitoring | unavail | h-vitals | **NOT IMPLEMENTED** | Approved as "unavailable with reason" (Method not yet validated); the reason page is RC2. |
| SR-01 | Sleep duration and schedule | shown | h-sleep, health | **NOT IMPLEMENTED** | Approved screen(s) h-sleep, health — not in RC1 (RC2+). |
| SR-02 | Sleep stages (REM, deep, light) | shown | h-sleep | **NOT IMPLEMENTED** | Approved screen(s) h-sleep — not in RC1 (RC2+). |
| SR-03 | Sleep score | unavail | h-sleep | **NOT IMPLEMENTED** | Approved as "unavailable with reason" (Method not yet validated); the reason page is RC2. |
| SR-04 | Sleep consistency | shown | h-sleep | **NOT IMPLEMENTED** | Approved screen(s) h-sleep — not in RC1 (RC2+). |
| SR-05 | Sleep debt | hidden | — | **NOT IMPLEMENTED** | Hidden in the approved design (listed under Settings → Feature availability); not planned for RC1. |
| SR-06 | Sleep need recommendation | hidden | — | **NOT IMPLEMENTED** | Hidden in the approved design (listed under Settings → Feature availability); not planned for RC1. |
| SR-07 | Recovery / readiness score | unavail | h-rec, health | **NOT IMPLEMENTED** | Approved as "unavailable with reason" (Decision V7: unavailable until validated); the reason page is RC2. |
| SR-08 | Body Battery / energy estimate | hidden | — | **NOT IMPLEMENTED** | Hidden in the approved design (listed under Settings → Feature availability); not planned for RC1. |
| SR-09 | Recovery time recommendation | unavail | h-rec | **NOT IMPLEMENTED** | Approved as "unavailable with reason" (Method not yet validated); the reason page is RC2. |
| SR-10 | Sleep coaching | hidden | — | **NOT IMPLEMENTED** | Hidden in the approved design (listed under Settings → Feature availability); not planned for RC1. |
| SR-11 | Recovery trends | shown | h-trends | **NOT IMPLEMENTED** | Approved screen(s) h-trends — not in RC1 (RC2+). |
| SR-12 | Resilience / long-term stress | hidden | — | **NOT IMPLEMENTED** | Hidden in the approved design (listed under Settings → Feature availability); not planned for RC1. |
| SR-13 | Biological age / pace of aging | hidden | — | **NOT IMPLEMENTED** | Hidden in the approved design (listed under Settings → Feature availability); not planned for RC1. |
| TC-01 | Today’s workout plan | shown | today, today-plan | **BLOCKED BY APP INTEGRATION** | Today screen built: planned session, target and Start (with demo data only, labelled); honest "No plan on the watch yet" otherwise. Real plan needs the iPhone link. |
| TC-02 | Adaptive training schedule | shown | today-week | **BLOCKED BY APP INTEGRATION** | Week strip built (done / planned / missed / rest); real data from the iPhone. |
| TC-03 | AI training coach | shown | coach, w-coach | **BLOCKED BY APP INTEGRATION** | Coach widget built; text comes from the iPhone ("No note" otherwise). |
| TC-04 | Live workout coaching cues | shown | ride-cockpit, wk-coach | **IMPLEMENTED AND VERIFIED** | Cockpit command line (e.g. HOLD 245 W) — simulated plan; hardware-checked in Stage 1 B2 (V2-7). |
| TC-05 | Personalized HR zones | shown | ride-hr | **NOT IMPLEMENTED** | Approved screen(s) ride-hr — not in RC1 (RC2+). |
| TC-06 | Power zones and FTP | shown | ride-cockpit, ride-power | **IMPLEMENTED AND VERIFIED** | Cockpit power target — simulated values; hardware-checked in Stage 1 B2 (V2-7). Real FTP from the iPhone. |
| TC-07 | Training load and strain | shown | h-load | **NOT IMPLEMENTED** | Approved screen(s) h-load — not in RC1 (RC2+). |
| TC-08 | Training readiness | unavail | h-rec | **NOT IMPLEMENTED** | Approved as "unavailable with reason" (Same rule as SR-07); the reason page is RC2. |
| TC-09 | Training status / fitness trend | unavail | h-load | **NOT IMPLEMENTED** | Approved as "unavailable with reason" (Method not yet validated); the reason page is RC2. |
| TC-10 | Overtraining and undertraining warnings | unavail | co-week | **NOT IMPLEMENTED** | Approved as "unavailable with reason" (Method not yet validated); the reason page is RC2. |
| TC-11 | Suggested daily workouts | shown | today | **BLOCKED BY APP INTEGRATION** | Shown on Today when the iPhone provides it (demo data only in RC1). |
| TC-12 | Training goal tracking | shown | co-goal | **NOT IMPLEMENTED** | Approved screen(s) co-goal — not in RC1 (RC2+). |
| TC-13 | Workout adherence / missed sessions | shown | today-week, co-week | **BLOCKED BY APP INTEGRATION** | Week strip built; real week from the iPhone. |
| TC-14 | AI explanation: Why this workout? | shown | co-why, wk-coach | **PARTIALLY IMPLEMENTED** | Coach widget "Why?" button opens the Coach destination, which is "Not in this release". |
| TC-15 | Weekly coaching review | shown | co-week | **NOT IMPLEMENTED** | Approved screen(s) co-week — not in RC1 (RC2+). |
| CY-01 | Live power (watts) | shown | ride-cockpit, ride-power | **BLOCKED BY HARDWARE** | Lead power display hardware-checked with simulated values (B2 V2-7); a real power meter needs Bluetooth (Stage 2b/4). |
| CY-02 | 3s / 10s / average power | shown | ride-power | **NOT IMPLEMENTED** | Approved screen(s) ride-power — not in RC1 (RC2+). |
| CY-03 | Cadence (RPM) | shown | ride-cockpit, ride-cad | **BLOCKED BY HARDWARE** | Cadence shown with simulated values (B2 V2-7); real sensor needs Bluetooth. |
| CY-04 | Speed, distance and duration | shown | wk-summary, ride-climb | **NOT IMPLEMENTED** | Approved screen(s) wk-summary, ride-climb — not in RC1 (RC2+). |
| CY-05 | Heart rate and HR zones | shown | ride-cockpit, ride-hr | **BLOCKED BY HARDWARE** | Heart rate shown with simulated values; zones page RC2; real sensor needs Bluetooth. |
| CY-06 | Power zone target guidance | shown | ride-cockpit, ride-power | **PARTIALLY IMPLEMENTED** | Target shown in the cockpit (simulated); zone guidance pages RC2. |
| CY-07 | Normalized Power / IF / TSS | shown | ride-pacing, wk-summary | **NOT IMPLEMENTED** | Approved screen(s) ride-pacing, wk-summary — not in RC1 (RC2+). |
| CY-08 | Power and HR graphs | shown | ride-power, ride-hr | **NOT IMPLEMENTED** | Approved screen(s) ride-power, ride-hr — not in RC1 (RC2+). |
| CY-09 | Lap and interval controls | shown | wk-ctl, ride-pacing | **PARTIALLY IMPLEMENTED** | Lap = Key 2 twice in the cockpit; interval counter shown (simulated). Controls page RC2. |
| CY-10 | Auto pause | shown | se-work | **NOT IMPLEMENTED** | Approved screen(s) se-work — not in RC1 (RC2+). |
| CY-11 | Route and turn-by-turn navigation | shown | wk-nav | **NOT IMPLEMENTED** | Approved screen(s) wk-nav — not in RC1 (RC2+). |
| CY-12 | Climb grade and elevation | shown | ride-climb | **NOT IMPLEMENTED** | Approved screen(s) ride-climb — not in RC1 (RC2+). |
| CY-13 | Real-time stamina estimate | hidden | — | **NOT IMPLEMENTED** | Hidden in the approved design (listed under Settings → Feature availability); not planned for RC1. |
| CY-14 | Power guide / pacing strategy | shown | ride-pacing | **NOT IMPLEMENTED** | Approved screen(s) ride-pacing — not in RC1 (RC2+). |
| CY-15 | Incident detection and live tracking | hidden | — | **NOT IMPLEMENTED** | Hidden in the approved design (listed under Settings → Feature availability); not planned for RC1. |
| CY-16 | Indoor smart trainer controls | hidden | — | **NOT IMPLEMENTED** | Hidden in the approved design (listed under Settings → Feature availability); not planned for RC1. |
| ST-01 | Today’s strength workout | shown | review, act | **NOT IMPLEMENTED** | Approved screen(s) review, act — not in RC1 (RC2+). |
| ST-02 | Exercise list and instructions | shown | st-next, st-instr | **NOT IMPLEMENTED** | Approved screen(s) st-next, st-instr — not in RC1 (RC2+). |
| ST-03 | Log sets, reps and weights | shown | st-set, st-reps, st-kg | **NOT IMPLEMENTED** | Approved screen(s) st-set, st-reps, st-kg — not in RC1 (RC2+). |
| ST-04 | Edit or undo a logged set | shown | st-ctl, st-reps, st-kg | **NOT IMPLEMENTED** | Approved screen(s) st-ctl, st-reps, st-kg — not in RC1 (RC2+). |
| ST-05 | Rest timer | shown | st-rest | **NOT IMPLEMENTED** | Approved screen(s) st-rest — not in RC1 (RC2+). |
| ST-06 | Next / previous exercise | shown | st-ctl, st-next | **NOT IMPLEMENTED** | Approved screen(s) st-ctl, st-next — not in RC1 (RC2+). |
| ST-07 | Skip or substitute exercise | shown | st-ctl, st-sub | **NOT IMPLEMENTED** | Approved screen(s) st-ctl, st-sub — not in RC1 (RC2+). |
| ST-08 | Automatic rep counting | shown | st-auto | **NOT IMPLEMENTED** | Approved screen(s) st-auto — not in RC1 (RC2+). |
| ST-09 | Automatic set detection | hidden | — | **NOT IMPLEMENTED** | Hidden in the approved design (listed under Settings → Feature availability); not planned for RC1. |
| ST-10 | Strength training load / strain | shown | h-load | **NOT IMPLEMENTED** | Approved screen(s) h-load — not in RC1 (RC2+). |
| RW-01 | Walking and running sessions | shown | act, review, run-cockpit, walk-cockpit | **NOT IMPLEMENTED** | Approved screen(s) act, review, run-cockpit, walk-cockpit — not in RC1 (RC2+). |
| RW-02 | Live pace, distance, duration | shown | run-cockpit, walk-cockpit | **NOT IMPLEMENTED** | Approved screen(s) run-cockpit, walk-cockpit — not in RC1 (RC2+). |
| RW-03 | Running cadence and stride length | unavail | run-splits | **NOT IMPLEMENTED** | Approved as "unavailable with reason" (Cadence and stride source not validated); the reason page is RC2. |
| RW-04 | Running intervals and splits | shown | run-splits | **NOT IMPLEMENTED** | Approved screen(s) run-splits — not in RC1 (RC2+). |
| RW-05 | Race time predictions | hidden | — | **NOT IMPLEMENTED** | Hidden in the approved design (listed under Settings → Feature availability); not planned for RC1. |
| RW-06 | Automatic activity detection | hidden | — | **NOT IMPLEMENTED** | Hidden in the approved design (listed under Settings → Feature availability); not planned for RC1. |
| DL-01 | Steps and distance | shown | w-activity | **BLOCKED BY HARDWARE** | Activity widget shows "STEPS —" with "Estimated"; accelerometer step counting not implemented. |
| DL-02 | Active calories | shown | w-activity | **BLOCKED BY APP INTEGRATION** | Activity widget shows "— kcal"; calories come from the iPhone / heart rate. |
| DL-03 | Hydration tracking | shown | ut-water | **NOT IMPLEMENTED** | Approved screen(s) ut-water — not in RC1 (RC2+). |
| DL-04 | Weight and body composition trends | shown | h-trends | **NOT IMPLEMENTED** | Approved screen(s) h-trends — not in RC1 (RC2+). |
| DL-05 | Habit and journal logging | hidden | — | **NOT IMPLEMENTED** | Hidden in the approved design (listed under Settings → Feature availability); not planned for RC1. |
| NS-01 | GPS location and route tracking | shown | wk-nav | **NOT IMPLEMENTED** | Approved screen(s) wk-nav — not in RC1 (RC2+). |
| NS-02 | Back to start | shown | wk-nav | **NOT IMPLEMENTED** | Approved screen(s) wk-nav — not in RC1 (RC2+). |
| HI-01 | Workout history and summaries | shown | hist, hi-ride, hi-lift, hi-laps, wk-summary | **NOT IMPLEMENTED** | Approved screen(s) hist, hi-ride, hi-lift, hi-laps, wk-summary — not in RC1 (RC2+). |
| HI-02 | Weekly and monthly trends | shown | hi-trends, h-trends | **NOT IMPLEMENTED** | Approved screen(s) hi-trends, h-trends — not in RC1 (RC2+). |
| HI-03 | Apple Health integration | shown | health | **NOT IMPLEMENTED** | Approved screen(s) health — not in RC1 (RC2+). |
| HI-04 | External Bluetooth sensors | shown | sensors, se-conn | **NOT IMPLEMENTED** | Approved screen(s) sensors, se-conn — not in RC1 (RC2+). |
| HI-05 | Data quality and sensor freshness | shown | ride-cockpit, health, sensors | **PARTIALLY IMPLEMENTED** | Missing sensors shown as missing, not zero (B2 V2-7); "Simulated ride" label added in RC1 (unverified on the watch). |
| WC-01 | Start / pause / resume / end | shown | review, ride-cockpit, wk-ctl, wk-paused, wk-end | **PARTIALLY IMPLEMENTED** | Start / pause / resume with the simulated iPhone hardware-checked (B2 V2-5, V2-7). End and summary: RC2. |
| WC-02 | Two-way iPhone synchronization | shown | all workout screens | **BLOCKED BY APP INTEGRATION** | Two-way sync: Stage 4 (Bluetooth). Architecture in BLE_ARCHITECTURE_RC1.md. |
| WC-03 | Disconnected and pending command states | shown | start-fail, st-sync, wk-ctl | **IMPLEMENTED AND VERIFIED** | Pending command / confirmed states hardware-checked with the simulated iPhone (B2 V2-7); refusal and no-answer states computer-tested. |
| WC-04 | Physical button shortcuts | shown | se-buttons | **PARTIALLY IMPLEMENTED** | Key 1 / Key 2 hardware-checked (B2 V2-3, V2-4); RC1 adds hold Key 1 to unlock (unverified). Button settings page RC2. |
| WC-05 | Customizable workout screens | shown | se-pages | **NOT IMPLEMENTED** | Approved screen(s) se-pages — not in RC1 (RC2+). |
| WC-06 | Wrist / bike / gym view modes | shown | qs, review | **IMPLEMENTED BUT UNVERIFIED** | Quick Settings Mode Wrist / Bike / Gym; Bike switches the cockpit to the Bike layout. Computer-tested only. |
| WC-07 | Battery and connection status | shown | face, qs, alert-batt | **PARTIALLY IMPLEMENTED** | Battery % on face and Quick Settings (no battery fitted: cannot be verified); connection status in the cockpit. |
| WC-08 | Screen brightness and timeout | shown | se-display, qs | **IMPLEMENTED BUT UNVERIFIED** | Quick Settings brightness 30/50/70/100 % drives the backlight (RAM only, reset at restart). Timeout: RC2. |
| WC-09 | Haptic feedback and alerts | shown | se-haptic | **NOT IMPLEMENTED** | Approved screen(s) se-haptic — not in RC1 (RC2+). |
| WC-10 | Firmware and diagnostic screens | shown | se-about, se-diag | **PARTIALLY IMPLEMENTED** | Serial diagnostics only (M memory, R clock, u/h performance); on-watch About / Diagnostics pages RC2. |
