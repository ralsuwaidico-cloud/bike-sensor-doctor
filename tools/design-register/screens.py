# Cyclift — design approval register: the single source both files are generated from.
# docs/design/CYCLIFT_APPROVED_SCREENS.md and .pdf are written by build.py from this data.
# Rule (owner, 20 Nov 2026): add or revise an entry ONLY on an explicit owner approval; never alter an earlier
# decision — a revision is appended to `history` and the earlier one is kept as superseded.
# Status words are never interchangeable: approved / implemented / compiled / simulator-verified / physically verified.

UPDATED = "20 Nov 2026, 23:15 (Dubai)"

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
        status="APPROVED DESIGN AND REQUIREMENTS — implementation and verification pending. NOT functionally complete",
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
        commits="Not yet implemented. The page in builds 6 and 7 (commit 19340b09) is the earlier cycling-and-strength roster.",
        stages=[("Approved design", "YES", "Owner, 20 Nov 2026 23:04: Z2 / Z3 visual baseline and the multisport requirement."),
                ("Implemented in code", "NOT YET", "The approved presentation and the minimum safe athlete-selection changes are not written yet."),
                ("Compiled", "NOT YET", ""),
                ("Simulator-verified", "NOT YET", "Not to be marked functionally complete until selected activities persist correctly and the screen reports its capabilities accurately."),
                ("Physically verified on iPhone", "NO", "")],
        visual_verification="PENDING — no implementation screenshot exists yet.",
        functional_verification="PENDING.",
        remaining=["Implement the approved presentation and the minimum safe selection changes; show the iPhone 15 Pro screenshot.",
                   "Engineering review to record: what the existing sport registry, athlete model, planner and recorders can support through "
                   "configuration, and what needs a new training engine.",
                   "Downstream development to document: planning and recording for each sport that is selectable but unsupported."],
        images=[("S03_roster_Z2_two_sports.png", "APPROVED VISUAL BASELINE. Sheet Z2, two main sports with the balance control (actual sheet image; activities shown are illustrative)."),
                ("S03_roster_Z2_empty.png", "APPROVED VISUAL BASELINE. Sheet Z2, nothing selected yet."),
                ("S03_roster_Z3_library.png", "APPROVED VISUAL BASELINE. Sheet Z3, the activity library.")],
        history=[("15 Nov 2026", "Onboarding v3.4 Athletic Roster selected as the page 2 design baseline (sheets Z1–Z6).", "IN FORCE (visual)"),
                 ("20 Nov 2026, 23:04", "Z2 / Z3 approved as the Screen 3 visual baseline. Product requirement changed: multi-sport, extensible athletic "
                  "roster; identity from selected activities; selection, recording and planning kept as separate concepts; no fake support.", "IN FORCE")],
    ),
]
