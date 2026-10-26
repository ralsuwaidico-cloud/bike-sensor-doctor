# Cyclift 1.0 — App Store compliance checklist (what the build already satisfies, what the owner confirms)

**1.0 status (26 Oct 2026, branch `ios/rel-release`):** no accounts, no placeholders, privacy manifests, support
contact published — per `docs/briefs/RELEASE_1_0_DECISIONS.md`. Simulator/CI-tested only.

| Guideline / requirement | Status in the build | Owner action |
|---|---|---|
| Name / trademark | App Store name **Cyclift** accepted (draft); no live trademark for the exact word found in public mirrors — see `ios/NAME_CHECK.md` | Commission a trademark clearance search before submission (not legal advice) |
| 4.8 Sign in with Apple | **Not applicable in 1.0**: no sign-in of any kind (`ReleaseFlags.accountsEnabled = false`). The entitlement stays in the build (harmless; CI checks it) | — |
| 5.1.1 (i) Privacy policy link in the app and in App Store Connect | Profile › About › Privacy policy (bundled, 1.0 text: no account, no server, data on the iPhone); `ios/legal/privacy.md`, `docs/site/privacy.html` | Publish the pages (GitHub Pages, below); paste the URL in ASC |
| 5.1.1 (ii) Permission purpose strings | Bluetooth, Location **When In Use only** (the unused Always string was removed), Health share/update (iPhone + Watch) — all start with "Cyclift" and describe 1.0 exactly (unit test + CI check) | — |
| 5.1.1 (v) Data deletion inside the app | Profile › Your data › Delete all data on this phone (confirmation; nothing exists off the device) | — |
| 5.1.1 (iv) No account required | There are no accounts | — |
| 5.1.2 Data use and sharing | No analytics, ads, tracking or server. Supabase SDK still linked but never initialised (no client, no request) | ASC › App Privacy: **"Data Not Collected"** |
| Privacy manifest | `PrivacyInfo.xcprivacy` in iPhone + Watch apps: tracking false, no domains, no collected data; UserDefaults `CA92.1` (iPhone). CI verifies both in the archive | — |
| 5.1.3 Health and Fitness (HealthKit) | Health read/write only after the rider connects it; Health data never leaves the device; no advertising use | Keep the HealthKit capability |
| 2.5.4 Background modes | `bluetooth-central` (sensors / BikeComputer during rides) and `location` (ride recording with the screen locked) | State both in Review Notes |
| 2.1 Completeness | No "planned / coming soon / not configured" rows; Garmin/WHOOP/Oura hidden; phone-only ride, strength log, plan, coach and onboarding work offline without hardware | — |
| 2.3 Accurate metadata | Screenshots from the simulator build | **Store description + review notes still mention accounts/Google sign-in and "Profile > Account"** — update `ios/store/en-US/` (ASC listing workstream) before submission |
| 1.4.1 Safety — health claims | Coach wording is "suggestion"/"estimate"; terms: not medical advice | — |
| Encryption export compliance | `ITSAppUsesNonExemptEncryption = false` (iPhone + Watch) | — |
| Support URL / contact | ralsuwaidico@gmail.com (owner's public choice): Info.plist, Profile › About › Contact support, legal pages, `docs/site/*` | — |
| Watch app | Companion-only, HealthKit workout, no separate listing needed | — |

Nothing here is hardware-verified; the device-side checklist remains TEST-v0.7.0.txt / BUILD40-TEST.txt.

---

## App Store Connect listing — status (26 Oct 2026, `ios/ci/asc_listing.py`, drafts only, run `ios/asc-listing/run-4`)

Run with the **App Store listing** workflow (push to branch `asc-listing/apply`, or Actions tab). Reports and
screenshots: branch `ci-logs`, folder `ios/asc-listing/run-N/`. Nothing is ever submitted by the script.

| Item | Status |
|---|---|
| Store name | **"Cyclift" — ACCEPTED** (replaces "Athletics: Hybrid Training"). Home-screen name "Cyclift". |
| Subtitle, privacy policy URL | set ("Ride, lift and plan your week") |
| Categories | Health & Fitness / Sports — set |
| Age rating | set (24 answers; kids band / overrides left empty) |
| Version | **1.0.0**, copyright "2026 Cyclift" — set |
| Description, keywords, support + marketing URLs | set from `ios/store/en-US/` (Cyclift text, standard Bluetooth sensors, BikeComputer optional) |
| Promotional text | set (run 5; shortened to 153 characters after run 4 refused 178 > 170) |
| App Review notes | **old (Athletics) notes still on Apple's side**: Apple accepts an update only after the owner fills the App Review contact fields; then re-run the listing workflow |
| Screenshots | 5 × 1320×2868 from the real app (simulator, seeded rider "Alex"), uploaded. **Retake after the ride-layout and sources workstreams are merged** (the ride screenshot shows the pre-Cyclift ride screen) |
| Sign in with Apple | capability on the App ID enabled; entitlement in project.yml since commit b67cfd4 (CI verifies it in the signed app) |
| App icon | new Cyclift icon (ships with the next build; the store icon comes from the build) |
| Build attached to the version | none — owner picks the 1.0.0 release candidate |
| Legal/support pages | 1.0 versions in `docs/site/` with the support address; **not online yet** |

### Owner actions (account holder)
1. **Trademark**: read `ios/NAME_CHECK.md`; commission a clearance search (UAE + US + EU/WIPO) before submitting. Check
   the domains cyclift.com / cyclift.app at a registrar if you want them.
2. **Support e-mail**: done — ralsuwaidico@gmail.com is in the app, the legal pages and `docs/site/` (no secret needed;
   the `CYCLIFT_SUPPORT_EMAIL` GitHub secret is no longer used and can be deleted).
3. **Publish the legal pages** (one toggle): GitHub › Settings › Pages › Source "Deploy from a branch", branch `ios/dev`
   (or `main` after merging), folder `/docs` → Save. The listing URLs then work:
   https://ralsuwaidico-cloud.github.io/bike-sensor-doctor/site/privacy.html · …/terms.html · …/support.html · …/index.html
4. **App Review contact** (App Store Connect › 1.0.0 › App Review Information): first/last name, phone, e-mail. Then
   ask Claude to re-run the listing workflow so the Cyclift review notes and promotional text are written.
5. **App Privacy** (App Store Connect › App Privacy): **Data Not Collected** (1.0 has no account, server or analytics;
   everything stays on the device). Tracking: No. Privacy Policy URL as above.
6. **Pricing and Availability**: confirm price **Free**; choose countries.
7. **Accounts backend**: not needed for 1.0 (accounts come in 1.1; `backend/supabase/README.md` stays for then).
8. **Build**: after the merged 1.0.0 RC is on TestFlight and tested on the iPhone + Watch (+ BikeComputer), select it on
   the 1.0.0 page.
9. **Submit for Review** — only you, after approving everything above. Nothing is submitted automatically.

## Android (Google Play) — gap list (honest status: not releasable as 1.0)
The Android app is a Jetpack Compose **skeleton**: Link codec + five empty tabs, label "Cyclift" and the new icon
(CI builds a debug APK). Missing before a Play release:
1. **Feature parity**: onboarding, weekly plan, ride recording (GPS foreground service, recording/storage), ride layouts
   + coach panel, strength logging/routines/templates, progress/history, profile pages, data export, deletion.
2. **Sources**: BLE direct sensors (standard HR 0x180D, power 0x1818, CSC 0x1816), BikeComputer link (pairing, profile
   sync, ride mirroring), Health Connect instead of Apple Health, Wear OS instead of Apple Watch (or none).
3. **Accounts + sync**: Supabase Auth (Google via Credential Manager, e-mail, Sign in with Apple optional on Android),
   session storage in EncryptedSharedPreferences/Keystore, the same sync engine and merge rules as iOS.
4. **Permissions/background**: BLUETOOTH_SCAN/CONNECT, location (fine + background with Play's declaration form),
   foreground-service type `location|connectedDevice`, notifications.
5. **Release plumbing**: upload keystore + Play App Signing, signed **AAB** (release build in CI), versioning, ProGuard/R8.
6. **Play Console**: store listing (texts can reuse `ios/store/en-US`), screenshots, Data safety form, content rating,
   privacy-policy URL, account-deletion web URL (required by Play), target-API compliance, internal testing track.
7. **Play developer account**: one-time registration fee — a **paid agreement the owner must approve**; nothing has been
   created. Recommendation: ship iOS 1.0 first; Android as a later version.
