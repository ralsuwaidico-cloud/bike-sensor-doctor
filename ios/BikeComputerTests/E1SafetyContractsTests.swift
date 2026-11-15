import XCTest
@testable import BikeComputer

/// E1 (owner decisions of 16 Nov 2026): ride authorization data rules, save consistency across the records that Plan,
/// Home, Progress and Coach read, and recovery. Foundation only, so the file runs in the fast Linux logic tests and in
/// the iOS unit tests. EVERY test here checks the UNDERLYING DATA (the Store and the files); none looks at a screen.
/// The screens read these same lists; screen-level coverage is listed as missing in the E1 dashboard.
final class E1SafetyContractsTests: XCTestCase {
    private func tmp(_ tag: String) -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("e1c-\(tag)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private func setHold(_ s: Store, _ on: Bool) {
        var p = s.profile; var h = HealthScreen(); h.answeredAt = Date().addingTimeInterval(-3600); h.chestPain = on; p.healthScreen = h; s.profile = p
    }
    /// A device ride of today with 22 minutes of power, so an unmarked copy of it WOULD propose an FTP.
    private func deviceRide(marked: Bool, boardRideId: Int = 41) -> RideRecord {
        var r = RideRecord(boardRideId: boardRideId, boardId: "test-board", start: today.addingTimeInterval(6 * 3600), durationS: 1320, distanceM: 9000, recorder: .board, sources: ["BikeComputer", "Power meter"])
        r.samples = (1...1320).map { RideRecord.Sample(t: $0, w: 250, cad: 88, hr: 141) }
        if marked { r.startedExternallyDuringHealthHold = true }
        return r
    }
    private func plannedRideToday() -> Workout { Workout(date: today.addingTimeInterval(7 * 3600), kind: .endurance, minutes: 60) }
    private func storeJSON(_ d: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: d.appendingPathComponent("store.json"))) as? [String: Any])
    }

    // MARK: A — a BikeComputer ride begun during a health hold (underlying data)
    func testADeviceRideBegunDuringAHoldIsKeptButCompletesNothingAndProposesNoFTP() throws {
        // control: the same ride without the marker completes the planned ride and proposes an FTP
        let c = Store(directory: tmp("ext-control"), generatePlan: false); c.plan = [plannedRideToday()]
        XCTAssertTrue(c.addRide(deviceRide(marked: false)))
        XCTAssertTrue(c.plan[0].done, "control: an ordinary ride completes the planned ride of its day")
        XCTAssertNotNil(c.ftpSuggestion, "control: an ordinary ride with 20 minutes of power proposes an FTP")

        // the marker alone decides (the hold may already be lifted when the athlete reviews and saves the ride)
        let d = tmp("ext"); let s = Store(directory: d, generatePlan: false); s.plan = [plannedRideToday()]
        let ride = deviceRide(marked: true)
        XCTAssertTrue(s.addRide(ride), "the recording is kept")
        XCTAssertEqual(s.rides.count, 1)
        XCTAssertEqual(s.rides[0].samples, ride.samples, "no measurement is altered"); XCTAssertEqual(s.rides[0].durationS, 1320); XCTAssertEqual(s.rides[0].distanceM, 9000)
        XCTAssertTrue(s.rides[0].samples.allSatisfy { $0.lat == nil && $0.lon == nil }, "no route is invented")
        XCTAssertFalse(s.plan.contains { $0.done }, "the planned session is not completed")
        XCTAssertNil(s.ftpSuggestion, "no FTP is proposed from it")
        XCTAssertNotNil(s.rides[0].restrictionNote, "the review screens have words for the restriction")
        // persistence: the marker survives a relaunch and is in the file an export is made from
        let again = Store(directory: d, generatePlan: false)
        XCTAssertEqual(again.rides.first?.startedExternallyDuringHealthHold, true)
        XCTAssertEqual(again.rides.first?.samples, ride.samples)
        XCTAssertFalse(again.plan.contains { $0.done })
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let exported = try enc.encode(again.snapshot)                           // what "Export your data" writes
        let rides = try XCTUnwrap((JSONSerialization.jsonObject(with: exported) as? [String: Any])?["rides"] as? [[String: Any]])
        XCTAssertEqual(rides.first?["startedExternallyDuringHealthHold"] as? Bool, true, "the marker is exported")
        guard case .ok(let back, _, _) = StoreRecovery.load(exported) else { return XCTFail("the exported file reads back") }
        XCTAssertEqual(back.rides.first?.startedExternallyDuringHealthHold, true, "and survives reading the export back")
    }
    func testAbsenceOfTheMarkerMeansUnknownAndIsNotWritten() throws {
        let d = tmp("nomark"); let s = Store(directory: d, generatePlan: false)
        XCTAssertTrue(s.addRide(deviceRide(marked: false)))
        XCTAssertNil(s.rides[0].startedExternallyDuringHealthHold, "unknown, not 'authorized'")
        XCTAssertNil(s.rides[0].restrictionNote)
        let rides = try XCTUnwrap(storeJSON(d)["rides"] as? [[String: Any]])
        XCTAssertNil(rides.first?["startedExternallyDuringHealthHold"], "an unmarked ride is stored exactly as before (no new key)")
    }
    func testAMarkedRideIsNeverEvidenceThatRidingIsGoingWell() {
        func ride(_ daysAgo: Int, marked: Bool) -> RideRecord {
            var r = RideRecord(start: today.addingTimeInterval(-Double(daysAgo) * 86_400 + 7 * 3600), durationS: 3600, distanceM: 25_000, recorder: .board, sources: ["BikeComputer"])
            r.checkIn = CheckIn(performance: 9, effort: 4, at: r.start)
            if marked { r.startedExternallyDuringHealthHold = true }
            return r
        }
        let now = today.addingTimeInterval(20 * 3600)
        let a = Store(directory: tmp("well-a"), generatePlan: false); a.rides = [ride(1, marked: false), ride(2, marked: false)]
        XCTAssertTrue(TrainingAnalyzer.analyze(a.adaptationInput(now: now)).cyclingImproving, "control: two good rated rides count")
        let b = Store(directory: tmp("well-b"), generatePlan: false); b.rides = [ride(1, marked: true), ride(2, marked: true)]
        XCTAssertFalse(TrainingAnalyzer.analyze(b.adaptationInput(now: now)).cyclingImproving, "rides begun during a hold are not progression evidence")
    }

    // MARK: B — the authoritative training status (underlying data; the recorder's use of it is tested on iOS)
    func testTrainingAuthorityIsReadFromTheAthleteRecordAtOnce() throws {
        let d = tmp("auth"); let s = Store(directory: d, generatePlan: false)
        XCTAssertEqual(s.trainingAuthority, .allowed)
        setHold(s, true);  XCTAssertEqual(s.trainingAuthority, .onHold, "into a hold: the very next read")
        setHold(s, false); XCTAssertEqual(s.trainingAuthority, .allowed, "out of a hold: the very next read")
        setHold(s, true)
        XCTAssertEqual(Store(directory: d, generatePlan: false).trainingAuthority, .onHold, "immediately after a launch, before any timer")
        try Data("not a store".utf8).write(to: d.appendingPathComponent("store.json"))
        XCTAssertEqual(Store(directory: d, generatePlan: false).trainingAuthority, .unavailable, "an athlete record that cannot be read is never 'allowed'")
    }

    // MARK: C — save consistency (underlying data)
    func testASuccessfulSaveCompletesTheMatchingPlannedSessionOnly() {
        let d = tmp("match"); let s = Store(directory: d, generatePlan: false)
        let tomorrow = Workout(date: today.addingTimeInterval(86_400 + 7 * 3600), kind: .endurance, minutes: 60)
        let rideToday = plannedRideToday(), lift = Workout(date: today.addingTimeInterval(17 * 3600), kind: .strength, minutes: 40)
        s.plan = [rideToday, lift, tomorrow]
        XCTAssertTrue(s.addRide(deviceRide(marked: false)))
        func w(_ st: Store, _ id: UUID) -> Workout? { st.plan.first { $0.id == id } }
        XCTAssertEqual(w(s, rideToday.id)?.done, true, "today's planned ride"); XCTAssertEqual(w(s, rideToday.id)?.completion, .recorded)
        XCTAssertEqual(w(s, tomorrow.id)?.done, false, "not tomorrow's"); XCTAssertEqual(w(s, lift.id)?.done, false, "not the lift")
        XCTAssertTrue(s.addStrength(StrengthSession(date: today.addingTimeInterval(17 * 3600), minutes: 40, focus: .fullBody)))
        XCTAssertEqual(w(s, lift.id)?.done, true, "the lift is completed by the lift"); XCTAssertEqual(w(s, tomorrow.id)?.done, false)
        let again = Store(directory: d, generatePlan: false)
        XCTAssertEqual(again.rides.count, 1); XCTAssertEqual(again.strength.count, 1)
        XCTAssertEqual(w(again, rideToday.id)?.done, true); XCTAssertEqual(w(again, lift.id)?.done, true); XCTAssertEqual(w(again, tomorrow.id)?.done, false)
        XCTAssertFalse(again.addRide(deviceRide(marked: false)), "the same device ride is not stored twice"); XCTAssertEqual(again.rides.count, 1)
    }
    func testAFailedSaveCompletesNothingAndLeavesNoRecordForAnyScreen() throws {
        let d = tmp("failsave"); let url = d.appendingPathComponent("store.json")
        let s = Store(directory: d, generatePlan: false)
        let rideToday = plannedRideToday(), lift = Workout(date: today.addingTimeInterval(17 * 3600), kind: .strength, minutes: 40)
        s.plan = [rideToday, lift]
        let disk = try Data(contentsOf: url), plan = s.plan
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: d.path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        let ride = deviceRide(marked: false), session = StrengthSession(date: today.addingTimeInterval(17 * 3600), minutes: 40, focus: .fullBody)
        let rideSaved = s.addRide(ride), rideFailure = s.saveFailure
        let liftSaved = s.addStrength(session), liftFailure = s.saveFailure
        let after = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: d.path); try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        if after != disk { throw XCTSkip("this environment let the write through despite read-only permissions (for example when running as root)") }
        XCTAssertFalse(rideSaved); XCTAssertNotNil(rideFailure, "the ride save says it failed")
        XCTAssertFalse(liftSaved); XCTAssertNotNil(liftFailure, "the strength save says it failed")
        // the lists every screen and the coach read: nothing was added, nothing completed, nothing proposed
        XCTAssertTrue(s.rides.isEmpty, "Home, Progress and Coach read this list: no ride in it")
        XCTAssertTrue(s.strength.isEmpty, "no strength session in it")
        XCTAssertEqual(s.plan, plan, "Plan: no planned session was completed"); XCTAssertFalse(s.plan.contains { $0.done })
        XCTAssertNil(s.ftpSuggestion, "no FTP proposal from an unsaved ride")
        let input = s.adaptationInput(); XCTAssertTrue(input.rides.isEmpty && input.strength.isEmpty, "the adaptive coach sees no unsaved session")
        // retry: one record each, the right planned sessions, and a second retry is refused as a duplicate
        XCTAssertTrue(s.addRide(ride)); XCTAssertTrue(s.addStrength(session)); XCTAssertNil(s.saveFailure)
        XCTAssertFalse(s.addRide(ride), "retrying again does not duplicate the ride"); XCTAssertNil(s.saveFailure, "a refused duplicate is not a failure")
        let again = Store(directory: d, generatePlan: false)
        XCTAssertEqual(again.rides.count, 1); XCTAssertEqual(again.strength.count, 1)
        XCTAssertEqual(again.plan.first { $0.id == rideToday.id }?.done, true); XCTAssertEqual(again.plan.first { $0.id == lift.id }?.done, true)
    }

    // MARK: recovery and the previous copy (underlying data)
    /// A store with history: one completed planned ride, one lift, one open planned session; then one more launch that
    /// writes, so the previous copy holds all of it.
    private func storeWithHistory(_ tag: String) -> (URL, UUID, UUID) {
        let d = tmp(tag); let s = Store(directory: d, generatePlan: false)
        let done = plannedRideToday(), open = Workout(date: today.addingTimeInterval(86_400 + 7 * 3600), kind: .endurance, minutes: 45)
        s.profile.name = "E1 Recovery"; s.plan = [done, open]
        XCTAssertTrue(s.addRide(deviceRide(marked: false)))
        XCTAssertTrue(s.addStrength(StrengthSession(date: today.addingTimeInterval(-86_400), minutes: 30, focus: .upper)))
        let s2 = Store(directory: d, generatePlan: false); s2.settings.keepScreenOn.toggle()      // next launch, first write: the copy is taken
        return (d, done.id, open.id)
    }
    func testRecoveryAfterAnInterruptedWriteRestoresHistoryAndSessionStatusAndCanBeRepeated() throws {
        let (d, doneId, openId) = storeWithHistory("recover"); let url = d.appendingPathComponent("store.json")
        for round in 1...2 {
            let full = try Data(contentsOf: url)
            try Data(full.prefix(full.count / 3)).write(to: url)            // a write that stopped part-way: the file is cut short
            let s = Store(directory: d, generatePlan: false)
            XCTAssertEqual(s.storage, .unreadable, "round \(round): a cut-short file is reported, never opened as an empty athlete")
            XCTAssertTrue(s.rides.isEmpty && s.persistCount == 0, "round \(round): nothing invented, nothing written")
            XCTAssertEqual(s.trainingAuthority, .unavailable)
            XCTAssertTrue(s.canRestorePreviousCopy); XCTAssertTrue(s.restorePreviousCopy(), "round \(round)")
            XCTAssertEqual(s.storage, .ok); XCTAssertEqual(s.profile.name, "E1 Recovery")
            XCTAssertEqual(s.rides.count, 1, "round \(round): the ride is back"); XCTAssertEqual(s.rides.first?.samples.count, 1320, "with its samples")
            XCTAssertEqual(s.strength.count, 1, "round \(round): the lift is back")
            XCTAssertEqual(s.plan.first { $0.id == doneId }?.done, true, "round \(round): the completed session is still completed")
            XCTAssertEqual(s.plan.first { $0.id == doneId }?.completion, .recorded)
            XCTAssertEqual(s.plan.first { $0.id == openId }?.done, false, "round \(round): the open session is still open")
            let relaunched = Store(directory: d, generatePlan: false)
            XCTAssertEqual(relaunched.storage, .ok); XCTAssertEqual(relaunched.rides.count, 1); XCTAssertEqual(relaunched.plan.first { $0.id == doneId }?.done, true)
        }
        XCTAssertFalse(((try? FileManager.default.contentsOfDirectory(atPath: d.path)) ?? []).filter { $0.hasPrefix("store.unreadable-") }.isEmpty, "the damaged file was kept")
    }
    func testAStalePreviousCopyIsReplacedByAFreshOneBeforeTheFirstWrite() throws {
        let (d, _, _) = storeWithHistory("stale"); let url = d.appendingPathComponent("store.json"), prev = d.appendingPathComponent(StoreRecovery.previousName)
        let empty = tmp("stale-src"); _ = Store(directory: empty, generatePlan: false)
        try Data(contentsOf: empty.appendingPathComponent("store.json")).write(to: prev)          // an old copy: a readable store with no history
        let asFound = try Data(contentsOf: url)
        let s = Store(directory: d, generatePlan: false); s.settings.keepScreenOn.toggle()
        XCTAssertEqual(try Data(contentsOf: prev), asFound, "the copy is made from the file as this launch found it, not trusted from before")
        try Data("damaged".utf8).write(to: url)
        let r = Store(directory: d, generatePlan: false)
        XCTAssertTrue(r.restorePreviousCopy()); XCTAssertEqual(r.rides.count, 1, "the restore brings back the history, not the stale empty copy")
    }
    func testAnUnreadablePreviousCopyIsNeverRestoredAndIsReplacedAtTheNextGoodLaunch() throws {
        let (d, _, _) = storeWithHistory("badprev"); let url = d.appendingPathComponent("store.json"), prev = d.appendingPathComponent(StoreRecovery.previousName)
        let good = try Data(contentsOf: url)
        try Data("not a store".utf8).write(to: prev)
        let damaged = Data(good.prefix(good.count / 2)); try damaged.write(to: url)
        let s = Store(directory: d, generatePlan: false)
        XCTAssertEqual(s.storage, .unreadable); XCTAssertFalse(s.canRestorePreviousCopy, "an unreadable copy is not offered")
        XCTAssertFalse(s.restorePreviousCopy()); XCTAssertEqual(s.storage, .unreadable)
        XCTAssertEqual(try Data(contentsOf: url), damaged, "and the damaged file is left exactly as it is")
        try good.write(to: url)                                                 // the primary is readable again
        let ok = Store(directory: d, generatePlan: false); XCTAssertEqual(ok.storage, .ok); ok.settings.keepScreenOn.toggle()
        guard case .ok = StoreRecovery.load(prev) else { return XCTFail("the next launch that writes replaces the unreadable copy with a readable one") }
        XCTAssertEqual(try Data(contentsOf: prev), good)
    }
    func testALeftoverPartialFileBesideAnIntactStoreChangesNothing() throws {
        let (d, doneId, _) = storeWithHistory("leftover")
        try Data("{\"schema\":4,\"rides\":[".utf8).write(to: d.appendingPathComponent("store.json.partial"))   // an interrupted write that never replaced the file
        let s = Store(directory: d, generatePlan: false)
        XCTAssertEqual(s.storage, .ok); XCTAssertEqual(s.rides.count, 1); XCTAssertEqual(s.plan.first { $0.id == doneId }?.done, true)
    }
}
