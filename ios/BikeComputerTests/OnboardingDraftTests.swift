import XCTest
@testable import BikeComputer

// V1 onboarding (ios/V1_ONBOARDING_PROFILE_DEVICES.md): every answer lands in its documented field, no answer never
// becomes a value, the coach's proposal is realistic and never overrides the athlete's week, and the Stage E preview is
// the same planner run Approve saves. Pure — Linux harness and CI simulator.

final class OnboardingAnswersMappingTests: XCTestCase {
    private func fresh() -> PlanInputs { PlanInputs(profile: RiderProfile(), availability: nil, equipment: EquipmentProfile(), strengthPrefs: StrengthPrefs()) }

    func testNoAnswersChangeNothingAndInventNothing() {
        var x = fresh()
        OnboardingAnswers().apply(to: &x)
        XCTAssertEqual(x.profile.name, "")
        XCTAssertNil(x.profile.dateOfBirth); XCTAssertNil(x.profile.weightKg); XCTAssertFalse(x.profile.ftpKnown)
        XCTAssertNil(x.availability); XCTAssertFalse(x.equipment.isSet); XCTAssertTrue(x.equipment.isProvisional)
        XCTAssertNil(x.strengthPrefs.experience); XCTAssertNil(x.strengthPrefs.prefersSupersets)
        XCTAssertEqual(x.profile.provenance(.weight).source, .unknown); XCTAssertEqual(x.profile.provenance(.dateOfBirth).source, .unknown)
    }

    func testEveryAnswerLandsInItsField() throws {
        var x = fresh()
        var a = OnboardingAnswers()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let dob = Calendar.current.date(from: DateComponents(year: 1995, month: 6, day: 2))!
        a.name = " Sara "; a.mode = .hybrid; a.cyclingLevel = .beginner; a.strengthLevel = .intermediate; a.priority = .strength
        a.dateOfBirth = dob; a.weightKg = 61
        a.goals = [.endurance, .muscle]; a.primaryGoal = .muscle
        a.week = [.lift, .ride, .lift, .rest, .lift, .ride, .rest]; a.rideMinutes = 60; a.liftMinutes = 30
        a.equipment = .home; a.supersets = true
        a.ftpWatts = 230; a.ftpSource = .entered
        a.apply(to: &x, now: now)
        let p = x.profile
        XCTAssertEqual(p.name, "Sara", "trimmed, stored once")
        XCTAssertEqual(p.trainingMode, .hybrid); XCTAssertEqual(p.level, .beginner); XCTAssertEqual(x.strengthPrefs.experience, .intermediate); XCTAssertEqual(p.priority, .strength)
        XCTAssertEqual(p.dateOfBirth, dob); XCTAssertEqual(p.birthYear, 1995); XCTAssertEqual(p.provenance(.dateOfBirth).source, .entered); XCTAssertEqual(p.provenance(.dateOfBirth).recordedAt, now)
        XCTAssertEqual(p.weightKg, 61); XCTAssertEqual(p.provenance(.weight).source, .entered); XCTAssertEqual(p.provenance(.weight).recordedAt, now)
        XCTAssertEqual(p.goals, [.endurance, .muscle]); XCTAssertEqual(p.primaryGoal, .muscle)
        XCTAssertEqual(p.goal, .endurance, "the cycling goal the planner reads follows the goals"); XCTAssertEqual(x.strengthPrefs.goal, GoalID.muscle.strengthGoal)
        let av = try XCTUnwrap(x.availability)
        XCTAssertEqual(av.days.map { $0.cycles && $0.lifts ? "both" : $0.cycles ? "ride" : $0.lifts ? "lift" : "rest" }, ["lift", "ride", "lift", "rest", "lift", "ride", "rest"])
        XCTAssertEqual(av.days[1].cycleMinutes, 60); XCTAssertEqual(av.days[0].liftingMinutes, 30)
        XCTAssertEqual(p.weekIsExplicit, true); XCTAssertEqual(p.preferredDays, [0, 1, 2, 4, 5]); XCTAssertEqual(p.trainingDaysPerWeek, 5)
        XCTAssertEqual(p.cyclingDaysPerWeek, 2); XCTAssertEqual(p.liftDaysPerWeek, 3); XCTAssertEqual(p.cyclingSessionMinutes, 60); XCTAssertEqual(p.strengthSessionMinutes, 30)
        XCTAssertEqual(p.hoursPerWeek, 2); XCTAssertEqual(p.liftingHoursPerWeek, 2)
        XCTAssertTrue(x.equipment.isSet); XCTAssertEqual(x.equipment.owned, EquipmentPreset.homeKit); XCTAssertEqual(x.strengthPrefs.prefersSupersets, true)
        XCTAssertTrue(p.ftpKnown); XCTAssertEqual(p.ftpValue, 230); XCTAssertEqual(p.ftpSource, .entered)
    }

    func testModeSetsPriorityAndNeverTouchesOtherSports() {
        var x = fresh()
        var a = OnboardingAnswers(); a.mode = .cycling; a.apply(to: &x)
        XCTAssertEqual(x.profile.priority, .cycling)
        a = OnboardingAnswers(); a.mode = .strength; a.apply(to: &x)
        XCTAssertEqual(x.profile.priority, .strength)
        a = OnboardingAnswers(); a.mode = .hybrid; a.apply(to: &x)
        XCTAssertEqual(x.profile.priority, .balanced, "hybrid without a stated priority is balanced")
    }

    func testFTPStaysUnknownWithoutAValidNumber() {
        var x = fresh()
        var a = OnboardingAnswers(); a.ftpSource = .entered; a.ftpWatts = nil; a.apply(to: &x)
        XCTAssertFalse(x.profile.ftpKnown, "choosing Entered without watts never saves 200/225 W")
        a.ftpWatts = 20; a.apply(to: &x); XCTAssertFalse(x.profile.ftpKnown, "out of range → Unknown")
        a.ftpWatts = 250; a.apply(to: &x); XCTAssertTrue(x.profile.ftpKnown)
        a = OnboardingAnswers(); a.ftpSource = .unknown; a.apply(to: &x)
        XCTAssertFalse(x.profile.ftpKnown); XCTAssertNil(x.profile.ftpValue)
    }

    func testEquipmentNotSureStaysProvisional() {
        var x = fresh()
        var a = OnboardingAnswers(); a.equipment = .notSure; a.apply(to: &x)
        XCTAssertTrue(x.equipment.isProvisional); XCTAssertFalse(x.equipment.isSet)
        a.equipment = .bodyweight; a.apply(to: &x)
        XCTAssertTrue(x.equipment.isSet); XCTAssertTrue(x.equipment.owned.isEmpty); XCTAssertEqual(x.equipment.confirmed, true)
    }

    func testSwitchingTypeKeepsTheDays() {
        // a hybrid week edited in Strength mode keeps every training day as a lift day; back in Hybrid nothing was lost
        let hybrid: [DayKind] = [.lift, .ride, .both, .rest, .lift, .ride, .rest]
        let asStrength = hybrid.map { OnboardingWeek.normalise($0, mode: .strength, twoADay: false) }
        XCTAssertEqual(asStrength, [.lift, .lift, .lift, .rest, .lift, .lift, .rest])
        let asCycling = hybrid.map { OnboardingWeek.normalise($0, mode: .cycling, twoADay: false) }
        XCTAssertEqual(asCycling, [.ride, .ride, .ride, .rest, .ride, .ride, .rest])
        XCTAssertEqual(OnboardingWeek.normalise(.both, mode: .hybrid, twoADay: false), .ride)
        XCTAssertEqual(OnboardingWeek.normalise(.both, mode: .hybrid, twoADay: true), .both)
    }
}

final class OnboardingWeekTests: XCTestCase {
    func testProposalIsRealisticForEachType() {
        let c = OnboardingWeek.propose(mode: .cycling, cyclingLevel: .beginner, strengthLevel: nil, priority: .cycling)
        XCTAssertEqual(OnboardingWeek.rides(c), 3); XCTAssertEqual(OnboardingWeek.lifts(c), 0)
        let s = OnboardingWeek.propose(mode: .strength, cyclingLevel: .intermediate, strengthLevel: .beginner, priority: .strength)
        XCTAssertEqual(OnboardingWeek.lifts(s), 3); XCTAssertEqual(OnboardingWeek.rides(s), 0)
        let h = OnboardingWeek.propose(mode: .hybrid, cyclingLevel: .intermediate, strengthLevel: .beginner, priority: .balanced)
        XCTAssertEqual(OnboardingWeek.lifts(h), 3); XCTAssertEqual(OnboardingWeek.rides(h), 2)
        XCTAssertTrue(h.contains(.rest), "every proposal has a rest day")
        let f = OnboardingWeek.feasibility(h, mode: .hybrid, ride: 60, lift: 30, strengthLevel: .beginner)
        XCTAssertTrue(f.ok, f.text); XCTAssertFalse(f.blocking)
        XCTAssertTrue(f.text.contains("3 h 30 min a week"), f.text)
    }
    func testTapCycleAndFeasibility() {
        XCTAssertEqual(OnboardingWeek.next(.ride, mode: .hybrid, twoADay: false), .lift)
        XCTAssertEqual(OnboardingWeek.next(.lift, mode: .hybrid, twoADay: false), .rest)
        XCTAssertEqual(OnboardingWeek.next(.lift, mode: .hybrid, twoADay: true), .both)
        XCTAssertEqual(OnboardingWeek.next(.rest, mode: .cycling, twoADay: false), .ride)
        let none = OnboardingWeek.feasibility(Array(repeating: .rest, count: 7), mode: .cycling, ride: 60, lift: 30, strengthLevel: nil)
        XCTAssertTrue(none.blocking)
        let noRest = OnboardingWeek.feasibility(Array(repeating: .ride, count: 7), mode: .cycling, ride: 60, lift: 30, strengthLevel: nil)
        XCTAssertFalse(noRest.ok); XCTAssertFalse(noRest.blocking, "the athlete's week is never overridden — only warned")
        XCTAssertTrue(noRest.text.contains("no rest day"))
        let many = OnboardingWeek.feasibility([.lift, .lift, .lift, .lift, .rest, .rest, .rest], mode: .strength, ride: 60, lift: 30, strengthLevel: .beginner)
        XCTAssertTrue(many.text.contains("4 lifts"))
    }
    func testPreviewIsTheSamePlannerRunApproveSaves() {
        var x = PlanInputs(profile: RiderProfile(), availability: nil, equipment: EquipmentProfile(), strengthPrefs: StrengthPrefs())
        var a = OnboardingAnswers()
        a.name = "A"; a.mode = .hybrid; a.cyclingLevel = .intermediate; a.strengthLevel = .beginner; a.priority = .balanced
        a.goals = [.endurance]; a.primaryGoal = .endurance
        a.week = OnboardingWeek.propose(mode: .hybrid, cyclingLevel: .intermediate, strengthLevel: .beginner, priority: .balanced)
        a.rideMinutes = 60; a.liftMinutes = 30; a.equipment = .notSure
        a.apply(to: &x)
        let cal = Calendar.current
        let monday = cal.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let preview = PlanEngine.week(starting: monday, profile: x.profile, availability: x.availability!)
        let again = PlanEngine.week(starting: monday, profile: x.profile, availability: x.availability!)
        XCTAssertEqual(preview.map { "\($0.kind.rawValue)-\($0.minutes)" }, again.map { "\($0.kind.rawValue)-\($0.minutes)" }, "deterministic for the same inputs")
        let training = preview.filter { $0.kind.isRide || $0.kind == .strength }
        XCTAssertEqual(training.filter { $0.kind == .strength }.count, 3)
        XCTAssertEqual(training.filter { $0.kind.isRide }.count, 2)
        for w in training where w.kind == .strength { XCTAssertEqual(w.minutes, 30, "firm session length") }
        for w in training where w.kind.isRide { XCTAssertEqual(w.minutes, 60) }
        let first = OnboardingApproach.firstWorkout(in: preview, from: monday)
        XCTAssertEqual(first?.date, monday); XCTAssertEqual(first?.kind, .strength)
        let lines = OnboardingApproach.lines(primary: .endurance, mode: .hybrid, kinds: a.week!, liftMinutes: 30, ftpKnown: false, ftpWatts: nil, equipmentProvisional: true)
        XCTAssertEqual(lines.count, 3)
        XCTAssertTrue(lines[0].hasPrefix("Endurance:"), lines[0])
        XCTAssertTrue(lines.contains { $0.contains("FTP Unknown") }, "no guessed watts in the approach")
    }
    func testGoalInfoCoversEveryGoalAndEmphasisSumsToSeven() {
        for g in GoalID.allCases {
            XCTAssertFalse(GoalInfo.line(g).isEmpty); XCTAssertFalse(GoalInfo.effect(g).isEmpty); XCTAssertFalse(GoalInfo.icon(g).isEmpty)
            XCTAssertFalse(GoalInfo.effect(g).lowercased().contains("guarantee"))
        }
        for m in TrainingMode.allCases {
            let e = GoalInfo.emphasis(mode: m, primary: .endurance, priority: .balanced)
            XCTAssertEqual(e.easyRiding + e.hardRiding + e.strength + e.rest, 7)
        }
        XCTAssertEqual(GoalInfo.choices(for: .strength).map(\.title), ["Strength", "General"])
        XCTAssertEqual(GoalInfo.choices(for: .hybrid).map(\.title), ["Cycling", "Strength", "General"])
    }
}

final class DeviceCardsTests: XCTestCase {
    func testCardsShowRealStatesAndOnlySupportedActions() {
        let now = Date()
        let states: [String: DeviceStatus] = [
            DeviceCards.healthId: DeviceStatus(id: DeviceCards.healthId, name: "Apple Health", state: .connected, lastSyncedAt: nil, provides: "", detail: "connected · no data yet"),
            DeviceCards.watchId: DeviceStatus(id: DeviceCards.watchId, name: "Apple Watch", state: .receivingData(lastSampleAt: now), lastSyncedAt: now, provides: "", detail: "live"),
            DeviceCards.boardId: DeviceStatus(id: DeviceCards.boardId, name: "BikeComputer", state: .notPaired, lastSyncedAt: nil, provides: "", detail: "not set up"),
        ]
        let cards = DeviceCards.build(states: states, mode: .hybrid, bleSensors: [DeviceCards.Sensor(id: "ble:1", name: "HRM-Pro", provides: "Heart rate", hasHR: true, hasPower: false, hasCadence: false)], healthAvailable: true, boardRemembered: false)
        func card(_ id: String) -> DeviceCardModel { cards.first { $0.id == id }! }
        XCTAssertEqual(card(DeviceCards.healthId).state.cy, .connected); XCTAssertEqual(card(DeviceCards.healthId).action, .openDetail)
        XCTAssertEqual(card(DeviceCards.watchId).state.cy, .receiving, "paired-but-silent is never shown as receiving; live samples are")
        XCTAssertEqual(card(DeviceCards.boardId).state.cy, .notPaired); XCTAssertEqual(card(DeviceCards.boardId).action, .connectBoard)
        XCTAssertEqual(card("ble:1").action, .openDetail)
        XCTAssertFalse(cards.contains { $0.id == "add.hr" }, "a paired strap replaces the 'add a strap' card")
        XCTAssertTrue(cards.contains { $0.id == "add.power" && $0.action == .pairSensor })
        let strengthOnly = DeviceCards.build(states: states, mode: .strength, bleSensors: [], healthAvailable: false, boardRemembered: false)
        XCTAssertFalse(strengthOnly.contains { $0.id == DeviceCards.boardId }, "strength-only hides the board and sensors")
        XCTAssertEqual(strengthOnly.first { $0.id == DeviceCards.healthId }?.action, DeviceCardModel.Action.none, "no Health action when Health is unavailable")
    }
    func testEveryModelStateHasAPresentation() {
        let all: [DeviceState] = [.notPaired, .paired, .connected, .receivingData(lastSampleAt: Date()), .problem(reason: "x")]
        XCTAssertEqual(Set(all.map { $0.cy }).count, 5)
    }
}
