# Progress v2.1 — discipline-agnostic architecture, profile audit and design record

Status: **Current Draft — awaiting owner review** · Version 0.1 · 13 Nov 2026 · Level 3
**Design and specification only.** No production code, UI Lab code, renderer, calculation engine, database, migration,
firmware or TestFlight change. Screens are static drawings with **illustrative sample data**.
Code read (read-only): release branch `ios/checkpoint-f-ride`, commit `4e2e9dc`. Nothing was run.

Builds on (unchanged and still valid): `PROGRESS_V2_PHASE0_AUDIT.md`, `PROGRESS_V2_RESEARCH_AND_FRAMEWORK.md`,
`PROGRESS_V2_VISUAL_DESIGN_SPECIFICATION.md` v0.2 (cinematic singularity, collapsing header, six themes).
Companion: `PROGRESS_V21_METRIC_REGISTRY.md`.

**Not received:** the additional WHOOP Healthspan screenshots referred to in the brief did not arrive with the message
(text only). Section 7 therefore works from the patterns the brief itself lists and from the sources verified on
13 Nov. Please resend the images if you want them checked directly.

## 1. What changes from v2.0

| v2.0 | v2.1 |
|---|---|
| Performance selector: Cycling / Strength / Hybrid | **Hybrid / Endurance / Strength** — only the views the athlete's profile supports |
| Cycling treated as the endurance category | Endurance is the category; cycling is one sport inside it, chosen in onboarding/Profile |
| One headline trend on the landing page | Per-discipline rows, each in its own unit; no combined number |
| "Consistency & training maturity" | **Training maturity**, explicitly labelled exposure, separate from capability |
| Trend arrows implied by the chart | Interpretive labels (Improving / Maintaining / Reduced / Not enough evidence) only with a documented rule |
| 4 / 8 / 12 / 16 weeks | Same, plus **All** (since baseline); ranges longer than the history are disabled, never stretched |

Unchanged: singularity, scroll-linked collapse, section order A–F, G0–G5 provisional notation, evidence ladder,
"current evaluation" separate from "highest achieved", no thresholds, no scoring engine.
Addition to the scroll rule: when collapsed, the page content moves up with the scroll — no hero-sized empty spacer remains.

## 2. Information architecture

```
Progress (landing)
 A  Athlete Singularity ............ stage · name · profile · confidence        → Athlete Evolution details
 B  Evolution since baseline ....... one row per SELECTED discipline + training maturity (+ hybrid)  → detail
 C  Performance development ........ [Hybrid] [Endurance] [Strength]  ·  4/8/12/16 wk/All
        Hybrid view ............... one row per discipline, own unit            → Hybrid development
        Endurance view ............ headline measure of the primary sport       → Endurance development
        Strength view ............. headline lifts                              → Strength development
 D  Next evolution ................. demonstrated / evidence needed / not measurable → Evolution details
 E  Evolution timeline ............. entry                                       → Evolution details (timeline)
 F  Records & history .............. secondary entry

Endurance development   [All endurance] [sport] [sport]…   (sport chips only for selected, supported sports)
   Performance (capability) · Aerobic development (supporting) · Training distribution (exposure) · Longitudinal
Strength development    [modality]…
   Exercise by exercise (capability) · Recorded bests · Movement patterns · Muscle groups · Training volume (exposure)
Metric detail           what it is · how it is compared · why the label · efforts used and left out · long-term trend
```

Rules:

1. **Disciplines are fixed (Endurance, Strength); sports and modalities are data.** Screens are assembled from the
   Metric Registry for the athlete's selected, supported sports. No screen is written for "cycling" or "lifting".
2. **A view appears only if the athlete selected that discipline.** A strength-only athlete has no Endurance tab and no
   "insufficient" endurance row; an endurance-only athlete has no Strength tab.
3. **Performance is never combined across sports or disciplines.** "All endurance" lists each sport in its own unit and
   combines only what shares a definition (time, heart-rate zone time).
4. **Three kinds of information, always labelled:** capability · training exposure · context.
5. **A metric with no supported source is not drawn as a card.** At most one quiet line that says how to enable it.
6. Records and session history stay in section F.

Images (`design-v21/`): `PE1` landing + Hybrid development · `PE2` Endurance (cycling today; running and two-sport
screens are marked illustrations) · `PE3` Strength, loaded-exercise and bodyweight-exercise detail · `PE4` metric
explanation, long-term trend, Athlete Evolution details · `PE5` first-time, partial data, strength-only, returning ·
`PE6` Ocean, Forest, Sandstone, High Contrast. Obsidian and Arctic are in PE1–PE5.

## 3. Audit — athlete type, sports and Profile today

| Question | What exists in the code today | Where |
|---|---|---|
| Athlete type | `TrainingMode`: **cycling / strength / hybrid** (shown as "Cycling", "Strength", "Hybrid Athlete"). Asked in onboarding; editable in Profile › type and experience | `Hybrid.swift`, `OnboardingView.swift`, `ProfileEditors.swift` |
| Selected sports | `RiderProfile.sports`: road cycling, indoor cycling, mountain bike, commuting, running, swimming, strength, other. Default "road cycling". Editable only in Profile › "Other sports". **Not asked in onboarding and not read by the plan, coach or Progress** — it is a stored list with no effect | `Models.swift`, `ProfileView.swift`, `ProfileSections.swift` |
| Primary vs secondary | No sport-level primary/secondary. Hybrid athletes have a priority (balanced / cycling / strength) and a hybrid goal | `RiderProfile.priority`, `HybridGoal` |
| Experience | Separate per discipline: cycling level and strength experience (beginner / intermediate / advanced each) | `RiderProfile.Level`, `StrengthPrefs.Experience` |
| Goals | Goal list split into cycling goals (endurance, power, sprint, climbing, event) and strength goals (muscle, strength, stamina, maintain); an older single goal field also remains | `Rc3Engine.swift` `GoalID`, `RiderProfile.Goal` |
| Measurement sources | Sensor hub with source, timing and quality per measurement; power meter, heart rate (strap or watch); Apple Health reads: weight, resting HR, HRV, sleep. **VO₂ max is not read.** | `SensorHub.swift`, `HealthReads.swift`, `Provenance.swift` |
| Stored activities | Two record types only: a cycling ride record and a strength session. **There is no record type for running, swimming or any other endurance sport.** Apple Health import accepts cycling and strength workouts and ignores everything else | `Models.swift` `RideRecord`, `Hybrid.swift` `StrengthSession`, `HealthImport.swift` |
| Strength detail | Sets with reps, weight, a bodyweight flag and optional RPE; 165 built-in exercises, each with a movement pattern and muscle tags (41 bodyweight-only); quick logs have no sets | `Strength.swift`, `Resources/exercises.json` |

Support status of selectable activities:

| Activity | Status | Reason |
|---|---|---|
| Cycling (road / indoor / MTB / commuting) | **Supported** as one sport ("cycling"); the four sub-types are labels only | One ride record, no per-type logic |
| Resistance training | **Supported** | Detailed logs, catalogue, planner |
| Bodyweight training | **Partially supported** | Logged inside strength sessions with the bodyweight flag; no separate modality or progression view |
| Running, swimming | **Future** | Selectable as a label only; nowhere to record or import them |
| "Other" | Label only | — |

Onboarding v2 specification (planned, not implemented) says: sports are limited to cycling and strength for coaching;
other activities may be named as "also do" at logging level; "Selected sports" and per-sport experience are mandatory
profile items. That agrees with this brief's direction and with the audit: **the selector should reuse and extend the
existing `sports` list and `TrainingMode`; no new, duplicate question is needed.**

Gaps to close (proposals — each is a schema or onboarding change needing its own impact assessment and approval):

1. `TrainingMode` wording and meaning: "Cycling" → Endurance. Renaming the label alone would breach "do not rename
   Cycling to Endurance while keeping cycling-only logic"; the planner, coach and plan screens are cycling-specific
   throughout (`includesCycling`, ride/lift day kinds, cycling budget). The rename must follow, not precede, a sport model.
2. Give `sports` meaning: discipline per sport, primary/secondary, support status. Today it has none.
3. Remove "strength" from the sports list (it is a discipline, already expressed by `TrainingMode`).
4. A general endurance activity record (or a sport field on the existing one) before any second endurance sport.
5. Ask selected sports in onboarding (Onboarding v2 stage 3) instead of only in Profile.

Conflict noted: Master Project Instructions §1 say "supports cycling, strength training and hybrid athletes, with an
extensible architecture for additional endurance … disciplines". The code is not yet extensible in that sense (item 4).

## 4. How labels are decided (proposal)

An interpretive label is shown only when **all** of these hold; otherwise the label is "Not enough evidence".

1. The metric's registry entry defines a comparison (which efforts are comparable).
2. Both periods compared contain at least the registry's minimum number of valid efforts.
3. The difference is larger than that metric's normal session-to-session variation.

| Label | Meaning |
|---|---|
| Improving | Recent period better than the comparison period by more than normal variation |
| Maintaining | Within normal variation |
| Reduced | Worse by more than normal variation — only with recent comparable evidence, never from absence of data |
| Not enough evidence | Any condition above fails |
| Provisional | A value exists but is below the minimum evidence for a label |

The minimum counts and variation bands per metric are **not defined in this document** and are not approved; the sample
screens use placeholders. They are a prerequisite (dependency E3). Existing code to reconcile: the strength
"progression trend" compares **tonnage** of the last two sessions with the two before (±3 %). That treats volume as
progress and conflicts with this brief; it must not feed Progress labels.

Comparison periods are per metric (registry column "Comparison"): for example period-against-previous-period for
repeatable efforts, and recent-against-baseline for development since baseline. No blanket 30-day / 6-month rule.

## 5. Known problems — how each is corrected before any generation engine uses the data

No production change in this phase. Each item is a prerequisite.

| Problem (from the Phase 0 audit) | Correction specified |
|---|---|
| Seconds-long rides count as completed sessions | Introduce one definition of a **valid session** (recorded, above a minimum duration, and for a planned session a minimum share of the plan). Records are kept, not deleted; invalid ones are excluded from completion, consistency and evidence. Note: the Apple Health import already ignores workouts under 60 seconds — the recorder path has no equivalent rule. Thresholds are an owner decision |
| "Longest time" record can show 0 minutes | Records use the same validity rule; durations display in h/min/s so a short value can never read as zero |
| Training totals use different definitions | One glossary: sessions = valid completed sessions; time = recorded duration; planned = scheduled. Every total names which one it is |
| Large empty-data cards | Registry "missing-data behaviour": hide, or one line. No empty charts |
| Repeated 4/8/12-week checkpoints | Replaced by the range control and the evaluation timeline |
| History overemphasised | History and records live in section F only |

## 6. Athlete Evolution — dependencies by modality

| # | Dependency | Applies to |
|---|---|---|
| E1 | Valid-session and valid-record rules (section 5) | All |
| E2 | Sport model: discipline, primary/secondary, support status; general endurance record | Any sport beyond cycling |
| E3 | Per-metric comparison rule, minimum evidence and variation band | Every capability metric |
| E4 | Capability evidence defined per sport, without requiring a power meter: cycling with power (20-min power); cycling without power (duration- and heart-rate-based evidence, lower confidence); running and swimming (time over a repeatable distance) — **not yet designed in detail** | Endurance |
| E5 | Capability evidence per strength modality: loaded lifts (estimated 1RM or same reps with more load); bodyweight (repetitions, harder variations) — no invented external load | Strength |
| E6 | Rule for combining dimensions into a stage that is not an average and does not let a missing measurement lower the stage | All |
| E7 | Storage for evaluation history, highest achieved, body-weight history; optional VO₂ max read | All |
| E8 | An approved methodology and thresholds | **Not authorised** |

The five dimensions stay separate everywhere: endurance capability · strength capability · training maturity · hybrid
development · evaluation confidence. No composite score.

## 7. Competitor patterns — what is taken and what is not

| Pattern (source) | Cyclift use | Not taken |
|---|---|---|
| One strong identity visual with supporting measures explained beneath (WHOOP Healthspan, as described in the brief) | Singularity, then evidence rows | WHOOP Age, Pace of Aging, their graphics |
| Recent versus long-term comparison (WHOOP: 30 days against 6 months) | Period-against-period and recent-against-baseline, chosen per metric | A fixed 30-day/6-month rule; any grading thresholds |
| Change indicators beside each measure (WHOOP) | Text labels with a documented rule | Arrows drawn from chart slope |
| Heart-rate-zone distribution, strength activity time (WHOOP) | Zone time and sets per week, labelled exposure | Using them as capability |
| VO₂ max, resting HR, body composition as context (WHOOP) | Resting HR as optional context; VO₂ max only from a supported source | Health or ageing claims |
| Status built from several inputs with a plain-language state (Garmin Training Status) | Stage with confidence and "what is missing" | A single opaque status |
| Long-window fitness trend (TrainingPeaks CTL 42 d / ATL 7 d) | Not used in Progress — load belongs to Home | Load charts in Progress |
| Separate cardio, muscle and perceived load (Polar) | Disciplines kept separate | — |

WHOOP rows rest on the brief's description and the 13 Nov research; the screenshots themselves were not seen.

## 8. Acceptance criteria (for review of this design; UI Lab is not authorised)

1. No screen title, selector or rule names cycling or lifting as a permanent category.
2. A view or row exists only for a discipline and sport the athlete selected **and** that is supported.
3. No number combines watts, pace, distance, load or minutes across sports or disciplines.
4. Every metric on screen has a registry entry with source, unit, method, comparison, minimum evidence, missing-data
   behaviour, kind and status.
5. Every interpretive label can be traced to the rule in section 4; "Reduced" never appears from missing data.
6. Estimated values say "estimate" and name the method; bodyweight exercises never show a load estimate.
7. Quick logs appear only as participation.
8. Unsupported sensors produce no card; at most one line.
9. A range longer than the athlete's history is disabled; no points are interpolated.
10. An athlete without a supportable stage sees "Establishing your baseline" and no generation.
11. Running, swimming or any unimplemented sport is never shown as available.
12. All v2.0 criteria for the singularity and collapsing header still apply.
13. All six themes render every screen type; High Contrast uses line and shape.

## 9. Open questions

1. May the discipline label change ("Cycling" → "Endurance") wait for the sport model (section 3, gap 1)? Recommended: yes.
2. Order of sports after cycling — is running the next intended endurance sport?
3. Is bodyweight training a separate strength modality in Profile, or a property of exercises (as stored today)?
4. Who sets the per-metric minimum evidence and variation bands (section 4)?
5. Landing page length: with four rows in B and two in C it no longer fits one screen on a standard iPhone. Accept, or
   reduce B to one line per discipline?

## 10. Limits

Read from code and documents; nothing executed. The audit covers the files named and is not exhaustive for every
editor screen. Sample values, counts and labels in the images are invented. No behaviour, accessibility or small-screen
fit has been verified; small-iPhone versions of the v2.1 detail screens were not drawn in this round.
