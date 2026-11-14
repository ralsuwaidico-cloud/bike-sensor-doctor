# Training Hub v1.3 — Data ownership, persistence and capability contract

Status: **Current Draft — pending owner review. Not approved.** · Version 0.1 · 14 Nov 2026 · Level 3
No schema, engine, protocol or recording-ownership change is made or authorised. Source read (read-only): commit `4e2e9dc`.
Labels: Existing Verified (repository test, not re-run) · Existing Unverified · Proposed · Dependent.

## 1. Who owns what

| Data | Owner today | Stored when | v1.3 |
|---|---|---|---|
| Plan and planned sessions | iPhone store | On change | Unchanged |
| Active strength session (sets, start, pauses) | iPhone store | Continuously — survives a restart (Existing Verified) | Unchanged; the coordinator reads it |
| Ride in progress — phone | Ride recorder, in memory | At the end of the ride (as read) | **Dependent:** needs storing while it runs before minimising a ride is safe |
| Ride in progress — BikeComputer | The device; the phone mirrors | On the device | Unchanged; protocols untouched |
| Saved rides and strength logs | iPhone store | At Save | Unchanged |
| Apple Health workout | Written once at Save (Existing Verified: "recorded once") | At Save | Unchanged |
| Check-in (effort, performance, pain) | iPhone store, linked to the session | After Save | Meaning unchanged; "not answered" is Proposed |
| Session coordinator state | — | — | Proposed: holds no training data; can be rebuilt from the stores |
| Recovery entries | — | — | Dependent: new record type |

## 2. Save contract

| Situation | What is stored | Plan | Label |
|---|---|---|---|
| Complete | All logged sets or the recorded ride | Marked done | Existing Verified (UI journey test: start → log → finish → save → check-in → history) |
| Partial | Only what was done; the rest named as not done | Marked done, shown as partial | Storing only logged sets: Existing. The "partial" label: Proposed |
| Empty | Nothing. Optional "mark done without details" stores a marked completion, not a measured one | Not marked unless the athlete marks it | "Marked" as its own completion type: Existing Verified |
| Save failed | Nothing new; the session is kept and can be retried | Not marked | Dependent |
| Discard | Nothing | Unchanged | Existing Unverified |
| Review skipped | The workout is already saved; ratings stay unknown | Unaffected | Proposed (today the check-in is pre-filled) |

A session is never completed because its date passed or because it is on the calendar — an existing rule, kept.

## 3. Coach's dependence on effort — audit

As read in the adaptation code and its tests:

- Coach reads from a check-in: effort (1–10), performance (1–10), pain level, pain area.
- Session load is effort × minutes.
- For strength, if there is no check-in, the effort entered on today's Finish screen is used instead.
- Reference values when history is thin: effort 6, performance 7.
- Today's check-in opens pre-filled with performance 7 and effort 6, and stores both as required numbers.

What follows for v1.3 (requirements from the brief, consequences stated, **no fallback invented**):

| Requirement | Consequence | Status |
|---|---|---|
| No Effort on Finish | A skipped review leaves a strength session with no effort and therefore no session load | Needs a separate proposal for what Coach does with a session of unknown effort |
| No pre-filled ratings | Storage must allow "unknown" for each rating | Proposed data change |
| Unknown is not zero and not a default | Coach must skip unknown values, not read them as low | Part of the same proposal |
| Intensity | Stored only; not an input to Coach, load or Progress | Proposed; needs approval to exist at all |
| Pain | The existing three levels and five areas are offered unchanged, so current Coach rules keep working when a level is given | Existing. With no level: nothing is passed (Proposed) |

How the rules behave across several sessions with unknown effort was not traced and must be before any change.

## 4. Capability matrix — today and proposed

| Activity | Today | v1.3 status | Minimise | Depends on |
|---|---|---|---|---|
| Road / indoor / other cycling | Recorded: time, power, cadence, heart rate, speed, distance, route, laps, interval guidance | Record | Dependent (RA-01; storing a ride in progress) | — |
| Resistance training | Recorded: sets, reps, load, rest; group members alternate (Existing Verified) | Record | Mostly existing | Rounds, skipped, typing a value |
| Bodyweight | Flag on a set | Record | As strength | — |
| Added weight · assisted · timed sets | Not in the data | Shown as forms, FUTURE | — | New set forms |
| Breathing, mobility, stretching, meditation | Nothing | Guided or Timed — proposed | Dependent | Recovery record type |
| Sauna, massage, cold exposure | Nothing | Manual log — proposed | Not applicable (nothing runs) | Recovery record type |
| Running | No record type | Planned — cannot be started. One clearly marked future example on sheet 5 | — | Record type; pace and splits from GPS; cadence or power only from a running source |
| Rowing, swimming, hiking, walking | Nothing | Planned — cannot be started | — | Per-sport record types |

Status always comes from the registry, never from a name or an icon. A manual log is never shown as sensor-recorded.

## 5. Measured, entered, unknown

| Kind | Shown as |
|---|---|
| Measured (sensor, GPS, clock) | The value; its source in the status line |
| Entered by the athlete | "Entered by you" / "logged by you" |
| Calculated | Named (average, 3-second power) |
| Unknown or lost | "—" or "Not answered", with the reason. Never zero, never carried forward |
| Sample figures in these drawings | Stated on every sheet; none is live or measured |
