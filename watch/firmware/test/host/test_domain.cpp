// Cyclift Watch OS — host-side tests of the pure domain (no hardware). Build & run: make -C watch/firmware/test/host
// Every check prints PASS/FAIL; the process exits non-zero on any failure, so CI and the owner see real outcomes.
#include "../../src/domain/activity.hpp"
#include "../../src/domain/rep_detector.hpp"
#include "../../src/domain/coach.hpp"
#include "../../src/domain/sync.hpp"
#include "../../src/domain/grading.hpp"
#include "../../src/domain/strength.hpp"
#include "../../src/domain/navigation.hpp"
#include "../../src/domain/buttons.hpp"
#include "../../src/domain/round_layout.hpp"
#include "../../src/domain/screens.hpp"
#include "../../src/domain/layout_checks.hpp"
#include "../../src/domain/ride_telemetry.hpp"
#include "../../src/domain/ride_screens.hpp"
#include <cstdio>
#include <cmath>
#include <random>
#include <map>

static int failures = 0, checks = 0;
#define CHECK(cond, msg) do { checks++; std::string _m = (msg); if (!(cond)) { failures++; std::printf("FAIL  %s  (%s:%d)\n", _m.c_str(), __FILE__, __LINE__); } else std::printf("pass  %s\n", _m.c_str()); } while (0)

using namespace cyw;

// ---------------------------------------------------------------- synthetic wrist motion
// A repetition is modelled as one period of a sine on the forearm axis with amplitude A (m/s²), sampled at 50 Hz,
// on top of 1 g gravity (tilted) and white noise; pauses are gravity + noise only.
struct Synth {
    std::mt19937 rng{42}; std::normal_distribution<float> noise{0.f, 0.25f};
    float g = 9.81f;
    Accel rest(float tilt) { return {g * std::sin(tilt) + noise(rng), noise(rng), g * std::cos(tilt) + noise(rng)}; }
    std::vector<Accel> reps(int n, float periodS, float amp, float tilt = 0.3f, float hz = 50.f) {
        std::vector<Accel> v; int per = int(periodS * hz);
        for (int r = 0; r < n; r++) for (int i = 0; i < per; i++) { float ph = 2.f * float(M_PI) * i / per; Accel a = rest(tilt); a.x += amp * std::sin(ph); a.z += 0.3f * amp * std::cos(ph); v.push_back(a); }
        return v;
    }
    std::vector<Accel> pause(float seconds, float tilt = 0.3f, float hz = 50.f) { std::vector<Accel> v; for (int i = 0; i < int(seconds * hz); i++) v.push_back(rest(tilt)); return v; }
    std::vector<Accel> walk(float seconds, float hz = 50.f) {       // arm swing while walking: ~1.9 Hz, small amplitude
        std::vector<Accel> v; for (int i = 0; i < int(seconds * hz); i++) { float t = i / hz; Accel a = rest(0.9f); a.x += 0.9f * std::sin(2 * float(M_PI) * 1.9f * t); a.y += 0.6f * std::sin(2 * float(M_PI) * 0.95f * t); v.push_back(a); } return v;
    }
    std::vector<Accel> bump(float hz = 50.f) {                       // one sharp knock
        std::vector<Accel> v = pause(1.0f); for (int i = 0; i < 3; i++) { Accel a = rest(0.3f); a.x += 6.f; v.push_back(a); } auto p = pause(2.0f); v.insert(v.end(), p.begin(), p.end()); return v;
    }
};
static uint32_t run(RepDetector& d, const std::vector<Accel>& s, uint32_t t0 = 0, float hz = 50.f) { uint32_t t = t0; for (auto& a : s) { d.feed(a, t); t += uint32_t(1000.f / hz); } return t; }

int main() {
    std::printf("== activity lifecycle ==\n");
    {
        const ActivityType* ride = findActivity("cycling_outdoor"); const ActivityType* lift = findActivity("strength");
        CHECK(ride && lift && findActivity("nope") == nullptr, "registry resolves known ids and rejects unknown ones");
        CHECK(activityRegistry().size() == 11, "eleven initial activity categories (directive §5)");
        ActivitySession s(*ride);
        CHECK(!s.pause(0) && !s.end(0), "cannot pause or end before start");
        CHECK(s.prepare(0) && s.start(1000), "Select → Prepare → Start");
        CHECK(s.pause(11000) && s.phase() == Phase::Paused, "Active → Pause");
        CHECK(s.resume(16000) && s.activeMs(26000) == 20000 && s.pausedMs(26000) == 5000 && s.elapsedMs(26000) == 25000, "elapsed 25 s = active 20 s + paused 5 s");
        CHECK(s.pause(26000) && s.end(30000) && s.phase() == Phase::Ended, "End is allowed while paused (never trapped)");
        CHECK(s.elapsedMs(99999) == 29000 && s.activeMs(99999) == 20000, "timers freeze at End");
        CHECK(s.review() && s.save() && s.phase() == Phase::Saved, "End → Review → Save");
        ActivitySession s2(*ride); s2.start(0); CHECK(s2.end(5000) && s2.discard() && s2.phase() == Phase::Discarded, "End → Review → Discard also valid; End directly from Active");
        Sources none; none.stepCounter = true;
        CHECK(!s.canShow(Metric::Distance, none) && !s.canShow(Metric::Power, none) && !s.canShow(Metric::HeartRate, none), "no GPS / power / HR source → those metrics are not offered (never faked)");
        Sources gps; gps.phoneGps = true; CHECK(s.canShow(Metric::Distance, gps) && s.canShow(Metric::Speed, gps) && !s.canShow(Metric::Power, gps), "phone GPS enables distance/speed only");
        Sources pm; pm.power = true; CHECK(s.canShow(Metric::Power, pm) && s.canShow(Metric::Cadence, pm), "a power meter brings power and cadence");
        ActivitySession l(*lift); CHECK(!l.canShow(Metric::Distance, gps) && l.canShow(Metric::Reps, none) && l.canShow(Metric::RestTimer, none), "strength lists no distance; reps/rest need no external source");
    }

    std::printf("== rep detector (synthetic wrist motion) ==\n");
    {
        Synth syn;
        RepDetector d;
        auto set = syn.reps(10, 2.0f, 4.0f);                   // 10 curls at a 2 s tempo, 4 m/s² swing
        run(d, set);
        std::printf("   10 curls → counted %u, rejected %u, confidence %.2f\n", d.count(), d.rejectedCycles(), d.confidence());
        CHECK(d.count() >= 9 && d.count() <= 11, "10 steady curls → 9–11 counted");
        CHECK(d.confidence() >= 0.6f, "steady tempo and amplitude → confidence ≥ 0.6");

        RepDetector still; run(still, syn.pause(20.f));
        CHECK(still.count() == 0, "20 s holding still → 0 reps");

        RepDetector walking; run(walking, syn.walk(20.f));
        std::printf("   walking 20 s → counted %u, confidence %.2f\n", walking.count(), walking.confidence());
        CHECK(walking.count() <= 4 || walking.confidence() < 0.5f, "arm swing while walking: few or low-confidence counts (not a set)");

        RepDetector knocks; for (int i = 0; i < 5; i++) run(knocks, syn.bump(), 0);
        CHECK(knocks.count() <= 1, "five isolated knocks → at most 1 false rep");

        RepDetector tempo; auto fast = syn.reps(8, 1.2f, 3.5f); run(tempo, fast);
        std::printf("   8 fast reps (1.2 s) → counted %u\n", tempo.count());
        CHECK(tempo.count() >= 7 && tempo.count() <= 9, "8 fast reps → 7–9 counted");

        RepDetector slow; auto s3 = syn.reps(6, 4.0f, 3.0f); run(slow, s3);
        std::printf("   6 slow reps (4 s) → counted %u\n", slow.count());
        CHECK(slow.count() >= 5 && slow.count() <= 7, "6 slow reps → 5–7 counted");

        RepDetector two; auto a = syn.reps(8, 2.0f, 4.f); uint32_t t = run(two, a); auto p = syn.pause(45.f); t = run(two, p, t); auto b = syn.reps(8, 2.0f, 4.f); run(two, b, t);
        std::printf("   two sets of 8 with 45 s rest → counted %u\n", two.count());
        CHECK(two.count() >= 15 && two.count() <= 17, "two sets of 8 with a 45 s pause → 15–17 counted (the pause does not add reps)");

        RepDetector corr; run(corr, syn.reps(10, 2.0f, 4.0f)); corr.undoLastRep(); corr.setCountManually(10);
        CHECK(corr.count() == 10 && corr.manualCorrections() == 2, "undo and manual correction are recorded as the athlete's word");
    }

    std::printf("== coaching inbox ==\n");
    {
        CoachInbox in;
        CoachMessage a; a.id = 1; a.instruction = "Keep this effort."; a.priority = Priority::Info; a.context = Context::Cycling;
        CoachMessage b; b.id = 2; b.instruction = "Reduce power."; b.priority = Priority::Action; b.context = Context::Cycling; b.expiresAtMs = 20000;
        in.receive(a, 1000); in.receive(b, 2000);
        CHECK(in.primary(3000, Context::Cycling)->id == 2, "the higher-priority message is the one shown");
        CHECK(in.primary(25000, Context::Cycling)->id == 1, "an expired message is never shown; the next one takes over");
        auto lost = LocalRules::sensorLost("heart-rate", 26000); in.receive(lost, 26000);
        CHECK(in.primary(27000, Context::Strength)->safety && CoachInbox::wantsHaptic(*in.primary(27000, Context::Strength)), "a safety message wins in every context and asks for a haptic");
        CHECK(in.primary(27000, Context::Strength)->local, "offline rules are marked local (never presented as AI)");
        CoachMessage b2 = b; b2.instruction = "Reduce power a little."; b2.expiresAtMs = 0; in.receive(b2, 28000);
        CHECK(in.size() == 3, "the same id replaces, never duplicates");
        in.dismiss(lost.id); CHECK(in.primary(29000, Context::Cycling)->id == 2, "dismissing the safety cue returns to the action");
    }

    std::printf("== protocol frames, event queue, dedup, clock ==\n");
    {
        Frame f; f.type = MsgType::Event; f.seq = 0x1234; f.payload = {1, 2, 3, 4, 5};
        auto bytes = encode(f); auto back = decode(bytes);
        CHECK(back && back->type == MsgType::Event && back->seq == 0x1234 && back->payload == f.payload, "frame round-trips with CRC");
        bytes[7] ^= 0x40; CHECK(!decode(bytes), "a corrupted byte fails the CRC");
        auto other = encode(f); other[0] = 2; CHECK(!decode(other), "a different protocol version is refused, not misread");

        EventQueue q(4);
        for (int i = 0; i < 3; i++) q.push({0, 100u + i, 6, "w1", i, 8, 600});
        CHECK(q.lastSeq() == 3 && q.pending().size() == 3, "three unacknowledged events wait");
        q.ack(2); CHECK(q.pending().size() == 1 && q.pending()[0].seq == 3, "cumulative ack removes ≤ 2");
        q.ack(1); CHECK(q.pending().size() == 1, "an old / duplicate ack changes nothing");
        for (int i = 0; i < 5; i++) q.push({0, 200u + i, 7, "w1", 0, 0, 0});
        CHECK(q.overflowed() == 2 && q.size() == 4, "bounded queue reports overflow instead of losing data silently");
        EventQueue r; r.restore(42, 40, {{41, 1, 6, "w1"}, {42, 2, 6, "w1"}}); CHECK(r.pending().size() == 2 && r.push({0, 3, 5, "w1"}).seq == 43, "restored after reboot: sequence continues, unacked events are resent");

        DedupFilter d;
        CHECK(d.accept("watch", 1) && !d.accept("watch", 1) && d.accept("watch", 3) && d.accept("watch", 2) && !d.accept("watch", 3) && d.accept("phone", 1), "(device, seq) is processed once, out of order and across devices");

        ClockSync c; c.apply(1762600000, 500, 10000, 1762600000);
        CHECK(c.nowMs(11000) == 1762600001500LL, "phone time is authoritative after a sync");
        c.apply(1762603600, 0, 3610000, 1762603604);           // an hour later the RTC is 4 s fast
        CHECK(std::fabs(c.driftPpm - 1111.1) < 1.0, "drift measured between syncs (≈1111 ppm here)");
        CHECK(c.ageS(1762603700) == 100, "sync age is reported, never hidden");
    }

    std::printf("== grading (fixed four colours) ==\n");
    {
        CHECK(!gradeAgainstBand(std::nullopt, 180, 216), "no reading → no grade");
        CHECK(gradeAgainstBand(200.f, 180, 216) == Grade::LightBlue && gradeAgainstBand(217.f, 180, 216) == Grade::Yellow && gradeAgainstBand(240.f, 180, 216) == Grade::Red, "power band: inside / just outside / far outside");
        CHECK(gradeStep(0.95f, false) == Grade::Green && gradeStep(0.95f, true) == Grade::Red && !gradeStep(std::nullopt, false), "step: achieved / cut short / unknown");
        CHECK(!gradeCadence(90.f, 0, 0) && gradeCadence(90.f, 85, 95) == Grade::LightBlue, "cadence: no range → no grade; inside → on target");
        CHECK(style(Grade::Red).rgb565Dark == 0xFAEB && style(Grade::Green).text[0] == 'a' && style(Grade::LightBlue).icon[0] == 'c', "one style table: colours, text and icon per grade");
    }

    std::printf("== strength session ==\n");
    {
        std::vector<PlannedExercise> plan = {
            {"bench", "Bench press", {{8, 60, false}, {8, 60, false}, {8, 60, false}}, 90, 0},
            {"row", "Dumbbell row", {{10, 24, false}, {10, 24, false}}, 60, 'A'},
            {"press", "Shoulder press", {{10, 16, false}, {10, 16, false}}, 60, 'A'},
        };
        StrengthSession s(plan);
        CHECK(s.current()->id == "bench" && s.currentTarget()->targetReps == 8 && s.totalSets() == 7, "starts at bench set 1 of 3; 7 sets in total");
        auto l1 = s.logSet(8, std::nullopt, false, 1000);
        CHECK(l1.weightKg == 60.f && s.currentSet() == 1 && s.resting(2000) && s.restRemainingS(2000) == 89, "manual set logged at the planned weight; 90 s rest runs");
        s.skipRest(); CHECK(!s.resting(3000), "skip rest");
        s.logSet(7, 62.5f, false, 4000); s.logSet(8, std::nullopt, true, 5000);
        CHECK(s.current()->id == "row" && s.currentSet() == 0, "after 3 bench sets the superset A starts with row");
        s.logSet(10, std::nullopt, false, 6000);
        CHECK(s.current()->id == "press", "superset alternates: row → press");
        s.logSet(10, std::nullopt, false, 7000);
        CHECK(s.current()->id == "row" && s.currentSet() == 1, "… → row set 2");
        CHECK(s.correctLast(9, std::nullopt) && s.log().back().reps == 9 && s.log().back().corrected, "correcting the last set marks it corrected");
        CHECK(s.undoLast() && s.current()->id == "press" && s.currentSet() == 0 && s.completedSets() == 4, "undo steps back to the undone set");
        s.logSet(10, std::nullopt, false, 8000); s.logSet(10, std::nullopt, false, 9000); s.logSet(10, std::nullopt, false, 10000);
        CHECK(s.finished() && s.completedSets() == 7, "all seven sets logged → finished");
        std::printf("   logged: "); for (auto& x : s.log()) std::printf("[%u/%u %u×%.1f%s] ", x.exercise, x.set, x.reps, x.weightKg, x.autoCounted ? " auto" : ""); std::printf("\n");
    }

    std::printf("== navigation ==\n");
    {
        Navigator n;
        CHECK(n.handle(Gesture::SwipeLeft) && n.current() == Screen::Today && n.handle(Gesture::SwipeLeft) && n.current() == Screen::Recovery, "face → swipe left → Today → Recovery");
        CHECK(n.handle(Gesture::Button1) && n.current() == Screen::Face, "the first button is always Back to the face");
        CHECK(n.handle(Gesture::SwipeUp) && n.current() == Screen::Activities && n.handle(Gesture::SwipeDown) && n.current() == Screen::Face, "swipe up = activities, swipe down returns");
        CHECK(n.handle(Gesture::SwipeDown) && n.current() == Screen::QuickSettings, "swipe down from the face = quick settings");
        n.handle(Gesture::Button1);
        n.startActivity(true, false);
        CHECK(n.current() == Screen::RideCockpit && n.activityRunning(), "starting a ride lands on the Cockpit");
        CHECK(!n.handle(Gesture::SwipeUp) && !n.handle(Gesture::SwipeDown) && n.current() == Screen::RideCockpit, "during a ride, up/down never leave the activity (controls stay visible)");
        CHECK(n.handle(Gesture::SwipeLeft) && n.current() == Screen::RideNavigation && n.handle(Gesture::SwipeLeft) && n.current() == Screen::RidePerformance && n.handle(Gesture::SwipeLeft) && n.current() == Screen::RideCockpit, "Cockpit → Navigation → Performance → Cockpit ring");
        n.endActivity(); CHECK(n.current() == Screen::RideReview && !n.activityRunning(), "End → Review");
        CHECK(!n.handle(Gesture::SwipeLeft), "Review is left only through Save / Discard, never by a swipe");
        n.finishReview(); CHECK(n.current() == Screen::Face, "after Save the watch face returns");
        n.startActivity(false, true); CHECK(n.current() == Screen::LiftExercise && n.handle(Gesture::SwipeLeft) && n.current() == Screen::LiftRest, "strength: Exercise ⇄ Rest");
    }

    std::printf("== physical buttons ==\n");
    {
        KeyDecoder k;                                   // 30 ms debounce, 700 ms long press, 250 ms repeat guard
        bool fired = false; Press p = Press::Short;
        auto f = [&](bool down, uint32_t t) { auto e = k.feed(down, t); if (e.fired) { fired = true; p = e.press; } };
        // bouncing contact: 5 ms chatter is ignored
        f(true, 0); f(false, 3); f(true, 6); f(false, 9); f(true, 12);
        CHECK(!fired, "contact bounce produces no event");
        f(true, 40); f(true, 100); f(false, 120); f(false, 160);
        CHECK(fired && p == Press::Short, "a clean 120 ms press is one short press");
        fired = false; f(true, 200); f(true, 240); f(false, 260); f(false, 300);
        CHECK(!fired, "a second press 80 ms later is swallowed by the repeat guard (no double trigger)");
        fired = false; f(true, 1000); f(true, 1040); f(true, 1500); f(true, 1750);
        CHECK(fired && p == Press::Long, "held 700 ms → exactly one long press while still held");
        fired = false; f(true, 1900); f(false, 1950); f(false, 2000);
        CHECK(!fired, "releasing after a long press fires nothing more");
        // context map
        CHECK(actionFor(Mode::Face, Key::Key1, Press::Short, true, true) == Action::Wake, "with the screen off any key only wakes");
        CHECK(actionFor(Mode::Face, Key::Key1, Press::Short, false, true) == Action::OpenActivities && actionFor(Mode::Panel, Key::Key1, Press::Short, false, true) == Action::Back, "Key1: activities from the face, Back elsewhere");
        CHECK(actionFor(Mode::Live_Ride, Key::Key1, Press::Short, false, false) == Action::TogglePause && actionFor(Mode::Live_Ride, Key::Key2, Press::Short, false, false) == Action::Lap, "ride: Key1 pause/resume, Key2 lap — also with the phone gone");
        CHECK(actionFor(Mode::Live_Ride, Key::Key1, Press::Long, false, true) == Action::EndRequest && actionFor(Mode::Live_Ride, Key::Key2, Press::Long, false, true) != Action::EndRequest, "End is only a LONG press of Key1 and only a request (UI confirms) — no accidental termination");
        CHECK(actionFor(Mode::Live_Lift, Key::Key2, Press::Short, false, true) == Action::LogSet && actionFor(Mode::Live_Lift, Key::Key2, Press::Long, false, true) == Action::OpenCorrections, "strength: Key2 logs the set, long press opens corrections");
        CHECK(actionFor(Mode::Live_Rest, Key::Key2, Press::Short, false, true) == Action::SkipRest, "rest: Key2 skips rest");
        CHECK(actionFor(Mode::Live_Ride, Key::Boot, Press::Short, false, true) == Action::None && actionFor(Mode::Live_Lift, Key::Boot, Press::Long, false, true) == Action::None, "the Boot key does nothing during a workout (it is the recovery key)");
        CHECK(actionFor(Mode::Review, Key::Key2, Press::Short, false, true) == Action::Save && actionFor(Mode::Review, Key::Key1, Press::Long, false, true) == Action::Discard, "review: Key2 saves, long Key1 asks to discard");
        CHECK(hapticMs(Action::EndRequest) > hapticMs(Action::Back) && hapticMs(Action::Wake) == 0, "haptics scale with consequence; wake is silent");
    }

    std::printf("== round-screen layout engine ==\n");
    {
        using namespace cyw::ui;
        CHECK(std::fabs(halfChord(CY) - (RADIUS - EDGE_INSET)) < 0.01f && halfChord(CY - 100) < 60 && halfChord(0) == 0, "chord: full width at the centre, narrow near the top, zero at the edge");
        Rect band = bandAt(160, 44, 0); CHECK(band.w > 150 && band.w < 158 && insideCircle(band), "two 72-pt buttons fit side by side at y 160–204 (chord ≈ 154)");
        CHECK(!insideCircle({10, 10, 40, 20}) && insideCircle({100, 100, 40, 20}), "insideCircle rejects a corner rectangle, accepts a central one");
        HostMeasurer m;
        Fitted f = fitText(m, "Bench press", {15, 13, 2, false}, true, 120, 40);
        CHECK(f.fits && f.font >= 13 && f.lines.size() <= 2, "short text fits at ≥ 13 px");
        Fitted g = fitText(m, "Bulgarian split squat with dumbbells, rear foot elevated", {15, 13, 2, false}, true, 150, 36);
        CHECK(!g.fits, "a long name does NOT fit two lines at ≥ 13 px — the engine says so instead of shrinking");
        Fitted h = fitText(m, "Bulgarian split squat with dumbbells, rear foot elevated", {15, 13, 2, true}, true, 150, 36);
        CHECK(h.fits && h.truncated && h.lines.back().back() != ' ', "with ellipsis allowed it is marked truncated (never silent)");
        Fitted w = fitText(m, "Supercalifragilisticexpialidocious", {15, 13, 2, false}, true, 100, 40);
        CHECK(!w.fits, "a single word wider than the box never fits (no mid-word cut)");
        // every primary screen, every appearance, every text variant passes the automated round-display checks
        int scenes = 0, findings = 0;
        for (auto& [vn, content] : contentVariants()) for (auto& ap : appearances()) for (auto& sc : allScreens(m, content)) { scenes++; findings += int(check(sc, ap, vn).size()); }
        std::printf("   %d scenes, %d findings\n", scenes, findings);
        CHECK(scenes == 744 && findings == 0, "(17 screens + 3 ride views × 6 telemetry fixtures) × 6 appearances × 4 text variants: 0 overflow / overlap / contrast / truncation / touch-size findings");
        // grading colours are identical across the six appearances (per canvas), independent of the theme
        std::string d, l; for (auto& ap : appearances()) { std::string g1 = ap.resolve("grade.green"); if (ap.dark) { if (d.empty()) d = g1; CHECK(g1 == d, "dark grading green identical in " + ap.name); } else { if (l.empty()) l = g1; CHECK(g1 == l, "light grading green identical in " + ap.name); } }
        CHECK(appearances()[0].resolve("accent") != appearances()[2].resolve("accent"), "theme accents differ while grading colours do not");
    }


    // ------------------------------------------------------------ cycling instrument (owner 8 Nov 15:31, A–F)
    {
        using namespace cyw::ride;
        auto rd = [](float v, uint32_t age) { Reading r; r.value = v; r.ageMs = age; return r; };
        Live l; l.recording = true; l.ftpKnown = true; l.ftp = 240; l.powerBand = std::make_pair(180, 216); l.stepName = "Interval 2"; l.stepTotalS = 300; l.stepRemainingS = 200;
        l.hrZones = {{0, 110}, {111, 130}, {131, 150}, {151, 170}, {171, std::nullopt}};
        l.power = rd(214, 500); l.hr = rd(148, 800); l.cadence = rd(89, 500); l.speedKmh = rd(29.8f, 1500);
        // A: adaptive lead metric + gauges
        CHECK(chooseLead(l) == Lead::Power, "power fresh → power leads");
        l.power.ageMs = 4000; CHECK(chooseLead(l) == Lead::HeartRate, "power stale (> 3 s) → heart rate leads; a stale reading is never promoted");
        l.hr.ageMs = 6000; CHECK(chooseLead(l) == Lead::Speed, "HR stale (> 5 s) → GPS speed leads");
        l.speedKmh.ageMs = 9000; CHECK(chooseLead(l) == Lead::Time, "no fresh sensor → elapsed time leads (no invented metric)");
        l.power.ageMs = 500; l.hr.ageMs = 800; l.speedKmh.ageMs = 1500;
        Gauge pg = powerGauge(l); CHECK(pg.valid && pg.fraction > 0.f && pg.fraction <= 1.f && pg.grade && *pg.grade == cyw::Grade::LightBlue && !pg.meaning.empty() && !pg.source.empty(), "power gauge: in-range fraction, graded light blue (on target) inside the band, meaning + source defined");
        l.power.value = 260; CHECK(*powerGauge(l).grade == cyw::Grade::Red, "well above the band → red"); l.power.value = 214;
        l.power.value = 9000; CHECK(powerGauge(l).fraction == 1.f, "absurd power clamps the gauge at 100 % (never draws outside the arc)"); l.power.value = 214;
        Live noFtp = l; noFtp.ftpKnown = false; noFtp.powerBand = std::nullopt; Gauge ng = powerGauge(noFtp);
        CHECK(ng.valid && !ng.grade && ng.meaning.find("FTP unknown") != std::string::npos, "unknown FTP: power is shown but NOT graded and the gauge says why");
        Live noPwr = l; noPwr.power = Reading{}; CHECK(!powerGauge(noPwr).valid && chooseLead(noPwr) == Lead::HeartRate, "missing power meter: no power gauge, HR leads");
        Live noHr = noPwr; noHr.hr = Reading{}; noHr.speedKmh = Reading{}; noHr.cadence = Reading{};
        CHECK(!hrGauge(noHr).valid && !cadenceGauge(noHr).valid && chooseLead(noHr) == Lead::Time, "no sensors at all: no gauges, time leads");
        Gauge ig = intervalGauge(l); CHECK(ig.valid && std::fabs(ig.fraction - (1.f - 200.f / 300.f)) < 1e-4f, "interval gauge = share of the step completed");
        Live freeRide = l; freeRide.stepTotalS = 0; CHECK(!intervalGauge(freeRide).valid, "free ride: no interval gauge is drawn");
        Gauge hg = hrGauge(l); CHECK(hg.valid && hg.fraction > 0.f && hg.fraction < 1.f, "HR zone indicator positions 148 bpm inside the ladder");
        // B: rolling series with honest gaps
        Series ser(300); for (uint32_t t = 0; t < 30; t++) ser.push(t, 200.f + (t % 3)); ser.push(40, 210.f);      // 10 missing seconds
        CHECK(ser.size() == 41 && ser.gaps() == 10, "ten missing seconds are stored as ten gaps, not interpolated");
        auto sp = ser.sparkline(60, 150, 250); size_t gapPts = 0; for (auto& p : sp) if (!p) gapPts++;
        CHECK(gapPts == 10, "sparkline breaks the line across the gap (no invented samples)");
        CHECK(ser.average(5) && std::fabs(*ser.average(5) - 210.f) < 1e-3f, "rolling average over a window that is mostly gaps uses only the present sample");
        Series empty; CHECK(!empty.average(30) && empty.sparkline(60, 0, 1).empty(), "empty series → no average, no points");
        Series big(300); for (uint32_t t = 0; t < 2000; t++) big.push(t, 100.f); CHECK(big.size() == 300, "ring stays bounded (300 s) for a long ride");
        auto bk = big.buckets(60); CHECK(bk.size() == 5 && bk[0] && std::fabs(*bk[0] - 100.f) < 1e-3f, "5-min window downsamples into 60 s buckets");
        Series gappy(300); gappy.push(0, 1.f); gappy.push(120, 2.f); auto gb = gappy.buckets(60); CHECK(gb.size() == 3 && gb[0] && !gb[1] && gb[2], "a bucket with no samples is a gap");
        ZoneTime zt; for (int i = 0; i < 10; i++) zt.add(148.f, l.hrZones); zt.add(std::nullopt, l.hrZones); zt.add(std::nullopt, l.hrZones);
        CHECK(zt.seconds[2] == 10 && zt.unknownS == 2 && std::fabs(zt.shares()[2] - 1.f) < 1e-4f, "time in zone counts only present samples; missing seconds are reported separately");
        // C: GPS mirror — freshness, offline preservation, bounded memory, no duplicates, no points while disconnected
        GpsMirror g(50, 8.f);
        CHECK(g.state(0) == GpsMirror::State::Searching && g.ageS(0) == UINT32_MAX && !g.lastFix(), "linked phone, no fix yet → Searching, age unknown");
        for (int i = 0; i < 20; i++) g.onFix({25.1972 + i * 0.0002, 55.2744, 30.f, 0.f, 1000u + i, 1000u * i});
        CHECK(g.state(19000) == GpsMirror::State::Live && g.ageS(19000) == 0 && g.trail().size() == 20 && g.distanceM() > 400.f, "fresh fixes → Live; trail + distance accumulate");
        CHECK(g.state(19000 + 11000) == GpsMirror::State::Stale, "no fix for > 10 s → Stale (shown, never animated)"); CHECK(!g.mayAnimate(30000) && g.mayAnimate(19000), "animation only while Live");
        CHECK(!g.onFix({25.2, 55.2744, 30.f, 0.f, 1019u, 19500u}), "a fix repeating the last phone timestamp is rejected (no duplicate record)");
        g.onPhoneLink(false, 20000);
        CHECK(g.state(20000) == GpsMirror::State::PhoneLost && g.lastFix() && g.lastFix()->phoneUnixS == 1019 && g.ageS(25000) == 6, "phone lost: last valid fix kept with its time; age keeps counting");
        CHECK(!g.onFix({25.3, 55.3, 30.f, 0.f, 1030u, 21000u}) && g.trail().size() == 20, "while the phone is marked disconnected no GPS point is created silently");
        float dBefore = g.distanceM(); g.onPhoneLink(true, 26000); CHECK(g.onFix({25.1972 + 20 * 0.0002, 55.2744, 30.f, 0.f, 1031u, 26000u}) && g.trail().size() == 21 && g.distanceM() > dBefore, "reconnect → fixes resume, trail continues from the preserved point");
        for (int i = 0; i < 200; i++) g.onFix({25.1972 + (21 + i) * 0.0002, 55.2744, 30.f, 0.f, 1100u + i, 30000u + 1000u * i});
        CHECK(g.trail().size() <= 50 && g.distanceM() > 4000.f, "trail is bounded (50 points here) while distance stays exact");
        GpsMirror never; never.onPhoneLink(false, 0); CHECK(never.state(0) == GpsMirror::State::NoSource, "never had a fix and no phone → NoSource (no fake map, no invented position)");
        // C: route guidance bounds
        GpsMirror::Route route; for (int i = 0; i <= 10; i++) route.points.emplace_back(25.1972 + i * 0.001, 55.2744); route.turnIdx = {5, 10};
        GpsMirror r; r.setRoute(route); CHECK(!r.guidance().available, "no fix → no guidance");
        r.onFix({25.1972 + 0.002, 55.2744, 20.f, 0.f, 1u, 0u}); auto gd = r.guidance();
        CHECK(gd.available && !gd.offRoute && std::fabs(gd.progress - 0.2f) < 1e-4f && gd.toNextTurnM > 300.f && gd.toNextTurnM < 340.f, "on route: progress 20 %, next turn ≈ 330 m");
        r.onFix({25.1972 + 0.002, 55.2744 + 0.002, 20.f, 0.f, 2u, 1000u}); CHECK(r.guidance().offRoute && r.guidance().deviationM > 50.f, "200 m off the line → deviation warning");
        r.onFix({25.1972 + 0.0105, 55.2744, 20.f, 0.f, 3u, 2000u}); CHECK(r.guidance().progress == 1.f && r.guidance().toNextTurnM == 0.f, "past the last turn: progress 100 %, no next turn (never indexes past the end)");
        auto tr = projectTrail(g, 120, 98, 50, 6.f); size_t outside = 0, inside = 0; for (auto& p : tr) (p ? inside : outside)++;
        CHECK(outside > 0 && inside > 0, "breadcrumbs beyond the dial radius become gaps, never rim artefacts");
        // E: two-press preview → confirm
        cyw::TwoPress tp(2500);
        auto r1 = tp.press(cyw::Key::Key1, cyw::Press::Short, cyw::Mode::Live_Ride, false, true, 1000);
        CHECK(r1.preview && !r1.execute && r1.action == cyw::Action::TogglePause && r1.label == "KEY 1 · Pause / Resume" && r1.hapticMs > 0, "first press previews: name + action, haptic tick, nothing executes");
        auto r2 = tp.press(cyw::Key::Key1, cyw::Press::Short, cyw::Mode::Live_Ride, false, true, 2000);
        CHECK(!r2.preview && r2.execute && r2.action == cyw::Action::TogglePause && !tp.previewing(), "second press of the same key within the window executes");
        tp.press(cyw::Key::Key1, cyw::Press::Short, cyw::Mode::Live_Ride, false, true, 5000);
        CHECK(!tp.tick(7400) && tp.previewing() && tp.tick(7600) && !tp.previewing(), "preview expires after 2.5 s and the UI is told to hide it");
        auto r3 = tp.press(cyw::Key::Key1, cyw::Press::Short, cyw::Mode::Live_Ride, false, true, 8000); CHECK(r3.preview && !r3.execute, "after expiry a press is a fresh preview, not an execution");
        auto r4 = tp.press(cyw::Key::Key2, cyw::Press::Short, cyw::Mode::Live_Ride, false, true, 8500);
        CHECK(r4.preview && !r4.execute && r4.action == cyw::Action::Lap && *tp.previewedAction() == cyw::Action::Lap, "a different key replaces the preview with its own (no cross-confirmation)");
        auto r5 = tp.press(cyw::Key::Key1, cyw::Press::Long, cyw::Mode::Live_Ride, false, true, 9000); CHECK(r5.preview && r5.action == cyw::Action::EndRequest && r5.label == "KEY 1 hold · End ride", "long Key1 previews End ride");
        auto r6 = tp.press(cyw::Key::Key1, cyw::Press::Short, cyw::Mode::Live_Ride, false, true, 9300); CHECK(r6.preview && r6.action == cyw::Action::TogglePause, "a short press after a long preview is a new preview, not a confirmation of End");
        auto r7 = tp.press(cyw::Key::Key1, cyw::Press::Short, cyw::Mode::Live_Ride, true, true, 9600); CHECK(r7.execute && r7.action == cyw::Action::Wake && !tp.previewing(), "screen off: a key wakes immediately and clears any preview");
        auto r8 = tp.press(cyw::Key::Key1, cyw::Press::Short, cyw::Mode::Live_Ride, false, false, 9900); CHECK(r8.preview && r8.action == cyw::Action::TogglePause, "phone disconnected: keys keep working");
        CHECK(cyw::actionFor(cyw::Mode::Live_Lift, cyw::Key::Key2, cyw::Press::Long, false, true) == cyw::Action::OpenCorrections && cyw::actionFor(cyw::Mode::Face, cyw::Key::Key1, cyw::Press::Short, false, true) == cyw::Action::OpenActivities && cyw::actionFor(cyw::Mode::Face, cyw::Key::Key2, cyw::Press::Short, false, true) == cyw::Action::OpenQuickSettings, "strength long Key2 = Correct reps; outside workouts Key1 = Activities, Key2 = Quick settings");
        // E: debouncing with the two-press layer — a 5 ms bounce burst yields exactly one event
        cyw::KeyDecoder kd; int fired = 0; for (uint32_t t = 0; t < 400; t++) { bool level = t >= 100 && t < 200 ? ((t - 100) < 12 ? (t % 2 == 0) : true) : false; if (kd.feed(level, t).fired) fired++; }
        CHECK(fired == 1, "bouncing edge + 100 ms hold → one short press (debounced)");
        // live screens always carry the touchscreen safety controls (Pause immediate; End while paused) — every fixture, every appearance
        bool allControls = true; cyw::ui::HostMeasurer hm;
        for (auto& [vn, content] : cyw::ui::contentVariants()) for (auto& sc : cyw::ui::allScreens(hm, content)) if (sc.name.rfind("live:ride", 0) == 0) { bool pause = false, endOrLap = false; for (auto& e : sc.els) { if (e.id == "pause" || e.id == "resume") pause = true; if (e.id == "end" || e.id == "lap") endOrLap = true; } allControls = allControls && pause && endOrLap; }
        CHECK(allControls, "every ride view in every state keeps an immediate touchscreen Pause/Resume and a Lap/End control");
    }

    std::printf("\n%d checks, %d failures\n", checks, failures);
    return failures ? 1 : 0;
}
