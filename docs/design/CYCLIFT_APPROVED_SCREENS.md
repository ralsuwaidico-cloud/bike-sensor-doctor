# Cyclift — Approved Screens Register

Last updated: 21 Nov 2026, 02:00 (Dubai) · Screens recorded: 4

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

## Summary

| # | ID | Screen | Approved design | Implemented in code | Compiled | Simulator-verified | Physically verified on iPhone |
|---|---|---|---|---|---|---|---|
| 1 | ONB-01 | Welcome | YES | YES | YES | YES — with limits | NO |
| 2 | ONB-02 | About You | YES | YES | YES | YES — visual and functional | NO |
| 3 | ONB-03 | Athletic Roster | YES | YES — selection only | YES | FUNCTION: PARTLY. VISUAL: NOT YET | NO |
| 4 | ONB-04 | Goals | DIRECTION ONLY | NOT YET | NOT YET | NOT YET | NO |

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
- OWNER DECISION NEEDED — an athlete whose roster has nothing Cyclift can plan (for example a runner) cannot continue onboarding: pages 3–7 and the plan need a stored training type of cycling, strength or hybrid. Letting them through needs a 'roster without a plan' path across those pages and the plan model.
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
- **Approval date:** 21 Nov 2026, 00:30 (design direction: Build 6 goal cards with mandatory adjustments)
- **Approval status:** DESIGN DIRECTION APPROVED — implementation and visual verification pending
- **Original design reference and source:** The Build 6 implementation of this page (TestFlight build 6, commit 9b9d3a68; simulator screenshot from Lab run 44), chosen by the owner over the v3.3 sheet Y3 and the Build 7 rebuild, WITH MANDATORY ADJUSTMENTS. The screenshot shows a visible defect of Build 6 (text overlapping the lower cards) that the adjustments remove; it is the reference for the card design, not for the layout.
- **Implementation commit:** Not yet verified. Implementation in progress on branch ios/lab.

### Exact approved wording

- **Page title:** What are you aiming for? (as in Build 6)
- **Main-goal explanation:** Heading in the form "MUSCLE · MAIN GOAL", then a compact explanation of the selected main goal, e.g. "Build muscle through progressive strength training, with an emphasis on appropriate working sets and recovery." (owner's example)
- **Note:** Other strings were not approved one by one.

### Approved layout, visual elements and interactions

- Build 6 goal-card design: compact icon-based cards; two columns where appropriate; clear sport categories; distinct selected states; main-goal star indicator; existing Obsidian design language. Keep the visual character; reduce unnecessary height and spacing.
- At the standard iPhone 15 Pro display size all essential content fits on one screen without vertical scrolling. Text is not reduced until hard to read; nothing overlaps, is clipped, or hides behind the footer; Continue stays visible at the bottom.
- Larger accessibility text sizes scroll instead of clipping.
- The balance question (Cycling / Balanced / Strength) is NOT asked again; Screen 3 collected it and the stored preference is used.
- The page adapts to the athlete's roster: cycling goals for a cycling athlete, strength goals for a strength athlete, both for a cycling/strength athlete, running goals for a runner, swimming goals for a swimmer, the relevant goals for a multisport athlete. Cycling and strength goals are not shown to every athlete.
- Goals the existing planner supports are distinguished from goals that can be saved but cannot yet generate a sport-specific plan.
- Multiple goals are allowed; exactly one is the main goal, marked by the star. Changing the main goal is intuitive and deletes no other goal.
- A compact explanation of the selected main goal sits at the bottom of the content, immediately above Continue, and changes with the main goal.

### Mandatory functionality and dependencies

- Preserved: goal selection; multiple goals; main-goal selection; relevant experience levels; existing goal storage; planner integration; accurate training explanations; Back and Continue behaviour. Selections persist after Back and after reopening the app.
- Cycling and lifting experience is kept where the current planner needs it; athletes of other sports are not asked irrelevant cycling or strength experience. No experience field the planner needs is removed without saying how it will be collected.
- No workout prescriptions are invented for unsupported sports; no unsupported training calculations; no promise of programme capabilities the app does not have.
- No change to the production app; existing athlete records are not overwritten.

### Explicitly rejected alternatives

- The v3.3 sheet Y3 layout and the Build 7 rebuild of this page as the card design.
- Asking the Cycling / Balanced / Strength preference again on this page.
- Showing cycling and strength goals to every athlete regardless of roster.
- Inventing prescriptions or plans for sports Cyclift does not support.

### Status

| Stage | State | Evidence |
|---|---|---|
| Approved design | DIRECTION ONLY | Owner, 21 Nov 2026 00:30. The final screenshot is not approved until the owner reviews the updated implementation. |
| Implemented in code | NOT YET | Being written. |
| Compiled | NOT YET |  |
| Simulator-verified | NOT YET | To verify on the iPhone 15 Pro simulator: fits without scrolling at standard size; no overlap or clipping; correct categories; explanation updates; goals and main-goal changes persist; unsupported goals trigger no fabricated plan; Back and Continue keep selections; larger text scrolls. |
| Physically verified on iPhone | NO |  |

- **Visual verification:** PENDING — owner to review screenshots of: a cycling/strength athlete, a runner-only athlete, and a different main goal selected.
- **Functional verification:** PENDING.

### Remaining work or limitations

- Implement only these Screen 4 changes; provide the three screenshots and the functional results.
- Goal lists for sports without a planner (running, swimming, walking, mobility and recovery, bodyweight) do not exist in any approved document; the implementation's lists are provisional and need the owner's review.
- After the owner's visual approval: Screen 5 — Build Your Week, three-column review.

### Images

- `assets/S04_goals_build6_reference_9b9d3a68.png` — APPROVED CARD DESIGN REFERENCE. Build 6 (commit 9b9d3a68), simulator screenshot. Approved WITH MANDATORY ADJUSTMENTS not shown: compact height, everything on one screen, no overlap, roster-dependent categories, main-goal explanation above Continue.

### Decision history

| When | Decision | State |
|---|---|---|
| 21 Nov 2026, 00:30 | Build 6 goal-card design chosen with mandatory adjustments: one screen without scrolling, no repeated balance question, goals follow the roster, planned and saved-only goals distinguished, multiple goals with exactly one main goal, main-goal explanation above Continue, experience only where the planner needs it. | IN FORCE |
