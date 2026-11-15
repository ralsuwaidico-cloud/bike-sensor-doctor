# Onboarding v3.0 — "Your Athletic Blueprint" — experience design

**Version:** 0.1 · 15 Nov 2026 · **Status:** New design direction — **Pending Owner Review**. **Implementation NOT AUTHORIZED; not started.** Design and documentation only: nothing implemented, compiled or run; no prototype. **ILLUSTRATIVE DESIGN — NOT IMPLEMENTED.**
Companions: `ONBOARDING_V30_INTEGRATION_AND_OWNERSHIP.md`, `ONBOARDING_V30_ACTIVITY_REGISTRY_AND_COMPATIBILITY.md`. Reference only (per owner): `../v20/` — technical and migration reference, not the approved experience; kept unchanged.
Naming note: the app's current code calls its five-stage flow "onboarding v3" (2 Nov). This document's "v3.0" is the owner's new design direction and is a different thing.
Labels: **[CURRENT]** read in code at `4e2e9dc`, not run · **[PROPOSAL]** designed here · **[FUTURE]** not supported.

## A. Rationale and differences from v2.0
v2.0 mapped the existing questions onto six screens. v3.0 starts from the three domains — **Endurance, Strength, Rest & Recovery** — and ends in a single statement of what Cyclift will and will not do for this athlete.
| | v2.0 (reference) | v3.0 (this proposal) |
|---|---|---|
| Structure | six screens | eight adaptive chapters |
| Domains | Endurance, Strength, Other | Endurance, Strength, Rest & Recovery — rest is a first-class part of the week |
| Activity choice | chip groups | a searchable activity library of icon tiles; recovery activities marked occasional |
| Unsupported-only athletes | stopped at the sports screen | complete setup, get a truthful "no plan" blueprint |
| Coach | not introduced | its own chapter: what it does, asks, and cannot measure, with a sample approval |
| Ending | plan summary | the Athletic Blueprint: rhythm grid plus what appears on Home, Plan, Train, Progress |
| Recovery | not asked | rest days as planned rest; flexibility; pauses explained; no medical inference |
| Look | Profile-style rows | large type, numbered chapter line, tiles, three-lane rhythm grid |

## B. End-to-end journey
Welcome (optional, decision) → **1 Meet your athlete → 2 Your activities → 3 Your direction → 4 Your training setup → 5 Your rhythm & recovery → 6 Your devices → 7 Meet your Coach → 8 Your athletic blueprint** → Approve → Home with the Navigation v1.2 dock. Back on every chapter; answers saved as given [CURRENT behaviour]; relaunch opens a resume page [PROPOSAL]. No dock, no plan and no recorded session exist before approval [CURRENT].

## D. Adaptive question tree
- Ch.2 selection defines three facts: **E** = any endurance activity Cyclift can plan (cycling family today); **S** = any strength activity; **U** = only unsupported or recovery activities.
- Ch.3: emphasis suggested (E only → Endurance; S only → Strength; both → Hybrid) and confirmable. Hybrid → "when time is short, protect". Experience asked per relevant discipline only. One goal per planned sport, one marked main.
- Ch.4: E → where you ride, FTP (known / unknown). Unsupported endurance sports → no questions, shown as saved. S → equipment, exercises to avoid, supersets, split. **Strength-only athletes are never asked for FTP.**
- Ch.5: always. Ride length only if E; strength length only if S; two-a-day only if Hybrid.
- Ch.6: always, skippable. BikeComputer and power meter only if E.
- Ch.7: always.
- Ch.8: plan blueprint if E or S; **if U: chapters 3–5 are skipped and the blueprint is the "no plan" version.**

## E. Screen-by-screen specification
| Ch. | Collects / shows | Required | Rules | Primary action |
|---|---|---|---|---|
| 1 | name; date of birth; height; weight; units; one-line data-use hints | name | empty stays empty; Apple Health weight offered, not applied [CURRENT]; stored on this iPhone | Continue |
| 2 | search field; Endurance, Strength, Rest & Recovery tiles with icon and capability mark | at least one activity | recovery tiles select as "occasional" (dashed), never scheduled as training; search covers the full library; unknown terms are not invented | Continue |
| 3 | emphasis; protect-when-short; experience ("what you tell us"); goals | emphasis; one goal when a plan is possible | declared experience is separate from Athlete Evolution and never overwrites it | Continue |
| 4 | per-discipline setup (tree above) | none | every baseline shows measured / entered / estimated / unknown; unknown FTP is never estimated [CURRENT] | Continue |
| 5 | week cells; lengths; feasibility line; "days can move within the week"; rest-day preference; pause explanation | one training day; hybrid needs one of each [CURRENT] | the line reports and never edits or blocks further [CURRENT]; rest days are worded as planned rest; no clearance or diagnosis is inferred | Continue |
| 6 | "Works today" connections with real state; "Not available" (Cyclift Watch — future) | none | permission requested only on tapping a connection, with what will be read; skip | Continue / Skip |
| 7 | four statements; one illustrative proposal with Approve / Keep; "rules-based, not a chat assistant" | none | sample is labelled illustrative and changes nothing | Continue |
| 8 | rhythm grid (Endurance ●, Strength ■, Rest ○); nine numbered lines: activities, direction, rhythm, endurance and its measurements, strength, rest & recovery, Coach, devices and limits, what appears on Home / Plan / Train / Progress | explicit approval | dry run of the real planner [CURRENT]; nothing active before Approve [CURRENT]; unsupported sports listed as not planned | Approve my first plan / Adjust |
| 8 (U) | saved activities; "No training plan — nothing is invented"; what works now; what happens when support arrives | — | no fake workouts; offer to add an activity Cyclift can plan | Finish setup |

**Exercise limitations and the Coach [PROPOSAL, built on CURRENT exclusions]:** an exercise the athlete marks to avoid is never programmed; a substitute comes only from the exercise library for the same equipment; if no substitute exists the slot is left open and the athlete is asked. Coach never interprets a limitation medically, never suggests treatment, and asks for confirmation before re-introducing an avoided exercise or when a pause for injury ends.

## Journeys drawn (sheets)
B1 hybrid, all eight chapters · B2 library search, Coach approval, blueprint top/lower, Home after approval · B3 strength with recovery preferences · B4 several endurance sports, FTP unknown, no power meter · B5 no devices; only unsupported sports; limited availability · B6 resume; Profile activity change; availability change · B7 six themes · B8 small iPhone, largest text, High Contrast, Arabic, assistive behaviour.
All eight sheets were inspected after final rendering.

## Contradictions found (flagged, not silently resolved)
1. **Coach approval.** Design principle and owner decision of 12 Nov: increases need approval. Code today: `autoAdapt` is on by default and applies some increases automatically; the correction is proposed, not implemented. Chapter 7 shows the intended rule — it must not ship before the correction does.
2. **"AI Coach"** (master instructions) vs rules-based Coach today. Chapter 7 says rules-based.
3. **Unsupported sports.** Training Hub v1.1 registry proposes "Log only" for running, walking, swimming; nothing of the kind exists. v2.0 stopped such athletes; v3.0 lets them finish. v3.0 follows the latest brief; "Log only" stays a proposal.
4. **Walking**: recovery activity or endurance sport — open in the Training Hub recovery specification. Drawn under Endurance, unsupported.
5. **Recovery activities** (timer / log) are proposals in Training Hub v1.1–v1.4; none exists. Selecting one stores a preference only.
6. **Flow length.** App: Welcome + five stages (approved 2 Nov). v2.0: six. v3.0: eight.
7. **Profile v2.0** has no "recovery" section; recovery preferences sit in Training Setup and recovery activities in My Activities — no seventh section is proposed.
8. **Home**: v2.3 pending review; the post-approval Home frame is a placeholder, not a Home design.
9. **Strength tiles**: the app stores one `strength` activity; "Bodyweight" is an equipment setting today. Two tiles need either a new activity value or a mapping (compatibility document).

## L. Risks and unresolved decisions
Risks: eight chapters is longer than today's flow (mitigation: adaptive skipping; most athletes see six or seven); shared editors with Profile; `sports` unused by engines; Plan has no goal or schedule editor of its own; recovery and search features are new work; chapter 7 promises behaviour the code does not yet have; two open test failures (ride GPS-route samples; Plan edit-and-apply); Navigation v1.2 not implemented; tolerant decoding of unknown activities unconfirmed.
Decisions for the owner: 1 eight chapters, and whether a Welcome page precedes them · 2 the starter library (11 tiles) and where Walking belongs · 3 recovery activities selectable before any timer or log exists · 4 "no plan" completion for unsupported-only athletes and its Home state · 5 "days can move within the week" as a stored preference · 6 Bodyweight as an activity or an equipment choice · 7 Coach chapter wording given the automatic-increase behaviour today · 8 resume page · 9 the rhythm grid as the blueprint's signature element.

## M. Milestones — each with its own approval gate
M0 owner review of this package → M1 read-only engineering confirmation (decoding, shared editors, planner reporting, autoAdapt correction status) and test plan → M2 investigate the two open test failures → M3 Coach approval correction (prerequisite for chapter 7) → M4 additive data fields and activity registry with migration tests, no UI → M5 UI Lab prototype of the eight chapters → M6 onboarding in the app → M7 Profile v2.0 on the same data → M8 recovery log/timer and "no plan" Home state → M9 device validation and release decision.
