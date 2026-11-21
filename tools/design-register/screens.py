# Cyclift — design approval register: the single source both files are generated from.
# docs/design/CYCLIFT_APPROVED_SCREENS.md and .pdf are written by build.py from this data.
# Rule (owner, 20 Nov 2026): add or revise an entry ONLY on an explicit owner approval; never alter an earlier
# decision — a revision is appended to `history` and the earlier one is kept as superseded.
# Status words are never interchangeable: approved / implemented / compiled / simulator-verified / physically verified.

UPDATED = "21 Nov 2026, 22:40 (Dubai)"

# Approved product direction (owner, 21 Nov 2026): five separate facts per sport. Change a cell only when the thing works.
CAPABILITY = [
    ("Road cycling", "Yes", "Yes", "Yes — existing rules-based planner", "Yes — cycling recorder", "No — rules-based Coach only"),
    ("Indoor, mountain, gravel, commuting cycling", "Yes", "Yes", "As general cycling only", "As a cycling ride", "No"),
    ("Gym strength", "Yes", "Yes", "Yes — existing rules-based planner", "Yes — strength recorder", "No — rules-based Coach only"),
    ("Free weights, machines", "Yes", "Yes", "As gym training only", "As gym training", "No"),
    ("Bodyweight, calisthenics", "Yes", "Yes", "No", "No", "No"),
    ("Running (road, trail, treadmill)", "Yes", "Yes", "No", "No", "No"),
    ("Swimming (pool, open water)", "Yes", "Yes", "No", "No", "No"),
    ("Walking, hiking", "Yes", "Yes", "No", "No", "No"),
    ("Mobility, stretching, recovery", "Yes", "Yes", "No", "No", "No"),
]

# Cross-screen integration requirements decided by the owner. They are REQUIREMENTS, not implemented features, and are
# taken up when their screen is reached in the sequential review — not before.
INTEGRATION = [
    ("INT-01", "Home", "21 Nov 2026, 20:50", "Home's training categories and icons reflect the athlete's actual sports. A runner must not see Cycling as their main Endurance card.", "NOT IMPLEMENTED — for the Home review"),
    ("INT-02", "Train", "21 Nov 2026, 20:50", "Train's primary shortcuts are sport-aware. Other activities stay accessible, without presenting cycling as every athlete's default.", "NOT IMPLEMENTED — for the Training Hub review"),
    ("INT-03", "Plan", "21 Nov 2026, 20:50", "Plan's 'Add a goal' flow respects the athlete's roster, with truthful handling when personalized planning is not yet available.", "NOT IMPLEMENTED — for the Plan review"),
    ("INT-04", "Goals (all screens)", "21 Nov 2026, 20:50", "Existing working goal names and planner mappings are retained. Goals are not renamed solely for cosmetic reasons.", "IN FORCE — current behaviour"),
]

SCREENS = [
    dict(
        number=1, id="ONB-01", name="Welcome",
        location="Onboarding · first screen, shown before page 1 (About you). Shown once to a new athlete.",
        approved_on="20 Nov 2026, 16:59 (visual design and final wording); locked 17:01",
        status="APPROVED AND LOCKED — do not modify without the owner's approval",
        reference="No earlier design sheet existed for a welcome screen. The canonical design is the owner's written "
                  "\"Screen 1 final decision\" (20 Nov 2026) as shown in the simulator screenshot he approved, with the "
                  "final wording he then set.",
        wording=[("Headline", "Your evolution starts here."),
                 ("Supporting text", "Your goals. Your training. A better you, every day."),
                 ("Circular control", "Hold to begin"),
                 ("Helper", "Hold for 3 seconds")],
        design=["Black-hole / orbital hero in the upper-middle of the screen: a still image made by the drawing routine "
                "of the approved Progress design sheets (baseline form, one image per theme). Static.",
                "Order, top to bottom: hero · headline · supporting text · circular hold control. Centred, generous spacing.",
                "Press and hold the circular control for three seconds; a progress ring fills around it; the control "
                "responds subtly to touch; releasing early resets the ring; a tap does nothing.",
                "Subtle haptics: light when the hold begins, success when it completes.",
                "On completion the welcome screen dissolves (fade with a slight scale and blur), then About you appears.",
                "Accessible alternative: VoiceOver / Switch Control activation starts onboarding without the sustained hold.",
                "No Cyclift icon, no app-name heading, no technical legend, no explanatory paragraph."],
        mandatory=["Completing the hold must do what the earlier \"Get started\" button did: the athlete continues "
                   "without an account (guest state set) and onboarding page 1 opens. Dependency: the onboarding entry "
                   "in OnboardingV34.swift.",
                   "Lab controls (badge, Theme, Scenario, Restore) are not part of this screen and must not appear in the main app."],
        rejected=["The earlier welcome: Cyclift icon and name, the \"Seven short pages…\" paragraph, the three-mark legend "
                  "(Declared by you / Coach's proposal / Measured evidence), the \"About two minutes…\" line, and a tap "
                  "\"Get started\" button.",
                  "The flat Progress placeholder as the finished hero (allowed only as a fallback if an image is missing).",
                  "Flashy, cinematic or game-like transitions; continuous animation is optional and not required."],
        commits="Screen and interaction 08b4bfbf · hero image 7da39754 · final wording 58cec7b5 (branch ios/lab). Not in any TestFlight build.",
        stages=[("Approved design", "YES", "Owner, 20 Nov 2026 16:59; locked 17:01."),
                ("Implemented in code", "YES", "Commits above."),
                ("Compiled", "YES", "Fast check 24 (run 44740474661) built the Lab app at commit c67e1883."),
                ("Simulator-verified", "YES — with limits", "iPhone 15 Pro simulator, Obsidian. Fast check 24: the four approved "
                 "strings exact; tap and a 1-second hold do nothing; ring reported empty after early release; a finger drifting "
                 "about 10 pt still completes; About you opens; seven pages run to an approved plan. Main app (iOS run 307, "
                 "commit 3b326a3d, earlier wording, a different simulator size): no Lab strip, holding starts onboarding."),
                ("Physically verified on iPhone", "NO", "Nothing on this screen has been checked on a real iPhone.")],
        visual_verification="Owner approved the simulator screenshot (fast check 23) and set the final wording; the final-wording "
                            "screenshot (fast check 24) is the image in this book. Obsidian only.",
        functional_verification="Simulator only, as listed under Simulator-verified.",
        remaining=["Real iPhone: VoiceOver / Switch Control activation, the haptics, and how the dissolve looks and feels.",
                   "Other five themes and the largest text size have no screenshot with the hero image.",
                   "Main-app evidence predates the final wording (the wording change itself was verified in Lab).",
                   "Observation from fast check 25, cause not proven: a hold begun the instant the app launched did not open "
                   "page 1; with a two-second wait it did. To be checked on a real iPhone.",
                   "Open choices left to the owner: richer hero form; subtle hero motion."],
        images=[("S01_welcome_approved_sim_c67e1883.png",
                 "APPROVED DESIGN — as implemented. iPhone 15 Pro simulator, Obsidian, commit c67e1883 (fast check 24). "
                 "The yellow badge and Theme / Scenario / Restore controls are Cyclift Lab controls, not part of the screen.")],
        history=[("20 Nov 2026, 15:12", "Direction approved: black-hole hero, three-second hold, dissolve. Wording then: "
                  "\"Start your journey to a better lifestyle\" / \"See where you fit in the athletic world, and build a "
                  "routine around your life.\" / \"Hold to start\".", "SUPERSEDED (wording only)"),
                 ("20 Nov 2026, 15:28", "Hero must be the original black-hole artwork, not the flat placeholder; static image acceptable.", "IN FORCE"),
                 ("20 Nov 2026, 16:59", "Visual design approved with the final wording recorded above.", "IN FORCE"),
                 ("20 Nov 2026, 17:01", "Approved and locked as the canonical Screen 1.", "IN FORCE")],
    ),
    dict(
        number=2, id="ONB-02", name="About You",
        location="Onboarding · page 1 of 7, directly after Welcome. The same measurements are editable later in Profile › Personal details.",
        approved_on="20 Nov 2026, 17:09 (design); revised 18:24; implementation approved exactly as shown 22:00 (02_about_you_revision.png, commit 9dd5a862)",
        status="APPROVED AND LOCKED — visually approved and functionally verified on the iPhone 15 Pro simulator. No further visual changes without the owner's approval",
        reference="Canonical design: the implementation screenshots the owner approved on 20 Nov 2026 at 22:00 (board 02_about_you_revision.png, "
                  "iPhone 15 Pro simulator, Obsidian, commit 9dd5a862). Origin: onboarding v3.3 design sheet Y1, page 1 (15 Nov 2026), with the "
                  "owner's modifications of 17:09 and 18:24.",
        wording=[("Page title", "About you"),
                 ("Fields", "First name · Date of birth · Weight · Height"),
                 ("Units selector", "Units: Metric ▾ (choices: Metric, Imperial)"),
                 ("Button", "Continue"),
                 ("Removed", "Every \"optional\" label; the line \"Only your name is needed. Nothing is estimated from blanks — a missing weight stays unknown.\"; redundant technical descriptions.")],
        design=["Keep the clean, minimal v3.3 layout: large editable first name, simple Date of birth, Weight and Height rows, "
                "minimal typography and separators, clear Continue button, existing step navigation.",
                "MODIFICATION — a fourth row, Height (not on the v3.3 sheet).",
                "MODIFICATION — units: the full-width Metric / Imperial control is replaced by a compact, discreet native-style "
                "selector near the Weight and Height rows, presented as \"Units: Metric ▾\"; tapping it offers Metric or Imperial. "
                "Changing units converts the displayed values without changing the underlying measurements.",
                "MODIFICATION — date of birth: the compact date-entry sheet with direct day, month and year entry, Cancel and Done; "
                "no full-screen scrolling wheel.",
                "MODIFICATION — the bottom explanatory paragraph and all \"optional\" labels are removed.",
                "When information is missing or invalid, the page gives a clear indication of what must be corrected."],
        mandatory=["All four fields are mandatory for a new athlete: first name, date of birth, weight, height. Continue is "
                   "disabled until all four hold valid values.",
                   "First name not blank. Date of birth valid and not in the future. Weight and height positive and within "
                   "validated ranges. Nothing is filled in automatically and no assumed values are used.",
                   "The four values are kept in the authoritative athlete model and persist after reopening; Back and Continue "
                   "preserve what was entered; Metric / Imperial conversion is accurate.",
                   "BMI = weight in kilograms ÷ (height in metres)², only from actual valid measurements; descriptive only — not "
                   "body-fat, never a basis for automatic training-load decisions.",
                   "Existing athletes upgrading from an older version: no record is erased and no unsafe migration is forced "
                   "because height was missing. Existing data is handled separately from the new-athlete requirement.",
                   "Measurements stay editable later through Profile."],
        rejected=["Build 6's large boxed input cards.",
                  "The full-screen scrolling date-of-birth wheel.",
                  "The full-width Metric / Imperial segmented control (unnecessarily large).",
                  "Optional date of birth, weight or height for a new athlete (superseded 18:24).",
                  "Estimating or silently filling missing measurements."],
        commits="891d80aa (18:24 revision) on top of 848f015f (height, date sheet, BMI rule); checked at 9dd5a862 (branch ios/lab). Not in any TestFlight build.",
        stages=[("Approved design", "YES", "Owner: design 17:09, requirements 18:24, implementation as shown 22:00 (20 Nov 2026)."),
                ("Implemented in code", "YES", "Commit 891d80aa. BMI is calculated but not displayed on any screen."),
                ("Compiled", "YES", "Fast check 27 (run 44754061376) built the Lab app at commit 9dd5a862."),
                ("Simulator-verified", "YES — visual and functional", "Owner approved the screenshots at 22:00. iPhone 15 Pro simulator, Obsidian, fast check 27 (run 44754061376): Continue disabled on "
                 "an empty page and with one, two or three of the four fields; the page names what is missing; an impossible height (17 cm) is named and "
                 "blocks Continue; all four valid values enable it; no 'optional' label and no old paragraph; date typed as day/month/year with no wheel; "
                 "31 April, 29 February 1999 and a 2090 birthday each rejected with their reason, Cancel stores nothing, 29 February 2000 accepted and "
                 "shown; the units menu offers Metric and Imperial and is under 200 pt wide; Imperial shows 154 lb and 5 ft 9 in, Metric shows the "
                 "unchanged 70 and 175 again; Back and Continue keep the answers; all four present and the page complete after closing and reopening; "
                 "the seven-page journey still reaches an approved plan. Lab app only."),
                ("Physically verified on iPhone", "NO", "Nothing on this screen has been checked on a real iPhone.")],
        visual_verification="APPROVED by the owner on 20 Nov 2026, 22:00, exactly as shown in 02_about_you_revision.png (commit 9dd5a862). Obsidian, iPhone 15 Pro simulator only.",
        functional_verification="VERIFIED on the iPhone 15 Pro simulator (Lab app): fast check 27, as listed. Logic tests (19): BMI arithmetic, no BMI "
                                "without two valid measurements, the four-field rule and its wording, weight and height limits in both unit systems, "
                                "leap years, future dates, older records without a height still readable and not rejected.",
        remaining=["OUTSTANDING — redesigned main app: this screen has not been run there since the change (the main-app check was updated to enter the new required fields but not run).",
                   "OUTSTANDING — accessibility: largest text sizes, VoiceOver labels and order, High Contrast and the other four themes are unchecked for this screen.",
                   "OUTSTANDING — physical iPhone: nothing on this screen has been checked on a real device (keyboard, date sheet, units menu).",
                   "OUTSTANDING — regression: the full Lab run and two other updated checks have not been run since the change.",
                   "Where BMI should be shown — it is calculated but appears nowhere; owner decision needed.",
                   "Limits in the approved implementation, for the record: height 120–230 cm; age 13–100; weight 30–200 kg.",
                   "Profile › Personal details still uses the date wheel (left for the Profile review); its new Height row has not been seen on the simulator.",
                   "Open observation: a hold on Welcome begun the instant the app launched did not open this page (cause not proven; see Screen 1)."],
        images=[("S02_approved_about_sim_9dd5a862.png",
                 "APPROVED DESIGN — as implemented. All four fields complete, Metric. iPhone 15 Pro simulator, Obsidian, commit 9dd5a862 (fast check 27). "
                 "The yellow badge and Theme / Scenario / Restore controls are Cyclift Lab controls, not part of the screen."),
                ("S02_approved_about-empty_sim_9dd5a862.png", "APPROVED DESIGN. Empty page: Continue disabled, the line names what is missing."),
                ("S02_approved_dob-sheet_sim_9dd5a862.png", "APPROVED DESIGN. Date of birth typed as day, month and year."),
                ("S02_approved_units-menu_sim_9dd5a862.png", "APPROVED DESIGN. The compact units menu open."),
                ("S02_approved_about-imperial_sim_9dd5a862.png", "APPROVED DESIGN. Imperial: the same measurements shown in pounds and feet / inches."),
                ("S02_about_you_reference_v33_Y1_page1.png", "ORIGIN ONLY — NOT THE CANONICAL DESIGN. Onboarding v3.3 sheet Y1, page 1, from which the approved screen was developed.")],
        history=[("20 Nov 2026, 17:09", "Approved: the v3.3 reference layout with height, the compact date-of-birth entry, unit handling "
                  "and the BMI rule. First name mandatory; date of birth, weight and height optional initially.", "SUPERSEDED IN PART (optional fields)"),
                 ("20 Nov 2026, 18:24", "Revised and approved: all four fields mandatory with Continue disabled until valid and a clear "
                  "indication of what to correct; compact \"Units: Metric ▾\" selector; \"optional\" labels and the bottom paragraph "
                  "removed; date sheet preserved; existing athletes not forced through a migration.", "IN FORCE"),
                 ("20 Nov 2026, 19:05", "Record only (no new decision): the 18:24 revision was implemented and passed its simulator check; visual verdict pending.", "NOTE"),
                 ("20 Nov 2026, 22:00", "Approved exactly as shown in 02_about_you_revision.png, commit 9dd5a862: visually approved and functionally verified "
                  "on the iPhone 15 Pro simulator. All four fields stay mandatory; compact units selector, direct date entry, validation and persistence "
                  "preserved. No further visual changes without the owner's approval.", "IN FORCE")],
    ),
    dict(
        number=3, id="ONB-03", name="Athletic Roster",
        location="Onboarding · page 2 of 7, after About You. Opens the activity library as a sheet (\"Browse all activities\").",
        approved_on="20 Nov 2026, 23:04 (visual baseline Z2 / Z3; multisport product requirement)",
        status="APPROVED DESIGN AND REQUIREMENTS — implemented; owner's visual verification pending. NOT functionally complete",
        reference="Onboarding v3.4 design sheets Z2 (the page) and Z3 (the activity library), selected as the page 2 baseline on 15 Nov 2026 "
                  "and approved as the Screen 3 visual baseline on 20 Nov 2026. The sheets are illustrative drawings; they predate the "
                  "multisport requirement, so their example activities and capability groupings are not binding.",
        wording=[("Page title", "What do you train? (as on sheet Z2)"),
                 ("Library title", "All activities (as on sheet Z3)"),
                 ("Capability wording", "Must state truthfully what Cyclift can plan and record for each activity. An unsupported activity is never called \"planned and recorded\"."),
                 ("Note", "Individual strings were not approved one by one; they follow the sheets unless the multisport requirement changes them.")],
        design=["Use the Z2 / Z3 visual structure: clean sport list, compact selection controls, searchable activity library, clear distinction "
                "between main and additional activities, sport-specific options where relevant, simple Continue action.",
                "No complex configuration controls on this screen; the initial roster is fast and easy to complete.",
                "PRODUCT REQUIREMENT — Cyclift is a multi-sport athletic platform, not a cycling-and-strength application with a list of other interests.",
                "Multiple sports and activities can be selected, with no arbitrary two-sport limit.",
                "Variants and disciplines within each sport, for example: Cycling — road, indoor, mountain, gravel, commuting; Strength — gym, free "
                "weights, machines, bodyweight, calisthenics; Running — road, treadmill, trail; Swimming — pool, open water; Walking and hiking; "
                "Mobility, stretching and recovery; other activities through an extensible activity catalogue. Variants are not treated as "
                "interchangeable when their training requirements differ.",
                "Athlete identity derives from the activities actually selected (Cycling + Strength → Cycling/Strength hybrid; Running + Strength → "
                "Running/Strength hybrid; Cycling + Running + Swimming → Multisport/endurance athlete; Running only → Runner; multiple activities → "
                "Multisport athlete). No athlete is forced into Cycling, Strength or Cycling + Strength.",
                "The athlete can choose a main sport or training priority without losing additional activities."],
        mandatory=["Three separate concepts in the model: selected activities (what the athlete practises), supported recording (what Cyclift can "
                   "measure or log), supported planning (what Cyclift can schedule and prescribe).",
                   "An activity the planner or recorder does not support is retained as a selection where technically safe, with the limitation "
                   "clearly disclosed; no training plans or measurements are manufactured for it.",
                   "Retained: sport selection and removal; main sport or priority selection; additional activities; hybrid balance where relevant; "
                   "activity search and categories; persistence in the authoritative athlete model; supported cycling and strength planning and recording.",
                   "Working features are not broken and existing athlete records are not silently altered. Any model change is additive and backward-compatible.",
                   "CURRENTLY SUPPORTED (existing engines): cycling and gym strength planning and recording.",
                   "SEPARATE IMPLEMENTATION REQUIREMENTS — NOT COMPLETED FEATURES: sport-specific planning and recording for running, swimming, "
                   "walking and hiking, mobility and recovery, bodyweight and calisthenics, and discipline-specific cycling. No fake functionality; "
                   "no new training engines are to be started during the screen review."],
        rejected=["Builds 6 and 7's page and library presentation as the visual baseline (the Z2 / Z3 structure was chosen).",
                  "Treating Cyclift as a cycling-and-strength application with other sports as mere interests.",
                  "An arbitrary two-sport limit; forcing every athlete into Cycling, Strength or Cycling + Strength.",
                  "Calling an unsupported activity \"planned and recorded\"."],
        commits="43027d27 (catalogue, selection, identity, storage, Z2 / Z3 presentation), support sentence shortened in 1a414ccb; checked at 39a398f1 (branch ios/lab). Not in any TestFlight build.",
        stages=[("Approved design", "YES", "Owner, 20 Nov 2026 23:04: Z2 / Z3 visual baseline and the multisport requirement."),
                ("Implemented in code", "YES — selection only", "Catalogue of 20 activities in six sports; any number selectable; any can be main; identity derived from the "
                 "selection; planning and recording support stated per activity; one additive stored field. No new planner or recorder was built."),
                ("Compiled", "YES", "Fast check 30 (run 44808739059) built the Lab app at commit 39a398f1."),
                ("Simulator-verified", "FUNCTION: PARTLY. VISUAL: NOT YET", "iPhone 15 Pro simulator, Obsidian. Roster check PASSED in fast checks 28 and 30 (run 44808739059, commit 39a398f1): six sports offered with none "
                 "preselected; running says it is not planned or recorded and is never called planned and recorded; Runner identity; a runner-only roster "
                 "cannot continue and says why; adding sports removes none; identities Running/Strength hybrid and Multisport athlete; balance control with "
                 "cycling and strength; library search and categories; six activities selected at once; any activity made main without losing others; removal; "
                 "roster kept after Back and Continue and after closing and reopening. The seven-page journey FAILED once in fast check 28 on an expectation written for the old identity text "
                 "(\"Road cycling + Gym training\"); with that expectation corrected it PASSED in fast check 29 (run 44805193425, commit 170f90e2)."),
                ("Physically verified on iPhone", "NO", "Nothing on this screen has been checked on a real iPhone.")],
        visual_verification="PENDING. Implementation screenshots sent to the owner; no verdict yet. Known visual points: the sentence above Continue was cut off with "
                            "many activities (shortened in 1a414ccb; reads in full in fast check 30); capability lines wrap to two rows; with six starter rows the Browse row sits at the fold.",
        functional_verification="PARTLY, simulator only (fast check 28). Logic tests: 15 for the roster (578 in all passing): catalogue, truthful capability, unlimited "
                                "selection, any activity main, identity examples, training type from plannable activities only, additive storage, older records unchanged.",
        remaining=["Owner's visual verdict on the implementation.",
                   "DECIDED 21 Nov 2026 (00:46 / 00:49) and implemented at 9834cb7f: an athlete whose roster has nothing Cyclift can plan (for example a runner) now "
                   "continues and finishes onboarding without a plan (see Screen 4). The earlier 'cannot continue' behaviour and its check are SUPERSEDED. Capability wording now "
                   "reads 'In your roster · plans coming soon'. Roster check last passed in focused check 32 (run 44819311147, commit 75335114).",
                   "Deviations from the sheets, for the owner to accept or reject: the library groups by sport (sheet Z3 groups by capability); the empty page offers one "
                   "activity per sport (sheet Z2 lists cycling and gym only); page 7's \"Interests\" label now reads \"In your roster · not planned yet\"; the "
                   "\"Recovery interests\" row of sheet Z2 is not built (recovery activities are ordinary selections).",
                   "ENGINEERING FINDING — supported through configuration today: every cycling discipline (one cycling planner and recorder); gym, free weights, machines "
                   "(one strength planner and recorder).",
                   "ENGINEERING FINDING — needs a real new training engine, NOT built: running, swimming, walking and hiking, mobility and recovery, bodyweight and "
                   "calisthenics; and discipline-specific cycling (indoor, mountain, gravel, commuting are planned as general cycling).",
                   "Not checked: redesigned main app, full Lab regression, large text, other themes, real iPhone. Profile's older \"Other sports\" list still shows only the "
                   "earlier closed list (kept in step with the roster; its redesign belongs to the Profile review).",
                   "An older build does not see the newer selections (it reads the earlier sports list, which still receives every activity it can name)."],
        images=[("S03_roster_Z2_two_sports.png", "APPROVED VISUAL BASELINE. Sheet Z2, two main sports with the balance control (actual sheet image; activities shown are illustrative)."),
                ("S03_roster_Z2_empty.png", "APPROVED VISUAL BASELINE. Sheet Z2, nothing selected yet."),
                ("S03_roster_Z3_library.png", "APPROVED VISUAL BASELINE. Sheet Z3, the activity library."),
                ("S03_impl_roster-empty_sim_e32920dc.png", "IMPLEMENTATION — NOT YET VISUALLY VERIFIED BY THE OWNER. Nothing selected. iPhone 15 Pro simulator, Obsidian, commit e32920dc (fast check 28)."),
                ("S03_impl_roster-runner_sim_e32920dc.png", "IMPLEMENTATION — NOT YET VISUALLY VERIFIED. Runner only, same run."),
                ("S03_impl_library_sim_e32920dc.png", "IMPLEMENTATION — NOT YET VISUALLY VERIFIED. The activity library, same run."),
                ("S03_impl_roster-multisport_sim_39a398f1.png", "IMPLEMENTATION — NOT YET VISUALLY VERIFIED. Five activities with trail running as the main sport, commit 39a398f1 (fast check 30).")],
        history=[("15 Nov 2026", "Onboarding v3.4 Athletic Roster selected as the page 2 design baseline (sheets Z1–Z6).", "IN FORCE (visual)"),
                 ("20 Nov 2026, 23:04", "Z2 / Z3 approved as the Screen 3 visual baseline. Product requirement changed: multi-sport, extensible athletic "
                  "roster; identity from selected activities; selection, recording and planning kept as separate concepts; no fake support.", "IN FORCE")],
    ),
    dict(
        number=4, id="ONB-04", name="Goals",
        location="Onboarding · page 3 of 7, after the Athletic Roster.",
        approved_on="21 Nov 2026, 00:30 (design direction); summary card with training mix required 13:38; approved exactly as shown 20:50 (run34_s4.png, commit ac046799)",
        status="APPROVED AND LOCKED — visually approved and simulator-verified on the iPhone 15 Pro. Do not modify without the owner's authorization",
        reference="Canonical design: the implementation screenshot the owner approved on 21 Nov 2026 at 20:50 (run34_s4.png, iPhone 15 Pro simulator, Obsidian, commit ac046799). Origin: the Build 6 implementation of this page (TestFlight build 6, commit 9b9d3a68; simulator screenshot from Lab run 44), chosen by the owner "
                  "over the v3.3 sheet Y3 and the Build 7 rebuild, WITH MANDATORY ADJUSTMENTS. The screenshot shows a visible defect of Build 6 "
                  "(text overlapping the lower cards) that the adjustments remove; it is the reference for the card design, not for the layout.",
        wording=[("Page title", "What are you aiming for? (as in Build 6)"),
                 ("Main-goal explanation", "Heading in the form \"MUSCLE · MAIN GOAL\", then a compact explanation of the selected main goal, e.g. \"Build muscle through progressive strength training, with an emphasis on appropriate working sets and recovery.\" (owner's example)"),
                 ("As approved", "Heading \"MUSCLE · MAIN GOAL\" with the planner's own rule for the goal (e.g. \"8–12 reps, more working sets per muscle each week. Measured by weekly working sets and top sets.\"); legend: Easy riding · Hard riding · Strength · Rest; athlete without a plan: \"Your running goals are saved. Personalized running plans are coming soon. You can finish setting up without a training plan.\""),
                 ("Goal names", "The existing working goal names and planner mappings are retained (owner, 21 Nov 20:50): cycling — Endurance, Power, Climbing, Sprint, Event; strength — Strength, Muscle, Stamina, Maintain; general — Fitness. Goals are not renamed for cosmetic reasons."),
                 ("Note", "Other strings were not approved one by one; they are approved as shown in the screenshot.")],
        design=["Build 6 goal-card design: compact icon-based cards; two columns where appropriate; clear sport categories; distinct selected states; "
                "main-goal star indicator; existing Obsidian design language. Keep the visual character; reduce unnecessary height and spacing.",
                "At the standard iPhone 15 Pro display size all essential content fits on one screen without vertical scrolling. Text is not reduced "
                "until hard to read; nothing overlaps, is clipped, or hides behind the footer; Continue stays visible at the bottom.",
                "Larger accessibility text sizes scroll instead of clipping.",
                "The balance question (Cycling / Balanced / Strength) is NOT asked again; Screen 3 collected it and the stored preference is used.",
                "The page adapts to the athlete's roster: cycling goals for a cycling athlete, strength goals for a strength athlete, both for a "
                "cycling/strength athlete, running goals for a runner, swimming goals for a swimmer, the relevant goals for a multisport athlete. "
                "Cycling and strength goals are not shown to every athlete.",
                "Goals the existing planner supports are distinguished from goals that can be saved but cannot yet generate a sport-specific plan.",
                "Multiple goals are allowed; exactly one is the main goal, marked by the star. Changing the main goal is intuitive and deletes no other goal.",
                "A compact explanation of the selected main goal sits at the bottom of the content, immediately above Continue, and changes with the main goal.",
                "REVISION 21 Nov 13:38 — the bottom section is the main-goal SUMMARY CARD (visual basis: the Build 6 card): heading, concise explanation of the goal "
                "and how it influences training, segmented training-mix bar, and the legend for each segment, in a tinted card directly above Continue.",
                "The legend size is approved as shown and stays unchanged (owner, 20:50).",
                "The mix may be identical for two main goals (e.g. Muscle and Endurance) when the authoritative planner proposes the same session distribution. "
                "Values are never invented to create a visual difference.",
                "The runner-only version — the same card with the truthful no-plan summary and no bar — is accepted."],
        mandatory=["Preserved: goal selection; multiple goals; main-goal selection; relevant experience levels; existing goal storage; planner integration; "
                   "accurate training explanations; Back and Continue behaviour. Selections persist after Back and after reopening the app.",
                   "Cycling and lifting experience is kept where the current planner needs it; athletes of other sports are not asked irrelevant "
                   "cycling or strength experience. No experience field the planner needs is removed without saying how it will be collected.",
                   "No workout prescriptions are invented for unsupported sports; no unsupported training calculations; no promise of programme "
                   "capabilities the app does not have.",
                   "No change to the production app; existing athlete records are not overwritten.",
                   "The training-mix bar reflects the athlete's selected sports and the ACTUAL proposed training distribution: it is counted from the week the real "
                   "planner proposes for the athlete's answers (sessions by kind, then free days). No hardcoded cycling/strength segments, no invented values. "
                   "Dependency: the planner dry run used by the Blueprint.",
                   "An athlete with no supported training plan gets a truthful summary and NO mix chart."],
        rejected=["The v3.3 sheet Y3 layout and the Build 7 rebuild of this page as the card design.",
                  "Asking the Cycling / Balanced / Strength preference again on this page.",
                  "Showing cycling and strength goals to every athlete regardless of roster.",
                  "Inventing prescriptions or plans for sports Cyclift does not support.",
                  "The two-line explanation without the card, bar and legend (rejected 21 Nov 13:38).",
                  "Build 6's own bar values — a fixed table of shares per goal — as the source of the bar (conflicts with the no-invented-values rule).",
                  "Renaming existing goals for cosmetic reasons."],
        commits="Summary card and mix: ba77dcd9; checked and approved at ac046799 (branch ios/lab). Earlier Goals work: 23ec4893, 31ea6914, 606651c2. Not in any TestFlight build.",
        stages=[("Approved design", "YES", "Owner, 21 Nov 2026 20:50: exactly as shown in run34_s4.png, commit ac046799. Direction 00:30; summary card required 13:38."),
                ("Implemented in code", "YES", "Commit ba77dcd9 (card and planner-derived mix) on the earlier Goals implementation; includes the profile-only outcome "
                 "(owner decisions of 21 Nov 00:46 and 00:49)."),
                ("Compiled", "YES", "Lab app built in focused check 34 (run 44890889110) at commit ac046799. Main-app build not run on this commit."),
                ("Simulator-verified", "YES — visual and functional", "Owner approved the screenshot at 20:50. iPhone 15 Pro simulator, Obsidian, Lab app. Focused check 34 "
                 "(run 44890889110, commit ac046799), 2 of 2 passed: all goal cards, level menus, the summary card and Continue on one screen without scrolling, "
                 "nothing under the card; roster-dependent groups; heading and explanation follow the main goal; the bar is inside the card, names riding and strength "
                 "for the cycling/strength athlete and no sport not chosen; several goals kept when the main goal changes; Back and reopening keep selections and "
                 "level; no bar for the runner; the runner completes onboarding without a plan and Home, Plan and Train show no cycling plan, goal or session, also "
                 "after reopening. On earlier commits only: mixed roster planned only from a chosen goal (check 33, run 44826330301, 9834cb7f); larger-text scrolling "
                 "(check 31, run 44813599677, 23ec4893 — before the card was added). Check 32 (run 44819311147) had FAILED on a leftover cycling week for the "
                 "runner; corrected in 606651c2."),
                ("Physically verified on iPhone", "NO", "Nothing on this screen has been checked on a real iPhone.")],
        visual_verification="APPROVED by the owner on 21 Nov 2026, 20:50, exactly as shown in run34_s4.png (commit ac046799). Obsidian, iPhone 15 Pro simulator only.",
        functional_verification="VERIFIED on the iPhone 15 Pro simulator (Lab app): focused check 34, as listed. Logic tests for goals, the profile-only outcome and the mix counting pass.",
        remaining=["OUTSTANDING — larger text sizes: scrolling has not been checked since the summary card was added.",
                   "OUTSTANDING — other five themes: no screenshot of this screen.",
                   "OUTSTANDING — redesigned main app: this screen has not been run there.",
                   "OUTSTANDING — physical iPhone: nothing checked on a real device; VoiceOver unchecked.",
                   "OUTSTANDING — regression: the full Lab run and the full logic suite have not been run on ac046799.",
                   "Goal lists for sports without a planner (running, swimming, walking, mobility and recovery, bodyweight) remain PROVISIONAL until the owner reviews them.",
                   "No route yet for an athlete without a plan to set one up later.",
                   "Cross-screen integration requirements decided with this approval are recorded in their own section of this register."],
        images=[("S04_approved_goals_sim_ac046799.png",
                 "APPROVED DESIGN — as implemented (run34_s4.png). iPhone 15 Pro simulator, Obsidian, commit ac046799 (check 34). Left: cycling and strength, Muscle as "
                 "main goal. Middle: the same athlete, Endurance as main goal. Right: runner-only, Pace as main goal. The yellow badge and Theme / Scenario / Restore "
                 "controls are Cyclift Lab controls, not part of the screen."),
                ("S04_goals_impl_sim_9834cb7f.png",
                 "SUPERSEDED — NOT APPROVED (two-line explanation without the summary card; rejected 13:38). Simulator, iPhone 15 Pro, Obsidian, commit 9834cb7f (check 33). Left: cycling/strength athlete. Middle: "
                 "runner-only athlete. Right: a different main goal selected."),
                ("S04_no_plan_home_plan_train_sim_9834cb7f.png",
                 "NOT PART OF THIS APPROVAL — record only. The runner after 'Create my profile': Home, Plan and Train without a training plan (commit 9834cb7f)."),
                ("S04_goals_build6_reference_9b9d3a68.png",
                 "ORIGIN ONLY — NOT THE CANONICAL DESIGN. Build 6 (commit 9b9d3a68), simulator screenshot. Approved WITH MANDATORY ADJUSTMENTS not shown: compact height, "
                 "everything on one screen, no overlap, roster-dependent categories, main-goal explanation above Continue.")],
        history=[("21 Nov 2026, 00:30", "Build 6 goal-card design chosen with mandatory adjustments: one screen without scrolling, no repeated balance question, "
                  "goals follow the roster, planned and saved-only goals distinguished, multiple goals with exactly one main goal, main-goal explanation above "
                  "Continue, experience only where the planner needs it.", "IN FORCE"),
                 ("21 Nov 2026, 00:46 / 00:49", "Every athlete completes onboarding; athletes whose sports cannot be planned yet get a profile-only outcome with no "
                  "fabricated plan and no automatic cycling or strength goal. Goal categories for new sports remain provisional. Screen 4 stays visually unverified "
                  "until the owner reviews the screenshots.", "IN FORCE"),
                 ("21 Nov 2026, 03:10", "Record only (no decision): implementation with a two-line explanation above Continue sent for review (check 33, commit 9834cb7f).", "NOTE"),
                 ("21 Nov 2026, 13:38", "Not approved as sent: the bottom section must be the main-goal summary card — heading, concise explanation, segmented "
                  "training-mix bar and legend — with the mix reflecting the athlete's sports and the actual proposed distribution; truthful summary without a chart "
                  "when there is no plan.", "IN FORCE"),
                 ("21 Nov 2026, 20:50", "Approved exactly as shown in run34_s4.png, commit ac046799: Build 6-style goal cards, selected states, main-goal summary card, "
                  "goal-specific explanation, planner-derived mix bar, legend and compact one-screen layout are the approved visual baseline. Legend size unchanged. The "
                  "mix may be identical between goals when the planner proposes the same distribution. The runner-only no-plan version is accepted. Existing goal names "
                  "and planner mappings are retained. Screens 1–4 are not to be modified without further authorization.", "IN FORCE")],
    ),
    dict(
        number=5, id="ONB-05", name="Build Your Week",
        location="Onboarding · page 4 of 7, after Goals. Every athlete builds their week here, including athletes whose sports have no planner yet.",
        approved_on="21 Nov 2026, 21:18 (design direction with required changes)",
        status="DESIGN DIRECTION APPROVED — implementation and final visual verification pending",
        reference="The layout the owner chose from the Screen 5 comparison board (05_build_your_week.png): compact seven-day calendar, day editor, weekly totals, "
                  "equipment selector and Continue — WITH REQUIRED CHANGES. The owner's own screenshot was not received with the decision; the layout is taken "
                  "to be the current-implementation column of the board, whose elements match the decision's list. To be confirmed at visual review. Origin: "
                  "onboarding v3.3 sheet Y4.",
        wording=[("Page title", "Build your week"),
                 ("Note", "No individual strings were approved. Unnecessary technical text and large explanatory areas are to be removed.")],
        design=["Preserve the compact seven-day calendar, day editor, weekly totals, equipment selector and Continue button.",
                "All essential content on one screen on the iPhone 15 Pro at standard text size, with readable typography; larger accessibility sizes scroll.",
                "No large empty explanatory areas; no unnecessary technical text.",
                "START WITH SEVEN REST DAYS: on first entry Monday to Sunday all show Rest; no session is preselected or inserted; the athlete decides.",
                "Tapping a day opens its activity editor. The athlete selects a sport, session type and duration, then CONFIRMS the day; only then does the day "
                "change from Rest. Any day can return to Rest.",
                "The day editor uses the roster saved on Screen 3 — never hardcoded Cycling and Gym. Appropriate, consistently styled native icons per sport "
                "(bicycle, dumbbell, runner, swimmer, walking figure, mountain/hiker, stretching and yoga figures); no random emoji.",
                "The calendar shows each day's selected activity and its duration.",
                "Weekly summary: total duration, number of sessions, training days, rest days, sport breakdown where space permits; updated immediately on every edit.",
                "Equipment selector retained, shown only when relevant to the selected activities (strength); never required of a runner-only or swimmer-only athlete."],
        mandatory=["Continue stays disabled until at least one valid training day is configured.",
                   "New-user rule only: an existing athlete's saved schedule is preserved when editing or resuming; choices are not reset on return.",
                   "An activity per training day; each session's duration set independently — a duration on one day never silently changes another day; up to two "
                   "sessions on one day; a session can be changed or removed; choices persist through Back, Continue and reopening.",
                   "Feasibility warnings stay accurate.",
                   "The page is the athlete's chosen availability and preferred activities, kept distinct from a generated training programme, and passed to the "
                   "planner as authoritative input.",
                   "No training prescription is fabricated for a sport without a planning engine, and cycling or strength is never substituted for it. Continue still "
                   "works for valid days of such sports, using the profile-only outcome where necessary.",
                   "Scope: Screen 5 and the minimum shared-model changes for athlete-selected activities and per-day durations. Screens 1–4 unchanged."],
        rejected=["A pre-filled Coach's proposed week on first entry.",
                  "Hardcoded Cycling and Gym as the only day choices.",
                  "One ride length and one strength length applied to the whole week.",
                  "Large explanatory panels and technical wording.",
                  "Requiring an equipment choice from athletes with no strength training."],
        commits="Implementation in progress on branch ios/lab. Not in any TestFlight build.",
        stages=[("Approved design", "DIRECTION ONLY", "Owner, 21 Nov 2026 21:18. Not final visual approval."),
                ("Implemented in code", "NOT YET VERIFIED", "Being written and checked."),
                ("Compiled", "NOT YET", ""),
                ("Simulator-verified", "NOT YET", "To verify on the iPhone 15 Pro simulator: seven rest days for a new athlete; Continue disabled until a valid day; an "
                 "activity enables Continue; an appropriate icon per sport; different durations on different days; a day returns to Rest; two sessions on one day; "
                 "totals update; Back, Continue and reopening keep choices; planned and not-yet-planned sports handled truthfully; nothing clipped or under Continue."),
                ("Physically verified on iPhone", "NO", "")],
        visual_verification="PENDING — owner to review screenshots of: all seven days at Rest; a running-only week; a multisport week with different durations and two sessions on one day.",
        functional_verification="PENDING.",
        remaining=["Implement, verify on the simulator, and present the three screenshots with the functional results.",
                   "Confirm with the owner which screenshot the chosen layout refers to (not received with the decision).",
                   "After approval: Screen 6, three-column comparison."],
        images=[("S05_week_comparison_board_75335114.png",
                 "COMPARISON BOARD — NOT AN APPROVED SCREENSHOT. Left two: design sheet Y4 (drawings). Middle: Build 6 (commit 9b9d3a68). Right two: the implementation "
                 "BEFORE the required changes (commit 75335114, check 32) — it still shows a pre-filled proposed week and week-wide lengths, both now rejected.")],
        history=[("21 Nov 2026, 21:18", "Layout chosen with required changes: seven rest days on first entry; roster-based day editor with confirmation; independent "
                  "durations; up to two sessions a day; fuller weekly summary; equipment only when relevant; truthful handling of sports without a planner; one screen "
                  "at standard text size.", "IN FORCE")],
    ),
]
