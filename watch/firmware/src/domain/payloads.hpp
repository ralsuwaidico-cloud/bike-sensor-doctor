#pragma once
// Cyclift Watch OS — binary payload codecs for the frames in sync.hpp (protocol v1, docs/BLE_PROTOCOL.md).
// Little-endian fixed fields; every optional value has an explicit "absent" encoding (0xFFFF / 0x7FFFFFFF) so a missing
// sensor is transmitted as missing, never as zero. Pure C++, host-tested; the iPhone companion mirrors these layouts.
#include <cstdint>
#include <string>
#include <vector>
#include <optional>
#include "sync.hpp"

namespace cyw::wire {

inline void put8(std::vector<uint8_t>& b, uint8_t v) { b.push_back(v); }
inline void put16(std::vector<uint8_t>& b, uint16_t v) { b.push_back(uint8_t(v)); b.push_back(uint8_t(v >> 8)); }
inline void put32(std::vector<uint8_t>& b, uint32_t v) { for (int i = 0; i < 4; i++) b.push_back(uint8_t(v >> (8 * i))); }
inline void puti32(std::vector<uint8_t>& b, int32_t v) { put32(b, uint32_t(v)); }
inline void putStr(std::vector<uint8_t>& b, const std::string& s) { size_t n = std::min<size_t>(s.size(), 255); put8(b, uint8_t(n)); b.insert(b.end(), s.begin(), s.begin() + n); }
struct Reader {
    const std::vector<uint8_t>& b; size_t i = 0; bool ok = true;
    explicit Reader(const std::vector<uint8_t>& v) : b(v) {}
    uint8_t u8() { if (i + 1 > b.size()) { ok = false; return 0; } return b[i++]; }
    uint16_t u16() { if (i + 2 > b.size()) { ok = false; return 0; } uint16_t v = uint16_t(b[i]) | (uint16_t(b[i + 1]) << 8); i += 2; return v; }
    uint32_t u32() { if (i + 4 > b.size()) { ok = false; return 0; } uint32_t v = 0; for (int k = 0; k < 4; k++) v |= uint32_t(b[i + k]) << (8 * k); i += 4; return v; }
    int32_t i32() { return int32_t(u32()); }
    std::string str() { uint8_t n = u8(); if (i + n > b.size()) { ok = false; return ""; } std::string s(b.begin() + i, b.begin() + i + n); i += n; return s; }
};
constexpr uint16_t ABSENT16 = 0xFFFF; constexpr int32_t ABSENT32 = 0x7FFFFFFF;

/// 0x20 Live: phone → watch sensor mirror. Values ×1 (W, bpm, rpm) and speed ×10 km/h; age in ms since the sample.
struct Live {
    std::optional<uint16_t> powerW, hrBpm, cadenceRpm, speedKmh10;
    uint16_t powerAgeMs = ABSENT16, hrAgeMs = ABSENT16, cadenceAgeMs = ABSENT16, speedAgeMs = ABSENT16;
    bool ftpKnown = false; uint16_t ftpW = 0;
    std::optional<std::pair<uint16_t, uint16_t>> powerBandW, hrBandBpm, cadenceRange;
    std::string stepName; uint16_t stepRemainingS = 0, stepTotalS = 0;
    bool recording = false, paused = false; uint32_t elapsedS = 0, distanceM = 0;
    std::vector<uint8_t> encode() const {
        std::vector<uint8_t> b; auto opt = [&](std::optional<uint16_t> v) { put16(b, v.value_or(ABSENT16)); };
        opt(powerW); put16(b, powerAgeMs); opt(hrBpm); put16(b, hrAgeMs); opt(cadenceRpm); put16(b, cadenceAgeMs); opt(speedKmh10); put16(b, speedAgeMs);
        put8(b, ftpKnown); put16(b, ftpW);
        auto band = [&](const std::optional<std::pair<uint16_t, uint16_t>>& p) { put16(b, p ? p->first : ABSENT16); put16(b, p ? p->second : ABSENT16); };
        band(powerBandW); band(hrBandBpm); band(cadenceRange);
        putStr(b, stepName); put16(b, stepRemainingS); put16(b, stepTotalS);
        put8(b, uint8_t(recording) | uint8_t(paused) << 1); put32(b, elapsedS); put32(b, distanceM); return b;
    }
    static std::optional<Live> decode(const std::vector<uint8_t>& p) {
        Reader r(p); Live l; auto opt = [&]() -> std::optional<uint16_t> { uint16_t v = r.u16(); return v == ABSENT16 ? std::nullopt : std::optional<uint16_t>(v); };
        l.powerW = opt(); l.powerAgeMs = r.u16(); l.hrBpm = opt(); l.hrAgeMs = r.u16(); l.cadenceRpm = opt(); l.cadenceAgeMs = r.u16(); l.speedKmh10 = opt(); l.speedAgeMs = r.u16();
        l.ftpKnown = r.u8(); l.ftpW = r.u16();
        auto band = [&]() -> std::optional<std::pair<uint16_t, uint16_t>> { uint16_t a = r.u16(), c = r.u16(); if (a == ABSENT16 || c == ABSENT16) return std::nullopt; return std::make_pair(a, c); };
        l.powerBandW = band(); l.hrBandBpm = band(); l.cadenceRange = band();
        l.stepName = r.str(); l.stepRemainingS = r.u16(); l.stepTotalS = r.u16();
        uint8_t f = r.u8(); l.recording = f & 1; l.paused = f & 2; l.elapsedS = r.u32(); l.distanceM = r.u32();
        if (!r.ok) return std::nullopt; return l;
    }
};

/// 0x21 Gps: one timestamped fix (lat/lon ×1e7, speed ×10 km/h, heading degrees, phone unix seconds, fix age ms).
struct Gps {
    int32_t latE7 = 0, lonE7 = 0; uint16_t speedKmh10 = 0, headingDeg = 0; uint32_t phoneUnixS = 0; uint16_t ageMs = 0;
    std::vector<uint8_t> encode() const { std::vector<uint8_t> b; puti32(b, latE7); puti32(b, lonE7); put16(b, speedKmh10); put16(b, headingDeg); put32(b, phoneUnixS); put16(b, ageMs); return b; }
    static std::optional<Gps> decode(const std::vector<uint8_t>& p) { Reader r(p); Gps g; g.latE7 = r.i32(); g.lonE7 = r.i32(); g.speedKmh10 = r.u16(); g.headingDeg = r.u16(); g.phoneUnixS = r.u32(); g.ageMs = r.u16(); if (!r.ok || std::abs(g.latE7) > 900000000 || std::abs(g.lonE7) > 1800000000) return std::nullopt; return g; }
};

/// 0x02 TimeSync: phone unix seconds + ms + tz offset minutes.
struct TimeSync {
    uint32_t unixS = 0; uint16_t ms = 0; int16_t tzOffsetMin = 0;
    std::vector<uint8_t> encode() const { std::vector<uint8_t> b; put32(b, unixS); put16(b, ms); put16(b, uint16_t(tzOffsetMin)); return b; }
    static std::optional<TimeSync> decode(const std::vector<uint8_t>& p) { Reader r(p); TimeSync t; t.unixS = r.u32(); t.ms = r.u16(); t.tzOffsetMin = int16_t(r.u16()); if (!r.ok) return std::nullopt; return t; }
};

/// 0x03 Status: watch → phone.
struct Status {
    uint8_t batteryPct = 0; bool charging = false; uint32_t freeHeap = 0; uint8_t phase = 0; uint32_t pendingEvents = 0;
    std::vector<uint8_t> encode() const { std::vector<uint8_t> b; put8(b, batteryPct); put8(b, charging); put32(b, freeHeap); put8(b, phase); put32(b, pendingEvents); return b; }
};

/// 0x22 Coach: id, priority, context, flags, expiry seconds, instruction, reason, target.
struct Coach {
    uint32_t id = 0; uint8_t priority = 0, context = 0; bool requiresAction = false, safety = false; uint16_t expiresInS = 0; std::string instruction, reason, target;
    std::vector<uint8_t> encode() const { std::vector<uint8_t> b; put32(b, id); put8(b, priority); put8(b, context); put8(b, uint8_t(requiresAction) | uint8_t(safety) << 1); put16(b, expiresInS); putStr(b, instruction); putStr(b, reason); putStr(b, target); return b; }
    static std::optional<Coach> decode(const std::vector<uint8_t>& p) { Reader r(p); Coach c; c.id = r.u32(); c.priority = r.u8(); c.context = r.u8(); uint8_t f = r.u8(); c.requiresAction = f & 1; c.safety = f & 2; c.expiresInS = r.u16(); c.instruction = r.str(); c.reason = r.str(); c.target = r.str(); if (!r.ok) return std::nullopt; return c; }
};

/// 0x10 PlanToday: kind (1 ride, 2 strength, 0 none), title, start hh:mm, duration min, and for strength the exercises.
struct PlanToday {
    struct Exercise { std::string id, name; uint8_t sets = 3, reps = 8; uint16_t weightKg10 = 0; uint16_t restS = 90; char superset = 0; };
    uint8_t kind = 0; std::string workoutId, title; uint16_t startMin = 0, durationMin = 0; std::vector<Exercise> exercises;
    std::vector<uint8_t> encode() const { std::vector<uint8_t> b; put8(b, kind); putStr(b, workoutId); putStr(b, title); put16(b, startMin); put16(b, durationMin); put8(b, uint8_t(exercises.size())); for (auto& e : exercises) { putStr(b, e.id); putStr(b, e.name); put8(b, e.sets); put8(b, e.reps); put16(b, e.weightKg10); put16(b, e.restS); put8(b, uint8_t(e.superset)); } return b; }
    static std::optional<PlanToday> decode(const std::vector<uint8_t>& p) { Reader r(p); PlanToday t; t.kind = r.u8(); t.workoutId = r.str(); t.title = r.str(); t.startMin = r.u16(); t.durationMin = r.u16(); uint8_t n = r.u8(); for (uint8_t i = 0; i < n && r.ok; i++) { Exercise e; e.id = r.str(); e.name = r.str(); e.sets = r.u8(); e.reps = r.u8(); e.weightKg10 = r.u16(); e.restS = r.u16(); e.superset = char(r.u8()); t.exercises.push_back(e); } if (!r.ok) return std::nullopt; return t; }
};

/// 0x11 Cached: recovery summaries with source + timestamp; absent values are absent.
struct Cached {
    std::optional<uint16_t> sleepMin; std::string sleepSource; uint32_t sleepUnixS = 0;
    std::optional<uint16_t> hrvMs; uint32_t hrvUnixS = 0; std::optional<uint8_t> recoveryPct; std::string recoveryWord; std::string insight; uint8_t loadPct = 0;
    std::vector<uint8_t> encode() const { std::vector<uint8_t> b; put16(b, sleepMin.value_or(ABSENT16)); putStr(b, sleepSource); put32(b, sleepUnixS); put16(b, hrvMs.value_or(ABSENT16)); put32(b, hrvUnixS); put8(b, recoveryPct.value_or(255)); putStr(b, recoveryWord); putStr(b, insight); put8(b, loadPct); return b; }
    static std::optional<Cached> decode(const std::vector<uint8_t>& p) { Reader r(p); Cached c; uint16_t s = r.u16(); if (s != ABSENT16) c.sleepMin = s; c.sleepSource = r.str(); c.sleepUnixS = r.u32(); uint16_t h = r.u16(); if (h != ABSENT16) c.hrvMs = h; c.hrvUnixS = r.u32(); uint8_t rp = r.u8(); if (rp != 255) c.recoveryPct = rp; c.recoveryWord = r.str(); c.insight = r.str(); c.loadPct = r.u8(); if (!r.ok) return std::nullopt; return c; }
};

/// 0x30 Event: WatchEvent on the wire.
inline std::vector<uint8_t> encodeEvent(const WatchEvent& e, const std::string& deviceId) { std::vector<uint8_t> b; putStr(b, deviceId); put32(b, e.seq); put32(b, e.watchUnixS); put8(b, e.kind); putStr(b, e.workoutId); puti32(b, e.a); puti32(b, e.b); puti32(b, e.c); put8(b, e.manual); return b; }
inline std::optional<std::pair<std::string, WatchEvent>> decodeEvent(const std::vector<uint8_t>& p) { Reader r(p); std::string dev = r.str(); WatchEvent e; e.seq = r.u32(); e.watchUnixS = r.u32(); e.kind = r.u8(); e.workoutId = r.str(); e.a = r.i32(); e.b = r.i32(); e.c = r.i32(); e.manual = r.u8(); if (!r.ok) return std::nullopt; return std::make_pair(dev, e); }
/// 0x31 Ack: cumulative seq.
inline std::vector<uint8_t> encodeAck(uint32_t upTo) { std::vector<uint8_t> b; put32(b, upTo); return b; }
inline std::optional<uint32_t> decodeAck(const std::vector<uint8_t>& p) { Reader r(p); uint32_t v = r.u32(); if (!r.ok) return std::nullopt; return v; }

} // namespace cyw::wire
