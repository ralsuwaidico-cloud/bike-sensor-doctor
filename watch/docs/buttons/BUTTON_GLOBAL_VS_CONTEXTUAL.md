# Cyclift Watch — global vs contextual vs hybrid button models (12 Nov 2026)

Constraints from the hardware audit:
- three readable buttons: L1, L2 and R2;
- R2 doubles as the recovery (Boot) button;
- R1 is a hardware reset;
- there is a possible pinch risk L1 ↔ R1.

## A. Global: every button does the same everywhere

Example: L1 = Menu, L2 = Back, R2 = Next, always.

| | |
|---|---|
| **Pros** | Easiest to learn. Predictable without looking. No mode errors. |
| **Cons** | Three buttons cannot hold Pause, Lap, Log Set, End and Next as fixed meanings. Workout actions would be buried behind Menu → tap, which is impossible with gloves or eyes-on-road. Fails the core cycling and gym use. |
| **Gloves / one hand** | good for navigation; bad for workouts (touch needed) |
| **Accidental presses** | low harm (navigation only) |
| **Screen lock** | simple |

## B. Contextual: every screen redefines every button

Example: the v2 8 Nov map.

| | |
|---|---|
| **Pros** | Every screen gets the best possible use of each button; workout actions are one press away. |
| **Cons** | Hard to learn: the same button means Back here, Pause there, Confirm elsewhere. Risk of mode errors (pressing "Back" pauses a ride). Every screen needs on-screen hints. Testing load grows with every screen. |
| **Gloves / one hand** | good once learned |
| **Accidental presses** | higher harm: a destructive meaning may sit on a button the user expects to be harmless |
| **Screen lock** | each screen needs its own lock rules |

## C. Hybrid: a few fixed meanings, the rest adapts

The recommended model.

**Fixed meanings, always the same:**

| Button | Meaning everywhere |
|---|---|
| **L2** | "get me out": Back, Cancel, Dismiss. Hold L2 = Home, or the workout during a workout. |
| **R2** | "next": next page, next item, move highlight, scroll. Hold R2 = touch lock on / off. |
| **L1** | "do it / primary": Menu on screens without a primary action, otherwise that screen's primary action. |

**Adapts only inside an active workout** (one clear context, with a visible key hint):
- L2 two-press = Lap (cycling) / Log Set (gym) / Skip rest (rest timer);
- L1 hold = End request.

**Exceptions, kept to a minimum:**
- value editors (reps / weight): L2 = −1, R2 = +1, L1 = Done;
- dialogs: L1 = Confirm, L2 = Cancel. This matches the fixed meanings.

| | |
|---|---|
| **Pros** | Learnable in three words (do / back / next). Workout actions without touch. Destructive actions need a hold with a countdown. Navigation stays predictable. Uses all three readable buttons, and puts no critical action on R2. |
| **Cons** | Workout mode changes L2's meaning; mitigated by the "press again for Lap" preview and an on-screen key hint. The editor exception must be shown on screen. |
| **Gloves** | every workout action is reachable by buttons; nothing needs fine touch |
| **Accidental presses** | Lap / Log Set need two presses within 2.5 s. End and destructive confirms need a 2 s hold with a visible countdown that can be cancelled by releasing. Pause needs L1 twice (Controls → Pause), so a brushed button cannot pause. |
| **Screen lock** | locks touch only; buttons keep working (they are deliberate), so Lap and Pause still work in rain. Owner decision G4. |
| **One-handed** | the watch is on one wrist, so all operation is one-handed by the other hand. Single-button actions everywhere except the restart chord. |

## Priority when meanings conflict

Highest first:
1. **Hardware:** R1 resets; R2 held at a start = download mode. Firmware cannot override either.
2. **Restart chord** (L2 + R2 held): cancels any pending single-button action as soon as both are held for 400 ms.
3. **Open dialog / confirmation:** its Confirm / Cancel win over everything below.
4. **Active-workout bindings** (Lap / Log Set / End / Controls) on workout pages and their overlays.
5. **Screen-specific primary action** (L1) and page navigation (R2).
6. **Global fixed meanings** (L2 Back / Home, R2 hold lock).
7. **Lock:** if the owner chooses "lock blocks buttons too", it sits above 4–6 but below 1–3.

**Background workout:** outside the workout pages (menu, Today …) the global meanings apply, and hold L2 returns to the
workout. Workout bindings never act from a non-workout screen, so a Lap is never recorded by accident from the menu.
