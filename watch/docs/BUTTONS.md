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
| Watch face | Activities | Quick settings | Activities | Quick settings | Quick settings |
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
