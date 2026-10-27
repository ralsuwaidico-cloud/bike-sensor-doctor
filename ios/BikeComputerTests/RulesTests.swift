import XCTest
@testable import BikeComputer

/// Connection status colours, plan-day stacking, profile versioning and tolerant decoding (0.4.0).
final class RulesTests: XCTestCase {
    private func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("bc-rules-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    // MARK: Connections — red only when wanted
    func testBoardColours() {
        XCTAssertEqual(ConnectionRules.board(linkState: .ready, liveFresh: true, remembered: true, autoConnect: true, phoneOnlyMode: false), .green)
        XCTAssertEqual(ConnectionRules.board(linkState: .ready, liveFresh: false, remembered: true, autoConnect: true, phoneOnlyMode: false), .amber)
        XCTAssertEqual(ConnectionRules.board(linkState: .connecting, liveFresh: false, remembered: true, autoConnect: true, phoneOnlyMode: false), .amber)
        XCTAssertEqual(ConnectionRules.board(linkState: .idle, liveFresh: false, remembered: true, autoConnect: true, phoneOnlyMode: false), .red)      // paired board out of reach
        XCTAssertEqual(ConnectionRules.board(linkState: .idle, liveFresh: false, remembered: false, autoConnect: true, phoneOnlyMode: false), .gray)    // never paired: not a warning
        XCTAssertEqual(ConnectionRules.board(linkState: .idle, liveFresh: false, remembered: true, autoConnect: true, phoneOnlyMode: true), .gray)      // phone-only rides: board not required
        XCTAssertEqual(ConnectionRules.board(linkState: .idle, liveFresh: false, remembered: true, autoConnect: false, phoneOnlyMode: false), .gray)   // link switched off on purpose
        XCTAssertEqual(ConnectionRules.board(linkState: .off, liveFresh: false, remembered: true, autoConnect: true, phoneOnlyMode: false), .red)
    }
    func testOptionalDevicesNeverRedUnlessEnabled() {
        XCTAssertEqual(ConnectionRules.watch(paired: false, appInstalled: false, hrFresh: false, workoutRunning: false, enabled: false), .gray)
        XCTAssertEqual(ConnectionRules.watch(paired: false, appInstalled: false, hrFresh: false, workoutRunning: false, enabled: true), .red)
        XCTAssertEqual(ConnectionRules.watch(paired: true, appInstalled: true, hrFresh: false, workoutRunning: false, enabled: true), .gray)   // nothing wrong, workout not started
        XCTAssertEqual(ConnectionRules.watch(paired: true, appInstalled: true, hrFresh: false, workoutRunning: true, enabled: true), .amber)
        XCTAssertEqual(ConnectionRules.watch(paired: true, appInstalled: true, hrFresh: true, workoutRunning: true, enabled: true), .green)
        XCTAssertEqual(ConnectionRules.strap(boardLive: true, hrFromStrap: false, enabled: false), .gray)
        XCTAssertEqual(ConnectionRules.strap(boardLive: true, hrFromStrap: false, enabled: true), .amber)
        XCTAssertEqual(ConnectionRules.strap(boardLive: false, hrFromStrap: true, enabled: false), .green)
        XCTAssertEqual(ConnectionRules.meter(boardLive: true, meterLink: 4, enabled: true), .green)
        XCTAssertEqual(ConnectionRules.meter(boardLive: true, meterLink: 1, enabled: false), .gray)
        XCTAssertEqual(ConnectionRules.meter(boardLive: true, meterLink: 1, enabled: true), .red)
        XCTAssertEqual(ConnectionRules.meter(boardLive: true, meterLink: 2, enabled: true), .amber)
        XCTAssertEqual(ConnectionRules.health(wanted: false, authorized: false, available: true), .gray)
        XCTAssertEqual(ConnectionRules.health(wanted: true, authorized: false, available: true), .red)
        XCTAssertEqual(ConnectionRules.health(wanted: true, authorized: true, available: true), .green)
        XCTAssertEqual(ConnectionRules.health(wanted: true, authorized: false, available: false), .gray)
    }
    func testPhoneColours() {
        XCTAssertEqual(ConnectionRules.bluetooth(linkState: .off, boardWanted: true), .red)
        XCTAssertEqual(ConnectionRules.bluetooth(linkState: .off, boardWanted: false), .gray)
        XCTAssertEqual(ConnectionRules.bluetooth(linkState: .idle, boardWanted: true), .green)
        XCTAssertEqual(ConnectionRules.gps(authorized: false, sharing: false, hasFix: false, requiredForRides: true), .red)
        XCTAssertEqual(ConnectionRules.gps(authorized: false, sharing: false, hasFix: false, requiredForRides: false), .gray)
        XCTAssertEqual(ConnectionRules.gps(authorized: true, sharing: true, hasFix: false, requiredForRides: true), .amber)
        XCTAssertEqual(ConnectionRules.gps(authorized: true, sharing: true, hasFix: true, requiredForRides: true), .green)
        XCTAssertEqual(ConnectionRules.internet(online: false), .amber)     // the app works offline: never red
    }

    // MARK: Plan — several activities on one day stack, never overlap
    func testPlanDayGroupsMultipleActivities() {
        let cal = Calendar.current
        let monday = cal.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        var p = RiderProfile.screened(); p.hoursPerWeek = 6
        var week = PlanEngine.week(starting: monday, profile: p, availability: WeeklyAvailability.suggested(hoursPerWeek: 6))
        week.append(Workout(date: cal.date(byAdding: .day, value: 1, to: monday)!, kind: .mobility, minutes: 30))
        week.append(Workout(date: cal.date(byAdding: .hour, value: 30, to: monday)!, kind: .strength, minutes: 20))   // Tuesday 06:00
        let days = PlanDay.group(week, weekOf: cal.date(byAdding: .day, value: 3, to: monday)!, calendar: cal)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days[0].items.count, 1)
        XCTAssertEqual(days[1].items.count, 3)
        XCTAssertEqual(days[1].items.first?.kind, .endurance)                  // the ride is listed first
        XCTAssertEqual(days.map { $0.items.count }.reduce(0, +), week.count)  // nothing lost, nothing drawn twice
        XCTAssertTrue(days.allSatisfy { d in d.items.allSatisfy { cal.isDate($0.date, inSameDayAs: d.date) } })
    }

    // MARK: Profile versioning — every rider change bumps, loading does not
    func testProfileVersionBumpsOnChangeOnly() {
        let dir = tempDir()
        let s = Store(directory: dir, generatePlan: false)
        let v0 = s.profile.version
        s.profile.name = "Rashed"
        XCTAssertEqual(s.profile.version, v0 + 1)
        s.profile.name = "Rashed"                     // same value: SwiftUI bindings re-set; no bump
        XCTAssertEqual(s.profile.version, v0 + 1)
        s.updateProfile { $0.ftpW = 260; $0.ftpHow = .tested }
        XCTAssertEqual(s.profile.version, v0 + 2)
        let again = Store(directory: dir, generatePlan: false)
        XCTAssertEqual(again.profile.version, v0 + 2)   // reload keeps the version (no bump on load)
        XCTAssertEqual(again.profile.ftpHow, .tested)
    }

    func testSyncRecordPerBoard() {
        let s = Store(directory: tempDir(), generatePlan: false)
        XCTAssertEqual(s.syncRecord(for: "aa").ackedVersion, 0); XCTAssertFalse(s.syncRecord(for: "aa").confirmed)
        var r = s.syncRecord(for: "aa"); r.confirmed = true; r.ackedVersion = 7; s.setSyncRecord(r)
        XCTAssertTrue(s.syncRecord(for: "aa").confirmed); XCTAssertEqual(s.syncRecord(for: "aa").ackedVersion, 7)
        XCTAssertFalse(s.syncRecord(for: "bb").confirmed)                     // a second board starts unconfirmed
    }

    // MARK: Tolerant decoding — a build-17/21 store.json loads with the new fields defaulted
    func testOldProfileAndSettingsJSONLoad() throws {
        let json = """
        {"schema":1,"profile":{"name":"R","goal":"stronger","hoursPerWeek":4,"level":"beginner","weightKg":70,"age":40,"ftpW":180,"ftpHow":"entered","hrPrefWatchFirst":false},
         "settings":{"units":"metric","phoneOnlyMode":true,"hrPref":"watch","keepScreenOn":true},"plan":[],"rides":[],"tiles":["power"],"onboarded":true,"guest":true}
        """
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let f = try dec.decode(StoreFile.self, from: Data(json.utf8))
        XCTAssertEqual(f.profile.name, "R"); XCTAssertEqual(f.profile.goal, .stronger); XCTAssertEqual(f.profile.ftpHow, .entered)
        XCTAssertNil(f.profile.birthYear); XCTAssertEqual(f.profile.sports, [.roadCycling]); XCTAssertEqual(f.profile.version, 1)
        XCTAssertEqual(f.profile.effectiveAge, 40)                                  // age slider still honoured when no birth year
        XCTAssertTrue(f.settings.phoneOnlyMode); XCTAssertEqual(f.settings.hrPref, .watch)
        XCTAssertTrue(f.settings.autoConnectBoard); XCTAssertEqual(f.settings.enabledConnections, ["board", "watch"]); XCTAssertFalse(f.settings.appleHealthWanted)
        XCTAssertEqual(f.boardSync, []); XCTAssertEqual(f.onboardingStage, 0)
        // an unknown goal string from a future build falls back instead of failing the load
        let future = json.replacingOccurrences(of: "\"stronger\"", with: "\"timeTrial\"")
        XCTAssertEqual(try dec.decode(StoreFile.self, from: Data(future.utf8)).profile.goal, .endurance)
    }

    // MARK: Onboarding — skipped values stay unknown, never invented
    func testSkippedOnboardingValuesStayUnknown() {
        var p = RiderProfile()
        XCTAssertNil(p.birthYear); XCTAssertNil(p.maxHR); XCTAssertNil(p.restHR); XCTAssertNil(p.lthr)
        XCTAssertEqual(p.ftpHow, .assumed); XCTAssertEqual(p.ftpLabel, "Provisional estimate")
        XCTAssertEqual(p.maxHRLabel, "estimated from age")
        p.birthYear = 1990; XCTAssertEqual(p.effectiveAge, Calendar.current.component(.year, from: Date()) - 1990)
        p.maxHR = 186; XCTAssertEqual(p.estimatedMaxHR, 186); XCTAssertEqual(p.maxHRLabel, "measured / entered")
        // the Link message carries 0 for unknowns, so the board also shows "not set"
        var q = RiderProfile(); q.version = 3
        let m = q.linkMessage(units: .metric)
        XCTAssertEqual(m.birthYear, 0); XCTAssertEqual(m.maxHR, 0); XCTAssertEqual(m.lthr, 0); XCTAssertEqual(m.ftpHow, 0)
    }

    // MARK: Coach — one line, honest reasoning
    func testCoachLineAndWhyNeverClaimRecoveryData() {
        let s = Store(directory: tempDir(), generatePlan: false)
        let w = Workout(date: Date(), kind: .endurance, minutes: 45)
        XCTAssertEqual(Coach.todayLine(w), "Today: 45 min endurance ride (Zone 2) to improve aerobic fitness.")
        XCTAssertEqual(Coach.todayLine(Workout(date: Date(), kind: .rest, minutes: 0)), "Today: rest day — adaptation happens here.")
        let why = Coach.why(w, store: s)
        XCTAssertTrue(why.contains("No rides are recorded yet"))
        XCTAssertTrue(why.contains("No sleep, HRV or recovery source is connected"))
        XCTAssertFalse(why.lowercased().contains("your sleep was"))
        XCTAssertEqual(Coach.alternatives(for: w).map { $0.kind }, [.recovery, .mobility])
        XCTAssertEqual(Coach.alternatives(for: Workout(date: Date(), kind: .threshold, minutes: 70)).map { $0.kind }, [.recovery, .threshold, .mobility])
    }
}
