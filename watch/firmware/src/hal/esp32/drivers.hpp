#pragma once
// Cyclift Watch OS — ESP32 / Arduino implementations of the HAL for the LILYGO T-Watch 2021 (device build only).
// Everything here is written from the manufacturer's schematic and library; NOTHING has been exercised on hardware yet
// (owner: no flashing without approval). The first device milestone (M1) verifies each driver with the diagnostics build.
#ifndef CYW_HOST
#include <Arduino.h>
#include <Wire.h>
#include <SPI.h>
#include <TFT_eSPI.h>
#include <lvgl.h>
#include <LittleFS.h>
#include <NimBLEDevice.h>
#include "../hal.hpp"
#include "../board_pins.hpp"
#include "../rtc_time.hpp"

namespace cyw::hal::esp32 {

// ---------------------------------------------------------------- display (TFT_eSPI GC9A01 + LVGL flush)
class Display : public IDisplay {
public:
    static constexpr int W = 240, H = 240, BUF_LINES = 120;        // half-screen buffer: 240 × 120 × 2 B = 57.6 KB in internal RAM
    void begin() {
        tft_.init(); tft_.setRotation(0); tft_.fillScreen(TFT_BLACK);
        ledcAttach(pins::LCD_BL, 2000, 8); setBrightness(60);   // Arduino-ESP32 core 3.x LEDC API (pin-based)
        lv_init();
        buf_ = static_cast<lv_color_t*>(heap_caps_malloc(W * BUF_LINES * sizeof(lv_color_t), MALLOC_CAP_INTERNAL | MALLOC_CAP_DMA));
        lv_disp_draw_buf_init(&draw_, buf_, nullptr, W * BUF_LINES);
        lv_disp_drv_init(&drv_); drv_.hor_res = W; drv_.ver_res = H; drv_.draw_buf = &draw_; drv_.user_data = this;
        drv_.flush_cb = [](lv_disp_drv_t* d, const lv_area_t* a, lv_color_t* px) { auto* self = static_cast<Display*>(d->user_data); self->flush(a->x1, a->y1, a->x2, a->y2, reinterpret_cast<const uint16_t*>(px)); lv_disp_flush_ready(d); };
        lv_disp_drv_register(&drv_);
    }
    void setBrightness(uint8_t pct) override { ledcWrite(pins::LCD_BL, uint32_t(pct) * 255 / 100); }
    void sleep(bool on) override { if (on) { tft_.writecommand(0x10); ledcWrite(pins::LCD_BL, 0); } else { tft_.writecommand(0x11); delay(120); setBrightness(60); } }
    void flush(int x1, int y1, int x2, int y2, const uint16_t* px) override {
        uint32_t t0 = micros();
        tft_.startWrite(); tft_.setAddrWindow(x1, y1, x2 - x1 + 1, y2 - y1 + 1); tft_.pushPixels(const_cast<uint16_t*>(px), (x2 - x1 + 1) * (y2 - y1 + 1)); tft_.endWrite();
        flushUs += micros() - t0; flushPx += uint32_t(x2 - x1 + 1) * uint32_t(y2 - y1 + 1); flushes++;
    }
    /// Time spent sending pixels to the panel over SPI (blocking), pixels sent and transfers — read by the perf report.
    uint32_t flushUs = 0, flushPx = 0, flushes = 0;
private:
    TFT_eSPI tft_; lv_disp_draw_buf_t draw_{}; lv_disp_drv_t drv_{}; lv_color_t* buf_ = nullptr;
};

// ---------------------------------------------------------------- touch (CST816S over I2C: gesture + one point)
class Touch : public ITouch {
public:
    void begin() { pinMode(pins::TOUCH_RST, OUTPUT); digitalWrite(pins::TOUCH_RST, LOW); delay(10); digitalWrite(pins::TOUCH_RST, HIGH); delay(60); pinMode(pins::TOUCH_INT, INPUT); }
    /// Registers (CST816S datasheet): 0x01 gesture (0 none · 1 up · 2 down · 3 left · 4 right · 5 tap · 0x0C long), 0x02 finger count, 0x03..0x06 XY.
    bool poll(TouchEvent& out) override {
        if (digitalRead(pins::TOUCH_INT) == HIGH && millis() - lastReadMs_ < 20) return false;   // INT is active-low; still poll at ≤ 50 Hz for releases
        lastReadMs_ = millis();
        Wire.beginTransmission(pins::ADDR_TOUCH); Wire.write(0x01); if (Wire.endTransmission(false) != 0) return false;
        if (Wire.requestFrom(int(pins::ADDR_TOUCH), 6) != 6) return false;
        uint8_t g = Wire.read(), n = Wire.read(), xh = Wire.read(), xl = Wire.read(), yh = Wire.read(), yl = Wire.read();
        int16_t x = ((xh & 0x0F) << 8) | xl, y = ((yh & 0x0F) << 8) | yl; bool down = n > 0;
        if (down && !down_) { down_ = true; downX_ = x; downY_ = y; downMs_ = millis(); out = {TouchEvent::Down, x, y}; return true; }
        if (!down && down_) {
            down_ = false; uint32_t held = millis() - downMs_; int dx = x - downX_, dy = y - downY_;
            // the controller's gesture code is used when it is set; otherwise we derive one from the stroke
            TouchEvent::Kind k = TouchEvent::Tap;
            if (g == 1 || (g == 0 && dy < -40 && std::abs(dy) > std::abs(dx))) k = TouchEvent::SwipeUp;
            else if (g == 2 || (g == 0 && dy > 40 && std::abs(dy) > std::abs(dx))) k = TouchEvent::SwipeDown;
            else if (g == 3 || (g == 0 && dx < -40)) k = TouchEvent::SwipeLeft;
            else if (g == 4 || (g == 0 && dx > 40)) k = TouchEvent::SwipeRight;
            else if (g == 0x0C || held > 600) k = TouchEvent::LongPress;
            out = {k, downX_, downY_}; return true;
        }
        if (down) { out = {TouchEvent::Move, x, y}; return true; }
        return false;
    }
private:
    bool down_ = false; int16_t downX_ = 0, downY_ = 0; uint32_t downMs_ = 0, lastReadMs_ = 0;
};

// ---------------------------------------------------------------- keys (Key1 IO35, Key2 IO34: input-only, external pull-ups → active low; Boot IO0)
struct Keys {
    void begin() { pinMode(pins::BTN_KEY1, INPUT); pinMode(pins::BTN_KEY2, INPUT); pinMode(pins::BTN_BOOT, INPUT_PULLUP); }
    bool key1() const { return digitalRead(pins::BTN_KEY1) == LOW; }
    bool key2() const { return digitalRead(pins::BTN_KEY2) == LOW; }
    bool boot() const { return digitalRead(pins::BTN_BOOT) == LOW; }
};

// ---------------------------------------------------------------- haptics (motor on IO4 via transistor)
class Haptics : public IHaptics {
public:
    void begin() { pinMode(pins::MOTOR, OUTPUT); digitalWrite(pins::MOTOR, LOW); }
    void pulse(uint16_t ms) override { if (!ms) return; offAtMs_ = millis() + ms; digitalWrite(pins::MOTOR, HIGH); }
    void pattern(const std::vector<uint16_t>& onOff) override { if (!onOff.empty()) pulse(onOff[0]); }   // W4: full patterns via a timer
    void tick() { if (offAtMs_ && millis() >= offAtMs_) { digitalWrite(pins::MOTOR, LOW); offAtMs_ = 0; } }
private:
    uint32_t offAtMs_ = 0;
};

// ---------------------------------------------------------------- power (battery ADC on IO36 through a 2:1 divider; CHARGING on IO2)
class Power : public IPower {
public:
    void begin() { analogReadResolution(12); analogSetPinAttenuation(pins::BAT_ADC, ADC_11db); if (pins::CHARGING >= 0) pinMode(pins::CHARGING, INPUT_PULLUP); }
    float batteryVolts() override { uint32_t acc = 0; for (int i = 0; i < 8; i++) acc += analogRead(pins::BAT_ADC); return acc / 8.f / 4095.f * 3.3f * 2.0f * 1.0f; }   // calibration factor 1.0 until measured (M4)
    /// Until the discharge curve is measured (M4) this is a plain LiPo voltage table and is flagged as an estimate by the caller.
    uint8_t batteryPct() override { float v = batteryVolts(); const float pts[][2] = {{4.20f, 100}, {4.05f, 85}, {3.95f, 70}, {3.85f, 55}, {3.78f, 40}, {3.70f, 25}, {3.60f, 10}, {3.40f, 0}}; for (size_t i = 1; i < 8; i++) if (v >= pts[i][0]) { float t = (v - pts[i][0]) / (pts[i - 1][0] - pts[i][0]); return uint8_t(pts[i][1] + t * (pts[i - 1][1] - pts[i][1])); } return 0; }
    bool charging() override { return pins::CHARGING >= 0 && digitalRead(pins::CHARGING) == LOW; }
    void lightSleep(uint32_t ms) override { esp_sleep_enable_timer_wakeup(uint64_t(ms) * 1000); esp_light_sleep_start(); }
    void deepSleep() override { esp_deep_sleep_start(); }
};

// ---------------------------------------------------------------- RTC (PCF8563 at 0x51): read/write BCD time
class Rtc : public IRtc {
public:
    uint32_t unixTime() override {
        Wire.beginTransmission(pins::ADDR_RTC); Wire.write(0x02); if (Wire.endTransmission(false) != 0) return 0;
        if (Wire.requestFrom(int(pins::ADDR_RTC), 7) != 7) return 0;
        uint8_t s = bcd(Wire.read() & 0x7F), mi = bcd(Wire.read() & 0x7F), h = bcd(Wire.read() & 0x3F), d = bcd(Wire.read() & 0x3F); Wire.read(); uint8_t mo = bcd(Wire.read() & 0x1F), y = bcd(Wire.read());
        return toUnix(2000 + y, mo, d, h, mi, s);
    }
    void set(uint32_t unixS) override {
        int y, mo, d, h, mi, s; fromUnix(unixS, y, mo, d, h, mi, s);
        Wire.beginTransmission(pins::ADDR_RTC); Wire.write(0x02); Wire.write(enc(s)); Wire.write(enc(mi)); Wire.write(enc(h)); Wire.write(enc(d)); Wire.write(0); Wire.write(enc(mo)); Wire.write(enc(y - 2000)); Wire.endTransmission();
    }
    void alarmIn(uint32_t) override {}   // M2: minute alarm via IO32 for the low-power clock
    /// Stage 1.2 (v3poc): reads the clock with its integrity flag (VL) — false after a power loss, so no stale time is shown.
    bool read(cyw::rtc::Reading& out) {
        uint8_t r[7];
        Wire.beginTransmission(pins::ADDR_RTC); Wire.write(0x02); if (Wire.endTransmission(false) != 0) return false;
        if (Wire.requestFrom(int(pins::ADDR_RTC), 7) != 7) return false;
        for (auto& b : r) b = uint8_t(Wire.read());
        out = cyw::rtc::fromRegs(r); return true;
    }
    /// Stage 1.2 (v3poc): writes local time; also clears VL. Returns false if the chip did not acknowledge.
    bool write(uint32_t t) {
        uint8_t r[7]; cyw::rtc::toRegs(t, r);
        Wire.beginTransmission(pins::ADDR_RTC); Wire.write(0x02); for (uint8_t b : r) Wire.write(b);
        return Wire.endTransmission() == 0;
    }
    static uint8_t bcd(uint8_t v) { return (v >> 4) * 10 + (v & 0x0F); }
    static uint8_t enc(int v) { return uint8_t(((v / 10) << 4) | (v % 10)); }
    static uint32_t toUnix(int y, int mo, int d, int h, int mi, int s) { int a = (14 - mo) / 12, yy = y + 4800 - a, mm = mo + 12 * a - 3; long jdn = d + (153 * mm + 2) / 5 + 365L * yy + yy / 4 - yy / 100 + yy / 400 - 32045; return uint32_t((jdn - 2440588L) * 86400L + h * 3600 + mi * 60 + s); }
    static void fromUnix(uint32_t t, int& y, int& mo, int& d, int& h, int& mi, int& s) { long days = t / 86400; long rem = t % 86400; h = rem / 3600; mi = (rem % 3600) / 60; s = rem % 60; long z = days + 719468; long era = (z >= 0 ? z : z - 146096) / 146097; unsigned doe = unsigned(z - era * 146097); unsigned yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365; long yr = long(yoe) + era * 400; unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100); unsigned mp = (5 * doy + 2) / 153; d = int(doy - (153 * mp + 2) / 5 + 1); mo = int(mp < 10 ? mp + 3 : mp - 9); y = int(yr + (mo <= 2)); }
};

// ---------------------------------------------------------------- storage (LittleFS)
class Storage : public IStorage {
public:
    bool begin() { return LittleFS.begin(true); }
    bool write(const std::string& path, const std::vector<uint8_t>& bytes) override { fs::File f = LittleFS.open(path.c_str(), "w"); if (!f) return false; f.write(bytes.data(), bytes.size()); f.close(); return true; }
    bool read(const std::string& path, std::vector<uint8_t>& out) override { fs::File f = LittleFS.open(path.c_str(), "r"); if (!f) return false; out.resize(f.size()); f.read(out.data(), out.size()); f.close(); return true; }
};

// ---------------------------------------------------------------- BLE (NimBLE peripheral: one service, TX notify / RX write)
class Ble : public IBle {
public:
    static constexpr const char* SERVICE = "6E400001-C1F7-4F1A-9C5E-2026110800C1";   // Cyclift Watch service (assigned 8 Nov 2026)
    static constexpr const char* TX = "6E400002-C1F7-4F1A-9C5E-2026110800C1";        // watch → phone (notify)
    static constexpr const char* RX = "6E400003-C1F7-4F1A-9C5E-2026110800C1";        // phone → watch (write without response)
    void start(const std::string& name) override {
        NimBLEDevice::init(name); NimBLEDevice::setMTU(247);
        server_ = NimBLEDevice::createServer(); server_->setCallbacks(new ServerCb(this));
        NimBLEService* svc = server_->createService(SERVICE);
        tx_ = svc->createCharacteristic(TX, NIMBLE_PROPERTY::NOTIFY);
        rx_ = svc->createCharacteristic(RX, NIMBLE_PROPERTY::WRITE_NR | NIMBLE_PROPERTY::WRITE); rx_->setCallbacks(new RxCb(this));
        svc->start(); NimBLEAdvertising* adv = NimBLEDevice::getAdvertising(); adv->addServiceUUID(SERVICE); adv->setScanResponse(true); adv->start();
    }
    bool connected() override { return connected_; }
    bool send(const std::vector<uint8_t>& frame) override { if (!connected_ || !tx_) return false; tx_->setValue(frame.data(), frame.size()); tx_->notify(); return true; }   // NimBLE 1.4 notify() returns void
    void onReceive(std::function<void(const std::vector<uint8_t>&)> cb) override { cb_ = std::move(cb); }
    bool takeLinkChange(bool& linked) { if (!changed_) return false; changed_ = false; linked = connected_; return true; }
private:
    struct ServerCb : NimBLEServerCallbacks { Ble* b; explicit ServerCb(Ble* x) : b(x) {} void onConnect(NimBLEServer*) override { b->connected_ = true; b->changed_ = true; } void onDisconnect(NimBLEServer*) override { b->connected_ = false; b->changed_ = true; NimBLEDevice::startAdvertising(); } };
    struct RxCb : NimBLECharacteristicCallbacks { Ble* b; explicit RxCb(Ble* x) : b(x) {} void onWrite(NimBLECharacteristic* c) override { if (b->cb_) { std::string v = c->getValue(); b->cb_(std::vector<uint8_t>(v.begin(), v.end())); } } };
    NimBLEServer* server_ = nullptr; NimBLECharacteristic* tx_ = nullptr; NimBLECharacteristic* rx_ = nullptr; std::function<void(const std::vector<uint8_t>&)> cb_; volatile bool connected_ = false, changed_ = false;
};

} // namespace cyw::hal::esp32
#endif
