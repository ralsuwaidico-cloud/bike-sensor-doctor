# Cyclift Watch — button matrix for every screen (12 Nov 2026) — APPROVED model, Stage 1.4 RC1 (offline)

Owner decisions G1–G11 of 12 Nov 2026 12:59 replace the earlier proposal. Stage 1.4 RC1 implements them for every screen
the firmware has (computer-tested; **not installed, not tested on the watch**). Screens marked DESIGNED are prototype-only:
their row is the approved behaviour they will get when they are built.

**Buttons:**
- **L1** = left upper (GPIO35) — Select / do;
- **L2** = left lower (GPIO34) — Back;
- **R2** = right lower (GPIO0, the Boot button) — Next; non-critical actions only (G3);
- **R1** = right upper (the chip's reset line). R1 restarts the watch on every screen; firmware can neither see nor
  remap it. Not repeated per row. Whether L1 presses can press R1 by accident is check G11 (physical test pending).

**On every screen (not repeated per row):**
- **R2 hold 1 s** = touch lock on / off. The lock blocks **only the touchscreen**; every button keeps working (G4).
- **L1 + L2 held 10 s** = software restart (G5, G6): countdown shown from 2 s, release either button = cancelled at once,
  nothing else fires. During a workout the 10 s hold opens a warning screen ("Restart the watch? The ride on the watch ends",
  Cancel highlighted); only an explicit Restart restarts. The restart happens after all buttons are released and the reason
  is recorded and printed at the next start. A restart does **not** keep the watch's ride state (no session recovery exists).

**Timing (implemented in `cyv3_keys.hpp`, all tested):**
- debounce 30 ms; short press fires on release (< 1 s); hold = 1 s; L1 End request = 2 s with a filling ring;
- Lap / Log Set two-press window = 2.5 s (approved V8);
- L1 + L2 count as the restart combination only if the second goes down within 1 s of the first, before any hold fired.

**Status:**
- IMPLEMENTED = in the Stage 1.4 RC1 firmware (offline);
- PARTIAL = in that firmware with parts missing (listed);
- DESIGNED = approved prototype only.

"[SIM]" = computer-tested through the same decoder → model path the watch uses (`test_buttons.cpp`); nothing in this
document has been verified on the watch yet.

## Operating states (apply over the per-screen rows)

| State | L1 | L2 | R2 | Holds / combinations |
|---|---|---|---|---|
| No workout | per screen | Back (hold: Home) | Next (hold: touch lock) | L1 hold: Quick Settings · L1 + L2 10 s: restart |
| Cycling active, on a ride page | Controls, Pause highlighted → 2nd L1 = Pause | two-press Lap | next data page | L1 hold 2 s: End request → confirmation; L2 hold → cockpit |
| Cycling paused | Controls, Resume highlighted → 2nd L1 = Resume | two-press Lap | next page | L1 hold 2 s: End request |
| Gym active (set page) — designed, not built | Primary / confirm (Controls → Pause) | two-press Log Set | next item | L1 hold 2 s: End request |
| Rest timer — designed, not built | Controls | two-press Skip rest | next / +15 s | L1 hold 2 s: End request |
| Reps / weight editor — designed, not built | Confirm | Decrease | Increase | — |
| Workout in background (any non-ride screen) | per screen | Back; **hold = return to the ride** | per screen | ride bindings never act here |
| Disconnected from the iPhone | same buttons; Pause / Lap / End are refused at once with "Unable to …" | same | same | same |
| Touch locked | **works** | **works** | **works** (hold = unlock) | all work; touches and swipes are ignored |
| Confirmation open (End, restart warning) | activate the highlighted choice | Cancel | move highlight | L1 hold does nothing |
| Starting up (≤ 0.6 s) | ignored | ignored | **never hold: download mode** | R1 resets |

## Firmware-only screens and overlays (not in the prototype)

| Screen | Status | L1 | R2 | L2 | Notes |
|---|---|---|---|---|---|
| Restart warning (during a ride) | IMPLEMENTED (NEW, owner G5) | activate highlighted (opens on Cancel) | Cancel ↔ Restart | Cancel | wording NEW — owner review |
| End-request ring (L1 held on a ride page / Controls) | IMPLEMENTED (NEW, G8) | release before 2 s = nothing | — | — | "Hold to end" panel + ring round the edge |
| Restart countdown (L1 + L2 held) | IMPLEMENTED (NEW, G6) | release = cancel | independent | release = cancel | "Restart in N · Release to cancel" |
| Touch-lock chip | IMPLEMENTED (G4) | buttons work | hold = unlock | buttons work | "LOCKED · HOLD NEXT" (was "LOCKED · HOLD KEY 1"); in a ride it replaces the Pause button, which cannot be tapped while locked |
| "Not in this release" page | IMPLEMENTED (RC1) | Menu | — | Back | |
| Start-up (first 0.6 s) | not designed | — | **do not hold** | — | |
| Screen off | designed in v2, not in v3 | wake | wake | wake | |

## Every designed screen (prototype v3.3, 89 screens)

### Face

| Screen | Name | Status | Stage 1.4 RC1 (offline) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `face` | Watch face | IMPLEMENTED | as approved [SIM] | Menu | Next widget (Health) | — (already home) | Quick Settings | — (already home) |
| `w-health` | Widget · Health | PARTIAL — L1 opens "Not in this release" (Health app not built) | as approved [SIM] | Open that widget's app (Health / Coach / Activity) | Next widget (… → face) | Face | Quick Settings | Face |
| `w-coach` | Widget · Coach | PARTIAL — L1 opens "Not in this release" (Coach app not built) | as approved [SIM] | Open that widget's app (Health / Coach / Activity) | Next widget (… → face) | Face | Quick Settings | Face |
| `w-activity` | Widget · Activity rings | PARTIAL — L1 opens "Not in this release" (History not built) | as approved [SIM] | Open that widget's app (Health / Coach / Activity) | Next widget (… → face) | Face | Quick Settings | Face |
| `qs` | Quick Settings | PARTIAL — 5 rows, RAM only | as approved [SIM] | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `fpick` | Face picker | DESIGNED (prototype v3.3) | not in firmware | Use this face | Next face | Back (keep face) | — | Home |
| `fcomp` | Complications | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |

### Menu

| Screen | Name | Status | Stage 1.4 RC1 (offline) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `menu` | App menu | PARTIAL — 8 rows; Today and Activities (simulated ride) open, 5 rows open "Not in this release" | as approved [SIM] | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |

### Today

| Screen | Name | Status | Stage 1.4 RC1 (offline) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `today` | Today | IMPLEMENTED | as approved [SIM] | Start the planned session (if any), else Menu | Week strip | Back | Quick Settings | Home (or the workout) |
| `today-plan` | Planned session detail | DESIGNED (prototype v3.3) | not in firmware | Start this session | Scroll | Back | Quick Settings | Home (face; in a workout: the workout) |
| `today-week` | Week strip | PARTIAL — R2 does nothing (no further page yet) | as approved [SIM] | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |

### Activities

| Screen | Name | Status | Stage 1.4 RC1 (offline) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `act` | Activities | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `review` | Review | DESIGNED (prototype v3.3) | not in firmware | Start (after the sensor check) | Next field (sport / route) | Back | Quick Settings | Home (or the workout) |
| `sensors` | Sensor check | DESIGNED (prototype v3.3) | not in firmware | Re-scan / continue | Next sensor | Back | Quick Settings | Home (face; in a workout: the workout) |
| `starting` | Starting (pending) | DESIGNED (prototype v3.3) | not in firmware | — | — | Cancel where the screen allows it (Starting), else — | — | — |
| `start-fail` | Start refused | DESIGNED (prototype v3.3) | not in firmware | Retry | — | Back | — | Cancel |

### Strength

| Screen | Name | Status | Stage 1.4 RC1 (offline) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `st-set` | Set editor | DESIGNED (prototype v3.3) | not in firmware | Primary / confirm: Controls with Pause highlighted; 2nd L1 = Pause | Next field (Reps → Weight) then next page | Two-press: Log Set | End request (2 s) | Set page |
| `st-reps` | Edit reps | DESIGNED (prototype v3.3) | not in firmware | Confirm (keep the new value) | Increase (+1 step) | Decrease (−1 step) — the one exception to "L2 = Back" (G10) | — | Cancel (old value kept) |
| `st-kg` | Edit Weight | DESIGNED (prototype v3.3) | not in firmware | Confirm (keep the new value) | Increase (+1 step) | Decrease (−1 step) — the one exception to "L2 = Back" (G10) | — | Cancel (old value kept) |
| `st-rest` | Rest timer | DESIGNED (prototype v3.3) | not in firmware | Controls | Next / +15 s | Two-press: Skip rest | End request (2 s) | Set page |
| `st-next` | Up next · exercise list | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted exercise | Move highlight | Two-press: Log Set | End request (2 s) | Set page |
| `st-ctl` | Strength controls | DESIGNED (prototype v3.3) | not in firmware | Activate the highlighted control | Move highlight (Pause/Resume → Lap → End → Why? → Menu) | Close controls (back to the same page) | End request (2 s) | Cockpit |
| `st-instr` | Exercise instructions | DESIGNED (prototype v3.3) | not in firmware | Back to the set | Scroll | Back | End request (2 s) | Set page |
| `st-sub` | Substitute exercise | DESIGNED (prototype v3.3) | not in firmware | Choose the highlighted exercise | Next exercise | Back (keep current) | End request (2 s) | Set page |
| `st-auto` | Rep count (experimental) | DESIGNED (prototype v3.3) | not in firmware | Primary / confirm: Controls with Pause highlighted; 2nd L1 = Pause | Next field (Reps → Weight) then next page | Two-press: Log Set | End request (2 s) | Set page |
| `st-sync` | Offline sync result | DESIGNED (prototype v3.3) | not in firmware | OK | Next result | Back | — | Cancel |

### Cycling

| Screen | Name | Status | Stage 1.4 RC1 (offline) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `ride-cockpit` | Cockpit | PARTIAL — cockpit + Power / HR / Cadence pages (Bike mode: cockpit + Power); pacing, climb, navigation, coach pages not built; simulated data | as approved [SIM] | Controls opened with Pause / Resume highlighted; a 2nd deliberate L1 = Pause / Resume | Next data page (wraps) | 1st press: "Press again for Lap"; 2nd within 2.5 s: Lap | End request (ring fills over 2 s → End confirmation, Cancel highlighted) | First data page (cockpit) |
| `ride-power` | Performance · Power | IMPLEMENTED | as approved [SIM] | Controls opened with Pause / Resume highlighted; a 2nd deliberate L1 = Pause / Resume | Next data page (wraps) | 1st press: "Press again for Lap"; 2nd within 2.5 s: Lap | End request (ring fills over 2 s → End confirmation, Cancel highlighted) | First data page (cockpit) |
| `ride-hr` | Performance · Heart rate | IMPLEMENTED | as approved [SIM] | Controls opened with Pause / Resume highlighted; a 2nd deliberate L1 = Pause / Resume | Next data page (wraps) | 1st press: "Press again for Lap"; 2nd within 2.5 s: Lap | End request (ring fills over 2 s → End confirmation, Cancel highlighted) | First data page (cockpit) |
| `ride-cad` | Performance · Cadence | IMPLEMENTED | as approved [SIM] | Controls opened with Pause / Resume highlighted; a 2nd deliberate L1 = Pause / Resume | Next data page (wraps) | 1st press: "Press again for Lap"; 2nd within 2.5 s: Lap | End request (ring fills over 2 s → End confirmation, Cancel highlighted) | First data page (cockpit) |
| `ride-pacing` | Pacing · interval | DESIGNED (prototype v3.3) | not in firmware | Controls opened with Pause / Resume highlighted; a 2nd deliberate L1 = Pause / Resume | Next data page (wraps) | 1st press: "Press again for Lap"; 2nd within 2.5 s: Lap | End request (ring fills over 2 s → End confirmation, Cancel highlighted) | First data page (cockpit) |
| `ride-climb` | Climb | DESIGNED (prototype v3.3) | not in firmware | Controls opened with Pause / Resume highlighted; a 2nd deliberate L1 = Pause / Resume | Next data page (wraps) | 1st press: "Press again for Lap"; 2nd within 2.5 s: Lap | End request (ring fills over 2 s → End confirmation, Cancel highlighted) | First data page (cockpit) |

### Workout

| Screen | Name | Status | Stage 1.4 RC1 (offline) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `wk-nav` | Navigation | DESIGNED (prototype v3.3) | not in firmware | Controls opened with Pause / Resume highlighted; a 2nd deliberate L1 = Pause / Resume | Next data page (wraps) | 1st press: "Press again for Lap"; 2nd within 2.5 s: Lap | End request (ring fills over 2 s → End confirmation, Cancel highlighted) | First data page (cockpit) |
| `wk-coach` | Coach (in workout) | DESIGNED (prototype v3.3) | not in firmware | Controls opened with Pause / Resume highlighted; a 2nd deliberate L1 = Pause / Resume | Next data page (wraps) | 1st press: "Press again for Lap"; 2nd within 2.5 s: Lap | End request (ring fills over 2 s → End confirmation, Cancel highlighted) | First data page (cockpit) |
| `wk-ctl` | Workout controls | PARTIAL — Lap, Pause/Resume, End, Why? (opens "Not in this release"), Menu; Large Text / long Arabic labels: list | as approved [SIM] | Activate the highlighted control | Move highlight (Pause/Resume → Lap → End → Why? → Menu) | Close controls (back to the same page) | End request (2 s) | Cockpit |
| `wk-paused` | Paused | DESIGNED (prototype v3.3) | not in firmware | Controls with Resume highlighted; 2nd L1 = Resume | Next data page | Two-press: Lap | End request (2 s) | Cockpit |
| `wk-end` | End confirmation | PARTIAL — Cancel / End; Discard not built (no iPhone command yet) | as approved [SIM] | Activate the highlighted choice (opens on Cancel; End sends End to the iPhone) | Highlight Cancel ↔ End | Cancel (back to the ride page) | — | Cancel |
| `wk-saving` | Saving on iPhone | DESIGNED (prototype v3.3) | not in firmware | — | — | Cancel where the screen allows it (Starting), else — | — | — |
| `wk-summary` | Summary | DESIGNED (prototype v3.3) | not in firmware | Done (close summary → face) | Scroll | Back to the summary list top | Quick Settings | Face |

### Running

| Screen | Name | Status | Stage 1.4 RC1 (offline) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `run-cockpit` | Run cockpit | DESIGNED (prototype v3.3) | not in firmware | Controls opened with Pause / Resume highlighted; a 2nd deliberate L1 = Pause / Resume | Next data page (wraps) | 1st press: "Press again for Lap"; 2nd within 2.5 s: Lap | End request (ring fills over 2 s → End confirmation, Cancel highlighted) | First data page (cockpit) |
| `run-splits` | Splits | DESIGNED (prototype v3.3) | not in firmware | Controls opened with Pause / Resume highlighted; a 2nd deliberate L1 = Pause / Resume | Next data page (wraps) | 1st press: "Press again for Lap"; 2nd within 2.5 s: Lap | End request (ring fills over 2 s → End confirmation, Cancel highlighted) | First data page (cockpit) |

### Walking

| Screen | Name | Status | Stage 1.4 RC1 (offline) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `walk-cockpit` | Walk cockpit | DESIGNED (prototype v3.3) | not in firmware | Controls opened with Pause / Resume highlighted; a 2nd deliberate L1 = Pause / Resume | Next data page (wraps) | 1st press: "Press again for Lap"; 2nd within 2.5 s: Lap | End request (ring fills over 2 s → End confirmation, Cancel highlighted) | First data page (cockpit) |

### Health

| Screen | Name | Status | Stage 1.4 RC1 (offline) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `health` | Health | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `h-hr` | Heart rate (day) | DESIGNED (prototype v3.3) | not in firmware | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `h-sleep` | Sleep | DESIGNED (prototype v3.3) | not in firmware | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `h-hrv` | HRV | DESIGNED (prototype v3.3) | not in firmware | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `h-rec` | Recovery / readiness | DESIGNED (prototype v3.3) | not in firmware | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `h-load` | Training load | DESIGNED (prototype v3.3) | not in firmware | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `h-vitals` | Vitals (unavailable sources) | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `h-trends` | Trends | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |

### Coach

| Screen | Name | Status | Stage 1.4 RC1 (offline) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `coach` | Coach | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `co-why` | Why this workout? | DESIGNED (prototype v3.3) | not in firmware | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `co-last` | Last workout feedback | DESIGNED (prototype v3.3) | not in firmware | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `co-week` | Weekly review | DESIGNED (prototype v3.3) | not in firmware | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `co-goal` | Week focus · goal | DESIGNED (prototype v3.3) | not in firmware | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `co-ask` | Ask on iPhone (hand-off) | DESIGNED (prototype v3.3) | not in firmware | Send to iPhone | — | Back | — | Cancel |

### History

| Screen | Name | Status | Stage 1.4 RC1 (offline) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `hist` | History list | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `hi-ride` | Workout detail | DESIGNED (prototype v3.3) | not in firmware | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `hi-laps` | Laps | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `hi-lift` | Strength detail · sets | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `hi-trends` | Weekly and monthly trends | DESIGNED (prototype v3.3) | not in firmware | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |

### Utilities

| Screen | Name | Status | Stage 1.4 RC1 (offline) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `util` | Utilities | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `ut-notif` | Notifications | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `ut-notif-d` | Notification detail | DESIGNED (prototype v3.3) | not in firmware | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `ut-call` | Incoming call | DESIGNED (prototype v3.3) | not in firmware | Silence ringing (answering stays on the iPhone) | — | Dismiss | — | Cancel |
| `ut-music` | Music controls | DESIGNED (prototype v3.3) | not in firmware | Play / pause | Next track | Back | Previous track | Home (or the workout) |
| `ut-alarm` | Alarms | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `ut-sw` | Stopwatch | DESIGNED (prototype v3.3) | not in firmware | Start / stop | Split | Back (stopwatch keeps running) | Reset (stopped only) | Home (or the workout) |
| `ut-timer` | Timers | DESIGNED (prototype v3.3) | not in firmware | Start / pause | +1 min | Back (timer keeps running) | Reset | Home (or the workout) |
| `ut-water` | Hydration log | DESIGNED (prototype v3.3) | not in firmware | +1 glass | — | Back | Undo last glass | Home (or the workout) |
| `ut-find` | Find phone | DESIGNED (prototype v3.3) | not in firmware | Stop ringing | — | Back | — | Cancel |

### Settings

| Screen | Name | Status | Stage 1.4 RC1 (offline) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `set` | Settings | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `se-display` | Display | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `se-appear` | Appearance | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `se-theme` | Theme picker | DESIGNED (prototype v3.3) | not in firmware | Choose the shown item and go back | Next item | Back without changing | — | Home |
| `se-work` | Workout settings | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `se-pages` | Customize cycling pages | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `se-buttons` | Button layout (provisional) | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `se-haptic` | Haptics | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `se-lang` | Language and digits | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `se-conn` | Connections | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `se-feat` | Feature availability | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `se-feat-d` | Feature availability detail | DESIGNED (prototype v3.3) | not in firmware | Primary action of the page if it has one (e.g. Today: Start), else Menu | Next page / scroll down | Back | Quick Settings | Home (or the workout) |
| `se-about` | About | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |
| `se-diag` | Diagnostics | DESIGNED (prototype v3.3) | not in firmware | Open the highlighted row | Move highlight down (wraps) | Back | Quick Settings | Home (face; in a workout: the workout) |

### System

| Screen | Name | Status | Stage 1.4 RC1 (offline) | L1 short | R2 short | L2 short | L1 hold | L2 hold |
|---|---|---|---|---|---|---|---|---|
| `sys-loading` | Loading (syncing) | DESIGNED (prototype v3.3) | not in firmware | — | — | Cancel where the screen allows it (Starting), else — | — | — |
| `alert-hr` | High heart rate alert | DESIGNED (prototype v3.3) | not in firmware | Acknowledge | — | Dismiss | — | Cancel |
| `alert-batt` | Low battery | DESIGNED (prototype v3.3) | not in firmware | Acknowledge | — | Dismiss | — | Cancel |
| `wk-banner` | Notification banner over a workout | DESIGNED (prototype v3.3) | not in firmware | Open the notification | Dismiss | Dismiss | — | Dismiss → workout |


## Functions that stay touch-only (by choice)
- Discard a workout (hold-to-discard on the End screen): deliberately not on a button.
- Typing or free selection on long lists: R2 steps through them, but touch is faster.
- Chart scrubbing (History, Health trends).
- Quick Settings brightness levels can be stepped by R2 + L1, but touch is quicker.
