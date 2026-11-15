# Onboarding v2.0 — six-screen specification, adaptive journeys and Profile-change impact contract

**Version:** 0.1 · 15 Nov 2026 · **Status:** Current Draft — design for owner review. **Implementation NOT AUTHORIZED; not started.** Designed only: nothing implemented, compiled or run. **ILLUSTRATIVE DESIGN — NOT IMPLEMENTED.**
Companions: `ONBOARDING_V20_AUDIT_AND_FIELD_MATRIX.md`, `ATHLETE_MODEL_AND_MIGRATION.md`, `../../profile/v20/PROFILE_V20_DESIGN.md`. Navigation v1.2 and Profile v2.0's six sections are used unchanged. The current five-stage onboarding is not modified.
Labels: **[FACT]** in the app today · **[NEW]** proposed · **[FUTURE]** unsupported.

## 1. The six screens
One primary action per screen; a six-segment progress bar; Back on every screen after the first; no dock until a plan is approved.
| # | Screen | Collects | Required | Rules | Lands in Profile |
|---|---|---|---|---|---|
| 1 | About you | name; date of birth; height; weight; units | name only | empty optional values stay empty; Apple Health weight offered, not applied [FACT]; height and units asked here [NEW] | A › Personal details; E › Units |
| 2 | Your sports | activities (multi-select, grouped Endurance / Strength / Other, each with its capability mark); classification (suggested, confirmable); balance (hybrid); experience per relevant discipline | at least one activity Cyclift records today | selecting only unsupported activities stops truthfully — no plan can be built [NEW]; classification suggested: endurance-recordable only → Endurance, strength only → Strength, both → Hybrid; the athlete may override | A › My activities, Athlete type, Experience, Hybrid balance |
| 3 | Your goals | goals for the confirmed type; one main | at least one | today's ten goals [FACT]; with goals in both sports the screen says the main goal leads and balance decides when time is short; no goals offered for unsupported sports | Plan (linked from B › Goals) |
| 4 | Build your week | days; session lengths; two-a-day (hybrid); equipment; exercises to avoid [NEW here]; supersets | one training day; hybrid needs one of each [FACT] | the feasibility line reports time, rest and spacing and **never edits the athlete's days** [FACT] | Plan (schedule); B › Equipment & restrictions, Strength preferences |
| 5 | Connections and baselines | only connections relevant to the type and verified today; FTP (endurance types); max and resting HR with source [NEW here] | nothing; Skip | each baseline shows measured / entered / estimated / unknown; nothing is filled to look complete | D; C |
| 6 | Your first plan | review: classification and activities; main goal; time offered vs time used; week; balance; equipment assumed; device data; limits | explicit Approve | dry run of the real planner [FACT]; no plan is active before Approve [FACT]; "Adjust my week" returns to 4 | plan state Approved |

**Truthful fallbacks where the planner cannot do what was asked:** unsupported activities → "saved, not planned"; several goals in one sport → the main one shapes the plan, others are kept; unknown FTP → effort and heart-rate guidance, never watts; "Not sure" equipment → bodyweight until confirmed [FACT].

## 2. Adaptive journeys (sheets O1–O5)
| Athlete | Screen 2 asks | Screen 3 shows | Screen 4 shows | Screen 5 shows |
|---|---|---|---|---|
| Hybrid | balance, riding and lifting experience | cycling, strength, general | ride and lift lengths, two-a-day, equipment | all connections; FTP; heart rate |
| Endurance | riding experience | cycling, general | ride length only | all connections; FTP; heart rate |
| Strength | lifting experience | strength, general | lift length, equipment | Health, Watch, HR sensor; heart rate; **no FTP, no bike devices** |
| Multi-activity | as the supported subset dictates | as above | as above | as above; unsupported choices listed under "Limits to know" on screen 6 |
| No devices | — | — | — | every row "Not configured"; baselines unknown or estimated; plan still offered |
| Interrupted | resume page lists finished steps and continues at the next [NEW]; stored answers are read back, not re-asked [FACT] |

## 3. Onboarding ↔ Profile
Every value has one home (field matrix §2). The Profile editor and the onboarding screen read and write the same stored value [FACT for today's fields]. One sport selector, one experience model, one equipment list. **Interim route [required]:** goals and weekly schedule are Plan-owned in Profile v2.0, but Plan has no editor of its own today; until it does, Profile › Training Setup › Goals / Training schedule opens the existing editors, labelled "Managed in Plan". No capability disappears.

## 4. Profile-change impact contract
Sequence for anything that affects an approved plan: **Edit → Validate → Impact preview → Athlete approval → Apply → Undo where safely supported.** [FACT] preview, approval, versioned plans and an undo that can be refused already exist for profile changes.
| Change | Applies to | Preview shows | History | Undo |
|---|---|---|---|---|
| Activities / classification | future sessions from the next unstarted week | type change, sessions per sport before → after | untouched | offered while the earlier version can be restored exactly; otherwise refused with the reason |
| Experience | future recommendations | sessions whose difficulty or volume changes | untouched; **Athlete Evolution in Progress is not edited** | as above |
| Weekly availability | future schedule | proposed reschedule | completed, missed and skipped sessions keep their status | as above |
| Equipment / restrictions | upcoming strength workouts | affected workouts and substitutions | recorded workouts untouched | as above |
| Weight | calculations from now on | none (no plan change) | past records keep the weight of their day | edit again |
| FTP / HR values / zone method | zones and targets from now on | changed zones; sessions whose targets change | past sessions keep the zones they were ridden with; source and date recorded | edit again; plan change as above |
| Device disconnected / forgotten | current sensor availability | none | measurements already recorded stay | reconnect |
| Goals | future plan | emphasis before → after | untouched | as above |
| Units, name, appearance | display | none | — | edit again |
Declining a preview leaves both the plan and the edited value unchanged. **Open design issue:** whether the planner can list per-workout substitutions for the preview (drawn on O6) must be confirmed against the code.

## 5. Risks and blockers
1. Shared editors: screens 1–4 reuse code Profile depends on; changing them changes both.
2. `sports` has no consumer; the new selector must not imply the plan uses unsupported choices.
3. Classification derived from activities can disagree with the stored type for existing athletes — never auto-changed.
4. Plan has no goal or schedule editor of its own (interim route).
5. One effective goal per sport.
6. Navigation v1.2 is a design baseline only; the app still has five numbered pages and a Profile tab.
7. Two open test failures (ride GPS-route samples; Plan edit-and-apply — the latter touches the very preview-and-apply flow this contract relies on).
8. Tolerant decoding of unknown activities is unconfirmed.
9. Height, units and HR baselines in onboarding, the resume page and "Walking" are new work.
10. No account, cloud or restore exists; none is assumed.

## 6. Acceptance criteria (for a later implementation, not met by drawings)
A1 a value entered in onboarding reads identically in Profile and back, with one stored copy · A2 six screens, each with one primary action · A3 questions shown only for relevant disciplines · A4 every activity shows a capability status true for that build · A5 only-unsupported selection cannot produce a plan · A6 stated availability is never altered by the app · A7 no plan active before explicit approval · A8 no optional baseline is invented · A9 relaunch at any screen resumes with answers intact · A10 existing installations open with data, plan and history unchanged · A11 plan-affecting edits never apply without approval; decline changes nothing · A12 history is never rewritten · A13 undo is offered only when exact restore is possible · A14 six themes, small iPhone, largest text, High Contrast pass; Arabic only when the app supports it · A15 no existing capability lost (Profile v2.0 function map).

## 7. Proposed milestones — each needs its own approval
| # | Milestone | Output | Gate |
|---|---|---|---|
| M0 | Owner review of this package | decisions in §8 | owner |
| M1 | Read-only engineering confirmation | answers to open points (decoding, substitution preview, shared-editor impact); test plan | owner |
| M2 | Data-model additions behind no UI | additive fields, mapping, migration tests | owner; tests green without weakening |
| M3 | UI Lab prototype of the six screens | isolated prototype, no production change | owner design acceptance |
| M4 | Onboarding v2.0 in the app | six screens on the shared editors | owner; simulator evidence |
| M5 | Profile v2.0 sections A–C on the same data | — | owner |
| M6 | Impact previews for the new change types | — | owner |
| M7 | Physical-device validation and release decision | — | owner |
Investigating the two open test failures should precede M2.

## 8. Decisions for the owner
1. Six screens replacing the current Welcome + five stages (keep a Welcome page or not).
2. Activity list and groups; adding Walking; wording of the capability marks.
3. Classification suggested and confirmable (as drawn) or fixed by the choices.
4. Stop when only unsupported activities are chosen (as drawn) or allow completing setup without a plan.
5. "Endurance" as the display label for the stored `cycling` type.
6. Resume page (as drawn) or reopen directly on the saved screen (today).
7. Heart-rate baselines and exercise restrictions inside onboarding, or Profile only.
8. One "Confirm your activities" prompt for existing athletes.
9. Interim route for goals and schedule until Plan owns them.

## 9. Sheets (`sheets/`)
O1 hybrid journey · O2 endurance · O3 strength · O4 multi-activity and no devices · O5 interrupted and resume · O6 Profile edit with plan impact · O7 six themes · O8 small iPhone, large text, High Contrast, Arabic.
