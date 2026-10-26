# Cyclift accounts — Supabase setup (owner steps)

The app uses Supabase Auth (Apple, Google, e-mail) and a small Postgres database with row-level security for sync.
Nothing here costs money on the Free plan at our scale; no paid agreement is needed. All values below go into
GitHub Actions **secrets** (Settings › Secrets and variables › Actions) — never into source files.

## 1. Create the project (5 min)
1. https://supabase.com → Sign in (GitHub or e-mail) → **New project**.
2. Organisation: your own. Name: `cyclift`. Database password: let it generate one and store it in your password
   manager (you will not need it for the app). Region: **Frankfurt (eu-central-1)**. Plan: Free.
3. Wait until the project is ready, then open **Project Settings › API** and copy:
   - **Project URL** → GitHub secret `SUPABASE_URL` (looks like `https://xxxxxxxx.supabase.co`)
   - **anon public** key → GitHub secret `SUPABASE_ANON_KEY` (a long `eyJ…` string; it is safe to ship in the app,
     the row-level-security policies protect the data; never copy the `service_role` key anywhere).

## 2. Database (2 min)
1. **SQL Editor › New query** → paste the whole of `schema.sql` → **Run**. It is idempotent (safe to run again).
2. Check **Table Editor** shows `profiles, rides, strength_sessions, templates, plans, settings`, each with RLS on.

## 3. Authentication providers
**Authentication › URL Configuration**
- Site URL: `https://ralsuwaidico-cloud.github.io/bike-sensor-doctor/site/index.html` (the Cyclift home page; any https
  page you own works — it is only used when a link cannot open the app)
- Redirect URLs: add `com.ralsuwaidico.bikecomputer://auth-callback`

**Authentication › Providers › Email**: enabled, **Confirm email ON**, Secure email change ON. (Templates › keep
defaults; you can change the sender name to "Cyclift" under Authentication › Email Templates, and the subject lines to
mention Cyclift.)

**Apple** (needed for Sign in with Apple through Supabase):
1. https://developer.apple.com/account/resources/identifiers → the App ID `com.ralsuwaidico.bikecomputer` already
   exists → tick **Sign In with Apple** → Save. (The CI job `asc-prepare` also does this through the API.)
2. Identifiers › **+** › Services IDs → identifier `com.ralsuwaidico.cyclift.signin`, description "Cyclift web
   sign in" → Register → open it → tick Sign In with Apple › Configure: primary App ID = the app, Domains =
   `<your-project-ref>.supabase.co`, Return URLs = `https://<your-project-ref>.supabase.co/auth/v1/callback` → Save.
3. Keys › **+** › name "Cyclift SIWA" → tick Sign in with Apple › Configure → primary App ID → Register →
   **Download the .p8 once** and note the Key ID.
4. Supabase › Authentication › Providers › **Apple**: enabled; Client IDs = `com.ralsuwaidico.bikecomputer,com.ralsuwaidico.cyclift.signin`;
   Secret Key (for OAuth) = generated from Team ID + Key ID + the .p8 (Supabase shows a generator link; the secret
   expires every 6 months — put a reminder). The native iOS flow only needs the Client ID list; the web flow needs the secret.

**Google**:
1. https://console.cloud.google.com → New project "Cyclift" → APIs & Services › **OAuth consent screen**: External,
   app name Cyclift, app logo = `ios/store/app-icon-1024.png`, support e-mail = the public support address, scopes: email, profile, openid → Save. Add yourself as a test user
   until the app is published (then "Publish app"; no verification needed for these basic scopes).
2. Credentials › **Create credentials › OAuth client ID**:
   - type **Web application**, name "Cyclift Supabase", Authorised redirect URI
     `https://<your-project-ref>.supabase.co/auth/v1/callback` → copy **Client ID** → GitHub secret `GOOGLE_WEB_CLIENT_ID`
     and its **Client secret** → Supabase › Providers › Google › Client Secret.
   - type **iOS**, name "Cyclift iOS", Bundle ID `com.ralsuwaidico.bikecomputer` → copy Client ID → GitHub secret
     `GOOGLE_IOS_CLIENT_ID`.
3. Supabase › Authentication › Providers › **Google**: enabled; Client IDs = the web client ID (add the iOS client
   ID too, comma-separated); Client Secret = the web client secret; "Skip nonce check" OFF.

## 4. GitHub secrets (summary)
| Secret | Value | Used for |
|---|---|---|
| `SUPABASE_URL` | Project URL | app config (Info.plist at build time) |
| `SUPABASE_ANON_KEY` | anon public key | app config |
| `GOOGLE_WEB_CLIENT_ID` | Google web OAuth client ID | Google sign-in via Supabase |
| `GOOGLE_IOS_CLIENT_ID` | Google iOS OAuth client ID | reserved (native Google SDK not used in 1.0) |
| `CYCLIFT_SUPPORT_EMAIL` | the public support address (optional) | shown on the in-app privacy policy and terms; without it they say "Contact: see the support page" |

Until `SUPABASE_URL`/`SUPABASE_ANON_KEY` exist, the app builds and runs exactly as before: guest mode, everything
on the phone, and the account page says "Accounts not configured yet".

## 5. What the app does with it
- Sign in with Apple: native Apple credential → `signInWithIdToken(provider: .apple)` (nonce-checked).
- Google: Supabase OAuth web flow in an in-app browser (`ASWebAuthenticationSession`) → redirect to
  `com.ralsuwaidico.bikecomputer://auth-callback`.
- E-mail: sign up (confirmation e-mail), sign in, password reset (e-mail link), all by Supabase — the app never
  stores or hashes passwords.
- Session: Supabase JWT + refresh token kept in the iOS Keychain; logout = `signOut` + local session wipe (data stays).
- Guest → account: on first sign-in every local record is pushed; nothing is deleted or replaced locally.
- Deletion: Profile › Account › **Delete account and all data** → `auth_delete_user()` RPC (removes all rows and the
  auth user) → local wipe. Reachable in 3 taps. Also available without an account (local wipe only).
- Export: Profile › Account › Export my data → JSON file (local data; `export_my_data()` when signed in).

## 6. Names and identifiers (Cyclift rebrand)
The app is called **Cyclift**; the identifiers keep their original names on purpose and must not be changed:
bundle ID / Apple Client ID `com.ralsuwaidico.bikecomputer`, redirect URL `com.ralsuwaidico.bikecomputer://auth-callback`,
table names (`profiles, rides, strength_sessions, templates, plans, settings`). Only the names users see change: Supabase
e-mail sender name and templates, the Google consent-screen app name and logo, the Apple Services ID description.
The Services ID string itself (`com.ralsuwaidico.cyclift.signin`) is a suggestion — any unused identifier works, as long
as it is the same in Apple's portal and in Supabase › Providers › Apple › Client IDs.

## 7. Checks after setup (on a real iPhone, TestFlight build that was built after the secrets were added)
1. Profile › Account › Create account or sign in → **Sign in with Apple** → the row says "Signed in with Apple".
2. Sign out → **Sign in with Google** → Google page opens inside the app → back in the app, signed in.
3. Sign out → **Create** with an e-mail → confirmation e-mail → tap the link on the iPhone → the app opens signed in.
4. **Forgot password** → link → the app shows "New password" → save → sign in with it.
5. Second device (or delete + reinstall): sign in → rides, sessions, templates, plan, profile and settings appear.
6. Profile › Account › **Delete account and all data** → Supabase › Authentication › Users no longer lists the user.
