# Cyclift — functional development backlog

**Version:** 0.2 · 28 Nov 2026, 14:00 (Dubai) · Level 2 · Status: Current.
Created by the owner's decision of 28 Nov 2026, 11:47 (`decisions/2026-11-28_uiux-first-workflow-and-strength-performance-approval.md`): UI/UX approval and functional development are tracked apart. UI/UX status lives in `docs/design/CYCLIFT_UIUX_APPROVAL_TRACKER.md`.

**Nothing in this backlog is approved for implementation, and nothing in it is finalised.** A method listed as a "candidate" is a proposal kept for the functionality phase. No item here may be presented in the app as working until it has been built, validated and verified.

What belongs here: calculation methodologies · algorithm validation · data storage · sensor integrations · activity recording and importing · scheduling support · Coach intelligence · data migrations · functional defects · regression testing.

## 1. Strength Performance — transferred by the owner on 28 Nov 2026, 11:47

| # | Item | State | Preserved material |
|---|---|---|---|
| S1 | Review of all 165 exercise-to-muscle mappings | Not started. Every row is NOT REVIEWED; needs a qualified reviewer | `docs/design/proposals/strength-performance-v1/Cyclift_Exercise_Muscle_Mapping_Review_CANDIDATE.xlsx` |
| S2 | Primary and secondary muscle attribution | Candidate only (main sets × 1, supporting sets × ½). The app today has two different rules: the planner treats the first two listed muscles as main; Progress counts a full set for every listed muscle | Revision 1.1 PDF |
| S3 | Muscle-group target methodology | Not defined. Target ranges are drawn as future-state design with illustrative data. Three published sources were confirmed to exist only; their content has not been applied | Revision 1.1 PDF |
| S4 | Progressive-overload classification (progressing, stable, declining, establishing a baseline) | Candidate only: like-for-like sessions, same exercise, variation and set count, similar effort | Revision 1.1 PDF |
| S5 | Plan-matching criteria | Deferred. The four presentation states are approved as UI. Today a planned session is completed by an explicit link, or by an unlinked log on the same day unless it is marked unplanned | Revision 1.1 PDF |
| S6 | Standardised exercise-volume calculation | Candidate only. Two rules exist in the app today: weight × repetitions × 2 for one-sided exercises (Day page, Key Metrics, workout log) and weight × repetitions (Progress). Changing either changes figures on approved screens | Revision 1.1 PDF |
| S7 | Dumbbell and one-sided recording conventions | Not decided. Today a dumbbell weight is per hand and is never doubled; the number of implements per set is not stored | Revision 1.1 PDF |
| S8 | Non-gym activity recording, importing and scheduling (calisthenics, Pilates, bodyweight and others) | Not built. Sessions carry no discipline field. Apple Health strength imports carry duration only | — |
| S9 | Exercise variation and difficulty progression | Not built; no variation ladders are stored | — |
| S10 | Strength fatigue and workload modelling | No validated model. Nothing is shown | — |
| S11 | Existing workout-log defects | Open: an empty record is counted as a session on the existing summary; the "unplanned" label can disagree with the completion rule; red trend line; pure-black background | `docs/design/proposals/strength-card-review/` |
| S12 | Intermittent first tap on the Strength card | Open. 1 failure in 17 simulator launches (check 84); not reproduced in checks 85, 86 or the eight-launch probe 87; cause not established | Checks 84–87 |

## 2. Endurance Performance — recorded on 28 Nov 2026, 01:27

Full table: `product/endurance/ENDURANCE_PERFORMANCE_V1_APPROVED_DESIGN_AND_REQUIREMENTS.md`, "Outstanding requirements".

| Group | Items |
|---|---|
| Calculations | Comparable-effort efficiency (initial candidate, for testing and validation only) · power curve across rides · aerobic decoupling · prescribed-versus-actual intensity roll-up · Intensity Factor and Training Stress · training load across sports (no approved method) · fitness, fatigue and form (no validated model) · endurance-only plan completion reusing the one existing rule |
| Storage | Dated FTP history — feasibility and compatibility review authorised, implementation not authorised · recovery readings beyond 90 days are not kept · no in-app restore from an export |
| Sensors | Power-based modules need rides recorded with a power meter · heart-rate zone settings · temperature not recorded · VO₂ max not read (a new Apple Health permission is not authorised) · cycling dynamics |
| Multisport | Recording, importing and scheduling for non-cycling endurance activities · a Home Endurance card for running-based athletes · adding an activity after onboarding · thresholds per sport |

## 3. Carried from the design register ("Outstanding work")

Full text: `docs/design/CYCLIFT_APPROVED_SCREENS.md`.

| Item | State |
|---|---|
| Planning and recording for additional sports | Not built |
| Multisport recording for Training Mix | Not built |
| Training-load method | Not defined |
| WHOOP and Garmin integrations | Not built; shown as "Coming soon" |
| Athlete Evolution assessment and verification policy | Not activated; policy specification awaiting approval |
| Experience questions for sports other than cycling and lifting | Not asked; adding them changes locked onboarding pages |
| A route for an athlete who finished onboarding without a plan to set one up later | Not built |
| Production integration and compatibility of the redesign | Not done |
| Persistence changes made during onboarding work | Additive only; compatibility assessment outstanding |
| Coach: AI conversation, fueling guidance, extended policy vocabulary | Not authorised / not reviewed |
| Arabic localisation; data import and recovery | Not started |

## 3a. Recovery Dashboard and Sleep & Wellness — recorded with Review Package 1 (28 Nov 2026)

| Item | State |
|---|---|
| Journal store: morning and evening entries per day, each answer optional, with its entry time and "entered by you" | Not built |
| Energy, headache, stress, soreness, water, caffeine as daily entries; bedtime, wake time, interruptions | Not built. Apple Health sleep timing is not read today; a new permission is not authorised |
| Edit, delete one entry, delete the whole journal, export | Not built |
| Manual and measured sleep kept side by side with source and time | Not built |
| Association rules behind the Coach card (minimum seven paired days, tentative wording) | Not defined |
| Usual-range rule applied to entered values (normalised view) | Not defined. The rule exists only for measured readings |
| Urgent-care wording and trigger; whether other symptoms get the same handling | Owner's decision at UI review; wording then to be reviewed |
| Retiring the older Recovery page; where "Today — Train as planned" goes, if anywhere | Owner's decision in Review Package 1 |
| Re-capture of the Recovery "no readings" state on the corrected build | Outstanding verification |

## 4. Release blockers and verification — unchanged

- Build 216 downgrade / data-loss risk: OPEN, a release blocker. Build 216 is the protected production baseline.
- E1 safety requirements: open.
- Accessibility, the five other themes, the redesigned main app, full Lab regression and physical-iPhone testing: outstanding for every approved screen.
- Approved designs not yet built: Endurance Performance (APP-09), Strength Performance (APP-10), Sleep & Wellness (APP-06, direction only).
