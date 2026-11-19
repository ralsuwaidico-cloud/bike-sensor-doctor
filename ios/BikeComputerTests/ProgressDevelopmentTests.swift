import XCTest
@testable import BikeComputer

/// Progress v2.3 sections: every figure is counted from weekly buckets, lift summaries and ride analytics; nothing is
/// said without enough weeks, and no stage is derived.
final class ProgressDevelopmentTests: XCTestCase {
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 2; return c }()
    private func weeks(_ minutes: [Int], sessions: [Int]? = nil) -> [WeekBucket] {
        let first = Date(timeIntervalSince1970: 1_790_553_600)       // a Monday 00:00 UTC
        return minutes.enumerated().map { i, m in
            WeekBucket(start: cal.date(byAdding: .day, value: 7 * i, to: first)!, minutes: m, sessions: sessions?[i] ?? (m > 0 ? 1 : 0))
        }
    }

    func testEnduranceAveragesFullWeeksAndComparesOnlyWithEnoughOfThem() throws {
        // nine weeks; the last one is the unfinished current week and is not part of the average
        let e = try XCTUnwrap(ProgressDevelopment.endurance(weeks([100, 100, 100, 100, 150, 150, 150, 150, 30]), best20: (nil, nil), show: true, calendar: cal))
        XCTAssertEqual(e.averageMinutes, 150); XCTAssertEqual(e.fullWeeks, 4); XCTAssertEqual(e.direction, .higher)
        XCTAssertEqual(e.weeks.count, 9); XCTAssertEqual(e.weeks.last, 30); XCTAssertNil(e.powerLine, "no power measured: no power line")
        XCTAssertEqual(ProgressDevelopment.endurance(weeks([150, 150, 150, 150, 100, 100, 100, 100, 0]), best20: (nil, nil), show: true, calendar: cal)?.direction, .lower)
        XCTAssertEqual(ProgressDevelopment.endurance(weeks([100, 100, 100, 100, 102, 100, 101, 100, 0]), best20: (nil, nil), show: true, calendar: cal)?.direction, .same)
        // too few weeks to compare: the average is shown, no direction is claimed
        let short = try XCTUnwrap(ProgressDevelopment.endurance(weeks([60, 90, 10]), best20: (nil, nil), show: true, calendar: cal))
        XCTAssertNil(short.direction); XCTAssertEqual(short.averageMinutes, 75); XCTAssertEqual(short.fullWeeks, 2)
        // measured power is stated as measured, with what it is compared with
        XCTAssertEqual(ProgressDevelopment.endurance(weeks([60, 60, 60]), best20: (221, 208), show: true, calendar: cal)?.powerLine, "Best 20-minute power 221 W · 208 W in the 6 weeks before")
        // nothing recorded, or an athlete who does not ride: no section
        XCTAssertNil(ProgressDevelopment.endurance(weeks([0, 0, 0, 0]), best20: (nil, nil), show: true, calendar: cal))
        XCTAssertNil(ProgressDevelopment.endurance(weeks([60, 60, 60]), best20: (nil, nil), show: false, calendar: cal))
        XCTAssertEqual(ProgressDevelopment.direction(recent: 10, before: 0), nil, "nothing before: nothing to compare with")
    }

    func testStrengthShowsTheMostLoggedLiftAsRecorded() throws {
        let d0 = Date(timeIntervalSince1970: 1_790_000_000)
        func lift(_ name: String, _ sets: [(Double, Int, Double?)]) -> LiftSummary {
            LiftSummary(exerciseId: "x-" + name, name: name, topSets: sets.enumerated().map { i, s in LiftPoint(date: d0.addingTimeInterval(Double(i) * 604_800), weightKg: s.0, reps: s.1, e1RM: s.2) })
        }
        let squat = lift("Squat", [(85, 5, 92), (90, 5, 97), (95, 4, 100), (100, 3, 104)])
        let s = try XCTUnwrap(ProgressDevelopment.strength([lift("Row", [(40, 10, nil), (42.5, 10, nil)]), squat, lift("Once", [(200, 1, nil)])]) { "\(Int($0)) kg" })
        XCTAssertEqual(s.liftName, "Squat"); XCTAssertEqual(s.sessions, 4); XCTAssertEqual(s.latestKg, 100); XCTAssertEqual(s.latestText, "100 kg × 3")
        XCTAssertEqual(s.direction, .higher)
        XCTAssertEqual(s.ranges.map(\.title), ["Estimated 1RM", "Recorded top set"])
        XCTAssertEqual(s.ranges[1].note, "85 kg × 5 → 100 kg × 3"); XCTAssertEqual(s.ranges[0].fromText, "92 kg"); XCTAssertEqual(s.ranges[0].toText, "104 kg")
        // an estimate is shown only when the app's own rule says a trend is available (three qualifying sessions)
        let few = try XCTUnwrap(ProgressDevelopment.strength([lift("Press", [(40, 8, 50), (42.5, 8, nil)])]) { "\(Int($0)) kg" })
        XCTAssertEqual(few.ranges.map(\.title), ["Recorded top set"]); XCTAssertNil(few.direction, "two sessions: no direction")
        XCTAssertNil(ProgressDevelopment.strength([lift("Once", [(200, 1, nil)])]) { "\($0)" }, "one session is not development")
        XCTAssertNil(ProgressDevelopment.strength([]) { "\($0)" })
    }

    func testConsistencyCountsWeeksWithAnySessionAndZonesAddUp() throws {
        let r = weeks([60, 0, 60, 0, 0], sessions: [2, 0, 1, 0, 0]), l = weeks([0, 0, 40, 40, 0], sessions: [0, 0, 1, 5, 0])
        let c = try XCTUnwrap(ProgressDevelopment.consistency(riding: r, lifting: l, calendar: cal))
        XCTAssertEqual(c.active, 3); XCTAssertEqual(c.total, 5)
        XCTAssertEqual(c.weeks.map(\.rides), [2, 0, 1, 0, 0]); XCTAssertEqual(c.weeks.map(\.lifts), [0, 0, 1, 5, 0])
        XCTAssertNil(ProgressDevelopment.consistency(riding: weeks([0, 0]), lifting: [], calendar: cal), "nothing recorded: no section")
        XCTAssertNil(ProgressDevelopment.consistency(riding: [], lifting: [], calendar: cal))

        func analytics(_ z: [Int], basis: String, rides: Int = 3) -> CyclingAnalytics {
            CyclingAnalytics(period: .quarter, rides: rides, distanceKm: nil, minutes: 0, avgSpeedKmh: nil, avgPower: nil, avgHR: nil, avgCadence: nil, powerTrend: [], hrTrend: [], cadenceTrend: [],
                             zoneSeconds: z, zoneBasis: basis, consistency: (0, 0), records: [], comparison: nil)
        }
        let z = try XCTUnwrap(ProgressDevelopment.zones(analytics([3_333, 3_333, 3_334, 0, 0], basis: "heart-rate zones")).zones)
        XCTAssertEqual(z.shares.reduce(0, +), 100, "the shares are whole per cents that add up"); XCTAssertEqual(z.shares.count, 5)
        XCTAssertEqual(z.easyPercent, z.shares[0] + z.shares[1]); XCTAssertEqual(z.basis, "heart-rate zones"); XCTAssertEqual(z.hours, "2.8 h")
        // rides without any measurable zone time: the section is replaced by the reason, not by a guess
        let none = ProgressDevelopment.zones(analytics([], basis: "not measurable: no FTP and no HR zones"))
        XCTAssertNil(none.zones); XCTAssertEqual(none.missing, "not measurable: no FTP and no HR zones")
        let noRides = ProgressDevelopment.zones(analytics([], basis: "x", rides: 0)); XCTAssertNil(noRides.zones); XCTAssertNil(noRides.missing)
        XCTAssertTrue(ProgressDevelopment().isEmpty)
    }

    /// Time in zones without per-second samples: the zone totals saved with the rides are used as they are, never mixed
    /// across power and heart rate, and when nothing can be shown the reason names exactly what is missing.
    func testZonesFromSavedRideTotalsAndExactReasons() throws {
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        func ride(_ daysAgo: Int, zones: [Int], power: Int? = nil) -> RideRecord {
            var r = RideRecord(start: now.addingTimeInterval(Double(-daysAgo) * 86_400), durationS: 3600, distanceM: 27_000, recorder: .phone, sources: [])
            r.zoneSeconds = zones; r.avgPower = power; return r
        }
        let hr = [ride(2, zones: [900, 2100, 600, 0, 0, 0, 0]), ride(9, zones: [900, 2100, 600, 0, 0, 0, 0])]
        let z = try XCTUnwrap(ProgressDevelopment.storedZones(rides: hr, now: now, calendar: cal).zones)
        XCTAssertEqual(z.shares.count, 5, "a ride without power holds the five heart-rate zones"); XCTAssertEqual(z.kind, .heartRate)
        XCTAssertEqual(z.shares, [25, 58, 17, 0, 0]); XCTAssertEqual(z.shares.reduce(0, +), 100)
        XCTAssertEqual(z.easyPercent, z.shares[0] + z.shares[1]); XCTAssertTrue(z.fromRideTotals); XCTAssertEqual(z.title, "Time in heart-rate zones")
        XCTAssertEqual(z.times[1], "1 h 10"); XCTAssertEqual(z.times[0], "30 min"); XCTAssertTrue(z.basis.contains("saved with 2 rides"))
        let pw = try XCTUnwrap(ProgressDevelopment.storedZones(rides: [ride(1, zones: [60, 60, 60, 60, 60, 60, 60], power: 200)], now: now, calendar: cal).zones)
        XCTAssertEqual(pw.shares.count, 7, "a ride with power holds the seven power zones"); XCTAssertEqual(pw.kind, .power)
        // power and heart-rate totals are never added together
        let mixed = ProgressDevelopment.storedZones(rides: hr + [ride(1, zones: [60, 60, 60, 60, 60, 60, 60], power: 200)], now: now, calendar: cal)
        XCTAssertNil(mixed.zones); XCTAssertTrue(mixed.mixed)
        // older than the period, or no totals: nothing
        XCTAssertNil(ProgressDevelopment.storedZones(rides: [ride(200, zones: [600, 600, 0, 0, 0, 0, 0])], now: now, calendar: cal).zones)
        XCTAssertNil(ProgressDevelopment.storedZones(rides: [ride(2, zones: [0, 0, 0, 0, 0, 0, 0])], now: now, calendar: cal).zones)

        // sampled zones win; then saved totals; then the reason
        let sampled = ProgressDevelopment.Zones(easyPercent: 50, basis: "power zones (FTP 240 W), from recorded samples", hours: "1.0 h", shares: [25, 25, 50])
        XCTAssertEqual(ProgressDevelopment.zonesResolved(sampled: sampled, rides: hr, ftpKnown: true, hrZonesKnown: true, now: now, calendar: cal).zones, sampled)
        XCTAssertEqual(ProgressDevelopment.zonesResolved(sampled: nil, rides: hr, ftpKnown: false, hrZonesKnown: false, now: now, calendar: cal).zones, z)
        let bare = [ride(2, zones: [0, 0, 0, 0, 0, 0, 0])]
        let none = ProgressDevelopment.zonesResolved(sampled: nil, rides: bare, ftpKnown: true, hrZonesKnown: true, now: now, calendar: cal)
        XCTAssertNil(none.zones); XCTAssertEqual(none.unavailable?.settings, []); XCTAssertTrue(none.unavailable?.text.contains("no per-second power or heart-rate samples") == true)
        var withPower = ride(2, zones: [0, 0, 0, 0, 0, 0, 0]); withPower.samples = (1...60).map { RideRecord.Sample(t: $0, w: 180) }
        XCTAssertEqual(ProgressDevelopment.zonesUnavailable(rides: [withPower], ftpKnown: false, hrZonesKnown: true, now: now, calendar: cal)?.settings, [.power])
        XCTAssertEqual(ProgressDevelopment.zonesUnavailable(rides: [withPower], ftpKnown: false, hrZonesKnown: false, now: now, calendar: cal)?.settings, [.power, .heartRate])
        var withHR = ride(2, zones: [0, 0, 0, 0, 0, 0, 0]); withHR.samples = (1...60).map { RideRecord.Sample(t: $0, hr: 130) }
        XCTAssertEqual(ProgressDevelopment.zonesUnavailable(rides: [withHR], ftpKnown: true, hrZonesKnown: false, now: now, calendar: cal)?.settings, [.heartRate])
        XCTAssertNil(ProgressDevelopment.zonesUnavailable(rides: [], ftpKnown: false, hrZonesKnown: false, now: now, calendar: cal), "no rides: nothing to explain")
        XCTAssertEqual(ProgressDevelopment.zoneTime(59), "0 min"); XCTAssertEqual(ProgressDevelopment.zoneTime(34_800), "9 h 40")

        // strength: one logged session is said, not hidden and not called development
        XCTAssertNotNil(ProgressDevelopment.strengthPending(lifts: [], sessions: 1))
        XCTAssertNil(ProgressDevelopment.strengthPending(lifts: [], sessions: 0))
    }
}
