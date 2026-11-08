#pragma once
// Cyclift Watch OS — hardware abstraction (owner directive §14: rendering, domain logic and drivers stay separate).
// Every driver sits behind one of these interfaces; the domain never includes Arduino headers. The host build (tests)
// links `FakeHal`; the watch build links the GC9A01 / CST816S / BMA423 / PCF8563 / NimBLE implementations in hal/esp32.
#include <cstdint>
#include <functional>
#include <vector>
#include <string>

namespace cyw::hal {

struct TouchEvent { enum Kind : uint8_t { Down, Move, Up, Tap, LongPress, SwipeLeft, SwipeRight, SwipeUp, SwipeDown } kind; int16_t x, y; };

struct IDisplay {           // GC9A01 240×240 round, 16-bit; LVGL draws into a half-screen buffer in internal RAM
    virtual void setBrightness(uint8_t pct) = 0;       // backlight PWM on TFT_BL
    virtual void sleep(bool on) = 0;                   // panel sleep for the low-power clock mode
    virtual void flush(int x1, int y1, int x2, int y2, const uint16_t* px) = 0;
    virtual ~IDisplay() = default;
};
struct ITouch {             // CST816S over I2C; gestures decoded by the controller, verified by the firmware (W1 test)
    virtual bool poll(TouchEvent& out) = 0;
    virtual ~ITouch() = default;
};
struct IImu {               // BMA423: raw 50/100 Hz samples for the rep detector, built-in step counter, wrist-raise
    virtual bool start(uint16_t hz) = 0;
    virtual void stop() = 0;
    virtual bool read(float& x, float& y, float& z) = 0;   // m/s²
    virtual uint32_t steps() = 0;                           // hardware step counter (since reset)
    virtual bool wristRaised() = 0;
    virtual ~IImu() = default;
};
struct IRtc {               // PCF8563: unix time, alarm interrupt on IO32 (V1.1) for wake-ups
    virtual uint32_t unix() = 0;
    virtual void set(uint32_t unix) = 0;
    virtual void alarmIn(uint32_t seconds) = 0;
    virtual ~IRtc() = default;
};
struct IPower {             // battery ADC (IO36) through a divider, charge detect (IO2 on V1.x), deep sleep
    virtual float batteryVolts() = 0;
    virtual uint8_t batteryPct() = 0;                        // from a measured discharge curve — W8; until then voltage only
    virtual bool charging() = 0;
    virtual void lightSleep(uint32_t ms) = 0;
    virtual void deepSleep() = 0;
    virtual ~IPower() = default;
};
struct IHaptics {           // vibration motor on IO4 (V1.x); patterns: tick, double, long
    virtual void pulse(uint16_t ms) = 0;
    virtual void pattern(const std::vector<uint16_t>& onOffMs) = 0;
    virtual ~IHaptics() = default;
};
struct IBle {               // NimBLE: peripheral towards the iPhone (one service, notify/write characteristics)
    virtual void start(const std::string& deviceName) = 0;
    virtual bool connected() = 0;
    virtual bool send(const std::vector<uint8_t>& frame) = 0;
    virtual void onReceive(std::function<void(const std::vector<uint8_t>&)> cb) = 0;
    virtual ~IBle() = default;
};
struct IStorage {           // LittleFS: settings, event queue, cached plan / recovery summaries
    virtual bool write(const std::string& path, const std::vector<uint8_t>& bytes) = 0;
    virtual bool read(const std::string& path, std::vector<uint8_t>& out) = 0;
    virtual ~IStorage() = default;
};

struct Board { IDisplay* display; ITouch* touch; IImu* imu; IRtc* rtc; IPower* power; IHaptics* haptics; IBle* ble; IStorage* storage; };

} // namespace cyw::hal
