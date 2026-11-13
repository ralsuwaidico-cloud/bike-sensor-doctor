# Training Hub v1.1 — G · Design decision register

Status: **Current Draft — design exploration, pending owner review** · Version 0.1 · 13 Nov 2026 · Level 3
Authorised: audit, architecture, specifications and static mock-ups only. **Production implementation not approved. Onboarding out of scope.**
Nothing was built or run. Code read (read-only): release branch `ios/checkpoint-f-ride`, commit `4e2e9dc`. All figures in the sheets are illustrative.

## 1. Approved by the owner (direction, not production)

| # | Decision |
|---|---|
| A1 | The centre button stays the global entry and gets one permanent Cyclift symbol; states do not change its identity |
| A2 | Compact panel first, expanding to the full hub |
| A3 | Recording is a dedicated full-screen experience |
| A4 | Onboarding is assumed complete and is out of scope |
| A5 | An extensible activity registry; profile, category, activity, capability, prescription and record stay distinct |

## 2. Unresolved — owner decisions

| # | Question | Options |
|---|---|---|
| U1 | Train symbol | Pulse · Orbit · Ascent · Vector C · none of these |
| U2 | Does Start on a planned workout open Preparation or go straight to recording? | Preparation (drawn) · direct |
| U3 | Input method to prototype | D Hybrid (recommended) · A Stepper |
| U4 | Review scale | 5-point words · 1–10 (matches stored data) · 7-point |
| U5 | May an active session be minimised? | Yes · no |
| U6 | Filter labels | Merge Recovery and Wellness, or keep both |
| U7 | Is an easy walk recovery (timer) or endurance (needs recording)? | — |

## 3. Design hypotheses (untested)

H1 a rising panel is as reliable as today's animation-free hub · H2 hybrid input is fastest and least error-prone ·
H3 athletes can distinguish intensity from effort · H4 three ratings are quick enough to be answered · H5 one-row
status words (Record / Timer / Log only) are understood · H6 the cockpit's seven values are readable while riding.

## 4. Proposed dependencies (not approved scope)

P1 activity registry and its storage · P2 a single Train presentation owner · P3 session-level source labels ·
P4 a record type for recovery and wellness entries · P5 superset model with rounds and rest rules · P6 explicit
skipped state; bodyweight-plus-load and assisted forms; timed sets · P7 a visible save result with retry ·
P8 review stored as an attachment, with a scale version · P9 final icon drawing.

## 5. Technical dependencies and blockers

B1 shared presenter repair unfinished · B2 Ride-screen ownership rule (RA-01) · B3 ride restoration and background
behaviour unverified · B4 simultaneous ride and strength sessions unverified · B5 valid-session rule (seconds-long
rides) from the Progress audit · B6 check-in scale used by Coach rules · B7 no record type for any sport beyond
cycling and strength.

## 6. Things asked for that I could not supply

The WHOOP screenshots were not received. No measured usability data exists. The earlier "Cyclift Pulse" reference was
not found in the project.
