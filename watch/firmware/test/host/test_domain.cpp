// Cyclift Watch OS — host-side tests of the pure domain (no hardware). Build & run: make -C watch/firmware/test/host
// Every check prints PASS/FAIL; the process exits non-zero on any failure, so CI and the owner see real outcomes.
#include "../../src/domain/activity.hpp"
#include "../../src/domain/rep_detector.hpp"
#include "../../src/domain/coach.hpp"
#include "../../src/domain/sync.hpp"
#include "../../src/domain/grading.hpp"
#include "../../src/domain/strength.hpp"
#include "../../src/domain/navigation.hpp"
#include <cstdio>
#include <cmath>
#include <random>
#include <map>

static int failures = 0, checks = 0;
#define CHECK(cond, msg) do { checks++; if (!(cond)) { failures++; std::printf("FAIL  %s  (%s:%d)\n", msg, __FILE__, __LINE__); } else std::printf("pass  %s\n", msg); } while (0)

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

    std::printf("\n%d checks, %d failures\n", checks, failures);
    return failures ? 1 : 0;
}
