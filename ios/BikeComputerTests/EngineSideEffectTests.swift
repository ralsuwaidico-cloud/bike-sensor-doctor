import XCTest
@testable import BikeComputer

/// Owner (2 Nov): a feasibility check must not change the athlete's training state. These tests pin the rules from
/// ios/ENGINE_SIDE_EFFECTS_AUDIT.md: evaluation is pure; Cancel and failed validation leave the plan equal; other
/// proposals never evict the athlete's pending preview; background refreshes leave the athlete's own sessions alone;
/// Health import is idempotent.
final class EngineSideEffectTests: XCTestCase {
    var nextMonday: Date { let c = Calendar.current; let t = c.startOfDay(for: Date()); let wd = (c.component(.weekday, from: t) + 5) % 7; return c.date(byAdding: .day, value: 7 - wd, to: t)! }
    private func day(_ sport: DayAssignment.Sport?, _ minutes: Int = 0) -> DayAvailability {
        guard let s = sport else { return DayAvailability(activity: .rest, minutes: 0) }
        return DayAvailability(assignments: [DayAssignment(sport: s, minutes: minutes)])
    }
    private func store() -> Store {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("side-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let s = Store(directory: d, generatePlan: false)
        s.profile.trainingMode = .hybrid; s.profile.level = .intermediate; s.profile.hoursPerWeek = 3; s.profile.liftingHoursPerWeek = 2
        s.profile.cyclingSessionMinutes = 60; s.profile.strengthSessionMinutes = 30; s.profile.weekIsExplicit = true
        s.strengthPrefs.experience = .intermediate; s.strengthPrefs.prefersSupersets = true
        s.equipment = EquipmentProfile(owned: ["dumbbell", "bench"])
        s.availability = WeeklyAvailability(days: [day(.strength, 30), day(.cycling, 60), day(.strength, 30), day(nil), day(.strength, 30), day(.cycling, 60), day(nil)])
        s.plan = PlanEngine.week(starting: nextMonday, profile: s.profile, availability: s.availability!)
        s.refreshGeneratedSessions(now: nextMonday.addingTimeInterval(-86_400))
        return s
    }
    private var now: Date { nextMonday.addingTimeInterval(-3_600) }
    private func lift(_ s: Store) -> Workout { s.plan.first { $0.kind == .strength }! }

    // 1 — pure evaluation: the persisted snapshot is value-identical afterwards
    func testEvaluateSessionChangeLeavesPersistedStateIdentical() {
        let s = store()
        let before = s.snapshot
        let pendingBefore = s.pendingProposals, lastBefore = s.lastProposalId
        for m in [15, 20, 25, 28, 45] {
            var req = SessionChangeRequest(); req.minutes = m
            let p = s.evaluateSessionChange(workoutId: lift(s).id, request: req, now: now)
            XCTAssertNotNil(p, "evaluation produces a proposal for \(m) min")
        }
        for _ in 0..<30 { _ = s.shortestFeasibleMinutes(for: lift(s), target: 20, now: now) }
        XCTAssertEqual(s.snapshot, before, "evaluation and feasibility checks write nothing that is persisted")
        XCTAssertEqual(s.pendingProposals.count, pendingBefore.count, "nothing registered")
        XCTAssertEqual(s.lastProposalId, lastBefore)
    }

    // 2 — the athlete's pending preview survives 50 coach / background proposals and the hour limit
    func testPendingPreviewSurvivesOtherProposals() {
        let s = store()
        var w = lift(s); w.minutes = 25
        let r = s.edit(w)
        XCTAssertTrue(r == .needsConfirmation || { if case .blocked = r { return true }; return false }(), "\(r)")
        guard let mine = s.lastProposalId, s.pendingProposals[mine] != nil else { return XCTFail("preview registered") }
        let other = s.plan.filter { $0.kind == .strength && $0.id != w.id }
        for i in 0..<50 {
            var req = SessionChangeRequest(); req.minutes = 20 + (i % 8); req.origin = .coach
            // later createdAt than the athlete's and, after many, beyond the hour window
            _ = s.proposeSessionChange(workoutId: other[i % other.count].id, request: req, now: now.addingTimeInterval(Double(i) * 600))
        }
        XCTAssertNotNil(s.pendingProposals[mine], "the athlete's preview is never evicted by other proposals")
        XCTAssertEqual(s.lastProposalId, mine)
        XCTAssertLessThanOrEqual(s.pendingProposals.count, 21, "the table stays bounded")
        XCTAssertNotNil(s.pendingProposals[mine])
        // and it still commits
        if case .applied = s.commit(proposalId: mine, confirmed: true) {} else if s.pendingProposals[mine]?.report.outcome == .block {} else { XCTFail("commit after eviction pressure") }
    }

    // 3 — Cancel and a blocked (failed-validation) proposal leave the plan and versions equal
    func testCancelAndBlockedValidationLeavePlanEqual() {
        let s = store()
        let planBefore = s.plan, versionsBefore = s.planVersions, trashBefore = s.trash.count
        var w = lift(s); w.minutes = 10          // below what the exercises allow → TIME-001 block
        let r = s.edit(w)
        if case .blocked(let ids) = r { XCTAssertTrue(ids.contains("TIME-001") || !ids.isEmpty) } else { XCTAssertEqual(r, .needsConfirmation) }
        if let id = s.lastProposalId {
            let c = s.commit(proposalId: id, confirmed: true)
            if s.pendingProposals[id]?.report.outcome == .block { if case .blocked = c {} else { XCTFail("a blocked proposal must not commit: \(c)") } }
            s.discardProposal(id)
        }
        XCTAssertEqual(s.plan, planBefore, "Cancel / blocked validation: plan unchanged")
        XCTAssertEqual(s.planVersions, versionsBefore)
        XCTAssertEqual(s.trash.count, trashBefore)
    }

    // 4 — background refresh and adaptation leave hand-edited / completed / fixed sessions and plan versions alone
    func testBackgroundRefreshLeavesAthleteSessionsAndVersionsAlone() {
        let s = store()
        var p = s.plan
        let li = p.indices.filter { p[$0].kind == .strength }
        XCTAssertGreaterThanOrEqual(li.count, 3)
        p[li[0]].entriesHandEdited = true; p[li[0]].markRiderEdited()
        p[li[1]].completion = .marked
        p[li[2]].fixed = true
        s.plan = p
        let hand = p[li[0]], done = p[li[1]], fixed = p[li[2]], versions = s.planVersions
        for _ in 0..<3 {
            s.refreshGeneratedSessions(now: now)
            _ = s.runAdaptation(now: now)
        }
        XCTAssertEqual(s.plan.first { $0.id == hand.id }, hand, "hand-edited session untouched")
        XCTAssertEqual(s.plan.first { $0.id == done.id }, done, "completed session untouched")
        XCTAssertEqual(s.plan.first { $0.id == fixed.id }?.plannedEntries, fixed.plannedEntries, "fixed session's prescription untouched")
        XCTAssertEqual(s.planVersions, versions, "background work records no plan version")
        XCTAssertEqual(s.plan.count, p.count)
    }

    // 5 — Health import twice (same UUID, or same start/duration) is idempotent
    func testHealthImportIsIdempotent() {
        let s = store()
        let start = nextMonday.addingTimeInterval(-7 * 86_400 + 7 * 3600)
        XCTAssertTrue(s.importHealthRide(start: start, durationS: 3600, distanceM: 25_000, activeKcal: 500, avgHR: 140, healthUUID: "h-1"))
        let after = s.snapshot
        XCTAssertFalse(s.importHealthRide(start: start, durationS: 3600, distanceM: 25_000, activeKcal: 500, avgHR: 140, healthUUID: "h-1"))
        XCTAssertFalse(s.importHealthRide(start: start.addingTimeInterval(60), durationS: 3630, distanceM: 25_000, activeKcal: 500, avgHR: 140, healthUUID: "h-2"), "same ride, different id")
        XCTAssertEqual(s.snapshot, after)
        XCTAssertEqual(s.rides.filter { $0.recorder == .health }.count, 1)
    }

    // 6 — a Fix-plan report (render path) is side-effect free however often it is built
    func testFixPlanReportIsRenderSafe() {
        let s = store()
        s.profile.liftingHoursPerWeek = 1
        let before = s.snapshot, pending = s.pendingProposals.count
        for _ in 0..<25 {
            _ = BudgetFix.report(week: s.workouts(weekOf: nextMonday), riding: false, budgetHours: 1, isCompleted: { _ in false }, now: now,
                                 feasibleMinutes: { w, t in s.shortestFeasibleMinutes(for: w, target: t, now: now) })
        }
        XCTAssertEqual(s.snapshot, before)
        XCTAssertEqual(s.pendingProposals.count, pending)
    }
}
