// Cyclift Watch OS — firmware entry (Arduino framework, LILYGO T-Watch 2021).
// NOT FLASHED: the owner has not authorised flashing. Two builds share this file:
//   -DCYW_DIAG  → M1 diagnostics (read-only probes + display test pattern + touch / key echo), used to verify the board
//   default     → the application: HAL → AppModel (domain/app_model.hpp) → LVGL scene renderer
#ifndef CYW_HOST
#include <Arduino.h>
#include <Wire.h>
#include "../hal/board_pins.hpp"
#include "../hal/hal.hpp"
#include "../hal/esp32/drivers.hpp"
#include "../ui/lvgl_renderer.hpp"
#include "../domain/app_model.hpp"

using namespace cyw;

static hal::esp32::Display g_display; static hal::esp32::Touch g_touch; static hal::esp32::Keys g_keys; static hal::esp32::Haptics g_haptics;
static hal::esp32::Power g_power; static hal::esp32::Rtc g_rtc; static hal::esp32::Storage g_storage; static hal::esp32::Ble g_ble;
static app::AppModel g_app; static ui::LvglMeasurer g_measure; static ui::SceneRenderer g_renderer; static lv_obj_t* g_root = nullptr;
static uint32_t g_lastLvMs = 0, g_lastKeyMs = 0, g_lastRtcMs = 0, g_lastPersistMs = 0, g_frames = 0, g_renderUs = 0, g_lastPerfMs = 0;

// ---------------------------------------------------------------- persistence (LittleFS): face / appearance / event seq + pending events
static void persistLoad() {
    std::vector<uint8_t> b; app::Persist p;
    if (g_storage.read("/settings.bin", b) && b.size() >= 10) { p.face = b[0]; p.appearance = b[1]; p.eventSeq = uint32_t(b[2]) | uint32_t(b[3]) << 8 | uint32_t(b[4]) << 16 | uint32_t(b[5]) << 24; p.eventAcked = uint32_t(b[6]) | uint32_t(b[7]) << 8 | uint32_t(b[8]) << 16 | uint32_t(b[9]) << 24; }
    std::vector<WatchEvent> pending; std::vector<uint8_t> q;
    if (g_storage.read("/events.bin", q)) { size_t i = 0; while (i + 2 <= q.size()) { uint16_t n = uint16_t(q[i]) | uint16_t(q[i + 1]) << 8; i += 2; if (i + n > q.size()) break; std::vector<uint8_t> one(q.begin() + i, q.begin() + i + n); i += n; if (auto e = wire::decodeEvent(one)) pending.push_back(e->second); } }
    g_app.restore(p, pending);
}
static void persistSave() {
    auto& p = g_app.persist(); if (!p.dirty) return; p.dirty = false;
    std::vector<uint8_t> b{p.face, p.appearance}; for (int i = 0; i < 4; i++) b.push_back(uint8_t(p.eventSeq >> (8 * i))); for (int i = 0; i < 4; i++) b.push_back(uint8_t(p.eventAcked >> (8 * i)));
    g_storage.write("/settings.bin", b);
    std::vector<uint8_t> q; for (auto& e : g_app.events().pending()) { auto one = wire::encodeEvent(e, ""); q.push_back(uint8_t(one.size())); q.push_back(uint8_t(one.size() >> 8)); q.insert(q.end(), one.begin(), one.end()); }
    g_storage.write("/events.bin", q);
}

#ifdef CYW_DIAG
// ---------------------------------------------------------------- M1 diagnostics
static void probeI2c() {
    const struct { uint8_t addr; const char* name; } expect[] = {{pins::ADDR_TOUCH, "CST816S touch"}, {pins::ADDR_BMA423, "BMA423 accelerometer"}, {pins::ADDR_RTC, "PCF8563 RTC"}, {pins::ADDR_QMC5883L, "QMC5883L compass"}, {pins::ADDR_QMC5883P, "QMC5883P compass"}};
    for (auto& e : expect) { Wire.beginTransmission(e.addr); bool ok = Wire.endTransmission() == 0; Serial.printf("  0x%02X %-22s %s\n", e.addr, e.name, ok ? "FOUND" : "—"); }
}
void setup() {
    Serial.begin(115200); delay(300);
    pinMode(pins::PWR_ON, OUTPUT); digitalWrite(pins::PWR_ON, HIGH);
    Serial.println("Cyclift Watch OS — M1 diagnostics (nothing written to flash)");
    Serial.printf("  chip %s rev %d, %u MHz, flash %u MB, PSRAM %u KB, free heap %u\n", ESP.getChipModel(), ESP.getChipRevision(), ESP.getCpuFreqMHz(), ESP.getFlashChipSize() / (1024 * 1024), ESP.getPsramSize() / 1024, ESP.getFreeHeap());
    Wire.begin(pins::I2C_SDA, pins::I2C_SCL); probeI2c();
    g_power.begin(); Serial.printf("  battery %.2f V (uncalibrated) · %s\n", g_power.batteryVolts(), g_power.charging() ? "charging" : "not charging");
    g_keys.begin(); g_haptics.begin(); g_touch.begin();
    g_display.begin(); g_root = lv_scr_act();
    // test pattern: the six appearance backgrounds as rings + a centred label; confirms orientation, colour order and the round mask
    for (int i = 0; i < 6; i++) { lv_obj_t* o = lv_obj_create(g_root); lv_obj_remove_style_all(o); int r = 120 - i * 18; lv_obj_set_size(o, 2 * r, 2 * r); lv_obj_center(o); lv_obj_set_style_radius(o, LV_RADIUS_CIRCLE, 0); lv_obj_set_style_bg_opa(o, LV_OPA_COVER, 0); lv_obj_set_style_bg_color(o, ui::colorOf(ui::appearances()[i], "accent"), 0); }
    lv_obj_t* lb = lv_label_create(g_root); lv_label_set_text(lb, "CYCLIFT\nM1"); lv_obj_set_style_text_font(lb, &lv_font_montserrat_24, 0); lv_obj_set_style_text_color(lb, lv_color_white(), 0); lv_obj_set_style_text_align(lb, LV_TEXT_ALIGN_CENTER, 0); lv_obj_center(lb);
    g_haptics.pulse(60);
    Serial.printf("  RTC unix %u\n", g_rtc.unixTime());
}
void loop() {
    lv_timer_handler(); g_haptics.tick();
    hal::TouchEvent t; if (g_touch.poll(t)) Serial.printf("  touch kind %d at %d,%d\n", int(t.kind), t.x, t.y);
    static bool k1 = false, k2 = false, kb = false; bool a = g_keys.key1(), b = g_keys.key2(), c = g_keys.boot();
    if (a != k1) { k1 = a; Serial.printf("  KEY1 (IO%d) %s\n", pins::BTN_KEY1, a ? "down" : "up"); if (a) g_haptics.pulse(20); }
    if (b != k2) { k2 = b; Serial.printf("  KEY2 (IO%d) %s\n", pins::BTN_KEY2, b ? "down" : "up"); if (b) g_haptics.pulse(20); }
    if (c != kb) { kb = c; Serial.printf("  BOOT (IO0) %s\n", c ? "down" : "up"); }
    static uint32_t last = 0; if (millis() - last > 5000) { last = millis(); Serial.printf("  heap %u · psram free %u · battery %.2f V\n", ESP.getFreeHeap(), ESP.getFreePsram(), g_power.batteryVolts()); }
    delay(5);
}
#else
// ---------------------------------------------------------------- the application
void setup() {
    Serial.begin(115200); delay(200);
    pinMode(pins::PWR_ON, OUTPUT); digitalWrite(pins::PWR_ON, HIGH);
    Wire.begin(pins::I2C_SDA, pins::I2C_SCL);
    g_power.begin(); g_keys.begin(); g_haptics.begin(); g_touch.begin(); g_storage.begin();
    g_display.begin(); g_root = lv_scr_act();
    persistLoad();
    uint64_t mac = ESP.getEfuseMac(); char id[20]; snprintf(id, sizeof id, "cyw-%04X%08X", uint16_t(mac >> 32), uint32_t(mac)); g_app.setDeviceId(id);
    g_app.setRtc(g_rtc.unixTime()); g_app.setBattery(g_power.batteryPct(), g_power.charging(), true);
    g_ble.onReceive([](const std::vector<uint8_t>& bytes) { if (auto f = decode(bytes)) g_app.onFrame(*f, millis()); });
    g_ble.start("Cyclift Watch");
    Serial.printf("Cyclift Watch OS · %s · heap %u · psram %u\n", id, ESP.getFreeHeap(), ESP.getPsramSize());
}
void loop() {
    uint32_t now = millis();
    // inputs
    bool linked; if (g_ble.takeLinkChange(linked)) g_app.onConnected(linked, now);
    hal::TouchEvent t; while (g_touch.poll(t)) g_app.onTouch(t, now);
    if (now - g_lastKeyMs >= 5) { g_lastKeyMs = now; g_app.onKey(Key::Key1, g_keys.key1(), now); g_app.onKey(Key::Key2, g_keys.key2(), now); g_app.onKey(Key::Boot, g_keys.boot(), now); }
    if (now - g_lastRtcMs >= 10000) { g_lastRtcMs = now; g_app.setRtc(g_rtc.unixTime()); g_app.setBattery(g_power.batteryPct(), g_power.charging(), true); }
    g_app.tick(now);
    // outputs
    for (auto& f : g_app.takeOutbox()) g_ble.send(encode(f));
    if (uint16_t h = g_app.takeHaptic()) g_haptics.pulse(h);
    g_haptics.tick();
    if (g_app.takeDirty()) {
        uint32_t t0 = micros();
        if (!g_app.screenIsOn()) { lv_obj_clean(g_root); g_display.setBrightness(0); }
        else { g_display.setBrightness(60); g_renderer.render(g_root, g_app.render(g_measure, now), g_app.appearance()); }
        g_renderUs += micros() - t0; g_frames++;
    }
    if (now - g_lastPersistMs > 2000) { g_lastPersistMs = now; persistSave(); }
    if (now - g_lastPerfMs > 30000) { g_lastPerfMs = now; Serial.printf("perf: %u frames, avg render %u us, heap %u, psram free %u\n", g_frames, g_frames ? g_renderUs / g_frames : 0, ESP.getFreeHeap(), ESP.getFreePsram()); g_frames = 0; g_renderUs = 0; }
    if (now - g_lastLvMs >= 10) { g_lastLvMs = now; lv_timer_handler(); }
    delay(2);
}
#endif
#endif
