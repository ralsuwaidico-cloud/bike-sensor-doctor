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
        var s = RosterGoals.Selection(); for id in ["runPace", "endurance", "swimDistance", "muscle"] { s.toggle(id) }
        XCTAssertEqual(s.main, "runPace")
        XCTAssertEqual(s.plannerGoals, [.endurance, .muscle]); XCTAssertEqual(s.savedOnly, ["runPace", "swimDistance"])
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

    func testExplanations() {
        var s = RosterGoals.Selection(); s.toggle("muscle")
        let m = RosterGoals.explanation(main: s.main, roster: ["roadCycling", "strength"], selection: s)
        XCTAssertEqual(m?.title, "Muscle · main goal"); XCTAssertEqual(m?.text, GoalInfo.effect(.muscle), "a planned goal is explained by the planner's own rule")
        XCTAssertNil(RosterGoals.explanation(main: nil, roster: ["roadCycling"], selection: RosterGoals.Selection()))
        // a runner: nothing is prescribed
        var r = RosterGoals.Selection(); r.toggle("runPace")
        let run = RosterGoals.explanation(main: r.main, roster: ["running"], selection: r)
        XCTAssertEqual(run?.title, "Pace · main goal")
        XCTAssertEqual(run?.text, "Saved as your main goal. Cyclift cannot plan running yet, so no sessions are prescribed. Add cycling or gym training to build a plan.")
        // the general goal in a roster Cyclift cannot plan is not explained with riding and lifting
        var f = RosterGoals.Selection(); f.toggle("fitness")
        let fit = RosterGoals.explanation(main: f.main, roster: ["running"], selection: f)?.text ?? ""
        XCTAssertTrue(fit.contains("no sessions are prescribed")); XCTAssertFalse(fit.contains("riding") || fit.contains("lifting"))
        // a saved-only main goal beside a planned sport
        var mix = RosterGoals.Selection(); mix.toggle("runPace")
        XCTAssertTrue(RosterGoals.explanation(main: mix.main, roster: ["running", "roadCycling"], selection: mix)!.text.contains("Choose a goal Cyclift can plan as well"))
        mix.toggle("endurance")
        XCTAssertEqual(RosterGoals.explanation(main: mix.main, roster: ["running", "roadCycling"], selection: mix)?.text,
                       "Saved as your main goal. Cyclift does not plan running yet, so nothing is prescribed for it; your plan follows Endurance.")
        // no saved-only explanation ever carries a prescription
        for g in RosterGoals.all where g.planner == nil {
            var x = RosterGoals.Selection(); x.toggle(g.id)
            let t = RosterGoals.explanation(main: g.id, roster: ["running", "swimming", "walking", "mobility", "bodyweight"], selection: x)?.text ?? ""
            XCTAssertTrue(t.contains("no sessions are prescribed"), g.id)
            for word in ["Zone", "reps", "FTP", "threshold", "sets", " km", "minutes"] { XCTAssertFalse(t.contains(word), "\(g.id): '\(word)'") }
        }
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
        var changed = x; changed.profile.activityGoals = ["swimDistance"]; changed.profile.mainGoalID = "swimDistance"
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
