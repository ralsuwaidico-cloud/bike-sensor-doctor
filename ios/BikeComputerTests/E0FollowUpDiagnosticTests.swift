import XCTest
import CoreLocation
@testable import BikeComputer

/// E0 FOLLOW-UP DIAGNOSTICS (15 Nov 2026) — diagnostics only. No product code and no existing test is changed.
/// They print evidence as "E0-DIAG2 …" lines; the few assertions state behaviour that should already hold.
/// Synthetic fixtures in the temporary directory only.
final class E0FollowUpDiagnosticTests: XCTestCase {
    private func diag(_ s: String) { print("E0-DIAG2 \(s)") }
    private func tmp(_ tag: String) -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("e0b-\(tag)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    /// The store the failing UI flow seeds (schema 1, hybrid, full-body routine session today, no equipment recorded).
    private func seedJSON() -> String {
        let iso = ISO8601DateFormatter(); let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let wd = (cal.component(.weekday, from: today) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -wd, to: today)!
        let tid = UUID().uuidString
        var plan: [String] = []
        for i in 0..<7 {
            let d = cal.date(byAdding: .day, value: i, to: monday)!.addingTimeInterval(7 * 3600)
            let kind = i == wd ? "strength" : (i % 2 == 0 ? "rest" : "endurance")
            let tpl = i == wd ? "\"templateId\":\"\(tid)\",\"routineManual\":true," : ""
            plan.append("{\"id\":\"\(UUID().uuidString)\",\"date\":\"\(iso.string(from: d))\",\"kind\":\"\(kind)\",\"minutes\":\(kind == "rest" ? 0 : 45),\"done\":false,\"skipped\":false,\"note\":\"\",\"edited\":\(i == wd),\(tpl)\"strengthFocus\":\(kind == "strength" ? "\"fullBody\"" : "null"),\"sequence\":0}")
        }
        let set = "{\"id\":\"\(UUID().uuidString)\",\"reps\":10,\"weightKg\":20,\"bodyweight\":false,\"unilateral\":false,\"done\":true}"
        let logDate = cal.date(byAdding: .day, value: -4, to: today)!.addingTimeInterval(18 * 3600)
        return """
        {"schema":1,
         "profile":{"name":"E0 Fixture","goal":"fitness","hoursPerWeek":5,"level":"intermediate","weightKg":82,"age":35,"ftpW":210,"ftpHow":"entered","birthYear":1988,
                    "sports":["roadCycling","strength"],"version":14,"updatedAt":"2026-10-25T20:00:00Z","wheelMm":2096,"cadenceLow":85,"cadenceHigh":95,"hrZoneMethod":"maxHR",
                    "trainingMode":"hybrid","priority":"balanced","cyclingDaysPerWeek":3,"liftDaysPerWeek":3,"liftingHoursPerWeek":2,"preferredDays":[1,3,5,6]},
         "settings":{"units":"metric","phoneOnlyMode":false,"hrPref":"watch","keepScreenOn":true,"autoConnectBoard":true,"enabledConnections":["board","watch"],"appearance":"system","backgroundNotice":true,"coachTalk":"normal","coachEnabled":true,"appleHealthImportWorkouts":false},
         "plan":[\(plan.joined(separator: ","))],
         "rides":[],"tiles":["power","cadence","hr","speed","time","dist"],"onboarded":true,"guest":true,"createdAt":"2026-10-24T10:00:00Z","boardSync":[],"onboardingStage":0,
         "templates":[{"id":"\(tid)","name":"Short Full Body Workout","focus":"fullBody","entries":[{"id":"\(UUID().uuidString)","exerciseId":"ex-003","name":"Goblet squat","pattern":"squat","sets":[\(set),\(set)],"notes":""},{"id":"\(UUID().uuidString)","exerciseId":"ex-088","name":"Dumbbell row","pattern":"pull","sets":[\(set),\(set)],"superset":"A","notes":""}],"updatedAt":"2026-10-25T19:00:00Z"}],
         "customExercises":[],"appliedProposals":[],
         "strength":[{"id":"\(UUID().uuidString)","date":"\(iso.string(from: logDate))","minutes":35,"focus":"fullBody","customName":"","rpe":7,"notes":"","source":"manual","templateId":"\(tid)","exercises":[{"id":"\(UUID().uuidString)","exerciseId":"ex-003","name":"Goblet squat","pattern":"squat","sets":[\(set),\(set)],"notes":""}]}]}
        """
    }
    private func seededStore(_ tag: String) -> (Store, URL) {
        let d = tmp(tag)
        try? Data(seedJSON().utf8).write(to: d.appendingPathComponent("store.json"))
        return (Store(directory: d), d)
    }
    private func fix(_ i: Int) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: 24.45 + Double(i) * 0.0001, longitude: 54.38), altitude: 12, horizontalAccuracy: 5, verticalAccuracy: 8, course: 0, speed: 8.33, timestamp: Date())
    }

    // MARK: A — why the planner has no counted hip-dominant work without equipment

    func testE0b_Planner_HipCandidatePoolAndPickByExperience() {
        let (s, _) = seededStore("hip")
        guard let w = s.plan.first(where: { $0.kind == .strength && Calendar.current.isDateInToday($0.date) }) else { return XCTFail("fixture: no strength session today") }
        for label in ["as migrated", "beginner", "intermediate", "advanced"] {
            switch label {
            case "beginner": s.strengthPrefs.experience = .beginner
            case "intermediate": s.strengthPrefs.experience = .intermediate
            case "advanced": s.strengthPrefs.experience = .advanced
            default: break
            }
            let ctx = s.plannerContext()
            diag("hip: [\(label)] ctx.experience=\(ctx.experience.rawValue) maxDifficulty=\(ctx.experience.maxDifficulty) goal=\(ctx.goal.rawValue) equipment.isSet=\(ctx.equipment.isSet)")
            if label == "as migrated" {
                // every catalogue exercise that could supply hip-dominant work, with each gate the planner applies
                for e in ctx.catalogue {
                    let m = ExerciseLibrary.meta(e)
                    let dom = ExerciseLibrary.dominance(e)
                    guard m.slot == .hinge || dom == .hip else { continue }
                    diag("hip: candidate \(e.id) '\(e.name)' equipment=\(e.equipment) slot=\(m.slot.rawValue) compound=\(m.compound) difficulty=\(m.difficulty) dominance=\(dom.rawValue) plannable(noEquipment)=\(ctx.equipment.plannable(e)) available=\(StrengthPlanner.available(e, ctx: ctx)) passesLevelFilter=\(m.difficulty <= ctx.experience.maxDifficulty)")
                }
            }
            let hinge = StrengthPlanner.pick(StrengthPlanner.SlotSpec(slot: .hinge, role: .main), ctx: ctx, used: [])
            let lunge = StrengthPlanner.pick(StrengthPlanner.SlotSpec(slot: .lunge, role: .accessory), ctx: ctx, used: [])
            diag("hip: [\(label)] hinge slot picks '\(hinge?.name ?? "nothing")' (dominance \(hinge.map { ExerciseLibrary.dominance($0).rawValue } ?? "-"), compound \(hinge.map { ExerciseLibrary.meta($0).compound } ?? false)) · lunge slot picks '\(lunge?.name ?? "nothing")' (dominance \(lunge.map { ExerciseLibrary.dominance($0).rawValue } ?? "-"))")
            for m in [30, 45, 60, 95] {
                var req = SessionChangeRequest(); req.minutes = m; req.detachRoutine = true
                guard let p = s.evaluateSessionChange(workoutId: w.id, request: req) else { diag("hip: [\(label)] m=\(m) no proposal"); continue }
                let cov = WorkoutValidator.coverage(p.afterEntries, catalogue: s.allExercises)
                let blocks = p.report.issues.filter { $0.outcome == .block }.map { $0.ruleId }.joined(separator: ",")
                let left = (p.after.rationale?.notes ?? []).first { $0.hasPrefix("To fit") } ?? "nothing left out for time"
                diag("hip: [\(label)] m=\(m) outcome=\(p.report.outcome.rawValue) blocks=[\(blocks)] hipSets=\(cov.hip) entries=\(p.afterEntries.map { "\($0.name) x\($0.sets.count)" }.joined(separator: "; ")) · \(left)")
            }
        }
    }

    // MARK: B — memory versus disk versus relaunch

    private func deepDiff(_ a: Any, _ b: Any, path: String, depth: Int, out: inout [String]) {
        if out.count >= 14 { return }
        if let ha = a as? AnyHashable, let hb = b as? AnyHashable, ha == hb { return }
        if let da = a as? Date, let db = b as? Date {
            if da != db { out.append("\(path): Date differs by \(String(format: "%.6f", da.timeIntervalSince(db))) s (memory \(da.timeIntervalSince1970) vs \(db.timeIntervalSince1970))") }
            return
        }
        let ca = Array(Mirror(reflecting: a).children), cb = Array(Mirror(reflecting: b).children)
        if ca.isEmpty || cb.isEmpty || ca.count != cb.count || depth == 0 {
            let sa = String(describing: a), sb = String(describing: b)
            if sa != sb || ca.count != cb.count { out.append("\(path): memory=\(sa.prefix(80)) | other=\(sb.prefix(80)) [children \(ca.count) vs \(cb.count)]") }
            return
        }
        for (i, pair) in zip(ca, cb).enumerated() { deepDiff(pair.0.value, pair.1.value, path: path + "." + (pair.0.label ?? "\(i)"), depth: depth - 1, out: &out) }
    }
    private func decodeDisk(_ d: URL) throws -> StoreFile {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try dec.decode(StoreFile.self, from: Data(contentsOf: d.appendingPathComponent("store.json")))
    }
    func testE0b_RoundTrip_ExactDifferencesBetweenMemoryDiskAndRelaunch() throws {
        let (s, d) = seededStore("rt")
        let url = d.appendingPathComponent("store.json")
        let beforeSaveMemory = s.snapshot
        let beforeBytes = try Data(contentsOf: url)
        let writesBefore = s.persistCount
        let added = s.addStrength(StrengthSession(date: Date(), minutes: 30, focus: .fullBody))
        let afterBytes = try Data(contentsOf: url)
        diag("rt: addStrength returned \(added) · file writes caused by it=\(s.persistCount - writesBefore) · file changed=\(beforeBytes != afterBytes) · bytes \(beforeBytes.count) → \(afterBytes.count) · write is synchronous (file already changed when the call returned)=\(beforeBytes != afterBytes)")
        let memory = s.snapshot
        let disk = try decodeDisk(d)
        var out: [String] = []
        deepDiff(memory, disk, path: "store", depth: 7, out: &out)
        diag("rt: memory vs disk · equal=\(memory == disk) · differences found=\(out.count)")
        for l in out { diag("rt:   \(l)") }
        // was the difference there before this save too (i.e. it comes from loading / migration, not from the save)?
        var out0: [String] = []
        let beforeDisk = try JSONDecoder.e0iso().decode(StoreFile.self, from: beforeBytes)
        deepDiff(beforeSaveMemory, beforeDisk, path: "store", depth: 7, out: &out0)
        diag("rt: before the save, memory vs disk differences=\(out0.count)")
        for l in out0.prefix(8) { diag("rt:   (before) \(l)") }
        // relaunch: a second Store on the same directory
        let relaunch = Store(directory: d, generatePlan: false)
        var out2: [String] = []
        deepDiff(relaunch.snapshot, disk, path: "store", depth: 7, out: &out2)
        diag("rt: relaunch vs disk · equal=\(relaunch.snapshot == disk) · differences=\(out2.count) · relaunch file writes=\(relaunch.persistCount)")
        for l in out2.prefix(8) { diag("rt:   (relaunch) \(l)") }
        var out3: [String] = []
        deepDiff(memory, relaunch.snapshot, path: "store", depth: 7, out: &out3)
        diag("rt: memory vs relaunch · equal=\(memory == relaunch.snapshot) · differences=\(out3.count) · records: strength \(memory.strength.count)/\(relaunch.snapshot.strength.count) plan \(memory.plan.count)/\(relaunch.snapshot.plan.count) templates \(memory.templates.count)/\(relaunch.snapshot.templates.count)")
        for l in out3.prefix(8) { diag("rt:   (mem-vs-relaunch) \(l)") }
        XCTAssertEqual(memory.strength.map { $0.id }, relaunch.snapshot.strength.map { $0.id }, "no record is lost or duplicated by a relaunch")
        XCTAssertEqual(memory.plan.map { $0.id }, relaunch.snapshot.plan.map { $0.id })
    }

    // MARK: C — ride: controlled stalls, route points always kept

    func testE0b_Ride_ControlledStallsExplainTheExtraSamples() {
        for (name, before, mid) in [("none", 0.0, 0.0), ("1.6 s before first tick", 1.6, 0.0), ("5.6 s before first tick", 5.6, 0.0), ("2.6 s mid-ride", 0.0, 2.6)] {
            let loc = LocationService(); let r = RideRecorder(autoTick: false); r.location = loc
            XCTAssertTrue(r.start())
            if before > 0 { Thread.sleep(forTimeInterval: before) }
            for i in 0..<5 {
                if i == 2, mid > 0 { Thread.sleep(forTimeInterval: mid) }
                loc.injectForTests(fix(i)); r.tick()
            }
            let gapPositions = r.samples.enumerated().filter { $0.element.gap == true }.map { String($0.offset) }.joined(separator: ",")
            r.pause(); r.end()
            let saved = r.pendingResult
            diag("ride: stall=\(name) → samples=\(r.samples.count) gapSeconds=\(r.gapSeconds) gapPositions=[\(gapPositions)] routeFixes=\(r.samples.compactMap(\.lat).count) elapsedS=\(r.elapsedS) · saved: samples=\(saved?.samples.count ?? -1) routePoints=\(saved?.samples.filter { $0.lat != nil }.count ?? -1) gapSeconds=\(String(describing: saved?.gapSeconds))")
            XCTAssertEqual(r.samples.compactMap(\.lat).count, 5, "all route fixes kept (\(name))")
            XCTAssertEqual(saved?.samples.filter { $0.lat != nil }.count, 5, "saved record keeps the route (\(name))")
            XCTAssertEqual(r.samples.count, 5 + r.gapSeconds, "extra samples are exactly the gap seconds (\(name))")
        }
    }

    // MARK: D — identity and idempotency probes

    func testE0b_Idempotency_RepeatedSavesAndImports() {
        let (s, d) = seededStore("idem")
        let x = StrengthSession(date: Date(), minutes: 30, focus: .fullBody)
        let n0 = s.strength.count
        let a1 = s.addStrength(x), a2 = s.addStrength(x)
        diag("idem: same strength session saved twice → first=\(a1) second=\(a2) count \(n0) → \(s.strength.count)")
        let loc = LocationService(); let rec = RideRecorder(autoTick: false); rec.location = loc
        XCTAssertTrue(rec.start()); for i in 0..<3 { loc.injectForTests(fix(i)); rec.tick() }; rec.pause(); rec.end()
        if let ride = rec.pendingResult {
            let r1 = s.addRide(ride), r2 = s.addRide(ride)
            let imported = s.importHealthRide(start: ride.start, durationS: ride.durationS, distanceM: ride.distanceM, activeKcal: nil, avgHR: nil, healthUUID: UUID().uuidString)
            diag("idem: same ride saved twice → first=\(r1) second=\(r2) rides=\(s.rides.count) · same ride arriving from Apple Health → imported=\(imported) rides=\(s.rides.count)")
            let c = CheckIn(performance: 6, effort: 5)
            _ = s.recordCheckIn(c, rideId: ride.id); let plan1 = s.plan
            _ = s.recordCheckIn(c, rideId: ride.id)
            diag("idem: same check-in submitted twice → plan identical after the second=\(s.plan == plan1) adaptations=\(s.adaptations.count)")
        } else { diag("idem: no ride result produced") }
        let relaunch = Store(directory: d, generatePlan: false)
        diag("idem: after relaunch strength=\(relaunch.strength.count) rides=\(relaunch.rides.count)")
        XCTAssertFalse(a2, "a session with the same id is not saved twice")
    }
}
private extension JSONDecoder { static func e0iso() -> JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d } }
