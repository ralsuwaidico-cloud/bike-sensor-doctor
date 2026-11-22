import XCTest
@testable import BikeComputer

/// Onboarding Screen 4 (owner decision 21 Nov 2026): goals follow the roster; planned and saved-only goals are kept
/// apart; any number of goals, exactly one main goal; nothing is prescribed for a sport Cyclift does not plan.
final class RosterGoalsTests: XCTestCase {
    private func titles(_ ids: [String]) -> [String] { RosterGoals.groups(roster: ids).map(\.title) }

    func testGroupsFollowTheRoster() {
        XCTAssertEqual(titles(["roadCycling"]), ["Cycling", "General"])
        XCTAssertEqual(titles(["strength"]), ["Strength", "General"])
        XCTAssertEqual(titles(["roadCycling", "strength"]), ["Cycling", "Strength", "General"])
        XCTAssertEqual(titles(["strength", "gravel"]), ["Strength", "Cycling", "General"], "roster order")
        XCTAssertEqual(titles(["running"]), ["Running", "General"])
        XCTAssertEqual(titles(["openWater"]), ["Swimming", "General"])
        XCTAssertEqual(titles(["trailRunning", "roadCycling", "swimming", "mobility"]), ["Running", "Cycling", "Swimming", "Mobility & recovery", "General"])
        XCTAssertEqual(titles([]), [], "no roster, no goals")
        XCTAssertEqual(titles(["roadCycling", "indoorCycling", "gravel"]), ["Cycling", "General"], "disciplines of one sport share its goals")
    }
    func testPlannedAndSavedOnlyAreKeptApart() {
        let g = RosterGoals.groups(roster: ["running", "roadCycling", "bodyweight"])
        XCTAssertEqual(g.map(\.planned), [false, true, false, true])          // running, cycling, strength (bodyweight only), general
        XCTAssertTrue(g[1].goals.allSatisfy { $0.planner != nil }); XCTAssertTrue(g[0].goals.allSatisfy { $0.planner == nil })
        XCTAssertEqual(g[2].goals.map(\.id), ["bodyStrength", "bodySkill"], "bodyweight without gym training gets saved-only goals, not the gym planner's")
        let gym = RosterGoals.groups(roster: ["bodyweight", "strength"])
        XCTAssertEqual(gym[0].goals.map(\.id), ["strength", "muscle", "stamina", "maintain"]); XCTAssertTrue(gym[0].planned)
        let runner = RosterGoals.groups(roster: ["running"])
        XCTAssertEqual(runner.map(\.planned), [false, false], "nothing is planned for a roster Cyclift cannot plan, the general goal included")
        XCTAssertEqual(Set(RosterGoals.all.map(\.id)).count, RosterGoals.all.count, "identifiers are unique")
        XCTAssertEqual(Set(RosterGoals.all.compactMap(\.planner)), Set(GoalID.allCases), "every planner goal is offered somewhere; none is invented")
    }

    func testManyGoalsExactlyOneMain() {
        var s = RosterGoals.Selection()
        XCTAssertNil(s.main)
        s.toggle("muscle"); XCTAssertEqual(s.main, "muscle", "the first goal chosen is the main goal")
        s.toggle("endurance"); s.toggle("runPace")
        XCTAssertEqual(s.ids, ["muscle", "endurance", "runPace"]); XCTAssertEqual(s.main, "muscle", "adding goals does not move the main goal")
        s.setMain("runPace")
        XCTAssertEqual(s.main, "runPace"); XCTAssertEqual(s.ids, ["muscle", "endurance", "runPace"], "changing the main goal deletes nothing")
        s.setMain("climbing"); XCTAssertEqual(s.main, "runPace", "only a selected goal can be main")
        s.toggle("runPace"); XCTAssertEqual(s.main, "muscle", "removing the main goal hands it to the first remaining goal")
        s.toggle("muscle"); s.toggle("endurance"); XCTAssertNil(s.main); XCTAssertTrue(s.ids.isEmpty)
    }
    func testThePlannerOnlyReceivesItsOwnGoals() {
        var s = RosterGoals.Selection(); for id in ["runPace", "endurance", "swimSpeed", "muscle"] { s.toggle(id) }
        XCTAssertEqual(s.main, "runPace")
        XCTAssertEqual(s.plannerGoals, [.endurance, .muscle]); XCTAssertEqual(s.savedOnly, ["runPace", "swimSpeed"])
        XCTAssertEqual(s.plannerMain, .endurance, "a saved-only main goal leaves the planner on the first goal it knows")
        s.setMain("muscle"); XCTAssertEqual(s.plannerMain, .muscle)
        var only = RosterGoals.Selection(); only.toggle("runRace")
        XCTAssertTrue(only.plannerGoals.isEmpty); XCTAssertNil(only.plannerMain, "nothing reaches the planner from a runner's goals")
    }
    func testGoalsOfARemovedSportGoWithIt() {
        var s = RosterGoals.Selection(); for id in ["runPace", "endurance", "muscle"] { s.toggle(id) }
        s.keep(offered: RosterGoals.groups(roster: ["roadCycling", "strength"]))
        XCTAssertEqual(s.ids, ["endurance", "muscle"]); XCTAssertEqual(s.main, "endurance")
        s.keep(offered: RosterGoals.groups(roster: ["roadCycling", "strength", "running"]))
        XCTAssertEqual(s.ids, ["endurance", "muscle"], "nothing is selected on the athlete's behalf when a sport is added")
    }

    /// The provisional categories of the owner's decision of 21 Nov 2026 (not yet reviewed, not approved).
    func testProvisionalGoalCategories() {
        func t(_ f: RosterFamily) -> [String] { (RosterGoals.savedOnly[f] ?? []).map(\.title) }
        XCTAssertEqual(t(.running), ["Distance", "Pace", "Endurance", "Race preparation"])
        XCTAssertEqual(t(.swimming), ["Technique", "Endurance", "Speed", "Event preparation"])
        XCTAssertEqual(t(.recovery), ["Flexibility", "Mobility", "Recovery"])
        XCTAssertEqual(RosterGoals.cycling.map(\.title), ["Endurance", "Power", "Climbing", "Sprint", "Event"])
        XCTAssertEqual(RosterGoals.strength.map(\.title), ["Strength", "Muscle", "Stamina", "Maintain"])
    }

    /// A plan exists only for a planned activity AND a goal of its own that the athlete chose. Nothing is chosen for them.
    func testWhenAPlanCanBeBuilt() {
        func sel(_ ids: [String]) -> RosterGoals.Selection { var s = RosterGoals.Selection(); ids.forEach { s.toggle($0) }; return s }
        XCTAssertTrue(RosterGoals.canPlan(roster: ["roadCycling"], selection: sel(["endurance"])))
        XCTAssertTrue(RosterGoals.canPlan(roster: ["roadCycling", "running"], selection: sel(["runPace", "endurance"])))
        XCTAssertTrue(RosterGoals.canPlan(roster: ["strength"], selection: sel(["fitness"])), "the general goal is the planner's own")
        XCTAssertFalse(RosterGoals.canPlan(roster: ["running"], selection: sel(["runPace"])), "a runner has no plan")
        XCTAssertFalse(RosterGoals.canPlan(roster: ["running"], selection: sel(["fitness"])), "the general goal does not turn a runner into a cyclist")
        XCTAssertFalse(RosterGoals.canPlan(roster: ["roadCycling", "running"], selection: sel(["runPace"])), "a cycling goal is never added for the athlete")
        XCTAssertFalse(RosterGoals.canPlan(roster: ["roadCycling"], selection: sel([])))
    }

    func testExplanations() {
        var s = RosterGoals.Selection(); s.toggle("muscle")
        let m = RosterGoals.explanation(main: s.main, roster: ["roadCycling", "strength"], selection: s)
        XCTAssertEqual(m?.title, "Muscle · main goal"); XCTAssertEqual(m?.text, GoalInfo.effect(.muscle), "a planned goal is explained by the planner's own rule")
        XCTAssertNil(RosterGoals.explanation(main: nil, roster: ["roadCycling"], selection: RosterGoals.Selection()))
        // a runner: saved, plans coming soon, nothing prescribed
        var r = RosterGoals.Selection(); r.toggle("runPace")
        let run = RosterGoals.explanation(main: r.main, roster: ["running"], selection: r)
        XCTAssertEqual(run?.title, "Pace · main goal")
        XCTAssertEqual(run?.text, "Your running goals are saved. Personalized running plans are coming soon. You can finish setting up without a training plan.")
        // the general goal for a runner is not explained with riding and lifting
        var f = RosterGoals.Selection(); f.toggle("fitness")
        let fit = RosterGoals.explanation(main: f.main, roster: ["running"], selection: f)?.text ?? ""
        XCTAssertTrue(fit.contains("coming soon")); XCTAssertFalse(fit.contains("riding") || fit.contains("lifting"))
        // a running goal beside a planned sport, no cycling goal chosen: how to get a plan is said; nothing is chosen
        var mix = RosterGoals.Selection(); mix.toggle("runPace")
        XCTAssertEqual(RosterGoals.explanation(main: mix.main, roster: ["running", "roadCycling"], selection: mix)?.text,
                       "Your running goals are saved. Personalized running plans are coming soon. Choose a goal for a sport Cyclift plans today if you also want a plan now.")
        mix.toggle("endurance")
        XCTAssertEqual(RosterGoals.explanation(main: mix.main, roster: ["running", "roadCycling"], selection: mix)?.text,
                       "Your running goals are saved. Personalized running plans are coming soon. Your plan today follows Endurance.")
        // no saved-only explanation ever carries a prescription or technical wording
        for g in RosterGoals.all where g.planner == nil {
            var x = RosterGoals.Selection(); x.toggle(g.id)
            let t = RosterGoals.explanation(main: g.id, roster: ["running", "swimming", "walking", "mobility", "bodyweight"], selection: x)?.text ?? ""
            XCTAssertTrue(t.contains("are saved") && t.contains("coming soon"), g.id)
            for word in ["Zone", "reps", "FTP", "threshold", "sets", " km", "minutes", "unsupported", "not supported", "not implemented", "unavailable", "engine", "planner"] {
                XCTAssertFalse(t.contains(word), "\(g.id): '\(word)'")
            }
        }
    }

    private func freshStore() -> (Store, URL) {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("profileonly-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return (Store(directory: d, generatePlan: false), d)
    }
    /// The whole point of the profile-only outcome: a runner enters the app with their profile, sports and goals saved
    /// and NO session — not at once, not at the next launch, not when a rebuild is asked for — and with no cycling or
    /// strength goal or type written on their behalf.
    func testAProfileOnlyAthleteIsSavedAndNeverGetsAPlan() {
        let (s, d) = freshStore()
        var sel = RosterGoals.Selection(); sel.toggle("runPace"); sel.toggle("runDistance")
        var a = OnboardingAnswers(); a.name = "Sam"; a.activities = ["trailRunning", "running"]
        a.goalIDs = sel.ids; a.mainGoalID = sel.main; a.goals = sel.plannerGoals; a.primaryGoal = sel.plannerMain
        let goalsBefore = s.profile.goals, modeBefore = s.profile.trainingMode
        OnboardingOutcome.createProfileOnly(a, store: s)
        XCTAssertTrue(s.onboarded); XCTAssertTrue(s.profile.isProfileOnly)
        XCTAssertEqual(s.profile.name, "Sam"); XCTAssertEqual(s.profile.activities, ["trailRunning", "running"])
        XCTAssertEqual(s.profile.activityGoals, ["runPace", "runDistance"]); XCTAssertEqual(s.profile.mainGoalID, "runPace")
        XCTAssertEqual(s.profile.goals, goalsBefore, "no cycling or strength goal is added"); XCTAssertEqual(s.profile.trainingMode, modeBefore, "no training type is assigned")
        XCTAssertTrue(s.plan.isEmpty, "no session is created")
        XCTAssertTrue(s.planVersions.isEmpty, "no plan was approved, so none is recorded")
        s.ensurePlan(); XCTAssertTrue(s.plan.isEmpty, "the daily plan check creates nothing")
        XCTAssertTrue(s.regenerate(weekOf: Date(), replaceEdited: true).isEmpty); XCTAssertTrue(s.plan.isEmpty, "a rebuild creates nothing")
        let again = Store(directory: d)                       // a real launch, plan generation switched on
        XCTAssertTrue(again.onboarded); XCTAssertTrue(again.profile.isProfileOnly); XCTAssertTrue(again.plan.isEmpty, "the next launch creates nothing")
        XCTAssertEqual(again.profile.activityGoals, ["runPace", "runDistance"])
    }
    /// Found on the simulator (focused check 32): the app generates a week from the default profile at first launch,
    /// before set-up, and the future part of it stayed on Home, Plan and Train as a cycling plan the runner never chose.
    func testProfileOnlyLeavesNoGeneratedWeekBehind() {
        let (s, _) = freshStore()
        s.ensurePlan()
        XCTAssertFalse(s.plan.isEmpty, "the starting point: a week generated before set-up")
        var sel = RosterGoals.Selection(); sel.toggle("runPace"); sel.toggle("runDistance")
        var a = OnboardingAnswers(); a.name = "Sam"; a.activities = ["running"]; a.goalIDs = sel.ids; a.mainGoalID = sel.main
        OnboardingOutcome.createProfileOnly(a, store: s)
        XCTAssertTrue(s.plan.isEmpty, "no generated session or rest day stays, on any date")
        XCTAssertEqual(ProfileOnlyText.identity(s.profile), "Runner")
        XCTAssertEqual(ProfileOnlyText.goalTitle(s.profile), "Pace + 1 more")
        XCTAssertEqual(ProfileOnlyText.saved(s.profile), "Your running goals are saved. Personalized running plans are coming soon.")
    }
    /// The training-mix bar is counted from a planned week, never from a table: sessions by kind, then free days.
    func testTrainingMixIsCountedFromThePlannedWeek() {
        let cal = Calendar(identifier: .gregorian)
        let mon = cal.date(from: DateComponents(year: 2026, month: 11, day: 23))!
        func w(_ d: Int, _ k: WorkoutKind) -> Workout { Workout(date: cal.date(byAdding: .day, value: d, to: mon)!, kind: k, minutes: 60) }
        let week = [w(0, .strength), w(1, .endurance), w(2, .rest), w(3, .strength), w(4, .tempo), w(5, .long), w(5, .strength), w(6, .recoveryDay)]
        let s = TrainingMix.shares(of: week, calendar: cal)
        XCTAssertEqual(s, [.init(part: .easyRiding, count: 2), .init(part: .hardRiding, count: 1), .init(part: .strength, count: 3), .init(part: .rest, count: 2)])
        XCTAssertEqual(TrainingMix.summary(s), "Easy riding 2, Hard riding 1, Strength 3, Rest 2")
        XCTAssertEqual(TrainingMix.shares(of: [w(0, .strength), w(2, .strength)], calendar: cal).map(\.part), [.strength, .rest], "a strength-only week shows no riding")
        XCTAssertTrue(TrainingMix.shares(of: [], calendar: cal).isEmpty, "no plan, no bar")
        XCTAssertTrue(TrainingMix.shares(of: [w(0, .rest), w(1, .recoveryDay)], calendar: cal).isEmpty, "rest alone is not a training mix")
    }
    // MARK: Build your week — the athlete's chosen schedule (owner decision 21 Nov 2026, 21:18)

    /// Seven rest days to start with; nothing is inserted; Continue has nothing to continue with.
    func testANewWeekIsSevenRestDays() {
        let w = ChosenWeek.normalised(nil)
        XCTAssertEqual(w.count, 7); XCTAssertTrue(w.allSatisfy(\.isEmpty))
        XCTAssertEqual(ChosenWeek.totals(w), .init(minutes: 0, sessions: 0, trainingDays: 0, restDays: 7))
        XCTAssertTrue(ChosenWeek.feasibility(w, strengthLevel: nil).blocking)
        XCTAssertEqual(ChosenWeek.kinds(w), Array(repeating: .rest, count: 7))
        XCTAssertFalse(ChosenWeek.hasPlannable(w))
    }
    /// Each session has its own length; totals and the by-sport breakdown are sums of what was chosen.
    func testChosenWeekTotalsAndPerDayLengths() {
        var w = ChosenWeek.empty
        w[0] = [.init(activity: "roadCycling", minutes: 60)]
        w[2] = [.init(activity: "strength", minutes: 45), .init(activity: "trailRunning", minutes: 30)]
        w[5] = [.init(activity: "roadCycling", minutes: 120)]
        XCTAssertEqual(ChosenWeek.totals(w), .init(minutes: 255, sessions: 4, trainingDays: 3, restDays: 4))
        XCTAssertEqual(ChosenWeek.bySport(w).map { "\($0.sport) \($0.minutes)" }, ["Cycling 180", "Strength 45", "Running 30"])
        XCTAssertEqual(ChosenWeek.kinds(w), [.ride, .rest, .lift, .rest, .rest, .ride, .rest], "running is never turned into a ride or a lift")
        let av = ChosenWeek.availability(w)
        XCTAssertEqual(av.days[0].assignments.map(\.minutes), [60]); XCTAssertEqual(av.days[5].assignments.map(\.minutes), [120], "one day's length does not change another's")
        XCTAssertEqual(av.days[2].assignments.map(\.sport), [.strength]); XCTAssertEqual(av.days[2].assignments.map(\.minutes), [45])
        XCTAssertFalse(ChosenWeek.feasibility(w, strengthLevel: .beginner).blocking)
    }
    /// The editor's rules (owner decision 21 Nov 2026, 22:22): any two activities share a day — the same sport or the
    /// same activity twice included — each stored separately; nothing is replaced; no third session; lengths in range.
    func testDayEditingRules() {
        var d = ChosenWeek.adding("running", to: [])
        XCTAssertEqual(d, [.init(activity: "running", minutes: 30)])
        d = ChosenWeek.adding("running", to: d)
        XCTAssertEqual(d.map(\.activity), ["running", "running"], "two sessions of the same activity are two sessions")
        XCTAssertEqual(ChosenWeek.adding("walking", to: d), d, "a third session is not added")
        let ride = [ChosenSession(activity: "roadCycling", minutes: 90)]
        XCTAssertEqual(ChosenWeek.adding("gravel", to: ride), [.init(activity: "roadCycling", minutes: 90), .init(activity: "gravel", minutes: 60)], "a second ride is added; the first is not replaced")
        let n = ChosenWeek.normalised([[.init(activity: "nope", minutes: 30), .init(activity: "strength", minutes: 500), .init(activity: "strength", minutes: 20), .init(activity: "running", minutes: 30)]])[0]
        XCTAssertEqual(n, [.init(activity: "strength", minutes: 120), .init(activity: "strength", minutes: 20)], "unknown activities are not stored; two a day; lengths inside the range")
    }
    /// A cycling-and-strength athlete may schedule one sport only: Continue is not blocked, and the planner plans
    /// exactly the chosen sessions — no strength session is added to a rides-only week, and no ride to a strength-only one.
    func testAHybridAthleteMayScheduleOneSportOnly() {
        let cal = Calendar.current
        func day(_ x: Workout) -> Int { (cal.component(.weekday, from: x.date) + 5) % 7 }
        for (activity, wrong) in [("roadCycling", "strength"), ("strength", "ride")] {
            let (s, _) = freshStore()
            var a = OnboardingAnswers(); a.name = "Sam"; a.activities = ["roadCycling", "strength"]; a.mode = .hybrid
            a.goals = [.endurance, .muscle]; a.primaryGoal = .endurance
            var w = ChosenWeek.empty; w[0] = [.init(activity: activity, minutes: 50)]; w[3] = [.init(activity: activity, minutes: 80)]
            a.schedule = w
            XCTAssertFalse(ChosenWeek.feasibility(w, strengthLevel: .beginner).blocking, "\(activity) only: Continue is not blocked")
            let plan = OnboardingOutcome.dryRun(a, store: s, kinds: ChosenWeek.kinds(w), ride: 60, lift: 30, weekOffset: 1).filter { (x: Workout) in x.kind != .rest && x.kind != .recoveryDay }
            XCTAssertEqual(plan.map(day).sorted(), [0, 3], "\(activity) only: sessions on the chosen days only")
            XCTAssertEqual(plan.sorted { day($0) < day($1) }.map(\.minutes), [50, 80], "with the chosen minutes")
            XCTAssertTrue(plan.allSatisfy { ($0.kind == .strength) == (activity == "strength") }, "\(activity) only: no \(wrong) session is added (\(plan.map { $0.kind.rawValue }))")
        }
    }
    /// Two rides, or two strength sessions, on one day: the planner is given both and schedules both, with their own
    /// minutes. Nothing is dropped and nothing is invented; a sport without a planner on the same day is not planned.
    func testThePlannerTakesEveryPlannableSessionOfTheChosenWeek() {
        let (s, _) = freshStore()
        var a = OnboardingAnswers(); a.name = "Sam"; a.activities = ["roadCycling", "gravel", "strength", "running"]; a.mode = .hybrid
        a.goals = [.endurance]; a.primaryGoal = .endurance
        var w = ChosenWeek.empty
        w[0] = [.init(activity: "roadCycling", minutes: 50), .init(activity: "gravel", minutes: 30)]
        w[3] = [.init(activity: "strength", minutes: 40), .init(activity: "strength", minutes: 25)]
        w[5] = [.init(activity: "running", minutes: 35), .init(activity: "running", minutes: 20)]
        a.schedule = w
        let av = ChosenWeek.availability(w)
        XCTAssertEqual(av.days[0].assignments.map(\.minutes), [50, 30]); XCTAssertEqual(av.days[3].assignments.map(\.minutes), [40, 25]); XCTAssertTrue(av.days[5].assignments.isEmpty)
        let cal = Calendar.current
        func day(_ x: Workout) -> Int { (cal.component(.weekday, from: x.date) + 5) % 7 }
        let plan = OnboardingOutcome.dryRun(a, store: s, kinds: ChosenWeek.kinds(w), ride: 60, lift: 30, weekOffset: 1).filter { (x: Workout) in x.kind != .rest && x.kind != .recoveryDay }
        XCTAssertEqual(plan.filter { day($0) == 0 }.map(\.minutes).sorted(), [30, 50], "both rides are planned (\(plan.map { "\(day($0)) \($0.kind.rawValue) \($0.minutes)" }))")
        XCTAssertEqual(plan.filter { day($0) == 3 }.map(\.minutes).sorted(), [25, 40], "both strength sessions are planned")
        XCTAssertTrue(plan.filter { day($0) == 3 }.allSatisfy { $0.kind == .strength })
        XCTAssertTrue(plan.filter { day($0) == 5 }.isEmpty, "the two runs are saved, and planned as nothing")
        XCTAssertEqual(plan.count, 4, "nothing is added")
        OnboardingOutcome.commit(a, to: s)
        XCTAssertEqual(s.profile.chosenWeek, w, "all six sessions are stored separately, as chosen")
    }
    /// The planner is given the athlete's own days and minutes, and plans exactly those.
    func testThePlannerPlansTheChosenDaysWithTheirOwnMinutes() {
        let (s, _) = freshStore()
        var a = OnboardingAnswers(); a.name = "Sam"; a.activities = ["roadCycling", "strength", "running"]; a.mode = .hybrid
        a.goals = [.endurance]; a.primaryGoal = .endurance; a.goalIDs = ["endurance"]; a.mainGoalID = "endurance"
        var w = ChosenWeek.empty
        w[1] = [.init(activity: "roadCycling", minutes: 50)]; w[3] = [.init(activity: "strength", minutes: 40), .init(activity: "running", minutes: 25)]; w[5] = [.init(activity: "roadCycling", minutes: 110)]
        a.schedule = w
        let plan = OnboardingOutcome.dryRun(a, store: s, kinds: ChosenWeek.kinds(w), ride: 60, lift: 30, weekOffset: 1).filter { (w: Workout) in w.kind != .rest && w.kind != .recoveryDay }
        let cal = Calendar.current
        func day(_ x: Workout) -> Int { (cal.component(.weekday, from: x.date) + 5) % 7 }
        XCTAssertEqual(Set(plan.map(day)), [1, 3, 5], "sessions only on the chosen days (\(plan.map { "\(day($0)) \($0.kind) \($0.minutes)" }))")
        XCTAssertEqual(plan.filter { day($0) == 1 }.map(\.minutes), [50]); XCTAssertEqual(plan.filter { day($0) == 5 }.map(\.minutes), [110])
        XCTAssertEqual(plan.filter { day($0) == 3 }.map(\.kind), [.strength], "the running session is not planned as anything")
        XCTAssertEqual(plan.filter { day($0) == 3 }.map(\.minutes), [40])
        OnboardingOutcome.commit(a, to: s)
        XCTAssertEqual(s.profile.chosenWeek, w, "every chosen session is saved, planned sport or not")
    }
    /// A runner's week is saved as chosen; no availability, plan, type or goal is written from it.
    func testARunnersWeekIsSavedAndNothingIsPlannedFromIt() {
        let (s, _) = freshStore()
        var sel = RosterGoals.Selection(); sel.toggle("runPace")
        var a = OnboardingAnswers(); a.name = "Sam"; a.activities = ["running"]; a.goalIDs = sel.ids; a.mainGoalID = sel.main
        var w = ChosenWeek.empty; w[0] = [.init(activity: "running", minutes: 40)]; w[4] = [.init(activity: "running", minutes: 70)]
        a.schedule = w
        let before = s.availability
        OnboardingOutcome.commit(a, to: s)                 // as onboarding does on every change
        XCTAssertEqual(s.availability, before, "a week with nothing Cyclift plans writes no planner availability")
        OnboardingOutcome.createProfileOnly(a, store: s)
        XCTAssertEqual(s.profile.chosenWeek, w)
        XCTAssertEqual(s.availability, before); XCTAssertTrue(s.plan.isEmpty); XCTAssertTrue(s.profile.isProfileOnly)
        XCTAssertEqual(OnboardingOutcome.storedSchedule(s), w, "shown again as it was left")
        XCTAssertFalse(ChosenWeek.feasibility(w, strengthLevel: nil).blocking, "a valid training day lets the runner continue")
    }
    /// An older record without the field still reads; an existing athlete's saved week is kept, not reset to rest.
    func testAnExistingWeekIsKept() throws {
        let old = try JSONDecoder().decode(RiderProfile.self, from: JSONEncoder().encode(RiderProfile()))
        XCTAssertNil(old.chosenWeek)
        let av = OnboardingWeek.availability([.lift, .ride, .rest, .both, .rest, .rest, .rest], ride: 75, lift: 35)
        let w = ChosenWeek.from(av, roster: ["gravel", "strength"])
        XCTAssertEqual(w?[0], [.init(activity: "strength", minutes: 35)]); XCTAssertEqual(w?[1], [.init(activity: "gravel", minutes: 75)])
        XCTAssertEqual(Set(w?[3].map(\.activity) ?? []), ["gravel", "strength"])
    }
    // MARK: Equipment environments (owner decision 22 Nov 2026, 13:34)

    /// Four environments, no "Not sure"; each opens with its own preset, and nothing more than that preset.
    func testEquipmentEnvironmentsAndTheirPresets() {
        XCTAssertEqual(EquipmentEnvironment.allCases.map(\.title), ["Gym", "Home", "Bodyweight", "Custom"])
        XCTAssertEqual(EquipmentEnvironment.bodyweight.selection(in: nil), [], "bodyweight needs no equipment by default")
        XCTAssertEqual(EquipmentEnvironment.custom.selection(in: nil), [])
        XCTAssertEqual(Set(EquipmentEnvironment.home.selection(in: nil)), EquipmentPreset.homeKit, "home starts from the app's existing home kit")
        XCTAssertFalse(EquipmentEnvironment.gym.selection(in: nil).contains("trap bar"), "a gym is not assumed to have every piece of equipment")
        for e in EquipmentEnvironment.allCases { XCTAssertTrue(e.checklist.allSatisfy { EquipmentCatalogue.item($0) != nil }, "\(e.title): every listed item is in the catalogue") }
        XCTAssertTrue(EquipmentEnvironment.bodyweight.checklist.contains("dumbbell") && EquipmentEnvironment.bodyweight.checklist.contains("band"))
        XCTAssertEqual(Set(EquipmentCatalogue.items.map(\.id)).count, EquipmentCatalogue.items.count, "identifiers are unique")
        XCTAssertTrue(EquipmentCatalogue.items.filter(\.planner).allSatisfy { ExerciseCatalogue.equipmentOptions.contains($0.id) }, "an item marked as used by the planner is one the planner knows")
        XCTAssertEqual(Set(EquipmentCatalogue.items.map(\.group)), Set(EquipmentGroup.allCases), "the catalogue covers every sport group")
    }
    /// Each environment keeps its own selection; choosing another never deletes it; exactly the ticked items are stored.
    func testEachEnvironmentKeepsItsOwnSelection() {
        let (s, _) = freshStore()
        s.equipment.excluded = ["barbell-back-squat"]
        var a = OnboardingAnswers(); a.name = "Sam"
        a.environment = .bodyweight; a.equipmentSets = ["bodyweight": ["dumbbell", "band"], "gym": ["barbell", "bench"], "custom": ["squat rack", "pull buoy"]]
        OnboardingOutcome.commit(a, to: s)
        XCTAssertEqual(s.equipment.owned, ["dumbbell", "band"]); XCTAssertEqual(s.equipment.confirmed, true)
        XCTAssertEqual(s.equipment.excluded, ["barbell-back-squat"], "the athlete's exercise exclusions are kept")
        a.environment = .gym; OnboardingOutcome.commit(a, to: s)
        XCTAssertEqual(s.equipment.owned, ["barbell", "bench"], "the gym's own selection, not the bodyweight one")
        XCTAssertEqual(s.profile.equipmentSets?["bodyweight"], ["dumbbell", "band"], "switching did not delete the bodyweight selection")
        a.environment = .custom; OnboardingOutcome.commit(a, to: s)
        XCTAssertEqual(s.equipment.owned, ["squat rack", "pull buoy"], "custom holds equipment across categories")
        XCTAssertEqual(s.profile.equipmentEnvironment, "custom")
        let old = try? JSONDecoder().decode(RiderProfile.self, from: JSONEncoder().encode(RiderProfile()))
        XCTAssertNil(old?.equipmentEnvironment); XCTAssertNil(old?.equipmentSets)
    }
    /// The existing strength planner respects what is ticked: a bodyweight athlete with dumbbells and bands can be
    /// offered dumbbell and band exercises and no barbell ones; items the planner does not use change nothing.
    func testThePlannerRespectsTickedEquipment() {
        let all = ExerciseCatalogue.builtIn
        XCTAssertFalse(all.isEmpty, "the exercise catalogue is loaded")
        func can(_ ids: [String]) -> Set<String> { let e = EquipmentProfile(owned: Set(ids), confirmed: true); return Set(all.filter { e.hasEquipment(for: $0) }.map(\.id)) }
        let none = can([]), kit = can(["dumbbell", "band"])
        XCTAssertTrue(kit.isSuperset(of: none) && kit.count > none.count, "dumbbells and bands add exercises (\(none.count) → \(kit.count))")
        let added = all.filter { kit.contains($0.id) && !none.contains($0.id) }
        XCTAssertTrue(added.allSatisfy { !Set($0.equipment).isDisjoint(with: ["dumbbell", "band"]) }, "every added exercise uses a dumbbell or a band")
        XCTAssertFalse(all.contains { kit.contains($0.id) && $0.equipment == ["barbell"] }, "no barbell-only exercise without a barbell")
        XCTAssertEqual(can(["dumbbell", "band", "squat rack", "weighted vest", "pull buoy"]), kit, "stored-only items do not change what is offered")
        XCTAssertEqual(EquipmentCatalogue.eligibleExercises(["dumbbell", "band"]).can, kit.count); XCTAssertEqual(EquipmentCatalogue.eligibleExercises([]).of, all.count)
        XCTAssertGreaterThan(can(EquipmentEnvironment.gym.preset).count, kit.count)
    }
    /// 22 Nov 2026 (14:36): an environment is needed only by a week with a strength session the planner builds; the
    /// grouped machines item keeps its identifier; the non-strength equipment lists are classed as provisional.
    func testEnvironmentIsNeededOnlyWithStrength() {
        var run = ChosenWeek.empty; run[0] = [.init(activity: "running", minutes: 30)]; run[2] = [.init(activity: "roadCycling", minutes: 60)]
        XCTAssertFalse(ChosenWeek.needsEnvironment(run), "a runner or rider is not asked for equipment")
        var lift = run; lift[4] = [.init(activity: "strength", minutes: 30)]
        XCTAssertTrue(ChosenWeek.needsEnvironment(lift))
        XCTAssertFalse(ChosenWeek.needsEnvironment(ChosenWeek.empty))
        XCTAssertEqual(EquipmentCatalogue.item(EquipmentCatalogue.machines)?.title, "Weight machines (leg press and others)")
        XCTAssertTrue(EquipmentCatalogue.plannerOwned(["machine", "squat rack"]).contains("machine"))
        XCTAssertTrue(EquipmentCatalogue.items.allSatisfy { $0.partOf == nil || EquipmentCatalogue.item($0.partOf!) != nil }, "an individual type names a group that exists")
        XCTAssertEqual(EquipmentGroup.allCases.filter(\.isProvisional), [.cycling, .running, .swimming, .mobility])
        XCTAssertTrue(EquipmentCatalogue.items.filter { $0.group.isProvisional }.allSatisfy { !$0.planner }, "no provisional item is presented as used for planning")
    }
    // MARK: Connect your devices (owner's approved direction, 22 Nov 2026, 15:55)

    /// Five integrations in a fixed order; Lab offers nothing and consults nothing; WHOOP and Garmin are never claimed.
    func testConnectionRowsAreTruthful() {
        let lab = OnbConnections.rows(live: nil)
        XCTAssertEqual(lab.map(\.name), ["Apple Health", "Apple Watch", "WHOOP", "Garmin", "Bluetooth devices"])
        XCTAssertEqual(lab.map(\.id), OnbConnections.order)
        XCTAssertTrue(lab.allSatisfy { $0.action == nil }, "no button in Lab")
        XCTAssertEqual(lab.map(\.status), [.notInLab, .notInLab, .comingSoon, .comingSoon, .notInLab])
        let fresh = OnbConnections.rows(live: .init(healthAvailable: true))
        XCTAssertEqual(fresh.map(\.status), [.notConnected, .notConnected, .comingSoon, .comingSoon, .notConnected])
        XCTAssertEqual(fresh.map(\.action), [.connectHealth, .manageWatch, nil, nil, .pairBluetooth], "an action only where a real service exists")
        let on = OnbConnections.rows(live: .init(healthAvailable: true, healthConnected: true, watchConnected: true, bluetoothPaired: 2))
        XCTAssertEqual(on.map(\.status), [.connected, .connected, .comingSoon, .comingSoon, .connected])
        XCTAssertEqual(on[0].action, .manageHealth); XCTAssertEqual(on[4].note, "2 paired")
        let noHealth = OnbConnections.rows(live: .init(healthAvailable: false))[0]
        XCTAssertNil(noHealth.action, "no Connect button where Apple Health does not exist"); XCTAssertEqual(noHealth.note, "Not available on this device")
        XCTAssertFalse((lab + fresh + on).contains { $0.name.contains("BikeComputer") || $0.name.contains("sensors") })
    }
    /// "Always ask me" is where a new athlete starts — once; a stored choice and an existing athlete's are never changed.
    func testPlanChangesStartingPoint() {
        var r = OnbConnections.startingPlanChanges(asked: nil, onboarded: false, current: true)
        XCTAssertFalse(r.autoAdapt); XCTAssertEqual(r.asked, true)
        r = OnbConnections.startingPlanChanges(asked: true, onboarded: false, current: true)
        XCTAssertTrue(r.autoAdapt, "a choice already made in onboarding is kept")
        r = OnbConnections.startingPlanChanges(asked: nil, onboarded: true, current: true)
        XCTAssertTrue(r.autoAdapt, "an existing athlete's preference is untouched"); XCTAssertNil(r.asked)
        XCTAssertTrue(AppSettings().autoAdapt, "the app-wide default itself is unchanged")
    }
    /// FTP is no longer asked in onboarding: answers without an FTP leave the stored one exactly as it is, and an
    /// athlete who never entered one stays Unknown.
    func testOnboardingWithoutFTPLeavesTheStoredFTPAlone() {
        let (s, _) = freshStore()
        s.profile.setFTP(230, source: .entered)
        let stored = (s.profile.ftpValue, s.profile.ftpSource, s.profile.ftpHow)
        var a = OnboardingAnswers(); a.name = "Sam"; a.activities = ["roadCycling"]; a.mode = .cycling
        XCTAssertNil(a.ftpSource); XCTAssertNil(a.ftpWatts)
        OnboardingOutcome.commit(a, to: s)
        XCTAssertEqual(s.profile.ftpValue, 230)
        XCTAssertEqual(s.profile.ftpSource, stored.1); XCTAssertEqual(s.profile.ftpHow, stored.2, "a stored FTP and its source are not touched")
        let (n, _) = freshStore()
        let before = (n.profile.ftpKnown, n.profile.ftpValue)
        OnboardingOutcome.commit(a, to: n)
        XCTAssertEqual(n.profile.ftpKnown, before.0); XCTAssertEqual(n.profile.ftpValue, before.1, "nothing is invented for a new athlete")
        XCTAssertFalse(n.profile.ftpKnown, "a new athlete's FTP is Unknown")
    }
    /// The marker of an athlete without a plan is additive, off by default, and survives saving.
    func testProfileOnlyMarker() throws {
        XCTAssertFalse(RiderProfile().isProfileOnly)
        var p = RiderProfile(); p.profileOnly = true
        let read = try JSONDecoder().decode(RiderProfile.self, from: JSONEncoder().encode(p))
        XCTAssertTrue(read.isProfileOnly)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(RiderProfile())) as! [String: Any]
        json.removeValue(forKey: "profileOnly")
        XCTAssertFalse(try JSONDecoder().decode(RiderProfile.self, from: JSONSerialization.data(withJSONObject: json)).isProfileOnly, "an older record is an ordinary planned athlete")
    }

    func testAnswersStoreBothKindsAndFeedThePlannerOnlyItsOwn() {
        var x = PlanInputs(profile: RiderProfile(), availability: nil, equipment: EquipmentProfile(), strengthPrefs: StrengthPrefs())
        var s = RosterGoals.Selection(); for id in ["runPace", "endurance", "muscle"] { s.toggle(id) }
        var a = OnboardingAnswers(); a.goalIDs = s.ids; a.mainGoalID = s.main; a.goals = s.plannerGoals; a.primaryGoal = s.plannerMain
        a.apply(to: &x)
        XCTAssertEqual(x.profile.goals, [.endurance, .muscle]); XCTAssertEqual(x.profile.primaryGoal, .endurance)
        XCTAssertEqual(x.profile.activityGoals, ["runPace"]); XCTAssertEqual(x.profile.mainGoalID, "runPace")
        let read = try! JSONDecoder().decode(RiderProfile.self, from: JSONEncoder().encode(x.profile))
        XCTAssertEqual(read.activityGoals, ["runPace"]); XCTAssertEqual(read.mainGoalID, "runPace"); XCTAssertEqual(read.goals, [.endurance, .muscle])
        var changed = x; changed.profile.activityGoals = ["swimSpeed"]; changed.profile.mainGoalID = "swimSpeed"
        XCTAssertFalse(changed.planningDiffers(from: x), "saved-only goals are not a planning input")
    }
    func testAnOlderRecordHasNoSavedOnlyGoalsAndReadsUnchanged() throws {
        var old = RiderProfile(); old.goals = [.endurance, .strength]; old.primaryGoal = .strength
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "activityGoals"); json.removeValue(forKey: "mainGoalID")
        let read = try JSONDecoder().decode(RiderProfile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(read.activityGoals); XCTAssertNil(read.mainGoalID); XCTAssertEqual(read.goals, [.endurance, .strength]); XCTAssertEqual(read.primaryGoal, .strength)
    }
}
