import XCTest

/// Ride layouts smoke test: a phone updated from build 40 with a RIDE scheduled today opens the Ride screen from the
/// centre button and switches through all five layouts with the quick switch; every layout shows the coach panel and
/// the app stays in the foreground. The seed follows LaunchSmokeTests.build40Store (copied here, not shared).
final class RideLayoutsSmokeTests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }

    func testSwitchThroughAllRideLayouts() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = Self.rideDayStore()
        app.launch()
        XCTAssertTrue(app.navigationBars["Hi Rashed"].waitForExistence(timeout: 25) || app.staticTexts["Hi Rashed"].waitForExistence(timeout: 5), "seeded rider lands on Home")

        let centre = app.buttons["centreButton"].firstMatch
        XCTAssertTrue(centre.waitForExistence(timeout: 10))
        centre.tap()
        // a ride day opens the Ride screen directly; close a sheet if the plan offered a choice
        for name in ["Done", "Cancel", "Close"] { let c = app.buttons[name].firstMatch; if c.exists && c.isHittable { c.tap(); break } }

        let menu = app.buttons["rideLayoutMenu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 15), "ride layout quick switch on the live screen")
        XCTAssertTrue(app.otherElements["rideLayout.coach"].firstMatch.waitForExistence(timeout: 10), "default layout is Ride Coach")
        XCTAssertTrue(app.otherElements["coachPanel"].firstMatch.exists, "coach panel embedded")

        // one tap on the layout name = next layout (coach → gauges → classic → rings → analytics → coach)
        let order: [(String, String)] = [("gauges", "Large gauges"), ("classic", "Classic"), ("rings", "Rings"), ("analytics", "Analytics"), ("coach", "Ride Coach")]
        for (raw, title) in order {
            XCTAssertTrue(menu.waitForExistence(timeout: 5))
            menu.tap()
            XCTAssertTrue(app.otherElements["rideLayout.\(raw)"].firstMatch.waitForExistence(timeout: 10), "\(title) layout shown")
            XCTAssertTrue(app.otherElements["coachPanel"].firstMatch.exists, "coach panel embedded in \(title)")
            XCTAssertEqual(app.state, .runningForeground, "app alive after switching to \(title)")
        }

        // Why? opens the explanation in place; Ride settings and Details stay reachable
        let why = app.buttons["coachWhy"].firstMatch
        if why.exists && why.isEnabled { why.tap(); sleep(1); why.tap() }
        app.buttons["rideSettings"].firstMatch.tap()
        XCTAssertTrue(app.buttons["rideLayoutOption.rings"].firstMatch.waitForExistence(timeout: 10), "Ride settings lists the layouts")
        app.buttons["rideLayoutOption.rings"].firstMatch.tap()
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["rideLayout.rings"].firstMatch.waitForExistence(timeout: 10), "choice from Ride settings applied")
        app.buttons["rideDetails"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Ride details"].waitForExistence(timeout: 10))
        app.buttons["Done"].firstMatch.tap()
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Build-40 shaped store.json with an endurance ride scheduled TODAY (so the centre button reads "Ride now").
    static func rideDayStore() -> String {
        let iso = ISO8601DateFormatter()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let wd = (cal.component(.weekday, from: today) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -wd, to: today)!
        let tid = UUID().uuidString
        var plan: [String] = []
        for i in 0..<7 {
            let d = cal.date(byAdding: .day, value: i, to: monday)!.addingTimeInterval(7 * 3600)
            let kind = i == wd ? "endurance" : (i % 2 == 0 ? "rest" : "strength")
            plan.append("{\"id\":\"\(UUID().uuidString)\",\"date\":\"\(iso.string(from: d))\",\"kind\":\"\(kind)\",\"minutes\":\(kind == "rest" ? 0 : 60),\"done\":false,\"skipped\":false,\"note\":\"\",\"edited\":false,\"strengthFocus\":\(kind == "strength" ? "\"fullBody\"" : "null"),\"sequence\":0}")
        }
        let set = "{\"id\":\"\(UUID().uuidString)\",\"reps\":10,\"weightKg\":20,\"bodyweight\":false,\"unilateral\":false,\"done\":true}"
        return """
        {"schema":1,
         "profile":{"name":"Rashed","goal":"fitness","hoursPerWeek":5,"level":"intermediate","weightKg":82,"age":35,"ftpW":210,"ftpHow":"entered","birthYear":1988,
                    "sports":["roadCycling","strength"],"version":14,"updatedAt":"2026-10-25T20:00:00Z","wheelMm":2096,"cadenceLow":85,"cadenceHigh":95,"hrZoneMethod":"maxHR",
                    "trainingMode":"hybrid","priority":"balanced","cyclingDaysPerWeek":3,"liftDaysPerWeek":3,"liftingHoursPerWeek":2,"preferredDays":[1,3,5,6]},
         "settings":{"units":"metric","phoneOnlyMode":false,"hrPref":"watch","keepScreenOn":true,"autoConnectBoard":true,"enabledConnections":["board","watch"],"appearance":"system","backgroundNotice":true,"coachTalk":"normal","coachEnabled":true,"appleHealthImportWorkouts":false},
         "plan":[\(plan.joined(separator: ","))],
         "rides":[],"tiles":["power","cadence","hr","speed","time","dist"],"onboarded":true,"guest":true,"createdAt":"2026-10-24T10:00:00Z","boardSync":[],"onboardingStage":0,
         "templates":[{"id":"\(tid)","name":"Short Full Body Workout","focus":"fullBody","entries":[{"id":"\(UUID().uuidString)","exerciseId":"ex-003","name":"Goblet squat","pattern":"squat","sets":[\(set),\(set)],"notes":""}],"updatedAt":"2026-10-25T19:00:00Z"}],
         "customExercises":[],"appliedProposals":[],"weekdayRoutines":{},"equipment":{"owned":["dumbbells","bench"],"excluded":[]},"activeSession":null,"ignoredInsights":[],
         "strength":[]}
        """
    }
}
