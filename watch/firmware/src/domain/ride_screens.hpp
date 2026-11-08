#pragma once
// Cyclift Watch OS — the cycling instrument, second design (owner 8 Nov 15:31 + 16:07 redesign directive).
//
// ONE SCREEN, ONE QUESTION
//   Cockpit      → "How am I performing right now?"   one dominant number, one orbital gauge, two secondary metrics,
//                                                     one short command, one compact Pause.
//   Performance  → "How has my effort changed?"       one large chart per page (power · HR · cadence · target vs actual).
//   Navigation   → "Where am I, and where do I go?"   map-style dial with three honest states (tracking · route · lost).
//
// Every arc represents one defined metric (source, min, max, target, current, colour, missing state, update rate are
// documented in docs/CYCLING_INSTRUMENT.md and encoded in `ride::Gauge`). Nothing is drawn without a live or valid
// source. Commands come from `ride::command()` so they can never contradict the numbers shown next to them.
#include "round_layout.hpp"
#include "ride_telemetry.hpp"
#include <sstream>
#include <iomanip>
#include <algorithm>

namespace cyw::ui {

struct RideFrame {                            // everything the ride screens need for one render
    ride::Live live;
    const ride::Series* power = nullptr; const ride::Series* hr = nullptr; const ride::Series* cadence = nullptr;
    const ride::ZoneTime* zoneTime = nullptr;
    const ride::GpsMirror* gps = nullptr;
    uint32_t nowMs = 0;
    std::string coachCue;                      // the phone's own message (shown on the detail screen, not live)
    uint32_t windowS = 60;                     // performance window: 60 / 300 / whole ride
    uint32_t lapAvgW = 0; bool lapAvgKnown = false;
    std::string nextTurn;                      // "" when no route guidance
    bool northUp = false;                      // navigation orientation (heading-up default)
    bool simulated = false;                    // fixture data: the gallery labels it, the product never sets it
};
enum class PerfPage : uint8_t { Power, HeartRate, Cadence, Target };

inline std::string mmss(uint32_t s) { std::ostringstream o; o << s / 60 << ":" << std::setw(2) << std::setfill('0') << s % 60; return o.str(); }
inline std::string km(uint32_t m) { std::ostringstream o; o << std::fixed << std::setprecision(1) << m / 1000.0 << " km"; return o.str(); }
inline std::string one(float v) { std::ostringstream o; o << std::fixed << std::setprecision(1) << v; return o.str(); }
inline std::string gradeTok(std::optional<Grade> g, const std::string& fallback = "accent") {
    if (!g) return fallback;
    switch (*g) { case Grade::Red: return "grade.red"; case Grade::Yellow: return "grade.yellow"; case Grade::LightBlue: return "grade.blue"; case Grade::Green: return "grade.green"; }
    return fallback;
}

// ---------------------------------------------------------------- shared pieces
/// Compact status indicator (top): recording dot + elapsed + ONE link word. Distinct words for distinct states (§6).
inline void statusIndicator(Builder& b, const RideFrame& f, float y = 26.f) {
    const ride::Live& l = f.live;
    ride::LinkState st = ride::linkState(f.gps, f.nowMs, l.phoneLinked);
    std::string link = ride::linkLabel(st, f.gps, f.nowMs);
    std::string rec = l.paused ? "PAUSED" : "REC";
    std::string col = l.paused ? "grade.yellow" : st == ride::LinkState::GpsLive ? "mut" : "grade.yellow";
    Rect r = b.textFirstFit({rec + " " + mmss(l.elapsedS) + " · " + link, rec + " " + mmss(l.elapsedS)}, y, {11, 11, 1, false}, Role::Label, true, col, 4);
    if (!l.paused) b.dot(r.x - 7, r.cy(), 3, "grade.red");          // blinks 1 Hz on the device = recording
}
/// Compact ride control: ONE Pause pill (immediate, one tap) while recording; Resume + End while paused. Lap and End
/// live on the controls overlay (tap the status line or swipe up) and on the physical keys with the two-press preview.
inline void compactControls(Builder& b, const ride::Live& l) {
    if (l.paused) { b.button("Resume", CX - 39, 160, 72, "accent", "onAccent", true, "resume"); b.button("End", CX + 39, 160, 72, "grade.red", "onAccent", true, "end"); }
    else b.button("Pause", CX, 180, 84, "accent", "onAccent", true, "pause");
}

// ---------------------------------------------------------------- COCKPIT
inline Scene rideCockpit(const TextMeasurer& m, const RideFrame& f) {
    Scene s{"live:ride-cockpit"}; Builder b(s, m);
    const ride::Live& l = f.live;
    statusIndicator(b, f, 32.f);                                   // low enough to clear the ring's inner edge
    ride::Lead lead = ride::chooseLead(l);
    ride::Gauge pg = ride::powerGauge(l), hg = ride::hrGauge(l), cg = ride::cadenceGauge(l), ig = ride::intervalGauge(l);
    ride::LinkState link = ride::linkState(f.gps, f.nowMs, l.phoneLinked);
    ride::Command cmd = ride::command(l, link);

    // ORBITAL GAUGE (270°, open at the bottom where the control sits): zone ladder of the lead metric; target band
    // inside it; a white position marker. Min = 0, max = 1.5 × FTP (power) or the top of the last HR zone (HR).
    const float A0 = -135.f, A1 = 135.f, RING = RADIUS - EDGE_INSET - 4;  // 110
    int zones = 0, lit = -1; std::optional<Grade> ringGrade;
    if (lead == ride::Lead::Power && l.ftpKnown) { zones = 7; float pct = *l.power.value / l.ftp; static const float ub[] = {0.55f, 0.75f, 0.90f, 1.05f, 1.20f, 1.50f}; lit = 6; for (int i = 0; i < 6; i++) if (pct <= ub[i]) { lit = i; break; } ringGrade = pg.grade; }
    else if (lead == ride::Lead::HeartRate && !l.hrZones.empty()) { zones = int(l.hrZones.size()); for (int i = 0; i < zones; i++) if (*l.hr.value >= l.hrZones[i].first && (!l.hrZones[i].second || *l.hr.value <= *l.hrZones[i].second)) lit = i; ringGrade = hg.grade; }
    if (zones) b.segments(A0, A1, zones, 6, "line", lit, gradeTok(ringGrade, "accent"), RING, "zoneLadder");
    else if (lead == ride::Lead::Power || lead == ride::Lead::HeartRate) b.arc(A0, A1, 6, "line", RING, "gaugeTrack");   // value without zones: plain track, no invented zones
    if (lead == ride::Lead::Power && l.ftpKnown && l.powerBand) { float top = l.ftp * 1.5f; float lo = l.powerBand->first / top, hi = l.powerBand->second / top; b.arc(A0 + 270 * std::clamp(lo, 0.f, 1.f), A0 + 270 * std::clamp(hi, 0.f, 1.f), 4, "grade.blue", RING - 9, "targetBand"); }
    if (lead == ride::Lead::HeartRate && l.hrBand && !l.hrZones.empty()) { float lo0 = float(l.hrZones.front().first), hi0 = l.hrZones.back().second ? float(*l.hrZones.back().second) : float(l.hrZones.back().first) + 20; auto fr = [&](float v) { return std::clamp((v - lo0) / std::max(1.f, hi0 - lo0), 0.f, 1.f); }; b.arc(A0 + 270 * fr(float(l.hrBand->first)), A0 + 270 * fr(float(l.hrBand->second)), 4, "grade.blue", RING - 9, "targetBand"); }
    if (lead == ride::Lead::Power && pg.valid) b.needle(A0 + 270 * pg.fraction, RING - 6, 4.5f, "text", "marker");
    else if (lead == ride::Lead::HeartRate && hg.valid) b.needle(A0 + 270 * hg.fraction, RING - 6, 4.5f, "text", "marker");
    // INTERVAL PROGRESS in the bottom opening (140°…220°): share of the step completed; hidden in a free ride.
    if (ig.valid && !l.paused) { b.arc(140, 220, 4, "line", RING, "intervalTrack"); if (ig.fraction > 0.01f) b.arc(140, 140 + 80 * ig.fraction, 4, "accent", RING, "intervalArc"); }

    // DOMINANT NUMBER with a large unit; its label names the metric and the target so the command can be checked.
    std::string label, value, unit, vcol = "text";
    switch (lead) {
        case ride::Lead::Power: label = l.powerBand ? "POWER · " + std::to_string(l.powerBand->first) + "–" + std::to_string(l.powerBand->second) + " W" : (l.ftpKnown ? "POWER" : "POWER · NO FTP"); value = std::to_string(int(std::lround(*l.power.value))); unit = "W"; vcol = gradeTok(pg.grade, "text"); break;
        case ride::Lead::HeartRate: label = l.hrBand ? "HR · " + std::to_string(l.hrBand->first) + "–" + std::to_string(l.hrBand->second) + " bpm" : "HEART RATE"; value = std::to_string(int(std::lround(*l.hr.value))); unit = "bpm"; vcol = gradeTok(hg.grade, "text"); break;
        case ride::Lead::Speed: label = "SPEED · PHONE GPS"; value = one(*l.speedKmh.value); unit = "km/h"; break;
        case ride::Lead::Time: label = "TIME · NO SENSORS"; value = mmss(l.elapsedS); unit = ""; break;
    }
    Rect lab = b.text(label, 46, {11, 11, 1, false}, Role::Label, true, "mut", 14);
    float vf = 58.f, lh = m.lineHeight(vf), vy = lab.bottom() + 1;
    float uf = 20.f;                                               // large readable unit (owner §2)
    float vw = m.width(value, vf, true), uw = unit.empty() ? 0 : m.width(unit, uf, false) + 6;
    Rect band = bandAt(vy, lh, 10);
    while (vw + uw > band.w && vf > 34) { vf -= 2; lh = m.lineHeight(vf); vw = m.width(value, vf, true); band = bandAt(vy, lh, 10); }
    float x0 = CX - (vw + uw) / 2;
    { Element v{Kind::Text, Role::Value, {x0, vy, vw, lh}}; v.text = value; v.font = vf; v.bold = true; v.color = vcol; v.id = "lead"; v.critical = true; s.els.push_back(v);
      if (!unit.empty()) { Element u{Kind::Text, Role::Unit, {x0 + vw + 6, vy + lh - m.lineHeight(uf) - 6, uw - 6, m.lineHeight(uf)}}; u.text = unit; u.font = uf; u.color = "mut"; u.id = "leadUnit"; s.els.push_back(u); } }
    float below = vy + lh;                                         // ≈ 124 at 58 px

    // TWO SECONDARY METRICS, chosen by relevance: the step's other target first, then cadence, speed, distance.
    struct T { std::string v, u, col; };
    std::vector<T> sec;
    if (lead != ride::Lead::HeartRate && hg.valid) sec.push_back({std::to_string(int(std::lround(*l.hr.value))), "bpm", gradeTok(hg.grade, "text")});
    if (lead != ride::Lead::Power && pg.valid) sec.push_back({std::to_string(int(std::lround(*l.power.value))), "W", gradeTok(pg.grade, "text")});
    if (cg.valid) sec.push_back({std::to_string(int(std::lround(*l.cadence.value))), "rpm", gradeTok(cg.grade, "text")});
    if (lead != ride::Lead::Speed && l.speedKmh.fresh(5000)) sec.push_back({one(*l.speedKmh.value), "km/h", "text"});
    sec.push_back({km(l.distanceM), "", "text"});
    if (sec.size() > 2) sec.resize(2);
    { float colW = 84.f, x = CX - colW * sec.size() / 2; for (size_t i = 0; i < sec.size(); i++) { Rect box{x + i * colW, below + 2, colW, 18}; std::string txt = sec[i].v + (sec[i].u.empty() ? "" : " " + sec[i].u); Fitted ft = fitText(m, txt, {15, 12, 1, false}, true, colW - 6, 18); if (!ft.fits) continue; float tw = m.width(ft.lines[0], ft.font, true); Element e{Kind::Text, Role::Comp, {box.cx() - tw / 2, box.y, tw, m.lineHeight(ft.font)}}; e.text = txt; e.font = ft.font; e.bold = true; e.color = sec[i].col; e.id = "sec" + std::to_string(i); e.fitLines = ft.lines; s.els.push_back(e); } }

    // ONE COMMAND (≤ 16 chars) or the interval countdown; the explanation is behind a tap (controls overlay → Why?).
    if (!l.paused) {
        std::string cmdText = cmd.text.empty() ? (ig.valid ? "INTERVAL " + mmss(l.stepRemainingS) : "FREE RIDE") : cmd.text;
        b.text(cmdText, 155, {15, 13, 1, false}, Role::Body, true, cmd.text.empty() ? "mut" : gradeTok(cmd.grade, "text"), 16, false, "command");
    }
    compactControls(b, l);
    return s;
}

/// Controls overlay (tap the status line, swipe up, or Key 2 preview): Lap · Pause/Resume · End · Why?
inline Scene rideControls(const TextMeasurer& m, const RideFrame& f) {
    Scene s{"live:ride-controls"}; Builder b(s, m);
    const ride::Live& l = f.live;
    statusIndicator(b, f);
    ride::Command cmd = ride::command(l, ride::linkState(f.gps, f.nowMs, l.phoneLinked));
    b.text(l.paused ? "PAUSED" : "RIDE CONTROLS", 44, {11, 11, 1, false}, Role::Label, true, "mut", 14);
    b.button("Lap", CX - 39, 62, 72, "card2", "text", false, "lap");
    b.button(l.paused ? "Resume" : "Pause", CX + 39, 62, 72, "accent", "onAccent", true, "pause");
    b.button("End ride", CX, 112, 120, "grade.red", "onAccent", true, "end");         // asks to confirm (never one tap)
    if (!cmd.reason.empty()) b.moreText(cmd.reason, 164, {13, 13, 2, false}, Role::Body, false, "mut", 18, "why");
    else b.text("swipe down to return", 166, {11, 11, 1, false}, Role::Label, true, "mut", 14);
    return s;
}

// ---------------------------------------------------------------- PERFORMANCE (one large chart per page)
inline Scene ridePerformance(const TextMeasurer& m, const RideFrame& f, PerfPage page = PerfPage::Power) {
    Scene s{"live:ride-performance"}; Builder b(s, m);
    const ride::Live& l = f.live;
    statusIndicator(b, f);
    const ride::Series* ser = page == PerfPage::HeartRate ? f.hr : page == PerfPage::Cadence ? f.cadence : f.power;
    std::string name = page == PerfPage::HeartRate ? "HEART RATE" : page == PerfPage::Cadence ? "CADENCE" : page == PerfPage::Target ? "VS TARGET" : "POWER";
    std::string unit = page == PerfPage::HeartRate ? "bpm" : page == PerfPage::Cadence ? "rpm" : "W";
    std::string win = f.windowS <= 60 ? "1 min" : f.windowS <= 300 ? "5 min" : "ride";
    s.name += page == PerfPage::HeartRate ? "-hr" : page == PerfPage::Cadence ? "-cadence" : page == PerfPage::Target ? "-target" : "-power";
    // scale: min / max from the data and the target, rounded to a clean step so the axis labels mean something
    std::optional<std::pair<int, int>> target = page == PerfPage::HeartRate ? l.hrBand : (page == PerfPage::Cadence ? l.cadenceRange : l.powerBand);
    float lo = 1e9f, hi = -1e9f; bool any = false;
    if (ser) if (auto rg = ser->range(f.windowS)) { lo = rg->first; hi = rg->second; any = true; }
    if (target) { lo = std::min(lo, float(target->first)); hi = std::max(hi, float(target->second)); any = true; }
    float step = page == PerfPage::HeartRate ? 10.f : page == PerfPage::Cadence ? 10.f : 50.f;
    if (any) { lo = std::floor(lo / step) * step; hi = std::ceil(hi / step) * step; if (hi - lo < step) hi = lo + step; } else { lo = 0; hi = step; }
    std::optional<float> cur = ser ? ser->average(3) : std::nullopt;
    // header: metric · window · current value (clear, large)
    b.text(name + " · " + win, 40, {11, 11, 1, false}, Role::Label, true, "mut", 14);
    if (cur) { std::string cv = std::to_string(int(std::lround(*cur))) + " " + unit; std::optional<float> prev = ser->average(30); std::string trend = prev ? (std::fabs(*cur - *prev) < 1.f ? "steady" : (*cur > *prev ? "▲ " : "▼ ") + std::to_string(int(std::fabs(std::lround(*cur - *prev)))) + " vs 30 s") : "";
        b.textFirstFit({cv + "  ·  " + trend, cv}, 54, {17, 14, 1, false}, Role::Comp, true, "text", 14); }
    else b.text("no " + std::string(page == PerfPage::HeartRate ? "heart-rate" : page == PerfPage::Cadence ? "cadence" : "power") + " source", 54, {13, 13, 1, false}, Role::Body, true, "grade.yellow", 14);
    // the chart: one panel using most of the centre; axis labels inside its corners; target band + line; gaps break the trace
    float ph = l.paused ? 64.f : 82.f;                              // paused: Resume + End need the y 160 row
    Rect panel = bandAt(76, ph, 8); b.panel(panel, "card");
    Rect plot{panel.x + 30, panel.y + 6, panel.w - 40, panel.h - 12};
    auto yOf = [&](float v) { return plot.bottom() - (std::clamp(v, lo, hi) - lo) / (hi - lo) * plot.h; };
    b.textIn(std::to_string(int(hi)), {panel.x + 4, plot.y - 2, 24, 14}, {11, 11, 1, false}, Role::Label, true, "mut", false, "axisHi");
    b.textIn(std::to_string(int(lo)), {panel.x + 4, plot.bottom() - 12, 24, 14}, {11, 11, 1, false}, Role::Label, true, "mut", false, "axisLo");
    if (target) { Rect tb{plot.x, yOf(float(target->second)), plot.w, std::max(2.f, yOf(float(target->first)) - yOf(float(target->second)))}; b.panel(tb, "card2"); b.polyline({std::make_pair(plot.x, yOf((target->first + target->second) / 2.f)), std::make_pair(plot.right(), yOf((target->first + target->second) / 2.f))}, "grade.blue", 1.5f, "targetLine"); }
    if (ser && any) { auto pts = ser->sparkline(f.windowS, lo, hi); std::vector<std::optional<std::pair<float, float>>> abs; for (auto& p : pts) abs.push_back(p ? std::optional<std::pair<float, float>>(std::make_pair(plot.x + p->first * plot.w, plot.bottom() - p->second * plot.h)) : std::nullopt);
        b.polyline(abs, page == PerfPage::HeartRate ? "accent2" : "accent", 2.5f, "trace");
        for (auto it = abs.rbegin(); it != abs.rend(); ++it) if (*it) { b.dot((*it)->first, (*it)->second, 3.5f, "text"); break; } }
    else b.textIn("no samples yet", {plot.x, plot.y + plot.h / 2 - 8, plot.w, 16}, {12, 11, 1, false}, Role::Label, true, "mut");
    // time axis + the page indicator (swipe changes the metric)
    // the window is named in the header; the axis shows only "now" on the right and the target on the left
    { std::string now = "now"; float tw = m.width(now, 11, true); b.textIn(now, {plot.right() - tw, panel.bottom() + 2, tw + 2, 14}, {11, 11, 1, false}, Role::Label, true, "mut", false, "tEnd"); }
    { int idx = int(page); float dy = panel.bottom() + (l.paused ? 15.f : 18.f); for (int i = 0; i < 4; i++) b.dot(CX - 15 + i * 10, dy, i == idx ? 3 : 2, i == idx ? "text" : "line"); }
    if (target) { std::string tl = "target " + std::to_string(target->first) + "–" + std::to_string(target->second) + " " + unit; float tw = m.width(tl, 11, true); b.textIn(tl, {plot.x, panel.bottom() + 2, tw + 2, 14}, {11, 11, 1, false}, Role::Label, true, "grade.blue", false, "targetLabel"); }
    compactControls(b, l);
    return s;
}

// ---------------------------------------------------------------- NAVIGATION (three states)
inline Scene rideNavigation(const TextMeasurer& m, const RideFrame& f) {
    Scene s{"live:ride-navigation"}; Builder b(s, m);
    const ride::Live& l = f.live;
    statusIndicator(b, f);
    ride::LinkState link = ride::linkState(f.gps, f.nowMs, l.phoneLinked);
    ride::RouteState rs = ride::routeState(f.gps);
    auto fix = f.gps ? f.gps->lastFix() : std::nullopt;
    const float cx = CX, cy = l.paused ? 96.f : 106.f, R = l.paused ? 46.f : 56.f;
    const float py = (f.northUp || l.paused) ? cy : cy + 12;                                       // heading-up: position sits low so the road ahead gets the room
    b.dot(cx, cy, R + 2, "card", Role::Decor);                                        // the map dial
    if (fix) {
        ride::MapFrame mf{cx, py, R - 3 - (py - cy), ride::autoScale(*f.gps, 30, R - 3 - (py - cy)), f.northUp};
        bool live = link == ride::LinkState::GpsLive;
        // north indicator on the dial rim (rotates with heading in heading-up mode)
        float nAng = f.northUp ? 0.f : -fix->headingDeg; float t = (nAng - 90) * 3.14159265f / 180; float nx = cx + (R + 2) * std::cos(t), ny = cy + (R + 2) * std::sin(t);
        b.dot(nx, ny, 7, "card2", Role::Decor); { Element e{Kind::Text, Role::Label, {nx - 4, ny - 7, 8, 14}}; e.text = "N"; e.font = 11; e.bold = true; e.color = "grade.red"; e.id = "north"; s.els.push_back(e); }
        auto trail = ride::projectTrailScaled(*f.gps, mf);
        if (std::count_if(trail.begin(), trail.end(), [](auto& p) { return bool(p); }) >= 2) b.polyline(trail, live ? "mut" : "line", 3, "trail");
        if (rs != ride::RouteState::NoRoute) { std::optional<std::pair<float, float>> turn; auto ahead = ride::projectRouteAhead(*f.gps, mf, &turn); if (std::count_if(ahead.begin(), ahead.end(), [](auto& p) { return bool(p); }) >= 2) b.polyline(ahead, rs == ride::RouteState::RouteLost ? "grade.yellow" : "accent", 4, "routeAhead"); if (turn) b.dot(turn->first, turn->second, 4, "accent2"); }
        b.marker(cx, py, f.northUp ? fix->headingDeg : 0.f, live ? "text" : "mut", !live, "position");
        if (link == ride::LinkState::PhoneDisconnected) b.textIn("reconnecting…", {cx - 40, cy + R - 27, 84, 14}, {11, 11, 1, false}, Role::Label, true, "grade.yellow", false, "reconnecting");
        // scale bar (bottom-left inside the dial), hidden while the phone is lost (the spot shows the reconnect state)
        if (link != ride::LinkState::PhoneDisconnected) { float barM = ride::scaleBarM(mf.scaleMPerPx); float barPx = barM / mf.scaleMPerPx; float bx = cx - 40, by = cy + R - 12; b.polyline({std::make_pair(bx, by), std::make_pair(bx + barPx, by)}, "mut", 2, "scaleBar"); std::string lbl = std::to_string(int(barM)) + " m"; b.textIn(lbl, {bx, by - 15, 50, 14}, {11, 11, 1, false}, Role::Label, true, "mut", false, "scaleLabel"); }
    } else {
        b.textIn(link == ride::LinkState::PhoneDisconnected ? "no position · phone lost" : "waiting for the iPhone's GPS", {cx - 48, cy - 16, 96, 32}, {12, 11, 2, false}, Role::Label, true, "mut");
    }
    // ONE context line under the dial, by state (§5 A/B/C) — never a combined warning (§6)
    std::string line; std::string col = "text";
    if (link == ride::LinkState::PhoneDisconnected) { line = fix ? "LAST FIX " + std::to_string(f.gps->ageS(f.nowMs)) + " s AGO" : "PHONE LOST · NO POSITION"; col = "grade.yellow"; }
    else if (link == ride::LinkState::GpsUnavailable) { line = "NO GPS SOURCE"; col = "grade.yellow"; }
    else if (link == ride::LinkState::GpsStale) { line = "STALE · LAST FIX " + std::to_string(f.gps->ageS(f.nowMs)) + " s"; col = "grade.yellow"; }
    else if (rs == ride::RouteState::RouteLost) { line = "OFF ROUTE · " + std::to_string(int(f.gps->guidance().deviationM)) + " m"; col = "grade.yellow"; }
    else if (rs == ride::RouteState::OnRoute) { auto g = f.gps->guidance(); line = (f.nextTurn.empty() ? "" : "↱ ") + std::to_string(int(g.toNextTurnM)) + " m" + (f.nextTurn.empty() ? " to next turn" : " · " + f.nextTurn); }
    else line = one(fix->speedKmh) + " km/h · " + std::to_string(int(fix->headingDeg)) + "° · " + km(uint32_t(f.gps->distanceM()));
    if (!line.empty()) b.textFirstFit({line, line.substr(0, line.find(" · ") == std::string::npos ? line.size() : line.find(" · "))}, l.paused ? 144.f : 164.f, {13, 12, 1, false}, Role::Comp, true, col, 14);
    compactControls(b, l);
    return s;
}

} // namespace cyw::ui
