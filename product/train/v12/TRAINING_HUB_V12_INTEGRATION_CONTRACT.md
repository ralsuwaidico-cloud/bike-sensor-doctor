# Training Hub v1.2 — Integration and data contract; capability matrix

Status: **Current Draft — pending owner review. Not approved.** · Version 0.1 · 14 Nov 2026 · Level 3
Design only. No schema, protocol, engine or recording-ownership change is authorised or made.
Source read (read-only): release branch `ios/checkpoint-f-ride`, commit `4e2e9dc`. Code was read, not run.

## 1. Flow

`Train → Session record → Plan → Progress → Coach → History`

| Step | What passes | Rule |
|---|---|---|
| Train → Session record | Identity (planned item or free), activity, start, pauses, recorded values, athlete entries | Created at Start; written to history only at Saved |
| Session record → Plan | "Done" for the planned item, with Complete or Partial | Only on Saved. Never on Start, Finish or Discard |
| Session record → Progress | Saved records that pass Progress's own validity rules | Completion alone is not evidence of capability. Recovery and manual entries are not performance evidence |
| Session record → Coach | Only the fields in §4 | New fields reach Coach only through a written, approved rule |
| Session record → History | Everything saved, with its source labels | Nothing rewritten later |

Not computed in this phase: athlete generations, readiness, recovery scores, rankings.

## 2. Kinds of data

| Kind | Examples | Shown as |
|---|---|---|
| Measured | Power, cadence (power meter); heart rate (strap or watch); speed, distance, route (GPS); elapsed time | Value with its source |
| Athlete-entered | Sets, repetitions, load; manual recovery duration; ratings; chips; note | "Entered by you" |
| Calculated | Averages; session load = effort × minutes (existing) | Named as calculated |
| Estimated | None introduced by v1.2 | — |
| Missing | Sensor lost, GPS not ready, question not answered | "—" or "Not answered", with the reason. Never zero, never filled in |
| Planned, not performed | Prescription | Kept separate from what was logged |

## 3. Events and duplicates

| Event | Effect |
|---|---|
| Start | Coordinator creates the one active session. A second Start is ignored (same item) or refused (another session active) |
| Save | Record stored; planned item marked done; review offered |
| Save with some sets or intervals missing | Stored as **Partial** with only what was done; the prescription is unchanged |
| Nothing recorded | No record. Optional "mark done without details" (exists today for strength) |
| Discard | Nothing stored; planned item unchanged |
| Review saved or skipped | Attached to the record; the record itself is not altered |

Duplicates today: a second strength session cannot start while one is active; a completed planned item cannot be logged again;
a BikeComputer ride and the phone's copy are reconciled by ride id; Apple Health writing follows the existing approved rule
(one workout per ride). v1.2 changes none of these.

## 4. What Coach reads today (rules-based)

From a check-in: **effort (1–10)**, **performance (1–10)**, **pain level** (none, normal soreness, unusual discomfort,
concerning pain) and **pain area** (five areas). Session load uses effort × minutes. For strength, when there is no check-in,
the **effort given on the Finish screen** is used instead. Coach compares recent sessions with a four-week baseline, or with
a default reference of effort 6 and performance 7.

Consequences for v1.2:
- Removing Effort from Finish means a skipped review leaves a strength session with **no effort and no load**. Decision 5.
- Today's check-in stores both ratings as required numbers, pre-filled 7 and 6. "Not answered" needs optional values. Decision 6.
- The proposed words under each number must not contradict the reference values. Decision 7.
- A pain chip without a level has no place in today's model. Decision 8.

## 5. Proposed fields that need future changes

| Field | Needs |
|---|---|
| Intensity (1–10) | New stored value. **Not** an input to Coach, load or Progress unless separately approved. No effect on history |
| Unusual fatigue, equipment problem, technique difficulty | New coded choices; stored and shown; not read by Coach |
| Rating "not answered" | Optional values in the check-in |
| Skipped set / movement | A state distinct from "not done" |
| Superset rounds and round rest | A model for rounds |
| Bodyweight plus load; assistance; timed sets | New set forms |
| Recovery entries (guided, timed, manual) | A new, simple record type |
| Session-level source label; Partial / Complete | New labels on a record |
| Visible save result with retry | Save that can report failure |
| Ride in progress surviving termination | Saving the ride while it runs |
| Capability registry | New; statuses come only from it |

## 6. Capability matrix — today and proposed

| Activity | Today in the app | v1.2 status | Depends on |
|---|---|---|---|
| Road cycling | Recorded: time, power, cadence, heart rate, speed, distance, route, laps; interval guidance | Record | — |
| Indoor cycling | Recorded as a ride; no indoor-specific handling confirmed | Record | — |
| Mountain bike and other cycling types | Labels of the same record | Record | — |
| Resistance training | Recorded: sets, reps, load, rest, restart recovery; superset members alternate | Record | Rounds, skipped, direct entry are proposed |
| Bodyweight strength | Bodyweight flag on a set | Record | Plus-load and assisted forms |
| Mobility, stretching, breathing, meditation | Nothing | Timer — **proposed** | Recovery record type |
| Sauna, massage, cold exposure | Nothing | Log — **proposed** | Recovery record type |
| Running, treadmill | No record type; Health import ignores it | Planned — cannot be started | Record type, GPS pace, splits; running cadence and power only from a real running source |
| Rowing, swimming, hiking, walking | Nothing | Planned — cannot be started | Record types and sources per sport |
| Sleep | Duration read from Apple Health for Home | Not an activity | — |

## 7. Unsupported today — stated plainly

Any sport other than cycling and strength · any recovery or wellness entry · timed sets · assisted and weighted-bodyweight sets ·
skipped as a state · rounds · typing a value directly · Undo on a logged set (not found) · a save that can visibly fail ·
restoring a phone-recorded ride after the app is closed (not found) · a single owner for Train presentation · the capability registry.
