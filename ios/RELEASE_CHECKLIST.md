# Athletics 1.0 — App Store compliance checklist (what the build already satisfies, what the owner confirms)

| Guideline / requirement | Status in the build | Owner action |
|---|---|---|
| 4.8 Sign in with Apple required when another third-party login (Google) is offered | Apple is offered first, natively, on onboarding and in Profile › Account | Enable the Sign in with Apple capability on the App ID; configure the Apple provider in Supabase (backend/supabase/README.md) |
| 5.1.1 (i) Privacy policy link in the app and in App Store Connect | Profile › About › Privacy policy (bundled); `ios/legal/privacy.md` for hosting | Host the two legal pages (TRACK 2 publishes them on GitHub Pages); paste the URL in ASC › App Privacy and the listing |
| 5.1.1 (ii) Permission purpose strings | All usage descriptions rewritten for Athletics (Bluetooth, Location when-in-use + always-and-when-in-use, Health share/update, Watch Health) | — |
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

## App Store Connect listing — status (26 Oct 2026, written by `ios/ci/asc_listing.py`, drafts only)

Run with the **App Store listing** workflow (Actions tab, or push to branch `asc-listing/check` / `asc-listing/apply`).
Reports and screenshots: branch `ci-logs`, folder `ios/asc-listing/run-N/`. Nothing is ever submitted by the script.

| Item | Status |
|---|---|
| Store name | **"Athletics: Hybrid Training"** (plain "Athletics" is taken by another developer — HTTP 409 DUPLICATE.DIFFERENT_ACCOUNT). Home-screen name stays "Athletics". |
| Subtitle, privacy policy URL | set ("Ride, lift and plan your week") |
| Categories | Health & Fitness / Sports — set |
| Age rating | content questions answered "None"/No, health-or-wellness topics Yes, social media No — set; kids band / overrides left empty (not a kids app) |
| Version | 1.0 renamed to **1.0.0** (matches the build), copyright "2026 Athletics" — set |
| Description, keywords, promotional text, support + marketing URLs | set from `ios/store/en-US/` |
| App Review notes, demo account not required | set (guest mode, background modes, HealthKit, deletion path explained); later edits need the owner's contact fields first (Apple rule) |
| Screenshots | 5 × 1320×2868 from the real app (simulator, seeded rider "Alex") in the largest iPhone set (`APP_IPHONE_67`, which takes the 6.9" size) |
| Sign in with Apple capability on the App ID | enabled by the script (`APPLE_ID_AUTH`) |
| **Sign in with Apple entitlement in the app** | **MISSING** — `ios/project.yml` entitlements lack `com.apple.developer.applesignin: [Default]`; native Apple sign-in fails on a real iPhone (error 1000) until it is added and a new build is uploaded |
| Build attached to the version | none yet — owner picks the 1.0.0 release-candidate build |
| Legal/support pages | prepared in `docs/site/` (privacy, terms, support, index); **not online yet** — see owner actions |

### Owner actions (account holder, in App Store Connect / GitHub)
1. **Support e-mail**: decide which address is public. Replace `SUPPORT_EMAIL` in `docs/site/*.html` (Claude can do it once you name the address). The in-app privacy policy and terms still contain your personal Gmail — say if that should change too.
2. **Publish the legal pages** (one toggle): GitHub › repository Settings › Pages › Source "Deploy from a branch", branch `ios/dev` (or `main` after merging), folder `/docs` → Save. The URLs used in the listing are then live:
   - https://ralsuwaidico-cloud.github.io/bike-sensor-doctor/site/privacy.html
   - https://ralsuwaidico-cloud.github.io/bike-sensor-doctor/site/terms.html
   - https://ralsuwaidico-cloud.github.io/bike-sensor-doctor/site/support.html
   - https://ralsuwaidico-cloud.github.io/bike-sensor-doctor/site/index.html
3. **App Privacy** (App Store Connect › App Privacy › Get Started) — answer exactly:
   - Do you collect data? **Yes** (only when the rider creates an account; guest mode collects nothing).
   - Contact Info › **Email Address** — App Functionality; linked to the user; not used for tracking.
   - Health & Fitness › **Health**, **Fitness** — App Functionality; linked; not tracking.
   - Location › **Precise Location** — App Functionality; linked; not tracking (route of synced rides).
   - Identifiers › **User ID** — App Functionality; linked; not tracking.
   - User Content › **Other User Content** (notes on workouts) — App Functionality; linked; not tracking.
   - Everything else (purchases, financial, contacts, browsing, search, usage data, diagnostics, sensitive info, advertising data): **not collected**. Tracking: **No**.
   - Privacy Policy URL: the privacy URL above (already in the listing).
4. **Pricing and Availability**: price **Free** (a price schedule exists — confirm it is Free); availability: all countries or your choice.
5. **App Review information**: contact first/last name, phone, e-mail (the script never writes personal data). Sign-in required: **No**.
6. **Build**: after the 1.0.0 RC is on TestFlight and tested, select it on the 1.0.0 version page.
7. **Accounts backend** (needed before Google/e-mail sign-in work): `backend/supabase/README.md` — Supabase project, Apple Services ID + key, Google OAuth clients, GitHub secrets.
8. **Submit for Review** — only you, after approving everything above. Nothing is submitted automatically.

### Android (Google Play)
Not releasable as 1.0: the Android app is a Compose skeleton (Link codec + five empty tabs). Missing for a Play release:
recording, plan/strength/coach screens, BLE device link, Google Sign-In/Supabase, Health Connect, background location
service, signed AAB + Play App Signing, store listing, Data safety form, account deletion web link. Do not create a Play
listing for 1.0; iOS ships first.
