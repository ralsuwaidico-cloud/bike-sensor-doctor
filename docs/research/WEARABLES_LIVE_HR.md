# Live heart rate by device family — research notes (24 Oct 2026)

Verification labels: DOC = official vendor documentation; COMMUNITY = forum/user reports; SECONDARY = press/partner page; UNKNOWN = not found.
Nothing here is "confirmed" for BikeComputer until tested on real hardware (see the compatibility matrix in the platform plan).

## Summary table

| Family | Live HR path | Category | Verification | Notes |
|---|---|---|---|---|
| Any 0x180D device | connect, subscribe 0x2A37 | Direct BLE | DOC (spec) | some demand bonding + rotate addresses (RPA ~15 min) |
| WHOOP 4.0 / 5.0 / MG | app: Device Settings → Heart Rate Broadcast | Direct BLE | 3.0 DOC; 4.0/5.0 COMMUNITY; MG UNKNOWN | BLE only (no ANT+); hidden unless broadcasting; appears as "WHOOP"; no tier gate found; cloud API has no live HR |
| Apple Watch | watchOS app (HKWorkoutSession) → iPhone (WatchConnectivity / mirroring) | Companion relay | DOC (Apple) | watchOS cannot advertise BLE; HealthKit-only on iPhone is delayed; ~5 s HR cadence in workouts |
| Garmin watches | Broadcast Heart Rate (BLE + ANT+) | Direct BLE | DOC procedure; BLE model list SECONDARY | Edge units are receivers only; Connect IQ cannot advertise; Health API is post-sync |
| Samsung Galaxy Watch (Wear OS) | Wear OS app (Health Services) → Data Layer → Android phone | Companion relay | DOC APIs | no native broadcast; Samsung Sensor SDK needs partner approval; Health Connect delayed |
| Google Pixel Watch 2+ | Settings → Connectivity → Share Heart Rate | Direct BLE | DOC | PW3+ 2 connections; central must bond (LTK/IRK) and expose Device Name; PW1 unsupported |
| Polar H9 / H10 / Verity Sense | standard BLE (+ANT+) | Direct BLE | DOC | H10 "2 BLE devices" setting; Verity 2 BLE |
| Polar watches | HR sensor mode (pre-training) | Direct BLE | DOC (Grit X, Ignite 2/3, Unite) | stops when leaving pre-training mode |
| Wahoo TICKR / RIVAL | standard BLE + ANT+; RIVAL Settings → Broadcasting | Direct BLE | DOC | TICKR (2020): 3 BLE + 1 ANT+; ELEMNT ACE is a receiver |
| Fitbit Charge 6 / Air | HR on Equipment / Share heart rate | Direct BLE | DOC | 1 connection; Garmin listed incompatible; Fitbit Web API shuts 2 Nov 2026 |
| Fitbit other models | legacy SDK relay or cloud | Historical only | DOC API | Sense 2 / Versa 4: no third-party apps |
| COROS | Toolbox → Broadcast HR (BLE + ANT+) | Direct BLE | DOC | 1 BLE only; disconnect phone first |
| Suunto (Race 2, Vertical 2…) | Broadcast HR (fw 2.53.42+, Apr 2026) | Direct BLE | DOC release note | Wahoo receivers show no bpm (unresolved) |
| Amazfit / Zepp (Zepp OS 3+) | Heart Rate Push | Direct BLE | SECONDARY only | some models only during a workout |
| Oura ring | none live; API 5-min data hours later | Historical only | DOC | |
| Xiaomi Smart Band 10 | Settings → Share HR | Direct BLE (profile unverified) | DOC feature | older bands unknown |

## Engineering takeaways for the ESP32 central
1. Implement bonding with persistent LTK/IRK and RPA resolution (NimBLE store), or Google devices drop after ~15 min.
2. Expose a readable GAP Device Name (0x2A00).
3. Do not rely on 0x180D in the advertisement: connect and discover services for devices the rider picks.
4. Apple Watch and Galaxy Watch need a phone-side relay; the ESP32 phone link carries HR with source + timestamp.
5. WHOOP 4.0: HR notifications on standard 0x2A37 ~1/s; only visible while broadcast is on (COMMUNITY reverse-engineering).

## Cloud APIs (none give live HR)
- WHOOP Developer API v2: recovery, cycles, sleep, workout, body measurement, profile; 100 req/min; webhooks carry IDs only.
- Garmin Health API: approved partners, post-sync summaries incl. second-level HR of activities.
- Fitbit Web API: legacy ends 30 Sep 2026 / off 2 Nov 2026 → Google Health API (restricted scopes).
- Polar AccessLink: post-sync. COROS Partner API: companies only. Suunto Cloud API: partner approval. Oura API v2: 5-min HR, hours of lag.

## Key sources
- https://support.google.com/product-documentation/answer/16923066 (BLE HR peripheral guideline: bonding, RPA, Device Name)
- https://support.google.com/fitbit/answer/14236705 (Pixel Watch / Fitbit share heart rate)
- https://support.whoop.com/hc/en-us/articles/360023430193-Heart-Rate-Broadcast
- https://www.community.whoop.com/t/whoop-connects-to-cycling-computer-but-hr-is-not-broadcasted/11198
- https://developer.whoop.com/docs/api-changelog/
- https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager.md (watchOS cannot advertise)
- https://developer.apple.com/forums/thread/774953 (HealthKit sync not real time)
- https://developer.apple.com/tutorials/data/documentation/healthkit/building-a-multidevice-workout-app.md
- https://www8.garmin.com/manuals-apac/webhelp/forerunner965/EN-SG/GUID-6A7D55B6-EBC0-4235-8970-FE3795630EEF-8656.html
- https://www.myzone.digital/app-support/which-garmin-devices-support-real-time-in-club-tracking-bluetooth-broadcasting
- https://developer.android.com/health-and-fitness/health-services
- https://developer.samsung.com/health/sensor/guide/introduction.html
- https://support.polar.com/ae-en/can-i-pair-h10-with-several-devices
- https://support.wahoofitness.com/hc/en-us/articles/204281384
- https://support.wahoofitness.com/hc/en-us/articles/11947819498514-Broadcasting-HR-or-Pace-Cadence-with-RIVAL
- https://support.coros.com/hc/en-us/articles/360040256991-Broadcast-heart-rate
- https://www.suunto.com/ja-jp/Support/Software-updates/Release-notes/suunto-race-2-software-updates/
- https://support.ouraring.com/hc/en-us/articles/50433376859283-Live-Activity-Tracking
- https://mi.com/global/support/faq/details/KA-579104
- https://developers.google.com/health/about
