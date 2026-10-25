import XCTest

/// Launch smoke tests: the app must come up on a fresh install AND on a phone updated from an older build whose
/// store.json lacks the newer keys (build 27 crashed at launch on exactly that path). Runs on the simulator in CI
/// before every archive; the seed/reset hooks are simulator-only (UITestSupport.swift).
final class LaunchSmokeTests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    func testFreshInstallShowsWelcome() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_RESET"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["BikeComputer"].waitForExistence(timeout: 20), "fresh launch must show the welcome screen")
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testUpgradeFromBuild24StoreShowsHomeAndAllTabsOpen() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = Self.build24Store()
        app.launch()
        // Home: the navigation title carries the rider's name from the seeded profile
        XCTAssertTrue(app.navigationBars["Hi Rashed"].waitForExistence(timeout: 25) || app.staticTexts["Hi Rashed"].waitForExistence(timeout: 5),
                      "an existing rider must land on Home, not crash or see onboarding")
        for label in ["Plan", "Ride now, open the Ride screen", "Progress", "Profile", "Home"] {
            let b = app.buttons[label].firstMatch
            XCTAssertTrue(b.waitForExistence(timeout: 10), "tab \(label) missing")
            b.tap()
            sleep(1)
            XCTAssertEqual(app.state, .runningForeground, "app died after opening \(label)")
        }
    }

    /// A store.json as build 24 (0.4.0) wrote it: schema 1, no `availability`, no `edited` on workouts, profile without
    /// the 0.5.0 fields, one phone ride with 1 Hz samples, this week's plan including today.
    static func build24Store() -> String {
        let iso = ISO8601DateFormatter()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let wd = (cal.component(.weekday, from: today) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -wd, to: today)!
        let kinds = ["endurance", "rest", "tempo", "endurance", "rest", "long", "strength"]
        var plan: [String] = []
        for i in 0..<7 {
            let d = cal.date(byAdding: .day, value: i, to: monday)!
            plan.append("{\"id\":\"\(UUID().uuidString)\",\"date\":\"\(iso.string(from: d))\",\"kind\":\"\(kinds[i])\",\"minutes\":\(kinds[i] == "rest" ? 0 : 60),\"done\":\(i < wd),\"skipped\":false,\"note\":\"\"}")
        }
        let rideStart = cal.date(byAdding: .day, value: -2, to: today)!.addingTimeInterval(8 * 3600)
        var samples: [String] = []
        for t in 0..<120 { samples.append("{\"t\":\(t),\"w\":\(150 + (t % 20)),\"cad\":\(85 + (t % 5)),\"hr\":\(130 + (t % 10)),\"speedCms\":\(700 + (t % 30))}") }
        return """
        {"schema":1,
         "profile":{"name":"Rashed","goal":"endurance","hoursPerWeek":6,"level":"intermediate","weightKg":82,"age":35,"ftpW":210,"ftpHow":"entered",
                    "hrPrefWatchFirst":true,"birthYear":1988,"sports":["roadCycling"],"version":4,"updatedAt":"2026-10-24T20:00:00Z"},
         "settings":{"units":"metric","phoneOnlyMode":false,"hrPref":"watch","keepScreenOn":true,"autoConnectBoard":true,"enabledConnections":["board","watch"]},
         "plan":[\(plan.joined(separator: ","))],
         "rides":[{"id":"\(UUID().uuidString)","start":"\(iso.string(from: rideStart))","durationS":120,"distanceM":860,"avgPower":160,"maxPower":169,"normalizedPower":162,
                   "avgCadence":87,"avgHR":134,"maxHR":139,"kj":19,"zoneSeconds":[0,120,0,0,0,0,0],"recorder":"phone","sources":["Phone GPS","Apple Watch"],"demo":false,
                   "samples":[\(samples.joined(separator: ","))]}],
         "tiles":["power","cadence","hr","speed","time","dist"],"onboarded":true,"guest":true,"createdAt":"2026-10-24T10:00:00Z",
         "boardSync":[],"onboardingStage":3}
        """
    }
}
