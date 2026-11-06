# UX Checkpoint C — correction pass: navigation map, change map, deferred items

Owner reviews of build 169 (6 Nov 2026): Home cards must reach meaningful pages; the avatar opens a Profile Quick Menu.
Commits: `1f9ca28` (pages, layout, checklist, menu), `bcc2989` (validation fixes 1 and 2 + targeted regressions).
Every page reads stored data only; nothing here writes the plan, preferences, settings or schemas.

## 1. Navigation map

### Home (the dashboard)
| Tap | Opens | Notes |
|---|---|---|
| Date (top bar) | — | label only (not a control) |
| Avatar (top bar) | **Profile Quick Menu** (floating panel) | tap again / outside / Close / VoiceOver escape / tab change closes it |
| Weekly ring card | **Weekly overview** (this week) | counts from the ledger, W12 window |
| Cycling card | **Cycling summary** | recorded rides only |
| Strength card | **Strength summary** | logged sessions only |
| Week strip · day with one planned session | its **prescription** (strength logger screen / ride workout detail — the screens Plan opens) | never changes the plan |
| Week strip · day with one recorded session | **Ride details** / **Strength log details** | |
| Week strip · two or more sessions, rest day, before-plan day, nothing planned | **Day page** (each session individually, or the explanation) | |
| "Plan ›" | Plan tab | the label names the destination |
| Coach card | the existing proposal / adjustment / FTP / check-in sheet | unchanged; opening never changes the plan |
| Recovery card | **Recovery page** | latest enabled Health readings with source and date, or the empty state → Connections |
| Goal card | **Goal details** | what it tracks, measured so far, next step |
| Today reminder | **Training Hub** | as the centre button |
| Getting started rows | Plan tab ("Open Plan") / Profile tab ("Open Connections") | only while a required step is open |
| Dock centre button | **Training Hub** | unchanged from Checkpoint C build 169 |

### Weekly overview
| Tap | Opens |
|---|---|
| ‹ / › | previous / next week (next is limited to the coming week) |
| Session row (planned, not recorded) | its prescription (sheet) |
| Session row (recorded) | Ride details / Strength log details |
| Row action (Start / Resume / Results / Move to today) | the Training Hub's existing routes |
| "Day" / "Rest" / "Before plan" chip | Day page |

### Day page
Session rows as above; empty days explain themselves: before the plan · rest (today and later: from Your week; past: "No session was planned for this day.") · nothing planned · no plan yet.

### Cycling summary
Period (This week / 4 weeks / All) · tiles (rides, time, distance, avg power / HR / cadence — only from rides that measured them) · Next planned ride → prescription (+ Start) · Recent rides → Ride details.

### Strength summary
Period · tiles (sessions, recorded time) · Next planned workout → prescription (+ Start), with its A1/A2 lines · Recent workouts → Strength log details; "n exercises" expands the logged sets, reps, weights and stored superset letters.

### Profile Quick Menu
| Row | Opens |
|---|---|
| Header (initials, stored name, athlete type, "View profile") | Profile tab |
| My profile | **My profile** facts: name, age, height (read-only), weight (with source), athlete type, riding level, lifting experience → each editable fact opens the existing editor (Personal / Type & experience) |
| Goals & training preferences | **Goals & preferences** facts: goals, strength goal, cycling focus; ride/lift days, lengths, sessions per week, balance, **supersets (stored value)**, split, experience, recovery; equipment, avoided exercises, FTP, HR zones → each opens its existing editor (plan-affecting edits end in the before/after preview) |
| Devices & connections | **Devices & sensors** (existing device manager: paired / connected / receiving / problem / not set up) |
| App settings | **Settings** (existing: units, appearance, ride notifications, ride & coach, your data, about) |
| Help & support | **Help & support** (how Cyclift works, how plans are made, the numbers, devices, troubleshooting → Diagnostics, Support page, Contact support when configured, Privacy, Terms, version) |

## 2. File-level change map (commit 1f9ca28)

| File | Change |
|---|---|
| `BikeComputer/HomeSummaries.swift` (new, Foundation) | Weekly overview, Day detail, Cycling and Strength summaries, Getting-started items — read from plan, ledger, rides, logs, availability |
| `BikeComputer/HomeDetailPages.swift` (new) | `HomeRoute`; `HomeItemRow`; Weekly overview, Day, Cycling summary, Strength summary pages; dynamic checklist view |
| `BikeComputer/ProfileMenuModel.swift` (new, Foundation) | menu header, My-profile and Preferences facts, row summaries; `ProfileText` moved here unchanged |
| `BikeComputer/ProfileQuickMenu.swift` (new) | the floating menu, facts page (read-only rows → existing editors), Help & support page |
| `BikeComputer/HomeView.swift` | Home on a path-based stack; transparent top bar with date + avatar (B1); menu overlay, dismissal; route destinations |
| `BikeComputer/HomeDashboardView.swift` | cards open their own routes; calendar tap rule; old simple overview removed; hub bottom clearance |
| `BikeComputer/HomeFirstWeek.swift` | removed (replaced by the dynamic checklist) |
| `BikeComputer/DesignSystem/CyTheme.swift` | `dockClearance` constant (B2) |
| `BikeComputer/DesignSystem/CyCards.swift` | metric-tile title/subtitle wrap instead of truncating (B3) |
| `BikeComputer/ProfileScreens.swift` | equipment proposal moved to a shared `Store.proposeEquipmentEdit` (no behaviour change) |
| `BikeComputer/ProfileSections.swift` | `ProfileText` moved out (no change) |
| `BikeComputerTests/HomeSummariesTests.swift`, `ProfileMenuTests.swift` (new) | model tests (harness + Xcode) |
| `BikeComputerUITests/HomeNavigationTests.swift` (new) | simulator navigation, layout and menu tests |
| `tools/coach-harness/test.sh` | new Foundation files and tests in the Linux list |

`bcc2989`: `HomeSummaries.swift` (recorded vs planned subtitles; past days without the current setup), tests.

## 3. B4 — the "0 of 1" vs "six sessions" difference
Root cause: the old Getting-started line counted **every** training session stored in the plan (this week's remaining one plus next week's five) and called it "this week". The ring counted this week from the effective start — correct. Fix: the checklist uses the ring's window and names next week separately. Ledger unchanged. Test: `HomeSummariesTests.testSetupChecklistCountsLikeTheRingAndDisappearsWhenRequiredStepsAreDone`.

## 4. Deferred (not in Checkpoint C)
- **C2 (Profile redesign, proposed):** a height editor; a full Profile layout review; photo avatar (no photo support exists); profile-level account features.
- **D (Progress analytics):** weekly trend charts beyond the 8-week mini series; FTP development; power-zone and training-load analysis; personal records, estimated 1RM trends, muscle-volume analysis; goal trend pages.
- **E (Recovery):** recovery history storage, check-ins, sleep history; any readiness or recovery score.
- **F (Horizon):** the ride screen map / focus modes.
- **Known limits kept:** rescheduled days have no stored marker (needs a schema change); the hub/dock state is not mirrored on the Watch; swipe-to-dismiss is not offered on the menu (it would conflict with scrolling a tall menu at large text); VoiceOver checked by labels and the audit, not on a real iPhone.
