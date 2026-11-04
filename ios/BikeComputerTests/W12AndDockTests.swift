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
}
