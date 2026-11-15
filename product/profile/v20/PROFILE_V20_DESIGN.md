# Profile v2.0 — Information architecture and visual design

**Version:** 0.1 · 15 Nov 2026
**Status:** Information architecture — **Approved** (owner brief, 15 Nov 2026). Visual design — **Pending Review**. **Implementation: NOT AUTHORISED, not started.**
Designed only. Nothing was implemented, compiled, run on a simulator or a device. **ILLUSTRATIVE DESIGN — NOT IMPLEMENTED.**
Preserved unchanged: `../PROFILE_PHASE0_AUDIT_AND_IA.md`, `../PROFILE_AND_NAVIGATION_V1_DESIGN.md` (five-section proposal — its section list is replaced by this six-section architecture; its sheets remain as history), Navigation v1.2 (Current Approved — Visual Design Baseline; shown here unchanged).
Companion: `PROFILE_V20_FUNCTION_INVENTORY_AND_MAP.md` (complete old-to-new map). Diagram source: `profile_navigation.mmd`.

## 1. Purpose and ownership
Profile is one destination for who the athlete is and how Cyclift is configured. It is reached **only** from the avatar at the top right of Home. Home stays the selected tab; back returns to Home at its previous position.
| Section of the app | Owns |
|---|---|
| Profile | Who the athlete is; how Cyclift is configured |
| Plan | Goals, schedules, programmed workouts, routines |
| Train | Starting, recording, completing activities |
| Progress | Development, performance evidence, history |
| Home | Overview and entry points |
Profile may open another section's function but holds no second editor and no duplicate state.

## 2. Visual language
Open surface — no cards on Profile pages; hairline dividers only between rows; one large page title (32 pt) with an optional one-line purpose; rows 60 pt minimum (landing rows 74 pt) with a 16.5 pt title and a 13.5 pt one-line summary taken from stored values; six line icons, on the landing page only; primary text colour for every control (no coloured tiles); 24 pt side margins; existing theme tokens only. All touch targets ≥ 44 pt. Content ends above the Navigation v1.2 scrolling inset (128 / 110 pt).
Row vocabulary (one meaning each): chevron = opens a Profile page · outlined tag **Plan / Train** + chevron = opens that section · switch = saves at once · value without chevron = read-only fact · **Not available** tag = a stated limit · arrow-out = leaves the app · state mark + word = device state.

## 3. Screen-by-screen functional specification
"→" is what a tap opens. Plan-affecting = Save → preview → approve → undo (existing app behaviour).

### P · Profile landing
Back → Home. Identity: initials, name, athlete type and balance (not tappable; edited in A). Six rows → A, B, C, D, E, F, each with a live one-line summary.

### A · Athlete Profile
| Row | → | Behaviour |
|---|---|---|
| Personal details | page: name, date of birth, height, weight, each with source and date | typed values; Save when changed. **Height editor is new** |
| My activities | page: eight activities as chips | instant. Text states "stored only — does not change your plan or Coach guidance today" |
| Athlete type | Type & experience page | plan-affecting |
| Experience | same page: riding and lifting experience | plan-affecting; the only place lifting experience is edited |
| Hybrid balance | same page | plan-affecting; shown only for Hybrid |

### B · Training Setup
| Row | → | Owner |
|---|---|---|
| Equipment & restrictions | page: equipment owned; avoided exercises; always-use-instead; temporarily unavailable | Profile · plan-affecting |
| Strength preferences | page: split; strength goal; supersets; lifting experience shown read-only | Profile · plan-affecting |
| Recovery preference | Recovery & pauses page | Profile · plan-affecting |
| Training pauses & health check | same page: pause training; review saved health answers | Profile |
| Goals | **Plan** goals | Plan |
| Training schedule | **Plan** weekly calendar / recurring plan | Plan |
| Saved routines | **Plan** routines and routine-per-weekday | Plan |
| My exercises | exercise library | Train / library |

### C · Performance Settings (all athlete types)
| Row | → | Behaviour |
|---|---|---|
| Heart rate | resting, maximum, threshold with source; zone method; five calculated zones | Edit → typed values; zones never typed |
| Power | FTP with source and date; "I don't know my FTP"; power-meter state; calculated power zones | plan-affecting; unknown stays unknown; "Tested" only after a recorded test with verified power |
| Cadence | low / high | typed |
| Cycling parameters | bike name; wheel circumference | typed |
| Measurement sources | preferred heart-rate source | single control; the BikeComputer's own copy would follow it |

### D · Devices & Connections
Rows: Apple Health · Apple Watch · Cyclift BikeComputer (Waveshare) · Cyclift Watch (LILYGO) · Heart-rate sensors · Power meters · Other sensors · This iPhone · Connection diagnostics.
Six states, each a distinct mark plus a word: **Receiving** (measurements arriving now) · **Connected** (reachable, nothing arriving) · **Paired** (remembered, not connected) · **Disconnected** (link lost) · **Unavailable** (unsupported, or Bluetooth / permission off) · **Not configured**.
BikeComputer → status, connect automatically, profile sync, device settings & Wi-Fi, diagnostics, reconnect, repair, forget — the existing screens sit behind these rows. Sensors → paired list, add a sensor, detail (connection, measures, reconnect, forget). Apple Health → use, ride export, workout import, optional reads. This iPhone → Bluetooth, location / GPS, "phone records every ride". **Cyclift Watch is shown Unavailable — a future device.** No capability is invented; Cyclift never writes to a power meter's control point.

### E · App Preferences
| Row | → | Truthfulness |
|---|---|---|
| Appearance | System / Light / Dark | the six Cyclift themes are listed as **Not available** (designed, not in the app) |
| Language | English | Arabic **Not available** |
| Units | Metric / Imperial | one setting; the BikeComputer follows |
| Notifications | Ride recording notice | other notifications **Not available** |
| Coach | during rides on/off; how much it talks; let Coach suggest adjustments; → current adjustments in Coach | rules-based; never changes the plan without approval |
| Training display | keep screen on; ride tiles; ride display | — |
| Accessibility | information only: follows iPhone text size, contrast and motion | no in-app switches exist |

### F · Data, Help & About
Where your data lives (only on this iPhone; **Cloud backup — Not available; Restore or import — Not available**; what loss means) · Export my data (one file; cannot be imported back) · Permissions (Bluetooth, location, Apple Health, notifications — current state; → iPhone Settings) · Delete all data (protected: separate confirmation stating consequences, export offered first, the app's two existing delete options, cancel) · How Cyclift works · Diagnostics · Contact support · Privacy policy · Terms of use · Version.

## 4. Editing and save behaviour (one rule set)
1. Switches and single choices save at once.
2. Typed values: Edit → Save appears only when something changed → Cancel asks before discarding.
3. Plan-affecting changes: preview → approve → undo. Unchanged from the app.
4. Tagged rows open the owning section; back returns to Profile.
5. No dead ends: every page has a back path; nothing is presented as a sheet on top of another sheet.

## 5. Accessibility, themes, sizes
Six themes share one layout (sheet P10). Small iPhone: pages scroll; last row clears the dock. Largest text: rows grow and wrap; nothing truncated. High Contrast: dividers and states use line and shape. VoiceOver: each row reads "title, summary, [state], [opens Plan]"; "Not available" rows are read as dimmed, not as buttons. Arabic: content mirrors, the dock keeps the Train ball on the left (Navigation v1.2); Arabic text is illustrative — the app has no Arabic.

## 6. Current Profile versus Profile v2.0
| | Current app | Profile v2.0 |
|---|---|---|
| Doors | Profile tab **and** a five-option quick menu, with different names | one door: Home avatar → landing |
| Structure | four groups, up to eleven rows; a second structure in the menu | six sections, 5–10 rows each |
| Look | Cyclift rows at the root; grey iOS settings forms behind | one open-surface language throughout |
| Duplicated settings | nine found (lifting experience, equipment / supersets, HR source, units, ride tiles, Coach adjustments, legal, diagnostics, version) | one home each |
| Plan-owned items | goals, week, routines edited inside Profile | opened in Plan |
| Heart rate | cycling athletes only | everyone |
| Help | quick menu only | in section F |
| Saving | two behaviours, depending on the page | one rule set |
| Unsupported things | not mentioned | stated as Not available (themes, Arabic, cloud backup, restore, other notifications) |
| Untrue statement | "Other sports count toward your weekly load" | replaced by "stored only" |

## 7. Unresolved dependencies and decisions
1. **Plan must own goal and schedule editing.** Today those editors live in Profile and are the onboarding screens reused. Until Plan has its own, the B links have no destination — the existing editors must stay reachable.
2. **Shared onboarding editors.** Personal, type & experience, goals, week and health check are shared code. The one-rule save behaviour and any new field (height) touch that code; onboarding is not authorised to change.
3. **Cyclift Watch.** The brief says "future, not a working connection"; the app contains an unverified link with a switch on the Devices screen. Decision: hide the switch (as drawn), or keep it visibly marked experimental.
4. **"Endurance" versus "Cycling"** for the first athlete type — label only, or a wider meaning.
5. **BikeComputer duplicates** (heart-rate source, units): making the board follow the phone needs a device-settings decision; no protocol change is proposed here.
6. **My activities** is not used by any engine; Training Hub v1.4 expects it as an input.
7. **"Phone records every ride"** — placed under Devices › This iPhone; confirm.
8. **Six themes, Arabic, cloud backup, restore, further notifications, a permissions view, a height editor** — none exists; each needs its own approval to build.
9. **Home quick-menu retirement** is an approved design direction (decision of 15 Nov); the app is unchanged. Home's setup checklist points at the Profile tab today.
10. Navigation v1.2 dependencies stand: numbered routes and hidden pages (Profile is page 4 today), the two open test failures, physical-device checks.
11. Screenshots named in the brief were not received.

## 8. Quality gate — self-check from the drawings
| Check | Result |
|---|---|
| Every button has a purpose and destination | Met in the specification and map; B's Plan links depend on item 1 above |
| All audited functions have a destination | Met — see the inventory (one inert row removed) |
| Six sections are distinct | Met |
| No dead ends | Met in the design |
| Plan-owned functions not duplicated | Met in the design |
| Nothing unsupported looks operational | Met — Not available tags; Cyclift Watch Unavailable |
| One design language | Met |
| Small devices usable | Drawn; pages scroll — not checked on a device |
| Text does not overlap controls | Checked on every sheet after rendering; two-line wraps at the largest text size |
| Dock does not obscure content | Met at end of scroll; long pages pass behind the dock while scrolling (B, F, small iPhone) |
| Navigation v1.2 geometry respected | Met — dock drawn from the approved geometry, unchanged |

## 9. Sheets (`sheets/`)
P01 navigation context · P02 landing · P03 Athlete Profile · P04 Training Setup · P05 Performance Settings · P06 Devices & Connections · P07 App Preferences · P08 Data, Help & About · P09a editing behaviour · P09b button map · P10 themes and accessibility.
