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
#include <algorithm>
#include <cstring>
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

// ---------------------------------------------------------------- frame-time instrumentation (Stage 1.1, 9 Nov 2026)
// One loop pass = one frame. Phases: input (serial, touch, keys), model (tick), ui (rebuild or in-place update),
// lv (LVGL timer: drawing + SPI flush), of which flush (SPI to the panel) is measured inside the display driver.
// "work" frames are those that rebuilt the screen or sent pixels; their totals go into a ring buffer for percentiles
// and into a histogram. Read with 'u' (report + reset) and 'h' (histogram + percentiles by frame kind).
namespace perf {
constexpr int RING = 512;
constexpr uint32_t EDGES_US[] = {1000, 2000, 5000, 10000, 20000, 50000, 100000, 200000, 400000};
constexpr int NB = sizeof(EDGES_US) / sizeof(EDGES_US[0]) + 1;
struct Sample { uint32_t us; uint32_t uiUs, lvUs, flushUs, px; uint8_t kind; };   // kind: 1 update, 2 rebuild
Sample ring[RING]; int n = 0, head = 0;
uint32_t hist[3][NB];                 // [idle, update, rebuild]
uint32_t maxIn = 0, maxModel = 0, idleMax = 0;
void add(uint8_t kind, uint32_t us, uint32_t uiUs, uint32_t lvUs, uint32_t flushUs, uint32_t px) {
    int b = 0; while (b < NB - 1 && us >= EDGES_US[b]) b++;
    hist[kind][b]++;
    if (kind == 0) { idleMax = std::max(idleMax, us); return; }
    ring[head] = {us, uiUs, lvUs, flushUs, px, kind}; head = (head + 1) % RING; n = std::min(n + 1, RING);
}
uint32_t pct(uint8_t kind, int p, uint32_t Sample::*field) {
    static uint32_t v[RING]; int k = 0;
    for (int i = 0; i < n; i++) if (!kind || ring[i].kind == kind) v[k++] = ring[i].*field;
    if (!k) return 0;
    std::sort(v, v + k);
    return v[std::min(k - 1, (k * p + 99) / 100 - 1 < 0 ? 0 : (k * p + 99) / 100 - 1)];
}
int count(uint8_t kind) { int k = 0; for (int i = 0; i < n; i++) k += !kind || ring[i].kind == kind; return k; }
void print() {
    static const char* names[3] = {"idle", "update", "rebuild"};
    Serial.printf("hist (frame ms):  <1  1-2  2-5  5-10  10-20  20-50  50-100  100-200  200-400  >=400\n");
    for (int k = 0; k < 3; k++) {
        Serial.printf("hist %-8s", names[k]);
        for (int b = 0; b < NB; b++) Serial.printf(" %u", unsigned(hist[k][b]));
        Serial.printf("\n");
    }
    for (uint8_t k : {uint8_t(1), uint8_t(2)}) {
        if (!count(k)) continue;
        Serial.printf("frames %s (last %d): total ms p50 %.1f p95 %.1f p99 %.1f max %.1f · ui max %.1f · draw+flush max %.1f · flush max %.1f · px max %u\n",
            names[k], count(k), pct(k, 50, &Sample::us) / 1000.f, pct(k, 95, &Sample::us) / 1000.f, pct(k, 99, &Sample::us) / 1000.f,
            pct(k, 100, &Sample::us) / 1000.f, pct(k, 100, &Sample::uiUs) / 1000.f, pct(k, 100, &Sample::lvUs) / 1000.f,
            pct(k, 100, &Sample::flushUs) / 1000.f, unsigned(pct(k, 100, &Sample::px)));
    }
    Serial.printf("frames idle max %.1f ms · input max %.1f ms · model max %.1f ms\n", idleMax / 1000.f, maxIn / 1000.f, maxModel / 1000.f);
}
void reset() { n = head = 0; std::memset(hist, 0, sizeof hist); maxIn = maxModel = idleMax = 0; }
}  // namespace perf

static void readClock() {
    uint32_t t = g_rtc.unixTime();
    g_model.clock.valid = t > 1700000000u;           // an unset RTC reads 2000-01-01: show "--:--" and NOT SYNCED
    if (!g_model.clock.valid) return;
    int y, mo, d, h, mi, s; hal::esp32::Rtc::fromUnix(t, y, mo, d, h, mi, s);
    g_model.clock.hh = h; g_model.clock.mm = mi; g_model.clock.day = d; g_model.clock.month = mo;
    g_model.clock.weekday = int(((t / 86400) + 4) % 7);   // 1970-01-01 was a Thursday
}

static void help() {
    Serial.println("v3poc: m menu/Key1 · b Key2 · f face · r ride · p Pause/Resume · d density · t text size · l language · c phone · s sensors · x refuse next · n no answer next · u perf · h frame-time histogram · z reset histogram");
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
        case 'h': perf::print(); break;
        case 'z': perf::reset(); Serial.println("perf: histogram reset"); break;
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
    Serial.printf("Cyclift v3 proof of concept · Stage 1.1 (rendering optimisation) · simulated data · first frame after %u ms · heap %u · psram %u · flash %u MB\n",
        unsigned(millis() - t0), ESP.getFreeHeap(), ESP.getPsramSize(), unsigned(ESP.getFlashChipSize() / (1024 * 1024)));
    help();
}

void loop() {
    uint32_t now = millis();
    uint32_t f0 = micros();
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
    uint32_t f1 = micros();
    g_model.tick(now);
    uint32_t f2 = micros();
    perf::maxIn = std::max(perf::maxIn, f1 - f0); perf::maxModel = std::max(perf::maxModel, f2 - f1);
    while (g_logShown < g_model.log.size()) Serial.printf("  %s\n", g_model.log[g_logShown++].c_str());
    if (g_model.log.size() >= 60) { g_model.log.clear(); g_logShown = 0; }
    if (now - g_lastLv >= 10) {
        g_lastLv = now;
        uint32_t r0 = micros(), fl0 = g_display.flushUs, px0 = g_display.flushPx;
        bool rb = g_ui.render(g_model);
        if (rb) g_rebuilds++;
        uint32_t r1 = micros();
        lv_timer_handler();
        uint32_t r2 = micros();
        uint32_t dt = r2 - r0; g_renderUs += dt; g_renderMax = std::max(g_renderMax, dt); g_frames++;
        uint32_t px = g_display.flushPx - px0;
        perf::add(rb ? 2 : px ? 1 : 0, (r2 - f0), r1 - r0, r2 - r1, g_display.flushUs - fl0, px);
    }
    if (now - g_lastPerf >= 30000) { g_lastPerf = now; perfReport(); }
    delay(2);
}
#endif
