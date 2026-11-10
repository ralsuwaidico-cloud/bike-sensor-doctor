// Cyclift Watch v3 — Stage 1 proof-of-concept firmware entry (PlatformIO env T-Watch-2021-*-v3poc only).
// A separate program from the existing application (app/main.cpp is not part of this build): approved v3 screens with
// SIMULATED ride data and a SIMULATED iPhone. No Bluetooth is started, nothing is sent to the iPhone, nothing is written to
// flash storage. NOT FLASHED: loading it onto the watch is Stage 2 and needs the owner's approval.
//
// Serial console (115200 baud) for the Stage 2 test procedure — one character per command:
//   m menu (Key 1)   b Key 2   f face   r start ride   p tap Pause/Resume   d density   t text size   l language
//   c phone link     s cycle sensors   x next reply: refuse   n next reply: no answer   u perf report   ? help
// Stage 1.2 diagnostics: M memory + stack report · R read the clock · T<seconds>⏎ set the clock (temporary PC test command,
// local time as seconds since 1970; the approved time source remains the iPhone over Bluetooth, Stage 4).
#if defined(CYW_V3POC) && !defined(CYW_HOST)
#include <Arduino.h>
#include <Wire.h>
#include <algorithm>
#include <numeric>
#include <cstring>
#include "../hal/board_pins.hpp"
#include "../hal/esp32/drivers.hpp"
#include "../hal/rtc_time.hpp"
#include "../ui/v3/cyv3_ui.hpp"
#include <esp_heap_caps.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
extern "C" { extern int _iram_start, _iram_end, _data_start, _bss_end; }   // ESP-IDF linker symbols (sections.ld)

using namespace cyw;
using namespace cyw::v3;

static hal::esp32::Display g_display; static hal::esp32::Touch g_touch; static hal::esp32::Keys g_keys;
static hal::esp32::Power g_power; static hal::esp32::Rtc g_rtc;
static Model g_model; static Ui g_ui;
static uint32_t g_lastMemSample = 0;
static uint32_t g_lastLv = 0, g_lastSlow = 0, g_lastPerf = 0, g_renderUs = 0, g_renderMax = 0, g_frames = 0, g_rebuilds = 0;
static bool g_k1 = false, g_k2 = false;
static size_t g_logShown = 0;

// ---------------------------------------------------------------- frame-time instrumentation (Stage 1.1, 9 Nov 2026)
// One loop pass = one frame. Phases: input (serial, touch, keys), model (tick), ui (rebuild or in-place update),
// lv (LVGL timer: drawing + SPI flush), of which flush (SPI to the panel) is measured inside the display driver.
// "work" frames are those that rebuilt the screen or sent pixels; their totals go into a ring buffer for percentiles
// and into a histogram. Read with 'u' (report + reset) and 'h' (histogram + percentiles by frame kind).
// Stage 1.2: ring 512 → 128 samples (percentiles over the last 128 work frames; the histogram and the per-kind maxima still
// cover every frame since 'z'). Saves 11,904 B of internal RAM (14,456 → 2,552 B incl. the sort buffer).
namespace perf {
constexpr int RING = 128;
constexpr uint32_t EDGES_US[] = {1000, 2000, 5000, 10000, 20000, 50000, 100000, 200000, 400000};
constexpr int NB = sizeof(EDGES_US) / sizeof(EDGES_US[0]) + 1;
struct Sample { uint32_t us; uint32_t uiUs, lvUs, flushUs, px; uint8_t kind; };   // kind: 1 update, 2 rebuild
Sample ring[RING]; int n = 0, head = 0;
uint32_t hist[3][NB];                 // [idle, update, rebuild]
uint32_t maxIn = 0, maxModel = 0, idleMax = 0;
uint32_t allMax[3];                   // exact maxima over all frames since 'z' (not limited to the ring)
void add(uint8_t kind, uint32_t us, uint32_t uiUs, uint32_t lvUs, uint32_t flushUs, uint32_t px) {
    int b = 0; while (b < NB - 1 && us >= EDGES_US[b]) b++;
    hist[kind][b]++;
    allMax[kind] = std::max(allMax[kind], us);
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
    Serial.printf("frames since reset: update %u (max %.1f ms) · rebuild %u (max %.1f ms)\n", unsigned(std::accumulate(hist[1], hist[1] + NB, 0u)),
        allMax[1] / 1000.f, unsigned(std::accumulate(hist[2], hist[2] + NB, 0u)), allMax[2] / 1000.f);
    Serial.printf("frames idle max %.1f ms · input max %.1f ms · model max %.1f ms\n", idleMax / 1000.f, maxIn / 1000.f, maxModel / 1000.f);
}
void reset() { n = head = 0; std::memset(hist, 0, sizeof hist); std::memset(allMax, 0, sizeof allMax); maxIn = maxModel = idleMax = 0; }
}  // namespace perf

// ---------------------------------------------------------------- memory diagnostics (Stage 1.2, 10 Nov 2026)
// ESP.getFreeHeap() counts MALLOC_CAP_INTERNAL, which on the ESP32 includes unused IRAM that only 32-bit/executable
// allocations can use. 'M' therefore reports byte-addressable internal heap (what malloc/new, LVGL, strings and Bluetooth
// use) separately. LVGL's own "max_used" counts requested sizes but subtracts real block sizes on free, so it under-reads;
// the LVGL pool peak here is sampled (total − free) after every screen rebuild and once per second.
namespace mem {
uint32_t lvPeak = 0, lvMinBiggest = UINT32_MAX;
void sampleLv() {
    lv_mem_monitor_t m; lv_mem_monitor(&m);
    lvPeak = std::max<uint32_t>(lvPeak, m.total_size - m.free_size);
    lvMinBiggest = std::min<uint32_t>(lvMinBiggest, m.free_biggest_size);
}
void stackLine(const char* name, TaskHandle_t h, uint32_t size) {
    if (!h) { Serial.printf("  stack %-10s not found\n", name); return; }
    uint32_t hw = uxTaskGetStackHighWaterMark(h);   // ESP-IDF: bytes never used since the task started
    if (size) Serial.printf("  stack %-10s unused %5u B (of %u B)\n", name, unsigned(hw), unsigned(size));
    else Serial.printf("  stack %-10s unused %5u B\n", name, unsigned(hw));
}
void report() {
    const uint32_t I8 = MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT;
    uint32_t inAll = heap_caps_get_free_size(MALLOC_CAP_INTERNAL), in8 = heap_caps_get_free_size(I8);
    uint32_t iramUsed = uint32_t(reinterpret_cast<uintptr_t>(&_iram_end) - reinterpret_cast<uintptr_t>(&_iram_start));
    Serial.printf("mem: internal 8-bit heap free %u, min %u, largest block %u · DMA largest %u\n", unsigned(in8),
        unsigned(heap_caps_get_minimum_free_size(I8)), unsigned(heap_caps_get_largest_free_block(I8)),
        unsigned(heap_caps_get_largest_free_block(MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL)));
    Serial.printf("mem: getFreeHeap-style total %u (min %u) = 8-bit %u + IRAM-only %u\n", unsigned(inAll),
        unsigned(heap_caps_get_minimum_free_size(MALLOC_CAP_INTERNAL)), unsigned(in8), unsigned(inAll - in8));
    Serial.printf("mem: psram free %u of %u, largest block %u, min %u\n", unsigned(heap_caps_get_free_size(MALLOC_CAP_SPIRAM)),
        unsigned(heap_caps_get_total_size(MALLOC_CAP_SPIRAM)), unsigned(heap_caps_get_largest_free_block(MALLOC_CAP_SPIRAM)),
        unsigned(heap_caps_get_minimum_free_size(MALLOC_CAP_SPIRAM)));
    Serial.printf("mem: iram code %u of 131072 B (%u free) · static dram %u B\n", unsigned(iramUsed), unsigned(131072u - iramUsed),
        unsigned(reinterpret_cast<uintptr_t>(&_bss_end) - reinterpret_cast<uintptr_t>(&_data_start)));
    lv_mem_monitor_t m; lv_mem_monitor(&m); sampleLv();
    Serial.printf("mem: lvgl pool used %u of %u, peak %u (sampled), largest free %u (min %u), frag %u%%\n", unsigned(m.total_size - m.free_size),
        unsigned(m.total_size), unsigned(lvPeak), unsigned(m.free_biggest_size), unsigned(lvMinBiggest), unsigned(m.frag_pct));
    stackLine("loopTask", xTaskGetCurrentTaskHandle(), getArduinoLoopTaskStackSize());
    for (const char* t : {"IDLE0", "IDLE1", "esp_timer", "ipc0", "ipc1", "Tmr Svc"}) stackLine(t, xTaskGetHandle(t), 0);
}
}  // namespace mem

static cyw::rtc::TimeCommand g_timeCmd;

static void readClock() {
    cyw::rtc::Reading r;
    // Stage 1.2: valid only if the chip answered, kept time since it was last set (VL clear) and the date is 2024 or later;
    // otherwise the face shows "--:--" and NOT SYNCED. Without a battery the clock loses its time whenever USB is unplugged.
    g_model.clock.valid = g_rtc.read(r) && r.integrity;
    if (!g_model.clock.valid) return;
    int y, mo, d, h, mi, s; cyw::rtc::fromUnix(r.t, y, mo, d, h, mi, s);
    g_model.clock.hh = h; g_model.clock.mm = mi; g_model.clock.day = d; g_model.clock.month = mo;
    g_model.clock.weekday = cyw::rtc::weekday(r.t);
}

static void printClock(const char* what) {
    cyw::rtc::Reading r; bool ok = g_rtc.read(r);
    int y, mo, d, h, mi, s; cyw::rtc::fromUnix(r.t, y, mo, d, h, mi, s);
    if (!ok) Serial.printf("%s: clock chip did not answer\n", what);
    else if (!r.integrity) Serial.printf("%s: no valid time (not set since power loss) — face shows --:--\n", what);
    else Serial.printf("%s: %04d-%02d-%02d %02d:%02d:%02d local\n", what, y, mo, d, h, mi, s);
}

static void help() {
    Serial.println("v3poc: m menu/Key1 · b Key2 · f face · r ride · p Pause/Resume · d density · t text size · l language · c phone · s sensors · x refuse next · n no answer next · u perf · h frame-time histogram · z reset histogram · M memory+stacks · R clock · T<seconds> set clock (test)");
}

static void perfReport() {
    lv_mem_monitor_t mm; lv_mem_monitor(&mm); mem::sampleLv();
    // "heap free/min" keep the Stage 1/1.1 meaning (getFreeHeap, includes IRAM-only memory) so logs stay comparable; see 'M'.
    Serial.printf("perf: frames %u, avg render %u us, max %u us, rebuilds %u · lv_mem used %u / %u, peak %u (sampled) · heap free %u, min %u · psram %u / %u\n",
        g_frames, g_frames ? g_renderUs / g_frames : 0, g_renderMax, g_rebuilds, unsigned(mm.total_size - mm.free_size), unsigned(mm.total_size), unsigned(mem::lvPeak),
        ESP.getFreeHeap(), ESP.getMinFreeHeap(), ESP.getFreePsram(), ESP.getPsramSize());
    g_frames = g_renderUs = g_renderMax = g_rebuilds = 0;
}

static void serialCommand(char c, uint32_t now) {
    switch (g_timeCmd.feed(c)) {
        case cyw::rtc::TimeCommand::Busy: return;
        case cyw::rtc::TimeCommand::Error: Serial.println("time: not set — send T followed by local time in seconds since 1970 (2024-2099) and Enter"); return;
        case cyw::rtc::TimeCommand::Done:
            if (g_rtc.write(uint32_t(g_timeCmd.value))) { readClock(); printClock("time set from PC (temporary test command)"); }
            else Serial.println("time: clock chip did not acknowledge — not set");
            return;
        case cyw::rtc::TimeCommand::Idle: break;
    }
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
        case 'M': mem::report(); break;
        case 'R': printClock("clock"); break;
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
    Serial.printf("Cyclift v3 proof of concept · Stage 1.2 (diagnostics; IRAM rendering off) · simulated data · first frame after %u ms · heap %u · psram %u · flash %u MB\n",
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
        if (rb) { g_rebuilds++; mem::sampleLv(); }
        uint32_t r1 = micros();
        lv_timer_handler();
        uint32_t r2 = micros();
        uint32_t dt = r2 - r0; g_renderUs += dt; g_renderMax = std::max(g_renderMax, dt); g_frames++;
        uint32_t px = g_display.flushPx - px0;
        perf::add(rb ? 2 : px ? 1 : 0, (r2 - f0), r1 - r0, r2 - r1, g_display.flushUs - fl0, px);
    }
    if (now - g_lastPerf >= 30000) { g_lastPerf = now; perfReport(); }
    if (now - g_lastMemSample >= 1000) { g_lastMemSample = now; mem::sampleLv(); }
    delay(2);
}
#endif
