# Training Hub v1.1 — H · UI review checklist and self-review

Status: **Current Draft — design exploration, pending owner review** · Version 0.1 · 13 Nov 2026 · Level 3
Authorised: audit, architecture, specifications and static mock-ups only. **Production implementation not approved. Onboarding out of scope.**
Nothing was built or run. Code read (read-only): release branch `ios/checkpoint-f-ride`, commit `4e2e9dc`. All figures in the sheets are illustrative.

## 1. Criteria per sheet

| Sheet | Accept when |
|---|---|
| S01 | Symbol is recognisable at dock size in all themes; states read without changing the symbol; no red dot |
| S02 | One primary session and one Start; nothing a second large button; fits a small iPhone without scrolling |
| S03 | Only the athlete's activities; no calendar; "Explore all" reachable |
| S04 | Every activity shows Record / Timer / Log only; search finds synonyms; unsupported never looks recordable |
| S05 | Essential values readable at a glance; lost sensor shows "—" with a reason; GPS-not-ready differs from zero |
| S06–S07 | No cycling values on other sports; no map where GPS is meaningless; future screens labelled |
| S08 | Order, equipment, grouping visible; one Start; no per-row buttons |
| S09 | Reps and load changeable one-handed; value unambiguous; alternative to gestures exists |
| S10 | Log is explicit; Undo present; rest never blocks; superset follows the prescription |
| S11 | Optional in tone; no effect claims; manual entries labelled as entered |
| S12 | Three ratings in one row on a standard iPhone; unanswered visibly unanswered; vertical on small |
| S13 | Offered actions match what was recorded; Save and Discard never equal; failure keeps the data |
| S14 | Each step has one purpose and one primary action |
| S15 | Legible in six themes, at large text and on a small iPhone |

General: 44 pt targets · Dynamic Type · VoiceOver labels and adjustable values · Reduce Motion · no colour-only
meaning · no hidden destructive gesture · no moving targets · nothing behind the dock · no horizontal overflow.

## 2. Self-review — problems found in these drawings

| Sheet | Problem |
|---|---|
| S01 | Ascent reads as "expand", and the expanded state already uses a chevron. Orbit can read as "record" or "sync". Pulse is close to a heartbeat. Vector C is busy at dock size |
| S02 | With two sessions the activity shortcuts disappear — inconsistent with the one-session panel |
| S03 | The hybrid hub is longer than one screen; "Explore all" is below the fold |
| S04 | Right-hand status words may be taken for buttons. Icons for indoor cycling, foam rolling and massage are unclear at 22 pt. The list is cut at the bottom of the frame (it scrolls) |
| S05 | Seven live values plus the interval strip is dense for riding. Finish and Pause are the same size |
| S07 | Swimming shows two empty values — arguably it should be a timer screen with no metric grid at all |
| S09 | The dotted underline that signals "tap to type" may not be understood. The keypad sheet hides the Log button |
| S10 | **The Log button moves down when the rest strip appears** — breaks the no-moving-targets rule; must be fixed |
| S12 | No scale meets 44 pt by tap alone. Intensity and effort wording may not be distinguishable |
| S13 | The complete-workout sheet still has an "Effort" row, duplicating the review |
| S15 | Large text is approximated by scaling; real Dynamic Type behaviour is not shown |
| All | Layouts are drawn at 393 × 852 and 375 × 667; the current standard simulator is 402 pt wide. Nothing has been measured on a device |
