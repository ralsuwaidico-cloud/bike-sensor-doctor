# Training Hub v1.1 — B · Activity registry and capability matrix

Status: **Current Draft — design exploration, pending owner review** · Version 0.1 · 13 Nov 2026 · Level 3
Authorised: audit, architecture, specifications and static mock-ups only. **Production implementation not approved. Onboarding out of scope.**
Nothing was built or run. Code read (read-only): release branch `ios/checkpoint-f-ride`, commit `4e2e9dc`. All figures in the sheets are illustrative.

## 1. Six separate concepts

Athlete profile (Endurance / Strength / Hybrid) · activity category · specific activity · recording capability ·
training prescription (planned) · session record (done). None implies another: a category never grants a capability.

## 2. Registry entry (proposed schema, version 1)

`id` (stable) · `name` and localisation key · `category` and `subcategory` · `icon` and icon family ·
`recordingMode` (sensor recording / timer / sets-and-reps / manual entry / imported / none) · `measurements` each
with its permitted sources · `prescriptions` supported · `manualFields` · `background` (supported, or not verified) ·
`selectableInHub` · `plannable` · `coachMayRecommend` · `contributesTo` (training exposure / recovery history /
neither) · `evolutionEvidence` (yes / no — default **no**) · `status` (Implemented / Proposed / Future / Manual-only /
Unsupported) · `importExport` mapping · `permissions` and equipment · `schemaVersion`.

Rule: an entry has only the capabilities written in it. Adding a name adds nothing else.

## 3. Capability matrix — every activity shown in the sheets

"Today" is what the current code does. "Hub status" is the proposed label in the selector.

| Activity | Category | Today in the code | Recording mode (proposed) | Measurements with a real source today | Hub status | Evolution evidence |
|---|---|---|---|---|---|---|
| Road cycling | Training · endurance | **Implemented** (ride record; the four cycling types are labels of one sport) | Sensor recording | Time; power, cadence (power meter); HR (strap or watch); speed, distance, route (GPS); laps | Record | Possible, per Progress rules |
| Indoor cycling | Training · endurance | Implemented as a ride; no indoor-specific handling confirmed | Sensor recording, no GPS | Time, power, cadence, HR; speed and distance only from a sensor | Record | Possible |
| Mountain bike | Training · endurance | Label only | Sensor recording | As road cycling | Record (as cycling) | Possible |
| Resistance training | Training · strength | **Implemented** (sets, reps, load, rest, restart recovery) | Sets and reps | Athlete-entered sets; duration | Record | Possible |
| Bodyweight strength | Training · strength | Partly: bodyweight flag on a set | Sets and reps | Reps; duration | Record | Possible |
| Running, treadmill | Training · endurance | **Not supported** (no record type, import ignores it) | Future: sensor recording | None | Log only | No |
| Walking, hiking | Training · endurance | Not supported | Future | None | Log only | No |
| Rowing | Training · endurance | Not supported | Future | None | Log only | No |
| Swimming | Training · endurance | Not supported | Future: timer plus manual lengths | None | Log only | No |
| Stretching, mobility, foam rolling | Recovery | Not present | Timer; optional saved sequence | Time (phone) | Timer — **Proposed** | No |
| Breathing, meditation | Wellness | Not present | Timer | Time (phone) | Timer — Proposed | No |
| Sauna, cold exposure, massage | Recovery | Not present | Manual entry afterwards | None | Log only — Proposed | No |
| Sleep, naps | Sleep | Sleep duration is read from Apple Health for Home; not a loggable activity | Imported only | Imported value | Not selectable (Future) | No |
| Other sports | Other | Not present | Manual entry | None | Log only — Proposed | No |

"Timer" and "Log only" for recovery and wellness are **proposals**: nothing of the kind exists in the app today, and
they need a new, simple record type (proposed dependency P4 in document G).

## 4. Source integrity

Every stored value carries one of: sensor-measured · phone-recorded · Apple Health-imported · manually entered ·
calculated/estimated · planned-not-performed. The app already tracks source and quality per live measurement
(`SensorHub`) and provenance for profile readings; session-level labelling for manual and marked-done records is a
proposed dependency.

## 5. Icon family

One 24-pt grid, one stroke weight, round ends; figures share a round head and line limbs (sheet S04). The drawings are
concept sketches that fix the rules; several (indoor cycling, foam rolling, massage) are not yet clear enough at 22 pt.
Final drawing is a separate task. No third-party artwork was used.
