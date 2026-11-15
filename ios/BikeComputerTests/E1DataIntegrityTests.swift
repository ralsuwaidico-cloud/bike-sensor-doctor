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
        // Corrected after logic runs 81/82: my first version expected zero writes on the FIRST relaunch. That premise was
        // wrong — the baseline app writes one log line the first time an onboarded store is opened (the one-time W12
        // clean-up marker, Models.w12CleanupIfNeeded). That write is existing, intended behaviour; it is counted here
        // instead of being hidden, and "no write" is asserted for every launch after it.
        let first = Store(directory: d, generatePlan: false)
        XCTAssertLessThanOrEqual(first.persistCount, 1, "at most the one-time clean-up marker"); XCTAssertNil(first.storageNotice)
        let s = Store(directory: d, generatePlan: false)
        XCTAssertEqual(s.persistCount, 0); XCTAssertNil(s.storageNotice)
        XCTAssertFalse(files(d).contains(StoreRecovery.quarantineName), "\(files(d))")
    }
    /// What exactly does the one-time first-launch write change? (Owner question, 15 Nov.) It is NOT a separate log file:
    /// the baseline's one-time clean-up (Models.w12CleanupIfNeeded) appends its "done" line to `migrationLog`, which lives
    /// inside store.json, so the primary store is rewritten once through the normal atomic save. This test proves, value
    /// by value, that for a store with no verified plan start the ONLY difference is that one added line, that the file
    /// as it was is kept as the previous copy, and that no later launch writes again.
    func testTheOneTimeFirstLaunchWriteAddsOneLogLineAndChangesNothingElse() throws {
        let (_, d) = healthy("w12"); let url = d.appendingPathComponent("store.json")
        let beforeData = try Data(contentsOf: url); var before = try json(d)
        let first = Store(directory: d, generatePlan: false)
        var after = try json(d)
        let logBefore = (before["migrationLog"] as? [String]) ?? [], logAfter = (after["migrationLog"] as? [String]) ?? []
        print("E1-W12 first relaunch: file writes=\(first.persistCount) · log lines \(logBefore.count) → \(logAfter.count) · added=\(logAfter.filter { !logBefore.contains($0) })")
        XCTAssertLessThanOrEqual(first.persistCount, 1)
        XCTAssertEqual(logAfter.filter { !logBefore.contains($0) }.count, first.persistCount, "one write = one added log line, nothing else")
        XCTAssertTrue(logAfter.filter { !logBefore.contains($0) }.allSatisfy { $0.hasPrefix(Store.w12CleanupTag) })
        before["migrationLog"] = nil; after["migrationLog"] = nil
        var diff: [String] = []; differences(before, after, "store", &diff)
        XCTAssertTrue(diff.isEmpty, "the one-time write changed something besides its log line:\n" + diff.joined(separator: "\n"))
        XCTAssertEqual(Set(after.keys), Set(before.keys), "no field added or removed")
        if first.persistCount > 0 { XCTAssertEqual(try Data(contentsOf: d.appendingPathComponent(StoreRecovery.previousName)), beforeData, "the file as it was is kept before the write") }
        let stable = try Data(contentsOf: url)
        for _ in 0..<3 { let again = Store(directory: d, generatePlan: false); XCTAssertEqual(again.persistCount, 0, "no write on any later launch") }
        XCTAssertEqual(try Data(contentsOf: url), stable, "three more launches left the file byte for byte unchanged")
        let app = Store(directory: d)                                    // launched the way the app launches, same day
        XCTAssertEqual(app.persistCount, 0, "a normal launch with a plan already in place writes nothing either")
    }
    /// The one-time clean-up when it really has something to do (owner's seven checks, 15 Nov). An athlete whose plan was
    /// approved on a Wednesday has generated sessions on Monday and Tuesday. Only an untouched generated placeholder may
    /// be moved to the trash; every session with an athlete action or a record stays. The whole change is one write.
    func testTheOneTimeCleanUpMovesOnlyUntouchedPlaceholdersInOneWriteAndKeepsEverythingElse() throws {
        let cal = Calendar.current
        let d = tmp("w12-real"); let s = Store(directory: d, generatePlan: false)
        s.profile.name = "E1 W12"
        let start = cal.startOfDay(for: Date())                                    // the plan was approved today
        func at(_ back: Int, _ hour: Double) -> Date { start.addingTimeInterval(Double(-back) * 86_400 + hour * 3600) }
        let placeholderA = Workout(date: at(6, 7), kind: .endurance, minutes: 60)   // untouched, generated → eligible
        let placeholderB = Workout(date: at(6, 18), kind: .strength, minutes: 40, strengthFocus: .fullBody)
        var completed = Workout(date: at(5, 7), kind: .endurance, minutes: 45); completed.done = true; completed.completion = .marked
        var edited = Workout(date: at(4, 7), kind: .tempo, minutes: 50); edited.edited = true
        var skipped = Workout(date: at(3, 7), kind: .endurance, minutes: 60); skipped.skipped = true
        let linked = Workout(date: at(2, 18), kind: .strength, minutes: 40, strengthFocus: .upper)   // has a strength log
        let rideDay = Workout(date: at(1, 7), kind: .endurance, minutes: 60)                           // a ride was recorded that day
        let future = Workout(date: at(-1, 7), kind: .endurance, minutes: 60)
        let todayW = Workout(date: at(0, 18), kind: .strength, minutes: 40, strengthFocus: .fullBody)
        s.plan = [placeholderA, placeholderB, completed, edited, skipped, linked, rideDay, todayW, future]
        s.strength = [StrengthSession(date: at(2, 18), minutes: 38, focus: .upper, workoutId: linked.id)]
        XCTAssertTrue(s.importHealthRide(start: at(1, 8), durationS: 3000, distanceM: 21_000, activeKcal: nil, avgHR: nil, healthUUID: "E1-IMPORTED-RIDE"))
        s.planVersions = [PlanVersion(createdAt: Date(), effectiveDate: start, cause: .profile, before: [], after: [todayW, future], inputsBefore: nil, summary: ["Plan approved in onboarding"], proposalId: nil)]
        s.onboarded = true
        let url = d.appendingPathComponent("store.json")
        let beforeData = try Data(contentsOf: url); let before = try json(d)
        let eligible: Set<String> = [placeholderA.id.uuidString, placeholderB.id.uuidString]
        let protected: Set<String> = Set([completed, edited, skipped, linked, rideDay, todayW, future].map { $0.id.uuidString })

        let launched = Store(directory: d, generatePlan: false)                    // the clean-up runs here, once
        XCTAssertEqual(launched.persistCount, 1, "the whole clean-up is ONE write")
        let after = try json(d)
        func ids(_ o: [String: Any], _ key: String) -> [String] { ((o[key] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String } }
        func byId(_ o: [String: Any]) -> [String: Any] { Dictionary(uniqueKeysWithValues: ((o["plan"] as? [[String: Any]]) ?? []).compactMap { w in (w["id"] as? String).map { ($0, w as Any) } }) }
        XCTAssertEqual(Set(ids(before, "plan")).subtracting(ids(after, "plan")), eligible, "exactly the two untouched placeholders left the plan")
        XCTAssertTrue(protected.isSubset(of: Set(ids(after, "plan"))), "completed, edited, skipped, linked, ride-day, today's and future sessions all stay")
        var diff: [String] = []
        for id in protected { differences(byId(before)[id]!, byId(after)[id]!, "plan[\(id.prefix(8))]", &diff) }
        XCTAssertTrue(diff.isEmpty, "a kept session was altered:\n" + diff.joined(separator: "\n"))
        let trashed = ((after["trash"] as? [[String: Any]]) ?? []).compactMap { ($0["workout"] as? [String: Any])?["id"] as? String }
        XCTAssertEqual(Set(trashed), eligible, "the removed sessions are kept in the trash, not deleted")
        XCTAssertEqual(launched.restoreW12Cleanup(), 2, "and can be put back")
        XCTAssertEqual(((after["migrationLog"] as? [String]) ?? []).count, ((before["migrationLog"] as? [String]) ?? []).count + 1, "one log line")
        var rest: [String] = []
        var b = before, a = after; for k in ["plan", "trash", "migrationLog"] { b[k] = nil; a[k] = nil }
        differences(b, a, "store", &rest)
        XCTAssertTrue(rest.isEmpty, "the clean-up changed something outside plan, trash and its log line:\n" + rest.joined(separator: "\n"))
        XCTAssertEqual(launched.rides.count, 1); XCTAssertEqual(launched.strength.count, 1)
        XCTAssertEqual(try Data(contentsOf: d.appendingPathComponent(StoreRecovery.previousName)), beforeData, "the complete original is kept before the write")
        // idempotent across launches
        let fresh = Store(directory: d, generatePlan: false)                       // (launched.restore above wrote; reload that state)
        XCTAssertNil(fresh.w12CleanupIfNeeded(), "the clean-up never runs a second time")
        XCTAssertEqual(Store(directory: d, generatePlan: false).persistCount, 0, "and later launches write nothing")
    }
    /// A clean-up whose write fails changes nothing on disk, and the next launch does the whole thing.
    func testACleanUpThatCannotBeWrittenLeavesTheStoreExactlyAsItWas() throws {
        let cal = Calendar.current
        let d = tmp("w12-fail"); let s = Store(directory: d, generatePlan: false)
        let start = cal.startOfDay(for: Date())
        let old = Workout(date: start.addingTimeInterval(-3 * 86_400 + 7 * 3600), kind: .endurance, minutes: 60)
        let now = Workout(date: start.addingTimeInterval(18 * 3600), kind: .endurance, minutes: 60)
        s.plan = [old, now]
        s.planVersions = [PlanVersion(createdAt: Date(), effectiveDate: start, cause: .profile, before: [], after: [now], inputsBefore: nil, summary: ["Plan approved in onboarding"], proposalId: nil)]
        s.onboarded = true
        let url = d.appendingPathComponent("store.json"); let before = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: d.path)
        let blocked = Store(directory: d, generatePlan: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: d.path)
        if try Data(contentsOf: url) != before { throw XCTSkip("this environment let the write through despite read-only permissions (for example when running as root)") }
        XCTAssertNotNil(blocked.lastSaveError, "the failed write is reported")
        XCTAssertEqual(try Data(contentsOf: url), before, "nothing on disk changed — not the trash, not the plan, not the log")
        let next = Store(directory: d, generatePlan: false)
        XCTAssertEqual(next.persistCount, 1); XCTAssertEqual(next.plan.map(\.id), [now.id]); XCTAssertEqual(next.w12TrashItems.count, 1)
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

    // MARK: planned-ride completion (E1-F1)
    private func rideStore(_ tag: String, plannedDaysAgo: Int) -> (Store, UUID) {
        let s = Store(directory: tmp(tag), generatePlan: false)
        let day = Calendar.current.date(byAdding: .day, value: -plannedDaysAgo, to: Calendar.current.startOfDay(for: Date()))!
        let w = Workout(date: day.addingTimeInterval(7 * 3600), kind: .endurance, minutes: 60)
        s.plan = [w]
        return (s, w.id)
    }
    func testARideSavedAfterMidnightCompletesTheSessionOfTheDayItStarted() {
        let (s, id) = rideStore("midnight", plannedDaysAgo: 1)
        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-40 * 60)        // 23:20 yesterday
        XCTAssertTrue(s.addRide(RideRecord(start: start, durationS: 3600, distanceM: 30_000, recorder: .phone, sources: ["iPhone"])))
        let w = s.plan.first { $0.id == id }
        XCTAssertEqual(w?.done, true, "yesterday's planned ride was ridden; it must not stay open and turn into 'missed'")
        XCTAssertEqual(w?.completedAt, start.addingTimeInterval(3600), "completed when the ride ended, not when it was saved")
    }
    func testARideDoesNotCompleteASessionOfAnotherDay() {
        let (s, id) = rideStore("otherday", plannedDaysAgo: 2)
        XCTAssertTrue(s.addRide(RideRecord(start: Date().addingTimeInterval(-3600), durationS: 1800, distanceM: 10_000, recorder: .phone, sources: ["iPhone"])))
        XCTAssertEqual(s.plan.first { $0.id == id }?.done, false)
    }
    func testASkippedSessionIsNotReopenedByALateRide() {
        let (s, id) = rideStore("skipped", plannedDaysAgo: 1)
        s.plan[0].skipped = true
        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-3 * 3600)
        XCTAssertTrue(s.addRide(RideRecord(start: start, durationS: 1800, distanceM: 10_000, recorder: .phone, sources: ["iPhone"])))
        XCTAssertEqual(s.plan.first { $0.id == id }?.done, false, "the athlete's own decision to skip is kept")
    }

    // MARK: upgrade from build 216 (E1-A4)
    /// Every store written by the build-216 code (tools/coach-harness/fixtures216, produced in the same CI job from commit
    /// fb52ae27) must open in this build with nothing lost, nothing set aside and nothing rewritten that changes a record.
    /// Runs wherever FIXTURES_216 is set (the fast logic tests); elsewhere it is skipped and says so.
    func testStoresWrittenByBuild216OpenWithoutLoss() throws {
        guard let root = ProcessInfo.processInfo.environment["FIXTURES_216"] else { throw XCTSkip("FIXTURES_216 is not set: this run has no build-216 fixtures") }
        let names = ["empty", "strength", "cycling", "hybrid", "noequipment", "large"]
        for name in names {
            let src = URL(fileURLWithPath: root).appendingPathComponent(name)
            let m = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: src.appendingPathComponent("manifest.json"))) as? [String: Any], "fixture '\(name)' was not produced by the build-216 code")
            let d = tmp("b216-\(name)"); let url = d.appendingPathComponent("store.json")
            let original = try Data(contentsOf: src.appendingPathComponent("store.json")); try original.write(to: url)
            let s = Store(directory: d)                                  // launched the way the app launches
            XCTAssertEqual(s.storage, .ok, name); XCTAssertNil(s.storageNotice, "\(name): nothing to report")
            XCTAssertFalse(files(d).contains(StoreRecovery.quarantineName), "\(name): no record set aside")
            XCTAssertEqual(s.profile.name, m["name"] as? String, name); XCTAssertEqual(s.onboarded, m["onboarded"] as? Bool, name)
            XCTAssertEqual(s.strength.count, m["strength"] as? Int, "\(name): strength sessions")
            XCTAssertEqual(s.strength.reduce(0) { $0 + $1.minutes }, m["strengthMinutes"] as? Int, "\(name): strength minutes")
            XCTAssertEqual(s.rides.count, m["rides"] as? Int, "\(name): rides")
            XCTAssertEqual(s.rides.reduce(0) { $0 + $1.durationS }, m["rideSeconds"] as? Int, "\(name): ride time")
            XCTAssertEqual(s.templates.count, m["templates"] as? Int, "\(name): routines")
            XCTAssertEqual(s.strength.map { $0.id.uuidString }.sorted(), m["strengthIds"] as? [String], "\(name): the same strength sessions")
            XCTAssertEqual(s.rides.map { $0.id.uuidString }.sorted(), m["rideIds"] as? [String], "\(name): the same rides")
            let planIds = Set(m["planIds"] as? [String] ?? [])
            XCTAssertTrue(planIds.isSubset(of: Set(s.plan.map { $0.id.uuidString })), "\(name): no planned session disappeared")
            XCTAssertEqual(s.plan.filter { $0.done && planIds.contains($0.id.uuidString) }.count, m["planDone"] as? Int, "\(name): completed sessions stay completed")
            // rollback: if this launch wrote, the file build 216 wrote is kept byte for byte as the previous copy
            if s.persistCount > 0 { XCTAssertEqual(try Data(contentsOf: d.appendingPathComponent(StoreRecovery.previousName)), original, "\(name): the build-216 file is kept for a rollback") }
            // and a second launch reads the same athlete again
            let again = Store(directory: d, generatePlan: false)
            XCTAssertEqual(again.strength.count, s.strength.count, name); XCTAssertEqual(again.rides.count, s.rides.count, name)
        }
    }

    /// Field by field: every value build 216 wrote is still in the file after this build has loaded it and saved again.
    /// The comparison walks the two JSON documents; a value that is missing or different is listed with its path.
    private func differences(_ old: Any, _ new: Any, _ path: String, _ out: inout [String]) {
        if out.count >= 40 { return }
        switch (old, new) {
        case let (a as [String: Any], b as [String: Any]):
            for k in a.keys.sorted() { if let v = b[k] { differences(a[k]!, v, path + "." + k, &out) } else { out.append("\(path).\(k): missing after save (was \(a[k]!))") } }
        case let (a as [Any], b as [Any]):
            if a.count != b.count { out.append("\(path): \(a.count) elements became \(b.count)"); return }
            for i in a.indices { differences(a[i], b[i], "\(path)[\(i)]", &out) }
        case let (a as NSNumber, b as NSNumber):
            if abs(a.doubleValue - b.doubleValue) > 1e-9 { out.append("\(path): \(a) became \(b)") }
        case let (a as String, b as String):
            if a != b { out.append("\(path): '\(a)' became '\(b)'") }
        case (is NSNull, is NSNull): break
        default: out.append("\(path): type changed (\(type(of: old)) → \(type(of: new)))")
        }
    }
    func testEveryFieldBuild216WroteSurvivesLoadAndSave() throws {
        guard let root = ProcessInfo.processInfo.environment["FIXTURES_216"] else { throw XCTSkip("FIXTURES_216 is not set: this run has no build-216 fixtures") }
        for name in ["empty", "strength", "cycling", "hybrid", "noequipment", "large"] {
            let original = try Data(contentsOf: URL(fileURLWithPath: root).appendingPathComponent(name).appendingPathComponent("store.json"))
            let before = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
            let d = tmp("b216-fields-\(name)"); try original.write(to: d.appendingPathComponent("store.json"))
            let s = Store(directory: d, generatePlan: false)             // load only: no plan generation, so nothing may differ
            XCTAssertEqual(s.persistCount, 0, "\(name): loading a build-216 store writes nothing")
            XCTAssertEqual(try Data(contentsOf: d.appendingPathComponent("store.json")), original, "\(name): the file is untouched by loading")
            s.ignoredInsights = s.ignoredInsights                        // force one save of exactly what was loaded
            XCTAssertGreaterThan(s.persistCount, 0, name)
            let after = try json(d)
            var diff: [String] = []
            differences(before, after, name, &diff)
            let added = Set(after.keys).subtracting(before.keys).sorted()
            print("E1-MIGRATION \(name): schema \(before["schema"] ?? "?") → \(after["schema"] ?? "?") · top-level fields \(before.count) → \(after.count) · added by this build: \(added) · differences: \(diff.count)")
            XCTAssertTrue(diff.isEmpty, "\(name): values changed or lost by load + save:\n" + diff.joined(separator: "\n"))
            // repeating it changes nothing more
            let again = Store(directory: d, generatePlan: false); again.ignoredInsights = again.ignoredInsights
            var diff2: [String] = []; differences(after, try json(d), name, &diff2)
            XCTAssertTrue(diff2.isEmpty, "\(name): a second load + save changed values:\n" + diff2.joined(separator: "\n"))
            XCTAssertEqual(Store(directory: d, generatePlan: false).strength.count, s.strength.count, "\(name): no session duplicated")
        }
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
