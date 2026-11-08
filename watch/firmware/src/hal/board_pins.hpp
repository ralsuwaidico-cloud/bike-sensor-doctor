#pragma once
// LILYGO T-Watch 2021 (round, T-Micro32 Plus, GC9A01) — pin maps per board revision, transcribed from the official
// repository (Xinyuan-LilyGO/T-Watch-2021: TWatch_2021_Library/src/board/*.h and image/T-WATCH2021-V1.1-en.jpg).
// Never reuse the rectangular T-Watch 2020 or the ESP32-S3 T-Watch S3 maps: this board is different.
// LCD_* (not TFT_*): TFT_eSPI defines TFT_* macros on the compiler command line, so those names cannot be identifiers.
// The revision is printed on the silkscreen; CYW_BOARD_* is set per PlatformIO environment.
#include <cstdint>
namespace cyw::pins {
#if defined(CYW_BOARD_V2)
constexpr int PWR_ON = 32, CHARGING = -1, BAT_ADC = 36;
constexpr int BTN_1 = 0, BTN_2 = 39, BTN_3 = 34;
constexpr int MOTOR = 2;
constexpr int I2C_SCL = 26, I2C_SDA = 27;
constexpr int TOUCH_RST = -1, TOUCH_INT = 37, RTC_INT = 37, BMA_INT1 = 37, BMA_INT2 = 37, AIO_INT = 37;
constexpr int LCD_MOSI = 23, LCD_SCLK = 18, LCD_CS = 5, LCD_DC = 22, LCD_RST = -1, LCD_BL = 21, LCD_MISO = -1;
constexpr bool HAS_GPS = true, HAS_SD = true, HAS_ENCODER = true, HAS_BME280 = true;
constexpr int GPS_RX = 3, GPS_TX = 1, GPS_WAKE = 25;
#elif defined(CYW_BOARD_V1_0)
constexpr int PWR_ON = 5, CHARGING = 2, BAT_ADC = 36;
constexpr int BTN_1 = 0, BTN_2 = 34, BTN_3 = 35;
constexpr int MOTOR = 4;
constexpr int I2C_SCL = 25, I2C_SDA = 26;
constexpr int TOUCH_RST = 33, TOUCH_INT = 35, RTC_INT = -1, BMA_INT1 = 22, BMA_INT2 = 39, AIO_INT = -1;
constexpr int LCD_MOSI = 13, LCD_SCLK = 14, LCD_CS = 15, LCD_DC = 19, LCD_RST = 27, LCD_BL = 21, LCD_MISO = -1;
constexpr bool HAS_GPS = false, HAS_SD = false, HAS_ENCODER = false, HAS_BME280 = false;
#else   // V1.1 (library name V1_2): the revision sold with the Type-C case; all interrupts on IO32
constexpr int PWR_ON = 5, CHARGING = 2, BAT_ADC = 36;
constexpr int BTN_1 = 0, BTN_2 = 35, BTN_3 = 34;
constexpr int MOTOR = 4;
constexpr int I2C_SCL = 25, I2C_SDA = 26;
constexpr int TOUCH_RST = 33, TOUCH_INT = 32, RTC_INT = 32, BMA_INT1 = 32, BMA_INT2 = 32, AIO_INT = 32;
constexpr int LCD_MOSI = 13, LCD_SCLK = 14, LCD_CS = 15, LCD_DC = 19, LCD_RST = 27, LCD_BL = 21, LCD_MISO = -1;
constexpr bool HAS_GPS = false, HAS_SD = false, HAS_ENCODER = false, HAS_BME280 = false;
#endif
constexpr int SCREEN_W = 240, SCREEN_H = 240;        // GC9A01, round active area, 16-bit colour
// I2C peripherals (7-bit addresses from the datasheets / library): CST816S touch 0x15 · BMA423 0x19 · PCF8563 RTC 0x51 ·
// QMC5883L 0x0D (factory variant A) or QMC5883P 0x2C (variant B — the factory firmware ships one binary per variant)
// Key aliases used by the firmware: KEY1 = upper-left user key, KEY2 = lower-left, BOOT = IO0 (strapping; shortcut only)
constexpr int BTN_BOOT = BTN_1, BTN_KEY1 = BTN_2, BTN_KEY2 = BTN_3;
constexpr uint8_t ADDR_TOUCH = 0x15, ADDR_BMA423 = 0x19, ADDR_RTC = 0x51, ADDR_QMC5883L = 0x0D, ADDR_QMC5883P = 0x2C;
}
