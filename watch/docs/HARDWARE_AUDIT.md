# W0 — Hardware audit: LILYGO T-Watch 2021 (round · T-Micro32 Plus · GC9A01)

Sources: the official repository [Xinyuan-LilyGO/T-Watch-2021](https://github.com/Xinyuan-LilyGO/T-Watch-2021)
(pin diagram `image/T-WATCH2021-V1.1-en.jpg`, `TWatch_2021_Library/src/board/*.h`, `sch/sch.pdf`, `T-U2T/schematic`,
`software/factory`), the [LILYGO product page](https://lilygo.cc/en-us/products/t-watch-2021) and the
[CNX Software launch article](https://www.cnx-software.com/2021/08/31/t-watch-2021-round-smartwatch-esp32-touchscreen-500mah-battery/).
**Nothing below has been measured on the owner's watch yet** — every "Confirmed" item is confirmed from the
manufacturer's files, and the "Needs testing" column is the W0 device checklist. The LILYGO *wiki* page titled
"T-Watch 2021" describes a different board (ST7789 square display, AXP202, GNSS) and must not be used.

## 1. Identification — what the owner must check first

| Check | How | Why it matters |
|---|---|---|
| Board revision **V1.0 / V1.1 / V2** | printed on the PCB silkscreen (open the back) — the official library says "look at the silkscreen" | the pin map differs per revision (see §3); V1.1 moved every interrupt to IO32 and added the RTC alarm; V2 adds GPS, SD, encoder, BME280 and changes most pins |
| Compass variant **QMC5883L or QMC5883P** | the factory firmware ships two binaries (`Factory-QMC5883L.bin`, `Factory-QMC5883P.bin`); the W0 diagnostics sketch probes both I2C addresses (0x0D / 0x2C) | the right driver, and the right factory binary for a restore |
| **T-U2T dongle present?** | a small white "T-U2T · USB TO TTL" stick with a USB-C plug | without it the watch cannot be read, backed up or programmed (§4) |

The factory firmware showing an analog face confirms the display, backlight, RTC and power path work; it says nothing
about touch, accelerometer or BLE yet.

## 2. Capability matrix

Classification: **Confirmed** (manufacturer files) · **Needs testing** (W0 checklist on the real watch) ·
**Requires external sensor** · **Unsupported**.

| Capability | Component | Status | Notes |
|---|---|---|---|
| MCU | T-Micro32 Plus module: ESP32 dual-core Xtensa LX6 @ 240 MHz, Wi-Fi 4, **Bluetooth 4.2 BR/EDR + BLE** | Confirmed | classic ESP32 (not S3): no USB-OTG, no BLE 5 features |
| Flash | **8 MB** (library build flags; factory partition table is 8 MB) | Confirmed · size to verify with `esptool flash_id` | OTA with two 3 MB app slots fits (`boards/partitions_8mb_ota.csv`) |
| PSRAM | **2 MB** (README: "Flash 8MB, PSRAM 2MB") | Confirmed · size to verify at boot | LVGL frame buffers can live in PSRAM only at a speed cost; plan: half-screen buffer in internal RAM |
| Display | **GC9A01**, 1.28–1.3" round, **240 × 240**, SPI (MOSI 13 · SCLK 14 · CS 15 · DC 19 · RST 27 · BL 21 on V1.x) | Confirmed | 16-bit colour; full frame = 115 KB; SPI up to 40–80 MHz → ~25–40 full frames/s theoretical, partial redraws in practice |
| Touch | **CST816S** capacitive, I2C 0x15, RST 33, INT 32 (V1.1) / 35 (V1.0) | Confirmed | controller decodes tap / swipe / long press; glove use is NOT expected to work (capacitive) — the three buttons are the glove path |
| Accelerometer | **BMA423**, I2C 0x19, INT on IO32 (V1.1) | Confirmed | 12-bit, ±2–16 g, ODR 12.5–1600 Hz, 1 KB FIFO, hardware step counter, wrist-wear wake, tap detection → rep counting input (§6 of the directive) |
| RTC | **PCF8563**, I2C 0x51, 32.768 kHz crystal, alarm → IO32 (V1.1 only) | Confirmed | typical drift of this class: ±10–20 ppm (≈ 1–2 s/day) — to be measured against the phone (W1) |
| Compass | **QMC5883L** (0x0D) or **QMC5883P** (0x2C), DRDY IO12 ("keep disabled") | Confirmed (two variants) | heading for the Navigation view; needs calibration; disturbed by the bike's steel |
| Vibration motor | on IO4 (V1.x) / IO2 (V2), transistor-driven; V1.1 added a current limit | Confirmed | haptic cues |
| Buttons | **Reset**, **Boot (IO0)**, and two user buttons (IO35 / IO34 on V1.1; swapped on V1.0) | Confirmed | Boot doubles as a user key after start-up |
| Battery | LiPo on a JST 1.25 mm connector, **TP4054** linear charger from USB-C VBUS, voltage on **IO36** (divider), charge status **IO2** (V1.x) | Confirmed | capacity: product page 470 mAh / article 500 mAh — **read the cell label**; no fuel gauge → percentage must come from a measured discharge curve (W8) |
| Power control | **PWR_ON IO5** (V1.x) latches the board on; hold-to-power-off | Confirmed | deep-sleep current to be measured |
| USB-C | **charging only** on the watch; D+/D− carry UART0 to the **T-U2T** (CP2104) dongle | Confirmed from the schematic (no USB-serial chip on the watch) | the supplied cable charges; programming needs the T-U2T |
| Antenna | on-module ceramic + u.FL pad (a resistor must be moved for the external antenna) | Confirmed | leave as is |
| Microphone / speaker | — | Unsupported | not on this board |
| Optical heart-rate sensor | — | **Unsupported** | HR only from Apple Watch / a BLE strap / the BikeComputer's sensors via the phone |
| GPS | — on V1.0 / V1.1 (V2 has a GPS module) | Unsupported on V1.x → **phone GPS mirrored over BLE** | never fabricate positions |
| Barometer / altitude | BME280 on V2 only | Unsupported on V1.x | elevation only from the phone's data |
| Wi-Fi | ESP32 | Confirmed · not planned for daily use | OTA updates when needed; high current |
| BLE roles | NimBLE: peripheral to the iPhone; central to external sensors **possible but shares one radio** | Needs testing | simultaneous iPhone link + 1–2 sensors is plausible on ESP32; measured in W2 |
| ANT+ | — | **Unsupported** (no ANT radio) | as the directive requires: not promised |
| SD card | V2 only | Unsupported on V1.x | LittleFS on flash for persistence |

## 3. Pin maps (transcribed, per revision)

| Signal | V1.0 | V1.1 (library "V1_2") | V2 |
|---|---|---|---|
| PWR_ON | 5 | 5 | 32 |
| CHARGING | 2 | 2 | — |
| BAT_ADC | 36 | 36 | 36 |
| BTN_1 (Boot) / BTN_2 / BTN_3 | 0 / 34 / 35 | 0 / 35 / 34 | 0 / 39 / 34 |
| MOTOR | 4 | 4 | 2 |
| I2C SDA / SCL | 26 / 25 | 26 / 25 | 27 / 26 |
| TOUCH_RST / TOUCH_INT | 33 / 35 | 33 / 32 | — / 37 |
| RTC_INT · BMA_INT1 · BMA_INT2 | — · 22 · 39 | 32 · 32 · 32 (all-in-one) | 37 · 37 · 37 |
| TFT MOSI / SCLK / CS / DC / RST / BL | 13 / 14 / 15 / 19 / 27 / 21 | same | 23 / 18 / 5 / 22 / — / 21 |
| GPS RX / TX / WAKE | — | — | 3 / 1 / 25 |

`firmware/src/hal/board_pins.hpp` carries exactly these values behind `CYW_BOARD_V1_0 / V1_1 / V2`.

## 4. Programming method

- The watch has **no USB-to-serial converter**. Its USB-C port carries VBUS (charging through the TP4054) and routes
  UART0 TX/RX on the D+/D− lines to LILYGO's **T-U2T** dongle (a CP2104 bridge with a USB-C *plug* and an auto-reset
  circuit). Plug the T-U2T into the watch, then a normal USB cable from the T-U2T to the computer.
- The **supplied USB-C cable charges the watch and nothing else**; whether it is a "data" cable is irrelevant on the
  watch side, since no data path exists without the T-U2T. (A data-capable cable *is* needed between the T-U2T and the
  computer.)
- Toolchain: PlatformIO (`platform = espressif32`, `board = esp32dev`, Arduino framework), flash mode QIO, 8 MB, PSRAM
  on — as in `firmware/platformio.ini`. Libraries: TFT_eSPI (GC9A01 driver), LVGL 8, NimBLE-Arduino, the Bosch BMA4
  API, PCF8563, CST816S, QMC5883 — the manufacturer's `TWatch_2021_Library` bundles tested copies of all of them.

## 5. Factory firmware — backup and recovery strategy

1. **Before anything is written**: `tools/backup_factory_firmware.sh <port>` dumps the whole 8 MB flash with
   `esptool read_flash` (read-only) and records the SHA-256. Keep two copies.
2. **Restore path A**: write the dump back with `esptool write_flash 0x0 factory-8mb.bin` — byte-identical factory state.
3. **Restore path B**: the manufacturer's `software/factory/firmware/Factory-QMC5883L.bin` or `-QMC5883P.bin` (choose
   by the compass detected in W0) with the factory partition table (`T_Watch2021_default_8MB.csv`).
4. **Our own safety**: the Cyclift partition table has two OTA slots; a build that fails to boot three times rolls back
   to the previous slot (ESP-IDF rollback), and `Boot + Reset` always reaches the ROM bootloader for a manual reflash.
5. Nothing in steps 2–4 runs without the owner's explicit approval; step 1 is read-only and is the first thing to do
   once the T-U2T is available.

## 6. Non-destructive diagnostic procedure (W0, read-only)

`firmware/src/app/main.cpp` in the W0 state prints over serial: chip model / revision / flash size / PSRAM size,
which I2C devices answer (touch 0x15, BMA423 0x19, RTC 0x51, compass 0x0D or 0x2C), the battery ADC reading and the
charge-pin state. It initialises no display and writes nothing to flash or to any sensor. Running it **does** require
uploading it, so it waits for the owner's authorisation; until then the identification in §1 is done by eye and with
`esptool chip_id / flash_id` (read-only).

## 7. What the current watch can and cannot do (summary)

Can: show time (RTC), vibrate, sense wrist motion and steps, sense heading, touch and three buttons, talk BLE to the
iPhone and to BLE sensors, run for a day-class battery life (to be measured), survive offline with LittleFS.
Cannot: measure heart rate, HRV, sleep stages, SpO₂, position, altitude or weather on its own; support gloves on the
touch layer; ANT+. Every such value shown on the watch is **received** from the iPhone / Apple Watch / sensors with its
timestamp and source, or not shown.

## 8. Power and memory — plan to measure (W0/W1), no figures promised

Measurement points (USB power meter on the T-U2T line is not valid — it includes charging; use the battery line with a
µA-capable meter): idle clock (display off), display on at 30/60/100 %, BLE connected idle, active workout with 50 Hz
IMU sampling, compass sampling, vibration, deep sleep. Memory: free internal heap after LVGL init with a half-screen
buffer, PSRAM use, largest free block (fragmentation) after 1 h of screen changes.
