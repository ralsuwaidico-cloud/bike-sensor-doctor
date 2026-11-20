import XCTest
@testable import BikeComputer

/// Onboarding Screen 3 — the multi-sport Athletic Roster (owner decision 20 Nov 2026, 23:04): any number of activities,
/// any of them main, identity from what was selected, and selection kept apart from planning and recording support.
/// The earlier tests assumed a cycling-and-strength roster in which other sports were "interests" and five activities
/// could not be chosen at all; that product rule was replaced, so those expectations are rewritten here.
final class AthleticRosterTests: XCTestCase {
    // MARK: the catalogue

    func testCatalogueHasTheDisciplinesOfEachSport() {
        func ids(_ f: RosterFamily) -> [String] { AthleticRoster.library.filter { $0.family == f }.map(\.id) }
        XCTAssertEqual(ids(.cycling), ["roadCycling", "indoorCycling", "mountainBike", "gravel", "commuting"])
        XCTAssertEqual(ids(.strength), ["strength", "freeWeights", "machines", "bodyweight", "calisthenics"])
        XCTAssertEqual(ids(.running), ["running", "treadmill", "trailRunning"])
        XCTAssertEqual(ids(.swimming), ["swimming", "openWater"])
        XCTAssertEqual(ids(.walking), ["walking", "hiking"])
        XCTAssertEqual(ids(.recovery), ["mobility", "breathing", "sauna"])
        XCTAssertEqual(Set(AthleticRoster.library.map(\.id)).count, AthleticRoster.library.count, "identifiers are unique")
    }
    /// Only the two engines that exist are claimed. Everything else is selectable and says it is not planned or recorded.
    func testCapabilityIsToldTruthfully() {
        for x in AthleticRoster.library {
            switch x.family {
            case .cycling: XCTAssertEqual(x.planning, .cycling, x.id); XCTAssertEqual(x.recording, .cycling, x.id)
            case .strength where ["strength", "freeWeights", "machines"].contains(x.id): XCTAssertEqual(x.planning, .strength, x.id); XCTAssertEqual(x.recording, .strength, x.id)
            default:
                XCTAssertNil(x.planning, "\(x.id) is not planned"); XCTAssertNil(x.recording, "\(x.id) is not recorded")
                XCTAssertEqual(x.capabilityWords, "In your roster · not planned or recorded yet", x.id)
                XCTAssertFalse(x.capabilityWords.lowercased().contains("planned and recorded"), "\(x.id) must never be called planned and recorded")
            }
        }
        XCTAssertEqual(AthleticRoster.activity("roadCycling")?.capabilityWords, "Planned · recorded")
        XCTAssertEqual(AthleticRoster.activity("strength")?.capabilityWords, "Planned · recorded")
        XCTAssertEqual(AthleticRoster.activity("gravel")?.capabilityWords, "Planned and recorded as general cycling")
        XCTAssertEqual(AthleticRoster.activity("machines")?.capabilityWords, "Planned and recorded as gym training")
        XCTAssertEqual(AthleticRoster.library.filter { $0.capability == .plansAndRecords }.map(\.id), ["roadCycling", "strength"])
    }

    // MARK: selection

    func testEmptyRosterOffersOneActivityPerSport() {
        let v = AthleticRoster.view([])
        XCTAssertTrue(v.isEmpty); XCTAssertNil(v.mode); XCTAssertFalse(v.hasOnlyUnsupported)
        XCTAssertEqual(v.suggestions.map(\.id), ["roadCycling", "strength", "running", "swimming", "walking", "mobility"])
        XCTAssertEqual(Set(v.suggestions.map(\.family)).count, 6, "one per sport: none is the app's default")
    }
    func testAnyNumberOfActivitiesCanBeSelected() {
        var r: [String] = []
        for x in AthleticRoster.library { r = AthleticRoster.adding(x.id, to: r) }
        XCTAssertEqual(r.count, AthleticRoster.library.count, "every catalogue activity can be in the roster at once")
        XCTAssertEqual(AthleticRoster.adding("running", to: r), r, "each activity once")
        XCTAssertEqual(AthleticRoster.adding("notAnActivity", to: ["running"]), ["running"], "only catalogue activities")
        XCTAssertEqual(AthleticRoster.removing("running", from: ["running", "hiking"]), ["hiking"])
    }
    func testAnyActivityCanBeMainAndNothingIsLost() {
        let r = ["roadCycling", "strength", "trailRunning", "openWater"]
        let m = AthleticRoster.makingMain("trailRunning", in: r)
        XCTAssertEqual(m, ["trailRunning", "roadCycling", "strength", "openWater"])
        let v = AthleticRoster.view(m)
        XCTAssertEqual(v.main?.id, "trailRunning", "a sport Cyclift cannot plan can still be the athlete's main sport")
        XCTAssertEqual(v.mains.map(\.id), ["trailRunning", "roadCycling", "strength"]); XCTAssertEqual(v.also.map(\.id), ["openWater"])
        XCTAssertEqual(v.mode, .hybrid, "the plan is still built from the activities Cyclift can plan")
        XCTAssertEqual(Set(m), Set(r))
    }

    // MARK: the stored training type still comes from what can be planned

    func testTrainingTypeFollowsThePlannableActivities() {
        XCTAssertEqual(AthleticRoster.view(["roadCycling"]).mode, .cycling)
        XCTAssertEqual(AthleticRoster.view(["gravel"]).mode, .cycling)
        XCTAssertEqual(AthleticRoster.view(["machines"]).mode, .strength)
        XCTAssertEqual(AthleticRoster.view(["running", "strength"]).mode, .strength)
        let v = AthleticRoster.view(["roadCycling", "strength", "indoorCycling", "running"])
        XCTAssertEqual(v.mode, .hybrid); XCTAssertTrue(v.showsLead)
        XCTAssertEqual(v.mainEndurance?.id, "roadCycling"); XCTAssertEqual(v.mainStrength?.id, "strength")
        XCTAssertEqual(v.also.map(\.id), ["indoorCycling", "running"])
        XCTAssertEqual(AthleticRoster.priority(for: v.mode, chosen: nil), .balanced)
        XCTAssertEqual(AthleticRoster.priority(for: .cycling, chosen: .strength), .cycling)
    }
    /// Nothing is manufactured: a roster with no plannable activity has no training type.
    func testARosterCycliftCannotPlanHasNoTrainingType() {
        let v = AthleticRoster.view(["running", "openWater", "bodyweight"])
        XCTAssertNil(v.mode); XCTAssertTrue(v.hasOnlyUnsupported); XCTAssertFalse(v.showsLead)
        XCTAssertEqual(v.main?.id, "running"); XCTAssertNil(v.mainEndurance); XCTAssertNil(v.mainStrength)
        XCTAssertNil(AthleticRoster.priority(for: v.mode, chosen: .balanced))
    }

    // MARK: identity from what was selected (the decision's examples)

    func testIdentity() {
        XCTAssertEqual(AthleticRoster.identity(["roadCycling", "strength"]), "Cycling/Strength hybrid")
        XCTAssertEqual(AthleticRoster.identity(["running", "strength"]), "Running/Strength hybrid")
        XCTAssertEqual(AthleticRoster.identity(["roadCycling", "running", "swimming"]), "Multisport endurance athlete")
        XCTAssertEqual(AthleticRoster.identity(["trailRunning"]), "Runner")
        XCTAssertEqual(AthleticRoster.identity(["running", "treadmill", "trailRunning"]), "Runner", "three disciplines of one sport are one sport")
        XCTAssertEqual(AthleticRoster.identity(["roadCycling", "running", "strength"]), "Multisport athlete")
        XCTAssertEqual(AthleticRoster.identity(["gravel", "mountainBike"]), "Cyclist")
        XCTAssertEqual(AthleticRoster.identity(["machines"]), "Strength athlete")
        XCTAssertEqual(AthleticRoster.identity(["openWater"]), "Swimmer")
        XCTAssertEqual(AthleticRoster.identity(["roadCycling", "mobility"]), "Cyclist", "mobility and recovery do not change the sport")
        XCTAssertEqual(AthleticRoster.identity(["mobility", "breathing"]), "Mobility & recovery")
        XCTAssertEqual(AthleticRoster.identity([]), "No activity selected yet")
        XCTAssertEqual(AthleticRoster.identityLine(["roadCycling", "strength"], priority: .strength), "Cycling/Strength hybrid · strength-led")
        XCTAssertEqual(AthleticRoster.identityLine(["running"], priority: .balanced), "Runner")
    }
    func testSupportLineSaysWhatIsAndIsNotCovered() {
        XCTAssertNil(AthleticRoster.supportLine([]))
        XCTAssertEqual(AthleticRoster.supportLine(["roadCycling", "strength"]), "Cyclift will plan and record Road cycling and Gym training.")
        XCTAssertEqual(AthleticRoster.supportLine(["running"]), "Road running is in your roster. Cyclift cannot plan or record it yet.")
        XCTAssertEqual(AthleticRoster.supportLine(["roadCycling", "running"]), "Cyclift will plan and record Road cycling. Road running is not planned or recorded yet.")
        // more than two activities are counted, so the sentence is always read in full on the page
        XCTAssertEqual(AthleticRoster.supportLine(["roadCycling", "running", "hiking"]), "Cyclift will plan and record 1 of your 3 activities. The other 2 are not planned or recorded yet.")
        XCTAssertEqual(AthleticRoster.supportLine(["roadCycling", "strength", "gravel", "running"]), "Cyclift will plan and record 3 of your 4 activities. The other one is not planned or recorded yet.")
        XCTAssertEqual(AthleticRoster.supportLine(["roadCycling", "strength", "gravel"]), "Cyclift will plan and record all 3 activities.")
        XCTAssertEqual(AthleticRoster.supportLine(["running", "hiking", "openWater"]), "All 3 are in your roster. Cyclift cannot plan or record them yet.")
        for ids in [["roadCycling", "running"], AthleticRoster.library.map(\.id), ["running", "hiking", "openWater"]] {
            XCTAssertLessThan((AthleticRoster.supportLine(ids) ?? "").count, 100, "short enough for the line above Continue")
        }
    }

    // MARK: storage — additive, older records and older builds unharmed

    func testAnswersWriteTheRosterAndTheOlderList() {
        var x = PlanInputs(profile: RiderProfile(), availability: nil, equipment: EquipmentProfile(), strengthPrefs: StrengthPrefs())
        var a = OnboardingAnswers(); a.activities = ["trailRunning", "strength", "gravel", "roadCycling", "swimming"]; a.mode = .hybrid; a.priority = .strength
        a.apply(to: &x)
        XCTAssertEqual(x.profile.activities, ["trailRunning", "strength", "gravel", "roadCycling", "swimming"], "the selection is stored exactly, in order")
        XCTAssertEqual(x.profile.sports, [.strength, .roadCycling, .swimming], "the older list receives what it can name")
        XCTAssertEqual(x.profile.trainingMode, .hybrid); XCTAssertEqual(x.profile.priority, .strength)
        var b = OnboardingAnswers(); b.name = "A"; b.apply(to: &x)
        XCTAssertEqual(x.profile.activities, ["trailRunning", "strength", "gravel", "roadCycling", "swimming"], "answers without a roster leave the stored one untouched")
        XCTAssertFalse(x.planningDiffers(from: { var y = x; y.profile.activities = ["hiking"]; return y }()), "the selection alone is not a planning input")
    }
    func testTheRosterSurvivesSavingAndReading() throws {
        var p = RiderProfile(); p.activities = ["trailRunning", "gravel", "strength"]; p.sports = AthleticRoster.legacySports(p.activities!)
        let read = try JSONDecoder().decode(RiderProfile.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(read.activities, ["trailRunning", "gravel", "strength"]); XCTAssertEqual(AthleticRoster.roster(of: read), ["trailRunning", "gravel", "strength"])
    }
    /// A record from before the multi-sport roster has no `activities` key: it reads as it always did, and its roster is
    /// its older sports list. Nothing is rewritten by reading it.
    func testAnOlderRecordReadsUnchanged() throws {
        var old = RiderProfile(); old.name = "Sam"; old.sports = [.roadCycling, .strength, .running]
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "activities")
        let read = try JSONDecoder().decode(RiderProfile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(read.activities); XCTAssertEqual(read.sports, [.roadCycling, .strength, .running]); XCTAssertEqual(read.name, "Sam")
        XCTAssertEqual(AthleticRoster.roster(of: read), ["roadCycling", "strength", "running"])
    }
    /// What an older build sees of a new record: the `sports` list, every value one it already knows.
    func testTheOlderListOnlyEverHoldsValuesAnOlderBuildKnows() {
        let all = AthleticRoster.library.map(\.id)
        XCTAssertEqual(Set(AthleticRoster.legacySports(all)), Set(RiderProfile.Sport.allCases).subtracting([.other]))
        XCTAssertEqual(AthleticRoster.legacySports(["gravel", "hiking", "calisthenics"]), [], "new activities add nothing an older build could trip over")
    }
    /// An identifier from a newer catalogue is not shown and not destroyed by reading.
    func testAnUnknownIdentifierIsIgnoredNotRewritten() {
        var p = RiderProfile(); p.activities = ["roadCycling", "kitesurfing"]
        XCTAssertEqual(AthleticRoster.roster(of: p), ["roadCycling"]); XCTAssertEqual(p.activities, ["roadCycling", "kitesurfing"])
    }
    func testTheOlderSportsPickerKeepsBothListsInStep() {
        var p = RiderProfile(); p.sports = [.roadCycling]; p.activities = ["roadCycling", "hiking"]
        AthleticRoster.toggleLegacy(.strength, in: &p)
        XCTAssertEqual(p.sports, [.roadCycling, .strength]); XCTAssertEqual(p.activities, ["roadCycling", "hiking", "strength"])
        AthleticRoster.toggleLegacy(.roadCycling, in: &p)
        XCTAssertEqual(p.sports, [.strength]); XCTAssertEqual(p.activities, ["hiking", "strength"])
        var legacy = RiderProfile(); legacy.sports = [.roadCycling]
        AthleticRoster.toggleLegacy(.running, in: &legacy)
        XCTAssertNil(legacy.activities, "a record without a saved roster does not gain one by this"); XCTAssertEqual(legacy.sports, [.roadCycling, .running])
    }
}
