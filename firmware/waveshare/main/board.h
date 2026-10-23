/*
 * Waveshare ESP32-S3-Touch-LCD-1.28-B (SKU 26959 = the 1.28 board in the CNC metal case).
 * ESP32-S3R2 (2 MB quad PSRAM in package), 16 MB W25Q128 flash, GC9A01A 240×240 round IPS (SPI), CST816S touch (I2C),
 * QMI8658 6-axis IMU (same I2C bus), ETA6096 LiPo charger on an MX1.25 connector, CH343P USB-UART on USB-C (UART0).
 *
 * Pin map cross-checked 2026-10-23 between the Waveshare wiki (GPIO1/2/6/7), the Apache NuttX board port and the RIOT-OS
 * board port (both list identical LCD/touch/IMU pins). Verified on hardware: NOT YET (Phase A diagnostic does that).
 */
#pragma once

/* LCD — GC9A01A, SPI2 */
#define BOARD_LCD_HOST       SPI2_HOST
#define BOARD_LCD_SCLK       10
#define BOARD_LCD_MOSI       11
#define BOARD_LCD_MISO       12
#define BOARD_LCD_CS         9
#define BOARD_LCD_DC         8
#define BOARD_LCD_RST        14
#define BOARD_LCD_BL         2      /* backlight via MOSFET, PWM-able */
#define BOARD_LCD_W          240
#define BOARD_LCD_H          240
#define BOARD_LCD_PCLK_HZ    (40 * 1000 * 1000)   /* datasheet allows 80 MHz; start conservative */

/* I2C0 — touch + IMU */
#define BOARD_I2C_SDA        6
#define BOARD_I2C_SCL        7
#define BOARD_TP_INT         5
#define BOARD_TP_RST         13
#define BOARD_IMU_INT1       4
#define BOARD_IMU_INT2       3
#define BOARD_IMU_ADDR_A     0x6B   /* QMI8658 SA0 high */
#define BOARD_IMU_ADDR_B     0x6A   /* QMI8658 SA0 low */

/* Battery: VBAT → 200 kΩ / 100 kΩ divider → GPIO1 (ADC1_CH0); VBAT = 3 × pin voltage (Waveshare wiki) */
#define BOARD_BAT_ADC_GPIO   1
#define BOARD_BAT_DIVIDER    3.0f

#define BOARD_BOOT_BUTTON    0
