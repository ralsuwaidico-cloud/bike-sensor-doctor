# Cyclift Watch — button-only scenarios under the proposal (12 Nov 2026)

Proposal: BUTTON_UX_RECOMMENDATION.md.
- **L1** = Select;
- **L2** = Back;
- **R2** = Next.
"Hold" = 1 s unless stated. "Today" means: what the current firmware (RC1 / RC2) can do.

| # | Scenario | Button-only sequence (proposal) | Touch needed under the proposal? | Today (firmware) |
|---|---|---|---|---|
| 1 | **Start a cycling session** | From the face: L1 (Menu) → R2 until "Activities" is highlighted → L1 → "Ride" highlighted → L1 → sensor check → L1 (Start). Faster with a planned ride: L1 (Menu, Today highlighted first) → L1 (Today) → **L1 = Start** | No, once the list highlight (G9) exists | Touch only (Menu row or Today Start) |
| 2 | **Change data pages while riding** | R2 = next page (cockpit → power → HR → cadence → pacing → climb → navigation → coach → cockpit; Bike mode has 4 pages). Hold L2 jumps back to the cockpit | No | Not possible: one page only |
| 3 | **Record laps** | L2, L2 within 2.5 s → "Lap 3" toast + haptic. A single L2 shows "Press again for Lap" and expires | No | **Works** [HW 12 Nov] |
| 4 | **Pause and resume** | L1 (Controls open, Pause highlighted) → L1 = Pause. Resume: L1 (Controls, Resume highlighted) → L1. Touch Pause / Resume remains one tap | No | Touch only |
| 5 | **End a cycling session safely** | Hold L1 for 2 s (ring fills; releasing cancels) → End confirmation → hold L1 for 2 s = End and save; L2 = Cancel. Discard: touch only (hold-to-discard) | No (Discard by design yes) | Not implemented |
| 6 | **Start a gym workout** | As #1 with "Strength", or Today → L1 = Start if a strength session is planned | No (with G9) | Not implemented |
| 7 | **Complete a set** | L2, L2 = Log Set → rest timer starts | No | Not implemented |
| 8 | **Edit reps and weight** | On the set page: R2 highlights Reps → L1 opens the editor → R2 = +1 / L2 = −1 (holds repeat) → L1 = Done; R2 highlights Weight → same with 2.5 kg steps | No | Not implemented |
| 9 | **Navigate while a workout runs in the background** | From any workout page: L1 → Controls → R2 to "Menu" → L1. Browse with L1 / R2 / L2. **Hold L2 from anywhere = back to the workout.** Workout bindings (Lap etc.) do not act on non-workout screens | No | Partly: L1 = Menu from the cockpit, and on the menu L1 returns to the workout |
| 10 | **Return Home from any screen** | Hold L2 → face (or the workout, during one) | No | Repeated L2 presses, or L1 on the menu |
| 11 | **Lock and unlock** | Hold R2 → touch lock on; hold R2 again → off. Buttons keep working while locked (G4) | No | Lock: touch only (Quick Settings row). Unlock: hold L1 ≥ 1 s [HW] |
| 12 | **Restart the watch** | Hold L2 + R2. After 2 s the countdown is visible; at 10 s "release to restart" → release both → logged restart | No | R1 (hardware reset) only: instant, unconfirmed |

## Scenarios that still need touch
- **None of the 12**, once the list highlight (G9), the Controls overlay and the hold-countdown are built.
- **By choice:** Discard a workout, chart scrubbing, and any typing.
- **Until the list highlight exists**, scenarios 1, 6 and 9 (choosing a menu row) need touch.
