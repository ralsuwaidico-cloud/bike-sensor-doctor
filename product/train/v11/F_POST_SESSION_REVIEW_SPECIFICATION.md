# Training Hub v1.1 — F · Post-session review specification

Status: **Current Draft — design exploration, pending owner review** · Version 0.1 · 13 Nov 2026 · Level 3
Authorised: audit, architecture, specifications and static mock-ups only. **Production implementation not approved. Onboarding out of scope.**
Nothing was built or run. Code read (read-only): release branch `ios/checkpoint-f-ride`, commit `4e2e9dc`. All figures in the sheets are illustrative.

## 1. What exists today

A check-in after a session stores **performance** (1–10, relative to expectations), **effort** (1–10, session RPE),
a pain level with an area, and a note. The rules-based Coach reads it. **Intensity is new.** Any change of scale
affects those rules and stored history, so it needs an impact assessment before adoption.

## 2. Architecture (separate from the interface)

`Finish → Summary → Save → Saved → optional review → Done`

The record is saved **before** any question. Skipping, dismissing or closing the review loses nothing; feedback can be
added later from the saved workout. The review is stored as an attachment to the record with its own timestamp.

## 3. Three ratings (provisional terms)

| Rating | Question | Ends |
|---|---|---|
| Intensity | How demanding was the session itself? | Low … Very high |
| Effort | How hard did you have to work? | Easy … Maximal |
| Performance | How did you do against what you intended? | Below … As expected … Above |

Intensity and effort will often move together; they are not treated as independent measurements, nothing is derived
from one to another, and no combined score is formed. Whether athletes can tell them apart is a question for testing.

## 4. Control (S12)

Three arc instruments in one row; drag along the arc or tap a segment; a − / + stepper is the accessible alternative
and the VoiceOver adjustable action. **Unanswered is shown as dashes and "Not answered" — no default value.**
Small iPhone and large text: the three stack vertically.

## 5. Scale options

| | 5-point words | 7-point | 1–10 |
|---|---|---|---|
| Thinking effort | Lowest | Medium | Highest |
| Precision | Coarse | Finer | Finest |
| One-finger target (on a 110 pt arc / full-width row) | about 30 pt of arc per step | about 22 pt | about 23 pt per box |
| Fits today's stored scale | Needs a mapping | Needs a mapping | Yes for effort and performance |
| Meets 44 pt by tap alone | No — relies on drag and stepper | No | No |

None meets the 44 pt target by direct tap at this size; every option needs the drag gesture plus the stepper. The
five-point version is the easiest to answer; the 1–10 version is the only one compatible with stored data without a
mapping. This trade-off is the main decision in this document.

## 6. Body and Coach

"How does your body feel?" — three common choices and one "Discomfort or other…" that opens the rest; multiple
selection; a discomfort choice asks only location and Mild / Moderate / Strong. No diagnosis. Severe pain, chest pain
or breathing trouble shows a line directing the athlete to medical help.

"Anything your Coach should know?" — a few quick choices and an optional note. Voice capture is a future possibility,
not designed. **The present Coach is rules-based and reads only defined fields**; a free-text note is stored and shown
to the athlete, and is not interpreted unless a rule is written and approved.

## 7. Storage (proposal)

Per rating: value or "unanswered", scale version, timestamp. Body selections as coded choices. Note as text. All
labelled subjective and athlete-entered; never presented as a physiological measurement.
