# Physical buttons — what the hardware really offers, and what each does (W1)

Source: manufacturer schematic `sch/sch.pdf` and pin diagram `image/T-WATCH2021-V1.1-en.jpg`; to be verified on the
owner's watch with the W0 diagnostics (which prints the live level of each readable key) before W1 ships.

| Button (position, V1.1) | Wired to | Readable by firmware? | Hardware function kept |
|---|---|---|---|
| **Reset** — right, upper | module EN | **No** | resets the chip; untouched |
| **Boot** — right, lower | GPIO0 (strapping) | yes, after boot | held during a reset → ROM bootloader (firmware recovery). Preserved. Used only for a non-critical shortcut; **never** for a workout action |
| **Key 1** — left, upper | GPIO35 (input-only, board pull-up) | yes | — |
| **Key 2** — left, lower | GPIO34 (input-only, board pull-up) | yes | — |

So: **two independently programmable buttons + one shortcut key**, not four. (V1.0 swaps Key 1/Key 2 GPIOs; V2 uses
GPIO39/34 — handled in `board_pins.hpp`.)

## Actions by context (`firmware/src/domain/buttons.hpp`, host-tested)

| Context | Key 1 short | Key 1 long (≥ 700 ms) | Key 2 short | Key 2 long | Boot long |
|---|---|---|---|---|---|
| Screen off | wake | wake | wake | wake | wake |
| Watch face | Activities | Quick settings | Quick settings | Activities | Quick settings |
| Panel / menu | Back | Home (face) | Confirm / open | Home | Home |
| Cycling (live) | Pause ⇄ Resume | **End request** (UI confirms) | Lap | Quick settings | — |
| Strength (live) | Pause ⇄ Resume | End request | **Log set** | Corrections | — |
| Rest timer | Pause ⇄ Resume | End request | Skip rest | Corrections | — |
| Review | Back | Discard (confirms) | Save | — | — |

Rules: debounce 30 ms; short press on release; long press fires once while held (no second event on release); a repeat
guard of 250 ms prevents double triggers; haptics 15 ms (navigation) / 40 ms (log, lap, save) / 60 ms (end, discard);
behaviour is identical with the phone disconnected; **End is never a single short press and always confirms**; Pause,
Resume and End are also on the touchscreen on every live view, so neither a dead button nor a dead touch layer traps the
athlete. Wake-on-key is the display-off behaviour; the BMA423 wrist-raise wake is the other path (W1 test).

## Two-press action system (owner 8 Nov 15:31, E) — `TwoPress` in `buttons.hpp`, host-tested

Physical keys never act on a single press. **First press** shows the key's name and the action it would perform
("KEY 1 · Pause / Resume", "KEY 2 · Lap", "KEY 1 hold · End ride") with a 15 ms haptic tick; **second press of the same
key** within 2.5 s executes it with the action's haptic. The preview expires after ~2.5 s and the UI hides it; a different
key (or a different press type) replaces the preview with its own instead of confirming; a key press while the screen is
off only wakes the display. End ride is three deliberate steps: long-Key1 preview → long-Key1 confirm → the UI's own
End confirmation.

| Context | Key 1 | Key 2 | Key 1 hold | Key 2 hold |
|---|---|---|---|---|
| Cycling | Pause / Resume | Lap | End ride (then confirm) | Quick settings |
| Strength | Pause / Resume | Log set | End workout (then confirm) | Correct reps |
| Outside a workout | Activities | Quick settings | Quick settings | Activities |

**Safety exception (owner):** the touchscreen Pause is immediate (one tap) on every live view, and End ride stays on the
touchscreen regardless of whether the iPhone, the Watch link or the BikeComputer is connected — the two-press rule
governs the physical keys only. Tests: preview → confirm, expiry, different-key replacement, short-after-long is not a
confirmation, screen-off wake, phone-disconnected behaviour, and debouncing (a bouncing edge yields one event).
Hardware-tested: **pending** (no firmware has been flashed).
