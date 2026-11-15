# Cyclift — Onboarding v3.2 — refinement of the existing experience

**Version:** 0.1 · 15 Nov 2026 · **Status:** Design proposal — **Pending Owner Review**. **Implementation NOT AUTHORIZED.** Static drawings only: nothing implemented, compiled or run; no prototype. **ILLUSTRATIVE DESIGN — NOT IMPLEMENTED.**

**Owner direction recorded (15 Nov):** Genesis v3.1 concepts A and B are not selected. Onboarding is to be a refinement of what already works, with one visual language; ordinary fields, segmented controls and lists wherever they are clearest; no dials or instruments unless they are demonstrably more usable. The v2.0 / v3.0 functional research and the v3.1 document are kept unchanged as references.

**Basis of the "existing" drawings:** the onboarding source of build 216 (`OnboardingView`, `OnboardingDraft`, `ProfileEditors`, read-only). They are reconstructions from code, **not screenshots**; the owner's screenshots did not reach this session. Small visual differences from the real screens are possible.

## 1. What exists today (as read in source)
Welcome, then five stages: **A Who you are** (name, three type cards, experience chips, priority, date of birth, weight) · **B Your goals** (goal cards, ★ main goal, effect card with emphasis bar) · **C Your week** (seven-day strip, tap cycles the day, counts, feasibility line, typical ride / strength length, two-sessions switch, equipment, supersets, live preview) · **D Your ecosystem** (device cards, FTP) · **E Your training system** (goals, week, first workout, the approach, Approve).

## 2. Component decisions
| Component (today) | Decision | Reason |
|---|---|---|
| Welcome screen | REFINE | One tap, no input; copy says "cycling and strength" only. Kept as a launch screen, not counted as setup. |
| Top bar: back, progress segments, "n of 5" | KEEP | Clear; becomes "n of 6". |
| Large title + one-line explanation | KEEP | Already confident and readable. |
| Name field | KEEP | Asked once. |
| Date of birth and weight rows with reasons; Apple Health offer | KEEP | Optional, honest, never applied silently. |
| Three athlete-type cards | REDESIGN | They force a label before the athlete has said what they train, take 128 pt, and cannot hold other sports. Replaced by the activity list; cycling + strength selected is the same stored "hybrid" type. |
| Experience chips, Priority control | REFINE | Moved to the goals screen as three compact segmented rows; shown only for the disciplines chosen. |
| Goal cards, two columns, grouped by discipline | KEEP | Strong reference: all goals visible, multi-select, grouped. |
| ★ main goal | KEEP | One tap, clear. Now inside the cell at the right edge (was overlapping the corner). |
| Goal icon boxes and card borders | REMOVE | Three icons repeated ten times add no information; the group title already names the discipline. |
| Effect sentence for the main goal | REFINE | Same text from the planner's rules; moved to the fixed line above Continue so it is always visible and changes in place. |
| Emphasis bar (seven "parts") | REMOVE | An abstraction that can disagree with the real week shown on the next screen. |
| Seven-day strip | KEEP | Clearest presentation of a week. |
| Tap cycles ride → lift → both → rest | REDESIGN | Hidden order; overshooting means cycling round again. Tap now selects the day; a fixed-height editor offers the choices by name. |
| Typical ride / strength length (one value for all days) | REFINE | Length is shown on every day and set per day in the editor. |
| "Two sessions in one day" switch | REMOVE | "Both" is a day option for hybrid athletes; no separate mode. |
| Counts row and feasibility line | REFINE | Weekly total becomes the headline; the planner's existing checks stay as one line beneath. |
| "Coach's proposal" label with restore | KEEP | Extended: days changed by the athlete carry a dot; the label counts them. |
| Equipment chips | KEEP | Needed to offer the right exercises. |
| Supersets switch | REMOVE | Advanced preference; stays in Profile. |
| Live plan preview in the week screen | REMOVE | Duplicates the last screen. |
| Device cards (six) | REFINE | Four lines; three separate sensor cards become one "Bike sensors" line. Real states only, as today. |
| FTP "Don't know / I know it" | KEEP | Honest; no watts guessed. |
| Skip link on devices | REMOVE | The screen states everything is optional; Continue is the skip. |
| Final dashboard: week, first workout, the approach | KEEP | Becomes the blueprint half of screen 6. |
| Goal chips and three stat boxes on the dashboard | REFINE | One line: "2 rides · 3 lifts · 3 h 30 min". |
| Approve / Edit week | REFINE | Approval moves to the review, where every answer can be reopened. |

**Not carried over from v3.0 / v3.1:** activity tiles, constellation, dials, wheels, bars, pebbles, device orbit, the "living form", a primary-activity flag, a "days may move" flag, height.

## 3. The proposal — six screens and a review
| # | Screen | Asks | Changes for single-discipline athletes |
|---|---|---|---|
| 1 | About you | name; date of birth, weight (optional); units | — |
| 2 | What do you train? | activities in three domains | decides which rows appear on 3, 4, 5 |
| 3 | What are you aiming for? | experience per discipline; priority (hybrid only); goals and main goal | only the chosen discipline's rows and goals |
| 4 | Build your week | each day: ride, lift, both, rest; length; equipment | day options and equipment only as relevant |
| 5 | Connect and calibrate | connections; FTP; how plan changes reach the athlete | no FTP or bike devices for strength-only |
| 6 | Your starting point | nothing — Athlete Evolution and the training blueprint | — |
| 7 | Review and approve | approval | — |

Every screen has the same three parts: title, content, and a fixed two-part footer (one explanation line of fixed height, then the button). The explanation changes in place; no control moves when an answer changes.

**One selection language:** list rows end in a check ring (filled = chosen); cells and day tiles show an outline (chosen) and, for goals, a filled ★ (main). Colour is never the only signal.

**Why a seventh screen is kept:** screen 6 explains; approval belongs where every answer is visible and can be reopened. If the owner prefers six, Approve can move to screen 6 with "Review answers" as a link.

## 4. Goals (screen 3)
Functional reference kept. First goal chosen becomes the main goal; ★ on another chosen goal moves it. The line above Continue states what the main goal changes, using the existing rule text (for example Endurance: "Most riding stays easy (Zone 2) with one short tempo block a week; weekly riding time is the measure."). Continue is unavailable until one goal is chosen. No dial.

## 5. Weekly planner (screen 4)
| Need | Design |
|---|---|
| Select a day | tap; outlined tile |
| Change sport | segmented choice in the editor: Ride · Lift · Both · Rest (only the relevant ones) |
| Set duration | stepper in the editor; minutes shown on the day tile |
| Rest day | a choice like any other; tile shows the moon and "rest" |
| Two sessions | "Both" — two length rows, lift first (existing rule) |
| Weekly commitment | headline total, then rides · lifts · rest days |
| Coach's proposal vs the athlete's choices | dot on each changed day; "n days changed by you"; Restore proposal |
| Reverse a change | Undo in the explanation line reverses the last change only |
| Warnings | the planner's existing checks (no rest day, four or more days in a row, two double days, four lifts for a beginner); they advise and never block, except a week with no training day |

**Verification note:** per-day lengths use the per-day minutes already present in stored availability (as read). How the planner behaves with unequal lengths has not been run or tested.

## 6. Activity library (screen 2)
Three domains from Training Hub v1.4: Endurance, Strength, Rest & recovery. Nine relevant activities first; "more" and Search open in place. Labels: **Planned · recorded** (cycling types, gym, bodyweight) or **Interest only** (saved; Cyclift cannot plan or record it yet). Rest & recovery is marked "optional · not a sport"; rest days are set in the week, and sleep is a data source on screen 5. Selecting only unsupported activities is stated plainly and Continue stays unavailable.

## 7. Athlete Evolution (screen 6)
One block: the Singularity (small, unchanged, simplified line drawing here), the G0–G5 track, "You told us" and "Measured" as separate lines.
- **No evidence:** "Baseline pending"; track unfilled; no stage.
- **Returning athlete today:** real recorded counts; "Stage not evaluated yet", because the stage rules are not approved (register 74).
- **Once rules are approved:** the stage Progress shows would be repeated here (drawn as illustrative only). Onboarding never computes a stage.

## 8. Ownership and where answers appear
| Answer | Stored in (existing unless noted) | Later edited in | Read by |
|---|---|---|---|
| Name, date of birth, weight | profile | Profile › Athlete Profile | Coach, zones, loads |
| Units | settings | Profile › App Preferences | all |
| Activities | `sports` (+ identifiers for activities not yet listed — additive); type derived to `trainingMode` | Profile › Training Setup | Plan, Train |
| Experience, priority | `level`, strength experience, `priority` | Training Setup | Plan |
| Goals, main goal | goals, primary goal | Training Setup / Plan | Plan, Progress (measure) |
| Week, lengths | availability, session minutes | Plan | Plan, Home |
| Equipment | equipment | Training Setup | Train, Plan |
| Connections, FTP | settings, profile | Devices & Connections, Performance Settings | Train |
| Plan-change preference | existing adaptation setting | App Preferences / Coach | Coach |
| Approval | plan version 1 | — | Plan, Home |

No new athlete model. Compared with v3.1, two proposed fields are dropped (primary activity, "days may move").

## 9. Open issues
1. **Coach approval (register 69):** the screen says increases always need approval — the owner's decision — but the app today applies some automatically.
2. **Evolution criteria (register 74):** not approved; the screen promises nothing about the next stage.
3. **Activities → type:** today the type is chosen directly and `sports` is read by no engine; deriving the type from activities needs a mapping and tests.
4. **Small iPhone:** screens 2, 3, 4 and 6 scroll. The footer explanation and button stay fixed.
5. **Returning athletes:** when setup is offered again is not defined.
6. **Profile v2.0 visuals** are still pending review; sheet V5 shows placement only.
7. Two existing UI-test failures (ride GPS route samples; Plan edit-and-apply) remain open and uninvestigated.

## 10. Not drawn
Ocean, Forest, Sandstone; Arabic; date picker; search results and the "more" list; error and loading states; Dynamic Type sizes between standard and accessibility.

## 11. Sheets (`sheets/`)
V1 existing and proposed · V2 goals and week interactions · V3 journeys · V4 Arctic, small iPhone, accessibility · V5 where answers appear later.
