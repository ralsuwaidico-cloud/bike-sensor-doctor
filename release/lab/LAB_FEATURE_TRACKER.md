# Cyclift Lab — feature tracker (redesign in the shared app)

**Version:** 0.1 · 16 Nov 2026 · Level 3 · Status: Current Draft, kept short on purpose.
One codebase: every item below is shared code behind the redesign switch (on in Cyclift Lab, off in production).
Evidence words: **compiled** = built in CI · **ran** = seen running in the iOS simulator (Lab run named) · nothing here is physical-device tested.

## 1. Screens

| Screen | State on 16 Nov 2026 (22:00 Dubai) | Evidence |
|---|---|---|
| Navigation v1.2 rev 1.1 | Ran; dock checks pass | Lab 6, 8, 9, 11 |
| Profile v2.0 (six sections) | Ran; theme switching through Appearance passes | Lab 8, 11 |
| Plan v2.0 | Ran (this week only). Interaction checks not written | Lab 9 |
| Training Hub compact panel → full Hub | Ran; panel and expansion checks pass | Lab 11 |
| Progress compact hero (no stage shown) | Ran; "no stage" checks pass | Lab 11 |
| Coach page (timeline, rules-based conversation, shadow policy check, stored decisions) | Compiled. Not yet seen running: the check that opens it was faulty | iOS 261; Lab 13 pending |
| Onboarding, seven pages with Athletic Roster | Compiled. Journey not yet run: the test ran in the wrong order | iOS 261; Lab 13 pending |
| Strength recorder v1.4 | Compiled. Journey test pending | iOS 262; Lab 13 pending |
| Review v1.4 (three sliders) | Written | iOS 263 pending |
| Cycling v1.4 screen (Lab: labelled simulation) | Compiled. Journey test pending | iOS 262; Lab 13 pending |
| Home v2.x | Not started (existing Home in use) | — |
| Strength preparation screen v1.4 | Not started (existing session page in use) | — |

## 2. Capabilities deliberately not built — kept visible

| Capability | Why not | Needs |
|---|---|---|
| Onboarding: sport per session | No stored field | Owner decision on a new field |
| Onboarding: recovery reminder on a rest day | No stored field | Owner decision on a new field |
| Onboarding / Progress: Athlete Evolution stage | No approved stage criteria | Approved criteria |
| Main-sport flag as its own field | Not approved; roster order carries it | Decision if order is not enough |
| Activities without an identifier (walking, bodyweight, mobility, breathing, sauna) | Cannot be stored | Identifiers approved |
| Review: unanswered pain stored as "unknown" | The stored record always holds a pain answer and the Coach acts on it | Storage and Coach decision (v1.4 pending item 4) |
| Strength: skipped set, superset rounds and round rest, added-weight / assisted / timed sets | New data | Schema decision (v1.4 pending items 5, 6) |
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

## 4. E1 safety work — unchanged and still open
No fully verified E1 commit. Open: Progress large-text preview bubble; cancelled owner job of run 252; Delete All Data definition; "Not saved" screen test; large-text truncation; ride-start pathway tests; release accounting; device check; evidence report. E1 commits after `4970c5c7` are not in the Lab branch.
