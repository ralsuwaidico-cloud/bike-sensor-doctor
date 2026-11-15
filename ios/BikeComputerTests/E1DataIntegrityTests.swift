import XCTest
@testable import BikeComputer

/// E1 data integrity (owner authorization 15 Nov 2026). Foundation only, so the same file runs in the fast Linux logic
/// tests and in the iOS unit tests. Every fixture is synthetic and lives in a temporary directory.
final class E1DataIntegrityTests: XCTestCase {
    private func tmp(_ tag: String) -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("e1-\(tag)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private func files(_ d: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: d.path)) ?? []).sorted() }
    private func json(_ d: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: d.appendingPathComponent("store.json"))) as? [String: Any])
    }
    /// A healthy store written by the current code: an onboarded athlete with two strength sessions and a plan.
    private func healthy(_ tag: String) -> (Store, URL) {
        let d = tmp(tag); let s = Store(directory: d)
        s.profile.name = "E1 Fixture"; s.onboarded = true
        XCTAssertTrue(s.addStrength(StrengthSession(date: Date().addingTimeInterval(-3 * 86_400), minutes: 30, focus: .fullBody)))
        XCTAssertTrue(s.addStrength(StrengthSession(date: Date().addingTimeInterval(-1 * 86_400), minutes: 40, focus: .upper)))
        return (s, d)
    }

    // MARK: first launch and repeated launches
    func testAFirstTimeAthleteIsNeverShownTheRecoveryScreen() throws {
        let d = tmp("first"); let s = Store(directory: d)
        XCTAssertEqual(s.storage, .ok); XCTAssertNil(s.storageNotice); XCTAssertNil(s.lastSaveError)
        XCTAssertFalse(s.onboarded, "a new athlete starts in onboarding")
        XCTAssertTrue(files(d).contains("store.json")); XCTAssertEqual(files(d).filter { $0 != "store.json" }, [], "no recovery file on a clean install")
        let again = Store(directory: d)
        XCTAssertEqual(again.storage, .ok); XCTAssertNil(again.storageNotice)
    }
    func testThePreviousCopyFollowsEachLaunchAndSurvivesAFailedWrite() throws {
        let (_, d) = healthy("prevroll"); let prev = d.appendingPathComponent(StoreRecovery.previousName), cur = d.appendingPathComponent("store.json")
        let launch1 = try Data(contentsOf: cur)
        let a = Store(directory: d)
        XCTAssertTrue(a.addStrength(StrengthSession(date: Date().addingTimeInterval(-5 * 86_400), minutes: 20, focus: .push)))
        XCTAssertEqual(try Data(contentsOf: prev), launch1, "the copy is the file as this launch found it")
        XCTAssertTrue(a.addStrength(StrengthSession(date: Date().addingTimeInterval(-6 * 86_400), minutes: 20, focus: .pull)))
        XCTAssertEqual(try Data(contentsOf: prev), launch1, "taken once per launch, not at every write")
        let launch2 = try Data(contentsOf: cur)
        let b = Store(directory: d, generatePlan: false)                 // a launch that writes nothing
        XCTAssertEqual(b.persistCount, 0); XCTAssertEqual(try Data(contentsOf: prev), launch1, "a launch without a write does not move the copy")
        let c = Store(directory: d, generatePlan: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: d.path)
        let failed = !c.addStrength(StrengthSession(date: Date().addingTimeInterval(-8 * 86_400), minutes: 20, focus: .legs))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: d.path)
        if failed {
            XCTAssertEqual(try Data(contentsOf: prev), launch1, "a failed write changes neither the store nor its previous copy")
            XCTAssertEqual(try Data(contentsOf: cur), launch2)
        }
        guard case .ok = StoreRecovery.load(prev) else { return XCTFail("the previous copy must always be a readable store") }
    }

    // MARK: unreadable store
    func testUnreadableStoreIsLeftUntouchedCopiedAndNeverWritten() throws {
        let (_, d) = healthy("unreadable"); let url = d.appendingPathComponent("store.json")
        let full = try Data(contentsOf: url); let bad = Data(full.prefix(full.count / 2))
        try bad.write(to: url)
        let s = Store(directory: d)
        XCTAssertEqual(s.storage, .unreadable)
        XCTAssertFalse(s.onboarded, "nothing from the unreadable file is invented")
        XCTAssertEqual(s.persistCount, 0, "no write during launch")
        s.settings.keepScreenOn.toggle(); s.profile.name = "someone else"; s.ensurePlan()
        XCTAssertFalse(s.addStrength(StrengthSession(date: Date(), minutes: 20, focus: .fullBody)), "a save in this state is reported as not saved")
        XCTAssertNotNil(s.saveFailure)
        XCTAssertEqual(try Data(contentsOf: url), bad, "store.json is byte for byte what it was")
        let copies = files(d).filter { $0.hasPrefix("store.unreadable-") }
        XCTAssertEqual(copies.count, 1, "one copy kept: \(files(d))")
        XCTAssertEqual(try Data(contentsOf: d.appendingPathComponent(copies[0])), bad)
        _ = Store(directory: d)                                          // a second launch does not pile up copies
        XCTAssertEqual(files(d).filter { $0.hasPrefix("store.unreadable-") }.count, 1)
    }
    func testRestorePreviousCopyBringsBackTheLastGoodLaunch() throws {
        let (_, d) = healthy("restore"); let url = d.appendingPathComponent("store.json")
        let s2 = Store(directory: d)                                     // second launch: previous copy is taken at its first write
        XCTAssertTrue(s2.addStrength(StrengthSession(date: Date(), minutes: 25, focus: .lower)))
        XCTAssertTrue(files(d).contains(StoreRecovery.previousName), "\(files(d))")
        try Data("not a store file".utf8).write(to: url)
        let s3 = Store(directory: d)
        XCTAssertEqual(s3.storage, .unreadable); XCTAssertTrue(s3.canRestorePreviousCopy)
        XCTAssertTrue(s3.restorePreviousCopy())
        XCTAssertEqual(s3.storage, .ok); XCTAssertEqual(s3.profile.name, "E1 Fixture")
        XCTAssertEqual(s3.strength.count, 2, "the state before the second launch's first write (the third session came after the copy)")
        XCTAssertTrue(s3.addStrength(StrengthSession(date: Date().addingTimeInterval(-7200), minutes: 15, focus: .pull)), "writes work again")
        XCTAssertEqual(Store(directory: d, generatePlan: false).strength.count, 3)
        XCTAssertFalse(files(d).filter { $0.hasPrefix("store.unreadable-") }.isEmpty, "the unreadable file is still kept")
    }
    func testADamagedPrimaryNeverReplacesThePreviousCopy() throws {
        let (_, d) = healthy("prevsafe"); let url = d.appendingPathComponent("store.json")
        let s2 = Store(directory: d); s2.settings.keepScreenOn.toggle()
        let prev = try Data(contentsOf: d.appendingPathComponent(StoreRecovery.previousName))
        try Data("garbage".utf8).write(to: url)
        let s3 = Store(directory: d); s3.settings.keepScreenOn.toggle()
        XCTAssertEqual(try Data(contentsOf: d.appendingPathComponent(StoreRecovery.previousName)), prev)
    }
    func testStartFreshKeepsTheUnreadableFile() throws {
        let (_, d) = healthy("fresh"); let url = d.appendingPathComponent("store.json")
        let bad = Data("a store cut off in the middle".utf8); try bad.write(to: url)
        let s = Store(directory: d)
        XCTAssertTrue(s.startFreshAfterUnreadableStore())
        XCTAssertEqual(s.storage, .ok); XCTAssertFalse(s.onboarded)
        let copies = files(d).filter { $0.hasPrefix("store.unreadable-") }
        XCTAssertEqual(copies.count, 1); XCTAssertEqual(try Data(contentsOf: d.appendingPathComponent(copies[0])), bad)
        XCTAssertEqual(Store(directory: d, generatePlan: false).storage, .ok, "the new store.json is readable")
    }

    // MARK: one bad record
    func testOneBadRecordInAnyListKeepsItsNeighboursAndIsSetAside() throws {
        let (s0, d0) = healthy("lists")
        let base = try json(d0)
        for key in ["plan", "rides", "strength", "templates", "appliedProposals", "adaptations", "adaptiveProposals", "painClearances", "trash", "planVersions", "boardSync"] {
            var o = base; var arr = (o[key] as? [Any]) ?? []; let valid = arr.count
            arr.insert(["id": "E1-BAD-RECORD", "date": "not-a-date", "minutes": "thirty"] as [String: Any], at: 0); o[key] = arr
            let d = tmp("list-\(key)"); try JSONSerialization.data(withJSONObject: o).write(to: d.appendingPathComponent("store.json"))
            let s = Store(directory: d, generatePlan: false)
            XCTAssertEqual(s.storage, .ok, key); XCTAssertEqual(s.profile.name, "E1 Fixture", key)
            XCTAssertEqual(s.strength.count, s0.strength.count, "\(key): strength history intact")
            XCTAssertGreaterThanOrEqual(s.plan.count, s0.plan.count, "\(key): plan intact")
            let n: Int
            switch key {
            case "plan": n = s.plan.count; case "rides": n = s.rides.count; case "strength": n = s.strength.count; case "templates": n = s.templates.count
            case "appliedProposals": n = s.appliedProposals.count; case "adaptations": n = s.adaptations.count; case "adaptiveProposals": n = s.adaptiveProposals.count
            case "painClearances": n = s.painClearances.count; case "trash": n = s.trash.count; case "planVersions": n = s.planVersions.count; default: n = s.boardSync.count
            }
            XCTAssertEqual(n, valid, "\(key): every valid record kept, the bad one skipped")
            let q = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: d.appendingPathComponent(StoreRecovery.quarantineName))) as? [[String: Any]], "\(key): quarantine file")
            XCTAssertEqual(q.count, 1, key); XCTAssertEqual(q.first?["list"] as? String, key)
            XCTAssertEqual((q.first?["record"] as? [String: Any])?["id"] as? String, "E1-BAD-RECORD", "\(key): the raw record is kept")
            XCTAssertTrue(s.migrationLog.contains { $0.contains("set aside") }, "\(key): the athlete is told")
            XCTAssertTrue(files(d).contains(StoreRecovery.previousName), "\(key): the file as it was is kept as the previous copy")
        }
    }
    func testAHealthyStoreProducesNoQuarantineAndNoLaunchWrite() throws {
        let (_, d) = healthy("clean")
        let s = Store(directory: d, generatePlan: false)
        XCTAssertEqual(s.persistCount, 0); XCTAssertNil(s.storageNotice)
        XCTAssertFalse(files(d).contains(StoreRecovery.quarantineName), "\(files(d))")
    }
    func testPlanThatIsNotAListIsAnUnreadableStoreNotAnEmptyPlan() throws {
        let (_, d) = healthy("notalist"); var o = try json(d); o["plan"] = "corrupted"
        try JSONSerialization.data(withJSONObject: o).write(to: d.appendingPathComponent("store.json"))
        XCTAssertEqual(Store(directory: d).storage, .unreadable)
    }

    // MARK: newer and unknown
    func testNewerSchemaIsReadOnly() throws {
        let (_, d) = healthy("newer"); var o = try json(d); o["schema"] = StoreFile.currentSchema + 1; o["futureField"] = ["kept": true]
        let data = try JSONSerialization.data(withJSONObject: o); let url = d.appendingPathComponent("store.json"); try data.write(to: url)
        let s = Store(directory: d)
        XCTAssertEqual(s.storage, .newerVersion(StoreFile.currentSchema + 1))
        s.profile.name = "changed"; s.ensurePlan()
        XCTAssertFalse(s.addStrength(StrengthSession(date: Date(), minutes: 20, focus: .fullBody)))
        XCTAssertEqual(try Data(contentsOf: url), data, "a newer store is never written by this build")
    }
    func testUnknownFieldsOfTheSameSchemaSurviveASave() throws {
        let (_, d) = healthy("unknown"); var o = try json(d); o["mainSport"] = "roadCycling"; o["futureBlock"] = ["kept": true, "n": 3] as [String: Any]
        try JSONSerialization.data(withJSONObject: o).write(to: d.appendingPathComponent("store.json"))
        let s = Store(directory: d, generatePlan: false)
        XCTAssertEqual(s.storage, .ok)
        XCTAssertTrue(s.addStrength(StrengthSession(date: Date(), minutes: 20, focus: .fullBody)))
        let after = try json(d)
        XCTAssertEqual(after["mainSport"] as? String, "roadCycling")
        XCTAssertEqual((after["futureBlock"] as? [String: Any])?["n"] as? Int, 3)
        XCTAssertEqual(after["schema"] as? Int, StoreFile.currentSchema)
        let again = Store(directory: d, generatePlan: false)
        XCTAssertEqual(again.strength.count, 3); XCTAssertEqual(again.profile.name, "E1 Fixture")
    }

    // MARK: saves
    func testOneSaveIsOneWrite() throws {
        let (_, d) = healthy("writes"); let s = Store(directory: d)
        let before = s.persistCount
        XCTAssertTrue(s.addStrength(StrengthSession(date: Date(), minutes: 30, focus: .fullBody)))
        XCTAssertEqual(s.persistCount - before, 1, "E0 run 225 counted six full-file writes for one save")
    }
    func testADuplicateIsRefusedWithoutBeingCalledAFailure() throws {
        let (s, _) = healthy("dup")
        let x = StrengthSession(date: Date(), minutes: 30, focus: .fullBody)
        XCTAssertTrue(s.addStrength(x)); XCTAssertFalse(s.addStrength(x))
        XCTAssertNil(s.saveFailure, "a duplicate is not a storage failure")
    }
    func testAFailedWriteRollsBackSoMemoryEqualsDiskAndRetryIsNotADuplicate() throws {
        let (s, d) = healthy("failed"); let url = d.appendingPathComponent("store.json")
        let before = try Data(contentsOf: url), count = s.strength.count, plan = s.plan
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: d.path)
        try? FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        let x = StrengthSession(date: Date(), minutes: 30, focus: .fullBody)
        let saved = s.addStrength(x)
        let after = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: d.path); try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        if after != before { throw XCTSkip("this environment let the write through despite read-only permissions (for example when running as root)") }
        XCTAssertFalse(saved); XCTAssertNotNil(s.saveFailure)
        XCTAssertEqual(s.strength.count, count, "the session is not shown as stored"); XCTAssertEqual(s.plan, plan, "no planned session was marked done")
        XCTAssertTrue(s.addStrength(x), "the same session can be saved again once storage works"); XCTAssertNil(s.saveFailure)
        XCTAssertEqual(Store(directory: d, generatePlan: false).strength.count, count + 1, "saved exactly once")
    }

    // MARK: delete all data
    func testDeleteAllDataRemovesTheSafetyCopiesToo() throws {
        let (_, d) = healthy("delete")
        var o = try json(d); var arr = (o["strength"] as? [Any]) ?? []; arr.append(["id": "bad"] as [String: Any]); o["strength"] = arr
        try JSONSerialization.data(withJSONObject: o).write(to: d.appendingPathComponent("store.json"))
        let s = Store(directory: d); s.settings.keepScreenOn.toggle()
        XCTAssertTrue(files(d).contains(StoreRecovery.quarantineName)); XCTAssertTrue(files(d).contains(StoreRecovery.previousName))
        s.resetAll()
        XCTAssertEqual(files(d).filter { $0 != "store.json" }, [], "nothing with the athlete's data is left beside the new empty store: \(files(d))")
        XCTAssertFalse(Store(directory: d, generatePlan: false).onboarded)
    }
}
