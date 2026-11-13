# Training Hub v1.1 — D · Strength execution specification

Status: **Current Draft — design exploration, pending owner review** · Version 0.1 · 13 Nov 2026 · Level 3
Authorised: audit, architecture, specifications and static mock-ups only. **Production implementation not approved. Onboarding out of scope.**
Nothing was built or run. Code read (read-only): release branch `ios/checkpoint-f-ride`, commit `4e2e9dc`. All figures in the sheets are illustrative.

## 1. What the data model holds today

A set: repetitions, optional weight in kg, a bodyweight flag, a unilateral flag, optional RPE, done.
An exercise entry: sets, an optional superset group letter, notes, optional rest in seconds.
Not present: timed sets · assisted work · an explicit "bodyweight plus added load" form (weight is "nil = bodyweight
or not recorded") · skipped as a state distinct from not done · rounds or rest rules for a superset · circuits.
Weight changes in fixed steps of 2.5 kg or 5 lb on the logging card. Imperial display exists.

## 2. Preparation (S08)

Name · duration · number of exercises and sets · order · equipment · grouping · one Coach note · Start. Tapping an
exercise opens its detail (prescription, the reason, request an alternative). No buttons under rows.

## 3. Logging (S09, S10)

Top: Pause · elapsed time · Finish. Centre: position ("Exercise 1 of 4"), exercise name, set markers.
Controls: repetitions and load. Primary: Log set. Secondary (text): Skip set · Add set. Below: last performance, next.
A set is stored only by Log; a finished timer logs nothing. After Log: a confirmation line with **Undo** (until the
next log) or **Edit**; no silent overwrite.

### Input methods compared

| | A Stepper | B Wheel | C Dial | D Hybrid |
|---|---|---|---|---|
| Small change (one step) | 1 tap | 1 short drag | 1 small rotation | 1 tap |
| Large change (20 → 60 kg) | 16 taps | 1 long flick, then correction | Several turns | Tap number, type (about 4 taps) |
| Precision when tired or sweaty | High — discrete targets | Medium — easy to overshoot | Low — continuous fine motion | High |
| One-handed | Yes | Yes | Awkward for two dials | Yes |
| VoiceOver | Adjustable value | Native picker | Needs a custom alternative | Adjustable value plus typed entry |
| Large text | Works | Works; takes height | Needs redesign | Works |
| Risk | Slow for big jumps | Accidental scroll while moving the page | Wrong value logged unnoticed | Two ways to do one thing |

Recommendation to test first: **D Hybrid**, as the brief proposes; A is its fallback. The dial is not recommended.
These are design judgements; none has been measured.

### Rest

A strip between the set markers and the controls: remaining time, prescribed time, −15 s, Skip, +15 s. It never covers
Undo or the controls. Adjusting rest changes this rest only, not the plan. End-of-rest notification: only if platform
behaviour is verified.

## 4. Sequencing

| Format | Sequence | Status |
|---|---|---|
| Straight sets | set → rest → next set → next exercise | Supported by today's data |
| Superset | A1 → A2 (no rest unless prescribed) → rest → next round | **Proposed**: today only a group letter exists; rounds and rest rules need a model |
| Circuit | movements in order, rest after the round | Future |
| Timed set | hold for a time, then Log | Future (no time field on a set) |

## 5. Exercise states

| State | Proposed handling | Model today |
|---|---|---|
| Bodyweight only | Load reads "Bodyweight"; no kg entry | Flag exists |
| Weighted bodyweight | "Bodyweight + added load" with a kg value | Ambiguous — needs a clear form |
| Assisted | "Assisted" with the assistance value | Not present — future |
| Dumbbells vs barbell | Unit label "kg each" for paired dumbbells | Not present as data — proposed |
| Unilateral | "each side" | Flag exists |
| Reps only | Load control hidden | Possible |
| Skipped exercise or set | Stored as skipped, never as done | Not distinct today — proposed |
| Changed load or reps | The logged values are what is stored; the prescription is unchanged | Supported |
| Interrupted | Restored as Paused | Supported |
| Incomplete | "Save as incomplete" — only logged sets | Supported (saves done sets) |
| Nothing logged | No record; optional "mark done without details" | Supported |

## 6. Known design defect (self-review)

On S10 the Log button sits lower while the rest strip is showing than when it is not. A primary control must not move
between states; the next round should reserve the strip's space permanently.
