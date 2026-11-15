# Cyclift Genesis — Onboarding v3.1 — two visual concepts for owner selection

**Version:** 0.1 · 15 Nov 2026 · **Status:** Design exploration — **Pending Owner Selection**. **Implementation NOT AUTHORIZED.** Static drawings only: nothing implemented, compiled or run; no prototype. **ILLUSTRATIVE DESIGN — NOT IMPLEMENTED.**
Owner decision recorded (15 Nov): the v3.0 functional research is retained; the **v3.0 visual design and experience are not approved**. `../v30/` and `../v20/` are kept unchanged as functional and migration references. The athlete model, field ownership, capability registry and compatibility plan in those documents apply to both concepts; **no new athlete model is introduced**.
**Not received:** the WHOOP screenshots mentioned in the brief did not reach the session. No WHOOP layout, symbol or typography was used; the activity taxonomy follows the Cyclift registry.

## 1. Structure common to both concepts
Six setup screens and one review — never more: **1 Identity · 2 Athletic DNA · 3 Direction · 4 Training rhythm · 5 Ecosystem · 6 Your evolution · 7 Review and approve.** Tap-to-type and search open in place; no hidden extra screens. Advanced settings (exercise restrictions, split, cadence, zones, sensors' details) stay in Profile.
Three fixed zones on every screen: **A instrument / context** (290 pt; 244 pt on the small iPhone) · **B primary input** (262 pt; 192 pt) · **C explanation and Continue** (132 pt; 116 pt). Changing an input never moves another control; the consequence of a change is written in zone C.

| Screen | Collects | Stored in (existing fields unless noted) |
|---|---|---|
| 1 Identity | name, birth date, height, weight, units | profile; `settings.units` |
| 2 Athletic DNA | activities; primary vs also; recovery options | `sports` (+ new identifiers, primary flag — additive) |
| 3 Direction | emphasis (five positions); experience; goals | `trainingMode` + `priority`; `level`; strength experience; goals |
| 4 Training rhythm | days, session minutes, rest days, equipment preset, "days may move" | availability; equipment; one new flag |
| 5 Ecosystem | connections; FTP / heart-rate baseline; Coach approval preference | settings; profile; existing adaptation setting |
| 6 Your evolution | nothing — explains G0–G5, shows evidence and the first-plan proposal | — |
| 7 Review | approval | first plan version |

**Emphasis has five positions, not a percentage**, because the model stores exactly: Endurance only (`cycling`), Endurance-led (`hybrid` + cycling priority), Balanced, Strength-led, Strength only. Nothing finer is stored, so nothing finer is drawn.
**Rest and recovery kept apart:** rest days are schedule states on screen 4; recovery activities are optional interests on screen 2; sleep and heart-rate measurements are a data source on screen 5.

## 2. Concept A — Precision Instrument
Technical, line-drawn, exact.
| Interaction | Before → input → after | Accessible alternative |
|---|---|---|
| **Rotary value dial** (screen 1) | 270° sweep, one tick per unit; a dashed mark stays where the value started; zone C states "178 → 181 cm · no plan effect · Undo" | tap the number to type; VoiceOver adjustable (swipe up/down = one step) |
| **Activity constellation** (screen 2) | three arcs — endurance, strength, recovery; tap selects, second tap marks primary (extra ring), third clears; dashed = interest only; search for more | plain grouped list with switches |
| **Balance dial** (screen 3) | five detents on a half-circle; turning previews the effect in zone C ("rides 2 → 3, lifts 3 → 2"); nothing saved until release; turning back restores everything | five-option picker |
| **Session bars** (screen 4) | bar height = minutes; drag to the line = rest day; solid = ride, outlined = lift | per-day rows with steppers |
| **Device orbit** (screen 5) | tap a node to connect; a line means linked | list of connections |
Strengths: unmistakably an instrument; states are exact; little motion needed. Weaknesses: the constellation is tight on a small iPhone (symbols 30 pt drawn); the dial is slower than typing for large changes.

## 3. Concept B — Living Athlete
A persistent, **non-generational** form of three arcs — endurance, strength, recovery — sits in zone A and responds to choices. It is captioned on every screen: "a picture of your choices — not a score, not your generation".
| Interaction | Before → input → after | Accessible alternative |
|---|---|---|
| **Value wheel** (screen 1) | vertical wheel, one notch per unit; zone C states the change and Undo | tap to type; VoiceOver adjustable |
| **Editorial activity list** (screen 2) | two columns with small symbols; ● selected, ●● primary, underlined = interest only; the form grows an arc per domain | the list itself is the accessible form |
| **Emphasis stops** (screen 3) | five stops; the form leans to the chosen side; preview and undo as in A | five-option picker |
| **Week line** (screen 4) | pebble size = minutes on a flowing line; small ring = rest day | per-day rows with steppers |
| **Device lines** (screen 5) | plain lines with state in words | same |
Strengths: warmer, tells one continuous story, activity names are always readable. Weaknesses: the form carries no information the inputs do not; risk of being read as a score despite the caption; the activity list scrolls inside its zone on a small iPhone; more animation to get right.

## 4. Athlete Evolution on screen 6 — and what cannot be shown truthfully yet
Shown: the Singularity (small, about one-sixth of the screen width in radius), the G0–G5 track, the distinction "told by you — not evidence" versus "measured", the evidence available, and the first-plan proposal.
- **New athlete:** no generation. Track drawn unfilled with "Establishing your baseline". G0 is not assigned (Progress framework: insufficient evidence is not G0).
- **Returning athlete with history:** the stage Progress would show is repeated here, labelled illustrative.
- Generation is never derived from the balance control, activities, body measurements or declared experience.
- **Conflict flagged:** the brief refers to "the existing approved G0–G5 framework" and asks what is needed for the next generation "if the approved criteria define it". The Progress documents record that generation **criteria, thresholds, confidence rules and transition review are not authorised and not defined**. The screen therefore says "criteria not yet defined" and makes no promise. No Progress rule was changed.
- The Singularity is a simplified line drawing here; the approved construction from Progress v2.3 would be used in any build.

## 5. Coach
Appears as one-line explanations in zone C and one preference on screen 5 ("Always ask me" / "Allow protective cuts"). Labelled rules-based. **Conflict carried over (register 69):** the screen states that increases always need approval — the owner's decision — while the app today applies some increases automatically by default. This must be corrected before such a screen ships.

## 6. Proof drawn (per concept)
Sheet 1: all six screens and the review, as a complete hybrid journey. Sheet 2: numeric before / input / after, tap-to-type; emphasis before / turning / after; a change reversed with no data lost. Sheet 3: strength-only (screens 2, 3, 5); endurance-only (screens 2, 4) and a first-time athlete with no measurable baseline (screen 5); returning athlete with evidence (screen 6); small iPhone (screens 2, 4); large-text accessible editor.
Not drawn in full for the single-discipline athletes: screens 1, 6 and 7, which do not differ in layout.

## 7. Open design issues
1. Generation criteria undefined (section 4). 2. Coach approval behaviour (section 5). 3. Small iPhone: A's constellation symbols are small; B's list scrolls. 4. "Primary" versus "also" needs an additive flag on the stored activities. 5. Recovery activities and unsupported sports are interests only — no recorder, timer or log exists. 6. Motion is specified in words only; Reduce Motion replaces all movement with fades. 7. Themes other than Obsidian and Arctic were not drawn in this round. 8. Arabic was not drawn in this round.

## 8. Sheets (`sheets/`)
A1 journey · A2 interactions · A3 variants · B1 journey · B2 interactions · B3 variants.
