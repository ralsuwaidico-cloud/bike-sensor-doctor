# Rebrand: BikeComputer → Athletics → **Cyclift** (1.0.0)

The app is **Cyclift**: a general hybrid cycling + strength training app. **BikeComputer** stays the name of the
optional ESP32 handlebar device (one supported accessory among standard Bluetooth sensors, Apple Watch and Apple
Health). "Athletics" was the working name of the 1.0 release candidate (26 Oct 2026, morning) and is retired.

## What changed (user-visible)
- iPhone and Apple Watch home-screen name: `CFBundleDisplayName = Cyclift` (project.yml, both apps). CI checks the
  archived apps carry it (`ios/ci/build.sh`).
- New original icon and launch mark, drawn by `ios/tools/make_icon.py` (no artwork, fonts or third-party marks): the
  turquoise accent of the app on a rounded square, a white "C" drawn as a chainring (teeth on the outside, open on the
  right), a hub, and a crank arm that runs out of the C and ends in two weight plates — a crank that is also a barbell.
  Regenerated: iPhone + Watch 1024 masters, launch mark 1x/2x/3x, Android mipmaps, Play icon, `ios/store/app-icon-1024.png`.
- Onboarding welcome (name, mark, a sensor-neutral intro), sign-in sheet, Profile › About ("Cyclift 1.0.0 (n)", Support
  link), Apple Watch title and hints, phone/watch "open Cyclift" messages, data export file name (`cyclift-export-…`).
- Privacy policy and terms (in the app, `ios/legal/`, `docs/site/`): Cyclift; describe the universal source design; no
  personal e-mail address anywhere (placeholder `SUPPORT_EMAIL`, see below).
- Store metadata (`ios/store/en-US/`), web pages (`docs/site/`), Supabase setup guide, Android label "Cyclift".
- The in-app mark view is `CycliftMark` (`AthleticsMark` remains as an alias so older code still compiles).

## Support contact
The repository is public, so no personal address is committed. The legal pages contain `SUPPORT_EMAIL`:
- web pages (`docs/site/*.html`): replace `SUPPORT_EMAIL` once the owner chooses the public address;
- in the app: CI writes the optional GitHub secret `CYCLIFT_SUPPORT_EMAIL` into Info.plist; when it is empty the pages
  show "Contact: see the support page" with a link to `docs/site/support.html` (published on GitHub Pages).

## What deliberately did NOT change
- Bundle identifiers `com.ralsuwaidico.bikecomputer` / `.watchkitapp` / `.tests` / `.uitests`, the Android package
  `com.ralsuwaidico.bikecomputer`, `PRODUCT_NAME` (BikeComputer / BikeComputerWatch), the Xcode target and scheme names,
  the URL scheme `com.ralsuwaidico.bikecomputer` (sign-in links), the Application Support folder
  `…/BikeComputer/store.json`, Supabase table names, BLE UUIDs and the "BikeComputer Link" Bluetooth name.
- Therefore installed data (profile, rides, strength logs, templates, plan, settings) survives the update unchanged —
  checked by the launch smoke tests on stores from builds 24, 30, 33, 36 and 40.

## Why the bundle ID must stay
Changing a bundle ID creates a *different app* for Apple and Google: a new App Store Connect record (new TestFlight
history, new review, new ratings), existing installs would not update to it and their on-device data would not migrate
(iOS keeps data per bundle ID), HealthKit permissions and Keychain items (the sign-in session) would be lost, and the
Watch app would have to be re-paired with the new companion ID. The App Store name ("Cyclift") is set in App Store
Connect and is independent of the bundle ID, so no ID change is needed.

## Still to rename after the workstream merge (files owned by other workstreams)
Listed in the A2 report; the integrator applies them when merging into `ios/dev`: permission texts in `project.yml`
(NSBluetooth…, NSLocation…, NSHealth… start with "Athletics"), `ConnectionsView.swift`, `DeviceLink.swift`,
`HealthImport.swift`, `RideRecorder.swift`, Android `MainActivity.kt` comment. `grep -rn Athletics ios android docs/site`
must then only find this file, the changelog and the briefs.

## Name availability
See `ios/NAME_CHECK.md` (App Store Connect result + web/trademark findings). Not legal advice: the owner should
commission a trademark clearance search before the final submission.
