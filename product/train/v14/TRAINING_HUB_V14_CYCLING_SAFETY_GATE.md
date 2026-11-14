# Training Hub v1.4 — Cycling minimisation: safety-gate architecture proposal

Status: **Current Draft — proposal only. Blocked pending separate audit, testing and owner approval.** · Version 0.1 · 14 Nov 2026 · Level 3
Nothing is changed. The Ride screen's rule and the ride recorder behave exactly as before.
Labels: **Verified** (test result in run 43013897973, simulator — see the design document §0) · **Exists, not verified** · **Proposed** · **Dependent** · **Blocked**.

**Plain statement.** Background running is not recovery. If the app is force-quit, or the system ends it, recording stops.
Nothing in this design or in the app as read guarantees a ride survives that.

| # | Requirement | What exists | Label | What would be needed |
|---|---|---|---|---|
| 1 | Single session ownership across the Ride recorder and the Training Hub | One ride recorder object for the whole app. One active strength session, a second refused | Recorder: exists, not verified. Strength refusal: verified. Whether a ride and a strength session can be active together: **not established** | One coordinator that reads both and refuses a second session of any kind (proposed) |
| 2 | Recording continuity when switching tabs or minimising | The recorder is not owned by the Ride screen. But the dock is removed while a ride records (rule RA-01), so the screen cannot be left | Exists, not verified · **Blocked** by RA-01 | Owner decision on RA-01; then a simulator and device test that a ride continues across tab changes with no second recorder |
| 3 | Background behaviour and permitted system states | Background location and Bluetooth modes are declared. A background notice exists. Seconds the timer missed are stored empty and flagged | Declared: exists, not verified. Empty flagged seconds: verified | Device tests: screen locked, another app in front, phone call, Low Power Mode, long ride. State clearly which states record and which do not |
| 4 | Interruption, force termination and restart | No handling found for a phone-recorded ride. A BikeComputer-recorded ride continues on the device; ending on the phone and refusing the device's later copy is verified | Phone ride: **Dependent**. Device ride: verified in part | A defined behaviour for each case; no promise of recovery after force-quit beyond what was stored |
| 5 | Persistence of in-progress measurements | None found: as read, a phone ride is held in memory until it ends | **Blocked** | Proposal: write the ride to storage as it runs (identity, start, pauses, samples in small batches). Needs its own impact assessment — it touches recording ownership |
| 6 | Restoration after unexpected termination | None | **Blocked** (depends on 5) | On next launch: "A ride stopped at 31:08" → Resume · Save what was recorded · Discard. The gap is stored as missing, never filled |
| 7 | Bluetooth sensor disconnection and reconnection | Connection-state model for BikeComputer, watch and sensors; lost BikeComputer link can be paused, resumed, ended and reviewed | Verified | The on-screen states of v1.4 (stale, disconnected, unavailable) are proposed |
| 8 | Missing data and partial-session recovery | Missing seconds stored empty; no heart rate invented without a source. **The test that GPS route samples are kept in the record failed in the last run** | Verified for empty seconds and heart rate · **route samples: failing — a blocker** | Find the cause of the failing test before anything else in this gate |
| 9 | Save confirmation, retry and duplicate prevention | One Apple Health workout per ride, written at Save; an old record is exported once | Verified | A save that reports confirmed, failed or unknown, and a retry that cannot write a second record (Dependent) |
| 10 | Compatibility with current Ride navigation and presentation | Ride is its own tab; RA-01 removes the dock; RA-20 fixes the controls | RA-20: verified. RA-01: exists, not verified | Two options for the owner — (a) keep the Ride screen where it is and let "minimise" bring the dock back with the emblem state; (b) move the recorder under Train. (a) changes less |

## Order of work if the gate is ever opened

1. Explain the failing route-sample test.
2. Decide RA-01.
3. Design and assess in-progress storage (5) and restoration (6).
4. Device test plan for item 3.
5. Only then a prototype of ride minimising.

No cycling minimisation may proceed until each step is separately audited, tested and approved.
