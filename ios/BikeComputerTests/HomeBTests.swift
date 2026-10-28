import XCTest
@testable import BikeComputer

/// Home Option B (coord/specs/HOME_B_SPEC.md v2.1): the state → primary-action mapping (card and centre button), health
/// holds, the coach-slot priority, the weekly counts that Home, Plan and Progress share (N1), one ride completes one
/// planned ride, and Move to another day with Undo.
final class HomeBTests: XCTestCase {
    private let cal = Calendar.current
    private var today: Date { cal.startOfDay(for: Date()) }
    private func at(_ dayOffset: Int, _ hour: Int = 7) -> Date { cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: dayOffset, to: today)!)! }
    private func store(mode: TrainingMode = .hybrid, health: HealthScreen.Status = .clear) -> Store {
        let s = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent("homeb-\(UUID().uuidString)"), generatePlan: false)
        var p = s.profile
        p.trainingMode = mode
        var h = HealthScreen()
        h.answeredAt = Date().addingTimeInterval(-3600)
        switch health {
        case .clear, .cleared: break
        case .notAnswered: h.answeredAt = nil
        case .needsClearance: h.heartOrBloodPressure = true
        case .stop: h.chestPain = true
        case .paused: h.currentIllness = true
        }
        p.healthScreen = h
        s.profile = p
        return s
    }
    private func home(_ s: Store, recorder: Bool = false) -> HomeToday { s.homeToday(now: at(0, 10), recorderActive: recorder) }
    private func single(_ h: HomeToday, file: StaticString = #filePath, line: UInt = #line) -> HomeSession? {
        if case .single(let x) = h.layout { return x }
        XCTFail("expected one session, got \(h.layout)", file: file, line: line); return nil
    }

    // MARK: state → primary action (and the centre button reaches the same place)
    func testPrimaryActionFollowsTheSessionState() {
        let s = store()
        let lift = Workout(date: at(0), kind: .strength, minutes: 40, strengthFocus: .fullBody)
        s.plan = [lift]
        var h = home(s)
        XCTAssertEqual(single(h)?.action, .startStrength(lift.id)); XCTAssertEqual(h.primary.label(), "Start workout")
        XCTAssertEqual(h.centre, .perform(.startStrength(lift.id)), "Train now opens the same logger as the card")
        XCTAssertNil(single(h)?.status.chip); XCTAssertEqual(single(h)?.subtitle, "40 min · Moderate")
        // in progress → Resume (StrengthWorkoutScreen, N11); no coach card while training
        var a = StrengthSession(date: at(0, 9), minutes: 0, focus: .fullBody, workoutId: lift.id); a.startedAt = at(0, 9)
        s.activeSession = a
        h = home(s)
        XCTAssertEqual(single(h)?.status, .inProgress); XCTAssertEqual(h.primary, .resumeStrength(lift.id)); XCTAssertEqual(h.centre, .perform(.resumeStrength(lift.id)))
        XCTAssertFalse(single(h)!.canChange, "N10: no Skip / Move / Swap while in progress"); XCTAssertFalse(h.showCoach)
        // logged → View results (never Start for a completed session)
        s.activeSession = nil
        let ex = ExerciseEntry(exercise: Exercise(id: "hb-sq", name: "Goblet squat", equipment: ["dumbbell"], pattern: .squat, unilateral: false, custom: true), sets: [SetEntry(reps: 8, weightKg: 20, done: true)])
        let log = StrengthSession(date: at(0, 9), minutes: 42, focus: .fullBody, rpe: 7, exercises: [ex], workoutId: lift.id)
        s.strength = [log]
        h = home(s)
        XCTAssertEqual(single(h)?.status, .done); XCTAssertEqual(h.primary, .strengthResults(log.id)); XCTAssertEqual(h.primary.label(), "View results")
        XCTAssertEqual(h.centre, .sheet, "done today → the optional-session sheet")
        // marked done without details → Add details
        s.strength = []; var m = lift; m.done = true; m.completion = .marked; s.plan = [m]
        h = home(s)
        XCTAssertEqual(single(h)?.status, .marked); XCTAssertEqual(h.primary, .addDetails(lift.id)); XCTAssertEqual(single(h)?.status.chip, "Done · no details")
        // skipped → Move to another day
        var k = lift; k.skipped = true; s.plan = [k]
        h = home(s)
        XCTAssertEqual(single(h)?.status, .skipped); XCTAssertEqual(h.primary, .reschedule(lift.id)); XCTAssertEqual(h.primary.label(), "Move to another day")
        // rest day → Recovery guidance; the centre opens the optional-session sheet
        s.plan = [Workout(date: at(0), kind: .rest, minutes: 0)]
        s.rides = [RideRecord(start: at(-10, 8), durationS: 3600, distanceM: 1, recorder: .phone, sources: [])]       /* not a first-time rider */
        h = home(s)
        XCTAssertEqual(h.primary, .recoveryGuidance); XCTAssertEqual(h.centre, .sheet)
    }

    func testRideStatesNeverStartRecording() {
        let s = store(mode: .cycling)
        let ride = Workout(date: at(0), kind: .endurance, minutes: 60)
        s.plan = [ride]
        var h = home(s)
        XCTAssertEqual(h.primary, .openRideScreen, "N4: Start ride opens the Ride screen only"); XCTAssertEqual(h.primary.label(), "Start ride")
        XCTAssertEqual(single(h)?.subtitle, "1 h · Easy · Zone 2")
        h = home(s, recorder: true)
        XCTAssertEqual(single(h)?.status, .inProgress); XCTAssertEqual(h.primary, .openLiveRide); XCTAssertEqual(h.primary.label(elapsed: 1084), "Open ride · 18:04")
        let r = RideRecord(start: at(0, 8), durationS: 3600, distanceM: 30_000, recorder: .phone, sources: ["Phone GPS"])
        s.rides = [r]
        h = home(s)
        XCTAssertEqual(h.primary, .rideResults(r.id))
    }

    func testHealthHoldsTakePrecedence() {
        for (status, hold) in [(HealthScreen.Status.stop, HomeHold.stop), (.paused, .ill)] {
            let s = store(health: status)
            s.plan = [Workout(date: at(0), kind: .strength, minutes: 40)]          /* even a session left on the plan */
            let h = home(s)
            XCTAssertEqual(h.layout, .hold(hold)); XCTAssertEqual(h.primary, .reviewHealth); XCTAssertEqual(h.centre, .hold, "Train now opens the hold sheet")
            XCTAssertFalse(h.showCoach); XCTAssertNil(h.missed)
            XCTAssertEqual(s.todayAction(now: at(0, 10)), .healthHold)
        }
        let sup = store(health: .stop); var hs = sup.profile.healthScreen!; hs.chestPain = false; hs.supervisedOnly = true; sup.profile.healthScreen = hs
        XCTAssertEqual(home(sup).layout, .hold(.supervised))
        // pending / clearance: a caution line, the session stays with its capped intensity
        let p = store(health: .notAnswered)
        p.plan = [Workout(date: at(0), kind: .strength, minutes: 40)]
        let h = home(p)
        XCTAssertEqual(h.caution, .pending(questions: HealthScreen.questions.count)); XCTAssertEqual(single(h)?.subtitle, "40 min · Moderate")
        XCTAssertTrue(h.caution!.title.contains("\(HealthScreen.questions.count) questions"))
        let c = store(health: .needsClearance)
        c.plan = [Workout(date: at(0), kind: .strength, minutes: 40)]
        XCTAssertEqual(home(c).caution, .clearance); XCTAssertEqual(single(home(c))?.subtitle, "40 min · Light", "RPE capped at 6 until clearance")
    }

    func testFirstMultiMissedAndFree() {
        // first: nothing planned, no history
        let f = store(mode: .strength)
        XCTAssertEqual(home(f).layout, .first(liftFirst: true)); XCTAssertEqual(home(f).primary, .createPlan); XCTAssertFalse(home(f).showWeek)
        // multi: one row per session, its own action; the centre button acts on the one open session
        let s = store()
        let r = Workout(date: at(0), kind: .recovery, minutes: 30, sequence: 0)
        let l = Workout(date: at(0), kind: .strength, minutes: 35, strengthFocus: .upper, sequence: 1)
        s.plan = [r, l]
        s.rides = [RideRecord(start: at(0, 7), durationS: 1800, distanceM: 9000, recorder: .phone, sources: [])]
        var h = home(s)
        guard case .multi(let rows) = h.layout else { return XCTFail("\(h.layout)") }
        XCTAssertEqual(rows.map { $0.status }, [.done, .planned]); XCTAssertEqual(rows[1].action, .startStrength(l.id))
        XCTAssertEqual(h.primary, .startStrength(l.id)); XCTAssertEqual(h.centre, .perform(.startStrength(l.id)))
        // missed (derived): planned, not done, not skipped, its day passed; today free → Move to today
        let m = Workout(date: at(-1), kind: .endurance, minutes: 60)
        let m2 = Workout(date: at(-3), kind: .strength, minutes: 40)
        s.plan = [m2, m, Workout(date: at(0), kind: .rest, minutes: 0)]; s.rides = []
        h = home(s)
        XCTAssertEqual(h.missed?.id, m.id, "the most recent missed one"); XCTAssertEqual(h.missed?.status, .missed); XCTAssertEqual(h.moreMissed, 1)
        XCTAssertEqual(h.primary, .moveToToday(m.id))
        // a strength session started without a plan
        let g = store(); g.plan = [Workout(date: at(0), kind: .rest, minutes: 0)]
        var a = StrengthSession(date: at(0, 9), minutes: 0, focus: .fullBody); a.startedAt = at(0, 9); g.activeSession = a
        XCTAssertEqual(home(g).layout, .freeSession); XCTAssertEqual(home(g).centre, .perform(.resumeStrength(nil)))
    }

    // MARK: coach frequency wording uses the week card's terms: done, still to come, target (owner 28 Oct; wording only)
    func testCoachFrequencyGapWording() {
        XCTAssertEqual(HybridCoach.frequencyGapText(sport: "Rides", done: 0, toCome: 1, target: 3, unit: ("ride", "rides")),
                       "Rides this week: 0 done and 1 still to come, 2 short of your target of 3 rides a week.")
        XCTAssertEqual(HybridCoach.frequencyGapText(sport: "Lifts", done: 1, toCome: 0, target: 2, unit: ("lift", "lifts")),
                       "Lifts this week: 1 done and 0 still to come, 1 short of your target of 2 lifts a week.")
        XCTAssertFalse(HybridCoach.frequencyGapText(sport: "Rides", done: 0, toCome: 1, target: 3, unit: ("ride", "rides")).dropLast().contains("."), "one sentence: Home shows it whole")
    }

    // MARK: Skip / Unskip from More are hand edits with Undo (lead review)
    func testSkipFromMoreHasUndoAndIsARiderEdit() {
        let s = store()
        let w = Workout(date: at(0, 18), kind: .strength, minutes: 40, strengthFocus: .fullBody)
        s.plan = [w]
        XCTAssertTrue(s.setSkipped(w.id, true))
        XCTAssertTrue(s.plan[0].skipped); XCTAssertTrue(s.plan[0].edited, "a skip is the rider's own change")
        XCTAssertEqual(s.undoToast?.text.hasSuffix("skipped"), true)
        XCTAssertFalse(s.setSkipped(w.id, true), "skipping twice changes nothing")
        if let t = s.undoToast { XCTAssertTrue(s.undoDelete(t.id)) }
        XCTAssertFalse(s.plan[0].skipped, "Undo restores the session exactly")
        XCTAssertFalse(s.plan[0].edited)
        XCTAssertTrue(s.setSkipped(w.id, true)); XCTAssertTrue(s.setSkipped(w.id, false))
        XCTAssertFalse(s.plan[0].skipped)
    }

    // MARK: one recorded ride completes ONE planned ride
    func testOneRideCompletesOnePlannedRide() {
        let s = store(mode: .cycling)
        let a = Workout(date: at(0), kind: .recovery, minutes: 30, sequence: 0), b = Workout(date: at(0), kind: .endurance, minutes: 60, sequence: 1)
        s.plan = [a, b]
        s.rides = [RideRecord(start: at(0, 8), durationS: 1800, distanceM: 9000, recorder: .phone, sources: [])]
        XCTAssertTrue(s.status(a).isCompleted); XCTAssertFalse(s.status(b).isCompleted, "the second planned ride stays open")
        let w = WeekTotals(s.ledger, weekOf: at(0))
        XCTAssertEqual(w.riding.plannedDone, 1); XCTAssertEqual(w.riding.extra, 0)
        s.rides.append(RideRecord(start: at(0, 18), durationS: 3600, distanceM: 20000, recorder: .phone, sources: []))
        XCTAssertTrue(s.status(b).isCompleted)
        // Store.addRide closes the first OPEN planned ride of its day, not the day's first session
        let t = store(mode: .hybrid)
        let lift = Workout(date: at(0), kind: .strength, minutes: 40, sequence: 0), ride = Workout(date: at(0), kind: .endurance, minutes: 60, sequence: 1)
        t.plan = [lift, ride]
        XCTAssertTrue(t.addRide(RideRecord(start: Date(), durationS: 600, distanceM: 1000, recorder: .phone, sources: [])))
        XCTAssertTrue(t.plan.first { $0.id == ride.id }!.done); XCTAssertFalse(t.plan.first { $0.id == lift.id }!.done)
    }

    // MARK: N1 — Home, Plan and Progress show the same weekly counts
    func testWeekCountsAgreeOnHomePlanAndProgress() {
        let s = store()
        let monday = TrainingLedger.monday(of: Date())
        func d(_ k: Int, _ h: Int = 7) -> Date { cal.date(byAdding: .hour, value: h, to: cal.date(byAdding: .day, value: k, to: monday)!)! }
        let r1 = Workout(date: d(0), kind: .endurance, minutes: 60), r2 = Workout(date: d(2), kind: .tempo, minutes: 75)
        let r3 = Workout(date: d(5), kind: .long, minutes: 120), rs = Workout(date: d(6), kind: .recovery, minutes: 30, skipped: true)
        let l1 = Workout(date: d(1), kind: .strength, minutes: 40), l2 = Workout(date: d(3), kind: .strength, minutes: 40)
        s.plan = [r1, r2, r3, rs, l1, l2]
        s.rides = [RideRecord(start: d(0, 8), durationS: 3600, distanceM: 1, recorder: .phone, sources: []),          /* completes r1 */
                   RideRecord(start: d(4, 18), durationS: 1800, distanceM: 1, recorder: .phone, sources: [])]         /* unplanned: +1 extra */
        s.strength = [StrengthSession(date: d(1, 18), minutes: 45, focus: .fullBody, rpe: 7, workoutId: l1.id)]
        let t = WeekTotals(s.ledger, weekOf: Date())
        // the parts add up
        XCTAssertEqual(t.riding.planned, 3); XCTAssertEqual(t.riding.plannedDone, 1); XCTAssertEqual(t.riding.extra, 1); XCTAssertEqual(t.riding.skipped, 1)
        XCTAssertEqual(t.lifting.planned, 2); XCTAssertEqual(t.lifting.plannedDone, 1); XCTAssertEqual(t.lifting.extra, 0)
        XCTAssertEqual(t.riding.completed, t.riding.plannedDone + t.riding.extra); XCTAssertEqual(t.lifting.completed, t.lifting.plannedDone + t.lifting.extra)
        // Home
        let w = s.homeWeek(now: Date())
        XCTAssertEqual(w.total.planned, 5); XCTAssertEqual(w.total.plannedDone, 2); XCTAssertEqual(w.line, "2 of 5 sessions done · +1 extra · 1 skipped")
        XCTAssertEqual(w.split, "Rides 1 of 3 · Lifts 1 of 2")
        // Plan (WeekTotals.done) and Progress (glance cards from the chart buckets) use the same numbers and words
        XCTAssertTrue(WeekTotals.done(t.riding, singular: "ride", plural: "rides").hasSuffix("1 of 3 rides done · +1 extra · 1 skipped"))
        let rb = TrendChartMath.buckets(s.ledger, riding: true, weeks: 4, now: Date()), lb = TrendChartMath.buckets(s.ledger, riding: false, weeks: 4, now: Date())
        XCTAssertEqual(rb.last!.plannedDone, t.riding.plannedDone); XCTAssertEqual(rb.last!.extra, t.riding.extra); XCTAssertEqual(lb.last!.plannedDone, t.lifting.plannedDone)
        let g = ProgressGlance.make(.init(riding: rb, lifting: lb, showRiding: true, showLifting: true, setsThisWeek: 0, ridingTargetMinutes: 0, ftpW: 200, ftpBadge: "entered", best20Recent: nil, best20Before: nil))
        XCTAssertTrue(g.cards[0].detail.contains("1 of 3 rides done · +1 extra · 1 skipped"), g.cards[0].detail)
        XCTAssertEqual(g.cards[1].value, "1 of 2")
        // cycling-only: no split, rides only
        let c = store(mode: .cycling); c.plan = s.plan; c.rides = s.rides; c.strength = s.strength
        XCTAssertNil(c.homeWeek().split); XCTAssertEqual(c.homeWeek().line, "1 of 3 sessions done · +1 extra · 1 skipped")
    }

    // MARK: coach slot — existing engine outputs only, fixed priority, nothing invented
    func testCoachSlotPriority() {
        var i = HomeCoachItem.Input()
        XCTAssertNil(HomeCoachItem.select(i), "no output → no card")
        i.feedbackRequest = "Only 1 rated session in the last 14 days. Rate your sessions so the coach can adjust."; i.lowConfidence = true
        XCTAssertNil(HomeCoachItem.select(i), "N13: no rating request before a session was completed without a rating")
        i.unrated = .ride(UUID())
        XCTAssertEqual(HomeCoachItem.select(i)?.actionLabel, "Rate last session"); XCTAssertEqual(HomeCoachItem.select(i)?.evidence, "Only 1 rated session in the last 14 days.")
        i.offerRevise = true; i.reviseText = "Two weeks missed half. Change the days."
        XCTAssertEqual(HomeCoachItem.select(i)?.source, .revise)
        i.gapFinding = CoachFinding(id: "g", severity: .gap, text: "A lift is missing this week. Thursday is free.")
        XCTAssertEqual(HomeCoachItem.select(i)?.source, .gap); XCTAssertEqual(HomeCoachItem.select(i)?.title, "A lift is missing this week.")
        i.ftp = FTPSuggestion(watts: 240, best20: 253, best60: nil, rideId: UUID(), rideDate: Date(), previousFTP: 225); i.currentFTP = 225
        XCTAssertEqual(HomeCoachItem.select(i)?.source, .ftp); XCTAssertEqual(HomeCoachItem.select(i)?.title, "Update FTP to 240 W?")
        // an applied change: on the card when it is today's (N6), in the slot when it is the next session's
        let todayW = UUID(), nextW = UUID()
        i.adjustments = [PlanAdjustment(workoutId: todayW, change: .minutes(delta: -5), category: .reduction, summary: "60 → 55 min", why: "Two tired check-ins. So shorter.")]
        i.todayIds = [todayW]; i.nextSessionId = todayW
        XCTAssertEqual(HomeCoachItem.select(i)?.source, .ftp, "today's change is shown on the workout card, not twice")
        i.adjustments.append(PlanAdjustment(workoutId: nextW, change: .kind(to: .tempo), category: .reduction, summary: "Threshold → Tempo", why: "Two tired check-ins in a row. Eased one level."))
        i.nextSessionId = nextW; i.nextSessionTitle = "Tue threshold"
        XCTAssertEqual(HomeCoachItem.select(i)?.source, .adjustment(nextW)); XCTAssertEqual(HomeCoachItem.select(i)?.title, "Tue threshold: Threshold → Tempo")
        XCTAssertEqual(HomeCoachItem.select(i)?.evidence, "Two tired check-ins in a row.")
        i.hybridProposals = [CoachProposal(id: "h1", text: "Move Friday's lift to Thursday", why: "Friday has a long ride.", change: .move(workoutId: UUID(), to: Date()))]
        XCTAssertEqual(HomeCoachItem.select(i)?.source, .hybridProposal("h1"))
        i.adaptiveProposals = [AdaptiveProposal(id: "a1", reason: .budget, text: "Keep this week within 5 h", why: "Planned riding is 6 h. Your budget is 5 h.")]
        XCTAssertEqual(HomeCoachItem.select(i)?.source, .adaptiveProposal("a1")); XCTAssertEqual(HomeCoachItem.select(i)?.evidence, "Planned riding is 6 h.")
    }

    // MARK: Move to another day (free days only, with Undo)
    func testRescheduleToAFreeDayWithUndo() {
        let s = store()
        let monday = TrainingLedger.monday(of: Date())
        let sunday = cal.date(byAdding: .hour, value: 7, to: cal.date(byAdding: .day, value: 6, to: monday)!)!
        var k = Workout(date: at(0), kind: .strength, minutes: 40); k.skipped = true
        s.plan = [k]
        let targets = s.moveTargets(for: k.id, now: at(0, 10))
        XCTAssertFalse(targets.contains { cal.isDate($0.date, inSameDayAs: at(0)) }, "not to its own day")
        XCTAssertEqual(targets.count, cal.dateComponents([.day], from: today, to: cal.startOfDay(for: sunday)).day!, "every later day of this week is free")
        if let day = targets.first?.date {
            XCTAssertTrue(s.reschedule(k.id, to: day, now: at(0, 10)))
            let moved = s.plan.first { $0.id == k.id }!
            XCTAssertTrue(cal.isDate(moved.date, inSameDayAs: day)); XCTAssertFalse(moved.skipped); XCTAssertTrue(moved.edited)
            XCTAssertNotNil(s.undoToast)
            XCTAssertTrue(s.undoDelete(s.undoToast!.id))
            XCTAssertEqual(s.plan.first { $0.id == k.id }, k, "Undo restores the session exactly")
        }
        // a missed session moves to today; never into the past or next week; a done session never moves
        let m = Workout(date: at(-1), kind: .endurance, minutes: 60)
        s.plan = [m]
        XCTAssertFalse(s.reschedule(m.id, to: at(-2), now: at(0, 10)))
        XCTAssertFalse(s.reschedule(m.id, to: cal.date(byAdding: .day, value: 7, to: monday)!, now: at(0, 10)))
        XCTAssertTrue(s.reschedule(m.id, to: at(0), now: at(0, 10)))
        XCTAssertTrue(cal.isDate(s.plan[0].date, inSameDayAs: at(0)))
        s.rides = [RideRecord(start: at(0, 8), durationS: 600, distanceM: 1, recorder: .phone, sources: [])]
        XCTAssertFalse(s.reschedule(m.id, to: sunday, now: at(0, 10)), "a completed session is not moved")
    }
}
