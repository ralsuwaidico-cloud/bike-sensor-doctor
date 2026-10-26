# Apple Watch → iPhone → BikeComputer: live heart rate (Cyclift 1.0, build 65+)

## What was wrong (code evidence, ios/dev e728ffa)
1. **Readings were dropped.** `BikeComputerWatch/WorkoutManager.swift` `send(bpm:at:)` sent a reading only
   `if WCSession.default.isReachable`; otherwise it set a status text and **discarded the reading**. There was no retry and
   no second channel. WatchConnectivity reachability goes false, often only briefly, whenever the watch–phone link is
   idle, being handed between Bluetooth and Wi-Fi, or lost. Every reading sent at such a moment was lost, and the phone
   view then flipped between connected and not connected. That matches the owner's reports: "Watch
   connecting/disconnecting" and "Watch data never reaches iPhone or BikeComputer reliably".
2. **No live workout channel.** Since iOS 17 / watchOS 10 the watch can mirror a running workout to the iPhone. The app
   did not use it.
3. **No version check.** CI builds the iPhone and watch apps with the same `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
   (project.yml, `ci/build.sh` passes `CURRENT_PROJECT_VERSION=$BUILD_NUMBER` to the whole archive), and the watch app is
   embedded in the iPhone app's `Watch` folder. **TestFlight installs or updates the watch app only when Automatic App
   Install is on** in the Watch app on the iPhone (Watch app › General). Otherwise the watch keeps an old build. Nothing
   told the rider about this.

## Design (what the code does now)
| Step | Watch (`BikeComputerWatch/WorkoutManager.swift`) | iPhone |
|---|---|---|
| Start | Ride start on the phone → `HKHealthStore.startWatchApp(with:)` → watch `WKApplicationDelegate.handle(_:)` → `WorkoutManager.start()`. The first time, the iPhone shows its own HealthKit sheet (workouts plus heart-rate read, the same set as Profile › Apple Health). | `WatchLink.startWatchWorkout` |
| Session | `HKWorkoutSession` + `HKLiveWorkoutBuilder`, `prepare()`, then `startActivity`. | — |
| Mirror | `startMirroringToCompanionDevice` runs once the session reports `.prepared`/`.running`, following Apple DevRel's advice in forums thread 804276. It is retried every 10 s while the workout runs and mirroring is down. | `HKHealthStore.workoutSessionMirroringStartHandler` is set at **every launch**: `WatchWorkoutMirror` is created by `WatchLink` in `BikeComputerApp.init`. HealthKit launches the app in the background if needed. |
| Live HR | Each `HKLiveWorkoutBuilder` sample becomes a `WatchHRPayload` (compact JSON: bpm, HealthKit sample time, state, build, battery, seq). It is sent with `sendToRemoteWorkoutSession(data:)` and also with WatchConnectivity `sendMessage` while the phone app is reachable. | `workoutSession(_:didReceiveDataFromRemoteWorkoutSession:)` and WCSession both feed `WatchLink.handle(payload:via:)` → `WatchHRIngest` |
| Gate | — | `WatchHRIngest` dedupes by sample time, so the same sample on both channels counts once. It drops out-of-order samples, readings older than 6 s and values outside 25–250 bpm, and never holds a value (`current(now:)` is nil after 6 s). Accepted readings go to the board as INPUT_HR with source Apple Watch. |
| Disconnect | `didDisconnectFromRemoteDeviceWithError` → mirroring is retried. After 5 failed sends, mirroring is restarted. | The mirrored session is dropped. Apple: "If the primary workout session is still running, it automatically tries to reconnect … calls the workoutSessionMirroringStartHandler block again". |
| Saving | Only the watch's primary session can save, and only when the rider taps **Save to Health**. | The mirrored session is never ended, finished or saved, and the iPhone has no builder, so **no duplicate Fitness workout**. |
| Version | On every WCSession activation the watch sends application context `{kind: watchInfo, build, hkWorkoutAuth}`. Every payload also carries the build. | `WatchVersion.compare` → "Update the Watch app: Watch app on iPhone › Cyclift › Update/Install" (Connections, Diagnostics, top message when nothing worse is wrong). The phone sends its build in the ride mirror, so the watch shows the same notice. |
| Permission | The watch reports `hkWorkoutAuth`. "denied" → "Watch heart rate needs Health permission: iPhone Settings › Health › Data Access & Devices › Cyclift". | HealthKit never reveals *read* permission. Only "no heart rate while the workout runs" is reported, never a guess. |

On iOS, `HKLiveWorkoutBuilder` exists only from iOS 26, so on the iOS 17 minimum the iPhone reads live values from the
data payloads, not from a builder on the mirrored session.

Background: the iPhone already has `UIBackgroundModes` `bluetooth-central` and `location`. A ride keeps the app running,
and HealthKit itself launches the app in the background to hand over a mirrored session. The forwarding to the board is
event-driven (`WatchLink.handle` → `DeviceLink.send(heartRate:)`), not timer-driven.

## Watch app UI (refreshed)
Cyclift teal header, live heart rate, workout state, the iPhone link (workout mirroring / Watch Connectivity / not
connected), "last delivery N s ago (channel)", the version line (watch and iPhone builds) with the update notice, the
phone's ride mirror and wrist controls (unchanged rules).

## Apple documentation followed
- Building a multidevice workout app (sample, WWDC23 10023): https://developer.apple.com/documentation/HealthKit/building-a-multidevice-workout-app
- WWDC23 session 10023 "Build a multidevice workout app" transcript: https://developer.apple.com/wwdc23/10023/ (index used: https://nonstrict.eu/wwdcindex/wwdc2023/10023/). Quotes: "first I'll set up a handler in the iPhone app launch sequence"; "if my iPhone app is not running, it will be launched in the background and handed over the workout session"; "I'll end the primary session and save it on the Apple Watch by finishing the builder".
- `HKHealthStore.startWatchApp(with:completion:)` (starts the mirrored workout from the iPhone, handled in `WKApplicationDelegate.handle(_:)`): https://developer.apple.com/documentation/healthkit/hkhealthstore/startwatchapp(with:completion:)
- `HKWorkoutSessionDelegate.workoutSession(_:didDisconnectFromRemoteDeviceWithError:)` (session invalid after disconnect; automatic reconnect calls the start handler again): https://developer.apple.com/documentation/healthkit/hkworkoutsessiondelegate/workoutsession(_:diddisconnectfromremotedevicewitherror:)
- Apple Developer Forums 804276 (watchOS 26 / iOS 26 mirroring failures; DevRel workaround: mirror only after `.prepared`/`.running`): https://developer.apple.com/forums/thread/804276
- Apple Developer Forums 769355 (`sendToRemoteWorkoutSession` sometimes never completes, so the WatchConnectivity fallback stays): https://developer.apple.com/forums/thread/769355
- Apple Developer Forums 782370 (start handler never called when not registered at launch): https://developer.apple.com/forums/thread/782370
- "Remote session delegate is not set up" timing note (send only after prepare + mirroring): https://nonstrict.eu/blog/2024/hkworkoutsession-remote-delegate-not-setup-error

## What CI proves vs what needs the real watch
**CI-verified (simulator, unit tests):** de-duplication across channels, the 6 s drop and no-hold rule, payload
encode/decode, WatchLink counting a sample once from both channels, version handshake parsing, and the watch-path stage and
message rules. CI also proves that the iPhone and watch targets compile against the iOS 26 / watchOS 26 SDK with
iOS 17 / watchOS 10 deployment.

**Needs a real iPhone + Apple Watch (cannot be simulated):**
1. `startWatchApp` wakes the watch app and starts the workout with the phone locked.
2. `workoutSessionMirroringStartHandler` fires (Diagnostics › Apple Watch app › Live channel = "workout mirroring").
   Also check it after force-quitting Cyclift on the phone.
3. Heart rate keeps arriving with the iPhone locked in a pocket for 10+ minutes. Diagnostics counters "mirrored" should
   rise while "messages" stays low.
4. Walk out of range and back: the mirrored session reconnects by itself and heart rate resumes within about 10 s.
5. The board shows HR source WATCH (Forwarded stage OK).
6. Exactly one workout in Fitness after Save; none after Discard.
7. On iOS / watchOS 26.0.x, the mirroring bug in forum 804276 may still occur. WatchConnectivity then carries the
   readings while the phone app is open, and the diagnostics show which channel was used.
8. TestFlight: with Automatic App Install off, the version notice appears until the watch app is updated.
