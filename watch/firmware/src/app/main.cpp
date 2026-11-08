// Cyclift Watch OS — firmware entry (Arduino framework, LILYGO T-Watch 2021). W0: structure only.
// NOT FLASHED: the owner has not authorised flashing; this file compiles the module layout and the boot diagnostics.
#ifndef CYW_HOST
#include <Arduino.h>
#include <Wire.h>
#include "../hal/board_pins.hpp"
#include "../hal/hal.hpp"
#include "../domain/activity.hpp"
#include "../domain/navigation.hpp"
#include "../domain/coach.hpp"
#include "../domain/sync.hpp"

// W0 diagnostics (non-destructive): probe the I2C bus, read the battery ADC, print chip info — no writes to flash,
// no display init. Used to confirm the board revision and sensors before anything else is built.
static void probeI2c() {
    Wire.begin(cyw::pins::I2C_SDA, cyw::pins::I2C_SCL);
    const struct { uint8_t addr; const char* name; } expect[] = {
        {cyw::pins::ADDR_TOUCH, "CST816S touch"}, {cyw::pins::ADDR_BMA423, "BMA423 accelerometer"},
        {cyw::pins::ADDR_RTC, "PCF8563 RTC"}, {cyw::pins::ADDR_QMC5883L, "QMC5883L compass"}, {cyw::pins::ADDR_QMC5883P, "QMC5883P compass"}};
    for (auto& e : expect) { Wire.beginTransmission(e.addr); bool ok = Wire.endTransmission() == 0; Serial.printf("  0x%02X %-22s %s\n", e.addr, e.name, ok ? "FOUND" : "—"); }
}

void setup() {
    Serial.begin(115200);
    delay(300);
    pinMode(cyw::pins::PWR_ON, OUTPUT); digitalWrite(cyw::pins::PWR_ON, HIGH);     // keep the board powered from the battery
    Serial.println("Cyclift Watch OS — W0 diagnostics");
    Serial.printf("  chip %s rev %d, %u MHz, flash %u MB, PSRAM %u KB free heap %u\n", ESP.getChipModel(), ESP.getChipRevision(), ESP.getCpuFreqMHz(), ESP.getFlashChipSize() / (1024 * 1024), ESP.getPsramSize() / 1024, ESP.getFreeHeap());
    probeI2c();
    uint32_t raw = analogRead(cyw::pins::BAT_ADC);
    Serial.printf("  battery ADC raw %u (≈ %.2f V with the 2:1 divider, to be calibrated)\n", raw, raw / 4095.0f * 3.3f * 2.0f);
    if (cyw::pins::CHARGING >= 0) { pinMode(cyw::pins::CHARGING, INPUT_PULLUP); Serial.printf("  charging pin: %s\n", digitalRead(cyw::pins::CHARGING) == LOW ? "charging" : "not charging"); }
}

void loop() { delay(1000); }
#endif
