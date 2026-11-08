# 03 — Hardware specifications (verified vs. documented)

Evidence tags: **B** = read from the owner's board (serial log / backup) · **M** = manufacturer files (schematic, wiki,
library) · **U** = unverified / to measure. A spec is only "verified" when tagged B.

## A. BikeComputer — Waveshare ESP32‑S3‑Touch‑LCD‑1.28‑B (SKU 26959)

Source: `firmware/waveshare/main/board.h`, `docs/POWER_FEASIBILITY.md`, `docs/HW_RISK_REGISTER.md`,
`coord/reports/FW_STORAGE_MEMORY_REPORT.md`, `docs/HW_TEST_LOG_0.4.0.md` (branch `fw/phonefirst`).

| Item | Value | Tag |
|---|---|---|
| MCU | ESP32‑S3R2, dual‑core Xtensa LX7, silicon rev **v0.2** | B |
| Flash | **16 MB** W25Q128, QIO, detected by the board | B |
| PSRAM | **2 MB** quad (in package), memory test OK | B |
| Display | GC9A01A 240×240 round IPS, SPI2: SCLK 10 · MOSI 11 · MISO 12 · CS 9 · DC 8 · RST 14 · BL 2 (MOSFET, PWM); pixel clock 40 MHz (datasheet allows 80) | M (pins cross‑checked with NuttX and RIOT board ports); display runs on hardware since fw 0.1.x (B) |
| Touch | CST816S, I2C0 SDA 6 · SCL 7, INT 5, RST 13; auto‑sleeps → wake logic needed (HW‑5/HW‑8 history) | M + B (touch issues observed on the real board) |
| IMU | QMI8658 6‑axis, same I2C bus, addr 0x6B (SA0 high) / 0x6A, INT1 4, INT2 3 | M |
| Battery sense | VBAT → 200 kΩ/100 kΩ → GPIO1 (ADC1_CH0), ×3; percentage is a LiPo‑curve estimate ("≈") | M; voltage read on hardware (B) |
| Charger | ETA6096 switching charger, CV 4.21 V, **1 A fast charge fitted (R15 = 160 kΩ)**, 130 mA termination, no NTC; STAT not routed; no VBUS sense | M |
| Fitted cell | HXJNLDC 503030, **500 mAh**, max charge 0.5 A (seller spec) → 1 A ≈ 2 C: **charging safety OPEN (HW‑1)** | M/owner |
| USB | USB‑C with CH343P USB‑UART on UART0 → programming + serial log; the board enumerated as COM3 on the owner's PC | B |
| Buttons | Boot (GPIO0) only; Reset; no user keys → everything is touch | M |
| Audio / haptics | none (no buzzer, speaker or motor) → charge alerts "unavailable" (HW‑7) | M |
| Power states | Active · Display off (link on) · Connected standby · Deep sleep (lowest; no true power‑off, HW‑3); deep‑sleep current unmeasured (HW‑4) | M/U |
| Partition table (0.7.3) | nvs 0x9000/24 K · otadata 0xF000/8 K · phy_init 0x11000/4 K · ota_0 0x20000/4 M · ota_1 0x420000/3.94 M · coredump 0x810000/64 K · storage (FAT, wear‑levelled) 0x820000/7.88 M | B |
| App size | 0.7.3 app 1.83 MB of the 4 MB slot; static internal DRAM remaining 23 989 B (0.7.3) vs 37 901 B (0.7.2) vs 34 645 B (0.7.4‑rc1); internal heap at `app_main` ≈ 111 KB | B/E |
| Storage state | FAT root directory erased (512/512 entries) since 24–25 Oct → files cannot be created; 5 096 KB free of 7 964 KB; NVS healthy | B/K |
| External sensors | BLE: power meter (Cycling Power 0x1818 / XDS‑named 0x1828, char 0x2A63), HR strap (0x180D / 0x2A37), cadence‑speed CSC (0x1816 / 0x2A5B); XDS control point **0x2A55 never written** | M; decoders host‑tested; never run on the board with the meter |
| Not available | GPS (phone provides), ANT+ (no radio; never claimed) | M |

## B. Cyclift Watch — LILYGO T‑Watch 2021

Source: `watch/docs/HARDWARE_AUDIT.md`, `watch/firmware/src/hal/board_pins.hpp`, `watch/docs/HARDWARE_READINESS.md`
(branch `watch/w0-foundation`). **Nothing has been measured on the owner's watch.**

| Item | Value | Tag |
|---|---|---|
| Board revision | V1.0 / **V1.1 (default in firmware)** / V2 — printed on the PCB silkscreen; pin maps differ | **U — owner must read it** |
| MCU | T‑Micro32 Plus: ESP32 dual‑core LX6 240 MHz, Wi‑Fi 4, Bluetooth 4.2 BR/EDR + BLE (classic ESP32: no USB‑OTG, no BLE 5) | M |
| Flash / PSRAM | 8 MB / 2 MB (library flags, README); OTA layout `boards/partitions_8mb_ota.csv` with two 3 MB app slots | M; sizes to verify with `esptool flash_id` / boot print |
| Display | GC9A01 240×240 round, SPI (V1.x: MOSI 13 · SCLK 14 · CS 15 · DC 19 · RST 27 · BL 21); 16‑bit, full frame 115 KB | M |
| Touch | CST816S I2C 0x15, RST 33, INT 32 (V1.1) / 35 (V1.0); capacitive → gloves need the keys | M |
| Accelerometer | BMA423 I2C 0x19, INT IO32 (V1.1); step counter, wrist‑wake, tap → rep‑counting input | M |
| RTC | PCF8563 I2C 0x51, alarm → IO32 (V1.1 only) | M |
| Compass | QMC5883L (0x0D) **or** QMC5883P (0x2C) — two factory variants; firmware probes both | M |
| Haptics | vibration motor IO4 (V1.x) / IO2 (V2) | M |
| Keys | Reset · Boot (IO0) · two user keys IO35/IO34 (V1.1; swapped on V1.0; 39/34 on V2) | M |
| Battery | LiPo JST 1.25, TP4054 linear charger from USB‑C VBUS, voltage IO36, charge status IO2 (V1.x); 470–500 mAh (read the cell label); no fuel gauge | M/U |
| Power latch | PWR_ON IO5 (V1.x) / IO32 (V2) | M |
| USB | **charging only**; D+/D− carry UART0 to the **T‑U2T** CP2104 dongle (USB‑C plug, auto‑reset) → programming and backup require the T‑U2T | M; **owner must confirm the dongle is present** |
| Not available (V1.x) | GPS, barometer, SD card, microphone/speaker, optical HR, ANT+ → phone GPS mirrored; HR from the phone's sources | M |
| Build figures (compile only) | app image: static RAM 111 856 B (34.1 % of 320 KB), flash 2 190 064 B (69.6 % of 3 MB OTA slot); diagnostics image: 105 848 B / 1 545 559 B — CI run 42485131249 | linker, not device |

## Components explicitly rejected or not selected

- No ANT+ on either device (no radio); never promised.
- BikeComputer charge alerts (80/90/98 %, beeps) — not feasible on this board (no sense line, no sound).
- Watch frame buffers in PSRAM — rejected for speed; half‑screen buffer in internal RAM planned.
- External antenna on the watch — left as is (resistor move needed).
