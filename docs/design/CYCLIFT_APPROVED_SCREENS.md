# Cyclift — Approved Screens Register

Last updated: 22 Nov 2026, 18:10 (Dubai) · Screens recorded: 7

This is the cumulative record of every UI/UX decision the owner has approved. The latest explicitly approved decision for a screen is the source of truth. Older designs, provisional sketches, newer unapproved implementations and screenshots that merely passed a check never replace it. An earlier decision is never altered: a revision is added to the screen's history and the earlier one is kept as superseded.

The five statuses below are separate facts and are never treated as interchangeable: **Approved design · Implemented in code · Compiled · Simulator-verified · Physically verified on iPhone.**

The visual book is `CYCLIFT_APPROVED_SCREENS.pdf` in this folder; images are in `assets/`.

## Approved product direction

**Cyclift is a universal multisport athlete platform** (owner, 21 Nov 2026 — `decisions/2026-11-21_universal-multisport-product-direction.md`). Every catalogue activity is selectable and any can be the primary sport; goals follow the selected sports; every athlete completes onboarding, with a plan where planning exists and profile-only otherwise; nothing is fabricated and no cycling or strength programme is assigned silently.

Five things are always distinguished, and a sport being selectable never means the rest exists:

| Sport / discipline | Selectable in the UI | Profile and goal storage | Workout planning | Recording | AI Coach |
|---|---|---|---|---|---|
| Road cycling | Yes | Yes | Yes — existing rules-based planner | Yes — cycling recorder | No — rules-based Coach only |
| Indoor, mountain, gravel, commuting cycling | Yes | Yes | As general cycling only | As a cycling ride | No |
| Gym strength | Yes | Yes | Yes — existing rules-based planner | Yes — strength recorder | No — rules-based Coach only |
| Free weights, machines | Yes | Yes | As gym training only | As gym training | No |
| Bodyweight, calisthenics | Yes | Yes | No | No | No |
| Running (road, trail, treadmill) | Yes | Yes | No | No | No |
| Swimming (pool, open water) | Yes | Yes | No | No | No |
| Walking, hiking | Yes | Yes | No | No | No |
| Mobility, stretching, recovery | Yes | Yes | No | No | No |

The goal categories for sports without a planner are PROVISIONAL until the owner reviews them.

## Cross-screen integration requirements

Decided by the owner; requirements, not implemented features. Each is taken up when its screen is reached in the sequential review.

| ID | Screen | Decided | Requirement | State |
|---|---|---|---|---|
| INT-01 | Home | 21 Nov 2026, 20:50 | Home's training categories and icons reflect the athlete's actual sports. A runner must not see Cycling as their main Endurance card. | NOT IMPLEMENTED — for the Home review |
| INT-02 | Train | 21 Nov 2026, 20:50 | Train's primary shortcuts are sport-aware. Other activities stay accessible, without presenting cycling as every athlete's default. | NOT IMPLEMENTED — for the Training Hub review |
| INT-03 | Plan | 21 Nov 2026, 20:50 | Plan's 'Add a goal' flow respects the athlete's roster, with truthful handling when personalized planning is not yet available. | NOT IMPLEMENTED — for the Plan review |
| INT-05 | Blueprint | 21 Nov 2026, 22:22 | The Blueprint shows the athlete's selected week, including sessions that are not yet prescribed. | NOT IMPLEMENTED — for the Blueprint review |
| INT-06 | Home and Plan | 21 Nov 2026, 22:22 | Home and Plan must not lose or misrepresent the athlete's selected week. | NOT IMPLEMENTED — for the Home and Plan reviews |
| INT-07 | Goals | 21 Nov 2026, 22:22 | The Goals summary distinguishes a provisional planner mix from the athlete's confirmed schedule. | NOT IMPLEMENTED — needs the owner's authorization to touch approved Screen 4 |
| INT-08 | Icons (all screens) | 21 Nov 2026, 22:22 | Distinctive mobility, yoga and recovery icons — a later visual refinement. Until then the existing sport icon system is reused. | LATER REFINEMENT |
| EQ-01 | Equipment catalogue — strength | 22 Nov 2026, 14:36 | Barbell, dumbbells, kettlebell, bench, cable machine, weight machines (grouped), resistance bands, pull-up bar, trap bar: used by the existing strength planner to choose exercises. Squat rack, dip bars, gymnastic rings, weighted vest: stored only. | IMPLEMENTED — planner support only for the nine items it already knew |
| EQ-02 | Equipment catalogue — cycling, running, swimming, mobility and recovery | 22 Nov 2026, 14:36 | Provisional, incomplete lists for recording what an athlete has. They change no generated training and are not exercise-planning support. | PROVISIONAL — STORAGE ONLY; lists to be reviewed |
| EQ-03 | Equipment catalogue — individual machines | 22 Nov 2026, 14:36 | Individual machine types (leg press and others) to be representable later, alongside the grouped 'Weight machines' item, which is kept for compatibility. | NOT IMPLEMENTED — structure prepared, no individual types listed |
| INT-09 | Blueprint | 22 Nov 2026, 17:19 | The Blueprint contains obsolete FTP and Plan changes links pointing back to Screen 6, which no longer holds either. To be corrected during the Blueprint review: FTP belongs in Performance Settings; Coach plan-change preferences belong in Profile › App Preferences › Coach. The Blueprint is not to be changed before that review. | OPEN — for the Blueprint review |
| INT-04 | Goals (all screens) | 21 Nov 2026, 20:50 | Existing working goal names and planner mappings are retained. Goals are not renamed solely for cosmetic reasons. | IN FORCE — current behaviour |

## Summary

| # | ID | Screen | Approved design | Implemented in code | Compiled | Simulator-verified | Physically verified on iPhone |
|---|---|---|---|---|---|---|---|
| 1 | ONB-01 | Welcome | YES | YES | YES | YES — with limits | NO |
| 2 | ONB-02 | About You | YES | YES | YES | YES — visual and functional | NO |
| 3 | ONB-03 | Athletic Roster | YES | YES — selection only | YES | FUNCTION: PARTLY. VISUAL: NOT YET | NO |
| 4 | ONB-04 | Goals | YES | YES | YES | YES — visual and functional | NO |
| 5 | ONB-05 | Build Your Week | DIRECTION ONLY | YES | YES | FUNCTIONAL YES (Lab, Obsidian, iPhone 15 Pro) — VISUAL PENDING | FUNCTIONAL YES (Lab, Obsidian, iPhone 15 Pro) — VISUAL PENDING | FUNCTIONAL YES (Lab, Obsidian, iPhone 15 Pro) — VISUAL PENDING | YES — functional (Lab, Obsidian, iPhone 15 Pro) | NO |
| 6 | ONB-06 | Connect Your Devices | YES | YES | YES | YES — Cyclift Lab, visual and functional (final state: check 45, below). Main app: previous commit only | YES — visual and functional, Cyclift Lab (Obsidian, iPhone 15 Pro) | YES for the previous commit a02fc5e5 (same rows, earlier subtitles; Plan changes still on the page) | NO |
| 7 | ONB-07 | Athlete Evolution | DIRECTION ONLY | YES — awaiting review | PENDING | PENDING | NO |

---

## Screen 1 — Welcome (ONB-01)

- **Navigation location:** Onboarding · first screen, shown before page 1 (About you). Shown once to a new athlete.
- **Approval date:** 20 Nov 2026, 16:59 (visual design and final wording); locked 17:01
- **Approval status:** APPROVED AND LOCKED — do not modify without the owner's approval
- **Original design reference and source:** No earlier design sheet existed for a welcome screen. The canonical design is the owner's written "Screen 1 final decision" (20 Nov 2026) as shown in the simulator screenshot he approved, with the final wording he then set.
- **Implementation commit:** Screen and interaction 08b4bfbf · hero image 7da39754 · final wording 58cec7b5 (branch ios/lab). Not in any TestFlight build.

### Exact approved wording

- **Headline:** Your evolution starts here.
- **Supporting text:** Your goals. Your training. A better you, every day.
- **Circular control:** Hold to begin
- **Helper:** Hold for 3 seconds

### Approved layout, visual elements and interactions

- Black-hole / orbital hero in the upper-middle of the screen: a still image made by the drawing routine of the approved Progress design sheets (baseline form, one image per theme). Static.
- Order, top to bottom: hero · headline · supporting text · circular hold control. Centred, generous spacing.
- Press and hold the circular control for three seconds; a progress ring fills around it; the control responds subtly to touch; releasing early resets the ring; a tap does nothing.
- Subtle haptics: light when the hold begins, success when it completes.
- On completion the welcome screen dissolves (fade with a slight scale and blur), then About you appears.
- Accessible alternative: VoiceOver / Switch Control activation starts onboarding without the sustained hold.
- No Cyclift icon, no app-name heading, no technical legend, no explanatory paragraph.

### Mandatory functionality and dependencies

- Completing the hold must do what the earlier "Get started" button did: the athlete continues without an account (guest state set) and onboarding page 1 opens. Dependency: the onboarding entry in OnboardingV34.swift.
- Lab controls (badge, Theme, Scenario, Restore) are not part of this screen and must not appear in the main app.

### Explicitly rejected alternatives

- The earlier welcome: Cyclift icon and name, the "Seven short pages…" paragraph, the three-mark legend (Declared by you / Coach's proposal / Measured evidence), the "About two minutes…" line, and a tap "Get started" button.
- The flat Progress placeholder as the finished hero (allowed only as a fallback if an image is missing).
- Flashy, cinematic or game-like transitions; continuous animation is optional and not required.

### Status

| Stage | State | Evidence |
|---|---|---|
| Approved design | YES | Owner, 20 Nov 2026 16:59; locked 17:01. |
| Implemented in code | YES | Commits above. |
| Compiled | YES | Fast check 24 (run 44740474661) built the Lab app at commit c67e1883. |
| Simulator-verified | YES — with limits | iPhone 15 Pro simulator, Obsidian. Fast check 24: the four approved strings exact; tap and a 1-second hold do nothing; ring reported empty after early release; a finger drifting about 10 pt still completes; About you opens; seven pages run to an approved plan. Main app (iOS run 307, commit 3b326a3d, earlier wording, a different simulator size): no Lab strip, holding starts onboarding. |
| Physically verified on iPhone | NO | Nothing on this screen has been checked on a real iPhone. |

- **Visual verification:** Owner approved the simulator screenshot (fast check 23) and set the final wording; the final-wording screenshot (fast check 24) is the image in this book. Obsidian only.
- **Functional verification:** Simulator only, as listed under Simulator-verified.

### Remaining work or limitations

- Real iPhone: VoiceOver / Switch Control activation, the haptics, and how the dissolve looks and feels.
- Other five themes and the largest text size have no screenshot with the hero image.
- Main-app evidence predates the final wording (the wording change itself was verified in Lab).
- Observation from fast check 25, cause not proven: a hold begun the instant the app launched did not open page 1; with a two-second wait it did. To be checked on a real iPhone.
- Open choices left to the owner: richer hero form; subtle hero motion.

### Images

- `assets/S01_welcome_approved_sim_c67e1883.png` — APPROVED DESIGN — as implemented. iPhone 15 Pro simulator, Obsidian, commit c67e1883 (fast check 24). The yellow badge and Theme / Scenario / Restore controls are Cyclift Lab controls, not part of the screen.

### Decision history

| When | Decision | State |
|---|---|---|
| 20 Nov 2026, 15:12 | Direction approved: black-hole hero, three-second hold, dissolve. Wording then: "Start your journey to a better lifestyle" / "See where you fit in the athletic world, and build a routine around your life." / "Hold to start". | SUPERSEDED (wording only) |
| 20 Nov 2026, 15:28 | Hero must be the original black-hole artwork, not the flat placeholder; static image acceptable. | IN FORCE |
| 20 Nov 2026, 16:59 | Visual design approved with the final wording recorded above. | IN FORCE |
| 20 Nov 2026, 17:01 | Approved and locked as the canonical Screen 1. | IN FORCE |

---

## Screen 2 — About You (ONB-02)

- **Navigation location:** Onboarding · page 1 of 7, directly after Welcome. The same measurements are editable later in Profile › Personal details.
- **Approval date:** 20 Nov 2026, 17:09 (design); revised 18:24; implementation approved exactly as shown 22:00 (02_about_you_revision.png, commit 9dd5a862)
- **Approval status:** APPROVED AND LOCKED — visually approved and functionally verified on the iPhone 15 Pro simulator. No further visual changes without the owner's approval
- **Original design reference and source:** Canonical design: the implementation screenshots the owner approved on 20 Nov 2026 at 22:00 (board 02_about_you_revision.png, iPhone 15 Pro simulator, Obsidian, commit 9dd5a862). Origin: onboarding v3.3 design sheet Y1, page 1 (15 Nov 2026), with the owner's modifications of 17:09 and 18:24.
- **Implementation commit:** 891d80aa (18:24 revision) on top of 848f015f (height, date sheet, BMI rule); checked at 9dd5a862 (branch ios/lab). Not in any TestFlight build.

### Exact approved wording

- **Page title:** About you
- **Fields:** First name · Date of birth · Weight · Height
- **Units selector:** Units: Metric ▾ (choices: Metric, Imperial)
- **Button:** Continue
- **Removed:** Every "optional" label; the line "Only your name is needed. Nothing is estimated from blanks — a missing weight stays unknown."; redundant technical descriptions.

### Approved layout, visual elements and interactions

- Keep the clean, minimal v3.3 layout: large editable first name, simple Date of birth, Weight and Height rows, minimal typography and separators, clear Continue button, existing step navigation.
- MODIFICATION — a fourth row, Height (not on the v3.3 sheet).
- MODIFICATION — units: the full-width Metric / Imperial control is replaced by a compact, discreet native-style selector near the Weight and Height rows, presented as "Units: Metric ▾"; tapping it offers Metric or Imperial. Changing units converts the displayed values without changing the underlying measurements.
- MODIFICATION — date of birth: the compact date-entry sheet with direct day, month and year entry, Cancel and Done; no full-screen scrolling wheel.
- MODIFICATION — the bottom explanatory paragraph and all "optional" labels are removed.
- When information is missing or invalid, the page gives a clear indication of what must be corrected.

### Mandatory functionality and dependencies

- All four fields are mandatory for a new athlete: first name, date of birth, weight, height. Continue is disabled until all four hold valid values.
- First name not blank. Date of birth valid and not in the future. Weight and height positive and within validated ranges. Nothing is filled in automatically and no assumed values are used.
- The four values are kept in the authoritative athlete model and persist after reopening; Back and Continue preserve what was entered; Metric / Imperial conversion is accurate.
- BMI = weight in kilograms ÷ (height in metres)², only from actual valid measurements; descriptive only — not body-fat, never a basis for automatic training-load decisions.
- Existing athletes upgrading from an older version: no record is erased and no unsafe migration is forced because height was missing. Existing data is handled separately from the new-athlete requirement.
- Measurements stay editable later through Profile.

### Explicitly rejected alternatives

- Build 6's large boxed input cards.
- The full-screen scrolling date-of-birth wheel.
- The full-width Metric / Imperial segmented control (unnecessarily large).
- Optional date of birth, weight or height for a new athlete (superseded 18:24).
- Estimating or silently filling missing measurements.

### Status

| Stage | State | Evidence |
|---|---|---|
| Approved design | YES | Owner: design 17:09, requirements 18:24, implementation as shown 22:00 (20 Nov 2026). |
| Implemented in code | YES | Commit 891d80aa. BMI is calculated but not displayed on any screen. |
| Compiled | YES | Fast check 27 (run 44754061376) built the Lab app at commit 9dd5a862. |
| Simulator-verified | YES — visual and functional | Owner approved the screenshots at 22:00. iPhone 15 Pro simulator, Obsidian, fast check 27 (run 44754061376): Continue disabled on an empty page and with one, two or three of the four fields; the page names what is missing; an impossible height (17 cm) is named and blocks Continue; all four valid values enable it; no 'optional' label and no old paragraph; date typed as day/month/year with no wheel; 31 April, 29 February 1999 and a 2090 birthday each rejected with their reason, Cancel stores nothing, 29 February 2000 accepted and shown; the units menu offers Metric and Imperial and is under 200 pt wide; Imperial shows 154 lb and 5 ft 9 in, Metric shows the unchanged 70 and 175 again; Back and Continue keep the answers; all four present and the page complete after closing and reopening; the seven-page journey still reaches an approved plan. Lab app only. |
| Physically verified on iPhone | NO | Nothing on this screen has been checked on a real iPhone. |

- **Visual verification:** APPROVED by the owner on 20 Nov 2026, 22:00, exactly as shown in 02_about_you_revision.png (commit 9dd5a862). Obsidian, iPhone 15 Pro simulator only.
- **Functional verification:** VERIFIED on the iPhone 15 Pro simulator (Lab app): fast check 27, as listed. Logic tests (19): BMI arithmetic, no BMI without two valid measurements, the four-field rule and its wording, weight and height limits in both unit systems, leap years, future dates, older records without a height still readable and not rejected.

### Remaining work or limitations

- OUTSTANDING — redesigned main app: this screen has not been run there since the change (the main-app check was updated to enter the new required fields but not run).
- OUTSTANDING — accessibility: largest text sizes, VoiceOver labels and order, High Contrast and the other four themes are unchecked for this screen.
- OUTSTANDING — physical iPhone: nothing on this screen has been checked on a real device (keyboard, date sheet, units menu).
- OUTSTANDING — regression: the full Lab run and two other updated checks have not been run since the change.
- Where BMI should be shown — it is calculated but appears nowhere; owner decision needed.
- Limits in the approved implementation, for the record: height 120–230 cm; age 13–100; weight 30–200 kg.
- Profile › Personal details still uses the date wheel (left for the Profile review); its new Height row has not been seen on the simulator.
- Open observation: a hold on Welcome begun the instant the app launched did not open this page (cause not proven; see Screen 1).

### Images

- `assets/S02_approved_about_sim_9dd5a862.png` — APPROVED DESIGN — as implemented. All four fields complete, Metric. iPhone 15 Pro simulator, Obsidian, commit 9dd5a862 (fast check 27). The yellow badge and Theme / Scenario / Restore controls are Cyclift Lab controls, not part of the screen.
- `assets/S02_approved_about-empty_sim_9dd5a862.png` — APPROVED DESIGN. Empty page: Continue disabled, the line names what is missing.
- `assets/S02_approved_dob-sheet_sim_9dd5a862.png` — APPROVED DESIGN. Date of birth typed as day, month and year.
- `assets/S02_approved_units-menu_sim_9dd5a862.png` — APPROVED DESIGN. The compact units menu open.
- `assets/S02_approved_about-imperial_sim_9dd5a862.png` — APPROVED DESIGN. Imperial: the same measurements shown in pounds and feet / inches.
- `assets/S02_about_you_reference_v33_Y1_page1.png` — ORIGIN ONLY — NOT THE CANONICAL DESIGN. Onboarding v3.3 sheet Y1, page 1, from which the approved screen was developed.

### Decision history

| When | Decision | State |
|---|---|---|
| 20 Nov 2026, 17:09 | Approved: the v3.3 reference layout with height, the compact date-of-birth entry, unit handling and the BMI rule. First name mandatory; date of birth, weight and height optional initially. | SUPERSEDED IN PART (optional fields) |
| 20 Nov 2026, 18:24 | Revised and approved: all four fields mandatory with Continue disabled until valid and a clear indication of what to correct; compact "Units: Metric ▾" selector; "optional" labels and the bottom paragraph removed; date sheet preserved; existing athletes not forced through a migration. | IN FORCE |
| 20 Nov 2026, 19:05 | Record only (no new decision): the 18:24 revision was implemented and passed its simulator check; visual verdict pending. | NOTE |
| 20 Nov 2026, 22:00 | Approved exactly as shown in 02_about_you_revision.png, commit 9dd5a862: visually approved and functionally verified on the iPhone 15 Pro simulator. All four fields stay mandatory; compact units selector, direct date entry, validation and persistence preserved. No further visual changes without the owner's approval. | IN FORCE |

---

## Screen 3 — Athletic Roster (ONB-03)

- **Navigation location:** Onboarding · page 2 of 7, after About You. Opens the activity library as a sheet ("Browse all activities").
- **Approval date:** 20 Nov 2026, 23:04 (visual baseline Z2 / Z3; multisport product requirement)
- **Approval status:** APPROVED DESIGN AND REQUIREMENTS — implemented; owner's visual verification pending. NOT functionally complete
- **Original design reference and source:** Onboarding v3.4 design sheets Z2 (the page) and Z3 (the activity library), selected as the page 2 baseline on 15 Nov 2026 and approved as the Screen 3 visual baseline on 20 Nov 2026. The sheets are illustrative drawings; they predate the multisport requirement, so their example activities and capability groupings are not binding.
- **Implementation commit:** 43027d27 (catalogue, selection, identity, storage, Z2 / Z3 presentation), support sentence shortened in 1a414ccb; checked at 39a398f1 (branch ios/lab). Not in any TestFlight build.

### Exact approved wording

- **Page title:** What do you train? (as on sheet Z2)
- **Library title:** All activities (as on sheet Z3)
- **Capability wording:** Must state truthfully what Cyclift can plan and record for each activity. An unsupported activity is never called "planned and recorded".
- **Note:** Individual strings were not approved one by one; they follow the sheets unless the multisport requirement changes them.

### Approved layout, visual elements and interactions

- Use the Z2 / Z3 visual structure: clean sport list, compact selection controls, searchable activity library, clear distinction between main and additional activities, sport-specific options where relevant, simple Continue action.
- No complex configuration controls on this screen; the initial roster is fast and easy to complete.
- PRODUCT REQUIREMENT — Cyclift is a multi-sport athletic platform, not a cycling-and-strength application with a list of other interests.
- Multiple sports and activities can be selected, with no arbitrary two-sport limit.
- Variants and disciplines within each sport, for example: Cycling — road, indoor, mountain, gravel, commuting; Strength — gym, free weights, machines, bodyweight, calisthenics; Running — road, treadmill, trail; Swimming — pool, open water; Walking and hiking; Mobility, stretching and recovery; other activities through an extensible activity catalogue. Variants are not treated as interchangeable when their training requirements differ.
- Athlete identity derives from the activities actually selected (Cycling + Strength → Cycling/Strength hybrid; Running + Strength → Running/Strength hybrid; Cycling + Running + Swimming → Multisport/endurance athlete; Running only → Runner; multiple activities → Multisport athlete). No athlete is forced into Cycling, Strength or Cycling + Strength.
- The athlete can choose a main sport or training priority without losing additional activities.

### Mandatory functionality and dependencies

- Three separate concepts in the model: selected activities (what the athlete practises), supported recording (what Cyclift can measure or log), supported planning (what Cyclift can schedule and prescribe).
- An activity the planner or recorder does not support is retained as a selection where technically safe, with the limitation clearly disclosed; no training plans or measurements are manufactured for it.
- Retained: sport selection and removal; main sport or priority selection; additional activities; hybrid balance where relevant; activity search and categories; persistence in the authoritative athlete model; supported cycling and strength planning and recording.
- Working features are not broken and existing athlete records are not silently altered. Any model change is additive and backward-compatible.
- CURRENTLY SUPPORTED (existing engines): cycling and gym strength planning and recording.
- SEPARATE IMPLEMENTATION REQUIREMENTS — NOT COMPLETED FEATURES: sport-specific planning and recording for running, swimming, walking and hiking, mobility and recovery, bodyweight and calisthenics, and discipline-specific cycling. No fake functionality; no new training engines are to be started during the screen review.

### Explicitly rejected alternatives

- Builds 6 and 7's page and library presentation as the visual baseline (the Z2 / Z3 structure was chosen).
- Treating Cyclift as a cycling-and-strength application with other sports as mere interests.
- An arbitrary two-sport limit; forcing every athlete into Cycling, Strength or Cycling + Strength.
- Calling an unsupported activity "planned and recorded".

### Status

| Stage | State | Evidence |
|---|---|---|
| Approved design | YES | Owner, 20 Nov 2026 23:04: Z2 / Z3 visual baseline and the multisport requirement. |
| Implemented in code | YES — selection only | Catalogue of 20 activities in six sports; any number selectable; any can be main; identity derived from the selection; planning and recording support stated per activity; one additive stored field. No new planner or recorder was built. |
| Compiled | YES | Fast check 30 (run 44808739059) built the Lab app at commit 39a398f1. |
| Simulator-verified | FUNCTION: PARTLY. VISUAL: NOT YET | iPhone 15 Pro simulator, Obsidian. Roster check PASSED in fast checks 28 and 30 (run 44808739059, commit 39a398f1): six sports offered with none preselected; running says it is not planned or recorded and is never called planned and recorded; Runner identity; a runner-only roster cannot continue and says why; adding sports removes none; identities Running/Strength hybrid and Multisport athlete; balance control with cycling and strength; library search and categories; six activities selected at once; any activity made main without losing others; removal; roster kept after Back and Continue and after closing and reopening. The seven-page journey FAILED once in fast check 28 on an expectation written for the old identity text ("Road cycling + Gym training"); with that expectation corrected it PASSED in fast check 29 (run 44805193425, commit 170f90e2). |
| Physically verified on iPhone | NO | Nothing on this screen has been checked on a real iPhone. |

- **Visual verification:** PENDING. Implementation screenshots sent to the owner; no verdict yet. Known visual points: the sentence above Continue was cut off with many activities (shortened in 1a414ccb; reads in full in fast check 30); capability lines wrap to two rows; with six starter rows the Browse row sits at the fold.
- **Functional verification:** PARTLY, simulator only (fast check 28). Logic tests: 15 for the roster (578 in all passing): catalogue, truthful capability, unlimited selection, any activity main, identity examples, training type from plannable activities only, additive storage, older records unchanged.

### Remaining work or limitations

- Owner's visual verdict on the implementation.
- DECIDED 21 Nov 2026 (00:46 / 00:49) and implemented at 9834cb7f: an athlete whose roster has nothing Cyclift can plan (for example a runner) now continues and finishes onboarding without a plan (see Screen 4). The earlier 'cannot continue' behaviour and its check are SUPERSEDED. Capability wording now reads 'In your roster · plans coming soon'. Roster check last passed in focused check 32 (run 44819311147, commit 75335114).
- Deviations from the sheets, for the owner to accept or reject: the library groups by sport (sheet Z3 groups by capability); the empty page offers one activity per sport (sheet Z2 lists cycling and gym only); page 7's "Interests" label now reads "In your roster · not planned yet"; the "Recovery interests" row of sheet Z2 is not built (recovery activities are ordinary selections).
- ENGINEERING FINDING — supported through configuration today: every cycling discipline (one cycling planner and recorder); gym, free weights, machines (one strength planner and recorder).
- ENGINEERING FINDING — needs a real new training engine, NOT built: running, swimming, walking and hiking, mobility and recovery, bodyweight and calisthenics; and discipline-specific cycling (indoor, mountain, gravel, commuting are planned as general cycling).
- Not checked: redesigned main app, full Lab regression, large text, other themes, real iPhone. Profile's older "Other sports" list still shows only the earlier closed list (kept in step with the roster; its redesign belongs to the Profile review).
- An older build does not see the newer selections (it reads the earlier sports list, which still receives every activity it can name).

### Images

- `assets/S03_roster_Z2_two_sports.png` — APPROVED VISUAL BASELINE. Sheet Z2, two main sports with the balance control (actual sheet image; activities shown are illustrative).
- `assets/S03_roster_Z2_empty.png` — APPROVED VISUAL BASELINE. Sheet Z2, nothing selected yet.
- `assets/S03_roster_Z3_library.png` — APPROVED VISUAL BASELINE. Sheet Z3, the activity library.
- `assets/S03_impl_roster-empty_sim_e32920dc.png` — IMPLEMENTATION — NOT YET VISUALLY VERIFIED BY THE OWNER. Nothing selected. iPhone 15 Pro simulator, Obsidian, commit e32920dc (fast check 28).
- `assets/S03_impl_roster-runner_sim_e32920dc.png` — IMPLEMENTATION — NOT YET VISUALLY VERIFIED. Runner only, same run.
- `assets/S03_impl_library_sim_e32920dc.png` — IMPLEMENTATION — NOT YET VISUALLY VERIFIED. The activity library, same run.
- `assets/S03_impl_roster-multisport_sim_39a398f1.png` — IMPLEMENTATION — NOT YET VISUALLY VERIFIED. Five activities with trail running as the main sport, commit 39a398f1 (fast check 30).

### Decision history

| When | Decision | State |
|---|---|---|
| 15 Nov 2026 | Onboarding v3.4 Athletic Roster selected as the page 2 design baseline (sheets Z1–Z6). | IN FORCE (visual) |
| 20 Nov 2026, 23:04 | Z2 / Z3 approved as the Screen 3 visual baseline. Product requirement changed: multi-sport, extensible athletic roster; identity from selected activities; selection, recording and planning kept as separate concepts; no fake support. | IN FORCE |

---

## Screen 4 — Goals (ONB-04)

- **Navigation location:** Onboarding · page 3 of 7, after the Athletic Roster.
- **Approval date:** 21 Nov 2026, 00:30 (design direction); summary card with training mix required 13:38; approved exactly as shown 20:50 (run34_s4.png, commit ac046799)
- **Approval status:** APPROVED AND LOCKED — visually approved and simulator-verified on the iPhone 15 Pro. Do not modify without the owner's authorization
- **Original design reference and source:** Canonical design: the implementation screenshot the owner approved on 21 Nov 2026 at 20:50 (run34_s4.png, iPhone 15 Pro simulator, Obsidian, commit ac046799). Origin: the Build 6 implementation of this page (TestFlight build 6, commit 9b9d3a68; simulator screenshot from Lab run 44), chosen by the owner over the v3.3 sheet Y3 and the Build 7 rebuild, WITH MANDATORY ADJUSTMENTS. The screenshot shows a visible defect of Build 6 (text overlapping the lower cards) that the adjustments remove; it is the reference for the card design, not for the layout.
- **Implementation commit:** Summary card and mix: ba77dcd9; checked and approved at ac046799 (branch ios/lab). Earlier Goals work: 23ec4893, 31ea6914, 606651c2. Not in any TestFlight build.

### Exact approved wording

- **Page title:** What are you aiming for? (as in Build 6)
- **Main-goal explanation:** Heading in the form "MUSCLE · MAIN GOAL", then a compact explanation of the selected main goal, e.g. "Build muscle through progressive strength training, with an emphasis on appropriate working sets and recovery." (owner's example)
- **As approved:** Heading "MUSCLE · MAIN GOAL" with the planner's own rule for the goal (e.g. "8–12 reps, more working sets per muscle each week. Measured by weekly working sets and top sets."); legend: Easy riding · Hard riding · Strength · Rest; athlete without a plan: "Your running goals are saved. Personalized running plans are coming soon. You can finish setting up without a training plan."
- **Goal names:** The existing working goal names and planner mappings are retained (owner, 21 Nov 20:50): cycling — Endurance, Power, Climbing, Sprint, Event; strength — Strength, Muscle, Stamina, Maintain; general — Fitness. Goals are not renamed for cosmetic reasons.
- **Note:** Other strings were not approved one by one; they are approved as shown in the screenshot.

### Approved layout, visual elements and interactions

- Build 6 goal-card design: compact icon-based cards; two columns where appropriate; clear sport categories; distinct selected states; main-goal star indicator; existing Obsidian design language. Keep the visual character; reduce unnecessary height and spacing.
- At the standard iPhone 15 Pro display size all essential content fits on one screen without vertical scrolling. Text is not reduced until hard to read; nothing overlaps, is clipped, or hides behind the footer; Continue stays visible at the bottom.
- Larger accessibility text sizes scroll instead of clipping.
- The balance question (Cycling / Balanced / Strength) is NOT asked again; Screen 3 collected it and the stored preference is used.
- The page adapts to the athlete's roster: cycling goals for a cycling athlete, strength goals for a strength athlete, both for a cycling/strength athlete, running goals for a runner, swimming goals for a swimmer, the relevant goals for a multisport athlete. Cycling and strength goals are not shown to every athlete.
- Goals the existing planner supports are distinguished from goals that can be saved but cannot yet generate a sport-specific plan.
- Multiple goals are allowed; exactly one is the main goal, marked by the star. Changing the main goal is intuitive and deletes no other goal.
- A compact explanation of the selected main goal sits at the bottom of the content, immediately above Continue, and changes with the main goal.
- REVISION 21 Nov 13:38 — the bottom section is the main-goal SUMMARY CARD (visual basis: the Build 6 card): heading, concise explanation of the goal and how it influences training, segmented training-mix bar, and the legend for each segment, in a tinted card directly above Continue.
- The legend size is approved as shown and stays unchanged (owner, 20:50).
- The mix may be identical for two main goals (e.g. Muscle and Endurance) when the authoritative planner proposes the same session distribution. Values are never invented to create a visual difference.
- The runner-only version — the same card with the truthful no-plan summary and no bar — is accepted.

### Mandatory functionality and dependencies

- Preserved: goal selection; multiple goals; main-goal selection; relevant experience levels; existing goal storage; planner integration; accurate training explanations; Back and Continue behaviour. Selections persist after Back and after reopening the app.
- Cycling and lifting experience is kept where the current planner needs it; athletes of other sports are not asked irrelevant cycling or strength experience. No experience field the planner needs is removed without saying how it will be collected.
- No workout prescriptions are invented for unsupported sports; no unsupported training calculations; no promise of programme capabilities the app does not have.
- No change to the production app; existing athlete records are not overwritten.
- The training-mix bar reflects the athlete's selected sports and the ACTUAL proposed training distribution: it is counted from the week the real planner proposes for the athlete's answers (sessions by kind, then free days). No hardcoded cycling/strength segments, no invented values. Dependency: the planner dry run used by the Blueprint.
- An athlete with no supported training plan gets a truthful summary and NO mix chart.

### Explicitly rejected alternatives

- The v3.3 sheet Y3 layout and the Build 7 rebuild of this page as the card design.
- Asking the Cycling / Balanced / Strength preference again on this page.
- Showing cycling and strength goals to every athlete regardless of roster.
- Inventing prescriptions or plans for sports Cyclift does not support.
- The two-line explanation without the card, bar and legend (rejected 21 Nov 13:38).
- Build 6's own bar values — a fixed table of shares per goal — as the source of the bar (conflicts with the no-invented-values rule).
- Renaming existing goals for cosmetic reasons.

### Status

| Stage | State | Evidence |
|---|---|---|
| Approved design | YES | Owner, 21 Nov 2026 20:50: exactly as shown in run34_s4.png, commit ac046799. Direction 00:30; summary card required 13:38. |
| Implemented in code | YES | Commit ba77dcd9 (card and planner-derived mix) on the earlier Goals implementation; includes the profile-only outcome (owner decisions of 21 Nov 00:46 and 00:49). |
| Compiled | YES | Lab app built in focused check 34 (run 44890889110) at commit ac046799. Main-app build not run on this commit. |
| Simulator-verified | YES — visual and functional | Owner approved the screenshot at 20:50. iPhone 15 Pro simulator, Obsidian, Lab app. Focused check 34 (run 44890889110, commit ac046799), 2 of 2 passed: all goal cards, level menus, the summary card and Continue on one screen without scrolling, nothing under the card; roster-dependent groups; heading and explanation follow the main goal; the bar is inside the card, names riding and strength for the cycling/strength athlete and no sport not chosen; several goals kept when the main goal changes; Back and reopening keep selections and level; no bar for the runner; the runner completes onboarding without a plan and Home, Plan and Train show no cycling plan, goal or session, also after reopening. On earlier commits only: mixed roster planned only from a chosen goal (check 33, run 44826330301, 9834cb7f); larger-text scrolling (check 31, run 44813599677, 23ec4893 — before the card was added). Check 32 (run 44819311147) had FAILED on a leftover cycling week for the runner; corrected in 606651c2. |
| Physically verified on iPhone | NO | Nothing on this screen has been checked on a real iPhone. |

- **Visual verification:** APPROVED by the owner on 21 Nov 2026, 20:50, exactly as shown in run34_s4.png (commit ac046799). Obsidian, iPhone 15 Pro simulator only.
- **Functional verification:** VERIFIED on the iPhone 15 Pro simulator (Lab app): focused check 34, as listed. Logic tests for goals, the profile-only outcome and the mix counting pass.

### Remaining work or limitations

- OUTSTANDING — larger text sizes: scrolling has not been checked since the summary card was added.
- OUTSTANDING — other five themes: no screenshot of this screen.
- OUTSTANDING — redesigned main app: this screen has not been run there.
- OUTSTANDING — physical iPhone: nothing checked on a real device; VoiceOver unchecked.
- OUTSTANDING — regression: the full Lab run and the full logic suite have not been run on ac046799.
- Goal lists for sports without a planner (running, swimming, walking, mobility and recovery, bodyweight) remain PROVISIONAL until the owner reviews them.
- No route yet for an athlete without a plan to set one up later.
- Cross-screen integration requirements decided with this approval are recorded in their own section of this register.

### Images

- `assets/S04_approved_goals_sim_ac046799.png` — APPROVED DESIGN — as implemented (run34_s4.png). iPhone 15 Pro simulator, Obsidian, commit ac046799 (check 34). Left: cycling and strength, Muscle as main goal. Middle: the same athlete, Endurance as main goal. Right: runner-only, Pace as main goal. The yellow badge and Theme / Scenario / Restore controls are Cyclift Lab controls, not part of the screen.
- `assets/S04_goals_impl_sim_9834cb7f.png` — SUPERSEDED — NOT APPROVED (two-line explanation without the summary card; rejected 13:38). Simulator, iPhone 15 Pro, Obsidian, commit 9834cb7f (check 33). Left: cycling/strength athlete. Middle: runner-only athlete. Right: a different main goal selected.
- `assets/S04_no_plan_home_plan_train_sim_9834cb7f.png` — NOT PART OF THIS APPROVAL — record only. The runner after 'Create my profile': Home, Plan and Train without a training plan (commit 9834cb7f).
- `assets/S04_goals_build6_reference_9b9d3a68.png` — ORIGIN ONLY — NOT THE CANONICAL DESIGN. Build 6 (commit 9b9d3a68), simulator screenshot. Approved WITH MANDATORY ADJUSTMENTS not shown: compact height, everything on one screen, no overlap, roster-dependent categories, main-goal explanation above Continue.

### Decision history

| When | Decision | State |
|---|---|---|
| 21 Nov 2026, 00:30 | Build 6 goal-card design chosen with mandatory adjustments: one screen without scrolling, no repeated balance question, goals follow the roster, planned and saved-only goals distinguished, multiple goals with exactly one main goal, main-goal explanation above Continue, experience only where the planner needs it. | IN FORCE |
| 21 Nov 2026, 00:46 / 00:49 | Every athlete completes onboarding; athletes whose sports cannot be planned yet get a profile-only outcome with no fabricated plan and no automatic cycling or strength goal. Goal categories for new sports remain provisional. Screen 4 stays visually unverified until the owner reviews the screenshots. | IN FORCE |
| 21 Nov 2026, 03:10 | Record only (no decision): implementation with a two-line explanation above Continue sent for review (check 33, commit 9834cb7f). | NOTE |
| 21 Nov 2026, 13:38 | Not approved as sent: the bottom section must be the main-goal summary card — heading, concise explanation, segmented training-mix bar and legend — with the mix reflecting the athlete's sports and the actual proposed distribution; truthful summary without a chart when there is no plan. | IN FORCE |
| 21 Nov 2026, 20:50 | Approved exactly as shown in run34_s4.png, commit ac046799: Build 6-style goal cards, selected states, main-goal summary card, goal-specific explanation, planner-derived mix bar, legend and compact one-screen layout are the approved visual baseline. Legend size unchanged. The mix may be identical between goals when the planner proposes the same distribution. The runner-only no-plan version is accepted. Existing goal names and planner mappings are retained. Screens 1–4 are not to be modified without further authorization. | IN FORCE |

---

## Screen 5 — Build Your Week (ONB-05)

- **Navigation location:** Onboarding · page 4 of 7, after Goals. Every athlete builds their week here, including athletes whose sports have no planner yet.
- **Approval date:** 21 Nov 2026, 21:18 (direction); calendar and scheduling layout 22 Nov 13:34; Equipment presentation 22 Nov 14:36
- **Approval status:** VISUAL DESIGN APPROVED (calendar and scheduling: run39_s5.png, 8dbbd54a; Equipment: run41_s5_equipment.png, e5f4819a) — functional and copy refinements of 22 Nov 14:36 IMPLEMENTED AND SIMULATOR-VERIFIED (48466cec); the refined sheet wording has not itself been visually reviewed by the owner
- **Original design reference and source:** The layout the owner chose from the Screen 5 comparison board (05_build_your_week.png): compact seven-day calendar, day editor, weekly totals, equipment selector and Continue — WITH REQUIRED CHANGES. The owner's own screenshot was not received with the decision; the layout is taken to be the current-implementation column of the board, whose elements match the decision's list. To be confirmed at visual review. Origin: onboarding v3.3 sheet Y4.
- **Implementation commit:** Calendar and scheduling: 8dbbd54a. Equipment presentation: e5f4819a. Final conditions: 48466cec (branch ios/lab). Not in any TestFlight build.

### Exact approved wording

- **Page title:** Build your week
- **Note:** No individual strings were approved. Unnecessary technical text and large explanatory areas are to be removed.

### Approved layout, visual elements and interactions

- Preserve the compact seven-day calendar, day editor, weekly totals, equipment selector and Continue button.
- All essential content on one screen on the iPhone 15 Pro at standard text size, with readable typography; larger accessibility sizes scroll.
- No large empty explanatory areas; no unnecessary technical text.
- START WITH SEVEN REST DAYS: on first entry Monday to Sunday all show Rest; no session is preselected or inserted; the athlete decides.
- Tapping a day opens its activity editor. The athlete selects a sport, session type and duration, then CONFIRMS the day; only then does the day change from Rest. Any day can return to Rest.
- The day editor uses the roster saved on Screen 3 — never hardcoded Cycling and Gym. Appropriate, consistently styled native icons per sport (bicycle, dumbbell, runner, swimmer, walking figure, mountain/hiker, stretching and yoga figures); no random emoji.
- The calendar shows each day's selected activity and its duration.
- Weekly summary: total duration, number of sessions, training days, rest days, sport breakdown where space permits; updated immediately on every edit.
- Equipment selector retained, shown only when relevant to the selected activities (strength); never required of a runner-only or swimmer-only athlete.

### Mandatory functionality and dependencies

- FINAL CONDITIONS 22 Nov 14:36 — (1) the Gym preset is a suggested starting selection, not a guarantee that every machine exists; easy to review and modify. (2) If any strength session is scheduled, a Gym, Home, Bodyweight or Custom selection is required before Continue; never imposed on athletes without relevant strength sessions. (3) The prominent exercise-count message is replaced by 'We'll choose exercises based on the equipment you have.'; exact counts may stay as secondary information. (4) Concise, user-friendly equipment wording; saved-but-not-yet-used items disclosed accurately without repetitive technical labels. (5) The grouped 'Weight machines' item is kept for compatibility, with room for individual machine types later. (6) The multisport equipment lists are retained as PROVISIONAL and incomplete — not exercise-planning support.
- EQUIPMENT REVISION 22 Nov 13:34 — the Equipment control has four choices: Gym | Home | Bodyweight | Custom. 'Not sure' is not an equipment environment. These are training environments or presets, not limits on what an athlete can own.
- EQUIPMENT REVISION — an Edit equipment action opens a compact bottom sheet with a checklist of individual tick boxes. Each environment has its own editable selection. Initial lists — Gym: barbell, dumbbells, bench, cable machine, squat rack, leg press, kettlebell, resistance bands. Home: dumbbells, resistance bands, kettlebell, bench, pull-up bar, exercise mat, barbell. Bodyweight: no equipment required by default; pull-up bar, dip bars, resistance bands, gymnastic rings, weighted vest, exercise mat, dumbbells. Custom: searchable full catalogue. The lists are examples, not mutually exclusive rules; equipment is never silently removed because it belongs to another category.
- EQUIPMENT REVISION — selecting an environment loads its saved choices; switching never deletes other selections; every choice is editable; selections persist after Back, Continue and restart; a gym is not assumed to have every piece of equipment; the effect on eligible exercises is shown where the existing planner can calculate it accurately.
- EQUIPMENT REVISION — an extensible canonical catalogue for all sports, sport-relevant equipment where helpful, no equipment selection required for activities that need none. Equipment is not represented as available unless the athlete selected it or an explicitly confirmed preset provides it. No breaking change to athlete records. Choices that cannot yet influence a planner are stored accurately without pretending they affect training.
- EQUIPMENT REVISION — the approved Screen 5 layout and its no-scrolling behaviour are preserved; the checklist lives in a separate bottom sheet (which may scroll); the calendar, session editor and Continue are not shrunk.
- REFINEMENT 22 Nov 01:03 — calendar tiles show ONLY the weekday and the activity icon(s): no duration numbers; a rest day shows a moon and a small 'Rest' label; two sessions show two small icons; the selected-day outline stays. Durations stay editable in the day editor, which shows activity names and minutes. The weekly total and the compact sessions / training days / rest days summary stay beneath the calendar. Equipment stays conditional on relevant activities. Rest is a consistent, easy-to-find action in the editor. Unconfirmed day edits are clearly told apart from the confirmed week, without a large explanatory card.
- STRICT HEIGHT (22 Nov 01:03) — on the iPhone 15 Pro at standard text size everything fits without scrolling INCLUDING the expanded editor with two sessions, the weekly summary, relevant equipment and Continue; not by hiding required functionality, overlapping controls or unreadable text; tighter spacing and compact controls instead. Equipment is never silently hidden. Larger accessibility sizes may scroll.
- Continue stays disabled until at least one valid training day is configured.
- New-user rule only: an existing athlete's saved schedule is preserved when editing or resuming; choices are not reset on return.
- An activity per training day; each session's duration set independently — a duration on one day never silently changes another day; up to two sessions on one day; a session can be changed or removed; choices persist through Back, Continue and reopening.
- Feasibility warnings stay accurate.
- DECIDED 21 Nov 22:22 — Continue depends only on at least one valid configured training session. A cycling-and-strength athlete is NOT required to schedule both sports; a roster activity need not appear in every week. The older both-sports rule is not applied, with safe handling: the planner plans exactly the sessions given.
- DECIDED 22:22 — the selected activity variant IS the session type on this screen; workout prescription stays the planner's responsibility.
- DECIDED 22:22 — any combination of two selected activities on a day, two of the same sport included; both stored separately; adding a second never replaces the first. The planner's constraints are kept separately: it is given only sessions it can genuinely handle, and nothing is fabricated or silently discarded.
- DECIDED 22:22 — editable starting durations: 60 minutes for cycling, 30 minutes for other activities. Starting values, not prescriptions.
- DECIDED 22:22 — the existing sport icon system is reused for now.
- INTEGRATION RULE (22:22) — the calendar is the athlete's DECLARED TRAINING PREFERENCES, not a generated Coach plan. Any roster activity on any day. The planner consumes only what it can handle and never changes or discards the declared schedule; a week that cannot be fully planned keeps the chosen schedule with a truthful profile-only or partially planned outcome.
- The page is the athlete's chosen availability and preferred activities, kept distinct from a generated training programme, and passed to the planner as authoritative input.
- No training prescription is fabricated for a sport without a planning engine, and cycling or strength is never substituted for it. Continue still works for valid days of such sports, using the profile-only outcome where necessary.
- Scope: Screen 5 and the minimum shared-model changes for athlete-selected activities and per-day durations. Screens 1–4 unchanged.

### Explicitly rejected alternatives

- A pre-filled Coach's proposed week on first entry.
- Hardcoded Cycling and Gym as the only day choices.
- One ride length and one strength length applied to the whole week.
- Large explanatory panels and technical wording.
- Requiring an equipment choice from athletes with no strength training.

### Status

| Stage | State | Evidence |
|---|---|---|
| Approved design | DIRECTION ONLY | Owner, 21 Nov 2026 21:18. Not final visual approval. |
| Implemented in code | YES | Commit 83ed8066, including the decisions of 22:22. Additive stored field for the chosen week; older records unchanged. |
| Compiled | YES | Lab app built in focused check 37 (run 44935585991). Main-app build not run on this commit. |
| Simulator-verified | FUNCTIONAL YES (Lab, Obsidian, iPhone 15 Pro) — VISUAL PENDING | Focused check 37, run 44935585991, commit 83ed8066, 4 of 4 passed: seven rest days for a new athlete; Continue disabled until a confirmed session, enabled by one session for a cycling-and-strength athlete; only roster activities offered, each with its icon; a day changes only on Confirm; a session removed on its own row; two sessions on a day with independent lengths, the same activity twice included, no third; different lengths on different days; a day back to Rest; totals, counts and by-sport breakdown follow each change; equipment only with a strength session, not for a runner; everything above the Continue area with the editor closed and with two sessions open; Back, Continue and reopening keep the week; a runner continues to a profile-only Blueprint; a mixed roster is planned only for the ride chosen; the seven-page journey reaches an approved plan with sessions only on chosen days. Logic: 600 tests, 0 failures. Earlier: check 35 (run 44930790358) FAILED on an empty total reading '0 h' and the equipment row under Continue with two sessions open — both corrected. Checks 35 and 36 also failed once each at launch (Welcome hold did not open page 1; cause unproven; passed in 37). |
| Simulator-verified — refinement of 22 Nov | FUNCTIONAL YES (Lab, Obsidian, iPhone 15 Pro) — VISUAL PENDING | Focused check 39, run 44952043241, commit 8dbbd54a, Build your week check passed: no minutes on the calendar tiles; Rest in the editor header; 'Confirmed' / 'Not confirmed yet' tag; the calendar and summary show the confirmed week during an edit and an unconfirmed edit is not saved; with a two-session day OPEN the calendar, editor, Confirm, summary, warning note, all four equipment choices and Continue are on one screen with no overlap and the title visible; plus all scheduling and persistence checks of check 37. Check 38 (run 44949793574, f2591ad2): runner and seven-page journeys passed; this check FAILED — the day name could not be found by its identifier (cause not established; day name and tag made separate elements). Runner and seven-page journeys were not re-run on 8dbbd54a. |
| Simulator-verified — Equipment revision | FUNCTIONAL YES (Lab, Obsidian, iPhone 15 Pro) — VISUAL PENDING | Focused check 41, run 45011571192, commit e5f4819a, equipment check passed: Gym | Home | Bodyweight | Custom shown, no 'Not sure'; compact Edit control; no equipment question before a strength session; Bodyweight opens its own list with nothing ticked; ticking and unticking work; dumbbells and resistance bands raise the count of exercises the planner can offer and a stored-only item does not; Gym shows its eight preset items ticked and does not include a trap bar; removing the barbell lowers the count; switching environments erases nothing; Custom searches the catalogue and holds a squat rack and a pull buoy together; all kept after Continue and Back and after closing and reopening. Check 40 (run 45008788939, 0281b566): Build your week (one-screen fit with the new row) and the seven-page journey PASSED; the equipment check FAILED — the sheet's own identifier hid its children's; corrected. Those two were not re-run on e5f4819a (one accessibility line changed). Logic: 603 tests, 0 failures. |
| Simulator-verified — final conditions of 22 Nov 14:36 | YES — functional (Lab, Obsidian, iPhone 15 Pro) | Focused check 42, run 45013559824, commit 48466cec, 3 of 3 passed: a strength athlete cannot continue without an equipment environment and the page says what is needed; Continue enables once one is chosen; a runner without strength sessions is never asked and continues; environment and all edited selections are kept after Continue, Back and reopening; the calendar, the expanded two-session editor, the summary, the Equipment row with its four choices and Continue are on one screen; the sheet leads with 'We'll choose exercises based on the equipment you have.' with the count as a secondary line; the Gym list is presented as a suggested starting list; saved-only items are disclosed once; ticking dumbbells and bands raises the planner's own count and a saved-only item does not. Logic: 604 tests, 0 failures, including that no barbell-only exercise is offered without a barbell. |
| Physically verified on iPhone | NO |  |

- **Visual verification:** PENDING — owner to review screenshots of: all seven days at Rest; a running-only week; a multisport week with different durations and two sessions on one day.
- **Functional verification:** Lab simulator: passed at 83ed8066 (see stages). Not verified: larger text on this commit, other themes, redesigned main app, full Lab regression, physical iPhone.

### Remaining work or limitations

- Owner's visual verdict on the screenshots (sent 21 Nov).
- OUTSTANDING — larger text sizes, the other five themes, VoiceOver, the redesigned main app, the full Lab regression and a physical iPhone. The seven-page journey, the mixed-roster check and the large-text check were not re-run on 48466cec.
- For the owner's confirmation: 'Leg press' is offered as 'Weight machines (leg press and others)' — the planner has one name for all machines; default ticks (Gym: its eight listed items; Home: the existing five-item home kit; Bodyweight and Custom: none); Gym no longer assumes a trap bar or pull-up bar; before an environment is chosen none is selected and Continue is not blocked; the cycling, running, swimming and mobility items are a provisional initial list; items the planner does not use are stored and labelled as not used to choose training yet.
- The '2 sessions' count was removed from the editor header to make room for the tag and Rest. A roster with more activities than one chip row wraps and may then need scrolling (checked with three activities).
- Confirm with the owner which screenshot the chosen layout refers to (not received with the decision).
- After approval: Screen 6, three-column comparison.

### Images

- `assets/S05_final_conditions_sim_48466cec.png` — AS IMPLEMENTED AFTER THE FINAL CONDITIONS — record of the verified state (the approved screenshots follow). iPhone 15 Pro simulator, Obsidian, commit 48466cec (check 42). Left: Equipment row. Middle: Bodyweight checklist with the refined wording. Right: expanded two-session editor with summary, Equipment and Continue on one screen.
- `assets/S05_equipment_sim_e5f4819a.png` — APPROVED DESIGN (Equipment presentation, 22 Nov 2026 14:36) — as implemented; the sheet's wording is then refined per the final conditions. iPhone 15 Pro simulator, Obsidian, commit e5f4819a (check 41). Left: Screen 5 with Gym | Home | Bodyweight | Custom and the compact Edit control. Right: the Bodyweight checklist with dumbbells and resistance bands ticked.
- `assets/S05_week_refined_sim_8dbbd54a.png` — APPROVED 22 Nov 2026 13:34 FOR THE CALENDAR, DAY EDITOR AND WEEKLY SUMMARY (the Equipment row shown, with 'Not sure', is NOT approved and is being revised). iPhone 15 Pro simulator, Obsidian, commit 8dbbd54a (check 39). Left: multisport week, editor closed. Right: a two-session day with the editor expanded, equipment visible.
- `assets/S05_week_impl_sim_83ed8066.png` — SUPERSEDED — NOT APPROVED (minutes on the tiles; equipment hidden during an edit — refinement requested 22 Nov 01:03). iPhone 15 Pro simulator, Obsidian, commit 83ed8066 (check 37). Left to right: all seven days at Rest; a running-only week; a multisport week with different durations and two-session days; the day editor with two sessions open.
- `assets/S05_week_comparison_board_75335114.png` — COMPARISON BOARD — NOT AN APPROVED SCREENSHOT. Left two: design sheet Y4 (drawings). Middle: Build 6 (commit 9b9d3a68). Right two: the implementation BEFORE the required changes (commit 75335114, check 32) — it still shows a pre-filled proposed week and week-wide lengths, both now rejected.

### Decision history

| When | Decision | State |
|---|---|---|
| 21 Nov 2026, 21:18 | Layout chosen with required changes: seven rest days on first entry; roster-based day editor with confirmation; independent durations; up to two sessions a day; fuller weekly summary; equipment only when relevant; truthful handling of sports without a planner; one screen at standard text size. | IN FORCE |
| 21 Nov 2026, 22:22 | Five decisions: no both-sports requirement; activity variant is the session type; any two activities a day including the same sport, stored separately; starting durations 60 / 30 minutes accepted; existing icons reused. Integration rule: the calendar is declared preferences, not a Coach plan. Screen 5 stays design direction approved — final visual approval pending. | IN FORCE |
| 22 Nov 2026, 00:10 | Record only (no decision): implementation sent for review (check 37, commit 83ed8066) with minutes on the calendar tiles and the equipment choice stepping aside during an edit. | NOTE |
| 22 Nov 2026, 01:03 | Not approved as sent. Refinement: icon-only calendar tiles; Rest easy to find in the editor; unconfirmed edits distinguished; strict one-screen fit including the expanded two-session editor with equipment visible. Screens 1–4 untouched; Screen 6 waits. | IN FORCE |
| 22 Nov 2026, 13:34 | APPROVED: the calendar, day editor and weekly summary layout of run39_s5.png, commit 8dbbd54a. Equipment section to be revised before complete visual approval: Gym | Home | Bodyweight | Custom, per-environment editable checklists in a bottom sheet, extensible multisport catalogue, truthful planner integration. | IN FORCE |
| 22 Nov 2026, 14:36 | APPROVED: the Equipment presentation of run41_s5_equipment.png, commit e5f4819a — four environments, compact row and Edit action, separate checklist sheet, individual items, independent selections per environment, effect on eligible exercises where the planner supports it, no checklist permanently expanded on the page. With six final conditions (see Mandatory functionality). | IN FORCE |

---

## Screen 6 — Connect Your Devices (ONB-06)

- **Navigation location:** Onboarding · page 5 of 7, after Build Your Week. Not shown to an athlete who finishes without a plan.
- **Approval date:** 22 Nov 2026, 15:55 (direction); 16:34 (layout, with refinements); approved and locked 17:19
- **Approval status:** APPROVED AND LOCKED (22 Nov 2026, 17:19; fast-onb-5-connect-your-devices.png, commit a66577ee) — visually approved; functionally verified in the iPhone 15 Pro Lab simulator. Do not change without the owner's approval
- **Original design reference and source:** Canonical design: the implementation screenshot the owner approved on 22 Nov 2026 at 17:19 (fast-onb-5-connect-your-devices.png, iPhone 15 Pro simulator, Obsidian, Cyclift Lab, commit a66577ee). Origin: onboarding v3.3 design sheet Y1, page 5 (the LEFT column of the Screen 6 comparison board) — the compact connection-row design — WITH MODIFICATIONS. The sheet is an illustrative drawing; its title, its rows and its FTP block are changed by the decision.
- **Implementation commit:** First implementation a02fc5e5; refinement a66577ee (branch ios/lab). Not in any TestFlight build.

### Exact approved wording

- **Page title:** Connect your devices ("and calibrate" removed — calibration is no longer part of this page)
- **Integrations, in order:** Apple Health · Apple Watch · WHOOP · Garmin · Bluetooth devices
- **Statuses:** Connected · Not connected · Coming soon (integration not available). Connect or Manage only where functional.
- **Subtitles (22 Nov 16:34):** Apple Health — Connect your health and activity data · Apple Watch — Connect your Apple Watch · WHOOP — Connect your WHOOP · Garmin — Connect your Garmin · Bluetooth devices — Connect your sensors and devices
- **Line above Continue (22 Nov 16:34):** Connect now or set up your devices later in Profile.
- **Plan changes:** REMOVED from onboarding on 22 Nov 16:34 (was: Always ask me · Auto-apply reductions). The setting stays in Profile › App preferences › Coach.

### Approved layout, visual elements and interactions

- Compact connection rows as on the reference: clear names and icons, status labels, Connect or Manage where functional, minimal row separators, fixed Continue, Obsidian design language.
- The whole page visible on the iPhone 15 Pro at standard text size without scrolling: all five rows, the Plan changes preference and Continue. Compact spacing, not unreadably small text. Larger accessibility sizes may scroll.
- No large device cards (Build 6).
- Cyclift BikeComputer removed from THIS page only; its functionality and settings are preserved elsewhere.
- No separate cycling-sensors row: supported cycling and heart-rate sensors belong under Bluetooth devices.
- FTP selector and wattage entry removed from onboarding.

### Mandatory functionality and dependencies

- REFINEMENT 22 Nov 16:34 — all five connections kept, in order, with the owner's subtitles; icons, compact rows, statuses and visual design kept; integrations are not removed for being under development.
- REFINEMENT 22 Nov 16:34 — the entire Plan changes section is removed from onboarding (both options and the paragraph about approval and reductions). Stored preferences are not deleted and the Coach safety rules are not weakened. New athletes keep the safe default of explicit approval before changes. The preference stays accessible and editable in Profile.
- REFINEMENT 22 Nov 16:34 — above Continue only: 'Connect now or set up your devices later in Profile.' The freed space is not filled. Continue stays enabled with no connection.
- iPHONE-FIRST (22 Nov 16:34) — Cyclift works as a complete iPhone-first app while the Cyclift Watch and BikeComputer are in development. The architecture for Apple Health, Apple Watch, WHOOP, Garmin and Bluetooth sensors is preserved. No device or service is said to supply data its integration cannot retrieve. No fake connections; no simulated data outside the isolated Lab.
- All connections optional; onboarding completes with no device connected.
- Truthful statuses only. No decorative Connect button that cannot start a real connection.
- Permissions are requested only when the athlete explicitly chooses to connect that service.
- Bluetooth: access to device pairing where supported, without suggesting every Bluetooth device is compatible.
- Cyclift Lab stays fully isolated from real HealthKit, Bluetooth and external accounts: the five rows in unavailable / demo states; no scanning, pairing, sign-in or permission prompt.
- Redesigned main app: the actual existing connection services where implemented. WHOOP and Garmin are not claimed to work unless an integration is implemented and verified.
- FTP is preserved in the authoritative athlete settings and the Performance Settings workflow; stored FTP is not deleted; the cycling planner can still use it; when FTP is unknown the planner invents no measured FTP.
- (15:55, SUPERSEDED IN PART at 16:34) Plan changes was to be retained on this page; it is now removed from onboarding. Still in force: explicit approval is the default for NEW athletes; increases always need explicit approval; production Coach behaviour and stored preferences are not changed without a migration and verification plan.

### Explicitly rejected alternatives

- Build 6's large device cards.
- The title 'Connect and calibrate'.
- The Cyclift BikeComputer row and the separate bike-sensors row on this page.
- Asking for FTP in onboarding.
- Buttons that look like actions but connect nothing; claiming WHOOP or Garmin connectivity.

### Status

| Stage | State | Evidence |
|---|---|---|
| Approved design | YES | Owner, 22 Nov 2026 17:19: approved and locked exactly as shown, commit a66577ee. |
| Implemented in code | YES | Commit a02fc5e5. One additive stored marker for the Plan changes starting point; the app-wide default is unchanged. |
| Compiled | YES | Lab app built in focused check 43 (run 45020206508). |
| Simulator-verified | YES — Cyclift Lab, visual and functional (final state: check 45, below). Main app: previous commit only | First implementation — focused check 43, run 45020206508, commit a02fc5e5: the Connect your devices check PASSED — new title; the five integrations in order; Apple Health, Apple Watch and Bluetooth devices read 'Not available in Lab', WHOOP and Garmin 'Coming soon'; no Connect, Manage or Pair button in Lab; no BikeComputer row, bike-sensors row, FTP or 'calibrate'; 'Always ask me' selected for a new athlete; all rows, the preference and Continue on one screen below the title; Continue works with nothing connected; the preference is kept after Continue and Back and after reopening, and is not reset. In the same run the seven-page journey FAILED on page 1 (the typed name 'Sam' arrived as 'Sa' — About You, before this screen); re-run requested. Logic: 607 tests, 0 failures, including a stored FTP left untouched and a new athlete's FTP staying Unknown. Main app (real services): run 45022440091 requested, not yet reported. |
| Simulator-verified — refinement of 22 Nov 16:34 | YES — visual and functional, Cyclift Lab (Obsidian, iPhone 15 Pro) | Focused check 45, run 45023216295, commit a66577ee, 2 of 2 passed. Connect your devices: the five rows in order with the owner's subtitles and the same statuses; no Plan changes section and no wording about approval or reductions; the line 'Connect now or set up your devices later in Profile.'; one screen; Continue enabled with nothing connected; no system permission prompt; Back returns to the page. Seven-page journey: reaches an approved plan, and the Blueprint shows 'Always ask me' for a new athlete who was never asked. |
| Simulator-verified — redesigned main app | YES for the previous commit a02fc5e5 (same rows, earlier subtitles; Plan changes still on the page) | iOS run 308 (GitHub run 45022440091), 7 of 7 passed: in the main app the five rows exist; Apple Health, Apple Watch and Bluetooth devices show the app's real service state, with Manage for Apple Watch, Pair for Bluetooth and an Apple Health action where Health exists; WHOOP and Garmin read 'Coming soon' with no button; FTP is not asked; Continue works with nothing connected; the new athlete reaches an approved plan; the main app without the redesign setting keeps the existing interface. Not re-run on a66577ee. |
| Physically verified on iPhone | NO |  |

- **Visual verification:** APPROVED by the owner on 22 Nov 2026, 17:19, exactly as shown (commit a66577ee). Obsidian, iPhone 15 Pro simulator, Cyclift Lab only.
- **Functional verification:** Lab simulator: passed at a02fc5e5 (see stages). Main app, larger text, other themes, VoiceOver and a physical iPhone: not verified.

### Remaining work or limitations

- PENDING — redesigned main app on the exact latest commit (a66577ee): last verified on a02fc5e5 (iOS run 308), before the subtitles changed and Plan changes was removed.
- PENDING — real-device permissions: whether the main app shows any permission prompt on this page without Connect being pressed; the Apple Health request, Apple Watch and Bluetooth pairing on a physical iPhone.
- PENDING — accessibility: larger text sizes, VoiceOver.
- PENDING — the other five themes.
- Not checked on screen in this round: the Profile › Coach switch (unchanged). A full Lab regression has not been run on this commit.
- FOLLOW-UP (INT-09): the Blueprint's obsolete FTP and Plan changes links back to this screen, to be corrected in the Blueprint review.

### Images

- `assets/S06_connect_refined_sim_a66577ee.png` — APPROVED DESIGN — as implemented. iPhone 15 Pro simulator, Obsidian, Cyclift Lab, commit a66577ee (check 45): the owner's subtitles, no Plan changes, the one line above Continue.
- `assets/S06_connect_impl_sim_a02fc5e5.png` — LAYOUT APPROVED 22 Nov 2026 16:34; its subtitles, Plan changes section and bottom paragraph are then changed. iPhone 15 Pro simulator, Obsidian, Cyclift Lab, commit a02fc5e5 (check 43).
- `assets/S06_connect_comparison_board_0281b566.png` — COMPARISON BOARD — NOT AN APPROVED SCREENSHOT. Left: design sheet Y1, page 5 (the chosen visual reference, before the modifications). Middle: Build 6 (commit 9b9d3a68). Right: the implementation BEFORE the decision (commit 0281b566) — with the old title, BikeComputer and bike-sensor rows and FTP, all now removed.

### Decision history

| When | Decision | State |
|---|---|---|
| 22 Nov 2026, 15:55 | Sheet Y1 page 5 chosen as the visual reference with modifications: title 'Connect your devices'; five integrations in a fixed order; BikeComputer and the bike-sensors row removed from this page; FTP removed from onboarding and preserved elsewhere; truthful statuses and functional actions only; Lab isolation; 'Always ask me' as a new athlete's default; one screen at standard text size. | IN FORCE — Plan changes on this page superseded 16:34 |
| 22 Nov 2026, 16:34 | Overall layout of fast-onb-5-connect-your-devices.png (a02fc5e5) APPROVED, with changes: the owner's five subtitles; the Plan changes section removed from onboarding (it belongs to Profile › App preferences › Coach); only one short line above Continue; iPhone-first device strategy recorded. | IN FORCE |
| 22 Nov 2026, 17:19 | Approved and locked exactly as shown in fast-onb-5-connect-your-devices.png, commit a66577ee. Main-app verification on the latest commit, real-device permissions, accessibility and other themes recorded as pending. | IN FORCE |

---

## Screen 7 — Athlete Evolution (ONB-07)

- **Navigation location:** Onboarding · page 6 of 7, after Connect Your Devices. Not shown to an athlete who finishes without a plan.
- **Approval date:** 22 Nov 2026, 17:33 — DESIGN DIRECTION ONLY. Not final approval; not approval of stage-assessment criteria.
- **Approval status:** DESIGN DIRECTION APPROVED — interactive stage visuals and assessment policy PENDING APPROVAL. Not locked.
- **Original design reference and source:** Design sheet v3.3 Y5, the LEFT design (page 6, Athlete Evolution), chosen by the owner on 22 Nov 2026 at 17:33 with substantial interactive improvements described in his written direction. The sheet is an illustrative drawing.
- **Implementation commit:** Implementation of the direction: c9e194c9 (branch ios/lab). Not in any TestFlight build.

### Exact approved wording

- **Page title:** Athlete Evolution
- **Stage names — PROVISIONAL working labels:** G0 Origin · G1 Foundation · G2 Development · G3 Performance · G4 Refinement · G5 Mastery
- **Athlete's status until an assessment method is approved:** Starting stage not yet assessed
- **Label for an estimated stage (not in use yet):** Estimated · based on your answers
- **Label for an explored stage (PROPOSED wording):** Exploring · not your stage
- **Button:** See my blueprint
- **Stage descriptions:** PROPOSED one-line descriptions, written for review; not approved and not assessment criteria.

### Approved layout, visual elements and interactions

- Preserve the LEFT layout: black-hole / orbital hero · title · six-stage rail G0–G5 · Declared experience · Measured evidence · the athlete's stage summary · 'See my blueprint'.
- The complete screen fits the iPhone 15 Pro without scrolling at standard text size.
- G0–G5 are individually selectable. Tapping a stage changes the black-hole visual to that stage's design, shows its name and a short description, and highlights it on the rail.
- Each stage has a visually distinct orbital appearance, more developed and refined through the progression; one coherent design family.
- Three statuses that must never be confused: Estimated (from answers), Verified (approved criteria and recorded evidence), Exploring (being viewed).
- Multisport: the athlete's actual sports and experience from the Athletic Roster; not hardcoded to cycling and strength.

### Mandatory functionality and dependencies

- Stage selection never modifies the athlete's actual status. A user tapping G5 must not become G5. Exploration is presentation-only.
- Until the assessment method is approved, the athlete's actual status is 'Starting stage not yet assessed', with all six stages explorable.
- Do not invent the G0–G5 assessment thresholds. A transparent, sport-aware classification method, with explicit assumptions and examples, is submitted separately for approval before any automatic stage assignment is enabled.
- G3 must not be assigned solely because an athlete chooses Intermediate.
- No invented measurements for sports without recording integrations.
- Reuse existing approved black-hole artwork and stage assets; where distinct stage assets do not exist, a PROPOSED visual set is created for approval and is not described as already approved.
- Production stage logic, training prescriptions and athlete records are not changed. Existing onboarding answers, recorded evidence and current stage data are preserved.
- Screens 1–6 are not changed.

### Explicitly rejected alternatives

- Simply showing G0 or 'None' rather than (eventually) an estimated starting stage.
- Assigning a stage from a tap, or from a declared level alone.
- A page hardcoded to cycling and strength; six unrelated stage illustrations.

### Status

| Stage | State | Evidence |
|---|---|---|
| Approved design | DIRECTION ONLY | Owner, 22 Nov 2026 17:33. Final appearance and rules to be decided after the visual concepts and assessment method are presented. |
| Implemented in code | YES — awaiting review | Commit c9e194c9: explorable rail (a view state that is not stored), provisional names and proposed descriptions, a proposed set of stage images (six stages × six themes, drawn by the same routine as the approved Welcome artwork), roster-based declared and evidence lines, status 'Starting stage not yet assessed'. No assessment is calculated. |
| Compiled | PENDING | Focused check 46 (run 45028993447) requested. |
| Simulator-verified | PENDING | Focused check 46. |
| Physically verified on iPhone | NO |  |

- **Visual verification:** NOT YET PRESENTED. The stage visual set and descriptions are proposals awaiting the owner's decision.
- **Functional verification:** Logic: 33 focused tests pass at c9e194c9 (status is not assessed; six stages with the working names; declared and evidence lines follow the roster). Simulator: pending.

### Remaining work or limitations

- PENDING APPROVAL — the six stage visuals (proposed set).
- PENDING APPROVAL — the stage descriptions and the 'Exploring · not your stage' wording.
- PENDING APPROVAL — the starting-stage assessment method: product/evolution/STARTING_STAGE_ASSESSMENT_PROPOSAL.md. Nothing in it is enabled.
- Experience is asked only for cycling and strength today; other sports read 'experience not asked yet'. Asking it would change an approved screen.
- Not verified: redesigned main app, larger text, other themes, VoiceOver, physical iPhone.

### Images

- `assets/S07_stage_visual_set_proposed_obsidian.png` — PROPOSED STAGE VISUAL SET — NOT APPROVED. G0 to G5, Obsidian, drawn by the routine of the approved black-hole artwork with more rings, streaks and reach at each stage.
- `assets/S07_evolution_comparison_board_a66577ee.png` — COMPARISON BOARD — NOT AN APPROVED SCREENSHOT. Left: design sheet Y5 (the chosen direction). Middle: Build 6. Right: the implementation BEFORE the decision (commit a66577ee).

### Decision history

| When | Decision | State |
|---|---|---|
| 22 Nov 2026, 17:33 | LEFT v3.3 Y5 design chosen as the direction, with selectable stages G0–G5, distinct stage visuals in one family, three separate statuses (estimated, verified, exploring), multisport declared experience, 'Starting stage not yet assessed' until a method is approved, and a separately submitted assessment proposal. Not final approval. | IN FORCE — direction only |
