# Cyclift (formerly BikeComputer / Athletics) iPhone + Apple Watch — changelog

## 1.0.0 — Cyclift App Store release build (26 Oct 2026)

The build intended for App Store submission: the release candidate below plus the release hardening (no accounts in 1.0,
no placeholder features, privacy manifests, final legal/support pages). Submission only after the owner's go-ahead.

### Release candidate (26 Oct 2026, TestFlight build 58)

One integrated build of five workstreams, each CI-tested on its own branch and again after merging. Nothing below is
real-device tested until Rashed confirms it. Firmware: compatible with BikeComputer 0.7.0 (protocol 1.2.1); the
BikeComputer is optional.
- **Cyclift** name, icon and launch screen; display name checked by CI; store name "Cyclift" accepted as a draft in
  App Store Connect (not submitted). Bundle IDs, BLE identifiers and data locations unchanged — all data kept.
- **Universal sources** (`docs/INTEGRATIONS.md`): phone connects directly to standard Bluetooth heart-rate (0x180D),
  power (0x1818) and speed/cadence (0x1816) sensors; per-source status; one priority rule per metric; Garmin / WHOOP /
  Oura listed as planned only (hidden in 1.0). No brand in metric labels ("POWER · W" + source shown separately).
- **Ride layouts** (`ios/RIDE_LAYOUTS.md`): Ride Coach, Large gauges, Classic, Rings, Analytics — restored from earlier
  builds, switchable during a ride without touching recording; coach panel with "Why?" in every layout.
- **Strength audit** (`ios/STRENGTH_AUDIT.md`): 11 fixes (plan rebuild no longer wipes edits, progression compares
  against the routine, duplicate logs prevented, kg/lb display, midnight centre button, deleted-template state …).
- **Accounts** (Supabase): 9 sync/auth fixes — then switched off for 1.0 (see Release hardening below).
- **Adaptive coach** (below).

### Release hardening for the App Store (26 Oct 2026, owner decisions `docs/briefs/RELEASE_1_0_DECISIONS.md`)

- **No accounts in 1.0.** `ReleaseFlags.accountsEnabled = false`: `CloudConfig.isConfigured` is always false (even if a
  build carries Supabase values), no Supabase client is created, the sync engine never starts, sign-in links are ignored.
  No sign-in surface anywhere: onboarding starts with **Get started** (first name only); Profile has **Your data**
  (data stays on this iPhone · Export my data · Delete all data on this phone, with confirmation) instead of Account;
  Home's "Create account" card and the cloud-sync rows in App & device settings are gone. The account and sync code
  stays compiled (and unit-tested) for 1.1; the Sign in with Apple entitlement stays.
- **No placeholders (App Review 2.1).** Garmin / WHOOP / Oura rows hidden (`ReleaseFlags.plannedProvidersVisible`), the
  WHOOP row on the Heart rate page removed, "(later build)", "sync coming", "prepared but not active", "arrives later",
  "Test build" and "Waveshare" wording replaced with what the app does today; the non-functional "Save finished rides
  as workouts" toggle (the iPhone never wrote rides to Health) removed — Health saving is the watch workout's Save.
- **Privacy manifests** (`PrivacyInfo.xcprivacy`) in the iPhone and Watch apps: no tracking, no tracking domains, no
  collected data; required-reason API: UserDefaults `CA92.1` (iPhone only). CI checks both manifests in the archive.
- **Support contact** ralsuwaidico@gmail.com (owner's choice): static Info.plist value, Profile › About › Contact support,
  privacy policy, terms and the four web pages. Privacy policy rewritten for 1.0 (no account, no server, on-device data,
  Health never leaves the device, location only while recording, Bluetooth only for sensors/BikeComputer, export +
  delete, children); terms with the training-guidance (not medical advice) and hardware-optional clauses.
- **Permissions**: the unused "Always" location string removed (the app asks for When In Use only); location, Health
  read and Health write strings describe exactly what 1.0 does.

### Adaptive hybrid-athlete coach (26 Oct 2026)

See `ios/ADAPTIVE_COACH.md`. Simulator / CI-tested only.
- **Hybrid plan** answers (Hybrid Athlete mode, optional, in onboarding "Your week" and Profile › Training profile):
  primary goal, total training days, sessions per sport, session length, budgets, strength split (Full Body /
  Push-Pull-Legs / Upper-Lower / Custom list with per-week counts and routines), equipment, routines to keep. No split
  implies a day count; extra sessions share a training day, never a new day.
- Sessions without a routine are built from the rider's own exercises and equipment (once a split is chosen).
- **Check-in** after every ride and strength session (performance, effort, pain, note), stored on the record.
- **Adaptive engine** (rules-based, deterministic): session-RPE load, 4-week baselines, two-session trends, fatigue vs
  improvement flags; bounded automatic changes to future sessions; approval for fixed days, session count, split,
  replacing saved exercises, budgets and > 10 % load. "Coach adjustments": Why this changed?, Undo per change, Restore
  original plan. Pain → progression stops in that area with plain advice, no diagnosis. Low confidence → plan kept.
- Store: new optional keys only; files from builds 24–40 load unchanged; completed logs and rides are never changed.

## 1.0.0 (build BUILDNO) — 26 Oct 2026 — release candidate, TestFlight

**Athletics.** The app is renamed; the cycling device stays "BikeComputer". Feature-frozen baseline = 0.8.0 (build 40);
this build adds only the rebrand, accounts, legal pages and compliance items. Everything is **simulator/CI-tested**;
nothing is device-tested until Rashed runs `BUILDBUILDNO-TEST.txt`. Firmware 0.7.0 is the matching board release.

### Changed
- Name, icon, launch screen and app-meaning strings → Athletics (see REBRAND.md). Bundle IDs, product names, URL scheme,
  data folder and Bluetooth identifiers unchanged → existing data and pairings survive (launch tests on build-24/30/33/36/40 data).
- Permission texts rewritten for the App Store review (what each permission is for, when it is used).
- **Accounts** (Supabase Auth; the app never handles passwords itself): Sign in with Apple (native, nonce-checked),
  Google (secure in-app browser via Supabase OAuth), e-mail (sign up with confirmation, sign in, reset link that opens the
  app and asks for a new password), session in the Keychain, sign out keeps local data, guest → account upgrade uploads
  everything already on the phone, **delete account and all data** (server function + local wipe, 3 taps from Profile),
  **export my data** (JSON share sheet). When the build carries no Supabase values the app is exactly the 0.8.0 guest app
  and says "Accounts not configured yet".
- **Cloud sync**: rides, strength sessions, templates, plan and settings/profile pushed and pulled per user with
  row-level security; last-writer-wins on the phone's change time; soft-delete tombstones; rides/sessions deduplicated by
  origin id and time; offline queue, retry on sign-in / foreground / change; status and "Sync now" in Profile › Account and
  App & device settings › Data synchronization. The BikeComputer Bluetooth profile sync is unchanged (phone authoritative).
- Privacy policy and Terms bundled (Profile › About, account sheet) and exported under `ios/legal/` for hosting.
- CI: account values injected from secrets at archive time (never in source or logs), display name verified in the archive.

### Known limitations
- Google and e-mail sign-in need the owner to create the Supabase project and Google OAuth client (backend/supabase/README.md);
  until then only Apple (local identification) and guest mode are active.
- Sync merges whole records (no field-level merge); a record edited on two devices at once keeps the newer edit.
- Health-imported workouts sync as records but are not re-imported into Health on another device.
- Android remains a skeleton (not releasable); see the Android gap list from TRACK 2.

## 0.8.0 (build 40) — 26 Oct 2026 — TestFlight, internal testers only — pairs with firmware 0.7.0

**Consolidated release** (Rashed, 25 Oct 22:41): pairing lifecycle + profile sync (P0), routines on the calendar and
the adaptive Train now button (P1), on top of everything in 0.7.0. Same Link protocol (v1.2.1) and profile schema as
firmware 0.7.0; works with 0.6.x boards too (features the board lacks say "needs firmware …"). Everything below is
**simulator-tested** (unit tests incl. the firmware's byte vectors, launch smoke tests on fresh, build-24, -30, -33 and
-36 data files). **Nothing is device-tested** until Rashed runs `BUILD40-TEST.txt`.

### P0 — Bluetooth pairing that recovers (PAIRING_SYNC_BRIEF)
- Explicit connection stages **Searching → Found → Connecting → Pairing → Authenticating → Connected → Syncing profile →
  Ready**, shown as a strip on the BikeComputer page with the current stage; a 20-second watchdog per stage, so
  "Connecting…" is never indefinite: it becomes "Waiting for the board (not in range)" or a failure with a reason.
- Failure reasons in plain words from the real iOS/ATT error: *"The BikeComputer no longer has this phone's keys"*
  (CBError peerRemovedPairingInformation, ATT insufficient authentication / encryption) → the **Repair** action;
  timeouts / out of range → Try again; Bluetooth off / no permission → Open Settings.
- **Repair connection** flow (sheet): why it happens, the three steps (board: Connections › Phone › HOLD: REPAIR —
  firmware 0.7.0 takes a new Bluetooth identity; iPhone: Settings › Bluetooth › Forget This Device — the only step
  the app cannot do, with an Open Settings button; app: Start repair = forget the old identifier (kept as "stale"),
  scan by the Link service, accept the board under its new identity, pair with the code). Same board recognised by
  its board id (INFO tag 07) across identity changes.
- Buttons by state, never contradictory: Connect / Repair / Disconnect / Forget device / Retry profile sync /
  Connection diagnostics; Disconnect only while a link exists, Connect only without one.
- **Connection diagnostics** page: stage history with timestamps, last failure + error code, identities (board id,
  remembered / stale identifier), firmware + caps, the board's **LINK_DIAG** report (why the previous link ended, phones
  remembered on the board, board sync state — firmware 0.7.0 sends it once per connection; decoder tested against the
  firmware vector), profile versions and last ack, app foreground/background state, counters.
- Background reconnect unchanged in principle (state restoration + pending connect); a repair-type failure stops the
  automatic retry loop so the phone does not hammer a board that cannot pair; the dashboard row turns red "pairing
  lost — tap for Repair".

### P0 — Profile synchronisation you can trust
- The phone range-checks the profile with the **same limits as the board** (name 1–24, FTP 50–600 W, weight 30–200 kg,
  birth year 1900–2030, max HR 100–230, rest HR 25–120 and below max, LTHR 80–220, hours ≤ 40) and names the field
  instead of sending something the board would reject; a board `status 2` is explained the same way.
- Status is **pending / synced hh:mm / failed: reason**, with the last successful version and time persisted per
  board (survives app restart; shown even while the board is away); "Retry profile sync" and "Retry now" buttons;
  automatic retry on every reconnect; success is claimed only after the board's acknowledgement, never on connect.
- Firmware 0.7.0 sends its profile right after connecting ("hello"); older 0.6.x boards are asked. First pairing shows
  the differences and says the phone's profile will be applied after confirmation; a board set up on its own
  (device-only, version 0) is reconciled the same way. Rides and sensor pairings are never part of it.
- The connection stage reaches Ready only when the sync question is settled (in sync / needs your confirmation /
  unsupported firmware); a sync failure is shown but does not take the link down.

### P1 — Your routines on the calendar (HYBRID_ROUTINES_BRIEF)
- **Choose routine** on any strength session; **"Set as every Tuesday"** weekday defaults (different routines per day),
  reused when future weeks are generated unless you changed that session by hand; the calendar card shows the routine's
  name, exercises and set count instead of a generic circuit. Order, sets, reps, weights, supersets and notes are kept;
  the lifting budget is checked at assignment (warning shown) and at generation.
- Edit / replace / remove an assignment without touching the template; deleting a template clears its assignments.
- **Equipment I own** and **exercises I cannot do** (Profile › Training profile): coach suggestions are filtered by
  both; a saved exercise is never swapped silently.
- **Next workout insight** (Home and the scheduled strength screen): ONE item — progression (+1 rep bodyweight / +1 kg
  dumbbell / +2.5 kg loaded, only when the last two completed sessions support it), hold (last session RPE ≥ 9 or missed
  reps), coverage gap (from detailed logs only, with a doable exercise named), interference (demanding ride planned
  within a day) — each labelled *suggestion* or *finding*, with Why? and the evidence; **Accept** (this session only or
  also the template) / **Ignore** / **Undo**; insufficient history is stated, never invented.
- **Centre button adapts to the day**: cycling day → bicycle, "Ride now" (Ride dashboard); strength day → dumbbell,
  "Train now" (the scheduled workout with its routine); both → choice; rest → optional session; everything done →
  "Done today" with the next session; in progress → resume. It never starts recording.
- **Scheduled strength screen** rebuilt around the routine: name and duration, exercises in order with planned sets ×
  reps and the previous performance per exercise, prominent **Start workout**, one insight with Why?, secondary actions
  (choose/replace routine, weekday default, adjust this session's sets, edit, move, skip, quick log, remove) under
  **More**. Workout mode: tick each set, adjust actual reps and weight, previous performance visible, pause / resume /
  finish (only completed sets are saved, working time excludes pauses); **partial sessions are saved as you go and
  resumable after an app restart**; a second session cannot start while one is in progress.
- **Templates are created directly** (Profile › Routines, Choose routine › Create) — no completed session is created;
  templates, scheduled sessions and completed sessions are three separate types; a completed session never rewrites its
  template (the next use is prefilled from it instead).

### Preserved (audited, not rebuilt)
Five tabs, Connections dashboard rules, onboarding, Ride dashboard + coach engine, Plan / availability / timeline,
hybrid phase 1 and the 0.7.0 brief (budgets, per-day assignments, exercise search, weekly review), Wi-Fi setup, device
settings, history sync client, store schema 1 (new keys optional; build-24/30/33/36 files load unchanged).

### Known limitations
- The iPhone's own Bluetooth bond cannot be deleted by an app: after a board data reset the Settings › Bluetooth ›
  Forget step is the rider's (the Repair sheet opens Settings). With firmware 0.7.0 the board's new identity usually
  makes this unnecessary; it is still listed in the checklist.
- LINK_DIAG, PROFILE hello and the new identity exist only on firmware 0.7.0; on 0.6.x the diagnostics page says "not
  received yet" and the app asks for the profile itself.
- Insights adjust sets in place; they do not move sessions across days (manual Move keeps fixed days inviolable).
- Health-imported strength carries no exercises; Google / e-mail sign-in still wait for Supabase + Google configuration.
- The board's power state (display off / standby / deep sleep) is not reported over the link; the app shows link state.

## 0.7.0 (build 36) — 25 Oct 2026 — TestFlight, internal testers only

**Hybrid Athlete brief, P0–P2.** Everything below is **simulator-tested** (XCTest unit tests + launch smoke tests on
fresh, build-24, build-30 and build-33 data files, the last at an accessibility text size). **Nothing is device-tested**
until Rashed runs `BUILD36-TEST.txt`. No firmware change; the board profile sync is unchanged.

### P0 — layout and budget correctness
- Strength Log type picker is a 3-column grid (2 columns at accessibility text sizes) with the labels Full Body / Upper /
  Lower / Push / Pull / Custom; ≥ 44 pt targets everywhere it appears (quick log, add workout, edit workout).
- Audit of onboarding (day chips as a 7-column grid, 44 pt), weekly calendar, workout cards, summaries, Profile pages
  and sheets: `ViewThatFits` fallbacks, line limits with scale factors instead of clipping, no fixed widths that
  overflow on compact iPhones; long duration values always through the one formatter ("1 h 5 min").
- **Budgets are enforced at plan generation.** The engine fits the week to both budgets before generating: a 2 h
  cycling budget can never produce 2 h 5 min, a 2 h lifting budget never 2 h 10 min (unit-tested at the exact limits).
  Flexible activities are shortened first (longest first, 5-minute steps, never under 20 min riding / 15 min lifting),
  then fixed ones; nothing is ever added and no day is dropped. What was trimmed is shown, never silent.
- Weekly summary is compact: rides and lifts planned/completed, two budget bars, ONE prioritised action. Warnings and
  options moved behind **Fix plan** (raise the budget / edit the days / keep the trimmed version).

### P1 — per-day sport assignment, exercise search and templates
- Onboarding step **Your days**: for Monday–Sunday assign Cycling / Strength / Both / Rest / Flexible, several
  activities per day, each with its type (cycling: Zone 2, tempo, threshold, intervals, recovery, long ride, custom;
  strength: full body, upper, lower, push, pull, legs, custom routine), planned duration and **Fixed or Flexible**.
  A readable weekly preview before saving; a consistency check compares frequency, per-day durations and both budgets
  and, when they conflict, explains the conflict and asks which to relax (raise a budget, shorten flexible days, drop
  the shortest flexible day). Guest entry stays name-only; the mode is editable in Profile › Training profile.
- The same editor is Plan › Days. Older availability files (0.5.0/0.6.0 cycle/lift/both/rest + minutes) migrate into
  the new model without loss and keep writing the legacy summary, so nothing breaks on the way back.
- **Exercise search** by name, alias, equipment, movement pattern and muscle group over a built-in catalogue of
  165 exercises (written for this app; users add their own, which appear first). Detailed sessions: exercises → sets
  with reps, weight or bodyweight, one-sided flag, optional RPE per set, notes; supersets by letter; drag to reorder.
- **Templates**: create from a session, rename, edit, reuse; the next use prefills the sets from the last session that
  used the template. Quick Log remains for type / duration / effort without exercise detail.
- Coverage (squat / hinge / single-leg / core / push / pull) and progression come **only** from detailed logs. A quick
  log labelled "Full body" is never turned into muscle coverage; with no detailed logs the coach says "not known from
  quick logs".

### P2 — adaptive coaching, timeline, weekly review
- The coach evaluates **completed** sessions only: recorded rides (frequency, hours, intensity distribution from
  recorded zones, whether power/HR were present) and logged strength sessions (frequency, hours, region labels,
  movement coverage, per-exercise progression = load × reps trend over the last sessions). Planned sessions are never
  counted as done; cycling time is never lifting volume (unit-tested).
- **Interference**: a heavy leg session (logged with evidence, or planned) the day before a quality ride is flagged,
  and the coach **proposes** a change within the approved schedule — soften the ride to endurance, or make the lift
  upper-body. Proposals need **Accept**; every accepted proposal has **Undo**. Fixed days and hand-edited sessions are
  never changed by a proposal (refused in code, unit-tested).
- Findings carry evidence labels ("estimate", "insufficient evidence"); "Why?" lists them under the recommendation.
- Timeline statuses: planned / completed / skipped / missed / **imported** (Apple Health, board sync), with stable
  source ids (`health:<uuid>`, `board:<id>:<ride>`, `phone:<uuid>`) and deduplication by them. Strength entries open a
  detail page with exercises, sets, movements trained and progression sparklines.
- **Weekly review** card on Home (Strength / Hybrid modes): planned vs completed per sport, missed sessions, one
  suggested adjustment for the coming week; after two or more recent weeks with half their sessions missed it offers
  to **revise the training days** instead of imposing the same plan again.
- "What changed" line in Plan after a rebuild (riding/lifting hours, counts, per-day changes).

### Automated results
- Unit tests: 91 passed, 0 failures (run 40215413686; new `HybridV2Tests`: 16 tests covering budgets at the exact limit,
  fit order fixed/flexible, legacy migration, day marks, suggested weeks inside both budgets, catalogue and search,
  coverage unknown vs known, progression trend, template prefill, set tonnage, completed-only coaching, cycling ≠
  lifting, interference proposals with fixed/edited refusal and undo, weekly review and the revise offer, stable
  source ids and imported status, store round trip of templates/exercises/detailed logs, formatter and labels).
- Launch smoke tests (Release build on the simulator): fresh install; build-24 store; build-30 store; **build-33 store
  at accessibility text size, opening Plan › Days, the quick strength log and Profile › Training profile**.

### Physically tested
- Nothing in this build yet; build-24/27/30/33 device findings are what this release answers.

### Known limitations
- Coverage/progression need detailed logs; Health-imported strength workouts carry no exercises.
- Interference rules are frequency/label/evidence based, not physiological; no recovery (sleep/HRV) source exists.
- Proposals are limited to softening a ride or changing a lift's region; moving sessions across days remains a manual
  action (Move) so fixed days and manual edits can never be overridden.
- Exercise catalogue muscle names are plain words, not a medical taxonomy; add your own exercises when something is missing.
- Google / e-mail sign-in still need Supabase + Google configuration; firmware 0.6.x features show "needs firmware" on
  a 0.5.0 board; Android skeleton unchanged.

## 0.6.0 (build 33) — 25 Oct 2026 — TestFlight, internal testers only

**Hybrid Athlete Mode, phase 1.** One coach that sees cycling and lifting side by side. Everything below is
**simulator-tested** (unit tests + the launch smoke tests on seeded build-24 and build-30 data files); nothing is
device-tested until Rashed runs `BUILD33-TEST.txt`. No firmware change; the board profile sync is unchanged.

### Implemented
- **Training mode** Cycling / Strength / Hybrid Athlete, chosen in onboarding right after the name and editable any time in
  Profile › Training profile (changing it rebuilds the coming weeks; hand-edited sessions are kept).
- **Short onboarding** stays name-first: mode (+ priority for Hybrid, + experience) → your week (rides per week, cycling
  hours, lifts per week, lifting hours, preferred days) → the existing skippable profile steps. Nothing unknown is invented.
- **One weekly plan across both sports**: rest, ride, lift and "Ride + lift" days (the editor has a fifth day type with
  separate riding and lifting minutes). The engine respects mode, frequencies, priority (which session comes first on a
  shared day), availability and BOTH hour budgets; combined days only when the day's time allows; the leg-loading lift
  (lower / full body) goes to the lift day with the fewest rides next to it and a hard ride (Zone 3+) is kept off the days
  around it when the availability leaves a choice — a long Zone 2 ride does not count as hard. Move / edit / skip / replace
  / add / remove as before; edited sessions are never regenerated without confirmation; planned strength sessions carry a
  body region you can change.
- **Quick Strength Log** (Home, Plan toolbar, any planned strength session): Full body / Upper / Lower / Push / Pull /
  Custom, duration, effort (easy / moderate / hard or RPE 1–10), optional notes, date. Logging marks that day's planned
  strength session done and counts toward the lifting hours only. Sets / reps / weights / supersets / templates are
  announced as "coming in a later build" — nothing fake.
- **Hybrid coach on Home** (Strength and Hybrid modes): cycling progress and strength progress bars (sessions and hours vs
  your targets, planned vs done), one recommendation line, the compact workout table (type, duration, intensity,
  expected outcome, status) and "Why?" with the reasons. The "Why?" uses only what exists: rides (count, hours, intensity
  mix from recorded power zones), strength logs (count, hours, body regions as you labelled them), the plan, your
  targets. It states that no sleep / HRV / recovery source is connected.
- **Missing-training detection from evidence only**: ride frequency vs target, lift frequency vs target, push/pull balance
  (only from Push / Pull logs, ≥ 3 in 4 weeks), no lower-body session while upper sessions exist, over-budget weeks, two
  hard days back to back. Squat / hinge / single-leg / core coverage and exercise progression are reported as "not known
  from quick logs"; a Full-body or Custom label is never turned into muscle coverage.
- **Cycling hours and lifting hours separate** everywhere: Plan summary (two budget bars, two suggestion lists), Progress
  (a weekly lifting chart beside the riding chart), Profile (two budgets, lifting history), Home footer.
- **Apple Health import** (Connections › Apple Health, and in onboarding): with the workouts read permission, cycling and
  traditional / functional strength workouts of the last 90 days (30 on every launch while the switch is on) become rides
  and strength sessions marked "Apple Health". Duplicates of what the phone or BikeComputer already recorded — start
  within 2 minutes and a similar duration — or of a quick log are skipped; the same Health workout is never imported
  twice. Health workouts carry no body region and no power, and none is invented. "Connected" still appears only after iOS
  confirms the permission; iOS does not reveal read permission, so an empty import says so instead of claiming an error.
- **Timeline / history** lists strength sessions (quick log · RPE, or Apple Health) next to rides; a logged session stands
  in for the planned one on that day (no duplicate rows).
- **Store**: schema stays 1; new fields are optional with defaults, verified against a build-30-shaped file and the
  build-24 file in the launch smoke tests. Nothing saved is lost.

### Known limitations
- Phase 2 not in this build: detailed exercise logging (sets, reps, weights, supersets, templates), progression tracking,
  movement-pattern coverage — the coach says "not known from quick logs" wherever those would apply.
- The hybrid coach is rule-based ("coach (rules)"); no AI model is involved yet.
- Apple Health heart-rate history, sleep and recovery are not read; a Health ride shows duration, distance and energy only.
- Hybrid fields (mode, priority, frequencies, lifting budget) live on the phone; the board keeps receiving the shared
  athlete profile as before and knows nothing about lifting.
- Firmware 0.6.0 (Connections, Wi-Fi setup, settings, history sync) is still waiting for Rashed's approval to flash; on
  0.5.0 those app features show "needs firmware 0.6.0".
- Google / e-mail sign-in still need the Supabase + Google configuration.

### Testing checklist (short) — step-by-step version in BUILD33-TEST.txt
1. Update; your profile, plan and rides are intact. 2. Profile › Training profile → Hybrid Athlete, balanced, 3 rides /
5 h, 3 lifts / 2 h → Plan rebuilds with rides and lifts on your days, two budgets shown. 3. Home shows the hybrid coach
with two progress bars, one line, the table and "Why?". 4. Log a strength session from Home → strength progress updates,
Plan marks the day done, Progress shows the lifting chart. 5. Connections › Apple Health → Import now → Watch strength
workouts appear once, labelled Apple Health. 6. Fresh install (optional): name → mode → week → … → Home.

## 0.5.1 (build 30) — 25 Oct 2026 — TestFlight, internal testers only — HOTFIX

**Fixes the launch crash of build 27** (black screen, app killed immediately) on phones that already had data from
build 24. Nothing else changes; profile, plan, rides and settings are untouched.

- **Cause**: the Ride dashboard's gauge-layout fitting loop. At launch all five tabs are laid out at once and SwiftUI's
  GeometryReader reports a 0 × 0 size on its first pass for the hidden Ride tab; the dashboard subtracted its padding
  (−28 pt), the loop's square root became NaN, every comparison was false and the loop never ended — the main thread
  hung and iOS's watchdog killed the app before the first screen appeared. A fresh install never showed the Ride tab
  (onboarding comes first), which is why it only hit updated phones.
- **Fix**: degenerate or non-finite sizes return a safe fallback layout at once, both loops are bounded, and the Ride
  tab draws nothing until it has a real size. Regression test with widths −28 … 159, NaN and ∞ must finish in < 0.5 s.
- **Pipeline**: a new launch smoke test runs the **Release** build on the simulator before every archive — fresh
  install (Welcome must appear) and an upgrade from a build-24-shaped store (Home must appear, then all five tabs are
  opened). Any launch crash or hang now fails CI instead of reaching TestFlight. Run 29 reproduced the hang with it.

### Known limitations
Unchanged from 0.5.0 (below).

## 0.5.0 (build 27) — 25 Oct 2026 — TestFlight, internal testers only

Everything below is **simulator-tested** (62 XCTest cases in GitHub Actions, 0 failures — including the 16 shared coach
vector files from the Nokia app, which the Swift coach engine now passes byte for byte). **Nothing new in this build is
real-device-tested** until Rashed runs `BUILD27-TEST.txt`. The board runs firmware 0.5.0; firmware 0.6.0 (prepared, not
flashed) is still needed for everything marked **(needs 0.6.0)**.

### Implemented (Rashed's real-device findings on build 24, items 3–7)
- **Profile is a category menu**: Rider information (name, birth year, optional gender, weight, height, units), Training
  profile (goals, level, sports, weekly limit, training days → the availability editor, training history), Heart rate
  (resting / max / LTHR, zone method % max HR or % LTHR, zones, sources), Power & cycling (FTP with its method, power
  zones, meter status with "power unverified", cadence preference, bike name, wheel circumference), Connections & devices
  (the dashboard), App & device settings (appearance, keep screen on, coach on/off and frequency, background-recording
  notice, privacy + delete, phone-only mode, auto-connect, sync status, firmware, board settings). Every page saves into
  the same store; no saved value is dropped (older `store.json` files load with defaults for the new fields).
- **Plan rebuilt around your availability**: Profile › Training profile › "Training days" (also the calendar icon on
  Plan) sets, per weekday, cycle / lift / other / rest and the preferred duration. The engine never schedules on a rest
  day, puts strength on lift days, rides only on cycling days at the chosen duration, the longest cycling day is the long
  ride, one quality session per week (tempo for beginners, threshold for strength/climbing goals), a recovery spin after
  it. If riding time exceeds the weekly limit the summary shows concrete suggestions (shorten X, skip Y, raise the
  limit) instead of silently cutting sessions.
- **Plan page redesign**: readable day strip (icon + duration + zone bars, "+N" when a day has several activities),
  weekly summary with a time-budget bar (riding / all training / done / budget), separate cards for workouts and for
  rest/recovery days, tap a day to view / edit / move / replace / skip / remove / add. Hand-edited sessions are
  flagged "edited" and never regenerated without confirmation ("Rebuild this week" asks first; completed sessions and
  past days are never touched).
- **Durations** everywhere through one formatter: "1 h 40 min", "45 min", "2 h" — never "1.66667 h".
- **Historical timeline** under the plan: rides and past sessions, newest first, with duration, distance, avg / max HR,
  avg power + NP, cadence, time-in-zone strip, training load (TSS only when NP and FTP both exist — otherwise blank),
  completed / skipped / missed status; tap a ride for the full report with graphs and route. Sparkline trends (duration,
  avg power, avg HR, load) once 5+ points exist. Duplicates across board sync and phone recordings are removed
  (same board ride id, or same recorder within 5 minutes); Apple Health import is not connected and says so.
- **Ride dashboard = the Nokia "Power Focus" design**, ported from `app/src/main/java/.../ui/{Design7,Dashboard}.kt`
  and `core/DashLayout.kt`: a large power gauge on top with zone ticks, target band and the live dot; cadence and heart
  rate gauges tucked below (computed, non-overlapping geometry for every iPhone width and the available height);
  BELOW TGT / ON TARGET / ABOVE TGT / COASTING / NOT TURNING / NO SENSOR / NO HR SOURCE pills; the coach box with the
  shape badge (▲ ✓ ▼) and the lit EASE · ON TARGET · FASTER scale; a combined live graph of power, HR and cadence each
  normalised against its own target band (last 5 minutes); distance, speed, normalized power and lap; START / PAUSE /
  LAP / END and "Start cool-down". No scrolling on the main screen; the route map, sensors and classic tiles are behind
  "DETAILS ›". Header tags: POWER UNVERIFIED (always, until the XDS is validated), FTP ASSUMED, DEMO.
- **Coach engine** (`Shared/CoachCore.swift`): line-by-line port of the Nokia `CoachEngine` v3 — HR is the authority
  when present, power confirms or pre-empts, cadence only when effort is in order; gear intelligence (easier / harder
  gear vs reduce pressure / increase effort); warm-up / main / cool-down phases from ride time (5 min each, cool-down
  on request); smoothing, hold times, hysteresis, spacing and back-off; sensor-loss notices; relative-effort coaching
  when the FTP is only an assumption; sensor-poor mode (cadence + pace only) when no effort sensor is live. The target
  zone is today's planned session (free ride = Z2). Coach on/off and frequency in App settings.
- **Source id 10 (BLE cadence/speed sensor on the board)** is named in live data and history; Connections wording aligned
  with the board's Connections menu (Phone, Wi-Fi, Power meter, Heart rate, Cadence, Speed, Other Bluetooth, Device sync).

### Known limitations
- Nothing in the Nokia source was missing: the dashboard, gauge, coach, graph scaling and layout code were all present
  and ported. Two things are intentionally different: the bundled Rajdhani / IBM Plex Mono fonts are replaced by the
  system rounded / monospaced fonts (no font files are shipped), and the Nokia "Classic" and "Compact" layouts are not
  offered — Power Focus is the only ride layout (the classic tiles remain under Details).
- The XDS power stays labelled **unverified**; the Nokia 60-second "verify power" test is not ported yet.
- Wheel circumference is stored on the phone; the Link v1.2 settings message has no wheel field, so it is entered on the
  board as well (Connections › Speed) until a later protocol revision.
- Coach cues are shown, not spoken (no audio in this build).
- Google and e-mail sign-in still wait for Supabase + Google configuration; board history sync, Wi-Fi setup, profile and
  device settings still need firmware 0.6.0 on the board.
- Dynamic Type: the dashboard keeps its own sizes (it is a cockpit, not text); every other page follows the system size.

## 0.4.0 (build 24) — 25 Oct 2026 — TestFlight, internal testers only

Everything below is **simulator-tested** (43 XCTest cases in GitHub Actions, 0 failures). **Nothing new in this build is
real-device-tested** until Rashed runs `BUILD24-TEST.txt`. Pairing, live data, GPS to the board and watch heart rate were
device-tested in builds 14–21 and are unchanged in code. The board runs firmware 0.5.0; firmware 0.6.0 (prepared, not
flashed) is needed for everything marked **(needs 0.6.0)** — the app checks the board's capability bits and says so.

### Implemented
- **Connections replaces Sensors.** Home shows a Connections card (BikeComputer, power meter, Apple Watch, phone GPS);
  it opens a dashboard with BikeComputer (link, firmware, battery estimate), Phone (Bluetooth, GPS, Internet), Apple
  Watch, Bluetooth sensors via the board (power meter, strap, speed/cadence = not supported yet) and other integrations
  (Apple Health; WHOOP and Garmin listed as not connected). Colours: green connected and working · red "!" only for
  connections you enabled or the ride setup requires · amber connecting / stale / limited · gray optional / off. Every
  row opens status, pairing steps, measurements, reconnect and troubleshooting. Pairing the board: Connect → tap the
  board → type the 6-digit code once.
- **Reconnection without touching the board.** The phone keeps a pending Bluetooth connection open (state restoration,
  `bluetooth-central` background mode, no polling) and attaches as soon as the board advertises. "Connect automatically"
  (Profile › Settings and the BikeComputer page) switches that off locally; the board's own phone-link switch is a
  device setting (needs 0.6.0). The screen-off BLE drop itself was a firmware defect, fixed in 0.6.0 (see
  `firmware/waveshare/docs/FIRMWARE_0.6.0.md`); on 0.5.0 the board still has to be woken.
- **Two-stage onboarding.** Stage A: Continue as guest (name only) · Sign in with Apple · Google / e-mail shown disabled
  with the reason (account service not configured). Stage B, one question per screen, every screen skippable: name ·
  birth year · weight + units · sports and activities · goal · experience and hours · max / resting heart rate and FTP
  (tested value, or "estimate for me" labelled provisional) · devices you own (board, watch, strap, power meter) ·
  Apple Health (save workouts / read workouts / read heart rate explained separately; marked connected only after iOS
  confirms the permission) · summary. Skipped values stay "not set"; nothing is invented.
- **Profile sync (needs 0.6.0).** Ownership: board alone, phone alone, or connected with the phone authoritative. At
  first pairing the app reads the board's profile, lists the differences and asks: use the phone's profile on the board,
  or keep the board's values (copied to the phone). After that every change on the phone (also through sliders and
  text fields) bumps a version and is pushed with acknowledgement and three retries; an older version never overwrites
  a newer one. Ride history, sensor pairings, calibration, Wi-Fi and the phone pairing on the board are never touched.
  Sync status page under Profile › Devices and Connections › BikeComputer.
- **Device settings from the phone (needs 0.6.0).** Brightness, screen timeout, wake gesture, ride layout, wake on
  coach cue, phone link, deep sleep after idle, heart-rate source, board units, diagnostics. Only controls the connected
  firmware reports as supported are shown; each change waits for the board's reply and shows synced / failed.
- **Wi-Fi setup from the phone (needs 0.6.0).** Scan list with signal bars, lock and "saved", password entry (sent once
  over the encrypted link, kept nowhere on the phone), connect progress, states Connected / Connecting / Wrong password /
  Not found / Connected, no internet, Forget, Rescan, "Other network", 2.4 GHz note and the iPhone-hotspot
  "Maximize Compatibility" hint.
- **Home coach redesigned.** One line at the top ("Today: 45-minute endurance ride (Zone 2) to improve aerobic
  fitness."), a compact table (workout, duration, target zone with watts, benefit, structure, status), "Why this
  workout?" in plain words using only data the app has (last ride, this week, goal, level, FTP label — and it says that
  no sleep/HRV/recovery source is connected), and Start / Adjust / Alternative (easier, shorter, off the bike, skip).
- **Ride tab button.** Five tabs kept; the middle one is a raised circular "Ride now" button (turns green while
  recording). Tapping it opens the Ride screen only; recording starts from Start ride there.
- **Layout audit.** Plan week strip: several activities on one day are stacked (first shown + "+N" badge that opens the
  day list; "Add another activity on this day"), cells have a minimum height and scale text instead of overlapping;
  Home coach text wraps (no truncation); Connections rows are two-line with a status badge; tab bar labels scale with
  Dynamic Type; all screens use system grouped backgrounds in light and dark.
- **Profile tab.** Birth year, max / resting / threshold heart rate (entered values replace estimates and are labelled),
  sports picker, FTP entry marked "tested", Devices section → Connections, BikeComputer settings and Wi-Fi, Sync status.
- **Protocol.** `Shared/BCLink.swift` implements Link v1.2 (Wi-Fi 0x60–0x66, profile 0x70–0x73, settings 0x74–0x76,
  INFO tag 07 device id, caps 0x80/0x100/0x200); `LinkV12Tests` reproduces the firmware's byte vectors from
  `firmware/waveshare/docs/BLE_LINK_PROTOCOL.md` exactly.
- **Store.** Schema stays 1; new fields are optional with defaults (tolerant decoding tested against a build-21 file).
  Profiles and rides survive the update.

### Known limitations
- Google and e-mail sign-in remain disabled until Supabase + Google OAuth + Sign in with Apple service id are configured.
- Everything marked (needs 0.6.0) shows "needs firmware 0.6.0" on the current 0.5.0 board; history sync too.
- Board power state (display off / standby / deep sleep) is not reported over the link yet; the app shows link state only.
- Apple Health: permission flow and status are real; saving rides as workouts is prepared but not active in this build.
- Speed/cadence BLE sensors (0x1816) are listed as not supported (firmware).
- WHOOP / Garmin: listed, not connected. Android skeleton unchanged.
- Long locked-screen phone-only rides and background reconnection are untested on devices.

### Testing checklist (short) — see BUILD24-TEST.txt
1. Update; existing profile, plan and rides are intact; Home shows the coach line + table and the Connections card.
2. Delete all data → onboarding: guest with a name only, skip screens, finish; Profile shows "not set" where skipped.
3. Connections: board paired → green; switch Bluetooth off → red "!" on Bluetooth and BikeComputer; back on → reconnects
   without touching the board.
4. Watch toggle off → watch row gray, never red; on → status follows the workout.
5. Plan: add a second activity on a day → stacked cell with "+1"; tap → day list.
6. Ride now button opens Ride; nothing records until Start ride.
7. With firmware 0.6.0 later: sync differences dialog, device settings synced/failed, Wi-Fi scan + connect.

## 0.3.1 (build 21) — 24 Oct 2026 — TestFlight, internal testers only

Everything below is **simulator-tested** (27 XCTest cases in GitHub Actions, 0 failures). **Nothing is real-device-tested**
until Rashed runs `BUILD21-TEST.txt`. The board is on firmware 0.5.0; the phone-link protocol is unchanged, so the
build-17 board tests still apply.

### Implemented
- **Ride-history sync, client side** (`SYNC_PROPOSAL.md`): the app subscribes to the board's Sync characteristic and
  requests finished rides — **only when the board's INFO advertises the RIDE_SYNC capability (bit 0x40)**. Firmware
  0.4.0/0.5.0 do not, so the app shows "not supported by firmware 0.5.0 — sync coming" in Progress and never invents
  rides. Imported board rides are owned by the board, keyed by board id + start time, merged with the phone's live
  mirror of the same ride (board totals win, phone GPS track kept); demo rides are dropped. Conformance vectors for the
  firmware author are in `BCLinkTests` (SYNC_REQ bytes, SYNC_RIDE round trip, SYNC_END).
- **FTP from rides**: best 20-minute (and 60-minute) mean power from a ride's 1 Hz samples (needs power on ≥ 95 % of
  the window). When 95 % of the best 20 min differs ≥ 2 % from the current FTP, a **"Suggested FTP" card** appears on
  Home and in Progress: "95 % of the best 20-minute power (N W) from <date> ride", with Accept / Not now. Nothing
  changes until Accept; an entered (tested) FTP is never replaced automatically. After Accept the label reads
  "estimated from <date> ride". Best 20 / 60 min are shown in each ride's detail.
- **Background phone-only recording**: the recorder now runs on its own 1 Hz timer (not the screen refresh), the
  location background mode keeps GPS flowing with the screen locked, and watch heart rate keeps arriving over the
  existing WatchConnectivity path. If iOS suspends the app, the unobserved seconds are stored as **marked gaps**
  (time stays correct, no values are interpolated) and the ride detail says how many. A local notification
  ("Recording in the background") appears when the app leaves the foreground during a ride; asked once, no new
  entitlements.
- **Apple Watch ride mirror and controls**: the watch shows the phone's ride (state, recorder, time, distance, W with
  zone, rpm, bpm with source) at 1 Hz while reachable, and offers Start / Pause / Resume / End (End asks first). Commands
  go to the phone, which applies the same one-owner rules as its own buttons (board records when connected with live
  data, otherwise the phone), so the wrist can never create a second ride. The HealthKit workout flow is unchanged.
- Store schema stays 1; new fields (`boardId`, `gapSeconds`, `ftpSuggestion`, `ftpFromDate`, sample `gap`) are optional,
  so build-17 data loads unchanged.

### Known limitations
- Board rides recorded while the phone was away still stay on the board: the firmware side of the sync proposal is not
  implemented yet (planned for firmware 0.6.0).
- Google and e-mail sign-in remain disabled until Supabase + Google OAuth are configured (needs Rashed).
- Watch controls need the phone app running (foreground or background); with the phone unreachable the watch says so.
- Background recording depends on iOS keeping the app alive with the location background mode; a long locked-screen
  ride is untested on a real phone.
- Training load / form still "not enough data"; cloud integrations still "not connected"; Android unchanged (skeleton).
- Build number is the GitHub run number (21); version 0.3.1.

## 0.3.0 (build 17) — 24 Oct 2026 — TestFlight, internal testers only

The five-tab app from Prototype v3. Everything below is **simulator-tested** (XCTest in GitHub Actions: Link codec
vectors, plan engine, store persistence and migration, ride ownership, zones). **Nothing in this build is
real-device-tested** until Rashed runs the checklist in `BUILD17-TEST.txt`; build-14 features that were device-tested
(pairing, live data, GPS to board, Watch HR relay) are carried over unchanged in code but must be re-confirmed.

### Implemented
- **Onboarding** (first run): Sign in with Apple or guest → goal → hours, weight, level → connect the BikeComputer or
  continue phone-only. Starting FTP is an assumption from weight × level and is labelled "provisional" everywhere.
- **Home**: today's workout card, Start ride (says which recorder it will use), Coach (rules) note, next days,
  recovery placeholder (no source → says so), device status, FTP label.
- **Plan**: this/next week from the deterministic plan engine (hours and level decide the mix; never over the weekly
  limit), workout detail with power steps from FTP, move / edit / skip, regenerate, strength / mobility / other /
  recovery-day / rest activities.
- **Ride**: three status chips (Recording · Devices · Heart rate), six configurable tiles (power, cadence, HR, speed,
  time, distance, lap, zone, normalized power, board battery ≈ estimate), zone bar, MapKit route from the phone's
  GPS, sensors list, pause / lap / end with confirmation, save / discard sheet.
  - **One recorder per ride, fixed at start**: a connected BikeComputer with live data is the recorder (the phone
    mirrors it and adds GPS); otherwise this phone records (GPS speed/distance, watch HR; no power is ever invented).
    A board that connects mid-ride does not take over; a phone ride cannot start while the board has a ride running.
    "Phone-only mode" (Profile › Settings) forces phone recording even with a board connected.
  - Phone link lost during a board ride → banner; the board keeps recording; nothing is recorded on the phone.
- **Progress**: weekly riding-time chart with the hours limit, FTP card with its label (provisional / entered /
  from rides), ride list, ride detail with interactive Swift Charts graph (power / HR / cadence / speed, touch to read
  values), time in zones, route map, Coach (rules) summary, delete. Rides stored on the BikeComputer while the phone
  was away are **not** shown (note says "sync coming"); nothing is fabricated.
- **Profile**: rider details, FTP entry, power + HR zones, Devices (BikeComputer with the full build-14 Devices
  screen, XDS via board, Apple Watch, strap via board, phone GPS) with LIVE / CLOUD capability pills, cloud
  integrations listed as "not connected", Settings (units, phone-only mode, HR preference, keep screen on), Account
  (guest → Create account; Sign in with Apple; sign out; **delete account and all data on this phone**), About with
  version and the simulator-vs-device note.
- **Persistence**: one `store.json` (schema 1) in Application Support; build-14 per-file data is imported once;
  missing keys take defaults so future builds never drop profile or rides.
- **Offline**: no network calls in this build.
- **Watch app**: unchanged from build 14 (HealthKit cycling workout, 1 Hz heart rate to the phone, no duplicate
  Fitness workouts).
- **Android foundation** (`android/`): Kotlin Link codec with the same conformance vectors as Swift and the firmware,
  minimal Compose app skeleton with the five tabs as empty states, CI workflow building a debug APK. Not a usable
  app yet.

### Known limitations
- Google and e-mail sign-in buttons are disabled ("coming with the sync service"): Supabase + Google configuration
  needed (Rashed). Sign in with Apple only identifies the rider on this phone; nothing is synced anywhere.
- Board ride history is not pulled from the BikeComputer (Sync characteristic not implemented in the app yet).
- The board's own ride totals are the authority; the phone's copy of a board ride is built from the 1 Hz mirror and
  may have gaps if the app was in the background. Avg/NP/kJ on the phone can therefore differ slightly from the
  board's results screen.
- FTP is never estimated from rides yet ("from rides" label exists but no detector runs).
- Training load / form intentionally shows "not enough data yet".
- Cloud integrations (WHOOP, Garmin, Apple Health) are listed but not connected.
- Units setting affects the Ride and results tiles; the Plan and Progress texts stay metric in this build.
- Imperial speed/distance conversions are display-only; stored data is always metric.
- Background recording on the phone depends on iOS keeping the app alive with the location background mode; a long
  phone-only ride with the screen locked is untested.
- Build number is the GitHub run number (17); the version is 0.3.0.

### Testing checklist (short) — see BUILD17-TEST.txt for the step-by-step version
1. Install 0.3.0 (17) from TestFlight; first run shows onboarding; choose guest.
2. Profile → data from onboarding present; set a tested FTP; zones update.
3. Board off: Ride → "Start ride · phone only" → walk 2 min → End → Save; Progress shows the ride with a map.
4. Board on (0.4.0), paired: Ride shows "board ready"; Start → board starts; tiles show XDS power/cadence; End from
   phone → results on both; Save; Progress lists it as "BikeComputer".
5. During a board ride, switch Bluetooth off on the phone for 30 s → banner; back on → values return.
6. Watch workout running → HR tile shows "Apple Watch"; strap paired on the board → HR source "via board".
7. Kill and relaunch the app → profile, plan, rides intact.
8. Profile → Delete account and all data → onboarding again; board remembered state cleared.
