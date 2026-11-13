# Progress v2.1 — Metric Registry (proposal)

Status: **Current Draft — awaiting owner review** · Version 0.1 · 13 Nov 2026 · Level 3
Specification only. Based on a read-only review of release commit `4e2e9dc`; nothing was run. No calculation engine is
authorised. Minimum-evidence numbers and variation bands are deliberately left as "to be approved".

## 1. Purpose

The registry is the single list that decides which metrics Progress may show. A metric appears only if:
(a) its modality is one the athlete selected, (b) that modality is supported, (c) its required inputs exist for this
athlete, and (d) it has enough valid evidence — otherwise its missing-data behaviour applies.

## 2. Fields of every entry

Name · category (family) · discipline and supported modalities · required inputs · source · unit · calculation ·
comparison eligibility · minimum valid evidence · missing-data behaviour · **kind** (capability / exposure / context) ·
implementation status · detail-screen presentation · data confidence.

Status values: **Implemented** (stored and computed in the app today) · **Calculable** (inputs are stored; calculation
or display not built) · **Missing** (an input is not captured) · **Future** (modality not supported).
Missing-data behaviours: **Hide** · **One line** (how to enable) · **Row "Not enough evidence"** (only when the athlete
has the source but too few efforts).

## 3. Endurance — cycling (supported)

| Metric | Family | Inputs · source | Unit | Calculation | Comparable when | Kind | Status | If missing | Detail |
|---|---|---|---|---|---|---|---|---|---|
| Best 20-minute power | Performance | 1 Hz power samples · power meter | W | Highest 20-min mean in a ride | Same power source; power verified; ride contains 20 min | Capability | Implemented (`best20`; verification flag exists) | One line if no power meter; else row | Chart of efforts, used/left out |
| Best power, other durations | Performance | as above | W | Highest mean for the duration | as above | Capability | Calculable (`bestMeanPower`) | Hide | Chart |
| Functional threshold power | Performance | Entered, tested or estimated value with its origin | W | As stored, with origin label | Only tested/entered values; "provisional" never compared | Capability | Implemented as a profile value | Row "no test or entered value" only if power meter present; else hide | Value + origin + date |
| Longest steady ride | Performance | Ride duration · recorder | h min | Longest valid ride | Valid sessions only | Capability (duration) | Implemented, **with the zero-minute defect** | Row | List |
| Power at the same heart rate | Aerobic | Power + HR samples | W at bpm | Not defined yet | Steady rides, similar conditions — rule to be approved | Capability (supporting) | Calculable; method missing | Row "Not enough evidence" | Comparison |
| Power per kg | Performance | Power + current body weight | W/kg | Power ÷ weight | Weight recent | Capability | Missing (no weight history; weight optional) | Hide | — |
| Time in heart-rate zones | Distribution | HR samples; zone setting | h, % | Seconds per zone | Any ride with HR | Exposure | Implemented (5 HR zones) | Hide | Bars |
| Time in power zones | Distribution | Power samples; FTP | h, % | Seconds per zone | FTP known | Exposure | Implemented (7 zones when FTP known) | Hide | Bars |
| Riding time, rides per week | Distribution | Ride records | h, count | Sum / count per week | Valid sessions | Exposure | Implemented, definitions inconsistent | Row | Weekly bars |
| Normalised power, average power per ride | Session | Power samples | W | Standard | — | Context | Implemented | Hide | Ride page, not Progress headline |

## 4. Endurance — supporting context (any sport)

| Metric | Inputs · source | Unit | Kind | Status | If missing |
|---|---|---|---|---|---|
| Resting heart rate | Apple Health | bpm | Context — not capability | Implemented (read) | Hide |
| Heart-rate variability | Apple Health | ms | Context | Implemented (read); belongs to Home, not Progress | Hide |
| Body weight | Entered or Apple Health | kg | Context | Implemented as a current value; no history | Hide dependent metrics |
| VO₂ max | A credible supported source | ml/kg/min | Context / supporting | **Missing** — not read today | Hide (one line in Aerobic) |

## 5. Endurance — running and swimming (future; candidates only)

| Metric | Unit | Kind | Status |
|---|---|---|---|
| Time over a repeatable distance (e.g. 5 km; a set swim distance) | min:s | Capability | Future |
| Pace at the same heart rate (running) | min/km at bpm | Capability (supporting) | Future |
| Longest run / swim | km or m | Capability (duration) | Future |
| Time in heart-rate zones | h, % | Exposure | Future |
| Distance and sessions per week | km, count | Exposure | Future |

Nothing here is implemented: there is no record type, recorder or import for these sports. Cycling power metrics are
never offered to them.

## 6. Strength — resistance training (supported)

| Metric | Inputs · source | Unit | Calculation | Comparable when | Kind | Status | If missing | Detail |
|---|---|---|---|---|---|---|---|---|
| Recorded top set | Logged sets | kg × reps | Heaviest logged set per session | Same exercise | Capability (recorded) | Implemented (`topWeightKg`) | Hide | Session list |
| Estimated 1RM | Logged sets with load | kg (estimate) | Epley: weight × (1 + reps ÷ 30); rep range limited (proposed 3–8) | Same exercise; eligible sets only | Capability (estimate) | Calculable (formula exists in the coach, not in Progress) | Hide — never invented | Chart + formula + limits |
| Same reps, more load / same load, more reps | Logged sets | kg × reps | Direct comparison | Same exercise | Capability (recorded) | Calculable | Hide | Row |
| Repeatable achievement | Logged sets | kg × reps × sessions | A set achieved in more than one session | Same exercise | Capability | Calculable | Hide | Row |
| Strength personal records | Logged sets | kg × reps | Best per exercise | Valid sets | Capability | Not confirmed as existing in Progress in this review | Hide | List |
| Movement-pattern coverage | Exercise patterns | sessions | Sessions per pattern (squat, hinge, single-leg, core, push, pull) | Detailed logs only | Coverage | Implemented (`CoverageReport`) | "no detailed logs" cell | Grid |
| Muscle-group distribution | Catalogue muscle tags | sets | Sets per tagged group | Detailed logs; custom exercises may have no tags | Exposure | Calculable | Hide | Bars |
| Sets, reps, tonnage per week | Logged sets | sets, kg | Sums | — | **Exposure** | Implemented (tonnage); today also used as a "trend" — to be retired for Progress | Row | Weekly bars |
| Sessions, lifting time | Session records incl. quick logs | count, min | Counts | Valid sessions | Exposure (participation) | Implemented | Row | — |

## 7. Strength — bodyweight (partially supported)

| Metric | Unit | Calculation | Kind | Status |
|---|---|---|---|---|
| Best set | reps | Most reps in one set | Capability (recorded) | Calculable (bodyweight flag + reps are stored) |
| Total reps per session | reps | Sum | Exposure | Calculable |
| Added external load | kg | As logged | Capability (recorded) | Calculable |
| Estimated 1RM | — | **Not offered** — no external weight is invented and body weight is not used | — | — |
| Progression to harder variations | — | Needs an exercise-difficulty relation | Capability | Missing |

## 8. Hybrid and Athlete Evolution

| Item | Kind | Status |
|---|---|---|
| Hybrid view | A layout of the two disciplines' own metrics — **no metric of its own, no score** | Design only |
| Training maturity (weeks trained, gaps, typical week) | Exposure | Calculable once the valid-session rule exists |
| Stage, confidence, current evaluation, highest achieved, evaluation history | — | **Missing** — no method approved, no storage |
| Optional reference context | Context | Missing — needs current weight and a tested value; never sets the stage |

## 9. Customisation

Primary metrics per sport come from the registry defaults. Later, the athlete may show or hide **secondary** metrics
from a short list inside each detail screen (not a settings page in Progress). The landing page is not configurable.

## 10. Limits

"Implemented" means the code was seen to store or compute the value, not that it was tested here. Entries marked
"not confirmed" were not found in the files reviewed. All minimum-evidence values and variation bands remain to be
approved.
