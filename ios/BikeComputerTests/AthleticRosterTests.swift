import XCTest
@testable import BikeComputer

/// Onboarding v3.4 Page 2: the roster's rules over the stored sports list, training type and priority.
final class AthleticRosterTests: XCTestCase {
    func testEmptyRosterSuggestsWhatCycliftPlansAndRecordsAndCannotContinue() {
        let v = AthleticRoster.view([])
        XCTAssertNil(v.mode, "no planned sport: Continue is unavailable")
        XCTAssertEqual(v.suggestions.count, 4)
        XCTAssertEqual(Array(v.suggestions.prefix(2)).map(\.id), ["roadCycling", "strength"], "the two fully supported sports come first")
        XCTAssertTrue(v.suggestions.allSatisfy { $0.capability.plannable }, "only sports Cyclift can plan are suggested")
    }

    func testOneSportIsMainAndSetsTheStoredType() {
        XCTAssertEqual(AthleticRoster.view([.roadCycling]).mode, .cycling)
        XCTAssertEqual(AthleticRoster.view([.strength]).mode, .strength)
        let v = AthleticRoster.view([.roadCycling])
        XCTAssertEqual(v.mainEndurance?.id, "roadCycling"); XCTAssertNil(v.mainStrength); XCTAssertFalse(v.showsLead)
        XCTAssertEqual(v.suggestions.first?.id, "strength", "the other domain is suggested first")
    }

    func testEnduranceAndStrengthIsHybridWithALead() {
        let v = AthleticRoster.view([.roadCycling, .strength, .indoorCycling, .running])
        XCTAssertEqual(v.mode, .hybrid); XCTAssertTrue(v.showsLead)
        XCTAssertEqual(v.also.map(\.id), ["indoorCycling", "running"], "further sports are listed once, under Also training")
        XCTAssertEqual(AthleticRoster.priority(for: v.mode, chosen: nil), .balanced, "the lead defaults to Balanced")
        XCTAssertEqual(AthleticRoster.priority(for: .cycling, chosen: .strength), .cycling, "a single-domain roster has no lead of its own")
    }

    func testOnlyUnsupportedSportsMeansNoPlannedSport() {
        let v = AthleticRoster.view([.running, .swimming])
        XCTAssertNil(v.mode); XCTAssertTrue(v.hasOnlyUnsupported)
        XCTAssertEqual(v.also.map(\.id), ["running", "swimming"], "the chosen interests are kept")
        XCTAssertEqual(AthleticRoster.identityLine([.running], priority: nil), "No planned sport yet")
    }

    func testMakeMainMovesAPlannableSportToTheFrontAndRefusesAnInterest() {
        let r: [RiderProfile.Sport] = [.roadCycling, .strength, .indoorCycling, .running]
        let m = AthleticRoster.makingMain(.indoorCycling, in: r)
        XCTAssertEqual(AthleticRoster.view(m).mainEndurance?.id, "indoorCycling")
        XCTAssertEqual(AthleticRoster.view(m).also.map(\.id), ["roadCycling", "running"], "the former main sport stays in the roster")
        XCTAssertEqual(AthleticRoster.makingMain(.running, in: r), r, "a sport Cyclift cannot plan is never main")
        XCTAssertEqual(Set(m), Set(r), "nothing is added or lost")
    }

    func testAddingAndRemovingKeepEachSportOnce() {
        var r = AthleticRoster.adding(.strength, to: [.roadCycling])
        r = AthleticRoster.adding(.strength, to: r)
        XCTAssertEqual(r, [.roadCycling, .strength])
        r = AthleticRoster.removing(.roadCycling, from: r)
        XCTAssertEqual(AthleticRoster.view(r).mode, .strength, "removing the endurance sport returns the type to strength")
    }

    func testFutureActivitiesHaveNoStoredIdentifierAndCannotBeSelected() {
        let future = AthleticRoster.library.filter { $0.capability == .future }
        XCTAssertEqual(Set(future.map(\.id)), ["walking", "bodyweight", "mobility", "breathing", "sauna"])
        XCTAssertTrue(future.allSatisfy { $0.sport == nil && !$0.capability.selectable })
        XCTAssertTrue(AthleticRoster.library.filter { $0.capability != .future }.allSatisfy { $0.sport != nil }, "everything selectable has a stored identifier")
    }

    func testIdentityLine() {
        XCTAssertEqual(AthleticRoster.identityLine([.roadCycling, .strength], priority: .balanced), "Road cycling + Gym training · balanced")
        XCTAssertEqual(AthleticRoster.identityLine([.roadCycling, .strength], priority: .strength), "Gym training + Road cycling · strength-led")
        XCTAssertEqual(AthleticRoster.identityLine([.indoorCycling], priority: nil), "Indoor cycling")
    }

    func testAnswersWriteTheRosterIntoTheOneProfile() {
        var x = PlanInputs(profile: RiderProfile(), availability: nil, equipment: EquipmentProfile(), strengthPrefs: StrengthPrefs())
        var a = OnboardingAnswers(); a.sports = [.strength, .roadCycling, .running]; a.mode = .hybrid; a.priority = .strength
        a.apply(to: &x)
        XCTAssertEqual(x.profile.sports, [.strength, .roadCycling, .running]); XCTAssertEqual(x.profile.trainingMode, .hybrid); XCTAssertEqual(x.profile.priority, .strength)
        var b = OnboardingAnswers(); b.name = "A"; b.apply(to: &x)
        XCTAssertEqual(x.profile.sports, [.strength, .roadCycling, .running], "answers without a roster leave the stored one untouched")
    }
}
