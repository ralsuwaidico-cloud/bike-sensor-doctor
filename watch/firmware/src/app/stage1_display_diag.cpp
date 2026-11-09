// Cyclift Watch — Stage 1 DISPLAY DIAGNOSTIC (T-Watch 2021 V1.1 pins). Built only in env T-Watch-2021-V1_1-display-diag.
// Purpose: find why the Stage 1 build showed a completely black screen (no backlight) on the owner's watch (9 Nov 2026).
// It tests each part of the display chain separately and reports every step on the USB serial line (115200 baud):
//   T1 power-hold pin IO5 · T2 backlight IO21 as a plain on/off pin · T3 backlight IO21 through LEDC PWM (12 kHz, like the
//   factory firmware) · T4 GC9A01 panel through TFT_eSPI 2.5.43 (the Stage 1 driver, VSPI) · T5 GC9A01 panel through an
//   independent raw-SPI driver on HSPI with the factory firmware's exact reset timing and init sequence.
// No Bluetooth, no Wi-Fi, no sleep, no touch/sensors, no flash writes. Keys only to repeat the cycle on the watch itself.
#if defined(CYW_DISPLAY_DIAG)
#include <Arduino.h>
#include <SPI.h>
#include <TFT_eSPI.h>
#include <esp_system.h>
#include "../hal/board_pins.hpp"

namespace pins = cyw::pins;
static TFT_eSPI tft;
static SPIClass rawSpi(HSPI);
static uint32_t cycleNo = 0;

static void say(const char* fmt, ...) {
    char b[200]; va_list ap; va_start(ap, fmt); vsnprintf(b, sizeof b, fmt, ap); va_end(ap);
    Serial.printf("[%7lu ms] %s\n", (unsigned long)millis(), b); Serial.flush();
}

// ---- T5: factory-equivalent GC9A01 init (same command/data sequence as LILYGO's firmware driver Arduino_GFX and TFT_eSPI)
struct InitCmd { uint8_t cmd, len; uint8_t data[12]; };
static const InitCmd GC9A01_INIT[] = {
    {0xEF, 0, {}},
    {0xEB, 1, {0x14}},
    {0xFE, 0, {}},
    {0xEF, 0, {}},
    {0xEB, 1, {0x14}},
    {0x84, 1, {0x40}},
    {0x85, 1, {0xFF}},
    {0x86, 1, {0xFF}},
    {0x87, 1, {0xFF}},
    {0x88, 1, {0x0A}},
    {0x89, 1, {0x21}},
    {0x8A, 1, {0x00}},
    {0x8B, 1, {0x80}},
    {0x8C, 1, {0x01}},
    {0x8D, 1, {0x01}},
    {0x8E, 1, {0xFF}},
    {0x8F, 1, {0xFF}},
    {0xB6, 2, {0x00, 0x20}},
    {0x3A, 1, {0x05}},
    {0x90, 4, {0x08, 0x08, 0x08, 0x08}},
    {0xBD, 1, {0x06}},
    {0xBC, 1, {0x00}},
    {0xFF, 3, {0x60, 0x01, 0x04}},
    {0xC3, 1, {0x13}},
    {0xC4, 1, {0x13}},
    {0xC9, 1, {0x22}},
    {0xBE, 1, {0x11}},
    {0xE1, 2, {0x10, 0x0E}},
    {0xDF, 3, {0x21, 0x0C, 0x02}},
    {0xF0, 6, {0x45, 0x09, 0x08, 0x08, 0x26, 0x2A}},
    {0xF1, 6, {0x43, 0x70, 0x72, 0x36, 0x37, 0x6F}},
    {0xF2, 6, {0x45, 0x09, 0x08, 0x08, 0x26, 0x2A}},
    {0xF3, 6, {0x43, 0x70, 0x72, 0x36, 0x37, 0x6F}},
    {0xED, 2, {0x1B, 0x0B}},
    {0xAE, 1, {0x77}},
    {0xCD, 1, {0x63}},
    {0x70, 9, {0x07, 0x07, 0x04, 0x0E, 0x0F, 0x09, 0x07, 0x08, 0x03}},
    {0xE8, 1, {0x34}},
    {0x62, 12, {0x18, 0x0D, 0x71, 0xED, 0x70, 0x70, 0x18, 0x0F, 0x71, 0xEF, 0x70, 0x70}},
    {0x63, 12, {0x18, 0x11, 0x71, 0xF1, 0x70, 0x70, 0x18, 0x13, 0x71, 0xF3, 0x70, 0x70}},
    {0x64, 7, {0x28, 0x29, 0xF1, 0x01, 0xF1, 0x00, 0x07}},
    {0x66, 10, {0x3C, 0x00, 0xCD, 0x67, 0x45, 0x45, 0x10, 0x00, 0x00, 0x00}},
    {0x67, 10, {0x00, 0x3C, 0x00, 0x00, 0x00, 0x01, 0x54, 0x10, 0x32, 0x98}},
    {0x74, 7, {0x10, 0x85, 0x80, 0x00, 0x00, 0x4E, 0x00}},
    {0x98, 2, {0x3E, 0x07}},
    {0x35, 0, {}},
    {0x21, 0, {}},
    {0x11, 0, {}},
    {0xFF, 120, {}},   // delay 120 ms
    {0x29, 0, {}},
    {0xFF, 20, {}},   // delay 20 ms
};
static void rawCmd(uint8_t c) { digitalWrite(pins::LCD_DC, LOW); digitalWrite(pins::LCD_CS, LOW); rawSpi.transfer(c); digitalWrite(pins::LCD_CS, HIGH); }
static void rawData(const uint8_t* d, size_t n) { digitalWrite(pins::LCD_DC, HIGH); digitalWrite(pins::LCD_CS, LOW); for (size_t i = 0; i < n; i++) rawSpi.transfer(d[i]); digitalWrite(pins::LCD_CS, HIGH); }
static void rawData1(uint8_t d) { rawData(&d, 1); }
static void rawFill(uint16_t c) {
    uint8_t ca[] = {0, 0, 0, 239}; rawCmd(0x2A); rawData(ca, 4); rawCmd(0x2B); rawData(ca, 4); rawCmd(0x2C);
    digitalWrite(pins::LCD_DC, HIGH); digitalWrite(pins::LCD_CS, LOW);
    for (uint32_t i = 0; i < 240UL * 240UL; i++) { rawSpi.transfer(c >> 8); rawSpi.transfer(c & 0xFF); }
    digitalWrite(pins::LCD_CS, HIGH);
}
static void testRaw() {
    say("T5 raw-SPI driver: HSPI begin(SCLK=%d, MOSI=%d), CS=%d DC=%d RST=%d, 40 MHz mode 0", pins::LCD_SCLK, pins::LCD_MOSI, pins::LCD_CS, pins::LCD_DC, pins::LCD_RST);
    pinMode(pins::LCD_CS, OUTPUT); digitalWrite(pins::LCD_CS, HIGH); pinMode(pins::LCD_DC, OUTPUT); digitalWrite(pins::LCD_DC, HIGH);
    rawSpi.begin(pins::LCD_SCLK, -1, pins::LCD_MOSI, -1);
    rawSpi.beginTransaction(SPISettings(40000000, MSBFIRST, SPI_MODE0));
    pinMode(pins::LCD_RST, OUTPUT); digitalWrite(pins::LCD_RST, HIGH); delay(50); digitalWrite(pins::LCD_RST, LOW); delay(50); digitalWrite(pins::LCD_RST, HIGH); delay(50);
    say("T5 reset pulse done (factory timing 50/50/50 ms); sending %u init entries", unsigned(sizeof GC9A01_INIT / sizeof GC9A01_INIT[0]));
    for (const auto& e : GC9A01_INIT) { if (e.cmd == 0xFF) { delay(e.len); continue; } rawCmd(e.cmd); if (e.len) rawData(e.data, e.len); }
    rawCmd(0x36); rawData1(0x08);   // MADCTL as TFT_eSPI rotation 0
    say("T5 init sent; filling WHITE / YELLOW / CYAN, 3 s each (WATCH: white, yellow, cyan?)");
    const uint16_t cols[] = {0xFFFF, 0xFFE0, 0x07FF}; const char* names[] = {"WHITE", "YELLOW", "CYAN"};
    for (int i = 0; i < 3; i++) { uint32_t t0 = millis(); rawFill(cols[i]); say("T5 %s filled in %lu ms", names[i], (unsigned long)(millis() - t0)); delay(3000); }
    rawSpi.endTransaction(); rawSpi.end();
    say("T5 done");
}

static void testTftEspi() {
    say("T4 TFT_eSPI %s: init() on VSPI, SCLK=%d MOSI=%d CS=%d DC=%d RST=%d, SPI_FREQUENCY=%d", TFT_ESPI_VERSION, TFT_SCLK, TFT_MOSI, TFT_CS, TFT_DC, TFT_RST, SPI_FREQUENCY);
    uint32_t t0 = millis(); tft.init(); say("T4 init returned after %lu ms", (unsigned long)(millis() - t0));
    tft.setRotation(0);
    say("T4 filling RED / GREEN / BLUE, 3 s each (WATCH: red, green, blue?)");
    const uint16_t cols[] = {TFT_RED, TFT_GREEN, TFT_BLUE}; const char* names[] = {"RED", "GREEN", "BLUE"};
    for (int i = 0; i < 3; i++) { t0 = millis(); tft.fillScreen(cols[i]); say("T4 %s filled in %lu ms", names[i], (unsigned long)(millis() - t0)); delay(3000); }
    tft.fillScreen(TFT_BLACK); say("T4 done (black)");
}

static void testBacklightGpio() {
    pinMode(pins::LCD_BL, OUTPUT);
    digitalWrite(pins::LCD_BL, HIGH); say("T2 backlight IO%d plain HIGH for 5 s (WATCH: screen glows?) readback=%d", pins::LCD_BL, digitalRead(pins::LCD_BL)); delay(5000);
    digitalWrite(pins::LCD_BL, LOW);  say("T2 backlight LOW for 2 s (WATCH: glow gone?) readback=%d", digitalRead(pins::LCD_BL)); delay(2000);
    digitalWrite(pins::LCD_BL, HIGH); say("T2 backlight HIGH again");
}

static void testBacklightPwm() {
    bool ok = ledcAttach(pins::LCD_BL, 12000, 8);
    say("T3 ledcAttach(IO%d, 12 kHz, 8 bit) returned %s", pins::LCD_BL, ok ? "true" : "FALSE");
    const uint8_t duty[] = {255, 128, 32, 255};
    for (uint8_t d : duty) { bool w = ledcWrite(pins::LCD_BL, d); say("T3 PWM duty %u/255 (ledcWrite %s) for 2 s (WATCH: brightness changes?)", d, w ? "ok" : "FAILED"); delay(2000); }
    ledcDetach(pins::LCD_BL); pinMode(pins::LCD_BL, OUTPUT); digitalWrite(pins::LCD_BL, HIGH);
    say("T3 done; backlight back to plain HIGH");
}

static void cycle() {
    cycleNo++;
    say("===== cycle %lu: T2 backlight GPIO -> T3 backlight PWM -> T4 TFT_eSPI R/G/B -> T5 raw W/Y/C =====", (unsigned long)cycleNo);
    testBacklightGpio(); testBacklightPwm(); testTftEspi(); testRaw();
    say("===== cycle %lu complete; repeats in 20 s, or press a side key / send 'c' =====", (unsigned long)cycleNo);
}

void setup() {
    Serial.begin(115200); delay(300);
    say("Cyclift DISPLAY DIAGNOSTIC (V1.1 pins) - reset reason %d, chip rev %d, CPU %lu MHz, heap %lu, psram %lu, flash %lu MB",
        int(esp_reset_reason()), ESP.getChipRevision(), (unsigned long)getCpuFrequencyMhz(), (unsigned long)ESP.getFreeHeap(),
        (unsigned long)ESP.getPsramSize(), (unsigned long)(ESP.getFlashChipSize() >> 20));
    pinMode(pins::PWR_ON, OUTPUT); digitalWrite(pins::PWR_ON, HIGH);
    say("T1 power-hold IO%d set HIGH (readback %d)", pins::PWR_ON, digitalRead(pins::PWR_ON));
    pinMode(pins::BTN_KEY1, INPUT); pinMode(pins::BTN_KEY2, INPUT);
    cycle();
}

void loop() {
    static uint32_t last = millis();
    bool key = digitalRead(pins::BTN_KEY1) == LOW || digitalRead(pins::BTN_KEY2) == LOW;
    bool cmd = Serial.available() && Serial.read() == 'c';
    if (key) say("side key pressed (KEY1 IO%d=%d, KEY2 IO%d=%d)", pins::BTN_KEY1, digitalRead(pins::BTN_KEY1), pins::BTN_KEY2, digitalRead(pins::BTN_KEY2));
    if (key || cmd || millis() - last > 20000) { cycle(); last = millis(); }
    delay(20);
}
#endif
