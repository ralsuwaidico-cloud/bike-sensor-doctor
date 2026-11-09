# Cyclift Watch — board identification (9 Nov 2026)

Evidence used (no assumptions): the owner's photographs (watch running the factory firmware; the pin sheet supplied with the watch),
the official LILYGO repository `Xinyuan-LilyGO/T-Watch-2021` (commit d18ff632, board headers `TWatch2021_V1.h`, `TWatch2021_V1_2.h`,
`TWatch2021_V2.h`, pin sheets `image/T-WATCH2021-V1.0-en.jpg` and `-V1.1-en.jpg`, firmware `software/SmartWatchFirmware/target.bin`
and its source `software/SmartWatch`), and the read-only readings from the watch (chip ID, eFuses, backup fingerprints).

## 1. What is installed on the watch today (proven)
The factory app in the backup (1 194 096 B, SHA-256 `6bfae0e5…35420f13`) is **byte-identical** to the app inside LILYGO's
`software/SmartWatchFirmware/target.bin`; its bootloader has the same code fingerprint and the partition table is the same.
That firmware is LILYGO's port of Open-SmartWatch (settings namespace `osw-config`), built with Arduino-ESP32 2.0.3. Its pin file
(`software/SmartWatch/include/osw_pins.h`) uses: display MOSI 13 / SCLK 14 / CS 15 / DC 19 / RST 27 / BL 21, power IO5, motor IO4,
I²C SCL 25 / SDA 26, touch reset 33 / interrupt 32, BMA423 interrupts 32, charge IO2, battery IO36, keys 34 and 35.

## 2. Pin comparison
| Signal | Owner's sheet (= LILYGO V1.0 sheet) | LILYGO V1.1 sheet | Library V1.0 (`TWatch2021_V1.h`) | Library V1.1 (`TWatch2021_V1_2.h`) | Library V2 | Our env V1_0 | Our env V1_1 | Our env V2 |
|---|---|---|---|---|---|---|---|---|
| Display MOSI/SCLK/CS/DC/RST/BL | 13/14/15/19/27/21 | same | same | same | 23/18/5/22/–/21 | same as V1 | same as V1 | V2 pins |
| Power enable | IO5 | IO5 | 5 | 5 | 32 | 5 | 5 | 32 |
| Motor | IO4 | IO4 | 4 | 4 | 2 | 4 | 4 | 2 |
| I²C SCL/SDA | 25/26 | 25/26 | 25/26 | 25/26 | 26/27 | 25/26 | 25/26 | 26/27 |
| Touch reset / interrupt | 33 / **32** | 33 / 32 (shared) | 33 / **35** | 33 / 32 | –/37 | 33 / **35** | 33 / 32 | –/37 |
| BMA423 interrupts | **22 / 39** | 32 (shared) | 22 / 39 | 32 | 37 | 22/39 | 32 | 37 |
| Upper-left / lower-left key | GPIO35 / GPIO34 | GPIO35 / GPIO34 | (BTN_2=34, BTN_3=35) | (BTN_2=35, BTN_3=34) | 39/34 | KEY1=34, KEY2=35 | **KEY1=35 (upper), KEY2=34 (lower)** | – |
| Charge status / battery | IO2 / IO36 | IO2 / IO36 | 2 / 36 | 2 / 36 | – / 36 | 2/36 | 2/36 | –/36 |
| Crown (encoder), GPS, SD, BME280 | none | none | none | none | yes | – | – | yes |

Display controller GC9A01, touch controller on I²C (CST816S per the LILYGO library), BMA423, QMC5883L, RTC (PCF8563 per the library):
the same on all V1 boards. Power management is the same simple scheme on V1.0 and V1.1 (power-hold IO5, charge-status IO2, battery
ADC IO36); there is no PMU chip.

## 3. Conclusions
* **Not V2 — proven.** No crown (owner), and the factory firmware drives the display with the V1 pins and the screen works (photo).
  On a V2 board those pins do not reach the display.
* **V1.0 vs V1.1 — not proven by the available evidence.** The sheet supplied with the watch is LILYGO's V1.0 sheet (separate BMA423
  interrupts 22/39); the factory firmware installed by LILYGO is configured the V1.1 way (all interrupts on 32). The two revisions
  differ only in how the BMA423 / RTC interrupt lines are wired. Settling it needs the **revision text printed on the main board**
  (visible only with the back cover off) — or a later approved hardware test of the motion-sensor interrupt line.
* **Stage 1 target: `T-Watch-2021-V1_1-v3poc` — every pin Stage 1 uses matches the owner's sheet**: display, power IO5, motor IO4,
  I²C 25/26, touch 33/32, keys 35 upper / 34 lower, charge IO2, battery IO36. Stage 1 does not use the BMA423 or RTC interrupt lines,
  so the unresolved V1.0/V1.1 wiring difference cannot affect it. The `V1_0` build is **wrong for this watch** either way: it follows
  the library's V1.0 header (touch interrupt on IO35, which the sheet shows as the upper key) and swaps the two keys.
* Documentation conflict recorded: LILYGO's V1.0 sheet says touch interrupt IO32, LILYGO's V1.0 library header says IO35.
* Must be resolved before any feature that uses motion or RTC interrupts (raise-to-wake, step interrupts, alarms).
