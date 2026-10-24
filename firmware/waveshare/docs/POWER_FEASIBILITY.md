# Power management on the Waveshare ESP32-S3-Touch-LCD-1.28-B — feasibility (24 Oct 2026)

Sources: Waveshare schematic (ESP32-S3-Touch-LCD-1.28-Sch.pdf, Rev3), ETA6096 datasheet (LCSC), CST816S datasheet + register map
(Waveshare), QMI8658A datasheet, ESP-IDF 5.x sleep-modes guide. Detailed table with URLs: see the research hand-off in this
commit's message history / section "Sources" below. Confidence is stated per item; nothing below is hardware-verified yet.

## What the board can and cannot do

| Topic | Finding | Confidence | Consequence for firmware |
|---|---|---|---|
| USB-C charging | ETA6096 switching charger, VIN 4.5–5.5 V, CV 4.21 V, pre-charge 200 mA, **1 A charge current fitted (R15 = 160 kΩ)**, fixed 130 mA termination, no NTC/temperature pin | High | Charging works from any USB-C 5 V source. The current is a hardware constant; firmware cannot change it |
| Charge-status to the ESP32 | STAT pin is not routed to a GPIO; no charge LED on the board | Medium-High | **Charging cannot be detected directly.** Only inference from the battery voltage (held at ≈4.2 V, or rising over minutes) |
| USB-present detection | No VBUS sense net to a GPIO | Medium | Same inference only. Labelled "USB power likely", never "charging" |
| Battery voltage | VBAT → 200 k/100 k divider → GPIO1 (ADC1_CH0), 3 : 1 | High | Real measurement (already in firmware, calibrated ADC, 16-sample average). Percentage = estimate from the LiPo curve, labelled "≈" |
| Power switch / true power-off | No power key, no latch, charger has no enable pin, regulator enable not under GPIO control | Medium-High | **True power-off is impossible.** The lowest state is ESP32 deep sleep; the menu will say "Deep sleep" and explain the RESET/USB recovery |
| Deep-sleep current | ESP32-S3 ≈ 8 µA; board adds divider (~13 µA), regulator quiescent, touch standby 6 µA, IMU, CH343P. Board figure unpublished | Unknown figure | To be measured by voltage slope over hours (no current meter on board) |
| Touch wake, light sleep | `gpio_wakeup_enable` works on any GPIO → GPIO5 (TP_INT) | High | Screen-off + light sleep outside rides is feasible |
| Touch wake, deep sleep | GPIO5 is an RTC GPIO → ext0 wake; CST816S must stay powered (3V3 rail does) and TP_RST (GPIO13) held high through sleep | High (capability) / Medium (practice) | Deep sleep with touch wake is feasible; first touch wakes the chip (~150 ms), firmware then decides |
| Triple-tap wake | The CST816S reports single/double tap gestures and wakes the host on finger detect; it has no triple-tap mode | High | Implement in firmware: any touch wakes the chip, which waits ≤1.5 s for three taps; otherwise goes straight back to sleep. Reliable and cheap (≈150 ms awake per false touch) |
| Wake on motion (IMU) | QMI8658 Wake-on-Motion on INT1/INT2 (GPIO4/3, RTC-capable) | High | Available but **not recommended** for a bike: vibration would wake it constantly. Kept off |
| Backlight | GPIO2 → N-FET → LED cathode; low = fully off | High | Screen off = backlight 0 % + GC9A01 Sleep-In (10h); sensors and recording continue |
| Battery-size suitability | 1 A ≈ 1 C for a 1000 mAh cell, ≈ 3 C for 300 mAh; 130 mA termination is above C/10 for cells < 1300 mAh (slightly early "full") | Medium | **Cells ≥ 1000 mAh: fine. 500–1000 mAh: acceptable (1–2 C), warmer. < 500 mAh: too fast; only a hardware change (larger R15) reduces it.** Firmware cannot limit charge current |

## Recommended implementation (firmware 0.5.0 "Power")

1. **Battery measurement, honestly labelled**: voltage (measured) + "≈ N %" from a 3.3–4.2 V LiPo curve, corrected for load (no correction claimed as exact). "USB power likely" when the voltage stays ≥ 4.18 V for 30 s or rises ≥ 30 mV in 5 min; never the word "charging" as a fact. Consumption measured as mV/hour per mode and logged (Device Health shows "about N h left", only after ≥ 20 min of data).
2. **Quick Settings** (swipe down from the top edge on any non-ride screen; during a ride the existing swipe-down control panel gains a "Quick Settings" button so the ride controls stay first): a compact round-safe grid: Brightness slider; Wi-Fi on/off; Sensors (jumps to Sensors); Phone link on/off; Battery (voltage, ≈ %, source, hours left); Touch lock; Screen off; Sleep; Restart; Power options (explains deep sleep + recovery). Close: swipe up, tap the X, or 20 s timeout. Ride screens A/B/C untouched.
3. **Screen off** (any time, also during a ride): backlight off, panel Sleep-In, LVGL paused; BLE, recording, coach and journal continue; wake = triple tap within 1.5 s (single taps ignored, so jersey or rain taps do nothing). While a ride is running the screen also wakes for 5 s on a coach warning (HR high) — optional, default on.
4. **Auto screen timeout outside rides**: 60 s default (Settings: 30 s / 1 / 2 / 5 min / never). Inside a ride: never automatic, only manual Screen off.
5. **Sleep** (only when no ride is active): save profile, stop BLE/Wi-Fi, panel off, **deep sleep** with ext0 wake on GPIO5 (TP_RST held high). Wake = triple tap (first touch wakes the chip, three taps within 1.5 s confirm, else back to sleep in < 200 ms). Also wakes on RESET and USB plug/unplug (brownout/reset). An "auto-sleep after N min idle on battery" option (default 10 min, off on USB).
6. **"Power off"** label replaced by **"Deep sleep (lowest power)"** with the one-line explanation and recovery: tap three times, press RESET, or plug in USB.
7. **Battery protection**: alert at ≈ 20 % (3.55 V under light load) and 10 %; at ≈ 5 % (3.35 V) during a ride: flush the journal, save the ride to history automatically, show "saved, battery empty", deep sleep. Outside a ride: deep sleep at 3.30 V. Hysteresis 50 mV so vibration/sag never triggers twice.
8. **Touch lock**: ignore touches until a long-press (3 s) on the lock icon; swipe-down still opens Quick Settings? No: locked means locked; only the 3 s hold unlocks.
9. **Safety invariants**: no action in Quick Settings can end a ride without the existing HOLD confirm; Sleep is greyed out while a ride runs; every power action writes the journal first.

## Test plan (power in isolation first, then with everything)
- Simulator: Quick Settings geometry on the round screen, state machine (screen off / lock / sleep guards), low-battery thresholds and hysteresis with scripted voltages, ride auto-save on critical voltage.
- Device, alone: screen off → triple-tap wake; auto timeout; sleep → triple-tap wake, RESET wake, USB wake; single taps must NOT wake; voltage shown vs multimeter (if available); USB-power inference while plugged.
- Device + meter + phone: screen off during a ride keeps watts flowing on the phone and the journal growing; BLE reconnect after wake; Wi-Fi state restored after sleep.
- Consumption: voltage slope in four modes (recording screen on, recording screen off, idle screen on, deep sleep), each ≥ 30 min, logged by the firmware; converted to hours per 100 % for the fitted cell.
- Data: history and settings identical before/after sleep and after an auto-save.

## Open question for Rashed
Which battery is connected: capacity (mAh) and the label on the cell? It decides whether the fitted 1 A charge current is suitable (≥ 1000 mAh: yes; 500–1000: acceptable; < 500: a hardware resistor change is the only remedy, firmware cannot reduce it).

## Sources
Waveshare wiki https://www.waveshare.com/wiki/ESP32-S3-Touch-LCD-1.28 · docs https://docs.waveshare.com/ESP32-S3-Touch-LCD-1.28 ·
schematic https://files.waveshare.com/wiki/ESP32-S3-Touch-LCD-1.28/ESP32-S3-Touch-LCD-1.28-Sch.pdf (Rev3 …_Rev3.pdf) ·
ETA6096 https://wmsc.lcsc.com/wmsc/upload/file/pdf/v2/lcsc/2307171444_etasolution-ETA6096D3K_C7465538.pdf ·
CST816S registers https://files.waveshare.com/wiki/common/CST816S_register_declaration.pdf · datasheet https://files.waveshare.com/upload/5/51/CST816S_Datasheet_EN.pdf ·
QMI8658A https://files.waveshare.com/upload/5/5f/QMI8658A_Datasheet_Rev_A.pdf · ESP-IDF sleep https://docs.espressif.com/projects/esp-idf/en/v5.1.6/esp32s3/api-reference/system/sleep_modes.html ·
Spotpear notes https://spotpear.com/wiki/ESP32-S3-1.28inch-Round-LCD-Display-TouchScreen.html · RIOT board doc https://doc.riot-os.org/boards/waveshare-esp32s3-touch-lcd-128
