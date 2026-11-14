# Profile — Phase 0 audit and proposed information architecture

Status: **Current Draft — pending owner review.** · Version 0.1 · 14 Nov 2026 · Level 3
Read-only audit. No code, data, onboarding, firmware or branch was changed. No screens were designed.
Source read: release branch `ios/checkpoint-f-ride`, commit `4e2e9dc`. Findings come from reading the code, not from running the app.

## 1. What Profile is today

There are **two separate doors** into profile content, with different structures and different names.

### Door 1 — the Profile tab (fifth dock item)

| Group | Row | Opens | Contains |
|---|---|---|---|
| Header | Initials, name, "Hybrid · ride regular · lift beginner" | Personal | Name, date of birth, weight (with source and date) |
| Training & goals | Type & experience | Editor | Cycling / Strength / Hybrid, balance, riding level, lifting experience |
| | Goals | Editor | Goal cards, main goal |
| Week & preferences | Your week | Editor | Training days, session lengths, two-a-day, equipment preset, supersets |
| | Equipment *(lifting only)* | Page | Equipment owned |
| | FTP *(cycling only)* | "Power & cycling" page | FTP and source, power zones, power-meter status, cadence range, bike name, wheel size |
| | Heart rate *(cycling only)* | Page | Resting, max, threshold, zone method, zones, preferred source |
| | Preferences | Page | Recovery speed, Coach adjustments, strength split, strength programming, routines, routine per weekday, my exercises, other sports |
| Devices & data | Devices & sensors | Screen | BikeComputer, Apple Watch, sensors, diagnostics |
| | Apple Health | Page | Use Health, ride export, workout import, optional reads (weight, resting HR, HRV, sleep) |
| App | Health & safety | Page | Pause training, saved health answers, safety notice |
| | Settings | Page | Units, appearance, ride notifications, Ride & coach, your data (export, delete), about, legal |

### Door 2 — the Profile quick menu (avatar on Home)

| Row | Opens |
|---|---|
| Header → "View profile" | The Profile tab |
| My profile | A read-only fact list (name, age, height, weight, athlete type, levels); each fact opens the editor |
| Goals & training preferences | A read-only fact list (goals, structure, equipment) |
| Devices & connections | The same Devices screen |
| App settings | The same Settings page |
| Help & support | How Cyclift works, diagnostics, support links, legal, version |

### What works well and should be kept

- One implementation of each editor, shared with onboarding.
- Every change that affects the plan goes through preview → approve → undo.
- Values carry their source and date ("Apple Health · 3 Nov", "Entered by you"); unknown stays unknown (FTP is never guessed).
- Real device states only; nothing shown as connected that is not.
- Export and delete-all exist, with a clear statement that data stays on the phone.

## 2. Duplicates and unnecessary settings

| # | Finding |
|---|---|
| D1 | **Two structures for one thing.** The tab and the quick menu name the same destinations differently: "Personal" / "My profile"; "Devices & sensors" / "Devices & connections"; "Settings" / "App settings"; "Preferences" / "Goals & training preferences" |
| D2 | **Help & support is only in the quick menu** — it cannot be reached from the Profile tab |
| D3 | Privacy policy and Terms appear in both Settings and Help. Diagnostics appears in both Devices and Help. The version appears in three places |
| D4 | Lifting experience can be changed in two places (Type & experience; Strength programming) |
| D5 | Equipment preset and supersets are in "Your week" and again under Equipment |
| D6 | Heart-rate source is set in Profile › Heart rate and again in BikeComputer device settings |
| D7 | Units are set in Settings and again as "Imperial units on the board" |
| D8 | Ride tiles are in Settings › Ride & coach and in the ride screen's own settings; ride display (night / daylight) is only in the ride screen |
| D9 | Coach adjustments are reachable from Profile › Preferences and from Home |
| D10 | Routines, routine per weekday and "My exercises" sit under Profile › Preferences and are also reachable from Plan and from the strength screens. They are training content, not profile settings |
| D11 | The row is called "FTP" but opens "Power & cycling", which also holds cadence, bike and wheel size |
| D12 | "Account: Not needed" is a row that does nothing |
| D13 | A stored "ride layout" setting is kept only so old saved settings still load; it has no effect |
| D14 | Three ways to record age exist in the data (date of birth, birth year, age); only date of birth is edited |

## 3. Things that are wrong or misleading today

| # | Finding |
|---|---|
| W1 | **"Other sports count toward your weekly load so the plan does not overload the bike days."** The sports list is not read by any planning or Coach code. The sentence is not true as the app stands |
| W2 | Heart rate is offered only to athletes whose type includes cycling; a strength-only athlete has no row for it |
| W3 | Height is stored and shown but cannot be edited ("no editor in this version") |
| W4 | "Health & safety" (pausing training) is filed under "App" |
| W5 | "Ride notifications" is the only notification control and its scope is unclear from the label |

## 4. Missing athlete-profile capabilities

| Capability | Today |
|---|---|
| Choosing "my activities" as a first-class input | Only a buried, unused "Other sports" list of eight. Training Hub v1.4 assumes this input exists |
| Height editor | None |
| Photo or avatar | Initials only |
| A view of permissions (location, Bluetooth, Apple Health, notifications) | Scattered across device pages |
| Theme choice | System / Light / Dark only. The six Cyclift themes exist in the UI Lab, not in the app |
| Backup or restore | None. There are no accounts and no cloud copy; data lives only on the phone. Export exists; import does not |
| Notification preferences | One toggle |
| LILYGO watch link | A setting exists in the data; no Profile row was found for it |
| Coach preferences in one place | Split between Settings › Ride & coach (talk during rides) and Preferences › Coach adjustments (automatic adjustments) |

None of these is proposed for building here; they are gaps to decide on.

## 5. Outdated interface and navigation

- **Two visual languages.** The Profile root uses Cyclift's own rows; almost every page behind it is a standard grey iOS settings form with long footers.
- Rows carry coloured icon tiles, values and chevrons at once; the root shows up to eleven rows in four groups.
- Editors are onboarding screens reused inside Profile, each with its own Save button, while other pages save instantly — two saving behaviours.
- The navigation title is hidden on the root and shown inline everywhere else.
- Technical wording reaches the athlete: "Strap via BikeComputer", "caps", "LTHR", "pairs on the board".

## 6. Data ownership and synchronisation

| Data | Owner | Synchronised with | Notes |
|---|---|---|---|
| Athlete profile, preferences, settings | iPhone only | — | No account, no cloud. A version number increases on change |
| Shared athlete settings (name, FTP, weight, birth year, heart rate, hours, experience, goal, units) | iPhone, once confirmed per device | BikeComputer | The phone becomes the authority only after the athlete confirms; before that, differences are shown and nothing is written |
| BikeComputer device settings (screen, wake, sleep, Wi-Fi, its own units and HR source) | The device | Read and written from the phone | Needs firmware 0.6.0 |
| Weight, resting HR, HRV, sleep | Apple Health when a read is switched on; otherwise the athlete | — | The newer of own entry and Health wins; source and date kept |
| Workouts | iPhone | Apple Health (export once at Save; optional import) | Existing approved rule |
| Heart-rate source choice | iPhone setting **and** a device setting | — | Duplicate (D6) |
| Plan-affecting values (type, goals, week, equipment, split, recovery, FTP) | iPhone | Plan | Always through preview → approve → undo |

### Connections to the rest of the app

| Area | What Profile supplies or shares |
|---|---|
| Onboarding | **The same editor code.** Changing a Profile editor changes onboarding. Onboarding must not be modified without separate authorisation, so this is a hard constraint on any Profile redesign |
| Plan | Type, goals, week, equipment, split and recovery feed the plan through the change preview |
| Train | Equipment, routines, own exercises, avoided exercises; "my activities" is needed and missing |
| Progress | FTP, zones, weight (for W/kg), athlete type |
| Devices | Profile sync, sensors, HR source, phone-only recording |
| Coach | Recovery speed, automatic adjustments, talk during rides, training pause, saved health answers |
| Home | The quick menu; the setup checklist sends the athlete to the Profile tab |

Automated checks that exist for this area: profile menu facts, onboarding draft, and the delete-all-data journey.

## 7. Proposed information architecture

Principle: **Profile is who the athlete is, how they want Cyclift to behave, and what is connected. It shows no charts, scores, schedules or history.**
One structure, reached from both doors with the same names. Every setting has exactly one home.

```
PROFILE
│
├─ Identity header ........ name · initials or photo · athlete type
│
├─ 1  Athlete ............. Personal: name, date of birth, height, weight
│                           Athlete type and balance · experience levels
│                           My activities
│
├─ 2  Performance ......... Power: FTP and source, power zones
│     baselines             Heart rate: resting, max, threshold, zones
│                           Cadence range
│
├─ 3  Training setup ...... Goals
│                           Week, session lengths      ┐ one home each —
│                           Equipment                  │ in Profile or in Plan
│                           Strength split, programming│ (decision 1)
│                           Recovery speed · training pause
│
├─ 4  Devices & ........... BikeComputer (settings, Wi-Fi, profile sync)
│     connections           Apple Watch · sensors · Apple Health
│                           Bike: name, wheel size
│                           Heart-rate source · phone records every ride
│
├─ 5  Preferences ......... Units · appearance
│                           Notifications
│                           Ride screen: keep on, tiles, display
│                           Coach: talk during rides, automatic adjustments
│
├─ 6  Privacy & data ...... Where data lives · permissions
│                           Export · delete
│
└─ 7  Help & about ........ How Cyclift works · support · diagnostics
                            Privacy policy · terms · version
```

### Where each current item would go

| Today | Proposed home | Change |
|---|---|---|
| Personal (name, DOB, weight) | 1 Athlete | Adds height |
| Type & experience | 1 Athlete | Lifting experience edited here only (ends D4) |
| Other sports | 1 Athlete › My activities | Becomes the input Train expects; the untrue sentence goes (W1) |
| "FTP" / Power & cycling | 2 Performance baselines | Renamed; bike and wheel move to Devices (D11) |
| Heart rate | 2 Performance baselines | For every athlete type (W2); source choice moves to Devices |
| Goals | 3 Training setup | — |
| Your week · Equipment · Strength split · Strength programming | 3 Training setup, or Plan | One home each (D5) — decision 1 |
| Routines · routine per weekday · my exercises | **Leave Profile** — Plan and Train | Ends D10 |
| Recovery speed · Health & safety (pause) | 3 Training setup | Out of "App" (W4) |
| Coach adjustments | 5 Preferences › Coach (the on/off); the list itself stays with Coach on Home | Ends D9 |
| Devices & sensors · Apple Health | 4 Devices & connections | One name |
| HR source (two places) · units (two places) | 4 Devices · 5 Preferences | One control each; the device follows the phone (D6, D7) — needs a decision on the device settings |
| Ride & coach | 5 Preferences | Ride display joins the tiles (D8) |
| Your data | 6 Privacy & data | Adds a permissions overview |
| About · legal · Help & support · diagnostics | 7 Help & about | Reachable from the tab (D2, D3) |
| "Account: Not needed" · unused ride-layout setting | Removed from view | D12, D13 |

The quick menu on Home would list the same seven destinations, or a shorter set of them, under the same names.

## 8. Decisions needed before any design

| # | Decision | Options |
|---|---|---|
| 1 | Where do week, equipment, split and strength programming live? The project instructions place training frequency, preferred days, routines and equipment under **Plan** | (a) Plan is the single home and Profile links to it · (b) Profile keeps them and Plan links back · (c) stay in both |
| 2 | Keep the Home quick menu? | Keep as a shortcut to the same structure · remove it and use the tab only |
| 3 | The editors are shared with onboarding | Redesign Profile around the existing editors (onboarding untouched) · or authorise onboarding to change with them |
| 4 | "My activities" | Add as a Profile input now · leave until Training Hub work begins |
| 5 | Theme choice | Keep System / Light / Dark · plan for the six themes |
| 6 | Backup, restore or accounts | Out of scope for Profile · include as a gap to design |
| 7 | Duplicated device settings (units, HR source) | Phone is the single control · keep both |
| 8 | Photo or avatar | Initials only · allow a photo |
| 9 | Seven sections, or fewer | As proposed · merge Performance baselines into Athlete, and Privacy into Help (five sections) |

## 9. What this audit did not do

It did not run the app, test any screen, check a physical device, or read every device page line by line.
Counts and labels come from the code as written at commit `4e2e9dc`.
