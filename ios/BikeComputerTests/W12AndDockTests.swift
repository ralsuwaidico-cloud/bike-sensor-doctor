import XCTest
@testable import BikeComputer

/// Checkpoint B (owner 4 Nov): W12 "before this plan started" and the Liquid Dock's centre-state mapping.
/// Pure and store-level checks; the simulator audit checks the drawn strips and the dock.
final class W12AndDockTests: XCTestCase {
    private let cal = Calendar.current
    private func fresh() -> Store {
        Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent("bc-w12-\(UUID().uuidString)", isDirectory: true), generatePlan: false)
    }
    private func day(_ offset: Int, hour: Int = 7, from base: Date = Date()) -> Date {
        cal.date(bySettingHour: hour, minute: 0, second: 0, of: cal.date(byAdding: .day, value: offset, to: base)!)!
    }
    private var today: Date { cal.startOfDay(for: Date()) }
    /// Monday of this week (0 on a Monday).
    private var weekdayIndex: Int { (cal.component(.weekday, from: today) + 5) % 7 }

    // MARK: effective start

    func testEffectiveStartComesFromTheOnboardingApprovalVersion() {
        let s = fresh()
        let tue = day(1)
        let w = Workout(date: tue, kind: .endurance, minutes: 60)
        s.plan = [w]
        // an onboarding approval: cause profile, nothing before, the made sessions after
        s.planVersions = [PlanVersion(createdAt: Date(), effectiveDate: tue, cause: .profile, before: [], after: [w], inputsBefore: nil, summary: ["Plan approved in onboarding"], proposalId: nil)]
        XCTAssertEqual(s.planEffectiveStart, cal.startOfDay(for: tue))
        // a later Profile change (cause profile WITH before sessions) never moves the start
        s.planVersions.append(PlanVersion(createdAt: Date().addingTimeInterval(60), effectiveDate: day(-10), cause: .profile, before: [w], after: [w], inputsBefore: nil, summary: ["Goal changed"], proposalId: nil))
        XCTAssertEqual(s.planEffectiveStart, cal.startOfDay(for: tue))
    }

    func testEffectiveStartFallsBackToTheEarliestPlannedDayForOlderStores() {
        let s = fresh()
        XCTAssertNil(s.planEffectiveStart, "no plan, no start")
        s.plan = [Workout(date: day(3), kind: .strength, minutes: 30), Workout(date: day(1), kind: .endurance, minutes: 60)]
        XCTAssertEqual(s.planEffectiveStart, cal.startOfDay(for: day(1)), "a store upgraded without plan versions starts at its earliest planned day — nothing before it is relabelled")
    }

    // MARK: the day rule

    func testDayBeforeTheStartIsBeforePlanOnlyWhenNothingWasRecorded() {
        let start = cal.startOfDay(for: day(1))
        XCTAssertTrue(CyPlanStart.isBeforePlan(day(0), effectiveStart: start, hasRecord: false))
        XCTAssertFalse(CyPlanStart.isBeforePlan(day(0), effectiveStart: start, hasRecord: true), "a recorded session keeps its real status")
        XCTAssertFalse(CyPlanStart.isBeforePlan(day(1), effectiveStart: start, hasRecord: false), "the start day itself is in the plan")
        XCTAssertFalse(CyPlanStart.isBeforePlan(day(-3), effectiveStart: nil, hasRecord: false), "no plan: nothing is 'before' it")
    }

    func testBeforePlanDayIsSpokenAsSuchAndNeverAsRest() {
        let d = CyDay(id: 0, shortName: "Mon", longName: "Monday", sport: .rest, status: .beforePlan)
        XCTAssertTrue(d.accessibilityLabel.contains("Before this plan started"), d.accessibilityLabel)
        XCTAssertFalse(d.accessibilityLabel.lowercased().contains("rest"), d.accessibilityLabel)
        XCTAssertEqual(CyDayStatus.beforePlan.spoken, "before this plan started")
    }

    func testStoreKnowsWhichDaysHaveARecord() {
        let s = fresh()
        XCTAssertFalse(s.hasRecord(on: day(-1)))
        s.rides.append(RideRecord(start: day(-1), durationS: 1800, distanceM: 12000, recorder: .phone, sources: []))
        XCTAssertTrue(s.hasRecord(on: day(-1)))
        var marked = Workout(date: day(-2), kind: .strength, minutes: 30); marked.completion = .marked
        s.plan.append(marked)
        XCTAssertTrue(s.hasRecord(on: day(-2)), "a session marked done counts as a record")
    }

    // MARK: adherence never counts pre-start days (regression for the run-147 fix, kept by Checkpoint B)

    func testPlanApprovedMidWeekCountsOnlyFromTheStartDay() {
        let s = fresh()
        _ = s.regenerate(weekOf: Date(), replaceEdited: true)
        let monday = TrainingLedger.monday(of: Date())
        let riding = s.ledger.riding(weekOf: monday), lifting = s.ledger.lifting(weekOf: monday)
        let planned = s.plan.filter { $0.date >= monday && $0.date < cal.date(byAdding: .day, value: 7, to: monday)! && !$0.skipped && ($0.kind.isRide || $0.kind == .strength) }
        XCTAssertEqual(riding.planned + lifting.planned, planned.count, "the denominator is exactly the planned sessions")
        XCTAssertTrue(planned.allSatisfy { cal.startOfDay(for: $0.date) >= today }, "no planned session before today: \(planned.map { "\($0.date)" })")
        XCTAssertEqual(riding.plannedDone + lifting.plannedDone, 0)
        XCTAssertNil(s.homeToday().missed, "a day before the plan is never a missed session")
        XCTAssertEqual(s.planEffectiveStart, s.plan.map { cal.startOfDay(for: $0.date) }.min())
        // every day of this week before today is a 'before plan' day on the strips
        for i in 0..<weekdayIndex {
            let d = cal.date(byAdding: .day, value: i, to: monday)!
            XCTAssertTrue(CyPlanStart.isBeforePlan(d, effectiveStart: s.planEffectiveStart, hasRecord: s.hasRecord(on: d)), "\(d)")
        }
    }

    func testRideRecordedBeforeApprovalStaysInHistoryAndCounts() throws {
        try XCTSkipIf(weekdayIndex == 0, "on a Monday there is no earlier day this week")
        let s = fresh()
        let monday = TrainingLedger.monday(of: Date())
        s.rides.append(RideRecord(start: cal.date(bySettingHour: 8, minute: 0, second: 0, of: monday)!, durationS: 3600, distanceM: 27000, recorder: .phone, sources: []))
        _ = s.regenerate(weekOf: Date(), replaceEdited: true)
        XCTAssertFalse(CyPlanStart.isBeforePlan(monday, effectiveStart: s.planEffectiveStart, hasRecord: s.hasRecord(on: monday)), "the recorded ride keeps Monday's real status")
        let riding = s.ledger.riding(weekOf: monday)
        XCTAssertEqual(riding.completed, 1); XCTAssertEqual(riding.minutes, 60)
        XCTAssertEqual(riding.extra, 1, "counted as an extra ride, never as a planned one")
    }

    func testApprovalDropsGeneratedSessionsOnDaysAlreadyOver() throws {
        try XCTSkipIf(weekdayIndex == 0, "on a Monday there is no earlier day this week")
        // the app's launch path: a plan is generated from the default profile before onboarding (Store(generatePlan: true))
        let s = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent("bc-w12g-\(UUID().uuidString)", isDirectory: true), generatePlan: true)
        let monday = TrainingLedger.monday(of: Date())
        let before = s.plan.filter { $0.date >= monday && cal.startOfDay(for: $0.date) < today }
        XCTAssertFalse(before.isEmpty, "the launch-time plan covers the days already over (the run-154 defect)")
        // a ride the athlete actually recorded on one of those days, and a session marked done, must survive — but only
        // when another day already over stays unrecorded, so there is something to remove
        if weekdayIndex > 1 { s.rides.append(RideRecord(start: cal.date(bySettingHour: 8, minute: 0, second: 0, of: monday)!, durationS: 1800, distanceM: 10000, recorder: .phone, sources: [])) }
        if weekdayIndex > 2, var marked = s.plan.first(where: { cal.isDate($0.date, inSameDayAs: cal.date(byAdding: .day, value: 1, to: monday)!) }) {
            marked.completion = .marked; s.update(marked)
        }
        let expected = s.plan.filter { cal.startOfDay(for: $0.date) < today && !$0.done && $0.completion != .marked && !s.hasRecord(on: $0.date) }.count
        XCTAssertGreaterThan(expected, 0, "at least one unrecorded day already over")
        let removed = s.dropUnapprovedSessions(before: Date())
        XCTAssertEqual(removed, expected)
        let left = s.plan.filter { cal.startOfDay(for: $0.date) < today }
        XCTAssertTrue(left.allSatisfy { $0.done || $0.completion == .marked || s.hasRecord(on: $0.date) }, "only recorded or done sessions stay: \(left.map { "\($0.date) \($0.kind)" })")
        XCTAssertEqual(s.rides.count, weekdayIndex > 1 ? 1 : 0, "rides are never touched")
        XCTAssertTrue(s.migrationLog.last?.hasPrefix("W12: removed") == true)
        _ = s.regenerate(weekOf: Date(), replaceEdited: true)
        XCTAssertNil(s.homeToday().missed, "nothing before the approval is ever 'missed'")
        XCTAssertEqual(s.dropUnapprovedSessions(before: Date()), 0, "idempotent")
    }

    // MARK: centre button state

    func testCentreStateFollowsTodayActionAndRecording() {
        let w = Workout(date: Date(), kind: .strength, minutes: 30)
        XCTAssertEqual(CyCentreState.from(action: .train(w), recording: false), .pending)
        XCTAssertEqual(CyCentreState.from(action: .ride(w), recording: false), .pending)
        XCTAssertEqual(CyCentreState.from(action: .choose([w, w]), recording: false), .multiple(2))
        XCTAssertEqual(CyCentreState.from(action: .choose([w]), recording: false), .pending)
        XCTAssertEqual(CyCentreState.from(action: .inProgress, recording: false), .active)
        XCTAssertEqual(CyCentreState.from(action: .doneToday(next: nil), recording: false), .done)
        XCTAssertEqual(CyCentreState.from(action: .rest, recording: false), .rest)
        XCTAssertEqual(CyCentreState.from(action: .healthHold, recording: false), .hold, "a health hold keeps its own look and still opens only the hold sheet")
        XCTAssertEqual(CyCentreState.from(action: .train(w), recording: true), .recording, "a recorded ride overrides everything")
        XCTAssertTrue(CyCentreState.pending.pulses); XCTAssertTrue(CyCentreState.multiple(2).pulses)
        for s in [CyCentreState.active, .done, .rest, .hold, .recording] { XCTAssertFalse(s.pulses, "\(s)") }
    }

    // MARK: one-time cleanup of historical placeholders (owner-approved in principle, 4 Nov)

    /// A store as build 153 left it: the launch-time plan, then an onboarding approval that kept the placeholders.
    private func build153Store() throws -> (Store, Date) {
        try XCTSkipIf(weekdayIndex == 0, "on a Monday there is no earlier day this week")
        let s = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent("bc-w12c-\(UUID().uuidString)", isDirectory: true), generatePlan: true)
        let now = Date()
        _ = s.regenerate(weekOf: now, replaceEdited: true)
        let made = s.plan.filter { $0.date >= today }
        s.planVersions.append(PlanVersion(createdAt: now, effectiveDate: made.first?.date ?? now, cause: .profile, before: [], after: made, inputsBefore: nil, summary: ["Plan approved in onboarding"], proposalId: nil))
        s.onboarded = true
        XCTAssertFalse(s.plan.filter { cal.startOfDay(for: $0.date) < today }.isEmpty, "the build-153 situation: placeholders before the approval day")
        return (s, today)
    }

    func testCleanupRemovesOnlyPositivelyIdentifiedPlaceholders() throws {
        let (s, start) = try build153Store()
        let monday = TrainingLedger.monday(of: Date())
        // make four earlier sessions "real" in different ways; the rest stay placeholders
        var earlier = s.plan.filter { cal.startOfDay(for: $0.date) < start }
        var protectedIds = Set<UUID>()
        if earlier.count > 0 { earlier[0].edited = true; s.update(earlier[0]); protectedIds.insert(earlier[0].id) }              // hand-edited
        if earlier.count > 1 { earlier[1].note = "felt good"; s.update(earlier[1]); protectedIds.insert(earlier[1].id) }          // a note
        if earlier.count > 2 { earlier[2].completion = .marked; s.update(earlier[2]); protectedIds.insert(earlier[2].id) }       // marked done
        if earlier.count > 3 { earlier[3].skipped = true; s.update(earlier[3]); protectedIds.insert(earlier[3].id) }             // skipped by the athlete
        // a ride recorded on Monday protects Monday's sessions too
        s.rides.append(RideRecord(start: cal.date(bySettingHour: 8, minute: 0, second: 0, of: monday)!, durationS: 1800, distanceM: 10000, recorder: .phone, sources: []))
        for w in s.plan where cal.isDate(w.date, inSameDayAs: monday) { protectedIds.insert(w.id) }
        let expected = s.plan.filter { cal.startOfDay(for: $0.date) < start && !protectedIds.contains($0.id) }
        let onOrAfter = s.plan.filter { cal.startOfDay(for: $0.date) >= start }
        let before = s.plan.count

        let r = s.w12CleanupIfNeeded()
        XCTAssertNotNil(r)
        XCTAssertEqual(r?.removed, expected.count, "removes exactly the positively identified placeholders")
        XCTAssertEqual(r?.before, expected.count + protectedIds.count)
        XCTAssertEqual(s.plan.count, before - expected.count)
        for id in protectedIds { XCTAssertNotNil(s.plan.first { $0.id == id }, "a session with an athlete action or a record is kept") }
        for w in onOrAfter { XCTAssertNotNil(s.plan.first { $0.id == w.id }, "nothing on or after the start is touched") }
        XCTAssertEqual(s.rides.count, 1); XCTAssertTrue(s.strength.isEmpty)
        XCTAssertTrue(s.migrationLog.last?.contains("removed \(expected.count)") == true, s.migrationLog.last ?? "")
        // recoverable: the removed sessions wait in the trash, flagged to survive the 30-day purge
        let kept = s.trash.filter { $0.keep == true && $0.label.hasPrefix(Store.w12CleanupTag) }
        XCTAssertEqual(kept.count, expected.count)
        s.purgeTrash(now: Date().addingTimeInterval(60 * 86_400))
        XCTAssertEqual(s.trash.filter { $0.keep == true }.count, expected.count, "never purged")
        // idempotent: a second run does nothing
        XCTAssertNil(s.w12CleanupIfNeeded())
        XCTAssertEqual(s.plan.count, before - expected.count)
        // restore puts every removed session back, once
        XCTAssertEqual(s.restoreW12Cleanup(), expected.count)
        XCTAssertEqual(s.plan.count, before)
        XCTAssertEqual(s.restoreW12Cleanup(), 0)
    }

    func testCleanupDoesNothingWithoutAVerifiedPlanStart() {
        let s = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent("bc-w12n-\(UUID().uuidString)", isDirectory: true), generatePlan: true)
        s.onboarded = true      // an older store: a plan, but no onboarding approval version
        let before = s.plan
        XCTAssertNil(s.w12CleanupIfNeeded())
        XCTAssertEqual(s.plan, before, "no positive identification, nothing deleted")
        XCTAssertTrue(s.migrationLog.last?.contains("skipped") == true)
        XCTAssertNil(s.w12CleanupIfNeeded(), "and it does not keep retrying")
    }

    func testCleanupSkipsSessionsReferencedByAPlanVersion() throws {
        let (s, start) = try build153Store()
        guard let w = s.plan.first(where: { cal.startOfDay(for: $0.date) < start }) else { return XCTFail("no earlier session") }
        s.planVersions.append(PlanVersion(createdAt: Date(), effectiveDate: w.date, cause: .edit, before: [w], after: [w], inputsBefore: nil, summary: ["edited"], proposalId: nil))
        XCTAssertFalse(s.isW12Placeholder(w, effectiveStart: start), "a session the athlete previewed or changed is never a placeholder")
        _ = s.w12CleanupIfNeeded()
        XCTAssertNotNil(s.plan.first { $0.id == w.id })
    }
}
