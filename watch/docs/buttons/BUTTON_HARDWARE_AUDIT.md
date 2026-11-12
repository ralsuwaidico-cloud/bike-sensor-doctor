# Cyclift Watch — button hardware audit (12 Nov 2026)

Scope: LILYGO T-Watch 2021, board V1.1 build (`T-Watch-2021-V1_1-v3poc`), the owner's watch. Analysis only: no firmware,
flash or button behaviour was changed.

Evidence key:
- **[HW]** seen on the owner's watch (serial log or owner observation);
- **[DOC]** the manufacturer's schematic, pin sheet or library;
- **[SPEC]** ESP32 datasheet behaviour;
- **[ASSUMED]** not yet verified.

## 1. The four buttons

| Name in this study | Physical position | Wired to | Firmware can read it? | Programmable? | Reserved hardware function |
|---|---|---|---|---|---|
| **L1** | left, upper | GPIO35 (input-only pin, board pull-up, active low) [DOC] | **yes [HW]**: "Key 1" in every log (B2 9 Nov: 10/10 presses, no double counts; 12 Nov: 15 events) | **yes** | none |
| **L2** | left, lower | GPIO34 (input-only pin, board pull-up, active low) [DOC] | **yes [HW]**: "Key 2" (B2: back ×4; 12 Nov: 5 laps by double press) | **yes** | none |
| **R1** | right, upper | module **EN (chip enable / reset)** [DOC] | **no**: pressing it resets the chip at once; firmware never sees it | **no** | hardware reset |
| **R2** | right, lower | **GPIO0 = BOOT** strapping pin, board pull-up [DOC] | **yes, after start-up** [DOC; the existing driver already reads it, `drivers.hpp` `boot()`]. Not used by the v3 firmware: B2 9 Nov, owner pressed it, no event, no effect [HW] | **yes, with restrictions (§3)** | held while the chip starts → ROM download mode (firmware recovery) |

Sources:
- `watch/docs/BUTTONS.md` (from LILYGO `sch/sch.pdf` and pin sheet `T-WATCH2021-V1.1-en.jpg`);
- `watch/docs/stage2a/BOARD_IDENTIFICATION.md`;
- the board's specification list: "Reset button, Boot button, 2× user buttons".

### Positions are not yet verified on this unit

**Verified on the watch:**
- two buttons produce Key 1 / Key 2 events;
- a third button did nothing when pressed (B2).

**Not verified on this unit:**
- which side and which height each button is on;
- which right-hand button is Reset and which is Boot.

The LILYGO V1.0 pin sheet supplied with the watch shows the user keys on the left. Earlier owner reports said "upper" and
"lower" without naming a side.

A 1-minute read-only check would settle this. The recorder runs, the owner presses each button once, and the log shows:

| Button pressed | What the log shows |
|---|---|
| L1 | `key1` |
| L2 | `key2` |
| R2 | nothing (RC1/RC2 do not read GPIO0) |
| R1 | a restart with ROM reset line `rst:0x1` |

R1 is the only one that changes anything, and it only restarts the watch. Proposed as decision G1.

## 2. Press types (all three readable buttons)

The firmware polls the pins every loop pass (≈ 10 ms) [HW: B2 timing].

| Press type | L1 / L2 / R2 | R1 (Reset) |
|---|---|---|
| Short press | possible (L1/L2 in use today) | n/a: always resets |
| Long press / hold | possible (L1 hold ≥ 1 s = unlock, in use) | n/a |
| Double press | possible (L2 two-press = Lap, in use, 2.5 s window) | n/a |
| Press-and-hold countdown | possible (timer on the held state) | n/a |
| Simultaneous presses | possible between any of L1, L2, R2: three independent GPIOs, no shared line (the shared IO32 line is the touch / RTC / motion interrupt, not a button) [DOC] | n/a |

### Restrictions

- **No debounce in v3:** the current v3 firmware acts on the raw falling edge. The v2 `KeyDecoder` (30 ms debounce,
  700 ms long press, 250 ms repeat guard) exists, host-tested, but is not used by v3. Contact bounce on GPIO34 / 35 has
  not been measured. In B2, 10 presses gave 10 events, so no bounce was seen.
- **GPIO34 / 35 are input-only:** they have no internal pull-up and rely on the board's resistors [SPEC + DOC].
- **GPIO0 (R2) at start-up:** if it is held low while the chip starts, the chip enters download mode, shows a black
  screen and waits for a PC [SPEC]. This covers power-on, R1 and the hardware brown-out / watchdog chip resets.
  Whether a firmware-requested restart (`esp_restart`) re-reads GPIO0 has **not been verified [ASSUMED either way]**.
  So any design that restarts while R2 is held must instead wait for R2 to be released.
- **Start-up:** buttons are read only after the UI starts (~0.6 s after reset, first frame 576 ms [HW]). Presses
  during start-up are ignored. R2 held at that moment = download mode (above).
- **Screen lock (current firmware):** L1 / L2 short presses are ignored while locked; L1 held ≥ 1 s unlocks [HW
  11 Nov, owner lock test PASS].
- **Screen off / sleep:** not implemented in v3. There is no battery, so the screen is always on. GPIO34 / 35 / 0 can
  all wake the chip from deep sleep [SPEC], so "any button wakes" is feasible later.
- **R1 cannot be disabled, delayed or logged by firmware.** After an R1 press the next start reports reset reason
  "power-on / external" (RC2 prints it); a deliberate R1 press and a power glitch look the same.

## 3. Hardware risks that shape the design

1. **Pinch effect (physical, [ASSUMED] until the owner checks the case).** A side button is normally pressed with the
   thumb while a finger braces the opposite side:
   - Pressing **L1** can press **R1 (Reset)** opposite it, which restarts the watch at once.
   - Pressing **L2** can press **R2 (Boot)** opposite it, which is harmless while running.

   This may explain the unexplained restart D7, which happened while the owner was pressing buttons. It is **not
   proven**. Check: is R1 recessed or flush?
2. **R2 is the recovery button.** Anything that encourages holding R2 makes "held during a restart" more likely. The
   design therefore restarts only after release and never asks for R2 during a reset.
3. **Only L1 and L2 are free of reserved hardware roles.** Workout-critical actions (Pause, Lap, Log Set, End) belong
   on L1 / L2. R2 may carry non-critical, frequent-but-harmless actions (next page, scroll, lock).

## 4. Summary

| | Count |
|---|---|
| Physical buttons | 4 [DOC] (R2 inert in the v3 firmware [HW]; others react [HW]) |
| Readable by firmware | 3 (L1, L2, R2) |
| Fully free | 2 (L1, L2) |
| Usable with care | 1 (R2) |
| Hardware-only | 1 (R1 = reset) |
