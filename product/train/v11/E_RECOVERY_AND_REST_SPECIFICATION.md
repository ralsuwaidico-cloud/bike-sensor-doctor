# Training Hub v1.1 — E · Recovery and rest activity specification

Status: **Current Draft — design exploration, pending owner review** · Version 0.1 · 13 Nov 2026 · Level 3
Authorised: audit, architecture, specifications and static mock-ups only. **Production implementation not approved. Onboarding out of scope.**
Nothing was built or run. Code read (read-only): release branch `ios/checkpoint-f-ride`, commit `4e2e9dc`. All figures in the sheets are illustrative.
Nothing in this document exists in the app today. It is a proposal that needs a new, simple record type.

## 1. Rest day

Compact panel: "Rest day — Nothing planned. Recover, or choose an activity." Up to three small shortcuts and "All".
No Start button, no obligation, no streak.

## 2. Recovery session framework (S11)

Identity → Start or Log → optional timer or sequence → Finish → short review.

| Kind | Example | Capture | Stored as |
|---|---|---|---|
| Timer | Breathing, meditation, foam rolling | Phone timer | Activity, start, duration (phone-recorded) |
| Timer with sequence | Stretching, mobility from a saved routine | Timer per movement | As above, plus the routine name |
| Logged afterwards | Sauna, cold exposure, massage | Manual entry: when, optional duration, optional note | Manually entered |

## 3. Wording rules

- No claim that an activity improves recovery, sleep, HRV, inflammation or performance.
- No recommended durations for heat or cold exposure; no guidance without a safety review.
- A logged activity is a report that it was done, nothing more.
- Wellness minutes are never turned into a recovery score.

## 4. Boundaries

Recovery entries go to recovery history. They do not count as completed endurance or strength workouts, do not change
training adherence, and are not Athlete Evolution evidence. Any future link needs separately approved definitions.

## 5. Review

One optional question ("How did it feel?" — three choices) instead of the three training ratings.

## 6. Open points

Whether an easy walk is a recovery activity (timer) or an endurance activity (needs recording, which is not supported);
whether guided content is in scope at all; label overlap between "Recovery" and "Wellness".
