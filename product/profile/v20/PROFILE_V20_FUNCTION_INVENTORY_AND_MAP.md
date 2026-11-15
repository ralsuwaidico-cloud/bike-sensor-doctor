# Profile v2.0 — Function inventory and old-to-new map

**Version:** 0.1 · 15 Nov 2026 · **Status:** Current Draft — Pending Review · read-only audit; **no code changed, built or run**
**Source re-read:** branch `impl/checkpoint-f-ride`, commit `4e2e9dc`, `ios/BikeComputer` — `ProfileScreens.swift`, `ProfileView.swift`, `ProfileSections.swift`, `ProfileQuickMenu.swift`, `ProfileMenuModel.swift`, `ProfileEditors.swift`, `ConnectionsView.swift`, `DeviceSettingsView.swift`, `StrengthCoachViews.swift`, `Watch/CyWatchView.swift`, `Models.swift`. "Works" below means *present in code*; nothing was run. The screenshots mentioned in the owner's brief did not reach the session.
Builds on `../PROFILE_PHASE0_AUDIT_AND_IA.md` (unchanged). **Corrections to Phase 0:** (1) a Cyclift Watch (LILYGO) card with a "Connect to Cyclift Watch" switch *does* exist on the Devices screen — Phase 0 said no row was found; (2) Garmin, WHOOP and Oura exist as hidden "planned" entries behind a release flag that is off.

Sections: **A** Athlete Profile · **B** Training Setup · **C** Performance Settings · **D** Devices & Connections · **E** App Preferences · **F** Data, Help & About.
Shared = the editor is the same code onboarding uses (must not change without authorisation).

## 1. Profile tab (door 1)
| # | Today: function | Where today | Shared | Storage owner | New home | Change |
|---|---|---|---|---|---|---|
| 1 | Name, date of birth, weight (source + date) | Profile › header › Personal | yes | profile | A › Personal details | adds Height editor (**new capability**) |
| 2 | Athlete type (Cycling / Strength / Hybrid) | Type & experience | yes | profile → plan preview | A › Type & experience | label "Endurance" proposed for "Cycling" (decision) |
| 3 | Hybrid balance (priority) | Type & experience | yes | profile → plan preview | A › Hybrid balance | — |
| 4 | Riding level | Type & experience | yes | profile → plan preview | A › Experience | — |
| 5 | Lifting experience | Type & experience **and** Strength programming | yes / no | strength prefs | A › Experience (only editor) | shown read-only in B (ends duplicate) |
| 6 | Goals, main goal | Goals | yes | profile → plan preview | **Plan** (B shows a link) | editor moves to Plan's ownership — **dependency: Plan has no goal editor of its own today** |
| 7 | Training days, session lengths, two-a-day | Your week | yes | profile → plan preview | **Plan** (B › Training schedule link) | same dependency |
| 8 | Equipment preset, supersets | Your week **and** Equipment / programming | yes | equipment, strength prefs | B › Equipment & restrictions; B › Strength preferences | one home each |
| 9 | Equipment owned, custom items, excluded-by-equipment | Equipment (lifting only) | no | equipment → plan preview | B › Equipment & restrictions | — |
| 10 | FTP value and source; "I don't know my FTP"; FTP suggestion note | "FTP" › Power & cycling | no | profile → plan preview | C › Power | row renamed from "FTP" |
| 11 | Power zones (calculated) | Power & cycling | no | calculated | C › Power | — |
| 12 | Power-meter status, "unverified" notice, no-calibration statement | Power & cycling | no | live device state | C › Power (state row) and D › Power meters | — |
| 13 | Cadence low / high | Power & cycling | no | profile | C › Cadence | — |
| 14 | Bike name, wheel circumference | Power & cycling | no | profile (sent to board) | C › Cycling parameters | — |
| 15 | Resting, max, threshold heart rate | Heart rate (cycling only) | no | profile | C › Heart rate | offered to all athlete types |
| 16 | Zone method; heart-rate zones | Heart rate | no | profile / calculated | C › Heart rate | — |
| 17 | Preferred heart-rate source; watch and strap status lines | Heart rate **and** BikeComputer device settings | no | app setting + device setting | C › Measurement sources | one control; board follows (**needs firmware-side decision**) |
| 18 | Recovery speed | Preferences | no | profile → plan preview | B › Recovery preference | — |
| 19 | Coach adjustments (list; on/off) | Preferences **and** Home | no | settings / adaptations | E › Coach (switch); list stays with Coach | ends duplicate |
| 20 | Strength split | Preferences › Hybrid plan editor | no | profile → plan preview | B › Strength preferences | — |
| 21 | Strength programming: strength goal | Preferences › Programming | no | strength prefs | B › Strength preferences | — |
| 22 | Excluded exercises (discomfort), "always use instead", temporarily unavailable | Programming | no | strength prefs | B › Equipment & restrictions | grouped with equipment |
| 23 | Routines; routine per weekday | Preferences **and** Plan / strength screens | no | templates | **Plan** (B › Saved routines link) | Profile editor entry removed; function kept in Plan |
| 24 | My exercises (create, delete) | Preferences **and** strength screens | no | custom exercises | exercise library (B › My exercises link) | link only |
| 25 | Other sports (8 choices) | Preferences › Sports | no | profile.sports (**read by no engine**) | A › My activities | untrue "counts toward weekly load" sentence replaced by "stored only" |
| 26 | Devices & sensors: device cards, Cyclift Watch card, "in use now", legend, diagnostics | Devices & sensors | no | live state | D | — |
| 27 | BikeComputer: stage, status, connect automatically, disconnect / forget / repair, profile sync, device settings & Wi-Fi, connection diagnostics, pairing steps, troubleshooting | Devices › BikeComputer | no | device + settings | D › Cyclift BikeComputer | all kept behind the same rows |
| 28 | BikeComputer device settings: screen timeout, wake gesture, ride layout, wake on cue, phone link, deep sleep, HR source, imperial units, Wi-Fi | Device settings | no | the device | D › BikeComputer › Device settings | HR source and units follow the phone (dup. removed — decision) |
| 29 | Apple Watch: status lines, "Use the Apple Watch", start watch workout, test connection, steps | Devices › Apple Watch | no | settings / live | D › Apple Watch | — |
| 30 | Cyclift Watch (LILYGO): "Connect to Cyclift Watch" switch, state, battery, event log | Devices › Cyclift Watch card | no | settings.cyWatchEnabled | D › Cyclift Watch — shown **Unavailable / future** | **decision:** the existing switch is unverified on hardware; design hides it behind "future device". Capability is not removed from code |
| 31 | Bluetooth sensors: list, add a sensor, detail (status, measures), reconnect, forget | Devices | no | BLE store | D › Heart-rate sensors / Power meters / Other sensors | same page, filtered by kind |
| 32 | This phone: Bluetooth state; location permission, "GPS on now"; internet | Devices › phone rows | no | system | D › This iPhone; F › Permissions | — |
| 33 | Apple Health: use Health, ride export, workout import, optional reads (weight, resting HR, HRV, sleep) | Apple Health | no | settings / Health | D › Apple Health | — |
| 34 | Pause training; saved health answers (review); safety notice | Health & safety (under "App") | review is shared | profile | B › Training pauses & health check | moved out of "App" |
| 35 | Units | Settings | no | settings | E › Units | board copy follows |
| 36 | Appearance (System / Light / Dark) | Settings | no | settings | E › Appearance | six Cyclift themes shown **not available** |
| 37 | Ride notifications (background recording notice) | Settings | no | settings | E › Notifications | renamed "Ride recording notice" |
| 38 | Keep the screen on | Settings › Ride & coach | no | settings | E › Training display | — |
| 39 | Phone records every ride | Settings › Ride & coach | no | settings | D › This iPhone (recording source) | moved to devices — **placement to confirm** |
| 40 | Ride tiles | Ride & coach **and** ride screen | no | tiles | E › Training display | one home; ride screen links |
| 41 | Ride display (night / daylight / auto) | ride screen only | no | settings | E › Training display | gains a home in Profile; ride screen keeps a shortcut |
| 42 | Coach during rides; how much it talks | Ride & coach | no | settings | E › Coach | — |
| 43 | "Your data stays on this iPhone"; export; delete all (with / without Health workouts) | Settings › Your data | no | store | F › Where your data lives; Export; Delete all data | — |
| 44 | Version; privacy policy; terms; contact support; support page | Settings › About | no | — | F › About / Help | one place |
| 45 | "Account: Not needed" | Settings › About | — | — | **removed** — does nothing; the fact is stated in F › Where your data lives | only removal; no capability lost |
| 46 | Setup checklist on Home sends the athlete to the Profile tab | Home | — | — | would open the Profile landing | Home code not changed here |

## 2. Home quick menu (door 2)
| # | Today | Opens | New home |
|---|---|---|---|
| Q1 | Header "View profile" | Profile tab | Profile landing (the only door) |
| Q2 | My profile — read-only facts (name, age, height, weight, type, levels), each opening its editor | fact list | A (summaries on the section page; same editors) |
| Q3 | Goals & training preferences — facts: goals, strength goal, cycling focus, ride/lift days and lengths, sessions per week, balance, supersets, split, recovery, gym equipment, avoided exercises, temporary limits, FTP, HR zones, pointer to devices | fact list | B (and A, C for the facts that belong there); schedule and goals facts link to Plan |
| Q4 | Devices & connections | Devices screen | D |
| Q5 | App settings | Settings page | E and F |
| Q6 | Help & support: How Cyclift works (4 topics), troubleshooting, diagnostics, support page, contact, privacy, terms, version | Help page | F › Help / About |
| Q7 | Close / scrim | — | not needed (no menu) |

## 3. Result
- **Every audited function has a destination.** The one item removed from view is the inert "Account: Not needed" row.
- **Presented differently, not removed:** the Cyclift Watch switch (shown as a future device); the quick menu's read-only fact lists (become section summaries).
- **Moved to another owner (link kept in Profile):** goals, weekly schedule, routines, routine per weekday, my exercises, the list of Coach adjustments.
- **New capabilities the design assumes (not in the app):** height editor; a single permissions view; "Endurance" label; a goal and schedule editor owned by Plan.
- **Duplicates ended (in the design):** lifting experience ×2; equipment preset / supersets ×2; HR source ×2; units ×2; ride tiles ×2; Coach adjustments ×2; legal ×2; diagnostics ×2; version ×3.
