# Touchscreen investigation — offline (9 Nov 2026, ~21:20 Dubai)

Scope: offline analysis plus reading the existing serial logs on the PC. No firmware write, no new code run on the watch,
no disassembly. Classification: **confirmed** (direct evidence) · **supported** (consistent evidence, not proven) ·
**unverified** (possible, no evidence either way).

## 1. Touch controller
* **Supported: CST816S at I²C address 0x15.** Evidence: LILYGO factory source (`SmartWatch/lib/MyCst816s`, address 0x15,
  chip-ID register 0xA7); the factory binary on the watch contains the strings `CST816S`, `State :`, `Press down`; Stage 1 logged
  a "swipe U" event, which can only come from a successful I²C read at 0x15 (see 4).
* Not confirmed physically (chip marking not seen). Documentation conflict: the LILYGO wiki T-Watch 2021 page lists an FT6236
  touch controller and ST7789 display; the LILYGO source code and the factory binary use CST816S and GC9A01. Treated as a wiki error.

## 2. Factory vs Cyclift touch start-up
| Item | Factory (LILYGO OSW port) | Cyclift Stage 1 (V1_1 build) | Same? |
|---|---|---|---|
| I²C pins | SDA 26, SCL 25, 100 kHz | SDA 26, SCL 25, default 100 kHz | yes |
| Address | 0x15 | 0x15 | yes |
| Reset pin | IO33: LOW 10 ms → HIGH, wait 50 ms | IO33: LOW 10 ms → HIGH, wait 60 ms | yes |
| Interrupt pin | IO32, input with pull-up; **not used for reading** (polls every loop) | IO32, input without pull-up; polls at least every 20 ms regardless of INT | effectively yes |
| Power | IO5 (power hold) HIGH; no separate touch power switch in the code | IO5 HIGH | yes |
| Register setup | writes auto-sleep on, scan rate, report mode (0xFA=0x60), auto-reset 5 s, long-press 16 s, low-power current, sleep after 1 s | none (controller defaults) | **differs** |
| Reading | register 0x00, 7 bytes; "touched" = contact flag (reg 0x03 bit 7) | register 0x01, 6 bytes; "touched" = finger count > 0 | differs, both valid |

The register-setup difference could matter for Cyclift's gestures, but cannot explain the factory firmware's failure (the
factory configures the controller itself). **Supported: the touch failure is not caused by Cyclift's touch code.**

## 3. Factory Touch app
* Opens in "coordinates" mode (State / X / Y); another button press switches to a drawing board. No calibration or setup.
* It polls the controller every loop and shows "Press down" + X/Y only while a finger is **in contact** (contact flag).
  A very short tap may be missed; a finger held or dragged should show it.
* **Supported: no special interaction is required beyond holding/dragging a finger** — which the owner did, with no reaction.
* The factory "Print debug" app shows "CST816S OK", but its check has a coding error (`if (data = 0xB4)` is always true).
  **Confirmed: that status line is meaningless** and cannot be used as a detection test.

## 4. Existing serial logs (install_log.txt 162 lines, a1_log.txt 30 lines; searched on the PC, read-only)
* No touch, I²C or Wire error lines in either log. Only `esp_core_dump_flash: No core dump partition found` (harmless, Stage 1).
* **Confirmed: the factory firmware cannot report touch problems on serial** — it prints nothing about touch start-up, and its
  Arduino 2.0.3 I²C layer has no error message for an unanswered address. So the absence of errors is not evidence.
* **One positive data point (supported):** during the Stage 1 observation (19:42–19:43) the log contains `swipe U`. In Stage 1
  that line is produced only by the touch driver after an I²C read at 0x15 succeeded twice (finger down, then up). So the
  controller answered on the I²C bus at least once. Caveats: the log only kept the first lines of each window; the owner
  does not recall a working touch; a single event could also be a stray reading.

## 5. Detection without changing the firmware
* esptool cannot reach the I²C bus. The factory firmware has no reliable detection screen (see 3). → **Not possible with the
  existing firmware alone.**
* Option needing separate approval: a **RAM-only diagnostic** (`esptool load_ram`) — a small test program is loaded into the
  chip's RAM and run once; **nothing is written to flash**, and it disappears at the next reset (the factory firmware then starts
  as normal). It would scan the I²C bus, read the controller's chip ID (0xA7), project ID and firmware version (0xA8/0xA9), and print
  finger count and X/Y live while the owner touches. Not built yet; it runs new code on the watch, so it is not covered by the
  current authorisation.

## 6. Board revision V1.0 / V1.1
* LILYGO headers: V1.0 touch INT IO35, V1.1/V1.2 touch INT IO32; **reset IO33 and I²C 25/26 are identical** in all V1 revisions.
* Both firmwares read the controller by polling, without needing the interrupt line.
* **Supported: the revision question cannot explain the failure.** (It still matters for interrupt-driven touch wake-up later.)

## 7. Potential causes
| Cause | Classification | Basis |
|---|---|---|
| Cyclift touch code | supported — not the cause | factory firmware fails the same way |
| Board revision / interrupt pin | supported — not the cause | polling reads; reset and I²C pins identical |
| Factory Touch app needs special use | supported — not the cause | source: polls continuously, no setup |
| Controller absent or unpowered | supported — unlikely | one successful read at 0x15 during Stage 1 (single event) |
| Touch ribbon fully disconnected | **unverified, evidence against** | the controller answered at least once; not assumed |
| Ribbon partly seated or intermittent (sensor or controller side) | unverified | would fit "answered once, otherwise dead"; needs a live diagnostic or inspection |
| Touch sensor or glass layer damaged, or sensor-to-controller connection broken | unverified | controller could answer I²C but sense nothing |
| Interference from the USB/PC connection during the tests (all touch tests were done while plugged in) | unverified | capacitive touch is known to be noise-sensitive; easy to test on battery |
| Screen protector, film, moisture, or a gloved/dry finger | unverified | not yet checked |
| Controller stuck in low-power mode or its own firmware hung | unverified | both firmwares reset it at start; a live register read would show it |

## 8. Safe checks without opening the watch (owner actions; no scripts, no writes)
1. **Battery-only test:** unplug USB (the factory firmware keeps running on the battery), open the factory Touch app, hold a
   clean, dry fingertip still in the centre for 2 s, then drag slowly; repeat near each edge; try the drawing mode too.
2. Remove any protective film; clean and dry the glass; use a bare fingertip, not a nail.
3. Look closely at the glass edge and the case for gaps, lifting or cracks (look only, do not press or pry).
4. Power-cycle on battery (if a power-off is available) or by reconnecting USB, then repeat 1 — the controller is reset at every start.
5. If the result is still negative: request approval for the RAM-only diagnostic (no flash write) before any disassembly.

## 9. If physical inspection becomes necessary (NOT approved; procedure to be completed before asking)
No verified teardown guide for the T-Watch 2021 case was found, so the steps below are general and must be confirmed with
photos of the owner's case (back, sides, screw heads) before an approval request:
* Preconditions: watch off/unplugged, battery charge moderate, ESD-safe surface, plastic pry tool, correct driver bit,
  photos of every step, a small tray for screws.
* Open the back only as far as needed; watch for the battery lead and any ribbon running to the back half; never pull on a ribbon.
* Ribbon inspection: photograph the touch ribbon and its connector before touching anything; check whether it is fully inserted
  and square and whether the locking flap is closed; look for creases or tears. Re-seat it only if it is clearly not seated:
  open the flap, re-insert straight to full depth, close the flap. Do not re-seat a correctly seated connector "just in case".
* Risks: cracking the case or the display glass, tearing a ribbon or breaking a connector latch, shorting the battery,
  losing water/dust sealing, voiding the warranty. Some of these cannot be undone.
* Alternative to opening: send the evidence to LILYGO support (factory firmware, factory Touch app, no response).

## Recommended sequence (lowest risk first)
1. Owner checks 8.1–8.4 (no approval needed beyond handling; nothing written).
2. If touch works on battery: it is interference or a contact issue → plan the B tests on battery power; record it.
3. If not: RAM-only diagnostic (separate approval) → tells "controller answers but senses nothing" apart from "controller not answering".
4. Decide with that result: LILYGO support, or a model-specific inspection procedure (separate approval).
5. B1 only after touch is either working or formally accepted as a known hardware issue.
