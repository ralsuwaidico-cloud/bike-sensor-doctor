import XCTest
@testable import BikeComputer

/// Coach page: the timeline is built only from the app's Coach records, oldest first, and never invents an entry.
final class CoachTimelineTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func at(_ day: Int, _ hour: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))! }
    private func workout() -> Workout { Workout(date: at(12, 9), kind: .endurance, minutes: 60) }
    private func adjustment(_ w: Workout, created: Date) -> PlanAdjustment {
        PlanAdjustment(workoutId: w.id, change: .minutes(delta: -10), category: .reduction, summary: "Thu ride: 60 → 50 min", why: "Two hard sessions in three days.", createdAt: created)
    }

    func testNoRecordsMeansAnEmptyTimeline() {
        let e = CoachTimeline.entries(.init(summary: nil, proposals: [], applied: [], accepted: [], now: at(10, 12)))
        XCTAssertTrue(e.isEmpty, "with no Coach records the page shows its empty state, not sample text")
    }

    func testEntriesAreTheRecordsInTimeOrder() {
        let w = workout()
        let summary = AdaptationSummary(at: at(10, 7), confidence: .medium, findings: ["Three sessions done this week.", "Ride load up on last week."],
                                        feedbackRequest: "How did Tuesday's ride feel?", painAdvice: "Knee: lower-body load is held.")
        let applied = adjustment(w, created: at(9, 18))
        let held = adjustment(w, created: at(10, 7))
        let proposal = AdaptiveProposal(id: "hold|x", reason: .heldIncrease, text: "Add a set?", why: "Increases like this one need your OK.", adjustments: [held])
        let advice = AdaptiveProposal(id: "split", reason: .split, text: "Consider an upper/lower split.", why: "Four strength days.")
        let accepted = AppliedProposal(id: "old", text: "Move Friday's ride to Saturday", before: w, appliedAt: at(8, 20))
        let e = CoachTimeline.entries(.init(summary: summary, proposals: [proposal, advice], applied: [applied], accepted: [accepted], now: at(10, 12)))

        XCTAssertEqual(e.map(\.kind), [.decision, .outcome, .observation, .observation, .recovery, .question, .proposal, .recommendation])
        XCTAssertEqual(e.map(\.at), e.map(\.at).sorted(), "oldest first")
        XCTAssertEqual(e[0].author, .athlete); XCTAssertEqual(e[0].text, "Approved: Move Friday's ride to Saturday")
        XCTAssertEqual(e[1].text, "Thu ride: 60 → 50 min"); XCTAssertEqual(e[1].detail, "Two hard sessions in three days."); XCTAssertEqual(e[1].opens, .adjustments)
        XCTAssertEqual(e[2].text, "Three sessions done this week."); XCTAssertNil(e[2].opens)
        XCTAssertEqual(e[6].opens, .proposal("hold|x"), "a proposal that changes the plan opens its approval")
        XCTAssertEqual(e[7].kind, .recommendation, "a proposal with no change of its own is advice, not a decision")
        XCTAssertEqual(Set(e.map(\.id)).count, e.count, "every entry has its own identifier")
        // nothing beyond the records: 1 accepted + 1 applied + 2 findings + pain + question + 2 proposals
        XCTAssertEqual(e.count, 8)
    }

    /// 18 Nov 2026: Plan showed "Coach suggests · Review" for a finding the Coach page did not list, and Review opened
    /// the list of applied changes. One item now feeds Home, Plan and the Coach page.
    func testTheItemShownOnHomeAndPlanIsAlsoOnTheCoachPage() {
        let gap = HomeCoachItem(source: .gap, title: "Not trained in 4 weeks of detailed logs: hinge.", evidence: "estimate", actionLabel: "Open Plan")
        XCTAssertFalse(gap.needsDecision); XCTAssertEqual(gap.planHeading, "COACH NOTES"); XCTAssertEqual(gap.planAction, "Open")
        var e = CoachTimeline.entries(.init(summary: nil, proposals: [], applied: [], accepted: [], now: at(10, 12), current: gap))
        XCTAssertEqual(e.map(\.kind), [.observation]); XCTAssertEqual(e[0].text, gap.title); XCTAssertNil(e[0].opens, "a finding asks for no decision")

        let hyb = HomeCoachItem(source: .hybridProposal("p1"), title: "Coach suggests: Move Friday's ride", evidence: "Two hard days in a row.", actionLabel: "Accept")
        XCTAssertTrue(hyb.needsDecision); XCTAssertEqual(hyb.planHeading, "COACH SUGGESTS"); XCTAssertEqual(hyb.planAction, "Review")
        XCTAssertEqual(hyb.plainTitle, "Move Friday's ride")
        e = CoachTimeline.entries(.init(summary: nil, proposals: [], applied: [], accepted: [], now: at(10, 12), current: hyb))
        XCTAssertEqual(e.map(\.kind), [.proposal]); XCTAssertEqual(e[0].opens, .hybrid("p1"), "its own approval sheet stays reachable")

        // a proposal of the adaptation engine is already a record: it is not listed twice
        let p = AdaptiveProposal(id: "split", reason: .split, text: "Consider an upper/lower split.", why: "Four strength days.")
        let own = HomeCoachItem(source: .adaptiveProposal("split"), title: "Coach suggests: \(p.text)", evidence: nil, actionLabel: "Details")
        e = CoachTimeline.entries(.init(summary: nil, proposals: [p], applied: [], accepted: [], now: at(10, 12), current: own))
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(HomeCoachItem(source: .adjustment(UUID()), title: "x", evidence: nil, actionLabel: nil).planHeading, "COACH CHANGED")
    }

    func testProposalWithoutAnAnalysisStandsAtNow() {
        let p = AdaptiveProposal(id: "p", reason: .budget, text: "Lengthen Sunday's ride by 10 min?", why: "Within your budget.", adjustments: [adjustment(workout(), created: at(10, 7))])
        let e = CoachTimeline.entries(.init(summary: nil, proposals: [p], applied: [], accepted: [], now: at(10, 12)))
        XCTAssertEqual(e.map(\.at), [at(10, 12)])
    }

    func testDaysGroupInOrderAndNameToday() {
        let w = workout()
        let e = CoachTimeline.entries(.init(summary: AdaptationSummary(at: at(10, 7), confidence: .low, findings: ["A"]), proposals: [],
                                            applied: [adjustment(w, created: at(9, 18))], accepted: [], now: at(10, 12)))
        let d = CoachTimeline.days(e, now: at(10, 12), calendar: cal)
        XCTAssertEqual(d.map(\.day), ["Mon 9 Nov", "Today · Tue 10 Nov"])
        XCTAssertEqual(d.map { $0.entries.count }, [1, 1])
    }
}
