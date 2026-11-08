#pragma once
// Cyclift Watch OS — cycling telemetry model (owner 8 Nov 15:31, A–C): the adaptive lead metric, gauge values with
// defined meaning and source, rolling series with honest gaps, time in zone, interval progress, GPS mirror with
// freshness and offline rules. Pure C++17, host-tested. Nothing here invents a sample.
#include <cstdint>
#include <optional>
#include <string>
#include <vector>
#include <deque>
#include <cmath>
#include <algorithm>
#include "grading.hpp"

namespace cyw::ride {

// ---------------------------------------------------------------- live inputs (each value carries its age; absent = no source)
struct Reading { std::optional<float> value; uint32_t ageMs = UINT32_MAX; bool fresh(uint32_t maxAgeMs) const { return value && ageMs <= maxAgeMs; } };
struct Live {
    Reading power, hr, cadence, speedKmh;   // speed comes from the phone's GPS mirror
    bool ftpKnown = false; float ftp = 0;
    std::optional<std::pair<int, int>> powerBand;   // W target band of the current step
    std::optional<std::pair<int, int>> hrBand;      // bpm band of the current step (zone)
    std::vector<std::pair<int, std::optional<int>>> hrZones;  // (lo, hi) per zone, hi nullopt = open
    std::optional<std::pair<int, int>> cadenceRange = std::make_pair(85, 95);
    bool recording = false, paused = false;
    uint32_t elapsedS = 0, distanceM = 0;
    std::string stepName; uint32_t stepRemainingS = 0, stepTotalS = 0;
    bool phoneLinked = true; uint32_t phoneLinkAgeMs = 0;
};

enum class Lead : uint8_t { Power, HeartRate, Speed, Time };

/// Adaptive lead metric (A): power when fresh (≤ 3 s) — with or without FTP; otherwise heart rate; otherwise speed
/// from a fresh GPS mirror; otherwise elapsed time. A stale reading is never promoted.
inline Lead chooseLead(const Live& l) {
    if (l.power.fresh(3000)) return Lead::Power;
    if (l.hr.fresh(5000)) return Lead::HeartRate;
    if (l.speedKmh.fresh(5000)) return Lead::Speed;
    return Lead::Time;
}

// ---------------------------------------------------------------- gauges: each has a meaning, a source and a range
struct Gauge {
    std::string id, meaning, source;    // "power vs target band", "power meter via phone"
    float fraction = 0;                 // 0…1 along the arc, clamped; NaN never leaves here
    std::optional<Grade> grade;         // colour by the fixed grading; nullopt → neutral accent (no target)
    bool valid = false;                 // false → the gauge is drawn as an empty track (no needle, no value)
};

/// Power gauge: 0 at 0 W, the band centred on the arc's middle third, full scale 1.5 × band top (or 1.5 × FTP without a band).
inline Gauge powerGauge(const Live& l) {
    Gauge g{"power", "current power against today's target band", "power meter (phone / BikeComputer)"};
    if (!l.power.fresh(3000)) return g;
    float v = *l.power.value;
    if (l.powerBand) { float lo = float(l.powerBand->first), hi = float(l.powerBand->second); float top = hi * 1.5f; g.fraction = std::clamp(v / top, 0.f, 1.f); g.grade = gradeAgainstBand(v, lo, hi); }
    else { float top = l.ftpKnown ? l.ftp * 1.5f : std::max(400.f, v * 1.2f); g.fraction = std::clamp(v / top, 0.f, 1.f); g.grade = std::nullopt; g.meaning = l.ftpKnown ? "current power vs FTP (no step target)" : "current power (FTP unknown: no target, no zones)"; }
    g.valid = true; return g;
}
/// Heart-rate zone indicator: fraction = position across the zone ladder; grade only when the step has a HR band.
inline Gauge hrGauge(const Live& l) {
    Gauge g{"hr", "heart rate across your zones", "chest strap / Apple Watch via phone"};
    if (!l.hr.fresh(5000)) return g;
    float v = *l.hr.value;
    if (!l.hrZones.empty()) { float lo = float(l.hrZones.front().first); float hi = l.hrZones.back().second ? float(*l.hrZones.back().second) : float(l.hrZones.back().first) + 20; g.fraction = std::clamp((v - lo) / std::max(1.f, hi - lo), 0.f, 1.f); }
    else g.fraction = std::clamp(v / 200.f, 0.f, 1.f);
    if (l.hrBand) g.grade = gradeAgainstBand(v, float(l.hrBand->first), float(l.hrBand->second));
    g.valid = true; return g;
}
inline Gauge cadenceGauge(const Live& l) {
    Gauge g{"cadence", "cadence against your preferred range", "power meter / cadence sensor via phone"};
    if (!l.cadence.fresh(3000)) return g;
    float v = *l.cadence.value; g.fraction = std::clamp(v / 130.f, 0.f, 1.f);
    if (l.cadenceRange) g.grade = gradeCadence(v, float(l.cadenceRange->first), float(l.cadenceRange->second));
    g.valid = true; return g;
}
/// Interval progress: elapsed share of the current step (no grade — it is time, not performance).
inline Gauge intervalGauge(const Live& l) {
    Gauge g{"interval", "share of the current step completed", "planned ride steps (phone)"};
    if (!l.stepTotalS) return g;
    g.fraction = std::clamp(1.f - float(l.stepRemainingS) / float(l.stepTotalS), 0.f, 1.f); g.valid = true; return g;
}

// ---------------------------------------------------------------- rolling series with honest gaps (B)
/// Fixed-capacity ring of 1 Hz samples; a missing second is stored as nullopt (a gap), never interpolated.
class Series {
public:
    explicit Series(size_t capacityS = 300) : cap_(capacityS) {}
    void push(uint32_t t, std::optional<float> v) {
        if (lastT_ && t > *lastT_ + 1) for (uint32_t g = *lastT_ + 1; g < t && buf_.size() < cap_ * 2; g++) emit(g, std::nullopt);   // gap seconds
        emit(t, v); lastT_ = t;
    }
    size_t size() const { return buf_.size(); }
    size_t gaps() const { size_t n = 0; for (auto& s : buf_) if (!s.second) n++; return n; }
    std::optional<float> average(uint32_t lastS) const {
        float sum = 0; size_t n = 0; for (auto it = buf_.rbegin(); it != buf_.rend() && lastS--; ++it) if (it->second) { sum += *it->second; n++; }
        return n ? std::optional<float>(sum / n) : std::nullopt;
    }
    /// Points for a sparkline over the last `windowS` seconds: x 0…1, y 0…1 (nullopt = gap → the line breaks).
    std::vector<std::optional<std::pair<float, float>>> sparkline(uint32_t windowS, float lo, float hi) const {
        std::vector<std::optional<std::pair<float, float>>> pts; if (buf_.empty()) return pts;
        uint32_t tEnd = buf_.back().first, tStart = tEnd >= windowS ? tEnd - windowS : 0;
        for (auto& s : buf_) { if (s.first < tStart) continue; float x = float(s.first - tStart) / float(std::max<uint32_t>(1, windowS)); if (s.second) pts.push_back(std::make_pair(x, std::clamp((*s.second - lo) / std::max(1.f, hi - lo), 0.f, 1.f))); else pts.push_back(std::nullopt); }
        return pts;
    }
    /// Min / max of the present samples in the last `windowS` seconds (nullopt when there is none).
    std::optional<std::pair<float, float>> range(uint32_t windowS) const {
        if (buf_.empty()) return std::nullopt;
        uint32_t tEnd = buf_.back().first, tStart = tEnd >= windowS ? tEnd - windowS : 0; float lo = 1e9f, hi = -1e9f; bool any = false;
        for (auto& s : buf_) if (s.first >= tStart && s.second) { lo = std::min(lo, *s.second); hi = std::max(hi, *s.second); any = true; }
        return any ? std::optional<std::pair<float, float>>(std::make_pair(lo, hi)) : std::nullopt;
    }
    /// Downsampled copy for a long window (one point per `bucketS`, average of present samples, gap if none): bounded memory for the ESP32.
    std::vector<std::optional<float>> buckets(uint32_t bucketS) const {
        std::vector<std::optional<float>> out; if (buf_.empty()) return out;
        uint32_t t0 = buf_.front().first; float sum = 0; size_t n = 0; uint32_t cur = 0;
        for (auto& s : buf_) { uint32_t b = (s.first - t0) / bucketS; while (cur < b) { out.push_back(n ? std::optional<float>(sum / n) : std::nullopt); sum = 0; n = 0; cur++; } if (s.second) { sum += *s.second; n++; } }
        out.push_back(n ? std::optional<float>(sum / n) : std::nullopt); return out;
    }
private:
    void emit(uint32_t t, std::optional<float> v) { buf_.emplace_back(t, v); while (buf_.size() > cap_) buf_.pop_front(); }
    size_t cap_; std::deque<std::pair<uint32_t, std::optional<float>>> buf_; std::optional<uint32_t> lastT_;
};

/// Time in zone from the stream of (present) samples — a missing sample adds to no zone.
struct ZoneTime {
    std::vector<uint32_t> seconds;                  // per zone
    uint32_t unknownS = 0;                          // seconds without a reading
    void add(std::optional<float> v, const std::vector<std::pair<int, std::optional<int>>>& zones) {
        if (seconds.size() != zones.size()) seconds.assign(zones.size(), 0);
        if (!v) { unknownS++; return; }
        for (size_t i = 0; i < zones.size(); i++) if (*v >= zones[i].first && (!zones[i].second || *v <= *zones[i].second)) { seconds[i]++; return; }
        unknownS++;
    }
    std::vector<float> shares() const { uint32_t t = 0; for (auto s : seconds) t += s; std::vector<float> o; for (auto s : seconds) o.push_back(t ? float(s) / t : 0.f); return o; }
};

// ---------------------------------------------------------------- GPS mirror (C)
struct Fix { double lat, lon; float speedKmh, headingDeg; uint32_t phoneUnixS; uint32_t watchMs; };

/// Bounded breadcrumb route with simplification; offline rules: the last valid fix is kept with its time, nothing is
/// added while the phone is gone, and the freshness tells the UI what to say.
class GpsMirror {
public:
    explicit GpsMirror(size_t maxPoints = 600, float minStepM = 8.f) : cap_(maxPoints), minStep_(minStepM) {}
    enum class State : uint8_t { NoSource, Searching, Live, Stale, PhoneLost };

    /// Returns false when the fix was NOT recorded: the phone is marked disconnected (a fix cannot legitimately arrive
    /// then — call onPhoneLink(true) first) or it duplicates the last fix's phone timestamp (no duplicate records).
    bool onFix(const Fix& f) {
        if (!linked_) return false;
        if (haveFix_ && f.phoneUnixS == last_.phoneUnixS) return false;
        last_ = f; haveFix_ = true;
        if (trail_.empty() || dist(trail_.back(), f) >= minStep_) { if (!trail_.empty()) distanceM_ += dist(trail_.back(), f); trail_.push_back(f); if (trail_.size() > cap_) simplify(); }
        return true;
    }
    void onPhoneLink(bool linked, uint32_t nowMs) { linked_ = linked; if (!linked) lostAtMs_ = nowMs; }
    State state(uint32_t nowMs) const {
        if (!linked_) return haveFix_ ? State::PhoneLost : State::NoSource;
        if (!haveFix_) return State::Searching;
        return nowMs - last_.watchMs <= 10000 ? State::Live : State::Stale;
    }
    uint32_t ageS(uint32_t nowMs) const { return haveFix_ ? (nowMs - last_.watchMs) / 1000 : UINT32_MAX; }
    const std::optional<Fix> lastFix() const { return haveFix_ ? std::optional<Fix>(last_) : std::nullopt; }
    const std::vector<Fix>& trail() const { return trail_; }
    float distanceM() const { return distanceM_; }
    /// Position/speed may only be DISPLAYED as moving between fixes (visual smoothing); recorded data is the fixes alone.
    bool mayAnimate(uint32_t nowMs) const { return state(nowMs) == State::Live; }

    // Route guidance (when a route is loaded): progress along it, distance to the next turn, deviation.
    struct Route { std::vector<std::pair<double, double>> points; std::vector<size_t> turnIdx; };
    void setRoute(Route r) { route_ = std::move(r); }
    const Route& route() const { return route_; }
    struct Guidance { bool available = false; float progress = 0; float toNextTurnM = 0; bool offRoute = false; float deviationM = 0; };
    Guidance guidance() const {
        Guidance g; if (!haveFix_ || route_.points.size() < 2) return g;
        size_t best = 0; float bestD = 1e9f; for (size_t i = 0; i < route_.points.size(); i++) { float d = distLL(last_.lat, last_.lon, route_.points[i].first, route_.points[i].second); if (d < bestD) { bestD = d; best = i; } }
        g.available = true; g.deviationM = bestD; g.offRoute = bestD > 50.f; g.progress = float(best) / float(route_.points.size() - 1);
        for (auto t : route_.turnIdx) if (t > best) { float d = 0; for (size_t i = best; i < t; i++) d += distLL(route_.points[i].first, route_.points[i].second, route_.points[i + 1].first, route_.points[i + 1].second); g.toNextTurnM = d; break; }
        return g;
    }
    static float distLL(double lat1, double lon1, double lat2, double lon2) {
        const double R = 6371000.0, p = 3.14159265358979 / 180; double dlat = (lat2 - lat1) * p, dlon = (lon2 - lon1) * p; double a = std::sin(dlat / 2) * std::sin(dlat / 2) + std::cos(lat1 * p) * std::cos(lat2 * p) * std::sin(dlon / 2) * std::sin(dlon / 2); return float(2 * R * std::asin(std::sqrt(a)));
    }
private:
    static float dist(const Fix& a, const Fix& b) { return distLL(a.lat, a.lon, b.lat, b.lon); }
    /// Keep every other point of the older half (bounded memory; the recent trail stays detailed).
    void simplify() { std::vector<Fix> out; size_t half = trail_.size() / 2; for (size_t i = 0; i < trail_.size(); i++) if (i >= half || i % 2 == 0) out.push_back(trail_[i]); trail_.swap(out); }
    size_t cap_; float minStep_; std::vector<Fix> trail_; Fix last_{}; bool haveFix_ = false, linked_ = true; uint32_t lostAtMs_ = 0; float distanceM_ = 0; Route route_;
};

/// Projection of the trail into the 240 × 240 circle (heading-up, position at 60 % down the screen), bounded to a radius.
/// Heading-up projection of the breadcrumb trail around the current fix. Points outside `radiusPx` become gaps (nullopt)
/// so the renderer breaks the line there instead of inventing geometry on the rim.
inline std::vector<std::optional<std::pair<float, float>>> projectTrail(const GpsMirror& g, float cx, float cy, float radiusPx, float scaleMPerPx) {
    std::vector<std::optional<std::pair<float, float>>> out; auto last = g.lastFix(); if (!last) return out;
    double h = last->headingDeg * 3.14159265 / 180.0;
    for (auto& f : g.trail()) {
        double dx = (f.lon - last->lon) * 111320.0 * std::cos(last->lat * 3.14159265 / 180.0), dy = (f.lat - last->lat) * 110540.0;   // metres east, north
        double rx = dx * std::cos(h) - dy * std::sin(h), ry = dx * std::sin(h) + dy * std::cos(h);                                      // rotate heading-up
        float px = cx + float(rx / scaleMPerPx), py = cy - float(ry / scaleMPerPx);
        float d = std::sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
        if (d > radiusPx) out.push_back(std::nullopt); else out.emplace_back(std::make_pair(px, py));
    }
    return out;
}


// ---------------------------------------------------------------- status taxonomy (owner 8 Nov 16:07 §6) — never merged into one vague warning
enum class LinkState : uint8_t { PhoneDisconnected, GpsUnavailable /* phone linked, no GPS source / no fix yet */, GpsStale /* last fix > 10 s */, GpsLive };
enum class RouteState : uint8_t { NoRoute, OnRoute, RouteLost /* > 50 m off the line */ };
inline LinkState linkState(const GpsMirror* g, uint32_t nowMs, bool phoneLinked) {
    if (!phoneLinked) return LinkState::PhoneDisconnected;
    if (!g) return LinkState::GpsUnavailable;
    switch (g->state(nowMs)) { case GpsMirror::State::Live: return LinkState::GpsLive; case GpsMirror::State::Stale: return LinkState::GpsStale; case GpsMirror::State::PhoneLost: return LinkState::PhoneDisconnected; default: return LinkState::GpsUnavailable; }
}
inline RouteState routeState(const GpsMirror* g) { if (!g) return RouteState::NoRoute; auto gd = g->guidance(); if (!gd.available) return RouteState::NoRoute; return gd.offRoute ? RouteState::RouteLost : RouteState::OnRoute; }
/// One short status word for the compact indicator. GPS age is shown only when live; stale shows its age in red-free yellow.
inline std::string linkLabel(LinkState st, const GpsMirror* g, uint32_t nowMs) {
    switch (st) { case LinkState::PhoneDisconnected: return "PHONE LOST"; case LinkState::GpsUnavailable: return "NO GPS"; case LinkState::GpsStale: return "GPS STALE " + std::to_string(g->ageS(nowMs)) + " s"; default: return "GPS " + std::to_string(g->ageS(nowMs)) + " s"; }
}

// ---------------------------------------------------------------- coaching commands (owner §2/§6): short, derived from the DISPLAYED target
/// The cockpit never shows a paragraph. It shows one command of ≤ 16 characters whose meaning follows from the numbers
/// on the same screen, so a reader can check it at a glance (214 W inside 180–216 W can only produce HOLD, never EASE
/// OFF). Priority: safety (link / sensor lost) → power vs band → heart rate vs band → cadence vs range → interval
/// countdown → free ride. `reason` is the sentence behind a tap, never on the live screen.
struct Command { std::string text; std::string reason; std::optional<Grade> grade; bool safety = false; };
inline Command command(const Live& l, LinkState link) {
    auto band = [](float v, float lo, float hi) { return gradeAgainstBand(v, lo, hi); };
    if (link == LinkState::PhoneDisconnected) return {"PHONE LOST", "The iPhone link dropped. Recording continues on the watch; GPS and new coaching resume when it reconnects.", Grade::Yellow, true};
    if (l.power.fresh(3000) && l.powerBand) {
        float v = *l.power.value, lo = float(l.powerBand->first), hi = float(l.powerBand->second); int mid = int(std::lround((lo + hi) / 2));
        auto g = band(v, lo, hi);
        if (v > hi) return {"EASE OFF", "Power " + std::to_string(int(std::lround(v))) + " W is above the step target " + std::to_string(int(lo)) + "–" + std::to_string(int(hi)) + " W.", g, false};
        if (v < lo) return {"PUSH TO " + std::to_string(mid) + " W", "Power " + std::to_string(int(std::lround(v))) + " W is below the step target " + std::to_string(int(lo)) + "–" + std::to_string(int(hi)) + " W.", g, false};
        if (l.cadence.fresh(3000) && l.cadenceRange) { int c = int(std::lround(*l.cadence.value)); if (c < l.cadenceRange->first) return {"CADENCE UP", "Cadence " + std::to_string(c) + " rpm is below the planned " + std::to_string(l.cadenceRange->first) + "–" + std::to_string(l.cadenceRange->second) + " rpm; power is on target.", Grade::Yellow, false}; if (c > l.cadenceRange->second) return {"CADENCE DOWN", "Cadence " + std::to_string(c) + " rpm is above the planned range; power is on target.", Grade::Yellow, false}; }
        return {"HOLD " + std::to_string(mid) + " W", "Power is inside the step target " + std::to_string(int(lo)) + "–" + std::to_string(int(hi)) + " W. Keep it there.", g, false};
    }
    if (l.hr.fresh(5000) && l.hrBand) {
        float v = *l.hr.value, lo = float(l.hrBand->first), hi = float(l.hrBand->second); auto g = band(v, lo, hi);
        if (v > hi) return {"HR ABOVE TARGET", "Heart rate " + std::to_string(int(v)) + " bpm is above the step zone " + std::to_string(int(lo)) + "–" + std::to_string(int(hi)) + " bpm.", g, false};
        if (v < lo) return {"HR BELOW TARGET", "Heart rate " + std::to_string(int(v)) + " bpm is below the step zone.", g, false};
        return {"HOLD HR " + std::to_string(int(lo)) + "–" + std::to_string(int(hi)), "Heart rate is inside the step zone.", g, false};
    }
    if (l.stepTotalS) { uint32_t r = l.stepRemainingS; std::string t = (r / 60 < 10 ? "0" : "") + std::to_string(r / 60) + ":" + (r % 60 < 10 ? "0" : "") + std::to_string(r % 60); return {"INTERVAL " + t, "Time left in " + l.stepName + ". No sensor target applies to this step.", std::nullopt, false}; }
    return {"", "", std::nullopt, false};
}

// ---------------------------------------------------------------- navigation projection with auto-scale (owner §5)
struct MapFrame { float cx, cy, radiusPx; float scaleMPerPx; bool northUp; };
/// Chooses the metres-per-pixel so the recent trail and the route ahead fit the dial (2…25 m/px), in 1-2-5 steps so the
/// scale bar reads 50 m / 100 m / 200 m / 500 m.
inline float autoScale(const GpsMirror& g, size_t recentPts, float radiusPx) {
    auto last = g.lastFix(); if (!last) return 5.f;
    float maxD = 0; auto& tr = g.trail(); size_t from = tr.size() > recentPts ? tr.size() - recentPts : 0;
    for (size_t i = from; i < tr.size(); i++) maxD = std::max(maxD, GpsMirror::distLL(last->lat, last->lon, tr[i].lat, tr[i].lon));
    auto gd = g.guidance(); if (gd.available) maxD = std::max(maxD, std::min(250.f, gd.toNextTurnM > 0 ? gd.toNextTurnM + 40.f : 250.f));   // keep the next turn in view
    maxD = std::max(maxD, 120.f);                                   // never zoom in past 120 m of context
    float want = maxD / (radiusPx * 0.9f);
    for (float s : {2.f, 3.f, 4.f, 5.f, 6.f, 8.f, 10.f, 12.f, 15.f, 20.f, 25.f}) if (want <= s) return s;
    return 25.f;
}
/// Scale-bar length in metres that draws between ~20 and ~55 px at `mPerPx`.
inline float scaleBarM(float mPerPx) { for (float m : {50.f, 100.f, 200.f, 500.f, 1000.f}) if (m / mPerPx >= 20.f) return m; return 1000.f; }
inline std::optional<std::pair<float, float>> projectLL(const Fix& origin, double lat, double lon, const MapFrame& mf, float headingDeg) {
    double dx = (lon - origin.lon) * 111320.0 * std::cos(origin.lat * 3.14159265 / 180.0), dy = (lat - origin.lat) * 110540.0;
    double h = mf.northUp ? 0.0 : headingDeg * 3.14159265 / 180.0;
    double rx = dx * std::cos(h) - dy * std::sin(h), ry = dx * std::sin(h) + dy * std::cos(h);
    float px = mf.cx + float(rx / mf.scaleMPerPx), py = mf.cy - float(ry / mf.scaleMPerPx);
    float d = std::sqrt((px - mf.cx) * (px - mf.cx) + (py - mf.cy) * (py - mf.cy));
    if (d > mf.radiusPx) return std::nullopt;
    return std::make_pair(px, py);
}
inline std::vector<std::optional<std::pair<float, float>>> projectTrailScaled(const GpsMirror& g, const MapFrame& mf) {
    std::vector<std::optional<std::pair<float, float>>> out; auto last = g.lastFix(); if (!last) return out;
    for (auto& f : g.trail()) out.push_back(projectLL(*last, f.lat, f.lon, mf, last->headingDeg));
    return out;
}
/// The route AHEAD of the nearest route point (what the rider still has to ride), projected like the trail.
inline std::vector<std::optional<std::pair<float, float>>> projectRouteAhead(const GpsMirror& g, const MapFrame& mf, std::optional<std::pair<float, float>>* nextTurnPx = nullptr) {
    std::vector<std::optional<std::pair<float, float>>> out; auto last = g.lastFix(); if (!last) return out;
    auto& r = g.route(); if (r.points.size() < 2) return out;
    size_t best = 0; float bd = 1e9f; for (size_t i = 0; i < r.points.size(); i++) { float d = GpsMirror::distLL(last->lat, last->lon, r.points[i].first, r.points[i].second); if (d < bd) { bd = d; best = i; } }
    for (size_t i = best; i < r.points.size(); i++) out.push_back(projectLL(*last, r.points[i].first, r.points[i].second, mf, last->headingDeg));
    if (nextTurnPx) { *nextTurnPx = std::nullopt; for (auto t : r.turnIdx) if (t > best && t < r.points.size()) { *nextTurnPx = projectLL(*last, r.points[t].first, r.points[t].second, mf, last->headingDeg); break; } }
    return out;
}

} // namespace cyw::ride
