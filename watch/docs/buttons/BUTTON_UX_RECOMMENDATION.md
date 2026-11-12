# Cyclift Watch — recommended four-button architecture (12 Nov 2026) — PROPOSAL, nothing implemented

Inputs:
- BUTTON_HARDWARE_AUDIT.md;
- BUTTON_CURRENT_BEHAVIOR.md;
- BUTTON_GLOBAL_VS_CONTEXTUAL.md;
- the full per-screen table in BUTTON_SCREEN_MATRIX.md.

## 1. Recommendation: hybrid model, "do / back / next"

| Button | Name on screen | Fixed meaning | Hold (1 s) | Why this button |
|---|---|---|---|---|
| **L1** (left upper) | **Select** | Primary action of the screen; Menu where there is none. In a workout: Controls, with a 2nd press = Pause / Resume | Quick Settings outside a workout; **End request (2 s countdown)** in a workout | Free GPIO with no hardware role, so it is safe for the most important actions. Upper position = "go / do" |
| **L2** (left lower) | **Back** | Back / Cancel / Dismiss. In a workout page: **two-press = Lap / Log Set / Skip rest** | **Home** (the face; during a workout: back to the workout) | Free GPIO; the button most pressed while riding, at the natural thumb position |
| **R2** (right lower, Boot) | **Next** | Next page / item / widget; move the highlight; scroll | **Touch lock on / off** | Readable but it is the recovery button, so it only gets non-critical, harmless actions |
| **R1** (right upper, Reset) | — | hardware restart (cannot be changed) | — | not readable by firmware |

### Why this design
- **Workout functions are one or two presses away, with no touch:**
  - Lap / Log Set = L2 twice;
  - Pause / Resume = L1 twice;
  - End = hold L1 for 2 s, then hold again on the confirmation;
  - next page = R2.
- **Mistakes are safe:**
  - one brushed press never records, pauses or ends anything;
  - destructive actions need a held countdown that can be cancelled by releasing;
  - Discard stays touch-only.
- **Learnable:** three words. L2 always gets you out; R2 always moves on; L1 always does the thing on screen.
- **Hardware-aware:**
  - nothing critical on R2 (Boot);
  - nothing on R1 (Reset);
  - restart never happens while R2 is held (§5).
- **Consistent with the approved design:**
  - Key 1 = Controls in a workout (correction 1);
  - Key 2 two-press = Lap / Log Set (V8);
  - End confirmed (wk-end).

  New: R2 is used; Pause gets a button path; L2 hold = Home; lock moves to R2 hold.

## 2. Global functions

| Function | Button | Where |
|---|---|---|
| Back / Cancel / Dismiss | L2 | every screen except value editors, where L2 = −1 |
| Home (face) / back to the workout | L2 hold 1 s | every screen |
| Next / scroll / highlight | R2 | every screen |
| Touch lock on / off | R2 hold 1 s | every screen (fires only if L2 is not pressed, so it does not clash with the restart chord) |
| Restart | L2 + R2 held 10 s | every screen (§5) |
| Wake (future, when sleep exists) | any button; the press is only consumed to wake | every screen |

## 3. Screen-specific functions (main ones; every screen in BUTTON_SCREEN_MATRIX.md)

| Screen | L1 | R2 | L2 | Development needed |
|---|---|---|---|---|
| Face | Menu | Next widget | — | R2 handling |
| Widgets | Open the app | Next widget | Face | R2, widget → app (apps not built) |
| Menu and all lists | Open the highlighted row | Move highlight | Back | **new: a visible highlight (focus ring) on list rows**, a new design element that needs owner approval of its look |
| Today | Start the planned session | Week | Back | small |
| Ride pages | Controls → Pause / Resume | Next page | two-press Lap | Controls overlay, data pages, page cycling (Stage 3 design exists) |
| Controls overlay | Activate highlighted | Move highlight | Close | overlay (designed) + highlight |
| End confirmation | hold 2 s = End and save | Cancel ↔ End | Cancel | designed, plus hold-countdown component |
| Strength set page | Controls → Pause | Next field (Reps → Weight) | two-press Log Set | strength flow (designed, not built) |
| Reps / weight editor | Done | +1 (hold repeats) | −1 (hold repeats) | editor exception, with "− ✓ +" key hints |
| Rest timer | Controls | +15 s | two-press Skip | rest screen (designed) |
| Dialogs | Confirm | Move highlight | Cancel | dialog component |

### Conflicts resolved
- **Hold L1:** in the prototype it means both "unlock" and "End". The proposal moves unlock to R2 hold, so hold L1
  means only End (in a workout) or Quick Settings (outside one).
- **L2 single press on a workout page** only previews "Press again for Lap". It no longer means Back there; leave the
  ride page with hold L2 / L1 → Menu. This matches the approved V8 behaviour.
- **Bracing / pinch:** an R2 press during an L2 press counts toward the restart chord only after both have been held
  for 1 s. Shorter overlaps are ignored, so the L2 action is kept.

## 4. Lock behaviour (decision G4)
**Proposal:** the lock blocks touch only (rain, sweat, jersey); buttons keep working because they are deliberate.
- The lock chip text becomes "Touch locked · hold Next".
- **Alternative** (the approved prototype): the lock also blocks buttons, except the unlock hold. This is safer against
  pocket presses, but no Lap or Pause in the rain without unlocking first.

## 5. Restart shortcut: L2 + R2 held 10 s

**Feasible.** Both are readable inputs (GPIO34 + GPIO0) and the firmware polls them every ~10 ms.

| Aspect | Specification |
|---|---|
| Detection | both pressed (debounced 30 ms) and both continuously held. A chord starts when the second button goes down within 1 s of the first. |
| Suppressing other actions | once both have been held for 400 ms, cancel any pending L2 preview (Lap / Log Set armed), the L2 hold-Home timer and the R2 hold-lock timer. No other action fires until both are released. Because short presses act on release, nothing has fired yet at the moment the chord is recognised. |
| Countdown | after 2 s held, show a full-screen countdown "Restart in 8 … 1 · release to cancel" with a closing ring. At 10 s: "Release both buttons to restart". |
| Cancellation | releasing either button before 10 s cancels, with no side effects. |
| **Execution** | **only after both buttons are released** (and 300 ms have passed). This guarantees R2 / GPIO0 is high when the chip restarts, so the chip can never land in download mode, whether or not a firmware restart re-reads that pin (not yet verified). |
| Active session | if a workout is active, the countdown screen says "Workout in progress: restart keeps what the iPhone has". Today the watch keeps no workout data that the iPhone does not already have, because the iPhone owns the record. Pending unsent commands would be lost, so they are shown as a count ("2 commands not sent"). Once a persistent command queue exists (design correction 3), it is flushed to storage before restarting. |
| Logging | before restarting, the firmware writes "user restart (buttons)" plus the time into RTC memory, which survives a firmware restart. The next start prints it with the reset reason (RC2 already prints the reset reason and start count). It also appears in Settings → About → Diagnostics. |
| Why 10 s | long enough that a pinch or bracing can never trigger it. A shorter hold (e.g. 5 s) is possible; owner decision G6. |

**Alternative if the owner prefers not to use R2:** L1 + L2 held 10 s (both free GPIOs) works the same way, but both
buttons are on the same side (one-thumb chord), which is easier to press by accident against a cycling jersey.
R1 (Reset) stays the emergency hardware restart. It needs no firmware, but it is instant, unconfirmed, and unlogged
except as "power-on / external".

## 6. What needs firmware work (none started)

| Item | Effort | Depends on |
|---|---|---|
| Key decoder (debounce, hold, two-press, chord) for L1 / L2 / R2 | small (the v2 `KeyDecoder` exists and is host-tested; extend it with chords) | — |
| R2 reading in v3 | trivial (the driver already has `boot()`) | — |
| Focus highlight on lists and controls | medium + design approval | owner approves the look |
| Controls overlay, End confirmation, ride data pages | medium (designed) | Stage 3 approval |
| Hold-countdown ring component | small | — |
| Strength pages, editors, rest timer | large (designed) | strength stage |
| Restart chord | small | approval G5–G6 |
| Lock = touch only | trivial | decision G4 |

**Hardware support:** everything above uses only L1, L2 and R2 as ordinary inputs. Nothing needs R1. Nothing needs
new hardware.

## 7. Decisions requiring owner approval
- **G1** Run the 1-minute button-identification check (recorder on; press L1, L2, R2 once each; optionally R1, which
  restarts the watch). It confirms the positions in this study.
- **G2** Adopt the hybrid "do / back / next" model (L1 Select · L2 Back · R2 Next), replacing the provisional V8
  mapping.
- **G3** Use R2 (Boot) for non-critical actions (next / scroll / lock), never for workout-critical ones.
- **G4** Lock = touch only (buttons keep working), or keep the approved lock-everything behaviour.
- **G5** Restart chord L2 + R2, or L1 + L2.
- **G6** Hold length: 10 s as proposed, or shorter.
- **G7** Pause by button = L1 twice (Controls → Pause), or a faster single "L1 hold" (but hold L1 is End in this
  proposal).
- **G8** End = hold L1 for 2 s, then hold again on the confirmation. Discard stays touch-only.
- **G9** Add a list highlight (focus ring) so lists and menus can be used by buttons alone. It is a new visual element.
- **G10** Editors: L2 = −1 / R2 = +1 / L1 = Done (the one exception to "L2 = Back").
- **G11** The physical check of the pinch risk: is R1 (Reset) recessed, and does pressing L1 press it?
