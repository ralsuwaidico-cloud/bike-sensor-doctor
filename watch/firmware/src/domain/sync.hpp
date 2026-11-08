#pragma once
// Cyclift Watch OS — versioned BLE protocol frames and the offline event queue (owner directive §12).
//
// Ownership (§12 "clear ownership of records"): the iPhone coordinates and owns the saved workout; the watch owns the
// EVENTS it generates (set logged, rep confirmed, lap, pause/resume/end) until they are acknowledged. Every event has a
// stable id (deviceId, sequence) and a watch timestamp, so re-sending after a reconnect can never duplicate anything:
// the phone treats (deviceId, seq) as idempotent. Nothing here depends on hardware.
#include <cstdint>
#include <vector>
#include <deque>
#include <string>
#include <optional>
#include <map>

namespace cyw {

constexpr uint8_t PROTOCOL_VERSION = 1;

enum class MsgType : uint8_t {
    Hello = 0x01,          // device identity + capabilities + protocol version (both directions)
    TimeSync = 0x02,       // phone → watch: unix seconds + ms, tz offset; watch replies with its RTC before/after
    Status = 0x03,         // watch → phone: battery %, charging, free heap, activity phase
    PlanToday = 0x10,      // phone → watch: today's workout (id, kind, steps/exercises, targets) — cached on the watch
    Cached = 0x11,         // phone → watch: sleep / recovery / HRV summaries with their source and timestamp
    Live = 0x20,           // phone → watch: live sensor values (power, HR, cadence, speed) with age
    Gps = 0x21,            // phone → watch: timestamped position, speed, heading, distance (mirror, never invented)
    Coach = 0x22,          // phone → watch: coaching message (see coach.hpp)
    Event = 0x30,          // watch → phone: activity / set / rep / lap event with (deviceId, seq, ts)
    Ack = 0x31,            // phone → watch: acknowledges seq numbers up to N (cumulative) + explicit list
    Error = 0x7F
};

struct Frame {
    uint8_t version = PROTOCOL_VERSION;
    MsgType type = MsgType::Error;
    uint16_t seq = 0;              // per-direction sequence
    std::vector<uint8_t> payload;  // CBOR-like compact fields; encoded by the transport layer
};

/// Simple framing: [ver][type][seq lo][seq hi][len lo][len hi][payload…][crc16 lo][crc16 hi]
inline uint16_t crc16(const uint8_t* d, size_t n) {
    uint16_t crc = 0xFFFF;
    for (size_t i = 0; i < n; i++) { crc ^= uint16_t(d[i]) << 8; for (int b = 0; b < 8; b++) crc = (crc & 0x8000) ? uint16_t((crc << 1) ^ 0x1021) : uint16_t(crc << 1); }
    return crc;
}
inline std::vector<uint8_t> encode(const Frame& f) {
    std::vector<uint8_t> out; out.reserve(f.payload.size() + 8);
    out.push_back(f.version); out.push_back(uint8_t(f.type));
    out.push_back(uint8_t(f.seq & 0xFF)); out.push_back(uint8_t(f.seq >> 8));
    out.push_back(uint8_t(f.payload.size() & 0xFF)); out.push_back(uint8_t(f.payload.size() >> 8));
    out.insert(out.end(), f.payload.begin(), f.payload.end());
    uint16_t c = crc16(out.data(), out.size()); out.push_back(uint8_t(c & 0xFF)); out.push_back(uint8_t(c >> 8));
    return out;
}
inline std::optional<Frame> decode(const std::vector<uint8_t>& b) {
    if (b.size() < 8) return std::nullopt;
    size_t len = size_t(b[4]) | (size_t(b[5]) << 8);
    if (b.size() != len + 8) return std::nullopt;
    uint16_t c = uint16_t(b[b.size() - 2]) | (uint16_t(b[b.size() - 1]) << 8);
    if (crc16(b.data(), b.size() - 2) != c) return std::nullopt;
    Frame f; f.version = b[0]; f.type = MsgType(b[1]); f.seq = uint16_t(b[2]) | (uint16_t(b[3]) << 8);
    if (f.version != PROTOCOL_VERSION) return std::nullopt;     // a newer phone must downgrade, an older watch must be updated
    f.payload.assign(b.begin() + 6, b.end() - 2);
    return f;
}

/// Watch-side event with a stable identity.
struct WatchEvent {
    uint32_t seq;            // monotonic per device, persisted (survives power loss)
    uint32_t watchUnixS;     // watch clock at the event
    uint8_t kind;            // 1 start, 2 pause, 3 resume, 4 end, 5 lap, 6 set logged, 7 rep count, 8 discard, 9 save
    std::string workoutId;   // the iPhone's workout id when known, else the watch's local session id
    int32_t a = 0, b = 0, c = 0;   // kind-specific: set index / reps / weight×10, lap number, …
    bool manual = false;     // true when the athlete typed or corrected the value
};

/// Offline queue: events wait here until acknowledged; the queue is bounded, oldest-acknowledged are dropped first and
/// unacknowledged events are never dropped silently (`overflowed()` tells the UI to warn before data is lost).
class EventQueue {
public:
    explicit EventQueue(size_t capacity = 512) : cap_(capacity) {}
    const WatchEvent& push(WatchEvent e) { e.seq = ++lastSeq_; q_.push_back(e); if (q_.size() > cap_) { q_.pop_front(); overflow_++; } return q_.back(); }
    /// Everything not yet acknowledged, oldest first — resent in full after a reconnect (idempotent on the phone).
    std::vector<WatchEvent> pending() const { std::vector<WatchEvent> v; for (auto& e : q_) if (e.seq > ackedUpTo_) v.push_back(e); return v; }
    /// Cumulative ack: everything ≤ seq is delivered. Out-of-order / duplicate acks are harmless.
    void ack(uint32_t seq) { if (seq > ackedUpTo_) ackedUpTo_ = seq; while (!q_.empty() && q_.front().seq <= ackedUpTo_) q_.pop_front(); }
    uint32_t lastSeq() const { return lastSeq_; }
    uint32_t ackedUpTo() const { return ackedUpTo_; }
    size_t size() const { return q_.size(); }
    uint32_t overflowed() const { return overflow_; }
    /// Restore after a reboot (the sequence counter and unacked events come from LittleFS).
    void restore(uint32_t lastSeq, uint32_t acked, std::vector<WatchEvent> events) { lastSeq_ = lastSeq; ackedUpTo_ = acked; q_.assign(events.begin(), events.end()); }
private:
    size_t cap_; std::deque<WatchEvent> q_; uint32_t lastSeq_ = 0, ackedUpTo_ = 0, overflow_ = 0;
};

/// Phone-side (and test) duplicate filter: the same (device, seq) is processed once.
class DedupFilter {
public:
    bool accept(const std::string& deviceId, uint32_t seq) {
        auto& hi = seen_[deviceId];
        if (seq <= hi.cumulative) return false;
        for (auto s : hi.sparse) if (s == seq) return false;
        if (seq == hi.cumulative + 1) { hi.cumulative = seq; compact(hi); } else hi.sparse.push_back(seq);
        return true;
    }
private:
    struct Hi { uint32_t cumulative = 0; std::vector<uint32_t> sparse; };
    static void compact(Hi& h) { bool more = true; while (more) { more = false; for (size_t i = 0; i < h.sparse.size(); i++) if (h.sparse[i] == h.cumulative + 1) { h.cumulative++; h.sparse.erase(h.sparse.begin() + i); more = true; break; } } }
    std::map<std::string, Hi> seen_;
};

/// Clock synchronisation (§12, Mode A): the phone's time is authoritative; the RTC (PCF8563, 32.768 kHz) drifts a few
/// seconds a day and is corrected at every sync; the watch keeps time alone after that.
struct ClockSync {
    int64_t offsetMs = 0;          // phoneTime − watchMonotonic at the last sync
    uint32_t lastSyncUnixS = 0;
    double driftPpm = 0;           // measured between two syncs (positive = watch runs fast)
    void apply(uint32_t phoneUnixS, uint16_t phoneMs, uint32_t watchMonotonicMs, uint32_t watchRtcUnixS) {
        int64_t phone = int64_t(phoneUnixS) * 1000 + phoneMs;
        if (lastSyncUnixS) {
            double elapsed = double(phoneUnixS - lastSyncUnixS);
            if (elapsed > 600) driftPpm = (double(watchRtcUnixS) - double(phoneUnixS)) / elapsed * 1e6;
        }
        offsetMs = phone - int64_t(watchMonotonicMs);
        lastSyncUnixS = phoneUnixS;
    }
    int64_t nowMs(uint32_t watchMonotonicMs) const { return offsetMs + int64_t(watchMonotonicMs); }
    /// Honest "last synced" age for the watch face (§4: cached values carry timestamps).
    uint32_t ageS(uint32_t nowUnixS) const { return lastSyncUnixS ? nowUnixS - lastSyncUnixS : UINT32_MAX; }
};

} // namespace cyw
