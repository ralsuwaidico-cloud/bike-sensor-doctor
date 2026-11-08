#pragma once
#include <algorithm>
// Cyclift Watch OS — the cycling instrument (owner 8 Nov 15:31): Cockpit, Performance, Navigation built from
// `ride_telemetry` state with the round-screen engine. Every arc, needle and line has a defined meaning and source;
// nothing is decorative; nothing is drawn without a live or valid source. Progressive disclosure: one lead metric and a
// few secondary readings per screen; swipe moves between the three screens.
#include "round_layout.hpp"
#include "ride_telemetry.hpp"
#include <sstream>
#include <iomanip>

namespace cyw::ui {

struct RideFrame {                            // everything the three screens need for one render
    ride::Live live;
    const ride::Series* power = nullptr; const ride::Series* hr = nullptr; const ride::Series* cadence = nullptr;
    const ride::ZoneTime* zoneTime = nullptr;
    const ride::GpsMirror* gps = nullptr;
    uint32_t nowMs = 0;
    std::string coachCue;                      // already wrist-contract limited by the inbox
    uint32_t windowS = 60;                     // performance window: 60 / 300 / whole ride
    uint32_t lapAvgW = 0; bool lapAvgKnown = false;
    std::string nextTurn;                      // "" when no route guidance
};

inline std::string mmss(uint32_t s) { std::ostringstream o; o << s / 60 << ":" << std::setw(2) << std::setfill('0') << s % 60; return o.str(); }
inline std::string km(uint32_t m) { std::ostringstream o; o << std::fixed << std::setprecision(1) << m / 1000.0 << " km"; return o.str(); }
inline std::string gradeTok(std::optional<Grade> g, const std::string& fallback = "accent") {
    if (!g) return fallback;
    switch (*g) { case Grade::Red: return "grade.red"; case Grade::Yellow: return "grade.yellow"; case Grade::LightBlue: return "grade.blue"; case Grade::Green: return "grade.green"; } return fallback;
}
/// Recording status line at the top (meaning: recording / paused; link freshness): "● REC 24:18 · GPS 2 s".
inline void statusLine(Builder& b, const RideFrame& f) {
    const ride::Live& l = f.live;
    std::string rec = l.paused ? "PAUSED" : "REC";
    std::string link = f.gps ? (f.gps->state(f.nowMs) == ride::GpsMirror::State::Live ? "GPS " + std::to_string(f.gps->ageS(f.nowMs)) + " s" : f.gps->state(f.nowMs) == ride::GpsMirror::State::PhoneLost ? "phone lost" : f.gps->state(f.nowMs) == ride::GpsMirror::State::Stale ? "GPS stale" : "no GPS") : "no GPS";
    Rect r = b.textFirstFit({rec + " " + mmss(l.elapsedS) + " · " + link, rec + " " + mmss(l.elapsedS)}, 26, {11, 11, 1, false}, Role::Label, true, l.paused ? "grade.yellow" : "mut", 4);
    if (!l.paused) b.dot(r.x - 7, r.cy(), 3, "grade.red");         // the recording dot (blinks 1 Hz on the device: meaning = recording)
}
inline void controls(Builder& b, const ride::Live& l) {
    if (l.paused) { b.button("Resume", CX - 39, 160, 72, "accent", "onAccent", true, "resume"); b.button("End", CX + 39, 160, 72, "grade.red", "onAccent", true, "end"); }
    else { b.button("Lap", CX - 39, 160, 72, "card2", "text", false, "lap"); b.button("Pause", CX + 39, 160, 72, "accent", "onAccent", true, "pause"); }
}

// ---------------------------------------------------------------- COCKPIT
inline Scene rideCockpit(const TextMeasurer& m, const RideFrame& f) {
    Scene s{f.live.paused ? "live:ride-cockpit-paused" : "live:ride-cockpit"}; Builder b(s, m);
    const ride::Live& l = f.live;
    // Outer ring (r 110): the ZONE LADDER of the lead metric — power zones (7) when FTP is known, HR zones otherwise;
    // the lit segment is the zone the athlete is in; its colour is the fixed grade against the step target.
    ride::Lead lead = ride::chooseLead(l);
    ride::Gauge pg = ride::powerGauge(l), hg = ride::hrGauge(l), cg = ride::cadenceGauge(l), ig = ride::intervalGauge(l);
    int zones = 0, lit = -1; std::string ladderSource;
    if (lead == ride::Lead::Power && l.ftpKnown) { zones = 7; float pct = *l.power.value / l.ftp; static const float ub[] = {0.55f, 0.75f, 0.90f, 1.05f, 1.20f, 1.50f}; lit = 6; for (int i = 0; i < 6; i++) if (pct <= ub[i]) { lit = i; break; } ladderSource = "power zones"; }
    else if (lead == ride::Lead::HeartRate && !l.hrZones.empty()) { zones = int(l.hrZones.size()); for (int i = 0; i < zones; i++) if (*l.hr.value >= l.hrZones[i].first && (!l.hrZones[i].second || *l.hr.value <= *l.hrZones[i].second)) lit = i; ladderSource = "HR zones"; }
    if (zones) b.segments(-120, 120, zones, 7, "line", lit, gradeTok(lead == ride::Lead::Power ? pg.grade : hg.grade), RADIUS - EDGE_INSET - 4, "zoneLadder");
    else b.arc(-120, 120, 7, "line", RADIUS - EDGE_INSET - 4, "zoneLadderEmpty");            // no zones: an empty track, nothing lit
    // target band marker on the ladder (power band → the arc span it covers)
    if (lead == ride::Lead::Power && l.ftpKnown && l.powerBand) { float lo = l.powerBand->first / (l.ftp * 1.5f), hi = l.powerBand->second / (l.ftp * 1.5f); b.arc(-120 + 240 * std::clamp(lo, 0.f, 1.f), -120 + 240 * std::clamp(hi, 0.f, 1.f), 3, "grade.blue", RADIUS - EDGE_INSET - 12, "targetBand"); }
    // needle: the current value on the same scale (fraction of 1.5 × FTP, or of the HR ladder)
    if (lead == ride::Lead::Power && pg.valid) b.needle(-120 + 240 * pg.fraction, RADIUS - EDGE_INSET - 10, 3.5f, "text", "needle");
    else if (lead == ride::Lead::HeartRate && hg.valid) b.needle(-120 + 240 * hg.fraction, RADIUS - EDGE_INSET - 10, 3.5f, "text", "needle");
    // Inner arc (r 96, bottom half): INTERVAL progress — meaning: share of the current step done; source: plan
    if (ig.valid) { b.arc(150, 210, 4, "line", RADIUS - EDGE_INSET - 16, "intervalTrack"); b.arc(150, 150 + 60 * ig.fraction, 4, "accent", RADIUS - EDGE_INSET - 16, "intervalArc"); }
    statusLine(b, f);
    // lead metric
    std::string label, value, unit, vcol = "text";
    switch (lead) {
        case ride::Lead::Power: label = l.powerBand ? "POWER · " + std::to_string(l.powerBand->first) + "–" + std::to_string(l.powerBand->second) + " W" : (l.ftpKnown ? "POWER" : "POWER · NO FTP"); value = std::to_string(int(std::lround(*l.power.value))); unit = "W"; vcol = gradeTok(pg.grade, "text"); break;
        case ride::Lead::HeartRate: label = l.hrBand ? "HR · " + std::to_string(l.hrBand->first) + "–" + std::to_string(l.hrBand->second) + " bpm" : "HEART RATE"; value = std::to_string(int(std::lround(*l.hr.value))); unit = "bpm"; vcol = gradeTok(hg.grade, "text"); break;
        case ride::Lead::Speed: label = "SPEED · GPS"; { std::ostringstream o; o << std::fixed << std::setprecision(1) << *l.speedKmh.value; value = o.str(); } unit = "km/h"; break;
        case ride::Lead::Time: label = "TIME · NO SENSORS"; value = mmss(l.elapsedS); unit = ""; break;
    }
    b.metric(label, value, unit, 40, 34, vcol, "lead");
    // secondary telemetry row (compact labels; only live sources; a missing source is simply absent — never 0)
    struct T { std::string v, u, col; };
    std::vector<T> tiles;
    if (lead != ride::Lead::HeartRate && hg.valid) tiles.push_back({std::to_string(int(std::lround(*l.hr.value))), "bpm", gradeTok(hg.grade, "mut")});
    if (cg.valid) tiles.push_back({std::to_string(int(std::lround(*l.cadence.value))), "rpm", gradeTok(cg.grade, "mut")});
    if (lead != ride::Lead::Speed && l.speedKmh.fresh(5000)) { std::ostringstream o; o << std::fixed << std::setprecision(1) << *l.speedKmh.value; tiles.push_back({o.str(), "km/h", "mut"}); }
    tiles.push_back({km(l.distanceM), "", "mut"});
    if (tiles.size() > 3) tiles.resize(3);
    float colW = 66.f, x0 = CX - colW * tiles.size() / 2;
    for (size_t i = 0; i < tiles.size(); i++) {
        Rect box{x0 + i * colW, 97, colW, 16};
        b.textIn(tiles[i].v + (tiles[i].u.empty() ? "" : " " + tiles[i].u), box, {13, 12, 1, false}, Role::Comp, true, tiles[i].col == "mut" ? "text" : tiles[i].col, false, "tile" + std::to_string(i));
    }
    // interval line + coach cue (one line each; the cue obeys the wrist contract)
    if (l.stepTotalS) b.textFirstFit({l.stepName + " · " + mmss(l.stepRemainingS) + " left", mmss(l.stepRemainingS) + " left"}, 114, {11, 11, 1, false}, Role::Label, true, "mut", 12);
    if (!f.coachCue.empty()) b.text(f.coachCue, 128, {13, 13, 2, false}, Role::Body, true, "text", 12, true, "coach");
    controls(b, l);
    return s;
}

// ---------------------------------------------------------------- PERFORMANCE
inline Scene ridePerformance(const TextMeasurer& m, const RideFrame& f) {
    Scene s{"live:ride-performance"}; Builder b(s, m);
    const ride::Live& l = f.live;
    statusLine(b, f);
    std::string win = f.windowS == 60 ? "1 min" : f.windowS == 300 ? "5 min" : "ride";
    { bool hp = f.power && f.power->size(), hh = f.hr && f.hr->size(); std::string hd = hp && hh ? "POWER · HR" : hp ? "POWER" : hh ? "HEART RATE" : "NO SOURCE"; b.text(hd + " · " + win, 42, {11, 11, 1, false}, Role::Label, true, "mut", 12); }
    // sparkline panel: power (accent) and HR (grade-free, muted) over the window; gaps break the line (never invented)
    Rect panel = bandAt(56, 46, 14); b.panel(panel, "card2");
    Rect plot{panel.x + 6, panel.y + 5, panel.w - 12, panel.h - 10};
    if (f.power && f.power->size()) { float top = l.ftpKnown ? l.ftp * 1.5f : 400.f; b.sparkline(plot, f.power->sparkline(f.windowS, 0, top), "accent", 2, "powerLine"); }
    if (f.hr && f.hr->size()) b.sparkline(plot, f.hr->sparkline(f.windowS, 60, 200), "mut", 1.5f, "hrLine");
    if ((!f.power || !f.power->size()) && (!f.hr || !f.hr->size())) b.textIn("no power / HR source", {plot.x, plot.y + 14, plot.w, 16}, {12, 11, 1, false}, Role::Label, true, "mut");
    // time-in-zone distribution: segmented bar (fixed grade colours would be wrong here — zones are not grades → accent shades)
    if (f.zoneTime && !f.zoneTime->seconds.empty()) {
        Rect bar = bandAt(104, 8, 22); float x = bar.x; auto sh = f.zoneTime->shares(); int zi = 0;
        for (float z : sh) { float w = bar.w * z; if (w > 1) { Element e{Kind::Rect, Role::Decor, {x, bar.y, w - 1, bar.h}}; e.fill = zi % 2 ? "accent2" : "accent"; e.id = "zone" + std::to_string(zi); s.els.push_back(e); } x += w; zi++; }
        Element track{Kind::Rect, Role::Decor, bar}; track.fill = "line"; s.els.insert(s.els.end() - zi, track);
        b.text("time in zone" + std::string(f.zoneTime->unknownS ? " · " + std::to_string(f.zoneTime->unknownS) + " s no reading" : ""), 114, {11, 11, 1, false}, Role::Label, true, "mut", 12);
    }
    // rolling averages + interval target vs actual (text, one line each; graphs above carry the shape)
    std::vector<std::string> avg;
    if (f.power) { auto a3 = f.power->average(3), a30 = f.power->average(30); if (a3) avg.push_back("3 s " + std::to_string(int(std::lround(*a3)))); if (a30) avg.push_back("30 s " + std::to_string(int(std::lround(*a30)))); }
    if (f.lapAvgKnown) avg.push_back("lap " + std::to_string(f.lapAvgW));
    if (!avg.empty()) { std::string t; for (size_t i = 0; i < avg.size(); i++) t += (i ? " · " : "") + avg[i]; b.text(t + " W", 128, {12, 12, 1, false}, Role::Comp, true, "text", 12); }
    if (l.stepTotalS) {
        std::string tgt = l.powerBand ? std::to_string(l.powerBand->first) + "–" + std::to_string(l.powerBand->second) + " W" : l.hrBand ? std::to_string(l.hrBand->first) + "–" + std::to_string(l.hrBand->second) + " bpm" : "by effort";
        b.textFirstFit({l.stepName + " · " + tgt + " · " + mmss(l.stepRemainingS), tgt + " · " + mmss(l.stepRemainingS) + " left"}, 144, {11, 11, 1, false}, Role::Label, true, "mut", 12);
    }
    controls(b, l);
    return s;
}

// ---------------------------------------------------------------- NAVIGATION
inline Scene rideNavigation(const TextMeasurer& m, const RideFrame& f) {
    Scene s{"live:ride-navigation"}; Builder b(s, m);
    const ride::Live& l = f.live;
    statusLine(b, f);
    const float mapCx = CX, mapCy = 98, mapR = 54;
    b.dot(mapCx, mapCy, mapR + 2, "card2", Role::Decor);                               // compass dial
    auto st = f.gps ? f.gps->state(f.nowMs) : ride::GpsMirror::State::NoSource;
    auto fix = f.gps ? f.gps->lastFix() : std::nullopt;
    if (fix) {
        // heading ring: N marker rotates with the heading (heading-up display)
        float nAngle = -fix->headingDeg; b.needle(nAngle, mapR + 2, 3, "grade.red", "north");
        auto trail = ride::projectTrail(*f.gps, mapCx, mapCy, mapR - 4, 6.f);         // 6 m per px → 300 m radius
        if (std::count_if(trail.begin(), trail.end(), [](auto& p) { return bool(p); }) >= 2) b.polyline(trail, st == ride::GpsMirror::State::Live ? "accent" : "mut", 3, "trail");
        b.marker(mapCx, mapCy, 0, st == ride::GpsMirror::State::Live ? "text" : "mut", st != ride::GpsMirror::State::Live, "position");
    } else {
        b.textIn(st == ride::GpsMirror::State::PhoneLost ? "tracking unavailable" : "waiting for the iPhone's GPS", {mapCx - 46, mapCy - 20, 92, 30}, {12, 11, 2, false}, Role::Label, true, "mut");
    }
    // honest status under the dial
    std::string line;
    if (st == ride::GpsMirror::State::Live && fix) { std::ostringstream o; o << std::fixed << std::setprecision(1) << fix->speedKmh; line = o.str() + " km/h · " + std::to_string(int(fix->headingDeg)) + "° · GPS " + std::to_string(f.gps->ageS(f.nowMs)) + " s"; }
    else if (st == ride::GpsMirror::State::PhoneLost && fix) line = "last fix " + std::to_string(f.gps->ageS(f.nowMs)) + " s ago · phone lost";
    else if (st == ride::GpsMirror::State::Stale && fix) line = "GPS stale " + std::to_string(f.gps->ageS(f.nowMs)) + " s · " + km(uint32_t(f.gps->distanceM()));
    else line = "no position · no GPS source";
    b.text(line, 118, {11, 11, 1, false}, Role::Label, true, st == ride::GpsMirror::State::Live ? "mut" : "grade.yellow", 12);
    // guidance: next turn or deviation; otherwise the ride distance
    if (f.gps) { auto g = f.gps->guidance(); if (g.available && g.offRoute) b.text("off route · " + std::to_string(int(g.deviationM)) + " m", 136, {13, 12, 1, false}, Role::Body, true, "grade.yellow", 14, true, "turn");
                 else if (g.available && !f.nextTurn.empty()) b.textFirstFit({"↱ " + std::to_string(int(g.toNextTurnM)) + " m · " + f.nextTurn, "↱ " + std::to_string(int(g.toNextTurnM)) + " m"}, 136, {14, 13, 1, false}, Role::Body, true, "text", 14);
                 else b.text(km(l.distanceM) + " · " + mmss(l.elapsedS), 136, {13, 12, 1, false}, Role::Body, true, "text", 14); }
    controls(b, l);
    return s;
}

} // namespace cyw::ui
