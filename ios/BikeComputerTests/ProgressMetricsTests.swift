import XCTest
@testable import BikeComputer

/// RC2-UX milestone 1: Progress chart maths (measured axis labels, ticks, selection detail, empty and partial weeks,
/// at-a-glance cards) and the Plan helpers (session states, working budget fixes). Pure: also run on Linux.
final class ProgressMetricsTests: XCTestCase {
    private let cal = Calendar.current
    private var monday: Date { TrainingLedger.monday(of: Date()) }
    private func weeks(_ n: Int, _ make: (Int, Date) -> WeekBucket = { _, d in WeekBucket(start: d, minutes: 0, sessions: 0) }) -> [WeekBucket] {
        (0..<n).map { i in make(i, cal.date(byAdding: .day, value: -7 * (n - 1 - i), to: monday)!) }
    }

    // MARK: axis labels: never overlapping, never clipped, at every width, range and text size
    func testAxisLabelsNeverOverlapOrLeaveThePlot() {
        // label widths per character: caption at Large (≈ 6 pt), xxLarge (≈ 8 pt) and a pessimistic 10 pt
        for perChar in [6.0, 8.0, 10.0] {
            for plot in [150.0, 200, 250, 270, 290, 310, 335, 380] {
                for r in ChartRange.allCases {
                    let b = weeks(r.weeks)
                    let labels = TrendChartMath.axisLabels(b.map { $0.start }, plotWidth: plot, gap: 8, rightRoom: 20, width: { Double($0.count) * perChar })
                    XCTAssertFalse(labels.isEmpty, "\(r) plot \(plot) perChar \(perChar): at least one date")
                    for l in labels {
                        XCTAssertGreaterThanOrEqual(l.centre - l.width / 2, -0.001, "\(r) \(plot): clipped left")
                        XCTAssertLessThanOrEqual(l.centre + l.width / 2, plot + 20.001, "\(r) \(plot): clipped right")
                    }
                    for (a, c) in zip(labels, labels.dropFirst()) {
                        XCTAssertGreaterThanOrEqual(c.centre - c.width / 2 - (a.centre + a.width / 2), 8 - 0.001, "\(r) \(plot) perChar \(perChar): \(a.text) / \(c.text) closer than 8 pt")
                    }
                    // one rhythm: equal steps between labels
                    let steps = Set(zip(labels, labels.dropFirst()).map { $1.index - $0.index })
                    XCTAssertLessThanOrEqual(steps.count, 1, "\(r) \(plot): one stride")
                }
            }
        }
        // the owner's iPhone (393 pt, plot ≈ 290 pt), Large text: 4 weeks every week, 16 weeks every 3rd or 4th, 1 year 4–5 dates
        let w = { (s: String) in Double(s.count) * 6.5 }
        XCTAssertEqual(TrendChartMath.axisLabels(weeks(4).map { $0.start }, plotWidth: 290, rightRoom: 20, width: w).count, 4)
        let l16 = TrendChartMath.axisLabels(weeks(16).map { $0.start }, plotWidth: 290, rightRoom: 20, width: w)
        XCTAssertTrue((4...6).contains(l16.count), "\(l16.map { $0.text })")
        XCTAssertEqual(l16.last?.index, 15, "the current week is labelled")
        let l52 = TrendChartMath.axisLabels(weeks(52).map { $0.start }, plotWidth: 290, rightRoom: 20, width: w)
        XCTAssertTrue((3...6).contains(l52.count), "\(l52.map { $0.text })")
    }

    func testTicksAndAxisText() {
        XCTAssertEqual(TrendChartMath.minuteTicks(maxMinutes: 0), [0, 30])
        XCTAssertEqual(TrendChartMath.minuteTicks(maxMinutes: 100), [0, 30, 60, 90, 120])
        XCTAssertEqual(TrendChartMath.minuteTicks(maxMinutes: 150), [0, 60, 120, 180])
        XCTAssertEqual(TrendChartMath.minuteTicks(maxMinutes: 300), [0, 120, 240, 360])
        XCTAssertEqual(TrendChartMath.countTicks(maxCount: 0), [0, 1, 2])
        XCTAssertEqual(TrendChartMath.countTicks(maxCount: 5), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(TrendChartMath.countTicks(maxCount: 7), [0, 2, 4, 6, 8])
        XCTAssertEqual(TrendChartMath.minuteAxisText(0), "0"); XCTAssertEqual(TrendChartMath.minuteAxisText(30), "30 min")
        XCTAssertEqual(TrendChartMath.minuteAxisText(60), "1 h"); XCTAssertEqual(TrendChartMath.minuteAxisText(90), "1 h 30")
        for m in [0, 45, 100, 150, 299, 600, 1500] { XCTAssertLessThanOrEqual(TrendChartMath.minuteTicks(maxMinutes: m).count, 5, "\(m)") }
    }

    // MARK: ranges, selection, empty and partial data
    func testRangesSelectionAndPartialWeeks() {
        var b = weeks(104)
        XCTAssertEqual(ChartRange.available(b), [.w4, .w8, .w12, .w16], "no 1-year range without older data")
        b[10].sessions = 1; b[10].minutes = 40
        XCTAssertEqual(ChartRange.available(b), ChartRange.allCases)
        XCTAssertTrue(TrendChartMath.isEmpty(TrendChartMath.window(b, weeks: 8)))
        XCTAssertEqual(TrendChartMath.window(b, weeks: 8).count, 8); XCTAssertEqual(TrendChartMath.window(b, weeks: 8).last?.start, monday)

        // this week: 1 h 03 over 3 rides, 4 h planned over 3; one ride marked done without a duration
        let wk = WeekBucket(start: monday, minutes: 63, sessions: 3, km: 20.9, unknownDuration: 1, plannedSessions: 3, plannedMinutes: 240)
        let d = TrendChartMath.detail(wk, metric: .riding)
        XCTAssertTrue(d.title.hasPrefix("This week so far · "), d.title)
        XCTAssertEqual(d.value, "1 h 3 min")
        XCTAssertEqual(d.done, "Done: 1 h 3 min · 3 rides · 20.9 km")
        XCTAssertEqual(d.planned, "Planned: 4 h · 3 rides")
        XCTAssertEqual(d.note, "1 marked done without a duration: counted as a session, adds no time.")
        let lift = WeekBucket(start: cal.date(byAdding: .day, value: -7, to: monday)!, minutes: 1, sessions: 1, plannedSessions: 5, plannedMinutes: 210)
        let dl = TrendChartMath.detail(lift, metric: .strength)
        XCTAssertTrue(dl.title.hasPrefix("Week of "), dl.title)
        XCTAssertEqual(dl.value, "1 session"); XCTAssertEqual(dl.done, "Done: 1 session · 1 min recorded"); XCTAssertEqual(dl.planned, "Planned: 5 sessions · 3 h 30 min")
        XCTAssertNil(dl.note)
        XCTAssertEqual(TrendChartMath.detail(WeekBucket(start: monday, minutes: 0, sessions: 0), metric: .riding).planned, "Planned: nothing")

        // summary: the running week is left out of the average, kept in the totals
        let v = weeks(4) { i, d in WeekBucket(start: d, minutes: [60, 120, 0, 30][i], sessions: [1, 2, 0, 1][i]) }
        let s = TrendChartMath.rangeSummary(v, metric: .riding)
        XCTAssertEqual(s.title, "Average per week"); XCTAssertEqual(s.value, "1 h")
        XCTAssertTrue(s.line.contains("total 3 h 30 min · 4 rides · average of 3 full weeks"), s.line)
        let ss = TrendChartMath.rangeSummary(v, metric: .strength)
        XCTAssertEqual(ss.value, "1 session"); XCTAssertTrue(ss.line.contains("lifted in 2 of 3 full weeks"), ss.line)
        XCTAssertEqual(TrendChartMath.rangeSummary(weeks(1), metric: .riding).title, "This week so far")
    }

    // MARK: at a glance
    func testGlanceCards() {
        let riding = weeks(16) { i, d in WeekBucket(start: d, minutes: i == 15 ? 63 : (i % 2 == 0 ? 320 : 200), sessions: i == 15 ? 3 : 3, plannedSessions: 3, plannedMinutes: 240) }
        let lifting = weeks(16) { i, d in WeekBucket(start: d, minutes: i == 15 ? 1 : 40, sessions: i == 15 ? 1 : (i == 12 ? 0 : 2), plannedSessions: i == 15 ? 5 : 2, plannedMinutes: 120) }
        let g = ProgressGlance.make(.init(riding: riding, lifting: lifting, showRiding: true, showLifting: true, setsThisWeek: 0, ridingTargetMinutes: 300,
                                          ftpW: 235, ftpBadge: "entered", best20Recent: 240, best20Before: 232))
        XCTAssertEqual(g.cards.map { $0.id }, ["glanceRiding", "glanceStrength", "glanceFrequency", "glanceGoal", "glanceFTP"])
        XCTAssertEqual(g.cards[0].value, "1 h 3 min"); XCTAssertEqual(g.cards[0].detail, "of 4 h planned · 3 rides · 4-wk avg 4 h 20 min")
        XCTAssertEqual(g.cards[1].value, "1 of 5"); XCTAssertEqual(g.cards[1].detail, "sessions done of planned · 1 min recorded · lifted in 7 of the last 8 weeks")
        XCTAssertEqual(g.cards[2].value, "4"); XCTAssertEqual(g.cards[2].detail, "3 rides + 1 lift · 4.5 a week over the last 4 weeks")
        XCTAssertEqual(g.cards[3].value, "2 of 4")
        XCTAssertEqual(g.cards[4].detail, "entered · best 20 min 240 W in the last 8 weeks, +8 W on the 8 weeks before")
        // a new rider: no averages over weeks that did not exist
        let new = ProgressGlance.make(.init(riding: weeks(16) { i, d in WeekBucket(start: d, minutes: i == 15 ? 60 : 0, sessions: i == 15 ? 1 : 0) }, lifting: weeks(16),
                                            showRiding: true, showLifting: false, setsThisWeek: 0, ridingTargetMinutes: 300, ftpW: 200, ftpBadge: "estimated · unverified", best20Recent: nil, best20Before: nil))
        XCTAssertEqual(new.cards.map { $0.id }, ["glanceRiding", "glanceFrequency", "glanceGoal", "glanceFTP"])
        XCTAssertEqual(new.cards[0].detail, "nothing planned · 1 ride")
        XCTAssertEqual(new.cards[1].detail, "averages start after your first full week")
        XCTAssertEqual(new.cards[2].detail, "measured after your first full week")
        XCTAssertTrue(new.cards[3].detail.hasSuffix("no ride with power in the last 16 weeks"))
    }

    // MARK: Plan: session states and working budget fixes
    private func at(_ day: Int) -> Date { cal.date(byAdding: .hour, value: 7, to: cal.date(byAdding: .day, value: day, to: cal.startOfDay(for: Date()))!)! }

    func testSessionStates() {
        var w = Workout(date: at(-1), kind: .endurance, minutes: 60)
        XCTAssertEqual(SessionState.of(w, status: .planned), .missed)
        XCTAssertEqual(SessionState.of(w, status: .completedManual), .completed("done"))
        XCTAssertEqual(SessionState.of(w, status: .skipped), .skipped)
        w.date = at(1); XCTAssertEqual(SessionState.of(w, status: .planned), .scheduled)
        w.edited = true; XCTAssertEqual(SessionState.of(w, status: .planned), .modified)
        XCTAssertEqual(SessionState.of(Workout(date: at(-2), kind: .rest, minutes: 0), status: .planned), .scheduled, "rest is never missed")
        XCTAssertEqual(SessionState.of(Workout(date: at(0), kind: .strength, minutes: 40), status: .inProgress), .inProgress)
        XCTAssertEqual(SessionState.of(Workout(date: at(0), kind: .strength, minutes: 40), status: .completedLogged).pill, "logged")
    }

    func testNoDurationSessionsAreNamedTheSameOnPlanAndProgress() {
        var w = TrainingLedger.SportWeek(monday: monday)
        w.planned = 5; w.plannedMinutes = 210; w.completed = 2; w.manual = 2; w.minutes = 0; w.unknownDuration = 2
        XCTAssertEqual(WeekTotals.done(w, singular: "session", plural: "sessions"), "0 min · 2 sessions of 5 planned (2 without duration)")
        let b = WeekBucket(start: monday, minutes: 0, sessions: 2, unknownDuration: 2, plannedSessions: 5, plannedMinutes: 210)
        let g = ProgressGlance.make(.init(riding: [], lifting: [b], showRiding: false, showLifting: true, setsThisWeek: 0, ridingTargetMinutes: 0,
                                          ftpW: 200, ftpBadge: "entered", best20Recent: nil, best20Before: nil))
        XCTAssertEqual(g.cards.first?.value, "2 of 5")
        XCTAssertEqual(g.cards.first?.detail, "sessions done of planned · no time recorded · 2 without duration")
        XCTAssertEqual(TrendChartMath.detail(b, metric: .strength).note, "2 marked done without a duration: counted as sessions, adds no time.")
    }

    func testBudgetFixActuallyFixes() {
        // the owner's lifting week: 5 sessions, 3 h 30 planned against a 2 h budget; two are already done
        let done1 = Workout(date: at(-1), kind: .strength, minutes: 45), done2 = Workout(date: at(-1), kind: .strength, minutes: 45)
        let today = Workout(date: at(0), kind: .strength, minutes: 40), sat = Workout(date: at(2), kind: .strength, minutes: 40)
        let extra = Workout(date: at(1), kind: .strength, minutes: 40)
        let week = [done1, done2, today, extra, sat, Workout(date: at(1), kind: .endurance, minutes: 60)]
        let doneIds: Set<UUID> = [done1.id, done2.id]
        let r = BudgetFix.report(week: week, riding: false, budgetHours: 2, isCompleted: { doneIds.contains($0.id) })!
        XCTAssertEqual(r.plannedMinutes, 210); XCTAssertEqual(r.overMinutes, 90)
        XCTAssertTrue(r.explanation.hasPrefix("Planned lifting this week is 3 h 30 min in 5 sessions; your weekly lifting budget is 2 h, so the week is 1 h 30 min over."), r.explanation)
        // no single 40-minute session can absorb 90 minutes: only the budget raise is offered, and the text says why
        XCTAssertEqual(r.fixes.map { $0.action }, [.raiseBudget(hours: 4)])
        XCTAssertTrue(r.explanation.contains("No single remaining session"), r.explanation)
        // a week 20 min over with a long ride left: shorten it, or skip a session that covers the excess, or raise the budget
        let past = Workout(date: at(-2), kind: .endurance, minutes: 80)
        let long = Workout(date: at(2), kind: .long, minutes: 150), easy = Workout(date: at(3), kind: .recovery, minutes: 30)
        let r2 = BudgetFix.report(week: [past, long, easy], riding: true, budgetHours: 4, isCompleted: { $0.id == past.id })!
        XCTAssertEqual(r2.fixes.map { $0.action }, [.shorten(long.id, to: 130), .skip(easy.id), .raiseBudget(hours: 5)])
        // applying each offered fix really brings the week within budget
        for f in r2.fixes {
            var wk = [past, long, easy]
            var hours = 4
            switch f.action {
            case .shorten(let id, let to): if let i = wk.firstIndex(where: { $0.id == id }) { wk[i].minutes = to }
            case .skip(let id): if let i = wk.firstIndex(where: { $0.id == id }) { wk[i].skipped = true }
            case .raiseBudget(let h): hours = h
            }
            XCTAssertNil(BudgetFix.report(week: wk, riding: true, budgetHours: hours, isCompleted: { _ in false }), "\(f.text) leaves the week over budget")
        }
        // everything over the budget already done: the text says nothing this week can bring it under
        let allDone = BudgetFix.report(week: [past, long], riding: true, budgetHours: 3, isCompleted: { _ in true })!
        XCTAssertEqual(allDone.fixes.count, 1); XCTAssertTrue(allDone.explanation.contains("nothing left this week can bring it under"), allDone.explanation)
        // within budget, or no budget: nothing to fix
        XCTAssertNil(BudgetFix.report(week: [long], riding: true, budgetHours: 5, isCompleted: { _ in false }))
        XCTAssertNil(BudgetFix.report(week: [today, sat], riding: false, budgetHours: 0, isCompleted: { _ in false }))
    }
}
