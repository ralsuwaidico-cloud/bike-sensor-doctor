# Training Hub v1.1 — C · Recording and session lifecycle architecture

Status: **Current Draft — design exploration, pending owner review** · Version 0.1 · 13 Nov 2026 · Level 3
Authorised: audit, architecture, specifications and static mock-ups only. **Production implementation not approved. Onboarding out of scope.**
Nothing was built or run. Code read (read-only): release branch `ios/checkpoint-f-ride`, commit `4e2e9dc`. All figures in the sheets are illustrative.
This document proposes structure. It does not authorise changing recording ownership, the Ride screen's rules, the
shared presenter, or any firmware protocol.

## 1. Layers

| Layer | Responsibility | Today |
|---|---|---|
| Activity registry | What exists and what each activity can do | Not present |
| Preference mapping | Selected activities → hub content | `TrainingMode`; unused `sports` list |
| Train presentation owner | Closed / compact / expanded / preparation / recording / finish | Five owners plus an overlay |
| **Session lifecycle** (shared) | One identity and state per session, whatever the sport | Strength: `activeSession`. Ride: `RideRecorder.state`. Two separate mechanisms |
| **Recorders** (per kind) | Endurance recorder · strength sets engine · recovery timer/log | Ride recorder and strength store exist; recovery none |
| Sensor adapters | Power meter, HR, GPS, watch — each reports availability and quality | `SensorHub` exists |
| Persistence | Store, restart recovery, save result | Strength survives restart; ride not verified; save cannot fail visibly |
| Feedback | Post-session review | `CheckIn` exists (performance, effort, pain, note) |
| Integrations | Plan, Progress, Coach | Exist; see §5 |

The lifecycle is common; measurement is not. No universal recorder is proposed.

## 2. States and transitions

`Selected → Preparing → Active ⇄ Paused → Finishing → Saving → Saved`

| From | Allowed | Not allowed |
|---|---|---|
| Selected | Preparing · cancel | Active without a start action |
| Preparing | Active · back | Saving |
| Active | Paused · Finishing · minimise (stays Active) | Starting another session · dismiss by swipe |
| Paused | Active · Finishing | Starting another session |
| Finishing | Active (back to workout) · Saving · Discarded (confirmed) · Marked done without details (only when nothing was recorded) | Silent exit |
| Saving | Saved · Save failed | Dismissal as if saved |
| Save failed | Saving (retry) · Active (back) | Discarding data automatically |
| Interrupted (app closed) | Restored → Paused, same identity | A new session |

Guards: a second Start for the same planned item is ignored while one is in progress; any Start is refused while an
incompatible session is active; the planned item is marked done only by Saved or by an explicit "mark done".

## 3. Endurance recording framework

One layout with slots: elapsed time (always) · up to four primary live values · a secondary row · interval strip ·
source line · two controls. A sport fills the slots from its registry entry; a slot with no source is not drawn; a
source that drops shows "—" and the reason; GPS not yet acquired shows "—", never 0. Metrics and Map are two views of
the same recording. Sport fill-ins are on sheets S05–S07; everything except cycling is a future illustration.

Continuity states to design for and then **verify in code before promising**: sensor disconnect and reconnect ·
GPS loss · app in background · pause and resume · call or other interruption · finishing · save failure.
Verified today: ride pause/resume; sensor availability reporting; a map and lap timing exist. Not verified in this
audit: background recording behaviour, restoration of a ride after the app is closed.

## 4. Devices

iPhone: authority for plans, sessions and storage. Apple Watch, Waveshare BikeComputer and the LILYGO watch are separate
workstreams; this design assumes nothing about them beyond what each has verified, and shares no protocol between them.

## 5. Integrations

- **Plan** supplies planned items and receives "done"; moving a missed session is Plan's action.
- **Progress** reads Saved records that pass its validity rules; marked-done, Log-only and recovery entries are not
  performance evidence.
- **Coach** today reads the check-in through defined rules; new feedback fields reach it only through rules that are
  written and approved (document F).

## 6. Conflicts and blockers

1. Shared presenter repair unfinished (proto/ui-lab) — not to be merged or bypassed.
2. The Ride screen owns the screen bottom during a ride (approved rule RA-01) — a full-screen recording owned by Train
   would change it; needs its own decision.
3. Two session mechanisms today (strength, ride) — whether both can be active together is unverified.
4. The current hub was made animation-free for tap reliability; a rising panel must be proven against the same failure.
