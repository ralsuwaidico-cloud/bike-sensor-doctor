# Progress v2.0 — Phase 1: competitor research and the Athlete Evolution framework (proposal)

Status: **Current Draft** · Version 0.1 · 13 Nov 2026 · Level 3 (product specification)
Source: `docs/cyclift-governance`, `product/progress/PROGRESS_V2_RESEARCH_AND_FRAMEWORK.md`
Companions: `PROGRESS_V2_PHASE0_AUDIT.md` · `PROGRESS_V2_CONCEPTS_AND_FEASIBILITY.md`

**A proposal for review. No rating engine, calculation or threshold was implemented, and none is proposed as fact.**
Where this document says "verified", a public page was read on 13 Nov 2026 (sources in §8). Where it says
"not verified in this pass", the statement is from general knowledge and must be checked before it is relied on.

## 1. The central position

**Athlete Evolution is a product-designed progression system. It is not a scientific classification and must never
be presented as one.** Research gives it structure and limits; it does not supply thresholds for "G3".

Three findings shape everything below:

1. **The best-known research framework classifies by competition level, which Cyclift cannot observe.** McKay et
   al. (2022) define six tiers — Sedentary, Recreationally Active, Trained / Developmental, Highly Trained /
   National Level, Elite / International Level, World Class — from training volume and performance metrics
   (verified). The upper tiers mean national and international competition. Nearly every Cyclift athlete would sit
   in the second or third tier, so those tiers cannot be Cyclift's six generations, and Cyclift's labels must not
   borrow their meaning.
2. **Performance reference tables describe populations; they do not validate a ladder.** Power-to-weight tables
   for cyclists and strength-standard tables for lifters are widely used, but they are descriptive, depend on a
   power meter or a tested lift and on body mass, and treat age and sex unevenly (not verified in this pass —
   to be reviewed source by source in Phase 4).
3. **Every competitor's long-term figure rests on measurements Cyclift mostly does not have** (heart-rate
   variability, VO₂ max estimates, continuous wear). Copying the idea would mean inventing the inputs.

So the proposal is a ladder built from **what the athlete has demonstrated and sustained**, with population
references offered only as labelled context where the measurements are good enough.

## 2. Competitor capability matrix

| Product · concept | Problem it solves | Measurements it needs | Does Cyclift have them? | Documented and defensible? | Use for Athlete Evolution | Original Cyclift interpretation |
|---|---|---|---|---|---|---|
| **WHOOP · WHOOP Age, Pace of Aging, Healthspan** (verified) | One long-term figure for "how am I doing over months" | Nine inputs: sleep hours, sleep consistency, weekly time in HR zones 1–3 and 4–5, weekly strength time, daily steps, resting HR, VO₂ max, lean body mass. Age uses about six months; Pace compares 30 days with six months | Partly: zone time (with HR), strength time. Not sleep consistency as a metric, steps, VO₂ max or lean mass | Inputs are published; the model is proprietary | The **two-speed idea** (slow long-term state, faster recent direction) | "Highest achieved" (slow, permanent) beside "current evaluation" (recent). **No age, no health claim** |
| **Garmin · Training Status, Load Focus** (verified) | "Is my recent training productive?" | Changes in VO₂ max, acute load and HRV status; Load Focus sorts four weeks of load by intensity | No VO₂ max or HRV status. Intensity distribution: yes, with power or HR | Inputs named; method proprietary | Words for direction rather than a number | Direction words per dimension (improving, maintaining, reduced), each tied to a stated measurement |
| **TrainingPeaks · Fitness, Fatigue, Form** (verified) | Long-term load management | A stress score per workout from duration and intensity relative to threshold; 42-day and 7-day weighted averages | Only with a trustworthy threshold (FTP) or a session-load substitute | Published and long established; "Fitness" is training load, **not** capability | Shows the trap to avoid: load is not ability | Load stays in Home / Plan. Progress shows capability evidence |
| **Polar · Cardio, Muscle and Perceived Load; Strain and Tolerance** (verified) | Separate loads for separate systems | HR-based training impulse; power × time; RPE × duration; 7-day against 28-day averages | Perceived load: yes (RPE × minutes). Muscle load: with power | Described publicly | Keeping dimensions separate, with the measurement named | Dimensions never merged into one score |
| **Intervals.icu** (not verified in this pass) | Power progression, estimated FTP, intensity distribution | Power data | Only for rides with power | — | Best-effort power over time as endurance evidence | "Repeatable best efforts" with dates and sources |
| **Hevy** (not verified in this pass) | Strength progression and records per exercise | Sets, load, reps | Yes, from detailed logs | — | Exercise-level evidence for strength | Records require a valid, repeatable measurement (see audit problem B) |
| **Strava** (not verified in this pass) | History, effort and long-term patterns | Activities, HR | Yes | — | History as supporting evidence | History is secondary on Progress |

## 3. What research can and cannot justify

| Question | What can be defended | What cannot |
|---|---|---|
| Training experience | Counting sustained training over time, with pauses excluded | That time served equals ability |
| Endurance capability | Change in the athlete's **own** repeatable power over a set duration, measured with the same equipment | Ranking athletes who have no power meter; treating a single best effort as a level |
| Power relative to body mass | Meaningful for climbing and for comparison, when weight is current | A fair comparison across body types, flat-terrain riders, or when weight is a guess |
| Strength capability | Change in load × reps on the same exercise; an estimated 1RM **with the formula disclosed** and within the rep range where such formulas hold | Comparing exercises with each other; estimates from very high-rep sets; bodyweight exercises treated like loaded ones |
| Consistency | Weeks trained, fairly interpreted (planned rest, illness, travel recognised) | Treating consistency as proof of performance — the brief rules this out |
| Hybrid development | Showing that both disciplines have evidence and direction | A composite number; an average of unrelated measures |
| Age and sex | Stating that references differ by age and sex, and using only references that publish those splits | Cyclift-made adjustment factors |
| Across sports and bodies | Each dimension judged on its own evidence | One universal scale |

## 4. Three ways to determine a generation

| | Option 1 — Evidence ladder | Option 2 — Reference ladder | Option 3 — Evidence ladder with labelled reference context *(recommended)* |
|---|---|---|---|
| A generation means | How much development the athlete has demonstrated and sustained since their own baseline | Where the athlete's measurements sit in published tables | As Option 1; references shown beside it as context, never as the gate |
| Fair to beginners, older athletes, returners, athletes without sensors | Yes | No — needs power, tested lifts and body mass | Yes |
| Recognises an accomplished athlete who is new to Cyclift | Poorly — everyone starts low | Yes | Yes, through a **recognised starting point** when reliable measurements exist |
| Scientific standing | Honest: a product milestone system | Looks scientific; the tables are not validated ladders | Honest, with sources named for every reference |
| Main risk | Not comparable between athletes | Excludes and misranks many athletes | More to explain |

**Recommended: Option 3.**

### How a generation would be formed (structure only — no numbers proposed)

1. Each of the four dimensions has its own **state**: not established · baseline established · developing ·
   established · advanced — judged only on that dimension's evidence.
2. A generation is **not an average**. It follows two things: training maturity (a floor everyone must show), and
   the athlete's **best-supported capability dimension**. A strong cyclist with little strength evidence keeps the
   generation their cycling supports; the lack of strength evidence appears in the profile label and in "Next
   evolution", not as a penalty.
3. Hybrid development never lowers a generation. It can be one of several ways to qualify for a higher one.
4. Each transition needs evidence that is **repeated and sustained**, not a single best day.
5. Every numerical threshold is to be set in Phase 4, with scientific and product review, and published in the app.

## 5. Evidence confidence

| Level | Meaning | Shown as |
|---|---|---|
| **Insufficient evidence** | Not enough valid measurements to say anything | No generation. "Establishing your baseline" with what is needed. **Not G0** |
| **Provisional** | A minimum exists, but it is thin, old, entered rather than measured, or from one kind of evidence | Generation with "Provisional" |
| **Evidence-supported** | Several independent, recent, valid measurements agree | Generation with "Evidence-supported" |
| **High confidence** | As above, sustained over a longer period and across more than one kind of evidence | Generation with "High confidence" |

What decides the level, per dimension: number of independent measurements · how recent · measurement quality
(tested or sensor-recorded above typed-in above assumed) · agreement between them. The counts and periods are
Phase 4 decisions. Missing data lowers **confidence**, never capability.

## 6. Achievement and current evaluation

Recommended, and definable:

- **Highest achieved generation** — permanent, with its date. Never removed.
- **Current evaluation** — what recent evidence supports. When recent evidence is missing, the app says
  **"Not currently evaluated — last evaluated on …"**; it does not demote on silence.
- When recent evidence does show lower capability, wording describes the period, not the person: "Returning",
  "Reduced training since …". Pauses the athlete declared (illness, injury, travel) are named as such.

Both lines can be supported with data Cyclift holds. The recency rule is a Phase 4 decision.

## 7. Terminology

### Assessment of the proposed names

| Proposed | Assessment |
|---|---|
| "Generation", "G2" | Distinctive. Risk: reads as a product or hardware generation, and "G" has no obvious meaning to a newcomer. Alternatives: **Stage 2**, **Orbit II** (fits the singularity), **E2** (Evolution). "Level" reads as gaming; "Tier" collides with the research framework |
| G0 Origin · The Initiate | Clear. G0 must mean "baseline established", never "no data" |
| G1 Foundation · The Builder | Clear and inclusive |
| G2 Development · The Ascendant | Clear |
| G3 Performance · **The Specialist** | **Conflict:** "Specialist" also describes a profile (endurance- or strength-focused). A hybrid athlete at G3 called "The Specialist" is confusing |
| G4 **Integration** · **The Vanguard** | **Two concerns:** "Integration" implies that the fourth generation requires hybrid balance, which the brief rules out; "Vanguard" is a military term, which the brief asks to avoid |
| G5 Mastery · The Apex | Clear; "Apex" suggests an end point — acceptable if mastery is described as maintained, not finished |

### Alternative sets

| Generation | Set 1 — brief, adjusted *(recommended)* | Set 2 — plain, no persona titles | Set 3 — orbital |
|---|---|---|---|
| 0 | Origin · The Initiate | Baseline | Origin |
| 1 | Foundation · The Builder | Foundation | First Orbit |
| 2 | Development · The Ascendant | Development | Ascent |
| 3 | Performance · **The Proven** | Performance | Stable Orbit |
| 4 | **Refinement** · **The Refined** | Advanced | Convergence |
| 5 | Mastery · The Apex | Mastery | Apex |

### Athletic profile (describes training, not worth)

Endurance-Focused · Strength-Focused · Developing Hybrid · Balanced Hybrid · **Not yet determined**.
Proposed basis: the share of training in each discipline over a rolling period, together with which dimensions have
established evidence. No profile ranks above another.

## 8. Sources

Verified on 13 Nov 2026:
- McKay A. K. A. et al., "Defining Training and Performance Caliber: A Participant Classification Framework",
  *International Journal of Sports Physiology and Performance* 17(2), 2022 —
  https://repository.lboro.ac.uk/articles/journal_contribution/Defining_training_and_performance_caliber_a_participant_classification_framework/17108441/1
- WHOOP community, "What is WHOOP Age and Pace of Aging?" — https://community.whoop.com/t/what-is-whoop-age-and-pace-of-aging/466
- Garmin manual, "Training Status" — https://www8.garmin.com/manuals/webhelp/GUID-25EFCCBC-D0EB-4E1B-AE9F-B4B900891C20/EN-US/GUID-44C7BB4B-EFF7-4A42-AC03-8A6AABB94807.html
- TrainingPeaks, "What is the Performance Management Chart?" — https://www.trainingpeaks.com/learn/articles/what-is-the-performance-management-chart/
- Polar manual, "Training Load Pro" — https://support.polar.com/e_manuals/vantage-v3/polar-vantage-v3-user-manual-english/training-load-pro.htm

Identified but **not read** (the pages could not be opened in this pass), to be reviewed in Phase 4:
De Pauw K. et al. (2013), "Guidelines to classify subject groups in sport-science research"; the companion
guidelines for female subject groups; Santos Junior et al. (2021), "Classification and determination model of
resistance training status"; published power-profile and strength-standard tables.

## 9. Limits

No threshold is proposed. No calculation exists. Three competitors were not verified in this pass. The research
papers on cyclist and strength-training classification were located but not read. Nothing here has had scientific
review, which the brief requires before implementation.

## Change log

| Version | Date | Change |
|---|---|---|
| 0.1 | 13 Nov 2026 | First proposal |
