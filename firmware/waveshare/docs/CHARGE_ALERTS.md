# Battery charging notifications — feasibility and decision (firmware 0.6.0, 25 Oct 2026)

Rashed asked for notices at about 80 %, 90 % and 98 % while charging (short beeps, then a full-charge notice), implemented only
if the hardware supports accurate detection, with no continuous alarm and no safety claims. The checks below use the sources
already in `POWER_FEASIBILITY.md` (Waveshare schematic Rev3, ETA6096 datasheet, Waveshare wiki) and `HW_RISK_REGISTER.md`.

## What the board can actually do

| Question | Answer | Evidence |
|---|---|---|
| Can the board detect that USB is connected / charging? | **No.** The charger's STAT pin and the USB VBUS net are not routed to any ESP32 GPIO. The firmware can only *infer* "USB power likely" from the battery-node voltage (≥ 4.18 V for 30 s, or rising), which is also what a full resting cell looks like. | Schematic Rev3 (ETA6096 pin 9 STAT unconnected; no VBUS divider), HW-2 |
| Can it distinguish charging from discharging? | **Only as a trend** (voltage rising over minutes vs falling). Not reliable in the last 10 % where the charger holds 4.2 V and the current tapers. | ETA6096 CC/CV behaviour |
| Is there a buzzer or any audio output? | **No.** The board has no buzzer, speaker, DAC amplifier or vibration motor; the only outputs are the display backlight and Bluetooth. "Short beeps" are impossible on this hardware. | Schematic Rev3 component list; Waveshare wiki feature list |
| Is the percentage measured or estimated? | **Estimated** from the cell voltage on GPIO1 (200 k/100 k divider, calibrated ADC). There is no fuel-gauge IC (no coulomb counter). Under charge the terminal voltage reads high; under load it reads low. Error ±10–15 % in the middle of the curve, worse at the ends. | HW-2 / `bc_power.c` |
| Are reliable state-of-charge thresholds (80/90/98 %) possible? | **No.** With a voltage estimate during charging, 80 % / 90 % / 98 % are not distinguishable from each other with any confidence; "98 %" cannot be told from "92 %". | above |
| Does the charger protect against overcharge? | **Electrically yes**: ETA6096 constant-voltage limit 4.21 V (4.17–4.25 V), termination at 130 mA, thermal regulation at 85 °C die temperature. **But** the fitted charge current (~1 A, R15 = 160 kΩ) is twice the 0.5 A limit of the 500 mAh HXJNLDC 503030 cell (HW-1), so charging this cell is *not verified safe* regardless of any notification. | ETA6096 datasheet, HW-1 |

## Decision (applies to 0.6.0)
Charging alerts stay **disabled**:
- Settings › Power shows the row **"Charging alerts — unavailable"** with the reason (no charge sensing, no buzzer, HW-1 open),
  and Device Health shows "Charging: not detectable (no STAT/VBUS line); alerts unavailable, HW-1 open".
- No beeps (no hardware), no continuous alarm, no forced maximum brightness: a bright backlight while a cell that is being
  charged above its rating sits against the PCB would add heat where it is least wanted, for no measurable benefit.
- The firmware never implies that a notification replaces the charger's electrical protection, and it never shows the word
  "charging" as a fact.

## What is prepared for later (after HW-1 is resolved, i.e. R15 changed or a 1 C-rated cell fitted)
- A single **EVENT** on the Events characteristic (`0007`, notify), one per stage while "USB power likely":
  `EVENT 0x40` — `01 u8 event_id` (0x10 battery_notice) `02 u8 level_pct_est` (ESTIMATE) `03 u16 mv` `04 u8 stage`
  (1 ≈ 80 %, 2 ≈ 90 %, 3 ≈ 98 %, judged from voltage bands 3.98 / 4.08 / 4.17 V; labelled "≈" everywhere).
  The phone app can turn it into a local notification (the practical replacement for a buzzer).
- Stage 3 also shows one on-screen notice "BATTERY ~98 % (estimate)" (a toast; no alarm, no brightness change).
- Implemented in `app_power.c` (`charge_notice`) behind the profile key `chg_notice` (default 0, **no menu toggle** while HW-1 is
  open; a phone SETTINGS tag will be added only once the hardware is fixed). The codec is tested in `test/host`.
- Even then the stages remain estimates; the docs and the UI will keep calling them that.
