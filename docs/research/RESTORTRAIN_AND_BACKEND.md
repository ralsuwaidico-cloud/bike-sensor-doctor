# RestOrTrain analysis and backend recommendation — research notes (24 Oct 2026)

## RestOrTrain (App Store id 6752621455) — facts
- Developer RESTORTRAIN SP Z O O (Kraków). Three co-founders (ex-Google engineer, ex-pro skier engineer, ex-EY data). iOS launched Apr 2026; Android 30 Sep 2026; no web, **no Apple Watch app**.
- Store: UAE 4.6★ (50 ratings), US 4.8★ (573). Free + Pro: AED 64.99/month, AED 549.99/year (US $14.99 / $134.99). Free tier ≈ 10 chat messages/month; workout push and indoor player are free.
- Structure: three tabs — Chat, Calendar, Athlete Profile (goals, preferences, Memory list, Custom Instructions); a newer Plan section.
- Onboarding: connect an activity source (Garmin Connect / Intervals.icu / COROS / Wahoo…) → sports, goal, weekly hours → "manage the rest in chat".
- Planning: season plan with phases and weekly-hour ranges; workouts generated per day (no library); changes via chat applied after approval; .fit/.zwo export; calendar subscription; free FTMS indoor player.
- Coaching: LLM chat (OpenAI/Google/Anthropic via enterprise APIs); metrics (CTL/ATL/TSB 42/7, zones, FTP estimate from power curve, power bests 5 s–60 min, Workout Score) are computed deterministically, the model only narrates. Memory across chats, proactive morning/post-ride notifications.
- Readiness: no named score; on-request train-or-rest advice from sleep/HRV/RHR (Garmin, COROS, Intervals.icu, Apple Health, WHOOP recovery). No Oura.
- Integrations: Garmin, COROS, Wahoo, Hammerhead, Intervals.icu (one-way push), Zwift, Rouvy, Apple Health, WHOOP. **Strava import stopped 1 Sep 2026** (Strava API policy) — archive upload instead.
- Praise: chat + automation, analysis quality, Garmin/Intervals integrations. Complaints: price, inconsistent FTP/max-HR estimates, rides mislabelled as commutes, one-way Intervals sync, loss of Strava.
- Lessons: deterministic metrics + plain-language narration; two-way sync and correct ride classification matter; do not depend on Strava import; a free useful tool (indoor player / workout push) is the acquisition hook. Our differentiator: the ESP32 computer with direct power-meter connection and an offline coach — nobody in this group ships hardware.

## Competitor table
| | RestOrTrain | TrainerRoad | JOIN | Xert | Intervals.icu |
|---|---|---|---|---|---|
| Plan adaptivity | chat-driven, approval before changes | Adaptive Training, Red/Green light | instant adaptation from 400+ library | Adaptive Training Advisor, Fitness Signature | none (analysis tool) |
| Coach explanations | conversational | no chat | no chat | advisor, no chat | none |
| Recovery inputs | sleep/HRV/RHR/WHOOP | none | Oura readiness; others manual | unknown | imports wellness fields |
| Price | $14.99/mo, $134.99/yr | $21.99/mo, $209.99/yr | €16.99/mo, €119.99/yr | $14.99/mo, $99.95/yr | free (+~$4/mo supporter) |
| Platforms | iOS, Android | iOS, Android, Win, Mac | iOS, Android, web | web + player apps | web |

## Backend / sign-in recommendation: Supabase
Compared Firebase, Supabase, AWS Amplify, CloudKit.
- **Supabase** (Auth + Postgres + Edge Functions + Storage): native Sign in with Apple (no 6-month secret rotation for native iOS), Google via GoogleSignIn-iOS / Android Credential Manager, email verify + reset built in, anonymous → upgrade, identity linking, Postgres row-level security, official Swift SDK and community supabase-kt (KMP: Android + iOS). Free: 50k MAU, 500 MB, pauses after 1 week idle → Pro $25/month. Regions: no Middle East (use Frankfurt or Mumbai). Low lock-in (plain Postgres). Account deletion = Edge Function with service role (`auth.admin.deleteUser`) + Apple token revocation. Offline-first not built in: cache-and-write-through first, PowerSync later if needed.
- Firebase: best built-in offline sync (Firestore persistence), Middle East regions (Doha/Dammam), but NoSQL model, Functions need a card (Blaze), KMP only via third-party GitLive, high lock-in.
- Amplify: Bahrain/UAE regions, but DataStore EOL May 2027, hosted-UI web view for social sign-in, more moving parts.
- CloudKit: Apple only — excludes Android.

## Apple rules
- Guideline 4.8: offering Google Sign-In requires an equivalent privacy-preserving option → Sign in with Apple.
- Guideline 5.1.1(v): in-app account deletion that removes the whole account, no support call needed; revoke Sign in with Apple tokens.

## Steps only the account holder can do (for Phase 1)
1. Apple Developer → Identifiers → App ID → enable Sign in with Apple. Create a Services ID (return URL `https://<project>.supabase.co/auth/v1/callback`). Keys → new key with Sign in with Apple → download .p8 once, note Key ID; note Team ID.
2. Google Cloud Console → project → OAuth consent screen (External, Testing while in TestFlight) → OAuth clients: Web (redirect = Supabase callback), iOS (bundle ID), Android (package + SHA-1 from developer).
3. Supabase → new project (Frankfurt) → Providers: Apple (bundle ID, secret from .p8), Google (web/iOS/Android IDs, web secret), Email (confirm on) → enable anonymous sign-ins and manual linking → copy project URL + anon key → accept DPA → Pro plan before testers depend on it.

## Key sources
- https://apps.apple.com/ae/app/restortrain/id6752621455 · https://www.restortrain.com/faq · https://restortrain.com/privacy · https://restortrain.com/strava
- https://forum.intervals.icu/t/restortrain-ai-that-thinks-about-your-training-for-ios-yes-another-one/126680
- https://the5krunner.com/2026/09/20/restortrain-ai-training-app/
- https://www.trainerroad.com/pricing · https://join.cc/pricing · https://aitoolsbakery.com/?p=18460
- https://developer.apple.com/app-store/review/guidelines/ · https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion
- https://supabase.com/pricing.md · https://supabase.com/docs/guides/auth/auth-apple · https://supabase.com/docs/guides/auth/social-login/auth-google.md · https://supabase.com/docs/guides/auth/auth-anonymous.md · https://supabase.com/docs/guides/platform/regions.md
- https://firebase.google.com/docs/firestore/manage-data/enable-offline · https://cloud.google.com/firestore/pricing · https://firebase.google.com/docs/firestore/pipelines/locations
- https://aws.amazon.com/cognito/pricing/ · https://docs.amplify.aws/gen1/android/build-a-backend/more-features/datastore/migrate-from-datastore/
- https://docs.powersync.com/integration-guides/supabase-+-powersync
