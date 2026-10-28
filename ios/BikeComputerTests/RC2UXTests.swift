import XCTest
@testable import BikeComputer

/// RC2 owner report (28 Oct): readable chart labels, Plan / Progress weekly totals that agree, a truthful link line.
final class RC2UXTests: XCTestCase {
    private let cal = Calendar.current

    // MARK: 1. chart labels never touch, at every phone width, range and text size
    func testDrawnStrideKeepsLabelsApart() {
        // plot widths: iPhone SE (375 pt) ≈ 270, iPhone 16 / 15 (393 pt) ≈ 290, Pro Max (440 pt) ≈ 335 — and narrower,
        // in case a larger text size widens the y-axis labels
        for width in [180.0, 230, 270, 290, 335] {
            for r in ChartRange.allCases {
                for ax in [false, true] {
                    for spacing in [54.0, 66.0] {
                        let base = r.labelStride(accessibility: ax)
                        let n = TrendChartMath.drawnStride(base: base, plotWidth: width, weeks: r.weeks, minSpacing: spacing)
                        XCTAssertGreaterThanOrEqual(Double(n) * width / Double(r.weeks), spacing, "\(r) w=\(width) ax=\(ax)")
                        XCTAssertEqual(n % base, 0, "a multiple of the range's stride keeps the weekly rhythm")
                        XCTAssertGreaterThanOrEqual(n, base)
                    }
                }
            }
        }
        // the owner's phone, 16 weeks: one label every 4 weeks ("5 Oct", "2 Nov" …), four in view
        let n16 = TrendChartMath.drawnStride(base: ChartRange.w16.labelStride(accessibility: false), plotWidth: 290, weeks: 16, minSpacing: 54)
        XCTAssertEqual(n16, 4)
        XCTAssertEqual(TrendChartMath.drawnStride(base: 2, plotWidth: 290, weeks: 8, minSpacing: 54), 2)
    }

    // MARK: 3. Plan and Progress show the same weekly numbers
    private func store() -> Store { Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent("rc2-\(UUID().uuidString)"), generatePlan: false) }
    private func at(_ dayOffset: Int, _ hour: Int, from monday: Date) -> Date { cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: dayOffset, to: monday)!)! }

    func testPlanAndProgressAgreeForTheSameData() {
        let s = store()
        let monday = TrainingLedger.monday(of: Date())
        // plan: 3 rides (one skipped is not planned), 2 strength sessions
        let r1 = Workout(date: at(0, 7, from: monday), kind: .endurance, minutes: 60)
        var r2 = Workout(date: at(2, 7, from: monday), kind: .tempo, minutes: 75)
        let r3 = Workout(date: at(5, 7, from: monday), kind: .long, minutes: 120)
        let skipped = Workout(date: at(6, 7, from: monday), kind: .recovery, minutes: 30, skipped: true)
        let l1 = Workout(date: at(1, 7, from: monday), kind: .strength, minutes: 40)
        var l2 = Workout(date: at(3, 7, from: monday), kind: .strength, minutes: 40)
        r2.completion = .marked; r2.done = true; r2.manualMinutes = 70        /* marked done by hand with a typed duration */
        l2.completion = .marked; l2.done = true                               /* marked done, no duration */
        s.plan = [r1, r2, r3, skipped, l1, l2]
        // done: one recorded ride, one Apple Health ride, a demo ride (never counted), one ride last week (other week)
        var rec = RideRecord(start: at(0, 8, from: monday), durationS: 3720, distanceM: 30_000, recorder: .phone, sources: ["Phone GPS"])
        var health = RideRecord(start: at(4, 18, from: monday), durationS: 1800, distanceM: 12_000, recorder: .health, sources: ["Apple Health"])
        health.healthUUID = "H-1"
        var demo = RideRecord(start: at(1, 9, from: monday), durationS: 5000, distanceM: 1, recorder: .board, sources: ["BikeComputer"]); demo.demo = true
        let lastWeek = RideRecord(start: at(-3, 8, from: monday), durationS: 7200, distanceM: 50_000, recorder: .phone, sources: ["Phone GPS"])
        rec.powerVerified = false
        s.rides = [rec, health, demo, lastWeek]
        // lifting: a detailed log linked to l1, a Health import
        let ex = ExerciseEntry(exercise: Exercise(id: "rc2-sq", name: "Goblet squat", equipment: ["dumbbell"], pattern: .squat, unilateral: false, custom: true), sets: [SetEntry(reps: 8, weightKg: 20, done: true)])
        s.strength = [StrengthSession(date: at(1, 18, from: monday), minutes: 45, focus: .fullBody, rpe: 7, exercises: [ex], workoutId: l1.id),
                      StrengthSession(date: at(5, 17, from: monday), minutes: 30, focus: .fullBody, source: "Apple Health", healthUUID: "H-2")]

        let t = WeekTotals(s.ledger, weekOf: Date())
        // what Progress draws for this week (chart bar + footer) …
        let ridingBar = TrendChartMath.buckets(s.ledger, riding: true, weeks: 8, now: Date()).last!
        let liftingBar = TrendChartMath.buckets(s.ledger, riding: false, weeks: 8, now: Date()).last!
        XCTAssertEqual(ridingBar.minutes, t.riding.minutes); XCTAssertEqual(ridingBar.sessions, t.riding.completed)
        XCTAssertEqual(liftingBar.minutes, t.lifting.minutes); XCTAssertEqual(liftingBar.sessions, t.lifting.completed)
        // … and what Plan's summary used to compute by itself (planned minutes of the week's plan) are the same figures
        XCTAssertEqual(PlanEngine.rideMinutes(s.workouts(weekOf: Date())), t.riding.plannedMinutes)
        XCTAssertEqual(PlanEngine.liftMinutes(s.workouts(weekOf: Date())), t.lifting.plannedMinutes)
        // the numbers themselves: done = 62 + 30 (Health) + 70 (marked, typed) min, 3 sessions; demo and last week excluded
        XCTAssertEqual(t.riding.completed, 3); XCTAssertEqual(t.riding.minutes, 62 + 30 + 70); XCTAssertEqual(t.riding.imported, 1)
        XCTAssertEqual(t.riding.planned, 3); XCTAssertEqual(t.riding.plannedMinutes, 60 + 75 + 120)
        XCTAssertEqual(t.lifting.completed, 3); XCTAssertEqual(t.lifting.minutes, 45 + 30); XCTAssertEqual(t.lifting.unknownDuration, 1)
        XCTAssertEqual(t.lifting.planned, 2); XCTAssertEqual(t.lifting.plannedMinutes, 80)
        // the words both screens print
        XCTAssertEqual(WeekTotals.done(t.riding, singular: "ride", plural: "rides"), "\(Fmt.duration(minutes: 162)) · 3 rides of 3 planned")
        XCTAssertEqual(WeekTotals.planned(t.riding, singular: "ride", plural: "rides"), "\(Fmt.duration(minutes: 255)) · 3 rides")
        let line = WeekTotals.sentence(t.lifting, singular: "session", plural: "sessions")
        XCTAssertTrue(line.hasPrefix("Done this week: \(Fmt.duration(minutes: 75)) · 3 sessions of 2 planned"), line)
        XCTAssertTrue(line.contains("Planned this week: \(Fmt.duration(minutes: 80)) · 2 sessions."), line)
        // a ride on Sunday 23:30 belongs to this week, Monday 00:00 to the next (one boundary for every screen)
        s.rides.append(RideRecord(start: at(6, 23, from: monday).addingTimeInterval(1800), durationS: 600, distanceM: 1, recorder: .phone, sources: []))
        s.rides.append(RideRecord(start: at(7, 0, from: monday), durationS: 600, distanceM: 1, recorder: .phone, sources: []))
        let t2 = WeekTotals(s.ledger, weekOf: Date())
        XCTAssertEqual(t2.riding.completed, 4); XCTAssertEqual(TrendChartMath.buckets(s.ledger, riding: true, weeks: 8, now: Date()).last!.sessions, 4)
    }

    // MARK: 4. the link line never says "Searching" / "Connecting" for good
    func testLinkStatusTextIsTruthful() {
        XCTAssertEqual(DeviceLink.statusText(state: .connecting, stage: .waiting, remembered: true, foundCount: 0),
                       "No BikeComputer found — it may be off, out of range or not advertising. Still looking.")
        XCTAssertEqual(DeviceLink.statusText(state: .idle, stage: .failed, remembered: false, foundCount: 0), "No BikeComputer found — it may be off or not advertising.")
        XCTAssertEqual(DeviceLink.statusText(state: .scanning, stage: .searching, remembered: false, foundCount: 0), "Searching… (up to 20 s)")
        XCTAssertEqual(DeviceLink.statusText(state: .ready, stage: .ready, remembered: true, foundCount: 1), "Connected")
        XCTAssertEqual(DeviceLink.statusText(state: .idle, stage: .idle, remembered: true, foundCount: 0), "Not in range")
        for st in DeviceLink.Stage.allCases {
            let t = DeviceLink.statusText(state: .connecting, stage: st, remembered: true, foundCount: 0)
            if st == .waiting || st == .failed { XCTAssertFalse(t.contains("Searching") || t.contains("Connecting"), "\(st): \(t)") }
        }
    }
}
