import XCTest
@testable import BikeComputer

/// E1-A4: writes synthetic athlete stores WITH THE BUILD-216 CODE. This file is compiled against the sources of commit
/// fb52ae27 (the commit of TestFlight build 216), so every store.json it produces went through build 216's own
/// serializer. The E1 tests then open those files with the new code. Nothing here is real athlete data.
final class Fixture216Generator: XCTestCase {
    private func make(_ name: String, _ fill: (Store) -> Void) throws {
        guard let out = ProcessInfo.processInfo.environment["FIXTURE_OUT"] else { throw XCTSkip("FIXTURE_OUT is not set") }
        let d = URL(fileURLWithPath: out).appendingPathComponent(name)
        try? FileManager.default.removeItem(at: d)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let s = Store(directory: d)
        s.profile.name = "Fixture \(name)"
        // identity, baselines, preferences and device settings with non-default values, so a lost field is visible
        s.profile.weightKg = 74.5; s.profile.ftpW = 215; s.profile.hoursPerWeek = 6
        s.settings.keepScreenOn = false; s.settings.units = .imperial; s.settings.phoneOnlyMode = true
        fill(s)
        s.onboarded = true
        // what the new build must find again, written beside the store by the code that created it
        let reopened = Store(directory: d, generatePlan: false)
        let manifest: [String: Any] = [
            "name": reopened.profile.name, "onboarded": reopened.onboarded,
            "plan": reopened.plan.count, "planDone": reopened.plan.filter { $0.done }.count,
            "strength": reopened.strength.count, "strengthMinutes": reopened.strength.reduce(0) { $0 + $1.minutes },
            "rides": reopened.rides.count, "rideSeconds": reopened.rides.reduce(0) { $0 + $1.durationS },
            "templates": reopened.templates.count,
            "strengthIds": reopened.strength.map { $0.id.uuidString }.sorted(), "rideIds": reopened.rides.map { $0.id.uuidString }.sorted(),
            "planIds": reopened.plan.map { $0.id.uuidString }.sorted(),
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: d.appendingPathComponent("manifest.json"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: d.appendingPathComponent("store.json").path))
    }
    private func day(_ back: Int, _ hour: Double = 18) -> Date { Calendar.current.startOfDay(for: Date()).addingTimeInterval(Double(-back) * 86_400 + hour * 3600) }

    func testWriteBuild216Fixtures() throws {
        try make("empty") { _ in }
        try make("strength") { s in
            s.equipment = EquipmentProfile(owned: ["dumbbell", "bench"])
            for i in 1...12 { XCTAssertTrue(s.addStrength(StrengthSession(date: self.day(i * 2), minutes: 30 + i, focus: i % 2 == 0 ? .fullBody : .upper, rpe: 6 + i % 3))) }
        }
        try make("cycling") { s in
            for i in 1...10 { XCTAssertTrue(s.addRide(RideRecord(start: self.day(i * 3, 7), durationS: 3000 + i * 120, distanceM: 20_000 + i * 500, recorder: .phone, sources: ["iPhone"]))) }
        }
        try make("hybrid") { s in
            for i in 1...8 { XCTAssertTrue(s.addStrength(StrengthSession(date: self.day(i * 3), minutes: 35, focus: .fullBody, rpe: 7))) }
            for i in 1...8 { XCTAssertTrue(s.addRide(RideRecord(start: self.day(i * 3 + 1, 7), durationS: 3600, distanceM: 28_000, recorder: .phone, sources: ["iPhone"]))) }
        }
        try make("noequipment") { s in
            for i in 1...4 { XCTAssertTrue(s.addStrength(StrengthSession(date: self.day(i * 4), minutes: 30, focus: .fullBody, rpe: 7))) }
        }
        try make("large") { s in
            for i in 1...400 { _ = s.addStrength(StrengthSession(date: self.day(i), minutes: 40, focus: .fullBody, rpe: 7)) }
            for i in 1...300 { _ = s.addRide(RideRecord(start: self.day(i, 7), durationS: 7200, distanceM: 55_000, recorder: .phone, sources: ["iPhone"])) }
        }
    }
}
