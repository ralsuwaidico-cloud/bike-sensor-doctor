import XCTest
@testable import BikeComputer

/// Checkpoint D — analytics from saved records only: de-duplication across Cyclift / Apple Health, measured-or-nil
/// values, zone distribution from samples, personal records from all saved history, strength volume and trends.
final class ProgressAnalyticsTests: XCTestCase {
    let cal = Calendar.current
    func ride(_ daysAgo: Int, min: Int, km: Double, power: Int? = nil, hr: Int? = nil, recorder: RideRecord.Recorder = .phone, samples: [RideRecord.Sample] = []) -> RideRecord {
        var r = RideRecord(start: cal.date(byAdding: .day, value: -daysAgo, to: Date())!, durationS: min * 60, distanceM: Int(km * 1000), recorder: recorder, sources: ["test"])
        r.avgPower = power; r.avgHR = hr; r.samples = samples; return r
    }
    func testHealthImportOfTheSameRideIsCountedOnce() {
        let own = ride(2, min: 60, km: 30, power: 200)
        var dup = own; dup.id = UUID(); dup.recorder = .health; dup.start = own.start.addingTimeInterval(60); dup.avgPower = nil
        let other = ride(9, min: 45, km: 20, recorder: .health)
        let a = ProgressAnalytics.cycling(rides: [own, dup, other], period: .month, ftpW: nil, hrZones: nil)
        XCTAssertEqual(a.rides, 2, "the Health copy of the Cyclift ride is dropped; the other import counts")
        XCTAssertEqual(a.distanceKm?.value ?? 0, 50, accuracy: 0.01)
        XCTAssertEqual(a.avgPower?.records, 1, "power is averaged over the one ride that measured it")
        XCTAssertEqual(a.avgHR, nil, "no heart rate measured → nil, not zero")
    }
    func testZonesComeFromSamplesAndNeedAnFTP() {
        let s = (0..<600).map { RideRecord.Sample(t: $0, w: $0 < 300 ? 150 : 250, cad: nil, hr: 140, speedCms: nil, lat: nil, lon: nil, alt: nil, gap: nil) }
        let r = ride(0, min: 10, km: 5, power: 200, samples: s)   // today: a "this week" test must not depend on the weekday (run 207 ran on a Monday — yesterday was last week)
        let withFTP = ProgressAnalytics.cycling(rides: [r], period: .week, ftpW: 250, hrZones: nil)
        XCTAssertEqual(withFTP.zoneSeconds.count, 7); XCTAssertEqual(withFTP.zoneSeconds.reduce(0, +), 600); XCTAssertEqual(withFTP.zoneSeconds[1], 300, "150 W at FTP 250 = zone 2 for 300 s")
        let noFTP = ProgressAnalytics.cycling(rides: [r], period: .week, ftpW: nil, hrZones: [(0, 120), (121, 140), (141, 160), (161, nil)])
        XCTAssertEqual(noFTP.zoneSeconds.count, 4, "without FTP the heart-rate zones are used"); XCTAssertEqual(noFTP.zoneSeconds[1], 600)
        let nothing = ProgressAnalytics.cycling(rides: [r], period: .week, ftpW: nil, hrZones: nil)
        XCTAssertTrue(nothing.zoneSeconds.isEmpty); XCTAssertTrue(nothing.zoneBasis.hasPrefix("not measurable"))
    }
    func testRecordsAndComparisonUseAllHistoryHonestly() {
        let rides = [ride(1, min: 60, km: 30), ride(5, min: 90, km: 45), ride(40, min: 120, km: 70), ride(45, min: 30, km: 10), ride(400, min: 200, km: 92.4)]
        let a = ProgressAnalytics.cycling(rides: rides, period: .month, ftpW: nil, hrZones: nil)
        XCTAssertEqual(a.rides, 2)
        XCTAssertEqual(a.records.first { $0.kind == "Longest ride" }?.value, "92.4 km", "records span all saved rides, not only the period")
        XCTAssertNotNil(a.comparison); XCTAssertTrue(a.comparison!.contains("vs the previous 30 days"), a.comparison!)
        let few = ProgressAnalytics.cycling(rides: [ride(1, min: 60, km: 30), ride(40, min: 60, km: 30)], period: .month, ftpW: nil, hrZones: nil)
        XCTAssertNil(few.comparison, "one ride on a side is not a comparison")
        XCTAssertEqual(a.consistency.weeks, ProgressAnalytics.weeksIn(ProgressAnalytics.range(.month, now: Date(), calendar: cal).from, Date(), calendar: cal).count)
    }
    func testStrengthVolumeTrendsAndRecords() {
        func session(_ daysAgo: Int, _ w: Double?) -> StrengthSession {
            let ex = ExerciseCatalogue.builtIn.first { $0.id == "ex-001" }!
            let e = ExerciseEntry(exercise: ex, sets: (0..<3).map { _ in SetEntry(reps: 5, weightKg: w, bodyweight: w == nil, done: true) })
            return StrengthSession(date: cal.date(byAdding: .day, value: -daysAgo, to: Date())!, minutes: 40, focus: .fullBody, exercises: [e])
        }
        let a = ProgressAnalytics.strength(sessions: [session(20, 80), session(12, 85), session(4, 90), session(1, nil)], period: .month)
        XCTAssertEqual(a.sessions, 4); XCTAssertEqual(a.detailedSessions, 4); XCTAssertEqual(a.sets, 12); XCTAssertEqual(a.reps, 60)
        XCTAssertEqual(a.tonnageKg?.value ?? 0, (80 + 85 + 90) * 15, accuracy: 0.01, "bodyweight sets add no tonnage"); XCTAssertEqual(a.tonnageKg?.records, 9)
        let line = a.exercises.first!; XCTAssertEqual(line.name, "Back squat"); XCTAssertEqual(line.topWeightKg, 90); XCTAssertTrue(line.trend.hasPrefix("+10.0 kg over 3 sessions"), line.trend)
        XCTAssertEqual(a.records.first?.kind, "Heaviest back squat"); XCTAssertEqual(a.records.first?.value, "90.0 kg × 5")
        XCTAssertFalse(a.muscleCoverage.isEmpty, "the catalogue tags ex-001 with muscle groups"); XCTAssertEqual(a.muscleCoverage.first?.sets, 12)
        var quick = StrengthSession(date: Date(), minutes: 30, focus: .fullBody)
        let b = ProgressAnalytics.strength(sessions: [quick], period: .week)
        XCTAssertEqual(b.sessions, 1); XCTAssertEqual(b.detailedSessions, 0); XCTAssertNil(b.tonnageKg, "a quick log counts as a session but has no sets to analyse")
        quick.source = "health"; let c = ProgressAnalytics.strength(sessions: [quick, StrengthSession(date: Date(), minutes: 30, focus: .fullBody)], period: .week)
        XCTAssertEqual(c.sessions, 1, "the Health import of the same-day session is not counted twice")
    }
    func testGoalsFromProfileHoursAndRecordedMinutes() {
        var r = TrainingLedger.SportWeek(monday: Date()); r.minutes = 130; r.planned = 3; r.plannedDone = 2
        var l = TrainingLedger.SportWeek(monday: Date()); l.minutes = 30; l.planned = 2; l.plannedDone = 0
        let g = ProgressAnalytics.goals(riding: r, lifting: l, hoursPerWeek: 3, liftingHoursPerWeek: 1, includesCycling: true, includesStrength: true)
        XCTAssertEqual(g.count, 3); XCTAssertEqual(g[0].fraction, 130.0 / 180.0, accuracy: 0.001); XCTAssertEqual(g[1].fraction, 0.5, accuracy: 0.001); XCTAssertEqual(g[2].detail, "2 of 5 done")
        XCTAssertEqual(ProgressAnalytics.goals(riding: r, lifting: l, hoursPerWeek: 0, liftingHoursPerWeek: 0, includesCycling: true, includesStrength: true).count, 1, "no weekly hours → no time goal is invented")
    }
}
