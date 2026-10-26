# Cyclift 1.0 — App Store compliance checklist (what the build already satisfies, what the owner confirms)

| Guideline / requirement | Status in the build | Owner action |
|---|---|---|
| Name / trademark | App Store name **Cyclift** accepted (draft); no live trademark for the exact word found in public mirrors — see `ios/NAME_CHECK.md` | Commission a trademark clearance search before submission (not legal advice) |
| 4.8 Sign in with Apple required when another third-party login (Google) is offered | Apple is offered first, natively, on onboarding and in Profile › Account | Enable the Sign in with Apple capability on the App ID; configure the Apple provider in Supabase (backend/supabase/README.md) |
| 5.1.1 (i) Privacy policy link in the app and in App Store Connect | Profile › About › Privacy policy (bundled); `ios/legal/privacy.md` for hosting | Host the two legal pages (TRACK 2 publishes them on GitHub Pages); paste the URL in ASC › App Privacy and the listing |
| 5.1.1 (ii) Permission purpose strings | All usage descriptions still start with "Athletics" — rename to Cyclift when the workstreams are merged (A2 report lists the exact texts); otherwise describe exactly what each permission is for (Bluetooth, Location when-in-use + always-and-when-in-use, Health share/update, Watch Health) | — |
| 5.1.1 (v) Account deletion inside the app | Profile › Account › Delete account and all data (3 taps): server RPC `auth_delete_user` + local wipe; also works for guests (local wipe) | Run `schema.sql` so the RPC exists |
| 5.1.1 (iv) Account not required to use the app | Guest mode is first on onboarding; every feature works offline without an account | — |
| 5.1.2 Data use and sharing | No analytics, no ads, no third-party SDKs besides Supabase (auth + the user's own rows). Data export in Profile › Account | Fill ASC App Privacy: Contact info (e-mail, for accounts), Health & Fitness (workouts, HR), Location (precise, while recording), Identifiers (user ID) — all "linked to the user", none used for tracking |
| 5.1.3 Health and Fitness (HealthKit) | Health read/write only on explicit opt-in; Health data never sent to servers unless the rider syncs a workout they recorded; no advertising use | Keep the HealthKit capability (it is in the entitlements and verified by CI) |
| 2.5.4 Background modes justification | `bluetooth-central` (BikeComputer link during rides) and `location` (ride recording with the screen locked) — both user-visible features | In Review Notes, state the two uses |
| 2.1 Performance / completeness | Guest flow, phone-only rides, strength logging, plan and coach work without any hardware or account; hardware-dependent features are labelled | Provide a demo account only if reviewers need to test sign-in (optional; guest works) |
| 2.3 Accurate metadata / screenshots must show the real app | Screenshots are taken from the simulator build by TRACK 2 (`asc-*` workflow) | Review the screenshots before submission |
| 1.4.1 Safety — health claims | Coach wording is "suggestion"/"estimate", terms state it is not medical advice | — |
| Encryption export compliance | `ITSAppUsesNonExemptEncryption = false` (HTTPS only) | — |
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
| Legal/support pages | Cyclift versions in `docs/site/`; **not online yet**; contain `SUPPORT_EMAIL` placeholders |

### Owner actions (account holder)
1. **Trademark**: read `ios/NAME_CHECK.md`; commission a clearance search (UAE + US + EU/WIPO) before submitting. Check
   the domains cyclift.com / cyclift.app at a registrar if you want them.
2. **Support e-mail**: choose the public address. Then (a) tell Claude to put it into `docs/site/*.html` (or replace
   `SUPPORT_EMAIL` there), and (b) add GitHub secret `CYCLIFT_SUPPORT_EMAIL` (Settings › Secrets and variables ›
   Actions) so the in-app privacy policy and terms show it; without it they say "Contact: see the support page".
   Your personal Gmail has been removed from every page in the app and repository.
3. **Publish the legal pages** (one toggle): GitHub › Settings › Pages › Source "Deploy from a branch", branch `ios/dev`
   (or `main` after merging), folder `/docs` → Save. The listing URLs then work:
   https://ralsuwaidico-cloud.github.io/bike-sensor-doctor/site/privacy.html · …/terms.html · …/support.html · …/index.html
4. **App Review contact** (App Store Connect › 1.0.0 › App Review Information): first/last name, phone, e-mail. Then
   ask Claude to re-run the listing workflow so the Cyclift review notes and promotional text are written.
5. **App Privacy** (App Store Connect › App Privacy): Collect data — Yes (only with an account). Contact Info › Email
   Address; Health & Fitness › Health, Fitness; Location › Precise Location; Identifiers › User ID; User Content › Other
   User Content — each: App Functionality, linked to the user, not used for tracking. Everything else: not collected.
   Tracking: No. Privacy Policy URL as above.
6. **Pricing and Availability**: confirm price **Free**; choose countries.
7. **Accounts backend** (Apple/Google/e-mail sign-in on real phones): follow `backend/supabase/README.md` (Supabase
   project, `schema.sql`, Apple Services ID e.g. `com.ralsuwaidico.cyclift.signin` + key, Google OAuth clients, GitHub
   secrets `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GOOGLE_WEB_CLIENT_ID`). Until then the app is guest-only and says so.
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
