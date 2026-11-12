# Cyclift Watch — button matrix for every screen (12 Nov 2026) — PROPOSAL (hybrid model, not approved)

**Buttons:**
- **L1** = left upper (GPIO35);
- **L2** = left lower (GPIO34);
- **R2** = right lower (Boot, GPIO0);
- **R1** = right upper (hardware Reset). R1 restarts the watch on every screen; firmware cannot change that, so it is
  not repeated per row.

**On every screen:**
- **R2 hold 1 s** = touch lock on / off.
- **L2 + R2 held 10 s** = restart (BUTTON_UX_RECOMMENDATION §5).

These are not repeated per row.

**Timing (proposal):**
- hold = 1 s;
- End / destructive confirm = 2 s hold with a countdown ring;
- two-press window = 2.5 s (approved V8);
- debounce 30 ms.

**"Current (firmware)" marks:**
- [HW] = verified on the watch;
- [SIM] = computer-tested;
- other screens are not in the firmware (designed in prototype v3.3 only).

**Status:**
- IMPLEMENTED = in RC1 / RC2 firmware;
- PARTIAL = in firmware with parts missing;
- DESIGNED = approved prototype only.

Nothing below is implemented as proposed.

## Operating states (apply over the per-screen rows)

| State | L1 | L2 | R2 | Holds / chords |
|---|---|---|---|---|
| No workout | per screen | Back (hold: Home) | Next (hold: lock) | restart chord |
| Cycling active, on a workout page | Controls → 2nd press Pause | two-press Lap | next data page | L1 hold 2 s End request; L2 hold → cockpit |
| Cycling paused | Controls → 2nd press Resume | two-press Lap | next page | L1 hold End request |
| Gym active (set page) | Controls → 2nd press Pause | two-press Log Set | next field / page | L1 hold End request |
| Rest timer running | Controls | two-press Skip rest | +15 s | L1 hold End request |
| Workout in background (any non-workout screen) | per screen | Back; **hold = return to the workout** | per screen | workout bindings never act here |
| Disconnected from the iPhone | same buttons. Commands queue and show "pending" (design WC-03); nothing silently fails | same | same | same |
| Simulated data | same buttons (the banner says simulated) | same | same | same |
| Screen locked | **proposal: buttons keep working, touch is blocked**; R2 hold unlocks (decision G4) | | | |
| Dialog open | Confirm (destructive = hold 2 s) | Cancel | move highlight | — |
| Error / warning banner | Open / acknowledge | Dismiss | Dismiss | — |
| Starting up (≤ 0.6 s) | ignored | ignored | **never hold: download mode** | R1 resets |
| Screen off (future, with battery) | first press only wakes (consumed) | same | same | — |

## Firmware-only screens (not in the prototype)

| Screen | Status | Current (firmware) | L1 | R2 | L2 | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|
| "Not in this release" page | IMPLEMENTED (RC1) | L1 Menu [SIM] · L2 Back [HW 11 Nov] | Menu | — | Back | Quick Settings | Home |
| Lock overlay (over any screen) | IMPLEMENTED | L1 / L2 ignored [HW]; L1 hold ≥ 1 s unlocks [HW] | proposal: works as the screen below | as below | as below | as below | as below — R2 hold unlocks |
| Start-up (first 0.6 s) | not designed | buttons not read | — | **do not hold** | — | — | — |
| Screen off | designed in v2, not in v3 | — | wake | wake | wake | — | — |

## Every designed screen (prototype v3.3, 89 screens)

### Face

| Screen | Name | Status | Current (firmware) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `face` | Watch face | IMPLEMENTED | L1 Menu [HW] · R2 none (no function; B2 HW: no event) · L2 Back → stays on face [SIM] · L1 hold Hold ≥ 1 s: unlock only when locked [HW 11 Nov] | Menu | Next widget (Health) | — (already home) | Quick Settings | — (already home) |
| `w-health` | Widget · Health | IMPLEMENTED | L1 Menu [SIM] · R2 none · L2 Back → face [SIM] · L1 hold unlock only | Open that widget's app (Health / Coach / Activity) | Next widget (… → face) | Face | Quick Settings | Face |
| `w-coach` | Widget · Coach | IMPLEMENTED | L1 Menu [SIM] · R2 none · L2 Back → face [SIM] · L1 hold unlock only | Open that widget's app (Health / Coach / Activity) | Next widget (… → face) | Face | Quick Settings | Face |
| `w-activity` | Widget · Activity rings | IMPLEMENTED | L1 Menu [SIM] · R2 none · L2 Back → face [SIM] · L1 hold unlock only | Open that widget's app (Health / Coach / Activity) | Next widget (… → face) | Face | Quick Settings | Face |
| `qs` | Quick Settings | PARTIAL — 5 rows, RAM only | L1 Menu [SIM] · R2 none · L2 Back → previous screen / face [SIM] · L1 hold unlock only | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `fpick` | Face picker | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Use this face | Next face | Back (keep face) | — | Home |
| `fcomp` | Complications | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |

### Menu

| Screen | Name | Status | Current (firmware) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `menu` | App menu | PARTIAL — 8 rows; Today and Activities (simulated ride) open, 5 rows open "Not in this release" | L1 Face, or the workout if one runs [HW] · R2 none · L2 Back (previous screen / face) [HW] · L1 hold unlock only | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |

### Today

| Screen | Name | Status | Current (firmware) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `today` | Today | IMPLEMENTED | L1 Menu [SIM] · R2 none · L2 Back → previous (menu or face) [HW 11 Nov, from the menu] · L1 hold unlock only | Start the planned session (if any), else Menu | Week strip | Back | Quick Settings | Home (or the workout) |
| `today-plan` | Planned session detail | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Start this session | Scroll | Back | Quick Settings | Home (face; in a workout: the workout) |
| `today-week` | Week strip | IMPLEMENTED | L1 Menu [SIM] · R2 none · L2 Back → Today [SIM] · L1 hold unlock only | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |

### Activities

| Screen | Name | Status | Current (firmware) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `act` | Activities | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `review` | Review | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Start (after the sensor check) | Next field (sport / route) | Back | Quick Settings | Home (or the workout) |
| `sensors` | Sensor check | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Re-scan / continue | Next sensor | Back | Quick Settings | Home (face; in a workout: the workout) |
| `starting` | Starting (pending) | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | — | — | Cancel where the screen allows it (Starting), else — | — | — |
| `start-fail` | Start refused | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Retry | — | Back | Confirm destructive choice (2 s) | Cancel |

### Strength

| Screen | Name | Status | Current (firmware) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `st-set` | Set editor | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Controls with Pause highlighted; 2nd press = Pause | Next field (Reps → Weight) then next page | Two-press: Log Set | End request (2 s) | Set page |
| `st-reps` | Edit reps | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Done (keep the new value) | +1 step (hold: repeat) | −1 step (hold: repeat) — the one exception to "L2 = Back" | — | Cancel (old value kept) |
| `st-kg` | Edit Weight | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Done (keep the new value) | +1 step (hold: repeat) | −1 step (hold: repeat) — the one exception to "L2 = Back" | — | Cancel (old value kept) |
| `st-rest` | Rest timer | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Controls | +15 s | Two-press: Skip rest | End request (2 s) | Set page |
| `st-next` | Up next · exercise list | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted exercise | Move highlight | Two-press: Log Set | End request (2 s) | Set page |
| `st-ctl` | Strength controls | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Activate the highlighted control | Move highlight (Pause/Resume → Lap → End → Why? → Menu) | Close controls | End request (2 s) | Cockpit |
| `st-instr` | Exercise instructions | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Back to the set | Scroll | Back | End request (2 s) | Set page |
| `st-sub` | Substitute exercise | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Choose the highlighted exercise | Next exercise | Back (keep current) | End request (2 s) | Set page |
| `st-auto` | Rep count (experimental) | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Controls with Pause highlighted; 2nd press = Pause | Next field (Reps → Weight) then next page | Two-press: Log Set | End request (2 s) | Set page |
| `st-sync` | Offline sync result | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | OK | Next result | Back | Confirm destructive choice (2 s) | Cancel |

### Cycling

| Screen | Name | Status | Current (firmware) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `ride-cockpit` | Cockpit | PARTIAL — cockpit only (no other ride pages, no controls overlay); wrist / bike / gym layouts; simulated data | L1 Menu (controls page not built) [HW 12 Nov log] · R2 none · L2 Two-press within 2.5 s: Lap; single press expires [HW 12 Nov: 5 laps] · L1 hold unlock only (End not built) | Controls opened with Pause / Resume highlighted; 2nd press within 2.5 s = Pause / Resume | Next data page (wraps) | 1st press: "Press again for Lap"; 2nd within 2.5 s: Lap | End request (2 s countdown ring → End confirmation) | First data page (cockpit) |
| `ride-power` | Performance · Power | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Controls opened with Pause / Resume highlighted; 2nd press within 2.5 s = Pause / Resume | Next data page (wraps) | 1st press: "Press again for Lap"; 2nd within 2.5 s: Lap | End request (2 s countdown ring → End confirmation) | First data page (cockpit) |
| `ride-hr` | Performance · Heart rate | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Controls opened with Pause / Resume highlighted; 2nd press within 2.5 s = Pause / Resume | Next data page (wraps) | 1st press: "Press again for Lap"; 2nd within 2.5 s: Lap | End request (2 s countdown ring → End confirmation) | First data page (cockpit) |
| `ride-cad` | Performance · Cadence | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Controls opened with Pause / Resume highlighted; 2nd press within 2.5 s = Pause / Resume | Next data page (wraps) | 1st press: "Press again for Lap"; 2nd within 2.5 s: Lap | End request (2 s countdown ring → End confirmation) | First data page (cockpit) |
| `ride-pacing` | Pacing · interval | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Controls opened with Pause / Resume highlighted; 2nd press within 2.5 s = Pause / Resume | Next data page (wraps) | 1st press: "Press again for Lap"; 2nd within 2.5 s: Lap | End request (2 s countdown ring → End confirmation) | First data page (cockpit) |
| `ride-climb` | Climb | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Controls opened with Pause / Resume highlighted; 2nd press within 2.5 s = Pause / Resume | Next data page (wraps) | 1st press: "Press again for Lap"; 2nd within 2.5 s: Lap | End request (2 s countdown ring → End confirmation) | First data page (cockpit) |

### Workout

| Screen | Name | Status | Current (firmware) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `wk-nav` | Navigation | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Controls opened with Pause / Resume highlighted; 2nd press within 2.5 s = Pause / Resume | Next data page (wraps) | 1st press: "Press again for Lap"; 2nd within 2.5 s: Lap | End request (2 s countdown ring → End confirmation) | First data page (cockpit) |
| `wk-coach` | Coach (in workout) | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Controls opened with Pause / Resume highlighted; 2nd press within 2.5 s = Pause / Resume | Next data page (wraps) | 1st press: "Press again for Lap"; 2nd within 2.5 s: Lap | End request (2 s countdown ring → End confirmation) | First data page (cockpit) |
| `wk-ctl` | Workout controls | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Activate the highlighted control | Move highlight (Pause/Resume → Lap → End → Why? → Menu) | Close controls | End request (2 s) | Cockpit |
| `wk-paused` | Paused | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Controls with Resume highlighted; 2nd press = Resume | Next data page | Two-press: Lap | End request (2 s) | Cockpit |
| `wk-end` | End confirmation | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | End and save (hold 2 s, countdown) | Highlight Cancel / End (Discard stays touch-only) | Cancel (back to the workout) | End and save (2 s) | Cancel |
| `wk-saving` | Saving on iPhone | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | — | — | Cancel where the screen allows it (Starting), else — | — | — |
| `wk-summary` | Summary | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Done (close summary → face) | Scroll | Back to the summary list top | Quick Settings | Face |

### Running

| Screen | Name | Status | Current (firmware) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `run-cockpit` | Run cockpit | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Controls opened with Pause / Resume highlighted; 2nd press within 2.5 s = Pause / Resume | Next data page (wraps) | 1st press: "Press again for Lap"; 2nd within 2.5 s: Lap | End request (2 s countdown ring → End confirmation) | First data page (cockpit) |
| `run-splits` | Splits | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Controls opened with Pause / Resume highlighted; 2nd press within 2.5 s = Pause / Resume | Next data page (wraps) | 1st press: "Press again for Lap"; 2nd within 2.5 s: Lap | End request (2 s countdown ring → End confirmation) | First data page (cockpit) |

### Walking

| Screen | Name | Status | Current (firmware) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `walk-cockpit` | Walk cockpit | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Controls opened with Pause / Resume highlighted; 2nd press within 2.5 s = Pause / Resume | Next data page (wraps) | 1st press: "Press again for Lap"; 2nd within 2.5 s: Lap | End request (2 s countdown ring → End confirmation) | First data page (cockpit) |

### Health

| Screen | Name | Status | Current (firmware) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `health` | Health | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `h-hr` | Heart rate (day) | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `h-sleep` | Sleep | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `h-hrv` | HRV | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `h-rec` | Recovery / readiness | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `h-load` | Training load | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `h-vitals` | Vitals (unavailable sources) | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `h-trends` | Trends | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |

### Coach

| Screen | Name | Status | Current (firmware) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `coach` | Coach | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `co-why` | Why this workout? | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `co-last` | Last workout feedback | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `co-week` | Weekly review | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `co-goal` | Week focus · goal | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `co-ask` | Ask on iPhone (hand-off) | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Send to iPhone | — | Back | Confirm destructive choice (2 s) | Cancel |

### History

| Screen | Name | Status | Current (firmware) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `hist` | History list | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `hi-ride` | Workout detail | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `hi-laps` | Laps | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `hi-lift` | Strength detail · sets | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `hi-trends` | Weekly and monthly trends | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |

### Utilities

| Screen | Name | Status | Current (firmware) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `util` | Utilities | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `ut-notif` | Notifications | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `ut-notif-d` | Notification detail | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `ut-call` | Incoming call | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Silence ringing (answering stays on the iPhone) | — | Dismiss | Confirm destructive choice (2 s) | Cancel |
| `ut-music` | Music controls | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Play / pause | Next track | Back | Previous track | Home (or the workout) |
| `ut-alarm` | Alarms | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `ut-sw` | Stopwatch | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Start / stop | Split | Back (stopwatch keeps running) | Reset (stopped only) | Home (or the workout) |
| `ut-timer` | Timers | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Start / pause | +1 min | Back (timer keeps running) | Reset | Home (or the workout) |
| `ut-water` | Hydration log | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | +1 glass | — | Back | Undo last glass | Home (or the workout) |
| `ut-find` | Find phone | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Stop ringing | — | Back | Confirm destructive choice (2 s) | Cancel |

### Settings

| Screen | Name | Status | Current (firmware) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `set` | Settings | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `se-display` | Display | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `se-appear` | Appearance | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `se-theme` | Theme picker | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Choose the shown item and go back | Next item | Back without changing | — | Home |
| `se-work` | Workout settings | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `se-pages` | Customize cycling pages | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `se-buttons` | Button layout (provisional) | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `se-haptic` | Haptics | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `se-lang` | Language and digits | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `se-conn` | Connections | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `se-feat` | Feature availability | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `se-feat-d` | Feature availability detail | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `se-about` | About | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `se-diag` | Diagnostics | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |

### System

| Screen | Name | Status | Current (firmware) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `sys-loading` | Loading (syncing) | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | — | — | Cancel where the screen allows it (Starting), else — | — | — |
| `alert-hr` | High heart rate alert | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Acknowledge | — | Dismiss | Confirm destructive choice (2 s) | Cancel |
| `alert-batt` | Low battery | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Acknowledge | — | Dismiss | Confirm destructive choice (2 s) | Cancel |
| `wk-banner` | Notification banner over a workout | DESIGNED (prototype v3.3) | not in firmware (prototype keys: Key1/Key2/hold Key1 only) | Open the notification | Dismiss | Dismiss | — | Dismiss → workout |

## Functions that stay touch-only under the proposal (by choice)
- Discard a workout (hold-to-discard on the End screen): deliberately not on a button.
- Typing or free selection on long lists: R2 steps through them, but touch is faster.
- Chart scrubbing (History, Health trends).
- Quick Settings brightness levels can be stepped by R2 + L1, but touch is quicker.
