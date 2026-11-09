// Cyclift Watch v3 — Stage 1 proof-of-concept firmware entry (PlatformIO env T-Watch-2021-*-v3poc only).
// A separate program from the existing application (app/main.cpp is not part of this build): approved v3 screens with
// SIMULATED ride data and a SIMULATED iPhone. No Bluetooth is started, nothing is sent to the iPhone, nothing is written to
// flash storage. NOT FLASHED: loading it onto the watch is Stage 2 and needs the owner's approval.
//
// Serial console (115200 baud) for the Stage 2 test procedure — one character per command:
//   m menu (Key 1)   b Key 2   f face   r start ride   p tap Pause/Resume   d density   t text size   l language
//   c phone link     s cycle sensors   x next reply: refuse   n next reply: no answer   u perf report   ? help
#if defined(CYW_V3POC) && !defined(CYW_HOST)
#include <Arduino.h>
#include <Wire.h>
#include "../hal/board_pins.hpp"
#include "../hal/esp32/drivers.hpp"
#include "../ui/v3/cyv3_ui.hpp"

using namespace cyw;
using namespace cyw::v3;

static hal::esp32::Display g_display; static hal::esp32::Touch g_touch; static hal::esp32::Keys g_keys;
static hal::esp32::Power g_power; static hal::esp32::Rtc g_rtc;
static Model g_model; static Ui g_ui;
static uint32_t g_lastLv = 0, g_lastSlow = 0, g_lastPerf = 0, g_renderUs = 0, g_renderMax = 0, g_frames = 0, g_rebuilds = 0;
static bool g_k1 = false, g_k2 = false;
static size_t g_logShown = 0;

static void readClock() {
    uint32_t t = g_rtc.unixTime();
    g_model.clock.valid = t > 1700000000u;           // an unset RTC reads 2000-01-01: show "--:--" and NOT SYNCED
    if (!g_model.clock.valid) return;
    int y, mo, d, h, mi, s; hal::esp32::Rtc::fromUnix(t, y, mo, d, h, mi, s);
    g_model.clock.hh = h; g_model.clock.mm = mi; g_model.clock.day = d; g_model.clock.month = mo;
    g_model.clock.weekday = int(((t / 86400) + 4) % 7);   // 1970-01-01 was a Thursday
}

static void help() {
    Serial.println("v3poc: m menu/Key1 · b Key2 · f face · r ride · p Pause/Resume · d density · t text size · l language · c phone · s sensors · x refuse next · n no answer next · u perf");
}

static void perfReport() {
    lv_mem_monitor_t mm; lv_mem_monitor(&mm);
    Serial.printf("perf: frames %u, avg render %u us, max %u us, rebuilds %u · lv_mem used %u / %u, peak %u · heap free %u, min %u · psram %u / %u\n",
        g_frames, g_frames ? g_renderUs / g_frames : 0, g_renderMax, g_rebuilds, unsigned(mm.total_size - mm.free_size), unsigned(mm.total_size), unsigned(mm.max_used),
        ESP.getFreeHeap(), ESP.getMinFreeHeap(), ESP.getFreePsram(), ESP.getPsramSize());
    g_frames = g_renderUs = g_renderMax = g_rebuilds = 0;
}

static void serialCommand(char c, uint32_t now) {
    switch (c) {
        case 'm': g_model.key1(now); break;
        case 'b': g_model.key2(now); break;
        case 'f': g_model.home(); break;
        case 'r': if (!g_model.inWorkout()) g_model.startRide(now); break;
        case 'p': g_model.act(g_model.wk == WkState::Paused ? Action::Resume : Action::Pause, 0, now); break;
        case 'd': g_model.settings.density = g_model.settings.density == Density::Standard ? Density::Focused : Density::Standard; break;
        case 't': g_model.settings.text = g_model.settings.text == TextSize::Default ? TextSize::Large : TextSize::Default; break;
        case 'l': g_model.settings.lang = g_model.settings.lang == Lang::En ? Lang::Ar : Lang::En; break;
        case 'c': g_model.phoneLinked = !g_model.phoneLinked; break;
        case 's': {   // all → no power → heart rate only → none → all
            Sensors& s = g_model.sensors;
            if (s.power && s.hr && s.cadence) s.power = false; else if (!s.power && s.hr && s.cadence) s.cadence = false;
            else if (!s.power && s.hr && !s.cadence) s.hr = false; else s = Sensors{};
            break; }
        case 'x': g_model.nextReply = Reply::Refuse; break;
        case 'n': g_model.nextReply = Reply::NoAnswer; break;
        case 'u': perfReport(); break;
        case '?': help(); break;
        default: break;
    }
}

void setup() {
    Serial.begin(115200); delay(200);
    pinMode(pins::PWR_ON, OUTPUT); digitalWrite(pins::PWR_ON, HIGH);
    Wire.begin(pins::I2C_SDA, pins::I2C_SCL);
    g_power.begin(); g_keys.begin(); g_touch.begin();
    uint32_t t0 = millis();
    g_display.begin();
    g_ui.begin(lv_scr_act());
    readClock(); g_model.battery = g_power.batteryPct(); g_model.charging = g_power.charging();
    g_ui.render(g_model); lv_refr_now(nullptr);
    Serial.printf("Cyclift v3 proof of concept · simulated data · first frame after %u ms · heap %u · psram %u · flash %u MB\n",
        unsigned(millis() - t0), ESP.getFreeHeap(), ESP.getPsramSize(), unsigned(ESP.getFlashChipSize() / (1024 * 1024)));
    help();
}

void loop() {
    uint32_t now = millis();
    while (Serial.available()) serialCommand(char(Serial.read()), now);
    hal::TouchEvent t;
    while (g_touch.poll(t)) {
        switch (t.kind) {
            case hal::TouchEvent::Tap: g_ui.tap(g_model, t.x, t.y, now); break;
            case hal::TouchEvent::SwipeLeft: g_model.swipe(Swipe::Left); break;
            case hal::TouchEvent::SwipeRight: g_model.swipe(Swipe::Right); break;
            case hal::TouchEvent::SwipeUp: g_model.swipe(Swipe::Up); break;
            case hal::TouchEvent::SwipeDown: g_model.swipe(Swipe::Down); break;
            default: break;
        }
    }
    bool k1 = g_keys.key1(), k2 = g_keys.key2();      // act on press (falling edge); pins per board revision
    if (k1 && !g_k1) g_model.key1(now);
    if (k2 && !g_k2) g_model.key2(now);
    g_k1 = k1; g_k2 = k2;
    if (now - g_lastSlow >= 10000) { g_lastSlow = now; readClock(); g_model.battery = g_power.batteryPct(); g_model.charging = g_power.charging(); }
    g_model.tick(now);
    while (g_logShown < g_model.log.size()) Serial.printf("  %s\n", g_model.log[g_logShown++].c_str());
    if (g_model.log.size() >= 60) { g_model.log.clear(); g_logShown = 0; }
    if (now - g_lastLv >= 10) {
        g_lastLv = now;
        uint32_t r0 = micros();
        if (g_ui.render(g_model)) g_rebuilds++;
        lv_timer_handler();
        uint32_t dt = micros() - r0; g_renderUs += dt; g_renderMax = std::max(g_renderMax, dt); g_frames++;
    }
    if (now - g_lastPerf >= 30000) { g_lastPerf = now; perfReport(); }
    delay(2);
}
#endif
