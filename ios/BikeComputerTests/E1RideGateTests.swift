import XCTest
import CoreLocation
@testable import BikeComputer

extension RideRecorder {
    /// E1 (owner decision 16 Nov 2026): a ride now starts only for an athlete whose training status can be read and is
    /// allowed, and a phone ride only with location permission. Before that decision a bare recorder with no athlete
    /// and no permission could start a ride; the tests that relied on it are about something else (timing, ownership,
    /// samples), so they now state both conditions explicitly. None of their assertions changed.
    static func allowedForTests() -> RideRecorder {
        let r = RideRecorder(autoTick: false); r.trainingAuthority = { .allowed }; r.gpsAuthorized = { true }; return r
    }
}

/// E1 ride-start authorization (owner decisions 15–16 Nov 2026). Every route that can start a ride (Ride screen, Plan,
/// Apple Watch, Cyclift Watch) calls `RideRecorder.startMode()` and, for a phone ride, `start()`; those two are tested
/// here against a real athlete record. What these tests cover: the recorder and the Store (UNDERLYING DATA AND LOGIC, in
/// the simulator). What they do not cover: the four screens and watch links that call it (read in source only), and any
/// physical device.
final class E1RideGateTests: XCTestCase {
    private func tmp(_ tag: String) -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("e1g-\(tag)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private func setHold(_ s: Store, _ on: Bool) {
        var p = s.profile; var h = HealthScreen(); h.answeredAt = Date().addingTimeInterval(-3600); h.chestPain = on; p.healthScreen = h; s.profile = p
    }
    /// Wired exactly as the app wires it (BikeComputerApp): the status is read from the store at each request.
    private func recorder(_ s: Store, gps: Bool = true) -> RideRecorder {
        let r = RideRecorder(autoTick: false); r.trainingAuthority = { [weak s] in s?.trainingAuthority ?? .unavailable }; r.gpsAuthorized = { gps }; return r
    }
    private func frame(_ rideId: Int, _ state: BCLink.RideState, _ elapsed: Int) -> BCLink.Live {
        var l = BCLink.Live(); l.rideId = rideId; l.rideState = state; l.elapsedS = elapsed; l.distanceM = elapsed * 8; l.powerW = 180; l.cadenceRpm = 85; l.hrBpm = 140
        return l
    }

    func testTheHoldIsReadAtTheMomentOfEachRequestInAndOutWithNoTimerInBetween() {
        let s = Store(directory: tmp("inout"), generatePlan: false); let r = recorder(s)
        XCTAssertEqual(r.startMode(), .phone)
        setHold(s, true)                                                 // no tick, no timer: the very next request sees it
        XCTAssertEqual(r.startMode(), .blockedByHealthHold)
        XCTAssertFalse(r.start(), "the phone ride is refused"); XCTAssertFalse(r.isActive)
        XCTAssertEqual(r.note, RideRecorder.holdNote, "and the refusal says why")
        setHold(s, false)
        XCTAssertEqual(r.startMode(), .phone, "out of the hold: the very next request")
        XCTAssertTrue(r.start(), "a ride starts as before"); r.pause(); r.end(); r.finish()
        setHold(s, true)
        XCTAssertEqual(r.startMode(), .blockedByHealthHold, "and into a hold again between two rides"); XCTAssertFalse(r.start())
    }
    func testAHoldAppliesImmediatelyAfterLaunch() {
        let d = tmp("launch"); let first = Store(directory: d, generatePlan: false); setHold(first, true)
        let s = Store(directory: d, generatePlan: false)                 // the next launch
        let r = recorder(s)                                              // nothing has ticked yet
        XCTAssertEqual(r.startMode(), .blockedByHealthHold); XCTAssertFalse(r.start()); XCTAssertFalse(r.isActive)
    }
    func testAnUnreadableOrUnwiredStatusNeverStartsARide() throws {
        let bare = RideRecorder(autoTick: false); bare.gpsAuthorized = { true }
        XCTAssertEqual(bare.startMode(), .blockedStatusUnavailable, "no athlete record wired: fail closed")
        XCTAssertFalse(bare.start()); XCTAssertEqual(bare.note, RideRecorder.statusNote)
        let d = tmp("unreadable"); _ = Store(directory: d, generatePlan: false)
        try Data("not a store".utf8).write(to: d.appendingPathComponent("store.json"))
        let s = Store(directory: d, generatePlan: false); let r = recorder(s)
        XCTAssertEqual(s.storage, .unreadable)
        XCTAssertEqual(r.startMode(), .blockedStatusUnavailable, "an athlete record that cannot be read: fail closed")
        XCTAssertFalse(r.start()); XCTAssertFalse(r.isActive)
    }
    func testAPhoneRideNeedsLocationPermissionAndSaysSo() {
        let s = Store(directory: tmp("gps"), generatePlan: false)
        var allowed = false
        let r = RideRecorder(autoTick: false); r.trainingAuthority = { [weak s] in s?.trainingAuthority ?? .unavailable }; r.gpsAuthorized = { allowed }
        XCTAssertEqual(r.startMode(), .blockedNoGPSPermission)
        XCTAssertFalse(r.start(), "no phone-GPS ride without location permission"); XCTAssertFalse(r.isActive)
        XCTAssertEqual(r.note, RideRecorder.locationNote, "the refusal names the permission")
        allowed = true
        XCTAssertEqual(r.startMode(), .phone); XCTAssertTrue(r.start()); r.pause(); r.end()
        // the hold outranks the permission question
        let h = Store(directory: tmp("gps-hold"), generatePlan: false); setHold(h, true)
        XCTAssertEqual(recorder(h, gps: false).startMode(), .blockedByHealthHold)
    }
    func testARideBegunOnTheBikeComputerDuringAHoldIsRecordedMarkedAndCompletesNothing() {
        let s = Store(directory: tmp("external"), generatePlan: false); setHold(s, true)
        let today = Calendar.current.startOfDay(for: Date())
        s.plan = [Workout(date: today.addingTimeInterval(12 * 3600), kind: .endurance, minutes: 60)]
        let r = recorder(s, gps: false)                                  // and no phone location: the recording is still kept
        r.adoptBoardForTests(frame(7, .running, 1)); r.adoptBoardForTests(frame(7, .running, 2))
        XCTAssertEqual(r.owner, .board); XCTAssertTrue(r.isActive, "the device's ride is mirrored, not refused")
        XCTAssertTrue(r.externalDuringHold); XCTAssertEqual(r.note, RideRecorder.externalHoldNote, "the phone says what this recording is as soon as it sees it")
        XCTAssertEqual(r.startMode(), .blockedByHealthHold, "and still starts nothing itself")
        r.adoptBoardForTests(frame(7, .ended, 2))
        guard let rec = r.pendingResult else { return XCTFail("the ended device ride is offered for review") }
        XCTAssertEqual(rec.startedExternallyDuringHealthHold, true)
        XCTAssertEqual(rec.recorder, .board); XCTAssertEqual(rec.boardRideId, 7); XCTAssertEqual(rec.durationS, 2); XCTAssertEqual(rec.distanceM, 16)
        XCTAssertEqual(rec.samples.map(\.w), [180, 180], "measurements exactly as received"); XCTAssertEqual(rec.samples.map(\.hr), [140, 140])
        XCTAssertTrue(rec.samples.allSatisfy { $0.lat == nil && $0.lon == nil }, "no route is invented without phone GPS")
        XCTAssertFalse(rec.sources.contains("Phone GPS"), "and the record does not claim a GPS source")
        XCTAssertTrue(s.addRide(rec), "the athlete can keep it")
        XCTAssertEqual(s.rides.count, 1); XCTAssertFalse(s.plan.contains { $0.done }, "no planned session is completed"); XCTAssertNil(s.ftpSuggestion)
        r.finish()
        XCTAssertEqual(r.state, .idle, "nothing else is started by saving it"); XCTAssertFalse(r.isActive); XCTAssertFalse(r.externalDuringHold)
    }
    func testADeviceRideWithoutAHoldIsNotMarkedAndTheNextRideIsJudgedOnItsOwn() {
        let s = Store(directory: tmp("external-free"), generatePlan: false); let r = recorder(s)
        r.adoptBoardForTests(frame(8, .running, 1)); r.adoptBoardForTests(frame(8, .ended, 1))
        XCTAssertNil(r.pendingResult?.startedExternallyDuringHealthHold, "no hold: no marker (absence = unknown)")
        XCTAssertFalse(r.externalDuringHold)
        r.finish(); r.adoptBoardForTests(frame(8, .idle, 0))
        setHold(s, true)
        r.adoptBoardForTests(frame(9, .running, 1)); r.adoptBoardForTests(frame(9, .ended, 1))
        XCTAssertEqual(r.pendingResult?.boardRideId, 9); XCTAssertEqual(r.pendingResult?.startedExternallyDuringHealthHold, true, "a later ride during a hold is marked")
    }
}

/// E1-F3: the phone ride's sample count with a clock the test controls. The existing RideRegression test is unchanged; it
/// still runs against the real clock.
final class E1RideClockTests: XCTestCase {
    private func fix(_ i: Int, at t: Date) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: 24.45 + Double(i) * 0.0001, longitude: 54.38), altitude: 12, horizontalAccuracy: 5, verticalAccuracy: 8, course: 0, speed: 8.33, timestamp: t)
    }
    func testFiveTicksAreFiveSamplesHoweverSlowTheMachineIs() {
        let loc = LocationService(); let r = RideRecorder.allowedForTests(); r.location = loc
        var t = Date(timeIntervalSince1970: 1_800_000_000); r.clock = { t }
        XCTAssertTrue(r.start())
        Thread.sleep(forTimeInterval: 1.6)                              // real time passing must not matter
        for i in 0..<5 { t = t.addingTimeInterval(1); loc.injectForTests(fix(i, at: t)); r.tick() }
        XCTAssertEqual(r.samples.count, 5); XCTAssertEqual(r.gapSeconds, 0)
        XCTAssertEqual(r.samples.compactMap(\.lat).count, 5, "every route fix is kept")
    }
    func testAGapInTheClockIsRecordedAsGapSamplesNeverAsInventedData() {
        let loc = LocationService(); let r = RideRecorder.allowedForTests(); r.location = loc
        var t = Date(timeIntervalSince1970: 1_800_000_000); r.clock = { t }
        XCTAssertTrue(r.start())
        t = t.addingTimeInterval(1); loc.injectForTests(fix(0, at: t)); r.tick()
        t = t.addingTimeInterval(6); loc.injectForTests(fix(1, at: t)); r.tick()          // five seconds were not observed
        XCTAssertEqual(r.gapSeconds, 5); XCTAssertEqual(r.samples.count, 7)
        XCTAssertEqual(r.samples.filter { $0.gap == true }.count, 5)
        XCTAssertTrue(r.samples.filter { $0.gap == true }.allSatisfy { $0.lat == nil && $0.speedCms == nil }, "a gap sample carries no position or speed")
        XCTAssertEqual(r.samples.compactMap(\.lat).count, 2)
    }
}
