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
