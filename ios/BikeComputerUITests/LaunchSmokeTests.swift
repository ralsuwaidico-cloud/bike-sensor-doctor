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
        XCTAssertTrue(app.staticTexts["Cyclift"].waitForExistence(timeout: 20), "fresh launch must show the Cyclift welcome screen")
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testUpgradeFromBuild24StoreShowsHomeAndAllTabsOpen() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = Self.build24Store()
        app.launch()
        // Home: the navigation title carries the rider's name from the seeded profile
        XCTAssertTrue(app.navigationBars["Hi Rashed"].waitForExistence(timeout: 25) || app.staticTexts["Hi Rashed"].waitForExistence(timeout: 5),
                      "an existing rider must land on Home, not crash or see onboarding")
        Self.tapAllTabs(app)
    }

    /// A phone updated from build 30 (0.5.1): availability, edited sessions and the 0.5 profile fields present, no hybrid
    /// keys. Must land on Home with the plan intact and open every tab.
    func testUpgradeFromBuild30StoreShowsHomeAndAllTabsOpen() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = Self.build30Store()
        app.launch()
        XCTAssertTrue(app.navigationBars["Hi Rashed"].waitForExistence(timeout: 25) || app.staticTexts["Hi Rashed"].waitForExistence(timeout: 5))
        Self.tapAllTabs(app)
    }

    /// Taps every tab including the centre button (whose label depends on today's plan — a strength day opens a sheet,
    /// which is dismissed again) and asserts the app is still alive.
    static func tapAllTabs(_ app: XCUIApplication) {
        for label in ["Plan", "centreButton", "Progress", "Profile", "Home"] {
            let b = app.buttons[label].firstMatch
            XCTAssertTrue(b.waitForExistence(timeout: 10), "tab \(label) missing")
            b.tap()
            sleep(1)
            XCTAssertEqual(app.state, .runningForeground, "app died after opening \(label)")
            if label == "centreButton" {
                // a sheet (Train now / strength workout) may be up: close it so the next tab is reachable
                for name in ["Done", "Cancel", "Close"] { let c = app.buttons[name].firstMatch; if c.exists && c.isHittable { c.tap(); break } }
            }
        }
    }

    /// Build 36 (0.7.0) data with a routine, an edited plan and a detailed strength log, and TODAY a strength session:
    /// the centre button must read "Train now" and open the scheduled strength workout (routine shown, Start workout).
    func testUpgradeFromBuild36CentreButtonOpensStrengthWorkout() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = Self.build36Store()
        app.launch()
        XCTAssertTrue(app.navigationBars["Hi Rashed"].waitForExistence(timeout: 25) || app.staticTexts["Hi Rashed"].waitForExistence(timeout: 5))
        let centre = app.buttons["centreButton"].firstMatch
        XCTAssertTrue(centre.waitForExistence(timeout: 10))
        XCTAssertTrue(centre.label.contains("Train now"), "a strength day must say Train now, got \(centre.label)")
        centre.tap()
        XCTAssertTrue(app.staticTexts["Short Full Body Workout"].firstMatch.waitForExistence(timeout: 10), "the assigned routine, not a generic circuit")
        XCTAssertTrue(app.buttons["startWorkout"].firstMatch.waitForExistence(timeout: 5), "Start workout visible")
        XCTAssertFalse(app.buttons["Replace"].exists, "secondary actions live under More")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertEqual(app.state, .runningForeground)
        Self.tapAllTabs(app)
    }

    /// A phone updated from build 40 (0.8.0): everything build 36 had plus weekday routine defaults, equipment and an
    /// empty insight list. Must land on Home. Cyclift 1.0 has no accounts: Profile shows no sign-in at all, but
    /// "Your data" — Export must open a share sheet, and Delete all data must ask first; Cancel keeps every record
    /// (the rider still lands on Home with the seeded name and the routine is still on today's centre button).
    func testUpgradeFromBuild40YourDataExportAndDeleteCancelKeepsData() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = Self.build40Store()
        app.launch()
        XCTAssertTrue(app.navigationBars["Hi Rashed"].waitForExistence(timeout: 25) || app.staticTexts["Hi Rashed"].waitForExistence(timeout: 5))
        // The app draws its own tab bar (raised centre button), so there is no system TabBar to index into.
        let profileTab = app.buttons["Profile"].firstMatch
        XCTAssertTrue(profileTab.waitForExistence(timeout: 10), "Profile tab missing")
        profileTab.tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 10))
        let export = app.buttons["exportData"].firstMatch
        var tries = 0
        while !(export.exists && export.isHittable) && tries < 6 { app.swipeUp(); tries += 1 }   // the section is below the fold
        XCTAssertTrue(export.waitForExistence(timeout: 10), "Profile › Your data › Export my data")
        // no sign-in surface anywhere in 1.0
        XCTAssertFalse(app.buttons["profileCreateAccount"].exists, "no Create account row")
        let signIn = NSPredicate(format: "label CONTAINS[c] 'sign in' OR label CONTAINS[c] 'create account' OR label CONTAINS[c] 'not configured'")
        XCTAssertEqual(app.buttons.matching(signIn).count, 0, "no sign-in button")
        XCTAssertEqual(app.staticTexts.matching(signIn).count, 0, "no sign-in text")

        // Export → the iOS share sheet with the JSON file
        export.tap()
        XCTAssertTrue(Self.waitForShareSheet(app), "Export must open the share sheet")
        Self.closeShareSheet(app)
        XCTAssertEqual(app.state, .runningForeground)

        // Delete all data → confirmation; Cancel keeps everything
        let delete = app.buttons["deleteAllData"].firstMatch
        tries = 0
        while !(delete.exists && delete.isHittable) && tries < 6 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        delete.tap()
        let alert = app.alerts["Delete everything on this phone?"].firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "deletion must ask for confirmation")
        alert.buttons["Cancel"].tap()
        XCTAssertFalse(alert.waitForExistence(timeout: 2))

        // legal page still opens from About
        let privacy = app.buttons["Privacy policy"].firstMatch
        if privacy.waitForExistence(timeout: 5) { privacy.tap(); XCTAssertTrue(app.staticTexts["Cyclift — Privacy policy"].firstMatch.waitForExistence(timeout: 10)); app.navigationBars.buttons.element(boundBy: 0).tap() }

        // data preserved: still onboarded, same rider, today's routine still scheduled
        app.buttons["Home"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Hi Rashed"].waitForExistence(timeout: 10), "Cancel must keep the profile")
        let centre = app.buttons["centreButton"].firstMatch
        XCTAssertTrue(centre.waitForExistence(timeout: 10))
        XCTAssertTrue(centre.label.contains("Train now"), "Cancel must keep the plan, got \(centre.label)")
        XCTAssertEqual(app.state, .runningForeground)
        Self.tapAllTabs(app)
    }

    /// The share sheet's elements differ between iOS versions: accept any of its known markers.
    static func waitForShareSheet(_ app: XCUIApplication, timeout: TimeInterval = 15) -> Bool {
        let file = NSPredicate(format: "label BEGINSWITH 'cyclift-export'")
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if app.otherElements["ActivityListView"].exists || app.staticTexts.matching(file).firstMatch.exists
                || app.buttons["Copy"].exists || app.cells["Copy"].exists || app.buttons["Save to Files"].exists || app.cells["Save to Files"].exists { return true }
            usleep(300_000)
        }
        return false
    }
    static func closeShareSheet(_ app: XCUIApplication) {
        for name in ["Close", "Cancel"] { let c = app.buttons[name].firstMatch; if c.exists && c.isHittable { c.tap(); break } }
        sleep(1)
        if !app.buttons["exportData"].firstMatch.isHittable { app.swipeDown(velocity: .fast); sleep(1) }
    }

    static func build40Store() -> String {
        var s = build36Store()
        s = s.replacingOccurrences(of: "\"customExercises\":[],\"appliedProposals\":[],", with: "\"customExercises\":[],\"appliedProposals\":[],\"weekdayRoutines\":{\"1\":\"00000000-0000-0000-0000-000000000000\"},\"equipment\":{\"owned\":[\"dumbbells\",\"bench\"],\"excluded\":[]},\"activeSession\":null,\"ignoredInsights\":[],")
        return s
    }

    static func build36Store() -> String {
        let iso = ISO8601DateFormatter()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let wd = (cal.component(.weekday, from: today) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -wd, to: today)!
        let tid = UUID().uuidString
        var plan: [String] = []
        for i in 0..<7 {
            let d = cal.date(byAdding: .day, value: i, to: monday)!.addingTimeInterval(7 * 3600)
            let kind = i == wd ? "strength" : (i % 2 == 0 ? "rest" : "endurance")
            let tpl = i == wd ? "\"templateId\":\"\(tid)\",\"routineManual\":true," : ""
            plan.append("{\"id\":\"\(UUID().uuidString)\",\"date\":\"\(iso.string(from: d))\",\"kind\":\"\(kind)\",\"minutes\":\(kind == "rest" ? 0 : 45),\"done\":false,\"skipped\":false,\"note\":\"\",\"edited\":\(i == wd),\(tpl)\"strengthFocus\":\(kind == "strength" ? "\"fullBody\"" : "null"),\"sequence\":0}")
        }
        let logDate = cal.date(byAdding: .day, value: -4, to: today)!.addingTimeInterval(18 * 3600)
        let set = "{\"id\":\"\(UUID().uuidString)\",\"reps\":10,\"weightKg\":20,\"bodyweight\":false,\"unilateral\":false,\"done\":true}"
        return """
        {"schema":1,
         "profile":{"name":"Rashed","goal":"fitness","hoursPerWeek":5,"level":"intermediate","weightKg":82,"age":35,"ftpW":210,"ftpHow":"entered","birthYear":1988,
                    "sports":["roadCycling","strength"],"version":14,"updatedAt":"2026-10-25T20:00:00Z","wheelMm":2096,"cadenceLow":85,"cadenceHigh":95,"hrZoneMethod":"maxHR",
                    "trainingMode":"hybrid","priority":"balanced","cyclingDaysPerWeek":3,"liftDaysPerWeek":3,"liftingHoursPerWeek":2,"preferredDays":[1,3,5,6]},
         "settings":{"units":"metric","phoneOnlyMode":false,"hrPref":"watch","keepScreenOn":true,"autoConnectBoard":true,"enabledConnections":["board","watch"],"appearance":"system","backgroundNotice":true,"coachTalk":"normal","coachEnabled":true,"appleHealthImportWorkouts":false},
         "plan":[\(plan.joined(separator: ","))],
         "rides":[],"tiles":["power","cadence","hr","speed","time","dist"],"onboarded":true,"guest":true,"createdAt":"2026-10-24T10:00:00Z","boardSync":[],"onboardingStage":0,
         "templates":[{"id":"\(tid)","name":"Short Full Body Workout","focus":"fullBody","entries":[{"id":"\(UUID().uuidString)","exerciseId":"ex-003","name":"Goblet squat","pattern":"squat","sets":[\(set),\(set)],"notes":""},{"id":"\(UUID().uuidString)","exerciseId":"ex-088","name":"Dumbbell row","pattern":"pull","sets":[\(set),\(set)],"superset":"A","notes":""}],"updatedAt":"2026-10-25T19:00:00Z"}],
         "customExercises":[],"appliedProposals":[],
         "strength":[{"id":"\(UUID().uuidString)","date":"\(iso.string(from: logDate))","minutes":35,"focus":"fullBody","customName":"","rpe":7,"notes":"","source":"manual","templateId":"\(tid)","exercises":[{"id":"\(UUID().uuidString)","exerciseId":"ex-003","name":"Goblet squat","pattern":"squat","sets":[\(set),\(set)],"notes":""}]}]}
        """
    }

    static func build30Store() -> String {
        let iso = ISO8601DateFormatter()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let wd = (cal.component(.weekday, from: today) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -wd, to: today)!
        let kinds = ["rest", "endurance", "strength", "tempo", "rest", "long", "other"]
        var plan: [String] = []
        for i in 0..<7 {
            let d = cal.date(byAdding: .day, value: i, to: monday)!.addingTimeInterval(7 * 3600)
            plan.append("{\"id\":\"\(UUID().uuidString)\",\"date\":\"\(iso.string(from: d))\",\"kind\":\"\(kinds[i])\",\"minutes\":\(kinds[i] == "rest" ? 0 : 60),\"done\":\(i < wd),\"skipped\":false,\"note\":\"\",\"edited\":\(i == 3)}")
        }
        return """
        {"schema":1,
         "profile":{"name":"Rashed","goal":"endurance","hoursPerWeek":6,"level":"intermediate","weightKg":82,"age":35,"ftpW":210,"ftpHow":"entered","birthYear":1988,
                    "sports":["roadCycling","strength"],"version":9,"updatedAt":"2026-10-25T08:00:00Z","gender":null,"wheelMm":2096,"cadenceLow":85,"cadenceHigh":95,"hrZoneMethod":"maxHR"},
         "settings":{"units":"metric","phoneOnlyMode":false,"hrPref":"watch","keepScreenOn":true,"autoConnectBoard":true,"enabledConnections":["board","watch"],"appearance":"system","backgroundNotice":true,"coachTalk":"normal","coachEnabled":true},
         "plan":[\(plan.joined(separator: ","))],
         "rides":[],"tiles":["power","cadence","hr","speed","time","dist"],"onboarded":true,"guest":true,"createdAt":"2026-10-24T10:00:00Z","boardSync":[],"onboardingStage":0,
         "availability":{"days":[{"activity":"rest","minutes":0},{"activity":"cycle","minutes":60},{"activity":"lift","minutes":30},{"activity":"cycle","minutes":60},{"activity":"rest","minutes":0},{"activity":"cycle","minutes":120},{"activity":"other","minutes":45}]}}
        """
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

    /// A phone updated from build 33 (0.6.0): hybrid mode, legacy availability with a "both" day, quick strength logs, no
    /// 0.7.0 keys (assignments, templates, exercises). Must land on Home, open every tab, and the 0.7.0 sheets must open
    /// and close at an accessibility text size on the smallest supported layout path.
    func testUpgradeFromBuild33OpensHybridSheetsAtLargeText() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = Self.build33Store()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Hi Rashed"].waitForExistence(timeout: 25) || app.staticTexts["Hi Rashed"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
        // Plan → Days editor (per-day assignments) opens and closes
        app.buttons["Plan"].firstMatch.tap()
        let days = app.buttons["Days"].firstMatch
        XCTAssertTrue(days.waitForExistence(timeout: 10)); days.tap()
        XCTAssertTrue(app.navigationBars["Training days"].waitForExistence(timeout: 10), "availability editor must open")
        XCTAssertEqual(app.state, .runningForeground)
        app.buttons["Cancel"].firstMatch.tap()
        // Plan → Log strength → Quick log sheet opens with the type grid, closes
        let log = app.buttons["Log strength"].firstMatch
        XCTAssertTrue(log.waitForExistence(timeout: 10))
        // The toolbar menu can still be animating at accessibility text sizes: open it again once if the sheet did not appear.
        var opened = false
        for _ in 0..<2 where !opened {
            log.tap()
            let quick = app.buttons["Quick log"].firstMatch
            if quick.waitForExistence(timeout: 5) { quick.tap() }
            opened = app.navigationBars["Log strength"].waitForExistence(timeout: 10)
        }
        XCTAssertTrue(opened, "quick strength log must open")
        XCTAssertTrue(app.buttons["Full body"].firstMatch.waitForExistence(timeout: 5) || app.staticTexts["Full Body"].firstMatch.waitForExistence(timeout: 2), "type grid visible")
        app.buttons["Cancel"].firstMatch.tap()
        // Profile → Training profile page
        app.buttons["Profile"].firstMatch.tap()
        let tp = app.buttons["Training profile"].firstMatch.exists ? app.buttons["Training profile"].firstMatch : app.staticTexts["Training profile"].firstMatch
        XCTAssertTrue(tp.waitForExistence(timeout: 10)); tp.tap()
        sleep(1)
        XCTAssertEqual(app.state, .runningForeground, "app died opening Training profile at large text")
        app.buttons["Home"].firstMatch.tap()
        XCTAssertEqual(app.state, .runningForeground)
    }

    static func build33Store() -> String {
        let iso = ISO8601DateFormatter()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let wd = (cal.component(.weekday, from: today) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -wd, to: today)!
        let kinds = ["rest", "endurance", "strength", "tempo", "rest", "long", "strength"]
        var plan: [String] = []
        for i in 0..<7 {
            let d = cal.date(byAdding: .day, value: i, to: monday)!.addingTimeInterval(7 * 3600)
            plan.append("{\"id\":\"\(UUID().uuidString)\",\"date\":\"\(iso.string(from: d))\",\"kind\":\"\(kinds[i])\",\"minutes\":\(kinds[i] == "rest" ? 0 : 60),\"done\":false,\"skipped\":false,\"note\":\"\",\"edited\":false,\"strengthFocus\":\(kinds[i] == "strength" ? "\"lower\"" : "null"),\"sequence\":0}")
        }
        let logDate = cal.date(byAdding: .day, value: -3, to: today)!.addingTimeInterval(18 * 3600)
        return """
        {"schema":1,
         "profile":{"name":"Rashed","goal":"fitness","hoursPerWeek":5,"level":"intermediate","weightKg":82,"age":35,"ftpW":210,"ftpHow":"entered","birthYear":1988,
                    "sports":["roadCycling","strength"],"version":12,"updatedAt":"2026-10-25T10:00:00Z","wheelMm":2096,"cadenceLow":85,"cadenceHigh":95,"hrZoneMethod":"maxHR",
                    "trainingMode":"hybrid","priority":"balanced","cyclingDaysPerWeek":3,"liftDaysPerWeek":3,"liftingHoursPerWeek":2,"preferredDays":[1,3,5,6]},
         "settings":{"units":"metric","phoneOnlyMode":false,"hrPref":"watch","keepScreenOn":true,"autoConnectBoard":true,"enabledConnections":["board","watch"],"appearance":"system","backgroundNotice":true,"coachTalk":"normal","coachEnabled":true,"appleHealthImportWorkouts":false},
         "plan":[\(plan.joined(separator: ","))],
         "rides":[],"tiles":["power","cadence","hr","speed","time","dist"],"onboarded":true,"guest":true,"createdAt":"2026-10-24T10:00:00Z","boardSync":[],"onboardingStage":0,
         "availability":{"days":[{"activity":"rest","minutes":0},{"activity":"both","minutes":60,"liftMinutes":30},{"activity":"lift","minutes":45},{"activity":"cycle","minutes":75},{"activity":"rest","minutes":0},{"activity":"cycle","minutes":150},{"activity":"lift","minutes":40}]},
         "strength":[{"id":"\(UUID().uuidString)","date":"\(iso.string(from: logDate))","minutes":40,"focus":"upper","customName":"","rpe":6,"notes":"","source":"manual"}]}
        """
    }
}
