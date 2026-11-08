import XCTest
@testable import BikeComputer

/// Checkpoint C correction pass (owner 6 Nov addendum): the Profile Quick Menu shows the stored values, never invents
/// them, and opening it (or computing its pages) never changes the plan, preferences or settings.
final class ProfileMenuTests: XCTestCase {
    private func store() -> Store {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("pm-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return Store(directory: d, generatePlan: false)
    }
    private func day(_ sport: DayAssignment.Sport?, _ minutes: Int = 0) -> DayAvailability {
        guard let s = sport else { return DayAvailability(activity: .rest, minutes: 0) }
        return DayAvailability(assignments: [DayAssignment(sport: s, minutes: minutes)])
    }
    private func hybrid(_ s: Store, supersets: Bool?) {
        var p = RiderProfile.screened(); p.name = "Rashed Example"; p.trainingMode = .hybrid; p.priority = .balanced; p.hoursPerWeek = 3; p.liftingHoursPerWeek = 1
        p.cyclingDaysPerWeek = 3; p.liftDaysPerWeek = 2; p.weekIsExplicit = true; p.goal = .endurance; p.goals = [.endurance, .strength]; p.primaryGoal = .endurance
        p.cyclingSessionMinutes = 60; p.strengthSessionMinutes = 30
        s.profile = p
        s.strengthPrefs.experience = .intermediate; s.strengthPrefs.prefersSupersets = supersets
        s.equipment = EquipmentPreset.gym.apply(to: s.equipment)
        s.availability = WeeklyAvailability(days: [day(.strength, 30), day(.cycling, 60), day(.strength, 30), day(.cycling, 60), day(nil), day(.cycling, 60), day(nil)])
    }
    private func fact(_ sections: [ProfileFactSection], _ title: String) -> ProfileFact? { sections.flatMap(\.facts).first { $0.title == title } }

    func testHeaderUsesTheStoredNameAndTypeOrSaysNotSet() {
        let s = store(); hybrid(s, supersets: true)
        let h = s.profileMenuHeader()
        XCTAssertEqual(h.initials, "RE"); XCTAssertEqual(h.name, "Rashed Example"); XCTAssertEqual(h.athleteType, "Hybrid · balanced")
        var p = s.profile; p.name = "  "; s.profile = p
        let none = s.profileMenuHeader()
        XCTAssertNil(none.name, "no placeholder presented as a real name"); XCTAssertEqual(none.initials, "")
        XCTAssertTrue(s.profileMenuLines(connectedDevices: 0, healthReadsOn: false).profile.hasPrefix("Name not set"))
    }

    func testPreferencesShowTheRealStoredValuesIncludingSupersets() {
        let s = store(); hybrid(s, supersets: true)
        let f = s.profilePreferenceFacts()
        XCTAssertEqual(f.map(\.title), ["Training goals", "Training structure", "Equipment"])
        XCTAssertEqual(fact(f, "Main goal")?.value, s.profile.effectivePrimaryGoal.title)
        XCTAssertEqual(fact(f, "Main goal")?.edit, .goals)
        XCTAssertEqual(fact(f, "Strength goal")?.value, s.plannerContext().goal.title)
        XCTAssertEqual(fact(f, "Ride days")?.value, "Tue, Thu, Sat")
        XCTAssertEqual(fact(f, "Lift days")?.value, "Mon, Wed")
        XCTAssertEqual(fact(f, "Ride length")?.value, Fmt.duration(minutes: 60))
        XCTAssertEqual(fact(f, "Lift length")?.value, Fmt.duration(minutes: 30))
        XCTAssertEqual(fact(f, "Sessions per week")?.value, "3 rides · 2 lifts")
        XCTAssertEqual(fact(f, "Strength / cycling balance")?.value, s.profile.priority.title)
        XCTAssertEqual(fact(f, "Supersets")?.value, "On — paired when the exercises allow it")
        XCTAssertEqual(fact(f, "Supersets")?.edit, .week, "edited where it is stored (Your week), through the plan preview")
        XCTAssertNil(fact(f, "Lifting experience"), "owner 8 Nov: experience is shown once, under My profile › Athlete, not again under Training settings")
        XCTAssertNil(fact(f, "Riding level"))
        XCTAssertEqual(fact(f, "Gym equipment")?.value, "Full gym")
        XCTAssertEqual(fact(f, "Avoided exercises")?.value, "None")
        XCTAssertEqual(fact(f, "Cycling devices")?.edit, nil, "devices are shown live on Devices & Connections, not here")
        s.strengthPrefs.prefersSupersets = false
        XCTAssertEqual(fact(s.profilePreferenceFacts(), "Supersets")?.value, "Off")
        s.strengthPrefs.prefersSupersets = nil
        XCTAssertEqual(fact(s.profilePreferenceFacts(), "Supersets")?.value, "Not set — no supersets")
        XCTAssertTrue(s.profileMenuLines(connectedDevices: 0, healthReadsOn: false).preferences.contains("supersets off"))
    }

    func testMyProfileNeverInventsPersonalValues() {
        let s = store(); hybrid(s, supersets: nil)
        let f = s.profileMyFacts()
        XCTAssertEqual(fact(f, "Name")?.value, "Rashed Example")
        XCTAssertEqual(fact(f, "Height")?.value, "Not recorded"); XCTAssertNil(fact(f, "Height")?.edit, "height has no editor — read-only")
        if s.profile.dateOfBirth == nil { XCTAssertEqual(fact(f, "Age")?.value, "Not set") }
        var p = s.profile; p.heightCm = 180; p.setDateOfBirth(Calendar.current.date(byAdding: .year, value: -40, to: Date())!); p.setWeight(78); s.profile = p
        let g = s.profileMyFacts()
        XCTAssertEqual(fact(g, "Height")?.value, "180 cm")
        XCTAssertEqual(fact(g, "Age")?.value, "40")
        XCTAssertTrue(fact(g, "Weight")?.note?.hasPrefix("Entered by you") == true, fact(g, "Weight")?.note ?? "")
        XCTAssertEqual(fact(g, "Athlete type")?.value, "Hybrid · balanced")
        XCTAssertEqual(fact(g, "Lifting experience")?.value, "Intermediate")
        XCTAssertEqual(ProfileMenuModel.height(180, units: .imperial), "5 ft 11 in")
    }

    func testConnectionLineCountsOnlyConnectedDevices() {
        let s = store(); hybrid(s, supersets: nil)
        XCTAssertEqual(s.profileMenuLines(connectedDevices: 0, healthReadsOn: false).connections, "No device connected")
        XCTAssertEqual(s.profileMenuLines(connectedDevices: 2, healthReadsOn: true).connections, "2 connected · Health reads on")
    }

    func testOpeningTheMenuPagesChangesNothing() {
        let s = store(); hybrid(s, supersets: true)
        _ = s.regenerate(weekOf: Calendar.current.date(byAdding: .day, value: 7, to: Date())!, replaceEdited: true)
        let plan = s.plan, versions = s.planVersions.count, prefs = s.strengthPrefs, profile = s.profile, settings = s.settings, equipment = s.equipment
        for _ in 0..<3 {
            _ = s.profileMenuHeader(); _ = s.profileMyFacts(); _ = s.profilePreferenceFacts()
            _ = s.profileMenuLines(connectedDevices: 1, healthReadsOn: true)
        }
        XCTAssertEqual(s.plan, plan); XCTAssertEqual(s.planVersions.count, versions)
        XCTAssertEqual(s.strengthPrefs, prefs); XCTAssertEqual(s.profile, profile); XCTAssertEqual(s.settings, settings); XCTAssertEqual(s.equipment, equipment)
    }
}
