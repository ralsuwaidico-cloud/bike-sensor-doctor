# Rebrand: BikeComputer → Athletics (1.0.0)

## What changed
- Displayed app name on the iPhone and Apple Watch home screens, launch screen, onboarding welcome, About, and every
  string where the name meant *the app*: `CFBundleDisplayName = Athletics` for both apps, new launch screen (accent colour +
  mark), new app icon set (`ios/tools/make_icon.py` draws it: turquoise square, white geometric "A" with a pulse bar — an
  original mark, no third-party artwork), permission texts rewritten to start with "Athletics …" and to describe exactly
  what each permission is for.
- Android skeleton: label "Athletics", launcher icon from the same master, Play listing icon in `android/store/`.
- "BikeComputer" stays wherever it means the device: Connections, pairing, firmware, device settings, ride-owner labels,
  Bluetooth service name "BikeComputer Link". The board's firmware and Bluetooth identifiers are untouched.

## What deliberately did NOT change
- Bundle identifiers `com.ralsuwaidico.bikecomputer` / `.watchkitapp` / `.tests` / `.uitests`, the Android package
  `com.ralsuwaidico.bikecomputer`, `PRODUCT_NAME` (BikeComputer / BikeComputerWatch), the Xcode target names, the URL
  scheme `com.ralsuwaidico.bikecomputer`, the Application Support folder `…/BikeComputer/store.json`.
- Therefore: installed data (profile, rides, strength logs, templates, plan, settings) survives the update unchanged —
  verified by the launch smoke tests on data files from builds 24, 30, 33, 36 and 40.

## Why the bundle ID must stay
Changing a bundle ID creates a *different app* for Apple and Google: a new App Store Connect record (new TestFlight
history, new review, new ratings), the existing installs would not update to it and their on-device data would not
migrate (iOS keeps data per bundle ID), HealthKit permissions and Keychain items would be lost, and the Watch app would
have to be re-paired with the new companion ID. The App Store product name ("Athletics") is set in App Store Connect and
is independent of the bundle ID, so no ID change is needed for the rebrand.
