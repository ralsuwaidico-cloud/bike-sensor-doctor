import XCTest
@testable import BikeComputer

/// APP-010 / APP-011 end-to-end data chain: a recorded ride is saved → it completes today's planned ride → the results
/// model shows measured values only → a 20-minute best proposes an FTP that changes NOTHING until accepted → accepting
/// records source + date (estimate, or tested on a planned test with verified power) → the check-in is stored on the
/// ride and feeds the adaptive coach → everything survives a relaunch. No UI, no simulator: Store + models.
final class RideChainTests: XCTestCase {
    private func dir() -> URL { let d = FileManager.default.temporaryDirectory.appendingPathComponent("chain-\(UUID().uuidString)"); try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d }
    private func day(_ sport: DayAssignment.Sport?, _ minutes: Int = 0) -> DayAvailability { sport.map { DayAvailability(assignments: [DayAssignment(sport: $0, minutes: minutes)]) } ?? DayAvailability(activity: .rest, minutes: 0) }

    /// 50 minutes of power: a 20-minute block at `block` W inside easier riding, 1 Hz samples.
    private func ride(start: Date, block: Int, verified: Bool? = true) -> RideRecord {
        var r = RideRecord(start: start, durationS: 3000, distanceM: 24_000, recorder: .phone, sources: ["Phone GPS", "Power meter"])
        r.samples = (1...3000).map { t in RideRecord.Sample(t: t, w: (900..<2100).contains(t) ? block : 150, hr: 120 + (t % 30)) }
        r.avgPower = r.samples.compactMap(\.w).reduce(0, +) / 3000; r.maxPower = block; r.avgHR = 135; r.maxHR = 149
        r.powerVerified = verified
        return r
    }

    func testRideToResultsToFTPToCheckInSurvivesRelaunch() {
        let d = dir(); let s = Store(directory: d, generatePlan: false)
        var p = RiderProfile.screened(); p.name = "Rashed"; p.trainingMode = .cycling; p.hoursPerWeek = 5; p.weekIsExplicit = true; p.setFTP(230, source: .entered); s.profile = p
        let cal = Calendar.current; let today = cal.startOfDay(for: Date())
        s.availability = WeeklyAvailability(days: (0..<7).map { _ in day(.cycling, 60) })
        _ = s.regenerate(weekOf: TrainingLedger.monday(of: today), replaceEdited: true)
        let planned = s.plan.first { cal.isDateInToday($0.date) && $0.kind.isRide }
        XCTAssertNotNil(planned, "a cycling-only athlete with every day available has a ride planned today")
        XCTAssertEqual(planned?.done, false)

        // 1. the ride is saved: one record, the planned ride completed, the ledger agrees
        let start = cal.date(byAdding: .hour, value: 7, to: today)!
        let r = ride(start: start, block: 270)
        XCTAssertTrue(s.addRide(r)); XCTAssertEqual(s.rides.count, 1)
        XCTAssertEqual(s.plan.first { $0.id == planned!.id }?.done, true, "the ride completes today's planned ride")
        XCTAssertTrue(s.ledger.status(s.plan.first { $0.id == planned!.id }!).isCompleted)
        XCTAssertFalse(s.addRide(r), "the same ride cannot be saved twice")

        // 2. results are measured values with sources, nothing estimated
        let saved = s.rides[0]
        XCTAssertEqual(saved.best20, 270, "the 20-minute best is the measured block")
        XCTAssertEqual(saved.avgHR, 135); XCTAssertEqual(saved.durationS, 3000); XCTAssertEqual(saved.distanceM, 24_000)
        XCTAssertNotNil(RidePerformanceModel.normalizedPower(saved.samples.compactMap(\.w)))

        // 3. a better 20-minute effort proposes an FTP but changes nothing until accepted
        let sug = try! XCTUnwrap(s.ftpSuggestion)
        XCTAssertEqual(sug.watts, Store.proposedFTP(best20: 270)); XCTAssertEqual(sug.watts, 257); XCTAssertEqual(sug.previousFTP, 230); XCTAssertEqual(sug.rideId, saved.id)
        XCTAssertEqual(s.profile.ftpW, 230, "the suggestion never changes the FTP by itself"); XCTAssertEqual(s.profile.ftpHow, .entered)
        XCTAssertEqual(sug.powerVerified, true); XCTAssertEqual(sug.testProtocol, false, "not a planned FTP test → an estimate, never 'tested'")
        s.acceptFTPSuggestion()
        XCTAssertEqual(s.profile.ftpW, 257); XCTAssertEqual(s.profile.ftpHow, .fromRides); XCTAssertNil(s.ftpSuggestion)
        XCTAssertEqual(s.profile.provenance(.ftp).source, .estimatedFromRides); XCTAssertEqual(s.profile.provenance(.ftp).recordedAt, start, "source and date move with the value")
        XCTAssertEqual(s.profile.ftpVerifiedTest, false)

        // 4. a small change (< 2 %) proposes nothing; a ride without power proposes nothing
        XCTAssertTrue(s.addRide(ride(start: start.addingTimeInterval(86_400), block: 272)))
        XCTAssertNil(s.ftpSuggestion, "272 W → 258 W is under 2 % of 257 W: no proposal")
        var noPower = RideRecord(start: start.addingTimeInterval(2 * 86_400), durationS: 1800, distanceM: 9000, recorder: .phone, sources: ["Phone GPS"])
        noPower.samples = (1...1800).map { RideRecord.Sample(t: $0, w: nil) }
        XCTAssertTrue(s.addRide(noPower)); XCTAssertNil(s.ftpSuggestion); XCTAssertNil(s.rides[0].best20)

        // 5. the check-in is stored on the ride and reaches the adaptive coach
        let c = CheckIn(performance: 8, effort: 7, at: start.addingTimeInterval(3600))
        _ = s.recordCheckIn(c, rideId: saved.id, now: start.addingTimeInterval(3600))
        XCTAssertEqual(s.rides.first { $0.id == saved.id }?.checkIn, c)
        XCTAssertNil(s.recordCheckIn(c, rideId: UUID()), "a check-in for an unknown ride is refused")

        // 6. relaunch: ride, check-in, FTP (value + source + date), completed plan all identical
        let again = Store(directory: d, generatePlan: false)
        XCTAssertEqual(again.rides, s.rides); XCTAssertEqual(again.rides.first { $0.id == saved.id }?.checkIn, c)
        XCTAssertEqual(again.profile.ftpW, 257); XCTAssertEqual(again.profile.ftpHow, .fromRides); XCTAssertEqual(again.profile.provenance(.ftp).recordedAt, start)
        XCTAssertEqual(again.plan.first { $0.id == planned!.id }?.done, true)
    }

    func testPlannedFTPTestWithVerifiedPowerBecomesATestedFTPAndIsNeverReplacedSilently() {
        let s = Store(directory: dir(), generatePlan: false)
        var p = RiderProfile.screened(); p.trainingMode = .cycling; p.setFTP(230, source: .entered); s.profile = p
        let cal = Calendar.current; let start = cal.date(byAdding: .hour, value: 8, to: cal.startOfDay(for: Date()))!
        s.plan = [Workout(date: start, kind: .ftpTest, minutes: 60)]
        XCTAssertTrue(s.addRide(ride(start: start, block: 280, verified: true)))
        let sug = try! XCTUnwrap(s.ftpSuggestion); XCTAssertEqual(sug.testProtocol, true); XCTAssertEqual(sug.powerVerified, true)
        s.acceptFTPSuggestion()
        XCTAssertEqual(s.profile.ftpW, 266); XCTAssertEqual(s.profile.ftpHow, .tested); XCTAssertEqual(s.profile.ftpVerifiedTest, true)
        XCTAssertEqual(s.profile.provenance(.ftp).source, .measuredTest)
        // a later ordinary ride proposes an estimate — the tested value stays until the athlete accepts
        XCTAssertTrue(s.addRide(ride(start: start.addingTimeInterval(3 * 86_400), block: 300)))
        XCTAssertNotNil(s.ftpSuggestion); XCTAssertEqual(s.profile.ftpW, 266); XCTAssertEqual(s.profile.ftpHow, .tested)
        s.dismissFTPSuggestion(); XCTAssertNil(s.ftpSuggestion); XCTAssertEqual(s.profile.ftpW, 266)
        // unverified power on a planned test is an estimate, not a test
        let s2 = Store(directory: dir(), generatePlan: false); s2.profile = p; s2.plan = [Workout(date: start, kind: .ftpTest, minutes: 60)]
        XCTAssertTrue(s2.addRide(ride(start: start, block: 280, verified: false))); s2.acceptFTPSuggestion()
        XCTAssertEqual(s2.profile.ftpHow, .fromRides); XCTAssertEqual(s2.profile.ftpVerifiedTest, false)
    }
}
