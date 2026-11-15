# E1 ride authorization, external BikeComputer rides and location permission

Status: **Owner-approved 16 Nov 2026 · implemented on a branch · evidence in the last section**
Scope: the iPhone app only. No firmware change. Not a redesign of the ride data model.
Code: commit `a6ded926` (see the evidence section for where it has run).

## 1. One start policy

Every route that can start a ride asks the same check: Ride screen, Plan "Start this workout", Apple Watch, Cyclift detachable watch.

- The check reads the athlete's training status from the athlete record at the moment of the request. The copied flag that a one-second timer refreshed is removed.
- Three answers: allowed, on hold, unavailable.
- Unavailable (the athlete record cannot be read, or the check is not connected) refuses the start. The app fails closed.
- "On hold" covers the health check ("stop" or "ill") and the athlete's own training pause, as before.

## 2. Rides begun on the BikeComputer during a hold

The phone cannot disable the device's Start button. It can only decide what the recording means.

- The recording is kept exactly as received. No measurement is changed and no route is invented.
- The ride record carries one optional marker, `startedExternallyDuringHealthHold`.
- A marked ride does not complete a planned session, does not produce an FTP suggestion, and is not counted by the adaptive coach as "rides going well". It still counts toward load, fatigue and pain, because the ride happened.
- The Ride screen shows a notice as soon as the phone sees the ride. The review page and the saved ride show the restriction.
- Saving it starts nothing else.

Existing metadata was checked first. `recorder` (board, phone, health) and `sources` (free-text labels) say who recorded a ride, not whether it was authorized, so one new field was needed. No other field was added.

**Limits, stated plainly**
- No marker means unknown. It is never proof that a ride was authorized.
- The marker is decided when the phone first sees the ride. A ride the phone only learns about later from device history is not marked, because the status at its start is unknown; such a ride makes no FTP suggestion while a hold is active.
- **Rollback is not safe for the marker.** Build 216 does not know this field. If build 216 is reinstalled and saves the data file, the marker is dropped and the ride looks like any other ride. Measurements survive; the restriction does not.
- The marker is in the data file, so it is in "Export your data". The app has no import feature; reading an exported file back was tested at data level.

## 3. Location permission

- A new phone-GPS ride does not start without location permission. The Ride screen says what is missing and offers "Allow location", or "Open Settings" when permission was refused earlier.
- Plan offers Start only when a ride can actually start; the Ride screen carries the explanation.
- A BikeComputer ride is never blocked or discarded for missing phone location. Its record then has no route and does not list phone GPS as a source.

## 4. What is not covered

- The four routes are tested at the point they all call (the recorder with a real athlete record). The screens and watch links themselves are read in source only.
- The permission prompt itself is not screen-tested; CI grants the simulator permission before the ride screen tests.
- Nothing here has run on a physical iPhone, Apple Watch or BikeComputer.

## Evidence

- Fast logic run 91 on `a6ded926` (Linux, data level): 426 executed, 0 failed, 3 skipped. Passed: marked ride kept, completes nothing, proposes no FTP, marker survives relaunch and export; no marker written for an ordinary ride; marked rides are not progression evidence; training status follows the athlete record at once and is "unavailable" for an unreadable store; a successful save completes only the matching planned session; recovery after a cut-short file restores history and session status, twice; stale and unreadable previous copies. Six build-216 fixtures: 0 differences.
- Skipped on Linux (needs a truly read-only folder): the failed-save test. It must run on iOS.
- iOS: pending on `a6ded926`. The recorder tests (hold in and out, after launch, unavailable status, location, external ride) run only on iOS.
- Physical device: none.
