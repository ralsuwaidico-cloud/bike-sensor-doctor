# Cyclift Watch — current button behaviour (12 Nov 2026)

Sources:
- firmware: RC1, which is installed, and RC2, which is offline. Their button behaviour is identical (`cyv3_model.hpp`
  key1 / key2 / key1Hold, `v3poc_main.cpp`);
- the approved prototype v3.3 (`app.js`);
- the older v2 design (`docs/BUTTONS.md`, `domain/buttons.hpp`), which is not running and is superseded by v3.

Verification marks:
- **HW** = seen on the watch (log or owner);
- **SIM** = computer tests (`test_nav.cpp` oracle: every screen × input, EN/AR, during a ride);
- **—** = not implemented.

## 1. Screens and their status

### In the watch firmware today (RC1; RC2 identical)

| Screen | Status |
|---|---|
| Orbit face | implemented |
| Widgets Health / Coach / Activity | implemented (empty states) |
| Quick Settings | implemented (5 rows, RAM only) |
| App menu | implemented (8 rows; Today and Activities work; 5 rows open "Not in this release") |
| Today | implemented |
| Week | implemented |
| "Not in this release" page | implemented (RC1 only, not in the design) |
| Cycling cockpit, wrist / bike / gym layouts | partial (cockpit page only; paused state and Pause / Resume on screen; no other data pages, no controls overlay, no End) |
| Screen-lock overlay | implemented |

**Not in firmware:** 80 of the 89 designed screens. The full list, with status, is in BUTTON_SCREEN_MATRIX.md.

**Not designed anywhere:**
- start-up screen;
- screen-off / sleep state;
- pairing flow (only "Connections" in Settings is designed).

## 2. What each button does now (firmware)

| Button | Short press | Long press | Double press | Chords |
|---|---|---|---|---|
| **L1** (GPIO35) | Menu from any screen; on the menu → face, or back to the workout if one runs (HW). Ignored when locked (HW) | **Hold ≥ 1 s: unlock** (HW 11 Nov). Does nothing when not locked | — | — |
| **L2** (GPIO34) | Back (HW). On the cockpit during a ride: 1st press arms "Lap" for 2.5 s (HW) | — | **Cockpit during a ride: 2nd press within 2.5 s = Lap** (HW 12 Nov: 5 laps confirmed) | — |
| **R1** (Reset) | restarts the watch (hardware) | same | same | — |
| **R2** (Boot) | **nothing** (HW: B2, no event) | nothing (held during a start = download mode) | nothing | — |

### Per implemented screen

| Screen | L1 | L2 | L1 hold | R2 |
|---|---|---|---|---|
| Face | Menu (HW) | nothing visible: back with empty history stays on the face (SIM) | unlock if locked | — |
| Widgets | Menu (SIM) | Face (SIM) | unlock | — |
| Quick Settings | Menu (SIM) | Back (SIM) | unlock | — |
| Menu | Face / workout (HW) | Back (HW) | unlock | — |
| Today, Week, Not-in-release | Menu (SIM) | Back: Today → previous; Week → Today (owner HW 11 Nov: Today → menu) | unlock | — |
| Cockpit, ride active or paused | Menu (HW 12 Nov) | two-press Lap (HW) | unlock | — |
| Locked (any screen) | ignored (HW) | ignored (SIM) | **unlock (HW)** | — |

## 3. Findings

1. **R2 does nothing.** A readable button is unused.
2. **No button pauses or resumes.** Pause / Resume is touch-only (cockpit buttons). With gloves or in rain this is the
   most important missing button function.
3. **No End workout at all.** Neither a button nor touch ends a ride in the firmware; it is in the design only.
4. **No way to change ride data pages.** The firmware has only one page. The design uses swipes only, so there is no
   button path.
5. **L1 on the cockpit opens the app menu.** This leaves the ride view, and two presses go menu → back to the ride.
   The approved design says L1 = workout Controls. The 12 Nov log shows 15 L1 events during a lap test; if they were
   unintended, the owner was taken off the ride screen repeatedly.
6. **L2 on the face does nothing visible.** This is an inconsistency: the button gives no feedback.
7. **Lap needs two presses, but there is no "press again" feedback in Bike mode** (the chip is shown, design V8;
   unverified on the watch).
8. **Lock blocks the buttons too.** Approved prototype behaviour, but it means the cyclist cannot Lap while the screen is
   locked against rain. Most sport watches lock touch only.
9. **Touch-only functions** (no button path): Quick Settings rows, widgets → apps, Today → Start, Week link, all menu
   rows except "close", Pause / Resume, simulated-ride start.
10. **No debounce in the v3 firmware.** v2 had one (30 ms); v3 acts on the raw edge. No bounce has been seen (B2 10/10),
    but there is no protection.
11. **Conflict in the approved prototype:** hold L1 = unlock when locked, but = End during a workout. In a locked workout
    one hold unlocks; a second hold asks to End. That is acceptable but needs to be known.
12. **Pinch risk** (BUTTON_HARDWARE_AUDIT §3): pressing L1 may press R1 (Reset) opposite it. Not proven.

## 4. Earlier designs, for reference (not running)

- **v2, 8 Nov:**
  - L1 short = Pause / Resume, hold = End request.
  - L2 short = Lap / Log Set.
  - R2 hold = Quick Settings / Home.
  - Every physical action needed two presses (preview → confirm).
- **v3 prototype (approved V8 "provisional"):**
  - Key 1 = Menu, or Controls during a workout.
  - Key 2 = Back, or two-press Lap / Log Set.
  - Hold Key 1 = End (confirmed) / unlock.
  - R2 unused.

Neither is approved as final; this study replaces both once decided.
