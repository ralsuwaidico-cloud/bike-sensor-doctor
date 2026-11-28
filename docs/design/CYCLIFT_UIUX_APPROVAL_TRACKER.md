# Cyclift — UI/UX approval tracker and application screen inventory

Updated: 28 Nov 2026, 12:45 (Dubai) · Audit requested by the owner 28 Nov 2026, 11:49 · Level 2 (tracker)

## How to read this

- This is an audit only. No design, functionality, calculation, storage or application code was changed to produce it.
- Evidence: the design register (docs/design/CYCLIFT_APPROVED_SCREENS.md), the recorded owner decisions (decisions/), the 15 Nov baseline register, the Lab feature tracker and the app source at commit 22d7cc15.
- UI/UX status and implementation status are separate columns. 'Approved' never means 'built' or 'works'. Nothing here has been verified on a physical iPhone.
- Only the seven agreed statuses are used. A screen that exists and runs in the app but has never been put in front of the owner is recorded as 'Designed but not reviewed'.
- Counting rule for the percentages: approved = 'Approved and locked' + 'Approved with minor refinements'. Every row of the table counts as one, including components of the locked Home that are listed separately because the owner named them.

## Completion overview

| Area | Approved | Identified | Complete | Approved and locked | Approved with minor refinements | Direction approved | Awaiting approval | Under review | Designed but not reviewed | Not designed |
|---|---|---|---|---|---|---|---|---|---|---|
| Home and its associated screens | 17 | 32 | 53% | 16 | 1 | 1 | 1 | 1 | 9 | 3 |
| Onboarding | 8 | 10 | 80% | 6 | 2 | 0 | 2 | 0 | 0 | 0 |
| Plan | 0 | 8 | 0% | 0 | 0 | 5 | 0 | 0 | 3 | 0 |
| Progress | 0 | 12 | 0% | 0 | 0 | 2 | 0 | 0 | 10 | 0 |
| Training Hub | 0 | 8 | 0% | 0 | 0 | 8 | 0 | 0 | 0 | 0 |
| Profile and settings | 0 | 10 | 0% | 0 | 0 | 8 | 0 | 0 | 2 | 0 |
| Overall application UI/UX (inventoried screens) | 25 | 80 | 31% | 22 | 3 | 24 | 3 | 1 | 24 | 3 |

Two judgements behind these figures:

- Area-level approvals given on 12–15 Nov, before the screen-by-screen workflow began (Training Hub v1.4 design baseline, Plan Direction B, Progress compact hero, Profile six-section architecture), are recorded here as 'Direction approved': no screen in those areas has been individually approved and locked, and several built screens differ from their sheets. If the owner treats the Training Hub v1.4 baseline as final, its 8 rows move to approved and the overall figure becomes 33 of 80 (41%).
- Navigation v1.2 rev 1.1 was approved on 15 Nov and kept unchanged by the Home lock, so it is counted as approved; the final Train emblem choice is still open.

## Master table

### Home and its associated screens

| Screen ID | Screen / component | Parent screen | Approved version | UI/UX status | Locked | Implementation status | Remaining UI/UX work |
|---|---|---|---|---|---|---|---|
| APP-01 | Home layout — header, three rings, weekly calendar, Endurance and Strength cards, Sleep row, Coach card, Trends, Key metrics | — | Original Home with the whole-card Coach change; owner 23 Nov 2026 09:40 | Approved and locked | Yes | Working UI in Cyclift Lab (check 55) | None. |
| HOME-A | Profile avatar in the Home header (entry to Profile) | Home | Part of APP-01; avatar-only access decided 14–15 Nov | Approved and locked | Yes | Working UI in Cyclift Lab | None on Home. Its destination is listed under Profile. |
| APP-02 | Consistency Dashboard | Home › Consistency ring | Focused check 61; owner 23 Nov 19:55 | Approved and locked | Yes | Working UI in Cyclift Lab | None. |
| APP-03 | Training Mix Dashboard | Home › Training Mix ring | Focused check 68; owner 24 Nov 18:29 | Approved and locked | Yes | Working UI in Cyclift Lab | None. |
| APP-04 | Recovery Dashboard | Home › Recovery ring | Direction accepted 24 Nov 10:22; three corrections shown in check 66 | Awaiting approval | No | Working UI in Cyclift Lab (check 66) | Your final approval of the three corrections; one small decision on the one-line floating label. |
| HOME-B | Weekly training calendar on Home | Home | Part of APP-01 | Approved and locked | Yes | Working UI in Cyclift Lab | None. |
| APP-05 | Day page (Daily Training Overview) | Home › a calendar day | Focused check 76; owner 25 Nov 19:21 | Approved and locked | Yes | Working UI in Cyclift Lab | None. |
| HOME-C | Weekly overview (older drill-down page) | Consistency Dashboard › View week; also reused by Plan | None | Designed but not reviewed | No | Working UI (existing page) | Never reviewed. It counts some sessions differently from the approved Consistency Dashboard — decide keep, restyle or retire. |
| HOME-D | Planned-session view ('View workout') | Day page; Endurance and Strength pages | None | Designed but not reviewed | No | Working UI (existing) | Not reviewed. |
| HOME-E | Endurance card on Home | Home | Part of APP-01 | Approved and locked | Yes | Working UI in Cyclift Lab | None. (A card for running-based athletes is a functional backlog item.) |
| APP-09 | Endurance Performance | Home › Endurance card | Option C Revision 1.1; owner 28 Nov 01:27 | Approved and locked | Yes | Design mockup only. The older 'Cycling summary' is still the working page | None. |
| HOME-F | Ride record (one recorded ride) | Endurance Performance; Day page | None | Designed but not reviewed | No | Working UI (existing) | Not reviewed. Known: a contradictory Records card and labels broken mid-word. |
| HOME-G | Strength card on Home | Home | Part of APP-01 | Approved and locked | Yes | Working UI in Cyclift Lab | None. |
| APP-10 | Strength Performance | Home › Strength card | Revision 1.1 with nine minor refinements; owner 28 Nov 11:47 | Approved and locked | Yes | Design mockup only. The older 'Strength summary' is still the working page | None. Refinements are drawn in the approved boards. |
| HOME-H | Workout log (one strength record) | Strength Performance; Day page | None | Designed but not reviewed | No | Working UI (existing) | Not reviewed. Known: red trend line and pure-black background do not match the approved pages. |
| HOME-I | Sleep row on Home | Home | Part of APP-01 | Approved and locked | Yes | Working UI in Cyclift Lab. It currently opens the older Recovery page | None on Home. |
| APP-06 | Sleep & Wellness | Home › Sleep row | Direction approved 25 Nov 20:11, subject to ten refinements | Direction approved | No | Design mockup only | Your visual approval of the refined mockups. The 30- and 90-day views, 'More' measures, normalised view and sources panel are described but not drawn. |
| HOME-J | Coach card on Home | Home | Part of APP-01 (the one approved change) | Approved and locked | Yes | Working UI in Cyclift Lab (check 55) | None. |
| COA-01 | Coach page — timeline | Home › Coach card | Sheet G1 (15 Nov) — pending owner review | Designed but not reviewed | No | Working UI, but its structure is not sheet G1 | Review of G1 against the running page. |
| COA-02 | Coach page — conversation | Coach page | Sheet G2 (15 Nov) — pending owner review | Designed but not reviewed | No | Working UI (rules-based replies, labelled as such) | Review. |
| COA-03 | Coach decision sheets (training proposal, FTP suggestion, 'Why') | Coach page | None | Designed but not reviewed | No | Working UI (existing) | Not reviewed. |
| HOME-K | Trends section on Home (Activity and Recovery tabs) | Home | Part of APP-01 (appearance) | Approved and locked | Yes | Working UI in Cyclift Lab | None for the appearance. |
| HOME-L | Trends interactions — tab change, point inspection, information sheet | Home › Trends | None | Designed but not reviewed | No | Working UI (existing) | Not yet captured or reviewed state by state. |
| HOME-M | Key metrics tiles on Home | Home | Part of APP-01; content chosen in APP-08 | Approved and locked | Yes | Working UI in Cyclift Lab | None. |
| APP-08a | Key Metrics hub (16 metrics, four swipeable rows) | Home › Key metrics | Focused check 81; owner 27 Nov 19:22 | Approved and locked | Yes | Working UI in Cyclift Lab (app code 22d7cc15) | None. |
| APP-08b | Choose four for Home | Key Metrics hub | Focused check 81; owner 27 Nov 19:22 | Approved and locked | Yes | Working UI in Cyclift Lab | None. |
| APP-07 | Resting Heart Rate page | Key Metrics hub | Proposal presented 25 Nov | Under review | No | Design mockup only. The older page is the working one | Your visual decision, and whether training advice stays on this page. |
| KM-HRV | HRV page | Key Metrics hub | None (next in the order you set) | Not designed | No | Older page only | Design and review. |
| KM-FTP | FTP page | Key Metrics hub | None | Not designed | No | Older page only | Design and review. |
| KM-OTH | Remaining metric detail pages (group — not yet counted one by one) | Key Metrics hub | None | Not designed | No | Not confirmed page by page | Inventory first. One shared metric-page template could be approved once and applied to all. |
| NAV-01 | Bottom navigation and Train control | All main tabs | Navigation v1.2 rev 1.1 (15 Nov); kept unchanged by the Home lock | Approved with minor refinements | Yes | Working UI (Lab 32, measured) | Final Train emblem choice; confirm the 'no content showing under the dock' correction on a build. |
| HOME-N | Conditional Home states and sheets — set-up banner, health hold, reschedule, swap, recovery guidance, ride duration | Home | None | Designed but not reviewed | No | Exist in the app; not confirmed which appear on the approved Home | Capture each state, then review. |

### Onboarding

| Screen ID | Screen / component | Parent screen | Approved version | UI/UX status | Locked | Implementation status | Remaining UI/UX work |
|---|---|---|---|---|---|---|---|
| ONB-01 | Welcome | First launch | Owner 20 Nov 16:59; locked 17:01 | Approved and locked | Yes | Working UI in Cyclift Lab | None. |
| ONB-02 | About You — personal information (name, date of birth, weight, height, units) | Onboarding 1 of 7 | Commit 9dd5a862; owner 20 Nov 22:00 | Approved and locked | Yes | Working UI in Cyclift Lab | None. |
| ONB-03 | Athletic Roster — sports and activities | Onboarding 2 of 7 | Sheets Z2 / Z3 approved as the visual baseline 20 Nov 23:04 | Awaiting approval | No | Working UI in Cyclift Lab | Your visual verdict on the built screen. Four deviations from the sheets to accept or reject. |
| ONB-03a | Activity library sheet ('Browse all activities') | Athletic Roster | Sheet Z3 | Awaiting approval | No | Working UI in Cyclift Lab | Same verdict. The library groups by sport; the sheet groups by capability. |
| ONB-04 | Goals — goals, main goal, experience level, training-mix summary | Onboarding 3 of 7 | Commit ac046799; owner 21 Nov 20:50 | Approved and locked | Yes | Working UI in Cyclift Lab | None. |
| ONB-05 | Build Your Week — availability, sessions, training preferences | Onboarding 4 of 7 | Calendar layout approved 22 Nov 13:34 (run 39) | Approved with minor refinements | Not recorded as locked | Working UI in Cyclift Lab | Confirm which screenshot the chosen layout refers to; lock. |
| ONB-05a | Equipment sheet | Build Your Week | Presentation approved 22 Nov 14:36 (run 41) | Approved with minor refinements | Not recorded as locked | Working UI in Cyclift Lab | The refined wording, built afterwards, has not been seen by you. |
| ONB-06 | Connect Your Devices — Apple Health, Apple Watch, sensors | Onboarding 5 of 7 | Commit a66577ee; owner 22 Nov 17:19 | Approved and locked | Yes | Working UI in Cyclift Lab | None. |
| ONB-07 | Athlete Evolution — declared experience and stage | Onboarding 6 of 7 | Commit 2402aefa; owner 22 Nov 19:47 | Approved and locked | Yes | Working UI in Cyclift Lab | None. (Stage names are provisional labels; assessment is not activated — backlog.) |
| ONB-08 | Athletic Blueprint — plan preview, approval, completion and hand-over to Home | Onboarding 7 of 7 | Commit d2ebe9f8; owner 23 Nov 00:12 | Approved and locked | Yes | Working UI in Cyclift Lab | None. |

### Plan

| Screen ID | Screen / component | Parent screen | Approved version | UI/UX status | Locked | Implementation status | Remaining UI/UX work |
|---|---|---|---|---|---|---|---|
| PLAN-01 | Weekly Calendar (Plan landing) | Plan tab | Direction B visual foundation (12 Nov); sheet B1 | Direction approved | No | Working UI in Lab; compared with B1 only | Full review. Your build feedback: larger and more colourful than B1. |
| PLAN-02 | Recurring Plan | Plan tab | Direction B; sheet B2 | Direction approved | No | Working UI in Lab; not compared | Full review. |
| PLAN-03 | Add a goal sheet | Plan › goal card | Direction B; sheet B3 | Direction approved | No | Working UI in Lab; not compared | Review. |
| PLAN-04 | Goal set-up and programme preview | Add a goal | Direction B; sheet B4 | Direction approved | No | Working UI in Lab; not compared | Review. |
| PLAN-05 | Coach planning proposal | Plan › Coach row | Direction B; sheet B5 | Direction approved | No | Not confirmed as built | Review; align with the Coach page. |
| PLAN-06 | Session editing — move to any day, skip, remove, edit scope | Plan › a session | Wireframe W5 only | Designed but not reviewed | No | Partly existing | Visual design and review. |
| PLAN-07 | Session states — missed with linked replacement, conflicts, linked sessions | Plan › Weekly Calendar | Wireframes W2, W3, W10 only | Designed but not reviewed | No | Partly existing | Visual design and review. |
| PLAN-08 | Secondary Plan screens | Plan | Wireframe W6 only | Designed but not reviewed | No | Partly existing | Inventory, visual design and review. |

### Progress

| Screen ID | Screen / component | Parent screen | Approved version | UI/UX status | Locked | Implementation status | Remaining UI/UX work |
|---|---|---|---|---|---|---|---|
| PROG-01 | Progress landing — compact hero and Evolution track | Progress tab | Compact hero approved 13 Nov (sheets PH1–PH5) | Direction approved | No | Working UI in Lab | Full review of the built screen. |
| PROG-02 | Landing sections (hybrid, endurance, strength, consistency) | Progress landing | Variant A direction and landing order (13 Nov) | Direction approved | No | Working UI in Lab on real records (Lab 39) | Review after the duplication decision. |
| PROG-03 | Endurance detail | Progress | Detail sheets only | Designed but not reviewed | No | Working UI | Duplicates approved Endurance Performance. |
| PROG-04 | Strength detail | Progress | Detail sheets only | Designed but not reviewed | No | Working UI | Duplicates approved Strength Performance. |
| PROG-05 | Consistency detail | Progress | Detail sheets only | Designed but not reviewed | No | Working UI | Duplicates the approved Consistency Dashboard. |
| PROG-06 | Zones page | Progress | None | Designed but not reviewed | No | Working UI | Overlaps the intensity section of Endurance Performance. |
| PROG-07 | Analytics page | Progress | None | Designed but not reviewed | No | Working UI | Review. |
| PROG-08 | History list | Progress | None | Designed but not reviewed | No | Working UI | Overlaps the recordings lists on the two Performance pages. |
| PROG-09 | Ride detail | Progress › History | None | Designed but not reviewed | No | Working UI | Same purpose as the ride record. |
| PROG-10 | Session detail | Progress › History | None | Designed but not reviewed | No | Working UI | Same purpose as the workout log. |
| PROG-11 | Evolution details and timeline | Progress › Evolution track | Sheets only | Designed but not reviewed | No | Details page exists; timeline absent | Stage criteria are not approved (backlog); the screen can still be designed. |
| PROG-12 | Progress menu sheet | Progress | None | Designed but not reviewed | No | Working UI | Review. |

### Training Hub

| Screen ID | Screen / component | Parent screen | Approved version | UI/UX status | Locked | Implementation status | Remaining UI/UX work |
|---|---|---|---|---|---|---|---|
| TRN-01 | Compact Train panel | Train control | v1.4 design baseline (14 Nov); sheets 06b, 06c | Direction approved | No | Working UI in Lab (Lab 32) | Screen-by-screen confirmation. |
| TRN-02 | Full Training Hub | Train panel | v1.4; sheets 06b, 06c | Direction approved | No | Working UI in Lab | Confirmation. |
| TRN-03 | Strength preparation | Training Hub | v1.4; sheets 01a, G3 | Direction approved | No | Working UI in Lab (Lab 33) | Decide on the extra 'More' button; confirm. |
| TRN-04 | Strength recorder — sets, supersets, corrections | Training Hub | v1.4; sheets 04a–04c | Direction approved | No | Working UI; a superset has not been seen on screen | Visual comparison; superset state. |
| TRN-05 | Cycling recorder — focus, map, sensors, pause, finish | Training Hub | v1.4; sheets 05a, 05b | Direction approved | No | Lab shows a labelled simulation; no map in Lab | Visual comparison. |
| TRN-06 | Finish and save | Recorder | v1.4; sheets 06e, 06f | Direction approved | No | Working, but the layout is not the approved one | Bring to the sheet, then confirm. |
| TRN-07 | Post-session review (Intensity, Performance, Effort) | Finish | v1.4; sheet 06a | Direction approved | No | Working, but the layout is not the approved one | Bring to the sheet, then confirm. |
| TRN-08 | Recovery activity interface | Training Hub | v1.4; sheet 06d (concept) | Direction approved | No | Not built | Design to final and review. |

### Profile and settings

| Screen ID | Screen / component | Parent screen | Approved version | UI/UX status | Locked | Implementation status | Remaining UI/UX work |
|---|---|---|---|---|---|---|---|
| PRO-01 | Profile landing (six sections) | Home › avatar | Six-section architecture approved 15 Nov; visual sheet P02 pending review | Direction approved | No | Working UI in Lab | Visual review. |
| PRO-02 | Athlete profile | Profile | Sheet P03 — pending review | Direction approved | No | Older inner page | Visual review. |
| PRO-03 | Training setup | Profile | Sheet P04 — pending review | Direction approved | No | Older inner page | Visual review. |
| PRO-04 | Performance settings (FTP, heart-rate zones) | Profile | Sheet P05 — pending review | Direction approved | No | Older inner page | Visual review. |
| PRO-05 | Devices and connections | Profile | Sheet P06 — pending review | Direction approved | No | Older inner page | Visual review. |
| PRO-06 | App preferences, themes and accessibility | Profile | Sheets P07, P10 — pending review | Direction approved | No | Older inner page; theme switching works | Visual review. |
| PRO-07 | Data, help and about | Profile | Sheet P08 — pending review | Direction approved | No | Older inner page | Visual review. |
| PRO-08 | Editors (personal, type and experience, goals, week, equipment, preferences, strength programming, FTP, heart rate) | Profile sections | Sheets P09a, P09b — pending review | Direction approved | No | Older editors | Visual review; reuse the approved onboarding components where the content is the same. |
| PRO-09 | Health check | Profile; Home health-hold sheet | None | Designed but not reviewed | No | Working UI (existing) | Not reviewed. It is not part of the approved onboarding. |
| PRO-10 | Pause training | Profile; Home hold sheet | None | Designed but not reviewed | No | Working UI (existing) | Not reviewed. |

## Onboarding — the requested journey against the approved structure

The approved onboarding is Welcome plus seven pages (design phase closed by the owner 23 Nov 2026, 00:12). It was checked against the register, not against the app.

| Requested item | Where it is in the approved structure | Standing |
|---|---|---|
| Personal information | ONB-02 About You | Approved and locked |
| Athlete type | No separate screen in the approved structure. The Athletic Roster (ONB-03) and the main goal (ONB-04) carry it. | Not a missing screen — the earlier 'athlete type' page was superseded by the roster on 15 Nov |
| Athletic Roster and activity selection | ONB-03 and its activity library sheet | Awaiting approval of the built screen |
| Experience level | Asked inside Goals (ONB-04) for cycling and lifting; shown as 'Declared experience' on Athlete Evolution (ONB-07) | Approved and locked. Experience questions for other sports are not asked — backlog; adding them changes locked pages |
| Goals | ONB-04 Goals | Approved and locked |
| Training preferences and weekly availability | ONB-05 Build Your Week | Approved; not recorded as locked |
| Equipment | Equipment sheet inside ONB-05, shown only for relevant activities | Approved; refined wording not seen |
| Health and device connections | ONB-06 Connect Your Devices (Apple Health, Apple Watch, sensors; WHOOP and Garmin 'Coming soon') | Approved and locked |
| Training configuration | No separate screen. Covered by ONB-05 (week) and ONB-07 (stage) | — |
| Plan generation, preview and approval | ONB-08 Athletic Blueprint | Approved and locked |
| Health check | NOT in the approved onboarding. A health check exists in the app, reached from Profile and from Home's health-hold sheet (PRO-09); it has never been reviewed | Owner decision needed: leave it where it is, or add it to onboarding (which would reopen a closed phase) |
| Completion and transition to Home | ONB-08 confirmation state, then Home | Approved and locked |
| Conditional paths | An athlete whose sports cannot be planned yet skips ONB-06 and ONB-07 and finishes without a plan (decided 21 Nov). Date-of-birth sheet, activity library sheet, equipment sheet | Covered by the approved screens; no route yet for such an athlete to set up a plan later — backlog |

## Plan and Progress — duplication with approved Home destinations

| Existing Plan or Progress view | Approved page with the same purpose |
|---|---|
| Progress › Endurance detail, Zones | Endurance Performance (APP-09) |
| Progress › Strength detail | Strength Performance (APP-10) |
| Progress › Consistency detail | Consistency Dashboard (APP-02) |
| Progress › History, Ride detail, Session detail | Recordings lists on the two Performance pages; ride record; workout log |
| Plan › day and week drill-downs | Plan already reuses Home's Day page (APP-05) and the older Weekly overview |

## Screens not yet inventoried

- Apple Watch app screens.
- Cyclift Watch / BikeComputer device screens (hardware workstream, separately gated).
- The remaining Key Metrics detail pages, one by one (grouped above as one row).
- System permission prompts, error, offline and save-failure states across the app.
- Export, import and delete-all-data screens inside Profile.
- Arabic right-to-left versions, and the five other themes, of every approved screen.
- Older production screens the redesign replaces (they stay in production until release is authorised).

## Remaining UI/UX review checklist and recommended sequence

### 1 · Close Home

- [ ] Recovery Dashboard (APP-04) — a decision only; the evidence (check 66) is already presented.
- [ ] Sleep row → Sleep & Wellness (APP-06) — approve the refined mockups. A capture of today's row and destination is running (focused check 88).
- [ ] Coach card → Coach page, conversation and decision sheets (COA-01 to 03).
- [ ] Key metric pages — decide Resting HR (APP-07), then approve ONE shared metric-page template for HRV, FTP and the rest instead of reviewing each page separately.
- [ ] Nested records in one sitting — ride record, workout log, planned-session view, Weekly overview.
- [ ] Trends interactions, conditional Home states, and the Train emblem.

### 2 · Close Onboarding

- [ ] Athletic Roster (ONB-03 and its library sheet) — visual verdict and the four deviations.
- [ ] Build Your Week and Equipment sheet (ONB-05) — see the refined wording, confirm the reference screenshot, lock.
- [ ] One decision: does the health check stay outside onboarding?

### 3 · Plan

- [ ] Weekly Calendar and Recurring Plan against sheets B1 and B2, then goal sheets, then editing and missed-session states (which need visual design first).

### 4 · Progress

- [ ] First a single decision on what Progress is for now that Endurance Performance, Strength Performance and the Consistency Dashboard are approved — otherwise up to seven Progress screens would be reviewed only to duplicate approved pages. Then the landing, Evolution, and whatever remains.

### 5 · Remaining screens

- [ ] Training Hub — confirm the v1.4 baseline screen by screen (finish/save and review are the two that differ from their sheets).
- [ ] Profile — visual review of sheets P02–P10.
- [ ] Apple Watch and the items not yet inventoried.

### 6 · Master UI/UX reference

- [ ] One consolidated reference of every approved board, built from the design register.

**Recommended next screen: Home › Sleep row → Sleep & Wellness (APP-06)**, with the Recovery Dashboard (APP-04) decision taken in the same sitting.

## References to approved boards and versions

| Area | Where |
|---|---|
| Onboarding 1–8 | docs/design/CYCLIFT_APPROVED_SCREENS.md, screens 1–8; assets S01–S08; sheets product/onboarding/v34/sheets (Z1–Z6) |
| Home, Consistency, Training Mix, Recovery, Day page | Approved Screens Report, screens 9–13 (focused checks 55, 61, 68, 66, 76) |
| Sleep & Wellness, Resting HR | Approved Screens Report, screens 14–15 (mockups) |
| Key Metrics hub and Choose four | Approved Screens Report, screen 16; assets H08_r3_sim_* (check 81) |
| Endurance Performance | Screen 17; assets H09_ap_1 to 5; docs/design/proposals/endurance-performance-v1/Cyclift_Endurance_Performance_Approved_UI_Reference.pdf |
| Strength Performance | Screen 18; assets H10_ap_1 to 5; docs/design/proposals/strength-performance-v1/Cyclift_Strength_Performance_Approved_UI_Reference.pdf; Revision 1.1 PDF and mapping workbook preserved beside it |
| Navigation | product/profile/nav-v12/final (sheets F1–F9); decision 15 Nov |
| Training Hub v1.4 | product/train/v14/sheets (01a–08); decision 14 Nov |
| Plan | product/plan/visual-v05-B and visual-v06-B (B1–B6); wireframes W1–W10; specification v0.6 |
| Progress | product/progress/design-v23-compact (PH1–PH5) and design-v23 (PG1–PG6); decision 13 Nov |
| Profile | product/profile/v20/sheets (P01–P10); decision 15 Nov |
| Coach | product/coach/design-review-v2/mockups (G1, G2) — pending review |

Functional requirements are kept apart from this tracker in `release/FUNCTIONAL_DEVELOPMENT_BACKLOG.md`.
