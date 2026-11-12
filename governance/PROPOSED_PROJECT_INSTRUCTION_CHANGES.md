# Proposed changes to the Master Project Instructions (v2.0) — exact before and after

Status: Current Draft · Version 0.3 · 12 Nov 2026 · **Approved in principle by the owner (12 Nov); Change 4 refined as instructed.**
**The Project Instructions were not changed and will not be changed by me — the owner applies these edits in Project Settings.**
"Before" is quoted from the Instructions as they stand. Every existing safeguard is kept; where a sentence carrying a
safeguard is reworded, the safeguard is repeated in the "after" text and named in the last line of the item.

---

## Change 1 — §2 Ecosystem Architecture (hardware workstreams)

**Before**

> Cyclift consists of three primary application and device surfaces:

> ### Cyclift Detachable Watch / BikeComputer
> One planned LILYGO-based device with multiple operating modes:
>
> - Wrist mode.
> - Bike mode.
> - Gym mode.
>
> The device is intended to display training information, interact with workouts and communicate with the iPhone application.
>
> The hardware concept must not be mistaken for verified hardware capability. Sensors, communication protocols, workout interactions and firmware features require independent implementation and testing.
>
> Do not recreate the detachable watch and BikeComputer as separate products unless a later approved architecture explicitly requires this.

**After**

> Cyclift consists of four application and device surfaces. The two hardware devices are distinct workstreams within one ecosystem:

> ### Cyclift Detachable Watch (LILYGO)
> A LILYGO-based detachable device with multiple operating modes:
>
> - Wrist mode.
> - Bike mode.
> - Gym mode.
>
> The device is intended to display training information, interact with workouts and communicate with the iPhone application.
>
> ### Cyclift BikeComputer (Waveshare)
> A Waveshare-based bike computer with its own firmware, documentation, communication protocol and development history. It is an active workstream, not a legacy product.
>
> ### Rules for both hardware workstreams
> The hardware concepts must not be mistaken for verified hardware capability. Sensors, communication protocols, workout interactions and firmware features require independent implementation and testing.
>
> The firmware and communication protocols of the two devices must not be assumed to be interchangeable.
>
> Preserve each workstream's firmware, documentation, protocols and history. Do not merge, replace or discontinue either workstream without an approved architecture decision.

Safeguards kept: "not mistaken for verified capability"; independent implementation and testing. The old last sentence
(do not split into separate products) is replaced, because it contradicts the decision of 12 Nov, by its mirror
(do not merge or discontinue without approval).

---

## Change 2 — §1 and §7 (Coach terminology)

**Before (§1)**

> - The AI Coach should provide practical, explainable and personalized guidance.

**After (§1)**

> - The Coach should provide practical, explainable and personalized guidance.

**Before (§7, heading and first sentence)**

> ## 7. AI Coach Philosophy
>
> The AI Coach is a persistent advisory layer across Cyclift.

**After (§7, heading and first sentences)**

> ## 7. Coach Philosophy
>
> The Coach is a persistent advisory layer across Cyclift. "Coach" is the user-facing feature name.
>
> The current coaching logic is rules-based. Generative AI coaching and advanced adaptive planning are future capabilities until they are implemented and verified. Existing rules-based recommendations must not be described as generative AI.

The rest of §7 is unchanged, including: "Distinguish rules-based guidance from genuinely AI-generated guidance",
"Respect the user's approval for meaningful training changes" and "Avoid unsupported medical or physiological claims".

---

## Change 3 — §5 Home (reference version)

**Before**

> The Home v2.2 UI Lab prototype is a design reference, not an approved production implementation until separately accepted.

**After**

> The current approved Home specification is the design reference. A UI Lab Home version becomes the approved specification only by explicit owner decision; a newer version is not approved merely because it is newer. No UI Lab prototype is an approved production implementation until separately accepted.

Safeguard kept: a prototype is not production until separately accepted.

---

## Change 4 — §3 Project Knowledge (source of truth)

**Before**

> The repository and approved project documentation are the authoritative records of implementation.

**After**

> The repository and approved project documentation are the authoritative records of implementation.
>
> Authoritative documentation is version-controlled in GitHub through an approved isolated documentation workflow, kept separate from release branches. Copies in Claude Project Knowledge are reference copies; each identifies its source, version and last synchronization date. Independently edited versions of the same specification must not be maintained.

Refined in v0.3: the text names "an approved isolated documentation workflow" instead of a particular branch form, so it does not permanently require an orphan branch.

Nothing removed.

---

## Change 5 — §8 Design System (themes)

**Before**

> Current theme families include Obsidian, Arctic, Ocean, Forest, Sandstone and High Contrast.
>
> Theme support must be validated rather than assumed.

**After**

> The approved theme families are Obsidian, Arctic, Ocean, Forest, Sandstone and High Contrast. They are the approved design direction; until a production migration is authorized and verified, the production iPhone app ships its existing light and dark palettes, and the six themes exist as prototype tokens only.
>
> For six-theme development, discipline colors are: endurance blue/cyan, strength amber/warm orange, recovery green. Status colors are independent of discipline colors.
>
> Theme support must be validated rather than assumed.

Safeguard kept: validation before assuming theme support.

---

## Change 6 — §9 Metrics (colour judgements)

**Before** (end of the section)

> Missing data must not be silently interpolated or presented as actual measurements.

**After**

> Missing data must not be silently interpolated or presented as actual measurements.
>
> Colors must communicate documented, meaningful states or validated thresholds. Do not use green or red to judge athlete performance or adherence without an approved interpretation.

Nothing removed.

---

## Change 7 — §15 Documentation and Handover (statuses)

**Before**

> Update the appropriate trackers after significant work.

**After**

> Update the appropriate trackers after significant work. Do not update a tracker by guessing progress; audit its status against verifiable implementation evidence.
>
> Every document carries one status: Current Approved, Current Draft, Historical, Superseded or Pending Review. Only the owner assigns Current Approved and Superseded. Each subject has one authoritative file, listed in the documentation index; contradictions are recorded in the conflict register with the decision, rationale and resolution status.

Nothing removed.

---

## Not proposed

No change is proposed to §4 (isolation), §6 (scheduling safeguards), §10 (engineering), §11 (testing and evidence),
§12 (UI Lab promotion), §13 (change management) or §14 (approval list). All approval requirements and evidence levels stay as written.
