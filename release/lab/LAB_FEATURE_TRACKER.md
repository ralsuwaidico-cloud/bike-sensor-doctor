# Cyclift Lab — feature tracker (redesign in the shared app)

**Version:** 0.6 · 28 Nov 2026 (section 9 added; sections 1–8 are as of 18 Nov 2026 and have not been re-audited) · Level 3 · Status: Current Draft, kept short on purpose.
One codebase: every item below is shared code behind the redesign switch (on in Cyclift Lab; on in the main app only in controlled CI; off in production).
Evidence words: **compiled** = built in CI · **ran** = seen running in the iOS simulator (run named) · **visually compared** = screenshot set beside its reference · nothing here is physical-device tested, and nothing is visually approved by the owner unless it says so.
Governing instructions: Master Project Instructions v3.0. The repository has no CLAUDE.md.

## 1. Screens

| Screen | Reference | State on 18 Nov 2026 | Evidence (commit · run) | Open |
|---|---|---|---|---|
| Navigation v1.2 rev 1.1 (dock) | Sheet F1, final visual specification | Ran. Measured by test: ball bottom 34.0 pt, left 14.0 pt, ball 72 pt, silhouette 90.8 pt. Was 18 pt too high before Batch 1. Visually compared with F1 | e91e38be · Lab 32 | Content passes behind the dock while scrolling, as sheet F7 allows; owner asked for no content showing beneath it — decision open |
| Home v2.3 | Prototype source (proto/ui-lab). PROVISIONAL: no picture reference, not approved | Ran on the athlete's own records in Lab and in the redesigned main app. Every control presents its page at the first tap (day, Consistency, Recovery, Endurance, Strength, Sleep, Key metrics; again after returning). End of page 128.0 pt | e91e38be · Lab 32 (8/8); iOS 286 redesigned main app ok | Differences in section 6. Awaits owner's visual review |
| Profile v2.0 (six sections) | Sheets P01–P10 | Ran; theme switching passes. Inner pages still the existing ones | Lab 32 | Batch 5 |
| Plan v2.0 | Sheets B1, B2 | Ran; visually compared with B1 (Obsidian). Week named by its dates; session cards show length · exercise count (or ride structure) and structure bars from the prescription. Remaining differences: no "Add a goal" control on the goal card (a chevron instead); the Coach row wraps to two lines; rest days show a dash under the date (not on the sheet); strength bars are one height (the plan holds no per-exercise intensity). Not owner-approved | Lab 33 (8ba4f4e1) | Owner visual review; "Add a goal" |
| Training Hub compact panel → full Hub | v1.4 sheets 06b, 06c | Ran; panel and expansion checks pass | Lab 32 | — |
| Strength preparation | v1.4 sheet 01a (J2), G3 | Built and ran: opens from the Train panel for a session that can start now; Start, minimise → Resume, finish all exercised in the Lab journey. Visually compared with J2: composition matches. Differences: a "More" button (top right, not on the sheet) opens the existing session page; equipment words are the library's ("dumbbell"); the demo session's name repeats "Strength"; a superset group has not been seen on screen (demo session has none; covered by logic tests only). Other states (done, skipped, later day, no routine, health hold) keep the existing page. Not owner-approved | Lab 33 (8ba4f4e1) | Owner visual review; decide on "More" |
| Strength recorder v1.4 | v1.4 sheets 04a–04c | Ran: journey logs 10 sets, saves, survives relaunch. Superset not seen on screen | Lab 32 | Visual comparison; superset on screen |
| Finish / save | v1.4 sheets 06e, 06f | Ran, but the layout is not the approved one | Lab 32 | Batch 3 |
| Review (three optional values, pain unknown ≠ none) | v1.4 sheet 06a | Ran, but the layout is not the approved one | Lab 32 | Batch 3 |
| Cycling v1.4 (Lab: labelled simulation) | v1.4 sheets 05a, 05b | Ran; saves nothing in Lab | Lab 32 | Visual comparison; real recorder behind it is gated |
| Coach page (timeline, rules-based conversation) | Sheets G1, G2 | Ran; card routes and chat pass. Structure is not G1 | Lab 32; iOS 286 | Batch 4 |
| Progress compact hero | Sheets PH1–PH5 | Ran; lower sections are the existing ones | Lab 32 | Batch 5 |
| Onboarding v3.4, seven pages | Sheets Z1–Z5 | Ran: new athlete onboards, approves, sees the plan; also in the redesigned main app | Lab 32; iOS 286 | Presentation of pages 3–7 provisional; Batch 5 |

## 2. Capabilities deliberately not built — kept visible

| Capability | Why not | Needs |
|---|---|---|
| Onboarding: sport per session | No stored field | Owner decision on a new field |
| Onboarding: recovery reminder on a rest day | No stored field | Owner decision on a new field |
| Onboarding / Progress: Athlete Evolution stage | No approved stage criteria | Approved criteria |
| Main-sport flag as its own field | Not approved; roster order carries it | Decision if order is not enough |
| Activities without an identifier (walking, bodyweight, mobility, breathing, sauna) | Cannot be stored | Identifiers approved |
| Cycling: minimise a ride; real recorder behind the new screen | Blocked by the cycling safety gate | Gate passed and approved |
| Cycling: Map view | Lab has no location | — |
| Coach: AI chat | No model authorised | Authorisation |
| Coach: fueling guidance | Wording not reviewed by a sports dietitian | Reviewed copy |
| Coach: policy check for sets, intervals, session type, exercise swaps, longer sessions | Policy has no description for them | Policy vocabulary extended |
| Coach: decisions made before 16 Nov 2026 | Not recorded at the time | — (not reconstructed) |

## 3. Storage changes made in the redesign (all additive)

| Change | Effect on existing records |
|---|---|
| Review record gains optional `intensity` (stored only; no engine reads it) | None: absent in every existing record; never defaulted |
| Coach's own files `coach-shadow.json`, `coach-page.json` beside the athlete record | None: separate files; removed by Delete all data |
| Session review record: three independent optional values (Intensity, Performance, Effort), pain optional so unknown is not "none" (approved 16 Nov) | None: absent in every existing record; never defaulted. Not downgrade-safe by itself — see build-216 risk |
| Strength sets: skipped sets and exercises, timed, added-weight and assisted sets (approved 16 Nov). Superset rounds: written, not seen on screen | Same: optional and additive; build 216 would not understand them |

## 4. E1 safety work — unchanged and still open
No fully verified E1 commit. Open: Progress large-text preview bubble; cancelled owner job of run 252; Delete All Data definition; "Not saved" screen test; large-text truncation; ride-start pathway tests; release accounting; device check; evidence report. E1 commits after `4970c5c7` are not in the Lab branch.

## 5. Regression evidence (each applies to its own commit only)

| Commit | Run | What passed | What did not |
|---|---|---|---|
| a4de9d30 | iOS 271 (smoke only) | 33 smoke tests, 0 failures, 7 skipped by design; 93 min. Earlier cancellations were the 75-minute limit | — |
| a4de9d30 | Lab 19 | 7/7 | — |
| caf4862e | iOS 274 (journeys; rerun) | Redesigned main app; production hybrid, cycling, strength journeys | First attempt: hybrid journey — Profile "Type & experience" row tapped, editor did not open. Not reproduced on rerun. Cause unknown; tracked (section 7) |
| e91e38be | Lab 32 | 8/8 including first-tap Home navigation | — |
| e91e38be | iOS 286 (journeys + smoke) | Redesigned main app (2 tests); production hybrid, cycling, strength journeys; 31 of 33 smoke tests incl. 8 of 9 production Home navigation tests | 2 smoke tests failed to START (simulator: "Timed out while launching application", "Failed to get background assertion"). Rerun alone: see iOS 288 |
| e91e38be | iOS 287, logic 131 | Compile, 809 unit tests; Linux logic tests | — |
| e91e38be | iOS 288 (the two smoke tests alone) | Both passed on small and standard simulators. Supports a simulator launch failure in 286; the cause of those two launch failures is not known | — |
| 8ba4f4e1 | Lab 33 | 8/8 incl. the strength journey through the v1.4 preparation screen and first-tap Home navigation | — |
| 8ba4f4e1 | iOS 290 (journeys) | Redesigned main app (2 tests); production hybrid, cycling, strength journeys | — |
| 8ba4f4e1 | logic 132 | Linux logic tests incl. 3 new preparation-row tests | iOS 289 (compile + 809 Mac unit tests) was CANCELLED, not failed: the full Mac unit suite has not run on this commit (the app did build in Lab 33 and iOS 290) |

CI changes of 17 Nov (c6d594bc, not yet exercised by a full run): smoke job limit 120 min with a 15-minute limit per test; the design gallery audit, which ran in no routine job, now runs on the standard-size layout job. Five Plan/Home smoke tests take 3–9 minutes each — optimisation deferred.

## 6. Home v2.3 — stated differences from the prototype and open points

- Header is pinned (prototype scrolled it): the avatar is the only way to Profile.
- A "Coach page" line follows a suggestion that opens its own sheet, so the Coach page stays reachable.
- Trend graph has two modes built from records (Activity; Recovery trends). The prototype's load-against-recovery-score mode is NOT built: no approved recovery score exists.
- Recovery is a status word, "partial" or "awaiting" — never a number. No sleep target is stored, so none is shown or offered.
- Taps open the existing week, day, cycling, strength and recovery pages; the prototype's own detail sheets are not brought over.
- The goal card and today's-session reminder of the previous dashboard are not on Home v2.3 (the Train ball covers today's session). Whether goals are reachable from Profile: not checked.
- G3's schematic shows a "Today" card and "Next 7 days"; Home v2.3 has the week strip instead.
- Lab demo athlete has no health readings: Recovery shows "Awaiting data", Key metrics "No data" — honest, but those parts are not visually exercised.
- The Lab's yellow strip dominates the top of the screen.

## 7. Defects and open issues

| Item | State |
|---|---|
| Home v2.3 pages never appeared (Lab runs 20–31) | CLOSED in e91e38be. Cause: Home's wrapper asked the window for its bottom safe-area inset while Home's body was evaluated; Home was then never redrawn, so handlers ran and the route list changed but nothing was shown. Shown both ways in Lab 31. Fix: the shell reads the inset outside rendering and hands it down. Why the system stops redrawing after that lookup is not explained. Introduced by Batch 1 (the previous dashboard navigated correctly in the same shell) |
| Production Profile → "Type & experience" did not open once (iOS 274, first attempt) | OPEN, cause unknown. Recording shows a still screen and a tap on the right row. Separate from the Home defect: different stack and mechanism. Covered by the required hybrid journey |
| Tests that reported a hidden page as visible | CLOSED: `tapPresents` requires the page on screen, its back button tappable, and the tapped control no longer reachable |
| Build-216 downgrade / data-loss risk | OPEN — release blocker |
| Arabic (right-to-left, localisation) | Not started — required for the complete product |
| Data import / recovery | Not started — required before production if export is presented as a backup |
| Main-app coverage of strength recorder, review, cycling with the redesign on | Missing |

## 8. Lab TestFlight builds and real-device feedback

| Build | Commit | Uploaded | State |
|---|---|---|---|
| 0.1.0 (3) | 59e2f033 | 16 Nov 2026 | Superseded |
| 0.1.0 (4) | 8ba4f4e1 | 18 Nov 2026 (owner approval 13:22 Dubai; signed-build check 3 passed; upload run 2) | Internal testers only. Installed on the owner's iPhone |

Owner's iPhone review of build 4 (18 Nov 2026, physical device). Corrections are on the development branch and are NOT in build 4; none is confirmed until seen running and shown to the owner.

| # | Feedback | Correction on the branch | Seen running |
|---|---|---|---|
| 1 | The yellow Lab band dominates every screen | One compact yellow tag on the app's own background (96e4c33c); isolation unchanged | Not yet |
| 2 | The dock overlaps or obscures content (Home, Progress) | Page fades into its background 12 pt above the dock and is not visible beneath it; Progress end-of-page checked against the dock (96e4c33c) | Not yet |
| 3 | Home v2.3 needs visual refinement and approval | Still provisional; no change made | — |
| 4 | Plan is larger and more colourful than B1 | Add a goal, one-line Coach row, no rest-day dash (80ce5347, seen in Lab 34 and 39). Whether that answers "larger and more colourful" is for the owner to judge on the next build | Lab 34, 39 |
| 5 | Progress must have its full structure | v2.3 sections on real records (74daaeb9, seen in Lab 39); Next evolution and the Evolution timeline still absent — stage criteria not approved | Lab 39 |

No further TestFlight upload without separate authorization.


## 9. Home destination pages — design decisions since 23 Nov 2026

The authoritative record of each screen's approval, evidence and remaining work is `docs/design/CYCLIFT_APPROVED_SCREENS.md`. This table tracks development state only.

| Destination | Design state | Development state on 28 Nov 2026 | Next action |
|---|---|---|---|
| Consistency Dashboard (APP-02) | Approved and locked 23 Nov | Built in Lab; focused check 61 | Accessibility, main app, regression, device |
| Training Mix Dashboard (APP-03) | Approved and locked 24 Nov | Built in Lab; focused check 68 | Same |
| Recovery Dashboard (APP-04) | Direction accepted; final approval pending | Built in Lab; focused check 66 | Owner's final approval |
| Day page (APP-05) | Approved and locked 25 Nov | Built in Lab; focused check 76 | Accessibility, main app, regression, device |
| Sleep & Wellness (APP-06) | Direction approved; refined mockups awaiting approval | Not built | Owner's visual approval |
| Resting Heart Rate page (APP-07) | Under review | Not built | Owner's decision |
| Key Metrics hub and Choose four for Home (APP-08) | Approved and locked 27 Nov | Built in Lab; focused checks 80 and 81 (app code 22d7cc15) | Accessibility, main app, regression, device |
| Endurance Performance (APP-09) | **UI design approved and locked 28 Nov** (Option C Revision 1.1, mockups) | **Not built.** The existing "Cycling summary" is still the page | Implementation in Lab when requested; comparable-effort validation; FTP history feasibility review (authorised, no storage change) |
| Strength Performance (APP-10) | Design exploration presented 28 Nov (balanced proposal, mockups); **not approved** | **Not built.** The existing "Strength summary" is still the page (captured in check 86) | Owner's decision on the proposal; no calculation, storage change or implementation authorised |

Outstanding Endurance Performance requirements (calculations, storage, sensors, multisport) are listed in `product/endurance/ENDURANCE_PERFORMANCE_V1_APPROVED_DESIGN_AND_REQUIREMENTS.md`. None is approved for implementation by the UI approval.
